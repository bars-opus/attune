-- Extends the stale-session sweep to this_or_that and truth_or_dare.
--
-- Both differ from the session games in one important way: they DO have
-- working UI abandon paths, so a couple who taps "leave" is fine, and
-- neither carries the permanent lockout that Mirror, Sliding Scale and
-- Scenario did. The gap is narrower -- a user who never taps it, because
-- the app was killed, the phone was lost, or a partner simply stopped
-- playing, leaves an 'active' session that createSession keeps handing
-- back.
--
-- So this is the safety net behind an escape hatch that already exists,
-- not a replacement for one. paint_ball and 36_questions keep their own
-- sweeps (24h and their chapter rules respectively); this covers the five
-- games that reuse sessions through the same
-- inFilter('status', ['invited','active']) find-or-create.
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
    WHERE s.game_type IN (
            'mirror', 'sliding_scale', 'scenario',
            'this_or_that', 'truth_or_dare'
          )
      AND s.status IN ('invited', 'active')
      -- Measured from the last round so "inactivity" means inactivity,
      -- not session age.
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
GRANT EXECUTE ON FUNCTION public.expire_stale_session_games() TO service_role;
