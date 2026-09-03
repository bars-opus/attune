-- Paint Ball: hidden-information prediction.
--
-- The game was a timing tap whose hit/miss the CLIENT decided. It is now
-- one asynchronous move per turn -- hide somewhere, shoot where you think
-- your partner is -- resolved by the server against where they actually
-- hid.
--
-- Two things that buys: the skill becomes guessing your partner rather
-- than reaction time, which is what this app is for; and the outcome is
-- server-derived, so trust-the-client stops being a question.

BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-00000000cb01'),
  ('00000000-0000-0000-0000-00000000cb02'),
  ('00000000-0000-0000-0000-00000000cb03') ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-00000000cb01', '+15558880011', 'PB1'),
  ('00000000-0000-0000-0000-00000000cb02', '+15558880012', 'PB2'),
  ('00000000-0000-0000-0000-00000000cb03', '+15558880013', 'PB3')
  ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000cb01';
  b uuid := '00000000-0000-0000-0000-00000000cb02';
  c uuid := '00000000-0000-0000-0000-00000000cb03';
  v_rel uuid;
  v_session uuid;
  v_result jsonb;
  v_lives int;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status,
    lives_a, lives_b, current_turn_user_id
  )
  VALUES (v_rel, a, 'paint_ball', 'active', 3, 3, a)
  RETURNING id INTO v_session;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);

  -- The opening move is neither a hit nor a miss: nobody has hidden yet,
  -- so the shot had nothing to find. Recording it as a miss would be a
  -- lie the reveal screen then has to tell.
  v_result := public.paint_ball_take_turn(v_session, 1, 1::smallint, 2::smallint);
  IF v_result->>'shot_result' <> 'opening' THEN
    RAISE EXCEPTION 'the first shot should be an opening, got %',
      v_result->>'shot_result';
  END IF;

  -- The turn passes.
  IF (SELECT current_turn_user_id FROM public.game_sessions WHERE id = v_session)
     IS DISTINCT FROM b THEN
    RAISE EXCEPTION 'the turn did not pass to the partner';
  END IF;

  -- A hid at 1. B shooting at 1 finds them.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_result := public.paint_ball_take_turn(v_session, 2, 0::smallint, 1::smallint);

  IF v_result->>'shot_result' <> 'hit' THEN
    RAISE EXCEPTION 'shooting where the partner hid should hit, got %',
      v_result->>'shot_result';
  END IF;
  IF (v_result->>'lives_a')::int <> 2 THEN
    RAISE EXCEPTION 'a hit should cost exactly one life, lives_a = %',
      v_result->>'lives_a';
  END IF;

  -- And the shooter learns where they were. This is what makes the next
  -- guess a prediction rather than a coin flip.
  IF (v_result->>'defender_was_at')::int <> 1 THEN
    RAISE EXCEPTION 'the shooter was not told where their partner hid';
  END IF;

  -- B hid at 0. A shooting at 2 finds nothing.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_result := public.paint_ball_take_turn(v_session, 3, 1::smallint, 2::smallint);

  IF v_result->>'shot_result' <> 'miss' THEN
    RAISE EXCEPTION 'shooting an empty position should miss, got %',
      v_result->>'shot_result';
  END IF;
  SELECT lives_b INTO v_lives FROM public.game_sessions WHERE id = v_session;
  IF v_lives <> 3 THEN
    RAISE EXCEPTION 'a miss must cost nothing, lives_b = %', v_lives;
  END IF;

  -- Out of turn is refused. The server decides whose move it is; without
  -- this a client could fire twice and drain a partner's lives.
  v_result := public.paint_ball_take_turn(v_session, 4, 0::smallint, 0::smallint);
  IF v_result->>'code' IS DISTINCT FROM 'NOT_YOUR_TURN' THEN
    RAISE EXCEPTION 'moving out of turn was allowed';
  END IF;

  -- A stranger cannot play someone else's game.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', c, 'role', 'authenticated')::text, true);
  v_result := public.paint_ball_take_turn(v_session, 4, 0::smallint, 0::smallint);
  IF v_result->>'code' IS DISTINCT FROM 'FORBIDDEN' THEN
    RAISE EXCEPTION 'a non-member took a turn';
  END IF;

  -- An out-of-range position is rejected rather than stored.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_result := public.paint_ball_take_turn(v_session, 4, 9::smallint, 0::smallint);
  IF v_result->>'code' IS DISTINCT FROM 'INVALID_POSITION' THEN
    RAISE EXCEPTION 'an out-of-range hiding place was accepted';
  END IF;
END $$;

-- The session state carries paint, but never the hiding places.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000cb01';
  b uuid := '00000000-0000-0000-0000-00000000cb02';
  v_rel uuid;
  v_session uuid;
  v_state jsonb;
  v_round jsonb;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status,
    lives_a, lives_b, current_turn_user_id
  )
  VALUES (v_rel, a, 'paint_ball', 'active', 3, 3, a)
  RETURNING id INTO v_session;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  PERFORM public.paint_ball_take_turn(v_session, 1, 1::smallint, 2::smallint);

  v_state := public.get_paint_ball_session_state(v_session)::jsonb;
  v_round := v_state -> 'rounds' -> 0;

  -- Without the position the field has nothing to paint, and a reopened
  -- game shows a clean arena however many rounds were fired.
  IF v_round ->> 'shot_position' IS NULL THEN
    RAISE EXCEPTION 'the session state omits where the shot landed';
  END IF;
  IF v_round ->> 'active_partner_id' IS NULL THEN
    RAISE EXCEPTION 'the session state omits whose shot it was';
  END IF;

  -- THE ONE THAT MATTERS. hide_position is the hidden information the
  -- game turns on: a client that could read past hiding places could
  -- read the current one, and the guess would stop being a guess.
  IF v_round ? 'hide_position' THEN
    RAISE EXCEPTION
      'the session state leaks hide_position -- the guess is no longer a guess';
  END IF;
END $$;

ROLLBACK;
