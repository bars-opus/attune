-- cleanup_expired_chat_media_intents (hourly cron, revived by
-- 20261019120100) must not DELETE FROM storage.objects: hosted Supabase
-- refuses direct deletes from storage tables ("Direct deletion from
-- storage tables is not allowed. Use the Storage API instead." -- see
-- 20260930120000), so the old body threw on every run and abandoned
-- uploads' bytes were never removed. It now queues them for
-- process-media-deletion-queue, once per intent.
BEGIN;

-- Stand in for the platform's guard: any direct delete from
-- storage.objects raises, as it does on the hosted project.
CREATE FUNCTION pg_temp.refuse_direct_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Direct deletion from storage tables is not allowed. Use the Storage API instead.';
END $$;
CREATE TRIGGER zz_refuse_direct_delete BEFORE DELETE ON storage.objects
  FOR EACH ROW EXECUTE FUNCTION pg_temp.refuse_direct_delete();

SET LOCAL session_replication_role = replica;
INSERT INTO auth.users (id) VALUES
  ('e1200000-0000-0000-0000-0000000000a1'),
  ('e1200000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('e1200000-0000-0000-0000-0000000000a1', '+15550912001', 'A'),
  ('e1200000-0000-0000-0000-0000000000b2', '+15550912002', 'B')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status)
VALUES ('e1200000-0000-0000-0000-000000000001',
        'e1200000-0000-0000-0000-0000000000a1',
        'e1200000-0000-0000-0000-0000000000b2', 'active')
ON CONFLICT (id) DO NOTHING;
SET LOCAL session_replication_role = origin;

DELETE FROM public.media_deletion_queue WHERE object_name LIKE 'chat-media/e120-%';
INSERT INTO public.message_media_upload_intents
  (id, relationship_id, requester_id, storage_key, media_type, mime_type, expires_at, used_at)
VALUES
  -- Abandoned: expired, never used. Its bytes must go.
  ('e1200000-0000-0000-0000-000000000101', 'e1200000-0000-0000-0000-000000000001',
   'e1200000-0000-0000-0000-0000000000a1', 'chat-media/e120-abandoned.jpg', 'image', 'image/jpeg',
   now() - interval '1 hour', NULL),
  -- Used: belongs to a live message. Never queued.
  ('e1200000-0000-0000-0000-000000000102', 'e1200000-0000-0000-0000-000000000001',
   'e1200000-0000-0000-0000-0000000000a1', 'chat-media/e120-used.jpg', 'image', 'image/jpeg',
   now() - interval '1 hour', now() - interval '50 minutes'),
  -- Still valid: an upload may be in flight. Never queued.
  ('e1200000-0000-0000-0000-000000000103', 'e1200000-0000-0000-0000-000000000001',
   'e1200000-0000-0000-0000-0000000000a1', 'chat-media/e120-live.jpg', 'image', 'image/jpeg',
   now() + interval '10 minutes', NULL);
INSERT INTO storage.objects (bucket_id, name) VALUES
  ('message-media', 'chat-media/e120-abandoned.jpg'),
  ('message-media', 'chat-media/e120-used.jpg'),
  ('message-media', 'chat-media/e120-live.jpg');

CREATE FUNCTION pg_temp.queued() RETURNS SETOF text LANGUAGE sql AS $$
  SELECT object_name FROM public.media_deletion_queue
  WHERE bucket_id = 'message-media' AND object_name LIKE 'chat-media/e120-%'
  ORDER BY object_name $$;

DO $$
DECLARE v_n int; v_names text[];
BEGIN
  -- 1. The cron's command runs without error against the guard, and
  --    queues exactly the abandoned object.
  EXECUTE (SELECT command FROM cron.job WHERE jobname = 'cleanup-expired-chat-media');
  SELECT array_agg(q) INTO v_names FROM pg_temp.queued() q;
  IF v_names IS DISTINCT FROM ARRAY['chat-media/e120-abandoned.jpg'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: queued %', v_names;
  END IF;

  -- 2. The object row is left for the Storage API (the queue drain).
  IF NOT EXISTS (SELECT 1 FROM storage.objects WHERE name = 'chat-media/e120-abandoned.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: storage.objects row deleted directly';
  END IF;

  -- 3. Once per intent: the stamp stops a second run re-queueing it,
  --    and the function reports how many it queued.
  IF (SELECT cleanup_queued_at FROM public.message_media_upload_intents
      WHERE id = 'e1200000-0000-0000-0000-000000000101') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: abandoned intent not stamped';
  END IF;
  UPDATE public.media_deletion_queue SET deleted_at = now()
  WHERE object_name = 'chat-media/e120-abandoned.jpg';
  v_n := public.cleanup_expired_chat_media_intents();
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: second run queued % again', v_n;
  END IF;
  IF (SELECT deleted_at FROM public.media_deletion_queue
      WHERE object_name = 'chat-media/e120-abandoned.jpg') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: second run re-armed a drained deletion';
  END IF;

  -- 4. Pruning: a stamped intent goes 24h after its stamp; used and live
  --    intents stay (deletion paths still read used ones).
  UPDATE public.message_media_upload_intents
     SET cleanup_queued_at = now() - interval '25 hours'
   WHERE id = 'e1200000-0000-0000-0000-000000000101';
  UPDATE public.message_media_upload_intents
     SET used_at = now() - interval '25 hours'
   WHERE id = 'e1200000-0000-0000-0000-000000000102';
  PERFORM public.cleanup_expired_chat_media_intents();
  IF EXISTS (SELECT 1 FROM public.message_media_upload_intents
             WHERE id = 'e1200000-0000-0000-0000-000000000101') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: stamped intent not pruned after 24h';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.message_media_upload_intents
                 WHERE id = 'e1200000-0000-0000-0000-000000000102') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a used intent was pruned';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.message_media_upload_intents
                 WHERE id = 'e1200000-0000-0000-0000-000000000103') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a live intent was pruned';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_temp.queued() q WHERE q <> 'chat-media/e120-abandoned.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a used or live object was queued';
  END IF;

  -- 5. Not callable by app users.
  IF has_function_privilege('authenticated', 'public.cleanup_expired_chat_media_intents()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.cleanup_expired_chat_media_intents()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: cleanup callable by app roles';
  END IF;
END $$;

-- 6. Mutation check: the old body (a direct storage delete) must trip
--    the guard, which is what the hourly job hit on the hosted project.
SAVEPOINT mutation;
CREATE OR REPLACE FUNCTION public.cleanup_expired_chat_media_intents()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, storage AS $$
DECLARE v_count int;
BEGIN
  WITH expired AS (
    DELETE FROM storage.objects o USING public.message_media_upload_intents i
    WHERE o.bucket_id = 'message-media' AND o.name = i.storage_key
      AND i.used_at IS NULL AND i.expires_at < now()
    RETURNING o.id
  ) SELECT count(*) INTO v_count FROM expired;
  RETURN v_count;
END $$;
UPDATE public.message_media_upload_intents SET cleanup_queued_at = NULL
WHERE id = 'e1200000-0000-0000-0000-000000000103';
UPDATE public.message_media_upload_intents SET expires_at = now() - interval '1 minute'
WHERE id = 'e1200000-0000-0000-0000-000000000103';
DO $$
BEGIN
  BEGIN
    PERFORM public.cleanup_expired_chat_media_intents();
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Direct deletion from storage tables%' THEN RAISE; END IF;
    RAISE NOTICE 'mutation check: the old direct delete fails against the guard (as intended)';
    RETURN;
  END;
  RAISE EXCEPTION 'MUTATION NOT DETECTED: the old direct delete passed the guard';
END $$;
ROLLBACK TO SAVEPOINT mutation;

ROLLBACK;
