-- Together Phase 2b contracts: prefs, morning summary, push budget.
BEGIN;
INSERT INTO auth.users (id) VALUES ('7e100000-0000-0000-0000-0000000000a1'), ('7e100000-0000-0000-0000-0000000000b2') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7e100000-0000-0000-0000-0000000000a1', '+233290000001', 'Ama'),
  ('7e100000-0000-0000-0000-0000000000b2', '+233290000002', 'Kofi') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7e200000-0000-0000-0000-000000000001', '7e100000-0000-0000-0000-0000000000a1',
        '7e100000-0000-0000-0000-0000000000b2', 'active', now(), now()) ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- Fixtures on Tue 2026-11-10 (UTC zone for both): Ama's dinner with Kofi,
-- Kofi's shared big day, Kofi's busy-only and private events.
DO $$
BEGIN
  PERFORM pg_temp.as_user('7e100000-0000-0000-0000-0000000000a1');
  PERFORM public.create_couple_event('7e200000-0000-0000-0000-000000000001',
    '{"title":"Dinner at Buka","all_day":false,"starts_at":"2026-11-10T19:00:00Z","tz":"UTC","participant_ids":["7e100000-0000-0000-0000-0000000000a1","7e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM pg_temp.as_user('7e100000-0000-0000-0000-0000000000b2');
  PERFORM public.create_couple_event('7e200000-0000-0000-0000-000000000001',
    '{"title":"Interview","kind":"big_day","all_day":false,"starts_at":"2026-11-10T10:00:00Z","tz":"UTC","participant_ids":["7e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM public.create_couple_event('7e200000-0000-0000-0000-000000000001',
    '{"title":"Therapy","all_day":false,"starts_at":"2026-11-10T15:00:00Z","tz":"UTC","visibility":"busy_only","participant_ids":["7e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM public.create_couple_event('7e200000-0000-0000-0000-000000000001',
    '{"title":"Ring shopping","all_day":true,"start_date":"2026-11-10","visibility":"private","participant_ids":["7e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 1. Ama's morning summary: her dinner and Kofi's big day; nothing private or busy.
DO $$
DECLARE v_body text; v_title text; v_n int;
BEGIN
  PERFORM public.together_enqueue_daily('2026-11-10T08:05:00Z');
  SELECT metadata->>'title', metadata->>'body' INTO v_title, v_body FROM public.scheduled_notifications
  WHERE source_key = 'together_daily:7e100000-0000-0000-0000-0000000000a1:2026-11-10';
  IF v_title <> 'Today' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: title %', v_title; END IF;
  IF v_body NOT LIKE '%19:00 Dinner at Buka%' OR v_body NOT LIKE '%Kofi''s big day: Interview at 10:00%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: summary body %', v_body;
  END IF;
  IF v_body LIKE '%Therapy%' OR v_body LIKE '%Ring%' OR v_body LIKE '%Busy%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: summary leaks a busy/private event: %', v_body;
  END IF;
  -- once per local day, even across the window
  PERFORM public.together_enqueue_daily('2026-11-10T08:05:00Z');
  PERFORM public.together_enqueue_daily('2026-11-10T09:50:00Z');
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
  WHERE user_id = '7e100000-0000-0000-0000-0000000000a1' AND metadata->>'type' = 'together_daily'
    AND source_key LIKE 'together_daily:%:2026-11-10';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % summaries in one day', v_n; END IF;
END $$;

-- 2. Outside the window nothing is sent; Kofi's own big day is his plan, not a nudge to himself.
DO $$
DECLARE v_n int; v_body text;
BEGIN
  PERFORM public.together_enqueue_daily('2026-11-11T07:30:00Z');
  PERFORM public.together_enqueue_daily('2026-11-11T11:00:00Z');
  SELECT count(*) INTO v_n FROM public.scheduled_notifications WHERE source_key LIKE 'together_daily:%:2026-11-11';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: summary outside 08:00-10:00'; END IF;
  SELECT metadata->>'body' INTO v_body FROM public.scheduled_notifications
  WHERE source_key = 'together_daily:7e100000-0000-0000-0000-0000000000b2:2026-11-10';
  IF v_body LIKE '%big day%' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: nudged about own big day: %', v_body; END IF;
END $$;

-- 3. Prefs: owner-only; summary off → nothing; care off → no big-day line.
DO $$
DECLARE v_prefs jsonb; v_n int; v_body text;
BEGIN
  PERFORM pg_temp.as_user('7e100000-0000-0000-0000-0000000000a1');
  v_prefs := public.get_together_prefs('7e200000-0000-0000-0000-000000000001');
  IF v_prefs <> '{"daily_summary": true, "care_nudges": true}'::jsonb THEN RAISE EXCEPTION 'CONTRACT VIOLATED: defaults %', v_prefs; END IF;
  PERFORM public.set_together_prefs('7e200000-0000-0000-0000-000000000001', true, false);
  PERFORM pg_temp.as_user('7e100000-0000-0000-0000-0000000000b2');
  PERFORM public.set_together_prefs('7e200000-0000-0000-0000-000000000001', false, true);
  PERFORM set_config('request.jwt.claims', '', true);

  -- Thursday: another big day for Kofi and a dinner for both
  PERFORM pg_temp.as_user('7e100000-0000-0000-0000-0000000000b2');
  PERFORM public.create_couple_event('7e200000-0000-0000-0000-000000000001',
    '{"title":"Exam","kind":"big_day","all_day":true,"start_date":"2026-11-12","participant_ids":["7e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM public.create_couple_event('7e200000-0000-0000-0000-000000000001',
    '{"title":"Cinema","all_day":true,"start_date":"2026-11-12","participant_ids":["7e100000-0000-0000-0000-0000000000a1","7e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.together_enqueue_daily('2026-11-12T08:05:00Z');
  SELECT count(*) INTO v_n FROM public.scheduled_notifications WHERE source_key = 'together_daily:7e100000-0000-0000-0000-0000000000b2:2026-11-12';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: summary sent with daily_summary off'; END IF;
  SELECT metadata->>'body' INTO v_body FROM public.scheduled_notifications WHERE source_key = 'together_daily:7e100000-0000-0000-0000-0000000000a1:2026-11-12';
  IF v_body IS NULL OR v_body NOT LIKE '%Cinema%' OR v_body LIKE '%big day%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: care-off summary %', v_body;
  END IF;
END $$;

-- 4. Sunday is the week ahead; nothing at all → no push.
DO $$
DECLARE v_title text; v_body text;
BEGIN
  PERFORM public.together_enqueue_daily('2026-11-08T08:05:00Z');
  SELECT metadata->>'title', metadata->>'body' INTO v_title, v_body FROM public.scheduled_notifications
  WHERE source_key = 'together_daily:7e100000-0000-0000-0000-0000000000a1:2026-11-08';
  IF v_title <> 'Your week together' OR v_body NOT LIKE '%Tue%Dinner at Buka%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: week ahead % / %', v_title, v_body;
  END IF;
  PERFORM public.together_enqueue_daily('2026-12-01T08:05:00Z');
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE source_key LIKE 'together_daily:%:2026-12-01') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an empty summary was sent';
  END IF;
END $$;

-- 5. Review fixes. (a) The partner saving the creator's big day keeps it a
--    big day. (b) Long distance: a Toronto 21:00 call is 02:00 the next day
--    in London and belongs to that London day's summary.
DO $$
DECLARE v_id uuid; v_kind text; v_tue text; v_wed text;
BEGIN
  PERFORM pg_temp.as_user('7e100000-0000-0000-0000-0000000000b2');
  v_id := public.create_couple_event('7e200000-0000-0000-0000-000000000001',
    '{"title":"Viva","kind":"big_day","all_day":true,"start_date":"2026-11-20","participant_ids":["7e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM pg_temp.as_user('7e100000-0000-0000-0000-0000000000a1');
  PERFORM public.update_couple_event(v_id,
    '{"title":"Viva","kind":"event","note":"Good luck!","all_day":true,"start_date":"2026-11-20","participant_ids":["7e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  SELECT kind INTO v_kind FROM public.couple_events WHERE id = v_id;
  IF v_kind <> 'big_day' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: partner save changed kind to %', v_kind; END IF;
  PERFORM set_config('request.jwt.claims', '', true);

  INSERT INTO auth.users (id) VALUES ('7e100000-0000-0000-0000-0000000000c3'), ('7e100000-0000-0000-0000-0000000000d4') ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    ('7e100000-0000-0000-0000-0000000000c3', '+233290000003', 'Leah'),
    ('7e100000-0000-0000-0000-0000000000d4', '+233290000004', 'Tom') ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
  VALUES ('7e200000-0000-0000-0000-000000000002', '7e100000-0000-0000-0000-0000000000c3',
          '7e100000-0000-0000-0000-0000000000d4', 'active', now(), now()) ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.planning_member_settings (relationship_id, user_id, timezone) VALUES
    ('7e200000-0000-0000-0000-000000000002', '7e100000-0000-0000-0000-0000000000c3', 'Europe/London'),
    ('7e200000-0000-0000-0000-000000000002', '7e100000-0000-0000-0000-0000000000d4', 'America/Toronto');
  PERFORM pg_temp.as_user('7e100000-0000-0000-0000-0000000000d4');
  PERFORM public.create_couple_event('7e200000-0000-0000-0000-000000000002',
    '{"title":"Call","all_day":false,"starts_at":"2026-11-11T02:00:00Z","tz":"America/Toronto","participant_ids":["7e100000-0000-0000-0000-0000000000c3","7e100000-0000-0000-0000-0000000000d4"]}'::jsonb);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.together_enqueue_daily('2026-11-10T08:05:00Z');
  PERFORM public.together_enqueue_daily('2026-11-11T08:05:00Z');
  SELECT metadata->>'body' INTO v_tue FROM public.scheduled_notifications WHERE source_key = 'together_daily:7e100000-0000-0000-0000-0000000000c3:2026-11-10';
  SELECT metadata->>'body' INTO v_wed FROM public.scheduled_notifications WHERE source_key = 'together_daily:7e100000-0000-0000-0000-0000000000c3:2026-11-11';
  IF v_tue LIKE '%Call%' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: London Tuesday shows a Wednesday 02:00 call: %', v_tue; END IF;
  IF v_wed IS NULL OR v_wed NOT LIKE '%02:00 Call%' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: London Wednesday summary %', v_wed; END IF;
END $$;

ROLLBACK;
