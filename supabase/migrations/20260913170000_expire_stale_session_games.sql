-- Mirror, Sliding Scale and Scenario had no expiry path.
--
-- game_sessions carries abandoned_at / abandon_reason, and paint ball and
-- 36 Questions both sweep their stale sessions -- but nothing ever did for
-- the three session games. That is not merely missing housekeeping:
-- createSession reuses any session whose status is 'invited' or 'active',
-- so a couple who abandoned a game mid-round (one partner answered, the
-- other never did) got that same stuck session back on every later attempt
-- and waited forever on a both_answered that could not flip. There was no
-- client escape either -- no quit, no restart.
--
-- Seven days rather than paint ball's 24 hours: these are reflective games
-- a couple may reasonably return to across a week, where paint ball is a
-- single sitting. Measured from the last round so "inactivity" means
-- inactivity, not session age.
CREATE OR REPLACE FUNCTION public.expire_stale_session_games()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  WITH stale AS (
    UPDATE public.game_sessions s
    SET status = 'abandoned',
        abandon_reason = 'inactivity',
        abandoned_at = now()
    WHERE s.game_type IN ('mirror', 'sliding_scale', 'scenario')
      AND s.status IN ('invited', 'active')
      AND COALESCE(
            (SELECT max(r.created_at)
             FROM public.game_session_rounds r
             WHERE r.session_id = s.id),
            s.created_at
          ) < now() - interval '7 days'
    RETURNING s.id
  )
  SELECT count(*) INTO v_count FROM stale;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_stale_session_games() FROM PUBLIC, anon;
-- Backend only: this is a sweep, never a client action. A client that wants
-- out of a session should get an explicit abandon RPC of its own.
GRANT EXECUTE ON FUNCTION public.expire_stale_session_games() TO service_role;

DO $$
BEGIN
  PERFORM cron.unschedule('expire-stale-session-games');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

SELECT cron.schedule(
  'expire-stale-session-games',
  '27 * * * *',
  $$ SELECT public.expire_stale_session_games(); $$
);
