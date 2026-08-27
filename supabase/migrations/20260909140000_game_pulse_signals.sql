-- Game signals for the Pulse score.
--
-- §7 lists "game engagement" as a Connection data source and "values
-- overlap from games" for Alignment, but compute-pulse reads no game
-- table at all — so 40% of the score is computed without the inputs its
-- own specification names.
--
-- Mirrors compute_relationship_chat_signals: pre-aggregates in Postgres
-- so the edge function never selects raw game rows (Algorithm Quality
-- Review Checklist 2.14, memory growth bounds), and is service-role
-- only.

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
  ),
  scale_rounds AS (
    -- Only rounds where BOTH partners rated: a one-sided rating has no
    -- gap to measure.
    SELECT abs(r.answer_a::int - r.answer_b::int) AS gap
    FROM public.game_session_rounds r
    JOIN completed c ON c.id = r.session_id
    WHERE c.game_type = 'sliding_scale'
      AND r.both_answered = true
      AND r.answer_a ~ '^[0-9]+$'
      AND r.answer_b ~ '^[0-9]+$'
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

-- Server-only: these aggregates feed scoring and are not client data.
REVOKE ALL ON FUNCTION
  public.compute_relationship_game_signals(uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.compute_relationship_game_signals(uuid, timestamptz)
  TO service_role;
