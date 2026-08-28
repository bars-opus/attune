-- Contract tests for Love Map. Run against a database with the migrations
-- applied. Each block RAISEs on violation, so a silent pass means the
-- contract holds.
--
-- Self-contained: it creates its own users and relationship rather than
-- depending on ambient fixtures. An earlier draft skipped every check when
-- public.relationships happened to be empty, which made it pass vacuously.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('7f000000-0000-0000-0000-0000000000a1'),
  ('7f000000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.users (id, phone, display_name) VALUES
  ('7f000000-0000-0000-0000-0000000000a1', '+233270000001', 'LoveMap A'),
  ('7f000000-0000-0000-0000-0000000000b2', '+233270000002', 'LoveMap B')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7e000000-0000-0000-0000-000000000001',
        '7f000000-0000-0000-0000-0000000000a1',
        '7f000000-0000-0000-0000-0000000000b2',
        'active', now(), now())
ON CONFLICT (id) DO NOTHING;

-- 1. A round must have exactly one owner: a session, or a relationship.
DO $$
DECLARE v_rel uuid := '7e000000-0000-0000-0000-000000000001';
BEGIN
  -- Neither owner.
  BEGIN
    INSERT INTO public.game_session_rounds (round_number, both_answered)
    VALUES (1, false);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a round with no owner was accepted';
  EXCEPTION
    WHEN check_violation OR not_null_violation THEN NULL;
  END;

  -- Both owners. The session is created here rather than selected: with no
  -- game_sessions rows the subselect returns NULL, only one owner is set,
  -- and the check passes for the wrong reason.
  INSERT INTO public.game_sessions
    (id, relationship_id, game_type, status, initiator_id, tone, total_rounds)
  VALUES ('7d000000-0000-0000-0000-000000000001', v_rel, 'mirror', 'active',
          '7f000000-0000-0000-0000-0000000000a1', 'connecting', 8)
  ON CONFLICT (id) DO NOTHING;

  BEGIN
    INSERT INTO public.game_session_rounds
      (session_id, relationship_id, round_number, both_answered)
    VALUES ('7d000000-0000-0000-0000-000000000001', v_rel, 99, false);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a round with both owners was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  -- Exactly one owner: must be accepted.
  INSERT INTO public.game_session_rounds
    (relationship_id, round_number, both_answered)
  VALUES (v_rel, 1, false);
END $$;

-- 2. love_map questions require a value_domain.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.game_questions (game_type, tone, question_text)
    VALUES ('love_map', 'connecting', 'missing its domain');
    RAISE EXCEPTION 'CONTRACT VIOLATED: love_map without value_domain accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- With a domain: accepted.
  INSERT INTO public.game_questions
    (game_type, tone, question_text, value_domain)
  VALUES ('love_map', 'connecting', 'a well-formed love map prompt', 'fears');
END $$;

-- 3. Regression: the pre-existing game types still hold their own branches.
--    A widening must never relax a neighbour.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.game_questions (game_type, tone, question_text)
    VALUES ('sliding_scale', 'connecting', 'missing its anchors');
    RAISE EXCEPTION 'CONTRACT VIOLATED: sliding_scale without anchors accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.game_questions (game_type, tone, question_text)
    VALUES ('this_or_that', 'connecting', 'missing its options');
    RAISE EXCEPTION 'CONTRACT VIOLATED: this_or_that without options accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

-- 4. The reveal gate holds for sessionless rounds: a Love Map guess is
--    withheld until both_answered, exactly as for a session round.
DO $$
DECLARE v_rel uuid := '7e000000-0000-0000-0000-000000000001';
        v_round uuid; v_a text; v_rows int;
BEGIN
  INSERT INTO public.game_session_rounds
    (relationship_id, round_number, both_answered, answer_a)
  VALUES (v_rel, 50, false, 'a guess that must stay hidden')
  RETURNING id INTO v_round;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7f000000-0000-0000-0000-0000000000a1',
                      'role','authenticated')::text, true);

  SELECT count(*) INTO v_rows FROM public.get_revealed_round(v_round);
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member cannot read a sessionless round at all';
  END IF;

  SELECT answer_a INTO v_a FROM public.get_revealed_round(v_round);
  IF v_a IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a guess leaked before both_answered';
  END IF;

  -- After the gate opens the guess is visible.
  UPDATE public.game_session_rounds SET both_answered = true WHERE id = v_round;
  SELECT answer_a INTO v_a FROM public.get_revealed_round(v_round);
  IF v_a IS DISTINCT FROM 'a guess that must stay hidden' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the guess is still hidden after reveal';
  END IF;

  -- A non-member sees nothing, gate open or not.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7f000000-0000-0000-0000-0000000000c3',
                      'role','authenticated')::text, true);
  SELECT count(*) INTO v_rows FROM public.get_revealed_round(v_round);
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-member read a sessionless round';
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
END $$;

ROLLBACK;
