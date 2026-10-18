-- Bills in Planning (2026-10-18): an expense line can carry a due date, it
-- shows on the shared calendar marked as an expense, "Start the next one"
-- moves past due dates to their next month, and the Home & bills starter
-- is an Expenses block (so its Budget adds the bills up).
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users (id) VALUES
  ('7f7a0000-0000-0000-0000-0000000000a1'), ('7f7a0000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7f7a0000-0000-0000-0000-0000000000a1', '+233279920001', 'Ama'),
  ('7f7a0000-0000-0000-0000-0000000000b2', '+233279920002', 'Kofi')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('7f7b0000-0000-0000-0000-000000000001', '7f7a0000-0000-0000-0000-0000000000a1',
   '7f7a0000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- A plan with an Expenses block.
DO $$
DECLARE v_block jsonb;
BEGIN
  PERFORM pg_temp.as_user('7f7a0000-0000-0000-0000-0000000000a1');
  PERFORM public.create_planning_category('7f7c0000-0000-0000-0000-000000000001', '7f7b0000-0000-0000-0000-000000000001',
    'Home', (public.planning_v2_icons())[1], (public.planning_v2_colors())[1]);
  PERFORM public.create_planning_entry('7f7d0000-0000-0000-0000-000000000001',
    '7f7c0000-0000-0000-0000-000000000001', 'October', false, 'GHS');
  PERFORM public.add_planning_block('7f7e0000-0000-0000-0000-000000000001',
    '7f7d0000-0000-0000-0000-000000000001', 'expenses', '{}'::jsonb, NULL, NULL, NULL);
END $$;

-- 1. A due date is saved, kept when an edit doesn't mention it, cleared by
--    null, and a date that doesn't exist is refused.
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.as_user('7f7a0000-0000-0000-0000-0000000000a1');
  v := public.save_planning_rich_item('7f7f0000-0000-0000-0000-000000000001', '7f7e0000-0000-0000-0000-000000000001', NULL,
    jsonb_build_object('label', 'Rent', 'amount_minor', 150000, 'due_date', (current_date + 3)::text), NULL);
  IF (v ->> 'due_date')::date IS DISTINCT FROM current_date + 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: due date not saved %', v;
  END IF;
  v := public.save_planning_rich_item('7f7f0000-0000-0000-0000-000000000001', '7f7e0000-0000-0000-0000-000000000001',
    (v ->> 'version')::int, jsonb_build_object('label', 'Rent', 'amount_minor', 160000), NULL);
  IF (v ->> 'due_date')::date IS DISTINCT FROM current_date + 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an edit without due_date (an older app) cleared it %', v;
  END IF;
  v := public.save_planning_rich_item('7f7f0000-0000-0000-0000-000000000001', '7f7e0000-0000-0000-0000-000000000001',
    (v ->> 'version')::int, jsonb_build_object('label', 'Rent', 'amount_minor', 160000, 'due_date', NULL), NULL);
  IF v ->> 'due_date' IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: null did not clear the due date'; END IF;
  BEGIN
    PERFORM public.save_planning_rich_item(gen_random_uuid(), '7f7e0000-0000-0000-0000-000000000001', NULL,
      jsonb_build_object('label', 'Water', 'amount_minor', 100, 'due_date', '2026-02-30'), NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: 30 February accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.save_planning_rich_item(gen_random_uuid(), '7f7e0000-0000-0000-0000-000000000001', NULL,
      jsonb_build_object('label', 'Water', 'amount_minor', 100, 'due_date', 'soon'), NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-date accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF;
  END;
END $$;

-- 2. On the calendar on its due date, marked as an expense, paid or not.
DO $$
DECLARE v_ref jsonb;
BEGIN
  PERFORM pg_temp.as_user('7f7a0000-0000-0000-0000-0000000000a1');
  PERFORM public.save_planning_rich_item('7f7f0000-0000-0000-0000-000000000002', '7f7e0000-0000-0000-0000-000000000001', NULL,
    jsonb_build_object('label', 'Electricity', 'amount_minor', 30000, 'due_date', (current_date + 5)::text), NULL);
  SELECT t.source_ref INTO v_ref
  FROM public.together_items_for('7f7a0000-0000-0000-0000-0000000000a1', '7f7b0000-0000-0000-0000-000000000001',
    current_date, current_date + 10) t
  WHERE t.item_kind = 'planning_item' AND t.item_id = '7f7f0000-0000-0000-0000-000000000002'
    AND t.item_date = current_date + 5;
  IF v_ref IS NULL OR v_ref ->> 'block_type' IS DISTINCT FROM 'expenses'
     OR (v_ref ->> 'is_complete')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the bill is not on the calendar as an unpaid expense %', v_ref;
  END IF;
END $$;

-- 3. "Start the next one": a past due date moves to the same day in the
--    first month that isn't past; a future one stays; paid resets.
DO $$
DECLARE v_copy jsonb; v_rent date; v_elec date; v_paid int;
BEGIN
  PERFORM pg_temp.as_user('7f7a0000-0000-0000-0000-0000000000a1');
  UPDATE public.planning_block_items SET due_date = current_date - 40, checked_at = now()
  WHERE id = '7f7f0000-0000-0000-0000-000000000001';
  v_copy := public.duplicate_planning_entry('7f7d0000-0000-0000-0000-000000000001',
    '7f7d0000-0000-0000-0000-000000000002', 'November');
  SELECT i.due_date INTO v_rent FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
  WHERE b.entry_id = '7f7d0000-0000-0000-0000-000000000002' AND i.text = 'Rent';
  SELECT i.due_date INTO v_elec FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
  WHERE b.entry_id = '7f7d0000-0000-0000-0000-000000000002' AND i.text = 'Electricity';
  IF v_rent IS NULL OR v_rent < current_date OR v_rent >= current_date + interval '1 month'
     OR extract(day FROM v_rent) <> least(extract(day FROM current_date - 40),
          extract(day FROM (date_trunc('month', v_rent) + interval '1 month - 1 day'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a past due date did not move to its next month (% from %)', v_rent, current_date - 40;
  END IF;
  IF v_elec IS DISTINCT FROM current_date + 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a future due date moved (%)', v_elec;
  END IF;
  SELECT count(*) INTO v_paid FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
  WHERE b.entry_id = '7f7d0000-0000-0000-0000-000000000002' AND i.checked_at IS NOT NULL;
  IF v_paid <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: paid copied into the next one'; END IF;
END $$;

-- 4. The Home & bills starter: an Expenses block of the usual bills and a
--    Budget, no table; a new couple's template is built from it.
DO $$
DECLARE v_blocks jsonb; v_types text[]; v_lines text[];
BEGIN
  SELECT blocks INTO v_blocks FROM public.planning_starter_templates WHERE seed_key = 'home_bills';
  SELECT array_agg(b ->> 'type' ORDER BY n) INTO v_types FROM jsonb_array_elements(v_blocks) WITH ORDINALITY AS t(b, n);
  IF v_types[1] <> 'expenses' OR NOT ('budget' = ANY(v_types)) OR 'table' = ANY(v_types) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Home & bills blocks %', v_types;
  END IF;
  PERFORM pg_temp.as_user('7f7a0000-0000-0000-0000-0000000000a1');
  PERFORM public.get_planning_home('7f7b0000-0000-0000-0000-000000000001');  -- seeds the starters
  SELECT array_agg(i.text ORDER BY i.sort_key) INTO v_lines
  FROM public.planning_categories c
  JOIN public.planning_entries t ON t.category_id = c.id AND t.is_template AND t.deleted_at IS NULL
  JOIN public.planning_blocks b ON b.entry_id = t.id AND b.block_type = 'expenses' AND b.deleted_at IS NULL
  JOIN public.planning_block_items i ON i.block_id = b.id AND i.deleted_at IS NULL
  WHERE c.relationship_id = '7f7b0000-0000-0000-0000-000000000001' AND c.seed_key = 'home_bills';
  IF v_lines IS DISTINCT FROM ARRAY['Rent', 'Electricity', 'Water', 'Internet', 'TV'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Home & bills template lines %', v_lines;
  END IF;
END $$;

ROLLBACK;
