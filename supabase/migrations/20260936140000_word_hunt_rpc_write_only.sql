-- SECURITY: Word Hunt sessions become RPC-write-only.
--
-- THE HOLE THIS CLOSES, verified against a database before this file was
-- written. The shared game_sessions policies grant relationship members
-- INSERT, UPDATE and DELETE on every game type not named in a carve-out.
-- Word Hunt was not named, so a player could:
--
--   UPDATE game_sessions SET status = 'completed' WHERE id = ...;
--   DELETE FROM game_sessions WHERE id = ...;
--   INSERT INTO game_sessions (..., game_type) VALUES (..., 'word_hunt');
--
-- All three worked. Completing the session directly releases the reveal
-- before a partner has finished -- which is the entire disclosure
-- boundary in §10 bypassed by one statement. Deleting it destroys a live
-- game the partner is mid-hunt in. Inserting one creates a session with
-- no puzzle row behind it, so start returns NO_PUZZLE forever.
--
-- This is the SAME defect Snakes shipped and had to fix in
-- 20260935130000. It recurs because the permissive branch is the default:
-- a new game_type inherits write access unless it opts out. Naming it
-- here is the opt-out.
--
-- Direct SELECT stays open. The shared row carries only lifecycle state:
-- every piece of puzzle material and every attempt lives in a table with
-- authenticated revoked outright.

DROP POLICY IF EXISTS "game_sessions_relationship_members_insert"
  ON public.game_sessions;
CREATE POLICY "game_sessions_relationship_members_insert"
ON public.game_sessions FOR INSERT
WITH CHECK (
  game_type NOT IN ('paint_ball', 'snakes_and_ladders', 'word_hunt')
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
  game_type NOT IN ('paint_ball', 'snakes_and_ladders', 'word_hunt')
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
)
WITH CHECK (
  game_type NOT IN ('paint_ball', 'snakes_and_ladders', 'word_hunt')
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
  game_type NOT IN ('paint_ball', 'snakes_and_ladders', 'word_hunt')
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

-- Word Hunt writes no rounds -- there are no turns -- but the round
-- policies are widened for the same reason: a game type that cannot
-- legitimately write rounds should not be able to write them.
DROP POLICY IF EXISTS "game_rounds_relationship_members_insert"
  ON public.game_session_rounds;
CREATE POLICY "game_rounds_relationship_members_insert"
ON public.game_session_rounds FOR INSERT
WITH CHECK (
  session_id IN (
    SELECT s.id FROM public.game_sessions s
    WHERE s.game_type NOT IN
            ('paint_ball', 'snakes_and_ladders', 'word_hunt')
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
    WHERE s.game_type NOT IN
            ('paint_ball', 'snakes_and_ladders', 'word_hunt')
      AND s.relationship_id IN (
        SELECT id FROM public.relationships
        WHERE user_a = auth.uid() OR user_b = auth.uid()
      )
  )
)
WITH CHECK (
  session_id IN (
    SELECT s.id FROM public.game_sessions s
    WHERE s.game_type NOT IN
            ('paint_ball', 'snakes_and_ladders', 'word_hunt')
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
    WHERE s.game_type NOT IN
            ('paint_ball', 'snakes_and_ladders', 'word_hunt')
      AND s.relationship_id IN (
        SELECT id FROM public.relationships
        WHERE user_a = auth.uid() OR user_b = auth.uid()
      )
  )
);

-- ---------------------------------------------------------------------
-- Shared allowlists.
-- ---------------------------------------------------------------------
-- The generic sweep must not reach Word Hunt: it abandons the session
-- without closing the in-progress attempts underneath it, which would
-- leave an attempt that is neither running nor finished.
-- expire_word_hunt_sessions() does both.
CREATE OR REPLACE FUNCTION public.game_type_display_name(p_game_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    CASE p_game_type
      WHEN 'this_or_that'       THEN 'This or That'
      WHEN 'truth_or_dare'      THEN 'Truth or Dare'
      WHEN '36_questions'       THEN '36 Questions'
      WHEN 'mirror'             THEN 'Mirror'
      WHEN 'sliding_scale'      THEN 'Sliding Scale'
      WHEN 'scenario'           THEN 'Scenario'
      WHEN 'love_map'           THEN 'Love Map'
      WHEN 'paint_ball'         THEN 'Paint Ball'
      WHEN 'snakes_and_ladders' THEN 'Snakes and Ladders'
      WHEN 'word_hunt'          THEN 'Word Hunt'
    END,
    initcap(replace(p_game_type, '_', ' '))
  );
$$;
