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

ROLLBACK;
