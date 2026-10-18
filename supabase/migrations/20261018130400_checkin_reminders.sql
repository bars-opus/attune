-- Spec 5 (R5-11, research 06 A7; plan review C5, I8, I9): the weekly
-- check-in reminder, generated in SQL like the other reminders (the
-- send-checkin-reminders function stays unscheduled). Hourly; a person is
-- reminded once on their own Sunday between 18:00 and 18:59, when they are
-- in an active relationship, have no check-in since their own Monday 00:00
-- (final review M-4: a Monday-morning check-in is this week's, though more
-- than six days old by Sunday evening) and their zone is known (never
-- guessed). The copy names nobody; the quiet-hours
-- guard still sees every row.
CREATE OR REPLACE FUNCTION public.generate_checkin_reminders(p_now timestamptz DEFAULT now())
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_count int;
BEGIN
  INSERT INTO public.scheduled_notifications
    (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  SELECT d.uid, 'immediate', p_now, 'pending',
    jsonb_build_object(
      'type', 'checkin_reminder',
      'screen', 'weekly_checkin',
      'title', 'Weekly check-in',
      'body', 'A minute to look back on your week.',
      -- Sync audit M-1: pause and end cancel it, like every other push.
      'relationship_id', d.rid),
    'checkin:' || d.uid || ':' || d.local_at::date,
    p_now, p_now
  FROM (
    SELECT DISTINCT ON (m.uid) m.uid, r.id AS rid, z.tz, (p_now AT TIME ZONE z.tz) AS local_at
    FROM public.relationships r
    CROSS JOIN LATERAL (VALUES (r.user_a), (r.user_b)) AS m(uid)
    CROSS JOIN LATERAL (SELECT public.notification_recipient_tz(m.uid) AS tz) z
    WHERE r.status = 'active' AND r.chat_archived_at IS NULL
      AND m.uid IS NOT NULL AND z.tz IS NOT NULL
    ORDER BY m.uid
  ) d
  WHERE extract(isodow FROM d.local_at) = 7
    AND extract(hour FROM d.local_at) = 18
    AND NOT EXISTS (
      SELECT 1 FROM public.weekly_checkins w
      WHERE w.user_id = d.uid
        AND w.submitted_at >= (date_trunc('week', d.local_at) AT TIME ZONE d.tz))
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.generate_checkin_reminders(timestamptz) FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'generate-checkin-reminders';
END;
$$;
SELECT cron.schedule(
  'generate-checkin-reminders',
  -- :10, clear of the planning countdown pushes at :05 (final review M-5).
  '10 * * * *',
  $$ SELECT public.generate_checkin_reminders(); $$
);
