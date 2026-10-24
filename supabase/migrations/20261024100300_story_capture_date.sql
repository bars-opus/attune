-- supabase/migrations/20261024100300_story_capture_date.sql
--
-- Stories Wave 5 (review 04 #3, #13):
--   * occurred_on was the poster's date at FINALIZE; an offline or slow post
--     near midnight landed on the next day. The client now sends the capture
--     instant (p_captured_at). It is clamped to the last 7 days and never the
--     future, so a client cannot back-date a story into the distant past.
--   * The phone's clock can be wrong (set by hand, reset by a dead battery),
--     so the client also sends its clock at finalize (p_client_now). The
--     capture's AGE on the phone's own clock (p_client_now - p_captured_at)
--     is applied to the server's now(): a constant clock error cancels out.
--     A client without p_client_now gets its capture instant as sent.
--   * The date never precedes the relationship's start
--     (coalesce(invite_accepted_at, created_at)).
--     created_at / expires_at stay at posting: the reel still gets 24 hours
--     (story_expires_in_24h pins expires_at = created_at + 24h).
--   * The date math no longer depends on the session TimeZone:
--     (timestamptz AT TIME ZONE 'UTC') + offset, then ::date.
--   * The wrapper and core move to search_path = ''.
-- The 9-argument wrapper and 8-argument core are DROPPED, not overloaded,
-- so PostgREST never sees two candidates (PGRST203); an old client's call
-- without p_captured_at / p_client_now still resolves to the new one
-- (DEFAULT NULL). The 10-argument wrapper and 9-argument core of this
-- file's first draft (applied only to local databases) are dropped too.
-- Body otherwise identical to 20260938120000 (core) and 20261017100000
-- (wrapper). One transaction: there is never a moment without a finalize.
BEGIN;

DROP FUNCTION IF EXISTS public.create_story_item(uuid, uuid, uuid, uuid, int, int, int, int, jsonb);
DROP FUNCTION IF EXISTS public.create_story_item_core(uuid, uuid, uuid, uuid, int, int, int, int);
DROP FUNCTION IF EXISTS public.create_story_item(uuid, uuid, uuid, uuid, int, int, int, int, jsonb, timestamptz);
DROP FUNCTION IF EXISTS public.create_story_item_core(uuid, uuid, uuid, uuid, int, int, int, int, timestamptz);

CREATE OR REPLACE FUNCTION public.create_story_item_core(
  p_relationship_id     uuid,
  p_client_story_id     uuid,
  p_media_intent_id     uuid,
  p_thumbnail_intent_id uuid,
  p_media_width         int,
  p_media_height        int,
  p_duration_ms         int,
  p_utc_offset_minutes  int,
  p_captured_at         timestamptz,
  p_client_now          timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user          uuid := auth.uid();
  v_existing_id   uuid;
  v_media_intent  public.story_media_upload_intents%ROWTYPE;
  v_thumb_intent  public.story_media_upload_intents%ROWTYPE;
  v_media_object  storage.objects%ROWTYPE;
  v_thumb_object  storage.objects%ROWTYPE;
  v_media_size    bigint;
  v_media_mime    text;
  v_thumb_size    bigint;
  v_thumb_mime    text;
  v_offset        int;
  v_now           timestamptz;
  v_captured      timestamptz;
  v_floor         timestamptz;
  v_occurred_on   date;
  v_story_id      uuid;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.story_intent_error('UNAUTHORIZED');
  END IF;

  IF p_relationship_id IS NULL
     OR p_client_story_id IS NULL
     OR p_media_intent_id IS NULL
     OR p_thumbnail_intent_id IS NULL
     OR p_media_width IS NULL OR p_media_width <= 0
     OR p_media_height IS NULL OR p_media_height <= 0
  THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;

  -- Idempotency first (sequential replay).
  SELECT si.id INTO v_existing_id
    FROM public.story_items si
   WHERE si.author_id = v_user
     AND si.client_story_id = p_client_story_id;
  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object('story_id', v_existing_id, 'existing', true);
  END IF;

  IF NOT public.story_relationship_is_open(p_relationship_id, v_user) THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  -- Lock both intents before validating them; a consumed intent re-checks
  -- idempotency (the 20260938120000 race fix).
  SELECT * INTO v_media_intent
    FROM public.story_media_upload_intents i
   WHERE i.id = p_media_intent_id
   FOR UPDATE;
  IF v_media_intent.id IS NULL
     OR v_media_intent.requester_id IS DISTINCT FROM v_user
     OR v_media_intent.relationship_id IS DISTINCT FROM p_relationship_id
     OR v_media_intent.object_kind IS DISTINCT FROM 'media'
     OR v_media_intent.used_at IS NOT NULL
     OR v_media_intent.expires_at <= now()
  THEN
    IF v_media_intent.used_at IS NOT NULL THEN
      SELECT si.id INTO v_existing_id
        FROM public.story_items si
       WHERE si.author_id = v_user AND si.client_story_id = p_client_story_id;
      IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object('story_id', v_existing_id, 'existing', true);
      END IF;
    END IF;
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  SELECT * INTO v_thumb_intent
    FROM public.story_media_upload_intents i
   WHERE i.id = p_thumbnail_intent_id
   FOR UPDATE;
  IF v_thumb_intent.id IS NULL
     OR v_thumb_intent.requester_id IS DISTINCT FROM v_user
     OR v_thumb_intent.relationship_id IS DISTINCT FROM p_relationship_id
     OR v_thumb_intent.object_kind IS DISTINCT FROM 'thumbnail'
     OR v_thumb_intent.used_at IS NOT NULL
     OR v_thumb_intent.expires_at <= now()
  THEN
    IF v_thumb_intent.used_at IS NOT NULL THEN
      SELECT si.id INTO v_existing_id
        FROM public.story_items si
       WHERE si.author_id = v_user AND si.client_story_id = p_client_story_id;
      IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object('story_id', v_existing_id, 'existing', true);
      END IF;
    END IF;
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  IF v_media_intent.media_type = 'video' THEN
    IF p_duration_ms IS NULL OR p_duration_ms < 500 OR p_duration_ms > 60000 THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
  ELSE
    IF p_duration_ms IS NOT NULL THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
  END IF;

  SELECT * INTO v_media_object
    FROM storage.objects o
   WHERE o.bucket_id = 'story-media' AND o.name = v_media_intent.storage_key;
  IF v_media_object.id IS NULL THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;
  v_media_size := COALESCE((v_media_object.metadata->>'size')::bigint, 0);
  v_media_mime := COALESCE(v_media_object.metadata->>'mimetype',
                           v_media_object.metadata->>'contentType');
  IF v_media_size <= 0
     OR v_media_size > v_media_intent.max_bytes
     OR v_media_mime IS DISTINCT FROM v_media_intent.mime_type
  THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  SELECT * INTO v_thumb_object
    FROM storage.objects o
   WHERE o.bucket_id = 'story-media' AND o.name = v_thumb_intent.storage_key;
  IF v_thumb_object.id IS NULL THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;
  v_thumb_size := COALESCE((v_thumb_object.metadata->>'size')::bigint, 0);
  v_thumb_mime := COALESCE(v_thumb_object.metadata->>'mimetype',
                           v_thumb_object.metadata->>'contentType');
  IF v_thumb_size <= 0
     OR v_thumb_size > v_thumb_intent.max_bytes
     OR v_thumb_mime IS DISTINCT FROM v_thumb_intent.mime_type
  THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  -- One captured now() for created_at and expires_at (posting). The date is
  -- the capture's, clamped to [max(now - 7 days, relationship start), now],
  -- at the device offset (clamped to [-840, 840]), with no session time
  -- zone involved.
  v_offset := greatest(-840, least(840, coalesce(p_utc_offset_minutes, 0)));
  v_now := now();
  IF p_captured_at IS NULL THEN
    v_captured := v_now;
  ELSIF p_client_now IS NULL THEN
    v_captured := p_captured_at;  -- a client that does not send its clock
  ELSE
    -- The capture's age on the phone's own clock, bounded to [0, 7 days]
    -- BEFORE any arithmetic on now(), applied to the server's clock.
    BEGIN
      v_captured := v_now - least(interval '7 days',
                                  greatest(interval '0', p_client_now - p_captured_at));
    EXCEPTION WHEN datetime_field_overflow THEN
      v_captured := v_now;  -- infinite or out-of-range clocks: posting time
    END;
  END IF;
  SELECT coalesce(r.invite_accepted_at, r.created_at) INTO v_floor
    FROM public.relationships r
   WHERE r.id = p_relationship_id;
  v_captured := least(v_now, greatest(v_now - interval '7 days',
                                      coalesce(v_floor, v_now - interval '7 days'),
                                      v_captured));
  v_occurred_on := ((v_captured AT TIME ZONE 'UTC') + make_interval(mins => v_offset))::date;

  INSERT INTO public.story_items (
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height, duration_ms,
    occurred_on, created_at, expires_at
  ) VALUES (
    p_client_story_id, p_relationship_id, v_user, v_media_intent.media_type,
    v_media_intent.storage_key, v_thumb_intent.storage_key,
    p_media_width, p_media_height, p_duration_ms,
    v_occurred_on, v_now, v_now + interval '24 hours'
  )
  ON CONFLICT (author_id, client_story_id) DO NOTHING
  RETURNING id INTO v_story_id;

  IF v_story_id IS NULL THEN
    SELECT si.id INTO v_story_id
      FROM public.story_items si
     WHERE si.author_id = v_user AND si.client_story_id = p_client_story_id;
    RETURN jsonb_build_object('story_id', v_story_id, 'existing', true);
  END IF;

  UPDATE public.story_media_upload_intents SET used_at = v_now WHERE id = v_media_intent.id;
  UPDATE public.story_media_upload_intents SET used_at = v_now WHERE id = v_thumb_intent.id;

  PERFORM public.bump_story_signal(p_relationship_id);

  RETURN jsonb_build_object('story_id', v_story_id, 'existing', false);
END;
$$;

REVOKE ALL ON FUNCTION public.create_story_item_core(uuid, uuid, uuid, uuid, int, int, int, int, timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_story_item(
  p_relationship_id     uuid,
  p_client_story_id     uuid,
  p_media_intent_id     uuid,
  p_thumbnail_intent_id uuid,
  p_media_width         int,
  p_media_height        int,
  p_duration_ms         int,
  p_utc_offset_minutes  int,
  p_place               jsonb DEFAULT NULL,
  p_captured_at         timestamptz DEFAULT NULL,
  p_client_now          timestamptz DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = '' AS $$
DECLARE v_res jsonb; v_place record;
BEGIN
  v_res := public.create_story_item_core(
    p_relationship_id, p_client_story_id, p_media_intent_id, p_thumbnail_intent_id,
    p_media_width, p_media_height, p_duration_ms, p_utc_offset_minutes, p_captured_at,
    p_client_now);
  -- A place only on a FRESH insert: a replay never adds one (no backfill).
  IF p_place IS NULL
     OR (v_res->>'error') IS NOT DISTINCT FROM 'true'
     OR (v_res->>'existing')::boolean IS DISTINCT FROM false THEN
    RETURN v_res;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.feature_flags f WHERE f.key = 'couple_map_enabled' AND f.enabled) THEN
    RETURN v_res;
  END IF;
  SELECT * INTO v_place FROM public.story_place_parse(p_place);
  IF v_place.lat IS NULL THEN
    RETURN v_res;
  END IF;
  BEGIN
    INSERT INTO public.story_places (story_item_id, relationship_id, author_id, lat, lng, label)
    VALUES ((v_res->>'story_id')::uuid, p_relationship_id, auth.uid(),
            v_place.lat, v_place.lng, v_place.label);
  EXCEPTION WHEN others THEN
    NULL; -- never fatal to the story
  END;
  RETURN v_res;
END $$;

REVOKE ALL ON FUNCTION public.create_story_item(uuid, uuid, uuid, uuid, int, int, int, int, jsonb, timestamptz, timestamptz)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_story_item(uuid, uuid, uuid, uuid, int, int, int, int, jsonb, timestamptz, timestamptz)
  TO authenticated;

COMMIT;
