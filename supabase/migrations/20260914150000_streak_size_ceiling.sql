-- Raise the streak clip ceiling from 12MB to 25MB.
--
-- A streak is up to 60 seconds of 720p with audio. Measured output runs
-- around 190KB/s, so a full-length clip lands near 11MB -- and busier
-- footage (motion, detail, poor light) goes well past it. The 12MB
-- ceiling therefore passed every short test clip and failed real
-- one-minute streaks, which is exactly the reported shape: short ones
-- send, longer ones do not.
--
-- 25MB matches the video ceiling already in this same CASE, so a streak
-- clip is no more permissive than an ordinary video of the same length.
-- Everything else is reproduced verbatim from the live definition.
CREATE OR REPLACE FUNCTION public.validate_message_media_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
  IF NEW.media_type NOT IN ('image', 'audio', 'video', 'streak') THEN
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
    -- A streak segment is up to 60s of 720p with audio. The parent row
    -- carries only the FIRST clip, so this is a per-clip ceiling, not a
    -- whole-streak one.
    WHEN 'streak' THEN 26214400 -- 25MB, same as video
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
