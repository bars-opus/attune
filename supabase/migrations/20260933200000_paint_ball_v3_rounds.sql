-- Paint Ball v3: a round is an exchange between BOTH players (spec §5.5).
--
-- Two rows now share a round_number -- one per player -- and the round
-- resolves when the second arrives. That collides with the table-wide
-- UNIQUE(session_id, round_number) that game_session_rounds has carried
-- since 36 Questions created it.
--
-- The constraint is still correct for the other six games on this table
-- (this_or_that, truth_or_dare, mirror, scenario, sliding_scale, love_map),
-- every one of which writes exactly one row per round. So it is replaced
-- with two PARTIAL unique indexes rather than dropped: the old rule keeps
-- applying to everything except Paint Ball, and Paint Ball gets a rule that
-- admits a second row only from the other player.
--
-- Dropping the constraint outright would silently let any of those six write
-- a duplicate round.

-- The predicate needs the session's game_type, which is on game_sessions,
-- so a partial index cannot test it directly. Denormalize it onto the row:
-- it is immutable for the life of a session, so there is nothing to keep in
-- sync.
ALTER TABLE public.game_session_rounds
  ADD COLUMN IF NOT EXISTS game_type text;

UPDATE public.game_session_rounds r
SET game_type = s.game_type
FROM public.game_sessions s
WHERE r.session_id = s.id AND r.game_type IS NULL;

-- Backfill first, then enforce, so an existing row cannot block the trigger.
CREATE OR REPLACE FUNCTION public.set_game_round_game_type()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.game_type IS NULL THEN
    SELECT game_type INTO NEW.game_type
    FROM public.game_sessions WHERE id = NEW.session_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS game_session_rounds_set_game_type ON public.game_session_rounds;
CREATE TRIGGER game_session_rounds_set_game_type
BEFORE INSERT ON public.game_session_rounds
FOR EACH ROW EXECUTE FUNCTION public.set_game_round_game_type();

ALTER TABLE public.game_session_rounds
  DROP CONSTRAINT IF EXISTS game_session_rounds_session_id_round_number_key;

-- Every other game: one row per (session, round). Unchanged behaviour.
CREATE UNIQUE INDEX IF NOT EXISTS idx_game_rounds_one_per_round
  ON public.game_session_rounds(session_id, round_number)
  WHERE game_type IS DISTINCT FROM 'paint_ball';

-- Paint Ball: one row per (session, round, player). A player retrying their
-- own half must not create a second row, and must never be mistaken for
-- their partner's half.
CREATE UNIQUE INDEX IF NOT EXISTS idx_paint_ball_rounds_one_per_player
  ON public.game_session_rounds(session_id, round_number, active_partner_id)
  WHERE game_type = 'paint_ball';

-- Null until the round's other half arrives and both halves resolve
-- together. Its nullness IS the "awaiting partner" state, so there is no
-- separate status column to drift out of sync with reality -- and it is the
-- boundary that decides whether a hide_position may be shown (§10.3).
ALTER TABLE public.game_session_rounds
  ADD COLUMN IF NOT EXISTS resolved_at timestamptz;

-- v3 has no turn that cannot hit, so 'opening' is retired. Existing rows
-- keep it (history stays readable); new rows may not use it.
ALTER TABLE public.game_session_rounds
  DROP CONSTRAINT IF EXISTS game_session_rounds_shot_result_check;
ALTER TABLE public.game_session_rounds
  ADD CONSTRAINT game_session_rounds_shot_result_check
  CHECK (shot_result IS NULL OR shot_result IN ('hit', 'miss', 'opening'));

CREATE INDEX IF NOT EXISTS idx_paint_ball_rounds_unresolved
  ON public.game_session_rounds(session_id, round_number)
  WHERE game_type = 'paint_ball' AND resolved_at IS NULL;

COMMENT ON COLUMN public.game_session_rounds.resolved_at IS
  'Paint Ball v3: set on BOTH rows of a round when its second half arrives '
  'and the two shots resolve against each other. Also the disclosure '
  'boundary -- hide_position may reach a client only once this is set.';
