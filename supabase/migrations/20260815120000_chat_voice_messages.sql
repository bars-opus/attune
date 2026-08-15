-- supabase/migrations/20260815120000_chat_voice_messages.sql
--
-- Extends the existing image-sharing media pipeline (bucket, upload-intent
-- RPC, insert-validation trigger, server-authoritative flag enforcement) to
-- also accept voice messages (media_type = 'audio'), per
-- docs/superpowers/specs/2026-08-15-voice-messages-design.md. No new bucket,
-- no new RLS policies — the existing intent-ownership and
-- relationship-membership policies already cover any media type stored
-- under an intent-issued key.
--
-- Deliberately does NOT touch enqueue_chat_media_processing/its trigger
-- (20260705200000_chat_media_hardening.sql) — that trigger's WHEN clause
-- already reads `AND NEW.media_type = 'image'`, so audio inserts correctly
-- skip the image-thumbnail processing outbox with zero changes needed.
-- Voice messages have no server-side processing step (spec: "waveform is
-- captured client-side at record time and never recomputed").

-- 1. New columns on messages, both nullable so existing image/text rows are
--    completely unaffected.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS media_duration_ms integer,
  ADD COLUMN IF NOT EXISTS media_waveform jsonb;

-- 1b. The messages table has its own inline column-level CHECK on
--     media_type, separate from the upload-intents table's constraint below
--     and not mentioned in the task brief's four call-outs:
--     `media_type text CHECK (media_type IN ('image', 'video'))`
--     (supabase/migrations/20260705120000_chat_system_v1_2.sql:48, unnamed,
--     so Postgres auto-named it messages_media_type_check). Without widening
--     this too, any INSERT with media_type = 'audio' fails here before the
--     validate_message_media_before_insert trigger even runs, so voice
--     messages would be completely non-functional regardless of the other
--     four fixes. Widen it the same drop-and-recreate way, preserving the
--     existing 'video' value since it's already in use.
ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_media_type_check;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_media_type_check
  CHECK (media_type IN ('image', 'video', 'audio'));

-- 2. Widen the upload-intents table's media_type CHECK constraint. A CHECK
--    constraint can't be altered in place — drop and recreate under the
--    same auto-generated-or-named constraint. Postgres names an inline
--    column CHECK automatically as <table>_<column>_check unless named
--    explicitly; the original migration didn't name it, so use that
--    convention here.
ALTER TABLE public.message_media_upload_intents
  DROP CONSTRAINT IF EXISTS message_media_upload_intents_media_type_check;
ALTER TABLE public.message_media_upload_intents
  ADD CONSTRAINT message_media_upload_intents_media_type_check
  CHECK (media_type IN ('image', 'audio'));

-- 3. Feature flag row, same convention as chat_image_sharing — defaults off.
INSERT INTO public.feature_flags (key, enabled)
VALUES ('chat_voice_messages', false)
ON CONFLICT (key) DO NOTHING;

-- 4. Widen create_chat_media_upload_intent: accept a new p_media_type
--    parameter (defaulted to 'image' so any caller not yet updated keeps
--    working), widen the MIME allowlist to accept audio/mp4 and audio/m4a,
--    branch the flag check and the storage-key extension on p_media_type,
--    and enforce a media-type-aware size expectation is NOT done here (size
--    is enforced by the storage object re-validation in
--    validate_message_media_before_insert below, not at intent-creation
--    time — intent creation has no file to measure yet).
-- The old two-argument signature is superseded — drop it BEFORE creating the
-- new three-argument signature below. PostgreSQL treats different-arity
-- functions as distinct overloads, so CREATE OR REPLACE on the new
-- 3-argument signature would NOT replace this old 2-argument one; dropping
-- it first avoids ever having two overloads (one with stale hard-coded
-- 'image' behavior) coexist, even momentarily.
DROP FUNCTION IF EXISTS public.create_chat_media_upload_intent(uuid, text);

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

  IF p_media_type NOT IN ('image', 'audio') THEN
    RAISE EXCEPTION 'Unsupported chat media type';
  END IF;

  -- Server-authoritative flag gate (Spec 12.2) — one flag per media type,
  -- same enforcement shape as images: a stale or hostile client cannot
  -- bypass this by skipping the UI gate.
  v_flag_key := CASE p_media_type
    WHEN 'audio' THEN 'chat_voice_messages'
    ELSE 'chat_image_sharing'
  END;
  IF COALESCE(
    (SELECT enabled FROM public.feature_flags WHERE key = v_flag_key),
    false
  ) = false THEN
    RAISE EXCEPTION '% is unavailable', p_media_type;
  END IF;

  IF p_media_type = 'audio' THEN
    IF p_mime_type NOT IN ('audio/mp4', 'audio/m4a') THEN
      RAISE EXCEPTION 'Unsupported audio type';
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

-- 5. Widen validate_message_media_before_insert: accept 'audio' as well as
--    'image', and make the post-upload size ceiling type-aware — audio's
--    target is ~1.2MB (1258291 bytes = 1.2 * 1024 * 1024, rounded), image's
--    stays at 819200 (800KB, unchanged).
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
BEGIN
  IF NEW.media_url IS NULL THEN RETURN NEW; END IF;
  IF NEW.media_type NOT IN ('image', 'audio') THEN
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
    WHEN 'audio' THEN 1258291  -- ~1.2MB
    ELSE 819200                -- 800KB, unchanged image ceiling
  END;

  IF v_size <= 0 OR v_size > v_max_size OR v_mime IS DISTINCT FROM v_intent.mime_type THEN
    RAISE EXCEPTION 'Chat media object failed validation';
  END IF;

  UPDATE public.message_media_upload_intents SET used_at = now() WHERE id = v_intent.id;
  RETURN NEW;
END;
$$;
