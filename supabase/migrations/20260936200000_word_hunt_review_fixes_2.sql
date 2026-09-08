-- Word Hunt review fixes, part two: findings 4, 7 and 9.

-- ---------------------------------------------------------------------
-- FINDING 4: an expired session stayed playable until cron or the lobby.
-- ---------------------------------------------------------------------
-- Session expiry was only invoked from creation and the lobby lookup.
-- Accept, Start, Submit and Give Up never checked the 48h/24h deadline
-- themselves, so during the hourly cron gap a client that goes straight
-- to a session -- a push notification, a deep link, a resumed screen --
-- could accept a 50-hour-old invitation and start hunting on it.
-- Reproduced:
--
--   CONFIRMED: accepted a 50-hour-old invitation -> {"ok": true, ...}
--   CONFIRMED: started hunting on an expired session
--
-- The migration comment claimed "every game RPC also expires lazily on
-- the way past". That was true of the ATTEMPT deadline and false of the
-- SESSION deadline, and I wrote the sentence as though it covered both.
--
-- One guard, called by every entry point that can act on a session.
-- Returns true if the session was stale and has now been closed.
CREATE OR REPLACE FUNCTION public.word_hunt_expire_session_if_stale(
  p_session_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz;
BEGIN
  -- Caller already holds the session lock; the order is session-then-
  -- attempt here as everywhere else.
  IF NOT public.word_hunt_session_is_stale(p_session_id) THEN
    RETURN false;
  END IF;

  v_now := clock_timestamp();

  UPDATE public.word_hunt_attempts
     SET status = 'timed_out',
         finished_at = GREATEST(v_now, started_at)
   WHERE session_id = p_session_id AND status = 'in_progress';

  UPDATE public.game_sessions
     SET status = 'abandoned',
         abandoned_at = v_now,
         abandon_reason = COALESCE(abandon_reason, 'inactivity'),
         current_turn_user_id = NULL
   WHERE id = p_session_id;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.word_hunt_accept_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.word_hunt_error('UNAUTHORIZED');
  END IF;

  SELECT * INTO v_session FROM public.game_sessions
  WHERE id = p_session_id AND game_type = 'word_hunt'
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.word_hunt_error('NOT_FOUND');
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;
  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.word_hunt_error('FORBIDDEN');
  END IF;
  IF v_rel.status <> 'active' OR v_rel.chat_archived_at IS NOT NULL THEN
    RETURN public.word_hunt_error('SESSION_EXPIRED');
  END IF;

  -- Lazy session expiry, under the lock we already hold.
  IF public.word_hunt_expire_session_if_stale(p_session_id) THEN
    RETURN public.word_hunt_error('SESSION_EXPIRED');
  END IF;

  IF v_session.status = 'active' THEN
    RETURN jsonb_build_object('ok', true, 'existing', true);
  END IF;
  IF v_session.status <> 'invited' THEN
    RETURN public.word_hunt_error('SESSION_EXPIRED');
  END IF;
  IF v_session.initiator_id = v_user THEN
    RETURN public.word_hunt_error('FORBIDDEN');
  END IF;

  UPDATE public.game_sessions
     SET status = 'active',
         started_at = COALESCE(started_at, now())
   WHERE id = p_session_id;

  RETURN jsonb_build_object('ok', true, 'existing', false);
END;
$$;

-- ---------------------------------------------------------------------
-- FINDING 9: completed_at could precede the finish that caused it.
-- ---------------------------------------------------------------------
-- Attempts record finished_at from a post-lock clock_timestamp(), but
-- completion wrote now(), which is transaction-start time. After a lock
-- wait the session's completed_at could land BEFORE the second player's
-- finished_at -- a session that finished before its last move.
CREATE OR REPLACE FUNCTION public.word_hunt_maybe_complete(
  p_session_id uuid,
  p_now timestamptz DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_terminal int;
  v_at timestamptz := COALESCE(p_now, clock_timestamp());
BEGIN
  SELECT count(*) INTO v_terminal
  FROM public.word_hunt_attempts
  WHERE session_id = p_session_id AND status <> 'in_progress';

  IF v_terminal >= 2 THEN
    UPDATE public.game_sessions
       SET status = 'completed',
           completed_at = COALESCE(completed_at, v_at)
     WHERE id = p_session_id AND status <> 'completed';
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

-- The single-argument form other migrations call keeps working and picks
-- up a fresh post-lock timestamp.
DROP FUNCTION IF EXISTS public.word_hunt_maybe_complete(uuid);

REVOKE ALL ON FUNCTION public.word_hunt_expire_session_if_stale(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.word_hunt_maybe_complete(uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.word_hunt_accept_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.word_hunt_accept_session(uuid) TO authenticated;
