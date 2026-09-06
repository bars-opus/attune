-- The player who CLOSED a round opens the next one.
--
-- v3 handed the next round back to the round's opener, which made the
-- turn order alternate per round: A opens, B closes, A opens again. From
-- B's seat that reads as playing once and then waiting twice.
--
-- The rhythm should be: you play, the round resolves in front of you, and
-- you immediately open the next one -- then it goes to your partner. So a
-- player's visit to the game is always "watch what happened, then move",
-- which is one coherent turn rather than two disconnected halves.
--
-- Concretely, with A opening round 1:
--   round 1: A opens, B closes  -> B watches the replay, B opens round 2
--   round 2: B opens, A closes  -> A watches the replay, A opens round 3
--
-- Each player alternates between closing a round (which resolves it) and
-- opening the next, and both of those happen in the same visit.

CREATE OR REPLACE FUNCTION public.paint_ball_take_turn(
  p_session_id uuid,
  p_round_number int,
  p_hide_position smallint,
  p_shot_position smallint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
  v_partner uuid;
  v_existing public.game_session_rounds%ROWTYPE;
  v_other public.game_session_rounds%ROWTYPE;
  v_mine public.game_session_rounds%ROWTYPE;
  v_hit_mine boolean;
  v_hit_other boolean;
  v_user_is_a boolean;
  v_lives_a int;
  v_lives_b int;
  v_out_a int;
  v_out_b int;
  v_double boolean := false;
  v_winner uuid;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  IF p_hide_position IS NULL OR p_shot_position IS NULL
     OR p_hide_position NOT BETWEEN 0 AND 2
     OR p_shot_position NOT BETWEEN 0 AND 2 THEN
    RETURN public.paint_ball_error('INVALID_INPUT');
  END IF;

  SELECT * INTO v_session FROM public.game_sessions
  WHERE id = p_session_id AND game_type = 'paint_ball'
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.paint_ball_error('NOT_FOUND');
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;
  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  v_user_is_a := v_rel.user_a = v_user;
  v_partner := CASE WHEN v_user_is_a THEN v_rel.user_b ELSE v_rel.user_a END;

  SELECT * INTO v_existing FROM public.game_session_rounds
  WHERE session_id = p_session_id
    AND round_number = p_round_number
    AND active_partner_id = v_user;
  IF FOUND THEN
    RETURN public.paint_ball_round_payload(p_session_id, p_round_number, v_user);
  END IF;

  IF v_session.status <> 'active' THEN
    RETURN public.paint_ball_error('SESSION_EXPIRED');
  END IF;

  IF v_session.current_turn_user_id IS DISTINCT FROM v_user THEN
    RETURN public.paint_ball_error('NOT_YOUR_TURN');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.game_session_rounds r
    WHERE r.session_id = p_session_id
      AND r.active_partner_id = v_user
      AND r.created_at > now() - interval '2 seconds'
  ) THEN
    RETURN public.paint_ball_error('RATE_LIMITED');
  END IF;

  IF p_round_number <> GREATEST(COALESCE(v_session.current_round, 1), 1) THEN
    RETURN public.paint_ball_error('INVALID_INPUT');
  END IF;

  INSERT INTO public.game_session_rounds (
    session_id, round_number, active_partner_id,
    hide_position, shot_position, game_type
  )
  VALUES (
    p_session_id, p_round_number, v_user,
    p_hide_position, p_shot_position, 'paint_ball'
  );

  SELECT * INTO v_other FROM public.game_session_rounds
  WHERE session_id = p_session_id
    AND round_number = p_round_number
    AND active_partner_id = v_partner;

  IF NOT FOUND THEN
    UPDATE public.game_sessions
       SET current_turn_user_id = v_partner
     WHERE id = p_session_id;

    RETURN jsonb_build_object(
      'round_state', 'awaiting_partner',
      'round_number', p_round_number,
      'current_turn_user_id', v_partner,
      'lives_a', v_session.lives_a,
      'lives_b', v_session.lives_b,
      'knockout', false,
      'double_knockout', false
    );
  END IF;

  SELECT * INTO v_mine FROM public.game_session_rounds
  WHERE session_id = p_session_id
    AND round_number = p_round_number
    AND active_partner_id = v_user;

  v_hit_mine  := v_mine.shot_position  = v_other.hide_position;
  v_hit_other := v_other.shot_position = v_mine.hide_position;

  UPDATE public.game_session_rounds
     SET shot_result = CASE WHEN v_hit_mine THEN 'hit' ELSE 'miss' END,
         life_lost = v_hit_mine,
         resolved_at = now()
   WHERE session_id = p_session_id
     AND round_number = p_round_number
     AND active_partner_id = v_user;

  UPDATE public.game_session_rounds
     SET shot_result = CASE WHEN v_hit_other THEN 'hit' ELSE 'miss' END,
         life_lost = v_hit_other,
         resolved_at = now()
   WHERE session_id = p_session_id
     AND round_number = p_round_number
     AND active_partner_id = v_partner;

  IF v_hit_mine THEN
    IF v_user_is_a THEN
      UPDATE public.game_sessions SET lives_b = lives_b - 1
       WHERE id = p_session_id AND lives_b > 0;
    ELSE
      UPDATE public.game_sessions SET lives_a = lives_a - 1
       WHERE id = p_session_id AND lives_a > 0;
    END IF;
  END IF;

  IF v_hit_other THEN
    IF v_user_is_a THEN
      UPDATE public.game_sessions SET lives_a = lives_a - 1
       WHERE id = p_session_id AND lives_a > 0;
    ELSE
      UPDATE public.game_sessions SET lives_b = lives_b - 1
       WHERE id = p_session_id AND lives_b > 0;
    END IF;
  END IF;

  SELECT lives_a, lives_b INTO v_lives_a, v_lives_b
  FROM public.game_sessions WHERE id = p_session_id;

  v_out_a := v_lives_a;
  v_out_b := v_lives_b;

  IF v_out_a <= 0 AND v_out_b <= 0 THEN
    v_double := true;
    PERFORM public.paint_ball_roll_penalty(p_session_id, v_rel.user_a);
    PERFORM public.paint_ball_roll_penalty(p_session_id, v_rel.user_b);
    UPDATE public.game_sessions
       SET current_turn_user_id = NULL,
           winner_user_id = NULL,
           penalty_status = 'pending'
     WHERE id = p_session_id;
  ELSIF v_out_a <= 0 OR v_out_b <= 0 THEN
    v_winner := CASE WHEN v_out_a <= 0 THEN v_rel.user_b ELSE v_rel.user_a END;
    PERFORM public.paint_ball_roll_penalty(
      p_session_id,
      CASE WHEN v_out_a <= 0 THEN v_rel.user_a ELSE v_rel.user_b END);
    UPDATE public.game_sessions
       SET current_turn_user_id = NULL,
           winner_user_id = v_winner,
           penalty_status = 'pending'
     WHERE id = p_session_id;
  ELSE
    -- THE CHANGE: the CLOSER opens the next round, not the opener.
    --
    -- The closer is the one standing here watching the replay, so handing
    -- them the next round keeps a single visit whole: see what happened,
    -- then move. Giving it back to the opener made the closer play once
    -- and then wait twice.
    UPDATE public.game_sessions
       SET current_turn_user_id = v_user,
           current_round = GREATEST(COALESCE(current_round, 1), 1) + 1
     WHERE id = p_session_id;
  END IF;

  RETURN public.paint_ball_round_payload(p_session_id, p_round_number, v_user);
END;
$$;
