-- SECURITY: Snakes sessions and rounds become RPC-write-only.
--
-- THE HOLE THIS CLOSES. The shared policies on game_sessions and
-- game_session_rounds grant relationship members INSERT, UPDATE and
-- DELETE on every game EXCEPT paint_ball, which carved itself out with
-- `game_type <> 'paint_ball'`. Snakes inherited the permissive branch,
-- so a player could skip the game entirely:
--
--   UPDATE game_sessions
--      SET board_position_a = 100, status = 'completed', winner_user_id = me
--    WHERE id = ...;
--
-- Verified against a local database: it worked. The server-side die, the
-- turn lock, the idempotency guard and the winner logic were all
-- bypassable by writing the table directly -- which makes every other
-- control in this game decorative.
--
-- Reads stay open: both players see the board, and there is no hidden
-- information in this game to protect.

DROP POLICY IF EXISTS "game_sessions_relationship_members_insert"
  ON public.game_sessions;
CREATE POLICY "game_sessions_relationship_members_insert"
ON public.game_sessions FOR INSERT
WITH CHECK (
  game_type NOT IN ('paint_ball', 'snakes_and_ladders')
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

DROP POLICY IF EXISTS "game_sessions_relationship_members_update"
  ON public.game_sessions;
CREATE POLICY "game_sessions_relationship_members_update"
ON public.game_sessions FOR UPDATE
USING (
  game_type NOT IN ('paint_ball', 'snakes_and_ladders')
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
)
WITH CHECK (
  game_type NOT IN ('paint_ball', 'snakes_and_ladders')
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

DROP POLICY IF EXISTS "game_sessions_relationship_members_delete"
  ON public.game_sessions;
CREATE POLICY "game_sessions_relationship_members_delete"
ON public.game_sessions FOR DELETE
USING (
  game_type NOT IN ('paint_ball', 'snakes_and_ladders')
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

-- Rounds: reads stay open for Snakes (the board is public), writes do not.
DROP POLICY IF EXISTS "game_rounds_relationship_members_select"
  ON public.game_session_rounds;
CREATE POLICY "game_rounds_relationship_members_select"
ON public.game_session_rounds FOR SELECT
USING (
  session_id IN (
    SELECT s.id FROM public.game_sessions s
    WHERE s.game_type <> 'paint_ball'
      AND s.relationship_id IN (
        SELECT id FROM public.relationships
        WHERE user_a = auth.uid() OR user_b = auth.uid()
      )
  )
);

DROP POLICY IF EXISTS "game_rounds_relationship_members_insert"
  ON public.game_session_rounds;
CREATE POLICY "game_rounds_relationship_members_insert"
ON public.game_session_rounds FOR INSERT
WITH CHECK (
  session_id IN (
    SELECT s.id FROM public.game_sessions s
    WHERE s.game_type NOT IN ('paint_ball', 'snakes_and_ladders')
      AND s.relationship_id IN (
        SELECT id FROM public.relationships
        WHERE user_a = auth.uid() OR user_b = auth.uid()
      )
  )
);

DROP POLICY IF EXISTS "game_rounds_relationship_members_update"
  ON public.game_session_rounds;
CREATE POLICY "game_rounds_relationship_members_update"
ON public.game_session_rounds FOR UPDATE
USING (
  session_id IN (
    SELECT s.id FROM public.game_sessions s
    WHERE s.game_type NOT IN ('paint_ball', 'snakes_and_ladders')
      AND s.relationship_id IN (
        SELECT id FROM public.relationships
        WHERE user_a = auth.uid() OR user_b = auth.uid()
      )
  )
)
WITH CHECK (
  session_id IN (
    SELECT s.id FROM public.game_sessions s
    WHERE s.game_type NOT IN ('paint_ball', 'snakes_and_ladders')
      AND s.relationship_id IN (
        SELECT id FROM public.relationships
        WHERE user_a = auth.uid() OR user_b = auth.uid()
      )
  )
);

DROP POLICY IF EXISTS "game_rounds_relationship_members_delete"
  ON public.game_session_rounds;
CREATE POLICY "game_rounds_relationship_members_delete"
ON public.game_session_rounds FOR DELETE
USING (
  session_id IN (
    SELECT s.id FROM public.game_sessions s
    WHERE s.game_type NOT IN ('paint_ball', 'snakes_and_ladders')
      AND s.relationship_id IN (
        SELECT id FROM public.relationships
        WHERE user_a = auth.uid() OR user_b = auth.uid()
      )
  )
);

-- ---------------------------------------------------------------------
-- A board version, once played on, is immutable.
-- ---------------------------------------------------------------------
-- Pinning board_version was pointless while the row it points at could
-- still be edited: updating v1 would retroactively rewrite every game
-- ever played on it, and a replay would animate a snake that was never
-- there. Tuning means inserting v2.
CREATE OR REPLACE FUNCTION public.guard_snakes_board_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF EXISTS (SELECT 1 FROM public.game_sessions
                WHERE board_version = OLD.version) THEN
      RAISE EXCEPTION
        'board % has been played on and cannot be deleted', OLD.version;
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.features IS DISTINCT FROM NEW.features
     AND EXISTS (SELECT 1 FROM public.game_sessions
                  WHERE board_version = OLD.version) THEN
    RAISE EXCEPTION
      'board % has been played on; add a new version instead', OLD.version;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS snakes_boards_immutable ON public.snakes_boards;
CREATE TRIGGER snakes_boards_immutable
BEFORE UPDATE OR DELETE ON public.snakes_boards
FOR EACH ROW EXECUTE FUNCTION public.guard_snakes_board_immutable();
