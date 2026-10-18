-- supabase/migrations/20261017190100_mirror_flag_removed.sql
--
-- The Mirror "attentiveness flag" goes (Spec 1b; research 06 §3 F6 (3);
-- owner Q11 "Remove"; ATTUNE_MASTER_SPEC decision 33). It stored a judgement
-- ("flagged") about how well someone reads their partner -- never shown,
-- but a label the product must not keep. The score stays: self-only, shown
-- to its owner at the end of the game.
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
  INSERT INTO public.mirror_scores (session_id, user_id, score)
  SELECT
    p_session_id,
    guesser.id,
    count(*) FILTER (WHERE t.was_correct)::int
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
    SET score = EXCLUDED.score;
END;
$$;

REVOKE ALL ON FUNCTION public.finalise_mirror_scores(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalise_mirror_scores(uuid) TO authenticated;

ALTER TABLE public.mirror_scores DROP COLUMN IF EXISTS flagged;
