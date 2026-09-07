-- Truth or Dare: an answer must survive the partner answering.
BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-0000000d0a01'),
  ('00000000-0000-0000-0000-0000000d0b02'),
  ('00000000-0000-0000-0000-0000000d0c03') ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000d0a01', '+15556660011', 'TD1'),
  ('00000000-0000-0000-0000-0000000d0b02', '+15556660012', 'TD2'),
  ('00000000-0000-0000-0000-0000000d0c03', '+15556660013', 'TD3')
  ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-0000000d0a01';
  b uuid := '00000000-0000-0000-0000-0000000d0b02';
  c uuid := '00000000-0000-0000-0000-0000000d0c03';
  v_rel uuid;
  v_session uuid;
  v_round uuid;
  v_result jsonb;
  v_a text;
  v_b text;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status, current_round
  )
  VALUES (v_rel, a, 'truth_or_dare', 'active', 1)
  RETURNING id INTO v_session;

  INSERT INTO public.game_session_rounds(session_id, round_number)
  VALUES (v_session, 1) RETURNING id INTO v_round;

  -- A answers first.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_result := public.submit_truth_or_dare_answer(v_round, 'The night we missed the train.');
  IF v_result->>'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'the first answer was rejected: %', v_result;
  END IF;
  IF (v_result->>'both_answered')::boolean THEN
    RAISE EXCEPTION 'one answer should not complete the round';
  END IF;

  -- B answers second. THE ONE THAT MATTERS: this used to overwrite A's
  -- answer with a sentinel, destroying it in a game about hearing what
  -- your partner said.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_result := public.submit_truth_or_dare_answer(v_round, 'Dancing in the kitchen.');

  SELECT answer_a, answer_b INTO v_a, v_b
  FROM public.game_session_rounds WHERE id = v_round;

  IF v_a IS DISTINCT FROM 'The night we missed the train.' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: the second answer destroyed the first (got %)', v_a;
  END IF;
  IF v_b IS DISTINCT FROM 'Dancing in the kitchen.' THEN
    RAISE EXCEPTION 'the second answer was not stored, got %', v_b;
  END IF;
  IF v_a = '__revealed__' OR v_b = '__revealed__' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: the reveal sentinel is back in an answer column';
  END IF;

  -- Both in: the round completes.
  IF NOT (SELECT both_answered FROM public.game_session_rounds WHERE id = v_round) THEN
    RAISE EXCEPTION 'two answers did not complete the round';
  END IF;

  -- Retrying returns the stored state rather than replacing an answer.
  v_result := public.submit_truth_or_dare_answer(v_round, 'Something else entirely.');
  IF v_result->>'existing' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'a retried submit was not idempotent: %', v_result;
  END IF;
  SELECT answer_b INTO v_b FROM public.game_session_rounds WHERE id = v_round;
  IF v_b <> 'Dancing in the kitchen.' THEN
    RAISE EXCEPTION 'a retry overwrote a stored answer, got %', v_b;
  END IF;

  -- An outsider cannot answer someone else's round.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', c, 'role', 'authenticated')::text, true);
  v_result := public.submit_truth_or_dare_answer(v_round, 'Intruding.');
  IF v_result->>'code' IS DISTINCT FROM 'FORBIDDEN' THEN
    RAISE EXCEPTION 'an outsider answered, got %', v_result;
  END IF;

  -- Empty and oversized answers are refused rather than stored.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  IF (public.submit_truth_or_dare_answer(v_round, '   ')->>'code')
     IS DISTINCT FROM 'EMPTY_ANSWER' THEN
    RAISE EXCEPTION 'an empty answer was accepted';
  END IF;
  IF (public.submit_truth_or_dare_answer(v_round, repeat('x', 2100))->>'code')
     IS DISTINCT FROM 'ANSWER_TOO_LONG' THEN
    RAISE EXCEPTION 'an unbounded answer was accepted';
  END IF;
END $$;

-- anon may not answer at all.
DO $$
DECLARE
  v_raised boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('role', 'anon')::text, true);
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.submit_truth_or_dare_answer(
      '00000000-0000-0000-0000-000000000001', 'x');
  EXCEPTION WHEN OTHERS THEN
    v_raised := true;
  END;
  RESET ROLE;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'anon can submit a Truth or Dare answer';
  END IF;
END $$;

ROLLBACK;
