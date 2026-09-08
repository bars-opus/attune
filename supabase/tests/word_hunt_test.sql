-- Word Hunt contracts.
--
-- The list in WORD_HUNT_GAME_SPEC.md §10, proven against the
-- authenticated role rather than by reading function source. Two of
-- these exist because the equivalent claim was made and was false: the
-- puzzle was readable from the table, and the session was writable
-- straight past every RPC.
BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-00000000e001'),
  ('00000000-0000-0000-0000-00000000e002'),
  ('00000000-0000-0000-0000-00000000e003') ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-00000000e001', '+15554450011', 'WH1'),
  ('00000000-0000-0000-0000-00000000e002', '+15554450012', 'WH2'),
  ('00000000-0000-0000-0000-00000000e003', '+15554450013', 'WH3')
  ON CONFLICT (id) DO NOTHING;

INSERT INTO public.relationships(id, user_a, user_b, status)
VALUES ('00000000-0000-0000-0000-0000000000e1',
        '00000000-0000-0000-0000-00000000e001',
        '00000000-0000-0000-0000-00000000e002', 'active')
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION pg_temp.act(p_user uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.new_session(p_key text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
  -- Age this couple's earlier sessions out of the limiter's one-hour
  -- window. Each fixture below wants a session of its own, and the
  -- limiter is not what any of them is testing.
  UPDATE public.game_sessions
     SET created_at = created_at - interval '2 hours'
   WHERE relationship_id = '00000000-0000-0000-0000-0000000000e1'
     AND created_at > now() - interval '1 hour';

  v := public.word_hunt_create_session(
    '00000000-0000-0000-0000-0000000000e1', p_key);
  IF v ? 'error' THEN
    RAISE EXCEPTION 'the fixture could not create a session (%): %',
      p_key, v->>'code';
  END IF;
  RETURN (v->>'session_id')::uuid;
END; $$;

-- ---------------------------------------------------------------------
-- The scanner, against grids built to break it (§4.2).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.blank() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_agg(repeat('X', 10)) FROM generate_series(1, 10);
$$;

CREATE OR REPLACE FUNCTION pg_temp.plant(
  g jsonb, w text, r int, c int, dr int, dc int
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE k int; rr int; cc int; out jsonb := g;
BEGIN
  FOR k IN 0..char_length(w) - 1 LOOP
    rr := r + dr * k; cc := c + dc * k;
    out := jsonb_set(out, ARRAY[rr::text],
      to_jsonb(overlay(out->>rr placing substr(w, k + 1, 1)
                       from cc + 1 for 1)));
  END LOOP;
  RETURN out;
END; $$;

DO $$
DECLARE
  d int; n int; dr int; dc int;
BEGIN
  -- One placement in each of the eight directions counts as one.
  FOR d IN 0..7 LOOP
    dr := (public.word_hunt_directions()->d->>0)::int;
    dc := (public.word_hunt_directions()->d->>1)::int;
    n := public.word_hunt_count_occurrences(
      pg_temp.plant(pg_temp.blank(), 'LOVE', 4, 4, dr, dc), 'LOVE');
    IF n <> 1 THEN
      RAISE EXCEPTION 'direction % counted % occurrences, not 1', d, n;
    END IF;

    -- A second, planted in that direction, must be seen.
    n := public.word_hunt_count_occurrences(
      pg_temp.plant(
        pg_temp.plant(pg_temp.blank(), 'LOVE', 0, 0, 0, 1),
        'LOVE', 5, 5, dr, dc), 'LOVE');
    IF n <> 2 THEN
      RAISE EXCEPTION 'a duplicate in direction % was missed (n=%)', d, n;
    END IF;
  END LOOP;

  -- Every corner, running off each edge.
  IF public.word_hunt_count_occurrences(
       pg_temp.plant(pg_temp.blank(), 'LOVE', 0, 0, 0, 1), 'LOVE') <> 1
     OR public.word_hunt_count_occurrences(
       pg_temp.plant(pg_temp.blank(), 'LOVE', 9, 9, 0, -1), 'LOVE') <> 1
     OR public.word_hunt_count_occurrences(
       pg_temp.plant(pg_temp.blank(), 'LOVE', 0, 9, 1, 0), 'LOVE') <> 1
     OR public.word_hunt_count_occurrences(
       pg_temp.plant(pg_temp.blank(), 'LOVE', 9, 0, -1, 0), 'LOVE') <> 1 THEN
    RAISE EXCEPTION 'an edge or corner placement was miscounted';
  END IF;

  -- The longest legal diagonal.
  IF public.word_hunt_count_occurrences(
       pg_temp.plant(pg_temp.blank(), 'INTIMATE', 0, 0, 1, 1),
       'INTIMATE') <> 1 THEN
    RAISE EXCEPTION 'the maximum-length diagonal was miscounted';
  END IF;

  -- Reversed where it was placed forwards: a real second occurrence.
  IF public.word_hunt_count_occurrences(
       pg_temp.plant(
         pg_temp.plant(pg_temp.blank(), 'LOVE', 0, 0, 0, 1),
         'LOVE', 5, 5, 0, -1), 'LOVE') <> 2 THEN
    RAISE EXCEPTION 'a reversed duplicate was missed';
  END IF;

  -- A repeated letter must not double-count.
  IF public.word_hunt_count_occurrences(
       pg_temp.plant(pg_temp.blank(), 'GIGGLE', 3, 2, 0, 1),
       'GIGGLE') <> 1 THEN
    RAISE EXCEPTION 'GIGGLE was miscounted';
  END IF;

  -- A palindrome reads the same both ways from ONE physical run, and is
  -- canonicalised by its sorted endpoints to count once.
  IF public.word_hunt_count_occurrences(
       pg_temp.plant(pg_temp.blank(), 'ROTOR', 2, 2, 0, 1), 'ROTOR') <> 1 THEN
    RAISE EXCEPTION 'a palindrome was counted twice';
  END IF;

  -- Two runs sharing a cell are still two.
  IF public.word_hunt_count_occurrences(
       pg_temp.plant(
         pg_temp.plant(pg_temp.blank(), 'LOVE', 4, 4, 0, 1),
         'LOVE', 4, 4, 1, 0), 'LOVE') <> 2 THEN
    RAISE EXCEPTION 'overlapping occurrences were miscounted';
  END IF;
END $$;

-- Malformed input raises rather than returning a misleading count.
DO $$
DECLARE
  v_case text;
  v_raised boolean;
BEGIN
  FOREACH v_case IN ARRAY
    ARRAY['rows', 'ragged', 'long', 'nonletter', 'null', 'lower']
  LOOP
    v_raised := false;
    BEGIN
      PERFORM CASE v_case
        WHEN 'rows' THEN public.word_hunt_count_occurrences(
          (SELECT jsonb_agg(repeat('X', 10)) FROM generate_series(1, 9)), 'LOVE')
        WHEN 'ragged' THEN public.word_hunt_count_occurrences(
          jsonb_set(pg_temp.blank(), '{3}', '"XXX"'), 'LOVE')
        -- A row of 12 uppercase letters: right alphabet, wrong length.
        -- The anchored pattern is what rejects it.
        WHEN 'long' THEN public.word_hunt_count_occurrences(
          jsonb_set(pg_temp.blank(), '{3}', '"XXXXXXXXXXXX"'), 'LOVE')
        WHEN 'nonletter' THEN public.word_hunt_count_occurrences(
          jsonb_set(pg_temp.blank(), '{3}', '"XX3XXXXXXX"'), 'LOVE')
        WHEN 'null' THEN public.word_hunt_count_occurrences(NULL, 'LOVE')
        WHEN 'lower' THEN public.word_hunt_count_occurrences(
          pg_temp.blank(), 'love')
      END;
    EXCEPTION WHEN OTHERS THEN v_raised := true;
    END;
    IF NOT v_raised THEN
      RAISE EXCEPTION 'malformed input "%" did not raise', v_case;
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- The generator, and the trigger that does not trust it.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_words text[];
  v_weights jsonb;
  v_word text;
  v_puzzle jsonb;
  i int;
BEGIN
  SELECT words, direction_weights INTO v_words, v_weights
  FROM public.word_hunt_configs WHERE version = 'v1';

  FOR i IN 1..60 LOOP
    v_word := v_words[1 + floor(random() * cardinality(v_words))::int];
    v_puzzle := public.word_hunt_generate(v_word, v_weights);
    IF public.word_hunt_count_occurrences(v_puzzle->'grid', v_word) <> 1 THEN
      RAISE EXCEPTION 'the generator produced an ambiguous grid for %', v_word;
    END IF;
    IF jsonb_array_length(v_puzzle->'placement') <> char_length(v_word) THEN
      RAISE EXCEPTION 'the placement for % is the wrong length', v_word;
    END IF;
  END LOOP;

  -- A word not in the config, and a word breaking the length rule, are
  -- both refused rather than placed.
  BEGIN
    PERFORM public.word_hunt_generate('AFFECTION', v_weights);
    RAISE EXCEPTION 'a 9-letter word was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'a 9-letter word was accepted' THEN RAISE; END IF;
  END;
END $$;

-- The config validator holds its own rules, so a hand edit cannot
-- reintroduce the mistakes the first draft of the word list made.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.word_hunt_configs(version, words, direction_weights)
    VALUES ('bad-long', ARRAY['AFFECTION'],
            jsonb_build_array(1, 1, 1, 1, 1, 1, 1, 1));
    RAISE EXCEPTION 'a 9-letter word entered the config';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'a 9-letter word entered the config' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO public.word_hunt_configs(version, words, direction_weights)
    VALUES ('bad-short', ARRAY['LOV'],
            jsonb_build_array(1, 1, 1, 1, 1, 1, 1, 1));
    RAISE EXCEPTION 'a 3-letter word entered the config';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'a 3-letter word entered the config' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO public.word_hunt_configs(version, words, direction_weights)
    VALUES ('bad-case', ARRAY['love'],
            jsonb_build_array(1, 1, 1, 1, 1, 1, 1, 1));
    RAISE EXCEPTION 'a lowercase word entered the config';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'a lowercase word entered the config' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO public.word_hunt_configs(version, words, direction_weights)
    VALUES ('bad-dup', ARRAY['LOVE', 'LOVE'],
            jsonb_build_array(1, 1, 1, 1, 1, 1, 1, 1));
    RAISE EXCEPTION 'a duplicate word entered the config';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'a duplicate word entered the config' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO public.word_hunt_configs(version, words, direction_weights)
    VALUES ('bad-empty', ARRAY[]::text[],
            jsonb_build_array(1, 1, 1, 1, 1, 1, 1, 1));
    RAISE EXCEPTION 'an empty word list entered the config';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'an empty word list entered the config' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO public.word_hunt_configs(version, words, direction_weights)
    VALUES ('bad-w', ARRAY['LOVE'],
            jsonb_build_array(0, 0, 0, 0, 0, 0, 0, 0));
    RAISE EXCEPTION 'zero-sum weights entered the config';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'zero-sum weights entered the config' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO public.word_hunt_configs(version, words, direction_weights)
    VALUES ('bad-neg', ARRAY['LOVE'],
            jsonb_build_array(1, 1, 1, 1, 1, 1, 1, -1));
    RAISE EXCEPTION 'a negative weight entered the config';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'a negative weight entered the config' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO public.word_hunt_configs(version, words, direction_weights)
    VALUES ('bad-n', ARRAY['LOVE'], jsonb_build_array(1, 1, 1));
    RAISE EXCEPTION 'three weights entered the config';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'three weights entered the config' THEN RAISE; END IF;
  END;
END $$;

-- A config that has been played on is immutable; retirement is not.
DO $$
DECLARE
  v_raised boolean := false;
  v_sid uuid;
BEGIN
  -- The guard only bites once a session has pinned the version, so pin
  -- one first. Without this the UPDATE below legitimately succeeds and
  -- the assertion would be testing nothing.
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  v_sid := pg_temp.new_session('wh-key-pin');
  IF NOT EXISTS (SELECT 1 FROM public.word_hunt_puzzles
                  WHERE word_list_version = 'v1') THEN
    RAISE EXCEPTION 'no session pinned v1, so immutability is untested';
  END IF;

  BEGIN
    UPDATE public.word_hunt_configs
       SET words = ARRAY['LOVE'] WHERE version = 'v1';
  EXCEPTION WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'a config that has been played on was rewritten';
  END IF;

  -- Retiring it must still work: it stops new sessions drawing from the
  -- version without touching what a past session pinned.
  UPDATE public.word_hunt_configs SET retired_at = now() WHERE version = 'v1';
  UPDATE public.word_hunt_configs SET retired_at = NULL WHERE version = 'v1';

  PERFORM public.word_hunt_decline_session(v_sid);
END $$;

-- THE UNIQUENESS SCAN, WHERE IT ACTUALLY BITES.
--
-- A black-box test of the generator cannot prove the scan runs. Measured
-- here rather than assumed: 500 generated grids for each of four
-- four-letter words produced an accidental second occurrence ZERO times,
-- because a 26-letter random fill almost never repeats a word by chance.
-- So a generator with the scan deleted passes any "generate many and
-- check" test comfortably, and such a test asserts nothing.
--
-- What the scan is actually for is the grid that IS ambiguous, whatever
-- produced it. That case is constructed directly and pushed at the
-- puzzle table, whose trigger runs the same scanner: an ambiguous puzzle
-- must be refused storage. This is the failure that matters -- an
-- ambiguous grid tells a player who genuinely found the word that they
-- are wrong.
DO $$
DECLARE
  v_sid uuid;
  v_grid jsonb;
  v_place jsonb;
  k int;
  v_raised boolean;
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  v_sid := pg_temp.new_session('wh-key-scan');
  DELETE FROM public.word_hunt_puzzles WHERE session_id = v_sid;

  -- LOVE twice: once at (0,0) running east, once at (5,5) running east.
  v_grid := pg_temp.plant(
    pg_temp.plant(pg_temp.blank(), 'LOVE', 0, 0, 0, 1),
    'LOVE', 5, 5, 0, 1);
  v_place := jsonb_build_array(
    jsonb_build_array(0, 0), jsonb_build_array(0, 1),
    jsonb_build_array(0, 2), jsonb_build_array(0, 3));

  v_raised := false;
  BEGIN
    INSERT INTO public.word_hunt_puzzles(
      session_id, word, grid, placement, word_list_version)
    VALUES (v_sid, 'LOVE', v_grid, v_place, 'v1');
  EXCEPTION WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION
      'an ambiguous puzzle was stored: the uniqueness scan is not running';
  END IF;

  -- The same grid with only ONE occurrence stores fine, so the rejection
  -- above is about ambiguity and not about the fixture being malformed.
  v_grid := pg_temp.plant(pg_temp.blank(), 'LOVE', 0, 0, 0, 1);
  INSERT INTO public.word_hunt_puzzles(
    session_id, word, grid, placement, word_list_version)
  VALUES (v_sid, 'LOVE', v_grid, v_place, 'v1');

  -- And the validator's other independent rules.
  DELETE FROM public.word_hunt_puzzles WHERE session_id = v_sid;
  FOREACH k IN ARRAY ARRAY[1, 2, 3, 4] LOOP
    v_raised := false;
    BEGIN
      CASE k
        -- A placement that does not spell the word.
        WHEN 1 THEN
          INSERT INTO public.word_hunt_puzzles(
            session_id, word, grid, placement, word_list_version)
          VALUES (v_sid, 'LOVE', v_grid,
            jsonb_build_array(
              jsonb_build_array(1, 0), jsonb_build_array(1, 1),
              jsonb_build_array(1, 2), jsonb_build_array(1, 3)), 'v1');
        -- A placement that BENDS but whose cells still spell the word.
        --
        -- THE BEND, isolated from every other rule.
        --
        -- Three things had to line up for this case to reach the
        -- straight-line check at all, and each one masked it in turn:
        --   * the bent cells must genuinely spell the word, or the
        --     spelling check fires first;
        --   * the bend must be at k >= 2, because the k = 1 step is what
        --     ESTABLISHES the direction -- a "bend" there is simply a
        --     different straight line;
        --   * the grid must still contain exactly one STRAIGHT occurrence,
        --     or the uniqueness scan rejects it first.
        -- So: LOVE runs straight down column 0 (the legitimate single
        -- occurrence), and a second L,O,V,E is laid out bent across
        -- row 5 turning south, which is what the placement points at.
        WHEN 2 THEN
          INSERT INTO public.word_hunt_puzzles(
            session_id, word, grid, placement, word_list_version)
          VALUES (v_sid, 'LOVE',
            jsonb_set(
              jsonb_set(
                jsonb_set(
                  jsonb_set(
                    jsonb_set(
                      jsonb_set(pg_temp.blank(), '{0}', '"LXXXXXXXXX"'),
                      '{1}', '"OXXXXXXXXX"'),
                    '{2}', '"VXXXXXXXXX"'),
                  '{3}', '"EXXXXXXXXX"'),
                '{5}', '"XXXXLOVXXX"'),
              '{6}', '"XXXXXXEXXX"'),
            jsonb_build_array(
              jsonb_build_array(5, 4), jsonb_build_array(5, 5),
              jsonb_build_array(5, 6), jsonb_build_array(6, 6)), 'v1');
        -- A word that is not in the referenced config.
        WHEN 3 THEN
          INSERT INTO public.word_hunt_puzzles(
            session_id, word, grid, placement, word_list_version)
          VALUES (v_sid, 'ZZZZ',
            pg_temp.plant(pg_temp.blank(), 'ZZZZ', 0, 0, 0, 1),
            v_place, 'v1');
        -- A placement out of bounds.
        WHEN 4 THEN
          INSERT INTO public.word_hunt_puzzles(
            session_id, word, grid, placement, word_list_version)
          VALUES (v_sid, 'LOVE', v_grid,
            jsonb_build_array(
              jsonb_build_array(0, 7), jsonb_build_array(0, 8),
              jsonb_build_array(0, 9), jsonb_build_array(0, 10)), 'v1');
      END CASE;
    EXCEPTION WHEN OTHERS THEN v_raised := true;
    END;
    IF NOT v_raised THEN
      RAISE EXCEPTION 'the puzzle validator accepted malformed case %', k;
    END IF;
  END LOOP;

  PERFORM public.word_hunt_decline_session(v_sid);
END $$;

-- ---------------------------------------------------------------------
-- The attempt transition trigger, directly.
-- ---------------------------------------------------------------------
-- These are the invariants beneath the RPCs. Asserted here rather than
-- only through gameplay, because a future RPC that gets one of them
-- wrong is exactly what this trigger exists to stop.
DO $$
DECLARE
  v_sid uuid;
  v_case text;
  v_raised boolean;
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  v_sid := pg_temp.new_session('wh-key-trigger');
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e002');
  PERFORM public.word_hunt_accept_session(v_sid);
  PERFORM public.word_hunt_start(v_sid);

  FOREACH v_case IN ARRAY ARRAY[
    'clock', 'count', 'submission_time', 'reopen', 'retime']
  LOOP
    v_raised := false;
    BEGIN
      CASE v_case
        WHEN 'clock' THEN
          UPDATE public.word_hunt_attempts
             SET started_at = started_at - interval '5 minutes'
           WHERE session_id = v_sid;
        WHEN 'count' THEN
          UPDATE public.word_hunt_attempts
             SET submission_count = submission_count - 1
           WHERE session_id = v_sid;
        WHEN 'submission_time' THEN
          UPDATE public.word_hunt_attempts
             SET last_submission_at = started_at + interval '1 second'
           WHERE session_id = v_sid;
          UPDATE public.word_hunt_attempts
             SET last_submission_at = started_at
           WHERE session_id = v_sid;
        WHEN 'reopen' THEN
          UPDATE public.word_hunt_attempts
             SET status = 'gave_up', finished_at = now()
           WHERE session_id = v_sid;
          UPDATE public.word_hunt_attempts
             SET status = 'in_progress', finished_at = NULL
           WHERE session_id = v_sid;
        WHEN 'retime' THEN
          UPDATE public.word_hunt_attempts
             SET finished_at = now() + interval '1 hour'
           WHERE session_id = v_sid;
      END CASE;
    EXCEPTION WHEN OTHERS THEN v_raised := true;
    END;
    IF NOT v_raised THEN
      RAISE EXCEPTION 'the transition trigger allowed "%"', v_case;
    END IF;
  END LOOP;

  PERFORM public.word_hunt_decline_session(v_sid);
END $$;

-- ---------------------------------------------------------------------
-- A session, played through.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE wh_ctx(sid uuid);
GRANT SELECT ON wh_ctx TO authenticated;

DO $$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  v := public.word_hunt_create_session(
    '00000000-0000-0000-0000-0000000000e1', 'wh-key-1');
  IF v ? 'error' THEN RAISE EXCEPTION 'create failed: %', v; END IF;
  INSERT INTO wh_ctx VALUES ((v->>'session_id')::uuid);

  -- The same key returns the same session rather than a second one.
  v := public.word_hunt_create_session(
    '00000000-0000-0000-0000-0000000000e1', 'wh-key-1');
  IF (v->>'session_id')::uuid <> (SELECT sid FROM wh_ctx)
     OR NOT (v->>'existing')::boolean THEN
    RAISE EXCEPTION 'the idempotency key did not hold: %', v;
  END IF;

  -- A puzzle exists behind the invitation, and it is legal.
  IF NOT EXISTS (SELECT 1 FROM public.word_hunt_puzzles
                  WHERE session_id = (SELECT sid FROM wh_ctx)) THEN
    RAISE EXCEPTION 'an invitation was created with no puzzle';
  END IF;
END $$;

-- A non-member reaches nothing.
DO $$
DECLARE v jsonb; sid uuid := (SELECT sid FROM wh_ctx);
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e003');
  FOR v IN SELECT * FROM (VALUES
    (public.get_word_hunt_state(sid)),
    (public.word_hunt_start(sid)),
    (public.word_hunt_submit(sid, '[[0,0],[0,1],[0,2],[0,3]]'::jsonb)),
    (public.word_hunt_give_up(sid)),
    (public.word_hunt_accept_session(sid)),
    (public.word_hunt_decline_session(sid))
  ) t(v) LOOP
    IF v->>'code' IS DISTINCT FROM 'FORBIDDEN' THEN
      RAISE EXCEPTION 'a non-member was not refused: %', v;
    END IF;
  END LOOP;
END $$;

-- Signed out reaches nothing.
DO $$
DECLARE v jsonb; sid uuid := (SELECT sid FROM wh_ctx);
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  FOR v IN SELECT * FROM (VALUES
    (public.get_word_hunt_state(sid)),
    (public.word_hunt_start(sid)),
    (public.word_hunt_submit(sid, '[[0,0],[0,1],[0,2],[0,3]]'::jsonb)),
    (public.word_hunt_give_up(sid)),
    (public.word_hunt_create_session(
      '00000000-0000-0000-0000-0000000000e1', 'x'))
  ) t(v) LOOP
    IF v->>'code' IS DISTINCT FROM 'UNAUTHORIZED' THEN
      RAISE EXCEPTION 'an unauthenticated call was not refused: %', v;
    END IF;
  END LOOP;
END $$;

-- The initiator cannot accept their own invitation; the invitee can.
DO $$
DECLARE v jsonb; sid uuid := (SELECT sid FROM wh_ctx);
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  v := public.word_hunt_accept_session(sid);
  IF v->>'code' IS DISTINCT FROM 'FORBIDDEN' THEN
    RAISE EXCEPTION 'the initiator accepted their own invite: %', v;
  END IF;

  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e002');
  v := public.word_hunt_accept_session(sid);
  IF v ? 'error' THEN RAISE EXCEPTION 'accept failed: %', v; END IF;

  -- Accepting starts nobody's clock, and Word Hunt has no turn owner.
  IF EXISTS (SELECT 1 FROM public.word_hunt_attempts WHERE session_id = sid) THEN
    RAISE EXCEPTION 'accepting started a clock';
  END IF;
  IF (SELECT current_turn_user_id FROM public.game_sessions WHERE id = sid)
     IS NOT NULL THEN
    RAISE EXCEPTION 'word hunt assigned a turn owner';
  END IF;
END $$;

-- Before Start: no grid, no word, no placement, no partner.
DO $$
DECLARE v jsonb; sid uuid := (SELECT sid FROM wh_ctx);
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  v := public.get_word_hunt_state(sid);
  IF v ? 'grid' OR v ? 'word' OR v ? 'placement'
     OR v ? 'partner_status' OR v ? 'partner_elapsed_ms' THEN
    RAISE EXCEPTION 'state before Start disclosed the puzzle: %',
      (SELECT jsonb_object_agg(k, 'present')
       FROM jsonb_object_keys(v) k
       WHERE k IN ('grid','word','placement','partner_status',
                   'partner_elapsed_ms'));
  END IF;
  -- Submitting without starting is refused rather than silently timed.
  IF public.word_hunt_submit(sid, '[[0,0],[0,1],[0,2],[0,3]]'::jsonb)->>'code'
     <> 'NOT_STARTED' THEN
    RAISE EXCEPTION 'submit worked without starting';
  END IF;
  IF public.word_hunt_give_up(sid)->>'code' IS DISTINCT FROM 'NOT_STARTED' THEN
    RAISE EXCEPTION 'give up worked without starting';
  END IF;
END $$;

-- Start is idempotent: the clock is set once and the puzzle never moves.
DO $$
DECLARE
  v1 jsonb; v2 jsonb; sid uuid := (SELECT sid FROM wh_ctx);
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  v1 := public.word_hunt_start(sid);
  IF v1 ? 'error' THEN RAISE EXCEPTION 'start failed: %', v1; END IF;
  IF NOT (v1 ? 'grid' AND v1 ? 'word') THEN
    RAISE EXCEPTION 'start returned no puzzle: %', v1;
  END IF;

  -- The lost-response retry: same timestamp, same puzzle, no new clock.
  v2 := public.word_hunt_start(sid);
  IF v2->>'my_started_at' <> v1->>'my_started_at'
     OR v2->'grid' <> v1->'grid'
     OR v2->>'word' <> v1->>'word' THEN
    RAISE EXCEPTION 'a Start retry moved the clock or the puzzle';
  END IF;

  IF (SELECT count(*) FROM public.word_hunt_attempts
       WHERE session_id = sid) <> 1 THEN
    RAISE EXCEPTION 'a retry created a second attempt';
  END IF;
END $$;

-- A structurally invalid drag is refused; a scattered set is not a drag.
DO $$
DECLARE
  sid uuid := (SELECT sid FROM wh_ctx);
  v_word text;
  v_place jsonb;
  v jsonb;
  v_scrambled jsonb;
  v_k int;
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  SELECT word, placement INTO v_word, v_place
  FROM public.word_hunt_puzzles WHERE session_id = sid;

  -- Wrong length.
  IF public.word_hunt_submit(sid, '[[0,0],[0,1]]'::jsonb)->>'code'
     <> 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'a short selection was accepted';
  END IF;

  -- OUT OF BOUNDS, at the correct length. The previous version of this
  -- case used four cells for a word that might be longer, so it was
  -- killed by the length check and never reached the bounds check at all
  -- -- a mutant that deleted the bounds check survived it.
  v := jsonb_build_array();
  FOR v_k IN 0..char_length(v_word) - 1 LOOP
    v := v || jsonb_build_array(jsonb_build_array(-1, v_k));
  END LOOP;
  IF public.word_hunt_submit(sid, v)->>'code' IS DISTINCT FROM 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'an out-of-bounds selection at the right length was accepted';
  END IF;

  -- Off the far edge too, so the check is not merely "no negatives".
  v := jsonb_build_array();
  FOR v_k IN 0..char_length(v_word) - 1 LOOP
    v := v || jsonb_build_array(jsonb_build_array(10, v_k));
  END LOOP;
  IF public.word_hunt_submit(sid, v)->>'code' IS DISTINCT FROM 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'a selection past row 9 was accepted';
  END IF;

  -- THE RIGHT CELLS IN THE WRONG ORDER -- the point of validating a drag
  -- rather than a set. Swapping the first two cells of the real placement
  -- keeps every cell and every letter and destroys the line, so a set
  -- comparison accepts it and a drag comparison does not.
  v_scrambled := jsonb_build_array(v_place->1, v_place->0);
  FOR v_k IN 2..jsonb_array_length(v_place) - 1 LOOP
    v_scrambled := v_scrambled || jsonb_build_array(v_place->v_k);
  END LOOP;
  IF public.word_hunt_submit(sid, v_scrambled)->>'code' IS DISTINCT FROM 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'the right cells in the wrong order were accepted';
  END IF;

  -- A legal straight line of the right length that is simply elsewhere is
  -- a MISS, not an error: the shape was fine, the answer was wrong. This
  -- separates "not a drag" from "not the word".
  IF (SELECT count(*) FROM jsonb_array_elements(v_place) e
       WHERE (e->>0)::int = 0) = 0 THEN
    v := jsonb_build_array();
    FOR v_k IN 0..char_length(v_word) - 1 LOOP
      v := v || jsonb_build_array(jsonb_build_array(0, v_k));
    END LOOP;
    PERFORM pg_sleep(0.35);
    v := public.word_hunt_submit(sid, v);
    IF v ? 'error' THEN
      RAISE EXCEPTION 'a legal line elsewhere was rejected as malformed: %', v;
    END IF;
    IF (v->>'hit')::boolean THEN
      RAISE EXCEPTION 'a line through no placement cell reported a hit';
    END IF;
  END IF;
END $$;

-- A miss says nothing, costs nothing, and does not end the attempt.
DO $$
DECLARE
  sid uuid := (SELECT sid FROM wh_ctx);
  v jsonb; v_before int; v_after int;
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  SELECT submission_count INTO v_before FROM public.word_hunt_attempts
  WHERE session_id = sid AND user_id = '00000000-0000-0000-0000-00000000e001';

  -- A legal straight drag that is not the word. Row 0 eastward is legal
  -- shape; the word is somewhere, but four cells of row 0 will not be it
  -- unless the puzzle placed it there, so pick a row it did not use.
  SELECT jsonb_agg(jsonb_build_array(r, c) ORDER BY c)
    INTO v
  FROM (
    SELECT (SELECT r FROM (
              SELECT gs AS r FROM generate_series(0, 9) gs
              WHERE NOT EXISTS (
                SELECT 1 FROM jsonb_array_elements(p.placement) e
                WHERE (e->>0)::int = gs)
              LIMIT 1) x) AS r, c
    FROM public.word_hunt_puzzles p,
         generate_series(0, char_length(p.word) - 1) c
    WHERE p.session_id = sid
  ) cells;

  IF v IS NOT NULL THEN
    PERFORM pg_sleep(0.35);  -- clear the 300ms limiter
    v := public.word_hunt_submit(sid, v);
    IF v ? 'error' THEN RAISE EXCEPTION 'a legal miss errored: %', v; END IF;
    IF (v->>'hit')::boolean THEN
      RAISE EXCEPTION 'a row with no placement cells reported a hit';
    END IF;
    IF v->>'my_status' IS DISTINCT FROM 'in_progress' THEN
      RAISE EXCEPTION 'a miss ended the attempt';
    END IF;
    IF v ? 'partner_status' THEN
      RAISE EXCEPTION 'a miss disclosed the partner';
    END IF;
  END IF;

  SELECT submission_count INTO v_after FROM public.word_hunt_attempts
  WHERE session_id = sid AND user_id = '00000000-0000-0000-0000-00000000e001';
  IF v_after <= v_before THEN
    RAISE EXCEPTION 'the miss was not counted';
  END IF;
END $$;

-- The rate limiter fires, and cannot change a result.
DO $$
DECLARE
  sid uuid := (SELECT sid FROM wh_ctx);
  v jsonb;
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  v := public.word_hunt_submit(sid, '[[0,0],[0,1],[0,2],[0,3]]'::jsonb);
  v := public.word_hunt_submit(sid, '[[0,0],[0,1],[0,2],[0,3]]'::jsonb);
  IF v->>'code' IS DISTINCT FROM 'RATE_LIMITED' THEN
    RAISE EXCEPTION 'two submissions in the same millisecond were allowed';
  END IF;
  IF (SELECT status FROM public.word_hunt_attempts
       WHERE session_id = sid
         AND user_id = '00000000-0000-0000-0000-00000000e001')
     <> 'in_progress' THEN
    RAISE EXCEPTION 'the limiter changed the attempt';
  END IF;
END $$;

-- The word is found, from either end, and the elapsed time is the
-- server's. The partner stays hidden.
DO $$
DECLARE
  sid uuid := (SELECT sid FROM wh_ctx);
  v_place jsonb; v jsonb; v_reversed jsonb; k int;
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  SELECT placement INTO v_place FROM public.word_hunt_puzzles
  WHERE session_id = sid;

  -- Dragged from the far end: the same run, read backwards.
  v_reversed := '[]'::jsonb;
  FOR k IN REVERSE jsonb_array_length(v_place) - 1..0 LOOP
    v_reversed := v_reversed || jsonb_build_array(v_place->k);
  END LOOP;

  PERFORM pg_sleep(0.35);
  v := public.word_hunt_submit(sid, v_reversed);
  IF NOT (v->>'hit')::boolean THEN
    RAISE EXCEPTION 'the word dragged backwards was not accepted: %', v;
  END IF;
  IF v->>'my_status' IS DISTINCT FROM 'found' THEN
    RAISE EXCEPTION 'a hit did not finish the attempt: %', v;
  END IF;
  IF (v->>'my_elapsed_ms')::int IS NULL
     OR (v->>'my_elapsed_ms')::int < 0 THEN
    RAISE EXCEPTION 'the elapsed time is not a server measurement: %', v;
  END IF;

  -- THE DISCLOSURE BOUNDARY. One player has finished; the other has not
  -- even started. Nothing about them may be visible, or the second
  -- player starts knowing the number to beat.
  IF v ? 'partner_status' OR v ? 'partner_elapsed_ms' OR v ? 'placement' THEN
    RAISE EXCEPTION 'a finished attempt disclosed the partner or the answer';
  END IF;
  IF (SELECT status FROM public.game_sessions WHERE id = sid) <> 'active' THEN
    RAISE EXCEPTION 'one finished attempt completed the session';
  END IF;
END $$;

-- A successful Submit is idempotent and returns the stored time.
DO $$
DECLARE
  sid uuid := (SELECT sid FROM wh_ctx);
  v_stored int; v jsonb;
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  SELECT elapsed_ms INTO v_stored FROM public.word_hunt_attempts
  WHERE session_id = sid AND user_id = '00000000-0000-0000-0000-00000000e001';

  -- No sleep: the retry must precede the rate-limit check, not trip it.
  v := public.word_hunt_submit(sid, '[[0,0],[0,1],[0,2],[0,3]]'::jsonb);
  IF v ? 'error' THEN
    RAISE EXCEPTION 'a retry after finishing errored: %', v;
  END IF;
  IF (v->>'my_elapsed_ms')::int <> v_stored THEN
    RAISE EXCEPTION 'a retry changed the recorded time';
  END IF;
  IF NOT (v->>'hit')::boolean THEN
    RAISE EXCEPTION 'a retry after a hit reported a miss';
  END IF;

  -- And giving up afterwards cannot rewrite the result.
  v := public.word_hunt_give_up(sid);
  IF v->>'my_status' IS DISTINCT FROM 'found' THEN
    RAISE EXCEPTION 'giving up rewrote a found result: %', v;
  END IF;
END $$;

-- Start after finishing returns the stored result rather than a new clock.
DO $$
DECLARE
  sid uuid := (SELECT sid FROM wh_ctx);
  v jsonb;
  v_before timestamptz;
  v_status text;
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  SELECT started_at, status INTO v_before, v_status
  FROM public.word_hunt_attempts
  WHERE session_id = sid AND user_id = '00000000-0000-0000-0000-00000000e001';
  IF v_status <> 'found' THEN
    RAISE EXCEPTION 'this case assumes a finished attempt, found %', v_status;
  END IF;

  v := public.word_hunt_start(sid);
  IF v->>'my_status' IS DISTINCT FROM 'found' THEN
    RAISE EXCEPTION 'Start reopened a finished attempt: %', v;
  END IF;
  IF (v->>'my_started_at')::timestamptz <> v_before THEN
    RAISE EXCEPTION 'Start moved the clock of a finished attempt';
  END IF;
  IF (SELECT count(*) FROM public.word_hunt_attempts
       WHERE session_id = sid
         AND user_id = '00000000-0000-0000-0000-00000000e001') <> 1 THEN
    RAISE EXCEPTION 'Start created a second attempt for the same player';
  END IF;
END $$;

-- The partner gives up. Both are now terminal, so the reveal opens for
-- both -- including the placement, for whoever did not find it.
DO $$
DECLARE
  sid uuid := (SELECT sid FROM wh_ctx);
  v jsonb;
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e002');
  v := public.word_hunt_start(sid);
  IF v ? 'partner_status' THEN
    RAISE EXCEPTION 'starting disclosed the partner who had finished';
  END IF;

  v := public.word_hunt_give_up(sid);
  IF v->>'my_status' IS DISTINCT FROM 'gave_up' THEN
    RAISE EXCEPTION 'give up did not record: %', v;
  END IF;
  IF v->>'my_elapsed_ms' IS NOT NULL THEN
    RAISE EXCEPTION 'giving up recorded a time';
  END IF;
  IF v->>'partner_status' IS DISTINCT FROM 'found' THEN
    RAISE EXCEPTION 'the reveal did not open once both were terminal: %', v;
  END IF;
  IF NOT (v ? 'placement') THEN
    RAISE EXCEPTION 'the player who gave up was not shown where it was';
  END IF;
  IF (SELECT status FROM public.game_sessions WHERE id = sid)
     <> 'completed' THEN
    RAISE EXCEPTION 'two terminal attempts did not complete the session';
  END IF;

  -- And the finder sees the same reveal.
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  v := public.get_word_hunt_state(sid);
  IF v->>'partner_status' IS DISTINCT FROM 'gave_up' OR NOT (v ? 'placement') THEN
    RAISE EXCEPTION 'the finder was not shown the result: %', v;
  END IF;
  -- Never a winner: §5.3, this is a comparison and not a contest.
  IF (SELECT winner_user_id FROM public.game_sessions WHERE id = sid)
     IS NOT NULL THEN
    RAISE EXCEPTION 'word hunt declared a winner';
  END IF;

  -- Reopening the finished game returns the stored result rather than
  -- SESSION_EXPIRED. This is the reveal screen: the client calls Start on
  -- open, and a completed session must answer with the result, not an
  -- error about the session being over.
  v := public.word_hunt_start(sid);
  IF v ? 'error' THEN
    RAISE EXCEPTION 'Start on a completed session errored: %', v;
  END IF;
  IF v->>'my_status' IS DISTINCT FROM 'found'
     OR v->>'partner_status' IS DISTINCT FROM 'gave_up'
     OR NOT (v ? 'placement') THEN
    RAISE EXCEPTION 'Start on a completed session lost the result: %', v;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- The deadline, at the boundary, with no sleeps.
-- ---------------------------------------------------------------------
DO $$
DECLARE t timestamptz := '2026-09-08 12:00:00+00';
BEGIN
  IF public.word_hunt_is_expired(t, t + interval '9 minutes 59.999 seconds')
  THEN RAISE EXCEPTION 'the millisecond before the deadline expired'; END IF;
  IF NOT public.word_hunt_is_expired(t, t + interval '10 minutes') THEN
    RAISE EXCEPTION 'the deadline itself did not expire';
  END IF;
  IF NOT public.word_hunt_is_expired(t, t + interval '11 minutes') THEN
    RAISE EXCEPTION 'past the deadline did not expire';
  END IF;
END $$;

-- An overdue attempt is swept on the next read, not left running.
DO $$
DECLARE
  v jsonb; sid uuid;
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  sid := pg_temp.new_session('wh-key-timeout');
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e002');
  PERFORM public.word_hunt_accept_session(sid);
  PERFORM public.word_hunt_start(sid);

  -- Reach past the RPCs to age the clock: the trigger forbids moving
  -- started_at, so this is done as owner with the trigger disabled --
  -- simulating elapsed time, not a legal transition.
  ALTER TABLE public.word_hunt_attempts DISABLE TRIGGER word_hunt_attempts_transition;
  UPDATE public.word_hunt_attempts
     SET started_at = now() - interval '11 minutes'
   WHERE session_id = sid;
  ALTER TABLE public.word_hunt_attempts ENABLE TRIGGER word_hunt_attempts_transition;

  v := public.get_word_hunt_state(sid);
  IF v->>'my_status' IS DISTINCT FROM 'timed_out' THEN
    RAISE EXCEPTION 'an overdue attempt was not swept on read: %', v;
  END IF;
  -- A timeout is recorded as a timeout, never as a surrender.
  IF (SELECT status FROM public.word_hunt_attempts
       WHERE session_id = sid) <> 'timed_out' THEN
    RAISE EXCEPTION 'a timeout was stored as something else';
  END IF;
  IF public.word_hunt_submit(sid, '[[0,0],[0,1],[0,2],[0,3]]'::jsonb)
       ->>'my_status' IS DISTINCT FROM 'timed_out' THEN
    RAISE EXCEPTION 'a timed-out attempt accepted a submission';
  END IF;

  -- Close this session out: one live Word Hunt per couple, so leaving it
  -- open would hand the next create() this session instead of a new one.
  PERFORM public.word_hunt_decline_session(sid);
END $$;

-- Session expiry with an absent partner: did not play, no synthetic row.
DO $$
DECLARE
  v jsonb; sid uuid; n int;
BEGIN
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e001');
  sid := pg_temp.new_session('wh-key-absent');
  -- The player who starts is e002, so the ABSENT partner is e001 -- who
  -- is user_a of this relationship. That detail is deliberate: a mutant
  -- inventing a synthetic row "for user_a" would find one already there
  -- if the starter were user_a, and do nothing. Here it has room to fail.
  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e002');
  PERFORM public.word_hunt_accept_session(sid);
  PERFORM public.word_hunt_start(sid);

  UPDATE public.game_sessions
     SET started_at = now() - interval '25 hours',
         created_at = now() - interval '25 hours'
   WHERE id = sid;
  ALTER TABLE public.word_hunt_attempts DISABLE TRIGGER word_hunt_attempts_transition;
  UPDATE public.word_hunt_attempts
     SET started_at = now() - interval '25 hours' WHERE session_id = sid;
  ALTER TABLE public.word_hunt_attempts ENABLE TRIGGER word_hunt_attempts_transition;

  PERFORM public.expire_word_hunt_sessions();

  SELECT count(*) INTO n FROM public.word_hunt_attempts WHERE session_id = sid;
  IF n <> 1 THEN
    RAISE EXCEPTION 'expiry invented a row for the absent partner (n=%)', n;
  END IF;
  -- Named explicitly, not merely counted: a mutant inserting a row for
  -- whichever user happens to be user_a would keep the count at one
  -- whenever user_a is the player who really did start.
  IF EXISTS (SELECT 1 FROM public.word_hunt_attempts
              WHERE session_id = sid
                AND user_id = '00000000-0000-0000-0000-00000000e001') THEN
    RAISE EXCEPTION 'expiry created an attempt for the partner who never played';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.word_hunt_attempts
                  WHERE session_id = sid
                    AND user_id = '00000000-0000-0000-0000-00000000e002') THEN
    RAISE EXCEPTION 'expiry destroyed the attempt that really happened';
  END IF;
  IF (SELECT status FROM public.word_hunt_attempts WHERE session_id = sid)
     <> 'timed_out' THEN
    RAISE EXCEPTION 'expiry left an attempt running under a dead session';
  END IF;

  PERFORM pg_temp.act('00000000-0000-0000-0000-00000000e002');
  v := public.get_word_hunt_state(sid);
  IF v->>'partner_status' IS DISTINCT FROM 'did_not_play' THEN
    RAISE EXCEPTION 'an absent partner was not shown as did not play: %', v;
  END IF;
  IF NOT (v ? 'placement') THEN
    RAISE EXCEPTION 'an expired session withheld the answer forever';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- The tables stay shut (the two findings that made this spec v2).
-- ---------------------------------------------------------------------
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  v_table text;
  v_denied boolean;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'word_hunt_configs', 'word_hunt_puzzles', 'word_hunt_attempts']
  LOOP
    v_denied := false;
    BEGIN
      EXECUTE format('SELECT 1 FROM public.%I LIMIT 1', v_table);
    EXCEPTION WHEN insufficient_privilege THEN v_denied := true;
    END;
    IF NOT v_denied THEN
      RAISE EXCEPTION '% is readable by authenticated', v_table;
    END IF;
  END LOOP;
END $$;

-- The shared session row is not writable for word_hunt.
DO $$
DECLARE
  sid uuid := (SELECT sid FROM wh_ctx);
  n int;
  v_denied boolean := false;
BEGIN
  UPDATE public.game_sessions SET status = 'active' WHERE id = sid;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN
    RAISE EXCEPTION 'a word_hunt session row was updated directly';
  END IF;

  DELETE FROM public.game_sessions WHERE id = sid;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN
    RAISE EXCEPTION 'a word_hunt session row was deleted directly';
  END IF;

  BEGIN
    INSERT INTO public.game_sessions(
      relationship_id, initiator_id, game_type, status)
    VALUES ('00000000-0000-0000-0000-0000000000e1',
            '00000000-0000-0000-0000-00000000e001', 'word_hunt', 'active');
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'a word_hunt session was inserted directly';
  END IF;
END $$;

-- An unrelated legacy game keeps its intended write access, so the
-- carve-out did not quietly break every other game. 36 Questions has no
-- guard trigger of its own, so what it hits here is the shared policy --
-- which is the thing under test.
DO $$
DECLARE n int;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-00000000e001","role":"authenticated"}',
    true);
  INSERT INTO public.game_sessions(
    relationship_id, initiator_id, game_type, status)
  VALUES ('00000000-0000-0000-0000-0000000000e1',
          '00000000-0000-0000-0000-00000000e001', '36_questions', 'invited');
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'the carve-out broke an unrelated game type';
  END IF;
END $$;
RESET ROLE;

-- Helper RPCs are not a client surface.
DO $$
DECLARE
  v_fn text;
  v_ok boolean;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY[
    'word_hunt_count_occurrences', 'word_hunt_generate',
    'word_hunt_pick_direction', 'word_hunt_state_payload',
    'word_hunt_authorize', 'word_hunt_maybe_complete',
    'word_hunt_expire_attempts', 'word_hunt_expire_sessions_for',
    'word_hunt_error', 'word_hunt_is_expired', 'word_hunt_directions',
    'expire_word_hunt_sessions']
  LOOP
    SELECT bool_or(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
      INTO v_ok
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = v_fn;
    IF v_ok THEN
      RAISE EXCEPTION '% is executable by authenticated', v_fn;
    END IF;
  END LOOP;
END $$;

-- The client RPCs ARE reachable, and are SECURITY DEFINER with a fixed
-- search_path.
DO $$
DECLARE
  v_fn text;
  v_ok boolean;
  v_bad text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY[
    'word_hunt_create_session', 'word_hunt_accept_session',
    'word_hunt_decline_session', 'word_hunt_start', 'word_hunt_submit',
    'word_hunt_give_up', 'get_word_hunt_state',
    'get_active_word_hunt_session']
  LOOP
    SELECT bool_or(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
      INTO v_ok
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = v_fn;
    IF NOT COALESCE(v_ok, false) THEN
      RAISE EXCEPTION '% is not callable by authenticated', v_fn;
    END IF;
  END LOOP;

  SELECT string_agg(p.proname, ', ') INTO v_bad
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname LIKE 'word_hunt%'
    AND p.prosecdef
    AND NOT EXISTS (
      SELECT 1 FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) c
      WHERE c LIKE 'search_path=%');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'SECURITY DEFINER without a fixed search_path: %', v_bad;
  END IF;
END $$;

-- No private table joins the realtime publication: publishing an attempt
-- would broadcast a partner's time straight past every RPC that exists
-- to withhold it.
DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(tablename, ', ') INTO v_bad
  FROM pg_publication_tables
  WHERE pubname = 'supabase_realtime'
    AND schemaname = 'public'
    AND tablename LIKE 'word_hunt%';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'a private word hunt table is published: %', v_bad;
  END IF;
END $$;

ROLLBACK;
