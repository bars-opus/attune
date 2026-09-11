-- The story row's shape is a security boundary, not just a schema.
-- expires_at must be exactly 24h from creation (a client-controlled
-- window would let a story live forever); a video must carry a duration
-- and an image must not; and the two storage keys must differ, or
-- deleting a story would remove its own thumbnail twice and its media
-- never.
BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-0000000051a1'::uuid),
  ('00000000-0000-0000-0000-0000000051a2'::uuid) ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000051a1'::uuid,'+15550510001','S1'),
  ('00000000-0000-0000-0000-0000000051a2'::uuid,'+15550510002','S2')
  ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  v_rel uuid;
  v_now timestamptz := now();
  v_ok  boolean;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-0000000051a1'::uuid,
          '00000000-0000-0000-0000-0000000051a2'::uuid, 'active')
  RETURNING id INTO v_rel;

  -- A 48-hour window must be refused.
  v_ok := false;
  BEGIN
    INSERT INTO public.story_items(
      client_story_id, relationship_id, author_id, media_type,
      media_key, thumbnail_key, media_width, media_height,
      occurred_on, created_at, expires_at)
    VALUES (gen_random_uuid(), v_rel,
            '00000000-0000-0000-0000-0000000051a1'::uuid, 'image',
            'k/a', 'k/b', 100, 100, current_date, v_now,
            v_now + interval '48 hours');
    v_ok := true;
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION 'EXPLOIT: a story set its own 48h expiry';
  END IF;

  -- An image carrying a duration must be refused.
  v_ok := false;
  BEGIN
    INSERT INTO public.story_items(
      client_story_id, relationship_id, author_id, media_type,
      media_key, thumbnail_key, media_width, media_height, duration_ms,
      occurred_on, created_at, expires_at)
    VALUES (gen_random_uuid(), v_rel,
            '00000000-0000-0000-0000-0000000051a1'::uuid, 'image',
            'k/c', 'k/d', 100, 100, 5000, current_date, v_now,
            v_now + interval '24 hours');
    v_ok := true;
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION 'an image row accepted a duration';
  END IF;

  -- A video outside 500ms-60s must be refused.
  v_ok := false;
  BEGIN
    INSERT INTO public.story_items(
      client_story_id, relationship_id, author_id, media_type,
      media_key, thumbnail_key, media_width, media_height, duration_ms,
      occurred_on, created_at, expires_at)
    VALUES (gen_random_uuid(), v_rel,
            '00000000-0000-0000-0000-0000000051a1'::uuid, 'video',
            'k/e', 'k/f', 100, 100, 90000, current_date, v_now,
            v_now + interval '24 hours');
    v_ok := true;
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION 'a 90s video was accepted';
  END IF;

  -- Identical media and thumbnail keys must be refused.
  v_ok := false;
  BEGIN
    INSERT INTO public.story_items(
      client_story_id, relationship_id, author_id, media_type,
      media_key, thumbnail_key, media_width, media_height,
      occurred_on, created_at, expires_at)
    VALUES (gen_random_uuid(), v_rel,
            '00000000-0000-0000-0000-0000000051a1'::uuid, 'image',
            'k/same', 'k/same', 100, 100, current_date, v_now,
            v_now + interval '24 hours');
    v_ok := true;
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION 'media_key and thumbnail_key were allowed to match';
  END IF;

  -- A valid row is accepted, and the same (author, client_story_id)
  -- twice is refused -- this is what makes finalize retries safe.
  INSERT INTO public.story_items(
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at)
  VALUES ('00000000-0000-0000-0000-00000000c1d1'::uuid, v_rel,
          '00000000-0000-0000-0000-0000000051a1'::uuid, 'image',
          'k/good', 'k/goodthumb', 1080, 1920, current_date, v_now,
          v_now + interval '24 hours');

  v_ok := false;
  BEGIN
    INSERT INTO public.story_items(
      client_story_id, relationship_id, author_id, media_type,
      media_key, thumbnail_key, media_width, media_height,
      occurred_on, created_at, expires_at)
    VALUES ('00000000-0000-0000-0000-00000000c1d1'::uuid, v_rel,
            '00000000-0000-0000-0000-0000000051a1'::uuid, 'image',
            'k/good2', 'k/goodthumb2', 1080, 1920, current_date, v_now,
            v_now + interval '24 hours');
    v_ok := true;
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION 'a replayed client_story_id posted twice';
  END IF;

  -- has_been_viewed starts false: nothing is seen before it is sent.
  PERFORM 1 FROM public.story_items
   WHERE client_story_id = '00000000-0000-0000-0000-00000000c1d1'::uuid
     AND has_been_viewed IS FALSE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'has_been_viewed did not default to false';
  END IF;

  RAISE NOTICE 'story schema contracts: all held';
END $$;

ROLLBACK;
