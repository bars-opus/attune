-- supabase/migrations/20261015110000_reminder_lead_times.sql
--
-- 1. The couple chooses when a reminder reaches them: on the day, 1, 3 or 7
--    days before (any of them, at least one). Until now it was always on
--    the day and 3 days before, which stays the default.
-- 2. A memory logged from a reminder (or a reminder made from a memory)
--    — always one of the same couple's —
--    follows the reminder's title and date when the reminder is edited —
--    unless the memory was edited on its own, which then stands. Deleting
--    the reminder keeps the memory (it already did: the link is held on
--    the reminder's side).

ALTER TABLE public.reminders
  ADD COLUMN IF NOT EXISTS remind_days_before int[] NOT NULL DEFAULT ARRAY[0, 3];

ALTER TABLE public.reminders DROP CONSTRAINT IF EXISTS reminders_remind_days_before_check;
ALTER TABLE public.reminders ADD CONSTRAINT reminders_remind_days_before_check
  CHECK (cardinality(remind_days_before) BETWEEN 1 AND 4
         AND remind_days_before <@ ARRAY[0, 1, 3, 7]);

GRANT INSERT (remind_days_before), UPDATE (remind_days_before)
  ON public.reminders TO authenticated;

-- Same job as 20261015100000, told on each chosen day instead of 0 and 3.
CREATE OR REPLACE FUNCTION public.generate_reminder_notifications(p_now timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  WITH ins AS (
  INSERT INTO public.scheduled_notifications
    (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  SELECT d.user_id, 'immediate', p_now, 'pending',
    jsonb_build_object(
      'title', d.title,
      'body', CASE d.days_until WHEN 0 THEN 'Today' WHEN 1 THEN 'Tomorrow'
                ELSE 'In ' || d.days_until || ' days' END,
      'type', 'reminder_upcoming',
      'reminder_id', d.reminder_id,
      'days_until', d.days_until),
    'reminder:' || d.reminder_id || ':' || d.next_on || ':' || d.user_id || ':' || d.days_until,
    p_now, p_now
  FROM (
    SELECT r.id AS reminder_id, r.title, r.remind_days_before, m.user_id,
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
       -- One-offs near today: every zone's today is within a day of UTC's,
       -- and the furthest ahead anyone hears is a week.
       OR (r.recurrence = 'none'
           AND (r.remind_at AT TIME ZONE 'UTC')::date
               BETWEEN (p_now AT TIME ZONE 'UTC')::date - 1 AND (p_now AT TIME ZONE 'UTC')::date + 8)
  ) d
  WHERE d.days_until = ANY (d.remind_days_before)
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING
  RETURNING (metadata->>'reminder_id')::uuid AS reminder_id,
            (metadata->>'days_until')::int AS days_until
  ),
  -- Bookkeeping only (see 20261015100000): this run's day-of pushes.
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

-- ---- The linked memory follows its reminder ---------------------------------------

-- Runs as the owner: the partner who edits the reminder may not own the
-- memory (moments are owner-edit only), and the edit is the couple's.
CREATE OR REPLACE FUNCTION public.reminders_sync_linked_memory()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.linked_timeline_event_id IS NULL THEN RETURN NULL; END IF;
  UPDATE public.timeline_events e SET
    -- Only what still matches the reminder's old value: a memory edited on
    -- its own keeps its own words and date.
    title = CASE WHEN NEW.title IS DISTINCT FROM OLD.title AND e.title = OLD.title
                 THEN NEW.title ELSE e.title END,
    occurred_at = CASE WHEN NEW.remind_at IS DISTINCT FROM OLD.remind_at
                        AND e.occurred_at = (OLD.remind_at AT TIME ZONE 'UTC')::date
                       THEN (NEW.remind_at AT TIME ZONE 'UTC')::date ELSE e.occurred_at END
  WHERE e.id = NEW.linked_timeline_event_id AND e.deleted_at IS NULL
    -- Never another couple's memory (the link is also checked on write).
    AND e.relationship_id = NEW.relationship_id;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.reminders_sync_linked_memory() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS reminders_sync_linked_memory ON public.reminders;
CREATE TRIGGER reminders_sync_linked_memory
  AFTER UPDATE OF title, remind_at ON public.reminders
  FOR EACH ROW EXECUTE FUNCTION public.reminders_sync_linked_memory();

-- A reminder links only a memory of its own couple: the link is client-
-- writable (20260814130000), and the sync above runs as the owner.
CREATE OR REPLACE FUNCTION public.reminders_check_linked_memory()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.linked_timeline_event_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.timeline_events e
       WHERE e.id = NEW.linked_timeline_event_id
         AND e.relationship_id = NEW.relationship_id) THEN
    RAISE EXCEPTION 'A reminder can only link a memory of its own couple'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.reminders_check_linked_memory() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS reminders_check_linked_memory ON public.reminders;
CREATE TRIGGER reminders_check_linked_memory
  BEFORE INSERT OR UPDATE OF linked_timeline_event_id, relationship_id ON public.reminders
  FOR EACH ROW EXECUTE FUNCTION public.reminders_check_linked_memory();
