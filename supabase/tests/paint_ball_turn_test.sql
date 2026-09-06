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

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'paint_ball_fire_shot'
  ) THEN
    RAISE EXCEPTION 'retired client-trusted paint_ball_fire_shot still exists';
  END IF;
END $$;

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

  -- v3: the opener's half resolves NOTHING. A round is an exchange, and
  -- until both halves are in there is no verdict to give and nothing to
  -- reveal -- otherwise the closer could read the opener's position and
  -- the prediction would stop being one.
  v_result := public.paint_ball_take_turn(v_session, 1, 0::smallint, 1::smallint);
  IF v_result->>'round_state' IS DISTINCT FROM 'awaiting_partner' THEN
    RAISE EXCEPTION 'the opener half should await the partner, got %', v_result;
  END IF;
  IF v_result ? 'opener' OR v_result ? 'closer' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a half-complete round exposed positions: %', v_result;
  END IF;
  IF (v_result->>'lives_a')::int <> 3 OR (v_result->>'lives_b')::int <> 3 THEN
    RAISE EXCEPTION 'the opener half changed lives';
  END IF;
  IF v_result->>'current_turn_user_id' IS DISTINCT FROM b::text THEN
    RAISE EXCEPTION 'the turn did not pass to the partner';
  END IF;

  -- The state RPC must withhold just as firmly as take_turn did.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  IF (public.get_paint_ball_session_state(v_session)::jsonb)::text
       ~ '"hide_position"' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: an unresolved round leaked hide_position to the closer';
  END IF;

  -- B closes the round. A hid at 0 and shot at 1; B now hides at 1 and
  -- shoots at 0 -- so both called it, and BOTH lose a life. That mutual
  -- outcome is only possible because the shots resolve against the same
  -- round's hides rather than the previous round's.
  PERFORM pg_sleep(2.1);
  v_result := public.paint_ball_take_turn(v_session, 1, 1::smallint, 0::smallint);
  IF v_result->>'round_state' IS DISTINCT FROM 'resolved' THEN
    RAISE EXCEPTION 'the closer half should resolve the round, got %', v_result;
  END IF;
  IF (v_result->>'lives_a')::int <> 2 OR (v_result->>'lives_b')::int <> 2 THEN
    RAISE EXCEPTION
      'a mutual hit should cost both a life, got a=% b=%',
      v_result->>'lives_a', v_result->>'lives_b';
  END IF;
  IF v_result->'opener'->>'shot_result' <> 'hit'
     OR v_result->'closer'->>'shot_result' <> 'hit' THEN
    RAISE EXCEPTION 'both shots should read as hits, got %', v_result;
  END IF;

  -- Round one can hit. 'opening' is retired: there is no longer a turn
  -- that cannot land, because the hide it resolves against is chosen in
  -- the same round rather than a previous one.
  IF v_result->'opener'->>'shot_result' = 'opening'
     OR v_result->'closer'->>'shot_result' = 'opening' THEN
    RAISE EXCEPTION 'v3 must not produce an opening result';
  END IF;

  -- The replay needs BOTH positions, and only now may it have them.
  IF v_result->'opener'->>'hide_position' IS NULL
     OR v_result->'closer'->>'hide_position' IS NULL THEN
    RAISE EXCEPTION 'a resolved round must expose both hides for the replay';
  END IF;

  -- The opener of the completed round opens the next one.
  IF v_result->>'current_turn_user_id' IS DISTINCT FROM a::text THEN
    RAISE EXCEPTION 'the next round should open with the previous opener';
  END IF;

  -- Retrying a half returns its stored outcome rather than playing twice.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_result := public.paint_ball_take_turn(v_session, 1, 0::smallint, 1::smallint);
  IF (v_result->>'lives_a')::int <> 2 OR (v_result->>'lives_b')::int <> 2 THEN
    RAISE EXCEPTION 'a retried half was replayed, lives moved';
  END IF;

  -- A miss costs nothing. Round 2: A hides 2 shoots 2; B hides 0 shoots 0.
  -- Neither is where the other shot.
  v_result := public.paint_ball_take_turn(v_session, 2, 2::smallint, 2::smallint);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  PERFORM pg_sleep(2.1);
  v_result := public.paint_ball_take_turn(v_session, 2, 0::smallint, 0::smallint);
  IF (v_result->>'lives_a')::int <> 2 OR (v_result->>'lives_b')::int <> 2 THEN
    RAISE EXCEPTION 'a mutual miss cost a life, got %', v_result;
  END IF;
  IF v_result->'opener'->>'shot_result' <> 'miss'
     OR v_result->'closer'->>'shot_result' <> 'miss' THEN
    RAISE EXCEPTION 'both shots should read as misses, got %', v_result;
  END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);

  -- Out of turn is refused. The server decides whose move it is; without
  -- this a client could play both halves and drain a partner's lives.
  -- Round 3 opens with A, so B moving now is out of turn.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_result := public.paint_ball_take_turn(v_session, 3, 0::smallint, 0::smallint);
  IF v_result->>'code' IS DISTINCT FROM 'NOT_YOUR_TURN' THEN
    RAISE EXCEPTION 'moving out of turn was allowed, got %', v_result;
  END IF;

  -- A is on turn, but A also moved less than two seconds ago.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_result := public.paint_ball_take_turn(v_session, 3, 0::smallint, 0::smallint);
  IF v_result->>'code' IS DISTINCT FROM 'RATE_LIMITED' THEN
    RAISE EXCEPTION 'rapid repeat fire was not rate limited, got %', v_result;
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
  IF v_result->>'code' IS DISTINCT FROM 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'an out-of-range hiding place was accepted';
  END IF;
END $$;

-- Paint Ball is server-authoritative all the way down. A relationship member
-- may read the session summary, but cannot update its lives or query/insert the
-- underlying rounds where hide_position lives.
INSERT INTO public.relationships(id, user_a, user_b, status)
VALUES (
  '00000000-0000-0000-0000-00000000cba0',
  '00000000-0000-0000-0000-00000000cb01',
  '00000000-0000-0000-0000-00000000cb02',
  'active'
);
INSERT INTO public.game_sessions(
  id, relationship_id, initiator_id, game_type, status,
  lives_a, lives_b, current_turn_user_id
)
VALUES (
  '00000000-0000-0000-0000-00000000cba1',
  '00000000-0000-0000-0000-00000000cba0',
  '00000000-0000-0000-0000-00000000cb01',
  'paint_ball', 'active', 3, 3,
  '00000000-0000-0000-0000-00000000cb01'
);
INSERT INTO public.game_session_rounds(
  id, session_id, round_number, active_partner_id,
  hide_position, shot_position, shot_result, life_lost
)
VALUES (
  '00000000-0000-0000-0000-00000000cba2',
  '00000000-0000-0000-0000-00000000cba1',
  1, '00000000-0000-0000-0000-00000000cb01',
  2, 1, 'opening', false
);

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', '00000000-0000-0000-0000-00000000cb01',
    'role', 'authenticated'
  )::text,
  true
);

DO $$
DECLARE
  v_count int;
BEGIN
  BEGIN
    INSERT INTO public.game_sessions(
      id, relationship_id, initiator_id, game_type, status,
      lives_a, lives_b, current_turn_user_id
    )
    VALUES (
      '00000000-0000-0000-0000-00000000cba3',
      '00000000-0000-0000-0000-00000000cba0',
      '00000000-0000-0000-0000-00000000cb01',
      'paint_ball', 'active', 3, 3,
      '00000000-0000-0000-0000-00000000cb01'
    );
    RAISE EXCEPTION 'a client can forge a Paint Ball session';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  SELECT count(*) INTO v_count
  FROM public.game_session_rounds
  WHERE session_id = '00000000-0000-0000-0000-00000000cba1';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'a client can read Paint Ball hide_position directly';
  END IF;

  UPDATE public.game_sessions
  SET lives_b = 0
  WHERE id = '00000000-0000-0000-0000-00000000cba1';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'a client can directly alter Paint Ball lives';
  END IF;

  BEGIN
    INSERT INTO public.game_session_rounds(
      session_id, round_number, active_partner_id,
      hide_position, shot_position, shot_result, life_lost
    )
    VALUES (
      '00000000-0000-0000-0000-00000000cba1',
      2, '00000000-0000-0000-0000-00000000cb01',
      0, 0, 'hit', true
    );
    RAISE EXCEPTION 'a client can forge a Paint Ball round';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END $$;

RESET ROLE;

-- Relationship teardown abandons a live game immediately rather than waiting
-- for the 24-hour inactivity sweep.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000cb01';
  b uuid := '00000000-0000-0000-0000-00000000cb02';
  v_rel uuid;
  v_session uuid;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status,
    lives_a, lives_b, current_turn_user_id
  )
  VALUES (v_rel, a, 'paint_ball', 'active', 3, 3, a)
  RETURNING id INTO v_session;

  UPDATE public.relationships
  SET status = 'ended',
      ended_at = now(),
      chat_archived_at = now()
  WHERE id = v_rel;

  IF NOT EXISTS (
    SELECT 1
    FROM public.game_sessions
    WHERE id = v_session
      AND status = 'abandoned'
      AND abandoned_at IS NOT NULL
      AND current_turn_user_id IS NULL
  ) THEN
    RAISE EXCEPTION 'relationship teardown left Paint Ball playable';
  END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  IF (public.paint_ball_create_session(
        v_rel,
        'playful',
        'closed-relationship-create',
        false
      )->>'code') IS DISTINCT FROM 'FORBIDDEN' THEN
    RAISE EXCEPTION 'a closed relationship could start another Paint Ball game';
  END IF;
END $$;

-- Completed games are readable in cursor pages and hide independently for
-- each partner.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000cb01';
  b uuid := '00000000-0000-0000-0000-00000000cb02';
  v_rel uuid;
  v_session uuid;
  v_page jsonb;
  v_result jsonb;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status, tone,
    winner_user_id, penalty_type, penalty_status,
    total_rounds_completed, completed_at
  )
  VALUES (
    v_rel, a, 'paint_ball', 'completed', 'playful',
    a, 'truth', 'declined', 7, now()
  )
  RETURNING id INTO v_session;

  -- v3 keeps penalties in their own table (a draw needs two). This fixture
  -- builds a finished session by hand, so it must write the row the RPCs
  -- would have written.
  INSERT INTO public.paint_ball_penalties (
    session_id, user_id, penalty_type, penalty_source,
    penalty_status, penalty_prompt_snapshot, resolved_at
  )
  VALUES (v_session, b, 'truth', 'app_random', 'declined', 'A test prompt.', now());

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_page := public.get_paint_ball_history(v_rel, 20, NULL);
  IF NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_page->'items') item
    WHERE item->>'session_id' = v_session::text
  ) THEN
    RAISE EXCEPTION 'completed Paint Ball session was absent from history';
  END IF;

  v_result := public.paint_ball_resolve_penalty(v_session, 'declined');
  IF v_result->>'code' IS DISTINCT FROM 'FORBIDDEN' THEN
    RAISE EXCEPTION 'the winner could retry the loser-only penalty mutation';
  END IF;

  PERFORM public.paint_ball_hide_session(v_session);
  v_page := public.get_paint_ball_history(v_rel, 20, NULL);
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_page->'items') item
    WHERE item->>'session_id' = v_session::text
  ) THEN
    RAISE EXCEPTION 'hidden session remained in the hiding user''s history';
  END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_page := public.get_paint_ball_history(v_rel, 20, NULL);
  IF NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_page->'items') item
    WHERE item->>'session_id' = v_session::text
  ) THEN
    RAISE EXCEPTION 'one partner hiding a session hid it for both partners';
  END IF;

  v_result := public.paint_ball_resolve_penalty(v_session, 'declined');
  IF v_result->>'existing' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'the loser could not safely retry a resolved penalty';
  END IF;

  v_result := public.paint_ball_resolve_penalty(v_session, NULL);
  IF v_result->>'code' IS DISTINCT FROM 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'a null penalty outcome did not return INVALID_INPUT';
  END IF;

  v_result := public.paint_ball_resolve_penalty(
    '00000000-0000-0000-0000-00000000cbff',
    'declined'
  );
  IF v_result->>'code' IS DISTINCT FROM 'NOT_FOUND' THEN
    RAISE EXCEPTION 'a missing penalty session did not return NOT_FOUND';
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
