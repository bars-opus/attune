-- claim_ai_session_dispatch / reconcile_ai_session_leases. Spec §6.2, §8.2.2.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_dispatch_claim_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000007';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000006a';
  v_session uuid;
  v_admit record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_a, 'claim_a@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_a, '+15550014001', 'A') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, status) VALUES (v_rel, v_user_a, 'active') ON CONFLICT DO NOTHING;

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
    INSERT INTO public.relationships (id, user_a, status) VALUES (v_rel2, v_user_a, 'active') ON CONFLICT DO NOTHING;
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
