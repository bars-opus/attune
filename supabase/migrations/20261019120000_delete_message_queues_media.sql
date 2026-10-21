-- Chat review 2026-10-18 #23: "Delete for everyone" nulled media_url /
-- media_thumbnail_url but never queued the storage objects, so the photo,
-- voice or video bytes stayed in the private bucket indefinitely (and any
-- signed URL minted in the previous 10 minutes kept working). Only the
-- BEFORE DELETE trigger queued media; delete_message is an UPDATE.
--
-- Body below is the CURRENT body (20261019110320, which is 20260950110000
-- plus the system-notice refusal, kept) (read in full) plus: the locking
-- SELECT also reads media_url / media_thumbnail_url, and after the UPDATE
-- succeeded both keys are handed to queue_media_deletion inside the same
-- transaction. queue_media_deletion ignores NULL/empty names and dedups
-- on (bucket_id, object_name), so a text message or a poster-less image is
-- a no-op and a retry cannot double-queue. Both chat media and the worker's
-- chat-thumbnails/… posters live in bucket 'message-media'. A legacy
-- bucket-prefixed key ('message-media/<key>') is queued as the bare object
-- name (final review M4). (The BEFORE DELETE trigger from
-- 20261018110000_chapters_deletion.sql still queues such keys as-is; it is
-- an earlier wave's migration and is left untouched here.)
CREATE OR REPLACE FUNCTION public.delete_message(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_locked_id uuid;
  v_locked_origin text;
  v_media_url text;
  v_thumbnail_url text;
  v_updated_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- Lock BEFORE the ownership/window check (Checklist 2.16); the media keys
  -- are read under the same lock so a concurrent delete cannot read them
  -- after this transaction has already nulled them.
  SELECT id, message_origin, media_url, media_thumbnail_url
    INTO v_locked_id, v_locked_origin, v_media_url, v_thumbnail_url
  FROM public.messages
  WHERE id = p_message_id
  FOR UPDATE;

  UPDATE public.messages
  SET content = NULL,
      media_url = NULL,
      media_type = NULL,
      media_thumbnail_url = NULL,
      deleted_at = now(),
      assistant_payload = CASE
        WHEN v_locked_origin = 'attune_assist' THEN NULL
        ELSE assistant_payload
      END,
      message_origin = CASE
        WHEN v_locked_origin = 'attune_assist' THEN 'user'
        ELSE message_origin
      END
  WHERE id = p_message_id
    AND sender_id = v_uid
    AND deleted_at IS NULL
    AND created_at > now() - interval '5 minutes'
    -- Chat review #19 (20261019110320): a system notice is never erased by
    -- the member it is attributed to. Kept verbatim.
    AND NOT messages.is_system_notice
    AND EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = messages.relationship_id
        AND r.status = 'active'
        AND r.chat_archived_at IS NULL
    )
  RETURNING id INTO v_updated_id;

  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'not_deletable' USING ERRCODE = '42501';
  END IF;

  -- Only after the tombstone is committed to this transaction: a rejected
  -- delete must never queue someone else's media.
  -- Final review M4: older rows may carry the bucket-prefixed form
  -- ('message-media/<key>', which the client tolerates); queued as-is the
  -- deletion worker would look for a non-existent object and the bytes
  -- would stay. A leading 'message-media/' is stripped before queueing.
  PERFORM public.queue_media_deletion(
    'message-media', regexp_replace(v_media_url, '^message-media/', ''));
  PERFORM public.queue_media_deletion(
    'message-media', regexp_replace(v_thumbnail_url, '^message-media/', ''));

  IF v_locked_origin = 'attune_assist' THEN
    DELETE FROM public.ai_assist_planning_links WHERE message_id = p_message_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_message(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_message(uuid) TO authenticated;
