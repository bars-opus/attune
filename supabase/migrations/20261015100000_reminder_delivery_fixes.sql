-- supabase/migrations/20261015100000_reminder_delivery_fixes.sql
--
-- Reminders reach each partner on their own local morning, and the gaps an
-- audit of the calendar's add flows found are closed (2026-10-15):
--
-- 1. Local time. The daily job ran at 07:00 UTC against UTC's date: 11pm
--    the night before in California, late afternoon in Sydney. It now runs
--    every 15 minutes and tells each partner from 09:00 in their own zone
--    (planning_member_settings, as the Together summary does; UTC when
--    unknown), once per person per day (source_key).
-- 2. Same-day reminders. One added after the single daily run never went
--    out; with the 15-minute job it goes out on the next run that day.
-- 3. The day-of push. The 3-days-before and day-of pushes shared one
--    source_key (the occurrence date), so after the first the second was
--    dropped as a duplicate. Each now has its own (:3 and :0).
-- 4. Edited one-offs. `sent` was set when a one-off fired and nothing
--    cleared it; moving the date silently stopped it ever firing. Delivery
--    no longer depends on it (the keys do), and a trigger clears it when
--    the date or recurrence changes.
-- 5. Ended relationships stop getting reminders (a paused one still does,
--    as before).
-- 6. Family birthdays follow their member: a cleared birthday or a deleted
--    member takes its reminder with it, and a rename renames the reminder
--    unless the couple gave it their own title.
-- 7. Moments stay in their own relationship: no new moment in an ended
--    one, and an existing moment can't be moved to another.

-- ---- Occurrence arithmetic ---------------------------------------------------

-- [p_on]'s month/day in year [p_year], the day clamped to that month's
-- length (Feb 29 -> Feb 28 in a non-leap year).
CREATE OR REPLACE FUNCTION public.reminder_day_in_year(p_on date, p_year int)
RETURNS date LANGUAGE sql IMMUTABLE AS $$
  SELECT make_date(p_year, extract(month FROM p_on)::int,
    least(extract(day FROM p_on)::int,
          extract(day FROM (make_date(p_year, extract(month FROM p_on)::int, 1)
                            + interval '1 month - 1 day'))::int))
$$;

-- The reminder's next occurrence on or after [p_from]: itself for a
-- one-off, this year's or next year's date for a yearly one.
CREATE OR REPLACE FUNCTION public.reminder_next_on(p_on date, p_recurrence text, p_from date)
RETURNS date LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_recurrence <> 'yearly' THEN p_on
    WHEN public.reminder_day_in_year(p_on, extract(year FROM p_from)::int) >= p_from
      THEN public.reminder_day_in_year(p_on, extract(year FROM p_from)::int)
    ELSE public.reminder_day_in_year(p_on, extract(year FROM p_from)::int + 1)
  END
$$;

REVOKE ALL ON FUNCTION public.reminder_day_in_year(date, int) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reminder_next_on(date, text, date) FROM PUBLIC, anon, authenticated;

-- ---- The generator -------------------------------------------------------------

DROP FUNCTION IF EXISTS public.generate_reminder_notifications();

-- remind_at holds the civil date as midnight UTC (the client writes a
-- plain YYYY-MM-DD), so the date is read back in UTC, never local time.
CREATE FUNCTION public.generate_reminder_notifications(p_now timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  WITH ins AS (
  INSERT INTO public.scheduled_notifications
    (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  SELECT d.user_id, 'immediate', p_now, 'pending',
    jsonb_build_object(
      'title', d.title,
      'body', CASE WHEN d.days_until = 0 THEN 'Today' ELSE 'In 3 days' END,
      'type', 'reminder_upcoming',
      'reminder_id', d.reminder_id,
      'days_until', d.days_until),
    'reminder:' || d.reminder_id || ':' || d.next_on || ':' || d.user_id || ':' || d.days_until,
    p_now, p_now
  FROM (
    SELECT r.id AS reminder_id, r.title, m.user_id,
           public.reminder_next_on((r.remind_at AT TIME ZONE 'UTC')::date, r.recurrence, m.local_day) AS next_on,
           public.reminder_next_on((r.remind_at AT TIME ZONE 'UTC')::date, r.recurrence, m.local_day)
             - m.local_day AS days_until
    FROM public.reminders r
    JOIN (
      SELECT rel.id AS relationship_id, u AS user_id, (p_now AT TIME ZONE z.tz)::date AS local_day
      FROM public.relationships rel
      CROSS JOIN LATERAL unnest(ARRAY[rel.user_a, rel.user_b]) AS u
      CROSS JOIN LATERAL (SELECT coalesce((SELECT s.timezone FROM public.planning_member_settings s
                           WHERE s.relationship_id = rel.id AND s.user_id = u), 'UTC') AS tz) z
      WHERE rel.status IN ('active', 'paused') AND u IS NOT NULL
        AND (p_now AT TIME ZONE z.tz)::time >= time '09:00'
    ) m ON m.relationship_id = r.relationship_id
    WHERE r.recurrence = 'yearly'
       -- One-offs near today (every zone's today is within a day of UTC's).
       OR (r.recurrence = 'none'
           AND (r.remind_at AT TIME ZONE 'UTC')::date
               BETWEEN (p_now AT TIME ZONE 'UTC')::date - 1 AND (p_now AT TIME ZONE 'UTC')::date + 4)
  ) d
  WHERE d.days_until IN (0, 3)
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING
  RETURNING (metadata->>'reminder_id')::uuid AS reminder_id,
            (metadata->>'days_until')::int AS days_until
  ),
  -- Bookkeeping only: a one-off counts as sent once its day-of push is
  -- queued for someone. Delivery itself never reads this. Only this run's
  -- rows are looked at, never the whole (shared, growing) push table.
  marked AS (
    UPDATE public.reminders r SET sent = true
    FROM ins
    WHERE r.id = ins.reminder_id AND ins.days_until = 0
      AND r.recurrence = 'none' AND NOT r.sent
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM ins;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public.generate_reminder_notifications(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.generate_reminder_notifications(timestamptz) TO service_role;

-- Moving a reminder's date (or making it yearly / one-off) makes it due
-- again.
CREATE OR REPLACE FUNCTION public.reminders_reset_sent()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.remind_at IS DISTINCT FROM OLD.remind_at
     OR NEW.recurrence IS DISTINCT FROM OLD.recurrence THEN
    NEW.sent := false;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reminders_reset_sent ON public.reminders;
CREATE TRIGGER reminders_reset_sent
  BEFORE UPDATE ON public.reminders
  FOR EACH ROW EXECUTE FUNCTION public.reminders_reset_sent();

-- Pushes the old daily job queued under the old keys
-- ('reminder:<id>:<date>:<user>') get their new key too, so the first runs
-- after deploy don't send today's "Today" / "In 3 days" a second time.
CREATE OR REPLACE FUNCTION public.reminder_carry_over_old_keys()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.scheduled_notifications
    (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  SELECT user_id, notification_type, scheduled_for, 'skipped', metadata,
         source_key || ':' || (metadata->>'days_until'), created_at, updated_at
  FROM public.scheduled_notifications
  WHERE source_key LIKE 'reminder:%' AND metadata ? 'days_until'
    AND source_key !~ ':[03]$' AND created_at >= now() - interval '4 days'
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
$$;
REVOKE ALL ON FUNCTION public.reminder_carry_over_old_keys() FROM PUBLIC, anon, authenticated;
SELECT public.reminder_carry_over_old_keys();

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'generate-reminder-notifications';
END;
$$;
SELECT cron.schedule(
  'generate-reminder-notifications',
  '*/15 * * * *',
  $$ SELECT public.generate_reminder_notifications(); $$
);

-- ---- Family birthdays follow their member ----------------------------------------

DO $$
DECLARE v_name text;
BEGIN
  SELECT conname INTO v_name FROM pg_constraint
  WHERE conrelid = 'public.reminders'::regclass AND contype = 'f'
    AND conkey = ARRAY[(SELECT attnum FROM pg_attribute
                        WHERE attrelid = 'public.reminders'::regclass AND attname = 'family_member_id')];
  IF v_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.reminders DROP CONSTRAINT %I', v_name);
  END IF;
END;
$$;
ALTER TABLE public.reminders
  ADD CONSTRAINT reminders_family_member_id_fkey
  FOREIGN KEY (family_member_id) REFERENCES public.couple_family_members(id) ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION public.upsert_family_member(
  p_id uuid,
  p_name text,
  p_birthday date
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_relationship_id uuid;
  v_member_id uuid;
  v_reminder_id uuid;
  v_old_name text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT id INTO v_relationship_id
  FROM public.relationships
  WHERE (user_a = v_user_id OR user_b = v_user_id) AND status = 'active';
  IF v_relationship_id IS NULL THEN
    RAISE EXCEPTION 'No active relationship';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.couple_family_members (relationship_id, name, birthday, created_by)
    VALUES (v_relationship_id, p_name, p_birthday, v_user_id)
    RETURNING id INTO v_member_id;
  ELSE
    SELECT name INTO v_old_name FROM public.couple_family_members
    WHERE id = p_id AND relationship_id = v_relationship_id;
    UPDATE public.couple_family_members
    SET name = p_name, birthday = p_birthday
    WHERE id = p_id AND relationship_id = v_relationship_id
    RETURNING id INTO v_member_id;
    IF v_member_id IS NULL THEN
      RAISE EXCEPTION 'Family member not found';
    END IF;
  END IF;

  SELECT id INTO v_reminder_id
  FROM public.reminders
  WHERE family_member_id = v_member_id AND reminder_type = 'birthday';

  IF p_birthday IS NULL THEN
    -- No birthday, no birthday reminder.
    DELETE FROM public.reminders WHERE id = v_reminder_id;
  ELSIF v_reminder_id IS NULL THEN
    INSERT INTO public.reminders (
      relationship_id, created_by, reminder_type, title,
      remind_at, recurrence, family_member_id
    ) VALUES (
      v_relationship_id, v_user_id, 'birthday', left(p_name || '''s birthday', 80),
      (p_birthday::text || ' 00:00:00+00')::timestamptz, 'yearly', v_member_id
    );
  ELSE
    UPDATE public.reminders
    SET remind_at = (p_birthday::text || ' 00:00:00+00')::timestamptz,
        -- Renamed with them, unless the couple wrote their own title.
        title = CASE WHEN title = left(coalesce(v_old_name, p_name) || '''s birthday', 80)
                     THEN left(p_name || '''s birthday', 80) ELSE title END
    WHERE id = v_reminder_id;
  END IF;

  RETURN v_member_id;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_family_member(uuid, text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_family_member(uuid, text, date) TO authenticated;

-- ---- Moments stay in their own, active relationship ------------------------------

DROP POLICY IF EXISTS timeline_insert_members ON public.timeline_events;
CREATE POLICY timeline_insert_members
ON public.timeline_events FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = logged_by
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE (user_a = auth.uid() OR user_b = auth.uid()) AND status <> 'ended'
  )
);

CREATE OR REPLACE FUNCTION public.timeline_events_freeze_owner()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.relationship_id IS DISTINCT FROM OLD.relationship_id
     OR NEW.logged_by IS DISTINCT FROM OLD.logged_by THEN
    RAISE EXCEPTION 'A moment stays with its relationship and author'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS timeline_events_freeze_owner ON public.timeline_events;
CREATE TRIGGER timeline_events_freeze_owner
  BEFORE UPDATE ON public.timeline_events
  FOR EACH ROW EXECUTE FUNCTION public.timeline_events_freeze_owner();
