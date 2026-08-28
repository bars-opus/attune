-- Love Map: sessionless rounds.
--
-- game_session_rounds is shared by 36 Questions, this_or_that, paint ball
-- and the three session games. Love Map is the first consumer with no
-- session, so session_id becomes nullable and a relationship_id is added
-- alongside it. Keeping Love Map in this table is what lets the §8.4 reveal
-- gate, the FOR UPDATE OF r race fix and the truth branch be reused rather
-- than forked -- a second copy of that gate is what produced the C2 breach.
ALTER TABLE public.game_session_rounds
  ADD COLUMN IF NOT EXISTS relationship_id uuid
    REFERENCES public.relationships(id) ON DELETE CASCADE;

ALTER TABLE public.game_session_rounds
  ALTER COLUMN session_id DROP NOT NULL;

-- Exactly one owner. num_nonnulls is what makes "a round belongs to a
-- session XOR a relationship" a constraint rather than a convention.
ALTER TABLE public.game_session_rounds
  DROP CONSTRAINT IF EXISTS game_session_rounds_owner_check;
ALTER TABLE public.game_session_rounds
  ADD CONSTRAINT game_session_rounds_owner_check
  CHECK (num_nonnulls(session_id, relationship_id) = 1);

CREATE INDEX IF NOT EXISTS idx_game_session_rounds_relationship
  ON public.game_session_rounds(relationship_id, round_number)
  WHERE relationship_id IS NOT NULL;

-- game_questions: add the love_map branch. Every pre-existing branch is
-- reproduced verbatim so this is provably a widening, never a relaxation.
ALTER TABLE public.game_questions
  DROP CONSTRAINT IF EXISTS game_questions_game_type_check;
ALTER TABLE public.game_questions
  ADD CONSTRAINT game_questions_game_type_check
  CHECK (game_type IN (
    'this_or_that', 'truth_or_dare',
    'mirror', 'sliding_scale', 'scenario', 'love_map'
  ));

-- The per-type shape constraint is game_questions_shape_check (an earlier
-- draft of this migration widened a differently-named constraint and left
-- this one untouched, which rejected every love_map row). Each pre-existing
-- branch below is transcribed from the live definition verbatim, so this is
-- provably a widening.
ALTER TABLE public.game_questions
  DROP CONSTRAINT IF EXISTS game_questions_shape_check;
ALTER TABLE public.game_questions
  ADD CONSTRAINT game_questions_shape_check
  CHECK (
    (game_type = 'this_or_that'
      AND question_subtype IS NULL
      AND option_a IS NOT NULL
      AND option_b IS NOT NULL)
    OR
    (game_type = 'truth_or_dare'
      AND question_subtype IS NOT NULL
      AND option_a IS NULL
      AND option_b IS NULL)
    OR
    (game_type = 'mirror'
      AND question_subtype IS NULL
      AND option_a IS NULL
      AND option_b IS NULL)
    OR
    (game_type = 'sliding_scale'
      AND question_subtype IS NULL
      AND value_domain IS NOT NULL
      AND scale_low IS NOT NULL
      AND scale_high IS NOT NULL
      AND option_a IS NULL
      AND option_b IS NULL)
    OR
    (game_type = 'scenario'
      AND question_subtype IS NULL
      AND options IS NOT NULL
      AND jsonb_typeof(options) = 'array'
      AND jsonb_array_length(options) >= 3
      AND jsonb_array_length(options) <= 4
      AND option_a IS NULL
      AND option_b IS NULL)
    OR
    -- Love Map: a free-text prompt about the partner's inner world.
    -- value_domain is required because it is what the refresh job maps a
    -- detected chat topic onto.
    (game_type = 'love_map'
      AND question_subtype IS NULL
      AND value_domain IS NOT NULL
      AND option_a IS NULL
      AND option_b IS NULL)
  );

-- game_questions_seen was never widened when the session games shipped, so
-- rotation is unavailable to mirror/sliding_scale/scenario today. Widening
-- it to all six types is required for Love Map's six-month re-ask and fixes
-- that omission as a side effect.
ALTER TABLE public.game_questions_seen
  DROP CONSTRAINT IF EXISTS game_questions_seen_game_type_check;
ALTER TABLE public.game_questions_seen
  ADD CONSTRAINT game_questions_seen_game_type_check
  CHECK (game_type IN (
    'this_or_that', 'truth_or_dare',
    'mirror', 'sliding_scale', 'scenario', 'love_map'
  ));

COMMENT ON COLUMN public.game_session_rounds.relationship_id IS
  'Set only for sessionless (Love Map) rounds; null for session rounds.';
COMMENT ON TABLE public.mirror_round_truth IS
  'Subject-authored truth for a guess-and-truth round. Serves Mirror AND '
  'Love Map -- the mirror_ prefix is historical, not a scope.';
