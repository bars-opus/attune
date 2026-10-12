-- Planning v2: Notes starter, pins and entry restore (Notes & pins change).
-- Run: psql -q -d attune_planning -f supabase/tests/planning_v2_notes_pin_contracts.sql
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel  uuid := '30000000-0000-0000-0000-000000000001';
  v_rel2 uuid := '30000000-0000-0000-0000-000000000002';
  v_a uuid := '30000000-0000-0000-0000-0000000000a1';
  v_b uuid := '30000000-0000-0000-0000-0000000000b1';
  v_c uuid := '30000000-0000-0000-0000-0000000000c1';
  v_d uuid := '30000000-0000-0000-0000-0000000000d1';
  v_x uuid := '30000000-0000-0000-0000-0000000000e1';
  v_home jsonb;
  v_trips uuid;
  v_notes uuid;
  v_custom uuid := '30000000-0000-0000-0000-00000000c001';
  v_e1 uuid := '30000000-0000-0000-0000-00000000e001';
  v_e2 uuid := '30000000-0000-0000-0000-00000000e002';
  v_gone_block uuid;
  v_r jsonb;
  v_page jsonb;
  v_n int;
  v_i int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_a,'np_a@t.test'),(v_b,'np_b@t.test'),(v_c,'np_c@t.test'),(v_d,'np_d@t.test'),(v_x,'np_x@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a,'+13000000001','A'),(v_b,'+13000000002','B'),(v_c,'+13000000003','C'),
    (v_d,'+13000000004','D'),(v_x,'+13000000005','X')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
    (v_rel, v_a, v_b, 'active'), (v_rel2, v_c, v_d, 'active')
  ON CONFLICT DO NOTHING;

  -- Contract 1: a new couple sees Notes FIRST, then the five other visible starters.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  v_home := public.get_planning_home(v_rel);
  IF (SELECT array_agg(c ->> 'seed_key' ORDER BY ord)
        FROM jsonb_array_elements(v_home -> 'categories') WITH ORDINALITY t(c, ord))
     IS DISTINCT FROM ARRAY['notes','goals','trips','date_nights','home_bills','groceries'] THEN
    RAISE EXCEPTION 'EXPLOIT: Notes not first: %', v_home;
  END IF;
  SELECT count(*) INTO v_n FROM public.planning_categories WHERE relationship_id = v_rel;
  IF v_n <> 7 THEN RAISE EXCEPTION 'EXPLOIT: expected 7 starters, got %', v_n; END IF;

  -- Contract 2: the Notes template is one empty text block (a blank sheet).
  SELECT id INTO v_notes FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'notes';
  SELECT count(*) INTO v_n FROM public.planning_blocks b JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE e.category_id = v_notes AND e.is_template AND b.deleted_at IS NULL
    AND b.block_type = 'text' AND coalesce(b.plain_text, '') = '';
  IF v_n <> 1 THEN RAISE EXCEPTION 'EXPLOIT: Notes template is not one empty text block (%)', v_n; END IF;

  -- Contract 3 (review M2): a couple seeded BEFORE Notes existed gets it at the
  -- top on the next home read, and the read does not fail.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_c), true);
  PERFORM public.get_planning_home(v_rel2);
  DELETE FROM public.planning_categories WHERE relationship_id = v_rel2 AND seed_key = 'notes';
  PERFORM public.create_planning_category(gen_random_uuid(), v_rel2, 'Wedding', 'ring', 'rose');
  v_home := public.get_planning_home(v_rel2);
  IF v_home -> 'categories' -> 0 ->> 'seed_key' IS DISTINCT FROM 'notes' THEN
    RAISE EXCEPTION 'EXPLOIT: Notes not inserted at the top for an existing couple: %', v_home -> 'categories' -> 0;
  END IF;
  IF v_home -> 'categories' -> -1 ->> 'name' <> 'Wedding' THEN
    RAISE EXCEPTION 'EXPLOIT: existing order disturbed';
  END IF;

  -- Contract 4: the notepad icon is allowed.
  PERFORM public.create_planning_category(gen_random_uuid(), v_rel2, 'Journal', 'note', 'indigo');

  -- Contract 5: pin moves an entry out of the paged list into `pinned`; unpin puts it back.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  SELECT id INTO v_trips FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'trips';
  PERFORM public.create_planning_entry(v_e1, v_trips, 'Bali', true, 'USD');
  PERFORM public.create_planning_entry(v_e2, v_trips, 'Accra', false, 'USD');
  v_r := public.pin_planning_entry(v_e1, true);
  IF v_r -> 'entry' ->> 'pinned_at' IS NULL THEN RAISE EXCEPTION 'EXPLOIT: pin not recorded'; END IF;
  v_page := public.list_planning_entries(v_trips, 'open', NULL, NULL, 30);
  IF jsonb_array_length(v_page -> 'pinned') <> 1 OR v_page -> 'pinned' -> 0 ->> 'id' <> v_e1::text
     OR NOT (v_page -> 'pinned' -> 0 ->> 'pinned')::boolean THEN
    RAISE EXCEPTION 'EXPLOIT: pinned group wrong: %', v_page -> 'pinned';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_page -> 'entries') x WHERE x ->> 'id' = v_e1::text) THEN
    RAISE EXCEPTION 'EXPLOIT: pinned entry duplicated in the paged list';
  END IF;
  -- pinning again is idempotent: the original pin time is kept
  IF (public.pin_planning_entry(v_e1, true) -> 'entry' ->> 'pinned_at') <> (v_r -> 'entry' ->> 'pinned_at') THEN
    RAISE EXCEPTION 'EXPLOIT: re-pin moved the pin time';
  END IF;
  PERFORM public.pin_planning_entry(v_e1, false);
  v_page := public.list_planning_entries(v_trips, 'open', NULL, NULL, 30);
  IF jsonb_array_length(v_page -> 'pinned') <> 0 OR jsonb_array_length(v_page -> 'entries') <> 2 THEN
    RAISE EXCEPTION 'EXPLOIT: unpin did not return the entry to the list';
  END IF;

  -- Contract 6: a pinned entry is never also returned by a later page.
  FOR v_i IN 1..33 LOOP
    PERFORM public.create_planning_entry(gen_random_uuid(), v_trips, 'Trip ' || v_i, false, 'USD');
  END LOOP;
  PERFORM public.pin_planning_entry(v_e2, true);
  v_page := public.list_planning_entries(v_trips, 'open', NULL, NULL, 30);
  v_n := jsonb_array_length(v_page -> 'entries');
  v_page := public.list_planning_entries(v_trips, 'open',
    (v_page -> 'next_cursor' ->> 'at')::timestamptz, (v_page -> 'next_cursor' ->> 'id')::uuid, 30);
  IF v_n + jsonb_array_length(v_page -> 'entries') <> 34 OR jsonb_array_length(v_page -> 'pinned') <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: paging with a pin returned % entries (expected 34 unpinned)',
      v_n + jsonb_array_length(v_page -> 'entries');
  END IF;

  -- Contract 7: pins follow the status group (a pinned plan marked done is pinned under closed).
  PERFORM public.update_planning_entry(v_e2, 'Accra', 'done');
  IF jsonb_array_length(public.list_planning_entries(v_trips, 'open', NULL, NULL, 30) -> 'pinned') <> 0
     OR jsonb_array_length(public.list_planning_entries(v_trips, 'closed', NULL, NULL, 30) -> 'pinned') <> 1 THEN
    RAISE EXCEPTION 'EXPLOIT: pinned group ignores status';
  END IF;

  -- Contract 8: templates cannot be pinned; at most 20 pins per category.
  BEGIN
    PERFORM public.pin_planning_entry(
      (SELECT id FROM public.planning_entries WHERE category_id = v_trips AND is_template), true);
    RAISE EXCEPTION 'EXPLOIT: template pinned';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  FOR v_r IN SELECT to_jsonb(e) FROM public.planning_entries e
             WHERE e.category_id = v_trips AND NOT e.is_template AND e.pinned_at IS NULL AND e.status = 'active'
               AND e.id <> v_e1   -- v_e1 must stay unpinned: it is the 21st pin below
             ORDER BY e.id LIMIT 19 LOOP
    PERFORM public.pin_planning_entry((v_r ->> 'id')::uuid, true);
  END LOOP;
  BEGIN
    PERFORM public.pin_planning_entry(v_e1, true);
    RAISE EXCEPTION 'EXPLOIT: 21st pin accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:limit_reached' THEN RAISE; END IF;
  END;

  -- Contract 9: a stranger can neither pin nor restore.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_x), true);
  BEGIN PERFORM public.pin_planning_entry(v_e1, true); RAISE EXCEPTION 'EXPLOIT: stranger pinned';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);

  -- Contract 10: restore brings back exactly what that delete removed — not a
  -- block the couple had deleted earlier on its own.
  SELECT id INTO v_gone_block FROM public.planning_blocks WHERE entry_id = v_e1 AND deleted_at IS NULL
  ORDER BY sort_key LIMIT 1;
  PERFORM public.delete_planning_block(v_gone_block);
  SELECT count(*) INTO v_n FROM public.planning_blocks WHERE entry_id = v_e1 AND deleted_at IS NULL;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_x), true);
  BEGIN PERFORM public.restore_planning_entry(v_e1); RAISE EXCEPTION 'EXPLOIT: stranger restored';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  BEGIN PERFORM public.restore_planning_entry(v_e1); RAISE EXCEPTION 'EXPLOIT: restored a live entry';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  -- separate transactions in the app; simulate by moving the block delete back in time
  UPDATE public.planning_blocks SET deleted_at = now() - interval '1 minute' WHERE id = v_gone_block;
  PERFORM public.delete_planning_entry(v_e1);
  v_r := public.restore_planning_entry(v_e1);
  IF v_r -> 'entry' ->> 'id' <> v_e1::text THEN RAISE EXCEPTION 'EXPLOIT: restore returned %', v_r; END IF;
  IF (SELECT count(*) FROM public.planning_blocks WHERE entry_id = v_e1 AND deleted_at IS NULL) <> v_n THEN
    RAISE EXCEPTION 'EXPLOIT: restore brought back the wrong blocks';
  END IF;
  IF (SELECT deleted_at FROM public.planning_blocks WHERE id = v_gone_block) IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: restore resurrected a block deleted earlier';
  END IF;

  -- Contract 11: no restore into a deleted category.
  PERFORM public.create_planning_category(v_custom, v_rel, 'Moving', 'box', 'orange');
  PERFORM public.create_planning_entry(gen_random_uuid(), v_custom, 'Boxes', false, 'USD');
  SELECT id INTO v_e1 FROM public.planning_entries WHERE category_id = v_custom AND NOT is_template;
  PERFORM public.delete_planning_entry(v_e1);
  PERFORM public.delete_planning_category(v_custom);
  BEGIN PERFORM public.restore_planning_entry(v_e1); RAISE EXCEPTION 'EXPLOIT: restored into a deleted category';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;

  -- Contract 12: grants.
  IF has_function_privilege('anon', 'public.pin_planning_entry(uuid, boolean)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.pin_planning_entry(uuid, boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.restore_planning_entry(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.restore_planning_entry(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: pin/restore grants wrong';
  END IF;

  RAISE NOTICE 'planning_v2_notes_pin_contracts: PASS';
END $$;
ROLLBACK;
