-- supabase/tests/story_hardening_contracts.sql
--
-- Stories Wave 5, Task 3: the story-media bucket refuses oversize and
-- foreign objects itself (05 #5, 01 #17); the two intent limits are
-- serialized per person (01 #18); video and thumbnail intents last an hour,
-- image media 15 minutes (Wave 2 final review I2).
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000930a1'), ('00000000-0000-0000-0000-0000000930b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000930a1', '+15550930001', 'HA'),
  ('00000000-0000-0000-0000-0000000930b2', '+15550930002', 'HB')
ON CONFLICT (id) DO NOTHING;
UPDATE public.feature_flags SET enabled = true WHERE key = 'stories';

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- H1. The bucket ceiling, against a storage.buckets shaped like the hosted
-- one (the local harness's has no limit columns; add them only if missing).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'storage' AND table_name = 'buckets' AND column_name = 'file_size_limit') THEN
    ALTER TABLE storage.buckets ADD COLUMN file_size_limit bigint, ADD COLUMN allowed_mime_types text[];
  END IF;
END $$;
\ir ../migrations/20261024100100_story_media_bucket_limits.sql
DO $$
DECLARE v_public boolean; v_limit bigint; v_types text[];
BEGIN
  EXECUTE 'SELECT public, file_size_limit, allowed_mime_types FROM storage.buckets WHERE id = ''story-media'''
    INTO v_public, v_limit, v_types;
  IF v_public IS DISTINCT FROM false THEN RAISE EXCEPTION 'CONTRACT VIOLATED: story-media is public'; END IF;
  IF v_limit IS DISTINCT FROM 26214400 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: story-media size limit is % (want 25 MB)', v_limit;
  END IF;
  IF v_types IS DISTINCT FROM ARRAY['image/jpeg', 'video/mp4'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: story-media accepts %', v_types;
  END IF;
END $$;

-- H2. Lifetimes: image media 15 minutes; video media and thumbnails an hour.
DO $$
DECLARE v_rel uuid; v_res jsonb; v_left interval;
BEGIN
  INSERT INTO public.relationships (user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-0000000930a1', '00000000-0000-0000-0000-0000000930b2', 'active')
  RETURNING id INTO v_rel;
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000930a1');
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  v_left := (v_res->>'expires_at')::timestamptz - now();
  IF v_left NOT BETWEEN interval '14 minutes 55 seconds' AND interval '15 minutes 5 seconds' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an image intent lasts % (want 15 min)', v_left;
  END IF;
  v_res := public.create_story_upload_intent(v_rel, 'media', 'video', 'video/mp4');
  v_left := (v_res->>'expires_at')::timestamptz - now();
  IF v_left NOT BETWEEN interval '59 minutes 55 seconds' AND interval '60 minutes 5 seconds' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a video intent lasts % (want 60 min)', v_left;
  END IF;
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_left := (v_res->>'expires_at')::timestamptz - now();
  IF v_left NOT BETWEEN interval '59 minutes 55 seconds' AND interval '60 minutes 5 seconds' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a thumbnail intent lasts % (want 60 min)', v_left;
  END IF;
  -- Still refused as before: a thumbnail cannot claim to be a video.
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'video', 'image/jpeg');
  IF v_res->>'code' IS DISTINCT FROM 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: thumbnail/video accepted: %', v_res;
  END IF;
  RESET ROLE;
END $$;

-- H3. The limits are counted under a per-person lock, taken before any
-- count; the function pins search_path to ''.
DO $$
DECLARE v_def text; v_lock int; v_count int; v_cfg text[];
BEGIN
  v_def := pg_get_functiondef('public.create_story_upload_intent(uuid,text,text,text)'::regprocedure);
  v_lock := position('pg_advisory_xact_lock' IN v_def);
  v_count := position('FROM public.story_media_upload_intents' IN v_def);
  IF v_lock = 0 OR v_count = 0 OR v_lock > v_count THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the intent limits are not serialized before counting (lock at %, count at %)', v_lock, v_count;
  END IF;
  SELECT proconfig INTO v_cfg FROM pg_proc WHERE oid = 'public.create_story_upload_intent(uuid,text,text,text)'::regprocedure;
  IF NOT ('search_path=""' = ANY (coalesce(v_cfg, '{}'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: create_story_upload_intent search_path is %', v_cfg;
  END IF;
  IF has_function_privilege('anon', 'public.create_story_upload_intent(uuid,text,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.create_story_upload_intent(uuid,text,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: create_story_upload_intent grants changed';
  END IF;
END $$;

ROLLBACK;
