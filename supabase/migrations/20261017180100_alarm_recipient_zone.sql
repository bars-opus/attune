-- supabase/migrations/20261017180100_alarm_recipient_zone.sql
--
-- Time-of-day pushes on the recipient's own clock (Spec 1b final review I1
-- and follow-up M8). The alarm, daily-summary, countdown and reminder
-- generators each picked "08:00 local" / "09:00 local" from the zone
-- Planning stored, else a UTC guess -- so a Toronto user who never opened
-- Planning got an all-day alarm at 03:00 (alarms are exempt from quiet hours,
-- D1), a summary a day late, a reminder at 04:00. All four now ask
-- notification_local_zone: the zone the phone reported, then Planning's,
-- then UTC. Each function is otherwise identical to its source:
--   together_enqueue_event_alarms      20261014110300_together_event_alarms.sql
--   together_enqueue_daily             20261014130000_together_daily.sql
--   planning_enqueue_countdown_pushes  20261012200900_planning_couple_blocks.sql
--   generate_reminder_notifications    20261015110000_reminder_lead_times.sql

CREATE OR REPLACE FUNCTION public.notification_local_zone(p_user uuid, p_relationship uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(
    public.notification_recipient_tz(p_user),
    (SELECT s.timezone FROM public.planning_member_settings s
      WHERE s.relationship_id = p_relationship AND s.user_id = p_user),
    'UTC')
$$;
REVOKE ALL ON FUNCTION public.notification_local_zone(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.together_enqueue_event_alarms(p_now timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  INSERT INTO public.scheduled_notifications
    (user_id, notification_type, scheduled_for, status, metadata, source_key)
  SELECT m.user_id, 'immediate', p_now, 'pending',
    jsonb_build_object(
      'type', 'together_event',
      'relationship_id', ce.relationship_id,
      'event_id', ce.id,
      'title', left(ce.title, 120),
      'body', CASE
        WHEN o.off = 0 AND ce.all_day THEN 'Today'
        WHEN o.off = 0 THEN 'Starting now'
        WHEN o.off % 1440 = 0 THEN 'In ' || (o.off / 1440) || CASE WHEN o.off = 1440 THEN ' day' ELSE ' days' END
        WHEN o.off % 60 = 0 THEN 'In ' || (o.off / 60) || CASE WHEN o.off = 60 THEN ' hour' ELSE ' hours' END
        ELSE 'In ' || o.off || ' minutes' END),
    'together_alarm:' || ce.id || ':' || occ.d || ':' || o.off || ':' || m.user_id
  FROM public.couple_events ce
  JOIN public.relationships r
    ON r.id = ce.relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
  CROSS JOIN LATERAL unnest(ce.remind_offsets_min) AS o(off)
  CROSS JOIN LATERAL (
    SELECT u AS user_id,
           public.notification_local_zone(u, r.id) AS tz
    FROM unnest(CASE WHEN ce.visibility = 'shared' THEN ce.participant_ids
                     ELSE ARRAY[ce.created_by] END) AS u
    WHERE u = r.user_a OR u = r.user_b
  ) m
  CROSS JOIN LATERAL public.together_event_dates(
    ce, (p_now AT TIME ZONE m.tz)::date - 1, (p_now AT TIME ZONE m.tz)::date + 8) AS occ(d)
  CROSS JOIN LATERAL (
    SELECT CASE
      WHEN ce.all_day THEN (occ.d + time '08:00') AT TIME ZONE m.tz
      WHEN ce.rrule IS NULL THEN ce.starts_at
      ELSE (occ.d + (ce.starts_at AT TIME ZONE ce.tz)::time) AT TIME ZONE ce.tz
    END AS ref
  ) t
  WHERE ce.deleted_at IS NULL AND ce.status = 'confirmed'
    AND cardinality(ce.remind_offsets_min) > 0
    -- one alarm per occurrence: a multi-day event alarms on its first day only
    AND (ce.rrule IS NOT NULL OR occ.d = CASE WHEN ce.all_day THEN ce.start_date
                                              ELSE (ce.starts_at AT TIME ZONE ce.tz)::date END)
    AND p_now >= t.ref - make_interval(mins => o.off)
    AND p_now < t.ref - make_interval(mins => o.off) + interval '20 minutes'
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.together_enqueue_event_alarms(timestamptz) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.together_enqueue_daily(p_now timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  INSERT INTO public.scheduled_notifications
    (user_id, notification_type, scheduled_for, status, metadata, source_key)
  SELECT m.user_id, 'immediate', p_now, 'pending',
    jsonb_build_object(
      'type', 'together_daily', 'relationship_id', m.relationship_id,
      'title', CASE WHEN m.week THEN 'Your week together' ELSE 'Today' END,
      'body', left(array_to_string(l.lines[1:3], ' · ')
                   || CASE WHEN cardinality(l.lines) > 3 THEN ' · and more' ELSE '' END, 160)),
    'together_daily:' || m.user_id || ':' || m.local_day
  FROM (
    SELECT r.id AS relationship_id, u AS user_id, z.tz,
           (p_now AT TIME ZONE z.tz)::date AS local_day,
           extract(isodow FROM (p_now AT TIME ZONE z.tz)) = 7 AS week,
           coalesce(p.daily_summary, true) AS summary_on,
           coalesce(p.care_nudges, true) AS care_on
    FROM public.relationships r
    CROSS JOIN LATERAL unnest(ARRAY[r.user_a, r.user_b]) AS u
    CROSS JOIN LATERAL (SELECT public.notification_local_zone(u, r.id) AS tz) z
    LEFT JOIN public.together_member_prefs p ON p.relationship_id = r.id AND p.user_id = u
    WHERE r.status = 'active' AND r.chat_archived_at IS NULL AND u IS NOT NULL
      AND (p_now AT TIME ZONE z.tz)::time >= time '08:00'
      AND (p_now AT TIME ZONE z.tz)::time < time '10:00'
  ) m
  CROSS JOIN LATERAL (
    SELECT public.together_digest_lines(m.relationship_id, m.user_id, m.local_day,
      CASE WHEN m.week THEN m.local_day + 6 ELSE m.local_day END, m.tz, m.care_on, m.week) AS lines
  ) l
  WHERE m.summary_on AND cardinality(l.lines) > 0
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.together_enqueue_daily(timestamptz) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.planning_enqueue_countdown_pushes(p_now timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key)
  SELECT m.user_id, 'immediate', p_now, 'pending',
         jsonb_build_object('type', 'planning_entry', 'relationship_id', e.relationship_id, 'entry_id', e.id,
           'title', 'Today''s the day', 'body', left(e.title, 160)),
         'planning_countdown:' || b.id || ':' || m.user_id || ':' || (p_now AT TIME ZONE m.tz)::date
  FROM public.planning_blocks b
  JOIN public.planning_entries e ON e.id = b.entry_id
   AND e.deleted_at IS NULL AND NOT e.is_template AND e.status = 'active'
  JOIN public.relationships r ON r.id = e.relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
  CROSS JOIN LATERAL (
    SELECT u AS user_id,
           public.notification_local_zone(u, r.id) AS tz
    FROM unnest(ARRAY[r.user_a, r.user_b]) u) m
  WHERE b.block_type = 'countdown' AND b.deleted_at IS NULL
    AND public.planning_v2_countdown_target(b) = (p_now AT TIME ZONE m.tz)::date
    AND (p_now AT TIME ZONE m.tz)::time >= time '08:00'
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_enqueue_countdown_pushes(timestamptz) FROM PUBLIC, anon, authenticated;

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
      CROSS JOIN LATERAL (SELECT public.notification_local_zone(u, rel.id) AS tz) z
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
