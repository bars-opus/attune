-- Planning P4: couple blocks (date poll, countdown, progress, dual clock),
-- time zones, notifications, gallery templates and the full starters.
-- Run: psql -q -d attune_planning -f supabase/tests/planning_couple_blocks_contracts.sql
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := '33000000-0000-0000-0000-000000000001';
  v_a uuid := '33000000-0000-0000-0000-0000000000a1';
  v_b uuid := '33000000-0000-0000-0000-0000000000b1';
  v_x uuid := '33000000-0000-0000-0000-0000000000e1';
  v_trips uuid; v_goals uuid;
  v_trip uuid := '33000000-0000-0000-0000-00000000e001';
  v_goal uuid := '33000000-0000-0000-0000-00000000e002';
  v_goal2 uuid := '33000000-0000-0000-0000-00000000e003';
  v_copy uuid := '33000000-0000-0000-0000-00000000e004';
  v_poll uuid := '33000000-0000-0000-0000-00000000b001';
  v_cd uuid := '33000000-0000-0000-0000-00000000b002';
  v_date2 uuid := '33000000-0000-0000-0000-00000000b003';
  v_prog uuid := '33000000-0000-0000-0000-00000000b004';
  v_list uuid := '33000000-0000-0000-0000-00000000b005';
  v_prog2 uuid := '33000000-0000-0000-0000-00000000b006';
  v_clock uuid := '33000000-0000-0000-0000-00000000b007';
  v_o1 uuid := '33000000-0000-0000-0000-0000000001a1';
  v_o2 uuid := '33000000-0000-0000-0000-0000000001a2';
  v_cat uuid := '33000000-0000-0000-0000-00000000c001';
  v_c1 uuid := '33000000-0000-0000-0000-0000000002a1';
  v_c2 uuid := '33000000-0000-0000-0000-0000000002a2';
  v_tbl uuid := '33000000-0000-0000-0000-00000000b008';
  v_row uuid := '33000000-0000-0000-0000-0000000003a1';
  v_copy2 uuid := '33000000-0000-0000-0000-00000000e005';
  v_r jsonb; v_d jsonb; v_n int; v_i int; v_t text;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_a,'cb_a@t.test'),(v_b,'cb_b@t.test'),(v_x,'cb_x@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a,'+13300000001','Ama'),(v_b,'+13300000002','Kofi'),(v_x,'+13300000003','X') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_a, v_b, 'active') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  PERFORM public.get_planning_home(v_rel);
  SELECT id INTO v_trips FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'trips';
  SELECT id INTO v_goals FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'goals';

  -- Contract 1: the starters carry their full block lists (spec §4.1).
  SELECT array_to_string(array_agg(b.block_type ORDER BY b.sort_key), ',') INTO v_t
  FROM public.planning_blocks b JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE e.category_id = v_trips AND e.is_template AND b.deleted_at IS NULL;
  IF v_t <> 'photo,date_poll,countdown,place,budget,expenses,link,table,checklist,text' THEN
    RAISE EXCEPTION 'EXPLOIT: trips template is %', v_t;
  END IF;
  SELECT array_to_string(array_agg(b.block_type ORDER BY b.sort_key), ',') INTO v_t
  FROM public.planning_blocks b JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE e.category_id = v_goals AND e.is_template AND b.deleted_at IS NULL;
  IF v_t <> 'progress,date,text,checklist' THEN RAISE EXCEPTION 'EXPLOIT: goals template is %', v_t; END IF;

  -- Blank plans to work in.
  PERFORM public.create_planning_entry(v_trip, v_trips, 'Bali', false, 'IDR');
  PERFORM public.create_planning_entry(v_goal, v_goals, 'House deposit', false, 'GHS');
  PERFORM public.create_planning_entry(v_goal2, v_goals, 'Read 2 books', false, 'GHS');

  -- Contract 2: poll options are date ranges; adding them tells the partner once an hour.
  PERFORM public.add_planning_block(v_poll, v_trip, 'date_poll', '{"title":"Pick dates"}', NULL, NULL, NULL);
  PERFORM public.save_planning_rich_item(v_o1, v_poll, NULL, '{"date_start":"2026-11-20","date_end":"2026-11-25"}', NULL);
  PERFORM public.save_planning_rich_item(v_o2, v_poll, NULL, '{"date_start":"2026-12-04","date_end":"2026-12-09"}', v_o1);
  BEGIN
    PERFORM public.save_planning_rich_item(gen_random_uuid(), v_poll, NULL, '{"date_start":"2026-12-09","date_end":"2026-12-04"}', NULL);
    RAISE EXCEPTION 'EXPLOIT: a backwards date range accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  SELECT count(*) INTO v_n FROM public.scheduled_notifications WHERE source_key LIKE 'planning_poll:' || v_poll || ':%';
  IF v_n <> 1 THEN RAISE EXCEPTION 'EXPLOIT: poll pushes not debounced to one (%)', v_n; END IF;
  SELECT metadata INTO v_r FROM public.scheduled_notifications WHERE source_key LIKE 'planning_poll:' || v_poll || ':%';
  IF (SELECT user_id FROM public.scheduled_notifications WHERE source_key LIKE 'planning_poll:' || v_poll || ':%') <> v_b
     OR v_r ->> 'type' <> 'planning_entry' OR v_r ->> 'entry_id' <> v_trip::text
     OR v_r ->> 'body' <> 'Ama suggested dates for Bali' THEN
    RAISE EXCEPTION 'EXPLOIT: poll push wrong: %', v_r;
  END IF;

  -- Contract 3: votes; the poll locks only on an option both partners chose.
  PERFORM public.vote_planning_poll(v_o1, true);
  PERFORM public.vote_planning_poll(v_o1, true);  -- idempotent
  SELECT count(*) INTO v_n FROM public.planning_poll_votes WHERE item_id = v_o1;
  IF v_n <> 1 THEN RAISE EXCEPTION 'EXPLOIT: double vote stored (%)', v_n; END IF;
  BEGIN PERFORM public.lock_planning_poll(v_poll, v_o1); RAISE EXCEPTION 'EXPLOIT: locked with one vote';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_b), true);
  PERFORM public.vote_planning_poll(v_o2, true);
  PERFORM public.vote_planning_poll(v_o2, false);
  v_r := public.vote_planning_poll(v_o1, true);
  SELECT i INTO v_d FROM jsonb_array_elements(v_r -> 'items') i WHERE i ->> 'id' = v_o1::text;
  IF jsonb_array_length(v_d -> 'votes') <> 2 THEN RAISE EXCEPTION 'EXPLOIT: votes not shown on the option: %', v_d; END IF;
  SELECT i INTO v_d FROM jsonb_array_elements(v_r -> 'items') i WHERE i ->> 'id' = v_o2::text;
  IF jsonb_array_length(v_d -> 'votes') <> 0 THEN RAISE EXCEPTION 'EXPLOIT: an unvote kept the vote'; END IF;

  -- Contract 4: locking turns the poll into a Date block, options kept as history.
  v_r := public.lock_planning_poll(v_poll, v_o1);
  IF v_r ->> 'block_type' <> 'date' OR v_r ->> 'date_start' <> '2026-11-20' OR v_r ->> 'date_end' <> '2026-11-25'
     OR jsonb_array_length(v_r -> 'payload' -> 'poll_history') <> 2 OR jsonb_array_length(v_r -> 'items') <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: lock result wrong: %', v_r;
  END IF;
  BEGIN PERFORM public.lock_planning_poll(v_poll, v_o1); RAISE EXCEPTION 'EXPLOIT: locked twice';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT IN ('planning:invalid_input', 'planning:not_found') THEN RAISE; END IF; END;
  v_r := public.update_planning_block(v_poll, (v_r ->> 'version')::int, '{"title":"Trip dates","poll_history":[]}', '2026-11-21', '2026-11-25');
  IF jsonb_array_length(v_r -> 'payload' -> 'poll_history') <> 2 THEN
    RAISE EXCEPTION 'EXPLOIT: a client edit rewrote poll history';
  END IF;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);

  -- Contract 5: a countdown counts to the plan's date, or to the Date block it names.
  PERFORM public.add_planning_block(v_cd, v_trip, 'countdown', '{}', NULL, NULL, NULL);
  SELECT b INTO v_d FROM jsonb_array_elements(public.get_planning_entry(v_trip) -> 'blocks') b WHERE b ->> 'id' = v_cd::text;
  IF v_d -> 'computed' ->> 'target_date' <> '2026-11-21' THEN RAISE EXCEPTION 'EXPLOIT: countdown target %', v_d -> 'computed'; END IF;
  PERFORM public.add_planning_block(v_date2, v_trip, 'date', '{"title":"Flight"}', '2026-11-19', NULL, NULL);
  v_r := public.update_planning_block(v_cd, 1, jsonb_build_object('date_block_id', v_date2), NULL, NULL);
  IF v_r -> 'computed' ->> 'target_date' <> '2026-11-19' THEN RAISE EXCEPTION 'EXPLOIT: named date ignored'; END IF;
  BEGIN PERFORM public.update_planning_block(v_cd, 2, '{"date_block_id":"tomorrow"}', NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: a malformed date reference accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 6: countdown pushes at 08:00 local, once per partner per day.
  BEGIN PERFORM public.set_planning_timezone(v_rel, 'Mars/Olympus'); RAISE EXCEPTION 'EXPLOIT: bogus time zone accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  PERFORM public.set_planning_timezone(v_rel, 'Asia/Makassar');   -- Ama: UTC+8; Kofi: unset = UTC
  IF has_function_privilege('authenticated', 'public.planning_enqueue_countdown_pushes(timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: clients can trigger countdown pushes';
  END IF;
  PERFORM public.planning_enqueue_countdown_pushes('2026-11-19 01:30+00');  -- Ama 09:30, Kofi 01:30
  PERFORM public.planning_enqueue_countdown_pushes('2026-11-19 02:30+00');  -- re-run: no duplicate
  SELECT count(*) FILTER (WHERE user_id = v_a), count(*) FILTER (WHERE user_id = v_b) INTO v_n, v_i
  FROM public.scheduled_notifications WHERE source_key LIKE 'planning_countdown:' || v_cd || ':%';
  IF v_n <> 1 OR v_i <> 0 THEN RAISE EXCEPTION 'EXPLOIT: countdown pushes wrong (Ama %, Kofi %)', v_n, v_i; END IF;
  PERFORM public.planning_enqueue_countdown_pushes('2026-11-19 08:10+00');  -- Kofi's 08:10
  SELECT count(*) FILTER (WHERE user_id = v_a), count(*) FILTER (WHERE user_id = v_b) INTO v_n, v_i
  FROM public.scheduled_notifications WHERE source_key LIKE 'planning_countdown:' || v_cd || ':%';
  IF v_n <> 1 OR v_i <> 1 THEN RAISE EXCEPTION 'EXPLOIT: countdown pushes wrong later (Ama %, Kofi %)', v_n, v_i; END IF;

  -- Contract 7: numeric progress celebrates once in chat when a Goal reaches 100%.
  PERFORM public.add_planning_block(v_prog, v_goal, 'progress', '{"mode":"numeric","unit":"money"}', NULL, NULL, NULL);
  PERFORM public.update_planning_block_target(v_prog, 1, 100000, 'GHS');
  PERFORM public.save_planning_rich_item(gen_random_uuid(), v_prog, NULL, '{"amount_minor":60000,"label":"Bonus"}', NULL);
  SELECT b INTO v_d FROM jsonb_array_elements(public.get_planning_entry(v_goal) -> 'blocks') b WHERE b ->> 'id' = v_prog::text;
  IF (v_d -> 'computed' ->> 'current')::int <> 60000 THEN RAISE EXCEPTION 'EXPLOIT: progress current %', v_d -> 'computed'; END IF;
  SELECT count(*) INTO v_n FROM public.messages WHERE relationship_id = v_rel AND is_system_notice;
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: celebrated early'; END IF;
  PERFORM public.save_planning_rich_item(gen_random_uuid(), v_prog, NULL, '{"amount_minor":40000}', NULL);
  PERFORM public.save_planning_rich_item(gen_random_uuid(), v_prog, NULL, '{"amount_minor":5000}', NULL);
  SELECT count(*) INTO v_n FROM public.messages WHERE relationship_id = v_rel AND is_system_notice AND content LIKE '%House deposit%';
  IF v_n <> 1 THEN RAISE EXCEPTION 'EXPLOIT: celebration count %', v_n; END IF;

  -- Contract 8: checklist progress follows the plan's checklist.
  PERFORM public.add_planning_block(v_list, v_goal2, 'checklist', '{"title":"Books"}', NULL, NULL, NULL);
  PERFORM public.add_planning_block_item(v_c1, v_list, 'Book one', NULL, NULL, NULL, NULL);
  PERFORM public.add_planning_block_item(v_c2, v_list, 'Book two', NULL, NULL, NULL, v_c1);
  PERFORM public.add_planning_block(v_prog2, v_goal2, 'progress', '{"mode":"checklist"}', NULL, NULL, NULL);
  PERFORM public.set_planning_block_item_checked(v_c1, true, gen_random_uuid());
  SELECT b INTO v_d FROM jsonb_array_elements(public.get_planning_entry(v_goal2) -> 'blocks') b WHERE b ->> 'id' = v_prog2::text;
  IF (v_d -> 'computed' ->> 'done')::int <> 1 OR (v_d -> 'computed' ->> 'total')::int <> 2 THEN
    RAISE EXCEPTION 'EXPLOIT: checklist progress %', v_d -> 'computed';
  END IF;
  PERFORM public.set_planning_block_item_checked(v_c2, true, gen_random_uuid());
  SELECT count(*) INTO v_n FROM public.messages WHERE relationship_id = v_rel AND is_system_notice AND content LIKE '%Read 2 books%';
  IF v_n <> 1 THEN RAISE EXCEPTION 'EXPLOIT: checklist goal not celebrated (%)', v_n; END IF;
  BEGIN PERFORM public.add_planning_block(gen_random_uuid(), v_goal2, 'progress', '{"mode":"vibes"}', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: unknown progress mode accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 9: dual clock stores nothing but a title.
  PERFORM public.add_planning_block(v_clock, v_trip, 'dual_clock', '{"title":"Our time"}', NULL, NULL, NULL);
  BEGIN PERFORM public.add_planning_block(gen_random_uuid(), v_trip, 'dual_clock', '{"city":"Lagos"}', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: dual clock stored a location';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 9b: the dual clock converts the partner's zone on the server.
  IF public.planning_timezone_offset_minutes('Asia/Makassar') <> 480
     OR public.planning_timezone_offset_minutes('UTC') <> 0
     OR public.planning_timezone_offset_minutes('Mars/Olympus') IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: time zone offsets wrong';
  END IF;

  -- Contract 10: "Start next one" re-points references at the copy and does not share files.
  v_r := public.duplicate_planning_entry(v_trip, v_copy, 'Bali again');
  SELECT b INTO v_d FROM jsonb_array_elements(v_r -> 'blocks') b WHERE b ->> 'block_type' = 'countdown';
  IF (v_d -> 'payload' ->> 'date_block_id')::uuid = v_date2
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_r -> 'blocks') b
                    WHERE b ->> 'id' = v_d -> 'payload' ->> 'date_block_id' AND b -> 'payload' ->> 'title' = 'Flight') THEN
    RAISE EXCEPTION 'EXPLOIT: the copy''s countdown points at the old plan: %', v_d -> 'payload';
  END IF;

  -- Contract 10b: a copy starts a new occasion: no ticks in check columns,
  -- no progress contributions (review I1).
  PERFORM public.add_planning_block(v_tbl, v_goal, 'table',
    '{"title":"Bills","columns":[{"key":"c0","label":"Bill","type":"text"},{"key":"c1","label":"Paid","type":"check"},{"key":"c2","label":"Who","type":"text"}]}',
    NULL, NULL, NULL);
  PERFORM public.save_planning_rich_item(v_row, v_tbl, NULL, '{"cells":{"c0":"Rent","c1":true,"c2":"Ama"}}', NULL);
  v_r := public.duplicate_planning_entry(v_goal, v_copy2, 'House deposit 2');
  SELECT b INTO v_d FROM jsonb_array_elements(v_r -> 'blocks') b WHERE b ->> 'block_type' = 'progress';
  IF jsonb_array_length(v_d -> 'items') <> 0 THEN RAISE EXCEPTION 'EXPLOIT: contributions copied: %', v_d -> 'items'; END IF;
  SELECT b INTO v_d FROM jsonb_array_elements(v_r -> 'blocks') b WHERE b ->> 'block_type' = 'table';
  IF v_d -> 'items' -> 0 -> 'cells' ? 'c1' OR v_d -> 'items' -> 0 -> 'cells' ->> 'c0' <> 'Rent' THEN
    RAISE EXCEPTION 'EXPLOIT: copied row cells wrong: %', v_d -> 'items' -> 0 -> 'cells';
  END IF;

  -- Contract 10c: changing a column's type or removing it clears those cells (review I3).
  v_r := public.update_planning_block(v_tbl, 1,
    '{"title":"Bills","columns":[{"key":"c0","label":"Bill","type":"text"},{"key":"c1","label":"Paid","type":"money"}]}', NULL, NULL);
  SELECT cells INTO v_d FROM public.planning_block_items WHERE id = v_row;
  IF v_d ? 'c1' OR v_d ? 'c2' OR v_d ->> 'c0' <> 'Rent' THEN RAISE EXCEPTION 'EXPLOIT: stale cells kept: %', v_d; END IF;

  -- Contract 11: gallery templates make a ready category.
  IF NOT (SELECT bool_and(k IN (SELECT g ->> 'key' FROM jsonb_array_elements(public.list_planning_gallery()) g))
          FROM unnest(ARRAY['next_visit','moving_house','wedding','baby']) k) THEN
    RAISE EXCEPTION 'EXPLOIT: gallery incomplete: %', public.list_planning_gallery();
  END IF;
  -- Wishlist and Diet are starters now, so the gallery no longer offers them.
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(public.list_planning_gallery()) g WHERE g ->> 'key' IN ('wishlist','diet')) THEN
    RAISE EXCEPTION 'EXPLOIT: a starter is still offered in the gallery';
  END IF;
  SELECT array_to_string(array_agg(b.block_type ORDER BY b.sort_key), ',') INTO v_t
  FROM public.planning_blocks b JOIN public.planning_entries e ON e.id = b.entry_id
  JOIN public.planning_categories c ON c.id = e.category_id
  WHERE c.relationship_id = v_rel AND c.seed_key = 'diet' AND e.is_template AND b.deleted_at IS NULL;
  IF v_t IS DISTINCT FROM 'table,checklist,progress' THEN RAISE EXCEPTION 'EXPLOIT: diet starter is %', v_t; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'wishlist' AND name = 'Wishlist') THEN
    RAISE EXCEPTION 'EXPLOIT: wishlist starter missing';
  END IF;
  v_r := public.create_planning_category_from_gallery(v_cat, v_rel, 'next_visit');
  v_r := public.create_planning_category_from_gallery(v_cat, v_rel, 'next_visit');  -- retry: idempotent
  SELECT array_to_string(array_agg(b.block_type ORDER BY b.sort_key), ',') INTO v_t
  FROM public.planning_blocks b JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE e.category_id = v_cat AND e.is_template AND b.deleted_at IS NULL;
  IF v_t <> 'countdown,date_poll,dual_clock,expenses,checklist,checklist' THEN RAISE EXCEPTION 'EXPLOIT: next visit is %', v_t; END IF;
  BEGIN PERFORM public.create_planning_category_from_gallery(gen_random_uuid(), v_rel, 'heist'); RAISE EXCEPTION 'EXPLOIT: unknown gallery key';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 12: strangers see nothing.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_x), true);
  BEGIN PERFORM public.vote_planning_poll(v_o2, true); RAISE EXCEPTION 'EXPLOIT: stranger voted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.set_planning_timezone(v_rel, 'UTC'); RAISE EXCEPTION 'EXPLOIT: stranger set a time zone';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.create_planning_category_from_gallery(gen_random_uuid(), v_rel, 'diet'); RAISE EXCEPTION 'EXPLOIT: stranger made a category';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;

  RAISE NOTICE 'PASS';
END $$;
ROLLBACK;
