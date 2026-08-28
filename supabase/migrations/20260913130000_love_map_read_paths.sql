-- Love Map rounds have no session, so both read paths must resolve the
-- relationship through either owner column. LEFT JOIN game_sessions and
-- COALESCE the two, rather than a UNION: one row source keeps the
-- membership predicate in exactly one place.
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
  LEFT JOIN public.game_sessions s ON s.id = r.session_id
  JOIN public.relationships rel
    ON rel.id = COALESCE(s.relationship_id, r.relationship_id)
  WHERE r.id = p_round_id
    AND (rel.user_a = auth.uid() OR rel.user_b = auth.uid());
$$;

-- CREATE OR REPLACE resets privileges to the default, so the original
-- grants must be reapplied or this becomes a privilege regression.
REVOKE ALL ON FUNCTION public.get_revealed_round(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_revealed_round(uuid) TO authenticated;

-- Same widening for the truth read policy. The both_answered gate and the
-- membership predicate are unchanged -- only how the relationship is
-- reached. Narrowing anything here would break Mirror; widening it would
-- reopen C2.
DROP POLICY IF EXISTS mirror_truth_members_read ON public.mirror_round_truth;
CREATE POLICY mirror_truth_members_read
ON public.mirror_round_truth FOR SELECT
USING (
  subject_id = auth.uid()
  OR round_id IN (
    SELECT r.id
    FROM public.game_session_rounds r
    LEFT JOIN public.game_sessions s ON s.id = r.session_id
    JOIN public.relationships rel
      ON rel.id = COALESCE(s.relationship_id, r.relationship_id)
    WHERE (rel.user_a = auth.uid() OR rel.user_b = auth.uid())
      AND r.both_answered
  )
);
