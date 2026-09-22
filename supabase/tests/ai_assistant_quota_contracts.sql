-- Atomic quota ledger contracts (Plan A, Task 4; hardened 20260951030000).
-- Run: psql -q -d attune_test -f supabase/tests/ai_assistant_quota_contracts.sql
--
-- Both RPCs now take an explicit p_actor_id instead of relying on
-- auth.uid() (they are called only by the service-role-connected edge
-- functions, where auth.uid() is NULL), so this file no longer needs
-- request.jwt.claims to exercise them. Two exploit classes are added:
-- Contract 2 now expects 'already_reserved', not a second 'reserved'
-- lease, and Contract 6b proves a terminal outcome cannot be rewritten.
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

  -- Contract 1: a fresh reservation succeeds.
  SELECT * INTO v_row FROM public.reserve_ai_assistant_quota(v_user_a, v_req_1, v_rel, 'assist');
  IF v_row.outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'EXPLOIT: a fresh reservation did not succeed, got %', v_row.outcome;
  END IF;

  -- Contract 2: retrying the SAME request_id returns 'already_reserved',
  -- NOT a second 'reserved' lease -- this is the exact defect a client
  -- could exploit to fund unlimited provider calls off one quota slot
  -- (finding F08). No second row, no second lease.
  SELECT * INTO v_row FROM public.reserve_ai_assistant_quota(v_user_a, v_req_1, v_rel, 'assist');
  IF v_row.outcome IS DISTINCT FROM 'already_reserved' THEN
    RAISE EXCEPTION 'EXPLOIT: retrying the same request_id granted outcome=% instead of already_reserved -- a replay could drive a second provider call', v_row.outcome;
  END IF;
  SELECT count(*) INTO v_count FROM public.ai_assistant_usage WHERE request_id = v_req_1;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: retrying the same request_id inserted a duplicate row';
  END IF;

  -- Contract 3: reusing the SAME request_id for a DIFFERENT mode is
  -- rejected as a conflict (a client bug, not a legitimate retry).
  BEGIN
    PERFORM public.reserve_ai_assistant_quota(v_user_a, v_req_1, v_rel, 'understand');
    RAISE EXCEPTION 'EXPLOIT: request_id reuse with a different mode was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 3b: reusing the SAME request_id for a DIFFERENT actor is
  -- rejected -- one user cannot piggyback on another's request_id to
  -- read or consume their reservation.
  BEGIN
    PERFORM public.reserve_ai_assistant_quota(v_user_b, v_req_1, v_rel, 'assist');
    RAISE EXCEPTION 'EXPLOIT: request_id reuse with a different actor was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 4: 20 distinct successful reservations exhaust the rolling
  -- window; the 21st is rejected with RATE_LIMITED and a positive
  -- retry_after_seconds.
  FOR i IN 2..20 LOOP
    PERFORM public.reserve_ai_assistant_quota(v_user_a, gen_random_uuid(), v_rel, 'assist');
  END LOOP;
  SELECT * INTO v_row FROM public.reserve_ai_assistant_quota(v_user_a, gen_random_uuid(), v_rel, 'understand');
  IF v_row.outcome IS DISTINCT FROM 'rate_limited' OR v_row.retry_after_seconds IS NULL OR v_row.retry_after_seconds <= 0 THEN
    RAISE EXCEPTION 'EXPLOIT: the 21st reservation in 24h was not rejected with a positive retry time, got outcome=% retry=%', v_row.outcome, v_row.retry_after_seconds;
  END IF;

  -- Contract 5: the quota is per-user, not per-relationship -- user_b
  -- in the SAME relationship still has their own full quota.
  SELECT * INTO v_row FROM public.reserve_ai_assistant_quota(v_user_b, gen_random_uuid(), v_rel, 'assist');
  IF v_row.outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'EXPLOIT: user_b was rate-limited by user_a''s usage in the same relationship';
  END IF;

  -- Contract 6: mark_ai_assistant_usage_outcome updates the row's own
  -- outcome/provider_calls when the row is still 'reserved'.
  PERFORM public.mark_ai_assistant_usage_outcome(v_user_a, v_req_1, 'succeeded', 1::smallint);
  SELECT outcome, provider_calls INTO v_row FROM public.ai_assistant_usage WHERE request_id = v_req_1;
  IF v_row.outcome IS DISTINCT FROM 'succeeded' OR v_row.provider_calls IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: mark_ai_assistant_usage_outcome did not update the row correctly';
  END IF;

  -- Contract 6b: a TERMINAL outcome cannot be rewritten, even by its own
  -- owner -- this is what stops a caller from walking a succeeded row
  -- back to 'cancelled' to escape the quota count (the other half of
  -- finding F08; 'cancelled' rows are excluded from Contract 4's count).
  PERFORM public.mark_ai_assistant_usage_outcome(v_user_a, v_req_1, 'cancelled', 0::smallint);
  SELECT outcome, provider_calls INTO v_row FROM public.ai_assistant_usage WHERE request_id = v_req_1;
  IF v_row.outcome IS DISTINCT FROM 'succeeded' OR v_row.provider_calls IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: a terminal outcome was rewritten to %, provider_calls=% -- the quota count is now evadable', v_row.outcome, v_row.provider_calls;
  END IF;

  -- Contract 7: a non-owner cannot mark another user's usage row. The
  -- function is deliberately silent (no exception) when no row matches
  -- its WHERE user_id = p_actor_id clause, so the contract is proven by
  -- the row staying untouched, not by an exception being raised.
  PERFORM public.mark_ai_assistant_usage_outcome(v_user_b, v_req_1, 'provider_failed', 2::smallint);
  SELECT outcome, provider_calls INTO v_row FROM public.ai_assistant_usage WHERE request_id = v_req_1;
  IF v_row.outcome IS DISTINCT FROM 'succeeded' OR v_row.provider_calls IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: user_b marked user_a''s own usage row, got outcome=% provider_calls=%', v_row.outcome, v_row.provider_calls;
  END IF;

  -- Contract 8: neither function is reachable by `authenticated` any
  -- more -- both are service_role-only. Verified by grant inspection
  -- rather than by attempting the call under an authenticated role from
  -- this same script (which already runs as the migration owner).
  IF EXISTS (
    SELECT 1 FROM information_schema.role_routine_grants g
    WHERE g.routine_name IN ('reserve_ai_assistant_quota', 'mark_ai_assistant_usage_outcome')
      AND g.grantee = 'authenticated'
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated still has EXECUTE on a quota RPC';
  END IF;

  RAISE NOTICE 'ai assistant quota contracts: all held';
END $$;
