-- The card must count a Mirror subject's truth as an answer.
--
-- session_game_round_state read only answer_a_submitted_at and
-- answer_b_submitted_at. In Mirror the SUBJECT of a round writes their
-- truth to mirror_round_truth instead -- it is a fact about themselves,
-- not a guess about their partner -- so the function saw neither slot
-- filled and reported that nobody had answered.
--
-- The effect: a player answered their Mirror round, the server correctly
-- refused a second submit with "Answer already submitted", and the chat
-- card still showed "Round 1 of 8" rather than "Waiting for your
-- partner". Their partner's card never said "Your turn" either, so from
-- both sides the game looked like it had not moved.
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
  v_partner uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  SELECT (r.user_a = v_user_id),
         CASE WHEN r.user_a = v_user_id THEN r.user_b ELSE r.user_a END
  INTO v_is_user_a, v_partner
  FROM public.game_sessions gs
  JOIN public.relationships r ON r.id = gs.relationship_id
  WHERE gs.id = p_session_id
    AND (r.user_a = v_user_id OR r.user_b = v_user_id);

  IF v_is_user_a IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    -- Answered means "has done their part of this round", which for a
    -- Mirror subject is a truth row and for everyone else is an answer
    -- slot. Reading only the slots made a subject look idle immediately
    -- after they had answered.
    CASE WHEN v_is_user_a
      THEN gsr.answer_a_submitted_at IS NOT NULL
      ELSE gsr.answer_b_submitted_at IS NOT NULL
    END
    OR EXISTS (
      SELECT 1 FROM public.mirror_round_truth t
      WHERE t.round_id = gsr.id AND t.subject_id = v_user_id
    ),
    CASE WHEN v_is_user_a
      THEN gsr.answer_b_submitted_at IS NOT NULL
      ELSE gsr.answer_a_submitted_at IS NOT NULL
    END
    OR EXISTS (
      SELECT 1 FROM public.mirror_round_truth t
      WHERE t.round_id = gsr.id AND t.subject_id = v_partner
    )
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
