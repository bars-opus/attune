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
