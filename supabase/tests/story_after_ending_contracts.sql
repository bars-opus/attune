-- supabase/tests/story_after_ending_contracts.sql
--
-- Stories Wave 5, Task 13 (review 05 #3; STORIES.md §3.3 "an author never
-- loses the right to remove their own retained media"): after an ending
-- the author can list and delete their own stories, and only their own.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000934a1'), ('00000000-0000-0000-0000-0000000934b2'),
  ('00000000-0000-0000-0000-0000000934c3'), ('00000000-0000-0000-0000-0000000934d4')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000934a1', '+15550934001', 'Ama'),
  ('00000000-0000-0000-0000-0000000934b2', '+15550934002', 'Kojo'),
  ('00000000-0000-0000-0000-0000000934c3', '+15550934003', 'Efua'),
  ('00000000-0000-0000-0000-0000000934d4', '+15550934004', 'Kwame')
ON CONFLICT (id) DO NOTHING;
-- R1: Ama and Kojo, ended. R2: Efua and Kwame, active (and Ama is not in it).
INSERT INTO public.relationships (id, user_a, user_b, status, ended_at) VALUES
  ('00000000-0000-0000-0000-0000000934e1', '00000000-0000-0000-0000-0000000934a1', '00000000-0000-0000-0000-0000000934b2', 'ended', now() - interval '3 days'),
  ('00000000-0000-0000-0000-0000000934e2', '00000000-0000-0000-0000-0000000934c3', '00000000-0000-0000-0000-0000000934d4', 'active', NULL);

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.story(p_rel uuid, p_author uuid, p_n int, p_days int) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.story_items (client_story_id, relationship_id, author_id, media_type, media_key,
    thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at)
  SELECT gen_random_uuid(), p_rel, p_author, CASE WHEN g % 3 = 0 THEN 'video' ELSE 'image' END,
         'story-media/' || p_rel || '/' || p_author || '/' || p_days || '-' || g || '-media',
         'story-media/' || p_rel || '/' || p_author || '/' || p_days || '-' || g || '-thumbnail', 100, 100,
         CURRENT_DATE - p_days, now() - make_interval(days => p_days, mins => g),
         now() - make_interval(days => p_days, mins => g) + interval '24 hours'
  FROM generate_series(1, p_n) g;
$$;

SET LOCAL session_replication_role = replica;  -- no outbox rows, no signals: fixtures only
SELECT pg_temp.story('00000000-0000-0000-0000-0000000934e1', '00000000-0000-0000-0000-0000000934a1', 3, 10);
SELECT pg_temp.story('00000000-0000-0000-0000-0000000934e1', '00000000-0000-0000-0000-0000000934b2', 2, 9);
SELECT pg_temp.story('00000000-0000-0000-0000-0000000934e2', '00000000-0000-0000-0000-0000000934c3', 2, 1);
-- Video rows need a duration (story_duration_matches_type).
UPDATE public.story_items SET duration_ms = 5000 WHERE media_type = 'video';
-- One place pin per story of Ama's (review I9: delete-all must clear them).
INSERT INTO public.story_places (story_item_id, relationship_id, author_id, lat, lng, label)
SELECT s.id, s.relationship_id, s.author_id, 5.6, -0.19, 'Osu'
  FROM public.story_items s WHERE s.author_id = '00000000-0000-0000-0000-0000000934a1';
SET LOCAL session_replication_role = origin;

-- A1. Ama sees her one closed chapter and only her own stories in it.
DO $$
DECLARE v record; v_n int; v_ids uuid[];
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934a1');
  SELECT count(*) INTO v_n FROM public.list_my_closed_story_chapters();
  SELECT * INTO v FROM public.list_my_closed_story_chapters();
  RESET ROLE;
  IF v_n <> 1 OR v.relationship_id <> '00000000-0000-0000-0000-0000000934e1' OR v.story_count <> 3
     OR v.status <> 'ended' OR v.ended_at IS NULL OR v.first_on <> CURRENT_DATE - 10 OR v.last_on <> CURRENT_DATE - 10 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ama''s chapters are % rows, first %', v_n, row_to_json(v);
  END IF;
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934a1');
  SELECT array_agg(i.id) INTO v_ids FROM public.list_my_closed_story_items('00000000-0000-0000-0000-0000000934e1') i;
  RESET ROLE;
  IF cardinality(v_ids) <> 3 OR EXISTS (SELECT 1 FROM public.story_items s WHERE s.id = ANY (v_ids)
                                         AND s.author_id <> '00000000-0000-0000-0000-0000000934a1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ama lists %', v_ids;
  END IF;
END $$;

-- A1b. The ex-partner sees only his own stories in the same past space.
DO $$
DECLARE v_ids uuid[];
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934b2');
  SELECT array_agg(i.id) INTO v_ids FROM public.list_my_closed_story_items('00000000-0000-0000-0000-0000000934e1') i;
  RESET ROLE;
  IF cardinality(v_ids) <> 2 OR EXISTS (SELECT 1 FROM public.story_items s WHERE s.id = ANY (v_ids)
                                         AND s.author_id <> '00000000-0000-0000-0000-0000000934b2') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ex-partner lists %', v_ids;
  END IF;
END $$;

-- A2. Paged by keyset.
DO $$
DECLARE v_first record; v_n int;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934a1');
  SELECT * INTO v_first FROM public.list_my_closed_story_items('00000000-0000-0000-0000-0000000934e1', NULL, NULL, 1);
  SELECT count(*) INTO v_n FROM public.list_my_closed_story_items('00000000-0000-0000-0000-0000000934e1', v_first.created_at, v_first.id, 50);
  RESET ROLE;
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the page after the first has % rows (want 2)', v_n; END IF;
END $$;

-- A3. An open space is not "past": nothing listed, delete refused.
DO $$
DECLARE v_n int; v_res jsonb;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934c3');
  SELECT count(*) INTO v_n FROM public.list_my_closed_story_chapters();
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: an open space is listed as past'; END IF;
  SELECT count(*) INTO v_n FROM public.list_my_closed_story_items('00000000-0000-0000-0000-0000000934e2');
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: an open space''s stories are listed here'; END IF;
  v_res := public.delete_my_closed_story_items('00000000-0000-0000-0000-0000000934e2');
  RESET ROLE;
  IF v_res->>'code' IS DISTINCT FROM 'UNAVAILABLE'
     OR (SELECT count(*) FROM public.story_items WHERE relationship_id = '00000000-0000-0000-0000-0000000934e2' AND deleted_at IS NULL) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: delete-all on an open space: %', v_res;
  END IF;
END $$;

-- A4. Someone else's space, or one that does not exist: nothing, and the same answer.
DO $$
DECLARE v_res jsonb; v_res2 jsonb;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934c3');
  v_res := public.delete_my_closed_story_items('00000000-0000-0000-0000-0000000934e1');
  v_res2 := public.delete_my_closed_story_items(gen_random_uuid());
  RESET ROLE;
  IF v_res IS DISTINCT FROM v_res2 OR (v_res->>'deleted')::int <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider''s delete-all says % vs %', v_res, v_res2;
  END IF;
  IF (SELECT count(*) FROM public.story_items WHERE relationship_id = '00000000-0000-0000-0000-0000000934e1' AND deleted_at IS NULL) <> 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider deleted stories';
  END IF;
END $$;

-- A8. can_download is true only while the chapter is still in an export
-- (relationship_chat_open_for: ended under 30 days, not sealed by me, not
-- archived), so the delete confirm never offers a download that cannot
-- happen (batch 7 review I1).
DO $$
DECLARE v_can boolean;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934a1');
  SELECT c.can_download INTO v_can FROM public.list_my_closed_story_chapters() c;
  RESET ROLE;
  IF v_can IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a space ended 3 days ago says can_download %', v_can;
  END IF;

  UPDATE public.relationships SET ended_at = now() - interval '31 days'
   WHERE id = '00000000-0000-0000-0000-0000000934e1';
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934a1');
  SELECT c.can_download INTO v_can FROM public.list_my_closed_story_chapters() c;
  RESET ROLE;
  IF v_can IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a space ended 31 days ago says can_download %', v_can;
  END IF;
  UPDATE public.relationships SET ended_at = now() - interval '3 days'
   WHERE id = '00000000-0000-0000-0000-0000000934e1';

  INSERT INTO public.relationship_seals (relationship_id, user_id)
  VALUES ('00000000-0000-0000-0000-0000000934e1', '00000000-0000-0000-0000-0000000934a1');
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934a1');
  SELECT c.can_download INTO v_can FROM public.list_my_closed_story_chapters() c;
  RESET ROLE;
  IF v_can IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a space I sealed says can_download %', v_can;
  END IF;
  DELETE FROM public.relationship_seals
   WHERE relationship_id = '00000000-0000-0000-0000-0000000934e1';

  UPDATE public.relationships SET status = 'archived', chat_archived_at = now()
   WHERE id = '00000000-0000-0000-0000-0000000934e1';
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934a1');
  SELECT c.can_download INTO v_can FROM public.list_my_closed_story_chapters() c;
  RESET ROLE;
  IF v_can IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an archived space says can_download %', v_can;
  END IF;
  UPDATE public.relationships SET status = 'ended', chat_archived_at = NULL
   WHERE id = '00000000-0000-0000-0000-0000000934e1';
END $$;

-- A5. Ama deletes all of hers: tombstoned, three keys each queued, Kojo's untouched.
DO $$
DECLARE v_res jsonb; v_n int;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934a1');
  v_res := public.delete_my_closed_story_items('00000000-0000-0000-0000-0000000934e1');
  RESET ROLE;
  IF (v_res->>'error') IS DISTINCT FROM 'false' OR (v_res->>'deleted')::int <> 3 OR (v_res->>'remaining')::int <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: delete-all said %', v_res;
  END IF;
  SELECT count(*) INTO v_n FROM public.story_items
   WHERE relationship_id = '00000000-0000-0000-0000-0000000934e1' AND author_id = '00000000-0000-0000-0000-0000000934a1' AND deleted_at IS NULL;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % of Ama''s stories remain', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.media_deletion_queue q
   WHERE q.bucket_id = 'story-media' AND q.deleted_at IS NULL
     AND (q.object_name LIKE 'story-media/00000000-0000-0000-0000-0000000934e1/00000000-0000-0000-0000-0000000934a1/%'
          OR q.object_name IN (SELECT public.story_archive_key(s.id) FROM public.story_items s
                                WHERE s.author_id = '00000000-0000-0000-0000-0000000934a1'));
  IF v_n <> 9 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % of 9 objects queued for deletion', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.story_places
   WHERE author_id = '00000000-0000-0000-0000-0000000934a1';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % of Ama''s place pins remain after delete-all', v_n; END IF;
  IF (SELECT count(*) FROM public.story_items WHERE author_id = '00000000-0000-0000-0000-0000000934b2' AND deleted_at IS NULL) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Kojo''s stories were touched';
  END IF;
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934a1');
  v_res := public.delete_my_closed_story_items('00000000-0000-0000-0000-0000000934e1');
  SELECT count(*) INTO v_n FROM public.list_my_closed_story_chapters();
  RESET ROLE;
  IF (v_res->>'deleted')::int <> 0 OR v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after deleting all, % deleted again and % chapters listed', v_res, v_n;
  END IF;
END $$;

-- A6. Big chapters go in batches of 200.
DO $$
DECLARE v_res jsonb;
BEGIN
  SET LOCAL session_replication_role = replica;
  PERFORM pg_temp.story('00000000-0000-0000-0000-0000000934e1', '00000000-0000-0000-0000-0000000934b2', 205, 20);
  UPDATE public.story_items SET duration_ms = 5000 WHERE media_type = 'video' AND duration_ms IS NULL;
  SET LOCAL session_replication_role = origin;
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000934b2');
  v_res := public.delete_my_closed_story_items('00000000-0000-0000-0000-0000000934e1');
  IF (v_res->>'deleted')::int <> 200 OR (v_res->>'remaining')::int <> 7 THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: the first batch said % (want 200 deleted, 7 left)', v_res;
  END IF;
  v_res := public.delete_my_closed_story_items('00000000-0000-0000-0000-0000000934e1');
  RESET ROLE;
  IF (v_res->>'deleted')::int <> 7 OR (v_res->>'remaining')::int <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second batch said %', v_res;
  END IF;
END $$;

-- A9. The batch locks its rows up front and skips rows another delete holds
-- (SKIP LOCKED), so it never waits on a story row while holding the
-- story_change_signals row a single delete on another device is waiting for
-- (batch 7 review M10: two-device deadlock).
DO $$
BEGIN
  IF pg_get_functiondef('public.delete_my_closed_story_items(uuid)'::regprocedure) !~* 'FOR UPDATE\s+SKIP LOCKED' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: delete_my_closed_story_items does not lock its batch with SKIP LOCKED';
  END IF;
END $$;

-- A7. Grants and search_path.
DO $$
DECLARE v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.list_my_closed_story_chapters()',
                              'public.list_my_closed_story_items(uuid,timestamptz,uuid,integer)',
                              'public.delete_my_closed_story_items(uuid)'] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % grants are wrong', v_fn;
    END IF;
    IF NOT (SELECT prosecdef AND 'search_path=""' = ANY (coalesce(proconfig, '{}')) FROM pg_proc WHERE oid = v_fn::regprocedure) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is not a definer with search_path ''''', v_fn;
    END IF;
  END LOOP;
END $$;

ROLLBACK;
