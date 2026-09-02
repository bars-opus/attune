-- Answering a round moves the game card to the bottom of the chat.
--
-- resurface_game_message fired only on game_sessions changes. Answering
-- writes to game_session_rounds and leaves the session row untouched, so
-- the card never moved: it stayed wherever the game was started --
-- usually far up the conversation, on the initiator's side -- while both
-- partners waited for something to arrive.
--
-- That is why a game "sent back" appeared to send nothing. There is one
-- card per game by design; what was missing is that it should RETURN to
-- the bottom when it becomes someone's move, which is the whole reason
-- sort_at exists.
CREATE OR REPLACE FUNCTION public.resurface_game_message_for_round()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only when an answer actually lands. Rounds are also touched by
  -- reveal and scoring, and moving the card for those would jump it
  -- around the conversation for changes neither partner acted on.
  IF NEW.answer_a_submitted_at IS DISTINCT FROM OLD.answer_a_submitted_at
     OR NEW.answer_b_submitted_at IS DISTINCT FROM OLD.answer_b_submitted_at
     OR NEW.both_answered IS DISTINCT FROM OLD.both_answered THEN
    UPDATE public.messages
    SET sort_at = clock_timestamp()
    WHERE game_session_id = NEW.session_id;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.resurface_game_message_for_round()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS resurface_game_message_for_round
  ON public.game_session_rounds;
CREATE TRIGGER resurface_game_message_for_round
  AFTER UPDATE ON public.game_session_rounds
  FOR EACH ROW EXECUTE FUNCTION public.resurface_game_message_for_round();

-- A Mirror subject writes their truth to a different table entirely, so
-- the round UPDATE above never fires for them. Without this, answering
-- as the subject moves nothing.
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
    UPDATE public.messages
    SET sort_at = clock_timestamp()
    WHERE game_session_id = v_session_id;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.resurface_game_message_for_truth()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS resurface_game_message_for_truth
  ON public.mirror_round_truth;
CREATE TRIGGER resurface_game_message_for_truth
  AFTER INSERT ON public.mirror_round_truth
  FOR EACH ROW EXECUTE FUNCTION public.resurface_game_message_for_truth();
