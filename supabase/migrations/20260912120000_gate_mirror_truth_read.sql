-- Gate mirror_round_truth's read policy on the reveal, and recalibrate
-- the attentiveness flag threshold for its real denominator.
--
-- C2 (Critical): mirror_truth_members_read (20260909120000) grants BOTH
-- relationship members SELECT on a truth row with no both_answered
-- condition. This branch adds Mirror's first writer to that table
-- (submit_session_game_answer, 20260911120000), so it creates the first
-- rounds where a truth actually exists to be read early. Until now the
-- policy was permissive but vacuous — there was nothing behind it.
--
-- The consequence: the guesser can issue one PostgREST call —
-- `from('mirror_round_truth').select('truth_text').eq('round_id', ...)`
-- — and read the subject's real answer before submitting their own
-- guess, then type it back verbatim and score perfectly every round.
-- §8.4 calls the hidden-reveal mechanic non-negotiable, and in Mirror
-- the truth IS the value being guessed at — this is not a minor
-- information leak, it is the entire game's integrity.
--
-- Do NOT edit 20260909120000_session_games_schema.sql — it is already
-- applied. This migration drops and recreates the same-named policy.

DROP POLICY IF EXISTS mirror_truth_members_read ON public.mirror_round_truth;

-- Narrowed, not widened: still requires relationship membership (a
-- stranger can never read this table), and adds a second condition on
-- top of it. A row is now visible only when EITHER of these holds:
--
--   1. The caller is the row's own subject (subject_id = auth.uid()).
--      The subject must always be able to see what they themselves
--      wrote — this is never gated on reveal, or a user could not even
--      review their own answer.
--   2. The round has been revealed (both_answered = true on the joined
--      game_session_rounds row). Only once BOTH partners have submitted
--      does the guesser gain read access to the truth their guess is
--      compared against — mirroring exactly how get_revealed_round
--      already withholds answer_a/answer_b from an early reader.
--
-- DO NOT remove this both_answered clause as "redundant" with the
-- membership check above: membership is who is allowed to ever see this
-- row; both_answered is when. Dropping it silently reopens the C2 hole
-- this migration exists to close, and nothing else in the schema
-- enforces it — mirror_round_truth has no other read gate.
CREATE POLICY mirror_truth_members_read
ON public.mirror_round_truth FOR SELECT
USING (
  subject_id = auth.uid()
  OR round_id IN (
    SELECT r.id FROM public.game_session_rounds r
    JOIN public.game_sessions s ON s.id = r.session_id
    JOIN public.relationships rel ON rel.id = s.relationship_id
    WHERE (rel.user_a = auth.uid() OR rel.user_b = auth.uid())
      AND r.both_answered
  )
);

-- ---------------------------------------------------------------------
-- I2: recalibrate finalise_mirror_scores' attentiveness threshold for
-- its real denominator.
--
-- §8.4 calibrated "below 6.5/8 = attentiveness flag" to tolerate roughly
-- one miss in eight rounds (6.5/8 = 0.8125). But a round's GUESSER only
-- guesses 4 of the 8 rounds — the subject alternates, so each partner is
-- the guesser in exactly half — and the achievable values at n=4 are
-- only 0, 0.25, 0.5, 0.75, 1.0. Applying 0.8125 to that set means only a
-- perfect 4/4 clears it; missing even one guess out of four (a
-- reasonable, non-inattentive outcome) trips the flag every time. That
-- is a much harsher bar than §8.4 intended.
--
-- 0.75 is the nearest achievable point below the original intent: it
-- fires at 2/4 or worse (score < 3), tolerating a single miss out of
-- four the same way 6.5/8 tolerated roughly one miss out of eight.
--
-- CREATE OR REPLACE in full because Postgres has no ALTER FUNCTION for
-- a function body — only the threshold expression changes; the score
-- derivation (SUM/count(*) FILTER), the guesser attribution (the
-- subject_id-vs-user_a/user_b CROSS JOIN LATERAL), and the
-- ON CONFLICT DO UPDATE are reproduced verbatim from
-- 20260911120000_mirror_truth_and_judgement.sql.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.finalise_mirror_scores(
  p_session_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_a uuid;
  v_user_b uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT rel.user_a, rel.user_b
    INTO v_user_a, v_user_b
  FROM public.game_sessions s
  JOIN public.relationships rel ON rel.id = s.relationship_id
  WHERE s.id = p_session_id
    AND s.game_type = 'mirror'
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id);

  IF v_user_a IS NULL THEN
    RAISE EXCEPTION 'Session not found';
  END IF;

  -- One row per guesser. A round's guesser is whichever partner is NOT
  -- its subject, so the score counts the rounds where that person read
  -- their partner correctly.
  INSERT INTO public.mirror_scores (session_id, user_id, score, flagged)
  SELECT
    p_session_id,
    guesser.id,
    count(*) FILTER (WHERE t.was_correct)::int,
    -- §8.4 intends "below 6.5/8" (0.8125) as roughly one tolerated miss
    -- in eight. Each guesser only guesses 4 of the 8 rounds, so 0.8125
    -- applied here would tolerate NO misses at all (only 4/4 clears it)
    -- — 0.75 is the nearest achievable point at n=4 (fires below 3/4),
    -- tolerating one miss the way the spec intended. Do not restore
    -- 6.5/8.0 here; that was correct for an 8-round denominator, not
    -- this 4-round one.
    (count(*) FILTER (WHERE t.was_correct)::numeric
       / NULLIF(count(*), 0)) < 0.75
  FROM public.mirror_round_truth t
  JOIN public.game_session_rounds r ON r.id = t.round_id
  CROSS JOIN LATERAL (
    SELECT CASE WHEN t.subject_id = v_user_a THEN v_user_b
                ELSE v_user_a END AS id
  ) AS guesser
  WHERE r.session_id = p_session_id
    AND t.was_correct IS NOT NULL
  GROUP BY guesser.id
  ON CONFLICT (session_id, user_id) DO UPDATE
    SET score = EXCLUDED.score,
        flagged = EXCLUDED.flagged;
END;
$$;

-- CREATE OR REPLACE resets privileges to the default, so the original
-- grants must be reapplied or this becomes a privilege regression.
REVOKE ALL ON FUNCTION public.finalise_mirror_scores(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalise_mirror_scores(uuid)
  TO authenticated;
