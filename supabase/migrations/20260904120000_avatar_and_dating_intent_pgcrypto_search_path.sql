-- supabase/migrations/20260904120000_avatar_and_dating_intent_pgcrypto_search_path.sql
--
-- Fixes: changing the couple's chat photo fails with
-- `PostgrestException: function gen_random_bytes(integer) does not exist,
-- code: 42883` (confirmed live, at the create-intent stage, with a valid
-- image/jpeg of 47078 bytes — so neither the MIME allowlist nor the 800KB
-- cap was involved).
--
-- Root cause: identical to the bug already fixed once for chat media in
-- 20260903120000_chat_media_upload_intent_pgcrypto_search_path.sql (and
-- before that for forums/opinions in
-- 20260716140000_forums_opinions_anonymity_hardening.sql): on this Supabase
-- project pgcrypto lives in the `extensions` schema, not `public`. A
-- SECURITY DEFINER function declaring `SET search_path = public` therefore
-- cannot resolve a bare `gen_random_bytes(16)` call.
--
-- That earlier migration's own NOTE named these two functions explicitly as
-- carrying the same latent bug, deferred because their features were not
-- being exercised at the time:
--   - public.create_relationship_avatar_upload_intent
--     (20260826130000_relationship_chat_identity.sql)
--   - public.create_dating_photo_upload_intent
--     (20260813130000_dating_photo_pipeline.sql)
--
-- The avatar one is now being exercised and is broken in production. Both
-- are fixed here rather than only the one currently reported: they are the
-- same one-line change to the same bug class, and leaving the dating one
-- armed would just defer an identical debugging session to whenever dating
-- photo upload is next touched. Neither has ever worked, so neither fix can
-- regress previously-working behaviour.
--
-- Fix: add `extensions` to each function's search_path. Both function
-- bodies are otherwise reproduced verbatim from their current live
-- definitions — this migration widens SET search_path and changes nothing
-- else.

-- === 1. Relationship chat avatar upload intent ===
-- Body verbatim from 20260826130000_relationship_chat_identity.sql.
CREATE OR REPLACE FUNCTION public.create_relationship_avatar_upload_intent(
  p_relationship_id uuid,
  p_mime_type text
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
  v_extension text;
  v_storage_key text;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_mime_type NOT IN ('image/jpeg', 'image/png', 'image/webp') THEN
    RAISE EXCEPTION 'Unsupported image type';
  END IF;

  -- Checklist 1.4: authorization at the resource-access point, not just
  -- entry — only an active relationship's own member may request an
  -- intent for it.
  SELECT * INTO v_relationship
  FROM public.relationships
  WHERE id = p_relationship_id
    AND status = 'active'
    AND (user_a = v_user_id OR user_b = v_user_id);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relationship not available for chat avatar upload';
  END IF;

  v_extension := CASE p_mime_type
    WHEN 'image/png' THEN 'png'
    WHEN 'image/webp' THEN 'webp'
    ELSE 'jpg'
  END;

  v_storage_key := 'relationship-avatars/' || p_relationship_id || '/' ||
    encode(gen_random_bytes(16), 'hex') || '.' || v_extension;

  INSERT INTO public.relationship_avatar_upload_intents (
    relationship_id, requester_id, storage_key, mime_type, expires_at
  ) VALUES (
    p_relationship_id, v_user_id, v_storage_key, p_mime_type, now() + interval '15 minutes'
  )
  RETURNING relationship_avatar_upload_intents.id,
            relationship_avatar_upload_intents.storage_key,
            relationship_avatar_upload_intents.expires_at
  INTO intent_id, storage_key, expires_at;

  bucket := 'relationship-avatars';
  RETURN NEXT;
END;
$$;

-- === 2. Dating photo upload intent ===
-- Body verbatim from 20260813130000_dating_photo_pipeline.sql.
CREATE OR REPLACE FUNCTION public.create_dating_photo_upload_intent(
  p_mime_type text
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
  v_extension text;
  v_storage_key text;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_mime_type NOT IN ('image/jpeg', 'image/png', 'image/webp') THEN
    RAISE EXCEPTION 'Unsupported image type';
  END IF;

  v_extension := CASE p_mime_type
    WHEN 'image/png' THEN 'png'
    WHEN 'image/webp' THEN 'webp'
    ELSE 'jpg'
  END;

  v_storage_key := 'dating-photos/' || encode(gen_random_bytes(16), 'hex') || '.' || v_extension;

  INSERT INTO public.dating_photo_upload_intents (
    user_id, storage_key, mime_type, expires_at
  ) VALUES (
    v_user_id, v_storage_key, p_mime_type, now() + interval '15 minutes'
  )
  RETURNING dating_photo_upload_intents.id, dating_photo_upload_intents.storage_key,
            dating_photo_upload_intents.expires_at
  INTO intent_id, storage_key, expires_at;

  bucket := 'dating-profile-photos';
  RETURN NEXT;
END;
$$;

-- CREATE OR REPLACE preserves existing privileges, so the GRANT EXECUTE
-- statements from each function's original migration still stand. Re-stated
-- here only as a guard against a future environment where the function is
-- created fresh from this file rather than replaced.
GRANT EXECUTE ON FUNCTION public.create_relationship_avatar_upload_intent(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_dating_photo_upload_intent(text) TO authenticated;
