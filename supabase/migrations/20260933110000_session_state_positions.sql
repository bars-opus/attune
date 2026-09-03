-- The session state must carry shot positions.
--
-- get_paint_ball_session_state returns each round's result but not WHERE
-- the shot landed or who took it -- so the field had nothing to paint
-- with. A reopened game would show a clean arena no matter how many
-- rounds had been fired, which is exactly the accumulated record the
-- field exists to show.
--
-- Rebuilt rather than patched: the function is short, and a partial
-- replacement of one json_build_object is harder to review than the
-- whole thing.
CREATE OR REPLACE FUNCTION public.get_paint_ball_session_state(
  p_session_id uuid
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
  v_rounds json;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.paint_ball_error('FORBIDDEN')::json;
  END IF;

  SELECT * INTO v_session FROM public.game_sessions WHERE id = p_session_id;
  IF NOT FOUND THEN
    RETURN public.paint_ball_error('FORBIDDEN')::json;
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;

  IF v_rel.user_a <> v_user AND v_rel.user_b <> v_user THEN
    RETURN public.paint_ball_error('FORBIDDEN')::json;
  END IF;

  SELECT COALESCE(
    json_agg(
      json_build_object(
        'round_number', r.round_number,
        'shot_result', r.shot_result,
        'life_lost', r.life_lost,
        'created_at', r.created_at,
        -- Where the shot landed, and whose it was, so the field can
        -- paint the match rather than starting clean each time.
        'shot_position', r.shot_position,
        'active_partner_id', r.active_partner_id
        -- hide_position is deliberately NOT returned. It is the hidden
        -- information the game turns on: a client that could read every
        -- past hiding place could see the current one too, and the guess
        -- would stop being a guess.
      )
      ORDER BY r.round_number
    ),
    '[]'::json
  )
  INTO v_rounds
  FROM public.game_session_rounds r
  WHERE r.session_id = p_session_id;

  RETURN json_build_object(
    'session_id', v_session.id,
    'relationship_id', v_session.relationship_id,
    'initiator_id', v_session.initiator_id,
    'status', v_session.status,
    'tone', v_session.tone,
    'lives_a', v_session.lives_a,
    'lives_b', v_session.lives_b,
    'current_round', COALESCE(v_session.current_round, 1),
    'total_rounds_completed', COALESCE(v_session.total_rounds_completed, 0),
    'current_turn_user_id', v_session.current_turn_user_id,
    'winner_user_id', v_session.winner_user_id,
    'penalty_type', v_session.penalty_type,
    'penalty_source', v_session.penalty_source,
    'penalty_status', v_session.penalty_status,
    'penalty_prompt_snapshot', v_session.penalty_prompt_snapshot,
    'penalty_allow_partner_authored',
      COALESCE(v_session.penalty_allow_partner_authored, false),
    'user_a', v_rel.user_a,
    'user_b', v_rel.user_b,
    'rounds', v_rounds
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_paint_ball_session_state(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_paint_ball_session_state(uuid)
  TO authenticated;
