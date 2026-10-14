-- Together's single read (spec §5.5). Recurrence is expanded here so the
-- app, alarms and (later) the ICS feed agree. RRULE subset per plan
-- ruling R3; month-end clamping per R4. Dates are in the event's zone.

CREATE FUNCTION public.together_last_day(d date) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT extract(day FROM (date_trunc('month', d) + interval '1 month - 1 day'))::int
$$;

CREATE FUNCTION public.together_event_dates(e public.couple_events, p_start date, p_end date)
RETURNS SETOF date LANGUAGE sql STABLE AS $$
  WITH a AS (
    SELECT
      CASE WHEN e.all_day THEN e.start_date
           ELSE (e.starts_at AT TIME ZONE e.tz)::date END AS anchor,
      CASE WHEN e.all_day THEN coalesce(e.end_date, e.start_date)
           ELSE (coalesce(e.ends_at, e.starts_at) AT TIME ZONE e.tz)::date END AS last_day,
      substring(e.rrule FROM 'FREQ=([A-Z]+)') AS freq,
      coalesce(substring(e.rrule FROM 'INTERVAL=([0-9]+)')::int, 1) AS step,
      string_to_array(substring(e.rrule FROM 'BYDAY=([A-Z,]+)'), ',') AS bydays
  )
  SELECT d::date
  FROM a, generate_series(
    greatest(p_start, a.anchor),
    least(p_end, CASE WHEN e.rrule IS NULL THEN a.last_day
                      ELSE coalesce(e.recurrence_until, p_end) END),
    interval '1 day') AS d
  WHERE e.rrule IS NULL
     OR (a.freq = 'DAILY' AND (d::date - a.anchor) % a.step = 0)
     OR (a.freq = 'WEEKLY'
         AND (ARRAY['MO','TU','WE','TH','FR','SA','SU'])[extract(isodow FROM d)::int]
             = ANY (coalesce(a.bydays,
                ARRAY[(ARRAY['MO','TU','WE','TH','FR','SA','SU'])[extract(isodow FROM a.anchor)::int]]))
         AND (((d::date - (extract(isodow FROM d)::int - 1))
               - (a.anchor - (extract(isodow FROM a.anchor)::int - 1))) / 7) % a.step = 0)
     OR (a.freq = 'MONTHLY'
         AND ((extract(year FROM d)::int * 12 + extract(month FROM d)::int)
              - (extract(year FROM a.anchor)::int * 12 + extract(month FROM a.anchor)::int)) % a.step = 0
         AND extract(day FROM d)::int
             = least(extract(day FROM a.anchor)::int, public.together_last_day(d::date)))
     OR (a.freq = 'YEARLY'
         AND (extract(year FROM d)::int - extract(year FROM a.anchor)::int) % a.step = 0
         AND extract(month FROM d) = extract(month FROM a.anchor)
         AND extract(day FROM d)::int
             = least(extract(day FROM a.anchor)::int, public.together_last_day(d::date)))
$$;
REVOKE ALL ON FUNCTION public.together_event_dates(public.couple_events, date, date) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.together_items_for(p_actor uuid, p_relationship_id uuid, p_start date, p_end date)
RETURNS TABLE (
  item_kind text, item_id uuid, item_date date, starts_at timestamptz, ends_at timestamptz,
  all_day boolean, tz text, title text, participant_ids uuid[], owner_id uuid,
  created_by uuid, visibility text, status text, source_ref jsonb
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
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
    AND b.deleted_at IS NULL AND e.deleted_at IS NULL AND NOT e.is_template;
END;
$$;
-- Internal: reads as p_actor. Only the member-checked wrapper below and the
-- service-role calendar feed call it (Phase 5).
REVOKE ALL ON FUNCTION public.together_items_for(uuid, uuid, date, date) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.list_together_items(p_relationship_id uuid, p_start date, p_end date)
RETURNS TABLE (
  item_kind text, item_id uuid, item_date date, starts_at timestamptz, ends_at timestamptz,
  all_day boolean, tz text, title text, participant_ids uuid[], owner_id uuid,
  created_by uuid, visibility text, status text, source_ref jsonb
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor uuid := public.together_actor(p_relationship_id);
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_end < p_start OR p_end - p_start > 93 THEN
    PERFORM public.together_fail('range');
  END IF;
  RETURN QUERY SELECT * FROM public.together_items_for(v_actor, p_relationship_id, p_start, p_end);
END;
$$;
REVOKE ALL ON FUNCTION public.list_together_items(uuid, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_together_items(uuid, date, date) TO authenticated;
