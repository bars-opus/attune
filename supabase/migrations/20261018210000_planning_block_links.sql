-- Countdown and Progress links (2026-10-18). Each now reports what it
-- follows (computed date_block_id / checklist_block_id), so the plan can say
-- "Counts to: Trip dates" / "Tracks: Packing". Existing unlinked ones (and
-- links to a block since deleted) are pinned once to what they show now, so
-- adding or reordering blocks never moves them; a countdown with no date yet
-- (a trip waiting on its poll) stays unlinked until it has one. The
-- countdown rule itself (planning_v2_countdown_target) is unchanged.
-- Replaced functions keep their grants; the helpers are internal.

-- The Date block a countdown counts to, by the same rule as its target: its
-- linked block while that has a date, else the plan's first dated one.
CREATE OR REPLACE FUNCTION public.planning_v2_countdown_date_block(p_block public.planning_blocks)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(
    (SELECT d.id FROM public.planning_blocks d
     WHERE public.planning_v2_is_uuid(p_block.payload -> 'date_block_id')
       AND d.id = (p_block.payload ->> 'date_block_id')::uuid
       AND d.entry_id = p_block.entry_id AND d.block_type = 'date' AND d.deleted_at IS NULL
       AND d.date_start IS NOT NULL),
    (SELECT d.id FROM public.planning_blocks d
     WHERE d.entry_id = p_block.entry_id AND d.block_type = 'date' AND d.deleted_at IS NULL
       AND d.date_start IS NOT NULL
     ORDER BY d.sort_key, d.id LIMIT 1));
$$;
REVOKE ALL ON FUNCTION public.planning_v2_countdown_date_block(public.planning_blocks) FROM PUBLIC, anon, authenticated;

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
      FROM public.planning_block_items i
      WHERE i.block_id = public.planning_v2_progress_checklist(p_block) AND i.deleted_at IS NULL)
    ELSE (
      SELECT jsonb_build_object('mode', 'numeric', 'current', coalesce(sum(i.amount_minor), 0))
      FROM public.planning_block_items i WHERE i.block_id = p_block.id AND i.deleted_at IS NULL)
    END
  ELSE NULL END;
$$;

-- Pins every countdown and checklist progress that has no live link to the
-- block it follows now. Returns how many it pinned; a second run pins none.
CREATE OR REPLACE FUNCTION public.planning_v2_pin_block_links()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_c int; v_p int;
BEGIN
  UPDATE public.planning_blocks c
  SET payload = c.payload || jsonb_build_object('date_block_id', x.target), version = c.version + 1
  FROM (SELECT b.id, public.planning_v2_countdown_date_block(b) AS target
        FROM public.planning_blocks b WHERE b.block_type = 'countdown' AND b.deleted_at IS NULL) x
  WHERE c.id = x.id AND x.target IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.planning_blocks d
      WHERE public.planning_v2_is_uuid(c.payload -> 'date_block_id')
        AND d.id = (c.payload ->> 'date_block_id')::uuid
        AND d.entry_id = c.entry_id AND d.block_type = 'date' AND d.deleted_at IS NULL);
  GET DIAGNOSTICS v_c = ROW_COUNT;
  UPDATE public.planning_blocks p
  SET payload = p.payload || jsonb_build_object('checklist_block_id', x.target), version = p.version + 1
  FROM (SELECT b.id, public.planning_v2_progress_checklist(b) AS target
        FROM public.planning_blocks b
        WHERE b.block_type = 'progress' AND b.deleted_at IS NULL AND b.payload ->> 'mode' = 'checklist') x
  WHERE p.id = x.id AND x.target IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.planning_blocks k
      WHERE public.planning_v2_is_uuid(p.payload -> 'checklist_block_id')
        AND k.id = (p.payload ->> 'checklist_block_id')::uuid
        AND k.entry_id = p.entry_id AND k.block_type = 'checklist' AND k.deleted_at IS NULL);
  GET DIAGNOSTICS v_p = ROW_COUNT;
  RETURN v_c + v_p;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_pin_block_links() FROM PUBLIC, anon, authenticated;

SELECT public.planning_v2_pin_block_links();
