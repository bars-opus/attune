-- Word Hunt: fixes for an external implementation review.
--
-- Ten findings, all ten reproduced against a database before being fixed.
-- Three were release-blocking, and all three are in this file. The pattern
-- across them is worth naming: every one lives in a path that no test
-- exercised because the tests were written by the same person who decided
-- which paths mattered.

-- ---------------------------------------------------------------------
-- BLOCKER 1: either partner could kill a live hunt and read the answer.
-- ---------------------------------------------------------------------
-- word_hunt_decline_session checked membership and then abandoned the
-- session whatever its status. Reproduced:
--
--   B is hunting: attempt=in_progress
--   A declines an ACTIVE session -> {"ok": true, "existing": false}
--   session is now: abandoned
--   B attempt is now: timed_out
--   WARNING: A destroyed B's live hunt AND got the answer:
--            [[6,0],[6,1],[6,2],[6,3],[6,4]]
--
-- Worse than a disclosure leak. Because an abandoned session is terminal
-- for disclosure, A -- who never started, and so risked nothing -- ends
-- B's attempt mid-hunt and is handed the placement. That is a griefing
-- move with a reward attached.
--
-- Decline now means "decline an INVITATION". Once both players are in,
-- leaving is not one person's decision: the session ends when both
-- attempts are terminal, or when it expires.
CREATE OR REPLACE FUNCTION public.word_hunt_decline_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
  v_now timestamptz;
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

  v_now := clock_timestamp();

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;
  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.word_hunt_error('FORBIDDEN');
  END IF;

  -- Idempotent: declining twice is one decline.
  IF v_session.status IN ('abandoned', 'completed') THEN
    RETURN jsonb_build_object('ok', true, 'existing', true);
  END IF;

  -- THE FIX. An active session is a game two people agreed to play.
  -- Either partner may still walk away from their own attempt --
  -- word_hunt_give_up exists for exactly that, and it ends only the
  -- caller's attempt while leaving the partner's alone.
  IF v_session.status <> 'invited' THEN
    RETURN public.word_hunt_error('GAME_IN_PROGRESS');
  END IF;

  -- An invitation has no attempts behind it, so there is nothing to
  -- close. Left as a defensive sweep in case a future path creates one.
  UPDATE public.word_hunt_attempts
     SET status = 'timed_out',
         finished_at = GREATEST(v_now, started_at)
   WHERE session_id = p_session_id AND status = 'in_progress';

  UPDATE public.game_sessions
     SET status = 'abandoned', abandoned_at = v_now,
         abandon_reason = COALESCE(abandon_reason, 'user_initiated'),
         current_turn_user_id = NULL
   WHERE id = p_session_id;

  RETURN jsonb_build_object('ok', true, 'existing', false);
END;
$$;

-- The new code needs a sentence of its own.
CREATE OR REPLACE FUNCTION public.word_hunt_error(p_code text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'error', true,
    'code', p_code,
    'message', CASE p_code
      WHEN 'UNAUTHORIZED'     THEN 'Please sign in to play games.'
      WHEN 'FORBIDDEN'        THEN 'You don''t have access to this game.'
      WHEN 'NOT_FOUND'        THEN 'Game session not found.'
      WHEN 'NOT_STARTED'      THEN 'Start the hunt first.'
      WHEN 'GAME_OVER'        THEN 'This game has already finished.'
      -- Says what to do instead, because there IS something to do.
      WHEN 'GAME_IN_PROGRESS' THEN
        'You''ve both joined this one. You can stop looking instead.'
      WHEN 'SESSION_EXPIRED'  THEN 'This session expired. Start a new game.'
      WHEN 'RATE_LIMITED'     THEN 'Slow down a moment.'
      WHEN 'INVALID_INPUT'    THEN 'Invalid value provided.'
      WHEN 'NO_PUZZLE'        THEN 'This game could not be set up. Try again.'
      ELSE 'Something went wrong. Please try again.'
    END
  );
$$;

REVOKE ALL ON FUNCTION public.word_hunt_error(text)
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- BLOCKER 2 and 3: lock order inversion, and a session/attempt race.
-- ---------------------------------------------------------------------
-- Gameplay locks session then attempt. Expiry wrote ATTEMPTS then
-- SESSIONS -- the inverse. Reproduced with two concurrent sessions:
--
--   session A (gameplay order): ERROR: deadlock detected
--
-- My checklist claimed "one lock order, so nothing here deadlocks
-- against itself". That was true of the paths I tested against each
-- other -- submit vs submit, submit vs give-up, start vs start -- and I
-- never ran gameplay against expiry. The claim was about the paths I had
-- thought of, not about the system.
--
-- The same rewrite fixes finding 3. The old routine snapshotted ids,
-- updated attempts, then updated sessions, leaving a window where a
-- concurrent Start inserted an attempt after the attempt-update and
-- before the session lock. Reproduced:
--
--   session  |   attempt
--   abandoned | in_progress
--
-- A clock running on a dead game, which no RPC would ever close.
--
-- Now: iterate session by session, take the SESSION lock first (matching
-- every other path), capture one post-lock timestamp, then close that
-- session's attempts and the session itself inside the same lock.
CREATE OR REPLACE FUNCTION public.word_hunt_expire_sessions_for(
  p_relationship_id uuid
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_now timestamptz;
  v_count int := 0;
  v_still_due boolean;
BEGIN
  FOR v_id IN
    SELECT s.id
    FROM public.game_sessions s
    WHERE s.game_type = 'word_hunt'
      AND s.status IN ('invited', 'active')
      AND (p_relationship_id IS NULL OR s.relationship_id = p_relationship_id)
      AND public.word_hunt_session_is_stale(s.id)
    ORDER BY s.id  -- Stable order, so two sweeps cannot deadlock either.
  LOOP
    -- SESSION FIRST, always. This is the whole fix for the deadlock.
    PERFORM 1 FROM public.game_sessions WHERE id = v_id FOR UPDATE;
    v_now := clock_timestamp();

    -- Re-check under the lock. The set was chosen before the lock was
    -- held, so a player may have started in between -- which is exactly
    -- the race that left an in_progress attempt under an abandoned
    -- session. Re-reading here means a session that came back to life
    -- is left alone instead of being half-closed.
    SELECT public.word_hunt_session_is_stale(v_id)
       AND EXISTS (SELECT 1 FROM public.game_sessions
                    WHERE id = v_id AND status IN ('invited', 'active'))
      INTO v_still_due;
    CONTINUE WHEN NOT v_still_due;

    UPDATE public.word_hunt_attempts
       SET status = 'timed_out',
           finished_at = GREATEST(v_now, started_at)
     WHERE session_id = v_id AND status = 'in_progress';

    UPDATE public.game_sessions
       SET status = 'abandoned',
           abandoned_at = v_now,
           abandon_reason = COALESCE(abandon_reason, 'inactivity'),
           current_turn_user_id = NULL
     WHERE id = v_id;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- The staleness rule, as a function so the sweep, the re-check under the
-- lock, and the per-RPC guard below cannot drift apart.
--
-- 48h for an invitation nobody accepted; 24h of no activity for a session
-- that was accepted. Measured from the last attempt start, so
-- "inactivity" means inactivity rather than session age.
CREATE OR REPLACE FUNCTION public.word_hunt_session_is_stale(p_session_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN s.status = 'invited'
      THEN s.created_at < now() - interval '48 hours'
    WHEN s.status = 'active'
      THEN COALESCE(
             (SELECT max(a.started_at) FROM public.word_hunt_attempts a
               WHERE a.session_id = s.id),
             s.started_at, s.created_at
           ) < now() - interval '24 hours'
    ELSE false
  END
  FROM public.game_sessions s
  WHERE s.id = p_session_id AND s.game_type = 'word_hunt';
$$;

-- The relationship trigger had the same inversion.
CREATE OR REPLACE FUNCTION public.abandon_word_hunt_on_relationship_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_now timestamptz;
BEGIN
  IF NEW.status = 'active' AND NEW.chat_archived_at IS NULL THEN
    RETURN NEW;
  END IF;

  FOR v_id IN
    SELECT id FROM public.game_sessions
    WHERE relationship_id = NEW.id
      AND game_type = 'word_hunt'
      AND status IN ('invited', 'active')
    ORDER BY id
  LOOP
    PERFORM 1 FROM public.game_sessions WHERE id = v_id FOR UPDATE;
    v_now := clock_timestamp();

    UPDATE public.word_hunt_attempts
       SET status = 'timed_out',
           finished_at = GREATEST(v_now, started_at)
     WHERE session_id = v_id AND status = 'in_progress';

    UPDATE public.game_sessions
       SET status = 'abandoned',
           abandon_reason = 'user_initiated',
           abandoned_at = v_now,
           current_turn_user_id = NULL
     WHERE id = v_id;
  END LOOP;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.word_hunt_session_is_stale(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.word_hunt_expire_sessions_for(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.abandon_word_hunt_on_relationship_change()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.word_hunt_decline_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.word_hunt_decline_session(uuid) TO authenticated;
