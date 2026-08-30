-- Direct deletion from storage.objects is refused by the platform:
--
--   PostgrestException(message: Direct deletion from storage tables is not
--   allowed. Use the Storage API instead., code: 42501)
--
-- Three SECURITY DEFINER functions did exactly that. Because the DELETE
-- came AFTER the state change in each, the raised exception rolled the
-- whole function back — so mark_streak_viewed never decremented the
-- budget and never stamped viewed_at, and a watched streak stayed on
-- "Play" across restarts. mark_video_viewed had the same defect: the
-- media_url was never cleared, so a view-once video stayed viewable.
--
-- The functions now record what should be deleted and leave the deletion
-- to something that can call the Storage API. Recording cannot fail the
-- way DELETE did, so the state change always commits.

CREATE TABLE IF NOT EXISTS public.media_deletion_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id text NOT NULL,
  object_name text NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  -- The same object can be queued twice (a retry, or a message whose
  -- thumbnail shares a path); deleting an already-deleted object is a
  -- no-op, so this only keeps the queue from growing without bound.
  UNIQUE (bucket_id, object_name)
);

CREATE INDEX IF NOT EXISTS media_deletion_queue_pending_idx
  ON public.media_deletion_queue (requested_at)
  WHERE deleted_at IS NULL;

-- Server-side only. No client ever reads or writes this: it names storage
-- paths for messages the reader may not be party to.
ALTER TABLE public.media_deletion_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.media_deletion_queue FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.media_deletion_queue TO service_role;

-- Queues one object for deletion. SECURITY DEFINER so the callers, which
-- are themselves definer functions, can record without the invoker having
-- any rights on the queue.
CREATE OR REPLACE FUNCTION public.queue_media_deletion(
  p_bucket_id text,
  p_object_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_object_name IS NULL OR p_object_name = '' THEN
    RETURN;
  END IF;

  INSERT INTO public.media_deletion_queue (bucket_id, object_name)
  VALUES (p_bucket_id, p_object_name)
  ON CONFLICT (bucket_id, object_name) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.queue_media_deletion(text, text) FROM PUBLIC, anon;
-- Not granted to authenticated: only the definer functions below call it.
GRANT EXECUTE ON FUNCTION public.queue_media_deletion(text, text) TO service_role;

-- Spends one view of a streak, returning what remains.
--
-- Identical to 20260914140000 except that the two storage DELETEs are
-- replaced by queue_media_deletion. The streak_clips rows are still
-- deleted directly — that is an ordinary table this function owns, and
-- removing it is what makes the clips unplayable immediately.
CREATE OR REPLACE FUNCTION public.mark_streak_viewed(p_message_id uuid)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_is_member boolean;
  v_sender uuid;
  v_viewed_at timestamptz;
  v_left int;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT
    EXISTS (
      SELECT 1 FROM public.messages m
      JOIN public.relationships r ON r.id = m.relationship_id
      WHERE m.id = p_message_id
        AND (r.user_a = v_user_id OR r.user_b = v_user_id)
    ),
    (SELECT sender_id FROM public.messages WHERE id = p_message_id),
    (SELECT viewed_at FROM public.messages WHERE id = p_message_id)
  INTO v_is_member, v_sender, v_viewed_at;

  IF NOT v_is_member THEN
    -- Same response for "belongs to someone else" and "does not exist":
    -- a distinguishable error is a membership oracle.
    RAISE EXCEPTION 'Streak unavailable';
  END IF;

  IF v_sender = v_user_id THEN
    -- The sender, after the recipient has opened it, is done.
    IF v_viewed_at IS NOT NULL THEN
      RAISE EXCEPTION 'Streak already opened';
    END IF;

    -- Still in flight: replay freely, spending nothing and marking
    -- nothing. A sender replay must not look like the recipient opening
    -- it, or the read receipt lies.
    SELECT streak_views_remaining INTO v_left
    FROM public.messages WHERE id = p_message_id;
    RETURN v_left;
  END IF;

  -- Recipient. The window opens on the FIRST view.
  IF v_viewed_at IS NULL THEN
    UPDATE public.messages SET viewed_at = now() WHERE id = p_message_id;
    v_viewed_at := now();
  ELSIF v_viewed_at < now() - interval '30 minutes' THEN
    -- Expired by time even with plays left. Destroy it and report spent.
    PERFORM public.queue_media_deletion('message-media', media_url)
    FROM public.streak_clips WHERE message_id = p_message_id;

    DELETE FROM public.streak_clips WHERE message_id = p_message_id;
    UPDATE public.messages SET streak_views_remaining = 0
    WHERE id = p_message_id;
    RETURN 0;
  END IF;

  -- GREATEST floors at zero so a double-tap cannot drive it negative.
  UPDATE public.messages
     SET streak_views_remaining = GREATEST(streak_views_remaining - 1, 0)
   WHERE id = p_message_id
   RETURNING streak_views_remaining INTO v_left;

  IF v_left = 0 THEN
    PERFORM public.queue_media_deletion('message-media', media_url)
    FROM public.streak_clips WHERE message_id = p_message_id;

    DELETE FROM public.streak_clips WHERE message_id = p_message_id;
  END IF;

  RETURN v_left;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_streak_viewed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_streak_viewed(uuid) TO authenticated;

-- Marks a view-once video watched. Same defect, same fix: the storage
-- DELETE threw, so the follow-up UPDATE never ran and the whole function
-- rolled back — including the viewed_at write — leaving the video
-- viewable after being watched.
--
-- Otherwise character-for-character 20260816130000: the same guarded
-- UPDATE (active relationship, view-once, not yet viewed, media present),
-- the same RETURNING-into-NULL retry semantics, the same search_path.
-- Only the DELETE FROM storage.objects is replaced.
CREATE OR REPLACE FUNCTION public.mark_video_viewed(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_message public.messages%ROWTYPE;
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  UPDATE public.messages
  SET viewed_at = now()
  WHERE id = p_message_id
    AND is_view_once = true
    AND viewed_at IS NULL
    AND media_url IS NOT NULL
    AND relationship_id IN (
      SELECT id FROM public.relationships
      WHERE status = 'active' AND (user_a = v_user_id OR user_b = v_user_id)
    )
  RETURNING * INTO v_message;

  IF v_message.id IS NULL THEN
    -- Already viewed by an earlier call (the common, expected retry/race
    -- case), or the message doesn't exist / isn't view-once / the caller
    -- isn't a relationship member. No way to distinguish these without
    -- leaking existence to a non-member, and the caller doesn't need to —
    -- "not viewable anymore" is the only actionable outcome either way.
    RETURN;
  END IF;

  PERFORM public.queue_media_deletion('message-media', v_message.media_url);
  PERFORM public.queue_media_deletion(
    'message-media', v_message.media_thumbnail_url
  );

  UPDATE public.messages
  SET media_url = NULL, media_thumbnail_url = NULL
  WHERE id = p_message_id;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_video_viewed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_video_viewed(uuid) TO authenticated;
