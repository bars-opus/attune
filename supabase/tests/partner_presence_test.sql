-- "Active in this chat".
--
-- chat_presence has been written since July but never read back: the chat
-- header's "Online" was driven by the VIEWER's own connectivity, so it
-- read Online whenever you had a connection, whatever your partner was
-- doing. Decoration, not data.
--
-- chat_presence's own policy is unchanged -- a user still reads only
-- their own row. This opens exactly one question through a SECURITY
-- DEFINER function: is my partner in this conversation right now? A
-- boolean, never a timestamp, because Attune does not show last-seen.

BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-0000000ab001'),
  ('00000000-0000-0000-0000-0000000ab002'),
  ('00000000-0000-0000-0000-0000000ab003') ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000ab001', '+15554440001', 'P1'),
  ('00000000-0000-0000-0000-0000000ab002', '+15554440002', 'P2'),
  ('00000000-0000-0000-0000-0000000ab003', '+15554440003', 'P3')
  ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  v_rel uuid;
  v_other_rel uuid;
  v_result boolean;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-0000000ab001',
          '00000000-0000-0000-0000-0000000ab002', 'active')
  RETURNING id INTO v_rel;

  -- Partner 2 is viewing the conversation, right now.
  INSERT INTO public.chat_presence(user_id, active_relationship_id, updated_at)
  VALUES ('00000000-0000-0000-0000-0000000ab002', v_rel, now())
  ON CONFLICT (user_id) DO UPDATE
    SET active_relationship_id = EXCLUDED.active_relationship_id,
        updated_at = now();

  -- Partner 1 asks, and sees them.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '00000000-0000-0000-0000-0000000ab001',
                      'role', 'authenticated')::text, true);

  SELECT public.partner_is_active_in_chat(v_rel) INTO v_result;
  IF NOT v_result THEN
    RAISE EXCEPTION 'a partner viewing the chat did not read as active';
  END IF;

  -- A stale heartbeat is not presence. This is what makes the indicator
  -- mean "here now" rather than "was here at some point".
  UPDATE public.chat_presence
  SET updated_at = now() - interval '5 minutes'
  WHERE user_id = '00000000-0000-0000-0000-0000000ab002';

  SELECT public.partner_is_active_in_chat(v_rel) INTO v_result;
  IF v_result THEN
    RAISE EXCEPTION 'a stale heartbeat still read as active';
  END IF;

  -- Being in a DIFFERENT conversation is not being in this one. A real
  -- second relationship, since active_relationship_id is a foreign key.
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-0000000ab002',
          '00000000-0000-0000-0000-0000000ab003', 'active')
  RETURNING id INTO v_other_rel;

  UPDATE public.chat_presence
  SET active_relationship_id = v_other_rel, updated_at = now()
  WHERE user_id = '00000000-0000-0000-0000-0000000ab002';

  SELECT public.partner_is_active_in_chat(v_rel) INTO v_result;
  IF v_result THEN
    RAISE EXCEPTION 'presence in another chat leaked into this one';
  END IF;

  -- A stranger must learn nothing. Without the membership check, any
  -- authenticated user could probe a relationship id and find out
  -- whether someone is at their phone.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '00000000-0000-0000-0000-0000000ab003',
                      'role', 'authenticated')::text, true);

  UPDATE public.chat_presence
  SET active_relationship_id = v_rel, updated_at = now()
  WHERE user_id = '00000000-0000-0000-0000-0000000ab002';

  SELECT public.partner_is_active_in_chat(v_rel) INTO v_result;
  IF v_result THEN
    RAISE EXCEPTION 'a non-member could read presence for this relationship';
  END IF;

  -- Own presence is not partner presence: a user alone in a chat must
  -- not see themselves reflected back as "Active".
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '00000000-0000-0000-0000-0000000ab001',
                      'role', 'authenticated')::text, true);

  DELETE FROM public.chat_presence
  WHERE user_id = '00000000-0000-0000-0000-0000000ab002';
  INSERT INTO public.chat_presence(user_id, active_relationship_id, updated_at)
  VALUES ('00000000-0000-0000-0000-0000000ab001', v_rel, now())
  ON CONFLICT (user_id) DO UPDATE
    SET active_relationship_id = EXCLUDED.active_relationship_id,
        updated_at = now();

  SELECT public.partner_is_active_in_chat(v_rel) INTO v_result;
  IF v_result THEN
    RAISE EXCEPTION 'a user saw their OWN presence as their partner''s';
  END IF;
END $$;

-- The window is bounded: a caller must not be able to widen it into
-- last-seen by another name.
DO $$
DECLARE
  v_rel uuid;
BEGIN
  SELECT id INTO v_rel FROM public.relationships
  WHERE user_a = '00000000-0000-0000-0000-0000000ab001' LIMIT 1;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '00000000-0000-0000-0000-0000000ab001',
                      'role', 'authenticated')::text, true);

  UPDATE public.chat_presence
  SET user_id = user_id, active_relationship_id = v_rel,
      updated_at = now() - interval '30 minutes'
  WHERE user_id = '00000000-0000-0000-0000-0000000ab001';

  INSERT INTO public.chat_presence(user_id, active_relationship_id, updated_at)
  VALUES ('00000000-0000-0000-0000-0000000ab002', v_rel,
          now() - interval '30 minutes')
  ON CONFLICT (user_id) DO UPDATE
    SET active_relationship_id = EXCLUDED.active_relationship_id,
        updated_at = EXCLUDED.updated_at;

  -- A 24-hour window request is clamped to 120 seconds, so half-hour-old
  -- presence still reads as absent.
  IF public.partner_is_active_in_chat(v_rel, 86400) THEN
    RAISE EXCEPTION 'the freshness window was not clamped';
  END IF;
END $$;

ROLLBACK;
