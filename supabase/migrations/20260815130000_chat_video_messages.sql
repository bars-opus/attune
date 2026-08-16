-- supabase/migrations/20260815130000_chat_video_messages.sql
--
-- Extends the existing image/voice media pipeline (bucket, upload-intent
-- RPC, insert-validation trigger, server-authoritative flag enforcement) to
-- also accept video messages (media_type = 'video'), per
-- docs/superpowers/specs/2026-08-15-video-sharing-design.md. No new bucket,
-- no new RLS policies — the existing intent-ownership and
-- relationship-membership policies already cover any media type stored
-- under an intent-issued key.
--
-- messages.media_type's own CHECK constraint ALREADY permits 'video' —
-- it was in the original schema (20260705120000_chat_system_v1_2.sql) and
-- the voice migration's rewrite of that constraint
-- (20260815120000_chat_voice_messages.sql:38-39) preserved it. Verified
-- directly against the live migration before writing this file. No change
-- to that constraint here.
--
-- Deliberately does NOT touch enqueue_chat_media_processing/its trigger —
-- that trigger's WHEN clause already reads `AND NEW.media_type = 'image'`,
-- so video inserts correctly skip the image-thumbnail processing outbox
-- with zero changes needed, exactly as audio already does. Video's
-- thumbnail is generated and uploaded client-side, synchronously with the
-- send — there is no server-side processing step for it.
--
-- create_chat_media_upload_intent already has the 3-argument signature
-- (p_relationship_id uuid, p_mime_type text, p_media_type text DEFAULT
-- 'image') from the voice migration. This migration's CREATE OR REPLACE
-- keeps that exact same signature — no arity change, so unlike the voice
-- migration (which had to DROP the old 2-arg overload before creating a
-- 3-arg one, to avoid two coexisting overloads), no DROP statement is
-- needed or added here.

-- 1. Widen the upload-intents table's media_type CHECK constraint.
ALTER TABLE public.message_media_upload_intents
  DROP CONSTRAINT IF EXISTS message_media_upload_intents_media_type_check;
ALTER TABLE public.message_media_upload_intents
  ADD CONSTRAINT message_media_upload_intents_media_type_check
  CHECK (media_type IN ('image', 'audio', 'video'));

-- 2. Feature flag row, same convention as chat_image_sharing/chat_voice_messages.
INSERT INTO public.feature_flags (key, enabled)
VALUES ('chat_video_sharing', false)
ON CONFLICT (key) DO NOTHING;

-- 3. Widen create_chat_media_upload_intent: accept 'video', widen the MIME
--    allowlist for it to video/mp4 ONLY (the client always transcodes to
--    mp4 before requesting an intent — accepting video/quicktime here
--    would let a hostile client skip compression), add the mp4 extension
--    case, and require BOTH chat_video_sharing AND chat_image_sharing for
--    a video intent (every video send also needs a thumbnail intent
--    through the ordinary image path, so this turns a confusing partial
--    failure into one clear upfront rejection).
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
SET search_path = public
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

  IF p_media_type NOT IN ('image', 'audio', 'video') THEN
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

REVOKE ALL ON FUNCTION public.create_chat_media_upload_intent(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_chat_media_upload_intent(uuid, text, text) TO authenticated;

-- 4. Widen validate_message_media_before_insert: accept 'video', add a
--    type-aware size ceiling (25MB for video), and add NEW logic (not a
--    widened allowlist — this doesn't exist in any form today) validating
--    NEW.media_thumbnail_url against its own consumed intent when present.
--    media_thumbnail_url was always server-written by an async worker for
--    every other media type, so nothing previously needed to validate it —
--    video is the first type where a client writes this field directly,
--    and without this check a client could point the thumbnail at an
--    arbitrary object in the bucket.
CREATE OR REPLACE FUNCTION public.validate_message_media_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_intent public.message_media_upload_intents%ROWTYPE;
  v_object storage.objects%ROWTYPE;
  v_size bigint;
  v_mime text;
  v_max_size bigint;
  v_thumb_intent public.message_media_upload_intents%ROWTYPE;
  v_thumb_object storage.objects%ROWTYPE;
  v_thumb_size bigint;
  v_thumb_mime text;
BEGIN
  IF NEW.media_url IS NULL THEN RETURN NEW; END IF;
  IF NEW.media_type NOT IN ('image', 'audio', 'video') THEN
    RAISE EXCEPTION 'Unsupported chat media type';
  END IF;

  SELECT * INTO v_intent
  FROM public.message_media_upload_intents intent
  WHERE intent.storage_key = NEW.media_url
    AND intent.relationship_id = NEW.relationship_id
    AND intent.requester_id = NEW.sender_id
    AND intent.media_type = NEW.media_type
    AND intent.used_at IS NULL
    AND intent.expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Chat media upload intent is invalid or expired'; END IF;

  SELECT * INTO v_object FROM storage.objects o
  WHERE o.bucket_id = 'message-media' AND o.name = NEW.media_url;
  IF NOT FOUND THEN RAISE EXCEPTION 'Chat media object is missing'; END IF;
  v_size := COALESCE((v_object.metadata->>'size')::bigint, 0);
  v_mime := COALESCE(v_object.metadata->>'mimetype', v_object.metadata->>'contentType');

  v_max_size := CASE NEW.media_type
    WHEN 'audio' THEN 1258291   -- ~1.2MB
    WHEN 'video' THEN 26214400  -- 25MB
    ELSE 819200                 -- 800KB, unchanged image ceiling
  END;

  IF v_size <= 0 OR v_size > v_max_size OR v_mime IS DISTINCT FROM v_intent.mime_type THEN
    RAISE EXCEPTION 'Chat media object failed validation';
  END IF;

  UPDATE public.message_media_upload_intents SET used_at = now() WHERE id = v_intent.id;

  -- Video-only: the client writes media_thumbnail_url directly (no async
  -- worker involved), so it must be independently validated against its
  -- own consumed intent, the same way the main object is above.
  IF NEW.media_type = 'video' AND NEW.media_thumbnail_url IS NOT NULL THEN
    SELECT * INTO v_thumb_intent
    FROM public.message_media_upload_intents intent
    WHERE intent.storage_key = NEW.media_thumbnail_url
      AND intent.relationship_id = NEW.relationship_id
      AND intent.requester_id = NEW.sender_id
      AND intent.media_type = 'image'
      AND intent.used_at IS NULL
      AND intent.expires_at > now()
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Chat media thumbnail upload intent is invalid or expired';
    END IF;

    SELECT * INTO v_thumb_object FROM storage.objects o
    WHERE o.bucket_id = 'message-media' AND o.name = NEW.media_thumbnail_url;
    IF NOT FOUND THEN RAISE EXCEPTION 'Chat media thumbnail object is missing'; END IF;
    v_thumb_size := COALESCE((v_thumb_object.metadata->>'size')::bigint, 0);
    v_thumb_mime := COALESCE(v_thumb_object.metadata->>'mimetype', v_thumb_object.metadata->>'contentType');

    IF v_thumb_size <= 0 OR v_thumb_size > 819200 OR v_thumb_mime IS DISTINCT FROM v_thumb_intent.mime_type THEN
      RAISE EXCEPTION 'Chat media thumbnail object failed validation';
    END IF;

    UPDATE public.message_media_upload_intents SET used_at = now() WHERE id = v_thumb_intent.id;
  END IF;

  RETURN NEW;
END;
$$;
