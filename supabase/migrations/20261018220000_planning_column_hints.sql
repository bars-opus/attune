-- Table columns can carry a hint (2026-10-18): a short example the row
-- editor shows in the column's empty field (validated: text, 1-60
-- characters). The template tables get theirs — and the Wishlist's "Where"
-- becomes "Where to buy" — in the starter and gallery templates, and once
-- in every table still laid out exactly as a template made it (old Bills
-- tables converted earlier today included). Anything else is left alone.
-- The validator keeps its grants; the helpers are internal.

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
         OR NOT public.planning_v2_keys_within(v_col, ARRAY['key','label','type','hint'])
         -- hint: a short example shown in the column's empty field.
         OR (v_col ? 'hint' AND (jsonb_typeof(v_col -> 'hint') <> 'string'
             OR char_length(btrim(v_col ->> 'hint')) NOT BETWEEN 1 AND 60))
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

-- A template table's columns, hinted: the same columns with their hints
-- (and the Wishlist's clearer label) when [p_cols] is exactly as that
-- template made them; otherwise [p_cols] as it is.
CREATE OR REPLACE FUNCTION public.planning_v2_hinted_columns(p_cols jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT coalesce((SELECT m.hinted FROM (VALUES
    ('[{"key": "c0", "label": "Item", "type": "text"}, {"key": "c1", "label": "Price", "type": "money"}, {"key": "c2", "label": "Where", "type": "text"}, {"key": "c3", "label": "Got it", "type": "check"}]'::jsonb, '[{"key": "c0", "label": "Item", "type": "text", "hint": "Headphones"}, {"key": "c1", "label": "Price", "type": "money"}, {"key": "c2", "label": "Where to buy", "type": "text", "hint": "Shop or website"}, {"key": "c3", "label": "Got it", "type": "check"}]'::jsonb),
    ('[{"key": "c0", "label": "Day", "type": "text"}, {"key": "c1", "label": "Plan", "type": "text"}, {"key": "c2", "label": "Where", "type": "text"}, {"key": "c3", "label": "Cost", "type": "money"}]'::jsonb, '[{"key": "c0", "label": "Day", "type": "text", "hint": "Mon"}, {"key": "c1", "label": "Plan", "type": "text", "hint": "Beach, then dinner"}, {"key": "c2", "label": "Where", "type": "text", "hint": "Old town"}, {"key": "c3", "label": "Cost", "type": "money"}]'::jsonb),
    ('[{"key": "c0", "label": "Room", "type": "text"}, {"key": "c1", "label": "What goes there", "type": "text"}]'::jsonb, '[{"key": "c0", "label": "Room", "type": "text", "hint": "Kitchen"}, {"key": "c1", "label": "What goes there", "type": "text", "hint": "Plates, pans, kettle"}]'::jsonb),
    ('[{"key": "c0", "label": "Name", "type": "text"}, {"key": "c1", "label": "Invited", "type": "check"}, {"key": "c2", "label": "Coming", "type": "check"}, {"key": "c3", "label": "Plus one", "type": "check"}]'::jsonb, '[{"key": "c0", "label": "Name", "type": "text", "hint": "Ama Owusu"}, {"key": "c1", "label": "Invited", "type": "check"}, {"key": "c2", "label": "Coming", "type": "check"}, {"key": "c3", "label": "Plus one", "type": "check"}]'::jsonb),
    ('[{"key": "c0", "label": "Name", "type": "text"}, {"key": "c1", "label": "We both love it", "type": "check"}]'::jsonb, '[{"key": "c0", "label": "Name", "type": "text", "hint": "Esi"}, {"key": "c1", "label": "We both love it", "type": "check"}]'::jsonb),
    ('[{"key": "c0", "label": "Bill", "type": "text"}, {"key": "c1", "label": "Amount", "type": "money"}, {"key": "c2", "label": "Due date", "type": "date"}, {"key": "c3", "label": "Paid", "type": "check"}, {"key": "c4", "label": "Paid by", "type": "person"}]'::jsonb, '[{"key": "c0", "label": "Bill", "type": "text", "hint": "Rent"}, {"key": "c1", "label": "Amount", "type": "money"}, {"key": "c2", "label": "Due date", "type": "date"}, {"key": "c3", "label": "Paid", "type": "check"}, {"key": "c4", "label": "Paid by", "type": "person"}]'::jsonb)
  ) AS m(plain, hinted) WHERE m.plain = p_cols), p_cols);
$$;
REVOKE ALL ON FUNCTION public.planning_v2_hinted_columns(jsonb) FROM PUBLIC, anon, authenticated;

-- The same blocks, each table's columns hinted.
CREATE OR REPLACE FUNCTION public.planning_v2_hinted_blocks(p_blocks jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT coalesce(jsonb_agg(
    CASE WHEN b ->> 'type' = 'table' AND b -> 'payload' ? 'columns'
         THEN jsonb_set(b, '{payload,columns}', public.planning_v2_hinted_columns(b -> 'payload' -> 'columns'))
         ELSE b END ORDER BY n), '[]'::jsonb)
  FROM jsonb_array_elements(p_blocks) WITH ORDINALITY AS t(b, n);
$$;
REVOKE ALL ON FUNCTION public.planning_v2_hinted_blocks(jsonb) FROM PUBLIC, anon, authenticated;

-- Hints every table still exactly as a template made it. Returns how many
-- it changed; a second run changes none.
CREATE OR REPLACE FUNCTION public.planning_v2_hint_template_tables()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  UPDATE public.planning_blocks b
  SET payload = jsonb_set(b.payload, '{columns}', public.planning_v2_hinted_columns(b.payload -> 'columns')),
      version = b.version + 1
  WHERE b.block_type = 'table'
    AND public.planning_v2_hinted_columns(b.payload -> 'columns') IS DISTINCT FROM b.payload -> 'columns';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_hint_template_tables() FROM PUBLIC, anon, authenticated;

-- Templates: new plans get the hints; unedited starter templates upgrade.
UPDATE public.planning_starter_templates
SET blocks = public.planning_v2_hinted_blocks(blocks), version = version + 1
WHERE public.planning_v2_hinted_blocks(blocks) IS DISTINCT FROM blocks;
UPDATE public.planning_gallery_templates
SET blocks = public.planning_v2_hinted_blocks(blocks)
WHERE public.planning_v2_hinted_blocks(blocks) IS DISTINCT FROM blocks;

SELECT public.planning_v2_hint_template_tables();
