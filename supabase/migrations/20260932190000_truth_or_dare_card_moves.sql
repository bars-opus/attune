-- Truth or Dare moves its card too.
--
-- The card machinery hangs off UPDATEs to game_session_rounds: a partner
-- fills an answer slot, the trigger moves the card to them and leaves a
-- trail. Truth or Dare does not work that way -- it INSERTS a new round
-- per turn, with active_partner_id naming whose turn it is, and never
-- updates an answer slot at all.
--
-- So the whole card-and-trail flow was invisible for it: the card stayed
-- on the initiator forever and the chat showed nothing after a turn.
CREATE OR REPLACE FUNCTION public.move_game_card_for_new_round()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- active_partner_id is whose turn the new round belongs to, which is
  -- exactly the side the card should now sit on.
  IF NEW.active_partner_id IS NOT NULL AND NEW.session_id IS NOT NULL THEN
    PERFORM public.move_game_card(NEW.session_id, NEW.active_partner_id);
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.move_game_card_for_new_round()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS move_game_card_for_new_round
  ON public.game_session_rounds;
CREATE TRIGGER move_game_card_for_new_round
  AFTER INSERT ON public.game_session_rounds
  FOR EACH ROW EXECUTE FUNCTION public.move_game_card_for_new_round();
