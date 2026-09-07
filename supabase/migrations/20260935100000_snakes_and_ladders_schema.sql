-- Snakes and Ladders: schema and board configuration.
--
-- The first Attune game with no insight layer, deliberately. See
-- SNAKES_AND_LADDERS_SPEC.md §1 -- a couple who have just had a hard
-- conversation should be able to roll a die rather than be handed
-- another prompt. Nothing here scores, records or analyses anything.

-- ---------------------------------------------------------------------
-- The board lives in a table, not a constant.
-- ---------------------------------------------------------------------
-- Two reasons. Both clients cannot disagree about where a snake is, and
-- the layout can be tuned without shipping an app update. The second is
-- only true if a session remembers WHICH board it was played on --
-- otherwise retuning silently rewrites the history of every finished
-- game, and a replay animates a snake that was never there.
CREATE TABLE IF NOT EXISTS public.snakes_boards (
  version text PRIMARY KEY,
  -- {"ladders": {"2": 38, ...}, "snakes": {"16": 6, ...}}
  features jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  retired_at timestamptz
);

ALTER TABLE public.snakes_boards ENABLE ROW LEVEL SECURITY;

-- Readable by any signed-in player: the board is the one thing in this
-- game that is not secret, and the client must draw it.
DROP POLICY IF EXISTS snakes_boards_read ON public.snakes_boards;
CREATE POLICY snakes_boards_read
ON public.snakes_boards FOR SELECT TO authenticated USING (true);

REVOKE ALL ON public.snakes_boards FROM anon, authenticated;
GRANT SELECT ON public.snakes_boards TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.snakes_boards TO service_role;

INSERT INTO public.snakes_boards (version, features)
VALUES (
  'v1',
  jsonb_build_object(
    'ladders', jsonb_build_object(
      '2', 38, '4', 14, '9', 31, '21', 42, '28', 84,
      '36', 44, '51', 67, '71', 91, '80', 99
    ),
    'snakes', jsonb_build_object(
      '16', 6, '47', 26, '49', 11, '56', 53, '62', 19,
      '64', 60, '87', 24, '93', 73, '95', 75, '98', 78
    )
  )
)
ON CONFLICT (version) DO NOTHING;

-- ---------------------------------------------------------------------
-- Board invariants, enforced rather than trusted.
-- ---------------------------------------------------------------------
-- These are cheap rules that are easy to break by eye -- the first draft
-- of the spec violated two of them (a ladder from 1, and one to 100 that
-- would have bypassed the exact-finish rule entirely). A trigger means a
-- future edit cannot reintroduce that by hand.
CREATE OR REPLACE FUNCTION public.validate_snakes_board()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_head text;
  v_dest int;
  v_all jsonb;
BEGIN
  IF NOT (NEW.features ? 'ladders' AND NEW.features ? 'snakes') THEN
    RAISE EXCEPTION 'board % must define ladders and snakes', NEW.version;
  END IF;

  v_all := (NEW.features->'ladders') || (NEW.features->'snakes');

  -- A cell that is the head of two features would make the outcome of
  -- landing there depend on evaluation order.
  IF (SELECT count(*) FROM jsonb_object_keys(NEW.features->'ladders'))
     + (SELECT count(*) FROM jsonb_object_keys(NEW.features->'snakes'))
     <> (SELECT count(*) FROM jsonb_object_keys(v_all)) THEN
    RAISE EXCEPTION 'board %: a cell is the head of two features', NEW.version;
  END IF;

  FOR v_head, v_dest IN
    SELECT key, value::int FROM jsonb_each_text(NEW.features->'ladders')
  LOOP
    IF v_dest <= v_head::int THEN
      RAISE EXCEPTION 'board %: ladder % does not climb', NEW.version, v_head;
    END IF;
  END LOOP;

  FOR v_head, v_dest IN
    SELECT key, value::int FROM jsonb_each_text(NEW.features->'snakes')
  LOOP
    IF v_dest >= v_head::int THEN
      RAISE EXCEPTION 'board %: snake % does not descend', NEW.version, v_head;
    END IF;
  END LOOP;

  FOR v_head, v_dest IN SELECT key, value::int FROM jsonb_each_text(v_all)
  LOOP
    IF v_head::int IN (1, 100) OR v_dest IN (1, 100) THEN
      RAISE EXCEPTION
        'board %: feature at % touches 1 or 100', NEW.version, v_head;
    END IF;
    -- No chaining: one roll must never trigger two slides, which would
    -- be impossible to animate honestly and surprising to play.
    IF v_all ? v_dest::text THEN
      RAISE EXCEPTION
        'board %: feature at % lands on another head', NEW.version, v_head;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS snakes_boards_validate ON public.snakes_boards;
CREATE TRIGGER snakes_boards_validate
BEFORE INSERT OR UPDATE ON public.snakes_boards
FOR EACH ROW EXECUTE FUNCTION public.validate_snakes_board();

-- ---------------------------------------------------------------------
-- Session and round columns.
-- ---------------------------------------------------------------------
-- Everything else -- invite/accept/expire, current_turn_user_id,
-- winner_user_id, the chat card -- comes free from the shared tables.
ALTER TABLE public.game_sessions
  ADD COLUMN IF NOT EXISTS board_position_a smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS board_position_b smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS board_version text;

ALTER TABLE public.game_sessions
  DROP CONSTRAINT IF EXISTS game_sessions_board_positions_range;
ALTER TABLE public.game_sessions
  ADD CONSTRAINT game_sessions_board_positions_range
  CHECK (
    board_position_a BETWEEN 0 AND 100
    AND board_position_b BETWEEN 0 AND 100
  );

ALTER TABLE public.game_session_rounds
  ADD COLUMN IF NOT EXISTS die_roll smallint,
  -- Where the die alone put them, BEFORE any snake or ladder. The replay
  -- walks here first and then slides; a client that only knew the final
  -- cell would have to re-derive this from the board, which stops being
  -- possible the moment board_version can differ between sessions.
  ADD COLUMN IF NOT EXISTS rolled_to smallint,
  ADD COLUMN IF NOT EXISTS moved_from smallint,
  ADD COLUMN IF NOT EXISTS moved_to smallint,
  ADD COLUMN IF NOT EXISTS movement_kind text;

ALTER TABLE public.game_session_rounds
  DROP CONSTRAINT IF EXISTS game_session_rounds_snakes_range;
ALTER TABLE public.game_session_rounds
  ADD CONSTRAINT game_session_rounds_snakes_range
  CHECK (
    (die_roll IS NULL OR die_roll BETWEEN 1 AND 6)
    AND (rolled_to IS NULL OR rolled_to BETWEEN 0 AND 100)
    AND (moved_from IS NULL OR moved_from BETWEEN 0 AND 100)
    AND (moved_to IS NULL OR moved_to BETWEEN 0 AND 100)
    AND (movement_kind IS NULL
         OR movement_kind IN ('normal', 'bounce', 'ladder', 'snake'))
  );

-- One row per player per round, matching Paint Ball's shape. Both games
-- alternate turns, so a round number identifies one player's move.
CREATE UNIQUE INDEX IF NOT EXISTS idx_snakes_rounds_one_per_player
  ON public.game_session_rounds(session_id, round_number, active_partner_id)
  WHERE game_type = 'snakes_and_ladders';

CREATE INDEX IF NOT EXISTS idx_snakes_sessions_turn
  ON public.game_sessions(current_turn_user_id)
  WHERE game_type = 'snakes_and_ladders' AND status = 'active';

COMMENT ON COLUMN public.game_sessions.board_version IS
  'Pinned at creation so retuning the board cannot rewrite the history '
  'of a finished game.';
