-- Paint Ball becomes hidden-information prediction, not timing.
--
-- The game was a timing tap: a marker swept, you tapped inside a window,
-- and the CLIENT decided whether that was a hit. Two problems with that
-- in this app. It is a reflex game, which is a poor fit for a couples
-- app -- it measures reaction time, not how well you know each other.
-- And the hit was trust-the-client, which the spec accepted only because
-- outcomes were socially worthless.
--
-- Now each turn is one asynchronous move, like every other game here:
-- you pick where to HIDE and where to SHOOT, and the server decides
-- whether your shot found where your partner was actually hiding. The
-- skill is prediction -- guessing your partner -- which is the thing this
-- app is for. And the outcome is server-derived, so trust-the-client
-- disappears as a question rather than being argued about.

ALTER TABLE public.game_session_rounds
  ADD COLUMN IF NOT EXISTS hide_position smallint,
  ADD COLUMN IF NOT EXISTS shot_position smallint;

-- Three positions, matching the three cover nodes already drawn per side.
-- Enough for a real guess; few enough to stay readable on a phone.
ALTER TABLE public.game_session_rounds
  DROP CONSTRAINT IF EXISTS game_session_rounds_positions_range;
ALTER TABLE public.game_session_rounds
  ADD CONSTRAINT game_session_rounds_positions_range
  CHECK (
    (hide_position IS NULL OR hide_position BETWEEN 0 AND 2)
    AND (shot_position IS NULL OR shot_position BETWEEN 0 AND 2)
  );

COMMENT ON COLUMN public.game_session_rounds.hide_position IS
  'Where the mover hid this turn (0-2). Their partner shoots at this on '
  'the FOLLOWING turn, which is what makes the guess a prediction rather '
  'than a coin flip.';

COMMENT ON COLUMN public.game_session_rounds.shot_position IS
  'Where the mover shot (0-2), resolved against the partner''s hide '
  'position from the previous round.';

-- The opening move is neither a hit nor a miss.
--
-- On the very first turn nobody has hidden yet, so the shot had nothing
-- to find. Recording it as 'miss' would be a lie the reveal screen then
-- has to tell -- "you missed" for a shot that could not have landed --
-- so it gets its own value.
ALTER TABLE public.game_session_rounds
  DROP CONSTRAINT IF EXISTS game_session_rounds_shot_result_check;

ALTER TABLE public.game_session_rounds
  ADD CONSTRAINT game_session_rounds_shot_result_check
  CHECK (shot_result IS NULL OR shot_result = ANY (ARRAY['hit', 'miss', 'opening']));

-- One turn: hide, shoot, and resolve.
--
-- Replaces paint_ball_fire_shot's p_hit boolean. The server compares the
-- shot to where the partner actually hid, so the client cannot report a
-- hit it did not earn.
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
      'penalty_type', v_session.penalty_type,
      'penalty_prompt_snapshot', v_session.penalty_prompt_snapshot
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

  UPDATE public.game_sessions
  SET current_turn_user_id = CASE WHEN v_knockout THEN NULL ELSE v_defender END,
      winner_user_id = CASE WHEN v_knockout THEN v_user ELSE winner_user_id END,
      status = CASE WHEN v_knockout THEN 'completed' ELSE status END,
      completed_at = CASE WHEN v_knockout THEN now() ELSE completed_at END
  WHERE id = p_session_id;

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
    'knockout', v_knockout
  );
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_take_turn(uuid, int, smallint, smallint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.paint_ball_take_turn(uuid, int, smallint, smallint)
  TO authenticated;
