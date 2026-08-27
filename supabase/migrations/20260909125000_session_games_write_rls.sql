-- Fix round 1: cross-couple write hole in the session-games RLS from
-- 20260909120000.
--
-- Both WITH CHECK clauses tested only "the caller is who they claim to
-- be" (subject_id = auth.uid() / user_id = auth.uid()). Neither tied
-- the target round_id / session_id to a relationship the caller
-- belongs to, so any authenticated user could INSERT a
-- mirror_round_truth row against ANY existing round_id, or a
-- mirror_scores row against ANY existing session_id, as long as they
-- named themselves in the checked column. That is cross-couple data
-- pollution: an outsider writing into another couple's game.
--
-- The already-applied migration is not edited (an applied migration
-- must not be rewritten); this migration drops and recreates only the
-- two WITH CHECK-bearing policies, adding the same relationship-
-- membership subquery already used by get_revealed_round() and by
-- mirror_truth_members_read: join round -> session -> relationship and
-- require the caller to be one of its two members.

-- ---------------------------------------------------------------------
-- mirror_round_truth: writer must be both the named subject AND a
-- member of the relationship that owns the round they're writing into.
-- ---------------------------------------------------------------------

DROP POLICY IF EXISTS mirror_truth_subject_write ON public.mirror_round_truth;
CREATE POLICY mirror_truth_subject_write
ON public.mirror_round_truth FOR INSERT
WITH CHECK (
  subject_id = auth.uid()
  AND round_id IN (
    SELECT r.id FROM public.game_session_rounds r
    JOIN public.game_sessions s ON s.id = r.session_id
    JOIN public.relationships rel ON rel.id = s.relationship_id
    WHERE rel.user_a = auth.uid() OR rel.user_b = auth.uid()
  )
);

-- ---------------------------------------------------------------------
-- mirror_scores — §11.1 stays read-side only: USING is left EXACTLY
-- `user_id = auth.uid()` so a partner can never read the other's
-- attentiveness score, even to prove relationship membership. Only the
-- WITH CHECK (write path) gains the membership condition, so a caller
-- can score only a session belonging to a relationship they're in.
-- ---------------------------------------------------------------------

DROP POLICY IF EXISTS mirror_scores_self_only ON public.mirror_scores;
CREATE POLICY mirror_scores_self_only
ON public.mirror_scores FOR ALL
USING (user_id = auth.uid())
WITH CHECK (
  user_id = auth.uid()
  AND session_id IN (
    SELECT s.id FROM public.game_sessions s
    JOIN public.relationships rel ON rel.id = s.relationship_id
    WHERE rel.user_a = auth.uid() OR rel.user_b = auth.uid()
  )
);
