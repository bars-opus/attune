-- The client-readable half of spec §12's capability flags: ONE RPC the
-- Flutter client calls to learn which AI Sessions entry points to render.
--
-- WHY THIS MIGRATION EXISTS (Plan D Task 5, pre-flight finding PF2).
--
-- Plan D Task 5's brief asked the client to read `public.feature_flags`
-- directly for five `ai_%` keys, the way chat_feature_flags.dart reads
-- its `chat_%` keys. That cannot work, and I measured it rather than
-- reasoning about it. As `authenticated`, inside a transaction, against
-- this database:
--
--   SET LOCAL ROLE authenticated;
--   SELECT count(*) FROM public.feature_flags WHERE key LIKE 'ai\_%';
--   -- 0
--   SELECT enabled FROM public.feature_flags
--     WHERE key = 'ai_sessions_private_enabled';
--   -- (0 rows)          <- exactly isEnabled()'s maybeSingle() query
--   SELECT count(*) FROM public.feature_flags WHERE key LIKE 'chat\_%';
--   -- 11                <- the control: chat_* IS readable
--
-- because 20260953200000_ai_capability_flags.sql deliberately narrowed
-- the SELECT policy to `key NOT LIKE 'dating\_%' AND key NOT LIKE
-- 'ai\_%'`. So five client providers reading that table would have read
-- `_defaults` (false) FOREVER, and no operator UPDATE could ever turn
-- the feature on. That is a worse failure than no flag at all: a dead
-- kill switch that LOOKS live.
--
-- WHICH OF THE THREE OPTIONS THIS IS, AND WHY.
--
-- (a) Narrowing the RLS predicate to expose the five session keys was
--     rejected. 20260712150000_dating_flag_defense_in_depth.sql's own
--     header says the bug was that `feature_flags` was client-readable
--     "so any authenticated user could enumerate the rollout plan", and
--     20260953200000's header says all six `ai_` keys "have NEVER
--     shipped, so they are in exactly the state `dating_mode_enabled`
--     was in when that review called it a finding". Re-exposing rows
--     also re-couples the client to the table's SHAPE, which is what
--     made the dating gate "advisory/spoofable" in the first place.
--
-- (c) Reporting capability in an edge-function response field was
--     rejected for three reasons I verified in index.ts.
--       1. `processSessionCommand` has exactly NINE cases and none of
--          them is a capability query, so (c) means a TENTH command --
--          a Deno change plus an envelope-allowlist change, outside a
--          Flutter task, and a new unknown-key surface under Ruling 4.
--       2. Every existing command requires a `relationship_id` and runs
--          `checkEligibility`, whose CHECK 0 is deliberately ordered
--          BEFORE membership so "a disabled capability must not be able
--          to tell an outsider whether a relationship id is real". A
--          capability probe that needs a relationship id therefore
--          cannot answer "should I render this entry point at all?"
--          before the user is in a relationship context.
--       3. It would cost a provider-capable edge invocation to decide
--          whether to draw a button.
--
-- (b) A server RPC, the in-repo precedent 20260712150000 itself points
--     at: `get_dating_eligibility()`. This is that, for Sessions.
--
-- WHAT THIS DOES AND DOES NOT DISCLOSE, stated precisely because the
-- enumeration argument is the one thing (b) must answer.
--
-- It discloses the on/off state of exactly five named capabilities, to
-- an AUTHENTICATED caller, and nothing else: not the table, not its
-- shape, not the `ai_understand_enabled` sixth key, not any other
-- family, and not whether a key is absent versus present-and-false
-- (COALESCE collapses both to false, as ai_capability_enabled already
-- does). It is NOT a key-by-key oracle: the argument list is empty, so
-- a caller cannot ask about a key of their choosing and so cannot probe
-- for the existence of a capability this function does not name. That
-- is the property `ai_capability_enabled`'s service_role-only grant was
-- protecting, and it is preserved here by taking no parameter at all
-- rather than by hiding the answer.
--
-- The rollout-plan secrecy that 20260712150000 protected is, for these
-- five keys specifically, lost at the moment Plan D's client ships:
-- that binary names all five capabilities in its own source in order to
-- decide what to draw. Keeping the VALUES secret from a client that
-- already knows the NAMES buys nothing and costs the kill switch. The
-- `dating_%` family and `ai_understand_enabled` are untouched and stay
-- hidden, so this is a five-key exception argued on its merits, not a
-- re-opening of the policy.
--
-- THIS IS NOT A GATE. §12: "A client flag alone is insufficient."
-- Enforcement stays exactly where it is -- checkEligibility's CHECK 0,
-- via the service_role-only ai_capability_enabled(). This function's
-- only job is to stop the client offering a door the server will slam.
-- A spoofed `true` here buys a user a FEATURE_DISABLED on the first
-- command, which is what the unspoofed client would have shown anyway.
--
-- READ-ONLY BY CONSTRUCTION. `LANGUAGE sql STABLE` with a single
-- SELECT: there is no UPDATE, no INSERT and no dynamic SQL anywhere in
-- this file, so nothing here can flip a flag. The seeded defaults from
-- 20260953200000 are untouched and all six remain false.
--
-- Additive and re-appliable: CREATE OR REPLACE plus idempotent grants.

-- ---------------------------------------------------------------------------
-- The five capabilities Plan D's client renders entry points for.
--
-- `ai_understand_enabled` is deliberately NOT reported: Understand is
-- Plan A's surface and no Plan D entry point depends on it, so adding
-- it would disclose a capability state no client needs. A later task
-- that renders an Understand entry point adds it here, with its own
-- reason, rather than this file pre-emptively exposing the whole family
-- -- which is the mistake 20260712150000 was written about.
--
-- Key naming mirrors feature_flags verbatim (`ai_assist_enabled`, not
-- `assist`) so an operator reading this function and an operator
-- reading the seed INSERT are looking at the same strings, and a typo
-- here cannot silently read as `false` through a name that exists in
-- neither place. The contract test asserts every key named here exists
-- as a row.
--
-- Calls ai_capability_enabled() rather than re-querying the table, so
-- the client's answer and the edge function's gate are computed by the
-- SAME predicate and cannot drift (including the COALESCE fail-closed
-- for an absent key). SECURITY DEFINER is what lets this reach that
-- service_role-only function; that is the whole mechanism -- the
-- narrow, parameterless door stays the only way through.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_ai_session_capabilities()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'ai_assist_enabled',
      public.ai_capability_enabled('ai_assist_enabled'),
    'ai_sessions_private_enabled',
      public.ai_capability_enabled('ai_sessions_private_enabled'),
    'ai_sessions_shared_enabled',
      public.ai_capability_enabled('ai_sessions_shared_enabled'),
    'ai_sessions_recent_window_enabled',
      public.ai_capability_enabled('ai_sessions_recent_window_enabled'),
    'ai_sessions_nearby_enabled',
      public.ai_capability_enabled('ai_sessions_nearby_enabled')
  )
  -- RETURNS NULL (not an all-false object) WHEN THERE IS NO AUTHENTICATED
  -- SUBJECT. This is a contract the Dart side depends on, so it is
  -- stated rather than left to be discovered: a NULL means "no answer",
  -- which the client treats exactly like a transport failure and fails
  -- safe to all-false. It is belt-and-braces rather than the gate --
  -- `anon` is already refused by the GRANT below, which is why a NULL
  -- here can only mean an `authenticated` role with no `sub` claim
  -- (a session that expired mid-call, or a misconfigured key).
  --
  -- It deliberately does NOT return all-false for that caller: a
  -- confident `{..., false, ...}` and "I could not ask" are different
  -- facts, and collapsing them would let an expired session look like a
  -- deliberate server-side disable. Only the latter should ever be
  -- reported to a user as "not available yet".
  WHERE auth.uid() IS NOT NULL;
$$;

-- `authenticated` only. `anon` must not be able to poll for launch, and
-- `service_role` has no use for this (it calls ai_capability_enabled
-- directly, per capability, which is what checkEligibility needs in
-- order to report WHICH capability was off).
REVOKE ALL ON FUNCTION public.get_ai_session_capabilities()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_ai_session_capabilities() TO authenticated;
