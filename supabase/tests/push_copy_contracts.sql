-- supabase/tests/push_copy_contracts.sql
-- Push copy carries no plan titles (Spec 1b Task 4; research 06 §3 F8 (4)).
-- Each Together, reminder and moment generator runs on a plan whose title
-- holds the marker "Zq"; no queued push may contain it. A declined
-- proposal's note reaches the asker only when they show message previews.
-- Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('8e100000-0000-0000-0000-0000000000a1'),
  ('8e100000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('8e100000-0000-0000-0000-0000000000a1', '+233598400001', 'Ama'),
  ('8e100000-0000-0000-0000-0000000000b2', '+233598400002', 'Kofi')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('8e200000-0000-0000-0000-000000000001', '8e100000-0000-0000-0000-0000000000a1',
        '8e100000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;
CREATE TEMP TABLE t_ids (name text PRIMARY KEY, id uuid) ON COMMIT DROP;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.meta_for_event(p_user uuid, p_type text, p_event uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT metadata FROM public.scheduled_notifications
  WHERE user_id = p_user AND metadata->>'type' = p_type AND metadata->>'event_id' = p_event::text $$;
CREATE FUNCTION pg_temp.meta_of_type(p_user uuid, p_type text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT metadata FROM public.scheduled_notifications
  WHERE user_id = p_user AND metadata->>'type' = p_type $$;

-- 1. An alarm on a plan: "Your plan · In 1 hour".
DO $$
DECLARE v_id uuid; v_m jsonb;
BEGIN
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000a1');
  v_id := public.create_couple_event('8e200000-0000-0000-0000-000000000001',
    '{"title":"Zq clinic visit","all_day":false,"starts_at":"2026-11-20T19:00:00Z","tz":"UTC","remind_offsets_min":[60],"participant_ids":["8e100000-0000-0000-0000-0000000000a1","8e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.together_enqueue_event_alarms('2026-11-20T18:05:00Z');
  v_m := pg_temp.meta_for_event('8e100000-0000-0000-0000-0000000000b2', 'together_event', v_id);
  IF v_m IS NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: fixture -- no alarm was queued'; END IF;
  IF v_m->>'title' <> 'Your plan' OR v_m->>'body' <> 'In 1 hour' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: alarm copy %', v_m;
  END IF;
END $$;

-- 2. A proposal, then a decline with a note while the asker's previews are
--    off: neither the title nor the note reaches the lock screen.
DO $$
DECLARE v_id uuid; v_m jsonb;
BEGIN
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000a1');
  v_id := public.propose_couple_event('8e200000-0000-0000-0000-000000000001',
    '{"title":"Zq weekend away","all_day":true,"participant_ids":["8e100000-0000-0000-0000-0000000000a1","8e100000-0000-0000-0000-0000000000b2"]}'::jsonb,
    '[{"start_date":"2026-11-28"}]'::jsonb);
  v_m := pg_temp.meta_for_event('8e100000-0000-0000-0000-0000000000b2', 'together_proposal', v_id);
  IF v_m->>'body' <> 'Open Attune to see it.' OR v_m->>'title' <> 'Ama suggested a plan' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: proposal copy %', v_m;
  END IF;
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000b2');
  PERFORM public.decide_couple_event(v_id, NULL, false, 'Zq not that weekend');
  v_m := pg_temp.meta_for_event('8e100000-0000-0000-0000-0000000000a1', 'together_proposal_reply', v_id);
  IF v_m->>'body' <> 'Open Attune to see it.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a decline note reached a lock screen with previews off: %', v_m;
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 3. With previews on, the note arrives -- without the plan's title.
DO $$
DECLARE v_id uuid; v_m jsonb;
BEGIN
  INSERT INTO public.notification_settings (user_id, chat_message_preview_enabled)
  VALUES ('8e100000-0000-0000-0000-0000000000a1', true)
  ON CONFLICT (user_id) DO UPDATE SET chat_message_preview_enabled = true;
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000a1');
  v_id := public.propose_couple_event('8e200000-0000-0000-0000-000000000001',
    '{"title":"Zq second try","all_day":true,"participant_ids":["8e100000-0000-0000-0000-0000000000a1","8e100000-0000-0000-0000-0000000000b2"]}'::jsonb,
    '[{"start_date":"2026-12-05"}]'::jsonb);
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000b2');
  PERFORM public.decide_couple_event(v_id, NULL, false, 'Sunday instead?');
  v_m := pg_temp.meta_for_event('8e100000-0000-0000-0000-0000000000a1', 'together_proposal_reply', v_id);
  IF v_m->>'body' <> 'Sunday instead?' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with previews on the note should arrive alone: %', v_m;
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 4. A hand-off, and a ritual proposed and accepted.
DO $$
DECLARE v_ev uuid; v_rit uuid; v_m jsonb;
BEGIN
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000a1');
  v_ev := public.create_couple_event('8e200000-0000-0000-0000-000000000001',
    '{"title":"Zq dentist","all_day":true,"start_date":"2026-11-12","participant_ids":["8e100000-0000-0000-0000-0000000000a1","8e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM public.propose_owner_handoff(v_ev);
  v_rit := public.propose_ritual('8e200000-0000-0000-0000-000000000001',
    '{"template":"date_night","title":"Zq ritual","cadence":"weekly","weekday":5,"local_time":"19:00","duration_min":120,"tz":"Africa/Accra"}'::jsonb);
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000b2');
  PERFORM public.decide_ritual(v_rit, true);
  PERFORM set_config('request.jwt.claims', '', true);
  v_m := pg_temp.meta_for_event('8e100000-0000-0000-0000-0000000000b2', 'together_handoff', v_ev);
  IF v_m->>'body' <> 'Open Attune to see it.' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: hand-off copy %', v_m; END IF;
  v_m := pg_temp.meta_of_type('8e100000-0000-0000-0000-0000000000b2', 'together_ritual');
  IF v_m->>'body' <> 'Open Attune to see it.' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: ritual copy %', v_m; END IF;
  v_m := pg_temp.meta_of_type('8e100000-0000-0000-0000-0000000000a1', 'together_ritual_reply');
  IF v_m->>'body' <> 'Open Attune to see it.' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: ritual reply copy %', v_m; END IF;
END $$;

-- 5. A reminder ("Reminder · Today") and a moment ("Ama added a moment").
DO $$
DECLARE v_m jsonb;
BEGIN
  INSERT INTO public.reminders (id, relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES ('8e500000-0000-0000-0000-000000000001', '8e200000-0000-0000-0000-000000000001',
          '8e100000-0000-0000-0000-0000000000a1', 'birthday', 'Zq birthday', '2020-11-21', 'yearly');
  PERFORM public.generate_reminder_notifications('2026-11-21T09:05:00Z');
  SELECT metadata INTO v_m FROM public.scheduled_notifications
   WHERE user_id = '8e100000-0000-0000-0000-0000000000a1' AND metadata->>'reminder_id' = '8e500000-0000-0000-0000-000000000001';
  IF v_m IS NULL OR v_m->>'title' <> 'Reminder' OR v_m->>'body' <> 'Today' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: reminder copy %', v_m;
  END IF;
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('8e200000-0000-0000-0000-000000000001', '8e100000-0000-0000-0000-0000000000a1', 'highlight', 'Zq beach', current_date);
  v_m := pg_temp.meta_of_type('8e100000-0000-0000-0000-0000000000b2', 'moment_logged');
  IF v_m->>'title' <> 'Ama added a moment' OR v_m->>'body' <> 'Open Attune to see it.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: moment copy %', v_m;
  END IF;
END $$;

-- 6. A countdown row is neutralised; a poll row (whose generator writes no
--    title) and a game push are untouched.
DO $$
DECLARE v_m jsonb;
BEGIN
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key) VALUES
    ('8e100000-0000-0000-0000-0000000000a1', 'immediate', '2026-11-19 12:00+00', 'pending',
     '{"type":"planning_entry","title":"Today''s the day","body":"Zq trip"}'::jsonb,
     'planning_countdown:8e-test:8e100000-0000-0000-0000-0000000000a1:2026-11-19'),
    ('8e100000-0000-0000-0000-0000000000a1', 'immediate', '2026-11-19 12:00+00', 'pending',
     '{"type":"planning_entry","title":"New dates to vote on","body":"Kofi suggested dates"}'::jsonb,
     'planning_poll:8e-test:8e100000-0000-0000-0000-0000000000a1:2026111912'),
    ('8e100000-0000-0000-0000-0000000000a1', 'immediate', '2026-11-19 12:00+00', 'pending',
     '{"type":"game_invite","title":"Kofi invited you","body":"Mirror — your turn to play."}'::jsonb, NULL);
  SELECT metadata INTO v_m FROM public.scheduled_notifications WHERE source_key LIKE 'planning_countdown:8e-test:%';
  IF v_m->>'title' <> 'Today''s the day' OR v_m->>'body' <> 'Open Attune to see it.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: countdown copy %', v_m;
  END IF;
  IF (SELECT metadata->>'body' FROM public.scheduled_notifications WHERE source_key LIKE 'planning_poll:8e-test:%') <> 'Kofi suggested dates'
     OR NOT EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE metadata->>'body' = 'Mirror — your turn to play.') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the guard rewrote a push it does not cover';
  END IF;
END $$;

-- 7. The sweep: no queued push anywhere carries a "Zq" title.
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE user_id IN ('8e100000-0000-0000-0000-0000000000a1', '8e100000-0000-0000-0000-0000000000b2')
     AND metadata::text LIKE '%Zq%';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % queued pushes carry a plan title', v_n; END IF;
END $$;

-- 8. An all-day plan's alarm ("Your plan · Today") is exempt from quiet
--    hours, so its 08:00 must be the recipient's own 08:00 -- from the zone
--    their phone reported, not a UTC guess (final review I1).
DO $$
DECLARE v_id uuid; v_n int;
BEGIN
  UPDATE public.users SET timezone = 'America/Toronto'
   WHERE id IN ('8e100000-0000-0000-0000-0000000000a1', '8e100000-0000-0000-0000-0000000000b2');
  PERFORM pg_temp.as_user('8e100000-0000-0000-0000-0000000000a1');
  v_id := public.create_couple_event('8e200000-0000-0000-0000-000000000001',
    '{"title":"Toronto day","all_day":true,"start_date":"2026-11-25","remind_offsets_min":[0],"participant_ids":["8e100000-0000-0000-0000-0000000000a1","8e100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.together_enqueue_event_alarms('2026-11-25T08:05:00Z');  -- 03:05 in Toronto
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE metadata->>'type' = 'together_event' AND metadata->>'event_id' = v_id::text;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an all-day alarm rang at 03:05 local'; END IF;
  PERFORM public.together_enqueue_event_alarms('2026-11-25T13:05:00Z');  -- 08:05 in Toronto
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE metadata->>'type' = 'together_event' AND metadata->>'event_id' = v_id::text;
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % all-day alarms at 08:05 local (want 2)', v_n; END IF;
END $$;

-- 9. The other time-of-day generators -- the daily summary, reminders and
--    countdowns -- also use the recipient's own zone first (follow-up M8),
--    so a summary never lands a day late and a reminder never at 04:00.
DO $$
DECLARE v_n int;
BEGIN
  IF public.notification_local_zone('8e100000-0000-0000-0000-0000000000a1', '8e200000-0000-0000-0000-000000000001') <> 'America/Toronto'
     OR public.notification_local_zone('8e100000-0000-0000-0000-0000000000ff', '8e200000-0000-0000-0000-000000000001') <> 'UTC' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: notification_local_zone does not prefer the reported zone';
  END IF;
  -- The summary for Toronto's 25 November, from block 8's all-day plan.
  PERFORM public.together_enqueue_daily('2026-11-25T08:05:00Z');  -- 03:05 Toronto
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE source_key = 'together_daily:8e100000-0000-0000-0000-0000000000a1:2026-11-25';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the daily summary was built at 03:05 local'; END IF;
  PERFORM public.together_enqueue_daily('2026-11-25T13:05:00Z');  -- 08:05 Toronto
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE source_key = 'together_daily:8e100000-0000-0000-0000-0000000000a1:2026-11-25';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: no daily summary at 08:05 local'; END IF;
  -- A reminder on its day, from 09:00 local.
  INSERT INTO public.reminders (id, relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES ('8e500000-0000-0000-0000-000000000002', '8e200000-0000-0000-0000-000000000001',
          '8e100000-0000-0000-0000-0000000000a1', 'birthday', 'Toronto birthday', '2020-11-26', 'yearly');
  PERFORM public.generate_reminder_notifications('2026-11-26T09:05:00Z');  -- 04:05 Toronto
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE user_id = '8e100000-0000-0000-0000-0000000000a1' AND metadata->>'reminder_id' = '8e500000-0000-0000-0000-000000000002';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a reminder was queued at 04:05 local'; END IF;
  PERFORM public.generate_reminder_notifications('2026-11-26T14:05:00Z');  -- 09:05 Toronto
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE user_id = '8e100000-0000-0000-0000-0000000000a1' AND metadata->>'reminder_id' = '8e500000-0000-0000-0000-000000000002';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: no reminder at 09:05 local'; END IF;
  IF (SELECT prosrc FROM pg_proc WHERE proname = 'planning_enqueue_countdown_pushes') NOT LIKE '%notification_local_zone%'
     OR (SELECT prosrc FROM pg_proc WHERE proname = 'together_enqueue_event_alarms') NOT LIKE '%notification_local_zone%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a time-of-day generator still guesses the zone';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'push_copy_contracts: all held'; END $$;
ROLLBACK;
