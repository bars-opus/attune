-- A bounce that then hits a snake must record BOTH facts.
--
-- 97 + 5 bounces to 98, which is a snake head, so it slides to 78. The
-- single movement_kind could only hold one of those, and the feature
-- overwrote the bounce -- so the animation walked 97 to 98 directly and
-- never showed the token reach 100 and come back. The most dramatic
-- moment the game has, silently dropped.
--
-- did_bounce is separate because the two are independent: a turn can
-- bounce, or hit a feature, or do both in that order.
ALTER TABLE public.game_session_rounds
  ADD COLUMN IF NOT EXISTS did_bounce boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.snakes_resolve_move(
  p_from smallint,
  p_roll smallint,
  p_features jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_target int;
  v_rolled int;
  v_dest int;
  v_kind text := 'normal';
  v_bounced boolean := false;
BEGIN
  v_target := p_from + p_roll;

  IF v_target > 100 THEN
    v_rolled := 100 - (v_target - 100);
    v_bounced := true;
    v_kind := 'bounce';
  ELSE
    v_rolled := v_target;
  END IF;

  v_dest := v_rolled;

  IF p_features->'ladders' ? v_rolled::text THEN
    v_dest := (p_features->'ladders'->>v_rolled::text)::int;
    v_kind := 'ladder';
  ELSIF p_features->'snakes' ? v_rolled::text THEN
    v_dest := (p_features->'snakes'->>v_rolled::text)::int;
    v_kind := 'snake';
  END IF;

  RETURN jsonb_build_object(
    'rolled_to', v_rolled,
    'moved_to', v_dest,
    'movement_kind', v_kind,
    -- Kept alongside movement_kind rather than folded into it: the two
    -- describe different halves of the same turn, and the animation
    -- needs both to play it honestly.
    'did_bounce', v_bounced
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.snakes_roll_die(
  p_session_id uuid,
  p_round_number int
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
  v_existing public.game_session_rounds%ROWTYPE;
  v_partner uuid;
  v_is_a boolean;
  v_from smallint;
  v_roll smallint;
  v_features jsonb;
  v_move jsonb;
  v_to smallint;
  v_won boolean;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.snakes_error('UNAUTHORIZED');
  END IF;

  IF p_round_number IS NULL OR p_round_number < 1
     OR p_round_number > 1000 THEN
    RETURN public.snakes_error('INVALID_INPUT');
  END IF;

  SELECT * INTO v_session FROM public.game_sessions
  WHERE id = p_session_id AND game_type = 'snakes_and_ladders'
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.snakes_error('NOT_FOUND');
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;
  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.snakes_error('FORBIDDEN');
  END IF;

  -- A relationship that has ended or been archived takes its games with
  -- it. Paint Ball has a trigger for this; Snakes checks directly, so a
  -- former partner cannot keep playing until cron notices.
  IF v_rel.status <> 'active' OR v_rel.chat_archived_at IS NOT NULL THEN
    RETURN public.snakes_error('SESSION_EXPIRED');
  END IF;

  v_is_a := v_rel.user_a = v_user;
  v_partner := CASE WHEN v_is_a THEN v_rel.user_b ELSE v_rel.user_a END;

  SELECT * INTO v_existing FROM public.game_session_rounds
  WHERE session_id = p_session_id
    AND round_number = p_round_number
    AND active_partner_id = v_user;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok', true, 'existing', true,
      'die_roll', v_existing.die_roll,
      'moved_from', v_existing.moved_from,
      'rolled_to', v_existing.rolled_to,
      'moved_to', v_existing.moved_to,
      'movement_kind', v_existing.movement_kind,
      'did_bounce', v_existing.did_bounce,
      'round_number', p_round_number,
      'position_a', v_session.board_position_a,
      'position_b', v_session.board_position_b,
      'current_turn_user_id', v_session.current_turn_user_id,
      'winner_user_id', v_session.winner_user_id
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.game_session_rounds r
    WHERE r.session_id = p_session_id
      AND r.active_partner_id = v_user
      AND r.created_at > now() - interval '1 second'
  ) THEN
    RETURN public.snakes_error('RATE_LIMITED');
  END IF;

  IF v_session.status = 'completed' THEN
    RETURN public.snakes_error('GAME_OVER');
  END IF;
  IF v_session.status <> 'active' THEN
    RETURN public.snakes_error('SESSION_EXPIRED');
  END IF;
  IF v_session.current_turn_user_id IS DISTINCT FROM v_user THEN
    RETURN public.snakes_error('NOT_YOUR_TURN');
  END IF;
  IF p_round_number <> GREATEST(COALESCE(v_session.current_round, 1), 1) THEN
    RETURN public.snakes_error('INVALID_INPUT');
  END IF;

  SELECT features INTO v_features FROM public.snakes_boards
  WHERE version = COALESCE(v_session.board_version, 'v1');
  IF v_features IS NULL THEN
    RETURN public.snakes_error('NOT_FOUND');
  END IF;

  v_from := CASE WHEN v_is_a
                 THEN v_session.board_position_a
                 ELSE v_session.board_position_b END;

  v_roll := floor(random() * 6)::smallint + 1;
  v_move := public.snakes_resolve_move(v_from, v_roll, v_features);
  v_to := (v_move->>'moved_to')::smallint;

  INSERT INTO public.game_session_rounds (
    session_id, round_number, active_partner_id, game_type,
    die_roll, moved_from, rolled_to, moved_to, movement_kind, did_bounce
  )
  VALUES (
    p_session_id, p_round_number, v_user, 'snakes_and_ladders',
    v_roll, v_from, (v_move->>'rolled_to')::smallint, v_to,
    v_move->>'movement_kind', (v_move->>'did_bounce')::boolean
  );

  v_won := v_to = 100;

  IF v_is_a THEN
    UPDATE public.game_sessions SET board_position_a = v_to
     WHERE id = p_session_id;
  ELSE
    UPDATE public.game_sessions SET board_position_b = v_to
     WHERE id = p_session_id;
  END IF;

  IF v_won THEN
    UPDATE public.game_sessions
       SET status = 'completed', completed_at = now(),
           winner_user_id = v_user, current_turn_user_id = NULL,
           total_rounds_completed = p_round_number
     WHERE id = p_session_id;
  ELSE
    UPDATE public.game_sessions
       SET current_turn_user_id = v_partner,
           current_round = p_round_number + 1,
           total_rounds_completed = p_round_number
     WHERE id = p_session_id;
  END IF;

  SELECT * INTO v_session FROM public.game_sessions WHERE id = p_session_id;

  RETURN jsonb_build_object(
    'ok', true, 'existing', false,
    'die_roll', v_roll,
    'moved_from', v_from,
    'rolled_to', (v_move->>'rolled_to')::smallint,
    'moved_to', v_to,
    'movement_kind', v_move->>'movement_kind',
    'did_bounce', (v_move->>'did_bounce')::boolean,
    'round_number', p_round_number,
    'position_a', v_session.board_position_a,
    'position_b', v_session.board_position_b,
    'current_turn_user_id', v_session.current_turn_user_id,
    'winner_user_id', v_session.winner_user_id,
    'won', v_won
  );
END;
$$;

-- The state payload carries it too, for a returning player's replay.
CREATE OR REPLACE FUNCTION public.get_snakes_session_state(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
  v_rounds jsonb;
  v_features jsonb;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.snakes_error('UNAUTHORIZED');
  END IF;

  SELECT * INTO v_session FROM public.game_sessions
  WHERE id = p_session_id AND game_type = 'snakes_and_ladders';
  IF NOT FOUND THEN
    RETURN public.snakes_error('NOT_FOUND');
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;
  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.snakes_error('FORBIDDEN');
  END IF;

  SELECT features INTO v_features FROM public.snakes_boards
  WHERE version = COALESCE(v_session.board_version, 'v1');

  SELECT COALESCE(
    jsonb_agg(row ORDER BY (row->>'round_number')::int), '[]'::jsonb)
    INTO v_rounds
  FROM (
    SELECT jsonb_build_object(
      'round_number', r.round_number,
      'active_partner_id', r.active_partner_id,
      'die_roll', r.die_roll,
      'moved_from', r.moved_from,
      'rolled_to', r.rolled_to,
      'moved_to', r.moved_to,
      'movement_kind', r.movement_kind,
      'did_bounce', r.did_bounce,
      'created_at', r.created_at
    ) AS row
    FROM public.game_session_rounds r
    WHERE r.session_id = p_session_id
    ORDER BY r.round_number DESC
    LIMIT 20
  ) recent;

  RETURN jsonb_build_object(
    'session_id', v_session.id,
    'relationship_id', v_session.relationship_id,
    'initiator_id', v_session.initiator_id,
    'status', v_session.status,
    'user_a', v_rel.user_a,
    'user_b', v_rel.user_b,
    'position_a', v_session.board_position_a,
    'position_b', v_session.board_position_b,
    'board_version', COALESCE(v_session.board_version, 'v1'),
    'board', v_features,
    'current_round', GREATEST(COALESCE(v_session.current_round, 1), 1),
    'current_turn_user_id', v_session.current_turn_user_id,
    'winner_user_id', v_session.winner_user_id,
    'created_at', v_session.created_at,
    'rounds', v_rounds
  );
END;
$$;
