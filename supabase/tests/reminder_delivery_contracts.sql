-- Reminder delivery contracts (2026-10-15): each partner's local morning,
-- same-day and edited reminders, ended couples, family birthdays, and
-- moments kept to their own active relationship.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users (id) VALUES ('7e300000-0000-0000-0000-0000000000a1'), ('7e300000-0000-0000-0000-0000000000b2'),
  ('7e300000-0000-0000-0000-0000000000c3') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7e300000-0000-0000-0000-0000000000a1', '+233290000101', 'Ama'),
  ('7e300000-0000-0000-0000-0000000000b2', '+233290000102', 'Kofi'),
  ('7e300000-0000-0000-0000-0000000000c3', '+233290000103', 'Esi') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('7e400000-0000-0000-0000-000000000001', '7e300000-0000-0000-0000-0000000000a1',
   '7e300000-0000-0000-0000-0000000000b2', 'active', now(), now()),
  -- Kofi's ended relationship with Esi.
  ('7e400000-0000-0000-0000-000000000002', '7e300000-0000-0000-0000-0000000000c3',
   '7e300000-0000-0000-0000-0000000000b2', 'ended', now(), now()),
  -- Esi's paused relationship with a third person: paused isn't over.
  ('7e400000-0000-0000-0000-000000000003', '7e300000-0000-0000-0000-0000000000c3',
   NULL, 'paused', now(), now())
ON CONFLICT (id) DO NOTHING;
-- Ama lives in Los Angeles (UTC-8 in November); Kofi has no zone (UTC).
INSERT INTO public.planning_member_settings (relationship_id, user_id, timezone, updated_at)
VALUES ('7e400000-0000-0000-0000-000000000001', '7e300000-0000-0000-0000-0000000000a1', 'America/Los_Angeles', now());
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.sent(p_key text) RETURNS int LANGUAGE sql AS $$
  SELECT count(*)::int FROM public.scheduled_notifications WHERE source_key LIKE p_key $$;

INSERT INTO public.reminders (id, relationship_id, created_by, reminder_type, title, remind_at, recurrence) VALUES
  ('7e500000-0000-0000-0000-000000000001', '7e400000-0000-0000-0000-000000000001',
   '7e300000-0000-0000-0000-0000000000a1', 'birthday', 'Mum''s birthday', '2020-11-10', 'yearly'),
  ('7e500000-0000-0000-0000-000000000009', '7e400000-0000-0000-0000-000000000002',
   '7e300000-0000-0000-0000-0000000000c3', 'birthday', 'Old flame''s birthday', '2020-11-10', 'yearly'),
  ('7e500000-0000-0000-0000-000000000008', '7e400000-0000-0000-0000-000000000003',
   '7e300000-0000-0000-0000-0000000000c3', 'birthday', 'Gran''s birthday', '2020-11-10', 'yearly');

-- 1. Each partner hears on their own local morning (from 09:00), never the night before.
DO $$
BEGIN
  PERFORM public.generate_reminder_notifications('2026-11-10T08:00:00Z');
  IF pg_temp.sent('reminder:7e500000-0000-0000-0000-000000000001:%') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: sent before anyone''s 09:00';
  END IF;
  PERFORM public.generate_reminder_notifications('2026-11-10T09:05:00Z');
  IF pg_temp.sent('reminder:7e500000-0000-0000-0000-000000000001:2026-11-10:7e300000-0000-0000-0000-0000000000b2:0') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Kofi (UTC) not told at 09:05 his time';
  END IF;
  IF pg_temp.sent('reminder:7e500000-0000-0000-0000-000000000001:%:7e300000-0000-0000-0000-0000000000a1:%') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ama told at 01:05 in Los Angeles';
  END IF;
  PERFORM public.generate_reminder_notifications('2026-11-10T17:05:00Z');
  IF pg_temp.sent('reminder:7e500000-0000-0000-0000-000000000001:2026-11-10:7e300000-0000-0000-0000-0000000000a1:0') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ama not told at 09:05 in Los Angeles';
  END IF;
  -- Once per person per day, however often the job runs.
  PERFORM public.generate_reminder_notifications('2026-11-10T17:20:00Z');
  PERFORM public.generate_reminder_notifications('2026-11-10T20:00:00Z');
  IF pg_temp.sent('reminder:7e500000-0000-0000-0000-000000000001:2026-11-10:%') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: duplicate day-of reminders';
  END IF;
END $$;

-- 2. Three days before, in the morning, and on the day too (the two never
--    share a key, so the first can't swallow the second); plain wording.
DO $$
DECLARE v_body text;
BEGIN
  PERFORM public.generate_reminder_notifications('2026-11-07T09:05:00Z');
  SELECT metadata->>'body' INTO v_body FROM public.scheduled_notifications
  WHERE source_key = 'reminder:7e500000-0000-0000-0000-000000000001:2026-11-10:7e300000-0000-0000-0000-0000000000b2:3';
  IF v_body IS DISTINCT FROM 'In 3 days' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: 3-day body %', v_body; END IF;
  SELECT metadata->>'body' INTO v_body FROM public.scheduled_notifications
  WHERE source_key = 'reminder:7e500000-0000-0000-0000-000000000001:2026-11-10:7e300000-0000-0000-0000-0000000000b2:0';
  IF v_body IS DISTINCT FROM 'Today' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: day-of body %', v_body; END IF;
END $$;

-- 3. An ended or paused couple hears nothing: Spec 3a made the reminder
--    generator active-only ("reminders stop" while paused; sync audit K-2).
DO $$
BEGIN
  IF pg_temp.sent('reminder:7e500000-0000-0000-0000-000000000009:%') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ended relationship still gets reminders';
  END IF;
  IF pg_temp.sent('reminder:7e500000-0000-0000-0000-000000000008:%') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused relationship still gets reminders';
  END IF;
END $$;

-- 4. A one-off for today, added in the afternoon, still goes out today.
DO $$
BEGIN
  INSERT INTO public.reminders (id, relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES ('7e500000-0000-0000-0000-000000000002', '7e400000-0000-0000-0000-000000000001',
          '7e300000-0000-0000-0000-0000000000b2', 'custom', 'Dentist', '2026-11-10', 'none');
  PERFORM public.generate_reminder_notifications('2026-11-10T15:15:00Z');
  IF pg_temp.sent('reminder:7e500000-0000-0000-0000-000000000002:2026-11-10:7e300000-0000-0000-0000-0000000000b2:0') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a same-day reminder never went out';
  END IF;
  IF NOT (SELECT sent FROM public.reminders WHERE id = '7e500000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a delivered one-off is not marked sent';
  END IF;
END $$;

-- 4b. Pushes the old daily job already sent today (old keys) aren't sent again.
DO $$
BEGIN
  INSERT INTO public.reminders (id, relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES ('7e500000-0000-0000-0000-000000000004', '7e400000-0000-0000-0000-000000000001',
          '7e300000-0000-0000-0000-0000000000b2', 'custom', 'Rent', '2026-11-12', 'none');
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  VALUES ('7e300000-0000-0000-0000-0000000000b2', 'immediate', now(), 'sent',
          '{"type":"reminder_upcoming","days_until":0}'::jsonb,
          'reminder:7e500000-0000-0000-0000-000000000004:2026-11-12:7e300000-0000-0000-0000-0000000000b2', now(), now());
  PERFORM public.reminder_carry_over_old_keys();
  PERFORM public.generate_reminder_notifications('2026-11-12T09:05:00Z');
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications
             WHERE source_key = 'reminder:7e500000-0000-0000-0000-000000000004:2026-11-12:7e300000-0000-0000-0000-0000000000b2:0'
               AND status <> 'skipped') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an already-sent push went out again under the new key';
  END IF;
END $$;

-- 5. A one-off that already went out, moved to a new date, goes out again.
DO $$
DECLARE v_sent boolean;
BEGIN
  UPDATE public.reminders SET sent = true WHERE id = '7e500000-0000-0000-0000-000000000002';
  UPDATE public.reminders SET remind_at = '2026-11-20' WHERE id = '7e500000-0000-0000-0000-000000000002';
  SELECT sent INTO v_sent FROM public.reminders WHERE id = '7e500000-0000-0000-0000-000000000002';
  IF v_sent THEN RAISE EXCEPTION 'CONTRACT VIOLATED: moving a reminder kept it marked sent'; END IF;
  PERFORM public.generate_reminder_notifications('2026-11-20T09:05:00Z');
  IF pg_temp.sent('reminder:7e500000-0000-0000-0000-000000000002:2026-11-20:7e300000-0000-0000-0000-0000000000b2:0') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a moved one-off never went out again';
  END IF;
END $$;

-- 6. Feb 29 falls on Feb 28 in a non-leap year.
DO $$
BEGIN
  INSERT INTO public.reminders (id, relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES ('7e500000-0000-0000-0000-000000000003', '7e400000-0000-0000-0000-000000000001',
          '7e300000-0000-0000-0000-0000000000b2', 'birthday', 'Leap', '2024-02-29', 'yearly');
  PERFORM public.generate_reminder_notifications('2027-02-28T09:05:00Z');
  IF pg_temp.sent('reminder:7e500000-0000-0000-0000-000000000003:2027-02-28:%') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Feb 29 did not land on Feb 28';
  END IF;
END $$;

-- 7. The job runs every 15 minutes.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-reminder-notifications'
                 AND schedule = '*/15 * * * *') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: reminder job is not every 15 minutes';
  END IF;
END $$;

-- 8. Family birthdays follow the member: renamed, cleared, deleted.
DO $$
DECLARE v_member uuid; v_title text; v_n int;
BEGIN
  PERFORM pg_temp.as_user('7e300000-0000-0000-0000-0000000000a1');
  v_member := public.upsert_family_member(NULL, 'Abena', '2019-05-04');
  PERFORM public.upsert_family_member(v_member, 'Abby', '2019-05-04');
  SELECT title INTO v_title FROM public.reminders WHERE family_member_id = v_member;
  IF v_title IS DISTINCT FROM 'Abby''s birthday' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: rename left %', v_title; END IF;
  PERFORM public.upsert_family_member(v_member, 'Abby', NULL);
  SELECT count(*) INTO v_n FROM public.reminders WHERE family_member_id = v_member;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: clearing the birthday kept its reminder'; END IF;
  PERFORM public.upsert_family_member(v_member, 'Abby', '2019-05-04');
  DELETE FROM public.couple_family_members WHERE id = v_member;
  SELECT count(*) INTO v_n FROM public.reminders WHERE title = 'Abby''s birthday';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: deleting the member kept its birthday reminder'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 9. A renamed member keeps a reminder title the couple wrote themselves.
DO $$
DECLARE v_member uuid; v_title text;
BEGIN
  PERFORM pg_temp.as_user('7e300000-0000-0000-0000-0000000000a1');
  v_member := public.upsert_family_member(NULL, 'Yaw', '2018-01-02');
  UPDATE public.reminders SET title = 'Yaw turns another year!' WHERE family_member_id = v_member;
  PERFORM public.upsert_family_member(v_member, 'Yaw K.', '2018-01-02');
  SELECT title INTO v_title FROM public.reminders WHERE family_member_id = v_member;
  IF v_title IS DISTINCT FROM 'Yaw turns another year!' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: custom title overwritten: %', v_title; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 9b. Deleting a member takes only their birthday reminder; anything else
--     linked to them stays. Renames go through the app's path only.
DO $$
DECLARE v_member uuid; v_n int;
BEGIN
  PERFORM pg_temp.as_user('7e300000-0000-0000-0000-0000000000a1');
  v_member := public.upsert_family_member(NULL, 'Kwame', '2017-03-03');
  INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence, family_member_id)
  VALUES ('7e400000-0000-0000-0000-000000000001', '7e300000-0000-0000-0000-0000000000a1', 'custom', 'Kwame''s school play', '2026-12-01', 'none', v_member);
  DELETE FROM public.couple_family_members WHERE id = v_member;
  SELECT count(*) INTO v_n FROM public.reminders WHERE title = 'Kwame''s birthday';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the birthday reminder outlived its member'; END IF;
  SELECT count(*) INTO v_n FROM public.reminders WHERE title = 'Kwame''s school play' AND family_member_id IS NULL;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: deleting a member took a reminder that wasn''t their birthday'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('7e300000-0000-0000-0000-0000000000a1');
DO $$
DECLARE v_member uuid;
BEGIN
  v_member := public.upsert_family_member(NULL, 'Akos', '2016-04-04');
  BEGIN
    UPDATE public.couple_family_members SET name = 'Akosua' WHERE id = v_member;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member was renamed around the app';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

-- 10. Moments stay in their own relationship, and none go into an ended one.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('7e300000-0000-0000-0000-0000000000b2');
DO $$
DECLARE v_id uuid;
BEGIN
  BEGIN
    INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
    VALUES ('7e400000-0000-0000-0000-000000000002', '7e300000-0000-0000-0000-0000000000b2', 'highlight', 'Into the ex', '2026-11-01');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a moment was written into an ended relationship';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e400000-0000-0000-0000-000000000001', '7e300000-0000-0000-0000-0000000000b2', 'highlight', 'Picnic', '2026-11-01')
  RETURNING id INTO v_id;
  BEGIN
    UPDATE public.timeline_events SET relationship_id = '7e400000-0000-0000-0000-000000000002' WHERE id = v_id;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a moment was moved to another relationship';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  -- Ordinary edits still work.
  UPDATE public.timeline_events SET title = 'Picnic by the lake' WHERE id = v_id;
END $$;
RESET ROLE;

ROLLBACK;
