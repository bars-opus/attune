-- paint_ball_take_turn dropped the penalty phase when it replaced
-- paint_ball_fire_shot. Two defects, both on the knockout path:
--
--   1. No penalty was rolled at all. The knockout ended the game with
--      penalty_type/penalty_prompt_snapshot NULL, so the Truth or Dare
--      forfeit the loser is supposed to face never appeared.
--   2. It set status = 'completed' on the knockout. paint_ball_resolve_penalty
--      returns early on an already-completed session, so even a queued
--      penalty could never have been resolved -- the loser was locked out.
--
-- This restores fire_shot's penalty roll verbatim (tone is an exact match,
-- the prompt is rolled once and then fixed, partner-authored preferred over
-- app_random) and leaves status alone on knockout so resolve_penalty owns
-- the transition to 'completed'.

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
  v_defender uuid;
  v_shooter_is_a boolean;
  v_existing public.game_session_rounds%ROWTYPE;
  v_defender_hid smallint;
  v_hit boolean := false;
  v_defender_lives int;
  v_knockout boolean := false;
  v_penalty_type text;
  v_penalty_source text;
  v_penalty_prompt_id uuid;
  v_penalty_snapshot text;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  IF p_hide_position IS NULL OR p_hide_position NOT BETWEEN 0 AND 2
     OR p_shot_position IS NULL OR p_shot_position NOT BETWEEN 0 AND 2 THEN
    RETURN public.paint_ball_error('INVALID_POSITION');
  END IF;

  -- The row lock plus the turn check is what makes a simultaneous
  -- double-move impossible rather than merely unlikely.
  SELECT s.* INTO v_session FROM public.game_sessions s
  WHERE s.id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;

  IF v_rel.user_a <> v_user AND v_rel.user_b <> v_user THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  -- Idempotency before the state checks, so a retried turn that ended the
  -- game returns its result rather than SESSION_EXPIRED.
  SELECT * INTO v_existing FROM public.game_session_rounds
  WHERE session_id = p_session_id AND round_number = p_round_number;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'lives_a', v_session.lives_a,
      'lives_b', v_session.lives_b,
      'shot_result', v_existing.shot_result,
      'life_lost', COALESCE(v_existing.life_lost, false),
      'round_number', p_round_number,
      'current_turn_user_id', v_session.current_turn_user_id,
      'knockout', v_session.winner_user_id IS NOT NULL,
      'penalty_type', COALESCE(v_penalty_type, v_session.penalty_type),
      'penalty_prompt_snapshot',
      COALESCE(v_penalty_snapshot, v_session.penalty_prompt_snapshot)
    );
  END IF;

  IF v_session.status <> 'active' THEN
    RETURN public.paint_ball_error('SESSION_EXPIRED');
  END IF;

  IF v_session.current_turn_user_id IS DISTINCT FROM v_user THEN
    RETURN public.paint_ball_error('NOT_YOUR_TURN');
  END IF;

  v_shooter_is_a := (v_rel.user_a = v_user);
  v_defender := CASE WHEN v_shooter_is_a THEN v_rel.user_b ELSE v_rel.user_a END;

  -- Where the defender hid on THEIR last turn. Null on the opening move,
  -- when nobody has hidden yet -- the first shot cannot hit, and the game
  -- properly begins once both have taken cover.
  SELECT r.hide_position INTO v_defender_hid
  FROM public.game_session_rounds r
  WHERE r.session_id = p_session_id
    AND r.active_partner_id = v_defender
    AND r.hide_position IS NOT NULL
  ORDER BY r.round_number DESC
  LIMIT 1;

  v_hit := v_defender_hid IS NOT NULL AND v_defender_hid = p_shot_position;

  INSERT INTO public.game_session_rounds (
    session_id, round_number, active_partner_id,
    hide_position, shot_position, shot_result, life_lost
  )
  VALUES (
    p_session_id, p_round_number, v_user,
    p_hide_position, p_shot_position,
    CASE
      WHEN v_defender_hid IS NULL THEN 'opening'
      WHEN v_hit THEN 'hit'
      ELSE 'miss'
    END,
    v_hit
  );

  -- The lives > 0 guard makes a below-zero life structurally impossible
  -- even under a replayed or racing call.
  IF v_hit THEN
    IF v_shooter_is_a THEN
      UPDATE public.game_sessions SET lives_b = lives_b - 1
       WHERE id = p_session_id AND lives_b > 0;
    ELSE
      UPDATE public.game_sessions SET lives_a = lives_a - 1
       WHERE id = p_session_id AND lives_a > 0;
    END IF;
  END IF;

  SELECT CASE WHEN v_shooter_is_a THEN lives_b ELSE lives_a END
    INTO v_defender_lives
  FROM public.game_sessions WHERE id = p_session_id;

  v_knockout := v_defender_lives <= 0;

  IF v_knockout THEN
    -- §10.4: the roll happens ONCE and the prompt is then fixed -- reopening
    -- the penalty screen must show the same prompt, never a reroll.
    v_penalty_type := CASE WHEN random() < 0.5 THEN 'truth' ELSE 'dare' END;

    IF v_session.penalty_allow_partner_authored THEN
      -- Tone is an EXACT match, never a range: it is the couple's consent
      -- boundary, so a Playful session must not surface a Spicy prompt.
      SELECT id, content INTO v_penalty_prompt_id, v_penalty_snapshot
      FROM public.custom_truth_or_dare_questions
      WHERE user_id = v_user
        AND question_type = v_penalty_type
        AND tone = v_session.tone
        AND is_private = false
        AND hidden_for_review = false
      ORDER BY random()
      LIMIT 1;
    END IF;

    IF v_penalty_prompt_id IS NOT NULL THEN
      v_penalty_source := 'partner_authored';
    ELSE
      v_penalty_source := 'app_random';

      SELECT q.id, q.question_text INTO v_penalty_prompt_id, v_penalty_snapshot
      FROM public.game_questions q
      WHERE q.game_type = 'truth_or_dare'
        AND q.question_subtype = v_penalty_type
        AND q.tone = v_session.tone
        AND q.active = true
        AND NOT EXISTS (
          SELECT 1 FROM public.game_questions_seen s
          WHERE s.relationship_id = v_session.relationship_id
            AND s.question_id = q.id
        )
      ORDER BY random()
      LIMIT 1;

      IF v_penalty_prompt_id IS NOT NULL THEN
        INSERT INTO public.game_questions_seen
          (relationship_id, question_id, game_type)
        VALUES
          (v_session.relationship_id, v_penalty_prompt_id, 'truth_or_dare')
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;

    -- status stays 'active' and completed_at stays NULL: the game is
    -- entering the penalty phase, not finishing. paint_ball_resolve_penalty
    -- is what sets status = 'completed', and it returns early on an
    -- already-completed session -- so marking it done here would lock the
    -- loser out of the penalty they just earned.
    UPDATE public.game_sessions
       SET current_turn_user_id = NULL,
           winner_user_id = v_user,
           penalty_type = v_penalty_type,
           penalty_source = v_penalty_source,
           penalty_prompt_id = v_penalty_prompt_id,
           penalty_prompt_snapshot = v_penalty_snapshot,
           penalty_status = 'pending'
     WHERE id = p_session_id;
  ELSE
    UPDATE public.game_sessions
       SET current_turn_user_id = v_defender
     WHERE id = p_session_id;
  END IF;

  RETURN jsonb_build_object(
    'lives_a', (SELECT lives_a FROM public.game_sessions WHERE id = p_session_id),
    'lives_b', (SELECT lives_b FROM public.game_sessions WHERE id = p_session_id),
    'shot_result', CASE
      WHEN v_defender_hid IS NULL THEN 'opening'
      WHEN v_hit THEN 'hit' ELSE 'miss' END,
    'life_lost', v_hit,
    -- The defender's position is returned to the SHOOTER after the fact,
    -- which is what makes the next guess informed rather than a coin
    -- flip: you learn where they were, and decide what that tells you.
    'defender_was_at', v_defender_hid,
    'round_number', p_round_number,
    'current_turn_user_id', CASE WHEN v_knockout THEN NULL ELSE v_defender END,
    'knockout', v_knockout,
    -- Carried on the knockout response so the client can show the forfeit
    -- card straight away rather than refetching the session to find it.
    'penalty_type', v_penalty_type,
    'penalty_source', v_penalty_source,
    'penalty_prompt_snapshot', v_penalty_snapshot
  );
END;
$$;
