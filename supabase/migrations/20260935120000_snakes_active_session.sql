-- Finding the game you already have open.
--
-- The client opens Snakes from a relationship, so it needs a way to
-- discover an invitation or an active session before it knows a session
-- id -- the same shape get_active_paint_ball_session has.
CREATE OR REPLACE FUNCTION public.get_active_snakes_session(
  p_relationship_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session uuid;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.snakes_error('UNAUTHORIZED');
  END IF;

  -- Membership is checked here rather than trusting the id: a caller
  -- who guessed a relationship must not learn whether it has a game.
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships
    WHERE id = p_relationship_id
      AND (user_a = v_user OR user_b = v_user)
  ) THEN
    RETURN public.snakes_error('FORBIDDEN');
  END IF;

  SELECT id INTO v_session
  FROM public.game_sessions
  WHERE relationship_id = p_relationship_id
    AND game_type = 'snakes_and_ladders'
    AND status IN ('invited', 'active')
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_session IS NULL THEN
    RETURN jsonb_build_object('session_id', NULL);
  END IF;

  RETURN public.get_snakes_session_state(v_session);
END;
$$;

REVOKE ALL ON FUNCTION public.get_active_snakes_session(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_active_snakes_session(uuid)
  TO authenticated;

-- Weekly sweep, matching the other games' expiry jobs.
SELECT cron.unschedule('expire-snakes-sessions')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expire-snakes-sessions');

SELECT cron.schedule(
  'expire-snakes-sessions',
  '23 * * * *',
  $$SELECT public.expire_snakes_sessions()$$
);
