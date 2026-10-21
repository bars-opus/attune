-- delete_message must queue the message's storage objects for deletion
-- (chat review 2026-10-18 #23): a soft-deleted photo/voice/video row kept
-- its bytes in the bucket forever because only the BEFORE DELETE trigger
-- queued media and delete_message is an UPDATE.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('d3110000-0000-0000-0000-0000000000a1'),
  ('d3110000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('d3110000-0000-0000-0000-0000000000a1', '+15550003101', 'A'),
  ('d3110000-0000-0000-0000-0000000000b2', '+15550003102', 'B')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status)
VALUES ('d3110000-0000-0000-0000-000000000001',
        'd3110000-0000-0000-0000-0000000000a1',
        'd3110000-0000-0000-0000-0000000000b2', 'active')
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- Media rows are inserted with triggers off: validate_message_media_before_insert
-- wants a consumed upload intent + storage object, which is not what is under
-- test here (same technique as relationship_purge_contracts.sql).
SET LOCAL session_replication_role = replica;
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_url, media_type, media_thumbnail_url, created_at)
VALUES
  ('d3110000-0000-0000-0000-000000000101', 'd3110000-0000-0000-0000-000000000001', 'd3110000-0000-0000-0000-0000000000a1', gen_random_uuid(), NULL, 'chat-media/d311-video.mp4', 'video', 'chat-media/d311-poster.jpg', now()),
  ('d3110000-0000-0000-0000-000000000102', 'd3110000-0000-0000-0000-000000000001', 'd3110000-0000-0000-0000-0000000000a1', gen_random_uuid(), NULL, 'chat-media/d311-photo.jpg', 'image', NULL, now()),
  ('d3110000-0000-0000-0000-000000000103', 'd3110000-0000-0000-0000-000000000001', 'd3110000-0000-0000-0000-0000000000b2', gen_random_uuid(), NULL, 'chat-media/d311-partner.jpg', 'image', NULL, now()),
  ('d3110000-0000-0000-0000-000000000104', 'd3110000-0000-0000-0000-000000000001', 'd3110000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'just words', NULL, NULL, NULL, now());
SET LOCAL session_replication_role = origin;

-- 1. Deleting my video queues BOTH the video and its poster, in bucket message-media.
SELECT pg_temp.as_user('d3110000-0000-0000-0000-0000000000a1');
SELECT public.delete_message('d3110000-0000-0000-0000-000000000101');
DO $$
DECLARE v_rows int;
BEGIN
  SELECT count(*) INTO v_rows FROM public.media_deletion_queue
  WHERE bucket_id = 'message-media'
    AND object_name IN ('chat-media/d311-video.mp4', 'chat-media/d311-poster.jpg')
    AND deleted_at IS NULL;
  IF v_rows <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expected video + poster queued, found % rows', v_rows;
  END IF;
  IF EXISTS (SELECT 1 FROM public.messages WHERE id = 'd3110000-0000-0000-0000-000000000101'
             AND (media_url IS NOT NULL OR media_thumbnail_url IS NOT NULL OR deleted_at IS NULL)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: tombstone not applied';
  END IF;
END $$;

-- 2. A photo with no thumbnail queues exactly one row.
SELECT public.delete_message('d3110000-0000-0000-0000-000000000102');
DO $$
BEGIN
  IF (SELECT count(*) FROM public.media_deletion_queue WHERE object_name = 'chat-media/d311-photo.jpg') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photo not queued exactly once';
  END IF;
END $$;

-- 3. A rejected delete (partner's message) queues nothing.
DO $$
BEGIN
  BEGIN
    PERFORM public.delete_message('d3110000-0000-0000-0000-000000000103');
    RAISE EXCEPTION 'CONTRACT VIOLATED: deleted the partner''s message';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = 'chat-media/d311-partner.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a rejected delete queued the partner''s media';
  END IF;
END $$;

-- 4. A text message deletes as before and adds no queue rows.
DO $$
DECLARE v_before int; v_after int;
BEGIN
  SELECT count(*) INTO v_before FROM public.media_deletion_queue;
  PERFORM public.delete_message('d3110000-0000-0000-0000-000000000104');
  SELECT count(*) INTO v_after FROM public.media_deletion_queue;
  IF v_after <> v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: text delete touched the media queue';
  END IF;
END $$;

-- 4b. A system notice still cannot be deleted (plan 1b protection kept).
SET LOCAL session_replication_role = replica;
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_url, media_type, is_system_notice, created_at)
VALUES ('d3110000-0000-0000-0000-000000000106', 'd3110000-0000-0000-0000-000000000001', 'd3110000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'A took a screenshot', 'chat-media/d311-notice.jpg', 'image', true, now());
SET LOCAL session_replication_role = origin;
DO $$
BEGIN
  BEGIN
    PERFORM public.delete_message('d3110000-0000-0000-0000-000000000106');
    RAISE EXCEPTION 'CONTRACT VIOLATED: deleted a system notice';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = 'chat-media/d311-notice.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused system-notice delete queued media';
  END IF;
END $$;

-- 4c. Final review M4: a legacy bucket-prefixed key ('message-media/<key>',
-- which the client still reads) is queued as the bare object name the
-- deletion worker can find — never with the bucket in the name.
SET LOCAL session_replication_role = replica;
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_url, media_type, media_thumbnail_url, created_at)
VALUES ('d3110000-0000-0000-0000-000000000107', 'd3110000-0000-0000-0000-000000000001', 'd3110000-0000-0000-0000-0000000000a1', gen_random_uuid(), NULL, 'message-media/chat-media/d311-legacy.mp4', 'video', 'message-media/chat-media/d311-legacy-poster.jpg', now());
SET LOCAL session_replication_role = origin;
SELECT pg_temp.as_user('d3110000-0000-0000-0000-0000000000a1');
SELECT public.delete_message('d3110000-0000-0000-0000-000000000107');
DO $$
BEGIN
  IF (SELECT count(*) FROM public.media_deletion_queue
      WHERE bucket_id = 'message-media'
        AND object_name IN ('chat-media/d311-legacy.mp4', 'chat-media/d311-legacy-poster.jpg')) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bucket-prefixed key was not queued under its bare object name';
  END IF;
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name LIKE 'message-media/%d311%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a key was queued with the bucket in its name';
  END IF;
END $$;

-- 4d. Mutation check for 4c: delete_message rebuilt WITHOUT the prefix strip
-- must queue the prefixed name (so 4c would fail). Savepoint-restored.
SAVEPOINT strip_mutation;
DO $$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('public.delete_message(uuid)'::regprocedure);
  v_def := replace(v_def, $r$regexp_replace(v_media_url, '^message-media/', '')$r$, 'v_media_url');
  v_def := replace(v_def, $r$regexp_replace(v_thumbnail_url, '^message-media/', '')$r$, 'v_thumbnail_url');
  IF position('regexp_replace' in v_def) > 0 THEN
    RAISE EXCEPTION 'MUTATION NOT APPLIED: the strip is still in the body';
  END IF;
  EXECUTE v_def;
END $$;
SET LOCAL session_replication_role = replica;
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_url, media_type, created_at)
VALUES ('d3110000-0000-0000-0000-000000000108', 'd3110000-0000-0000-0000-000000000001', 'd3110000-0000-0000-0000-0000000000a1', gen_random_uuid(), NULL, 'message-media/chat-media/d311-legacy-mutant.jpg', 'image', now());
SET LOCAL session_replication_role = origin;
SELECT pg_temp.as_user('d3110000-0000-0000-0000-0000000000a1');
SELECT public.delete_message('d3110000-0000-0000-0000-000000000108');
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = 'message-media/chat-media/d311-legacy-mutant.jpg') THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: without the strip the prefixed name should have been queued';
  END IF;
  RAISE NOTICE 'mutation check: contract 4c would fail without the prefix strip (as intended)';
END $$;
ROLLBACK TO SAVEPOINT strip_mutation;

-- 5. Mutation check: with queue_media_deletion stubbed to a no-op, contract 1
-- must FAIL. Done under a savepoint so the real function is restored.
SAVEPOINT mutation;
CREATE OR REPLACE FUNCTION public.queue_media_deletion(p_bucket_id text, p_object_name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$ BEGIN RETURN; END $$;
SET LOCAL session_replication_role = replica;
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_url, media_type, created_at)
VALUES ('d3110000-0000-0000-0000-000000000105', 'd3110000-0000-0000-0000-000000000001', 'd3110000-0000-0000-0000-0000000000a1', gen_random_uuid(), NULL, 'chat-media/d311-mutant.jpg', 'image', now());
SET LOCAL session_replication_role = origin;
SELECT pg_temp.as_user('d3110000-0000-0000-0000-0000000000a1');
SELECT public.delete_message('d3110000-0000-0000-0000-000000000105');
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = 'chat-media/d311-mutant.jpg') THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: the stubbed queue still recorded a row';
  END IF;
  RAISE NOTICE 'mutation check: contract 1 would fail with queue_media_deletion stubbed (as intended)';
END $$;
ROLLBACK TO SAVEPOINT mutation;

RESET ROLE;
ROLLBACK;
