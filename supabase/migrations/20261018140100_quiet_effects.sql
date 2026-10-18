-- Spec 7 (research 06 B9 (a), (d); A9; plan review I1, I5, M13): what a
-- quiet state silences on the server, and "Hide a period".
--   * the Planning goal-reached notice: not while either member is quiet,
--     and not later (the goal counts as celebrated);
--   * the daily summary: a quiet person keeps only the plain summary line
--     (no big-day nudge, no "a suggestion is waiting");
--   * On this day and memory prompts: nothing for a quiet person;
--   * hidden periods: a person's own date spans that never resurface for
--     them (On this day, memory prompts) — the moments stay in their list.
-- Grants in 20261018140110.

CREATE TABLE IF NOT EXISTS public.hidden_periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  starts_on date NOT NULL,
  ends_on date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_on >= starts_on)
);
CREATE INDEX IF NOT EXISTS hidden_periods_user_idx ON public.hidden_periods (user_id, starts_on);
ALTER TABLE public.hidden_periods ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.user_hides_date(p_user uuid, p_day date)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.hidden_periods h
                 WHERE h.user_id = p_user AND p_day BETWEEN h.starts_on AND h.ends_on);
$$;

CREATE OR REPLACE FUNCTION public.add_hidden_period(p_starts_on date, p_ends_on date)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'hidden_period:not_signed_in'; END IF;
  IF p_starts_on IS NULL OR p_ends_on IS NULL OR p_ends_on < p_starts_on THEN
    RAISE EXCEPTION 'hidden_period:invalid';
  END IF;
  IF (SELECT count(*) FROM public.hidden_periods WHERE user_id = v_uid) >= 50 THEN
    RAISE EXCEPTION 'hidden_period:too_many';
  END IF;
  INSERT INTO public.hidden_periods (user_id, starts_on, ends_on)
  VALUES (v_uid, p_starts_on, p_ends_on) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_hidden_period(p_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  DELETE FROM public.hidden_periods WHERE id = p_id AND user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.list_my_hidden_periods()
RETURNS TABLE (id uuid, starts_on date, ends_on date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT h.id, h.starts_on, h.ends_on FROM public.hidden_periods h
  WHERE h.user_id = auth.uid() ORDER BY h.starts_on DESC;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_maybe_celebrate(p_entry_id uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry public.planning_entries; v_seed text;
BEGIN
  SELECT * INTO v_entry FROM public.planning_entries WHERE id = p_entry_id;
  SELECT seed_key INTO v_seed FROM public.planning_categories WHERE id = v_entry.category_id;
  IF v_entry.id IS NULL OR v_entry.celebrated_at IS NOT NULL OR v_entry.is_template OR v_seed IS DISTINCT FROM 'goals'
     OR p_actor IS NULL THEN
    RETURN;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.planning_blocks b, LATERAL (SELECT public.planning_v2_block_computed(b) AS c) x
    WHERE b.entry_id = p_entry_id AND b.block_type = 'progress' AND b.deleted_at IS NULL
      AND CASE WHEN x.c ->> 'mode' = 'checklist'
               THEN (x.c ->> 'total')::int > 0 AND (x.c ->> 'done')::int = (x.c ->> 'total')::int
               ELSE coalesce(b.target_minor, 0) > 0 AND (x.c ->> 'current')::bigint >= b.target_minor END) THEN
    RETURN;
  END IF;
  -- Spec 7 (B9, A9; plan review I1): no goal notice while either member is
  -- quiet (it is shared, so it goes for both and says nothing about who),
  -- and none later either: the goal counts as celebrated.
  IF EXISTS (SELECT 1 FROM public.relationships r
             WHERE r.id = v_entry.relationship_id
               AND (public.user_is_quiet(r.user_a) OR public.user_is_quiet(r.user_b))) THEN
    UPDATE public.planning_entries SET celebrated_at = clock_timestamp() WHERE id = p_entry_id;
    RETURN;
  END IF;
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content,
                               is_system_notice, message_analysis_skipped, source, created_at)
  VALUES (gen_random_uuid(), v_entry.relationship_id, p_actor, gen_random_uuid(),
          '🎉 Goal reached: ' || v_entry.title, true, true, 'native', clock_timestamp());
  UPDATE public.planning_entries SET celebrated_at = clock_timestamp() WHERE id = p_entry_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.together_digest_lines(
  p_relationship_id uuid, p_user uuid, p_from date, p_to date, p_tz text,
  p_care boolean, p_week boolean
) RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH cand AS (
    SELECT ce.*, d.d AS ev_day,
      CASE WHEN ce.all_day THEN NULL
           WHEN ce.rrule IS NULL THEN ce.starts_at
           ELSE ((d.d + (ce.starts_at AT TIME ZONE ce.tz)::time) AT TIME ZONE ce.tz) END AS at
    FROM public.couple_events ce
    CROSS JOIN LATERAL public.together_event_dates(ce, p_from - 1, p_to + 1) AS d(d)
    WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
      AND ce.status = 'confirmed'
      AND (ce.rrule IS NOT NULL
           OR (ce.all_day AND d.d = greatest(p_from, ce.start_date))
           OR (NOT ce.all_day AND d.d = (ce.starts_at AT TIME ZONE ce.tz)::date))
  ), occ AS (
    SELECT cand.*,
      CASE WHEN at IS NULL THEN ev_day ELSE (at AT TIME ZONE p_tz)::date END AS on_day
    FROM cand
  ), placed AS (
    SELECT * FROM occ WHERE on_day BETWEEN p_from AND p_to
  ), mine AS (
    SELECT on_day, at FROM placed
    WHERE p_user = ANY (participant_ids) AND (visibility = 'shared' OR created_by = p_user)
  ), summary AS (
    SELECT p_from AS on_day, NULL::timestamptz AS at, 0 AS ord,
      s.n || CASE WHEN s.n = 1 THEN ' plan' ELSE ' plans' END
          || CASE WHEN p_week THEN ' this week' ELSE ' today' END
          || CASE
               WHEN p_week THEN CASE WHEN s.n = 1 THEN ': ' ELSE ', first ' END
                    || to_char(s.f_day, 'Dy')
                    || coalesce(' ' || to_char(s.f_at AT TIME ZONE p_tz, 'HH24:MI'), '')
               WHEN s.f_at IS NULL THEN ''
               ELSE CASE WHEN s.n = 1 THEN ' at ' ELSE ', first at ' END
                    || to_char(s.f_at AT TIME ZONE p_tz, 'HH24:MI')
             END AS line
    FROM (SELECT count(*) AS n,
                 (array_agg(on_day ORDER BY on_day, at NULLS FIRST))[1] AS f_day,
                 (array_agg(at ORDER BY on_day, at NULLS FIRST))[1] AS f_at
          FROM mine) s
    WHERE s.n > 0
  ), big AS (
    SELECT on_day, at, 1 AS ord,
      CASE WHEN p_week THEN to_char(on_day, 'Dy') || ': ' ELSE '' END
      || public.together_name(created_by) || '''s big day'
      || CASE WHEN at IS NULL THEN '' ELSE ' at ' || to_char(at AT TIME ZONE p_tz, 'HH24:MI') END
      || ' — a word of luck?' AS line
    FROM placed
    WHERE p_care AND kind = 'big_day' AND visibility = 'shared'
      AND created_by <> p_user AND NOT (p_user = ANY (participant_ids))
      -- Spec 7 (B9): a quiet person's summary stays plain.
      AND NOT public.user_is_quiet(p_user)
  ), sugg AS (
    SELECT p_from AS on_day, NULL::timestamptz AS at, 2 AS ord, 'A suggestion is waiting for you'::text AS line
    WHERE NOT p_week AND NOT public.user_is_quiet(p_user) AND EXISTS (
      SELECT 1 FROM public.couple_events ce
      WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
        AND ce.status = 'proposed' AND ce.proposed_to = p_user AND ce.proposal_expires_at > now())
  ), lines AS (
    SELECT on_day, at, ord, line FROM summary
    UNION ALL SELECT on_day, at, ord, line FROM big
    UNION ALL SELECT on_day, at, ord, line FROM sugg
  )
  SELECT coalesce(array_agg(line ORDER BY ord, on_day, at NULLS FIRST, line), '{}') FROM lines
$$;

CREATE OR REPLACE FUNCTION public.list_together_memory_prompts(p_relationship_id uuid, p_tz text, p_now timestamptz DEFAULT now())
RETURNS TABLE (event_id uuid, title text, event_day date, ended_at timestamptz, ritual_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE v_me uuid := public.together_actor(p_relationship_id); v_tz text := public.together_safe_tz(p_tz);
BEGIN
  -- Spec 7 (B9): nothing resurfaces at a quiet person.
  IF public.user_is_quiet(v_me) THEN RETURN; END IF;
  RETURN QUERY
  SELECT ce.id, ce.title, public.together_event_day(ce), public.together_event_end(ce, v_tz), ce.ritual_id
  FROM public.couple_events ce
  WHERE ce.relationship_id = p_relationship_id AND public.together_memorable(ce, v_me)
    AND public.together_event_end(ce, v_tz) <= p_now
    AND public.together_event_end(ce, v_tz) > p_now - interval '3 days'
    AND NOT EXISTS (SELECT 1 FROM public.timeline_events te
                    WHERE te.couple_event_id = ce.id AND te.logged_by = v_me AND te.deleted_at IS NULL)
    AND NOT EXISTS (SELECT 1 FROM public.together_memory_dismissals d
                    WHERE d.event_id = ce.id AND d.user_id = v_me)
    AND NOT public.user_hides_date(v_me, public.together_event_day(ce))
  ORDER BY 4 DESC
  LIMIT 3;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_together_on_this_day(p_relationship_id uuid, p_today date)
RETURNS TABLE (item_kind text, item_id uuid, item_date date, title text, note text, event_type text, years_ago int)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  v_me uuid := public.together_actor(p_relationship_id);
  v_m int := extract(month FROM p_today)::int;
  v_d int := extract(day FROM p_today)::int;
  v_y int := extract(year FROM p_today)::int;
  -- Feb 28 of a common year also brings back Feb 29 (R6).
  v_leap_gap boolean := v_m = 2 AND v_d = 28
    AND extract(day FROM make_date(v_y, 3, 1) - 1)::int = 28;
BEGIN
  IF p_today IS NULL THEN PERFORM public.together_fail('invalid_input'); END IF;
  -- Spec 7 (B9): nothing resurfaces at a quiet person.
  IF public.user_is_quiet(v_me) THEN RETURN; END IF;
  RETURN QUERY
  WITH moments AS (
    SELECT 'moment'::text AS k, te.id, te.occurred_at AS d, te.title AS t, te.note AS n, te.event_type AS et
    FROM public.timeline_events te
    WHERE te.relationship_id = p_relationship_id AND te.deleted_at IS NULL
      AND te.event_type <> 'conflict'
      AND (te.visibility = 'shared' OR te.logged_by = v_me)
  ), events AS (
    SELECT 'event'::text AS k, ce.id, public.together_event_day(ce) AS d, ce.title AS t, NULL::text AS n, NULL::text AS et
    FROM public.couple_events ce
    WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
      AND ce.status = 'confirmed' AND ce.visibility = 'shared' AND ce.rrule IS NULL
      -- an event that has its own memory shows as that memory
      AND NOT EXISTS (SELECT 1 FROM public.timeline_events te
                      WHERE te.couple_event_id = ce.id AND te.deleted_at IS NULL
                        AND (te.visibility = 'shared' OR te.logged_by = v_me))
  )
  SELECT x.k, x.id, x.d, x.t, x.n, x.et, v_y - extract(year FROM x.d)::int
  FROM (SELECT * FROM moments UNION ALL SELECT * FROM events) x
  WHERE extract(year FROM x.d)::int < v_y
    AND NOT public.user_hides_date(v_me, x.d)
    AND ((extract(month FROM x.d)::int = v_m AND extract(day FROM x.d)::int = v_d)
         OR (v_leap_gap AND extract(month FROM x.d)::int = 2 AND extract(day FROM x.d)::int = 29))
  ORDER BY x.d DESC, x.t
  LIMIT 5;
END;
$$;
