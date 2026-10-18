-- Spec 7 (research 06 B9 (c); plan review I2): "Put this away gently".
-- Archives a plan without a sound: no activity bump, its pending countdown
-- pushes cancelled, and out of Recent and the shared calendar (and so the
-- calendar feed). The button lives in Planning (owner list); this is the
-- server side. Grants in 20261018140410.
CREATE OR REPLACE FUNCTION public.put_planning_entry_away(p_entry_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel uuid;
BEGIN
  SELECT e.relationship_id INTO v_rel FROM public.planning_entries e
  WHERE e.id = p_entry_id AND e.deleted_at IS NULL AND NOT e.is_template;
  PERFORM public.planning_v2_actor(v_rel);
  UPDATE public.planning_entries SET status = 'archived' WHERE id = p_entry_id;
  UPDATE public.scheduled_notifications
  SET status = 'cancelled', source_key = NULL, last_error = 'put_away', updated_at = now()
  WHERE status = 'pending' AND metadata->>'type' = 'planning_entry'
    AND metadata->>'entry_id' = p_entry_id::text;
END;
$$;

CREATE OR REPLACE FUNCTION public.together_items_for(p_actor uuid, p_relationship_id uuid, p_start date, p_end date)
 RETURNS TABLE(item_kind text, item_id uuid, item_date date, starts_at timestamp with time zone, ends_at timestamp with time zone, all_day boolean, tz text, title text, participant_ids uuid[], owner_id uuid, created_by uuid, visibility text, status text, source_ref jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := p_actor;
  v_members uuid[];
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_end < p_start THEN PERFORM public.together_fail('range'); END IF;
  SELECT array_remove(ARRAY[r.user_a, r.user_b], NULL) INTO v_members
  FROM public.relationships r WHERE r.id = p_relationship_id;

  RETURN QUERY
  -- 1. Couple events, one row per day they fall on.
  SELECT 'event'::text, ce.id, occ.d,
    CASE WHEN ce.all_day THEN NULL
         WHEN ce.rrule IS NULL THEN ce.starts_at
         ELSE ((occ.d + (ce.starts_at AT TIME ZONE ce.tz)::time) AT TIME ZONE ce.tz) END,
    CASE WHEN ce.all_day OR ce.ends_at IS NULL THEN NULL
         WHEN ce.rrule IS NULL THEN ce.ends_at
         ELSE ((occ.d + (ce.starts_at AT TIME ZONE ce.tz)::time) AT TIME ZONE ce.tz)
              + (ce.ends_at - ce.starts_at) END,
    ce.all_day, ce.tz,
    CASE WHEN ce.visibility = 'busy_only' AND ce.created_by <> v_actor THEN 'Busy' ELSE ce.title END,
    ce.participant_ids, ce.owner_id, ce.created_by, ce.visibility, ce.status,
    -- 'continuation': a later day of a one-off event spanning days; the
    -- client lists it under item_date rather than under starts_at's day.
    CASE WHEN ce.visibility = 'busy_only' AND ce.created_by <> v_actor
      THEN jsonb_build_object('kind', ce.kind, 'continuation', coalesce(occ.d > together_anchor.d, false))
      ELSE jsonb_build_object(
        'kind', ce.kind, 'continuation', coalesce(occ.d > together_anchor.d, false),
        'note', ce.note, 'location_name', ce.location_name,
        'start_date', ce.start_date, 'end_date', ce.end_date,
        'event_starts_at', ce.starts_at, 'event_ends_at', ce.ends_at,
        'rrule', ce.rrule, 'recurrence_until', ce.recurrence_until,
        'remind_offsets_min', to_jsonb(ce.remind_offsets_min),
        'about_member_id', ce.about_member_id, 'planning_entry_id', ce.planning_entry_id,
        'owner_proposed_to', ce.owner_proposed_to)
    END
  FROM public.couple_events ce
  CROSS JOIN LATERAL (SELECT CASE WHEN ce.rrule IS NOT NULL THEN NULL::date
                                  WHEN ce.all_day THEN ce.start_date
                                  ELSE (ce.starts_at AT TIME ZONE ce.tz)::date END AS d) together_anchor
  CROSS JOIN LATERAL public.together_event_dates(ce, p_start, p_end) AS occ(d)
  WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
    -- Proposals are not plans until accepted (Phase 2a R3).
    AND ce.status = 'confirmed'
    AND (ce.visibility <> 'private' OR ce.created_by = v_actor)

  UNION ALL
  -- 2. Moments.
  SELECT 'moment'::text, te.id, te.occurred_at, NULL::timestamptz, NULL::timestamptz,
    true, NULL::text, te.title, ARRAY[te.logged_by], NULL::uuid, te.logged_by,
    te.visibility, 'confirmed'::text,
    jsonb_build_object('event_type', te.event_type, 'mood_score', te.mood_score, 'note', te.note)
  FROM public.timeline_events te
  WHERE te.relationship_id = p_relationship_id AND te.deleted_at IS NULL
    AND te.occurred_at BETWEEN p_start AND p_end
    -- A private conflict is its logger's alone (Phase 4 R7).
    AND (te.visibility = 'shared' OR te.logged_by = v_actor)

  UNION ALL
  -- 3. Reminders (family birthdays included, plan ruling R5).
  SELECT DISTINCT 'reminder'::text, r.id, x.day, NULL::timestamptz, NULL::timestamptz,
    true, NULL::text, r.title, v_members, NULL::uuid, r.created_by,
    'shared'::text, 'confirmed'::text,
    jsonb_build_object('reminder_type', r.reminder_type, 'recurrence', r.recurrence,
      'family_member_id', r.family_member_id,
      'linked_timeline_event_id', r.linked_timeline_event_id, 'note', r.note)
  FROM public.reminders r
  CROSS JOIN LATERAL (SELECT (r.remind_at AT TIME ZONE 'UTC')::date AS on_day) rd
  CROSS JOIN LATERAL (
    SELECT CASE WHEN r.recurrence = 'yearly' THEN
             make_date(y, extract(month FROM rd.on_day)::int,
               least(extract(day FROM rd.on_day)::int,
                     public.together_last_day(make_date(y, extract(month FROM rd.on_day)::int, 1))))
           ELSE rd.on_day END AS day
    FROM generate_series(extract(year FROM p_start)::int, extract(year FROM p_end)::int) AS y
  ) x
  WHERE r.relationship_id = p_relationship_id
    AND x.day BETWEEN p_start AND p_end

  UNION ALL
  -- 4. Planning date blocks, one row per day (as list_planning_calendar_entries).
  SELECT 'planning_date'::text, e.id, d::date, NULL::timestamptz, NULL::timestamptz,
    true, NULL::text, e.title, v_members, NULL::uuid, NULL::uuid,
    'shared'::text, 'confirmed'::text,
    jsonb_build_object('entry_id', e.id)
  FROM public.planning_blocks b
  JOIN public.planning_entries e ON e.id = b.entry_id
  CROSS JOIN LATERAL generate_series(
    greatest(b.date_start, p_start), least(coalesce(b.date_end, b.date_start), p_end), interval '1 day') d
  WHERE b.relationship_id = p_relationship_id AND b.block_type = 'date' AND b.deleted_at IS NULL
    AND b.date_start IS NOT NULL AND b.date_start <= p_end
    AND coalesce(b.date_end, b.date_start) >= p_start
    AND e.deleted_at IS NULL AND NOT e.is_template
    AND e.status <> 'archived'  -- Spec 7 (B9 (c)): put away gently

  UNION ALL
  -- 5. Planning to-dos with a due date.
  SELECT 'planning_item'::text, i.id, i.due_date, NULL::timestamptz, NULL::timestamptz,
    true, NULL::text, coalesce(i.text, ''), v_members, NULL::uuid, NULL::uuid,
    'shared'::text, 'confirmed'::text,
    jsonb_build_object('entry_id', e.id, 'is_complete', i.checked_at IS NOT NULL)
  FROM public.planning_block_items i
  JOIN public.planning_blocks b ON b.id = i.block_id
  JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE i.relationship_id = p_relationship_id AND i.deleted_at IS NULL
    AND i.due_date BETWEEN p_start AND p_end
    AND b.deleted_at IS NULL AND e.deleted_at IS NULL AND NOT e.is_template
    AND e.status <> 'archived';  -- Spec 7 (B9 (c))
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_planning_recent(p_relationship_id uuid, p_cursor_at timestamp with time zone, p_cursor_id uuid, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_limit   int := greatest(1, least(coalesce(p_limit, 30), 100));
  v_entries jsonb;
  v_next    jsonb := 'null'::jsonb;
BEGIN
  PERFORM public.planning_v2_actor(p_relationship_id);
  IF (p_cursor_at IS NULL) <> (p_cursor_id IS NULL) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"cursor"}');
  END IF;

  WITH page AS (
    SELECT e.id, e.last_activity_at, c.id AS category_id, c.name, c.icon, c.color,
           row_number() OVER (ORDER BY e.last_activity_at DESC, e.id DESC) AS rn
    FROM public.planning_entries e
    JOIN public.planning_categories c
      ON c.id = e.category_id AND c.deleted_at IS NULL AND c.hidden_at IS NULL
    WHERE e.relationship_id = p_relationship_id
      AND NOT e.is_template AND e.deleted_at IS NULL
      AND e.status <> 'archived'  -- Spec 7 (B9 (c)): put away gently
      AND (p_cursor_at IS NULL OR (e.last_activity_at, e.id) < (p_cursor_at, p_cursor_id))
    ORDER BY e.last_activity_at DESC, e.id DESC
    LIMIT v_limit + 1
  )
  SELECT
    coalesce(jsonb_agg(
      public.planning_v2_entry_summary(p.id) || jsonb_build_object('category', jsonb_build_object(
        'id', p.category_id, 'name', p.name, 'icon', p.icon, 'color', p.color))
      ORDER BY p.rn) FILTER (WHERE p.rn <= v_limit), '[]'::jsonb),
    CASE WHEN max(p.rn) > v_limit THEN
      (SELECT jsonb_build_object('at', q.last_activity_at, 'id', q.id) FROM page q WHERE q.rn = v_limit)
    ELSE 'null'::jsonb END
  INTO v_entries, v_next
  FROM page p;

  RETURN jsonb_build_object('entries', v_entries, 'next_cursor', coalesce(v_next, 'null'::jsonb));
END;
$function$;
