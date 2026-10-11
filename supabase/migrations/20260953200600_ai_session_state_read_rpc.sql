-- Plan D Task 8, GATE 1: THE PARTNER-READABLE SESSION REVISION.
--
-- Spec §4.3, §6.1 (as amended), §6.2, §7.2, §8.1. Ruling 1, Ruling 6.
--
-- ======================================================================
-- WHY THIS MIGRATION EXISTS: THE POLL IS UNIMPLEMENTABLE WITHOUT IT.
--
-- §6.1 was amended for Plan D: polling `session_revision` is the
-- sanctioned invalidation mechanism, Realtime Broadcast is out of scope,
-- and direct Postgres Changes publication of the transcript, staging and
-- source tables stays forbidden. Re-verified against this database
-- before writing this file, rather than taken on trust:
--
--   SELECT count(*) FROM pg_policies WHERE schemaname = 'realtime';
--   -- 0          (of 158 policies in the database)
--
-- so there is no private-channel authorization anywhere to subscribe
-- through, and the client's own usage confirms the same shape from the
-- other side: 14 `.onPostgresChanges` call sites against 2
-- `.onBroadcast`, neither of the latter in an AI surface.
--
-- But polling needs something to poll, AND THE PARTY THAT NEEDS TO POLL
-- COULD NOT READ IT. `session_revision` reached only the actor who
-- CAUSED the bump:
--
--   * commit_ai_session_ideas_turn  -> the generating actor
--   * publish_ai_session_nearby_result -> the publishing actor
--     (both via 20260953170000, which added exactly that disclosure)
--   * prepare_ai_session -> the creator, the INITIAL value only
--   * activate_ai_session -> {activated, state}, to the approver, at
--     the instant they approve
--
-- Enumerated over every non-void AI-session function, not sampled. The
-- two GATED PARTNER-READABLE surfaces are read_ai_session_turns and
-- read_ai_session_staging, and NEITHER carries a revision:
-- read_ai_session_turns is declared `RETURNS SETOF
-- public.ai_session_turns`, i.e. turn rows and nothing else, and
-- handleRead's response body is `{turns, staged?}` with zero mentions
-- of a revision. So the partner -- the one party that cannot learn of a
-- change from its own response, because it did not make the call that
-- caused it -- had no readable token at all. That was a gap in Ruling 1,
-- found by Plan C's final review.
--
-- ======================================================================
-- WHICH SHAPE, AND WHY IT IS (b) RATHER THAN (a).
--
-- (a) EXTEND handleRead's RESPONSE with the session's current revision.
--     Rejected, and not on taste: IT CANNOT SERVE THE PHASE THAT MOST
--     NEEDS THE POLL. read_ai_session_turns' gate 3 is
--
--       IF v_session.state != 'active' THEN RETURN; END IF;
--
--     so for a session still `preparing` it returns zero rows, and
--     handleRead cannot distinguish that from a stranger's zero rows --
--     deliberately, since collapsing them is the whole non-disclosure
--     property of §7.2. A partner who approved FIRST sits in the
--     `waitingForPartner` phase waiting to learn the session ACTIVATED;
--     that is a `preparing` -> `active` transition, and a revision
--     bolted onto a response the gate refuses to populate would be
--     absent for exactly that wait. Extending `read` would have given
--     the poll a value it could read only once the thing it was waiting
--     for had already happened AND committed a turn.
--
--     Worse, it would force a choice between two bad options inside a
--     function whose silence is its security property: report the
--     revision outside the gate (a new unauthenticated-by-that-gate
--     disclosure, and an existence oracle -- a real revision for a real
--     session, nothing for a fake one, which is precisely the oracle
--     read_ai_session_turns is written in SQL to deny), or report it
--     inside the gate (absent during `preparing`, i.e. useless). There
--     is no third option, because the gate and the need are on opposite
--     sides of `state = 'active'`.
--
-- (b) A GATED read_ai_session_state RPC. THIS FILE. It was Option B of
--     the original §6.1 decision, and 20260953170000's own header
--     already recorded why it would be needed later and that nothing
--     foreclosed it:
--
--       "Option B -- a gated read_ai_session_state RPC returning
--        revision plus request state -- was considered and NOT chosen
--        for this plan. It remains the right fix for a DIFFERENT gap
--        this file does not close: a client that loses its HTTP response
--        has no way to learn what happened. ... Nothing here forecloses
--        it."
--
--     A POLLING PARTNER IS THE LIMIT CASE OF THAT CLIENT: it has no
--     response to lose because it never made the call. So this closes
--     both gaps with one surface, which is why (b) is chosen even
--     though (a) is the smaller diff.
--
-- The in-repo precedent for an additive gated RPC is Plan D Task 5's
-- get_ai_session_capabilities (20260953200500), including its trap: a
-- visibility assertion run as the harness role proves nothing, because
-- the local harness is a superuser and a superuser bypasses RLS. The
-- contract test for this function therefore runs its authorization
-- probes through the RPC with each actor in turn AND carries an
-- anti-vacuity leg proving the role switch bites.
--
-- ======================================================================
-- THE CONSTRAINT THAT DOMINATES THE RETURN SHAPE: NO SIDE CHANNEL.
--
-- Ruling 6 in full: `generate` returns two `kind: "redirect"` shapes
-- that share the `kind` AND the reason set, and NOTHING may let a caller
-- distinguish them. Task 4 verified that ai_sessions.revision is NOT
-- bumped on a safety refusal -- which is exactly what makes polling the
-- revision safe rather than a disclosure -- and the edge function states
-- the hazard in its own words at the `generate` redirect branch:
--
--   "a durable redirect would be a safety side channel (redirect and
--    refusal share a reason set, so bumping the revision for
--    'unsupported' but not 'unsafe_to_assist' discloses the detector to
--    a partner polling session_revision -- §8.1 forbids exactly that)"
--
-- That sentence is about THIS POLL. So the rule for this function is:
-- A FIELD THAT MOVES ON A REFUSAL WHEN THE REVISION DOES NOT WOULD
-- REINTRODUCE THE DISCLOSURE RULING 6 EXISTS TO PREVENT.
--
-- Re-derived from the handler rather than assumed. On a safety refusal
-- (pass 1 before dispatch, or pass 2 after) the handler calls
-- settleDispatchedRequest and returns safetyRefusalResponse. It NEVER
-- reaches commit_ai_session_ideas_turn, so the `revision = revision + 1`
-- bump never runs. Confirmed structurally: every bump site in the schema
-- is inside commit_ai_session_ideas_turn,
-- publish_ai_session_nearby_result, end_ai_session,
-- reconcile_ai_session_leases or the include-window toggle -- none of
-- which a refusal calls.
--
-- SO WHAT THIS FUNCTION RETURNS, AND WHAT IT REFUSES TO RETURN:
--
--   RETURNED: `revision` and `state`.
--
--     `revision` -- the token §6.2's optimistic fence already uses and
--     the one the poll exists to compare. It does NOT move on a refusal
--     (above), so polling it discloses nothing about any detector.
--
--     `state` -- one of 'preparing' / 'active' / 'closed'. This is the
--     value that makes the `waitingForPartner` wait terminate, and it is
--     the reason (a) could not work. It carries NO safety information: a
--     refusal leaves the session `active` and leaves it `active`, so
--     this field is as unmoved by a refusal as the revision is. The
--     contract test asserts BOTH are unchanged across a refusal, with a
--     precondition proving the refusal happened.
--
--   DELIBERATELY NOT RETURNED -- each of these would be a side channel,
--   and the point of listing them is that each was considered and
--   refused rather than merely omitted:
--
--     * ANY ai_session_requests FIELD. 20260953200400 took no reason
--       parameter at all, specifically so that a safety refusal, a
--       validator rejection and a provider failure write a BYTE-IDENTICAL
--       row (state 'failed', terminal_code 'REQUEST_FAILED'). That
--       identity holds for the row, so exposing the row would not
--       disclose the detector TODAY -- but it would make a future
--       terminal_code the three paths did NOT share into a one-line
--       disclosure, through a surface already shipped and already being
--       polled. 20260953200400's own header rejects exactly this
--       reasoning ("a reason column ... is read by nothing
--       client-facing TODAY, but ... 'no reader today' is not a
--       security property"). Note also that Option B's original sketch
--       said "revision plus request state"; THIS FILE RETURNS SESSION
--       STATE, NOT REQUEST STATE, and the sentence above is why.
--     * attempt_count / generation_epoch. attempt_count advances on
--       ADMISSION, and a refusal is admitted before it is refused -- so
--       it is a counter that MOVES ON A REFUSAL WHEN THE REVISION DOES
--       NOT. That is the disclosure in its purest form: a partner
--       polling it would see "something was attempted and nothing
--       committed", which is a refusal with the serial numbers filed
--       off. Refused outright, and this is the single most important
--       omission in the file.
--     * context_revision. Frozen at activation and not advanced by the
--       bump, so it answers a different question than the poll asks; and
--       it is an input to the approval digest's neighbourhood, which
--       gate 2 keeps away from clients.
--     * expires_at / last_admitted_at. last_admitted_at advances ONLY on
--       admission, so it has attempt_count's defect exactly. expires_at
--       is recomputed FROM it, so it inherits the defect.
--     * creator_id / visibility / kind. The caller already knows all
--       three (it either created the session or approved its reviewed
--       context) and a poll is not the place to re-disclose them.
--
-- ONE CONSEQUENCE, STATED SO IT IS NOT MISTAKEN FOR AN OVERSIGHT: a
-- polling partner cannot distinguish "my partner's generation was
-- refused" from "my partner has not generated yet". That is not a
-- limitation of this function; it IS Ruling 6, and any field that
-- removed the ambiguity would be the bug.
--
-- ======================================================================
-- AUTHORIZATION: THE SAME FOUR GATES, MINUS THE ONE THAT MUST DIFFER.
--
-- read_ai_session_turns' gates 1, 2 and 4 are reproduced here verbatim
-- in intent -- active membership in a live un-archived relationship;
-- current consent from BOTH partners at the CURRENT policy version;
-- creator (private) or current-revision approver (shared). Consent is
-- computed inline for the same reason that function gives: Plan A's
-- get_ai_processing_consent_status derives its actor from auth.uid() and
-- RAISEs when it is NULL, and a service_role connection carries no JWT.
--
-- GATE 3 IS THE ONE THAT MUST DIFFER, AND THE DIFFERENCE IS THE WHOLE
-- POINT OF THE FUNCTION. read_ai_session_turns refuses `state !=
-- 'active'` because its job is to disclose CONTENT and a preparing
-- session's content is not approved yet. This function discloses NO
-- CONTENT -- there is no turn text, no snippet, no place name, no source
-- and no staged reply anywhere in its result -- so refusing a
-- `preparing` session would refuse exactly the transition the poll
-- exists to observe. Expiry IS still enforced: an expired session
-- reports nothing, so a stale sheet cannot keep polling a session whose
-- lifetime has run out and cannot learn that it ended by reading a
-- revision that still moves.
--
-- Gate 4 for a SHARED session is the approvals lookup at the session's
-- CURRENT context_revision, unchanged. A partner who has not yet
-- approved is therefore NOT authorized, which is correct and is not a
-- hole in the wait: before approving, the partner is in the `reviewing`
-- phase and holds a review_context response of its own; the poll starts
-- at `waitingForPartner`, i.e. after this actor's own approval, which is
-- what creates the approvals row this gate requires. The creator of a
-- shared session approves as part of preparation, so both parties reach
-- the wait authorized.
--
-- SILENCE, NOT AN ERROR -- the same deliberate choice, for the same
-- reason. Every unauthorized outcome is `RETURN` (zero rows): unknown
-- session, non-member, withdrawn consent, expired, a shared session this
-- actor never approved. A distinguishable error would make this an
-- existence oracle -- "no such session" versus "not authorized" tells a
-- caller whether a private session exists on a relationship they belong
-- to -- which is the disclosure §3.1's TARGET_UNAVAILABLE precedent and
-- read_ai_session_turns' entire header exist to prevent. A partner's
-- zero rows and a stranger's zero rows are byte-identical here too, and
-- the contract test asserts that directly. The p_actor_id NULL check is
-- the same single exception for the same reason: a caller bug, which
-- still returns silently rather than adding a second response shape to
-- a function whose security property is having exactly one.
--
-- AND ZERO ROWS IS NOT EVIDENCE THE SESSION IS GONE. §7.2's silence
-- applies to this function as much as to `read`: the client treats an
-- empty result as "no answer", never as "ended". The Dart side keeps
-- polling rather than concluding anything, and its own test asserts
-- that.
--
-- ======================================================================
-- LOCKS: NONE, AND THAT IS LOAD-BEARING FOR THE STRUCTURAL SWEEP.
--
-- STABLE, read-only, single SELECT per gate, no FOR UPDATE anywhere and
-- no advisory lock. So this function adds NO entry to the plan's fixed
-- lock order (relationship advisory -> requester quota advisory ->
-- ai_sessions row -> request row), exactly as read_ai_session_turns
-- adds none, and for the same stated reason: a read that took the
-- relationship lock would serialize every read behind every write for
-- no correctness gain, since a read is a single consistent snapshot
-- either way.
--
-- The reviewer's structural sweep -- enumerate every function that
-- locks or writes ai_sessions / ai_session_requests / ai_session_staging
-- and flag those holding TWO OR MORE of the three row-classes WITHOUT
-- the relationship advisory lock -- must keep returning ZERO rows. This
-- function holds ZERO row-classes: it writes nothing and locks nothing,
-- and it does not reference ai_session_requests or ai_session_staging at
-- all. It therefore cannot appear in that sweep under any reading of it,
-- which is a stronger statement than "it appears and is benign".
--
-- ======================================================================
-- SUPERSESSION: THIS FILE SUPERSEDES NOTHING. Established by grep over
-- supabase/, lib/ and docs/ before writing it, AND BY READING THE HITS
-- RATHER THAN COUNTING THEM:
--
--   grep -rn 'read_ai_session_state' supabase/ lib/ docs/
--
-- returns three pre-existing lines, and ALL THREE ARE PROSE, not
-- definitions -- a bare count would have been misleading here, which is
-- why they are enumerated:
--
--   * 20260953170000_ai_session_revision_disclosure.sql:61 -- the header
--     sentence recording Option B as considered and NOT chosen for that
--     plan (quoted above; it is the warrant for this file, not a rival
--     definition).
--   * docs/superpowers/plans/2026-10-10-ai-sessions-plan-b-merge-
--     blockers.md:201 -- the same option in the plan document.
--   * lib/.../ai_session_model.dart -- this task's own Dart doc comment.
--
-- There is NO `CREATE FUNCTION read_ai_session_state` anywhere before
-- this file. Confirmed against the live catalog as well as the tree:
--   SELECT count(*) FROM pg_proc WHERE proname = 'read_ai_session_state';
--   -- 0, before this migration applies
--
-- ONE SHIPPED COMMENT IS NOW HISTORICAL, AND IS DELIBERATELY LEFT AS
-- WRITTEN. 20260953200500's option-(c) rejection says "processSessionCommand
-- has exactly NINE cases"; this task's edge-function change makes it TEN
-- (`read_state`). That sentence is a faithful record of what was measured
-- when Task 5 was written and its ARGUMENT is untouched -- a capability
-- probe still should not be a session command, for the two reasons that
-- follow it there (it would need a relationship_id, and it would cost a
-- provider-capable invocation to decide whether to draw a button).
-- Neither reason applies to this command: it is scoped to ONE session the
-- caller is already in, and it is the cheapest possible call. Rewriting a
-- shipped migration's prose to keep a count current would damage the audit
-- trail; the Dart-side copy of the same count (ai_session_repository.dart)
-- IS updated, because it documents the CURRENT surface rather than a past
-- measurement.
--
-- public.read_ai_session_state is a NEW function. This file re-defines
-- NO existing function -- not read_ai_session_turns, not
-- read_ai_session_staging, not prepare_ai_session, not
-- activate_ai_session, not commit_ai_session_ideas_turn, not
-- publish_ai_session_nearby_result -- and adds no column, table,
-- constraint or index.
--
-- supabase/tests/ai_session_read_authorization_contracts.sql Contract 9
-- reports "12 superseded definitions"; that count is UNCHANGED by this
-- file, because nothing here was previously defined elsewhere. No
-- Contract 9 marker needed updating, and none was. This is the same
-- provenance note 20260953200400 recorded for the same reason, and its
-- accuracy is re-asserted by running the suite after this file applies.
--
-- Additive and re-appliable: CREATE OR REPLACE plus idempotent grants.
-- Sorts after 20260953200500, the current highest.

CREATE OR REPLACE FUNCTION public.read_ai_session_state(
  p_actor_id uuid, p_session_id uuid
) RETURNS TABLE (revision int, state text)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
  v_user_a uuid;
  v_user_b uuid;
  v_version text := public.ai_current_consent_policy_version();
  v_a_granted boolean;
  v_b_granted boolean;
  v_authorized boolean := false;
BEGIN
  -- Global Constraint: the NULL-actor guard is the FIRST statement, so a
  -- NULL actor is refused before this function resolves a session, a
  -- relationship or a consent event.
  IF p_actor_id IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_session FROM public.ai_sessions WHERE id = p_session_id;
  IF v_session.id IS NULL THEN
    RETURN;
  END IF;

  -- Gate 3, DELIBERATELY NARROWER THAN read_ai_session_turns': expiry is
  -- enforced, `state` is NOT constrained. See the header -- refusing a
  -- `preparing` session would refuse the preparing -> active transition
  -- this function exists to let a waiting partner observe, and no
  -- content is disclosed here for an unapproved context to leak.
  --
  -- Both clocks are checked because a session has two: preparation_deadline
  -- governs `preparing` and expires_at governs `active`. Checking only
  -- expires_at would leave a timed-out preparing session (expires_at
  -- still NULL, since it is set at activation) reporting forever.
  IF v_session.state = 'preparing' THEN
    IF v_session.preparation_deadline <= now() THEN
      RETURN;
    END IF;
  ELSIF v_session.expires_at IS NOT NULL AND v_session.expires_at <= now() THEN
    RETURN;
  END IF;

  -- Gate 1: active membership in a live, un-archived relationship.
  SELECT r.user_a, r.user_b INTO v_user_a, v_user_b
  FROM public.relationships r
  WHERE r.id = v_session.relationship_id
    AND r.status = 'active' AND r.chat_archived_at IS NULL
    AND (r.user_a = p_actor_id OR r.user_b = p_actor_id);
  -- The explicit bail-out, not left to the consent gate downstream to
  -- deny incidentally for it (review finding F3, asserted structurally
  -- by the read-authorization contracts for the sibling functions).
  IF v_user_a IS NULL THEN
    RETURN;
  END IF;

  -- Gate 2: current consent from BOTH partners at the CURRENT policy
  -- version. An event at an older version never counts as granted, which
  -- is what makes a version bump require two fresh grants -- and what
  -- makes a withdrawal stop this poll immediately rather than only
  -- stopping new generations.
  SELECT (e.action = 'granted') INTO v_a_granted
  FROM public.ai_processing_consent_events e
  WHERE e.relationship_id = v_session.relationship_id AND e.user_id = v_user_a
    AND e.policy_version = v_version
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;

  SELECT (e.action = 'granted') INTO v_b_granted
  FROM public.ai_processing_consent_events e
  WHERE e.relationship_id = v_session.relationship_id AND e.user_id = v_user_b
    AND e.policy_version = v_version
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;

  IF NOT (COALESCE(v_a_granted, false) AND COALESCE(v_b_granted, false)) THEN
    RETURN;
  END IF;

  -- Gate 4: creator (private) or current-revision approver (shared),
  -- unchanged from read_ai_session_turns. A partner who approved an
  -- OLDER snapshot does not inherit access to a re-approved one.
  IF v_session.visibility = 'private' THEN
    v_authorized := (v_session.creator_id = p_actor_id);
  ELSE
    v_authorized := EXISTS (
      SELECT 1 FROM public.ai_session_approvals a
      WHERE a.session_id = p_session_id
        AND a.member_id = p_actor_id
        AND a.revision = v_session.context_revision
    );
  END IF;

  IF NOT v_authorized THEN
    RETURN;
  END IF;

  -- TWO COLUMNS. Every other column of v_session is in scope on this
  -- line and each one is deliberately left out; the header says which
  -- and why. attempt_count and last_admitted_at in particular MOVE ON A
  -- REFUSAL, and returning either would be the Ruling 6 disclosure.
  RETURN QUERY SELECT v_session.revision, v_session.state;
END;
$$;

-- service_role ONLY, exactly like the two sibling read RPCs. The edge
-- function is the only caller: it is what turns a verified JWT into the
-- p_actor_id this function trusts as its sole authorization input, which
-- is the property that lets the function be silent. A direct
-- `authenticated` grant would let a caller pass any actor id and read
-- any session that actor could read.
REVOKE ALL ON FUNCTION public.read_ai_session_state(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_ai_session_state(uuid, uuid)
  TO service_role;
