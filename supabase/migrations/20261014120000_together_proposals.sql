-- Together Phase 2a: proposals ("Fri or Sat?"), owner hand-offs, and the
-- "Needs you" read. Everything that puts something on the partner is a
-- proposal they answer (spec §3.4). Pushes here are partner-initiated (D9).

ALTER TABLE public.couple_events
  ADD COLUMN decision_note text CHECK (decision_note IS NULL OR char_length(decision_note) <= 200),
  ADD COLUMN owner_proposed_to uuid,
  ADD COLUMN owner_proposed_at timestamptz;

CREATE TABLE public.couple_event_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.couple_events(id) ON DELETE CASCADE,
  position smallint NOT NULL CHECK (position BETWEEN 1 AND 3),
  all_day boolean NOT NULL,
  start_date date, end_date date, starts_at timestamptz, ends_at timestamptz,
  UNIQUE (event_id, position),
  CONSTRAINT couple_event_options_when CHECK (
    (all_day AND start_date IS NOT NULL AND starts_at IS NULL AND ends_at IS NULL
       AND (end_date IS NULL OR end_date >= start_date))
    OR (NOT all_day AND starts_at IS NOT NULL AND start_date IS NULL AND end_date IS NULL
       AND (ends_at IS NULL OR ends_at >= starts_at)))
);
ALTER TABLE public.couple_event_options ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.couple_event_options FROM PUBLIC, anon, authenticated;

-- One push to one person, idempotent per key.
CREATE FUNCTION public.together_push(p_user uuid, p_type text, p_title text, p_body text,
  p_event public.couple_events, p_key text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.scheduled_notifications
    (user_id, notification_type, scheduled_for, status, metadata, source_key)
  VALUES (p_user, 'immediate', now(), 'pending',
    jsonb_build_object('type', p_type, 'title', p_title, 'body', left(p_body, 160),
      'event_id', p_event.id, 'relationship_id', p_event.relationship_id), p_key)
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING
$$;
REVOKE ALL ON FUNCTION public.together_push(uuid, text, text, text, public.couple_events, text) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.together_name(p_user uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT nullif(btrim(display_name), '') FROM public.users WHERE id = p_user), 'Your partner')
$$;
REVOKE ALL ON FUNCTION public.together_name(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.together_partner(p_relationship_id uuid, p_me uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN r.user_a = p_me THEN r.user_b ELSE r.user_a END
  FROM public.relationships r WHERE r.id = p_relationship_id
$$;
REVOKE ALL ON FUNCTION public.together_partner(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.propose_couple_event(p_relationship_id uuid, p_event jsonb, p_options jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor uuid := public.together_actor(p_relationship_id);
  v_partner uuid := public.together_partner(p_relationship_id, v_actor);
  e public.together_event_input;
  v_first jsonb;
  v_id uuid;
  v_row public.couple_events;
  v_i int := 0;
  v_opt jsonb;
BEGIN
  BEGIN
    e := jsonb_populate_record(NULL::public.together_event_input, p_event);
  EXCEPTION WHEN OTHERS THEN PERFORM public.together_fail('invalid_input');
  END;
  IF v_partner IS NULL OR p_options IS NULL OR jsonb_typeof(p_options) <> 'array'
     OR jsonb_array_length(p_options) NOT BETWEEN 1 AND 3
     OR e.rrule IS NOT NULL OR coalesce(e.visibility, 'shared') <> 'shared'
     OR e.participant_ids IS NULL OR NOT (v_partner = ANY (e.participant_ids)) THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  v_first := p_options -> 0;
  e.start_date := (v_first->>'start_date')::date;
  e.end_date := (v_first->>'end_date')::date;
  e.starts_at := (v_first->>'starts_at')::timestamptz;
  e.ends_at := (v_first->>'ends_at')::timestamptz;
  PERFORM public.together_validate_input(p_relationship_id, v_actor, e);
  BEGIN
    INSERT INTO public.couple_events (
      relationship_id, created_by, kind, title, note, location_name, all_day,
      start_date, end_date, starts_at, ends_at, tz, participant_ids, owner_id,
      visibility, remind_offsets_min, status, proposed_to, proposal_expires_at)
    VALUES (p_relationship_id, v_actor, coalesce(e.kind, 'event'), btrim(e.title),
      nullif(btrim(e.note), ''), nullif(btrim(e.location_name), ''), e.all_day,
      e.start_date, e.end_date, e.starts_at, e.ends_at, e.tz, e.participant_ids, e.owner_id,
      'shared', coalesce(e.remind_offsets_min, '{}'), 'proposed', v_partner, now() + interval '7 days')
    RETURNING * INTO v_row;
    FOR v_opt IN SELECT * FROM jsonb_array_elements(p_options) LOOP
      v_i := v_i + 1;
      INSERT INTO public.couple_event_options (event_id, position, all_day, start_date, end_date, starts_at, ends_at)
      VALUES (v_row.id, v_i, e.all_day, (v_opt->>'start_date')::date, (v_opt->>'end_date')::date,
              (v_opt->>'starts_at')::timestamptz, (v_opt->>'ends_at')::timestamptz);
    END LOOP;
  EXCEPTION WHEN check_violation OR not_null_violation OR invalid_datetime_format
            OR datetime_field_overflow OR invalid_text_representation THEN
    PERFORM public.together_fail('invalid_input');
  END;
  PERFORM public.together_push(v_partner, 'together_proposal',
    public.together_name(v_actor) || ' suggested a plan', v_row.title, v_row,
    'together_proposal:' || v_row.id);
  RETURN v_row.id;
END;
$$;

CREATE FUNCTION public.decide_couple_event(p_event_id uuid, p_option_id uuid, p_accept boolean, p_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public.couple_events; v_opt public.couple_event_options; v_me uuid := auth.uid();
BEGIN
  SELECT * INTO v_row FROM public.couple_events WHERE id = p_event_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND OR v_row.status <> 'proposed' OR v_row.proposed_to IS DISTINCT FROM v_me THEN
    PERFORM public.together_fail('not_found');
  END IF;
  PERFORM public.together_actor(v_row.relationship_id);
  IF v_row.proposal_expires_at <= now() THEN PERFORM public.together_fail('expired'); END IF;
  IF p_accept THEN
    SELECT * INTO v_opt FROM public.couple_event_options WHERE id = p_option_id AND event_id = v_row.id;
    IF NOT FOUND THEN PERFORM public.together_fail('invalid_input'); END IF;
    BEGIN
      UPDATE public.couple_events SET
        start_date = v_opt.start_date, end_date = v_opt.end_date,
        starts_at = v_opt.starts_at, ends_at = v_opt.ends_at,
        status = 'confirmed', decided_at = now()
      WHERE id = v_row.id RETURNING * INTO v_row;
    EXCEPTION WHEN check_violation OR not_null_violation THEN
      PERFORM public.together_fail('invalid_input');
    END;
    PERFORM public.together_push(v_row.created_by, 'together_proposal_reply',
      public.together_name(v_me) || ' said yes', v_row.title, v_row, 'together_reply:' || v_row.id);
  ELSE
    IF p_note IS NOT NULL AND char_length(p_note) > 200 THEN PERFORM public.together_fail('invalid_input'); END IF;
    UPDATE public.couple_events SET status = 'cancelled', decided_at = now(),
      decision_note = nullif(btrim(p_note), '')
    WHERE id = v_row.id RETURNING * INTO v_row;
    -- The note travels with the reply, or it would reach no one.
    PERFORM public.together_push(v_row.created_by, 'together_proposal_reply',
      public.together_name(v_me) || ' can''t make it',
      CASE WHEN v_row.decision_note IS NULL THEN v_row.title
           ELSE left(v_row.title, 60) || ': ' || v_row.decision_note END,
      v_row, 'together_reply:' || v_row.id);
  END IF;
END;
$$;

CREATE FUNCTION public.propose_owner_handoff(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public.couple_events := public.together_editable_event(p_event_id);
        v_me uuid := auth.uid(); v_partner uuid;
BEGIN
  v_partner := public.together_partner(v_row.relationship_id, v_me);
  IF v_row.visibility <> 'shared' OR v_partner IS NULL
     OR NOT (v_partner = ANY (v_row.participant_ids)) THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  -- Already asked and not yet answered: asking again sends nothing.
  IF v_row.owner_proposed_to = v_partner THEN RETURN; END IF;
  UPDATE public.couple_events SET owner_proposed_to = v_partner, owner_proposed_at = now()
  WHERE id = v_row.id RETURNING * INTO v_row;
  PERFORM public.together_push(v_partner, 'together_handoff',
    public.together_name(v_me) || ' asked you to take this on', v_row.title, v_row,
    'together_handoff:' || v_row.id || ':' || extract(epoch FROM v_row.owner_proposed_at)::bigint);
END;
$$;

CREATE FUNCTION public.decide_owner_handoff(p_event_id uuid, p_accept boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public.couple_events; v_me uuid := auth.uid(); v_asker uuid;
BEGIN
  SELECT * INTO v_row FROM public.couple_events WHERE id = p_event_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND OR v_row.owner_proposed_to IS DISTINCT FROM v_me OR v_row.visibility <> 'shared'
     OR NOT (v_me = ANY (v_row.participant_ids)) THEN
    PERFORM public.together_fail('not_found');
  END IF;
  PERFORM public.together_actor(v_row.relationship_id);
  v_asker := public.together_partner(v_row.relationship_id, v_me);
  UPDATE public.couple_events SET
    owner_id = CASE WHEN p_accept THEN v_me ELSE owner_id END,
    owner_proposed_to = NULL, owner_proposed_at = NULL
  WHERE id = v_row.id RETURNING * INTO v_row;
  PERFORM public.together_push(v_asker, 'together_handoff_reply',
    CASE WHEN p_accept THEN public.together_name(v_me) || ' is taking care of it'
         ELSE public.together_name(v_me) || ' can''t take it on' END,
    v_row.title, v_row, 'together_handoff_reply:' || v_row.id || ':' || extract(epoch FROM now())::bigint);
END;
$$;

CREATE FUNCTION public.list_together_needs_you(p_relationship_id uuid)
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
  ORDER BY array_position(ARRAY['proposal','handoff','poll','unowned_todo','sent_proposal'], q.need_kind),
           q.due_date NULLS LAST, q.title;
END;
$$;

REVOKE ALL ON FUNCTION public.propose_couple_event(uuid, jsonb, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_couple_event(uuid, uuid, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.propose_owner_handoff(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_owner_handoff(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_needs_you(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.propose_couple_event(uuid, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_couple_event(uuid, uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.propose_owner_handoff(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_owner_handoff(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_needs_you(uuid) TO authenticated;
