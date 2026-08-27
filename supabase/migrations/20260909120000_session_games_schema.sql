-- Session games (§8.4): Mirror, Sliding Scale, Scenario.
--
-- These extend the existing generic game engine rather than adding
-- subsystems: game_sessions/game_session_rounds already carry
-- game_type, answer_a/answer_b, both_answered and revealed_at, and all
-- three shipped games use them with no tables of their own.

-- ---------------------------------------------------------------------
-- 1. Widen game_questions
-- ---------------------------------------------------------------------

ALTER TABLE public.game_questions
  ADD COLUMN IF NOT EXISTS value_domain text,
  ADD COLUMN IF NOT EXISTS scale_low text,
  ADD COLUMN IF NOT EXISTS scale_high text,
  ADD COLUMN IF NOT EXISTS options jsonb;

ALTER TABLE public.game_questions
  DROP CONSTRAINT IF EXISTS game_questions_game_type_check;

ALTER TABLE public.game_questions
  ADD CONSTRAINT game_questions_game_type_check
  CHECK (game_type IN (
    'this_or_that', 'truth_or_dare',
    'mirror', 'sliding_scale', 'scenario'
  ));

-- The original table-level CHECK was unnamed, so Postgres generated
-- `game_questions_check`. It is dropped and replaced with a named
-- constraint covering all five types — the two existing branches are
-- reproduced verbatim so this is a widening, never a relaxation.
ALTER TABLE public.game_questions
  DROP CONSTRAINT IF EXISTS game_questions_check;

ALTER TABLE public.game_questions
  ADD CONSTRAINT game_questions_shape_check CHECK (
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
    -- Mirror: a free-text prompt about the partner's current state.
    (game_type = 'mirror'
      AND question_subtype IS NULL)
    OR
    -- Sliding Scale: both 1 and 10 anchors required, or the rating is
    -- meaningless, plus the §8.4 value domain it belongs to.
    (game_type = 'sliding_scale'
      AND question_subtype IS NULL
      AND value_domain IS NOT NULL
      AND scale_low IS NOT NULL
      AND scale_high IS NOT NULL)
    OR
    -- Scenario: 3-4 options as [{"key":"a","text":"..."}].
    -- jsonb rather than more nullable text columns because the count
    -- varies; option_a/option_b cannot express 3 or 4.
    (game_type = 'scenario'
      AND question_subtype IS NULL
      AND options IS NOT NULL
      AND jsonb_typeof(options) = 'array'
      AND jsonb_array_length(options) BETWEEN 3 AND 4)
  );

-- ---------------------------------------------------------------------
-- 2. mirror_round_truth
--
-- Mirror is the only game whose round holds THREE values: A's guess,
-- B's guess, and the subject's real answer. The third has nowhere to
-- live in the two-column round shape.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.mirror_round_truth (
  round_id uuid PRIMARY KEY
    REFERENCES public.game_session_rounds(id) ON DELETE CASCADE,
  -- Whose inner state this round is about. Mirror alternates, so both
  -- partners are guessed about across the 8 rounds.
  subject_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  truth_text text NOT NULL CHECK (char_length(truth_text) <= 400),
  submitted_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.mirror_round_truth ENABLE ROW LEVEL SECURITY;

-- Both partners may read the truth (it is revealed to both, and that
-- reveal IS the game); only the subject may write their own.
DROP POLICY IF EXISTS mirror_truth_members_read ON public.mirror_round_truth;
CREATE POLICY mirror_truth_members_read
ON public.mirror_round_truth FOR SELECT
USING (
  round_id IN (
    SELECT r.id FROM public.game_session_rounds r
    JOIN public.game_sessions s ON s.id = r.session_id
    JOIN public.relationships rel ON rel.id = s.relationship_id
    WHERE rel.user_a = auth.uid() OR rel.user_b = auth.uid()
  )
);

DROP POLICY IF EXISTS mirror_truth_subject_write ON public.mirror_round_truth;
CREATE POLICY mirror_truth_subject_write
ON public.mirror_round_truth FOR INSERT
WITH CHECK (subject_id = auth.uid());

-- ---------------------------------------------------------------------
-- 3. mirror_scores — §11.1
--
-- "Asymmetric behavioural data is shown to each user about themselves
-- only. Never shown as a judgment of the partner." A per-person
-- attentiveness score on the shared game_sessions row would be readable
-- by both partners by construction, so it lives here instead, scoped by
-- RLS to its own subject. game_sessions.match_count is deliberately
-- left unused by Mirror for exactly this reason.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.mirror_scores (
  session_id uuid NOT NULL
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  score int NOT NULL CHECK (score BETWEEN 0 AND 8),
  flagged boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, user_id)
);

ALTER TABLE public.mirror_scores ENABLE ROW LEVEL SECURITY;

-- The whole §11.1 guarantee, in one clause: a partner cannot read this
-- row even with a direct PostgREST query. Enforced here rather than in
-- a widget so it survives any future client that forgets it.
DROP POLICY IF EXISTS mirror_scores_self_only ON public.mirror_scores;
CREATE POLICY mirror_scores_self_only
ON public.mirror_scores FOR ALL
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

REVOKE ALL ON public.mirror_round_truth FROM PUBLIC, anon;
REVOKE ALL ON public.mirror_scores FROM PUBLIC, anon;
GRANT SELECT, INSERT ON public.mirror_round_truth TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.mirror_scores TO authenticated;

-- ---------------------------------------------------------------------
-- 4. Reveal gate
--
-- game_session_rounds' RLS grants relationship members FOR ALL on the
-- whole row, and both_answered is checked only inside RPCs — never in a
-- policy. So a direct PostgREST select can read a partner's answer
-- before reveal. §8.4 calls that mechanic non-negotiable.
--
-- Fixing it for the three shipped games is out of scope (their clients
-- select the row directly and would break), but the new games must not
-- inherit it: they read answers ONLY through this function, which
-- returns them only once both partners have submitted.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_revealed_round(p_round_id uuid)
RETURNS TABLE (answer_a text, answer_b text, both_answered boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    CASE WHEN r.both_answered THEN r.answer_a ELSE NULL END,
    CASE WHEN r.both_answered THEN r.answer_b ELSE NULL END,
    r.both_answered
  FROM public.game_session_rounds r
  JOIN public.game_sessions s ON s.id = r.session_id
  JOIN public.relationships rel ON rel.id = s.relationship_id
  WHERE r.id = p_round_id
    AND (rel.user_a = auth.uid() OR rel.user_b = auth.uid());
$$;

REVOKE ALL ON FUNCTION public.get_revealed_round(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_revealed_round(uuid) TO authenticated;
