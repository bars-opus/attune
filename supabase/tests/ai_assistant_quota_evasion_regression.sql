-- Regression test for the quota-evasion gap the final whole-branch review
-- of Plan A found: a reservation whose provider call actually started
-- could still be excluded from the rolling-window COUNT by marking it
-- 'rejected' or 'cancelled' after the fact. Fixed in
-- 20260952030000_ai_assistant_quota_evasion_fix.sql.
--
-- Unlike ai_assistant_quota_release_contracts.sql's Contract 1 (which
-- hand-derives the marker-aware predicate inline to check
-- release_ai_assistant_quota_reservation's own invariant), this test
-- proves the fix through the REAL RPCs end-to-end: reserve -> claim the
-- provider-start marker -> attempt to mark the outcome 'rejected' ->
-- confirm the row still counts, and drive reserve_ai_assistant_quota
-- itself to the 20-per-24h cap using only started reservations that
-- attempted this exact exploit, then confirm the 21st is rate_limited.
-- That last step is the RPC's own admission decision, not an auxiliary
-- SELECT that could itself be wrong.
--
-- Note on observed behavior: mark_ai_assistant_usage_outcome's new guard
-- (20260952030000) makes a 'rejected'/'cancelled' write onto a started
-- row a silent no-op, per this function's established "silent when
-- inapplicable" convention -- the row simply stays at outcome='reserved'
-- rather than transitioning. That is fine and expected: 'reserved' is
-- not in the COUNT predicate's exclusion set either, so the row counts
-- either way. What this test proves is that the exploit path (claim the
-- marker, then try to reject/cancel to escape the count) never succeeds
-- in freeing a quota slot, regardless of which outcome value the row
-- ends up parked at.
--
-- Run: psql -q -d attune_test -f supabase/tests/ai_assistant_quota_evasion_regression.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a5000000-0000-0000-0000-000000000004';
  v_user_a uuid := 'a5000000-0000-0000-0000-00000000030a';
  v_user_b uuid := 'a5000000-0000-0000-0000-00000000030b';
  v_req_started_rejected uuid := 'a5000000-0000-0000-0000-000000000401';
  v_req_started_cancelled uuid := 'a5000000-0000-0000-0000-000000000402';
  v_row record;
  v_reserve_row record;
  v_count int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'evasion_a@t.test'), (v_user_b, 'evasion_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550950701', 'A'), (v_user_b, '+15550950702', 'B')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -- Reproduce the exploit path: reserve, claim the provider-start marker
  -- (a real provider call is now "in flight"), then attempt to mark the
  -- outcome 'rejected' -- exactly what ai-assist's handleNearby does when
  -- Gemini's real response comes back off-allowlist after a genuine
  -- dispatch.
  PERFORM public.reserve_ai_assistant_quota(v_user_a, v_req_started_rejected, v_rel, 'assist');
  IF public.claim_ai_assistant_provider_start(v_user_a, v_req_started_rejected) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: setup could not claim the provider-start marker';
  END IF;
  PERFORM public.mark_ai_assistant_usage_outcome(v_user_a, v_req_started_rejected, 'rejected', 1::smallint);

  SELECT * INTO v_row FROM public.ai_assistant_usage WHERE request_id = v_req_started_rejected;
  IF v_row.provider_started_at IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: setup row lost its provider-start marker';
  END IF;
  -- The guard makes the 'rejected' write a silent no-op (established
  -- convention for this function) -- the row must NOT have landed on
  -- 'rejected' or 'cancelled', the two outcomes the COUNT predicate
  -- excludes. Whatever it landed on (still 'reserved'), that is fine.
  IF v_row.outcome IN ('rejected', 'cancelled') THEN
    RAISE EXCEPTION 'EXPLOIT: a started reservation was moved to excluded outcome % -- quota evasion succeeded', v_row.outcome;
  END IF;

  -- Contract 1: querying with the EXACT production predicate (copied
  -- verbatim from the fixed reserve_ai_assistant_quota) must show this
  -- started row still counting, no matter what outcome it is parked at.
  SELECT count(*) INTO v_count FROM public.ai_assistant_usage u
  WHERE u.user_id = v_user_a AND u.created_at >= now() - interval '24 hours'
    AND (u.provider_started_at IS NOT NULL OR u.outcome NOT IN ('rejected', 'cancelled'));
  IF v_count != 1 THEN
    RAISE EXCEPTION 'EXPLOIT: a started reservation that attempted rejection was excluded from the production COUNT predicate, count=%', v_count;
  END IF;

  -- Contract 2: same proof for 'cancelled'.
  PERFORM public.reserve_ai_assistant_quota(v_user_a, v_req_started_cancelled, v_rel, 'assist');
  PERFORM public.claim_ai_assistant_provider_start(v_user_a, v_req_started_cancelled);
  PERFORM public.mark_ai_assistant_usage_outcome(v_user_a, v_req_started_cancelled, 'cancelled', 1::smallint);
  SELECT * INTO v_row FROM public.ai_assistant_usage WHERE request_id = v_req_started_cancelled;
  IF v_row.outcome IN ('rejected', 'cancelled') THEN
    RAISE EXCEPTION 'EXPLOIT: a started reservation was moved to excluded outcome % via cancelled attempt -- quota evasion succeeded', v_row.outcome;
  END IF;

  -- Contract 3 (the harder-to-fool proof): drive reserve_ai_assistant_quota
  -- itself to the 20-per-24h cap using ONLY started reservations that
  -- attempted this exact exploit, and confirm the RPC's own admission
  -- decision -- not a re-derived query -- treats them as consumed. We
  -- already have 2 such rows above; add 18 more identical
  -- started-then-attempted-rejection rows to reach 20, then confirm the
  -- 21st reservation is rate_limited.
  FOR i IN 1..18 LOOP
    DECLARE
      v_req uuid := gen_random_uuid();
    BEGIN
      PERFORM public.reserve_ai_assistant_quota(v_user_a, v_req, v_rel, 'assist');
      PERFORM public.claim_ai_assistant_provider_start(v_user_a, v_req);
      PERFORM public.mark_ai_assistant_usage_outcome(v_user_a, v_req, 'rejected', 1::smallint);
    END;
  END LOOP;

  SELECT * INTO v_reserve_row FROM public.reserve_ai_assistant_quota(v_user_a, gen_random_uuid(), v_rel, 'assist');
  IF v_reserve_row.outcome IS DISTINCT FROM 'rate_limited' THEN
    RAISE EXCEPTION 'EXPLOIT: 20 started reservations that attempted rejection/cancellation did not exhaust the quota via reserve_ai_assistant_quota itself -- outcome=% (quota evasion confirmed live)', v_reserve_row.outcome;
  END IF;

  RAISE NOTICE 'quota evasion regression: all held';
END $$;
