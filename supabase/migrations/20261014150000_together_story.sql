-- Together Phase 4: the story layer (spec §6.3; plan R2–R9).

-- A memory points at the event it remembers; each partner can add their own (R3).
ALTER TABLE public.timeline_events
  ADD COLUMN couple_event_id uuid REFERENCES public.couple_events(id) ON DELETE SET NULL;
CREATE INDEX idx_timeline_couple_event ON public.timeline_events (couple_event_id)
  WHERE couple_event_id IS NOT NULL AND deleted_at IS NULL;

-- "Not now" on a memory prompt: per person, for good (R4).
CREATE TABLE public.together_memory_dismissals (
  event_id uuid NOT NULL REFERENCES public.couple_events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, user_id)
);
ALTER TABLE public.together_memory_dismissals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.together_memory_dismissals FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.together_safe_tz(p_tz text) RETURNS text
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_tz) THEN p_tz ELSE 'UTC' END
$$;

-- The day an event happened, in its own zone.
CREATE FUNCTION public.together_event_day(e public.couple_events) RETURNS date
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE WHEN e.all_day THEN e.start_date ELSE (e.starts_at AT TIME ZONE e.tz)::date END
$$;

-- When an event is over: timed → its end (or an hour after it starts);
-- all-day → midnight after its last day, in the viewer's zone.
CREATE FUNCTION public.together_event_end(e public.couple_events, p_tz text) RETURNS timestamptz
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE WHEN e.all_day
    THEN (coalesce(e.end_date, e.start_date) + 1)::timestamp AT TIME ZONE p_tz
    ELSE coalesce(e.ends_at, e.starts_at + interval '1 hour') END
$$;
REVOKE ALL ON FUNCTION public.together_safe_tz(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.together_event_day(public.couple_events) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.together_event_end(public.couple_events, text) FROM PUBLIC, anon, authenticated;

-- A lived, shared event of both of ours that I'm in (R4).
CREATE FUNCTION public.together_memorable(e public.couple_events, p_me uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT e.deleted_at IS NULL AND e.status = 'confirmed' AND e.visibility = 'shared'
     AND e.rrule IS NULL AND cardinality(e.participant_ids) = 2 AND p_me = ANY (e.participant_ids)
$$;
REVOKE ALL ON FUNCTION public.together_memorable(public.couple_events, uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.add_event_memory(p_event_id uuid, p_line text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.couple_events; v_me uuid; v_line text := btrim(p_line); v_id uuid;
BEGIN
  SELECT * INTO v FROM public.couple_events WHERE id = p_event_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.together_fail('not_found'); END IF;
  v_me := public.together_actor(v.relationship_id);
  -- Only an event of both of ours (the prompt's rule, R4).
  IF v.status <> 'confirmed' OR v.visibility <> 'shared' OR NOT (v_me = ANY (v.participant_ids))
     OR cardinality(v.participant_ids) <> 2 THEN
    PERFORM public.together_fail('not_found');
  END IF;
  -- A repeating event has no single day to remember (it would land on its first week).
  IF v.rrule IS NOT NULL THEN PERFORM public.together_fail('invalid_input'); END IF;
  -- A memory is of something that has begun (a day's grace for all-day across zones).
  IF (v.all_day AND v.start_date > current_date + 1) OR (NOT v.all_day AND v.starts_at > now()) THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  IF v_line IS NULL OR v_line = '' OR char_length(v_line) > 300 THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, note, occurred_at, couple_event_id)
  VALUES (v.relationship_id, v_me, 'highlight', left(btrim(v.title), 80), v_line,
          public.together_event_day(v), v.id)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.dismiss_memory_prompt(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.couple_events; v_me uuid;
BEGIN
  SELECT * INTO v FROM public.couple_events WHERE id = p_event_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.together_fail('not_found'); END IF;
  v_me := public.together_actor(v.relationship_id);
  IF NOT (v_me = ANY (v.participant_ids)) THEN PERFORM public.together_fail('not_found'); END IF;
  INSERT INTO public.together_memory_dismissals (event_id, user_id) VALUES (v.id, v_me)
  ON CONFLICT DO NOTHING;
END;
$$;

CREATE FUNCTION public.list_together_memory_prompts(p_relationship_id uuid, p_tz text, p_now timestamptz DEFAULT now())
RETURNS TABLE (event_id uuid, title text, event_day date, ended_at timestamptz, ritual_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE v_me uuid := public.together_actor(p_relationship_id); v_tz text := public.together_safe_tz(p_tz);
BEGIN
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
  ORDER BY 4 DESC
  LIMIT 3;
END;
$$;

CREATE FUNCTION public.list_together_on_this_day(p_relationship_id uuid, p_today date)
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
    AND ((extract(month FROM x.d)::int = v_m AND extract(day FROM x.d)::int = v_d)
         OR (v_leap_gap AND extract(month FROM x.d)::int = 2 AND extract(day FROM x.d)::int = 29))
  ORDER BY x.d DESC, x.t
  LIMIT 5;
END;
$$;

CREATE FUNCTION public.list_together_ritual_memories(p_ritual_id uuid)
RETURNS TABLE (moment_id uuid, occurred_at date, title text, note text, logged_by uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE v public.couple_rituals := public.together_ritual_row(p_ritual_id); v_me uuid := auth.uid();
BEGIN
  RETURN QUERY
  SELECT te.id, te.occurred_at, te.title, te.note, te.logged_by
  FROM public.timeline_events te
  JOIN public.couple_events ce ON ce.id = te.couple_event_id
  WHERE ce.ritual_id = v.id AND te.relationship_id = v.relationship_id AND te.deleted_at IS NULL
    AND (te.visibility = 'shared' OR te.logged_by = v_me)
  ORDER BY te.occurred_at DESC, te.created_at DESC
  LIMIT 20;
END;
$$;

CREATE FUNCTION public.list_together_moments(p_relationship_id uuid,
  p_before_date date DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit int DEFAULT 30)
RETURNS SETOF public.timeline_events
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.together_actor(p_relationship_id);
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
     OR (p_before_date IS NULL) <> (p_before_id IS NULL) THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  RETURN QUERY
  SELECT te.* FROM public.timeline_events te
  WHERE te.relationship_id = p_relationship_id AND te.deleted_at IS NULL
    AND (te.visibility = 'shared' OR te.logged_by = v_me)
    AND (p_before_date IS NULL OR (te.occurred_at, te.id) < (p_before_date, p_before_id))
  ORDER BY te.occurred_at DESC, te.id DESC
  LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.add_event_memory(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.dismiss_memory_prompt(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_memory_prompts(uuid, text, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_on_this_day(uuid, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_ritual_memories(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_moments(uuid, date, uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_event_memory(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dismiss_memory_prompt(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_memory_prompts(uuid, text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_on_this_day(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_ritual_memories(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_moments(uuid, date, uuid, int) TO authenticated;
