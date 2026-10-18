-- Tables get a Person column (2026-10-18): a cell is one of the couple, by
-- id, chosen in the row editor like Expenses' "Paid by". Old Bills tables —
-- exactly the columns the Home & bills starter made before v3 — are
-- converted once: "Due day" (a number) becomes a "Due date" this month, and
-- "Paid by" (free text) becomes a Person, matched to a member by name.
-- Replaced functions keep their grants; the converter is internal.

CREATE OR REPLACE FUNCTION public.planning_v2_validate_block(
  p_type text, p_payload jsonb, p_date_start date, p_date_end date
) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_col  jsonb;
  v_keys text[] := '{}';
BEGIN
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}');
  END IF;
  IF octet_length(p_payload::text) > 16384 THEN
    PERFORM public.planning_v2_fail('limit_reached', '{"limit":"payload_bytes"}');
  END IF;
  IF p_type <> 'date' AND (p_date_start IS NOT NULL OR p_date_end IS NOT NULL) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
  END IF;
  IF NOT public.planning_v2_title_ok(p_payload) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"title"}');
  END IF;

  CASE p_type
  WHEN 'text' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['delta']) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}');
    END IF;
    RETURN public.planning_validate_delta(p_payload -> 'delta');
  WHEN 'checklist', 'expenses', 'date_poll', 'dual_clock' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title']) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}');
    END IF;
  WHEN 'budget' THEN
    -- source_block_id: the Expenses or table block it counts (any uuid is
    -- stored; planning_v2_block_computed only follows one in this plan).
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title','source_block_id'])
       OR (p_payload ? 'source_block_id' AND jsonb_typeof(p_payload -> 'source_block_id') <> 'null'
           AND NOT public.planning_v2_is_uuid(p_payload -> 'source_block_id')) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}');
    END IF;
  WHEN 'date' THEN
    -- poll_history is written only by lock_planning_poll.
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title','poll_history'])
       OR (p_payload ? 'poll_history' AND (jsonb_typeof(p_payload -> 'poll_history') <> 'array'
           OR jsonb_array_length(p_payload -> 'poll_history') > 20)) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}');
    END IF;
    IF p_date_end IS NOT NULL AND (p_date_start IS NULL OR p_date_end < p_date_start) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
    END IF;
  WHEN 'countdown' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title','date_block_id'])
       OR (p_payload ? 'date_block_id' AND jsonb_typeof(p_payload -> 'date_block_id') <> 'null'
           AND NOT public.planning_v2_is_uuid(p_payload -> 'date_block_id')) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date_block_id"}');
    END IF;
  WHEN 'progress' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title','mode','unit','checklist_block_id'])
       OR coalesce(p_payload ->> 'mode', '') NOT IN ('numeric', 'checklist')
       OR coalesce(p_payload ->> 'unit', 'count') NOT IN ('count', 'money')
       OR (p_payload ? 'checklist_block_id' AND jsonb_typeof(p_payload -> 'checklist_block_id') <> 'null'
           AND NOT public.planning_v2_is_uuid(p_payload -> 'checklist_block_id')) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"progress"}');
    END IF;
  WHEN 'table' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title','columns'])
       OR jsonb_typeof(p_payload -> 'columns') IS DISTINCT FROM 'array'
       OR jsonb_array_length(p_payload -> 'columns') NOT BETWEEN 1 AND 12 THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"columns"}');
    END IF;
    FOR v_col IN SELECT value FROM jsonb_array_elements(p_payload -> 'columns') LOOP
      IF jsonb_typeof(v_col) <> 'object'
         OR NOT public.planning_v2_keys_within(v_col, ARRAY['key','label','type'])
         OR coalesce(v_col ->> 'key', '') !~ '^c[0-9]{1,2}$'
         OR (v_col ->> 'key') = ANY (v_keys)
         OR char_length(btrim(coalesce(v_col ->> 'label', ''))) NOT BETWEEN 1 AND 40
         OR coalesce(v_col ->> 'type', '') NOT IN ('text','number','money','date','check','person') THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"columns"}');
      END IF;
      v_keys := v_keys || (v_col ->> 'key');
    END LOOP;
  WHEN 'photo' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title','paths'])
       OR (p_payload ? 'paths' AND (jsonb_typeof(p_payload -> 'paths') <> 'array'
           OR jsonb_array_length(p_payload -> 'paths') > 10)) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"paths"}');
    END IF;
  WHEN 'link' THEN
    -- A template's link has only a label until the couple adds the address.
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['url','label','preview'])
       OR (p_payload ? 'url' AND (jsonb_typeof(p_payload -> 'url') <> 'string'
           OR char_length(p_payload ->> 'url') > 2048
           OR (p_payload ->> 'url') !~* '^https?://[^[:space:]]+$'))
       OR (p_payload ? 'label' AND char_length(btrim(coalesce(p_payload ->> 'label', ''))) NOT BETWEEN 1 AND 80) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"url"}');
    END IF;
  WHEN 'place' THEN
    -- A template's place has only a title until the couple picks one.
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title','name','address','lat','lng'])
       OR (p_payload ? 'name' AND char_length(btrim(coalesce(p_payload ->> 'name', ''))) NOT BETWEEN 1 AND 120)
       OR (NOT p_payload ? 'name' AND (p_payload ? 'address' OR p_payload ? 'lat' OR p_payload ? 'lng'))
       OR char_length(coalesce(p_payload ->> 'address', '')) > 300
       OR (p_payload ? 'lat' AND (jsonb_typeof(p_payload -> 'lat') <> 'number'
           OR (p_payload ->> 'lat')::numeric NOT BETWEEN -90 AND 90))
       OR (p_payload ? 'lng' AND (jsonb_typeof(p_payload -> 'lng') <> 'number'
           OR (p_payload ->> 'lng')::numeric NOT BETWEEN -180 AND 180)) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"place"}');
    END IF;
  ELSE
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}');
  END CASE;
  RETURN NULL;
END;
$$;

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
          -- One of the couple, by id.
          WHEN 'person' THEN CASE WHEN public.planning_v2_is_uuid(v_cell.value)
                                  THEN public.planning_v2_is_member(p_block.relationship_id, (v_cell.value #>> '{}')::uuid)
                                  ELSE false END
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

CREATE OR REPLACE FUNCTION public.planning_v2_convert_old_bills_tables(p_today date DEFAULT current_date)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  c_old constant jsonb := '[{"key":"c0","label":"Bill","type":"text"},{"key":"c1","label":"Amount","type":"money"},{"key":"c2","label":"Due day","type":"number"},{"key":"c3","label":"Paid","type":"check"},{"key":"c4","label":"Paid by","type":"text"}]';
  v_month date := date_trunc('month', p_today)::date;
  v_last  int := extract(day FROM (date_trunc('month', p_today) + interval '1 month - 1 day'))::int;
  v_b     record;
  v_n     int := 0;
BEGIN
  FOR v_b IN SELECT b.id, b.relationship_id FROM public.planning_blocks b
             WHERE b.block_type = 'table' AND b.payload -> 'columns' = c_old FOR UPDATE LOOP
    UPDATE public.planning_blocks
    SET payload = jsonb_set(jsonb_set(payload,
          '{columns,2}', '{"key":"c2","label":"Due date","type":"date"}'),
          '{columns,4}', '{"key":"c4","label":"Paid by","type":"person"}'),
        version = version + 1
    WHERE id = v_b.id;
    -- Every row, deleted ones too (Undo can bring them back).
    UPDATE public.planning_block_items i
    SET cells = (i.cells - 'c2' - 'c4')
        || CASE WHEN jsonb_typeof(i.cells -> 'c2') = 'number'
                     AND (i.cells ->> 'c2')::numeric BETWEEN 1 AND 31
                     AND (i.cells ->> 'c2')::numeric = trunc((i.cells ->> 'c2')::numeric)
                THEN jsonb_build_object('c2', (v_month + (least((i.cells ->> 'c2')::int, v_last) - 1))::text)
                ELSE '{}'::jsonb END
        || coalesce((
             SELECT jsonb_build_object('c4', u.id::text)
             FROM public.relationships r JOIN public.users u ON u.id IN (r.user_a, r.user_b)
             WHERE r.id = v_b.relationship_id AND jsonb_typeof(i.cells -> 'c4') = 'string'
               AND lower(btrim(u.display_name)) = lower(btrim(i.cells ->> 'c4'))
             ORDER BY u.id LIMIT 1), '{}'::jsonb),
        version = version + 1
    WHERE i.block_id = v_b.id AND i.cells IS NOT NULL;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_convert_old_bills_tables(date) FROM PUBLIC, anon, authenticated;

SELECT public.planning_v2_convert_old_bills_tables();
