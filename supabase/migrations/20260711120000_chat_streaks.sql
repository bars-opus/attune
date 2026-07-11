-- Conversation streak: consecutive local days on which BOTH partners messaged.
-- Flag-gated (chat_streaks, default false) until its celebratory framing passes
-- clinical/cultural review — a broken streak must never read as loss/pressure.

INSERT INTO public.feature_flags (key, enabled)
VALUES ('chat_streaks', false)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.chat_conversation_streak(
  p_relationship_id uuid,
  p_utc_offset_minutes int DEFAULT 0
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_rel public.relationships%ROWTYPE;
  v_streak int := 0;
  v_today date;
BEGIN
  IF v_user_id IS NULL THEN RETURN 0; END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = p_relationship_id
    AND chat_archived_at IS NULL
    AND (user_a = v_user_id OR user_b = v_user_id);
  IF NOT FOUND OR v_rel.user_b IS NULL THEN RETURN 0; END IF;

  v_today := ((now() + make_interval(mins => p_utc_offset_minutes))::date);

  -- No temp table (the function may be called multiple times per transaction).
  -- qual_days = local days where BOTH members messaged; anchor = the most
  -- recent qualifying day, but only if it is today or yesterday; the streak is
  -- the count of consecutive qualifying days ending at that anchor.
  WITH qual_days AS (
    SELECT ((m.created_at + make_interval(mins => p_utc_offset_minutes))::date) AS day
    FROM public.messages m
    WHERE m.relationship_id = p_relationship_id
    GROUP BY 1
    HAVING bool_or(m.sender_id = v_rel.user_a)
       AND bool_or(m.sender_id = v_rel.user_b)
  ),
  anchor AS (
    SELECT max(day) AS day FROM qual_days
    WHERE day IN (v_today, v_today - 1)
  ),
  streak AS (
    -- Consecutive days ending at the anchor: a qualifying day is in the streak
    -- iff (anchor - day) equals its descending rank offset among qualifying
    -- days <= anchor.
    SELECT count(*) AS n
    FROM (
      SELECT q.day,
             (SELECT a.day FROM anchor a) - q.day AS gap,
             row_number() OVER (ORDER BY q.day DESC) - 1 AS rn
      FROM qual_days q, anchor a
      WHERE a.day IS NOT NULL AND q.day <= a.day
    ) ranked
    WHERE ranked.gap = ranked.rn
  )
  SELECT COALESCE((SELECT n FROM streak), 0) INTO v_streak;

  RETURN v_streak;
END;
$$;

REVOKE ALL ON FUNCTION public.chat_conversation_streak(uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_conversation_streak(uuid, int) TO authenticated;
