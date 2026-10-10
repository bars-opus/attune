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
