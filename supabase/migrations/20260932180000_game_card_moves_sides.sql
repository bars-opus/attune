-- Allow the trail marker's media_type.
ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_media_type_check;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_media_type_check
  CHECK (
    media_type IS NULL
    OR media_type = ANY (
      ARRAY['image', 'audio', 'video', 'streak', 'game', 'place', 'game_trail']
    )
  );

-- game_trail carries no session, unlike 'game'.
ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_game_session_shape_check;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_game_session_shape_check
  CHECK (
    (media_type = 'game' AND game_session_id IS NOT NULL)
    OR (media_type IS DISTINCT FROM 'game' AND game_session_id IS NULL)
  );

-- The game card moves between sides, leaving a trail behind.
--
-- iMessage's model, which is what a couple expects here: the card sits on
-- the side of whoever last acted, and each side it leaves keeps a small
-- one-line marker -- the game's name -- so the conversation shows the
-- back-and-forth rather than one bubble that silently mutates in place.
--
-- Before this the card was stuck on the initiator's side forever. Both
-- partners answered into a bubble that never changed sides and never
-- moved, so a game in active play looked like a message sent once and
-- never replied to.
--
-- sender_id is what decides the side (Message.isMine compares it to the
-- viewer), so moving the card means moving its sender to whoever just
-- acted.

-- A trail marker: the game's name, on the side the card is leaving.
--
-- media_type 'game_trail' rather than 'game': it is not a card, carries
-- no session, and must never render as one. The client draws it as a
-- single line -- icon plus name -- so the conversation keeps a record of
-- the exchange without repeating the whole card.
CREATE OR REPLACE FUNCTION public.leave_game_trail(
  p_message_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_card public.messages%ROWTYPE;
BEGIN
  SELECT * INTO v_card FROM public.messages WHERE id = p_message_id;
  IF NOT FOUND THEN RETURN; END IF;

  -- Positioned just before the card's current spot, so the trail stays
  -- where the exchange actually happened rather than collecting at the
  -- bottom with the card.
  INSERT INTO public.messages (
    relationship_id, sender_id, client_message_id,
    content, media_type, source, created_at, sort_at
  )
  VALUES (
    v_card.relationship_id,
    v_card.sender_id,
    gen_random_uuid(),
    v_card.content,
    'game_trail',
    'native',
    v_card.created_at,
    v_card.sort_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.leave_game_trail(uuid) FROM PUBLIC, anon, authenticated;

-- Moves the card to whoever just acted, leaving a trail behind.
CREATE OR REPLACE FUNCTION public.move_game_card(
  p_session_id uuid,
  p_actor_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_card public.messages%ROWTYPE;
BEGIN
  SELECT * INTO v_card FROM public.messages
  WHERE game_session_id = p_session_id;
  IF NOT FOUND THEN RETURN; END IF;

  -- Already on the actor's side: nothing to move, and no trail to leave.
  -- Without this a player answering twice in a row would stack duplicate
  -- markers for a card that never went anywhere.
  IF v_card.sender_id = p_actor_id THEN
    UPDATE public.messages
    SET sort_at = clock_timestamp()
    WHERE id = v_card.id;
    RETURN;
  END IF;

  PERFORM public.leave_game_trail(v_card.id);

  UPDATE public.messages
  SET sender_id = p_actor_id,
      sort_at = clock_timestamp()
  WHERE id = v_card.id;
END;
$$;

REVOKE ALL ON FUNCTION public.move_game_card(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Answering an ordinary round moves the card.
CREATE OR REPLACE FUNCTION public.resurface_game_message_for_round()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid;
  v_rel public.relationships%ROWTYPE;
BEGIN
  IF NEW.answer_a_submitted_at IS DISTINCT FROM OLD.answer_a_submitted_at
     OR NEW.answer_b_submitted_at IS DISTINCT FROM OLD.answer_b_submitted_at
     OR NEW.both_answered IS DISTINCT FROM OLD.both_answered THEN

    SELECT r.* INTO v_rel
    FROM public.game_sessions gs
    JOIN public.relationships r ON r.id = gs.relationship_id
    WHERE gs.id = NEW.session_id;

    -- Whichever slot just filled names the actor.
    IF NEW.answer_a_submitted_at IS DISTINCT FROM OLD.answer_a_submitted_at THEN
      v_actor := v_rel.user_a;
    ELSIF NEW.answer_b_submitted_at IS DISTINCT FROM OLD.answer_b_submitted_at THEN
      v_actor := v_rel.user_b;
    END IF;

    IF v_actor IS NOT NULL THEN
      PERFORM public.move_game_card(NEW.session_id, v_actor);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.resurface_game_message_for_round()
  FROM PUBLIC, anon, authenticated;

-- A Mirror subject writes their truth elsewhere, so the round UPDATE
-- above never fires for them.
CREATE OR REPLACE FUNCTION public.resurface_game_message_for_truth()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_id uuid;
BEGIN
  SELECT session_id INTO v_session_id
  FROM public.game_session_rounds WHERE id = NEW.round_id;

  IF v_session_id IS NOT NULL THEN
    PERFORM public.move_game_card(v_session_id, NEW.subject_id);
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.resurface_game_message_for_truth()
  FROM PUBLIC, anon, authenticated;
