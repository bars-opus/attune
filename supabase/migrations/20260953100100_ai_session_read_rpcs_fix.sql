-- Fix round 1 for Task 10 (authorized read RPCs). Spec §7.2.
--
-- ======================================================================
-- THIS MIGRATION SUPERSEDES PART OF ONE EARLIER MIGRATION.
--
-- It re-defines, by CREATE OR REPLACE:
--
--   * public.read_ai_session_staging -- originally 20260953100000 (Task 10)
--
-- It does NOT re-define public.read_ai_session_turns; that function's
-- authoritative definition remains the one in 20260953100000, which is
-- correct as shipped. See the "MIGRATION PROVENANCE" note at the bottom.
--
-- Per this plan's additive-migrations discipline (established by Task
-- 6's fix round, 20260953060100, and followed by Task 9's
-- 20260953090100), no earlier migration's logic is edited in place.
-- Later migrations win; the earlier files are kept as the historical
-- record of what shipped when.
-- ======================================================================
--
-- Review finding addressed here:
--
--   F1 (Important) -- read_ai_session_staging enforced NONE of spec
--     §7.2's content-read gates. Its entire WHERE clause was
--     `request_id = p_request_id AND requester_id = p_actor_id AND
--     expires_at > now()`: no active-membership gate, no current-consent
--     gate, no session-state gate. Spec §7.2 reads "Content reads
--     require active membership, current consent, unexpired active state
--     and creator (private) or accepted participant (shared). […] Own
--     staged Nearby is accessible only through an author-checking RPC,
--     never a shared SELECT policy." A staged Nearby reply is
--     AI-generated content derived from the relationship's data, so the
--     author-check clause adds the author requirement ON TOP OF the
--     content-read requirements -- it does not replace them.
--
--     The original migration's comment claimed the session-level gates
--     "would be redundant here", reasoning from the synchronous purge in
--     end_ai_session and from expires_at being capped at the session's
--     own expiry. That reasoning is sound for the STATE gate and wrong
--     for the other two: consent withdrawal and relationship end are
--     user-initiated, instantaneous, and nothing in the schema cascades
--     them to an in-flight session -- no trigger, RPC or cron closes a
--     session on withdrawal, and Task 11's purger is purely time-based.
--     So the gates the comment dismissed were not redundant at all; they
--     were absent.
--
--     Reproduced live before this fix, on all four reachable probes --
--     each returned the staging row with its full reply_text:
--
--       * partner withdrew AI-processing consent  -> 1 row (leak)
--       * relationships.status = 'ended'          -> 1 row (leak)
--       * relationships.chat_archived_at = now()  -> 1 row (leak)
--       * actor removed from the relationship     -> 1 row (leak)
--
--     while read_ai_session_turns correctly returned 0 rows for the
--     same actor on the same relationship in the first case. The window
--     is bounded at ~2 minutes by stage_ai_session_nearby_result's
--     `expires_at = LEAST(now() + interval '2 minutes',
--     session.expires_at)`, and the content leaked is the actor's OWN
--     staged result rather than the partner's private data -- which is
--     why this is Important and not Critical. But this plan's premise is
--     that consent gates content, so two minutes of post-withdrawal
--     readability is still a consent violation.

-- ---------------------------------------------------------------------
-- read_ai_session_staging -- the author-checking RPC for own staged
-- Nearby (spec §7.2: "Own staged Nearby is accessible only through an
-- author-checking RPC, never a shared SELECT policy"), NOW ALSO GATED
-- on the content-read requirements the same clause imposes.
--
-- Gates, in the order they fire:
--
--   0. author       -- requester_id = p_actor_id. KEPT, and still the
--      gate that makes this RPC narrower than read_ai_session_turns.
--      See "THE ASYMMETRY IS LOAD-BEARING" below.
--   1. active membership -- the actor is a current member of the
--      session's relationship, which must itself be active and
--      un-archived. Reached through the staging row's own session_id.
--   2. current consent   -- BOTH partners have a 'granted' consent event
--      at the CURRENT policy version. This is the gate that makes a
--      withdrawal effective immediately on staged reads, not merely on
--      new generations.
--   3. own expiry   -- expires_at > now(). KEPT.
--
-- Gates 1 and 2 are DELIBERATELY the byte-identical predicate shape
-- read_ai_session_turns already uses (20260953100000), which the review
-- confirmed matches canonical get_ai_processing_consent_status exactly
-- -- same predicates, same `ORDER BY e.created_at DESC, e.id DESC LIMIT
-- 1`, same `COALESCE(a,false) AND COALESCE(b,false)` -- and exactly
-- matches the covering index idx_ai_processing_consent_current
-- (relationship_id, user_id, policy_version, created_at DESC, id DESC).
-- A NEW predicate shape here would be a latent divergence; reusing the
-- existing one is the point. (Factoring the duplicated consent rule into
-- a shared no-actor helper is a ruled-accepted later follow-up, not this
-- fix's business. Consent cannot be read through Plan A's
-- get_ai_processing_consent_status: that function derives its actor from
-- auth.uid() and RAISEs 'Not authenticated' when it is NULL, and a
-- service_role connection -- the only caller either read RPC is granted
-- to -- carries no JWT.)
--
-- THE SESSION-STATE GATE IS GENUINELY OMITTED, AND THAT IS NOT AN
-- OVERSIGHT. read_ai_session_turns' Gate 3 (state = 'active' AND
-- unexpired) has no counterpart here, for the reason the original
-- migration's comment gave -- which was right about this one gate and
-- wrong about the other two. Both broken-state variants are unreachable:
-- end_ai_session purges ai_session_staging synchronously in the same
-- transaction that closes the session (this plan's Global Constraint),
-- and the only other close path -- prepare_ai_session's expired-slot
-- reclaim -- touches state = 'preparing' sessions only, which cannot
-- hold staging rows. A staging row also cannot outlive its session's
-- expiry, because stage_ai_session_nearby_result caps expires_at at
-- LEAST(now() + 2 minutes, session.expires_at), so Gate 3's own
-- expires_at check subsumes the session's. The reviewer confirmed both
-- variants are reachable only by direct UPDATE, i.e. already past the
-- trust boundary.
--
-- THE ASYMMETRY IS LOAD-BEARING, AND THIS FIX PRESERVES IT EXACTLY.
-- There is still no visibility branch, no approvals lookup, and no
-- partner path. The creator of a SHARED session, who MAY read that
-- session's turns, still reads ZERO rows of the partner's staging,
-- because requester_id = p_actor_id denies them before any of this
-- matters. The gates added here can only ever REMOVE access from the
-- requester; they can never grant it to anyone else. Task 10's contract
-- test asserts that asymmetry directly (Contracts 6b/6c), and this fix
-- round adds Contracts 6f-6i asserting each newly-gated denial is real
-- and restorable.
--
-- The DELIBERATE SILENCE property of 20260953100000 is unchanged: every
-- unauthorized outcome below is `RETURN` (zero rows), never RAISE, so a
-- partner's zero, a stranger's zero, a post-withdrawal zero and a
-- nonexistent-request zero are byte-identical and this RPC is not an
-- existence oracle.
CREATE OR REPLACE FUNCTION public.read_ai_session_staging(
  p_actor_id uuid, p_request_id uuid
) RETURNS SETOF public.ai_session_staging
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_session_id uuid;
  v_relationship_id uuid;
  v_user_a uuid;
  v_user_b uuid;
  v_version text := public.ai_current_consent_policy_version();
  v_a_granted boolean;
  v_b_granted boolean;
BEGIN
  IF p_actor_id IS NULL THEN
    RETURN;
  END IF;

  -- Gate 0: author. The staging row must exist, be unexpired, and
  -- belong to this actor. Resolved first so the session/relationship
  -- lookups below only ever run for a row the actor already owns.
  SELECT s.session_id INTO v_session_id
  FROM public.ai_session_staging s
  WHERE s.request_id = p_request_id
    AND s.requester_id = p_actor_id
    AND s.expires_at > now();
  IF v_session_id IS NULL THEN
    RETURN;
  END IF;

  SELECT se.relationship_id INTO v_relationship_id
  FROM public.ai_sessions se WHERE se.id = v_session_id;
  IF v_relationship_id IS NULL THEN
    RETURN;
  END IF;

  -- Gate 1: active membership in a live, un-archived relationship.
  SELECT r.user_a, r.user_b INTO v_user_a, v_user_b
  FROM public.relationships r
  WHERE r.id = v_relationship_id
    AND r.status = 'active' AND r.chat_archived_at IS NULL
    AND (r.user_a = p_actor_id OR r.user_b = p_actor_id);
  IF v_user_a IS NULL THEN
    RETURN;
  END IF;

  -- Gate 2: current consent from BOTH partners at the current policy
  -- version. An event at an older version never counts as granted,
  -- which is what makes a version bump require two fresh grants.
  SELECT (e.action = 'granted') INTO v_a_granted
  FROM public.ai_processing_consent_events e
  WHERE e.relationship_id = v_relationship_id AND e.user_id = v_user_a
    AND e.policy_version = v_version
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;

  SELECT (e.action = 'granted') INTO v_b_granted
  FROM public.ai_processing_consent_events e
  WHERE e.relationship_id = v_relationship_id AND e.user_id = v_user_b
    AND e.policy_version = v_version
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;

  IF NOT (COALESCE(v_a_granted, false) AND COALESCE(v_b_granted, false)) THEN
    RETURN;
  END IF;

  -- Gate 3: own expiry, re-stated on the returned row so the row that
  -- is returned is the row that was authorized -- not merely a row with
  -- the same request_id. request_id is globally unique (it references
  -- ai_session_requests(id), a PK), so this is the same single row.
  RETURN QUERY SELECT * FROM public.ai_session_staging
  WHERE request_id = p_request_id AND requester_id = p_actor_id
    AND expires_at > now();
END;
$$;
REVOKE ALL ON FUNCTION public.read_ai_session_staging(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_ai_session_staging(uuid, uuid)
  TO service_role;

-- ======================================================================
-- MIGRATION PROVENANCE -- see 20260953090100's own block for the full
-- table. After this file, the authoritative definitions of the Task 10
-- read RPCs are:
--
--   public.read_ai_session_turns    Task 10  20260953100000  (original,
--                                            NOT superseded -- correct
--                                            as shipped)
--   public.read_ai_session_staging  Task 10  20260953100100  (THIS FILE,
--                                            superseding 20260953100000)
--
-- The supersession-ordering contract in
-- supabase/tests/ai_session_read_authorization_contracts.sql (Contract 9)
-- is extended by this fix round to cover this supersession too: it
-- asserts the LIVE body (pg_get_functiondef) of read_ai_session_staging
-- carries the consent-gate marker that only THIS definition has, so a
-- future out-of-order re-apply of 20260953100000 cannot silently revert
-- the fix and ship green.
-- ======================================================================
