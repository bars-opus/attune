-- Plan C Task 5, ITEM A2 (user Ruling 18): SETTLE A REQUEST WITHOUT
-- WAITING FOR THE LEASE.
--
-- Spec §6.2, §7.3, §8.1, §8.2.2.
--
-- ======================================================================
-- THE GAP, as Task 4 measured it rather than inferred it.
--
-- Task 4 queried pg_proc for EVERY `%ai_session%` function and found
-- there is NO fail/release/abandon entry point anywhere in the schema.
-- Consequently all three of these leave the ai_session_requests row at
-- state = 'started' with a live 35-second lease:
--
--   * a PRE-PUBLISH SAFETY REFUSAL (the edge function's safety pass 2),
--   * a §5.3 VALIDATOR REJECTION of the provider's output,
--   * a PROVIDER FAILURE (Gemini or Mapbox returning nothing).
--
-- admit_ai_session_generation's single-outstanding-request gate then
-- refuses every retry with SESSION_BUSY until
-- reconcile_ai_session_leases settles the row, which is up to 35
-- seconds away and in the worst case up to a minute (pg_cron runs the
-- reconciler every minute). The user who tripped any of the three waits
-- before they can try again. Poor UX, not a correctness or disclosure
-- defect -- which is why Task 4 pinned the behaviour in a test rather
-- than inventing a column, and why this is a Plan B migration.
--
-- ======================================================================
-- THIS MIGRATION SUPERSEDES NOTHING. Established by grep over
-- supabase/, lib/ and docs/:
--
--   grep -rn 'settle_ai_session_request' supabase/ lib/ docs/
--     -> 0 files before this one
--
-- public.settle_ai_session_request is a NEW function. This file
-- re-defines NO existing function -- not reconcile_ai_session_leases,
-- not end_ai_session, not admit_ai_session_generation, not
-- claim_ai_session_dispatch, not release_ai_assistant_quota_reservation,
-- not mark_ai_assistant_usage_outcome -- and adds no column, table or
-- constraint.
--
-- supabase/tests/ai_session_read_authorization_contracts.sql Contract 9
-- reports "12 superseded definitions"; that count is UNCHANGED by this
-- file, because nothing here was previously defined elsewhere. No
-- Contract 9 marker needed updating, and none was.
--
-- ======================================================================
-- THE NON-NEGOTIABLE PROPERTY, AND HOW IT IS SATISFIED STRUCTURALLY.
--
-- Task 4 observed that the busy-until-lease-expiry disposition is
-- IDENTICAL for a safety refusal and a provider timeout, and named that
-- as the one good consequence of the gap: the request row cannot
-- disclose that a SAFETY detector fired. A settle RPC must not throw
-- that away. Plan C's Global Constraint: "A safety refusal never
-- reveals which detector fired, to either party."
--
-- THIS FUNCTION TAKES NO REASON PARAMETER AT ALL.
--
-- That is the choice, and it is stronger than the two alternatives the
-- brief allowed:
--
--   * Alternative 1, "the reason must not be client-readable": a
--     reason column on ai_session_requests is read by nothing
--     client-facing TODAY, but ai_session_requests has RLS enabled with
--     zero policies precisely because "no reader today" is not a
--     security property -- a future read RPC, an admin view or a support
--     tool makes it one. Storing the distinction and relying on nobody
--     reading it is the configuration that produced this plan's F2.
--
--   * Alternative 2, "the safety path reuses the provider-failure
--     value": correct in effect, but it leaves a SECOND, correct value
--     available in the signature and depends forever on every caller
--     choosing the right one. A caller adding `reason: 'safety'` for
--     debugging would be a one-line disclosure, and Task 4 already
--     found exactly that failure mode in itself ("a field added to the
--     refusal body survived every other test").
--
-- With no parameter there is no value to choose and nothing for a
-- caller to get wrong. Every settle -- safety, validator, provider --
-- writes the IDENTICAL row: state = 'failed', terminal_code =
-- 'REQUEST_FAILED'. Not merely indistinguishable: byte-identical, by
-- construction, with no code path that could differ.
--
-- WHY 'REQUEST_FAILED' AND NOT 'LEASE_EXPIRED'. The row must not be
-- distinguishable BY DETECTOR; it may be distinguishable by MECHANISM,
-- and here it must be. reconcile_ai_session_leases writes
-- terminal_code = 'LEASE_EXPIRED' for a worker that DIED without
-- reporting -- an operational fault worth seeing in a dashboard.
-- 'REQUEST_FAILED' means the worker lived, finished and reported a
-- failure. Collapsing the two would make a real outage (workers
-- vanishing) indistinguishable from routine refusals, and that
-- distinction carries no information about any user's content: it says
-- WHO ended the attempt, not WHY. 'REQUEST_FAILED' is also exactly the
-- §10 code the edge function already returns on this family of paths.
--
-- NOT A NEW STATE. 'failed' is already in ai_session_requests' CHECK
-- (20260953020000) and is already what reconcile_ai_session_leases
-- writes. This file adds NO terminal state to the schema, which is the
-- literal form of "must not introduce a terminal state that
-- distinguishes the safety path".
--
-- ======================================================================
-- QUOTA: A 'started' REQUEST STAYS CHARGED. This is the half that must
-- match what the remediation established, and the precedent is
-- reconcile_ai_session_leases' own 'reserved' branch plus
-- end_ai_session's loop. Both get it right; this function copies them.
--
--   * state = 'reserved' -- NEVER DISPATCHED. claim_ai_session_dispatch
--     never ran, so claim_ai_assistant_provider_start never set the
--     write-once ai_assistant_usage.provider_started_at marker and no
--     provider call was ever made. The reservation is genuinely
--     unconsumed and is released exactly once via Plan A's
--     release_ai_assistant_quota_reservation (spec §7.3: "A terminal
--     failure proven to have no provider-start marker may release
--     global quota once"). Without this the row sits at outcome =
--     'reserved' forever, counted against the actor's rolling 24h
--     window and invisible to the reconciler once this function has
--     moved it out of the scanned states.
--
--   * state IN ('started', 'staged') -- DISPATCHED. The write-once
--     provider marker IS set, so the quota is LEGITIMATELY consumed and
--     MUST STAY CHARGED. A settle that released it would be a REFUND
--     BUTTON FOR A CALL ALREADY PAID FOR: a user could burn no quota at
--     all by triggering a refusal on every attempt. The row is
--     deliberately NOT passed to the release RPC -- which would RAISE
--     'Cannot release a reservation whose provider call has started'
--     rather than silently no-op -- and is instead resolved to the
--     COUNTED terminal outcome 'provider_failed' via
--     mark_ai_assistant_usage_outcome. That outcome is outside the
--     rolling-window COUNT's exclusion set ('rejected', 'cancelled'),
--     so it stays counted; 20260952030000's own guard independently
--     refuses to move a marked row to either excluded value, so even a
--     future miscall here cannot refund it.
--
-- WHY 'provider_failed' RATHER THAN LEAVING THE LEDGER ROW AT
-- 'reserved'. Leaving it reserved would also stay charged (that is
-- 20260952030000's point), but it would leave the ledger permanently
-- non-terminal for a request that is terminal, and
-- reconcile_ai_session_quota_residue would then be the only thing that
-- ever resolves it. Resolving it here is the same narrowest-resolution
-- judgement 20260953160000 made for the orphan branch, and it is
-- quota-neutral by construction.
--
-- THE SAFETY PATH AND THE PROVIDER PATH REACH THIS FUNCTION IN THE SAME
-- STATE, which is what makes the indistinguishability real rather than
-- asserted: both run AFTER claim_ai_session_dispatch (the edge
-- function's step 7), so both arrive at state = 'started' and both take
-- the identical branch. A safety refusal is not even capable of
-- reaching the 'reserved' branch -- safety pass 1 returns BEFORE
-- admission, so it creates no request row at all.
--
-- ======================================================================
-- WHO MAY SETTLE: THE REQUEST'S OWN ACTOR, AND ONLY THEM.
--
-- Narrower than end_ai_session (either member may end a shared
-- session), deliberately. Settling is the WORKER reporting its own
-- attempt's outcome, not a session-lifecycle act. A partner being able
-- to settle the creator's in-flight request would be a way to cancel
-- someone else's generation mid-flight -- a smaller cousin of the
-- partner-weaponizable quota DoS that this plan's F1 was. The authority
-- to abandon an attempt belongs to whoever admitted it.
--
-- ======================================================================
-- IDEMPOTENT, AND SILENT ON EVERY NON-ACTIONABLE CASE.
--
-- An unknown request, an already-terminal request ('committed',
-- 'failed', 'cancelled') and a request belonging to another actor all
-- return WITHOUT raising and WITHOUT changing anything. Three reasons:
--
--   * The edge function calls this on failure paths, where a raise
--     would convert a handled refusal into an INTERNAL_ERROR and
--     replace a carefully neutral §8.1 refusal body with a
--     distinguishable error. The settle must never be able to change
--     what the caller returns.
--   * A retry of a settle is routine (the edge function may settle a
--     request whose lease the reconciler already settled), and
--     'already settled' is success, not failure.
--   * Silence on a foreign actor matches read_ai_session_turns'
--     deliberate silence (20260953100000's header): a raise would make
--     this RPC an existence oracle for other people's request ids.
--     Nothing is written, which is the security property; the caller
--     learning nothing is the point.
--
-- It returns `settled boolean` so a CALLER that cares can tell whether
-- it did the work, without any outcome being reported differently to
-- the end user.
--
-- ======================================================================
-- LOCK ORDER: A PREFIX OF THE FIXED ORDER, IN ORDER.
--
-- The plan's fixed order is
--   relationship advisory lock
--     -> quota advisory lock (inside reserve_ai_assistant_quota)
--     -> session row FOR UPDATE
--     -> request row.
--
-- This function takes elements 1, 3 and 4:
--   LOCK 1  pg_advisory_xact_lock(hashtext(v_relationship_id::text))
--   LOCK 2  PERFORM 1 FROM public.ai_sessions ... FOR UPDATE
--   LOCK 3  SELECT * FROM public.ai_session_requests ... FOR UPDATE
--
-- -- exactly the three end_ai_session, publish_ai_session_nearby_result
-- and discard_ai_session_nearby_staging take, at the same points and in
-- the same order. It reserves no quota, so it never reaches element 2;
-- release_ai_assistant_quota_reservation and
-- mark_ai_assistant_usage_outcome touch ai_assistant_usage only, which
-- no lock in this chain covers, and both are called while already
-- holding the relationship lock -- the same nesting
-- admit_ai_session_generation establishes.
--
-- THE SESSION ROW LOCK IS TAKEN EVEN THOUGH THIS FUNCTION NEVER WRITES
-- ai_sessions. Same reason 20260953150000 gives for discard: a
-- participant that SKIPS an element of a lock order is how the order
-- stops being a total order. This function holds the request row while
-- publish/discard/end hold the session row, so without element 3 it
-- would be a new cycle participant.
--
-- THE STRUCTURAL SWEEP STILL RETURNS ZERO. The sweep flags functions
-- locking or writing two or more of ai_sessions / ai_session_requests /
-- ai_session_staging WITHOUT the relationship advisory lock. This
-- function holds two of the three (ai_sessions, ai_session_requests) --
-- so it IS in scope -- and takes the advisory lock FIRST, which is the
-- property the sweep checks. Re-verified by running the sweep after
-- this migration: zero rows.
--
-- ======================================================================
-- NO SESSION REVISION IS BUMPED, AND THAT IS LOAD-BEARING. Ruling 1
-- sanctioned polling ai_sessions.revision as the invalidation
-- mechanism; Task 4 verified a safety refusal does not bump it, so it
-- cannot become a side channel. This function must not reintroduce
-- that: a settle on a safety path and a settle on a provider failure
-- would both bump, which is no disclosure between them -- but a
-- partner polling the revision would observe a bump for an attempt
-- that produced NO content, where today it observes nothing at all.
-- Nothing in a failed attempt is content, so there is nothing for a
-- revision to invalidate. ai_sessions is read FOR UPDATE and never
-- written here.
-- ======================================================================
CREATE OR REPLACE FUNCTION public.settle_ai_session_request(
  p_actor_id uuid,
  p_request_id uuid
) RETURNS TABLE (settled boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_id uuid;
  v_relationship_id uuid;
  v_request public.ai_session_requests;
BEGIN
  -- THE LITERAL FIRST STATEMENT (Global Constraint / Ruling 14).
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Lock-target lookup ONLY -- unlocked, decides nothing except which
  -- rows to lock and whether there is anything to do at all. The
  -- authorization comparison is NOT made here; it is made on the
  -- re-read under the locks below. Same shape 20260953120000 gave the
  -- completion RPCs and 20260953150000 gave discard.
  SELECT rq.session_id, se.relationship_id
  INTO v_session_id, v_relationship_id
  FROM public.ai_session_requests rq
  LEFT JOIN public.ai_sessions se ON se.id = rq.session_id
  WHERE rq.id = p_request_id;

  IF v_session_id IS NULL OR v_relationship_id IS NULL THEN
    -- Unknown request, or a request whose session is gone. Silent,
    -- per the header: a raise here would be an existence oracle and
    -- would corrupt the caller's own refusal body.
    RETURN QUERY SELECT false;
    RETURN;
  END IF;

  -- LOCK 1: the relationship advisory lock.
  PERFORM pg_advisory_xact_lock(hashtext(v_relationship_id::text));

  -- LOCK 2: the session row, before the request row. Not written here
  -- (see the header) -- taken so this function occupies the documented
  -- order at the same points as end_ai_session, publish and discard.
  PERFORM 1 FROM public.ai_sessions WHERE id = v_session_id FOR UPDATE;

  -- LOCK 3: the request row, re-read AUTHORITATIVELY under both locks.
  -- Everything below is decided from THIS read: a row that reached a
  -- terminal state while this transaction waited for the locks -- which
  -- is exactly the race against reconcile_ai_session_leases -- must be
  -- judged in its new state, not the pre-read's.
  SELECT * INTO v_request FROM public.ai_session_requests
  WHERE id = p_request_id FOR UPDATE;
  IF v_request.id IS NULL THEN
    RETURN QUERY SELECT false;
    RETURN;
  END IF;

  -- The request's OWN actor, and only them. See the header: settling is
  -- the worker reporting its own attempt, not a lifecycle act a partner
  -- shares. Silent, like every other non-actionable case.
  IF v_request.actor_id != p_actor_id THEN
    RETURN QUERY SELECT false;
    RETURN;
  END IF;

  -- Already terminal: 'committed' (it succeeded), 'failed' or
  -- 'cancelled' (something already settled it, very likely the
  -- reconciler or end_ai_session). Idempotent success, nothing written.
  -- Scoped as a positive allowlist of the two SETTLEABLE states rather
  -- than a deny-list of the terminal ones, so a state added to the
  -- table's CHECK in future fails closed here instead of being
  -- silently settled.
  IF v_request.state NOT IN ('reserved', 'started', 'staged') THEN
    RETURN QUERY SELECT false;
    RETURN;
  END IF;

  -- ---- THE SETTLE. One row, one shape, every path --------------------
  --
  -- IDENTICAL for a safety refusal, a validator rejection and a
  -- provider failure, because there is no parameter by which they could
  -- differ. 'failed' is already in the table's CHECK and is already
  -- what the reconciler writes; 'REQUEST_FAILED' distinguishes "the
  -- worker reported a failure" from the reconciler's 'LEASE_EXPIRED'
  -- ("the worker vanished"), which is a MECHANISM distinction carrying
  -- nothing about any user's content.
  UPDATE public.ai_session_requests
  SET state = 'failed', terminal_code = 'REQUEST_FAILED'
  WHERE id = p_request_id;

  IF v_request.state = 'reserved' THEN
    -- NEVER DISPATCHED: claim_ai_session_dispatch never ran, so
    -- ai_assistant_usage.provider_started_at IS NULL and no provider
    -- call was made. Release exactly once -- spec §7.3, and the same
    -- branch reconcile_ai_session_leases and end_ai_session both take.
    --
    -- v_request.actor_id, not p_actor_id: identical values here (the
    -- actor check above proved it), and written this way so the release
    -- is against the CHARGED actor by construction rather than by that
    -- coincidence holding forever.
    --
    -- The ORPHAN GUARD is 20260953160000's, for the same reason: Plan
    -- A's registered 30-day purge_old_ai_assistant_usage() hard-deletes
    -- usage rows and nothing prunes ai_session_requests, with no FK in
    -- either direction, so a request can outlive its ledger row. The
    -- release RPC would RAISE 'Reservation not found for this actor' on
    -- one, and an uncaught raise here would roll back the terminal
    -- UPDATE above and undo the whole settle. There is also nothing to
    -- release: reserve_ai_assistant_quota's window is 24 hours, so a
    -- row the 30-day purger could delete left that window 29 days ago.
    IF EXISTS (
      SELECT 1 FROM public.ai_assistant_usage
      WHERE request_id = p_request_id AND user_id = v_request.actor_id
    ) THEN
      PERFORM public.release_ai_assistant_quota_reservation(
        v_request.actor_id, p_request_id);
    END IF;
  ELSE
    -- 'started' or 'staged' -- DISPATCHED. The write-once provider
    -- marker IS set (20260953060100), so this reservation has
    -- LEGITIMATELY consumed quota and MUST STAY CHARGED. Releasing it
    -- would make a settle a refund button for a call already paid for.
    --
    -- Resolved to the COUNTED terminal outcome instead. 'provider_failed'
    -- is outside the rolling-window COUNT's exclusion set
    -- ('rejected', 'cancelled'), so the row stays counted; and
    -- 20260952030000's own guard independently refuses to move a
    -- marked row to either excluded value, so this cannot become a
    -- refund even if someone later changes the literal below.
    --
    -- mark_ai_assistant_usage_outcome is deliberately silent when no
    -- row matches (a purged ledger row, a row already terminal), so the
    -- orphan case needs no guard on this branch.
    --
    -- provider_calls = 1: one provider call was made and failed. A
    -- Nearby attempt that reached 'staged' made two, but a 'staged' row
    -- arriving here is the pre-publish refusal path, where the second
    -- call already returned -- so this is reported as the conservative
    -- 1 rather than a count this function would have to infer from
    -- kind. The value is accounting detail, not quota: the rolling
    -- window COUNTs ROWS, not provider_calls (verified in
    -- reserve_ai_assistant_quota's body), so it cannot change what the
    -- actor is charged either way.
    PERFORM public.mark_ai_assistant_usage_outcome(
      v_request.actor_id, p_request_id, 'provider_failed', 1::smallint);
  END IF;

  -- ai_sessions is NOT written. No revision bump, no epoch bump: a
  -- failed attempt produced no content, so there is nothing to
  -- invalidate, and bumping would make a partner polling
  -- session_revision (Ruling 1) observe an attempt that produced
  -- nothing. See the header.
  RETURN QUERY SELECT true;
END;
$$;

REVOKE ALL ON FUNCTION public.settle_ai_session_request(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_ai_session_request(uuid, uuid)
  TO service_role;

COMMENT ON FUNCTION public.settle_ai_session_request(uuid, uuid) IS
  'Settles ONE in-flight ai_session_requests row as terminal without waiting '
  'for its 35-second lease, so a pre-publish safety refusal, a spec 5.3 '
  'validator rejection and a provider failure do not each leave the session '
  'SESSION_BUSY for up to 35 seconds (Plan C Task 4''s finding; there was no '
  'fail/release/abandon entry point in the schema at all). TAKES NO REASON '
  'PARAMETER, deliberately: every path writes the byte-identical row '
  '(state = ''failed'', terminal_code = ''REQUEST_FAILED''), so the row cannot '
  'disclose that a SAFETY detector fired rather than the provider having '
  'failed -- there is no value for a caller to choose and none to get wrong. '
  'Adds NO terminal state to the schema: ''failed'' is already in the CHECK and '
  'is already what reconcile_ai_session_leases writes, whose ''LEASE_EXPIRED'' '
  'remains distinct because "the worker vanished" is an operational fact worth '
  'seeing. QUOTA: a ''reserved'' request never dispatched is released once per '
  'spec 7.3; a ''started''/''staged'' request carries the write-once '
  'provider-start marker and STAYS CHARGED, resolved to the counted outcome '
  '''provider_failed'' -- releasing it would make a settle a refund button for a '
  'provider call already paid for. Settleable only by the request''s OWN actor; '
  'silent and idempotent on an unknown, foreign or already-terminal request so '
  'it can never turn a caller''s neutral refusal into a distinguishable error. '
  'Bumps no session revision: a failed attempt produced no content. Lock order: '
  'relationship advisory lock, session row FOR UPDATE, request row FOR UPDATE '
  '-- the same three end_ai_session, publish and discard take.';
