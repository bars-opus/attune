-- Place updates (the deliberate half of location).
--
-- Ambient presence moved to couple_map_presence_contracts.sql with the
-- Couple Map (2026-10-16); what stays here is the chat place update.
--
-- Attune ships a discreet exit as a permanent constraint and runs
-- coercive-control detection on chat. This feature is designed so it
-- cannot become the thing the rest of the app defends against, and these
-- tests pin the properties that guarantee that -- not the UI copy, which
-- will change, but the rules that make the copy safe.

BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-00000000e001'),
  ('00000000-0000-0000-0000-00000000e002'),
  ('00000000-0000-0000-0000-00000000e003') ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-00000000e001', '+15559990101', 'E1'),
  ('00000000-0000-0000-0000-00000000e002', '+15559990102', 'E2'),
  ('00000000-0000-0000-0000-00000000e003', '+15559990103', 'E3')
  ON CONFLICT (id) DO NOTHING;

-- Place updates: the deliberate half of the feature.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000e001';
  b uuid := '00000000-0000-0000-0000-00000000e002';
  c uuid := '00000000-0000-0000-0000-00000000e003';
  v_rel uuid;
  v_msg uuid;
  v_count int;
  v_refused boolean := false;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);

  v_msg := public.post_place_update(
    v_rel, 'At the coffee shop', 'thinking of you', 5.5601, -0.2050,
    'Accra', 'Ghana'
  );

  -- One RPC, not two client writes: a failure must not leave a message
  -- with no place or a place with no message.
  SELECT count(*) INTO v_count
  FROM public.messages m
  JOIN public.place_updates p ON p.message_id = m.id
  WHERE m.id = v_msg AND m.media_type = 'place';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'the update did not create a message and a place together';
  END IF;

  -- Deleting the message takes the coordinates with it. A place that
  -- read one way tonight may read differently tomorrow, and there must be
  -- no way to remove the card while leaving the location behind.
  DELETE FROM public.messages WHERE id = v_msg;

  SELECT count(*) INTO v_count
  FROM public.place_updates WHERE message_id = v_msg;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'a deleted message left its coordinates behind';
  END IF;

  -- A non-member cannot post into someone else's chat.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', c, 'role', 'authenticated')::text, true);

  BEGIN
    PERFORM public.post_place_update(v_rel, 'Somewhere');
  EXCEPTION WHEN OTHERS THEN
    v_refused := true;
  END;

  IF NOT v_refused THEN
    RAISE EXCEPTION 'a non-member posted a place into this relationship';
  END IF;
END $$;

-- Input bounds (checklist 2.1): a chosen place is still a real place.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000e001';
  v_rel uuid;
  v_rejected boolean := false;
BEGIN
  SELECT id INTO v_rel FROM public.relationships WHERE user_a = a LIMIT 1;
  BEGIN
    INSERT INTO public.place_updates(relationship_id, user_id, label, latitude, longitude)
    VALUES (v_rel, a, 'Nowhere', 999, 0);
  EXCEPTION WHEN check_violation THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN
    RAISE EXCEPTION 'a place at latitude 999 was accepted';
  END IF;
  -- Real extremes must still be storable.
  INSERT INTO public.place_updates(relationship_id, user_id, label, latitude, longitude)
  VALUES (v_rel, a, 'Edge of the map', -90, 180);
END $$;

ROLLBACK;
