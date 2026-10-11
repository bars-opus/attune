-- Spec §12's six server-authoritative capability flags, plus the RLS
-- narrowing that keeps an unlaunched rollout plan out of client reach.
--
-- WHY THIS MIGRATION EXISTS. Spec §3.1 requires an "enabled capability"
-- check on EVERY AI Sessions command, and §12 requires "Separate
-- server-authoritative flags for base Assist, Understand, private
-- Sessions, shared Sessions, recent-window and Nearby; defaults off. A
-- client flag alone is insufficient." Neither Plan A nor Plan B seeded
-- any of them -- verified by catalog query: public.feature_flags held
-- 17 rows, all chat_*, dating_* and stories, and ZERO matching
-- session/ai/nearby/understand/assist. So every AI Sessions command had
-- no flag to read, and the edge function was failing closed on a
-- hardcoded refusal rather than on a flag an operator can flip.
--
-- THE PRECEDENT THIS FOLLOWS, AND THE TRAP IT AVOIDS.
-- 20260712150000_dating_flag_defense_in_depth.sql (Fable review
-- DATING-H1) documents both halves of the bug this migration must not
-- re-introduce:
--
--   1. `feature_flags` was client-readable with USING (true), so any
--      authenticated user could enumerate the whole rollout plan --
--      INCLUDING `dating_mode_enabled` before launch. A flag row's mere
--      existence discloses that an unshipped feature is being built and
--      roughly how it is subdivided. All six keys below name capabilities
--      that have NEVER shipped, so they are in exactly the state
--      `dating_mode_enabled` was in when that review called it a
--      finding. They get the same treatment.
--
--   2. The client-side gate was "advisory/spoofable". The fix was to
--      enforce the flag INSIDE the server-side path, not in the client.
--      Here the server-side path is the ai-sessions edge function's
--      eligibility gate, which calls ai_capability_enabled() below
--      through the service-role client. The function is granted to
--      service_role ONLY -- an `authenticated` caller cannot even ask
--      whether a capability is on, which is the point: asking is itself
--      enumeration.
--
-- NOT A NEW TABLE AND NOT A NEW MECHANISM. These are rows in the
-- existing public.feature_flags with the existing shape, and
-- ai_capability_enabled() is `dating_flag_enabled`'s body with a
-- different name and a narrower grant. A second flag table would be a
-- second place for an operator to forget to flip.
--
-- Additive and re-appliable: every statement is idempotent, so a
-- rebuild and a re-run produce the same schema.

-- ---------------------------------------------------------------------------
-- 1. The six §12 rows, DEFAULTS OFF.
--
-- Key naming: a single `ai_` prefix across all six, so ONE RLS clause
-- hides the entire family and a seventh capability added later is
-- hidden by construction rather than by remembering to extend a list.
-- Verified before choosing it that no `ai\_%` key existed in
-- feature_flags, so this prefix cannot shadow a shipped flag.
--
-- ON CONFLICT DO NOTHING, never DO UPDATE: re-applying this migration
-- against a database where an operator has already enabled a capability
-- must not silently switch it back off (and must not switch it ON
-- either -- hence seeding `false`). "Do not enable a capability until
-- its gates are recorded" (§12) means enabling is an operator act with
-- a §14 gate behind it, never a migration's side effect.
-- ---------------------------------------------------------------------------
INSERT INTO public.feature_flags (key, enabled) VALUES
  -- Base single-turn Ask Attune (Assist). Plan A's surface.
  ('ai_assist_enabled', false),
  -- Base Understand.
  ('ai_understand_enabled', false),
  -- Private multi-turn Sessions.
  ('ai_sessions_private_enabled', false),
  -- Shared (mutually joined) multi-turn Sessions. Distinct from private
  -- because §12 requires "Subcapability disable closes affected
  -- sessions, not unrelated chat" -- killing shared must leave private
  -- sessions alive, which one combined flag cannot express.
  ('ai_sessions_shared_enabled', false),
  -- The optional shared recent-message window (§4.2 item 3). Separate
  -- because it is the one subcapability that puts the PARTNER's chat
  -- text into a provider prompt, so it must be killable while leaving
  -- context-free shared sessions running.
  ('ai_sessions_recent_window_enabled', false),
  -- Nearby (the Mapbox-backed kind).
  ('ai_sessions_nearby_enabled', false)
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. Hide the `ai_%` family from clients, exactly as `dating_%` is
--    hidden. chat_* and stories stay readable.
--
-- This REPLACES 20260712150000's policy rather than adding a second
-- one, because multiple permissive SELECT policies are OR'ed: a new
-- policy saying "key NOT LIKE 'ai\_%'" alongside the old one saying
-- "key NOT LIKE 'dating\_%'" would make BOTH families visible again
-- (each row satisfies at least one of the two). The single combined
-- predicate is the only correct shape, and getting this wrong would
-- silently undo the dating fix -- which is why the contract test
-- asserts a dating key is still hidden, not just the new ones.
--
-- chat_feature_flags.dart reads with .eq('key', flagName) for a
-- specific chat_* key, so narrowing the policy cannot break it; the
-- contract test proves that by reading as `authenticated`.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS feature_flags_authenticated_read ON public.feature_flags;
CREATE POLICY feature_flags_authenticated_read
ON public.feature_flags FOR SELECT TO authenticated
USING (key NOT LIKE 'dating\_%' AND key NOT LIKE 'ai\_%');

-- ---------------------------------------------------------------------------
-- 3. The server-side predicate the edge function's eligibility gate
--    calls. Body is dating_flag_enabled's verbatim, with two
--    differences that matter:
--
--      * granted to service_role ONLY, never authenticated. A client
--        must not be able to probe capability state one key at a time
--        and so reconstruct what the RLS policy in (2) just hid.
--      * COALESCE(..., false) so an ABSENT key is disabled, not an
--        error and not enabled. A capability nobody has seeded yet is
--        off -- the same fail-closed default §12 demands.
--
-- STABLE, not VOLATILE: one command's eligibility check may consult
-- more than one capability, and they must agree within the request.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_capability_enabled(p_key text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT enabled FROM public.feature_flags WHERE key = p_key), false);
$$;

REVOKE ALL ON FUNCTION public.ai_capability_enabled(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ai_capability_enabled(text) TO service_role;
