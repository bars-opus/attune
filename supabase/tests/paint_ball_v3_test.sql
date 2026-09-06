-- Paint Ball v3: simultaneous rounds, the draw, and the disclosure boundary.
--
-- The boundary is the load-bearing rule. hide_position may reach a client
-- only once its round has resolved: before that it is live information the
-- closer could read to turn a prediction into a certainty; after, it is the
-- history the replay is made of. v2 withheld it forever, which is why the
-- game could never show what happened.
BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-00000003a001'),
  ('00000000-0000-0000-0000-00000003b002') ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-00000003a001', '+15557770031', 'V3A'),
  ('00000000-0000-0000-0000-00000003b002', '+15557770032', 'V3B')
  ON CONFLICT (id) DO NOTHING;

-- A DRAW: both players hit each other on their last life.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000003a001';
  b uuid := '00000000-0000-0000-0000-00000003b002';
  v_rel uuid;
  v_session uuid;
  v_result jsonb;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status, tone,
    lives_a, lives_b, current_turn_user_id, current_round
  )
  VALUES (v_rel, a, 'paint_ball', 'active', 'playful', 1, 1, a, 1)
  RETURNING id INTO v_session;

  -- A hides 0 shoots 1; B hides 1 shoots 0. Each is exactly where the
  -- other fired, so both land.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  PERFORM public.paint_ball_take_turn(v_session, 1, 0::smallint, 1::smallint);

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_result := public.paint_ball_take_turn(v_session, 1, 1::smallint, 0::smallint);

  IF (v_result->>'lives_a')::int <> 0 OR (v_result->>'lives_b')::int <> 0 THEN
    RAISE EXCEPTION 'a mutual kill should empty both, got %', v_result;
  END IF;
  IF NOT (v_result->>'double_knockout')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a mutual kill was not a draw: %', v_result;
  END IF;

  -- Nobody wins a draw. Awarding it on turn order would make the ending a
  -- technicality in a game whose whole point is playing together.
  IF (SELECT winner_user_id FROM public.game_sessions WHERE id = v_session)
     IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draw named a winner';
  END IF;

  -- Both forfeit, each their own prompt.
  IF (SELECT count(*) FROM public.paint_ball_penalties
      WHERE session_id = v_session) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draw did not give both a penalty';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.paint_ball_penalties
    WHERE session_id = v_session AND penalty_prompt_snapshot IS NULL
  ) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draw penalty had no prompt';
  END IF;

  -- BOTH may resolve, and the session completes only when both have. If
  -- the first to finish completed it, the second would be locked out of
  -- the forfeit they earned.
  v_result := public.paint_ball_resolve_penalty(v_session, 'completed');
  IF NOT (v_result->>'awaiting_partner_penalty')::boolean THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: one resolution ended a two-penalty session: %', v_result;
  END IF;
  IF (SELECT status FROM public.game_sessions WHERE id = v_session)
     = 'completed' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: the session completed with a penalty outstanding';
  END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_result := public.paint_ball_resolve_penalty(v_session, 'declined');
  IF NOT (v_result->>'session_completed')::boolean THEN
    RAISE EXCEPTION 'the second resolution did not end the game: %', v_result;
  END IF;

  -- Declining is free and says nothing about the other player's choice.
  IF (SELECT penalty_status FROM public.paint_ball_penalties
      WHERE session_id = v_session AND user_id = b) <> 'completed' THEN
    RAISE EXCEPTION 'one partner declining changed the other''s record';
  END IF;
END $$;

-- THE DISCLOSURE BOUNDARY, from both sides.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000003a001';
  b uuid := '00000000-0000-0000-0000-00000003b002';
  v_rel uuid;
  v_session uuid;
  v_state text;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status, tone,
    lives_a, lives_b, current_turn_user_id, current_round
  )
  VALUES (v_rel, a, 'paint_ball', 'active', 'playful', 3, 3, a, 1)
  RETURNING id INTO v_session;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  PERFORM public.paint_ball_take_turn(v_session, 1, 2::smallint, 0::smallint);

  -- BEFORE: the round is half-complete. If the closer could read the
  -- opener's hide here, they would simply shoot it, and the game would be
  -- over as a game.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_state := public.get_paint_ball_session_state(v_session)::text;
  IF v_state ~ '"hide_position"' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: an unresolved round exposed hide_position';
  END IF;

  PERFORM public.paint_ball_take_turn(v_session, 1, 1::smallint, 1::smallint);

  -- AFTER: the round resolved, so both hides are history and the replay
  -- needs them. Withholding here is what left v2 with no scene to show.
  v_state := public.get_paint_ball_session_state(v_session)::text;
  IF v_state !~ '"hide_position"' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a resolved round withheld hide_position from the replay';
  END IF;
END $$;

-- A round holds exactly two rows, and one player cannot fill both.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000003a001';
  b uuid := '00000000-0000-0000-0000-00000003b002';
  v_rel uuid;
  v_session uuid;
  v_raised boolean := false;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status, tone,
    lives_a, lives_b, current_turn_user_id, current_round
  )
  VALUES (v_rel, a, 'paint_ball', 'active', 'playful', 3, 3, a, 1)
  RETURNING id INTO v_session;

  INSERT INTO public.game_session_rounds
    (session_id, round_number, active_partner_id, hide_position, shot_position)
  VALUES (v_session, 1, a, 0, 0);

  BEGIN
    INSERT INTO public.game_session_rounds
      (session_id, round_number, active_partner_id, hide_position, shot_position)
    VALUES (v_session, 1, a, 1, 1);
  EXCEPTION WHEN unique_violation THEN
    v_raised := true;
  END;

  IF NOT v_raised THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: one player wrote two halves of the same round';
  END IF;

  -- The partner's half is allowed at the same round number.
  INSERT INTO public.game_session_rounds
    (session_id, round_number, active_partner_id, hide_position, shot_position)
  VALUES (v_session, 1, b, 2, 2);
END $$;

-- The other six games on this shared table keep one row per round.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000003a001';
  b uuid := '00000000-0000-0000-0000-00000003b002';
  v_rel uuid;
  v_session uuid;
  v_raised boolean := false;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status, current_round
  )
  VALUES (v_rel, a, 'this_or_that', 'active', 1)
  RETURNING id INTO v_session;

  INSERT INTO public.game_session_rounds
    (session_id, round_number, active_partner_id)
  VALUES (v_session, 1, a);

  BEGIN
    INSERT INTO public.game_session_rounds
      (session_id, round_number, active_partner_id)
    VALUES (v_session, 1, b);
  EXCEPTION WHEN unique_violation THEN
    v_raised := true;
  END;

  IF NOT v_raised THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: Paint Ball''s two-row rule leaked into this_or_that';
  END IF;
END $$;

ROLLBACK;
