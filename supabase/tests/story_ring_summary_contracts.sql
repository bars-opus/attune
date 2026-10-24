-- supabase/tests/story_ring_summary_contracts.sql
--
-- Stories Wave 5, Task 6 (review 03 L7, M2; Wave 4 M-6): the ring query
-- reads only active rows through its own index, and returns each author's
-- soonest expiry plus the server's clock.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000939a1'), ('00000000-0000-0000-0000-0000000939b2'),
  ('00000000-0000-0000-0000-0000000939c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000939a1', '+15550939001', 'GA'),
  ('00000000-0000-0000-0000-0000000939b2', '+15550939002', 'GB'),
  ('00000000-0000-0000-0000-0000000939c3', '+15550939003', 'GC')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
  ('00000000-0000-0000-0000-0000000939e1', '00000000-0000-0000-0000-0000000939a1', '00000000-0000-0000-0000-0000000939b2', 'active');

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- Two years of history (expired) plus three active stories.
SET LOCAL session_replication_role = replica;
INSERT INTO public.story_items (client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-0000000939e1',
       CASE WHEN g % 2 = 0 THEN '00000000-0000-0000-0000-0000000939a1'::uuid ELSE '00000000-0000-0000-0000-0000000939b2'::uuid END,
       'image', 'story-media/g939/old-' || g || '-media', 'story-media/g939/old-' || g || '-thumbnail', 100, 100,
       (now() - make_interval(hours => 5 + g))::date, now() - make_interval(hours => 5 + g),
       now() - make_interval(hours => 5 + g) + interval '24 hours'
FROM generate_series(30, 3600) g;
INSERT INTO public.story_items (client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at, has_been_viewed)
VALUES
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000939e1', '00000000-0000-0000-0000-0000000939b2', 'image',
   'story-media/g939/b1-media', 'story-media/g939/b1-thumbnail', 100, 100, CURRENT_DATE,
   now() - interval '20 hours', now() + interval '4 hours', false),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000939e1', '00000000-0000-0000-0000-0000000939b2', 'image',
   'story-media/g939/b2-media', 'story-media/g939/b2-thumbnail', 100, 100, CURRENT_DATE,
   now() - interval '2 hours', now() + interval '22 hours', true),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000939e1', '00000000-0000-0000-0000-0000000939a1', 'image',
   'story-media/g939/a1-media', 'story-media/g939/a1-thumbnail', 100, 100, CURRENT_DATE,
   now() - interval '1 hour', now() + interval '23 hours', false);
SET LOCAL session_replication_role = origin;
ANALYZE public.story_items;

-- R1. The index exists and the ring's own predicate uses it at volume.
DO $$
DECLARE v_plan text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_story_items_active'
                 AND indexdef LIKE '%(relationship_id, expires_at)%' AND indexdef LIKE '%deleted_at IS NULL%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no (relationship_id, expires_at) partial index for the ring (03 L7)';
  END IF;
  EXECUTE $q$EXPLAIN (FORMAT JSON)
    SELECT si.author_id, count(*) FROM public.story_items si
     WHERE si.relationship_id = '00000000-0000-0000-0000-0000000939e1'
       AND si.deleted_at IS NULL AND si.expires_at > now()
     GROUP BY si.author_id$q$ INTO v_plan;
  IF v_plan NOT LIKE '%idx_story_items_active%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ring query does not use idx_story_items_active: %', v_plan;
  END IF;
END $$;

-- R2. The summary's new columns.
DO $$
DECLARE v record; v_n int := 0;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000939a1');
  FOR v IN SELECT * FROM public.get_story_ring_summary('00000000-0000-0000-0000-0000000939e1') LOOP
    v_n := v_n + 1;
    IF v.server_now IS DISTINCT FROM now() THEN
      RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: server_now is %', v.server_now;
    END IF;
    IF v.author_id = '00000000-0000-0000-0000-0000000939b2' THEN
      IF v.active_count <> 2 OR v.unviewed_count <> 1 OR v.next_expires_at IS DISTINCT FROM now() + interval '4 hours'
         OR v.newest_thumbnail_key IS DISTINCT FROM 'story-media/g939/b2-thumbnail' THEN
        RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: partner row is %', row_to_json(v);
      END IF;
    ELSIF v.author_id = '00000000-0000-0000-0000-0000000939a1' THEN
      IF v.active_count <> 1 OR v.unviewed_count <> 0 OR v.next_expires_at IS DISTINCT FROM now() + interval '23 hours' THEN
        RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: my row is %', row_to_json(v);
      END IF;
    END IF;
  END LOOP;
  RESET ROLE;
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % ring rows (want 2)', v_n; END IF;

  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000939c3');
  SELECT count(*) INTO v_n FROM public.get_story_ring_summary('00000000-0000-0000-0000-0000000939e1');
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider sees % ring rows', v_n; END IF;
END $$;

-- R3. Grants and search_path.
DO $$
BEGIN
  IF has_function_privilege('anon', 'public.get_story_ring_summary(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_story_ring_summary(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_story_ring_summary grants are wrong';
  END IF;
  IF NOT ('search_path=""' = ANY (coalesce((SELECT proconfig FROM pg_proc
         WHERE oid = 'public.get_story_ring_summary(uuid)'::regprocedure), '{}'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_story_ring_summary does not pin search_path';
  END IF;
END $$;

ROLLBACK;
