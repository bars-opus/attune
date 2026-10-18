-- supabase/tests/pulse_privacy_contracts.sql
-- Pulse privacy (Spec 1a Task 7): Emotional safety is self-only, check-in
-- rows stay private, the forced-recompute limit is server-side and atomic.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('5e100000-0000-0000-0000-0000000000a1'),
  ('5e100000-0000-0000-0000-0000000000b2'),
  ('5e100000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('5e100000-0000-0000-0000-0000000000a1', '+233599500001', 'Pulse A'),
  ('5e100000-0000-0000-0000-0000000000b2', '+233599500002', 'Pulse B'),
  ('5e100000-0000-0000-0000-0000000000c3', '+233599500003', 'Pulse C')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000a1',
   '5e100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now(), '2026-10-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- 1. The shared row no longer needs emotional_safety.
DO $$
BEGIN
  IF (SELECT is_nullable FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'pulse_scores' AND column_name = 'emotional_safety') <> 'YES' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pulse_scores.emotional_safety is still NOT NULL';
  END IF;
  INSERT INTO public.pulse_scores (relationship_id, week_ending, overall_score, communication, connection,
                                   conflict_health, alignment, emotional_safety, data_confidence)
  VALUES ('5e200000-0000-0000-0000-000000000001', '2026-10-18', 60, 60, 60, 60, 60, NULL, 'low');
END $$;

-- 2. Private scores: each member reads only their own row; clients cannot write.
DO $$
DECLARE v int;
BEGIN
  INSERT INTO public.pulse_private_scores (relationship_id, user_id, week_ending, emotional_safety) VALUES
    ('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000a1', '2026-10-18', 71),
    ('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000b2', '2026-10-18', 43);
  IF has_table_privilege('authenticated', 'public.pulse_private_scores', 'INSERT')
     OR has_table_privilege('authenticated', 'public.pulse_private_scores', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.pulse_private_scores', 'DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients can write pulse_private_scores';
  END IF;
  PERFORM pg_temp.as_user('5e100000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v FROM public.pulse_private_scores;
  IF v <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: A sees % private rows (expected only their own)', v; END IF;
  IF (SELECT emotional_safety FROM public.pulse_private_scores) <> 71 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: A sees a row that is not theirs';
  END IF;
  PERFORM pg_temp.as_user('5e100000-0000-0000-0000-0000000000b2');
  IF (SELECT count(*) FROM public.pulse_private_scores WHERE user_id = '5e100000-0000-0000-0000-0000000000a1') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: B can read A''s private Emotional safety';
  END IF;
  BEGIN
    INSERT INTO public.pulse_private_scores (relationship_id, user_id, week_ending, emotional_safety)
    VALUES ('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000b2', '2026-10-25', 99);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member inserted a private score';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM pg_temp.as_user('5e100000-0000-0000-0000-0000000000c3');
  SELECT count(*) INTO v FROM public.pulse_private_scores;
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider sees % private rows', v; END IF;
  RESET ROLE;
END $$;

-- 3. Check-in rows stay private to their author (the RLS this whole feature
--    stands on had no contract until now).
DO $$
DECLARE v int;
BEGIN
  INSERT INTO public.weekly_checkins (user_id, relationship_id, week_ending, communication_rating, connection_rating,
                                      conflict_health_rating, conflict_health_na, alignment_rating, safety_rating)
  VALUES ('5e100000-0000-0000-0000-0000000000a1', '5e200000-0000-0000-0000-000000000001', '2026-10-18', 8, 7, NULL, true, 9, 6)
  ON CONFLICT (user_id, week_ending) DO NOTHING;
  PERFORM pg_temp.as_user('5e100000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v FROM public.weekly_checkins WHERE relationship_id = '5e200000-0000-0000-0000-000000000001';
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the partner can read % check-in rows', v; END IF;
  RESET ROLE;
END $$;

-- 4. The forced-recompute limit: service-role only, per member, granted once
--    per window, atomic, with an honest retry time. A's refusal must not
--    depend on B's refresh (M2: a 429 would otherwise say "your partner
--    refreshed recently").
DO $$
DECLARE v_granted boolean; v_retry int;
BEGIN
  IF has_function_privilege('authenticated', 'public.claim_pulse_recompute(uuid, uuid, interval)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.claim_pulse_recompute(uuid, uuid, interval)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client role can execute claim_pulse_recompute';
  END IF;
  IF NOT has_function_privilege('service_role', 'public.claim_pulse_recompute(uuid, uuid, interval)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: service_role cannot execute claim_pulse_recompute';
  END IF;
  IF has_table_privilege('authenticated', 'public.pulse_recompute_limits', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients can read pulse_recompute_limits';
  END IF;

  SELECT granted, retry_after_seconds INTO v_granted, v_retry
    FROM public.claim_pulse_recompute('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000a1');
  IF NOT v_granted OR v_retry <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first claim was not granted (% / %)', v_granted, v_retry;
  END IF;
  SELECT granted, retry_after_seconds INTO v_granted, v_retry
    FROM public.claim_pulse_recompute('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000a1');
  IF v_granted OR v_retry NOT BETWEEN 1 AND 86400 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second claim inside 24h was granted or mis-timed (% / %)', v_granted, v_retry;
  END IF;
  -- B's own first refresh is untouched by A's.
  SELECT granted INTO v_granted
    FROM public.claim_pulse_recompute('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000b2');
  IF NOT v_granted THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: B was refused because A refreshed (the limit leaks across partners)';
  END IF;
  UPDATE public.pulse_recompute_limits SET last_forced_at = now() - interval '25 hours'
   WHERE relationship_id = '5e200000-0000-0000-0000-000000000001'
     AND user_id = '5e100000-0000-0000-0000-0000000000a1';
  SELECT granted INTO v_granted
    FROM public.claim_pulse_recompute('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000a1');
  IF NOT v_granted THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a claim after the window was refused';
  END IF;
  -- A short window proves the interval is honoured, not a hard-coded day.
  SELECT granted INTO v_granted
    FROM public.claim_pulse_recompute('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-0000000000a1', interval '0 seconds');
  IF NOT v_granted THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a zero-length window still refused';
  END IF;
  RAISE NOTICE 'pulse_privacy_contracts: all held';
END $$;

ROLLBACK;
