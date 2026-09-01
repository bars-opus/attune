-- Whose move it is in a session game, for the chat card.
--
-- Session games (Mirror, Sliding Scale, Scenario) have no turn order:
-- both partners answer the SAME round independently, then it reveals. So
-- game_sessions.current_turn_user_id is null for them, and the chat card
-- could only say "Round 2 of 6" -- true, but useless for deciding whether
-- anything is waiting on you.
--
-- Returns whether the CALLER has answered the current round, and whether
-- their partner has. Booleans only, never the answers: §8.4 makes the
-- pre-reveal gate non-negotiable, and a card that leaked "they said X"
-- into the chat would defeat the entire mechanic. The two timestamps this
-- reads are answer_*_submitted_at, not answer_a/answer_b.
CREATE OR REPLACE FUNCTION public.session_game_round_state(
  p_session_id uuid
)
RETURNS TABLE (viewer_answered boolean, partner_answered boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_is_user_a boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  -- Membership decides which answer slot is the caller's: answer_a and
  -- answer_b follow relationships.user_a/user_b, not who asked. A
  -- non-member gets no row at all rather than a false, so they cannot
  -- distinguish "not a member" from "nobody has answered".
  SELECT (r.user_a = v_user_id)
  INTO v_is_user_a
  FROM public.game_sessions gs
  JOIN public.relationships r ON r.id = gs.relationship_id
  WHERE gs.id = p_session_id
    AND (r.user_a = v_user_id OR r.user_b = v_user_id);

  IF v_is_user_a IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    CASE WHEN v_is_user_a
      THEN gsr.answer_a_submitted_at IS NOT NULL
      ELSE gsr.answer_b_submitted_at IS NOT NULL
    END,
    CASE WHEN v_is_user_a
      THEN gsr.answer_b_submitted_at IS NOT NULL
      ELSE gsr.answer_a_submitted_at IS NOT NULL
    END
  FROM public.game_session_rounds gsr
  WHERE gsr.session_id = p_session_id
    AND gsr.both_answered IS NOT TRUE
  ORDER BY gsr.round_number
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.session_game_round_state(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.session_game_round_state(uuid)
  TO authenticated;
