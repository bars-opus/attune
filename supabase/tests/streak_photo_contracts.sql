-- Contract tests for streak photos (spec §6.3 step 3): media_kind on
-- streak_clips, the honest duration_ms=0 for a photo, and the widened
-- upload-intent mime allowlist. Self-contained, per streak_contracts.sql's
-- own opening note: reading an ambient relationship makes a test skip
-- silently and pass vacuously on an empty database.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('5f100000-0000-0000-0000-0000000000a1'),
  ('5f100000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.users (id, phone, display_name) VALUES
  ('5f100000-0000-0000-0000-0000000000a1', '+233251000001', 'Photo A'),
  ('5f100000-0000-0000-0000-0000000000b2', '+233251000002', 'Photo B')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('5e100000-0000-0000-0000-000000000001',
        '5f100000-0000-0000-0000-0000000000a1',
        '5f100000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;

-- 1. Existing rows default to 'video': a row inserted with no media_kind
--    at all (exactly what every pre-migration INSERT and every in-flight
--    outbox item looks like) must still read back as 'video'.
DO $$
DECLARE v_msg uuid; v_kind text;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content)
  VALUES ('5e100000-0000-0000-0000-000000000001',
          '5f100000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'streak parent')
  RETURNING id INTO v_msg;

  INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
  VALUES (v_msg, 0, 'chat/legacy-0', 4000);

  SELECT media_kind INTO v_kind
  FROM public.streak_clips WHERE message_id = v_msg;

  IF v_kind IS DISTINCT FROM 'video' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: an unmigrated-shaped insert defaulted to % not video',
      v_kind;
  END IF;
END $$;

-- 2. media_kind only accepts 'photo' or 'video'.
--
-- Read the constraint DEFINITION directly (streak_contracts.sql's own
-- pattern for messages_media_type_check), not an insert-and-catch: ANY
-- media_kind outside {photo, video} also fails
-- streak_clips_duration_ms_check (its two OR branches only name those two
-- values), so an insert attempting a third value is rejected regardless
-- of what the enum constraint itself says -- a bare check_violation catch
-- would pass this test even if the enum were silently widened to accept
-- 'gif', because the OTHER constraint catches the same row anyway.
DO $$
DECLARE v_def text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def
  FROM pg_constraint WHERE conname = 'streak_clips_media_kind_check';

  -- Exact string match against Postgres's own canonical rendering of
  -- `CHECK (media_kind IN ('photo', 'video'))`. Exact rather than a
  -- substring/LIKE test so this catches BOTH directions of drift: a
  -- missing value (would wrongly reject a real photo or video row) and a
  -- widened one (e.g. a stray extra value re-added to the allowed list,
  -- the mutation this test exists to catch).
  IF v_def IS DISTINCT FROM
    'CHECK ((media_kind = ANY (ARRAY[''photo''::text, ''video''::text])))'
  THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: streak_clips_media_kind_check is not exactly {photo, video}: %',
      v_def;
  END IF;
END $$;

-- 3. A photo clip stores duration_ms = 0 honestly.
DO $$
DECLARE v_msg uuid; v_dur int; v_kind text;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content)
  VALUES ('5e100000-0000-0000-0000-000000000001',
          '5f100000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'streak parent')
  RETURNING id INTO v_msg;

  INSERT INTO public.streak_clips
    (message_id, clip_index, media_url, duration_ms, media_kind)
  VALUES (v_msg, 0, 'chat/photo-0', 0, 'photo');

  SELECT duration_ms, media_kind INTO v_dur, v_kind
  FROM public.streak_clips WHERE message_id = v_msg;

  IF v_dur IS DISTINCT FROM 0 OR v_kind IS DISTINCT FROM 'photo' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a photo clip did not store kind=photo/duration=0 (got kind=%, duration=%)',
      v_kind, v_dur;
  END IF;
END $$;

-- 4. A video clip is still forbidden from having duration_ms <= 0 — the
--    constraint that guarded against a genuinely broken video must not
--    have been silently loosened by adding the photo case.
DO $$
DECLARE v_msg uuid; v_ok boolean := false;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content)
  VALUES ('5e100000-0000-0000-0000-000000000001',
          '5f100000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'streak parent')
  RETURNING id INTO v_msg;

  BEGIN
    INSERT INTO public.streak_clips
      (message_id, clip_index, media_url, duration_ms, media_kind)
    VALUES (v_msg, 0, 'chat/broken-video', 0, 'video');
    v_ok := true;
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  IF v_ok THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a video clip with duration_ms=0 was accepted';
  END IF;
END $$;

-- 5. A photo clip is forbidden from claiming a nonzero duration — the
--    honesty requirement cuts both ways.
DO $$
DECLARE v_msg uuid; v_ok boolean := false;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content)
  VALUES ('5e100000-0000-0000-0000-000000000001',
          '5f100000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'streak parent')
  RETURNING id INTO v_msg;

  BEGIN
    INSERT INTO public.streak_clips
      (message_id, clip_index, media_url, duration_ms, media_kind)
    VALUES (v_msg, 0, 'chat/fake-duration', 5000, 'photo');
    v_ok := true;
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  IF v_ok THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a photo clip with a nonzero duration was accepted';
  END IF;
END $$;

-- 6. The upload intent now accepts an image mime for a streak, and still
--    accepts the original video/mp4 unchanged.
DO $$
DECLARE v_key text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '5f100000-0000-0000-0000-0000000000a1',
                      'role', 'authenticated')::text, true);

  SELECT storage_key INTO v_key
  FROM public.create_chat_media_upload_intent(
    '5e100000-0000-0000-0000-000000000001'::uuid, 'image/jpeg', 'streak');
  IF v_key IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no upload intent issued for a streak photo';
  END IF;

  SELECT storage_key INTO v_key
  FROM public.create_chat_media_upload_intent(
    '5e100000-0000-0000-0000-000000000001'::uuid, 'video/mp4', 'streak');
  IF v_key IS NULL THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: streak video intents regressed while widening for photos';
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 7. The upload intent still rejects an unsupported mime for a streak
--    (the allowlist widened, it did not open up).
DO $$
DECLARE v_ok boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '5f100000-0000-0000-0000-0000000000a1',
                      'role', 'authenticated')::text, true);

  BEGIN
    PERFORM public.create_chat_media_upload_intent(
      '5e100000-0000-0000-0000-000000000001'::uuid, 'audio/mp4', 'streak');
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  PERFORM set_config('request.jwt.claims', '', true);

  IF v_ok THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a streak upload intent accepted an unsupported mime (audio/mp4)';
  END IF;
END $$;

-- 8. A photo streak's clips are destroyed exactly like a video's when the
--    budget reaches zero — mark_streak_viewed and the deletion queue are
--    media-kind agnostic, and this proves it rather than assuming it.
DO $$
DECLARE v_msg uuid; v_left int; v_queued int;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content,
     streak_views_remaining)
  VALUES ('5e100000-0000-0000-0000-000000000001',
          '5f100000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'photo streak', 1)
  RETURNING id INTO v_msg;

  INSERT INTO public.streak_clips
    (message_id, clip_index, media_url, duration_ms, media_kind)
  VALUES (v_msg, 0, 'chat/photo-spend-0', 0, 'photo');

  INSERT INTO storage.buckets (id, name)
  VALUES ('message-media', 'message-media')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO storage.objects (bucket_id, name)
  VALUES ('message-media', 'chat/photo-spend-0')
  ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '5f100000-0000-0000-0000-0000000000b2',
                      'role', 'authenticated')::text, true);

  v_left := public.mark_streak_viewed(v_msg);

  PERFORM set_config('request.jwt.claims', '', true);

  IF v_left <> 0 THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a one-view photo streak should report 0 left, got %',
      v_left;
  END IF;

  IF EXISTS (SELECT 1 FROM public.streak_clips WHERE message_id = v_msg) THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a photo streak''s clips survived a spent budget';
  END IF;

  SELECT count(*) INTO v_queued
  FROM public.media_deletion_queue
  WHERE bucket_id = 'message-media' AND object_name = 'chat/photo-spend-0'
    AND deleted_at IS NULL;
  IF v_queued <> 1 THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a spent photo streak''s object was not queued for deletion (%)',
      v_queued;
  END IF;
END $$;

ROLLBACK;
