-- The streak viewing rules, in one place.
--
--   SENDER, before the recipient opens it: unlimited replays. The streak
--     is still in flight and re-watching what you sent costs nothing.
--   SENDER, after: permanently locked out. This is also the sender's read
--     receipt -- "Opened" is the only signal they get.
--   RECIPIENT: one play, or three within 30 MINUTES of first opening when
--     the sender allowed replays.
--
-- The window and the budget both bound retention, whichever comes first.
-- A budget alone would let a streak sit on the server for days if the
-- recipient simply stopped after one play; a window alone would make
-- "3 times" meaningless.
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
    DELETE FROM storage.objects
    WHERE bucket_id = 'message-media'
      AND name IN (
        SELECT media_url FROM public.streak_clips WHERE message_id = p_message_id
      );
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
    DELETE FROM storage.objects
    WHERE bucket_id = 'message-media'
      AND name IN (
        SELECT media_url FROM public.streak_clips WHERE message_id = p_message_id
      );
    DELETE FROM public.streak_clips WHERE message_id = p_message_id;
  END IF;

  RETURN v_left;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_streak_viewed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_streak_viewed(uuid) TO authenticated;
