-- Widen create_chat_media_upload_intent to issue intents for streaks.
--
-- This is the FOURTH place media_type is gated -- after messages'
-- CHECK, message_media_upload_intents' CHECK, and
-- validate_message_media_before_insert. Every streak send failed here,
-- before a file was even transcoded, and the client swallowed the error
-- so the console showed only video_compress's informational logs.
--
-- Streaks ride chat_ephemeral_video: same capture surface, same privacy
-- contract, so one flag disables both. Everything else in the body is
-- reproduced verbatim from the live definition.
CREATE OR REPLACE FUNCTION public.create_chat_media_upload_intent(
  p_relationship_id uuid,
  p_mime_type text,
  p_media_type text DEFAULT 'image'
)
RETURNS TABLE (
  intent_id uuid,
  storage_key text,
  expires_at timestamptz,
  bucket text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id uuid;
  v_relationship public.relationships%ROWTYPE;
  v_storage_key text;
  v_extension text;
  v_flag_key text;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_media_type NOT IN ('image', 'audio', 'video', 'streak') THEN
    RAISE EXCEPTION 'Unsupported chat media type';
  END IF;

  -- Server-authoritative flag gate (Spec 12.2) — one flag per media type,
  -- same enforcement shape as images/audio. Video additionally requires
  -- chat_image_sharing since every video send also requires a thumbnail
  -- intent through the image path — checked explicitly below rather than
  -- letting a partial failure surface as a confusing thumbnail-intent 403
  -- after the video intent already succeeded.
  v_flag_key := CASE p_media_type
    WHEN 'audio' THEN 'chat_voice_messages'
    WHEN 'video' THEN 'chat_video_sharing'
    -- Streaks ride the ephemeral-video flag: they are the same capture
    -- surface and the same privacy contract, so one switch turns both off.
    WHEN 'streak' THEN 'chat_ephemeral_video'
    ELSE 'chat_image_sharing'
  END;
  IF COALESCE(
    (SELECT enabled FROM public.feature_flags WHERE key = v_flag_key),
    false
  ) = false THEN
    RAISE EXCEPTION '% is unavailable', p_media_type;
  END IF;

  IF p_media_type = 'video' AND COALESCE(
    (SELECT enabled FROM public.feature_flags WHERE key = 'chat_image_sharing'),
    false
  ) = false THEN
    RAISE EXCEPTION 'video is unavailable';
  END IF;

  IF p_media_type = 'audio' THEN
    IF p_mime_type NOT IN ('audio/mp4', 'audio/m4a') THEN
      RAISE EXCEPTION 'Unsupported audio type';
    END IF;
  ELSIF p_media_type = 'streak' THEN
    -- Same container as video: streak clips come off the same camera and
    -- through the same transcoder.
    IF p_mime_type NOT IN ('video/mp4') THEN
      RAISE EXCEPTION 'Unsupported streak type';
    END IF;
  ELSIF p_media_type = 'video' THEN
    IF p_mime_type NOT IN ('video/mp4') THEN
      RAISE EXCEPTION 'Unsupported video type';
    END IF;
  ELSE
    IF p_mime_type NOT IN ('image/jpeg', 'image/png', 'image/webp') THEN
      RAISE EXCEPTION 'Unsupported image type';
    END IF;
  END IF;

  SELECT *
  INTO v_relationship
  FROM public.relationships
  WHERE id = p_relationship_id
    AND status = 'active'
    AND chat_archived_at IS NULL
    AND (user_a = v_user_id OR user_b = v_user_id);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relationship not available for chat media';
  END IF;

  v_extension := CASE p_mime_type
    WHEN 'image/png' THEN 'png'
    WHEN 'image/webp' THEN 'webp'
    WHEN 'audio/mp4' THEN 'm4a'
    WHEN 'audio/m4a' THEN 'm4a'
    WHEN 'video/mp4' THEN 'mp4'
    ELSE 'jpg'
  END;

  v_storage_key := 'chat-media/' || encode(gen_random_bytes(16), 'hex') || '.' || v_extension;

  INSERT INTO public.message_media_upload_intents (
    relationship_id,
    requester_id,
    storage_key,
    media_type,
    mime_type,
    expires_at
  )
  VALUES (
    p_relationship_id,
    v_user_id,
    v_storage_key,
    p_media_type,
    p_mime_type,
    now() + interval '15 minutes'
  )
  RETURNING
    message_media_upload_intents.id,
    message_media_upload_intents.storage_key,
    message_media_upload_intents.expires_at
  INTO intent_id, storage_key, expires_at;

  bucket := 'message-media';
  RETURN NEXT;
END;

$$;

REVOKE ALL ON FUNCTION public.create_chat_media_upload_intent(uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_chat_media_upload_intent(uuid, text, text)
  TO authenticated;
