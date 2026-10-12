-- Planning v2 entry contracts (P1 Task 4).
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := '2d000000-0000-0000-0000-000000000001';
  v_a uuid := '2d000000-0000-0000-0000-0000000000a1';
  v_b uuid := '2d000000-0000-0000-0000-0000000000b1';
  v_x uuid := '2d000000-0000-0000-0000-0000000000e1';
  v_trips uuid;
  v_goals uuid;
  v_custom uuid := '2d000000-0000-0000-0000-00000000c001';
  v_e1 uuid := '2d000000-0000-0000-0000-00000000e001';
  v_e2 uuid := '2d000000-0000-0000-0000-00000000e002';
  v_dup uuid := '2d000000-0000-0000-0000-00000000e003';
  v_d jsonb;
  v_page jsonb;
  v_tpl uuid;
  v_n int;
  v_i int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_a,'v2e_a@t.test'),(v_b,'v2e_b@t.test'),(v_x,'v2e_x@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a,'+12300000001','Priya'),(v_b,'+12300000002','Sam'),(v_x,'+12300000003','X')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_a, v_b, 'active')
  ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  PERFORM public.get_planning_home(v_rel);
  SELECT id INTO v_trips FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'trips';
  SELECT id INTO v_goals FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'goals';

  -- Contract 1: create from template copies blocks + items, resetting checks.
  UPDATE public.planning_block_items i SET checked_at = now(), checked_by = v_b
  FROM public.planning_blocks b JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE i.block_id = b.id AND e.category_id = v_trips AND e.is_template;
  v_d := public.create_planning_entry(v_e1, v_trips, 'Bali, 10 days', true, 'IDR');
  IF jsonb_array_length(v_d -> 'blocks') <> 10 THEN RAISE EXCEPTION 'EXPLOIT: template copy block count %', jsonb_array_length(v_d -> 'blocks'); END IF;
  IF (v_d -> 'blocks' -> 8 ->> 'block_type') <> 'checklist'
     OR jsonb_array_length(v_d -> 'blocks' -> 8 -> 'items') <> 3 THEN
    RAISE EXCEPTION 'EXPLOIT: packing list not copied: %', v_d -> 'blocks' -> 8;
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_d -> 'blocks' -> 8 -> 'items') i WHERE i ->> 'checked_at' IS NOT NULL) THEN
    RAISE EXCEPTION 'EXPLOIT: copied items kept their ticks';
  END IF;
  IF v_d -> 'entry' ->> 'currency' <> 'IDR' OR (v_d -> 'entry' ->> 'is_template')::boolean THEN
    RAISE EXCEPTION 'EXPLOIT: entry fields wrong: %', v_d -> 'entry';
  END IF;
  IF jsonb_array_length(v_d -> 'members') <> 2 THEN RAISE EXCEPTION 'EXPLOIT: members missing'; END IF;

  -- Contract 2: blank create has no blocks.
  v_d := public.create_planning_entry(v_e2, v_trips, 'Weekend away', false, 'USD');
  IF jsonb_array_length(v_d -> 'blocks') <> 0 THEN RAISE EXCEPTION 'EXPLOIT: blank entry has blocks'; END IF;

  -- Contract 3: idempotent create; conflicting reuse rejected.
  v_d := public.create_planning_entry(v_e1, v_trips, 'Bali, 10 days', true, 'IDR');
  SELECT count(*) INTO v_n FROM public.planning_blocks WHERE entry_id = v_e1 AND deleted_at IS NULL;
  IF v_n <> 10 THEN RAISE EXCEPTION 'EXPLOIT: retry re-copied blocks (%)', v_n; END IF;
  BEGIN PERFORM public.create_planning_entry(v_e1, v_goals, 'Other', true, 'USD');
    RAISE EXCEPTION 'EXPLOIT: id reuse accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 4: stranger is refused everywhere with not_found.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_x), true);
  BEGIN PERFORM public.get_planning_entry(v_e1); RAISE EXCEPTION 'EXPLOIT: stranger read entry';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.list_planning_entries(v_trips, 'open', NULL, NULL, 30); RAISE EXCEPTION 'EXPLOIT: stranger listed';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.create_planning_entry(gen_random_uuid(), v_trips, 'x', false, 'USD'); RAISE EXCEPTION 'EXPLOIT: stranger created';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.delete_planning_entry(v_e1); RAISE EXCEPTION 'EXPLOIT: stranger deleted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);

  -- Contract 5: title validation, counted in characters.
  BEGIN PERFORM public.create_planning_entry(gen_random_uuid(), v_trips, '   ', false, 'USD'); RAISE EXCEPTION 'EXPLOIT: blank title';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.create_planning_entry(gen_random_uuid(), v_trips, repeat('a', 121), false, 'USD'); RAISE EXCEPTION 'EXPLOIT: 121 chars';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.create_planning_entry(gen_random_uuid(), v_trips, 'x', false, 'usd'); RAISE EXCEPTION 'EXPLOIT: bad currency';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  v_d := public.create_planning_entry(gen_random_uuid(), v_goals, repeat('🌴', 120), false, 'USD');
  IF char_length(v_d -> 'entry' ->> 'title') <> 120 THEN RAISE EXCEPTION 'EXPLOIT: emoji title mangled'; END IF;

  -- Contract 6: keyset pagination over 35 entries; newest activity first.
  FOR v_i IN 1..33 LOOP
    PERFORM public.create_planning_entry(gen_random_uuid(), v_trips, 'Trip ' || v_i, false, 'USD');
  END LOOP;
  v_page := public.list_planning_entries(v_trips, 'open', NULL, NULL, 30);
  IF jsonb_array_length(v_page -> 'entries') <> 30 OR v_page -> 'next_cursor' = 'null'::jsonb THEN
    RAISE EXCEPTION 'EXPLOIT: page 1 wrong: % entries, cursor %', jsonb_array_length(v_page -> 'entries'), v_page -> 'next_cursor';
  END IF;
  IF v_page -> 'entries' -> 0 ->> 'title' <> 'Trip 33' THEN RAISE EXCEPTION 'EXPLOIT: not newest first'; END IF;
  v_page := public.list_planning_entries(v_trips, 'open',
    (v_page -> 'next_cursor' ->> 'at')::timestamptz, (v_page -> 'next_cursor' ->> 'id')::uuid, 30);
  IF jsonb_array_length(v_page -> 'entries') <> 5 OR v_page -> 'next_cursor' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'EXPLOIT: page 2 wrong: %', v_page;
  END IF;
  -- template never listed
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_page -> 'entries') x WHERE x ->> 'title' = 'New trip') THEN
    RAISE EXCEPTION 'EXPLOIT: template listed as entry';
  END IF;
  -- limit is clamped to 100
  v_page := public.list_planning_entries(v_trips, 'open', NULL, NULL, 100000);
  IF jsonb_array_length(v_page -> 'entries') <> 35 THEN RAISE EXCEPTION 'EXPLOIT: clamp broke listing'; END IF;
  -- summary fields
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_page -> 'entries') x
                 WHERE x ->> 'id' = v_e1::text AND (x ->> 'checklist_total')::int = 3
                   AND (x ->> 'checklist_done')::int = 0) THEN
    RAISE EXCEPTION 'EXPLOIT: checklist summary wrong';
  END IF;

  -- Contract 7: status moves an entry between groups; template status is fixed.
  PERFORM public.update_planning_entry(v_e2, 'Weekend away', 'done');
  v_page := public.list_planning_entries(v_trips, 'closed', NULL, NULL, 30);
  IF jsonb_array_length(v_page -> 'entries') <> 1 THEN RAISE EXCEPTION 'EXPLOIT: closed group wrong'; END IF;
  SELECT id INTO v_tpl FROM public.planning_entries WHERE category_id = v_goals AND is_template;
  BEGIN PERFORM public.update_planning_entry(v_tpl, 'New goal', 'done'); RAISE EXCEPTION 'EXPLOIT: template closed';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.update_planning_entry(v_e2, 'x', 'deleted'); RAISE EXCEPTION 'EXPLOIT: bad status';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 8: renaming a template marks it edited (no auto-upgrade).
  PERFORM public.update_planning_entry(v_tpl, 'Our goal', 'active');
  IF (SELECT seed_version FROM public.planning_entries WHERE id = v_tpl) IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: edited template still upgradeable';
  END IF;

  -- Contract 9: reset restores the starter version.
  v_d := public.reset_planning_template(v_goals);
  IF jsonb_array_length(v_d -> 'blocks') <> 4 OR v_d -> 'entry' ->> 'title' <> 'New goal' THEN
    RAISE EXCEPTION 'EXPLOIT: reset wrong: %', v_d -> 'entry';
  END IF;
  IF (SELECT seed_version FROM public.planning_entries WHERE id = v_tpl) IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: reset did not restore seed_version';
  END IF;

  -- Contract 10: duplicate copies blocks, resets ticks, leaves source intact.
  UPDATE public.planning_block_items SET checked_at = now(), checked_by = v_a
  WHERE block_id IN (SELECT id FROM public.planning_blocks WHERE entry_id = v_e1);
  v_d := public.duplicate_planning_entry(v_e1, v_dup, 'Bali again');
  IF jsonb_array_length(v_d -> 'blocks') <> 10 THEN RAISE EXCEPTION 'EXPLOIT: duplicate lost blocks'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_d -> 'blocks') b, jsonb_array_elements(b -> 'items') i
             WHERE i ->> 'checked_at' IS NOT NULL) THEN
    RAISE EXCEPTION 'EXPLOIT: duplicate kept ticks';
  END IF;
  SELECT count(*) INTO v_n FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
  WHERE b.entry_id = v_e1 AND i.checked_at IS NOT NULL;
  IF v_n <> 5 THEN RAISE EXCEPTION 'EXPLOIT: duplicate changed the source'; END IF;  -- packing 3 + expense lines 2
  BEGIN PERFORM public.duplicate_planning_entry(v_tpl, gen_random_uuid(), 'x'); RAISE EXCEPTION 'EXPLOIT: template duplicated';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 11: delete; template delete refused; deleted entry is not_found.
  PERFORM public.delete_planning_entry(v_dup);
  BEGIN PERFORM public.get_planning_entry(v_dup); RAISE EXCEPTION 'EXPLOIT: deleted entry readable';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.delete_planning_entry(v_tpl); RAISE EXCEPTION 'EXPLOIT: template deleted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 12: cannot create inside a deleted category.
  PERFORM public.create_planning_category(v_custom, v_rel, 'Moving', 'box', 'orange');
  PERFORM public.delete_planning_category(v_custom);
  BEGIN PERFORM public.create_planning_entry(gen_random_uuid(), v_custom, 'x', false, 'USD'); RAISE EXCEPTION 'EXPLOIT: entry in deleted category';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;

  -- Contract 13: grants.
  IF has_function_privilege('anon', 'public.get_planning_entry(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_planning_entry(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.planning_v2_entry_detail(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: entry RPC grants wrong';
  END IF;

  RAISE NOTICE 'planning_v2_entry_contracts: PASS';
END $$;
ROLLBACK;
