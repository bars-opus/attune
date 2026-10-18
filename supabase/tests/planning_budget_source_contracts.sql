-- A budget follows one source (2026-10-18): all of the plan's expenses (the
-- default), one Expenses block, or a table (all its money columns). A
-- source that isn't a live Expenses or table block in the SAME plan counts
-- as "all expenses" — never another plan's money. Copies keep the link.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users (id) VALUES ('7f8a0000-0000-0000-0000-0000000000a1'), ('7f8a0000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7f8a0000-0000-0000-0000-0000000000a1', '+233279930001', 'Ama'),
  ('7f8a0000-0000-0000-0000-0000000000b2', '+233279930002', 'Kofi')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('7f8b0000-0000-0000-0000-000000000001', '7f8a0000-0000-0000-0000-0000000000a1',
   '7f8a0000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
-- A block of a plan, as the plan screen gets it.
CREATE FUNCTION pg_temp.block(p_entry uuid, p_block uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT b FROM jsonb_array_elements(public.get_planning_entry(p_entry) -> 'blocks') b WHERE b ->> 'id' = p_block::text $$;
CREATE FUNCTION pg_temp.spent(p_block uuid) RETURNS bigint LANGUAGE sql AS $$
  SELECT (pg_temp.block('7f8d0000-0000-0000-0000-000000000001', p_block) -> 'computed' ->> 'spent_minor')::bigint $$;
CREATE FUNCTION pg_temp.retarget(p_block uuid, p_source uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v jsonb := pg_temp.block('7f8d0000-0000-0000-0000-000000000001', p_block);
BEGIN
  PERFORM public.update_planning_block(p_block, (v ->> 'version')::int,
    jsonb_build_object('title', 'Budget', 'source_block_id', p_source), NULL, NULL);
END $$;

-- Trip (GHS): Expenses A (2000 + 1500), Expenses B (300), a table T with two
-- money columns (1000 + 500, 200 + nothing), and three budgets. A second
-- plan, Other, has its own expenses (9999).
DO $$
DECLARE
  v_e uuid := '7f8d0000-0000-0000-0000-000000000001';
BEGIN
  PERFORM pg_temp.as_user('7f8a0000-0000-0000-0000-0000000000a1');
  PERFORM public.create_planning_category('7f8c0000-0000-0000-0000-000000000001', '7f8b0000-0000-0000-0000-000000000001',
    'Trips', (public.planning_v2_icons())[1], (public.planning_v2_colors())[1]);
  PERFORM public.create_planning_entry(v_e, '7f8c0000-0000-0000-0000-000000000001', 'Lisbon', false, 'GHS');
  PERFORM public.create_planning_entry('7f8d0000-0000-0000-0000-000000000002', '7f8c0000-0000-0000-0000-000000000001', 'Other', false, 'GHS');
  PERFORM public.add_planning_block('7f8e0000-0000-0000-0000-00000000000a', v_e, 'expenses', '{"title":"Travel"}', NULL, NULL, NULL);
  PERFORM public.add_planning_block('7f8e0000-0000-0000-0000-00000000000b', v_e, 'expenses', '{"title":"Food"}', NULL, NULL, NULL);
  PERFORM public.add_planning_block('7f8e0000-0000-0000-0000-00000000000c', v_e, 'table',
    '{"title":"Costs","columns":[{"key":"c0","label":"Day","type":"text"},{"key":"c1","label":"Tickets","type":"money"},{"key":"c2","label":"Tips","type":"money"}]}',
    NULL, NULL, NULL);
  PERFORM public.add_planning_block('7f8e0000-0000-0000-0000-0000000000d1', v_e, 'budget', '{}', NULL, NULL, NULL);
  PERFORM public.add_planning_block('7f8e0000-0000-0000-0000-0000000000d2', v_e, 'budget', '{}', NULL, NULL, NULL);
  PERFORM public.add_planning_block('7f8e0000-0000-0000-0000-0000000000d3', v_e, 'budget', '{}', NULL, NULL, NULL);
  PERFORM public.add_planning_block('7f8e0000-0000-0000-0000-00000000000f', '7f8d0000-0000-0000-0000-000000000002',
    'expenses', '{}', NULL, NULL, NULL);
  PERFORM public.save_planning_rich_item(gen_random_uuid(), '7f8e0000-0000-0000-0000-00000000000a', NULL, '{"label":"Flights","amount_minor":2000}', NULL);
  PERFORM public.save_planning_rich_item(gen_random_uuid(), '7f8e0000-0000-0000-0000-00000000000a', NULL, '{"label":"Stay","amount_minor":1500}', NULL);
  PERFORM public.save_planning_rich_item(gen_random_uuid(), '7f8e0000-0000-0000-0000-00000000000b', NULL, '{"label":"Dinner","amount_minor":300}', NULL);
  PERFORM public.save_planning_rich_item(gen_random_uuid(), '7f8e0000-0000-0000-0000-00000000000c', NULL, '{"cells":{"c0":"Mon","c1":1000,"c2":500}}', NULL);
  PERFORM public.save_planning_rich_item(gen_random_uuid(), '7f8e0000-0000-0000-0000-00000000000c', NULL, '{"cells":{"c0":"Tue","c1":200}}', NULL);
  PERFORM public.save_planning_rich_item(gen_random_uuid(), '7f8e0000-0000-0000-0000-00000000000f', NULL, '{"label":"Elsewhere","amount_minor":9999}', NULL);
END $$;

-- 1. Unlinked, a budget counts all of the plan's expenses — even before a
--    target (and so a currency) is set — and says so.
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.as_user('7f8a0000-0000-0000-0000-0000000000a1');
  v := pg_temp.block('7f8d0000-0000-0000-0000-000000000001', '7f8e0000-0000-0000-0000-0000000000d1') -> 'computed';
  IF (v ->> 'spent_minor')::bigint <> 3800 OR v ->> 'source' <> 'all' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: unlinked budget %', v;
  END IF;
  IF jsonb_array_length(v -> 'other_currencies') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with no target yet, the plan''s own currency went uncounted %', v;
  END IF;
END $$;

-- 2. Linked to one Expenses block, or to the table (every money column).
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.as_user('7f8a0000-0000-0000-0000-0000000000a1');
  PERFORM pg_temp.retarget('7f8e0000-0000-0000-0000-0000000000d2', '7f8e0000-0000-0000-0000-00000000000a');
  PERFORM pg_temp.retarget('7f8e0000-0000-0000-0000-0000000000d3', '7f8e0000-0000-0000-0000-00000000000c');
  v := pg_temp.block('7f8d0000-0000-0000-0000-000000000001', '7f8e0000-0000-0000-0000-0000000000d2') -> 'computed';
  IF (v ->> 'spent_minor')::bigint <> 3500 OR v ->> 'source' <> 'expenses'
     OR v ->> 'source_block_id' <> '7f8e0000-0000-0000-0000-00000000000a' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: budget on one Expenses block %', v;
  END IF;
  v := pg_temp.block('7f8d0000-0000-0000-0000-000000000001', '7f8e0000-0000-0000-0000-0000000000d3') -> 'computed';
  IF (v ->> 'spent_minor')::bigint <> 1700 OR v ->> 'source' <> 'table' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: budget on the table %', v;
  END IF;
  IF pg_temp.spent('7f8e0000-0000-0000-0000-0000000000d1') <> 3800 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: linking one budget moved another';
  END IF;
END $$;

-- 3. Another plan's block is never a source: it counts as all expenses.
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.as_user('7f8a0000-0000-0000-0000-0000000000a1');
  PERFORM pg_temp.retarget('7f8e0000-0000-0000-0000-0000000000d1', '7f8e0000-0000-0000-0000-00000000000f');
  v := pg_temp.block('7f8d0000-0000-0000-0000-000000000001', '7f8e0000-0000-0000-0000-0000000000d1') -> 'computed';
  IF (v ->> 'spent_minor')::bigint <> 3800 OR v ->> 'source' <> 'all' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another plan''s expenses counted %', v;
  END IF;
END $$;

-- 4. A deleted source falls back to all expenses.
DO $$
BEGIN
  PERFORM pg_temp.as_user('7f8a0000-0000-0000-0000-0000000000a1');
  PERFORM public.delete_planning_block('7f8e0000-0000-0000-0000-00000000000c');
  IF pg_temp.spent('7f8e0000-0000-0000-0000-0000000000d3') <> 3800 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a budget kept counting a deleted table';
  END IF;
  PERFORM public.restore_planning_block('7f8e0000-0000-0000-0000-00000000000c');
END $$;

-- 5. In another currency, the table's money is listed, not counted.
DO $$
DECLARE v jsonb; v_ver int;
BEGIN
  PERFORM pg_temp.as_user('7f8a0000-0000-0000-0000-0000000000a1');
  v_ver := (pg_temp.block('7f8d0000-0000-0000-0000-000000000001', '7f8e0000-0000-0000-0000-0000000000d3') ->> 'version')::int;
  PERFORM public.update_planning_block_target('7f8e0000-0000-0000-0000-0000000000d3', v_ver, 50000, 'USD');
  v := pg_temp.block('7f8d0000-0000-0000-0000-000000000001', '7f8e0000-0000-0000-0000-0000000000d3') -> 'computed';
  IF (v ->> 'spent_minor')::bigint <> 0 OR v -> 'other_currencies' <> '[{"currency":"GHS","minor":1700}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a USD budget on a GHS table %', v;
  END IF;
END $$;

-- 6. A source must be a block id; nothing else rides in the payload.
DO $$
DECLARE v_ver int;
BEGIN
  PERFORM pg_temp.as_user('7f8a0000-0000-0000-0000-0000000000a1');
  v_ver := (pg_temp.block('7f8d0000-0000-0000-0000-000000000001', '7f8e0000-0000-0000-0000-0000000000d2') ->> 'version')::int;
  BEGIN
    PERFORM public.update_planning_block('7f8e0000-0000-0000-0000-0000000000d2', v_ver, '{"source_block_id":"bills"}', NULL, NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-uuid source accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.update_planning_block('7f8e0000-0000-0000-0000-0000000000d2', v_ver, '{"spent":1}', NULL, NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown budget key accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
END $$;

-- 7. "Start the next one": the copy's budget follows the copy's block.
DO $$
DECLARE v_src text; v_new_travel text;
BEGIN
  PERFORM pg_temp.as_user('7f8a0000-0000-0000-0000-0000000000a1');
  PERFORM public.duplicate_planning_entry('7f8d0000-0000-0000-0000-000000000001', '7f8d0000-0000-0000-0000-000000000003', 'Lisbon again');
  SELECT b.payload ->> 'source_block_id' INTO v_src FROM public.planning_blocks b
  WHERE b.entry_id = '7f8d0000-0000-0000-0000-000000000003' AND b.block_type = 'budget'
    AND b.sort_key = (SELECT sort_key FROM public.planning_blocks WHERE id = '7f8e0000-0000-0000-0000-0000000000d2');
  SELECT b.id::text INTO v_new_travel FROM public.planning_blocks b
  WHERE b.entry_id = '7f8d0000-0000-0000-0000-000000000003' AND b.block_type = 'expenses' AND b.payload ->> 'title' = 'Travel';
  IF v_src IS DISTINCT FROM v_new_travel THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the copied budget follows % not its own Travel %', v_src, v_new_travel;
  END IF;
END $$;

ROLLBACK;
