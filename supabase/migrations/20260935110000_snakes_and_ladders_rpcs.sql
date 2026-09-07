-- Snakes and Ladders: the server contract.
--
-- Structurally Paint Ball's turn RPC with the hard parts removed. There
-- is no hidden information here, so no disclosure boundary; no skill, so
-- no penalty; no content, so no consent or question bank.
--
-- What remains is the part that must be right: the die belongs to the
-- server. The entire content of a turn IS the die, so a client-supplied
-- roll would not be a game.

-- User-facing messages only, never internals (checklist 2.4, 5.5).
CREATE OR REPLACE FUNCTION public.snakes_error(p_code text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'error', true,
    'code', p_code,
    'message', CASE p_code
      WHEN 'UNAUTHORIZED'    THEN 'Please sign in to play games.'
      WHEN 'FORBIDDEN'       THEN 'You don''t have access to this game.'
      WHEN 'NOT_FOUND'       THEN 'Game session not found.'
      WHEN 'NOT_YOUR_TURN'   THEN 'It''s not your turn yet.'
      WHEN 'GAME_OVER'       THEN 'This game has already finished.'
      WHEN 'SESSION_EXPIRED' THEN 'This session expired. Start a new game.'
      WHEN 'RATE_LIMITED'    THEN 'Slow down a moment.'
      WHEN 'INVALID_INPUT'   THEN 'Invalid value provided.'
      ELSE 'Something went wrong. Please try again.'
    END
  );
$$;

-- ---------------------------------------------------------------------
-- Movement, as a pure function.
-- ---------------------------------------------------------------------
-- Separated so the contract test can check the exact-finish bounce and
-- every feature landing without creating a session for each case
-- (checklist 2.17: pure logic testable without I/O).
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
BEGIN
  v_target := p_from + p_roll;

  -- Exact finish. Overshooting bounces back by the excess rather than
  -- winning, which is the only tension this game contains.
  IF v_target > 100 THEN
    v_rolled := 100 - (v_target - 100);
    v_kind := 'bounce';
  ELSE
    v_rolled := v_target;
  END IF;

  v_dest := v_rolled;

  -- At most ONE feature: the board forbids chaining, so a destination is
  -- never another head.
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
    'movement_kind', v_kind
  );
END;
$$;

-- ---------------------------------------------------------------------
-- Create.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.snakes_create_session(
  p_relationship_id uuid,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session uuid;
  v_key_relationship uuid;
  v_key_game_type text;
  v_recent int;
  v_board text;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.snakes_error('UNAUTHORIZED');
  END IF;

  IF p_relationship_id IS NULL
     OR p_idempotency_key IS NULL OR btrim(p_idempotency_key) = ''
     OR char_length(p_idempotency_key) > 200 THEN
    RETURN public.snakes_error('INVALID_INPUT');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.relationships
    WHERE id = p_relationship_id
      AND status = 'active'
      AND chat_archived_at IS NULL
      AND (user_a = v_user OR user_b = v_user)
  ) THEN
    RETURN public.snakes_error('FORBIDDEN');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_relationship_id::text));

  SELECT k.session_id, s.relationship_id, s.game_type
    INTO v_session, v_key_relationship, v_key_game_type
  FROM public.session_idempotency_keys k
  JOIN public.game_sessions s ON s.id = k.session_id
  WHERE k.key = p_idempotency_key;

  IF v_session IS NOT NULL THEN
    IF v_key_relationship <> p_relationship_id THEN
      RETURN public.snakes_error('FORBIDDEN');
    END IF;
    IF v_key_game_type <> 'snakes_and_ladders' THEN
      RETURN public.snakes_error('INVALID_INPUT');
    END IF;
    RETURN jsonb_build_object('session_id', v_session, 'existing', true);
  END IF;

  SELECT id INTO v_session
  FROM public.game_sessions
  WHERE relationship_id = p_relationship_id
    AND game_type = 'snakes_and_ladders'
    AND status IN ('invited', 'active')
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_session IS NOT NULL THEN
    RETURN jsonb_build_object('session_id', v_session, 'existing', true);
  END IF;

  -- Shared initiation limiter (checklist 3.8), counting all games so a
  -- couple cannot spam invitations by rotating between them.
  SELECT count(*) INTO v_recent
  FROM public.game_sessions
  WHERE relationship_id = p_relationship_id
    AND created_at > now() - interval '1 hour';

  IF v_recent >= 5 THEN
    RETURN public.snakes_error('RATE_LIMITED');
  END IF;

  SELECT version INTO v_board
  FROM public.snakes_boards
  WHERE retired_at IS NULL
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_board IS NULL THEN
    RETURN public.snakes_error('INVALID_INPUT');
  END IF;

  INSERT INTO public.game_sessions (
    relationship_id, initiator_id, game_type, status,
    board_position_a, board_position_b, board_version,
    current_round, total_rounds, total_rounds_completed
  )
  VALUES (
    p_relationship_id, v_user, 'snakes_and_ladders', 'invited',
    0, 0, v_board, 1, 0, 0
  )
  RETURNING id INTO v_session;

  INSERT INTO public.session_idempotency_keys (key, session_id)
  VALUES (p_idempotency_key, v_session)
  ON CONFLICT (key) DO NOTHING;

  RETURN jsonb_build_object('session_id', v_session, 'existing', false);
END;
$$;

-- ---------------------------------------------------------------------
-- Accept.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.snakes_accept_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.snakes_error('UNAUTHORIZED');
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

  IF v_session.status = 'active' THEN
    RETURN jsonb_build_object('ok', true, 'existing', true);
  END IF;

  IF v_session.status <> 'invited' THEN
    RETURN public.snakes_error('SESSION_EXPIRED');
  END IF;

  -- The initiator cannot accept their own invitation.
  IF v_session.initiator_id = v_user THEN
    RETURN public.snakes_error('FORBIDDEN');
  END IF;

  -- §4.1a: the INVITEE moves first. They have the app open and their
  -- attention on it; handing the first move to the initiator would mean
  -- the game's first action happens whenever they next look.
  UPDATE public.game_sessions
     SET status = 'active',
         started_at = COALESCE(started_at, now()),
         current_turn_user_id = v_user
   WHERE id = p_session_id;

  RETURN jsonb_build_object('ok', true, 'existing', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.snakes_decline_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.snakes_error('UNAUTHORIZED');
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

  IF v_session.status IN ('abandoned', 'completed') THEN
    RETURN jsonb_build_object('ok', true, 'existing', true);
  END IF;

  UPDATE public.game_sessions
     SET status = 'abandoned', abandoned_at = now(),
         current_turn_user_id = NULL
   WHERE id = p_session_id;

  RETURN jsonb_build_object('ok', true, 'existing', false);
END;
$$;

-- ---------------------------------------------------------------------
-- The roll. The whole game.
-- ---------------------------------------------------------------------
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

  v_is_a := v_rel.user_a = v_user;
  v_partner := CASE WHEN v_is_a THEN v_rel.user_b ELSE v_rel.user_a END;

  -- IDEMPOTENCY FIRST, before every other rejection.
  --
  -- A retry arriving moments after the app was killed must return the
  -- roll that was recorded -- not RATE_LIMITED (it looks like spam) and
  -- not SESSION_EXPIRED (the roll it is retrying may have been the
  -- winning one). Either would let a player lose a turn they had
  -- already taken, or believe they could reroll a bad number by force
  -- quitting.
  SELECT * INTO v_existing FROM public.game_session_rounds
  WHERE session_id = p_session_id
    AND round_number = p_round_number
    AND active_partner_id = v_user;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok', true,
      'existing', true,
      'die_roll', v_existing.die_roll,
      'moved_from', v_existing.moved_from,
      'rolled_to', v_existing.rolled_to,
      'moved_to', v_existing.moved_to,
      'movement_kind', v_existing.movement_kind,
      'round_number', p_round_number,
      'position_a', v_session.board_position_a,
      'position_b', v_session.board_position_b,
      'current_turn_user_id', v_session.current_turn_user_id,
      'winner_user_id', v_session.winner_user_id
    );
  END IF;

  -- A burst of taps must not spend several turns in a second.
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

  -- The board this session was created on, never the newest one.
  SELECT features INTO v_features FROM public.snakes_boards
  WHERE version = COALESCE(v_session.board_version, 'v1');
  IF v_features IS NULL THEN
    RETURN public.snakes_error('NOT_FOUND');
  END IF;

  v_from := CASE WHEN v_is_a
                 THEN v_session.board_position_a
                 ELSE v_session.board_position_b END;

  -- The die is the server's. The client sends "I am rolling" and
  -- nothing else -- the entire content of a turn is this number.
  v_roll := floor(random() * 6)::smallint + 1;

  v_move := public.snakes_resolve_move(v_from, v_roll, v_features);
  v_to := (v_move->>'moved_to')::smallint;

  INSERT INTO public.game_session_rounds (
    session_id, round_number, active_partner_id, game_type,
    die_roll, moved_from, rolled_to, moved_to, movement_kind
  )
  VALUES (
    p_session_id, p_round_number, v_user, 'snakes_and_ladders',
    v_roll, v_from, (v_move->>'rolled_to')::smallint, v_to,
    v_move->>'movement_kind'
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
       SET status = 'completed',
           completed_at = now(),
           winner_user_id = v_user,
           current_turn_user_id = NULL,
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
    'ok', true,
    'existing', false,
    'die_roll', v_roll,
    'moved_from', v_from,
    'rolled_to', (v_move->>'rolled_to')::smallint,
    'moved_to', v_to,
    'movement_kind', v_move->>'movement_kind',
    'round_number', p_round_number,
    'position_a', v_session.board_position_a,
    'position_b', v_session.board_position_b,
    'current_turn_user_id', v_session.current_turn_user_id,
    'winner_user_id', v_session.winner_user_id,
    'won', v_won
  );
END;
$$;

-- ---------------------------------------------------------------------
-- State.
-- ---------------------------------------------------------------------
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

  -- Bounded (checklist 2.5, 3.1): a long game is still a finite payload.
  -- Only the most recent turns are needed -- the replay animates the
  -- last one, and nothing else reads history.
  SELECT COALESCE(jsonb_agg(row ORDER BY (row->>'round_number')::int), '[]'::jsonb)
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

-- ---------------------------------------------------------------------
-- Expiry (§12.2): 48h for an unaccepted invite, 24h of inactivity.
-- ---------------------------------------------------------------------
-- Not housekeeping. An abandoned board here is attached to a bad
-- evening, and a game card resurfacing weeks later would drag that
-- evening back into the chat unannounced.
CREATE OR REPLACE FUNCTION public.expire_snakes_sessions()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int;
BEGIN
  WITH expired AS (
    UPDATE public.game_sessions s
       SET status = 'abandoned',
           abandoned_at = now(),
           current_turn_user_id = NULL
     WHERE s.game_type = 'snakes_and_ladders'
       AND (
         (s.status = 'invited' AND s.created_at < now() - interval '48 hours')
         OR (
           s.status = 'active'
           AND COALESCE(
                 (SELECT max(r.created_at) FROM public.game_session_rounds r
                   WHERE r.session_id = s.id),
                 s.started_at, s.created_at
               ) < now() - interval '24 hours'
         )
       )
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM expired;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.snakes_error(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.snakes_resolve_move(smallint, smallint, jsonb)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.snakes_create_session(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.snakes_accept_session(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.snakes_decline_session(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.snakes_roll_die(uuid, int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_snakes_session_state(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.expire_snakes_sessions() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.snakes_error(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.snakes_resolve_move(smallint, smallint, jsonb)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.snakes_create_session(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.snakes_accept_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.snakes_decline_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.snakes_roll_die(uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_snakes_session_state(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_snakes_sessions() TO service_role;
