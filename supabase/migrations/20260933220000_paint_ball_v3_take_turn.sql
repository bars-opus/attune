-- Paint Ball v3: simultaneous rounds (spec §5.5, §10.3).
--
-- A round is an exchange between BOTH players. The opener's half records and
-- returns nothing; the closer's half resolves both shots against each other,
-- each checked against the hide the OTHER player chose in that same round.
--
-- Why same-round rather than the previous round (v2): you are predicting
-- where they will go, not recalling where they were. It also lets round one
-- be a real hit, which is why shot_result 'opening' is gone.
--
-- Symmetry: the opener's shot is locked before the closer picks a hide, but
-- the opener's HIDE is equally locked before the closer's shot. Both commit
-- blind. Neither seat has an information advantage.

-- Shared penalty roll, so a draw rolls twice through one code path rather
-- than duplicating the logic and letting the two drift apart.
CREATE OR REPLACE FUNCTION public.paint_ball_roll_penalty(
  p_session_id uuid,
  p_loser_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.game_sessions%ROWTYPE;
  v_type text;
  v_source text := 'app_random';
  v_prompt_id uuid;
  v_snapshot text;
BEGIN
  SELECT * INTO v_session FROM public.game_sessions WHERE id = p_session_id;

  -- Rolled ONCE and then fixed: reopening the penalty screen must show the
  -- same prompt, never a reroll.
  IF EXISTS (SELECT 1 FROM public.paint_ball_penalties
             WHERE session_id = p_session_id AND user_id = p_loser_id) THEN
    RETURN;
  END IF;

  v_type := CASE WHEN random() < 0.5 THEN 'truth' ELSE 'dare' END;

  IF v_session.penalty_allow_partner_authored THEN
    -- Tone is an EXACT match, never a range: it is the couple's consent
    -- boundary, so a Playful session must not surface a Spicy prompt.
    SELECT id, content INTO v_prompt_id, v_snapshot
    FROM public.custom_truth_or_dare_questions
    WHERE user_id <> p_loser_id
      AND question_type = v_type
      AND tone = v_session.tone
      AND is_private = false
      AND hidden_for_review = false
    ORDER BY random()
    LIMIT 1;
  END IF;

  IF v_prompt_id IS NOT NULL THEN
    v_source := 'partner_authored';
  ELSE
    SELECT q.id, q.question_text INTO v_prompt_id, v_snapshot
    FROM public.game_questions q
    WHERE q.game_type = 'truth_or_dare'
      AND q.question_subtype = v_type
      AND q.tone = v_session.tone
      AND q.active = true
      AND NOT EXISTS (
        SELECT 1 FROM public.game_questions_seen s
        WHERE s.relationship_id = v_session.relationship_id
          AND s.question_id = q.id
      )
    ORDER BY random()
    LIMIT 1;

    -- Every prompt of this type and tone has been seen: reuse rather than
    -- leave the loser with no forfeit at all.
    IF v_prompt_id IS NULL THEN
      SELECT q.id, q.question_text INTO v_prompt_id, v_snapshot
      FROM public.game_questions q
      WHERE q.game_type = 'truth_or_dare'
        AND q.question_subtype = v_type
        AND q.tone = v_session.tone
        AND q.active = true
      ORDER BY random()
      LIMIT 1;
    END IF;

    IF v_prompt_id IS NOT NULL THEN
      INSERT INTO public.game_questions_seen
        (relationship_id, question_id, game_type)
      VALUES (v_session.relationship_id, v_prompt_id, 'truth_or_dare')
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  INSERT INTO public.paint_ball_penalties (
    session_id, user_id, penalty_type, penalty_source,
    penalty_prompt_id, penalty_prompt_snapshot
  )
  VALUES (
    p_session_id, p_loser_id, v_type, v_source,
    v_prompt_id, COALESCE(v_snapshot, '(prompt unavailable)')
  )
  ON CONFLICT (session_id, user_id) DO NOTHING;
END;
$$;

-- The round payload, and the ONE place the disclosure boundary lives.
--
-- hide_position is returned only for a round whose resolved_at is set. Before
-- that it is live information -- the closer could read the opener's position
-- and the prediction would stop being one. After, it is history, and showing
-- it is what the replay is made of.
--
-- Both take_turn and get_paint_ball_session_state route through here so the
-- rule cannot be enforced in one and forgotten in the other.
CREATE OR REPLACE FUNCTION public.paint_ball_round_payload(
  p_session_id uuid,
  p_round_number int,
  p_viewer uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
  v_opener public.game_session_rounds%ROWTYPE;
  v_closer public.game_session_rounds%ROWTYPE;
  v_resolved boolean;
  v_penalties jsonb;
BEGIN
  SELECT * INTO v_session FROM public.game_sessions WHERE id = p_session_id;
  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;

  -- The opener is whoever went first this round.
  SELECT * INTO v_opener FROM public.game_session_rounds
  WHERE session_id = p_session_id AND round_number = p_round_number
  ORDER BY created_at, active_partner_id
  LIMIT 1;

  SELECT * INTO v_closer FROM public.game_session_rounds
  WHERE session_id = p_session_id AND round_number = p_round_number
    AND active_partner_id <> v_opener.active_partner_id
  LIMIT 1;

  v_resolved := v_opener.resolved_at IS NOT NULL;

  IF NOT v_resolved THEN
    -- Half-complete: reveal nothing at all, not even the viewer's own
    -- choices echoed back, since the client already holds those.
    RETURN jsonb_build_object(
      'round_state', 'awaiting_partner',
      'round_number', p_round_number,
      'current_turn_user_id', v_session.current_turn_user_id,
      'lives_a', v_session.lives_a,
      'lives_b', v_session.lives_b,
      'knockout', false,
      'double_knockout', false
    );
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'user_id', p.user_id,
    'penalty_type', p.penalty_type,
    'penalty_source', p.penalty_source,
    'penalty_status', p.penalty_status,
    'penalty_prompt_snapshot', p.penalty_prompt_snapshot
  )), '[]'::jsonb)
  INTO v_penalties
  FROM public.paint_ball_penalties p
  WHERE p.session_id = p_session_id;

  RETURN jsonb_build_object(
    'round_state', 'resolved',
    'round_number', p_round_number,
    'lives_a', v_session.lives_a,
    'lives_b', v_session.lives_b,
    'current_turn_user_id', v_session.current_turn_user_id,
    'opener', jsonb_build_object(
      'user_id', v_opener.active_partner_id,
      'hide_position', v_opener.hide_position,
      'shot_position', v_opener.shot_position,
      'shot_result', v_opener.shot_result
    ),
    'closer', jsonb_build_object(
      'user_id', v_closer.active_partner_id,
      'hide_position', v_closer.hide_position,
      'shot_position', v_closer.shot_position,
      'shot_result', v_closer.shot_result
    ),
    'knockout', v_session.penalty_status = 'pending',
    'double_knockout', (
      SELECT count(*) > 1 FROM public.paint_ball_penalties
      WHERE session_id = p_session_id
    ),
    'winner_user_id', v_session.winner_user_id,
    'penalties', v_penalties
  );
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_round_payload(uuid, int, uuid)
  FROM PUBLIC, anon, authenticated;

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

  -- Idempotency BEFORE the state checks, so a retried half that ended the
  -- game returns its result rather than SESSION_EXPIRED.
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

  -- Retained from 20260933190000: a burst of taps must not spend several
  -- rounds in a second. Checked BEFORE the round-number guard, so a player
  -- hammering the button is told to wait rather than told their input is
  -- invalid -- the latter is both wrong and unactionable.
  IF EXISTS (
    SELECT 1 FROM public.game_session_rounds r
    WHERE r.session_id = p_session_id
      AND r.active_partner_id = v_user
      AND r.created_at > now() - interval '2 seconds'
  ) THEN
    RETURN public.paint_ball_error('RATE_LIMITED');
  END IF;

  -- Retained from 20260933190000. The shared session table historically
  -- defaulted current_round to 0; treat that legacy value as round one.
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

  -- Is the partner's half already in?
  SELECT * INTO v_other FROM public.game_session_rounds
  WHERE session_id = p_session_id
    AND round_number = p_round_number
    AND active_partner_id = v_partner;

  IF NOT FOUND THEN
    -- Opener's half. Nothing resolves, nothing is revealed, turn passes.
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

  -- Closer's half: resolve BOTH shots against the other's same-round hide.
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

  -- Each hit costs the OTHER player a life. The lives > 0 guard makes a
  -- below-zero life structurally impossible even under a racing call.
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
    -- A draw. Both forfeit; nobody wins. Awarding it on turn order would
    -- be arbitrary, and a mutual forfeit is a shared moment where a
    -- technical win is a sour one.
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
    -- status stays 'active': the game is entering the penalty phase, not
    -- finishing. paint_ball_resolve_penalty sets 'completed' and returns
    -- early on an already-completed session, so marking it done here would
    -- lock the loser out of the forfeit they just earned.
    UPDATE public.game_sessions
       SET current_turn_user_id = NULL,
           winner_user_id = v_winner,
           penalty_status = 'pending'
     WHERE id = p_session_id;
  ELSE
    -- The opener of this round opens the next one, and the round counter
    -- advances now that both halves are in -- the round-number guard above
    -- is pinned to current_round, so it must move exactly once per
    -- completed exchange, not once per half.
    UPDATE public.game_sessions
       SET current_turn_user_id = v_other.active_partner_id,
           current_round = GREATEST(COALESCE(current_round, 1), 1) + 1
     WHERE id = p_session_id;
  END IF;

  RETURN public.paint_ball_round_payload(p_session_id, p_round_number, v_user);
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_roll_penalty(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
