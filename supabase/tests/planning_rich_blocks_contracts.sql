-- Planning P3: rich blocks (table, photo, link, place, expenses, budget).
-- Run: psql -q -d attune_planning -f supabase/tests/planning_rich_blocks_contracts.sql
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := '32000000-0000-0000-0000-000000000001';
  v_a uuid := '32000000-0000-0000-0000-0000000000a1';
  v_b uuid := '32000000-0000-0000-0000-0000000000b1';
  v_x uuid := '32000000-0000-0000-0000-0000000000e1';
  v_trips uuid;
  v_entry uuid := '32000000-0000-0000-0000-00000000e001';
  v_table uuid := '32000000-0000-0000-0000-00000000b001';
  v_exp uuid := '32000000-0000-0000-0000-00000000b002';
  v_budget uuid := '32000000-0000-0000-0000-00000000b003';
  v_photo uuid := '32000000-0000-0000-0000-00000000b004';
  v_link uuid := '32000000-0000-0000-0000-00000000b005';
  v_place uuid := '32000000-0000-0000-0000-00000000b006';
  v_line1 uuid := '32000000-0000-0000-0000-0000000001a1';
  v_line2 uuid := '32000000-0000-0000-0000-0000000001a2';
  v_line3 uuid := '32000000-0000-0000-0000-0000000001a3';
  v_row1 uuid := '32000000-0000-0000-0000-0000000002a1';
  v_r jsonb;
  v_d jsonb;
  v_n int;
  v_i int;
  v_path text;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_a,'rb_a@t.test'),(v_b,'rb_b@t.test'),(v_x,'rb_x@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a,'+13200000001','Priya'),(v_b,'+13200000002','Sam'),(v_x,'+13200000003','X') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_a, v_b, 'active') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  PERFORM public.get_planning_home(v_rel);
  SELECT id INTO v_trips FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'trips';
  PERFORM public.create_planning_entry(v_entry, v_trips, 'Bali', false, 'IDR');

  -- Contract 1: a table needs well-formed typed columns.
  PERFORM public.add_planning_block(v_table, v_entry, 'table',
    '{"title":"Itinerary","columns":[{"key":"c1","label":"Day","type":"date"},{"key":"c2","label":"Plan","type":"text"},{"key":"c3","label":"Cost","type":"money"},{"key":"c4","label":"Booked","type":"check"}]}',
    NULL, NULL, NULL);
  BEGIN
    PERFORM public.add_planning_block(gen_random_uuid(), v_entry, 'table',
      '{"columns":[{"key":"c1","label":"A","type":"text"},{"key":"c1","label":"B","type":"text"}]}', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: duplicate column keys accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.add_planning_block(gen_random_uuid(), v_entry, 'table',
      '{"columns":[{"key":"c1","label":"A","type":"emoji"}]}', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: unknown column type accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 2: table rows are typed by their columns.
  v_r := public.save_planning_rich_item(v_row1, v_table, NULL,
    '{"cells":{"c1":"2026-11-28","c2":"Ubud rice terraces","c3":350000,"c4":true}}', NULL);
  IF v_r -> 'cells' ->> 'c2' <> 'Ubud rice terraces' THEN RAISE EXCEPTION 'EXPLOIT: row cells not saved: %', v_r; END IF;
  BEGIN
    PERFORM public.save_planning_rich_item(gen_random_uuid(), v_table, NULL, '{"cells":{"c3":"lots"}}', NULL);
    RAISE EXCEPTION 'EXPLOIT: a text value accepted in a money column';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.save_planning_rich_item(gen_random_uuid(), v_table, NULL, '{"cells":{"c9":"x"}}', NULL);
    RAISE EXCEPTION 'EXPLOIT: a cell for an unknown column accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  -- version check on update
  v_r := public.save_planning_rich_item(v_row1, v_table, 1, '{"cells":{"c2":"Tegallalang"}}', NULL);
  IF (v_r ->> 'version')::int <> 2 THEN RAISE EXCEPTION 'EXPLOIT: row version not bumped'; END IF;
  BEGIN
    PERFORM public.save_planning_rich_item(v_row1, v_table, 1, '{"cells":{"c2":"stale"}}', NULL);
    RAISE EXCEPTION 'EXPLOIT: stale row save accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:stale_version' THEN RAISE; END IF; END;
  FOR v_i IN 1..49 LOOP
    PERFORM public.save_planning_rich_item(gen_random_uuid(), v_table, NULL, '{"cells":{"c2":"r"}}', NULL);
  END LOOP;
  BEGIN
    PERFORM public.save_planning_rich_item(gen_random_uuid(), v_table, NULL, '{"cells":{"c2":"51st"}}', NULL);
    RAISE EXCEPTION 'EXPLOIT: 51st table row accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:limit_reached' THEN RAISE; END IF; END;

  -- Contract 3: expense lines are integer minor units, and every change is audited.
  PERFORM public.add_planning_block(v_exp, v_entry, 'expenses', '{"title":"Costs"}', NULL, NULL, NULL);
  PERFORM public.save_planning_rich_item(v_line1, v_exp, NULL,
    jsonb_build_object('label','Flights','amount_minor',1001,'currency','USD','paid_by',v_a), NULL);
  BEGIN
    PERFORM public.save_planning_rich_item(gen_random_uuid(), v_exp, NULL,
      '{"label":"Taxi","amount_minor":12.5,"currency":"USD"}', NULL);
    RAISE EXCEPTION 'EXPLOIT: a fractional amount accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.save_planning_rich_item(gen_random_uuid(), v_exp, NULL,
      jsonb_build_object('label','Taxi','amount_minor',500,'currency','USD','paid_by',v_x), NULL);
    RAISE EXCEPTION 'EXPLOIT: a stranger as payer accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  PERFORM public.save_planning_rich_item(v_line1, v_exp, 1,
    jsonb_build_object('label','Flights','amount_minor',1001,'currency','USD','paid_by',v_a), NULL);
  PERFORM public.delete_planning_block_item(v_line1);
  PERFORM public.restore_planning_block_item(v_line1);
  SELECT count(*) INTO v_n FROM public.planning_expense_events WHERE item_id = v_line1;
  IF v_n <> 4 THEN RAISE EXCEPTION 'EXPLOIT: expected 4 audit events (create, update, delete, restore), got %', v_n; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.planning_expense_events
                 WHERE item_id = v_line1 AND action = 'update' AND before IS NOT NULL AND after IS NOT NULL
                   AND actor_id = v_a) THEN
    RAISE EXCEPTION 'EXPLOIT: update audit lacks actor/before/after';
  END IF;

  -- Contract 4: the audit cannot be rewritten, even by the table owner.
  BEGIN
    UPDATE public.planning_expense_events SET action = 'create' WHERE item_id = v_line1;
    RAISE EXCEPTION 'EXPLOIT: audit row updated';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF; END;
  BEGIN
    DELETE FROM public.planning_expense_events WHERE item_id = v_line1;
    RAISE EXCEPTION 'EXPLOIT: audit row deleted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF; END;
  IF has_table_privilege('authenticated', 'public.planning_expense_events', 'SELECT')
     OR has_table_privilege('authenticated', 'public.planning_expense_events', 'INSERT') THEN
    RAISE EXCEPTION 'EXPLOIT: clients can touch the audit table';
  END IF;

  -- Contract 5: split. Equal split of an odd amount: the payer keeps the extra unit.
  BEGIN
    PERFORM public.set_planning_entry_split(
      (SELECT id FROM public.planning_entries WHERE category_id = v_trips AND is_template), true);
    RAISE EXCEPTION 'EXPLOIT: a template turned on split';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  v_d := public.set_planning_entry_split(v_entry, true);
  v_d := public.get_planning_entry(v_entry);
  IF v_d -> 'entry' -> 'split' -> 'balances' -> 0 ->> 'minor' <> '500'
     OR (v_d -> 'entry' -> 'split' -> 'balances' -> 0 ->> 'owed_to')::uuid <> v_a
     OR (v_d -> 'entry' -> 'split' -> 'balances' -> 0 ->> 'owed_by')::uuid <> v_b THEN
    RAISE EXCEPTION 'EXPLOIT: equal split of 1001 should leave Sam owing Priya 500: %', v_d -> 'entry' -> 'split';
  END IF;
  -- a custom share and a second currency stay separate
  PERFORM public.save_planning_rich_item(v_line2, v_exp, NULL,
    jsonb_build_object('label','Villa','amount_minor',400,'currency','USD','paid_by',v_b,'split_share_minor',100), NULL);
  PERFORM public.save_planning_rich_item(v_line3, v_exp, NULL,
    jsonb_build_object('label','Dinner','amount_minor',90000,'currency','IDR','paid_by',v_a), NULL);
  v_d := public.get_planning_entry(v_entry);
  SELECT count(*) INTO v_n FROM jsonb_array_elements(v_d -> 'entry' -> 'split' -> 'balances');
  IF v_n <> 2 THEN RAISE EXCEPTION 'EXPLOIT: currencies were mixed in the balance: %', v_d -> 'entry' -> 'split'; END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_d -> 'entry' -> 'split' -> 'balances') b
                 WHERE b ->> 'currency' = 'USD' AND (b ->> 'minor')::int = 400 AND (b ->> 'owed_to')::uuid = v_a) THEN
    RAISE EXCEPTION 'EXPLOIT: USD net should be Sam owes Priya 500 - 100 = 400: %', v_d -> 'entry' -> 'split';
  END IF;
  -- settling clears the balance; later lines count from zero
  PERFORM public.settle_planning_split(v_entry);
  IF jsonb_array_length(public.get_planning_entry(v_entry) -> 'entry' -> 'split' -> 'balances') <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: settle did not clear the balance';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.planning_expense_events WHERE entry_id = v_entry AND action = 'settle')
     OR NOT EXISTS (SELECT 1 FROM public.planning_expense_events WHERE entry_id = v_entry AND action = 'split_on') THEN
    RAISE EXCEPTION 'EXPLOIT: split_on/settle not audited';
  END IF;
  -- money entered after a settle counts, even on an older line (review I5)
  PERFORM public.save_planning_rich_item(v_line3, v_exp, 1,
    jsonb_build_object('label','Dinner','amount_minor',100000,'currency','IDR','paid_by',v_a), NULL);
  v_d := public.get_planning_entry(v_entry);
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_d -> 'entry' -> 'split' -> 'balances') b
                 WHERE b ->> 'currency' = 'IDR' AND (b ->> 'minor')::int = 5000 AND (b ->> 'owed_to')::uuid = v_a)
     OR jsonb_array_length(v_d -> 'entry' -> 'split' -> 'balances') <> 1 THEN
    RAISE EXCEPTION 'EXPLOIT: an edit after settling was not counted: %', v_d -> 'entry' -> 'split';
  END IF;
  -- no partner balance at all without split
  PERFORM public.set_planning_entry_split(v_entry, false);
  IF public.get_planning_entry(v_entry) -> 'entry' -> 'split' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'EXPLOIT: a balance is shown with split off';
  END IF;

  -- Contract 6: budget spent is computed per currency on the server.
  PERFORM public.add_planning_block(v_budget, v_entry, 'budget', '{"title":"Budget"}', NULL, NULL, NULL);
  PERFORM public.update_planning_block_target(v_budget, 1, 5000, 'USD');
  SELECT b INTO v_r FROM jsonb_array_elements(public.get_planning_entry(v_entry) -> 'blocks') b WHERE b ->> 'id' = v_budget::text;
  IF (v_r -> 'computed' ->> 'spent_minor')::int <> 1401
     OR v_r -> 'computed' -> 'other_currencies' -> 0 ->> 'currency' <> 'IDR' THEN
    RAISE EXCEPTION 'EXPLOIT: budget spent wrong: %', v_r -> 'computed';
  END IF;

  -- Contract 7: links accept only http(s), and the server-owned preview survives client edits.
  BEGIN
    PERFORM public.add_planning_block(gen_random_uuid(), v_entry, 'link', '{"url":"javascript:alert(1)"}', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: a javascript: link accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  PERFORM public.add_planning_block(v_link, v_entry, 'link', '{"url":"https://villa.example/ubud"}', NULL, NULL, NULL);
  v_r := public.planning_link_preview_target(v_link);
  IF v_r ->> 'url' <> 'https://villa.example/ubud' THEN RAISE EXCEPTION 'EXPLOIT: preview target wrong'; END IF;
  IF has_function_privilege('authenticated', 'public.set_planning_link_preview(uuid, text, jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: clients can write link previews';
  END IF;
  IF NOT public.set_planning_link_preview(v_link, 'https://villa.example/ubud',
    jsonb_build_object('status','ok','title','Ubud villa','description','Pool','host','villa.example',
                       'image_path', v_rel || '/' || v_entry || '/preview-a.jpg')) THEN
    RAISE EXCEPTION 'EXPLOIT: a current preview reported as not applied';
  END IF;
  -- a refreshed preview replaces the image; the old file is queued for deletion
  PERFORM public.set_planning_link_preview(v_link, 'https://villa.example/ubud',
    jsonb_build_object('status','ok','title','Ubud villa','description','Pool','host','villa.example',
                       'image_path', v_rel || '/' || v_entry || '/preview-b.jpg'));
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = 'planning-media'
                 AND object_name = v_rel || '/' || v_entry || '/preview-a.jpg') THEN
    RAISE EXCEPTION 'EXPLOIT: a replaced preview image was not queued for deletion';
  END IF;
  IF public.set_planning_link_preview(v_link, 'https://other.example/',
    '{"status":"ok","title":"WRONG"}') THEN  -- stale: url no longer matches, ignored
    RAISE EXCEPTION 'EXPLOIT: a stale preview reported as applied';
  END IF;
  PERFORM public.update_planning_block(v_link, 1, '{"url":"https://villa.example/ubud","label":"Our villa"}', NULL, NULL);
  SELECT b INTO v_r FROM jsonb_array_elements(public.get_planning_entry(v_entry) -> 'blocks') b WHERE b ->> 'id' = v_link::text;
  IF v_r -> 'payload' -> 'preview' ->> 'title' <> 'Ubud villa' OR v_r -> 'payload' ->> 'label' <> 'Our villa' THEN
    RAISE EXCEPTION 'EXPLOIT: preview lost or stale write applied: %', v_r -> 'payload';
  END IF;
  -- changing the url drops the old preview
  PERFORM public.update_planning_block(v_link, 2, '{"url":"https://villa.example/canggu"}', NULL, NULL);
  SELECT b INTO v_r FROM jsonb_array_elements(public.get_planning_entry(v_entry) -> 'blocks') b WHERE b ->> 'id' = v_link::text;
  IF v_r -> 'payload' ? 'preview' THEN RAISE EXCEPTION 'EXPLOIT: a preview survived a url change'; END IF;
  -- preview fetches are rate limited per user: 30 a minute (spec §7.1)
  FOR v_i IN 1..29 LOOP PERFORM public.planning_link_preview_target(v_link); END LOOP;  -- 30 with the one above
  BEGIN PERFORM public.planning_link_preview_target(v_link); RAISE EXCEPTION 'EXPLOIT: 31st preview fetch in a minute allowed';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:rate_limited' THEN RAISE; END IF; END;

  -- Contract 8: places validate coordinates.
  PERFORM public.add_planning_block(v_place, v_entry, 'place',
    '{"name":"Ubud","address":"Bali, Indonesia","lat":-8.5069,"lng":115.2625}', NULL, NULL, NULL);
  BEGIN
    PERFORM public.add_planning_block(gen_random_uuid(), v_entry, 'place', '{"name":"Nowhere","lat":95}', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: latitude 95 accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 9: photos. Only a real JPEG under this couple's plan, at most 10, and removal queues the file.
  PERFORM public.add_planning_block(v_photo, v_entry, 'photo', '{"title":"Inspiration"}', NULL, NULL, NULL);
  IF NOT public.planning_storage_can_write(v_rel::text || '/' || v_entry::text || '/' || gen_random_uuid() || '.jpg') THEN
    RAISE EXCEPTION 'EXPLOIT: a member cannot upload under their own plan';
  END IF;
  INSERT INTO storage.buckets (id, name, public) VALUES ('planning-media', 'planning-media', false) ON CONFLICT DO NOTHING;
  FOR v_i IN 1..11 LOOP
    v_path := v_rel::text || '/' || v_entry::text || '/' || gen_random_uuid() || '.jpg';
    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES ('planning-media', v_path, '{"size": 200000, "mimetype": "image/jpeg"}');
    IF v_i <= 10 THEN
      PERFORM public.add_planning_photo(v_photo, v_path);
    ELSE
      BEGIN
        PERFORM public.add_planning_photo(v_photo, v_path);
        RAISE EXCEPTION 'EXPLOIT: an 11th photo accepted';
      EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:limit_reached' THEN RAISE; END IF; END;
    END IF;
  END LOOP;
  BEGIN
    PERFORM public.add_planning_photo(v_photo, v_rel::text || '/' || v_entry::text || '/missing.jpg');
    RAISE EXCEPTION 'EXPLOIT: a photo that was never uploaded accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  v_path := (SELECT b -> 'payload' -> 'paths' ->> 0 FROM jsonb_array_elements(public.get_planning_entry(v_entry) -> 'blocks') b
             WHERE b ->> 'id' = v_photo::text);
  PERFORM public.update_planning_block(v_photo, (SELECT version FROM public.planning_blocks WHERE id = v_photo),
    '{"title":"Renamed"}', NULL, NULL);
  IF jsonb_array_length((SELECT payload -> 'paths' FROM public.planning_blocks WHERE id = v_photo)) <> 10 THEN
    RAISE EXCEPTION 'EXPLOIT: editing the title dropped the photos';
  END IF;
  PERFORM public.remove_planning_photo(v_photo, v_path);
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = 'planning-media' AND object_name = v_path) THEN
    RAISE EXCEPTION 'EXPLOIT: a removed photo was not queued for deletion';
  END IF;

  -- Contract 10: strangers can do none of it.
  -- deleting and restoring a whole plan records each expense line (review I7)
  SELECT count(*) INTO v_n FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
  WHERE b.entry_id = v_entry AND b.block_type = 'expenses' AND b.deleted_at IS NULL AND i.deleted_at IS NULL;
  SELECT count(*) INTO v_i FROM public.planning_expense_events WHERE entry_id = v_entry AND action = 'delete';
  PERFORM public.delete_planning_entry(v_entry);
  IF v_n = 0 OR (SELECT count(*) FROM public.planning_expense_events WHERE entry_id = v_entry AND action = 'delete') - v_i <> v_n THEN
    RAISE EXCEPTION 'EXPLOIT: plan delete left % expense lines unaudited', v_n;
  END IF;
  SELECT count(*) INTO v_i FROM public.planning_expense_events WHERE entry_id = v_entry AND action = 'restore';
  PERFORM public.restore_planning_entry(v_entry);
  IF (SELECT count(*) FROM public.planning_expense_events WHERE entry_id = v_entry AND action = 'restore') - v_i <> v_n THEN
    RAISE EXCEPTION 'EXPLOIT: plan restore left expense lines unaudited';
  END IF;

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_x), true);
  IF public.planning_storage_can_write(v_rel::text || '/' || v_entry::text || '/x.jpg')
     OR public.planning_storage_can_read(v_path) THEN
    RAISE EXCEPTION 'EXPLOIT: a stranger can reach the couple''s photos';
  END IF;
  BEGIN PERFORM public.planning_link_preview_target(v_link); RAISE EXCEPTION 'EXPLOIT: stranger read a link';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.settle_planning_split(v_entry); RAISE EXCEPTION 'EXPLOIT: stranger settled';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.save_planning_rich_item(gen_random_uuid(), v_exp, NULL, '{"label":"x","amount_minor":1,"currency":"USD"}', NULL);
    RAISE EXCEPTION 'EXPLOIT: stranger added an expense';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;

  RAISE NOTICE 'planning_rich_blocks_contracts: PASS';
END $$;
ROLLBACK;
