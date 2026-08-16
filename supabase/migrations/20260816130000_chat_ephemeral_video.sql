-- supabase/migrations/20260816130000_chat_ephemeral_video.sql
--
-- Adds ephemeral (view-once) video capture on top of Part 1's video-sharing
-- pipeline (20260815130000_chat_video_messages.sql). Reuses media_type =
-- 'video' as-is — NO new media_type value, NO changes to
-- create_chat_media_upload_intent or validate_message_media_before_insert.
-- Every existing constraint/RPC/trigger check for media_type = 'video'
-- already applies unchanged to an ephemeral capture, since the only thing
-- that distinguishes one from a gallery-pick video is the new is_view_once
-- flag on the messages row — set only AFTER the upload-intent flow (which
-- this migration does not touch) has already completed successfully.
--
-- Confirmed directly against the live create_chat_media_upload_intent RPC
-- before writing this migration: it branches purely on p_media_type, with
-- no way to distinguish an ephemeral video intent from a gallery video
-- intent — both request media_type = 'video'. This means the CLIENT is
-- solely responsible for an additional chat_ephemeral_video flag gate
-- before even offering the capture UI (see chat_screen.dart wiring, a
-- later task in this feature's plan) — there is no corresponding
-- server-side flag branch to add here, because the RPC has no way to know
-- a given video intent request is "for an ephemeral capture" versus "for
-- a gallery pick." Both share the exact same chat_video_sharing AND
-- chat_image_sharing server-side gate Part 1 already established.

-- 1. Two new nullable/defaulted columns on messages. Both are safe no-ops
--    for every existing row (is_view_once defaults false, viewed_at stays
--    NULL) — no data migration needed.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS is_view_once boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS viewed_at timestamptz;

-- 2. Feature flag row, same convention as chat_video_sharing/
--    chat_voice_messages/chat_image_sharing — defaults off. This flag is
--    checked CLIENT-SIDE only (see comment above) — there is no
--    server-side branch for it, since the upload-intent RPC cannot
--    distinguish ephemeral from non-ephemeral video requests.
INSERT INTO public.feature_flags (key, enabled)
VALUES ('chat_ephemeral_video', false)
ON CONFLICT (key) DO NOTHING;

-- 3. mark_video_viewed: the one new piece of server logic this feature
--    needs. Atomic view-guard + Storage deletion + tombstone write, all in
--    one SECURITY DEFINER function so a client never needs direct DELETE
--    access to storage.objects or direct UPDATE access to media_url/
--    media_thumbnail_url on messages (both remain server-controlled).
--
--    Idempotency/atomicity (Algorithm Quality Review Checklist 1.1, 2.18,
--    [MUTATION] scope): the UPDATE ... WHERE viewed_at IS NULL guard below
--    is the entire safety mechanism. Two concurrent calls for the same
--    p_message_id — whether from the same device retrying after a network
--    failure, two devices open simultaneously, or sender-then-receiver
--    racing — can only ever have ONE of them find viewed_at still NULL and
--    proceed past the RETURNING clause; every other call's RETURNING
--    yields no row, v_message.id stays NULL, and the function returns
--    early with no side effects. This makes retries always safe: a client
--    that doesn't know whether its previous call actually landed
--    server-side can simply call again.
--
--    Deliberately does NOT distinguish sender from receiver — full
--    symmetry is the confirmed, intended design (see design spec Section
--    7.2's explicit confirmation): the sender's own complete view of their
--    sent clip counts as "viewed" and revokes it for the receiver too.
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

  DELETE FROM storage.objects
  WHERE bucket_id = 'message-media'
    AND name IN (v_message.media_url, v_message.media_thumbnail_url);

  UPDATE public.messages
  SET media_url = NULL, media_thumbnail_url = NULL
  WHERE id = p_message_id;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_video_viewed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_video_viewed(uuid) TO authenticated;
