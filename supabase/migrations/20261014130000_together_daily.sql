-- Together Phase 2b: per-partner prefs, the morning summary, and the
-- one-scheduled-push-per-day budget (spec D9, plan rulings R1–R4).
-- All copy is fixed templates (D6). Only shared events reach a partner.

CREATE TABLE public.together_member_prefs (
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  daily_summary boolean NOT NULL DEFAULT true,
  care_nudges boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (relationship_id, user_id)
);
ALTER TABLE public.together_member_prefs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.together_member_prefs FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.get_together_prefs(p_relationship_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.together_actor(p_relationship_id); v_row public.together_member_prefs;
BEGIN
  SELECT * INTO v_row FROM public.together_member_prefs
  WHERE relationship_id = p_relationship_id AND user_id = v_me;
  RETURN jsonb_build_object('daily_summary', coalesce(v_row.daily_summary, true),
                            'care_nudges', coalesce(v_row.care_nudges, true));
END;
$$;

CREATE FUNCTION public.set_together_prefs(p_relationship_id uuid, p_daily_summary boolean, p_care_nudges boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.together_actor(p_relationship_id);
BEGIN
  IF p_daily_summary IS NULL OR p_care_nudges IS NULL THEN PERFORM public.together_fail('invalid_input'); END IF;
  INSERT INTO public.together_member_prefs (relationship_id, user_id, daily_summary, care_nudges, updated_at)
  VALUES (p_relationship_id, v_me, p_daily_summary, p_care_nudges, now())
  ON CONFLICT (relationship_id, user_id) DO UPDATE
    SET daily_summary = EXCLUDED.daily_summary, care_nudges = EXCLUDED.care_nudges, updated_at = now();
  RETURN jsonb_build_object('daily_summary', p_daily_summary, 'care_nudges', p_care_nudges);
END;
$$;

-- The summary's lines for one person between two dates, in their zone.
-- Theirs: confirmed events they're in that they can see. Their partner's:
-- shared big days only (care on). Today only: a suggestion waiting.
CREATE FUNCTION public.together_digest_lines(
  p_relationship_id uuid, p_user uuid, p_from date, p_to date, p_tz text,
  p_care boolean, p_week boolean
) RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  -- Candidates from the event's own zone (a day either side), then each
  -- occurrence placed on the recipient's calendar: a Toronto 21:00 call is
  -- the next morning in London (Phase 2b review).
  WITH cand AS (
    SELECT ce.*, d.d AS ev_day,
      CASE WHEN ce.all_day THEN NULL
           WHEN ce.rrule IS NULL THEN ce.starts_at
           ELSE ((d.d + (ce.starts_at AT TIME ZONE ce.tz)::time) AT TIME ZONE ce.tz) END AS at
    FROM public.couple_events ce
    CROSS JOIN LATERAL public.together_event_dates(ce, p_from - 1, p_to + 1) AS d(d)
    WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
      AND ce.status = 'confirmed'
      -- one line per event: a one-off on its first day (timed: its start)
      AND (ce.rrule IS NOT NULL
           OR (ce.all_day AND d.d = greatest(p_from, ce.start_date))
           OR (NOT ce.all_day AND d.d = (ce.starts_at AT TIME ZONE ce.tz)::date))
  ), occ AS (
    SELECT cand.*,
      CASE WHEN at IS NULL THEN ev_day ELSE (at AT TIME ZONE p_tz)::date END AS on_day
    FROM cand
  ), placed AS (
    SELECT * FROM occ WHERE on_day BETWEEN p_from AND p_to
  ), lines AS (
    SELECT on_day, at,
      CASE WHEN p_week THEN to_char(on_day, 'Dy') || ': ' ELSE '' END
      || CASE WHEN at IS NULL THEN '' ELSE to_char(at AT TIME ZONE p_tz, 'HH24:MI') || ' ' END
      || title AS line
    FROM placed
    WHERE p_user = ANY (participant_ids) AND (visibility = 'shared' OR created_by = p_user)
    UNION ALL
    SELECT on_day, at,
      CASE WHEN p_week THEN to_char(on_day, 'Dy') || ': ' ELSE '' END
      || public.together_name(created_by) || '''s big day: ' || title
      || CASE WHEN at IS NULL THEN '' ELSE ' at ' || to_char(at AT TIME ZONE p_tz, 'HH24:MI') END
      || ' — a word of luck?'
    FROM placed
    WHERE p_care AND kind = 'big_day' AND visibility = 'shared'
      AND created_by <> p_user AND NOT (p_user = ANY (participant_ids))
    UNION ALL
    SELECT p_from, NULL::timestamptz, 'A suggestion is waiting for you'
    WHERE NOT p_week AND EXISTS (
      SELECT 1 FROM public.couple_events ce
      WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
        AND ce.status = 'proposed' AND ce.proposed_to = p_user AND ce.proposal_expires_at > now())
  )
  SELECT coalesce(array_agg(line ORDER BY on_day, at NULLS FIRST, line), '{}') FROM lines
$$;
REVOKE ALL ON FUNCTION public.together_digest_lines(uuid, uuid, date, date, text, boolean, boolean) FROM PUBLIC, anon, authenticated;

-- Every 15 minutes: each partner whose local time is 08:00–10:00 and who
-- has the summary on gets at most one push for their local day.
CREATE FUNCTION public.together_enqueue_daily(p_now timestamptz DEFAULT now())
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
    CROSS JOIN LATERAL (SELECT coalesce((SELECT s.timezone FROM public.planning_member_settings s
                         WHERE s.relationship_id = r.id AND s.user_id = u), 'UTC') AS tz) z
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

REVOKE ALL ON FUNCTION public.get_together_prefs(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_together_prefs(uuid, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_together_prefs(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_together_prefs(uuid, boolean, boolean) TO authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'together_daily';
END;
$$;
SELECT cron.schedule('together_daily', '*/15 * * * *', $$ SELECT public.together_enqueue_daily(); $$);
