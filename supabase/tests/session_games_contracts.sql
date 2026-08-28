-- Contract tests for the session-games schema. Run against a database
-- with the migration applied. Each block RAISEs on violation, so a
-- silent pass means the contract holds.

-- 1. game_questions accepts the three new types.
DO $$
BEGIN
  INSERT INTO public.game_questions
    (game_type, tone, question_text, value_domain, scale_low, scale_high)
  VALUES
    ('sliding_scale', 'connecting', 'Money should be fully shared.',
     'money', 'Keep separate', 'Fully shared');
  DELETE FROM public.game_questions WHERE value_domain = 'money'
    AND question_text = 'Money should be fully shared.';
END;
$$;

-- 2. A sliding_scale row WITHOUT its scale anchors is rejected.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.game_questions (game_type, tone, question_text)
    VALUES ('sliding_scale', 'connecting', 'No anchors');
    RAISE EXCEPTION 'sliding_scale without anchors was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL; -- expected
  END;
END;
$$;

-- 3. A scenario row WITHOUT options is rejected.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.game_questions (game_type, tone, question_text)
    VALUES ('scenario', 'connecting', 'No options');
    RAISE EXCEPTION 'scenario without options was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL; -- expected
  END;
END;
$$;

-- 4. The existing this_or_that contract still holds (regression).
DO $$
BEGIN
  BEGIN
    INSERT INTO public.game_questions (game_type, tone, question_text)
    VALUES ('this_or_that', 'connecting', 'Missing its options');
    RAISE EXCEPTION 'this_or_that without options was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL; -- expected
  END;
END;
$$;

-- 5. Abandoned sessions must not lock a couple out of the game forever.
--
-- createSession reuses any session with status 'invited' or 'active'. If a
-- couple abandons a game mid-round, nothing moved that session out of
-- 'active', so every later attempt returned the same stuck session and
-- waited on a both_answered that could never flip.
DO $$
DECLARE v_rel uuid; v_a uuid; v_b uuid; v_session uuid; v_status text;
BEGIN
  -- Self-contained: reading whatever relationship happens to exist makes
  -- this skip silently on an empty database and pass vacuously.
  v_a := '6f000000-0000-0000-0000-0000000000a1';
  v_b := '6f000000-0000-0000-0000-0000000000b2';
  v_rel := '6e000000-0000-0000-0000-000000000001';

  INSERT INTO auth.users(id) VALUES (v_a), (v_b) ON CONFLICT DO NOTHING;
  INSERT INTO public.users(id, phone, display_name) VALUES
    (v_a, '+233280000001', 'Stale A'),
    (v_b, '+233280000002', 'Stale B') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships(id, user_a, user_b, status, started_at, created_at)
  VALUES (v_rel, v_a, v_b, 'active', now(), now()) ON CONFLICT DO NOTHING;

  INSERT INTO public.game_sessions
    (relationship_id, game_type, status, initiator_id, tone, total_rounds,
     created_at)
  VALUES (v_rel, 'mirror', 'active', v_a, 'connecting', 8,
          now() - interval '10 days')
  RETURNING id INTO v_session;

  PERFORM public.expire_stale_session_games();

  SELECT status INTO v_status FROM public.game_sessions WHERE id = v_session;
  IF v_status <> 'abandoned' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a 10-day-idle session is still %, so the couple cannot start a new one',
      v_status;
  END IF;

  -- A fresh session must survive the same sweep.
  INSERT INTO public.game_sessions
    (relationship_id, game_type, status, initiator_id, tone, total_rounds,
     created_at)
  VALUES (v_rel, 'scenario', 'active', v_a, 'connecting', 6, now())
  RETURNING id INTO v_session;

  PERFORM public.expire_stale_session_games();

  SELECT status INTO v_status FROM public.game_sessions WHERE id = v_session;
  IF v_status <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh session was expired (%)', v_status;
  END IF;
END $$;

-- 6. this_or_that and truth_or_dare have UI abandon paths, so they are not
--    locked out the way the session games were. But a user who never taps
--    it -- app killed, phone lost, partner ghosted -- leaves an 'active'
--    session that createSession keeps handing back, with no server-side
--    sweep to clear it. The safety net must cover them too.
DO $$
DECLARE v_rel uuid := '6e000000-0000-0000-0000-000000000001';
        v_a uuid := '6f000000-0000-0000-0000-0000000000a1';
        v_session uuid; v_status text; v_type text;
BEGIN
  FOREACH v_type IN ARRAY ARRAY['this_or_that', 'truth_or_dare'] LOOP
    INSERT INTO public.game_sessions
      (relationship_id, game_type, status, initiator_id, tone, total_rounds,
       created_at)
    VALUES (v_rel, v_type, 'active', v_a, 'connecting', 10,
            now() - interval '10 days')
    RETURNING id INTO v_session;

    PERFORM public.expire_stale_session_games();

    SELECT status INTO v_status FROM public.game_sessions WHERE id = v_session;
    IF v_status <> 'abandoned' THEN
      RAISE EXCEPTION
        'CONTRACT VIOLATED: a 10-day-idle % session is still %', v_type, v_status;
    END IF;
  END LOOP;
END $$;

-- 7. abandon_session_game: a couple can leave a stuck game immediately
--    rather than waiting seven days for the sweep.
DO $$
DECLARE v_rel uuid := '6e000000-0000-0000-0000-000000000001';
        v_a uuid := '6f000000-0000-0000-0000-0000000000a1';
        v_b uuid := '6f000000-0000-0000-0000-0000000000b2';
        v_outsider uuid := '6f000000-0000-0000-0000-0000000000c3';
        v_session uuid; v_status text; v_ok boolean;
BEGIN
  INSERT INTO auth.users(id) VALUES (v_outsider) ON CONFLICT DO NOTHING;
  INSERT INTO public.users(id, phone, display_name)
  VALUES (v_outsider, '+233280000003', 'Outsider') ON CONFLICT DO NOTHING;

  INSERT INTO public.game_sessions
    (relationship_id, game_type, status, initiator_id, tone, total_rounds)
  VALUES (v_rel, 'mirror', 'active', v_a, 'connecting', 8)
  RETURNING id INTO v_session;

  -- A non-member cannot abandon someone else's game.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_outsider, 'role','authenticated')::text, true);
  v_ok := false;
  BEGIN
    PERFORM public.abandon_session_game(v_session);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-member abandoned a session';
  END IF;

  -- Either partner can. (The partner who did NOT start it, deliberately:
  -- being stuck is usually the other person's doing.)
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_b, 'role','authenticated')::text, true);
  PERFORM public.abandon_session_game(v_session);

  SELECT status INTO v_status FROM public.game_sessions WHERE id = v_session;
  IF v_status <> 'abandoned' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: session is % after abandon', v_status;
  END IF;

  -- Abandoning again is a no-op, not an error: a double tap must not fail.
  PERFORM public.abandon_session_game(v_session);

  -- A completed session must NOT be reopened or re-marked by this RPC.
  INSERT INTO public.game_sessions
    (relationship_id, game_type, status, initiator_id, tone, total_rounds)
  VALUES (v_rel, 'scenario', 'completed', v_a, 'connecting', 6)
  RETURNING id INTO v_session;

  PERFORM public.abandon_session_game(v_session);
  SELECT status INTO v_status FROM public.game_sessions WHERE id = v_session;
  IF v_status <> 'completed' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: abandon rewrote a completed session to %', v_status;
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
END $$;
