-- Reminder lead times and linked memories (2026-10-15): the couple picks
-- when they hear (on the day, 1, 3 or 7 days before), and a memory logged
-- from a reminder follows its title and date.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users (id) VALUES ('7e600000-0000-0000-0000-0000000000a1'), ('7e600000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7e600000-0000-0000-0000-0000000000a1', '+233290000201', 'Ama'),
  ('7e600000-0000-0000-0000-0000000000b2', '+233290000202', 'Kofi') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('7e700000-0000-0000-0000-000000000001', '7e600000-0000-0000-0000-0000000000a1',
   '7e600000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.body(p_key text) RETURNS text LANGUAGE sql AS $$
  SELECT metadata->>'body' FROM public.scheduled_notifications WHERE source_key = p_key $$;

-- 1. By default: on the day and 3 days before, as before.
DO $$
DECLARE v int[];
BEGIN
  INSERT INTO public.reminders (id, relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES ('7e800000-0000-0000-0000-000000000001', '7e700000-0000-0000-0000-000000000001',
          '7e600000-0000-0000-0000-0000000000a1', 'birthday', 'Mum''s birthday', '2020-12-10', 'yearly')
  RETURNING remind_days_before INTO v;
  IF v IS DISTINCT FROM ARRAY[0, 3] THEN RAISE EXCEPTION 'CONTRACT VIOLATED: default lead times %', v; END IF;
END $$;

-- 2. A day before and a week before, and nothing else.
DO $$
DECLARE k text := 'reminder:7e800000-0000-0000-0000-000000000002:2026-12-20:7e600000-0000-0000-0000-0000000000b2:';
BEGIN
  INSERT INTO public.reminders (id, relationship_id, created_by, reminder_type, title, remind_at, recurrence, remind_days_before)
  VALUES ('7e800000-0000-0000-0000-000000000002', '7e700000-0000-0000-0000-000000000001',
          '7e600000-0000-0000-0000-0000000000a1', 'anniversary', 'Our day', '2020-12-20', 'yearly', ARRAY[1, 7]);
  PERFORM public.generate_reminder_notifications('2026-12-13T09:05:00Z');
  PERFORM public.generate_reminder_notifications('2026-12-17T09:05:00Z');
  PERFORM public.generate_reminder_notifications('2026-12-19T09:05:00Z');
  PERFORM public.generate_reminder_notifications('2026-12-20T09:05:00Z');
  IF pg_temp.body(k || '7') IS DISTINCT FROM 'In 7 days' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: week-before %', pg_temp.body(k || '7'); END IF;
  IF pg_temp.body(k || '1') IS DISTINCT FROM 'Tomorrow' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: day-before %', pg_temp.body(k || '1'); END IF;
  IF pg_temp.body(k || '3') IS NOT NULL OR pg_temp.body(k || '0') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: told on a day not chosen';
  END IF;
END $$;

-- 3. A one-off a week out is still found by the job.
DO $$
BEGIN
  INSERT INTO public.reminders (id, relationship_id, created_by, reminder_type, title, remind_at, recurrence, remind_days_before)
  VALUES ('7e800000-0000-0000-0000-000000000003', '7e700000-0000-0000-0000-000000000001',
          '7e600000-0000-0000-0000-0000000000a1', 'custom', 'Flight', '2026-12-27', 'none', ARRAY[7]);
  PERFORM public.generate_reminder_notifications('2026-12-20T09:05:00Z');
  IF pg_temp.body('reminder:7e800000-0000-0000-0000-000000000003:2026-12-27:7e600000-0000-0000-0000-0000000000b2:7') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a one-off a week out was missed';
  END IF;
END $$;

-- 4. Only the offered choices, and at least one.
DO $$
BEGIN
  BEGIN
    UPDATE public.reminders SET remind_days_before = ARRAY[2] WHERE id = '7e800000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'CONTRACT VIOLATED: 2 days accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.reminders SET remind_days_before = '{}' WHERE id = '7e800000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'CONTRACT VIOLATED: no lead time accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

-- 5. Either partner can change when they hear.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('7e600000-0000-0000-0000-0000000000b2');
UPDATE public.reminders SET remind_days_before = ARRAY[0, 1] WHERE id = '7e800000-0000-0000-0000-000000000001';
RESET ROLE;
DO $$
BEGIN
  IF (SELECT remind_days_before FROM public.reminders WHERE id = '7e800000-0000-0000-0000-000000000001')
     IS DISTINCT FROM ARRAY[0, 1] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: partner could not change lead times';
  END IF;
END $$;

-- 6. A memory logged from a reminder follows its title and date; one
--    edited on its own keeps its own; deleting the reminder keeps it.
DO $$
DECLARE v_m uuid; v_m2 uuid; v_title text; v_on date;
BEGIN
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e700000-0000-0000-0000-000000000001', '7e600000-0000-0000-0000-0000000000a1', 'anniversary', 'First date', '2021-06-04')
  RETURNING id INTO v_m;
  INSERT INTO public.reminders (id, relationship_id, created_by, reminder_type, title, remind_at, recurrence, linked_timeline_event_id)
  VALUES ('7e800000-0000-0000-0000-000000000004', '7e700000-0000-0000-0000-000000000001',
          '7e600000-0000-0000-0000-0000000000b2', 'anniversary', 'First date', '2021-06-04', 'yearly', v_m);
  UPDATE public.reminders SET title = 'Our first date', remind_at = '2021-06-05'
  WHERE id = '7e800000-0000-0000-0000-000000000004';
  SELECT title, occurred_at INTO v_title, v_on FROM public.timeline_events WHERE id = v_m;
  IF v_title <> 'Our first date' OR v_on <> '2021-06-05' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: memory did not follow its reminder (% %)', v_title, v_on;
  END IF;

  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e700000-0000-0000-0000-000000000001', '7e600000-0000-0000-0000-0000000000a1', 'milestone', 'Moved in', '2023-01-10')
  RETURNING id INTO v_m2;
  INSERT INTO public.reminders (id, relationship_id, created_by, reminder_type, title, remind_at, recurrence, linked_timeline_event_id)
  VALUES ('7e800000-0000-0000-0000-000000000005', '7e700000-0000-0000-0000-000000000001',
          '7e600000-0000-0000-0000-0000000000a1', 'anniversary', 'Moved in', '2023-01-10', 'yearly', v_m2);
  UPDATE public.timeline_events SET title = 'Moved into the flat on Oxford St' WHERE id = v_m2;
  UPDATE public.reminders SET title = 'Move-in day' WHERE id = '7e800000-0000-0000-0000-000000000005';
  SELECT title INTO v_title FROM public.timeline_events WHERE id = v_m2;
  IF v_title <> 'Moved into the flat on Oxford St' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a memory''s own title was overwritten: %', v_title;
  END IF;

  DELETE FROM public.reminders WHERE id = '7e800000-0000-0000-0000-000000000004';
  IF NOT EXISTS (SELECT 1 FROM public.timeline_events WHERE id = v_m AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: deleting a reminder removed its memory';
  END IF;
END $$;

-- 7. A reminder can only link a memory of its own couple, and editing it
--    never reaches anyone else's.
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('7e700000-0000-0000-0000-000000000002', '7e600000-0000-0000-0000-0000000000a1', NULL, 'ended', now(), now())
ON CONFLICT (id) DO NOTHING;
DO $$
DECLARE v_old uuid;
BEGIN
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e700000-0000-0000-0000-000000000002', '7e600000-0000-0000-0000-0000000000a1', 'anniversary', 'Old times', '2019-02-02')
  RETURNING id INTO v_old;
  BEGIN
    INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence, linked_timeline_event_id)
    VALUES ('7e700000-0000-0000-0000-000000000001', '7e600000-0000-0000-0000-0000000000b2', 'anniversary', 'Old times', '2019-02-02', 'yearly', v_old);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reminder linked another couple''s memory';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.reminders SET linked_timeline_event_id = v_old WHERE id = '7e800000-0000-0000-0000-000000000005';
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reminder was relinked to another couple''s memory';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

ROLLBACK;
