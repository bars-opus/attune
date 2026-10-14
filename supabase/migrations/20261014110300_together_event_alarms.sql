-- Event alarms the user asked for (plan ruling R6; outside D9's budget).
-- Every 15 minutes: an alarm fires in the first run at or after
-- (start − offset), within a 20-minute window; idempotent per event,
-- day, offset and recipient. All-day events count from 08:00 in the
-- recipient's zone (planning_member_settings, else UTC). Shared events
-- alarm their participants; busy_only/private ones only their creator.

CREATE FUNCTION public.together_enqueue_event_alarms(p_now timestamptz DEFAULT now())
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
           coalesce((SELECT s.timezone FROM public.planning_member_settings s
                     WHERE s.relationship_id = r.id AND s.user_id = u), 'UTC') AS tz
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

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'together_event_alarms';
END;
$$;
SELECT cron.schedule('together_event_alarms', '*/15 * * * *',
  $$ SELECT public.together_enqueue_event_alarms(); $$);
