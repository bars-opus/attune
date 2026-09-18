-- Atomic quota ledger contracts (Plan A, Task 4).
-- Run: psql -q -d attune_test -f supabase/tests/ai_assistant_quota_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a4000000-0000-0000-0000-000000000001';
  v_user_a uuid := 'a4000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a4000000-0000-0000-0000-00000000000b';
  v_req_1 uuid := 'a4000000-0000-0000-0000-000000000101';
  v_req_2 uuid := 'a4000000-0000-0000-0000-000000000102';
  v_row record;
  v_count int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'quota_a@t.test'), (v_user_b, 'quota_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550004001', 'A'), (v_user_b, '+15550004002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 1: a fresh reservation succeeds.
  SELECT * INTO v_row FROM public.reserve_ai_assistant_quota(v_req_1, v_rel, 'assist');
  IF v_row.outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'EXPLOIT: a fresh reservation did not succeed, got %', v_row.outcome;
  END IF;

  -- Contract 2: retrying the SAME request_id returns the existing
  -- reservation state without inserting a second row.
  SELECT * INTO v_row FROM public.reserve_ai_assistant_quota(v_req_1, v_rel, 'assist');
  IF v_row.outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'EXPLOIT: retrying the same request_id did not return the existing reservation';
  END IF;
  SELECT count(*) INTO v_count FROM public.ai_assistant_usage WHERE request_id = v_req_1;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: retrying the same request_id inserted a duplicate row';
  END IF;

  -- Contract 3: reusing the SAME request_id for a DIFFERENT mode is
  -- rejected as a conflict (a client bug, not a legitimate retry).
  BEGIN
    PERFORM public.reserve_ai_assistant_quota(v_req_1, v_rel, 'understand');
    RAISE EXCEPTION 'EXPLOIT: request_id reuse with a different mode was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 4: 20 distinct successful reservations exhaust the rolling
  -- window; the 21st is rejected with RATE_LIMITED and a positive
  -- retry_after_seconds.
  FOR i IN 2..20 LOOP
    PERFORM public.reserve_ai_assistant_quota(gen_random_uuid(), v_rel, 'assist');
  END LOOP;
  SELECT * INTO v_row FROM public.reserve_ai_assistant_quota(gen_random_uuid(), v_rel, 'understand');
  IF v_row.outcome IS DISTINCT FROM 'rate_limited' OR v_row.retry_after_seconds IS NULL OR v_row.retry_after_seconds <= 0 THEN
    RAISE EXCEPTION 'EXPLOIT: the 21st reservation in 24h was not rejected with a positive retry time, got outcome=% retry=%', v_row.outcome, v_row.retry_after_seconds;
  END IF;

  -- Contract 5: the quota is per-user, not per-relationship -- user_b
  -- in the SAME relationship still has their own full quota.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
  SELECT * INTO v_row FROM public.reserve_ai_assistant_quota(gen_random_uuid(), v_rel, 'assist');
  IF v_row.outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'EXPLOIT: user_b was rate-limited by user_a''s usage in the same relationship';
  END IF;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 6: mark_ai_assistant_usage_outcome updates the row's own
  -- outcome/provider_calls without touching any other row.
  PERFORM public.mark_ai_assistant_usage_outcome(v_req_1, 'succeeded', 1::smallint);
  SELECT outcome, provider_calls INTO v_row FROM public.ai_assistant_usage WHERE request_id = v_req_1;
  IF v_row.outcome IS DISTINCT FROM 'succeeded' OR v_row.provider_calls IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: mark_ai_assistant_usage_outcome did not update the row correctly';
  END IF;

  -- Contract 7: a non-owner cannot mark another user's usage row. The
  -- function is deliberately silent (no exception) when no row matches
  -- its WHERE user_id = auth.uid() clause, so the contract is proven by
  -- the row staying untouched, not by an exception being raised.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
  PERFORM public.mark_ai_assistant_usage_outcome(v_req_1, 'succeeded', 2::smallint);
  SELECT outcome, provider_calls INTO v_row FROM public.ai_assistant_usage WHERE request_id = v_req_1;
  IF v_row.outcome IS DISTINCT FROM 'succeeded' OR v_row.provider_calls IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: user_b marked user_a''s own usage row, got outcome=% provider_calls=%', v_row.outcome, v_row.provider_calls;
  END IF;

  RAISE NOTICE 'ai assistant quota contracts: all held';
END $$;
