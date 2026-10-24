-- supabase/migrations/20261024100110_story_intent_hardening.sql
--
-- Stories Wave 5:
--   * 01 #18: the two abuse limits count and then insert, so two calls at
--     once could both pass. A per-person transaction lock now serializes
--     them. It is taken after input validation and before the membership
--     check, keyed on the caller only, so it says nothing about any
--     relationship.
--   * Wave 2 final review I2: a video on a slow link could not finish inside
--     a 15-minute intent. Video media intents and every thumbnail intent now
--     last 60 minutes; image media keeps 15. A thumbnail intent cannot say it
--     belongs to a video (thumbnail + 'video' stays INVALID_INPUT), and the
--     client judges a pair by its sooner expiry, so image pairs are unchanged.
--   * search_path pinned to '' (house rule); every name schema-qualified.
-- Otherwise identical to 20260938040000. CREATE OR REPLACE keeps the grants;
-- they are re-stated.
CREATE OR REPLACE FUNCTION public.create_story_upload_intent(
  p_relationship_id uuid,
  p_object_kind text,
  p_media_type text,
  p_mime_type text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_storage_key text;
  v_max_bytes bigint;
  v_open_intents int;
  v_recent_calls int;
  v_intent_id uuid;
  v_expires_at timestamptz;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.story_intent_error('UNAUTHORIZED');
  END IF;

  IF p_relationship_id IS NULL OR p_object_kind IS NULL OR p_media_type IS NULL
     OR p_mime_type IS NULL
     OR p_object_kind NOT IN ('media', 'thumbnail')
     OR p_media_type NOT IN ('image', 'video')
  THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;

  IF p_object_kind = 'thumbnail' THEN
    IF p_media_type <> 'image' OR p_mime_type <> 'image/jpeg' THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
  ELSE
    IF p_media_type = 'image' AND p_mime_type <> 'image/jpeg' THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
    IF p_media_type = 'video' AND p_mime_type <> 'video/mp4' THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
  END IF;

  v_max_bytes := public.story_intent_max_bytes(p_object_kind, p_media_type);
  IF v_max_bytes IS NULL THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;

  -- 01 #18: one call per person at a time from here to commit.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('story_intent:' || v_user::text));

  IF NOT public.story_relationship_is_open(p_relationship_id, v_user) THEN
    RETURN public.story_intent_error('FORBIDDEN');
  END IF;

  IF COALESCE(
    (SELECT f.enabled FROM public.feature_flags f WHERE f.key = 'stories'),
    false
  ) = false THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  SELECT count(*) INTO v_open_intents
    FROM public.story_media_upload_intents i
   WHERE i.requester_id = v_user
     AND i.used_at IS NULL
     AND i.expires_at > now();
  IF v_open_intents >= 20 THEN
    RETURN public.story_intent_error('RATE_LIMITED');
  END IF;

  SELECT count(*) INTO v_recent_calls
    FROM public.story_media_upload_intents i
   WHERE i.requester_id = v_user
     AND i.created_at > now() - interval '1 hour';
  IF v_recent_calls >= 120 THEN
    RETURN public.story_intent_error('RATE_LIMITED');
  END IF;

  v_storage_key := 'story-media/' || p_relationship_id::text || '/'
    || v_user::text || '/' || encode(extensions.gen_random_bytes(16), 'hex')
    || '-' || p_object_kind;
  v_expires_at := now() + CASE
    WHEN p_object_kind = 'media' AND p_media_type = 'image' THEN interval '15 minutes'
    ELSE interval '60 minutes'
  END;

  INSERT INTO public.story_media_upload_intents (
    relationship_id, requester_id, object_kind, media_type, mime_type,
    storage_key, max_bytes, expires_at
  ) VALUES (
    p_relationship_id, v_user, p_object_kind, p_media_type, p_mime_type,
    v_storage_key, v_max_bytes, v_expires_at
  ) RETURNING id INTO v_intent_id;

  RETURN jsonb_build_object(
    'intent_id', v_intent_id,
    'storage_key', v_storage_key,
    'bucket', 'story-media',
    'expires_at', v_expires_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_story_upload_intent(uuid, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_story_upload_intent(uuid, text, text, text)
  TO authenticated;
