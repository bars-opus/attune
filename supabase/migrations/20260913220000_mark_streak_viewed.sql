-- Spends one view of a streak, returning what remains.
--
-- Deliberately NOT mark_video_viewed: that function deletes the storage
-- object on first view, which is correct for strict view-once and fatal
-- for a replay budget. This deletes only when the budget reaches zero, so
-- a replayable streak outlives a view-once one on the server. That is a
-- real privacy difference, and the reason replays are opt-in and capped.
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
    (SELECT sender_id FROM public.messages WHERE id = p_message_id)
  INTO v_is_member, v_sender;

  IF NOT v_is_member THEN
    -- Same response for "belongs to someone else" and "does not exist":
    -- a distinguishable error is a membership oracle.
    RAISE EXCEPTION 'Streak unavailable';
  END IF;

  -- The sender re-opening their own streak must not spend the recipient's
  -- budget: the whole point of the budget is what the RECIPIENT has left.
  IF v_sender = v_user_id THEN
    SELECT streak_views_remaining INTO v_left
    FROM public.messages WHERE id = p_message_id;
    RETURN v_left;
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
