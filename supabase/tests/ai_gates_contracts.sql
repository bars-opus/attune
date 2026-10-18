-- supabase/tests/ai_gates_contracts.sql
-- Spec 8 (F15 (1), row 8; plan review I13, I14, I15): the Verdict refuses a
-- suppressed couple with exactly the "not enough data" answer; the
-- hostility signals start off; provider calls are ledgered server-side
-- only and aggregated per couple per day; the ledger forgets after 90 days.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('9fe00000-0000-0000-0000-0000000000a1'), ('9fe00000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9fe00000-0000-0000-0000-0000000000a1', '+233599630001', 'Ama'),
  ('9fe00000-0000-0000-0000-0000000000b2', '+233599630002', 'Kofi')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('9fe10000-0000-0000-0000-000000000001', '9fe00000-0000-0000-0000-0000000000a1', '9fe00000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE - 200, now() - interval '200 days', now());

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.request(p_user uuid, p_rel uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.as_user(p_user);
  v := public.request_verdict_generation(p_rel);
  RESET ROLE;
  RETURN v;
END $$;

DO $$
DECLARE
  v_rel uuid := '9fe10000-0000-0000-0000-000000000001';
  v_a uuid := '9fe00000-0000-0000-0000-0000000000a1';
  v_b uuid := '9fe00000-0000-0000-0000-0000000000b2';
  v_insufficient jsonb := jsonb_build_object(
    'status', 'ineligible', 'reason', 'insufficient_evidence',
    'message', 'Not enough shared data yet. Keep using Attune at your own pace.');
  v jsonb; i int; r record;
BEGIN
  -- 1. The hostility signals start off (I14).
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'chat_hostility_signals_enabled') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: chat_hostility_signals_enabled not seeded off';
  END IF;

  -- 2. Give the couple enough for a Verdict: 3 Pulse rows with a strength
  --    and a drop, 5 full sessions.
  FOR i IN 1..3 LOOP
    INSERT INTO public.pulse_scores (relationship_id, overall_score, communication, connection,
                                     conflict_health, alignment, week_ending, computed_at, delta_vs_previous)
    VALUES (v_rel, 75, 70, 70, 60, 60, CURRENT_DATE - (i * 7), now() - (i || ' weeks')::interval,
            jsonb_build_object('connection', -6));
  END LOOP;
  FOR i IN 1..5 LOOP
    INSERT INTO public.analysis_sessions (relationship_id, started_at, ended_at, message_count)
    VALUES (v_rel, now() - (i || ' days')::interval - interval '1 hour', now() - (i || ' days')::interval, 10);
  END LOOP;
  v := pg_temp.request(v_a, v_rel);
  IF v->>'status' <> 'queued' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fixture not eligible: %', v;
  END IF;
  DELETE FROM public.verdict_generation_jobs WHERE relationship_id = v_rel;

  -- 3. A safety event of any tier: the same answer as too little data,
  --    to either member, and nothing is queued (I13).
  INSERT INTO public.safety_events (relationship_id, at_risk_user_id, source_event_key, trigger_tier, trigger_family, config_version)
  VALUES (v_rel, v_a, 'gates-1', 3, 'test', 'test');
  IF pg_temp.request(v_a, v_rel) IS DISTINCT FROM v_insufficient
     OR pg_temp.request(v_b, v_rel) IS DISTINCT FROM v_insufficient THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a suppressed couple got %', pg_temp.request(v_a, v_rel);
  END IF;
  IF EXISTS (SELECT 1 FROM public.verdict_generation_jobs WHERE relationship_id = v_rel) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a job was queued for a suppressed couple';
  END IF;
  -- Final review m-11: a job queued before the event keeps reading as
  -- processing until the worker cancels it, then reads as too little data.
  DELETE FROM public.safety_events WHERE relationship_id = v_rel;
  v := pg_temp.request(v_a, v_rel);
  INSERT INTO public.safety_events (relationship_id, at_risk_user_id, source_event_key, trigger_tier, trigger_family, config_version)
  VALUES (v_rel, v_a, 'gates-2', 3, 'test', 'test');
  IF pg_temp.request(v_a, v_rel)->>'status' <> 'processing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a queued job flipped to %', pg_temp.request(v_a, v_rel);
  END IF;
  UPDATE public.verdict_generation_jobs SET status = 'cancelled' WHERE relationship_id = v_rel;
  IF pg_temp.request(v_a, v_rel) IS DISTINCT FROM v_insufficient THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after cancelling, %', pg_temp.request(v_a, v_rel);
  END IF;
  DELETE FROM public.verdict_generation_jobs WHERE relationship_id = v_rel;
  DELETE FROM public.safety_events WHERE relationship_id = v_rel;

  -- 4. Either member's positive private check does the same.
  INSERT INTO public.safety_self_checks (user_id, relationship_id, answered_at, until, positive_until)
  VALUES (v_b, v_rel, now(), now() + interval '180 days', now() + interval '180 days');
  IF pg_temp.request(v_a, v_rel) IS DISTINCT FROM v_insufficient THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a positive check did not suppress the Verdict';
  END IF;
  -- ...and an expired one no longer does.
  UPDATE public.safety_self_checks SET positive_until = now() - interval '1 day' WHERE user_id = v_b;
  IF pg_temp.request(v_a, v_rel)->>'status' <> 'queued' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an expired check still suppresses';
  END IF;
  DELETE FROM public.verdict_generation_jobs WHERE relationship_id = v_rel;

  -- 5. The provider-call ledger: server-side only (I15).
  IF has_table_privilege('authenticated', 'public.ai_provider_calls', 'SELECT')
     OR has_table_privilege('anon', 'public.ai_provider_calls', 'SELECT')
     OR has_table_privilege('authenticated', 'public.ai_provider_calls', 'INSERT')
     OR NOT has_table_privilege('service_role', 'public.ai_provider_calls', 'INSERT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ai_provider_calls privileges';
  END IF;
  IF has_table_privilege('authenticated', 'public.ai_cost_per_relationship', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.ai_cost_per_relationship', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ai_cost_per_relationship privileges';
  END IF;
  IF has_function_privilege('authenticated', 'public.purge_old_ai_provider_calls()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients can purge the ledger';
  END IF;

  -- 6. The cost view: calls and tokens per couple per day.
  INSERT INTO public.ai_provider_calls (fn, prompt_id, relationship_id, user_id, prompt_tokens, output_tokens, created_at) VALUES
    ('analyse-message', 'layer1', v_rel, v_a, 100, 20, now()),
    ('analyse-session', 'layer2', v_rel, NULL, 300, 80, now()),
    ('generate-verdict', 'verdict', v_rel, NULL, 50, 50, now() - interval '100 days');
  SELECT * INTO r FROM public.ai_cost_per_relationship
  WHERE relationship_id = v_rel AND day = (now() AT TIME ZONE 'UTC')::date;
  IF r.calls <> 2 OR r.prompt_tokens <> 400 OR r.output_tokens <> 100 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: cost view row %', row_to_json(r);
  END IF;

  -- 7. Forgotten after 90 days.
  PERFORM public.purge_old_ai_provider_calls();
  IF (SELECT count(*) FROM public.ai_provider_calls WHERE relationship_id = v_rel) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge kept or lost the wrong rows';
  END IF;

  -- 8. Leaves with the relationship.
  DELETE FROM public.verdict_generation_jobs WHERE relationship_id = v_rel;
  DELETE FROM public.pulse_scores WHERE relationship_id = v_rel;
  DELETE FROM public.analysis_sessions WHERE relationship_id = v_rel;
  DELETE FROM public.safety_self_checks WHERE relationship_id = v_rel;
  DELETE FROM public.relationships WHERE id = v_rel;
  IF EXISTS (SELECT 1 FROM public.ai_provider_calls WHERE relationship_id = v_rel) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ledger rows outlive the relationship';
  END IF;
END $$;

ROLLBACK;
