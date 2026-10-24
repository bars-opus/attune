-- supabase/tests/story_archival_contracts.sql
--
-- Stories Wave 5, Task 9 (review 04 #7, #9, #14): the claim hands the worker
-- each image's size, never hands it a deleted story, and a failure cannot
-- reopen a job that a delete already closed. Small images are considered and
-- left alone. The worker runs every 5 minutes, only while work waits.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000936a1'), ('00000000-0000-0000-0000-0000000936b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000936a1', '+15550936001', 'AA'),
  ('00000000-0000-0000-0000-0000000936b2', '+15550936002', 'AB')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
  ('00000000-0000-0000-0000-0000000936e1', '00000000-0000-0000-0000-0000000936a1', '00000000-0000-0000-0000-0000000936b2', 'active');

-- Three image stories past their 24 hours (the insert trigger seeds their jobs
-- with available_at = expires_at): s1 portrait 1440x2560, s2 soon deleted,
-- s3 already small (1080x1600).
INSERT INTO public.story_items (id, client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at)
VALUES
  ('00000000-0000-0000-0000-000000936001', gen_random_uuid(), '00000000-0000-0000-0000-0000000936e1', '00000000-0000-0000-0000-0000000936a1',
   'image', 'story-media/a936/1-media', 'story-media/a936/1-thumbnail', 1440, 2560, CURRENT_DATE - 2, now() - interval '30 hours', now() - interval '6 hours'),
  ('00000000-0000-0000-0000-000000936002', gen_random_uuid(), '00000000-0000-0000-0000-0000000936e1', '00000000-0000-0000-0000-0000000936a1',
   'image', 'story-media/a936/2-media', 'story-media/a936/2-thumbnail', 1440, 2560, CURRENT_DATE - 2, now() - interval '29 hours', now() - interval '5 hours'),
  ('00000000-0000-0000-0000-000000936003', gen_random_uuid(), '00000000-0000-0000-0000-0000000936e1', '00000000-0000-0000-0000-0000000936a1',
   'image', 'story-media/a936/3-media', 'story-media/a936/3-thumbnail', 1080, 1600, CURRENT_DATE - 2, now() - interval '28 hours', now() - interval '4 hours');
-- s2 is deleted by a path that did not close its job (a row from before
-- 20260938140000, or any future path): the job is still pending.
UPDATE public.story_items SET deleted_at = now() WHERE id = '00000000-0000-0000-0000-000000936002';

-- A1. The claim returns sizes, skips and closes the deleted story's job.
DO $$
DECLARE v record; v_ids uuid[] := '{}'; v_job record;
BEGIN
  FOR v IN SELECT * FROM public.claim_story_archival_batch(10) LOOP
    v_ids := v_ids || v.story_id;
    IF v.story_id = '00000000-0000-0000-0000-000000936001'
       AND (v.media_width <> 1440 OR v.media_height <> 2560 OR v.media_key <> 'story-media/a936/1-media') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the claim row is %', row_to_json(v);
    END IF;
  END LOOP;
  IF NOT (v_ids @> ARRAY['00000000-0000-0000-0000-000000936001', '00000000-0000-0000-0000-000000936003']::uuid[]) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: claimed %', v_ids;
  END IF;
  IF '00000000-0000-0000-0000-000000936002'::uuid = ANY (v_ids) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted story was handed to the worker (04 #14)';
  END IF;
  SELECT * INTO v_job FROM public.story_media_processing_outbox WHERE story_item_id = '00000000-0000-0000-0000-000000936002';
  IF v_job.state IS DISTINCT FROM 'done' OR v_job.last_error_code IS DISTINCT FROM 'story_deleted' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the deleted story''s job is % / %', v_job.state, v_job.last_error_code;
  END IF;
END $$;

-- A2. A failure after a delete closed the job does not reopen it.
DO $$
DECLARE v_res jsonb; v_job record;
BEGIN
  v_res := public.fail_story_archival('00000000-0000-0000-0000-000000936002', 'TRANSFORM_FAILED');
  SELECT * INTO v_job FROM public.story_media_processing_outbox WHERE story_item_id = '00000000-0000-0000-0000-000000936002';
  IF v_job.state IS DISTINCT FROM 'done' OR (v_res->>'found') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fail reopened a closed job: % %', v_job.state, v_res;
  END IF;
  -- A processing job still fails back to pending, as before.
  v_res := public.fail_story_archival('00000000-0000-0000-0000-000000936001', 'TRANSFORM_FAILED');
  SELECT * INTO v_job FROM public.story_media_processing_outbox WHERE story_item_id = '00000000-0000-0000-0000-000000936001';
  IF v_job.state IS DISTINCT FROM 'pending' OR v_job.attempts <> 1 OR v_job.last_error_code IS DISTINCT FROM 'TRANSFORM_FAILED' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a processing failure is % / % / %', v_job.state, v_job.attempts, v_job.last_error_code;
  END IF;
END $$;

-- A3. A small image is considered, its key kept, nothing queued for deletion.
DO $$
DECLARE v_res jsonb; v_story record; v_job record;
BEGIN
  v_res := public.skip_story_archival('00000000-0000-0000-0000-000000936003');
  SELECT * INTO v_story FROM public.story_items WHERE id = '00000000-0000-0000-0000-000000936003';
  SELECT * INTO v_job FROM public.story_media_processing_outbox WHERE story_item_id = '00000000-0000-0000-0000-000000936003';
  IF (v_res->>'skipped') IS DISTINCT FROM 'true' OR v_story.downscaled_at IS NULL
     OR v_story.media_key IS DISTINCT FROM 'story-media/a936/3-media'
     OR v_job.state IS DISTINCT FROM 'done' OR v_job.last_error_code IS DISTINCT FROM 'already_small' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: skip left % / % / %', v_res, v_story.downscaled_at, v_job.state;
  END IF;
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = 'story-media/a936/3-media') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: skipping queued the original for deletion';
  END IF;
  -- Skipping a deleted story changes nothing.
  v_res := public.skip_story_archival('00000000-0000-0000-0000-000000936002');
  IF (v_res->>'skipped') IS DISTINCT FROM 'false'
     OR (SELECT downscaled_at FROM public.story_items WHERE id = '00000000-0000-0000-0000-000000936002') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted story was marked considered: %', v_res;
  END IF;
  -- A considered story is never claimed again, and its stray job is closed.
  UPDATE public.story_media_processing_outbox SET state = 'pending' WHERE story_item_id = '00000000-0000-0000-0000-000000936003';
  IF EXISTS (SELECT 1 FROM public.claim_story_archival_batch(10) c WHERE c.story_id = '00000000-0000-0000-0000-000000936003') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a considered story was claimed again';
  END IF;
  IF (SELECT state FROM public.story_media_processing_outbox WHERE story_item_id = '00000000-0000-0000-0000-000000936003') <> 'done' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a considered story''s stray job stays open (the cron would never idle)';
  END IF;
END $$;

-- A4. Grants, search_path, index, cron.
DO $$
DECLARE v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.claim_story_archival_batch(integer)', 'public.fail_story_archival(uuid,text)',
                              'public.skip_story_archival(uuid)'] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR has_function_privilege('authenticated', v_fn, 'EXECUTE')
       OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % grants are wrong', v_fn;
    END IF;
    IF NOT ('search_path=""' = ANY (coalesce((SELECT proconfig FROM pg_proc WHERE oid = v_fn::regprocedure), '{}'))) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % does not pin search_path', v_fn;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_story_items_video_closeout') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the video close-out has no index';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'invoke-story-archival' AND schedule = '*/5 * * * *'
                 AND command LIKE '%process-story-archival%' AND command LIKE '%EXISTS%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the archival worker is not on its 5-minute, only-when-due schedule';
  END IF;
END $$;

-- A5. A second complete for a story already swapped (a lease that ran out
-- while the first worker was still finishing: both used the same archive key)
-- must not queue the live rendition for deletion. Deviation from the brief:
-- complete_story_archival gains this one guard and pins search_path.
INSERT INTO public.story_items (id, client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at)
VALUES ('00000000-0000-0000-0000-000000936004', gen_random_uuid(), '00000000-0000-0000-0000-0000000936e1', '00000000-0000-0000-0000-0000000936a1',
   'image', 'story-media/a936/4-media', 'story-media/a936/4-thumbnail', 2000, 2000, CURRENT_DATE - 2, now() - interval '27 hours', now() - interval '3 hours');
DO $$
DECLARE v_key text := public.story_archive_key('00000000-0000-0000-0000-000000936004'); v_res jsonb;
BEGIN
  v_res := public.complete_story_archival('00000000-0000-0000-0000-000000936004', v_key);
  IF (v_res->>'swapped') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first complete did not swap: %', v_res;
  END IF;
  v_res := public.complete_story_archival('00000000-0000-0000-0000-000000936004', v_key);
  IF (v_res->>'swapped') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second complete swapped again: %', v_res;
  END IF;
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = v_key) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a late second complete queued the live rendition for deletion';
  END IF;
  IF (SELECT media_key FROM public.story_items WHERE id = '00000000-0000-0000-0000-000000936004') IS DISTINCT FROM v_key THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the swapped key changed';
  END IF;
  IF NOT ('search_path=""' = ANY (coalesce((SELECT proconfig FROM pg_proc
          WHERE oid = 'public.complete_story_archival(uuid,text)'::regprocedure), '{}'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: complete_story_archival does not pin search_path';
  END IF;
END $$;

-- A6. ...but when the story was deleted after the first swap (and the drain
-- already removed its archive key), a late complete re-uploaded that key: it
-- must be queued again, or the deleted photo stays in the bucket (review B5 #1).
INSERT INTO public.story_items (id, client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at)
VALUES ('00000000-0000-0000-0000-000000936005', gen_random_uuid(), '00000000-0000-0000-0000-0000000936e1', '00000000-0000-0000-0000-0000000936a1',
   'image', 'story-media/a936/5-media', 'story-media/a936/5-thumbnail', 2000, 2000, CURRENT_DATE - 2, now() - interval '27 hours', now() - interval '3 hours');
DO $$
DECLARE v_key text := public.story_archive_key('00000000-0000-0000-0000-000000936005'); v_res jsonb;
BEGIN
  v_res := public.complete_story_archival('00000000-0000-0000-0000-000000936005', v_key);
  IF (v_res->>'swapped') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first complete did not swap: %', v_res;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000936a1', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '00000000-0000-0000-0000-0000000936a1', 'role', 'authenticated')::text, true);
  v_res := public.delete_story_item('00000000-0000-0000-0000-000000936005');
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF (v_res->>'deleted') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author could not delete: %', v_res;
  END IF;
  -- The drain ran: the archive key is gone from the bucket.
  UPDATE public.media_deletion_queue SET deleted_at = now() WHERE object_name = v_key;
  v_res := public.complete_story_archival('00000000-0000-0000-0000-000000936005', v_key);
  IF (v_res->>'swapped') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted story was swapped: %', v_res;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = v_key AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a late complete left a deleted story''s rendition behind';
  END IF;
END $$;

-- A7. The cron's idle check is index-backed: pending by available_at (the
-- claim index) and stale processing by processing_started_at (review B5 #7).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_story_media_jobs_processing'
                 AND indexdef LIKE '%(processing_started_at)%' AND indexdef LIKE '%processing%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: stale processing jobs have no index';
  END IF;
  IF (SELECT count(*) FROM regexp_matches((SELECT command FROM cron.job WHERE jobname = 'invoke-story-archival'), 'EXISTS', 'g')) < 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the cron predicate is not split into index-friendly EXISTS';
  END IF;
END $$;

ROLLBACK;
