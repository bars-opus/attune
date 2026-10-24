-- supabase/tests/story_day_reads_contracts.sql
--
-- Stories Wave 5, Task 7 (review 04 #4): one author's stories on a day are
-- read by the server, paged by keyset; the month counts carry each author's
-- unviewed count, so a day ring is right beyond the first page.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000938a1'), ('00000000-0000-0000-0000-0000000938b2'),
  ('00000000-0000-0000-0000-0000000938c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000938a1', '+15550938001', 'DA'),
  ('00000000-0000-0000-0000-0000000938b2', '+15550938002', 'DB'),
  ('00000000-0000-0000-0000-0000000938c3', '+15550938003', 'DC')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
  ('00000000-0000-0000-0000-0000000938e1', '00000000-0000-0000-0000-0000000938a1', '00000000-0000-0000-0000-0000000938b2', 'active');

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- A day three days ago: A posted a1..a3, B posted b1..b3 (b1 seen by A), plus a deleted b4.
SET LOCAL session_replication_role = replica;
INSERT INTO public.story_items (id, client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at, has_been_viewed, deleted_at)
SELECT ('00000000-0000-0000-0000-00000093800' || n)::uuid, gen_random_uuid(), '00000000-0000-0000-0000-0000000938e1',
       CASE WHEN n <= 3 THEN '00000000-0000-0000-0000-0000000938a1'::uuid ELSE '00000000-0000-0000-0000-0000000938b2'::uuid END,
       'image', 'story-media/d938/' || n || '-media', 'story-media/d938/' || n || '-thumbnail', 100, 100,
       CURRENT_DATE - 3, now() - interval '3 days' + make_interval(mins => n),
       now() - interval '3 days' + make_interval(mins => n) + interval '24 hours',
       n = 4, CASE WHEN n = 7 THEN now() END
FROM generate_series(1, 7) n;
SET LOCAL session_replication_role = origin;
-- ids: 1..3 = A's, 4..6 = B's (4 seen), 7 = B's deleted.

-- D1. Only B's, paged.
DO $$
DECLARE v_ids uuid[]; v_last public.story_items;
BEGIN
  SELECT * INTO v_last FROM public.story_items WHERE id = '00000000-0000-0000-0000-000000938005';
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938a1');
  SELECT array_agg(i.id ORDER BY i.created_at) INTO v_ids
    FROM public.list_story_day_items('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 3,
           p_limit => 2, p_author_id => '00000000-0000-0000-0000-0000000938b2') i;
  IF v_ids IS DISTINCT FROM ARRAY['00000000-0000-0000-0000-000000938004', '00000000-0000-0000-0000-000000938005']::uuid[] THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: page 1 of B''s day is %', v_ids;
  END IF;
  SELECT array_agg(i.id) INTO v_ids
    FROM public.list_story_day_items('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 3,
           v_last.created_at, v_last.id, 2, '00000000-0000-0000-0000-0000000938b2') i;
  IF v_ids IS DISTINCT FROM ARRAY['00000000-0000-0000-0000-000000938006']::uuid[] THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: page 2 of B''s day is %', v_ids;
  END IF;
  RESET ROLE;
END $$;

-- D2. The old call shape (no p_author_id) still reads the whole day; one function only.
DO $$
DECLARE v_n int;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938a1');
  SELECT count(*) INTO v_n FROM public.list_story_day_items(
    p_relationship_id => '00000000-0000-0000-0000-0000000938e1', p_occurred_on => CURRENT_DATE - 3,
    p_after_created_at => NULL, p_after_id => NULL, p_limit => 50);
  RESET ROLE;
  IF v_n <> 6 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the whole day returns % (want 6)', v_n; END IF;
  IF to_regprocedure('public.list_story_day_items(uuid,date,timestamptz,uuid,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 5-argument overload is still there (PGRST203)';
  END IF;
END $$;

-- D3. Per-author unviewed counts.
DO $$
DECLARE v record; v_seen int := 0;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938a1');
  FOR v IN SELECT * FROM public.list_story_day_counts('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 7, CURRENT_DATE) LOOP
    v_seen := v_seen + 1;
    IF v.author_id = '00000000-0000-0000-0000-0000000938b2' AND (v.item_count <> 3 OR v.unviewed_count <> 2 OR v.day_item_count <> 6) THEN
      RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: B''s day row is %', row_to_json(v);
    END IF;
    IF v.author_id = '00000000-0000-0000-0000-0000000938a1' AND (v.item_count <> 3 OR v.unviewed_count <> 0) THEN
      RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: my own day row is %', row_to_json(v);
    END IF;
    IF v.author_id = '00000000-0000-0000-0000-0000000938b2' AND v.newest_thumbnail_key IS DISTINCT FROM 'story-media/d938/6-thumbnail' THEN
      RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted story supplies the thumbnail: %', v.newest_thumbnail_key;
    END IF;
  END LOOP;
  RESET ROLE;
  IF v_seen <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % day-count rows (want 2)', v_seen; END IF;

  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938c3');
  SELECT count(*) INTO v_seen FROM public.list_story_day_counts('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 7, CURRENT_DATE);
  RESET ROLE;
  IF v_seen <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider sees % day-count rows', v_seen; END IF;
  UPDATE public.relationships SET status = 'paused' WHERE id = '00000000-0000-0000-0000-0000000938e1';
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938a1');
  SELECT count(*) INTO v_seen FROM public.list_story_day_counts('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 7, CURRENT_DATE);
  RESET ROLE;
  IF v_seen <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a paused couple''s calendar shows % rows', v_seen; END IF;
  UPDATE public.relationships SET status = 'active' WHERE id = '00000000-0000-0000-0000-0000000938e1';
END $$;

-- D4. Grants and search_path.
DO $$
DECLARE v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.list_story_day_items(uuid,date,timestamptz,uuid,integer,uuid)',
                              'public.list_story_day_counts(uuid,date,date)'] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % grants are wrong', v_fn;
    END IF;
    IF NOT (SELECT prosecdef AND 'search_path=""' = ANY (coalesce(proconfig, '{}')) FROM pg_proc WHERE oid = v_fn::regprocedure) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is not a definer with search_path ''''', v_fn;
    END IF;
  END LOOP;
END $$;

-- D4b. Fix round 1 (review #1): the newest thumbnail is found in the same
-- pass or by an index probe, never by re-scanning a materialized CTE per
-- (day, author) group (127 ms vs 44 ms over 365 days).
DO $$
BEGIN
  IF pg_get_functiondef('public.list_story_day_counts(uuid,date,date)'::regprocedure) LIKE '%FROM visible v2%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the thumbnail lookup must probe the index, not re-scan the CTE';
  END IF;
END $$;

-- D6. Output equivalence (fix round 1): the counts equal an independent
-- reading of the table on a second day with a created_at tie (the id
-- breaks it) and a deleted newest story.
SET LOCAL session_replication_role = replica;
INSERT INTO public.story_items (id, client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at, has_been_viewed, deleted_at)
SELECT ('00000000-0000-0000-0000-0000009380' || lpad(n::text, 2, '0'))::uuid, gen_random_uuid(),
       '00000000-0000-0000-0000-0000000938e1',
       CASE WHEN n = 12 THEN '00000000-0000-0000-0000-0000000938a1'::uuid ELSE '00000000-0000-0000-0000-0000000938b2'::uuid END,
       'image', 'story-media/d938/' || n || '-media', 'story-media/d938/' || n || '-thumbnail', 100, 100,
       CURRENT_DATE - 5, now() - interval '5 days' + CASE WHEN n = 13 THEN interval '9 minutes' ELSE interval '1 minute' END,
       now() - interval '5 days' + CASE WHEN n = 13 THEN interval '9 minutes' ELSE interval '1 minute' END + interval '24 hours',
       n = 10, CASE WHEN n = 13 THEN now() END
FROM generate_series(10, 13) n;
SET LOCAL session_replication_role = origin;
-- day -5: B's 10 (seen) and 11 tie on created_at, 11 wins; A's 12; B's 13 deleted.

CREATE TEMP TABLE d6_got AS SELECT * FROM public.list_story_day_counts(NULL, NULL, NULL) WHERE false;
GRANT ALL ON d6_got TO authenticated;
DO $$
DECLARE v_diff int; v_rows int;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938a1');
  INSERT INTO d6_got SELECT * FROM public.list_story_day_counts('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 7, CURRENT_DATE);
  RESET ROLE;
  WITH want AS (
    SELECT si.occurred_on, si.author_id,
           count(*) AS item_count,
           (SELECT count(*) FROM public.story_items d
             WHERE d.relationship_id = si.relationship_id AND d.occurred_on = si.occurred_on AND d.deleted_at IS NULL) AS day_item_count,
           (SELECT t.thumbnail_key FROM public.story_items t
             WHERE t.relationship_id = si.relationship_id AND t.occurred_on = si.occurred_on
               AND t.author_id = si.author_id AND t.deleted_at IS NULL
             ORDER BY t.created_at DESC, t.id DESC LIMIT 1) AS newest_thumbnail_key,
           max(si.created_at) AS newest_created_at,
           count(*) FILTER (WHERE si.author_id <> '00000000-0000-0000-0000-0000000938a1' AND NOT si.has_been_viewed) AS unviewed_count
      FROM public.story_items si
     WHERE si.relationship_id = '00000000-0000-0000-0000-0000000938e1' AND si.deleted_at IS NULL
     GROUP BY si.relationship_id, si.occurred_on, si.author_id
  )
  SELECT (SELECT count(*) FROM (SELECT * FROM want EXCEPT SELECT * FROM d6_got) a)
       + (SELECT count(*) FROM (SELECT * FROM d6_got EXCEPT SELECT * FROM want) b),
         (SELECT count(*) FROM d6_got)
    INTO v_diff, v_rows;
  IF v_diff <> 0 OR v_rows <> 4 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: day counts differ from the table (% rows differ, % rows)', v_diff, v_rows;
  END IF;
  IF (SELECT newest_thumbnail_key FROM d6_got WHERE occurred_on = CURRENT_DATE - 5
        AND author_id = '00000000-0000-0000-0000-0000000938b2') IS DISTINCT FROM 'story-media/d938/11-thumbnail' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a created_at tie or a deleted story picks the wrong thumbnail';
  END IF;
END $$;

-- D5. The author filter opens nothing new: an outsider naming an author gets
-- nothing, and an ended space reads nothing for either partner.
DO $$
DECLARE v_n int;
BEGIN
  -- Fix round 1 (review #3): my own space, naming a stranger as author.
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938a1');
  SELECT count(*) INTO v_n FROM public.list_story_day_items('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 3,
           p_author_id => '00000000-0000-0000-0000-0000000938c3');
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a stranger''s author id reads % stories', v_n; END IF;
  -- Fix round 1 (review #3): an archived chat (chat_archived_at set) reads
  -- nothing through either function.
  UPDATE public.relationships SET chat_archived_at = now() WHERE id = '00000000-0000-0000-0000-0000000938e1';
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938a1');
  SELECT count(*) INTO v_n FROM public.list_story_day_items('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 3,
           p_author_id => '00000000-0000-0000-0000-0000000938b2');
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: an archived space reads % of B''s stories', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.list_story_day_items('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 3);
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: an archived space reads % stories of the day', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.list_story_day_counts('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 7, CURRENT_DATE);
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an archived space''s calendar shows % rows', v_n; END IF;
  UPDATE public.relationships SET chat_archived_at = NULL WHERE id = '00000000-0000-0000-0000-0000000938e1';

  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938c3');
  SELECT count(*) INTO v_n FROM public.list_story_day_items('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 3,
           p_author_id => '00000000-0000-0000-0000-0000000938b2');
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider reads % of B''s stories', v_n; END IF;
  UPDATE public.relationships SET status = 'ended' WHERE id = '00000000-0000-0000-0000-0000000938e1';
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000938a1');
  SELECT count(*) INTO v_n FROM public.list_story_day_items('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 3,
           p_author_id => '00000000-0000-0000-0000-0000000938b2');
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: an ended space reads % of B''s stories', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.list_story_day_items('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 3,
           p_author_id => '00000000-0000-0000-0000-0000000938a1');
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: an ended space reads % of my own stories', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.list_story_day_counts('00000000-0000-0000-0000-0000000938e1', CURRENT_DATE - 7, CURRENT_DATE);
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an ended space''s calendar shows % rows', v_n; END IF;
END $$;

ROLLBACK;
