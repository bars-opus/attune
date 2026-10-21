-- Goals (2026-10-18). A progress bar follows a date — its "by" — and the
-- server reports what the app needs for its pace: date_block_id,
-- target_date and started_on (when the plan was made). A plan whose only
-- Date block arrives links its countdown and progress to it, and a
-- countdown or progress added to a plan with one Date block links to it,
-- so a goal made from the template follows its own Target date and a
-- second date never pulls it away. The Goals template gains a countdown
-- (v4), and its "Why this matters to us" becomes a bold line rather than a
-- big heading. Existing progress bars are pinned once to the date they
-- follow.
-- Replaced functions keep their grants; the helpers are internal.

-- The Date block a progress bar is due by: its linked one while that is a
-- live Date block in the same plan (set or not yet), else the plan's first
-- dated one.
CREATE OR REPLACE FUNCTION public.planning_v2_progress_date_block(p_block public.planning_blocks)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(
    (SELECT d.id FROM public.planning_blocks d
     WHERE public.planning_v2_is_uuid(p_block.payload -> 'date_block_id')
       AND d.id = (p_block.payload ->> 'date_block_id')::uuid
       AND d.entry_id = p_block.entry_id AND d.block_type = 'date' AND d.deleted_at IS NULL),
    (SELECT d.id FROM public.planning_blocks d
     WHERE d.entry_id = p_block.entry_id AND d.block_type = 'date' AND d.deleted_at IS NULL
       AND d.date_start IS NOT NULL
     ORDER BY d.sort_key, d.id LIMIT 1));
$$;
REVOKE ALL ON FUNCTION public.planning_v2_progress_date_block(public.planning_blocks) FROM PUBLIC, anon, authenticated;

-- A progress bar's pace inputs: the date it's due by and when its plan began.
CREATE OR REPLACE FUNCTION public.planning_v2_progress_pace(p_block public.planning_blocks)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'date_block_id', d.id,
    'target_date', (SELECT b.date_start FROM public.planning_blocks b WHERE b.id = d.id),
    'started_on', (SELECT (e.created_at AT TIME ZONE 'UTC')::date FROM public.planning_entries e WHERE e.id = p_block.entry_id))
  FROM (SELECT public.planning_v2_progress_date_block(p_block) AS id) d;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_progress_pace(public.planning_blocks) FROM PUBLIC, anon, authenticated;

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
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title','mode','unit','checklist_block_id','date_block_id'])
       OR coalesce(p_payload ->> 'mode', '') NOT IN ('numeric', 'checklist')
       OR coalesce(p_payload ->> 'unit', 'count') NOT IN ('count', 'money')
       OR (p_payload ? 'checklist_block_id' AND jsonb_typeof(p_payload -> 'checklist_block_id') <> 'null'
           AND NOT public.planning_v2_is_uuid(p_payload -> 'checklist_block_id'))
       -- date_block_id: the date it is due by (its pace).
       OR (p_payload ? 'date_block_id' AND jsonb_typeof(p_payload -> 'date_block_id') <> 'null'
           AND NOT public.planning_v2_is_uuid(p_payload -> 'date_block_id')) THEN
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
  -- date_block_id: the Date block it counts to (null while there is none).
  WHEN 'countdown' THEN jsonb_build_object('target_date', public.planning_v2_countdown_target(p_block),
    'date_block_id', public.planning_v2_countdown_date_block(p_block))
  WHEN 'progress' THEN
    CASE WHEN p_block.payload ->> 'mode' = 'checklist' THEN (
      -- checklist_block_id: the checklist it tracks (null while there is none).
      SELECT jsonb_build_object('mode', 'checklist',
               'done', count(*) FILTER (WHERE i.checked_at IS NOT NULL), 'total', count(*),
               'checklist_block_id', public.planning_v2_progress_checklist(p_block))
             || public.planning_v2_progress_pace(p_block)
      FROM public.planning_block_items i
      WHERE i.block_id = public.planning_v2_progress_checklist(p_block) AND i.deleted_at IS NULL)
    ELSE (
      SELECT jsonb_build_object('mode', 'numeric', 'current', coalesce(sum(i.amount_minor), 0))
             || public.planning_v2_progress_pace(p_block)
      FROM public.planning_block_items i WHERE i.block_id = p_block.id AND i.deleted_at IS NULL)
    END
  ELSE NULL END;
$$;

-- A countdown or progress added to a plan with exactly one Date block (and
-- no link of its own) follows it.
CREATE OR REPLACE FUNCTION public.planning_v2_link_new_dated_tool()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE v_only uuid;
BEGIN
  IF NEW.block_type IN ('countdown', 'progress') AND NOT (NEW.payload ? 'date_block_id') THEN
    SELECT min(d.id::text)::uuid INTO v_only FROM public.planning_blocks d
    WHERE d.entry_id = NEW.entry_id AND d.block_type = 'date' AND d.deleted_at IS NULL
    HAVING count(*) = 1;
    IF v_only IS NOT NULL THEN
      NEW.payload := NEW.payload || jsonb_build_object('date_block_id', v_only);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS planning_blocks_link_new_dated_tool ON public.planning_blocks;
CREATE TRIGGER planning_blocks_link_new_dated_tool BEFORE INSERT ON public.planning_blocks
  FOR EACH ROW EXECUTE FUNCTION public.planning_v2_link_new_dated_tool();

-- A plan's first Date block: the countdowns and progress bars already there
-- without a link follow it.
CREATE OR REPLACE FUNCTION public.planning_v2_link_to_first_date()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.block_type = 'date' AND (
       SELECT count(*) FROM public.planning_blocks d
       WHERE d.entry_id = NEW.entry_id AND d.block_type = 'date' AND d.deleted_at IS NULL) = 1 THEN
    UPDATE public.planning_blocks t
    SET payload = t.payload || jsonb_build_object('date_block_id', NEW.id), version = t.version + 1
    WHERE t.entry_id = NEW.entry_id AND t.block_type IN ('countdown', 'progress')
      AND t.deleted_at IS NULL AND NOT (t.payload ? 'date_block_id');
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS planning_blocks_link_to_first_date ON public.planning_blocks;
CREATE TRIGGER planning_blocks_link_to_first_date AFTER INSERT ON public.planning_blocks
  FOR EACH ROW EXECUTE FUNCTION public.planning_v2_link_to_first_date();
REVOKE ALL ON FUNCTION public.planning_v2_link_new_dated_tool() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_link_to_first_date() FROM PUBLIC, anon, authenticated;

-- The Goals template (v4): progress, the Target date, a countdown to it,
-- "Why this matters to us" as a bold Small line (bodyMedium, 14 — not a big
-- heading), and the steps. Unedited goal templates upgrade; their links
-- come from the triggers.
UPDATE public.planning_starter_templates
SET version = greatest(version, 3) + 1,
    blocks = jsonb_build_array(
      '{"type":"progress","payload":{"mode":"checklist"}}'::jsonb,
      '{"type":"date","payload":{"title":"Target date"}}'::jsonb,
      '{"type":"countdown","payload":{}}'::jsonb,
      jsonb_build_object('type', 'text', 'payload', jsonb_build_object('delta', jsonb_build_array(
        jsonb_build_object('insert', 'Why this matters to us', 'attributes', jsonb_build_object('bold', true, 'size', 'small')),
        jsonb_build_object('insert', E'\n'),
        jsonb_build_object('insert', E'\n')))),
      '{"type":"checklist","payload":{"title":"Steps"}}'::jsonb)
WHERE seed_key = 'goals';

-- Goals made before: their "Why this matters to us" Heading 2 becomes the
-- same bold line, once; what they wrote under it is untouched.
CREATE OR REPLACE FUNCTION public.planning_v2_soften_goal_headings()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  UPDATE public.planning_blocks b
  SET payload = jsonb_set(jsonb_set(b.payload,
        '{delta,0}', '{"insert":"Why this matters to us","attributes":{"bold":true,"size":"small"}}'::jsonb),
        '{delta,1}', jsonb_build_object('insert', E'\n')),
      version = b.version + 1
  FROM public.planning_entries e
  JOIN public.planning_categories c ON c.id = e.category_id AND c.seed_key = 'goals'
  WHERE b.entry_id = e.id AND b.block_type = 'text'
    AND b.payload -> 'delta' -> 0 = '{"insert":"Why this matters to us"}'::jsonb
    AND b.payload -> 'delta' -> 1 = jsonb_build_object('insert', E'\n', 'attributes', jsonb_build_object('header', 2));
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_soften_goal_headings() FROM PUBLIC, anon, authenticated;
SELECT public.planning_v2_soften_goal_headings();

-- Existing progress bars with no live date link follow the date they use
-- now (or the plan's only Date block), once.
UPDATE public.planning_blocks p
SET payload = p.payload || jsonb_build_object('date_block_id', x.target), version = p.version + 1
FROM (
  SELECT b.id, coalesce(public.planning_v2_progress_date_block(b),
    (SELECT min(d.id::text)::uuid FROM public.planning_blocks d
     WHERE d.entry_id = b.entry_id AND d.block_type = 'date' AND d.deleted_at IS NULL
     HAVING count(*) = 1)) AS target
  FROM public.planning_blocks b WHERE b.block_type = 'progress' AND b.deleted_at IS NULL) x
WHERE p.id = x.id AND x.target IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.planning_blocks d
    WHERE public.planning_v2_is_uuid(p.payload -> 'date_block_id')
      AND d.id = (p.payload ->> 'date_block_id')::uuid
      AND d.entry_id = p.entry_id AND d.block_type = 'date' AND d.deleted_at IS NULL);
