-- Planning v2 category contracts (P1 Task 3).
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := '2c000000-0000-0000-0000-000000000001';
  v_a uuid := '2c000000-0000-0000-0000-0000000000a1';
  v_b uuid := '2c000000-0000-0000-0000-0000000000b1';
  v_x uuid := '2c000000-0000-0000-0000-0000000000e1';
  v_custom uuid := '2c000000-0000-0000-0000-00000000c001';
  v_home jsonb;
  v_cat jsonb;
  v_goals uuid;
  v_tpl uuid;
  v_n int;
  v_i int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_a,'v2c_a@t.test'),(v_b,'v2c_b@t.test'),(v_x,'v2c_x@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a,'+12200000001','Ama'),(v_b,'+12200000002','Kofi'),(v_x,'+12200000003','X')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_a, v_b, 'active')
  ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);

  -- Contract 1: first home read seeds six visible starters in order, Notes
  -- first; Everyday exists but is hidden while empty.
  v_home := public.get_planning_home(v_rel);
  IF (SELECT array_agg(c ->> 'seed_key' ORDER BY ord)
        FROM jsonb_array_elements(v_home -> 'categories') WITH ORDINALITY t(c, ord))
     IS DISTINCT FROM ARRAY['notes','goals','trips','date_nights','home_bills','groceries','wishlist','diet'] THEN
    RAISE EXCEPTION 'EXPLOIT: starters wrong: %', v_home;
  END IF;
  SELECT count(*) INTO v_n FROM public.planning_categories WHERE relationship_id = v_rel;
  IF v_n <> 9 THEN RAISE EXCEPTION 'EXPLOIT: expected 9 seeded categories, got %', v_n; END IF;

  -- Contract 2: every starter has exactly one template with blocks.
  SELECT count(*) INTO v_n FROM public.planning_categories c
  WHERE c.relationship_id = v_rel AND (
    SELECT count(*) FROM public.planning_entries e
    WHERE e.category_id = c.id AND e.is_template AND e.deleted_at IS NULL) <> 1;
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: % starters without exactly one template', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.planning_block_items i
  JOIN public.planning_blocks b ON b.id = i.block_id
  JOIN public.planning_entries e ON e.id = b.entry_id
  JOIN public.planning_categories c ON c.id = e.category_id
  WHERE c.relationship_id = v_rel AND c.seed_key = 'home_bills';
  IF v_n <> 5 THEN RAISE EXCEPTION 'EXPLOIT: Home & bills template should have 5 bill items, got %', v_n; END IF;

  -- Contract 3: re-reading home never re-seeds.
  PERFORM public.get_planning_home(v_rel);
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_b), true);
  PERFORM public.get_planning_home(v_rel);
  SELECT count(*) INTO v_n FROM public.planning_categories WHERE relationship_id = v_rel;
  IF v_n <> 9 THEN RAISE EXCEPTION 'EXPLOIT: re-read reseeded (% categories)', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.planning_entries WHERE relationship_id = v_rel AND is_template;
  IF v_n <> 9 THEN RAISE EXCEPTION 'EXPLOIT: re-read duplicated templates (%)', v_n; END IF;

  -- Contract 4: a stranger gets not_found, never a seed.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_x), true);
  BEGIN PERFORM public.get_planning_home(v_rel); RAISE EXCEPTION 'EXPLOIT: stranger read home';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  BEGIN PERFORM public.create_planning_category(gen_random_uuid(), v_rel, 'Sneak', 'star', 'teal');
    RAISE EXCEPTION 'EXPLOIT: stranger created category';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);

  -- Contract 5: create a custom category; it appends last, gets a blank template.
  v_cat := public.create_planning_category(v_custom, v_rel, '  Wedding  ', 'ring', 'violet');
  IF v_cat ->> 'name' <> 'Wedding' THEN RAISE EXCEPTION 'EXPLOIT: name not trimmed'; END IF;
  v_home := public.get_planning_home(v_rel);
  IF (v_home -> 'categories' -> -1 ->> 'id')::uuid <> v_custom THEN
    RAISE EXCEPTION 'EXPLOIT: custom category not last';
  END IF;
  SELECT count(*) INTO v_n FROM public.planning_blocks b
  JOIN public.planning_entries e ON e.id = b.entry_id WHERE e.category_id = v_custom;
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: custom template not blank'; END IF;

  -- Contract 6: idempotent create; conflicting reuse rejected.
  v_cat := public.create_planning_category(v_custom, v_rel, 'Wedding', 'ring', 'violet');
  BEGIN PERFORM public.create_planning_category(v_custom, v_rel, 'Baby', 'baby', 'rose');
    RAISE EXCEPTION 'EXPLOIT: id reuse with different payload accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 7: icon and colour must be from the allow-lists.
  BEGIN PERFORM public.create_planning_category(gen_random_uuid(), v_rel, 'X', 'skull', 'teal');
    RAISE EXCEPTION 'EXPLOIT: unknown icon accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.create_planning_category(gen_random_uuid(), v_rel, 'X', 'star', '#ff0000');
    RAISE EXCEPTION 'EXPLOIT: hex colour accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 8: move to first; hide; rename.
  v_cat := public.move_planning_category(v_custom, NULL);
  v_home := public.get_planning_home(v_rel);
  IF (v_home -> 'categories' -> 0 ->> 'id')::uuid <> v_custom THEN RAISE EXCEPTION 'EXPLOIT: move to first failed'; END IF;
  v_cat := public.set_planning_category_hidden(v_custom, true);
  v_home := public.get_planning_home(v_rel);
  IF NOT (v_home -> 'categories' -> 0 ->> 'hidden')::boolean THEN RAISE EXCEPTION 'EXPLOIT: hidden flag not reported'; END IF;
  v_cat := public.update_planning_category(v_custom, 'Our wedding', 'ring', 'rose');
  IF v_cat ->> 'name' <> 'Our wedding' OR v_cat ->> 'color' <> 'rose' THEN RAISE EXCEPTION 'EXPLOIT: rename failed'; END IF;

  -- Contract 9: starters cannot be deleted; custom can, taking entries with it.
  SELECT id INTO v_goals FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'goals';
  BEGIN PERFORM public.delete_planning_category(v_goals);
    RAISE EXCEPTION 'EXPLOIT: starter deleted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  INSERT INTO public.planning_entries (id, relationship_id, category_id, title, created_by)
  VALUES (gen_random_uuid(), v_rel, v_custom, 'Venue', v_a);
  v_cat := public.delete_planning_category(v_custom);
  IF (v_cat ->> 'deleted_entries')::int <> 1 THEN RAISE EXCEPTION 'EXPLOIT: delete count wrong: %', v_cat; END IF;
  SELECT count(*) INTO v_n FROM public.planning_entries WHERE category_id = v_custom AND deleted_at IS NULL;
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: entries survived category delete'; END IF;
  BEGIN PERFORM public.update_planning_category(v_custom, 'Back', 'ring', 'rose');
    RAISE EXCEPTION 'EXPLOIT: deleted category updated';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:not_found' THEN RAISE; END IF; END;

  -- Contract 10: limit of 50 live categories.
  FOR v_i IN 1..41 LOOP  -- 9 starters + 41 = the 50-category limit
    PERFORM public.create_planning_category(gen_random_uuid(), v_rel, 'C' || v_i, 'star', 'teal');
  END LOOP;
  BEGIN PERFORM public.create_planning_category(gen_random_uuid(), v_rel, 'C51', 'star', 'teal');
    RAISE EXCEPTION 'EXPLOIT: 51st category accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:limit_reached' THEN RAISE; END IF; END;

  -- Contract 11: "new" dot = partner activity on a plan after I last opened
  -- that plan; never my own. Since 2026-10-18 (planning_entry_seen) opening
  -- the category alone no longer clears it — opening the plan does.
  UPDATE public.planning_entries SET last_activity_at = clock_timestamp(), last_activity_by = v_a
  WHERE category_id = v_goals AND is_template;  -- templates never count
  INSERT INTO public.planning_entries (id, relationship_id, category_id, title, created_by, last_activity_by)
  VALUES (gen_random_uuid(), v_rel, v_goals, 'Save for a car', v_b, v_b);
  v_home := public.get_planning_home(v_rel);
  IF NOT (SELECT (c ->> 'has_new')::boolean FROM jsonb_array_elements(v_home -> 'categories') c
          WHERE c ->> 'seed_key' = 'goals') THEN
    RAISE EXCEPTION 'EXPLOIT: partner activity not flagged new';
  END IF;
  PERFORM public.mark_planning_category_seen(v_goals);
  v_home := public.get_planning_home(v_rel);
  IF NOT (SELECT (c ->> 'has_new')::boolean FROM jsonb_array_elements(v_home -> 'categories') c
          WHERE c ->> 'seed_key' = 'goals') THEN
    RAISE EXCEPTION 'EXPLOIT: opening the category hid an unopened plan';
  END IF;
  PERFORM public.get_planning_entry(e.id) FROM public.planning_entries e
  WHERE e.category_id = v_goals AND e.title = 'Save for a car';
  v_home := public.get_planning_home(v_rel);
  IF (SELECT (c ->> 'has_new')::boolean FROM jsonb_array_elements(v_home -> 'categories') c
      WHERE c ->> 'seed_key' = 'goals') THEN
    RAISE EXCEPTION 'EXPLOIT: seen category still new';
  END IF;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_b), true);
  v_home := public.get_planning_home(v_rel);
  IF (SELECT (c ->> 'has_new')::boolean FROM jsonb_array_elements(v_home -> 'categories') c
      WHERE c ->> 'seed_key' = 'goals') THEN
    RAISE EXCEPTION 'EXPLOIT: own activity flagged new';
  END IF;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);

  -- Contract 12: Everyday appears once it has an entry.
  INSERT INTO public.planning_entries (id, relationship_id, category_id, title)
  SELECT gen_random_uuid(), v_rel, id, 'Note' FROM public.planning_categories
  WHERE relationship_id = v_rel AND seed_key = 'everyday';
  v_home := public.get_planning_home(v_rel);
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_home -> 'categories') c WHERE c ->> 'seed_key' = 'everyday') THEN
    RAISE EXCEPTION 'EXPLOIT: non-empty Everyday hidden';
  END IF;

  -- Contract 13: an unedited template auto-upgrades; an edited one does not.
  SELECT e.id INTO v_tpl FROM public.planning_entries e
  JOIN public.planning_categories c ON c.id = e.category_id
  WHERE c.relationship_id = v_rel AND c.seed_key = 'trips' AND e.is_template;
  UPDATE public.planning_entries SET seed_version = NULL
  FROM public.planning_categories c
  WHERE planning_entries.category_id = c.id AND c.relationship_id = v_rel AND c.seed_key = 'groceries'
    AND planning_entries.is_template;                                  -- groceries "edited"
  UPDATE public.planning_starter_templates
     SET version = version + 1,
         blocks = '[{"type":"text","payload":{"delta":[{"insert":"Upgraded\n"}]}}]'
   WHERE seed_key IN ('trips','groceries');
  PERFORM public.get_planning_home(v_rel);
  SELECT count(*) INTO v_n FROM public.planning_blocks WHERE entry_id = v_tpl AND deleted_at IS NULL;
  IF v_n <> 1 THEN RAISE EXCEPTION 'EXPLOIT: unedited template not upgraded (% blocks)', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.planning_blocks b
  JOIN public.planning_entries e ON e.id = b.entry_id
  JOIN public.planning_categories c ON c.id = e.category_id
  WHERE c.relationship_id = v_rel AND c.seed_key = 'groceries' AND e.is_template
    AND b.deleted_at IS NULL AND b.plain_text = 'Upgraded';
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: edited template was overwritten'; END IF;

  -- Contract 14: inactive relationship fails closed with inactive.
  UPDATE public.relationships SET status = 'ended' WHERE id = v_rel;
  BEGIN PERFORM public.get_planning_home(v_rel); RAISE EXCEPTION 'EXPLOIT: ended couple read home';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:inactive' THEN RAISE; END IF; END;

  -- Contract 15: grants (functions, and the starter-definitions table).
  IF EXISTS (SELECT 1 FROM information_schema.role_table_grants
             WHERE grantee IN ('anon','authenticated','PUBLIC') AND table_schema = 'public'
               AND table_name = 'planning_starter_templates') THEN
    RAISE EXCEPTION 'EXPLOIT: starter templates table granted to a client';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.get_planning_home(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_planning_home(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.planning_v2_ensure_starters(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: category RPC grants wrong';
  END IF;

  -- Contract 16 (Review Focus 5, final review I3): names are limited in CODE
  -- POINTS — the unit the Flutter client now counts — using a REAL combining
  -- mark (e + U+0301) and multi-code-point flags, not precomposed letters.
  UPDATE public.relationships SET status = 'active' WHERE id = v_rel;
  DELETE FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key IS NULL;
  v_cat := public.create_planning_category(gen_random_uuid(), v_rel,
             repeat('e' || chr(769), 20), 'star', 'teal');               -- 40 code points
  IF char_length(v_cat ->> 'name') <> 40 THEN RAISE EXCEPTION 'EXPLOIT: combining marks mangled'; END IF;
  v_cat := public.create_planning_category(gen_random_uuid(), v_rel,
             repeat(chr(127468) || chr(127469), 20), 'star', 'teal');    -- 20 flags = 40 code points
  BEGIN
    PERFORM public.create_planning_category(gen_random_uuid(), v_rel,
              repeat(chr(127468) || chr(127469), 21), 'star', 'teal');   -- 21 flags = 42 code points
    RAISE EXCEPTION 'EXPLOIT: 42 code points accepted as a 40-character name';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  RAISE NOTICE 'planning_v2_category_contracts: PASS';
END $$;
ROLLBACK;
