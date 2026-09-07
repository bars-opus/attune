-- Snakes and Ladders contracts.
BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-00000000f001'),
  ('00000000-0000-0000-0000-00000000f002'),
  ('00000000-0000-0000-0000-00000000f003') ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-00000000f001', '+15554440011', 'SL1'),
  ('00000000-0000-0000-0000-00000000f002', '+15554440012', 'SL2'),
  ('00000000-0000-0000-0000-00000000f003', '+15554440013', 'SL3')
  ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------
-- Movement: the pure function, exhaustively.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_board jsonb;
  v_move jsonb;
  v_roll int;
  v_from int;
BEGIN
  SELECT features INTO v_board FROM public.snakes_boards WHERE version = 'v1';

  -- A plain move.
  v_move := public.snakes_resolve_move(10::smallint, 3::smallint, v_board);
  IF (v_move->>'moved_to')::int <> 13
     OR v_move->>'movement_kind' <> 'normal' THEN
    RAISE EXCEPTION 'a plain move went wrong: %', v_move;
  END IF;

  -- A ladder: 28 -> 84.
  v_move := public.snakes_resolve_move(25::smallint, 3::smallint, v_board);
  IF (v_move->>'moved_to')::int <> 84
     OR (v_move->>'rolled_to')::int <> 28
     OR v_move->>'movement_kind' <> 'ladder' THEN
    RAISE EXCEPTION 'the ladder at 28 did not carry: %', v_move;
  END IF;

  -- A snake: 16 -> 6.
  v_move := public.snakes_resolve_move(14::smallint, 2::smallint, v_board);
  IF (v_move->>'moved_to')::int <> 6
     OR (v_move->>'rolled_to')::int <> 16
     OR v_move->>'movement_kind' <> 'snake' THEN
    RAISE EXCEPTION 'the snake at 16 did not bite: %', v_move;
  END IF;

  -- EXACT FINISH. From 97 a 3 wins; a 5 bounces to 98.
  v_move := public.snakes_resolve_move(97::smallint, 3::smallint, v_board);
  IF (v_move->>'moved_to')::int <> 100 THEN
    RAISE EXCEPTION 'an exact roll did not finish: %', v_move;
  END IF;

  -- 97 + 5 = 102, bouncing to 98 -- which is a snake head, so it then
  -- slides to 78. The bounce still happened; the movement_kind reports
  -- the LAST thing that befell the token, which is what the animation
  -- needs to know.
  v_move := public.snakes_resolve_move(97::smallint, 5::smallint, v_board);
  IF (v_move->>'rolled_to')::int <> 98 THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: overshooting 100 did not bounce back: %', v_move;
  END IF;
  IF (v_move->>'moved_to')::int <> 78 THEN
    RAISE EXCEPTION 'the snake at 98 did not bite after the bounce: %', v_move;
  END IF;

  -- A bounce onto a plain cell reports as a bounce. 96 + 6 = 102 -> 98
  -- is a snake, so use 99 + 3 = 102 -> 98... also a snake. 94 + 6 -> 100
  -- exactly. Use 99 + 2 = 101 -> 99, a plain cell.
  v_move := public.snakes_resolve_move(99::smallint, 2::smallint, v_board);
  IF (v_move->>'moved_to')::int <> 99
     OR v_move->>'movement_kind' <> 'bounce' THEN
    RAISE EXCEPTION 'a plain bounce was not reported as one: %', v_move;
  END IF;

  -- Boundary sweep (checklist 6.1): every start and every roll produces
  -- a position on the board and never beyond it.
  FOR v_from IN 0..99 LOOP
    FOR v_roll IN 1..6 LOOP
      v_move := public.snakes_resolve_move(
        v_from::smallint, v_roll::smallint, v_board);
      IF (v_move->>'moved_to')::int < 1
         OR (v_move->>'moved_to')::int > 100 THEN
        RAISE EXCEPTION
          'CONTRACT VIOLATED: from % rolling % left the board: %',
          v_from, v_roll, v_move;
      END IF;
      IF v_move->>'movement_kind' NOT IN
         ('normal', 'bounce', 'ladder', 'snake') THEN
        RAISE EXCEPTION 'unknown movement kind: %', v_move;
      END IF;
    END LOOP;
  END LOOP;
END $$;

-- A lost response remains recoverable after relationship teardown. This is
-- why idempotency is before every state rejection, not merely the rate limit.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000f001';
  b uuid := '00000000-0000-0000-0000-00000000f002';
  v_rel uuid;
  v_session uuid;
  v_first jsonb;
  v_retry jsonb;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;
  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status,
    board_position_a, board_position_b, board_version,
    current_round, current_turn_user_id, started_at)
  VALUES (v_rel, b, 'snakes_and_ladders', 'active', 0, 0, 'v1', 1, a, now())
  RETURNING id INTO v_session;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_first := public.snakes_roll_die(v_session, 1);
  UPDATE public.relationships SET chat_archived_at = now() WHERE id = v_rel;
  v_retry := public.snakes_roll_die(v_session, 1);

  IF (v_retry->>'existing')::boolean IS NOT TRUE
     OR v_retry->>'die_roll' IS DISTINCT FROM v_first->>'die_roll'
     OR v_retry->>'moved_to' IS DISTINCT FROM v_first->>'moved_to' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: teardown lost or rerolled a committed turn';
  END IF;
END $$;

-- Expired invitations disappear during lookup, without waiting for cron.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000f001';
  b uuid := '00000000-0000-0000-0000-00000000f002';
  v_rel uuid;
  v_session uuid;
  v_result jsonb;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;
  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status,
    board_position_a, board_position_b, board_version,
    current_round, created_at)
  VALUES (
    v_rel, a, 'snakes_and_ladders', 'invited', 0, 0, 'v1', 1,
    now() - interval '49 hours')
  RETURNING id INTO v_session;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_result := public.get_active_snakes_session(v_rel);
  IF v_result->>'session_id' IS NOT NULL THEN
    RAISE EXCEPTION 'an expired invitation remained active in the lobby';
  END IF;
  IF (SELECT status FROM public.game_sessions WHERE id = v_session)
     <> 'abandoned' THEN
    RAISE EXCEPTION 'lookup did not retire an expired invitation';
  END IF;
END $$;

-- Active expiry is enforced by the roll itself as well as by cron.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000f001';
  b uuid := '00000000-0000-0000-0000-00000000f002';
  v_rel uuid;
  v_session uuid;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;
  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status,
    board_position_a, board_position_b, board_version,
    current_round, current_turn_user_id, started_at)
  VALUES (
    v_rel, b, 'snakes_and_ladders', 'active', 0, 0, 'v1', 1, a,
    now() - interval '25 hours')
  RETURNING id INTO v_session;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  IF (public.snakes_roll_die(v_session, 1)->>'code')
     IS DISTINCT FROM 'SESSION_EXPIRED' THEN
    RAISE EXCEPTION 'an inactive-for-24h session still accepted a roll';
  END IF;
  IF (SELECT status FROM public.game_sessions WHERE id = v_session)
     <> 'abandoned' THEN
    RAISE EXCEPTION 'the roll did not retire an expired active session';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- The board's own invariants are enforced, not trusted.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_raised boolean;
BEGIN
  -- A ladder that descends.
  v_raised := false;
  BEGIN
    INSERT INTO public.snakes_boards(version, features)
    VALUES ('bad-1', jsonb_build_object(
      'ladders', jsonb_build_object('50', 20), 'snakes', '{}'::jsonb));
  EXCEPTION WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'a ladder that descends was accepted';
  END IF;

  -- A ladder to 100 would bypass the exact-finish rule entirely, which
  -- is the only tension the game has.
  v_raised := false;
  BEGIN
    INSERT INTO public.snakes_boards(version, features)
    VALUES ('bad-2', jsonb_build_object(
      'ladders', jsonb_build_object('80', 100), 'snakes', '{}'::jsonb));
  EXCEPTION WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a ladder to 100 was accepted';
  END IF;

  -- Chaining: one roll must never trigger two slides.
  v_raised := false;
  BEGIN
    INSERT INTO public.snakes_boards(version, features)
    VALUES ('bad-3', jsonb_build_object(
      'ladders', jsonb_build_object('10', 20),
      'snakes', jsonb_build_object('20', 5)));
  EXCEPTION WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chained feature was accepted';
  END IF;

  -- A cell that is both a ladder foot and a snake head.
  v_raised := false;
  BEGIN
    INSERT INTO public.snakes_boards(version, features)
    VALUES ('bad-4', jsonb_build_object(
      'ladders', jsonb_build_object('30', 60),
      'snakes', jsonb_build_object('30', 5)));
  EXCEPTION WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'a cell heading two features was accepted';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- The turn contract.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000f001';
  b uuid := '00000000-0000-0000-0000-00000000f002';
  c uuid := '00000000-0000-0000-0000-00000000f003';
  v_rel uuid;
  v_session uuid;
  v_result jsonb;
  v_first jsonb;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_result := public.snakes_create_session(v_rel, 'sl-key-1');
  v_session := (v_result->>'session_id')::uuid;

  -- Creation pins the board, so retuning cannot rewrite this game later.
  IF (SELECT board_version FROM public.game_sessions WHERE id = v_session)
     IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the session did not pin a board';
  END IF;

  -- Idempotent creation.
  IF (public.snakes_create_session(v_rel, 'sl-key-1')->>'session_id')::uuid
     <> v_session THEN
    RAISE EXCEPTION 'a repeated key made a second session';
  END IF;

  -- The initiator cannot accept their own invitation.
  IF (public.snakes_accept_session(v_session)->>'code')
     IS DISTINCT FROM 'FORBIDDEN' THEN
    RAISE EXCEPTION 'the initiator accepted their own invitation';
  END IF;

  -- The INVITEE accepts and moves first (§4.1a).
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  PERFORM public.snakes_accept_session(v_session);

  IF (SELECT current_turn_user_id FROM public.game_sessions
      WHERE id = v_session) <> b THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the invitee does not move first';
  END IF;

  -- A stranger cannot roll.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', c, 'role', 'authenticated')::text, true);
  IF (public.snakes_roll_die(v_session, 1)->>'code')
     IS DISTINCT FROM 'FORBIDDEN' THEN
    RAISE EXCEPTION 'a non-member rolled';
  END IF;

  -- Out of turn is refused.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  IF (public.snakes_roll_die(v_session, 1)->>'code')
     IS DISTINCT FROM 'NOT_YOUR_TURN' THEN
    RAISE EXCEPTION 'rolling out of turn was allowed';
  END IF;

  -- B rolls.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_first := public.snakes_roll_die(v_session, 1);

  IF (v_first->>'die_roll')::int NOT BETWEEN 1 AND 6 THEN
    RAISE EXCEPTION 'the die produced %', v_first->>'die_roll';
  END IF;
  IF v_first->>'current_turn_user_id' IS DISTINCT FROM a::text THEN
    RAISE EXCEPTION 'the turn did not pass after a roll';
  END IF;

  -- THE ONE THAT MATTERS. A retry must return the SAME roll. Otherwise
  -- a player could reroll a bad number by force quitting the app.
  v_result := public.snakes_roll_die(v_session, 1);
  IF (v_result->>'die_roll')::int <> (v_first->>'die_roll')::int THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a retried roll produced a different number (% vs %)',
      v_result->>'die_roll', v_first->>'die_roll';
  END IF;
  IF (v_result->>'existing')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'a retried roll was not reported as existing';
  END IF;
  IF (v_result->>'moved_to')::int <> (v_first->>'moved_to')::int THEN
    RAISE EXCEPTION 'a retried roll moved the token again';
  END IF;

  -- Idempotency is checked BEFORE the rate limit: the retry above
  -- returned its stored roll rather than RATE_LIMITED, which is the
  -- whole point of that ordering. A genuinely NEW roll still meets the
  -- limiter first.
  IF (public.snakes_roll_die(v_session, 2)->>'code')
     IS DISTINCT FROM 'RATE_LIMITED' THEN
    RAISE EXCEPTION 'a burst of new rolls was not rate limited';
  END IF;

  -- And once the limiter clears, B is still refused for the real reason.
  UPDATE public.game_session_rounds
     SET created_at = now() - interval '5 seconds' WHERE session_id = v_session;
  IF (public.snakes_roll_die(v_session, 2)->>'code')
     IS DISTINCT FROM 'NOT_YOUR_TURN' THEN
    RAISE EXCEPTION 'B rolled twice in a row';
  END IF;

  -- Out-of-sequence round numbers are refused.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  IF (public.snakes_roll_die(v_session, 99)->>'code')
     IS DISTINCT FROM 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'an arbitrary round number was accepted';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- Winning, and what happens after.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000f001';
  b uuid := '00000000-0000-0000-0000-00000000f002';
  v_rel uuid;
  v_session uuid;
  v_result jsonb;
  v_tries int := 0;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status,
    board_position_a, board_position_b, board_version,
    current_round, current_turn_user_id
  )
  VALUES (v_rel, a, 'snakes_and_ladders', 'active', 99, 0, 'v1', 1, a)
  RETURNING id INTO v_session;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);

  -- From 99 only a 1 wins; anything else bounces. Roll until one lands,
  -- ageing the rows so the limiter does not block the loop.
  WHILE v_tries < 60 LOOP
    v_tries := v_tries + 1;
    UPDATE public.game_session_rounds
       SET created_at = now() - interval '5 seconds'
     WHERE session_id = v_session;

    v_result := public.snakes_roll_die(
      v_session,
      (SELECT current_round FROM public.game_sessions WHERE id = v_session));

    IF (v_result->>'won')::boolean THEN
      EXIT;
    END IF;

    -- Not a win: hand the turn back so A can roll again.
    UPDATE public.game_sessions
       SET current_turn_user_id = a, board_position_a = 99
     WHERE id = v_session;
  END LOOP;

  IF NOT COALESCE((v_result->>'won')::boolean, false) THEN
    RAISE EXCEPTION 'never rolled a 1 in 60 attempts -- the die may be broken';
  END IF;

  IF (SELECT status FROM public.game_sessions WHERE id = v_session)
     <> 'completed' THEN
    RAISE EXCEPTION 'reaching 100 did not complete the session';
  END IF;
  IF (SELECT winner_user_id FROM public.game_sessions WHERE id = v_session)
     <> a THEN
    RAISE EXCEPTION 'the winner was not recorded';
  END IF;
  IF (SELECT current_turn_user_id FROM public.game_sessions
      WHERE id = v_session) IS NOT NULL THEN
    RAISE EXCEPTION 'the turn advanced past a finished game';
  END IF;

  -- A finished game is over.
  UPDATE public.game_session_rounds
     SET created_at = now() - interval '5 seconds' WHERE session_id = v_session;
  IF (public.snakes_roll_die(v_session, 99)->>'code')
     IS DISTINCT FROM 'GAME_OVER' THEN
    RAISE EXCEPTION 'a finished game accepted another roll';
  END IF;

  -- NO PENALTY. Paint Ball earns its forfeit because skill decided it;
  -- here a die did, and a consequence attached to a coin flip is the
  -- opposite of cooling off (§5.4).
  IF (SELECT penalty_status FROM public.game_sessions WHERE id = v_session)
     IS NOT NULL THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: this game queued a penalty -- it must never';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- The die is the server's, and nothing is secret.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_src text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'snakes_roll_die';

  -- The client sends "I am rolling" and nothing else. A face value in
  -- the signature would not be a game.
  IF v_src ~* 'p_die|p_roll|p_face|p_value' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: the roll RPC accepts a client-supplied die';
  END IF;
  IF v_src !~ 'random\(\)' THEN
    RAISE EXCEPTION 'the die is not rolled server-side';
  END IF;
END $$;

-- Only the intended roles can execute.
DO $$
DECLARE
  v_fn text;
BEGIN
  FOR v_fn IN
    SELECT unnest(ARRAY['snakes_create_session','snakes_accept_session',
                        'snakes_decline_session','snakes_roll_die',
                        'get_snakes_session_state'])
  LOOP
    IF EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname='public' AND p.proname = v_fn
        AND has_function_privilege('anon', p.oid, 'EXECUTE')
    ) THEN
      RAISE EXCEPTION 'anon can execute %', v_fn;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname = 'expire_snakes_sessions'
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'a player can expire sessions';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN (
        'snakes_error', 'snakes_resolve_move',
        'guard_snakes_board_immutable', 'validate_snakes_board',
        'abandon_snakes_on_relationship_change',
        'expire_snakes_for_relationship')
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'a player can execute an internal Snakes helper';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- SECURITY: the table is not a back door around the game.
-- ---------------------------------------------------------------------
-- Found by review, and confirmed against a live database before the fix:
-- the shared policies granted members write access to every game except
-- paint_ball, so a Snakes player could set their own position to 100 and
-- name themselves the winner without ever rolling. Every other control
-- in this game -- the server die, the turn lock, idempotency -- was
-- decorative while that held.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000f001';
  b uuid := '00000000-0000-0000-0000-00000000f002';
  v_rel uuid;
  v_session uuid;
  v_position int;
  v_winner uuid;
  v_rounds int;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status,
    board_position_a, board_position_b, board_version,
    current_round, current_turn_user_id
  )
  VALUES (v_rel, a, 'snakes_and_ladders', 'active', 5, 5, 'v1', 1, b)
  RETURNING id INTO v_session;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;

  UPDATE public.game_sessions
     SET board_position_a = 100, status = 'completed', winner_user_id = a
   WHERE id = v_session;

  -- A round insert is REFUSED outright rather than ignored, so it has
  -- to be caught. Either outcome is fine; what matters is that no round
  -- exists afterwards.
  BEGIN
    INSERT INTO public.game_session_rounds(
      session_id, round_number, active_partner_id, game_type,
      die_roll, moved_from, rolled_to, moved_to, movement_kind)
    VALUES (v_session, 50, a, 'snakes_and_ladders', 6, 5, 11, 11, 'normal');
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  RESET ROLE;

  SELECT board_position_a, winner_user_id INTO v_position, v_winner
  FROM public.game_sessions WHERE id = v_session;

  IF v_position <> 5 OR v_winner IS NOT NULL THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a player wrote the session directly (pos=% winner=%)',
      v_position, v_winner;
  END IF;

  SELECT count(*) INTO v_rounds FROM public.game_session_rounds
  WHERE session_id = v_session;
  IF v_rounds <> 0 THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a player inserted a round directly';
  END IF;

  -- Reads stay open: the board is not secret, and both players draw it.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  IF NOT EXISTS (SELECT 1 FROM public.game_sessions WHERE id = v_session) THEN
    RESET ROLE;
    RAISE EXCEPTION 'a player can no longer read their own game';
  END IF;
  RESET ROLE;
END $$;

-- A board that has been played on is frozen.
DO $$
DECLARE
  v_raised boolean := false;
BEGIN
  -- v1 is referenced by the sessions created above.
  BEGIN
    UPDATE public.snakes_boards
       SET features = jsonb_build_object('ladders','{}'::jsonb,
                                         'snakes','{}'::jsonb)
     WHERE version = 'v1';
  EXCEPTION WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a played board was edited -- every game on it '
      'would be retroactively rewritten';
  END IF;

  -- Renaming the primary key is just as destructive as editing features:
  -- every pinned session would point at a board version that no longer
  -- exists. The first immutability trigger guarded features but missed this.
  v_raised := false;
  BEGIN
    UPDATE public.snakes_boards SET version = 'v1-renamed'
    WHERE version = 'v1';
  EXCEPTION WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a referenced board version was renamed';
  END IF;
END $$;

-- Relationship teardown is session teardown, immediately rather than at
-- the next hourly expiry sweep. An archived couple must not retain a live
-- game card or be able to accept an old invitation.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000f001';
  b uuid := '00000000-0000-0000-0000-00000000f002';
  v_rel uuid;
  v_session uuid;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;
  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status,
    board_position_a, board_position_b, board_version,
    current_round, current_turn_user_id)
  VALUES (v_rel, a, 'snakes_and_ladders', 'invited', 0, 0, 'v1', 1, NULL)
  RETURNING id INTO v_session;

  UPDATE public.relationships SET chat_archived_at = now() WHERE id = v_rel;
  IF (SELECT status FROM public.game_sessions WHERE id = v_session)
     <> 'abandoned' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: relationship archive left a live Snakes session';
  END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  IF (public.snakes_accept_session(v_session)->>'code')
     IS DISTINCT FROM 'SESSION_EXPIRED' THEN
    RAISE EXCEPTION 'an archived relationship accepted a game invitation';
  END IF;
END $$;

-- SQL and client surfaces must use the same product name.
DO $$
BEGIN
  IF public.game_type_display_name('snakes_and_ladders')
     <> 'Snakes and Ladders' THEN
    RAISE EXCEPTION 'Snakes game card has the wrong display name';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.scheduled_notifications
     WHERE metadata->>'game_type' = 'snakes_and_ladders'
       AND metadata->>'body' =
           'Snakes and Ladders ' || U&'\2014' || ' your turn to play.'
  ) THEN
    RAISE EXCEPTION 'Snakes invite push has the wrong display name';
  END IF;
END $$;

-- Ranges and reachability.
DO $$
DECLARE
  v_raised boolean;
BEGIN
  -- A ladder off the end of the board. Landing on it would violate the
  -- position CHECK, abort the turn, and silently hand the player a
  -- reroll.
  v_raised := false;
  BEGIN
    INSERT INTO public.snakes_boards(version, features)
    VALUES ('bad-range', jsonb_build_object(
      'ladders', jsonb_build_object('99', 101), 'snakes', '{}'::jsonb));
  EXCEPTION WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a ladder to 101 was accepted';
  END IF;

  -- Snakes guarding every approach to 100: legal by every other rule,
  -- and no game on it can ever end.
  v_raised := false;
  BEGIN
    INSERT INTO public.snakes_boards(version, features)
    VALUES ('bad-reach', jsonb_build_object(
      'ladders', '{}'::jsonb,
      'snakes', jsonb_build_object(
        '94', 5, '95', 6, '96', 7, '97', 8, '98', 9, '99', 10)));
  EXCEPTION WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a board where 100 is unreachable was accepted';
  END IF;
END $$;

ROLLBACK;
