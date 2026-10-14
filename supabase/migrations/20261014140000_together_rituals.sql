-- Together Phase 3: rituals of connection (spec §6.2, D8; plan R1–R6).
-- Agreed once; weekly occurrences appear by themselves; skipping is free;
-- no counters of any kind.

ALTER TABLE public.couple_events ADD COLUMN ritual_date date;
CREATE UNIQUE INDEX couple_events_ritual_week
  ON public.couple_events (ritual_id, ritual_date)
  WHERE ritual_id IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE public.couple_rituals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  template text NOT NULL DEFAULT 'custom' CHECK (char_length(template) BETWEEN 1 AND 40),
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 80),
  cadence text NOT NULL CHECK (cadence IN ('weekly', 'fortnightly')),
  weekday smallint NOT NULL CHECK (weekday BETWEEN 1 AND 7),
  local_time time NOT NULL,
  duration_min int NOT NULL CHECK (duration_min BETWEEN 10 AND 480),
  tz text NOT NULL CHECK (char_length(tz) BETWEEN 1 AND 64),
  anchor_date date NOT NULL DEFAULT current_date,
  status text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'active', 'paused', 'ended')),
  proposed_to uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_couple_rituals_relationship ON public.couple_rituals (relationship_id) WHERE status <> 'ended';
ALTER TABLE public.couple_rituals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.couple_rituals FROM PUBLIC, anon, authenticated;
CREATE TRIGGER set_couple_rituals_updated_at BEFORE UPDATE ON public.couple_rituals
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS trigger_together_signal_rituals ON public.couple_rituals;
CREATE TRIGGER trigger_together_signal_rituals AFTER INSERT OR UPDATE OR DELETE ON public.couple_rituals
  FOR EACH ROW EXECUTE FUNCTION public.bump_together_signal();

-- Validated ritual fields from JSON (invalid input → together:invalid_input).
CREATE FUNCTION public.together_ritual_fields(p jsonb,
  OUT o_title text, OUT o_template text, OUT o_cadence text, OUT o_weekday smallint,
  OUT o_time time, OUT o_duration int, OUT o_tz text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  BEGIN
    o_title := btrim(p->>'title');
    o_template := coalesce(nullif(btrim(p->>'template'), ''), 'custom');
    o_cadence := p->>'cadence';
    o_weekday := (p->>'weekday')::smallint;
    o_time := (p->>'local_time')::time;
    o_duration := (p->>'duration_min')::int;
    o_tz := p->>'tz';
  EXCEPTION WHEN OTHERS THEN PERFORM public.together_fail('invalid_input');
  END;
  IF o_title IS NULL OR o_title = '' OR char_length(o_title) > 80
     OR o_cadence IS NULL OR o_cadence NOT IN ('weekly', 'fortnightly')
     OR o_weekday IS NULL OR o_weekday NOT BETWEEN 1 AND 7
     OR o_time IS NULL OR o_duration IS NULL OR o_duration NOT BETWEEN 10 AND 480
     OR o_tz IS NULL OR NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = o_tz) THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.together_ritual_fields(jsonb) FROM PUBLIC, anon, authenticated;

-- Keep the next 14 days of a ritual's weeks as confirmed shared events.
CREATE FUNCTION public.together_ensure_ritual_occurrences(p_now timestamptz DEFAULT now(), p_ritual_id uuid DEFAULT NULL)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  INSERT INTO public.couple_events (
    relationship_id, created_by, kind, title, all_day, starts_at, ends_at, tz,
    participant_ids, visibility, status, ritual_id, ritual_date)
  SELECT cr.relationship_id, cr.created_by, 'ritual_occurrence', cr.title, false,
    (d.d::date + cr.local_time) AT TIME ZONE cr.tz,
    ((d.d::date + cr.local_time) AT TIME ZONE cr.tz) + make_interval(mins => cr.duration_min),
    cr.tz, array_remove(ARRAY[r.user_a, r.user_b], NULL), 'shared', 'confirmed', cr.id, d.d::date
  FROM public.couple_rituals cr
  JOIN public.relationships r ON r.id = cr.relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
  -- generate_series(date, date, interval) yields timestamptz: every use casts
  -- back to date so local_time is read as wall time in the ritual's zone.
  CROSS JOIN LATERAL generate_series(
    greatest((p_now AT TIME ZONE cr.tz)::date, cr.anchor_date),
    (p_now AT TIME ZONE cr.tz)::date + 13, interval '1 day') AS d(d)
  WHERE cr.status = 'active' AND (p_ritual_id IS NULL OR cr.id = p_ritual_id)
    AND extract(isodow FROM d.d::date)::int = cr.weekday
    AND (cr.cadence = 'weekly'
         OR ((d.d::date - (cr.anchor_date - (extract(isodow FROM cr.anchor_date)::int - 1))) / 7) % 2 = 0)
    -- not in the past: a week whose start already went by isn't created
    AND (d.d::date + cr.local_time) AT TIME ZONE cr.tz > p_now
  ON CONFLICT (ritual_id, ritual_date) WHERE ritual_id IS NOT NULL AND deleted_at IS NULL DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.together_ensure_ritual_occurrences(timestamptz, uuid) FROM PUBLIC, anon, authenticated;

-- Future weeks (not skipped ones) go away, so the next ensure lays them out afresh.
CREATE FUNCTION public.together_clear_future_weeks(p_ritual_id uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.couple_events SET deleted_at = now()
  WHERE ritual_id = p_ritual_id AND deleted_at IS NULL AND status = 'confirmed' AND starts_at > now()
$$;
REVOKE ALL ON FUNCTION public.together_clear_future_weeks(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.together_ritual_row(p_ritual_id uuid) RETURNS public.couple_rituals
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.couple_rituals;
BEGIN
  SELECT * INTO v FROM public.couple_rituals WHERE id = p_ritual_id;
  IF NOT FOUND THEN PERFORM public.together_fail('not_found'); END IF;
  PERFORM public.together_actor(v.relationship_id);
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.together_ritual_row(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.propose_ritual(p_relationship_id uuid, p_ritual jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := public.together_actor(p_relationship_id);
  v_partner uuid := public.together_partner(p_relationship_id, v_me);
  f record;
  v public.couple_rituals;
BEGIN
  IF v_partner IS NULL THEN PERFORM public.together_fail('invalid_input'); END IF;
  SELECT * INTO f FROM public.together_ritual_fields(p_ritual);
  INSERT INTO public.couple_rituals (relationship_id, created_by, template, title, cadence, weekday,
    local_time, duration_min, tz, status, proposed_to)
  VALUES (p_relationship_id, v_me, f.o_template, f.o_title, f.o_cadence, f.o_weekday,
    f.o_time, f.o_duration, f.o_tz, 'proposed', v_partner)
  RETURNING * INTO v;
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key)
  VALUES (v_partner, 'immediate', now(), 'pending',
    jsonb_build_object('type', 'together_ritual', 'relationship_id', p_relationship_id,
      'title', public.together_name(v_me) || ' suggested a ritual', 'body', v.title),
    'together_ritual:' || v.id)
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  RETURN v.id;
END;
$$;

CREATE FUNCTION public.decide_ritual(p_ritual_id uuid, p_accept boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.couple_rituals; v_me uuid := auth.uid();
BEGIN
  SELECT * INTO v FROM public.couple_rituals WHERE id = p_ritual_id FOR UPDATE;
  IF NOT FOUND OR v.status <> 'proposed' OR v.proposed_to IS DISTINCT FROM v_me THEN
    PERFORM public.together_fail('not_found');
  END IF;
  PERFORM public.together_actor(v.relationship_id);
  UPDATE public.couple_rituals
  SET status = CASE WHEN p_accept THEN 'active' ELSE 'ended' END,
      proposed_to = NULL, anchor_date = (now() AT TIME ZONE v.tz)::date
  WHERE id = v.id;
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key)
  VALUES (v.created_by, 'immediate', now(), 'pending',
    jsonb_build_object('type', 'together_ritual_reply', 'relationship_id', v.relationship_id,
      'title', CASE WHEN p_accept THEN public.together_name(v_me) || ' is in'
                    ELSE public.together_name(v_me) || ' would rather not, for now' END,
      'body', v.title),
    'together_ritual_reply:' || v.id)
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  IF p_accept THEN PERFORM public.together_ensure_ritual_occurrences(now(), v.id); END IF;
END;
$$;

CREATE FUNCTION public.update_ritual(p_ritual_id uuid, p_ritual jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.couple_rituals := public.together_ritual_row(p_ritual_id); f record;
BEGIN
  IF v.status NOT IN ('active', 'paused') THEN PERFORM public.together_fail('not_found'); END IF;
  SELECT * INTO f FROM public.together_ritual_fields(p_ritual || jsonb_build_object('template', v.template));
  UPDATE public.couple_rituals SET title = f.o_title, cadence = f.o_cadence, weekday = f.o_weekday,
    local_time = f.o_time, duration_min = f.o_duration, tz = f.o_tz,
    -- a retime keeps the fortnight's phase; a new cadence starts from this week
    anchor_date = CASE WHEN f.o_cadence = v.cadence THEN v.anchor_date
                       ELSE (now() AT TIME ZONE f.o_tz)::date END
  WHERE id = v.id;
  PERFORM public.together_clear_future_weeks(v.id);
  PERFORM public.together_ensure_ritual_occurrences(now(), v.id);
END;
$$;

CREATE FUNCTION public.set_ritual_status(p_ritual_id uuid, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.couple_rituals := public.together_ritual_row(p_ritual_id);
BEGIN
  IF p_status NOT IN ('active', 'paused', 'ended') OR v.status = 'ended'
     -- a pending suggestion: only its proposer can withdraw it (decline is decide_ritual)
     OR (v.status = 'proposed' AND (p_status <> 'ended' OR v.created_by IS DISTINCT FROM auth.uid())) THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  UPDATE public.couple_rituals SET status = p_status, proposed_to = NULL WHERE id = v.id;
  IF p_status = 'active' THEN
    PERFORM public.together_ensure_ritual_occurrences(now(), v.id);
  ELSE
    PERFORM public.together_clear_future_weeks(v.id);
  END IF;
END;
$$;

CREATE FUNCTION public.skip_ritual_occurrence(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.couple_events;
BEGIN
  SELECT * INTO v FROM public.couple_events WHERE id = p_event_id AND deleted_at IS NULL;
  IF NOT FOUND OR v.kind <> 'ritual_occurrence' OR v.status <> 'confirmed' THEN
    PERFORM public.together_fail('not_found');
  END IF;
  PERFORM public.together_actor(v.relationship_id);
  UPDATE public.couple_events SET status = 'cancelled' WHERE id = v.id;
END;
$$;

CREATE FUNCTION public.list_together_rituals(p_relationship_id uuid)
RETURNS TABLE (ritual_id uuid, template text, title text, cadence text, weekday int,
  local_time text, duration_min int, tz text, status text, created_by uuid,
  proposed_to uuid, next_event_id uuid, next_starts_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.together_actor(p_relationship_id);
  RETURN QUERY
  SELECT cr.id, cr.template, cr.title, cr.cadence, cr.weekday::int,
    to_char(cr.local_time, 'HH24:MI'), cr.duration_min, cr.tz, cr.status, cr.created_by, cr.proposed_to,
    n.id, n.starts_at
  FROM public.couple_rituals cr
  LEFT JOIN LATERAL (
    SELECT ce.id, ce.starts_at FROM public.couple_events ce
    WHERE ce.ritual_id = cr.id AND ce.deleted_at IS NULL AND ce.status = 'confirmed'
      AND coalesce(ce.ends_at, ce.starts_at) > now()
    ORDER BY ce.starts_at LIMIT 1
  ) n ON true
  WHERE cr.relationship_id = p_relationship_id AND cr.status <> 'ended'
  ORDER BY (cr.status = 'proposed') DESC, n.starts_at NULLS LAST, cr.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.propose_ritual(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_ritual(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_ritual(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_ritual_status(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.skip_ritual_occurrence(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_rituals(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.propose_ritual(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_ritual(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_ritual(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_ritual_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.skip_ritual_occurrence(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_rituals(uuid) TO authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'together_rituals';
END;
$$;
SELECT cron.schedule('together_rituals', '15 3 * * *', $$ SELECT public.together_ensure_ritual_occurrences(); $$);

-- "Needs you" now includes ritual suggestions (Phase 3): the 2a function
-- re-created with one more branch, unchanged otherwise.
CREATE OR REPLACE FUNCTION public.list_together_needs_you(p_relationship_id uuid)
RETURNS TABLE (need_kind text, item_id uuid, title text, due_date date, created_by uuid, detail jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := public.together_actor(p_relationship_id);
  v_today date := (now() AT TIME ZONE coalesce(
    (SELECT s.timezone FROM public.planning_member_settings s
     WHERE s.relationship_id = p_relationship_id AND s.user_id = v_me), 'UTC'))::date;
BEGIN
  RETURN QUERY
  SELECT q.need_kind, q.item_id, q.title, q.due_date, q.created_by, q.detail FROM (
  SELECT CASE WHEN ce.proposed_to = v_me THEN 'proposal' ELSE 'sent_proposal' END AS need_kind,
    ce.id AS item_id, ce.title AS title, NULL::date AS due_date, ce.created_by AS created_by,
    jsonb_build_object(
      'all_day', ce.all_day, 'tz', ce.tz, 'note', ce.note,
      'proposed_to', ce.proposed_to, 'expires_at', ce.proposal_expires_at,
      'options', (SELECT coalesce(jsonb_agg(jsonb_build_object(
          'id', o.id, 'position', o.position, 'start_date', o.start_date, 'end_date', o.end_date,
          'starts_at', o.starts_at, 'ends_at', o.ends_at) ORDER BY o.position), '[]'::jsonb)
        FROM public.couple_event_options o WHERE o.event_id = ce.id)) AS detail
  FROM public.couple_events ce
  WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
    AND ce.status = 'proposed' AND ce.proposal_expires_at > now()
    AND (ce.proposed_to = v_me OR ce.created_by = v_me)

  UNION ALL
  SELECT 'ritual_proposal'::text, cr.id, cr.title, NULL::date, cr.created_by,
    jsonb_build_object('template', cr.template, 'cadence', cr.cadence, 'weekday', cr.weekday,
                       'local_time', to_char(cr.local_time, 'HH24:MI'), 'duration_min', cr.duration_min,
                       'tz', cr.tz)
  FROM public.couple_rituals cr
  WHERE cr.relationship_id = p_relationship_id AND cr.status = 'proposed' AND cr.proposed_to = v_me

  UNION ALL
  SELECT 'handoff'::text, ce.id, ce.title, ce.start_date, ce.created_by,
    jsonb_build_object('kind', ce.kind, 'starts_at', ce.starts_at, 'all_day', ce.all_day)
  FROM public.couple_events ce
  WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
    AND ce.owner_proposed_to = v_me AND ce.visibility = 'shared'

  UNION ALL
  SELECT 'unowned_todo'::text, i.id, coalesce(i.text, ''), i.due_date, NULL::uuid,
    jsonb_build_object('entry_id', e.id, 'entry_title', e.title)
  FROM public.planning_block_items i
  JOIN public.planning_blocks b ON b.id = i.block_id
  JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE i.relationship_id = p_relationship_id AND i.deleted_at IS NULL
    AND i.checked_at IS NULL AND i.assigned_to IS NULL
    AND i.due_date BETWEEN v_today AND v_today + 7
    AND b.deleted_at IS NULL AND b.block_type = 'checklist'
    AND e.deleted_at IS NULL AND NOT e.is_template

  UNION ALL
  SELECT 'poll'::text, b.id, e.title, NULL::date, NULL::uuid,
    jsonb_build_object('entry_id', e.id)
  FROM public.planning_blocks b
  JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE b.relationship_id = p_relationship_id AND b.block_type = 'date_poll'
    AND b.deleted_at IS NULL AND e.deleted_at IS NULL AND NOT e.is_template
    AND EXISTS (SELECT 1 FROM public.planning_block_items i
                WHERE i.block_id = b.id AND i.deleted_at IS NULL)
    AND NOT EXISTS (SELECT 1 FROM public.planning_block_items i
                    JOIN public.planning_poll_votes v ON v.item_id = i.id
                    WHERE i.block_id = b.id AND i.deleted_at IS NULL AND v.user_id = v_me)
  ) q
  -- A stable order, so the same three sit on top everywhere.
  ORDER BY array_position(ARRAY['proposal','ritual_proposal','handoff','poll','unowned_todo','sent_proposal'], q.need_kind),
           q.due_date NULLS LAST, q.title;
END;
$$;
REVOKE ALL ON FUNCTION public.list_together_needs_you(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_together_needs_you(uuid) TO authenticated;
