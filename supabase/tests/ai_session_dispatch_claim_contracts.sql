-- claim_ai_session_dispatch / reconcile_ai_session_leases. Spec §6.2, §8.2.2.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_dispatch_claim_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000007';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000006a';
  v_user_b uuid := 'b1000000-0000-0000-0000-000000000132';
  v_session uuid;
  v_admit record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_a, 'claim_a@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_a, '+15550014001', 'A') ON CONFLICT DO NOTHING;
  -- FIXTURE COMPLETION (Task 3, merge-blockers plan). This fixture
  -- previously created a ONE-SIDED relationship (user_b NULL) with NO
  -- consent events and still passed, because no dispatch-path RPC in
  -- Plan B ever checked consent -- only the Task 10 read RPCs and
  -- Task 11's Nearby publish did. admit_ai_session_generation now
  -- enforces the membership + AI-processing consent gate spec §7.2
  -- requires (20260953140000), so every admission here needs a real
  -- partner and two current grants.
  --
  -- This is an ADDITION, not a correction: the fixture was incomplete
  -- relative to §7.2, not wrong relative to the code as it then stood.
  -- No assertion below is changed.
  --
  -- A one-sided relationship can never satisfy two-party consent, which
  -- is correct by construction rather than incidental: the gate reads
  -- BOTH r.user_a and r.user_b, and a NULL user_b makes the second
  -- consent lookup filter on `e.user_id = NULL`, match nothing, and
  -- COALESCE(NULL, false) deny. That is the intended semantics for a
  -- relationship with only one member.
  --
  -- clock_timestamp(), never now(): now() is frozen per transaction, so
  -- events written in one DO block would share an identical created_at
  -- and the consent lookup's tiebreak would fall to `id DESC` on a
  -- random uuid, making any consent-ordering assertion a coin flip.
  -- ai_processing_consent_events.idempotency_key is NOT NULL.
  INSERT INTO auth.users (id, email) VALUES (v_user_b, 'admitgate_partner_claim@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_b, '+15550021003', 'B') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_user_a, v_user_b, 'active') ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp');

  -- Contract 1: the matching worker_token claims successfully.
  IF public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: the correct worker_token failed to claim dispatch';
  END IF;
  IF (SELECT state FROM public.ai_session_requests WHERE id = v_admit.request_id) != 'started' THEN
    RAISE EXCEPTION 'EXPLOIT: request state did not advance to started after a successful claim';
  END IF;

  -- Contract 2: a WRONG worker_token cannot claim the same request.
  IF public.claim_ai_session_dispatch(gen_random_uuid(), v_admit.request_id) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: a mismatched worker_token was allowed to claim dispatch';
  END IF;

  -- Contract 3: a second claim with the CORRECT token (retry after a
  -- lost HTTP response) returns false, not a second dispatch.
  IF public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: the same worker_token claimed dispatch twice';
  END IF;

  -- Contract 4: an EXPIRED lease is reconciled to failed and its
  -- request is fenced from further claims.
  DECLARE
    v_admit2 record;
  BEGIN
    SELECT * INTO v_admit2 FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp-2');
    UPDATE public.ai_session_requests SET lease_deadline = now() - interval '1 second' WHERE id = v_admit2.request_id;
    PERFORM public.reconcile_ai_session_leases();
    IF (SELECT state FROM public.ai_session_requests WHERE id = v_admit2.request_id) != 'failed' THEN
      RAISE EXCEPTION 'EXPLOIT: an expired lease was not reconciled to failed';
    END IF;
    IF public.claim_ai_session_dispatch(v_admit2.worker_token, v_admit2.request_id) IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'EXPLOIT: a reconciled (failed) request still allowed a dispatch claim';
    END IF;
  END;

  -- Contract 5 (fix round 1): a successful claim sets the REAL,
  -- ledger-level provider-start marker on ai_assistant_usage, not just
  -- the session-local ai_session_requests.provider_started_at. Uses a
  -- FRESH relationship + session (rather than v_session, whose only
  -- request from contract 1 is still 'started' and would make any
  -- further admission on that session return 'busy' per
  -- admit_ai_session_generation's single-outstanding-request gate;
  -- and prepare_ai_session itself refuses a second pending/active
  -- private session for the same (creator, relationship) pair).
  DECLARE
    v_rel2 uuid := 'b1000000-0000-0000-0000-000000000107';
    v_session3 uuid;
    v_admit3 record;
  BEGIN
    -- FIXTURE COMPLETION (Task 3): this SECOND relationship also needs
    -- a real partner and two current grants, for the same reason the
    -- outer fixture does -- admit_ai_session_generation now enforces
    -- spec §7.2's membership + consent gate (20260953140000). Consent
    -- is scoped per RELATIONSHIP, so the grants on v_rel above do not
    -- carry over here and must be repeated for v_rel2; the same two
    -- users are reused, which is why no new auth.users/public.users
    -- rows are needed. No assertion below is changed.
    INSERT INTO public.relationships (id, user_a, user_b, status)
      VALUES (v_rel2, v_user_a, v_user_b, 'active') ON CONFLICT DO NOTHING;
    INSERT INTO public.ai_processing_consent_events
      (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
    VALUES
      (v_rel2, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
      (v_rel2, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());
    SELECT session_id INTO v_session3 FROM public.prepare_ai_session(
      v_user_a, gen_random_uuid(), v_rel2, 'ideas', 'private', NULL, false
    );
    PERFORM public.approve_ai_session_context(v_user_a, v_session3, 1, 'd', 'v1');
    PERFORM public.activate_ai_session(v_user_a, v_session3, 1);
    SELECT * INTO v_admit3 FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session3, 1, 'ideas:fp-3');
    PERFORM public.claim_ai_session_dispatch(v_admit3.worker_token, v_admit3.request_id);

    IF (SELECT provider_started_at FROM public.ai_assistant_usage WHERE request_id = v_admit3.request_id) IS NULL THEN
      RAISE EXCEPTION 'EXPLOIT: claim_ai_session_dispatch did not set the ai_assistant_usage provider-start marker';
    END IF;

    -- Contract 6: with the marker now genuinely set,
    -- release_ai_assistant_quota_reservation must correctly REFUSE to
    -- release this reservation (it raises per its own guard), proving
    -- the quota consumption is now permanent for a 'started' request.
    BEGIN
      PERFORM public.release_ai_assistant_quota_reservation(v_user_a, v_admit3.request_id);
      RAISE EXCEPTION 'EXPLOIT: quota reservation for a STARTED request was released';
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLERRM != 'Cannot release a reservation whose provider call has started' THEN
          RAISE;
        END IF;
    END;
  END;

  RAISE NOTICE 'dispatch claim / reconcile contracts: all held';
END $$;


-- =====================================================================
-- Contract 7 (Task 4, merge-blockers plan): PER-ROW FAULT ISOLATION in
-- reconcile_ai_session_leases.
--
-- THE DEFECT. The pre-fix body called
-- release_ai_assistant_quota_reservation directly in the function body
-- with no handler. That RPC raises 'Reservation not found for this
-- actor' when no ai_assistant_usage row exists for
-- (request_id, actor_id), and an uncaught RAISE aborts the WHOLE
-- transaction -- which, for a function pg_cron invokes, is the whole
-- run. So one orphaned row rolled back every HEALTHY row reconciled
-- alongside it, and because pg_cron runs this every minute over an
-- UNBOUNDED scan (state IN ('reserved','started') AND lease_deadline <
-- now(), no LIMIT), that orphan matched again on every subsequent run
-- forever. One bad row starved lease reconciliation PLATFORM-WIDE:
-- no expired lease ever marked 'failed' again for any user, so no
-- session could admit a fresh attempt, and no never-dispatched quota
-- reservation ever released again.
--
-- WHY THIS CONTRACT SEEDS TWO ROWS AND NOT ONE. A single-orphan test
-- would pass against the pre-fix body for the wrong reason -- the raise
-- aborts a transaction that had nothing else in it, so there is no
-- observable collateral. The SECOND, healthy row in the SAME run is the
-- entire point: it is what distinguishes "the orphan was handled" from
-- "the orphan took the batch down with it." Contract 7b asserts that
-- healthy row IS resolved, and that assertion is what dies when the
-- isolation is removed.
--
-- A NOTE ON RUN ISOLATION. Both requests must have expired leases in
-- the SAME reconciler call, which means two sessions -- admit's
-- single-outstanding-request gate allows only one live request per
-- session, and prepare_ai_session refuses a second pending/active
-- PRIVATE session for the same (creator, relationship) pair. So this
-- block uses two fresh relationships, with their own users, rather than
-- reusing the outer fixture's v_rel/v_rel2 (whose sessions already
-- carry requests from contracts 1 and 5 and whose states those
-- contracts assert).
-- =====================================================================
DO $$
DECLARE
  v_user_a uuid := 'b1000000-0000-0000-0000-000000000040';
  v_user_b uuid := 'b1000000-0000-0000-0000-000000000041';
  v_rel_orphan  uuid := 'b1000000-0000-0000-0000-000000000042';
  v_rel_healthy uuid := 'b1000000-0000-0000-0000-000000000043';
  v_sess_orphan uuid;
  v_sess_healthy uuid;
  v_admit_orphan record;
  v_admit_healthy record;
  v_reconciled int;
  v_state text;
  v_outcome text;
BEGIN
  -- Fresh users and relationships. Both ids and both phones were swept
  -- suite-wide as unused and uuid-cast-validated before being chosen
  -- (the plan's fixture collisions have bitten seven times, twice via a
  -- silently-dropped ON CONFLICT DO NOTHING on the UNIQUE users.phone).
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'lease_iso_a@t.test'), (v_user_b, 'lease_iso_b@t.test');
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550077001', 'IsoA'), (v_user_b, '+15550077002', 'IsoB');
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
    (v_rel_orphan, v_user_a, v_user_b, 'active'),
    (v_rel_healthy, v_user_a, v_user_b, 'active');
  -- admit_ai_session_generation enforces spec §7.2's membership + AI
  -- processing consent gate (20260953140000), so BOTH partners need a
  -- current grant on EACH relationship -- consent is scoped per
  -- relationship. clock_timestamp(), never now(): now() is frozen per
  -- transaction, so events written in one DO block would share an
  -- identical created_at and the consent lookup's tiebreak would fall
  -- to `id DESC` on a random uuid. idempotency_key is NOT NULL.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel_orphan,  v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel_orphan,  v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel_healthy, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel_healthy, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_sess_orphan FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel_orphan, 'ideas', 'private', NULL, false);
  PERFORM public.approve_ai_session_context(v_user_a, v_sess_orphan, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_sess_orphan, 1);
  SELECT * INTO v_admit_orphan FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_sess_orphan, 1, 'ideas:iso-orphan');

  SELECT session_id INTO v_sess_healthy FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel_healthy, 'ideas', 'private', NULL, false);
  PERFORM public.approve_ai_session_context(v_user_a, v_sess_healthy, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_sess_healthy, 1);
  SELECT * INTO v_admit_healthy FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_sess_healthy, 1, 'ideas:iso-healthy');

  -- Both leases expire, so ONE reconciler call scans both rows.
  UPDATE public.ai_session_requests
    SET lease_deadline = now() - interval '1 second'
    WHERE id IN (v_admit_orphan.request_id, v_admit_healthy.request_id);

  -- ORPHAN the first row THE WAY SHIPPED CRON DOES IT, not by a manual
  -- DELETE. This is the second half of the defect and the reason it is
  -- Important rather than theoretical: Plan A registers
  -- purge_old_ai_assistant_usage() in cron.job ('purge-ai-assistant-
  -- usage', '37 * * * *', per 20260950100000) and it hard-deletes
  -- ai_assistant_usage rows older than 30 days. Nothing prunes
  -- ai_session_requests on any schedule, and there is NO foreign key in
  -- either direction between the two tables (ai_assistant_usage is Plan
  -- A's ledger, shared with the 'assist'/'understand' modes, keyed only
  -- on request_id), so nothing stops the purger deleting a usage row
  -- out from under a surviving request row.
  --
  -- Calling the REAL purger rather than issuing the DELETE ourselves is
  -- what makes this the shipped-cron-reachable contract the brief asked
  -- for: if Plan A ever adds an FK, narrows the predicate, or stops
  -- deleting, this setup stops producing an orphan and the SETUP FAILED
  -- guard below fires instead of passing vacuously.
  UPDATE public.ai_assistant_usage
    SET created_at = now() - interval '31 days'
    WHERE request_id = v_admit_orphan.request_id;
  PERFORM public.purge_old_ai_assistant_usage();

  -- Anti-vacuity on the setup itself, both directions. If the orphan is
  -- not actually orphaned, or the healthy row lost its usage row too,
  -- every assertion below would pass for the wrong reason.
  IF EXISTS (SELECT 1 FROM public.ai_assistant_usage
             WHERE request_id = v_admit_orphan.request_id) THEN
    RAISE EXCEPTION
      'SETUP FAILED: Plan A''s purge_old_ai_assistant_usage() did not delete the aged ai_assistant_usage row, so no orphan exists and this contract cannot discriminate. Either its 30-day predicate changed or an FK to ai_session_requests now blocks the delete -- re-derive this fixture.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ai_assistant_usage
                 WHERE request_id = v_admit_healthy.request_id
                   AND outcome = 'reserved') THEN
    RAISE EXCEPTION
      'SETUP FAILED: the HEALTHY request has no reserved ai_assistant_usage row, so it is not actually healthy and Contract 7b would prove nothing.';
  END IF;
  IF (SELECT count(*) FROM public.ai_session_requests
      WHERE state IN ('reserved','started') AND lease_deadline < now()
        AND id IN (v_admit_orphan.request_id, v_admit_healthy.request_id)) != 2 THEN
    RAISE EXCEPTION
      'SETUP FAILED: the orphan and the healthy request are not BOTH matched by the reconciler scan predicate, so they would not be processed in one run -- which is the only thing this contract tests.';
  END IF;

  -- Contract 7a: THE RUN SURVIVES. Pre-fix this raised 'Reservation not
  -- found for this actor' and aborted.
  BEGIN
    SELECT public.reconcile_ai_session_leases() INTO v_reconciled;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' OR SQLERRM LIKE 'SETUP FAILED:%' THEN
      RAISE;
    END IF;
    -- Assert the SPECIFIC pre-fix error, not "any error": that message
    -- is the signature of the missing per-row handler, and naming it is
    -- what makes this contract a regression test for THIS defect rather
    -- than a smoke test.
    IF SQLERRM = 'Reservation not found for this actor' THEN
      RAISE EXCEPTION
        'EXPLOIT: reconcile_ai_session_leases aborted the whole run with "Reservation not found for this actor" on an orphaned request row. One row with no ai_assistant_usage row -- which Plan A''s registered 30-day purge_old_ai_assistant_usage() creates on its own -- takes down every healthy row in the same run, and because pg_cron runs this every minute over an unbounded scan it does so forever, starving lease reconciliation platform-wide.';
    END IF;
    RAISE EXCEPTION
      'EXPLOIT: reconcile_ai_session_leases aborted the whole run on an orphaned request row with an unexpected error (%). Per-row fault isolation must contain ANY single row''s failure, not just the known missing-usage raise.', SQLERRM;
  END;

  -- Contract 7b: THE HEALTHY ROW IS RESOLVED. This is the assertion the
  -- whole task turns on. Pre-fix the run aborted, so this row was left
  -- byte-identical to its BEFORE state -- resolved, then rolled back.
  SELECT state INTO v_state FROM public.ai_session_requests
    WHERE id = v_admit_healthy.request_id;
  IF v_state != 'failed' THEN
    RAISE EXCEPTION
      'EXPLOIT: the HEALTHY request is still state=%, not failed, after a reconciler run that also scanned an orphaned row. Its reconciliation was rolled back as collateral damage from the orphan -- the absence of per-row fault isolation. Every user''s expired leases are starved by one bad row.', v_state;
  END IF;
  IF (SELECT terminal_code FROM public.ai_session_requests
      WHERE id = v_admit_healthy.request_id) != 'LEASE_EXPIRED' THEN
    RAISE EXCEPTION
      'EXPLOIT: the HEALTHY request reached a terminal state without terminal_code=LEASE_EXPIRED, so the reconciler''s own bookkeeping did not survive the orphan in the same run.';
  END IF;
  -- And its quota reservation was actually RELEASED, not merely marked.
  -- Fault isolation must not have been bought by skipping the release
  -- for everyone -- that would re-open the F1 quota-stranding leak.
  SELECT outcome INTO v_outcome FROM public.ai_assistant_usage
    WHERE request_id = v_admit_healthy.request_id;
  IF v_outcome != 'cancelled' THEN
    RAISE EXCEPTION
      'EXPLOIT: the HEALTHY request''s quota reservation is outcome=%, not cancelled, after reconciliation. A never-dispatched expired lease must release its reservation exactly once (review finding F1, Critical); isolating the orphan must not cost the healthy path its release.', v_outcome;
  END IF;

  -- Contract 7c: the return VALUE counts both rows. The orphan is
  -- resolved, not skipped, so a correct run reports 2. This also pins
  -- the documented decision (resolve rather than skip forever) against
  -- a future change that quietly reverts to skipping.
  IF v_reconciled != 2 THEN
    RAISE EXCEPTION
      'EXPLOIT: reconcile_ai_session_leases returned %, expected 2 (the orphan AND the healthy row). The orphaned row must be RESOLVED to a terminal state, not skipped: skipping leaves it matching the unbounded scan predicate on every run forever -- one WARNING per minute per orphan, and that session''s admit gate blocked permanently by its single-outstanding-request check.', v_reconciled;
  END IF;

  -- Contract 7d: the ORPHAN itself reached a terminal state, so it
  -- LEAVES the scan predicate. This is the documented judgment call
  -- made executable. It is safe precisely because there is no quota
  -- accounting left to touch: reserve_ai_assistant_quota's rolling
  -- window is 24 hours and purge_old_ai_assistant_usage deletes at 30
  -- days, so a row the purger could orphan left the quota window 29
  -- days earlier. There is nothing to release and nothing that could
  -- double-refund.
  SELECT state INTO v_state FROM public.ai_session_requests
    WHERE id = v_admit_orphan.request_id;
  IF v_state != 'failed' THEN
    RAISE EXCEPTION
      'EXPLOIT: the ORPHANED request is still state=%, not failed. It therefore still matches the reconciler''s unbounded scan predicate and will be re-scanned every minute forever, which is a slow leak of a different kind: unbounded WARNING spam and a session whose admit gate never reopens. Task 4 resolves orphans rather than skipping them.', v_state;
  END IF;
  IF (SELECT count(*) FROM public.ai_session_requests
      WHERE state IN ('reserved','started') AND lease_deadline < now()
        AND id IN (v_admit_orphan.request_id, v_admit_healthy.request_id)) != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a reconciled row still matches the scan predicate, so the next run will re-process it. Resolution must be terminal.';
  END IF;

  -- Contract 7e: resolving the orphan created NO quota refund out of
  -- thin air. The usage row is gone and must STAY gone -- the orphan
  -- branch skips the release rather than inserting or resurrecting a
  -- ledger row, so nothing is credited back to the actor.
  IF EXISTS (SELECT 1 FROM public.ai_assistant_usage
             WHERE request_id = v_admit_orphan.request_id) THEN
    RAISE EXCEPTION
      'EXPLOIT: reconciling an ORPHANED request created an ai_assistant_usage row that Plan A''s purger had deleted. The orphan branch must SKIP quota accounting entirely, never re-materialise a ledger row -- that would be a quota refund fabricated from a purged reservation.';
  END IF;

  -- Contract 7f: idempotent. A second run (as cron will do a minute
  -- later) finds nothing left to do and still does not raise.
  SELECT public.reconcile_ai_session_leases() INTO v_reconciled;
  IF v_reconciled != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a second reconciler run reported % rows, expected 0. Both rows reached terminal states, so neither should still be scannable.', v_reconciled;
  END IF;

  RAISE NOTICE 'lease reconcile per-row fault isolation: all held';
END $$;
