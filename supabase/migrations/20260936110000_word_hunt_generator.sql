-- Word Hunt: puzzle generation.
--
-- Separate from the RPCs because it is the one piece with no client
-- surface at all: it runs inside session creation, as owner, and is
-- revoked from every client role. Its output is checked twice -- once
-- here and again by the puzzle table's trigger (§9).

-- Weighted pick over the eight direction ordinals.
CREATE OR REPLACE FUNCTION public.word_hunt_pick_direction(p_weights jsonb)
RETURNS int
LANGUAGE plpgsql
VOLATILE
SET search_path = public
AS $$
DECLARE
  v_total numeric := 0;
  v_roll numeric;
  v_acc numeric := 0;
  i int;
BEGIN
  FOR i IN 0..7 LOOP
    v_total := v_total + (p_weights->>i)::numeric;
  END LOOP;
  IF v_total <= 0 THEN
    RAISE EXCEPTION 'word hunt: direction weights sum to zero';
  END IF;

  v_roll := random() * v_total;
  FOR i IN 0..7 LOOP
    v_acc := v_acc + (p_weights->>i)::numeric;
    IF v_roll < v_acc THEN
      RETURN i;
    END IF;
  END LOOP;
  RETURN 7;  -- Only reachable through floating-point drift at the top end.
END;
$$;

-- ---------------------------------------------------------------------
-- Generate one puzzle.
-- ---------------------------------------------------------------------
-- Places the word once, fills the rest at random, then scans all eight
-- directions from every cell and rejects the grid unless the word
-- appears exactly once.
--
-- WHY IT FAILS RATHER THAN FALLS BACK. The spec's first draft fell back
-- to "place it in a straight line", which is meaningless -- every legal
-- placement is already a straight line -- and worse, it bypassed the
-- validation it was falling back from. An unstarted game is a minor
-- annoyance. An ambiguous puzzle tells a player who genuinely found the
-- word that they are wrong, which is the worst thing this game can do.
CREATE OR REPLACE FUNCTION public.word_hunt_generate(
  p_word text,
  p_weights jsonb,
  p_max_attempts int DEFAULT 20
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = public
AS $$
DECLARE
  v_len int;
  v_dirs jsonb := public.word_hunt_directions();
  v_attempt int;
  v_d int; dr int; dc int;
  v_r int; v_c int;
  v_min_r int; v_max_r int; v_min_c int; v_max_c int;
  v_grid text[];
  v_row text;
  v_placement jsonb;
  v_out jsonb;
  r int; c int; k int;
BEGIN
  IF p_word IS NULL OR p_word !~ '^[A-Z]{4,8}$' THEN
    RAISE EXCEPTION 'word hunt: % is not a legal word', p_word;
  END IF;
  v_len := char_length(p_word);

  FOR v_attempt IN 1..GREATEST(p_max_attempts, 1) LOOP
    v_d := public.word_hunt_pick_direction(p_weights);
    dr := (v_dirs->v_d->>0)::int;
    dc := (v_dirs->v_d->>1)::int;

    -- Legal start range for this direction, so the run stays in bounds.
    v_min_r := CASE WHEN dr < 0 THEN v_len - 1 ELSE 0 END;
    v_max_r := CASE WHEN dr > 0 THEN 10 - v_len ELSE 9 END;
    v_min_c := CASE WHEN dc < 0 THEN v_len - 1 ELSE 0 END;
    v_max_c := CASE WHEN dc > 0 THEN 10 - v_len ELSE 9 END;

    v_r := v_min_r + floor(random() * (v_max_r - v_min_r + 1))::int;
    v_c := v_min_c + floor(random() * (v_max_c - v_min_c + 1))::int;

    -- Random fill first, then overwrite the run: filling around the word
    -- would need a mask, and this is the same result with less to hold.
    v_grid := ARRAY[]::text[];
    FOR r IN 0..9 LOOP
      v_row := '';
      FOR c IN 0..9 LOOP
        v_row := v_row || chr(65 + floor(random() * 26)::int);
      END LOOP;
      v_grid := array_append(v_grid, v_row);
    END LOOP;

    v_placement := '[]'::jsonb;
    FOR k IN 0..v_len - 1 LOOP
      r := v_r + dr * k;
      c := v_c + dc * k;
      v_grid[r + 1] :=
        overlay(v_grid[r + 1] placing substr(p_word, k + 1, 1)
                from c + 1 for 1);
      v_placement := v_placement || jsonb_build_array(
        jsonb_build_array(r, c));
    END LOOP;

    v_out := to_jsonb(v_grid);

    -- MUTATION-TESTING NOTE. Deleting this check is not detectable by any
    -- black-box test of this function: measured against the shipped word
    -- list, 2000 generated grids produced an accidental second occurrence
    -- ZERO times, so a generator that skipped the scan would pass any
    -- "generate many and count" test. The scan is covered instead where it
    -- bites -- the puzzle table's trigger runs the same scanner and refuses
    -- to store an ambiguous grid, and word_hunt_test.sql proves that with a
    -- deliberately ambiguous fixture. This call stays because failing at
    -- generation is cheaper than failing at INSERT, not because it is the
    -- only guard.
    IF public.word_hunt_count_occurrences(v_out, p_word) = 1 THEN
      RETURN jsonb_build_object(
        'grid', v_out,
        'placement', v_placement,
        'direction', v_d
      );
    END IF;
  END LOOP;

  RAISE EXCEPTION
    'word hunt: could not place % uniquely in % attempts',
    p_word, p_max_attempts;
END;
$$;

REVOKE ALL ON FUNCTION public.word_hunt_pick_direction(jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.word_hunt_generate(text, jsonb, int)
  FROM PUBLIC, anon, authenticated;
