-- Board validation: ranges, and that 100 is actually reachable.
--
-- The original trigger checked direction, endpoints, duplicate heads and
-- chaining, and missed two ways to ship a broken game:
--
--   1. A ladder to 101. Landing on it violates the position CHECK, which
--      aborts the whole turn transaction -- so the roll is discarded and
--      the player simply rolls again. A silent reroll, from a board
--      nobody validated.
--
--   2. Snakes on every cell from 94 to 99. Every approach to 100 is sent
--      backwards, and no game on that board can ever end. Legal by every
--      other rule.
--
-- Reachability is the real check, and it is cheap: from every cell, can
-- a sequence of rolls arrive at 100?
CREATE OR REPLACE FUNCTION public.validate_snakes_board()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_head text;
  v_dest int;
  v_all jsonb;
  v_reachable boolean[];
  v_changed boolean;
  v_cell int;
  v_roll int;
  v_target int;
  v_landing int;
BEGIN
  IF NOT (NEW.features ? 'ladders' AND NEW.features ? 'snakes') THEN
    RAISE EXCEPTION 'board % must define ladders and snakes', NEW.version;
  END IF;
  IF jsonb_typeof(NEW.features->'ladders') <> 'object'
     OR jsonb_typeof(NEW.features->'snakes') <> 'object' THEN
    RAISE EXCEPTION 'board %: ladders and snakes must be objects', NEW.version;
  END IF;

  v_all := (NEW.features->'ladders') || (NEW.features->'snakes');

  IF (SELECT count(*) FROM jsonb_object_keys(NEW.features->'ladders'))
     + (SELECT count(*) FROM jsonb_object_keys(NEW.features->'snakes'))
     <> (SELECT count(*) FROM jsonb_object_keys(v_all)) THEN
    RAISE EXCEPTION 'board %: a cell is the head of two features', NEW.version;
  END IF;

  FOR v_head, v_dest IN SELECT key, value::int FROM jsonb_each_text(v_all)
  LOOP
    -- Ranges. Everything must land on a real cell that is neither the
    -- start nor the finish.
    IF v_head !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'board %: head % is not a cell', NEW.version, v_head;
    END IF;
    IF v_head::int NOT BETWEEN 2 AND 99 THEN
      RAISE EXCEPTION
        'board %: head % is outside 2..99', NEW.version, v_head;
    END IF;
    IF v_dest NOT BETWEEN 2 AND 99 THEN
      RAISE EXCEPTION
        'board %: feature at % goes to %, outside 2..99',
        NEW.version, v_head, v_dest;
    END IF;
    IF v_all ? v_dest::text THEN
      RAISE EXCEPTION
        'board %: feature at % lands on another head', NEW.version, v_head;
    END IF;
  END LOOP;

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

  -- REACHABILITY. Work backwards from 100: a cell is reachable if any
  -- roll from it lands somewhere reachable. Iterate to a fixed point.
  v_reachable := array_fill(false, ARRAY[101]);
  v_reachable[101] := true;  -- index 101 is cell 100 (0 is off-board)

  LOOP
    v_changed := false;
    FOR v_cell IN 0..99 LOOP
      CONTINUE WHEN v_reachable[v_cell + 1];
      FOR v_roll IN 1..6 LOOP
        v_target := v_cell + v_roll;
        IF v_target > 100 THEN
          v_landing := 100 - (v_target - 100);
        ELSE
          v_landing := v_target;
        END IF;
        IF v_all ? v_landing::text THEN
          v_landing := (v_all->>v_landing::text)::int;
        END IF;
        IF v_reachable[v_landing + 1] THEN
          v_reachable[v_cell + 1] := true;
          v_changed := true;
          EXIT;
        END IF;
      END LOOP;
    END LOOP;
    EXIT WHEN NOT v_changed;
  END LOOP;

  FOR v_cell IN 0..99 LOOP
    IF NOT v_reachable[v_cell + 1] THEN
      RAISE EXCEPTION
        'board %: cell % can never reach 100 -- the game would not end',
        NEW.version, v_cell;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;
