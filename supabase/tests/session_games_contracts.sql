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
