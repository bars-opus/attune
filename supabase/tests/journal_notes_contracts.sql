-- Journal as notes contracts (spec 2026-10-14-journal-notes-design.md). Every check RAISEs on violation.
BEGIN;
INSERT INTO auth.users (id) VALUES ('8a100000-0000-0000-0000-0000000000a1'), ('8a100000-0000-0000-0000-0000000000b2') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('8a100000-0000-0000-0000-0000000000a1', '+233350000001', 'Ama'),
  ('8a100000-0000-0000-0000-0000000000b2', '+233350000002', 'Kofi') ON CONFLICT (id) DO NOTHING;
-- They are a couple: the partner must still see nothing.
INSERT INTO public.relationships (id, user_a, user_b, status, started_at) VALUES
  ('8a200000-0000-0000-0000-000000000001', '8a100000-0000-0000-0000-0000000000a1', '8a100000-0000-0000-0000-0000000000b2', 'active', now())
  ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.expect_fail(p_sql text, p_code text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_ok boolean := false;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%' || p_code || '%' THEN v_ok := true;
    ELSE RAISE EXCEPTION 'CONTRACT VIOLATED: % raised "%" (wanted %)', p_sql, SQLERRM, p_code; END IF;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % did not fail with %', p_sql, p_code; END IF;
END $$;

-- The whole flow, as Ama, inside one DO so values carry over.
DO $$
DECLARE
  a uuid := '8a100000-0000-0000-0000-0000000000a1';
  k uuid := '8a100000-0000-0000-0000-0000000000b2';
  d jsonb; r jsonb; e uuid; e2 uuid; e3 uuid; b1 uuid; b2 uuid; ph uuid; n int; i int; v_content text;
BEGIN
  PERFORM pg_temp.as_user(a);

  -- A new entry: one empty text block, empty content, the prompt kept.
  d := public.create_journal_entry_v2('What surprised you today?');
  e := (d->'entry'->>'id')::uuid;
  b1 := (d->'blocks'->0->>'id')::uuid;
  IF jsonb_array_length(d->'blocks') <> 1 OR d->'blocks'->0->>'kind' <> 'text' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new entry is one text block, got %', d->'blocks'; END IF;
  IF d->'entry'->>'content' <> '' OR d->'entry'->>'prompt_used' <> 'What surprised you today?' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: new entry content/prompt %', d->'entry'; END IF;

  -- Saving text recomputes content and bumps the version; a stale version is a conflict.
  UPDATE public.reflection_journal_entries SET tone = 'settled' WHERE id = e;
  r := public.save_journal_text(b1, 1, '[{"insert":"Morning walk\n"}]'::jsonb);
  IF r->>'status' <> 'saved' OR (r->'block'->>'version')::int <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: save %', r; END IF;
  IF (SELECT tone FROM public.reflection_journal_entries WHERE id = e) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: changed text keeps a stale tone'; END IF;
  r := public.save_journal_text(b1, 1, '[{"insert":"Stale\n"}]'::jsonb);
  IF r->>'status' <> 'conflict' OR r->'block'->>'plain_text' NOT LIKE 'Morning walk%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: stale save was not a conflict: %', r; END IF;

  -- A second text block: content is the text blocks in order, blank-line joined.
  b2 := (public.insert_journal_block(e, b1, 'text', '{"delta":[{"insert":"Felt calm\n"}]}'::jsonb)->>'id')::uuid;
  SELECT content INTO v_content FROM public.reflection_journal_entries WHERE id = e;
  IF v_content <> E'Morning walk\n\nFelt calm' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: content %', v_content; END IF;
  PERFORM public.move_journal_block(b2, 0);
  SELECT content INTO v_content FROM public.reflection_journal_entries WHERE id = e;
  IF v_content <> E'Felt calm\n\nMorning walk' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: content after move %', v_content; END IF;

  -- Photos: only inside the owner's own entry folder; at most 10.
  PERFORM pg_temp.expect_fail(format(
    $q$SELECT public.insert_journal_block(%L, NULL, 'photo', %L::jsonb)$q$,
    e, jsonb_build_object('path', k || '/' || e || '/x.jpg')), 'journal:invalid_input');
  ph := (public.insert_journal_block(e, NULL, 'photo', jsonb_build_object('path', a || '/' || e || '/p0.jpg'))->>'id')::uuid;
  FOR i IN 1..9 LOOP
    PERFORM public.insert_journal_block(e, NULL, 'photo', jsonb_build_object('path', a || '/' || e || '/p' || i || '.jpg'));
  END LOOP;
  PERFORM pg_temp.expect_fail(format(
    $q$SELECT public.insert_journal_block(%L, NULL, 'photo', %L::jsonb)$q$,
    e, jsonb_build_object('path', a || '/' || e || '/p10.jpg')), 'journal:limit');
  SELECT content INTO v_content FROM public.reflection_journal_entries WHERE id = e;
  IF v_content <> E'Felt calm\n\nMorning walk' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photos changed content %', v_content; END IF;

  -- Removing a photo queues its file for deletion.
  PERFORM public.delete_journal_block(ph);
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = 'journal-media' AND object_name = a || '/' || e || '/p0.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a removed photo is not queued for deletion'; END IF;

  -- The only block can't be deleted.
  d := public.create_journal_entry_v2(NULL);
  e2 := (d->'entry'->>'id')::uuid;
  PERFORM pg_temp.expect_fail(format('SELECT public.delete_journal_block(%L)', d->'blocks'->0->>'id'), 'journal:last_block');

  -- Titles: blank clears, too long fails.
  r := public.rename_journal_entry(e, '  Tuesday  ');
  IF r->>'title' <> 'Tuesday' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: rename %', r; END IF;
  r := public.rename_journal_entry(e2, '   ');
  IF r->>'title' IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: blank title kept %', r; END IF;
  PERFORM pg_temp.expect_fail(format('SELECT public.rename_journal_entry(%L, %L)', e, repeat('x', 121)), 'journal:too_long');

  -- The list: pinned apart; snippets short; photos flagged.
  PERFORM public.set_journal_pin(e, true);
  r := public.list_journal_entries(NULL, 30);
  IF jsonb_array_length(r->'pinned') <> 1 OR r->'pinned'->0->>'id' <> e::text OR NOT (r->'pinned'->0->>'has_photo')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pinned %', r->'pinned'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(r->'entries') x WHERE x->>'id' = e::text) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pinned entry also listed by date'; END IF;
  PERFORM public.save_journal_text(b2, 1, jsonb_build_array(jsonb_build_object('insert', repeat('word ', 60) || E'\n')));
  r := public.list_journal_entries(NULL, 30);
  IF char_length(r->'pinned'->0->>'snippet') > 80 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: snippet longer than 80'; END IF;

  -- Soft delete hides; restore brings back; the sweep purges only old deletions.
  PERFORM public.delete_journal_entry(e2);
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(public.list_journal_entries(NULL, 30)->'entries') x WHERE x->>'id' = e2::text) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted entry is listed'; END IF;
  PERFORM public.restore_journal_entry(e2);
  d := public.create_journal_entry_v2(NULL);
  e3 := (d->'entry'->>'id')::uuid;
  PERFORM public.delete_journal_entry(e2);
  PERFORM public.delete_journal_entry(e3);
  UPDATE public.reflection_journal_entries SET deleted_at = now() - interval '11 minutes' WHERE id = e2;
  n := public.purge_my_deleted_journal_entries();
  IF n <> 1 OR EXISTS (SELECT 1 FROM public.reflection_journal_entries WHERE id = e2)
     OR NOT EXISTS (SELECT 1 FROM public.reflection_journal_entries WHERE id = e3) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: sweep purged % (wanted only the old one)', n; END IF;

  -- Legacy RPCs (older app builds) still work and keep blocks in step.
  e2 := public.create_journal_entry('Legacy words here');
  IF (SELECT plain_text FROM public.reflection_journal_blocks WHERE entry_id = e2) <> 'Legacy words here' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: legacy create made no text block'; END IF;
  PERFORM public.insert_journal_block(e2, NULL, 'photo', jsonb_build_object('path', a || '/' || e2 || '/old.jpg'));
  PERFORM public.update_journal_entry(e2, 'Rewritten');
  IF (SELECT count(*) FROM public.reflection_journal_blocks WHERE entry_id = e2 AND kind = 'photo') <> 1
     OR (SELECT plain_text FROM public.reflection_journal_blocks WHERE entry_id = e2 AND kind = 'text') <> 'Rewritten'
     OR (SELECT position FROM public.reflection_journal_blocks WHERE entry_id = e2 AND kind = 'text') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: legacy update lost the photo or the text order'; END IF;

  -- The partner (Kofi) can do nothing to Ama's journal.
  PERFORM pg_temp.as_user(k);
  PERFORM pg_temp.expect_fail(format('SELECT public.get_journal_entry(%L)', e), 'journal:not_found');
  PERFORM pg_temp.expect_fail(format($q$SELECT public.save_journal_text(%L, 2, '[{"insert":"x\n"}]'::jsonb)$q$, b1), 'journal:not_found');
  PERFORM pg_temp.expect_fail(format($q$SELECT public.insert_journal_block(%L, NULL, 'text', '{"delta":[{"insert":"x\n"}]}'::jsonb)$q$, e), 'journal:not_found');
  PERFORM pg_temp.expect_fail(format('SELECT public.rename_journal_entry(%L, %L)', e, 'mine'), 'journal:not_found');
  PERFORM pg_temp.expect_fail(format('SELECT public.set_journal_pin(%L, false)', e), 'journal:not_found');
  PERFORM pg_temp.expect_fail(format('SELECT public.delete_journal_block(%L)', b1), 'journal:not_found');
  PERFORM pg_temp.expect_fail(format('SELECT public.move_journal_block(%L, 0)', b1), 'journal:not_found');
  PERFORM pg_temp.expect_fail(format('SELECT public.purge_journal_entry(%L)', e), 'journal:not_found');
  IF jsonb_array_length(public.list_journal_entries(NULL, 30)->'entries') <> 0
     OR jsonb_array_length(public.list_journal_entries(NULL, 30)->'pinned') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the partner lists Ama''s entries'; END IF;

  -- Backfill: an entry written before blocks gets them, its content untouched.
  INSERT INTO public.reflection_journal_entries (id, user_id, content)
  VALUES ('8a300000-0000-0000-0000-000000000001', k, repeat('a', 7000));
  PERFORM public.journal_backfill_blocks();
  IF (SELECT count(*) FROM public.reflection_journal_blocks WHERE entry_id = '8a300000-0000-0000-0000-000000000001') <> 3
     OR (SELECT string_agg(plain_text, '' ORDER BY position) FROM public.reflection_journal_blocks WHERE entry_id = '8a300000-0000-0000-0000-000000000001') <> repeat('a', 7000)
     OR (SELECT content FROM public.reflection_journal_entries WHERE id = '8a300000-0000-0000-0000-000000000001') <> repeat('a', 7000) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: backfill'; END IF;

  -- Long entries split between paragraphs (never mid-word), so a later save
  -- rebuilds exactly the same text.
  INSERT INTO public.reflection_journal_entries (id, user_id, content)
  VALUES ('8a300000-0000-0000-0000-000000000002', k,
          rtrim(repeat('word ', 400)) || E'\n\n' || rtrim(repeat('more ', 400)) || E'\n\n' || rtrim(repeat('last ', 400)));
  PERFORM public.journal_backfill_blocks();
  IF (SELECT count(*) FROM public.reflection_journal_blocks WHERE entry_id = '8a300000-0000-0000-0000-000000000002') <> 3
     OR EXISTS (SELECT 1 FROM public.reflection_journal_blocks
                 WHERE entry_id = '8a300000-0000-0000-0000-000000000002'
                   AND (plain_text ~ '^\s' OR plain_text ~ '\s$' OR plain_text !~ '^(word|more|last)')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a long entry was split mid-word or mid-paragraph'; END IF;
  SELECT content INTO v_content FROM public.reflection_journal_entries WHERE id = '8a300000-0000-0000-0000-000000000002';
  PERFORM public.journal_refresh_content('8a300000-0000-0000-0000-000000000002');
  IF (SELECT content FROM public.reflection_journal_entries WHERE id = '8a300000-0000-0000-0000-000000000002') <> v_content THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-saving a backfilled entry changed its text'; END IF;

  -- Deleting the account queues every remaining photo.
  DELETE FROM public.media_deletion_queue;
  DELETE FROM auth.users WHERE id = a;
  SELECT count(*) INTO n FROM public.media_deletion_queue WHERE bucket_id = 'journal-media';
  IF n <> 10 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: account deletion queued % photos (wanted 10)', n; END IF;

  -- No relationship link exists anywhere in the journal.
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND column_name = 'relationship_id'
               AND table_name IN ('reflection_journal_entries', 'reflection_journal_blocks', 'reflection_journal_analysis')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a journal table has relationship_id'; END IF;
END $$;

-- Row-level security: as the partner, through the API role, nothing is readable or writable.
SELECT pg_temp.as_user('8a100000-0000-0000-0000-0000000000b2');
INSERT INTO auth.users (id) VALUES ('8a100000-0000-0000-0000-0000000000c3') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES ('8a100000-0000-0000-0000-0000000000c3', '+233350000003', 'Esi') ON CONFLICT DO NOTHING;
SELECT pg_temp.as_user('8a100000-0000-0000-0000-0000000000c3');
SELECT public.create_journal_entry_v2(NULL);
SELECT pg_temp.as_user('8a100000-0000-0000-0000-0000000000b2');
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.reflection_journal_blocks WHERE user_id = '8a100000-0000-0000-0000-0000000000c3')
     OR EXISTS (SELECT 1 FROM public.reflection_journal_entries WHERE user_id = '8a100000-0000-0000-0000-0000000000c3') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another user''s journal is readable'; END IF;
  BEGIN
    INSERT INTO public.reflection_journal_blocks (entry_id, user_id, position, kind, payload)
    SELECT id, user_id, 9, 'text', '{"delta":[]}' FROM public.reflection_journal_entries LIMIT 1;
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated can insert blocks directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
ROLLBACK;
