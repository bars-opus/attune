-- Spec 1 W3c, migration 8 (spec §4.7 #8): journal_reminders.
--   * journal_reminder_settings: one weekly reminder per person (J3), read
--     by its owner only; written only through set_my_journal_reminder.
--   * enqueue_journal_reminders (cron every 15 minutes): one neutral push
--     per reminder per local day, at the chosen minute in the person's own
--     zone (notification_recipient_tz; never guessed). The time is kept
--     between 08:00 and 21:59 local, so the quiet-hours guard (22:00-08:00)
--     never moves a reminder to another day (W3 plan P-21). Cron runs that
--     are late or skipped still send it later the same local day, up to
--     21:59; a day missed until 22:00 is skipped, never moved to the next
--     morning (B6 review ruling M-1).
-- Grants in 20261026100010_journal_reminders_grants.sql; the server-only
-- function is revoked here as well.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.journal_reminder_settings (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT false,
  iso_weekday smallint
    CONSTRAINT journal_reminder_settings_weekday_check CHECK (iso_weekday BETWEEN 1 AND 7),
  local_time time
    CONSTRAINT journal_reminder_settings_time_check
      CHECK (local_time >= time '08:00' AND local_time < time '22:00'),
  last_enqueued_for date,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT journal_reminder_settings_enabled_check
    CHECK (NOT enabled OR (iso_weekday IS NOT NULL AND local_time IS NOT NULL))
);
ALTER TABLE public.journal_reminder_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS journal_reminder_settings_select_own ON public.journal_reminder_settings;
CREATE POLICY journal_reminder_settings_select_own ON public.journal_reminder_settings
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- J3's sheet. Turning it off keeps the day and time, so turning it on
-- again starts from them. A reminder already queued for the old setting is
-- cancelled (and its key freed), so the new one can go out today.
CREATE OR REPLACE FUNCTION public.set_my_journal_reminder(
  p_enabled boolean,
  p_iso_weekday smallint,
  p_local_time time
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_cancelled integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'journal_reminder:not_signed_in';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = v_uid) THEN
    RAISE EXCEPTION 'journal_reminder:no_account';
  END IF;
  IF p_enabled IS NULL
     OR (p_enabled AND (p_iso_weekday IS NULL OR p_local_time IS NULL))
     OR (p_iso_weekday IS NOT NULL AND p_iso_weekday NOT BETWEEN 1 AND 7) THEN
    RAISE EXCEPTION 'journal_reminder:invalid';
  END IF;
  IF p_local_time IS NOT NULL
     AND (p_local_time < time '08:00' OR p_local_time >= time '22:00') THEN
    RAISE EXCEPTION 'journal_reminder:quiet_hours';
  END IF;

  UPDATE public.scheduled_notifications AS n
     SET status = 'cancelled',
         source_key = NULL,
         last_error = 'journal_reminder_changed',
         updated_at = now()
   WHERE n.user_id = v_uid
     AND n.status = 'pending'
     AND n.source_key LIKE 'journal_reminder:' || v_uid::text || ':%';
  GET DIAGNOSTICS v_cancelled = ROW_COUNT;

  INSERT INTO public.journal_reminder_settings AS s
    (user_id, enabled, iso_weekday, local_time, updated_at)
  VALUES (v_uid, p_enabled, p_iso_weekday, date_trunc('minute', p_local_time)::time, now())
  ON CONFLICT (user_id) DO UPDATE
    SET enabled = EXCLUDED.enabled,
        iso_weekday = coalesce(EXCLUDED.iso_weekday, s.iso_weekday),
        local_time = coalesce(EXCLUDED.local_time, s.local_time),
        last_enqueued_for = CASE WHEN v_cancelled > 0 THEN NULL ELSE s.last_enqueued_for END,
        updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_journal_reminder()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(
    (SELECT jsonb_build_object(
              'enabled', s.enabled,
              'iso_weekday', s.iso_weekday,
              'local_time', to_char(s.local_time, 'HH24:MI'))
       FROM public.journal_reminder_settings AS s
      WHERE s.user_id = auth.uid()),
    jsonb_build_object('enabled', false, 'iso_weekday', NULL, 'local_time', NULL));
$$;

-- Every 15 minutes. A reminder is due when its local day and minute are at
-- most 15 minutes ahead of now, or already passed earlier the same local
-- day (late or skipped runs still catch it; the source key and
-- last_enqueued_for keep it to one per local day), it was set before that
-- minute, the person's zone is known and no hold is open. It is queued for
-- its own minute, or for now when late; never for 22:00 or later local and
-- never on another local day (ruling M-1: such a day is skipped). The copy
-- names nobody (checked phones).
CREATE OR REPLACE FUNCTION public.enqueue_journal_reminders(p_now timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count integer;
BEGIN
  WITH due AS (
    SELECT s.user_id, d.day, z.tz, ((d.day + s.local_time) AT TIME ZONE z.tz) AS due_at
      FROM public.journal_reminder_settings AS s
      CROSS JOIN LATERAL (SELECT public.notification_recipient_tz(s.user_id) AS tz) AS z
      CROSS JOIN LATERAL (
        SELECT ((p_now AT TIME ZONE z.tz)::date + k) AS day FROM generate_series(-1, 1) AS k
      ) AS d
     WHERE s.enabled
       AND z.tz IS NOT NULL
       AND extract(isodow FROM d.day) = s.iso_weekday
       AND (s.last_enqueued_for IS NULL OR s.last_enqueued_for < d.day)
       AND NOT EXISTS (SELECT 1 FROM public.account_holds AS h
                        WHERE h.user_id = s.user_id AND h.resolved_at IS NULL)
  ), picked AS (
    SELECT due.* FROM due
      JOIN public.journal_reminder_settings AS s ON s.user_id = due.user_id
     WHERE due.due_at <= p_now + interval '15 minutes'
       AND due.due_at > s.updated_at
       AND (greatest(due.due_at, p_now) AT TIME ZONE due.tz)::date = due.day
       AND (greatest(due.due_at, p_now) AT TIME ZONE due.tz)::time < time '22:00'
  ), queued AS (
    INSERT INTO public.scheduled_notifications
      (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
    SELECT p.user_id, 'immediate', greatest(p.due_at, p_now), 'pending',
           jsonb_build_object(
             'type', 'journal_reminder',
             'title', 'Attune',
             'body', 'A few quiet minutes for you, if you''d like.'),
           'journal_reminder:' || p.user_id::text || ':' || p.day::text,
           p_now, p_now
      FROM picked AS p
    ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING
    RETURNING user_id, split_part(source_key, ':', 3)::date AS day
  )
  UPDATE public.journal_reminder_settings AS s
     SET last_enqueued_for = q.day
    FROM queued AS q
   WHERE s.user_id = q.user_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.enqueue_journal_reminders(timestamptz) FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'enqueue-journal-reminders';
END;
$$;
SELECT cron.schedule(
  'enqueue-journal-reminders',
  '*/15 * * * *',
  $$ SELECT public.enqueue_journal_reminders(); $$
);

COMMIT;
