-- Corrections to the session-games schema and Pulse signal RPC found in
-- final whole-branch review of feat/session-games.
--
-- 20260909120000_session_games_schema.sql and
-- 20260909140000_game_pulse_signals.sql are already applied to the live
-- database and are not edited here — this migration layers fixes on top
-- with CREATE OR REPLACE / DROP+ADD CONSTRAINT.

-- ---------------------------------------------------------------------
-- 1. compute_relationship_game_signals: filter `completed` by game_type
--
-- game_sessions is the SHARED engine table used by all five games. The
-- original `completed` CTE had no game_type filter, so it also counted
-- the three already-shipped games (this_or_that, truth_or_dare,
-- paint_ball, thirty_six_questions) that happen to also write
-- status='completed'/completed_at. That meant sessions_completed (and
-- therefore the Connection score bump in applyGameSignals) was nonzero
-- for every couple who had ever played ANY game, not just the three new
-- diagnostic ones — breaking the "zero game signal is an exact no-op"
-- guarantee for couples who never touched Mirror/Sliding Scale/Scenario.
-- The two downstream CTEs already filter on c.game_type and are
-- unchanged.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.compute_relationship_game_signals(
  p_relationship_id uuid,
  p_window_start timestamptz
)
RETURNS TABLE (
  sessions_completed int,
  sliding_scale_pairs int,
  sliding_scale_avg_gap double precision,
  mirror_rounds_scored int
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH completed AS (
    SELECT s.id, s.game_type
    FROM public.game_sessions s
    WHERE s.relationship_id = p_relationship_id
      AND s.status = 'completed'
      AND s.completed_at >= p_window_start
      -- Only the three new diagnostic games feed the Pulse score (§7).
      -- Without this, this_or_that/truth_or_dare/paint_ball/
      -- thirty_six_questions sessions were also counted here, giving a
      -- false-positive Connection bump to couples with zero engagement
      -- in the games this RPC is actually meant to measure.
      AND s.game_type IN ('mirror', 'sliding_scale', 'scenario')
  ),
  scale_rounds AS (
    -- Only rounds where BOTH partners rated: a one-sided rating has no
    -- gap to measure.
    SELECT abs(r.answer_a::int - r.answer_b::int) AS gap
    FROM public.game_session_rounds r
    JOIN completed c ON c.id = r.session_id
    WHERE c.game_type = 'sliding_scale'
      AND r.both_answered = true
      -- Sliding Scale is a 1-10 rating (§8.4: "both 1 and 10 anchors
      -- required"). The original guard `^[0-9]+$` accepted any
      -- non-negative integer of any length: game_session_rounds' RLS
      -- policy is FOR ALL for relationship members, so any member can
      -- already INSERT an out-of-range value (e.g. '999') directly via
      -- PostgREST with no UI involved. That silently distorted the
      -- averaged gap, and a value with 10+ digits overflows ::int and
      -- RAISEs, killing the whole game's contribution to the score.
      -- Restricting the pattern to exactly 1-10 makes both cases
      -- impossible at the SQL level regardless of what the client sends.
      AND r.answer_a ~ '^([1-9]|10)$'
      AND r.answer_b ~ '^([1-9]|10)$'
  ),
  mirror_rounds AS (
    SELECT count(*)::int AS n
    FROM public.game_session_rounds r
    JOIN completed c ON c.id = r.session_id
    WHERE c.game_type = 'mirror'
      AND r.both_answered = true
  )
  SELECT
    (SELECT count(*)::int FROM completed),
    (SELECT count(*)::int FROM scale_rounds),
    (SELECT avg(gap)::double precision FROM scale_rounds),
    (SELECT n FROM mirror_rounds);
$$;

-- CREATE OR REPLACE resets function privileges, so re-apply them.
REVOKE ALL ON FUNCTION
  public.compute_relationship_game_signals(uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.compute_relationship_game_signals(uuid, timestamptz)
  TO service_role;

-- ---------------------------------------------------------------------
-- 2. game_questions_shape_check: constrain option_a/option_b on the
--    three new branches too
--
-- The two pre-existing branches (this_or_that, truth_or_dare) are
-- strict about option_a/option_b in both directions. The three branches
-- added for mirror/sliding_scale/scenario said nothing about
-- option_a/option_b, so a mirror row with option_a set would pass —
-- looser than the table's established convention that a row's shape is
-- fully determined by its game_type. This reproduces the two existing
-- branches verbatim and adds "AND option_a IS NULL AND option_b IS
-- NULL" to each of the three new ones.
--
-- Verified against the 40 seed rows in
-- 20260909130000_session_games_content.sql before writing this: all
-- three seed INSERTs (mirror x24, sliding_scale x6, scenario x10) omit
-- option_a/option_b from their column lists entirely, so those columns
-- are NULL on every seeded row and this tightening does not reject them.
-- ---------------------------------------------------------------------

ALTER TABLE public.game_questions
  DROP CONSTRAINT IF EXISTS game_questions_shape_check;

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
      AND question_subtype IS NULL
      AND option_a IS NULL
      AND option_b IS NULL)
    OR
    -- Sliding Scale: both 1 and 10 anchors required, or the rating is
    -- meaningless, plus the §8.4 value domain it belongs to.
    (game_type = 'sliding_scale'
      AND question_subtype IS NULL
      AND value_domain IS NOT NULL
      AND scale_low IS NOT NULL
      AND scale_high IS NOT NULL
      AND option_a IS NULL
      AND option_b IS NULL)
    OR
    -- Scenario: 3-4 options as [{"key":"a","text":"..."}].
    -- jsonb rather than more nullable text columns because the count
    -- varies; option_a/option_b cannot express 3 or 4.
    (game_type = 'scenario'
      AND question_subtype IS NULL
      AND options IS NOT NULL
      AND jsonb_typeof(options) = 'array'
      AND jsonb_array_length(options) BETWEEN 3 AND 4
      AND option_a IS NULL
      AND option_b IS NULL)
  );
