-- Bills in Planning (2026-10-18). An expense line can carry an optional due
-- date (save_planning_rich_item / planning_v2_rich_item_fields); it shows on
-- the shared calendar marked as an expense (together_items_for source_ref
-- block_type); "Start the next one" moves a past due date on an expense to
-- its next month (planning_v2_copy_blocks); and the Home & bills starter is
-- an Expenses block instead of a table, so its Budget finally adds the bills
-- up (version 3: unedited templates upgrade, edited ones and plans stay).
-- The replaced functions keep their grants; planning_v2_next_due is
-- internal (revoked below).

-- The same day of the month as p_due, in the first month on or after
-- p_today, clamped to that month's last day (31 Jan -> 28/29 Feb).
CREATE OR REPLACE FUNCTION public.planning_v2_next_due(p_due date, p_today date)
RETURNS date LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
DECLARE
  v_month date := date_trunc('month', p_today)::date;
  v_day   int := extract(day FROM p_due)::int;
  v_try   date;
BEGIN
  IF p_due >= p_today THEN RETURN p_due; END IF;
  LOOP
    v_try := v_month + (least(v_day,
      extract(day FROM (v_month + interval '1 month - 1 day'))::int) - 1);
    EXIT WHEN v_try >= p_today;
    v_month := (v_month + interval '1 month')::date;
  END LOOP;
  RETURN v_try;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_next_due(date, date) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.planning_v2_rich_item_fields(p_block public.planning_blocks, p_fields jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cell    record;
  v_type    text;
  v_ok      boolean;
  v_amount  numeric;
  v_share   numeric;
  v_paid_by uuid;
  v_cur     text;
  v_start   date;
  v_end     date;
BEGIN
  IF p_fields IS NULL OR jsonb_typeof(p_fields) <> 'object' THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"fields"}');
  END IF;
  CASE p_block.block_type
  WHEN 'table' THEN
    IF NOT public.planning_v2_keys_within(p_fields, ARRAY['cells'])
       OR jsonb_typeof(p_fields -> 'cells') IS DISTINCT FROM 'object'
       OR octet_length((p_fields -> 'cells')::text) > 4096 THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"cells"}');
    END IF;
    FOR v_cell IN SELECT key, value FROM jsonb_each(p_fields -> 'cells') LOOP
      SELECT c ->> 'type' INTO v_type FROM jsonb_array_elements(p_block.payload -> 'columns') c
      WHERE c ->> 'key' = v_cell.key;
      IF v_type IS NULL THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"cells"}'); END IF;
      -- Assigned first: PL/pgSQL ends an IF condition at the first THEN.
      v_ok := jsonb_typeof(v_cell.value) = 'null' OR CASE v_type
          WHEN 'text'   THEN jsonb_typeof(v_cell.value) = 'string' AND char_length(v_cell.value #>> '{}') <= 200
          WHEN 'number' THEN jsonb_typeof(v_cell.value) = 'number'
          WHEN 'money'  THEN public.planning_v2_is_int(v_cell.value) AND (v_cell.value #>> '{}')::numeric >= 0
          WHEN 'date'   THEN jsonb_typeof(v_cell.value) = 'string' AND (v_cell.value #>> '{}') ~ '^\d{4}-\d{2}-\d{2}$'
          WHEN 'check'  THEN jsonb_typeof(v_cell.value) = 'boolean'
          ELSE false END;
      IF NOT v_ok THEN
        PERFORM public.planning_v2_fail('invalid_input', jsonb_build_object('field', 'cells', 'column', v_cell.key));
      END IF;
      v_type := NULL;
    END LOOP;
    RETURN jsonb_build_object('cells', p_fields -> 'cells');
  WHEN 'expenses' THEN
    IF NOT public.planning_v2_keys_within(p_fields, ARRAY['label','amount_minor','currency','paid_by','split_share_minor','due_date'])
       OR char_length(btrim(coalesce(p_fields ->> 'label', ''))) NOT BETWEEN 1 AND 120
       OR NOT public.planning_v2_is_int(p_fields -> 'amount_minor') THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"expense"}');
    END IF;
    v_amount := (p_fields ->> 'amount_minor')::numeric;
    IF v_amount < 0 OR v_amount > 1000000000000 THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"amount_minor"}');
    END IF;
    v_cur := coalesce(p_fields ->> 'currency',
      (SELECT currency FROM public.planning_entries WHERE id = p_block.entry_id));
    IF v_cur !~ '^[A-Z]{3}$' THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"currency"}'); END IF;
    IF p_fields ? 'paid_by' AND jsonb_typeof(p_fields -> 'paid_by') <> 'null' THEN
      IF NOT public.planning_v2_is_uuid(p_fields -> 'paid_by') THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"paid_by"}');
      END IF;
      v_paid_by := (p_fields ->> 'paid_by')::uuid;
      IF NOT public.planning_v2_is_member(p_block.relationship_id, v_paid_by) THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"paid_by"}');
      END IF;
    END IF;
    IF p_fields ? 'split_share_minor' AND jsonb_typeof(p_fields -> 'split_share_minor') <> 'null' THEN
      IF NOT public.planning_v2_is_int(p_fields -> 'split_share_minor') THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"split_share_minor"}');
      END IF;
      v_share := (p_fields ->> 'split_share_minor')::numeric;
      IF v_share < 0 OR v_share > v_amount THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"split_share_minor"}');
      END IF;
    END IF;
    -- A bill's due date: optional, a real calendar day. Only an edit that
    -- names it changes it, so an older app's edit keeps the date.
    IF p_fields ? 'due_date' AND jsonb_typeof(p_fields -> 'due_date') <> 'null' THEN
      IF jsonb_typeof(p_fields -> 'due_date') <> 'string'
         OR (p_fields ->> 'due_date') !~ '^\d{4}-\d{2}-\d{2}$' THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"due_date"}');
      END IF;
      BEGIN
        v_start := (p_fields ->> 'due_date')::date;
      EXCEPTION WHEN others THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"due_date"}');
      END;
    END IF;
    RETURN jsonb_build_object('text', btrim(p_fields ->> 'label'), 'amount_minor', v_amount::bigint,
      'currency', v_cur, 'paid_by', v_paid_by, 'split_share_minor', v_share::bigint)
      || CASE WHEN p_fields ? 'due_date' THEN jsonb_build_object('due_date', v_start) ELSE '{}'::jsonb END;
  WHEN 'date_poll' THEN
    IF NOT public.planning_v2_keys_within(p_fields, ARRAY['date_start','date_end','label'])
       OR coalesce(p_fields ->> 'date_start', '') !~ '^\d{4}-\d{2}-\d{2}$'
       OR (p_fields ? 'date_end' AND jsonb_typeof(p_fields -> 'date_end') <> 'null'
           AND coalesce(p_fields ->> 'date_end', '') !~ '^\d{4}-\d{2}-\d{2}$')
       OR (p_fields ? 'label' AND char_length(coalesce(p_fields ->> 'label', '')) > 120) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
    END IF;
    BEGIN
      v_start := (p_fields ->> 'date_start')::date;
      v_end := (p_fields ->> 'date_end')::date;
    EXCEPTION WHEN others THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
    END;
    IF v_end IS NOT NULL AND v_end < v_start THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
    END IF;
    RETURN jsonb_build_object('date_start', v_start, 'date_end', v_end,
      'text', nullif(btrim(coalesce(p_fields ->> 'label', '')), ''));
  WHEN 'progress' THEN
    IF p_block.payload ->> 'mode' <> 'numeric' THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"mode"}');
    END IF;
    IF NOT public.planning_v2_keys_within(p_fields, ARRAY['amount_minor','label'])
       OR NOT public.planning_v2_is_int(p_fields -> 'amount_minor')
       OR (p_fields ? 'label' AND char_length(coalesce(p_fields ->> 'label', '')) > 120) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"amount_minor"}');
    END IF;
    -- Cast only once it is known to be a whole number (M7).
    IF (p_fields ->> 'amount_minor')::numeric NOT BETWEEN 1 AND 1000000000000 THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"amount_minor"}');
    END IF;
    RETURN jsonb_build_object('amount_minor', (p_fields ->> 'amount_minor')::bigint,
      'text', nullif(btrim(coalesce(p_fields ->> 'label', '')), ''));
  ELSE
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}');
  END CASE;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_planning_rich_item(
  p_id uuid, p_block_id uuid, p_version int, p_fields jsonb, p_after_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_block  public.planning_blocks := public.planning_v2_lock_block(p_block_id);
  v_actor  uuid := auth.uid();
  v_row    public.planning_block_items;
  v_cols   jsonb;
  v_before jsonb;
  v_count  int;
  v_limit  record;
BEGIN
  SELECT * INTO v_row FROM public.planning_block_items WHERE id = p_id FOR UPDATE;
  IF FOUND AND v_row.block_id <> p_block_id THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"id"}');
  END IF;
  IF FOUND AND v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF p_version IS NULL AND FOUND THEN
    RETURN public.planning_v2_item_object(p_id);         -- create retried
  END IF;
  IF p_version IS NOT NULL AND NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF p_version IS NOT NULL AND p_version <> v_row.version THEN
    PERFORM public.planning_v2_fail('stale_version', jsonb_build_object('current', public.planning_v2_item_object(p_id)));
  END IF;

  v_cols := public.planning_v2_rich_item_fields(v_block, p_fields);

  IF p_version IS NULL THEN
    v_limit := public.planning_v2_item_limit(v_block.block_type);
    SELECT count(*) INTO v_count FROM public.planning_block_items WHERE block_id = p_block_id AND deleted_at IS NULL;
    IF v_count >= v_limit.max_items THEN
      PERFORM public.planning_v2_fail('limit_reached', jsonb_build_object('limit', v_limit.limit_name));
    END IF;
    INSERT INTO public.planning_block_items (id, relationship_id, block_id, created_by, sort_key, created_at,
      text, amount_minor, currency, paid_by, split_share_minor, cells, date_start, date_end, due_date)
    VALUES (p_id, v_block.relationship_id, p_block_id, v_actor,
      public.planning_v2_key_after_item(p_block_id, p_after_id, p_id), clock_timestamp(),
      v_cols ->> 'text', (v_cols ->> 'amount_minor')::bigint, v_cols ->> 'currency',
      (v_cols ->> 'paid_by')::uuid, (v_cols ->> 'split_share_minor')::bigint, v_cols -> 'cells',
      (v_cols ->> 'date_start')::date, (v_cols ->> 'date_end')::date, (v_cols ->> 'due_date')::date)
    RETURNING * INTO v_row;
    IF char_length(v_row.sort_key) > 32 THEN PERFORM public.planning_v2_rebalance_items(p_block_id); END IF;
    IF v_block.block_type = 'date_poll' THEN PERFORM public.planning_v2_notify_poll(v_block, v_actor); END IF;
  ELSE
    v_before := public.planning_v2_item_object(p_id);
    UPDATE public.planning_block_items SET
      text = CASE WHEN v_cols ? 'text' THEN v_cols ->> 'text' ELSE text END,
      amount_minor = CASE WHEN v_cols ? 'amount_minor' THEN (v_cols ->> 'amount_minor')::bigint ELSE amount_minor END,
      currency = CASE WHEN v_cols ? 'currency' THEN v_cols ->> 'currency' ELSE currency END,
      paid_by = CASE WHEN v_cols ? 'paid_by' THEN (v_cols ->> 'paid_by')::uuid ELSE paid_by END,
      split_share_minor = CASE WHEN v_cols ? 'split_share_minor' THEN (v_cols ->> 'split_share_minor')::bigint ELSE split_share_minor END,
      cells = CASE WHEN v_cols ? 'cells' THEN coalesce(cells, '{}'::jsonb) || (v_cols -> 'cells') ELSE cells END,
      date_start = CASE WHEN v_cols ? 'date_start' THEN (v_cols ->> 'date_start')::date ELSE date_start END,
      date_end = CASE WHEN v_cols ? 'date_end' THEN (v_cols ->> 'date_end')::date ELSE date_end END,
      due_date = CASE WHEN v_cols ? 'due_date' THEN (v_cols ->> 'due_date')::date ELSE due_date END,
      version = version + 1
    WHERE id = p_id;
  END IF;

  IF v_block.block_type = 'expenses' THEN
    PERFORM public.planning_v2_audit_expense(v_block.relationship_id, v_block.entry_id, p_id,
      CASE WHEN p_version IS NULL THEN 'create' ELSE 'update' END, v_before, public.planning_v2_item_object(p_id));
  END IF;
  IF v_block.block_type = 'progress' THEN PERFORM public.planning_v2_maybe_celebrate(v_block.entry_id, v_actor); END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, v_actor);
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_copy_blocks(p_rel uuid, p_src uuid, p_dst uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b       public.planning_blocks;
  v_new     uuid;
  v_payload jsonb;
  v_map     jsonb := '{}'::jsonb;
  v_ref     text;
  v_checks  text[];
  v_tpl     boolean := (SELECT is_template FROM public.planning_entries WHERE id = p_dst);
BEGIN
  FOR v_b IN SELECT * FROM public.planning_blocks
             WHERE entry_id = p_src AND deleted_at IS NULL ORDER BY sort_key, id LOOP
    v_new := gen_random_uuid();
    v_map := v_map || jsonb_build_object(v_b.id::text, v_new::text);
    v_payload := v_b.payload;
    IF v_b.block_type = 'photo' THEN v_payload := v_payload || '{"paths":[]}'::jsonb; END IF;
    IF v_b.block_type = 'link' AND v_payload ? 'preview' THEN
      v_payload := jsonb_set(v_payload, '{preview}', (v_payload -> 'preview') - 'image_path');
    END IF;
    INSERT INTO public.planning_blocks (id, relationship_id, entry_id, created_by, block_type, sort_key,
      payload, plain_text, date_start, date_end, target_minor, target_currency)
    VALUES (v_new, p_rel, p_dst, p_actor, v_b.block_type, v_b.sort_key,
      v_payload, v_b.plain_text, v_b.date_start, v_b.date_end, v_b.target_minor, v_b.target_currency);
    -- Contributions belong to the occasion they were made for.
    CONTINUE WHEN v_b.block_type = 'progress';
    -- So do yes/no cells ("Paid ✓"); the rest of a row is the plan's shape.
    v_checks := CASE WHEN v_b.block_type = 'table' THEN ARRAY(
                  SELECT c ->> 'key' FROM jsonb_array_elements(v_b.payload -> 'columns') c WHERE c ->> 'type' = 'check')
                ELSE '{}'::text[] END;
    INSERT INTO public.planning_block_items (id, relationship_id, block_id, created_by, sort_key, text, section,
      assigned_to, due_date, amount_minor, currency, split_share_minor, date_start, date_end, cells)
    SELECT gen_random_uuid(), p_rel, v_new, p_actor, sort_key, text, section,
      assigned_to,
      -- A bill comes round again: a past due date on an expense moves to the
      -- same day of the first month that isn't past (clamped to its last
      -- day). Anything else keeps its date.
      CASE WHEN v_b.block_type = 'expenses' AND due_date < current_date
           THEN public.planning_v2_next_due(due_date, current_date) ELSE due_date END,
      amount_minor, currency, split_share_minor, date_start, date_end,
      CASE WHEN cells IS NULL THEN NULL ELSE cells - v_checks END
    FROM public.planning_block_items WHERE block_id = v_b.id AND deleted_at IS NULL;
    IF v_b.block_type = 'expenses' AND NOT v_tpl THEN
      PERFORM public.planning_v2_audit_expense(p_rel, p_dst, i.id, 'create', NULL, public.planning_v2_item_object(i.id))
      FROM public.planning_block_items i WHERE i.block_id = v_new;
    END IF;
  END LOOP;
  FOREACH v_ref IN ARRAY ARRAY['date_block_id', 'checklist_block_id'] LOOP
    UPDATE public.planning_blocks d
       SET payload = CASE WHEN v_map ? (d.payload ->> v_ref)
                          THEN jsonb_set(d.payload, ARRAY[v_ref], v_map -> (d.payload ->> v_ref))
                          ELSE d.payload - v_ref END
     WHERE d.entry_id = p_dst AND d.payload ? v_ref;
  END LOOP;
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
    -- block_type: an expense line here is a bill, not a to-do.
    jsonb_build_object('entry_id', e.id, 'is_complete', i.checked_at IS NOT NULL, 'block_type', b.block_type)
  FROM public.planning_block_items i
  JOIN public.planning_blocks b ON b.id = i.block_id
  JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE i.relationship_id = p_relationship_id AND i.deleted_at IS NULL
    AND i.due_date BETWEEN p_start AND p_end
    AND b.deleted_at IS NULL AND e.deleted_at IS NULL AND NOT e.is_template
    AND e.status <> 'archived';  -- Spec 7 (B9 (c))
END;
$function$;

UPDATE public.planning_starter_templates SET version = 3, blocks = jsonb_build_array(
  '{"type":"expenses","payload":{"title":"Bills"},"items":[{"text":"Rent"},{"text":"Electricity"},{"text":"Water"},{"text":"Internet"},{"text":"TV"}]}'::jsonb,
  '{"type":"budget","payload":{"title":"Monthly budget"}}'::jsonb,
  jsonb_build_object('type', 'text', 'payload', jsonb_build_object('delta', jsonb_build_array(
    jsonb_build_object('insert', 'Notes'),
    jsonb_build_object('insert', E'\n', 'attributes', jsonb_build_object('header', 2)),
    jsonb_build_object('insert', E'\n')))))
WHERE seed_key = 'home_bills';
