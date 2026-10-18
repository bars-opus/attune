-- supabase/tests/quiet_effects_contracts.sql
-- Spec 7 (B9 (a), (d); A9; plan review I1, I5, M13): while a person is quiet
-- the app stops celebrating at them — the Planning goal notice (for both, so
-- nothing says who), the big-day and suggestion lines of their own daily
-- summary, their On this day and memory prompts; "Hide a period" keeps a
-- span of dates out of their own resurfacing, never out of their list.
BEGIN;
DO $$
DECLARE
  v_rel uuid := '9fb00000-0000-0000-0000-000000000001';
  v_a uuid := '9fb00000-0000-0000-0000-0000000000a1';
  v_b uuid := '9fb00000-0000-0000-0000-0000000000b2';
  v_goals uuid; v_goal uuid := '9fb00000-0000-0000-0000-00000000e001';
  v_prog uuid := '9fb00000-0000-0000-0000-00000000b001';
  v_moment uuid; v_n int; v_lines text[]; v_msg text; v_hp uuid; v_quiet_view jsonb; v_plain_view jsonb;
BEGIN
  INSERT INTO auth.users (id) VALUES (v_a), (v_b) ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a, '+233599700001', 'Ama'), (v_b, '+233599700002', 'Kofi') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
  VALUES (v_rel, v_a, v_b, 'active', now() - interval '3 years', now() - interval '3 years') ON CONFLICT DO NOTHING;

  -- 1. The goal notice: none while either is quiet, and none later (I1).
  INSERT INTO public.quiet_states (user_id, kind, until) VALUES (v_a, 'loss', now() + interval '10 days');
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_b), true);
  PERFORM public.get_planning_home(v_rel);
  SELECT id INTO v_goals FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'goals';
  PERFORM public.create_planning_entry(v_goal, v_goals, 'House deposit', false, 'GHS');
  PERFORM public.add_planning_block(v_prog, v_goal, 'progress', '{"mode":"numeric","unit":"money"}', NULL, NULL, NULL);
  PERFORM public.update_planning_block_target(v_prog, 1, 100000, 'GHS');
  PERFORM public.save_planning_rich_item(gen_random_uuid(), v_prog, NULL, '{"amount_minor":100000}', NULL);
  IF EXISTS (SELECT 1 FROM public.messages WHERE relationship_id = v_rel AND content LIKE '%Goal reached%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a goal notice while a member is quiet';
  END IF;
  DELETE FROM public.quiet_states WHERE user_id = v_a;
  PERFORM public.save_planning_rich_item(gen_random_uuid(), v_prog, NULL, '{"amount_minor":5000}', NULL);
  IF EXISTS (SELECT 1 FROM public.messages WHERE relationship_id = v_rel AND content LIKE '%Goal reached%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the swallowed notice fired after the quiet ended (I1)';
  END IF;

  -- 2. The daily summary keeps only the plain line for a quiet person.
  INSERT INTO public.couple_events (id, relationship_id, created_by, kind, title, all_day, start_date, end_date,
                                    visibility, status, participant_ids)
  VALUES (gen_random_uuid(), v_rel, v_b, 'big_day', 'Interview', true, DATE '2026-10-18', DATE '2026-10-18',
          'shared', 'confirmed', ARRAY[v_b]),
         (gen_random_uuid(), v_rel, v_a, 'event', 'Dinner', true, DATE '2026-10-18', DATE '2026-10-18',
          'shared', 'confirmed', ARRAY[v_a, v_b]);
  v_lines := public.together_digest_lines(v_rel, v_a, DATE '2026-10-18', DATE '2026-10-18', 'UTC', true, false);
  IF NOT EXISTS (SELECT 1 FROM unnest(v_lines) l WHERE l LIKE '%big day%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: setup: no big-day line when not quiet: %', v_lines;
  END IF;
  INSERT INTO public.quiet_states (user_id, kind, until) VALUES (v_a, 'hard_time', now() + interval '10 days');
  v_lines := public.together_digest_lines(v_rel, v_a, DATE '2026-10-18', DATE '2026-10-18', 'UTC', true, false);
  IF EXISTS (SELECT 1 FROM unnest(v_lines) l WHERE l LIKE '%big day%' OR l LIKE '%suggestion%')
     OR NOT EXISTS (SELECT 1 FROM unnest(v_lines) l WHERE l LIKE '%plan%today%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a quiet person''s summary: %', v_lines;
  END IF;

  -- 3. On this day: nothing for the quiet person; their partner's is untouched.
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at, visibility)
  VALUES (v_rel, v_a, 'highlight', 'Engaged', DATE '2025-10-18', 'shared') RETURNING id INTO v_moment;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_a), true);
  SELECT count(*) INTO v_n FROM public.list_together_on_this_day(v_rel, DATE '2026-10-18');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: On this day for a quiet person'; END IF;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_b), true);
  SELECT count(*) INTO v_n FROM public.list_together_on_this_day(v_rel, DATE '2026-10-18');
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the quiet person''s partner lost their On this day (%)', v_n; END IF;
  DELETE FROM public.quiet_states WHERE user_id = v_a;

  -- 4. Hide a period: out of my On this day, still in my list (I5).
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_a), true);
  v_hp := public.add_hidden_period(DATE '2025-10-01', DATE '2025-10-31');
  SELECT count(*) INTO v_n FROM public.list_together_on_this_day(v_rel, DATE '2026-10-18');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a hidden period still resurfaces'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_moments(v_rel) m WHERE m.id = v_moment;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a hidden period hid the moment from my own list (I5)'; END IF;
  IF (SELECT count(*) FROM public.list_my_hidden_periods()) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: list_my_hidden_periods';
  END IF;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_b), true);
  SELECT count(*) INTO v_n FROM public.list_together_on_this_day(v_rel, DATE '2026-10-18');
  IF v_n <> 1 OR (SELECT count(*) FROM public.list_my_hidden_periods()) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: my hidden period reached my partner';
  END IF;
  BEGIN
    PERFORM public.remove_hidden_period(v_hp);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_a), true);
  IF (SELECT count(*) FROM public.list_my_hidden_periods()) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: my partner removed my hidden period';
  END IF;
  PERFORM public.remove_hidden_period(v_hp);
  SELECT count(*) INTO v_n FROM public.list_together_on_this_day(v_rel, DATE '2026-10-18');
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: removing the period did not bring it back'; END IF;
  BEGIN
    PERFORM public.add_hidden_period(DATE '2025-10-31', DATE '2025-10-01');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a backwards period was accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'hidden_period:invalid' THEN RAISE; END IF;
  END;

  -- 4b. Memory prompts (final review M-4): none for a quiet person, none
  -- for a date I hid, untouched for my partner.
  INSERT INTO public.couple_events (id, relationship_id, created_by, kind, title, all_day, start_date, end_date,
                                    visibility, status, participant_ids)
  VALUES ('9fb00000-0000-0000-0000-0000000000e9', v_rel, v_a, 'event', 'Picnic', true,
          (now() AT TIME ZONE 'UTC')::date - 1, (now() AT TIME ZONE 'UTC')::date - 1,
          'shared', 'confirmed', ARRAY[v_a, v_b]);
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_a), true);
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts(v_rel, 'UTC') WHERE title = 'Picnic';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: setup: no memory prompt (%).', v_n; END IF;
  v_hp := public.add_hidden_period((now() AT TIME ZONE 'UTC')::date - 2, (now() AT TIME ZONE 'UTC')::date);
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts(v_rel, 'UTC') WHERE title = 'Picnic';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a hidden date still prompts a memory'; END IF;
  PERFORM public.remove_hidden_period(v_hp);
  INSERT INTO public.quiet_states (user_id, kind, until) VALUES (v_a, 'loss', now() + interval '3 days');
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts(v_rel, 'UTC') WHERE title = 'Picnic';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a quiet person is prompted for a memory'; END IF;

  -- 4c. Final review M-4 / plan review C1: my partner's own surfaces are the
  -- same whether or not I am quiet.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_b), true);
  SELECT jsonb_build_object(
    'otd', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.item_id) FROM public.list_together_on_this_day(v_rel, DATE '2026-10-18') x),
    'prompts', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.event_id) FROM public.list_together_memory_prompts(v_rel, 'UTC') x),
    'digest', to_jsonb(public.together_digest_lines(v_rel, v_b, DATE '2026-10-18', DATE '2026-10-18', 'UTC', true, false)))
  INTO v_quiet_view;
  DELETE FROM public.quiet_states WHERE user_id = v_a;
  SELECT jsonb_build_object(
    'otd', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.item_id) FROM public.list_together_on_this_day(v_rel, DATE '2026-10-18') x),
    'prompts', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.event_id) FROM public.list_together_memory_prompts(v_rel, 'UTC') x),
    'digest', to_jsonb(public.together_digest_lines(v_rel, v_b, DATE '2026-10-18', DATE '2026-10-18', 'UTC', true, false)))
  INTO v_plain_view;
  IF v_quiet_view IS DISTINCT FROM v_plain_view THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: my partner can tell I am quiet: % vs %', v_quiet_view, v_plain_view;
  END IF;
  IF v_plain_view->'prompts' IS NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: setup: partner has no prompt'; END IF;

  -- 5. Grants.
  IF has_table_privilege('authenticated', 'public.hidden_periods', 'SELECT')
     OR has_function_privilege('anon', 'public.add_hidden_period(date,date)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.add_hidden_period(date,date)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.remove_hidden_period(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.list_my_hidden_periods()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: hidden period grants';
  END IF;
END $$;
DO $$ BEGIN RAISE NOTICE 'quiet_effects_contracts: all held'; END $$;
ROLLBACK;
