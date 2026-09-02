-- 36 Questions moves its card, and its card knows whose move it is.
--
-- 36 Questions writes answers to thirty_six_question_answers, not to the
-- answer_a/answer_b slots on the round. So the card triggers -- which
-- watch those slots -- never fired for it, exactly as they did not for
-- Mirror's truth table, and its card could not say whose turn it was.
--
-- Same shape as the Mirror fix: its own trigger for the move, and its own
-- clause in the state function for the label.
CREATE OR REPLACE FUNCTION public.move_game_card_for_thirty_six()
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
    PERFORM public.move_game_card(v_session_id, NEW.user_id);
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.move_game_card_for_thirty_six()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS move_game_card_for_thirty_six
  ON public.thirty_six_question_answers;
CREATE TRIGGER move_game_card_for_thirty_six
  AFTER INSERT ON public.thirty_six_question_answers
  FOR EACH ROW EXECUTE FUNCTION public.move_game_card_for_thirty_six();

-- And the label. "Answered" now also means a 36 Questions answer row,
-- alongside an answer slot and a Mirror truth.
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
  v_active uuid;
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

  -- Turn-based: the newest round names whose move it is.
  --
  -- Restricted BY GAME TYPE. Mirror also fills active_partner_id -- it
  -- names the round's SUBJECT -- but there the active partner is the one
  -- who ANSWERS, not the one being waited on, so keying on the column
  -- alone inverts Mirror entirely.
  SELECT gsr.active_partner_id INTO v_active
  FROM public.game_session_rounds gsr
  JOIN public.game_sessions gs ON gs.id = gsr.session_id
  WHERE gsr.session_id = p_session_id
    AND gs.game_type = 'truth_or_dare'
    AND gsr.active_partner_id IS NOT NULL
    AND gsr.both_answered IS NOT TRUE
  ORDER BY gsr.round_number DESC
  LIMIT 1;

  IF v_active IS NOT NULL THEN
    RETURN QUERY SELECT (v_active <> v_user_id), (v_active = v_user_id);
    RETURN;
  END IF;

  -- Everything else answers the same round. "Has done their part" spans
  -- three storage shapes: an answer slot, a Mirror truth, and a 36
  -- Questions answer row.
  RETURN QUERY
  SELECT
    CASE WHEN v_is_user_a
      THEN gsr.answer_a_submitted_at IS NOT NULL
      ELSE gsr.answer_b_submitted_at IS NOT NULL
    END
    OR EXISTS (
      SELECT 1 FROM public.mirror_round_truth t
      WHERE t.round_id = gsr.id AND t.subject_id = v_user_id
    )
    OR EXISTS (
      SELECT 1 FROM public.thirty_six_question_answers ta
      WHERE ta.round_id = gsr.id AND ta.user_id = v_user_id
        AND ta.is_removed IS NOT TRUE
    ),
    CASE WHEN v_is_user_a
      THEN gsr.answer_b_submitted_at IS NOT NULL
      ELSE gsr.answer_a_submitted_at IS NOT NULL
    END
    OR EXISTS (
      SELECT 1 FROM public.mirror_round_truth t
      WHERE t.round_id = gsr.id AND t.subject_id = v_partner
    )
    OR EXISTS (
      SELECT 1 FROM public.thirty_six_question_answers ta
      WHERE ta.round_id = gsr.id AND ta.user_id = v_partner
        AND ta.is_removed IS NOT TRUE
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
