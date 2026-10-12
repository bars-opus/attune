-- Planning calendar feed and Conversations summary on the new model (spec §16).
-- Run: psql -q -d attune_planning -f supabase/tests/planning_feeds_contracts.sql
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := '31000000-0000-0000-0000-000000000001';
  v_a uuid := '31000000-0000-0000-0000-0000000000a1';
  v_b uuid := '31000000-0000-0000-0000-0000000000b1';
  v_x uuid := '31000000-0000-0000-0000-0000000000e1';
  v_trips uuid;
  v_groc uuid;
  v_trip uuid := '31000000-0000-0000-0000-00000000e001';
  v_shop uuid := '31000000-0000-0000-0000-00000000e002';
  v_gone uuid := '31000000-0000-0000-0000-00000000e003';
  v_date_block uuid := '31000000-0000-0000-0000-00000000b001';
  v_list uuid := '31000000-0000-0000-0000-00000000b002';
  v_gone_list uuid := '31000000-0000-0000-0000-00000000b003';
  v_milk uuid := '31000000-0000-0000-0000-0000000001a1';
  v_eggs uuid := '31000000-0000-0000-0000-0000000001a2';
  v_bread uuid := '31000000-0000-0000-0000-0000000001a3';
  v_ghost uuid := '31000000-0000-0000-0000-0000000001a4';
  v_rows int;
  v_s record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_a,'pf_a@t.test'),(v_b,'pf_b@t.test'),(v_x,'pf_x@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a,'+13100000001','A'),(v_b,'+13100000002','B'),(v_x,'+13100000003','X') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_a, v_b, 'active') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);

  -- Contract 1: nothing planned -> no summary row (the card says "Start planning together").
  SELECT count(*) INTO v_rows FROM public.get_planning_summary(v_rel, '2026-11-10');
  IF v_rows <> 0 THEN RAISE EXCEPTION 'EXPLOIT: empty Planning produced a summary'; END IF;

  PERFORM public.get_planning_home(v_rel);
  SELECT id INTO v_trips FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'trips';
  SELECT id INTO v_groc  FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'groceries';
  PERFORM public.create_planning_entry(v_trip, v_trips, 'Bali', false, 'USD');
  PERFORM public.add_planning_block(v_date_block, v_trip, 'date', '{}', '2026-11-28', '2026-12-03', NULL);
  PERFORM public.create_planning_entry(v_shop, v_groc, 'Saturday shop', false, 'USD');
  PERFORM public.add_planning_block(v_list, v_shop, 'checklist', '{}', NULL, NULL, NULL);
  PERFORM public.add_planning_block_item(v_milk,  v_list, 'Milk',  NULL, NULL, '2026-11-05', NULL);
  PERFORM public.add_planning_block_item(v_eggs,  v_list, 'Eggs',  NULL, NULL, '2026-11-08', v_milk);
  PERFORM public.add_planning_block_item(v_bread, v_list, 'Bread', NULL, NULL, '2026-11-14', v_eggs);

  -- Contract 2 (Review Focus 2): a date range shows on every day inside the window and nowhere outside it.
  SELECT count(*) INTO v_rows FROM public.list_planning_calendar_entries(v_rel, '2026-11-01', '2026-11-30')
  WHERE entry_kind = 'date' AND entry_id = v_trip;
  IF v_rows <> 3 THEN RAISE EXCEPTION 'EXPLOIT: trip should show on Nov 28-30 only, got % days', v_rows; END IF;
  IF EXISTS (SELECT 1 FROM public.list_planning_calendar_entries(v_rel, '2026-11-01', '2026-11-30')
             WHERE entry_date NOT BETWEEN '2026-11-01' AND '2026-11-30') THEN
    RAISE EXCEPTION 'EXPLOIT: calendar returned a day outside the window';
  END IF;

  -- Contract 3: dated items appear on their due date, pointing at their plan; ticked ones are complete.
  PERFORM public.set_planning_block_item_checked(v_milk, true, gen_random_uuid());
  SELECT count(*) INTO v_rows FROM public.list_planning_calendar_entries(v_rel, '2026-11-01', '2026-11-30')
  WHERE entry_kind = 'item' AND entry_id = v_shop AND item_id = v_milk AND entry_date = '2026-11-05'
    AND title = 'Milk' AND is_complete;
  IF v_rows <> 1 THEN RAISE EXCEPTION 'EXPLOIT: ticked dated item not on its day as complete'; END IF;

  -- Contract 4 (Review Focus 3): items in a deleted block or plan never reach the feeds.
  PERFORM public.create_planning_entry(v_gone, v_groc, 'Old run', false, 'USD');
  PERFORM public.add_planning_block(v_gone_list, v_gone, 'checklist', '{}', NULL, NULL, NULL);
  PERFORM public.add_planning_block_item(v_ghost, v_gone_list, 'Ghost', NULL, NULL, '2026-11-02', NULL);
  PERFORM public.delete_planning_block(v_gone_list);
  IF EXISTS (SELECT 1 FROM public.list_planning_calendar_entries(v_rel, '2026-11-01', '2026-11-30') WHERE item_id = v_ghost)
     OR EXISTS (SELECT 1 FROM public.get_planning_summary(v_rel, '2026-11-10') WHERE title = 'Ghost') THEN
    RAISE EXCEPTION 'EXPLOIT: an item in a deleted block reached a feed';
  END IF;
  PERFORM public.restore_planning_block(v_gone_list);
  PERFORM public.delete_planning_entry(v_gone);
  IF EXISTS (SELECT 1 FROM public.list_planning_calendar_entries(v_rel, '2026-11-01', '2026-11-30') WHERE entry_id = v_gone) THEN
    RAISE EXCEPTION 'EXPLOIT: a deleted plan reached the calendar';
  END IF;

  -- Contract 5: the range bound and membership hold.
  BEGIN PERFORM public.list_planning_calendar_entries(v_rel, '2026-11-01', '2026-12-31');
    RAISE EXCEPTION 'EXPLOIT: a 60-day range was accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_x), true);
  BEGIN PERFORM public.list_planning_calendar_entries(v_rel, '2026-11-01', '2026-11-30');
    RAISE EXCEPTION 'EXPLOIT: a stranger read the calendar';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.get_planning_summary(v_rel, '2026-11-10');
    RAISE EXCEPTION 'EXPLOIT: a stranger read the summary';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);

  -- Contract 6: summary order. On Nov 10: Eggs (Nov 8, unticked) is overdue; Milk is ticked, so it is not.
  SELECT * INTO v_s FROM public.get_planning_summary(v_rel, '2026-11-10');
  IF v_s.kind <> 'overdue' OR v_s.title <> 'Eggs' OR v_s.entry_id <> v_shop OR v_s.context_date <> '2026-11-08' THEN
    RAISE EXCEPTION 'EXPLOIT: expected overdue Eggs, got % / % / %', v_s.kind, v_s.title, v_s.context_date;
  END IF;
  -- with Eggs ticked: the soonest upcoming is Bread (Nov 14), before the trip (Nov 28)
  PERFORM public.set_planning_block_item_checked(v_eggs, true, gen_random_uuid());
  SELECT * INTO v_s FROM public.get_planning_summary(v_rel, '2026-11-10');
  IF v_s.kind <> 'upcoming' OR v_s.title <> 'Bread' OR v_s.context_date <> '2026-11-14' THEN
    RAISE EXCEPTION 'EXPLOIT: expected upcoming Bread, got % / %', v_s.kind, v_s.title;
  END IF;
  -- upcoming dates count too: after Bread is ticked, the trip (a date block) is next, titled by its plan
  PERFORM public.set_planning_block_item_checked(v_bread, true, gen_random_uuid());
  SELECT * INTO v_s FROM public.get_planning_summary(v_rel, '2026-11-10');
  IF v_s.kind <> 'upcoming' OR v_s.title <> 'Bali' OR v_s.entry_id <> v_trip THEN
    RAISE EXCEPTION 'EXPLOIT: expected upcoming Bali, got % / %', v_s.kind, v_s.title;
  END IF;
  -- nothing dated ahead: the most recently active plan
  SELECT * INTO v_s FROM public.get_planning_summary(v_rel, '2027-01-10');
  IF v_s.kind <> 'recent' OR v_s.entry_id IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: expected a recent plan, got %', v_s.kind;
  END IF;

  -- Contract 7 (Review Focus 4): v1 is gone; the change signal survives, read-only.
  IF to_regclass('public.planning_items') IS NOT NULL OR to_regclass('public.planning_events') IS NOT NULL
     OR to_regclass('public.planning_notes') IS NOT NULL OR to_regclass('public.planning_event_tasks') IS NOT NULL
     OR to_regprocedure('public.create_planning_task(uuid,uuid,text,text,uuid,date)') IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: a v1 Planning object still exists';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.planning_change_signals', 'SELECT')
     OR has_table_privilege('authenticated', 'public.planning_change_signals', 'INSERT')
     OR has_table_privilege('authenticated', 'public.planning_change_signals', 'UPDATE') THEN
    RAISE EXCEPTION 'EXPLOIT: planning_change_signals grants wrong';
  END IF;
  IF has_function_privilege('anon', 'public.get_planning_summary(uuid, date)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.list_planning_calendar_entries(uuid, date, date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: feeds callable by anon';
  END IF;

  RAISE NOTICE 'planning_feeds_contracts: PASS';
END $$;
ROLLBACK;
