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

  -- With a domain: accepted. Marked inactive so it does not contaminate
  -- the seeded-bank count asserted below.
  INSERT INTO public.game_questions
    (game_type, tone, question_text, value_domain, active)
  VALUES ('love_map', 'connecting', 'a well-formed love map prompt', 'fears', false);
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

-- 5. The Love Map write path: the subject's text becomes the TRUTH, the
--    partner's becomes a guess, and both_answered flips only when both
--    have written.
DO $$
DECLARE v_rel uuid := '7e000000-0000-0000-0000-000000000001';
        v_a uuid := '7f000000-0000-0000-0000-0000000000a1';
        v_b uuid := '7f000000-0000-0000-0000-0000000000b2';
        v_round uuid; v_flipped boolean; v_truth text;
BEGIN
  INSERT INTO public.game_session_rounds
    (relationship_id, round_number, both_answered, active_partner_id)
  VALUES (v_rel, 60, false, v_a)
  RETURNING id INTO v_round;

  -- The guesser writes first: lands in an answer slot, never the truth.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_b, 'role','authenticated')::text, true);
  v_flipped := public.submit_session_game_answer(v_round, 'my guess about A');

  IF EXISTS (SELECT 1 FROM public.mirror_round_truth WHERE round_id = v_round) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a guesser wrote a truth row';
  END IF;
  IF v_flipped THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: both_answered flipped on one writer';
  END IF;

  -- The subject writes: lands in mirror_round_truth and opens the gate.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_a, 'role','authenticated')::text, true);
  v_flipped := public.submit_session_game_answer(v_round, 'what is really true');

  SELECT truth_text INTO v_truth
  FROM public.mirror_round_truth WHERE round_id = v_round;
  IF v_truth IS DISTINCT FROM 'what is really true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the subject''s answer is not the truth row';
  END IF;
  IF NOT v_flipped THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: both_answered did not flip after both wrote';
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 6. Only the subject may judge, and only after the reveal -- on a
--    sessionless round, which judge_mirror_round has never seen before.
--    The plan asserts this function needs no change; an untested assertion
--    is the C2 shape.
DO $$
DECLARE v_rel uuid := '7e000000-0000-0000-0000-000000000001';
        v_a uuid := '7f000000-0000-0000-0000-0000000000a1';
        v_b uuid := '7f000000-0000-0000-0000-0000000000b2';
        v_round uuid; v_ok boolean;
BEGIN
  INSERT INTO public.game_session_rounds
    (relationship_id, round_number, both_answered, active_partner_id)
  VALUES (v_rel, 61, false, v_a)
  RETURNING id INTO v_round;
  INSERT INTO public.mirror_round_truth (round_id, subject_id, truth_text)
  VALUES (v_round, v_a, 'my truth');

  -- Before the reveal: even the subject is refused.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_a, 'role','authenticated')::text, true);
  v_ok := false;
  BEGIN
    PERFORM public.judge_mirror_round(v_round, true);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: judged before both_answered';
  END IF;

  UPDATE public.game_session_rounds SET both_answered = true WHERE id = v_round;

  -- After the reveal: the guesser is still refused.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_b, 'role','authenticated')::text, true);
  v_ok := false;
  BEGIN
    PERFORM public.judge_mirror_round(v_round, true);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  IF v_ok THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-subject judged the round';
  END IF;

  -- The subject, after the reveal: allowed.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_a, 'role','authenticated')::text, true);
  PERFORM public.judge_mirror_round(v_round, true);

  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 7. Love Map never scores: no mirror_scores row may exist for it, and
--    Pulse must never come to reference it.
DO $$
DECLARE v_src text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc
  WHERE proname = 'compute_relationship_game_signals';
  IF v_src LIKE '%love_map%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Pulse signals now reference love_map';
  END IF;

  SELECT prosrc INTO v_src FROM pg_proc WHERE proname = 'finalise_mirror_scores';
  IF v_src LIKE '%love_map%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: finalise_mirror_scores sees love_map';
  END IF;
END $$;

-- 8. The coverage denominator is 60, 15 per domain. The progress bar is
--    meaningless if this drifts.
DO $$
DECLARE v_total int; v_bad text;
BEGIN
  SELECT count(*) INTO v_total
  FROM public.game_questions WHERE game_type = 'love_map' AND active;
  IF v_total <> 60 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expected 60 love_map questions, found %', v_total;
  END IF;

  SELECT string_agg(value_domain || '=' || n, ', ') INTO v_bad
  FROM (
    SELECT value_domain, count(*) AS n
    FROM public.game_questions
    WHERE game_type = 'love_map' AND active
    GROUP BY value_domain HAVING count(*) <> 15
  ) x;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: uneven domains: %', v_bad;
  END IF;
END $$;

ROLLBACK;
