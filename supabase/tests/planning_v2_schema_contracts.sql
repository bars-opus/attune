-- Planning v2 schema contracts (P1 Task 1).
-- Run: psql -q -d attune_test -f supabase/tests/planning_v2_schema_contracts.sql
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel  uuid := '2a000000-0000-0000-0000-000000000001';
  v_rel2 uuid := '2a000000-0000-0000-0000-000000000002';
  v_a uuid := '2a000000-0000-0000-0000-0000000000a1';
  v_b uuid := '2a000000-0000-0000-0000-0000000000b1';
  v_c uuid := '2a000000-0000-0000-0000-0000000000c1';
  v_d uuid := '2a000000-0000-0000-0000-0000000000d1';
  v_cat uuid := '2a000000-0000-0000-0000-00000000ca01';
  v_cat2 uuid := '2a000000-0000-0000-0000-00000000ca02';
  v_ent uuid := '2a000000-0000-0000-0000-00000000e001';
  v_blk uuid := '2a000000-0000-0000-0000-00000000b001';
  v_n int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_a,'v2s_a@t.test'),(v_b,'v2s_b@t.test'),(v_c,'v2s_c@t.test'),(v_d,'v2s_d@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a,'+12000000001','A'),(v_b,'+12000000002','B'),(v_c,'+12000000003','C'),(v_d,'+12000000004','D')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
    (v_rel, v_a, v_b, 'active'), (v_rel2, v_c, v_d, 'active')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.planning_categories (id, relationship_id, seed_key, name, icon, color, sort_key)
  VALUES (v_cat, v_rel, 'goals', 'Goals', 'flag', 'rose', 'V');
  INSERT INTO public.planning_categories (id, relationship_id, name, icon, color, sort_key)
  VALUES (v_cat2, v_rel2, 'Theirs', 'star', 'teal', 'V');

  -- Contract 1: a starter category can never be soft-deleted.
  BEGIN
    UPDATE public.planning_categories SET deleted_at = now() WHERE id = v_cat;
    RAISE EXCEPTION 'EXPLOIT: starter category was soft-deleted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Contract 2: one seed_key per relationship.
  BEGIN
    INSERT INTO public.planning_categories (id, relationship_id, seed_key, name, icon, color, sort_key)
    VALUES (gen_random_uuid(), v_rel, 'goals', 'Goals 2', 'flag', 'rose', 'k');
    RAISE EXCEPTION 'EXPLOIT: duplicate seed_key accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Contract 3: an entry cannot point at another couple's category.
  BEGIN
    INSERT INTO public.planning_entries (id, relationship_id, category_id, title)
    VALUES (gen_random_uuid(), v_rel, v_cat2, 'cross-couple');
    RAISE EXCEPTION 'EXPLOIT: cross-relationship entry accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  -- Contract 4: exactly one live template per category.
  INSERT INTO public.planning_entries (id, relationship_id, category_id, title, is_template)
  VALUES (v_ent, v_rel, v_cat, 'Template', true);
  BEGIN
    INSERT INTO public.planning_entries (id, relationship_id, category_id, title, is_template)
    VALUES (gen_random_uuid(), v_rel, v_cat, 'Template 2', true);
    RAISE EXCEPTION 'EXPLOIT: second live template accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Contract 5: a template can never enable split.
  BEGIN
    UPDATE public.planning_entries SET split_enabled = true WHERE id = v_ent;
    RAISE EXCEPTION 'EXPLOIT: template split enabled';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Contract 6: payload over 16384 bytes is rejected by the table itself.
  BEGIN
    INSERT INTO public.planning_blocks (id, relationship_id, entry_id, block_type, sort_key, payload)
    VALUES (gen_random_uuid(), v_rel, v_ent, 'text', 'V',
            jsonb_build_object('delta', repeat('x', 16400)));
    RAISE EXCEPTION 'EXPLOIT: oversized payload accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Contract 7: unknown block type rejected.
  BEGIN
    INSERT INTO public.planning_blocks (id, relationship_id, entry_id, block_type, sort_key)
    VALUES (gen_random_uuid(), v_rel, v_ent, 'video', 'V');
    RAISE EXCEPTION 'EXPLOIT: unknown block type accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Contract 8: date_end before date_start rejected.
  BEGIN
    INSERT INTO public.planning_blocks (id, relationship_id, entry_id, block_type, sort_key, date_start, date_end)
    VALUES (gen_random_uuid(), v_rel, v_ent, 'date', 'V', '2026-11-10', '2026-11-01');
    RAISE EXCEPTION 'EXPLOIT: inverted date range accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Contract 9: sort keys compare bytewise ('Z' < 'a'), not by locale.
  INSERT INTO public.planning_blocks (id, relationship_id, entry_id, block_type, sort_key)
  VALUES (v_blk, v_rel, v_ent, 'checklist', 'a'),
         (gen_random_uuid(), v_rel, v_ent, 'checklist', 'Z');
  SELECT count(*) INTO v_n FROM (
    SELECT sort_key, row_number() OVER (ORDER BY sort_key) rn
    FROM public.planning_blocks WHERE entry_id = v_ent) s
  WHERE (rn = 1 AND sort_key = 'Z') OR (rn = 2 AND sort_key = 'a');
  IF v_n <> 2 THEN RAISE EXCEPTION 'EXPLOIT: sort_key is not byte-ordered'; END IF;

  -- Contract 10: an item cannot point at another couple's block.
  BEGIN
    INSERT INTO public.planning_block_items (id, relationship_id, block_id, sort_key, text)
    VALUES (gen_random_uuid(), v_rel2, v_blk, 'V', 'cross');
    RAISE EXCEPTION 'EXPLOIT: cross-relationship item accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  -- Contract 11: clients have no table privileges at all.
  SELECT count(*) INTO v_n
  FROM information_schema.role_table_grants
  WHERE grantee IN ('anon','authenticated','PUBLIC')
    AND table_schema = 'public'
    AND table_name IN ('planning_categories','planning_entries','planning_blocks',
                       'planning_block_items','planning_applied_ops','planning_category_seen');
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: v2 table granted to a client role (% grants)', v_n; END IF;

  -- Contract 12: RLS is on for every v2 table.
  SELECT count(*) INTO v_n FROM pg_class
  WHERE relnamespace = 'public'::regnamespace
    AND relname IN ('planning_categories','planning_entries','planning_blocks',
                    'planning_block_items','planning_applied_ops','planning_category_seen')
    AND relrowsecurity;
  IF v_n <> 6 THEN RAISE EXCEPTION 'EXPLOIT: RLS missing on % v2 tables', 6 - v_n; END IF;

  -- Contract 13: updated_at is maintained by trigger.
  UPDATE public.planning_entries SET title = 'Template renamed' WHERE id = v_ent
    RETURNING (updated_at > created_at)::int INTO v_n;
  IF v_n <> 1 THEN RAISE EXCEPTION 'EXPLOIT: updated_at not touched'; END IF;

  -- Contract 14: relationship hard delete cascades all v2 rows.
  DELETE FROM public.relationships WHERE id = v_rel;
  SELECT (SELECT count(*) FROM public.planning_categories WHERE relationship_id = v_rel)
       + (SELECT count(*) FROM public.planning_entries    WHERE relationship_id = v_rel)
       + (SELECT count(*) FROM public.planning_blocks     WHERE relationship_id = v_rel)
    INTO v_n;
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: relationship delete left % v2 rows', v_n; END IF;

  RAISE NOTICE 'planning_v2_schema_contracts: PASS';
END $$;
ROLLBACK;
