-- Lets a couple leave a stuck session game immediately.
--
-- expire_stale_session_games is the seven-day safety net; this is the
-- escape hatch. Mirror, Sliding Scale and Scenario had neither, which is
-- what made an abandoned round a permanent lockout: createSession keeps
-- returning any session whose status is 'invited' or 'active', so without
-- a way out the couple could never start that game again.
--
-- An RPC rather than a client-side UPDATE (which is how this_or_that and
-- truth_or_dare do it): game_sessions' RLS is FOR ALL for relationship
-- members, so a direct write lets a client set ANY status -- flipping a
-- finished game back to 'active', or marking one 'completed' to trigger
-- scoring it never earned. This narrows that to exactly one transition.
CREATE OR REPLACE FUNCTION public.abandon_session_game(p_session_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_is_member boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.game_sessions s
    JOIN public.relationships rel ON rel.id = s.relationship_id
    WHERE s.id = p_session_id
      AND (rel.user_a = v_user_id OR rel.user_b = v_user_id)
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    -- Same response whether the session belongs to someone else or does
    -- not exist: a distinguishable error is a membership oracle.
    RAISE EXCEPTION 'Session unavailable';
  END IF;

  -- Only forward, and only from a live state. A completed session keeps
  -- its result, and a second call is a no-op rather than an error -- a
  -- double tap must not fail.
  UPDATE public.game_sessions
     SET status = 'abandoned',
         abandon_reason = 'user_initiated',
         abandoned_at = now()
   WHERE id = p_session_id
     AND status IN ('invited', 'active');
END;
$$;

REVOKE ALL ON FUNCTION public.abandon_session_game(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.abandon_session_game(uuid) TO authenticated;
