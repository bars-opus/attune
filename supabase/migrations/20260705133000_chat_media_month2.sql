CREATE TABLE IF NOT EXISTS public.message_media_upload_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  requester_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  storage_key text NOT NULL UNIQUE,
  media_type text NOT NULL CHECK (media_type IN ('image')),
  mime_type text NOT NULL,
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_message_media_upload_intents_lookup
  ON public.message_media_upload_intents(requester_id, relationship_id, expires_at DESC);

ALTER TABLE public.message_media_upload_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.message_media_upload_intents FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_chat_media_upload_intent(
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
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_relationship public.relationships%ROWTYPE;
  v_storage_key text;
  v_extension text;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_mime_type NOT IN ('image/jpeg', 'image/png', 'image/webp') THEN
    RAISE EXCEPTION 'Unsupported image type';
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
    'image',
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

CREATE OR REPLACE FUNCTION public.validate_message_media_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_intent_id uuid;
BEGIN
  IF NEW.media_url IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.media_type IS DISTINCT FROM 'image' THEN
    RAISE EXCEPTION 'Unsupported chat media type';
  END IF;

  SELECT id
  INTO v_intent_id
  FROM public.message_media_upload_intents intent
  WHERE intent.storage_key = NEW.media_url
    AND intent.relationship_id = NEW.relationship_id
    AND intent.requester_id = NEW.sender_id
    AND intent.media_type = NEW.media_type
    AND intent.used_at IS NULL
    AND intent.expires_at > now();

  IF v_intent_id IS NULL THEN
    RAISE EXCEPTION 'Chat media upload intent is invalid or expired';
  END IF;

  UPDATE public.message_media_upload_intents
  SET used_at = now()
  WHERE id = v_intent_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_message_media_before_insert ON public.messages;
CREATE TRIGGER validate_message_media_before_insert
BEFORE INSERT ON public.messages
FOR EACH ROW
WHEN (NEW.media_url IS NOT NULL)
EXECUTE FUNCTION public.validate_message_media_before_insert();

INSERT INTO storage.buckets (id, name, public)
VALUES ('message-media', 'message-media', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS message_media_insert_by_intent ON storage.objects;
CREATE POLICY message_media_insert_by_intent
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'message-media'
  AND EXISTS (
    SELECT 1
    FROM public.message_media_upload_intents intent
    WHERE intent.storage_key = name
      AND intent.requester_id = auth.uid()
      AND intent.used_at IS NULL
      AND intent.expires_at > now()
  )
);

DROP POLICY IF EXISTS message_media_select_relationship_members ON storage.objects;
CREATE POLICY message_media_select_relationship_members
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'message-media'
  AND EXISTS (
    SELECT 1
    FROM public.messages m
    JOIN public.relationships r
      ON r.id = m.relationship_id
    WHERE m.media_url = name
      AND r.chat_archived_at IS NULL
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
  )
);

DROP POLICY IF EXISTS message_media_delete_owner_unused_intent ON storage.objects;
CREATE POLICY message_media_delete_owner_unused_intent
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'message-media'
  AND EXISTS (
    SELECT 1
    FROM public.message_media_upload_intents intent
    WHERE intent.storage_key = name
      AND intent.requester_id = auth.uid()
      AND intent.used_at IS NULL
  )
);

REVOKE ALL ON FUNCTION public.create_chat_media_upload_intent(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_chat_media_upload_intent(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_chat_media_upload_intent(uuid, text) TO authenticated;
