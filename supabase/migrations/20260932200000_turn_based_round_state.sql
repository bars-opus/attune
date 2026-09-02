-- Whose move it is, for games that take turns.
--
-- session_game_round_state derives "whose move" from who has filled an
-- answer slot. That is right for games where both partners answer the
-- same round, and wrong for Truth or Dare, which takes strict turns: one
-- player acts per round, named by active_partner_id, and the answer slots
-- are never used at all.
--
-- So its card read the two empty slots as "neither has answered" and fell
-- back to a round count, never saying whose turn it was.
--
-- When a round names an active partner, that IS the answer: it is their
-- move, and by construction not the other player's.
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

  -- A turn-based game: the newest round names whose move it is.
  --
  -- Newest rather than oldest-incomplete, because these games add a round
  -- per turn instead of filling one in -- the latest round IS the current
  -- state, and earlier ones are history.
  --
  -- Restricted by GAME TYPE, not merely by the column being set. Mirror
  -- also fills active_partner_id -- it names the round's SUBJECT -- but
  -- there the active partner is the one who ANSWERS, not the one being
  -- waited on. Treating the column alone as a turn inverted Mirror
  -- completely: a subject who had just written their truth read as
  -- unanswered.
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
    -- Their move means they have NOT acted, and the other player has --
    -- which is what put the turn on them.
    RETURN QUERY SELECT (v_active <> v_user_id), (v_active = v_user_id);
    RETURN;
  END IF;

  -- Everything else: both partners answer the same round, so "whose
  -- move" comes from who has done their part.
  RETURN QUERY
  SELECT
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
