-- Word Hunt: make the state read honor the session expiry contract.
--
-- The review hardening guarded Accept, Start, Submit and Give Up, but a
-- direct state read could still return a 24/48-hour stale session as active
-- until cron ran. Deep links and resumed screens call this RPC directly, so
-- reads need the same lazy session sweep as mutations.
CREATE OR REPLACE FUNCTION public.get_word_hunt_state(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_auth text;
  v_now timestamptz;
  v_needs_expiry boolean;
BEGIN
  v_auth := public.word_hunt_authorize(p_session_id, v_user);
  IF v_auth <> 'OK' THEN
    RETURN public.word_hunt_error(v_auth);
  END IF;

  -- Avoid serialising ordinary reads. If either deadline looks due, lock
  -- the session first and let the helpers re-check beneath that lock.
  SELECT public.word_hunt_session_is_stale(p_session_id)
      OR EXISTS (
        SELECT 1
        FROM public.word_hunt_attempts
        WHERE session_id = p_session_id
          AND status = 'in_progress'
          AND public.word_hunt_is_expired(started_at, clock_timestamp())
      )
    INTO v_needs_expiry;

  IF v_needs_expiry THEN
    PERFORM 1
    FROM public.game_sessions
    WHERE id = p_session_id
    FOR UPDATE;
    v_now := clock_timestamp();

    -- Session expiry closes every open attempt itself. Otherwise only the
    -- caller-independent ten-minute attempt deadline needs sweeping.
    IF NOT public.word_hunt_expire_session_if_stale(p_session_id) THEN
      PERFORM public.word_hunt_expire_attempts(p_session_id, v_now);
      PERFORM public.word_hunt_maybe_complete(p_session_id, v_now);
    END IF;
  END IF;

  RETURN public.word_hunt_state_payload(p_session_id, v_user);
END;
$$;

REVOKE ALL ON FUNCTION public.get_word_hunt_state(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_word_hunt_state(uuid) TO authenticated;
