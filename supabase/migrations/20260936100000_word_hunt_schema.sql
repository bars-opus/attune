-- Word Hunt: schema, config and the puzzle scanner.
--
-- WORD_HUNT_GAME_SPEC.md §5 and §9. The second Arcade game with no
-- insight layer: nothing here scores, records or analyses anything.
--
-- THE SHAPE THIS TAKES AND WHY. The first draft of the spec put the
-- grid, the word and the placement on the game_sessions row, and argued
-- the placement was safe because the state RPC did not select it. That
-- is wrong, and it was proven wrong against a database before this file
-- was written: RLS is ROW-level. The existing member SELECT policy
-- returns every column of the row to either partner, so
--
--   select hunt_placement from game_sessions where id = ...;
--
-- returned the answer. Omitting a column from an RPC hides it from the
-- RPC, not from the table.
--
-- So every piece of puzzle material lives here instead, in tables with
-- authenticated revoked outright and NO POLICY AT ALL. A policy would be
-- a door. The only way in is a SECURITY DEFINER function running as
-- owner.

-- ---------------------------------------------------------------------
-- The word list and direction weights, versioned.
-- ---------------------------------------------------------------------
-- Same reasoning as snakes_boards: a session must remember which list it
-- was drawn from, or retuning difficulty silently rewrites the history of
-- games already played.
CREATE TABLE IF NOT EXISTS public.word_hunt_configs (
  version text PRIMARY KEY,
  words text[] NOT NULL,
  -- Eight non-negative weights, indexed by direction ordinal 0..7 as
  -- ordered in word_hunt_directions(). Diagonals and backwards run
  -- heavier: a word left-to-right along a row is found in two seconds
  -- and the game is over before it starts.
  direction_weights jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  retired_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.word_hunt_puzzles (
  session_id uuid PRIMARY KEY
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  word text NOT NULL,
  -- ["ABCDEFGHIJ", ...] exactly 10 rows of 10.
  grid jsonb NOT NULL,
  -- [[row, col], ...] in reading order along the placement axis. Never
  -- leaves the server until the session is over.
  placement jsonb NOT NULL,
  word_list_version text NOT NULL
    REFERENCES public.word_hunt_configs(version),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.word_hunt_attempts (
  session_id uuid NOT NULL
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  -- A boolean cannot tell a timeout from a choice. The UI shows both as
  -- "did not find it" (§3.1 -- reporting a surrender would turn a
  -- kindness into something to be embarrassed about), but the database
  -- must not record one as the other.
  status text NOT NULL DEFAULT 'in_progress'
    CHECK (status IN ('in_progress', 'found', 'gave_up', 'timed_out')),

  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  elapsed_ms int,

  -- Rate limiting reads these rather than scanning a log.
  last_submission_at timestamptz,
  submission_count int NOT NULL DEFAULT 0,

  PRIMARY KEY (session_id, user_id),
  CONSTRAINT word_hunt_attempts_count_nonneg CHECK (submission_count >= 0),
  CONSTRAINT word_hunt_attempts_finish_after_start
    CHECK (finished_at IS NULL OR finished_at >= started_at),
  CONSTRAINT word_hunt_attempts_submission_after_start
    CHECK (last_submission_at IS NULL OR last_submission_at >= started_at),
  CONSTRAINT word_hunt_attempts_status_shape CHECK (
    (status = 'in_progress'
      AND finished_at IS NULL AND elapsed_ms IS NULL)
    OR
    (status = 'found'
      AND finished_at IS NOT NULL
      AND elapsed_ms IS NOT NULL AND elapsed_ms BETWEEN 0 AND 599999)
    OR
    (status IN ('gave_up', 'timed_out')
      AND finished_at IS NOT NULL AND elapsed_ms IS NULL)
  )
);

-- ---------------------------------------------------------------------
-- Closed tables.
-- ---------------------------------------------------------------------
ALTER TABLE public.word_hunt_configs  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.word_hunt_puzzles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.word_hunt_attempts ENABLE ROW LEVEL SECURITY;

-- No policies at all, deliberately. A readable attempts table would let
-- a player see their partner's time before starting theirs, and a
-- writable one would let them rewrite their own clock.
REVOKE ALL ON public.word_hunt_configs  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.word_hunt_puzzles  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.word_hunt_attempts FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT, UPDATE ON public.word_hunt_configs  TO service_role;
GRANT SELECT, INSERT           ON public.word_hunt_puzzles TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.word_hunt_attempts TO service_role;

CREATE INDEX IF NOT EXISTS idx_word_hunt_attempts_open
  ON public.word_hunt_attempts(started_at)
  WHERE status = 'in_progress';

-- ---------------------------------------------------------------------
-- The eight legal directions, in a fixed order.
-- ---------------------------------------------------------------------
-- Weight ordinals reference this order, so it is a function rather than
-- a literal repeated in three places that could drift apart.
CREATE OR REPLACE FUNCTION public.word_hunt_directions()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_array(
    jsonb_build_array( 0,  1),  -- 0 east
    jsonb_build_array( 0, -1),  -- 1 west
    jsonb_build_array( 1,  0),  -- 2 south
    jsonb_build_array(-1,  0),  -- 3 north
    jsonb_build_array( 1,  1),  -- 4 south-east
    jsonb_build_array(-1, -1),  -- 5 north-west
    jsonb_build_array( 1, -1),  -- 6 south-west
    jsonb_build_array(-1,  1)   -- 7 north-east
  );
$$;

-- ---------------------------------------------------------------------
-- The occurrence scanner.
-- ---------------------------------------------------------------------
-- Random fill can accidentally spell the word a second time, or spell it
-- backwards where it was placed forwards. Either makes a correct answer
-- look wrong to the player who found it -- the worst failure this game
-- has. So every generated grid is scanned in all eight directions from
-- every cell, and rejected unless the count is exactly one.
--
-- CANONICALISATION. A palindrome placed once reads the same in both
-- directions and would otherwise count as two. Occurrences are therefore
-- keyed by the lexicographically sorted pair of endpoints, so one
-- physical run of letters counts once however it is read.
--
-- Used by the generator AND by the puzzle table's trigger, so a row that
-- somehow bypassed the generator still cannot be stored.
CREATE OR REPLACE FUNCTION public.word_hunt_count_occurrences(
  p_grid jsonb,
  p_word text
)
RETURNS int
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_rows int;
  v_len int;
  v_row text;
  v_dirs jsonb := public.word_hunt_directions();
  v_found text[] := ARRAY[]::text[];
  v_key text;
  r int; c int; d int; k int;
  dr int; dc int;
  er int; ec int;
  v_ok boolean;
  v_a text; v_b text;
BEGIN
  IF p_grid IS NULL OR jsonb_typeof(p_grid) <> 'array'
     OR p_word IS NULL OR p_word = '' THEN
    RAISE EXCEPTION 'word hunt: malformed scanner input';
  END IF;

  v_rows := jsonb_array_length(p_grid);
  IF v_rows <> 10 THEN
    RAISE EXCEPTION 'word hunt: grid must have 10 rows, has %', v_rows;
  END IF;

  FOR r IN 0..v_rows - 1 LOOP
    IF jsonb_typeof(p_grid->r) <> 'string' THEN
      RAISE EXCEPTION 'word hunt: grid row % is not a string', r;
    END IF;
    v_row := p_grid->>r;
    -- One anchored pattern covers length and alphabet together. A
    -- separate char_length check was here and was unreachable: ^[A-Z]{10}$
    -- already rejects every row that is not exactly ten letters, so the
    -- check could be deleted without any test noticing. Dead validation
    -- reads as protection it does not provide.
    IF v_row !~ '^[A-Z]{10}$' THEN
      RAISE EXCEPTION
        'word hunt: grid row % is not 10 uppercase letters (%)', r, v_row;
    END IF;
  END LOOP;

  IF p_word !~ '^[A-Z]+$' THEN
    RAISE EXCEPTION 'word hunt: word must be uppercase A-Z';
  END IF;

  v_len := char_length(p_word);

  FOR r IN 0..9 LOOP
    FOR c IN 0..9 LOOP
      FOR d IN 0..7 LOOP
        dr := (v_dirs->d->>0)::int;
        dc := (v_dirs->d->>1)::int;
        er := r + dr * (v_len - 1);
        ec := c + dc * (v_len - 1);
        CONTINUE WHEN er < 0 OR er > 9 OR ec < 0 OR ec > 9;

        v_ok := true;
        FOR k IN 0..v_len - 1 LOOP
          IF substr(p_grid->>(r + dr * k), c + dc * k + 1, 1)
             <> substr(p_word, k + 1, 1) THEN
            v_ok := false;
            EXIT;
          END IF;
        END LOOP;

        IF v_ok THEN
          -- Sorted endpoints: one physical run, one key.
          v_a := lpad(r::text, 2, '0') || ',' || lpad(c::text, 2, '0');
          v_b := lpad(er::text, 2, '0') || ',' || lpad(ec::text, 2, '0');
          IF v_a <= v_b THEN
            v_key := v_a || '-' || v_b;
          ELSE
            v_key := v_b || '-' || v_a;
          END IF;
          IF NOT (v_key = ANY(v_found)) THEN
            v_found := array_append(v_found, v_key);
          END IF;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  RETURN cardinality(v_found);
END;
$$;

-- ---------------------------------------------------------------------
-- Config validation.
-- ---------------------------------------------------------------------
-- The first draft of the word list broke its own 4-to-8-letter rule
-- twice (AFFECTION at nine). A trigger means a future hand edit cannot
-- reintroduce that.
CREATE OR REPLACE FUNCTION public.validate_word_hunt_config()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_word text;
  v_total numeric := 0;
  v_w numeric;
  i int;
BEGIN
  IF NEW.words IS NULL OR cardinality(NEW.words) = 0 THEN
    RAISE EXCEPTION 'word hunt config %: empty word list', NEW.version;
  END IF;

  IF cardinality(NEW.words)
     <> (SELECT count(DISTINCT w) FROM unnest(NEW.words) w) THEN
    RAISE EXCEPTION 'word hunt config %: duplicate words', NEW.version;
  END IF;

  FOREACH v_word IN ARRAY NEW.words LOOP
    IF v_word !~ '^[A-Z]{4,8}$' THEN
      RAISE EXCEPTION
        'word hunt config %: % is not 4 to 8 uppercase letters',
        NEW.version, v_word;
    END IF;
  END LOOP;

  IF jsonb_typeof(NEW.direction_weights) <> 'array'
     OR jsonb_array_length(NEW.direction_weights) <> 8 THEN
    RAISE EXCEPTION
      'word hunt config %: direction_weights must be 8 numbers', NEW.version;
  END IF;

  FOR i IN 0..7 LOOP
    IF jsonb_typeof(NEW.direction_weights->i) <> 'number' THEN
      RAISE EXCEPTION
        'word hunt config %: weight % is not a number', NEW.version, i;
    END IF;
    v_w := (NEW.direction_weights->>i)::numeric;
    IF v_w < 0 THEN
      RAISE EXCEPTION
        'word hunt config %: weight % is negative', NEW.version, i;
    END IF;
    v_total := v_total + v_w;
  END LOOP;

  IF v_total <= 0 THEN
    RAISE EXCEPTION
      'word hunt config %: direction weights sum to zero', NEW.version;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS word_hunt_configs_validate ON public.word_hunt_configs;
CREATE TRIGGER word_hunt_configs_validate
BEFORE INSERT OR UPDATE ON public.word_hunt_configs
FOR EACH ROW EXECUTE FUNCTION public.validate_word_hunt_config();

-- ---------------------------------------------------------------------
-- Config immutability, once played on.
-- ---------------------------------------------------------------------
-- Pinning word_list_version would be pointless if the row it points at
-- could still be edited. Retirement metadata may still change: retiring
-- a version stops new sessions drawing from it without altering what a
-- past session pinned.
CREATE OR REPLACE FUNCTION public.guard_word_hunt_config_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF EXISTS (SELECT 1 FROM public.word_hunt_puzzles
                WHERE word_list_version = OLD.version) THEN
      RAISE EXCEPTION
        'word hunt config % has been played on and cannot be deleted',
        OLD.version;
    END IF;
    RETURN OLD;
  END IF;

  IF (OLD.version IS DISTINCT FROM NEW.version
      OR OLD.words IS DISTINCT FROM NEW.words
      OR OLD.direction_weights IS DISTINCT FROM NEW.direction_weights)
     AND EXISTS (SELECT 1 FROM public.word_hunt_puzzles
                  WHERE word_list_version = OLD.version) THEN
    RAISE EXCEPTION
      'word hunt config % has been played on; add a new version instead',
      OLD.version;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS word_hunt_configs_immutable ON public.word_hunt_configs;
CREATE TRIGGER word_hunt_configs_immutable
BEFORE UPDATE OR DELETE ON public.word_hunt_configs
FOR EACH ROW EXECUTE FUNCTION public.guard_word_hunt_config_immutable();

-- ---------------------------------------------------------------------
-- Puzzle validation, independent of the generator.
-- ---------------------------------------------------------------------
-- The generator already checks all of this. Checking it again here is
-- the point: a puzzle row that reached the table by any other path --
-- a future RPC, a backfill, a hand insert -- still cannot be ambiguous.
CREATE OR REPLACE FUNCTION public.validate_word_hunt_puzzle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_len int;
  v_words text[];
  k int;
  r int; c int;
  pr int; pc int;
  dr int; dc int;
BEGIN
  IF NEW.word !~ '^[A-Z]{4,8}$' THEN
    RAISE EXCEPTION 'word hunt puzzle: word % is not 4 to 8 letters', NEW.word;
  END IF;

  SELECT words INTO v_words FROM public.word_hunt_configs
  WHERE version = NEW.word_list_version;
  IF v_words IS NULL OR NOT (NEW.word = ANY(v_words)) THEN
    RAISE EXCEPTION
      'word hunt puzzle: % is not in config %', NEW.word, NEW.word_list_version;
  END IF;

  v_len := char_length(NEW.word);

  IF jsonb_typeof(NEW.placement) <> 'array'
     OR jsonb_array_length(NEW.placement) <> v_len THEN
    RAISE EXCEPTION
      'word hunt puzzle: placement must have % cells', v_len;
  END IF;

  FOR k IN 0..v_len - 1 LOOP
    IF jsonb_typeof(NEW.placement->k) <> 'array'
       OR jsonb_array_length(NEW.placement->k) <> 2
       OR jsonb_typeof(NEW.placement->k->0) <> 'number'
       OR jsonb_typeof(NEW.placement->k->1) <> 'number' THEN
      RAISE EXCEPTION 'word hunt puzzle: placement cell % is malformed', k;
    END IF;
    r := (NEW.placement->k->>0)::int;
    c := (NEW.placement->k->>1)::int;
    IF r < 0 OR r > 9 OR c < 0 OR c > 9 THEN
      RAISE EXCEPTION 'word hunt puzzle: placement cell % out of bounds', k;
    END IF;

    -- Contiguity: one fixed step, held for the whole run.
    IF k > 0 THEN
      IF k = 1 THEN
        dr := r - pr;
        dc := c - pc;
        IF (dr = 0 AND dc = 0) OR abs(dr) > 1 OR abs(dc) > 1 THEN
          RAISE EXCEPTION 'word hunt puzzle: placement is not a single step';
        END IF;
      ELSIF r - pr <> dr OR c - pc <> dc THEN
        RAISE EXCEPTION 'word hunt puzzle: placement is not a straight line';
      END IF;
    END IF;

    -- The cells must actually spell the word.
    IF substr(NEW.grid->>r, c + 1, 1) <> substr(NEW.word, k + 1, 1) THEN
      RAISE EXCEPTION
        'word hunt puzzle: placement does not spell % at cell %', NEW.word, k;
    END IF;

    pr := r;
    pc := c;
  END LOOP;

  -- Grid shape and alphabet are validated inside the scanner, which
  -- raises on malformed input rather than returning a misleading count.
  IF public.word_hunt_count_occurrences(NEW.grid, NEW.word) <> 1 THEN
    RAISE EXCEPTION
      'word hunt puzzle: % does not appear exactly once', NEW.word;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS word_hunt_puzzles_validate ON public.word_hunt_puzzles;
CREATE TRIGGER word_hunt_puzzles_validate
BEFORE INSERT OR UPDATE ON public.word_hunt_puzzles
FOR EACH ROW EXECUTE FUNCTION public.validate_word_hunt_puzzle();

-- ---------------------------------------------------------------------
-- Attempt transition invariants.
-- ---------------------------------------------------------------------
-- A final net beneath the RPCs. If a future SECURITY DEFINER function
-- tries to reopen a finished attempt or move a clock, it fails here
-- rather than quietly producing a wrong number.
CREATE OR REPLACE FUNCTION public.guard_word_hunt_attempt_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.session_id <> OLD.session_id OR NEW.user_id <> OLD.user_id THEN
    RAISE EXCEPTION 'word hunt attempt: identity is immutable';
  END IF;

  IF NEW.started_at <> OLD.started_at THEN
    RAISE EXCEPTION 'word hunt attempt: the clock cannot be restarted';
  END IF;

  IF NEW.submission_count < OLD.submission_count THEN
    RAISE EXCEPTION 'word hunt attempt: submission count cannot decrease';
  END IF;

  IF OLD.last_submission_at IS NOT NULL
     AND (NEW.last_submission_at IS NULL
          OR NEW.last_submission_at < OLD.last_submission_at) THEN
    RAISE EXCEPTION 'word hunt attempt: submission time cannot move backwards';
  END IF;

  IF OLD.status <> 'in_progress' AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION
      'word hunt attempt: % is terminal and cannot change', OLD.status;
  END IF;

  -- Terminal results are written once and never edited.
  IF OLD.status <> 'in_progress'
     AND (NEW.finished_at IS DISTINCT FROM OLD.finished_at
          OR NEW.elapsed_ms IS DISTINCT FROM OLD.elapsed_ms) THEN
    RAISE EXCEPTION 'word hunt attempt: a finished result is immutable';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS word_hunt_attempts_transition ON public.word_hunt_attempts;
CREATE TRIGGER word_hunt_attempts_transition
BEFORE UPDATE ON public.word_hunt_attempts
FOR EACH ROW EXECUTE FUNCTION public.guard_word_hunt_attempt_transition();

-- Internal machinery, not a client surface.
REVOKE ALL ON FUNCTION public.word_hunt_directions()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.word_hunt_count_occurrences(jsonb, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_word_hunt_config()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_word_hunt_config_immutable()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_word_hunt_puzzle()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_word_hunt_attempt_transition()
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- The starting list.
-- ---------------------------------------------------------------------
-- §6: 4 to 8 letters, and nothing unkind to encounter. This is a
-- cool-off game that might be opened after an argument, and a grid
-- containing ALONE or LEAVING is a small cruelty at exactly the wrong
-- moment. The list is warm or neutral throughout.
INSERT INTO public.word_hunt_configs (version, words, direction_weights)
VALUES (
  'v1',
  ARRAY[
    'LOVE', 'KISS', 'LAUGH', 'HOME', 'WARM', 'TRUST',
    'SPARK', 'HONEY', 'SMILE', 'DANCE', 'SWEET', 'HEART',
    'CUDDLE', 'FLIRT', 'CHARM', 'ADORE', 'DEVOTE', 'TENDER',
    'GIGGLE', 'PATIENT', 'LOYAL', 'GENTLE', 'PLAYFUL', 'COMFORT',
    'DESIRE', 'ROMANCE', 'EMBRACE', 'CHERISH', 'DELIGHT', 'BELOVED',
    'DARLING', 'FOREVER', 'PARTNER', 'INTIMATE', 'SNUGGLE', 'BLUSH'
  ],
  -- east, west, south, north, SE, NW, SW, NE. Plain eastward reading is
  -- the easiest possible placement and is weighted down accordingly.
  jsonb_build_array(1, 2, 2, 2, 3, 3, 3, 3)
)
ON CONFLICT (version) DO NOTHING;

COMMENT ON TABLE public.word_hunt_puzzles IS
  'Puzzle material. No RLS policy exists by design: authenticated is '
  'revoked outright, and the only path in is a SECURITY DEFINER RPC.';
