-- Planning v2 block/item contracts (P1 Task 5).
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := '2e000000-0000-0000-0000-000000000001';
  v_a uuid := '2e000000-0000-0000-0000-0000000000a1';
  v_b uuid := '2e000000-0000-0000-0000-0000000000b1';
  v_x uuid := '2e000000-0000-0000-0000-0000000000e1';
  v_cat uuid;
  v_entry uuid := '2e000000-0000-0000-0000-00000000e001';
  v_text uuid := '2e000000-0000-0000-0000-00000000b001';
  v_list uuid := '2e000000-0000-0000-0000-00000000b002';
  v_date uuid := '2e000000-0000-0000-0000-00000000b003';
  v_i1 uuid := '2e000000-0000-0000-0000-0000000001a1';
  v_i2 uuid := '2e000000-0000-0000-0000-0000000001a2';
  v_op uuid := '2e000000-0000-0000-0000-00000000f001';
  v_r jsonb;
  v_hint text;
  v_n int;
  v_i int;
  v_tpl uuid;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_a,'v2b_a@t.test'),(v_b,'v2b_b@t.test'),(v_x,'v2b_x@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a,'+12400000001','Ama'),(v_b,'+12400000002','Kofi'),(v_x,'+12400000003','X')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_a, v_b, 'active')
  ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  PERFORM public.get_planning_home(v_rel);
  SELECT id INTO v_cat FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'groceries';
  PERFORM public.create_planning_entry(v_entry, v_cat, 'Saturday shop', false, 'GHS');

  -- Contract 1: add blocks in order; text derives plain_text.
  v_r := public.add_planning_block(v_text, v_entry, 'text',
    '{"delta":[{"insert":"Buy "},{"insert":"fresh","attributes":{"bold":true}},{"insert":"\n"}]}', NULL, NULL, NULL);
  IF v_r ->> 'plain_text' <> 'Buy fresh' OR (v_r ->> 'version')::int <> 1 THEN RAISE EXCEPTION 'EXPLOIT: text block wrong: %', v_r; END IF;
  PERFORM public.add_planning_block(v_list, v_entry, 'checklist', '{"title":"List"}', NULL, NULL, v_text);
  PERFORM public.add_planning_block(v_date, v_entry, 'date', '{}', '2026-10-17', NULL, v_list);
  SELECT array_agg(b ->> 'block_type' ORDER BY ord)::text INTO v_hint
  FROM jsonb_array_elements(public.get_planning_entry(v_entry) -> 'blocks') WITH ORDINALITY t(b, ord);
  IF v_hint <> '{text,checklist,date}' THEN RAISE EXCEPTION 'EXPLOIT: block order %', v_hint; END IF;

  -- Contract 2: idempotent add; id reuse with another type rejected.
  PERFORM public.add_planning_block(v_list, v_entry, 'checklist', '{"title":"List"}', NULL, NULL, v_text);
  SELECT count(*) INTO v_n FROM public.planning_blocks WHERE entry_id = v_entry AND deleted_at IS NULL;
  IF v_n <> 3 THEN RAISE EXCEPTION 'EXPLOIT: add retry duplicated (%)', v_n; END IF;
  BEGIN PERFORM public.add_planning_block(v_list, v_entry, 'date', '{}', NULL, NULL, NULL); RAISE EXCEPTION 'EXPLOIT: id reuse';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 3: an unknown block type is refused.
  BEGIN PERFORM public.add_planning_block(gen_random_uuid(), v_entry, 'spreadsheet', '{}', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: unknown block type added';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 4: version check — a stale save returns the current block in HINT.
  v_r := public.update_planning_block(v_text, 1, '{"delta":[{"insert":"Kofi edit\n"}]}', NULL, NULL);
  IF (v_r ->> 'version')::int <> 2 THEN RAISE EXCEPTION 'EXPLOIT: version not bumped'; END IF;
  BEGIN
    PERFORM public.update_planning_block(v_text, 1, '{"delta":[{"insert":"Ama edit\n"}]}', NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: stale save accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:stale_version' THEN RAISE; END IF;
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
    IF v_hint::jsonb -> 'current' ->> 'plain_text' <> 'Kofi edit' THEN
      RAISE EXCEPTION 'EXPLOIT: stale HINT lacks current block: %', v_hint;
    END IF;
  END;

  -- Contract 5: items — add, assign, reject stranger assignee.
  PERFORM public.add_planning_block_item(v_i1, v_list, 'Tomatoes', 'Produce', v_b, NULL, NULL);
  PERFORM public.add_planning_block_item(v_i2, v_list, 'Milk', 'Dairy', NULL, '2026-10-17', v_i1);
  BEGIN PERFORM public.add_planning_block_item(gen_random_uuid(), v_list, 'x', NULL, v_x, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: stranger assignee';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.add_planning_block_item(gen_random_uuid(), v_text, 'x', NULL, NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: item on a text block';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 6 (op_replay): a tick op applies once; replaying the same op
  -- after the partner unticked does NOT re-tick; a new op does.
  v_r := public.set_planning_block_item_checked(v_i1, true, v_op);
  IF v_r ->> 'checked_by' <> v_a::text THEN RAISE EXCEPTION 'EXPLOIT: tick not attributed'; END IF;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_b), true);
  PERFORM public.set_planning_block_item_checked(v_i1, false, gen_random_uuid());
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  v_r := public.set_planning_block_item_checked(v_i1, true, v_op);
  IF v_r ->> 'checked_at' IS NOT NULL THEN RAISE EXCEPTION 'EXPLOIT: replayed op re-applied'; END IF;
  v_r := public.set_planning_block_item_checked(v_i1, true, gen_random_uuid());
  IF v_r ->> 'checked_at' IS NULL THEN RAISE EXCEPTION 'EXPLOIT: fresh op ignored'; END IF;

  -- Contract 7: ticking an already-ticked item keeps the original tick.
  v_hint := v_r ->> 'checked_at';
  v_r := public.set_planning_block_item_checked(v_i1, true, gen_random_uuid());
  IF v_r ->> 'checked_at' <> v_hint THEN RAISE EXCEPTION 'EXPLOIT: re-tick moved timestamp'; END IF;

  -- Contract 8: item update with version; stale rejected.
  v_r := public.update_planning_block_item(v_i2, 1, 'Milk (2L)', 'Dairy', v_a, NULL);
  IF v_r ->> 'text' <> 'Milk (2L)' OR (v_r ->> 'version')::int <> 2 THEN RAISE EXCEPTION 'EXPLOIT: item update wrong'; END IF;
  BEGIN PERFORM public.update_planning_block_item(v_i2, 1, 'Milk', NULL, NULL, NULL); RAISE EXCEPTION 'EXPLOIT: stale item save';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:stale_version' THEN RAISE; END IF; END;

  -- Contract 9: move item to first; move block to first.
  PERFORM public.move_planning_block_item(v_i2, NULL);
  IF (public.get_planning_entry(v_entry) -> 'blocks' -> 1 -> 'items' -> 0 ->> 'id')::uuid <> v_i2 THEN
    RAISE EXCEPTION 'EXPLOIT: item move failed';
  END IF;
  PERFORM public.move_planning_block(v_date, NULL);
  IF (public.get_planning_entry(v_entry) -> 'blocks' -> 0 ->> 'id')::uuid <> v_date THEN
    RAISE EXCEPTION 'EXPLOIT: block move failed';
  END IF;
  BEGIN PERFORM public.move_planning_block(v_date, v_date); RAISE EXCEPTION 'EXPLOIT: moved after itself';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 10 (update_after_delete): partner deletes a block; my save is not_found;
  -- restore brings it back with its items.
  PERFORM public.delete_planning_block(v_list);
  BEGIN PERFORM public.add_planning_block_item(gen_random_uuid(), v_list, 'Eggs', NULL, NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: item added to deleted block';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.update_planning_block(v_list, 1, '{"title":"x"}', NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: deleted block updated';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  v_r := public.restore_planning_block(v_list);
  IF jsonb_array_length(v_r -> 'items') <> 2 THEN RAISE EXCEPTION 'EXPLOIT: restore lost items'; END IF;
  PERFORM public.delete_planning_block_item(v_i1);
  v_r := public.restore_planning_block_item(v_i1);
  IF v_r ->> 'text' <> 'Tomatoes' THEN RAISE EXCEPTION 'EXPLOIT: item restore failed'; END IF;

  -- Contract 11: limits — 200 blocks, 500 items.
  FOR v_i IN 1..197 LOOP
    PERFORM public.add_planning_block(gen_random_uuid(), v_entry, 'checklist', '{}', NULL, NULL, NULL);
  END LOOP;
  BEGIN PERFORM public.add_planning_block(gen_random_uuid(), v_entry, 'checklist', '{}', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: 201st block';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:limit_reached' THEN RAISE; END IF;
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
    IF v_hint::jsonb ->> 'limit' <> 'blocks_per_entry' THEN RAISE EXCEPTION 'EXPLOIT: wrong limit name'; END IF;
  END;
  FOR v_i IN 1..498 LOOP
    PERFORM public.add_planning_block_item(gen_random_uuid(), v_list, 'i' || v_i, NULL, NULL, NULL, NULL);
  END LOOP;
  BEGIN PERFORM public.add_planning_block_item(gen_random_uuid(), v_list, 'one too many', NULL, NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: 501st item';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:limit_reached' THEN RAISE; END IF; END;

  -- Contract 12: 400 inserts always at the top stay ≤ 64 chars (rebalance works).
  DELETE FROM public.planning_block_items WHERE block_id = v_list;
  FOR v_i IN 1..400 LOOP
    PERFORM public.add_planning_block_item(gen_random_uuid(), v_list, 'top ' || v_i, NULL, NULL, NULL, NULL);
  END LOOP;
  SELECT max(char_length(sort_key)) INTO v_n FROM public.planning_block_items WHERE block_id = v_list AND deleted_at IS NULL;
  IF v_n > 33 THEN RAISE EXCEPTION 'EXPLOIT: keys grew to %', v_n; END IF;
  IF (public.get_planning_entry(v_entry) -> 'blocks' -> 2 -> 'items' -> 0 ->> 'text') <> 'top 400' THEN
    RAISE EXCEPTION 'EXPLOIT: top inserts out of order after rebalance';
  END IF;

  -- Contract 13: editing a template block marks the template edited.
  SELECT id INTO v_tpl FROM public.planning_entries WHERE category_id = v_cat AND is_template;
  PERFORM public.add_planning_block(gen_random_uuid(), v_tpl, 'text', '{"delta":[{"insert":"Tip\n"}]}', NULL, NULL, NULL);
  IF (SELECT seed_version FROM public.planning_entries WHERE id = v_tpl) IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: template edit not recorded';
  END IF;

  -- Contract 14: stranger refused with not_found.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_x), true);
  BEGIN PERFORM public.set_planning_block_item_checked(v_i1, true, gen_random_uuid()); RAISE EXCEPTION 'EXPLOIT: stranger ticked';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.add_planning_block(gen_random_uuid(), v_entry, 'text', '{"delta":[{"insert":"\n"}]}', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: stranger added block';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;

  RAISE NOTICE 'planning_v2_block_item_contracts: PASS';
END $$;
ROLLBACK;
