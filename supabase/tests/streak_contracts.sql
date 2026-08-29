-- Contract tests for the streak camera. Self-contained: reading an ambient
-- relationship makes a test skip silently and pass vacuously on an empty
-- database, which is how an earlier Love Map draft fooled itself.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('5f000000-0000-0000-0000-0000000000a1'),
  ('5f000000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.users (id, phone, display_name) VALUES
  ('5f000000-0000-0000-0000-0000000000a1', '+233250000001', 'Streak A'),
  ('5f000000-0000-0000-0000-0000000000b2', '+233250000002', 'Streak B')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('5e000000-0000-0000-0000-000000000001',
        '5f000000-0000-0000-0000-0000000000a1',
        '5f000000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;

-- 1. Both media_type constraints accept 'streak', and stay in step.
--    Drift between exactly these two hid the voice-note bug (5c23cfc8):
--    the upload intent succeeded and only the final insert failed.
DO $$
DECLARE v_messages text; v_intents text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_messages
  FROM pg_constraint WHERE conname = 'messages_media_type_check';
  SELECT pg_get_constraintdef(oid) INTO v_intents
  FROM pg_constraint
  WHERE conname = 'message_media_upload_intents_media_type_check';

  IF v_messages NOT LIKE '%streak%' THEN
    RAISE EXCEPTION 'messages_media_type_check rejects streak: %', v_messages;
  END IF;
  IF v_intents NOT LIKE '%streak%' THEN
    RAISE EXCEPTION 'upload intents reject streak: %', v_intents;
  END IF;
END $$;

-- 2. Clips cascade with their message: a deleted streak leaves nothing.
DO $$
DECLARE v_msg uuid; v_left int;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content)
  VALUES ('5e000000-0000-0000-0000-000000000001',
          '5f000000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'streak parent')
  RETURNING id INTO v_msg;

  INSERT INTO public.streak_clips
    (message_id, clip_index, media_url, duration_ms)
  VALUES (v_msg, 0, 'chat/clip-0', 60000),
         (v_msg, 1, 'chat/clip-1', 20000);

  DELETE FROM public.messages WHERE id = v_msg;

  SELECT count(*) INTO v_left
  FROM public.streak_clips WHERE message_id = v_msg;
  IF v_left <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % clips survived their message', v_left;
  END IF;
END $$;

-- 3. clip_index is unique per message: playback order must be unambiguous.
DO $$
DECLARE v_msg uuid; v_dup boolean := false;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content)
  VALUES ('5e000000-0000-0000-0000-000000000001',
          '5f000000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'streak parent')
  RETURNING id INTO v_msg;

  INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
  VALUES (v_msg, 0, 'chat/a', 1000);

  BEGIN
    INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
    VALUES (v_msg, 0, 'chat/b', 1000);
    v_dup := true;
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  IF v_dup THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: duplicate clip_index accepted';
  END IF;
END $$;

-- 4. Views decrement, and clips are destroyed only at ZERO.
--
-- mark_video_viewed deletes the object on FIRST view, which is right for
-- strict view-once and fatal for a budget. Streaks need their own path.
DO $$
DECLARE v_msg uuid; v_left int;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content,
     streak_views_remaining)
  VALUES ('5e000000-0000-0000-0000-000000000001',
          '5f000000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'streak parent', 3)
  RETURNING id INTO v_msg;

  INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
  VALUES (v_msg, 0, 'chat/clip-0', 60000);

  -- The RECIPIENT views it.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '5f000000-0000-0000-0000-0000000000b2',
                      'role', 'authenticated')::text, true);

  v_left := public.mark_streak_viewed(v_msg);
  IF v_left <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expected 2 views left, got %', v_left;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.streak_clips WHERE message_id = v_msg) THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: clips destroyed while views still remained';
  END IF;

  v_left := public.mark_streak_viewed(v_msg);
  v_left := public.mark_streak_viewed(v_msg);
  IF v_left <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expected 0 views left, got %', v_left;
  END IF;

  IF EXISTS (SELECT 1 FROM public.streak_clips WHERE message_id = v_msg) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clips survived a spent budget';
  END IF;

  -- Spent: a further view must not go negative.
  v_left := public.mark_streak_viewed(v_msg);
  IF v_left <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: budget went below zero (%)', v_left;
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 5. The SENDER re-opening their own streak does not spend the
--    recipient's budget.
DO $$
DECLARE v_msg uuid; v_left int;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content,
     streak_views_remaining)
  VALUES ('5e000000-0000-0000-0000-000000000001',
          '5f000000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'streak parent', 2)
  RETURNING id INTO v_msg;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '5f000000-0000-0000-0000-0000000000a1',
                      'role', 'authenticated')::text, true);
  v_left := public.mark_streak_viewed(v_msg);

  IF v_left <> 2 THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: the sender spent the recipient budget (% left)', v_left;
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 6. A non-member cannot view, or even probe, another couple's streak.
DO $$
DECLARE v_msg uuid; v_ok boolean := false;
BEGIN
  INSERT INTO auth.users (id) VALUES ('5f000000-0000-0000-0000-0000000000c3')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content,
     streak_views_remaining)
  VALUES ('5e000000-0000-0000-0000-000000000001',
          '5f000000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'streak parent', 1)
  RETURNING id INTO v_msg;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '5f000000-0000-0000-0000-0000000000c3',
                      'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.mark_streak_viewed(v_msg);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  IF v_ok THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-member viewed a streak';
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 7. The upload intent accepts 'streak'.
--
-- This is the FOURTH place media_type is gated, after the two CHECK
-- constraints and the insert trigger. It rejected streak outright, so
-- every send failed before a file was even transcoded -- and the client
-- swallowed the error, so the console showed only video_compress's
-- informational logs.
DO $$
DECLARE v_key text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '5f000000-0000-0000-0000-0000000000a1',
                      'role', 'authenticated')::text, true);

  SELECT storage_key INTO v_key
  FROM public.create_chat_media_upload_intent(
    '5e000000-0000-0000-0000-000000000001'::uuid, 'video/mp4', 'streak');

  IF v_key IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no upload intent issued for a streak';
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 8. authenticated can write the columns a streak send touches.
--
-- Supabase grants table privileges platform-side when a table is created.
-- A column added by a LATER migration is not covered, and because
-- messages already carries column-level grants, Postgres then demands a
-- column privilege for every column written -- so inserting
-- streak_views_remaining failed with 42501 in production while passing
-- locally, where the test harness grants every column blanket.
DO $$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(c, ', ') INTO v_missing
  FROM unnest(ARRAY[
    'relationship_id', 'sender_id', 'client_message_id', 'content',
    'media_type', 'media_url', 'streak_views_remaining'
  ]) AS c
  WHERE NOT has_column_privilege('authenticated', 'public.messages', c, 'INSERT');

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: authenticated cannot INSERT messages columns: %',
      v_missing;
  END IF;

  IF NOT has_table_privilege('authenticated', 'public.streak_clips', 'INSERT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated cannot INSERT streak_clips';
  END IF;
END $$;

ROLLBACK;
