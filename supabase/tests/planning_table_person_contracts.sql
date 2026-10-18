-- Tables get a Person column (2026-10-18): a cell is one of the couple, by
-- id. Old Bills tables (the Home & bills starter before v3) are converted
-- once: "Due day" (a number) becomes a date this month, "Paid by" (free
-- text) becomes a Person, matched to a member by name.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users (id) VALUES
  ('7faa0000-0000-0000-0000-0000000000a1'), ('7faa0000-0000-0000-0000-0000000000b2'), ('7faa0000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7faa0000-0000-0000-0000-0000000000a1', '+233279950001', 'Ama'),
  ('7faa0000-0000-0000-0000-0000000000b2', '+233279950002', 'Kofi'),
  ('7faa0000-0000-0000-0000-0000000000c3', '+233279950003', 'Stranger')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('7fab0000-0000-0000-0000-000000000001', '7faa0000-0000-0000-0000-0000000000a1',
   '7faa0000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

DO $$
DECLARE v_e uuid := '7fad0000-0000-0000-0000-000000000001';
BEGIN
  PERFORM pg_temp.as_user('7faa0000-0000-0000-0000-0000000000a1');
  PERFORM public.create_planning_category('7fac0000-0000-0000-0000-000000000001', '7fab0000-0000-0000-0000-000000000001',
    'Home', (public.planning_v2_icons())[1], (public.planning_v2_colors())[1]);
  PERFORM public.create_planning_entry(v_e, '7fac0000-0000-0000-0000-000000000001', 'This month', false, 'GHS');
  -- A table with a Person column.
  PERFORM public.add_planning_block('7fae0000-0000-0000-0000-000000000001', v_e, 'table',
    '{"columns":[{"key":"c0","label":"Chore","type":"text"},{"key":"c1","label":"Who","type":"person"}]}', NULL, NULL, NULL);
  -- An old Bills table, exactly as the v2 starter made it.
  PERFORM public.add_planning_block('7fae0000-0000-0000-0000-000000000002', v_e, 'table',
    '{"title":"Bills","columns":[{"key":"c0","label":"Bill","type":"text"},{"key":"c1","label":"Amount","type":"money"},{"key":"c2","label":"Due day","type":"number"},{"key":"c3","label":"Paid","type":"check"},{"key":"c4","label":"Paid by","type":"text"}]}',
    NULL, NULL, NULL);
  PERFORM public.save_planning_rich_item('7faf0000-0000-0000-0000-000000000001', '7fae0000-0000-0000-0000-000000000002', NULL,
    '{"cells":{"c0":"Rent","c1":150000,"c2":5,"c3":true,"c4":"kofi "}}', NULL);
  PERFORM public.save_planning_rich_item('7faf0000-0000-0000-0000-000000000002', '7fae0000-0000-0000-0000-000000000002', NULL,
    '{"cells":{"c0":"Water","c2":31,"c4":"my sister"}}', NULL);
  PERFORM public.save_planning_rich_item('7faf0000-0000-0000-0000-000000000003', '7fae0000-0000-0000-0000-000000000002', NULL,
    '{"cells":{"c0":"TV","c2":45}}', NULL);
  -- A Bills table the couple had already reshaped: left alone.
  PERFORM public.add_planning_block('7fae0000-0000-0000-0000-000000000003', v_e, 'table',
    '{"title":"Bills","columns":[{"key":"c0","label":"Bill","type":"text"},{"key":"c2","label":"Due day","type":"number"}]}',
    NULL, NULL, NULL);
END $$;

-- 1. A Person cell is one of the couple; nobody else, and nothing else.
DO $$
BEGIN
  PERFORM pg_temp.as_user('7faa0000-0000-0000-0000-0000000000a1');
  PERFORM public.save_planning_rich_item(gen_random_uuid(), '7fae0000-0000-0000-0000-000000000001', NULL,
    '{"cells":{"c0":"Bins","c1":"7faa0000-0000-0000-0000-0000000000b2"}}', NULL);
  BEGIN
    PERFORM public.save_planning_rich_item(gen_random_uuid(), '7fae0000-0000-0000-0000-000000000001', NULL,
      '{"cells":{"c0":"Bins","c1":"7faa0000-0000-0000-0000-0000000000c3"}}', NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone outside the couple as a Person';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.save_planning_rich_item(gen_random_uuid(), '7fae0000-0000-0000-0000-000000000001', NULL,
      '{"cells":{"c0":"Bins","c1":"Kofi"}}', NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a name accepted as a Person';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
END $$;

-- 2. The old Bills table converts: a date this month — run in February, so
--    31 is clamped to the 28th (45 is no day, so dropped), and a name that matches a
--    member (any case, trimmed) becomes them; one that doesn't is dropped.
DO $$
DECLARE v_cols jsonb; v_rent jsonb; v_water jsonb; v_tv jsonb; v_month date := '2026-02-01';
BEGIN
  PERFORM public.planning_v2_convert_old_bills_tables('2026-02-10');
  SELECT payload -> 'columns' INTO v_cols FROM public.planning_blocks WHERE id = '7fae0000-0000-0000-0000-000000000002';
  IF v_cols -> 2 <> '{"key":"c2","label":"Due date","type":"date"}'::jsonb
     OR v_cols -> 4 <> '{"key":"c4","label":"Paid by","type":"person"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: columns not converted %', v_cols;
  END IF;
  SELECT cells INTO v_rent FROM public.planning_block_items WHERE id = '7faf0000-0000-0000-0000-000000000001';
  SELECT cells INTO v_water FROM public.planning_block_items WHERE id = '7faf0000-0000-0000-0000-000000000002';
  SELECT cells INTO v_tv FROM public.planning_block_items WHERE id = '7faf0000-0000-0000-0000-000000000003';
  IF v_rent ->> 'c2' IS DISTINCT FROM (v_month + 4)::text
     OR v_rent ->> 'c4' IS DISTINCT FROM '7faa0000-0000-0000-0000-0000000000b2'
     OR v_rent ->> 'c1' IS DISTINCT FROM '150000' OR v_rent ->> 'c3' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Rent row %', v_rent;
  END IF;
  IF v_water ->> 'c2' IS DISTINCT FROM '2026-02-28' OR v_water ? 'c4' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Water row %', v_water;
  END IF;
  IF v_tv ? 'c2' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: day 45 kept %', v_tv; END IF;
  SELECT payload -> 'columns' INTO v_cols FROM public.planning_blocks WHERE id = '7fae0000-0000-0000-0000-000000000003';
  IF v_cols -> 1 ->> 'type' <> 'number' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a reshaped table was converted'; END IF;
  -- Run again: nothing left to convert.
  IF public.planning_v2_convert_old_bills_tables('2026-02-10') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the conversion is not once-only';
  END IF;
END $$;

-- 3. The converted cells are valid for their new columns: an edit saves.
DO $$
DECLARE v_ver int;
BEGIN
  PERFORM pg_temp.as_user('7faa0000-0000-0000-0000-0000000000a1');
  SELECT version INTO v_ver FROM public.planning_block_items WHERE id = '7faf0000-0000-0000-0000-000000000001';
  PERFORM public.save_planning_rich_item('7faf0000-0000-0000-0000-000000000001', '7fae0000-0000-0000-0000-000000000002', v_ver,
    jsonb_build_object('cells', jsonb_build_object('c4', '7faa0000-0000-0000-0000-0000000000a1')), NULL);
END $$;

ROLLBACK;
