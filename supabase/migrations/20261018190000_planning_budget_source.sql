-- A budget follows one source (2026-10-18). Budget payload gains
-- source_block_id: one Expenses block, or a table (all its money columns);
-- absent, or not a live Expenses/table block in the same plan, it counts all
-- of the plan's expenses as before. planning_v2_block_computed reports what
-- it counted (source, source_block_id), and an unset target no longer leaves
-- the plan's own currency "not counted". Copies keep the link
-- (planning_v2_copy_blocks remaps it). Old Home & bills plans — a table and
-- a budget, no Expenses — get their budget linked to that table, once.
-- Replaced functions keep their grants.

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
         OR coalesce(v_col ->> 'type', '') NOT IN ('text','number','money','date','check') THEN
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

CREATE OR REPLACE FUNCTION public.planning_v2_block_computed(p_block public.planning_blocks)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE p_block.block_type
  WHEN 'budget' THEN (
    -- What it counts: the linked Expenses or table block when that is live
    -- and in THIS plan, else every Expenses block in the plan.
    WITH src AS (
      SELECT s.id, s.block_type, s.payload FROM public.planning_blocks s
      WHERE public.planning_v2_is_uuid(p_block.payload -> 'source_block_id')
        AND s.id = (p_block.payload ->> 'source_block_id')::uuid
        AND s.entry_id = p_block.entry_id AND s.deleted_at IS NULL
        AND s.block_type IN ('expenses', 'table')),
    -- Before a target is set the budget has no currency: the plan's counts.
    cur AS (
      SELECT coalesce(p_block.target_currency, e.currency) AS budget_currency, e.currency AS plan_currency
      FROM public.planning_entries e WHERE e.id = p_block.entry_id),
    spent AS (
      SELECT i.currency, sum(i.amount_minor) AS minor
      FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
      WHERE b.entry_id = p_block.entry_id AND b.block_type = 'expenses' AND b.deleted_at IS NULL
        AND i.deleted_at IS NULL AND i.amount_minor IS NOT NULL
        AND (NOT EXISTS (SELECT 1 FROM src) OR b.id IN (SELECT id FROM src WHERE block_type = 'expenses'))
      GROUP BY i.currency
      UNION ALL
      -- A table: every money cell (minor units, the plan's currency).
      SELECT (SELECT plan_currency FROM cur), sum((i.cells ->> col.k)::numeric)
      FROM src
      JOIN public.planning_block_items i ON i.block_id = src.id AND i.deleted_at IS NULL
      CROSS JOIN LATERAL (
        SELECT c ->> 'key' AS k FROM jsonb_array_elements(src.payload -> 'columns') c
        WHERE c ->> 'type' = 'money') col
      WHERE src.block_type = 'table' AND jsonb_typeof(i.cells -> col.k) = 'number'
      HAVING count(*) > 0),
    totals AS (SELECT currency, sum(minor)::bigint AS minor FROM spent GROUP BY currency)
    SELECT jsonb_build_object(
      'spent_minor', coalesce((SELECT minor FROM totals WHERE currency = (SELECT budget_currency FROM cur)), 0),
      'other_currencies', coalesce((
        SELECT jsonb_agg(jsonb_build_object('currency', currency, 'minor', minor) ORDER BY currency)
        FROM totals WHERE currency IS DISTINCT FROM (SELECT budget_currency FROM cur)), '[]'::jsonb),
      'source', coalesce((SELECT block_type FROM src), 'all'),
      'source_block_id', (SELECT id FROM src)))
  WHEN 'countdown' THEN jsonb_build_object('target_date', public.planning_v2_countdown_target(p_block))
  WHEN 'progress' THEN
    CASE WHEN p_block.payload ->> 'mode' = 'checklist' THEN (
      SELECT jsonb_build_object('mode', 'checklist',
               'done', count(*) FILTER (WHERE i.checked_at IS NOT NULL), 'total', count(*))
      FROM public.planning_block_items i
      WHERE i.block_id = public.planning_v2_progress_checklist(p_block) AND i.deleted_at IS NULL)
    ELSE (
      SELECT jsonb_build_object('mode', 'numeric', 'current', coalesce(sum(i.amount_minor), 0))
      FROM public.planning_block_items i WHERE i.block_id = p_block.id AND i.deleted_at IS NULL)
    END
  ELSE NULL END;
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
  FOREACH v_ref IN ARRAY ARRAY['date_block_id', 'checklist_block_id', 'source_block_id'] LOOP
    UPDATE public.planning_blocks d
       SET payload = CASE WHEN v_map ? (d.payload ->> v_ref)
                          THEN jsonb_set(d.payload, ARRAY[v_ref], v_map -> (d.payload ->> v_ref))
                          ELSE d.payload - v_ref END
     WHERE d.entry_id = p_dst AND d.payload ? v_ref;
  END LOOP;
END;
$$;

-- One-time: a budget in a plan with no Expenses block and exactly one table
-- with a money column follows that table (old Home & bills plans and
-- templates).
UPDATE public.planning_blocks bud
SET payload = bud.payload || jsonb_build_object('source_block_id', t.id), version = bud.version + 1
FROM public.planning_blocks t
WHERE bud.block_type = 'budget' AND bud.deleted_at IS NULL
  AND NOT (bud.payload ? 'source_block_id')
  AND t.entry_id = bud.entry_id AND t.block_type = 'table' AND t.deleted_at IS NULL
  AND EXISTS (SELECT 1 FROM jsonb_array_elements(t.payload -> 'columns') c WHERE c ->> 'type' = 'money')
  AND NOT EXISTS (SELECT 1 FROM public.planning_blocks x
                  WHERE x.entry_id = bud.entry_id AND x.block_type = 'expenses' AND x.deleted_at IS NULL)
  AND (SELECT count(*) FROM public.planning_blocks y
       WHERE y.entry_id = bud.entry_id AND y.block_type = 'table' AND y.deleted_at IS NULL
         AND EXISTS (SELECT 1 FROM jsonb_array_elements(y.payload -> 'columns') c WHERE c ->> 'type' = 'money')) = 1;
