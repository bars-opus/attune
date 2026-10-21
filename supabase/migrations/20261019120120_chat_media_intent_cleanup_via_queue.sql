-- Chat review 2026-10-18 #24, follow-up. 20261019120100 pointed the hourly
-- 'cleanup-expired-chat-media' job at cleanup_expired_chat_media_intents()
-- (20260705200000). That body DELETEs FROM storage.objects directly, which
-- the hosted project refuses ("Direct deletion from storage tables is not
-- allowed. Use the Storage API instead." -- see 20260930120000), so every
-- run threw and no abandoned upload's bytes were ever removed: cancelled
-- sends, uploads whose reply was lost, and sends whose 15-minute slot ran
-- out before the insert.
--
-- Same shape as cleanup_expired_story_media_intents (20260938090000): it
-- never touches storage.objects. An unused, expired intent's key is queued
-- once for process-media-deletion-queue, and a cleanup_queued_at stamp
-- stops later runs re-queueing it. Safe to delete: the insert trigger only
-- accepts an intent with used_at IS NULL AND expires_at > now(), so an
-- expired one can never be attached to a message afterwards.
--
-- Prune: an unused intent 24h after its stamp. Used intents are kept, as
-- before (never queued: their key is a live message's media; the chapter
-- and account deletion paths still read them).

ALTER TABLE public.message_media_upload_intents
  ADD COLUMN IF NOT EXISTS cleanup_queued_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_message_media_upload_intents_cleanup
  ON public.message_media_upload_intents (expires_at)
  WHERE used_at IS NULL AND cleanup_queued_at IS NULL;

CREATE OR REPLACE FUNCTION public.cleanup_expired_chat_media_intents()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_key text;
  v_count int := 0;
BEGIN
  -- SKIP LOCKED: never wait on a row the insert trigger is consuming.
  -- RETURNING names exactly the rows this run stamped.
  FOR v_key IN
    UPDATE public.message_media_upload_intents i
       SET cleanup_queued_at = now()
     WHERE i.id IN (
             SELECT id
               FROM public.message_media_upload_intents
              WHERE used_at IS NULL
                AND cleanup_queued_at IS NULL
                AND expires_at < now()
              FOR UPDATE SKIP LOCKED
           )
     RETURNING i.storage_key
  LOOP
    PERFORM public.queue_media_deletion('message-media', v_key);
    v_count := v_count + 1;
  END LOOP;

  DELETE FROM public.message_media_upload_intents
   WHERE used_at IS NULL
     AND cleanup_queued_at IS NOT NULL
     AND cleanup_queued_at < now() - interval '24 hours';

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.cleanup_expired_chat_media_intents()
  FROM PUBLIC, anon, authenticated;
