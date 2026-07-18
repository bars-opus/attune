-- Hardening pass on chat_conversation_streak (feature unchanged, still
-- flag-gated off behind 'chat_streaks'):
--   1. p_utc_offset_minutes was unbounded client input — now clamped to the
--      valid UTC offset range [-720, +840] so a client cannot shift the day
--      window arbitrarily.
--   2. The qualifying-days scan covered the relationship's full message
--      history on every call — now bounded to the last 366 local days, which
--      caps the reported streak at 366 (display as "365+" if it ever matters)
--      and keeps the query cost flat as history grows. Uses the
--      (relationship_id, created_at) index.
--   3. Marked STABLE (read-only) so the planner can optimize repeated calls.
-- Same signature, so CREATE OR REPLACE is safe; grants unchanged.

CREATE OR REPLACE FUNCTION public.chat_conversation_streak(
  p_relationship_id uuid,
  p_utc_offset_minutes int DEFAULT 0
)
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_rel public.relationships%ROWTYPE;
  v_streak int := 0;
  v_offset int;
  v_today date;
  v_horizon timestamptz;
BEGIN
  IF v_user_id IS NULL THEN RETURN 0; END IF;

  -- Valid UTC offsets span UTC-12:00 .. UTC+14:00.
  v_offset := greatest(-720, least(840, coalesce(p_utc_offset_minutes, 0)));

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = p_relationship_id
    AND chat_archived_at IS NULL
    AND (user_a = v_user_id OR user_b = v_user_id);
  IF NOT FOUND OR v_rel.user_b IS NULL THEN RETURN 0; END IF;

  v_today := ((now() + make_interval(mins => v_offset))::date);
  -- Only messages from the last 366 local days can contribute to a streak
  -- anchored at today/yesterday; older history cannot extend it past the cap.
  v_horizon := (v_today - 366)::timestamptz - make_interval(mins => v_offset);

  WITH qual_days AS (
    SELECT ((m.created_at + make_interval(mins => v_offset))::date) AS day
    FROM public.messages m
    WHERE m.relationship_id = p_relationship_id
      AND m.created_at >= v_horizon
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
