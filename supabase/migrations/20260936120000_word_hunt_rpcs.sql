-- Word Hunt: the server contract (§10).
--
-- Two things distinguish this from Snakes, and both drive the shape of
-- every function below.
--
-- SIMULTANEOUS, NOT ALTERNATING. There is no turn owner. Both players
-- hold their own attempt on the same puzzle, and near-simultaneous
-- finishes are ordinary rather than an edge case -- so every mutating
-- RPC takes the SESSION row FOR UPDATE before touching an attempt.
-- Without it two transactions could each read the other as unfinished
-- and neither would close the session. Lock order is always session,
-- then attempt, so nothing here can deadlock against anything else here.
--
-- THE CLOCK BELONGS TO THE SERVER. The client never sends a duration;
-- this game is nothing but a number, and a client-supplied number would
-- be the whole game handed to the client. Note that now() is fixed at
-- transaction start and could predate time spent waiting for the session
-- lock, so resolution uses clock_timestamp() captured AFTER the lock.

CREATE OR REPLACE FUNCTION public.word_hunt_error(p_code text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'error', true,
    'code', p_code,
    'message', CASE p_code
      WHEN 'UNAUTHORIZED'    THEN 'Please sign in to play games.'
      WHEN 'FORBIDDEN'       THEN 'You don''t have access to this game.'
      WHEN 'NOT_FOUND'       THEN 'Game session not found.'
      WHEN 'NOT_STARTED'     THEN 'Start the hunt first.'
      WHEN 'GAME_OVER'       THEN 'This game has already finished.'
      WHEN 'SESSION_EXPIRED' THEN 'This session expired. Start a new game.'
      WHEN 'RATE_LIMITED'    THEN 'Slow down a moment.'
      WHEN 'INVALID_INPUT'   THEN 'Invalid value provided.'
      WHEN 'NO_PUZZLE'       THEN 'This game could not be set up. Try again.'
      ELSE 'Something went wrong. Please try again.'
    END
  );
$$;

-- ---------------------------------------------------------------------
-- The attempt deadline, as a pure function.
-- ---------------------------------------------------------------------
-- Pure and IMMUTABLE so the boundary can be tested exactly -- the
-- millisecond before ten minutes finishes, the deadline itself times out
-- -- without any test depending on a sleep.
CREATE OR REPLACE FUNCTION public.word_hunt_is_expired(
  p_started_at timestamptz,
  p_now timestamptz
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_now >= p_started_at + interval '10 minutes';
$$;

-- ---------------------------------------------------------------------
-- Lazy expiry of one attempt.
-- ---------------------------------------------------------------------
-- Cron is the backstop; a player opening the game after eleven minutes
-- should see the finished state immediately rather than whenever the job
-- next runs. Callers must already hold the session lock.
CREATE OR REPLACE FUNCTION public.word_hunt_expire_attempts(
  p_session_id uuid,
  p_now timestamptz
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.word_hunt_attempts a
     SET status = 'timed_out',
         finished_at = p_now
   WHERE a.session_id = p_session_id
     AND a.status = 'in_progress'
     AND public.word_hunt_is_expired(a.started_at, p_now);
$$;

-- ---------------------------------------------------------------------
-- Close the session once both attempts are terminal.
-- ---------------------------------------------------------------------
-- Shared by Submit, Give Up and expiry rather than reimplemented three
-- ways. Caller holds the session lock. Returns whether the session is
-- now complete.
--
-- Deliberately NO winner_user_id: §5.3. Two times side by side, never a
-- contest -- a modified client can solve a 10x10 grid locally, and
-- nobody was present for the other person's attempt.
CREATE OR REPLACE FUNCTION public.word_hunt_maybe_complete(p_session_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_terminal int;
BEGIN
  SELECT count(*) INTO v_terminal
  FROM public.word_hunt_attempts
  WHERE session_id = p_session_id AND status <> 'in_progress';

  IF v_terminal >= 2 THEN
    UPDATE public.game_sessions
       SET status = 'completed',
           completed_at = COALESCE(completed_at, now())
     WHERE id = p_session_id AND status <> 'completed';
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

-- ---------------------------------------------------------------------
-- Session expiry for one relationship (lazy) and globally (cron).
-- ---------------------------------------------------------------------
-- An unaccepted invite dies at 48h; an accepted session with nobody
-- finishing dies at 24h. Both are terminal for disclosure: any
-- in-progress attempt becomes timed_out, and the placement may then be
-- revealed because nobody can start that expired puzzle any more.
CREATE OR REPLACE FUNCTION public.word_hunt_expire_sessions_for(
  p_relationship_id uuid
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ids uuid[];
BEGIN
  SELECT COALESCE(array_agg(s.id), ARRAY[]::uuid[]) INTO v_ids
  FROM public.game_sessions s
  WHERE s.game_type = 'word_hunt'
    AND s.status IN ('invited', 'active')
    AND (p_relationship_id IS NULL OR s.relationship_id = p_relationship_id)
    AND (
      (s.status = 'invited' AND s.created_at < now() - interval '48 hours')
      OR (
        s.status = 'active'
        AND COALESCE(
              (SELECT max(a.started_at) FROM public.word_hunt_attempts a
                WHERE a.session_id = s.id),
              s.started_at, s.created_at
            ) < now() - interval '24 hours'
      )
    );

  IF cardinality(v_ids) = 0 THEN
    RETURN 0;
  END IF;

  UPDATE public.word_hunt_attempts
     SET status = 'timed_out',
         -- now() is transaction-start time and word_hunt_start writes
         -- started_at from clock_timestamp() after taking the session
         -- lock, so in one transaction now() can precede it and the
         -- finish_after_start CHECK would reject this whole statement.
         finished_at = GREATEST(clock_timestamp(), started_at)
   WHERE session_id = ANY(v_ids) AND status = 'in_progress';

  UPDATE public.game_sessions
     SET status = 'abandoned',
         abandoned_at = now(),
         abandon_reason = COALESCE(abandon_reason, 'inactivity'),
         current_turn_user_id = NULL
   WHERE id = ANY(v_ids);

  RETURN cardinality(v_ids);
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_word_hunt_sessions()
RETURNS int
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.word_hunt_expire_sessions_for(NULL);
$$;

-- Ending or archiving a relationship ends its live games immediately.
CREATE OR REPLACE FUNCTION public.abandon_word_hunt_on_relationship_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'active' AND NEW.chat_archived_at IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.word_hunt_attempts a
     SET status = 'timed_out',
         -- now() is transaction-start time and word_hunt_start writes
         -- started_at from clock_timestamp() after taking the session
         -- lock, so in one transaction now() can precede it and the
         -- finish_after_start CHECK would reject this whole statement.
         -- Qualified: game_sessions has a started_at too, and the bare
         -- name here is ambiguous.
         finished_at = GREATEST(clock_timestamp(), a.started_at)
    FROM public.game_sessions s
   WHERE s.id = a.session_id
     AND s.relationship_id = NEW.id
     AND s.game_type = 'word_hunt'
     AND s.status IN ('invited', 'active')
     AND a.status = 'in_progress';

  UPDATE public.game_sessions
     SET status = 'abandoned',
         abandon_reason = 'user_initiated',
         abandoned_at = now(),
         current_turn_user_id = NULL
   WHERE relationship_id = NEW.id
     AND game_type = 'word_hunt'
     AND status IN ('invited', 'active');

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS abandon_word_hunt_on_relationship_change
  ON public.relationships;
CREATE TRIGGER abandon_word_hunt_on_relationship_change
AFTER UPDATE OF status, chat_archived_at ON public.relationships
FOR EACH ROW EXECUTE FUNCTION public.abandon_word_hunt_on_relationship_change();

-- ---------------------------------------------------------------------
-- Create.
-- ---------------------------------------------------------------------
-- Generation happens inside this transaction. A failure rolls the whole
-- thing back, so there is never an invitation without a puzzle behind it.
CREATE OR REPLACE FUNCTION public.word_hunt_create_session(
  p_relationship_id uuid,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session uuid;
  v_key_relationship uuid;
  v_key_game_type text;
  v_recent int;
  v_version text;
  v_words text[];
  v_weights jsonb;
  v_word text;
  v_puzzle jsonb;
  v_recent_words text[];
  v_pool text[];
BEGIN
  IF v_user IS NULL THEN
    RETURN public.word_hunt_error('UNAUTHORIZED');
  END IF;

  IF p_relationship_id IS NULL
     OR p_idempotency_key IS NULL OR btrim(p_idempotency_key) = ''
     OR char_length(p_idempotency_key) > 200 THEN
    RETURN public.word_hunt_error('INVALID_INPUT');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.relationships
    WHERE id = p_relationship_id
      AND status = 'active'
      AND chat_archived_at IS NULL
      AND (user_a = v_user OR user_b = v_user)
  ) THEN
    RETURN public.word_hunt_error('FORBIDDEN');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_relationship_id::text));

  SELECT k.session_id, s.relationship_id, s.game_type
    INTO v_session, v_key_relationship, v_key_game_type
  FROM public.session_idempotency_keys k
  JOIN public.game_sessions s ON s.id = k.session_id
  WHERE k.key = p_idempotency_key;

  IF v_session IS NOT NULL THEN
    IF v_key_relationship <> p_relationship_id THEN
      RETURN public.word_hunt_error('FORBIDDEN');
    END IF;
    IF v_key_game_type <> 'word_hunt' THEN
      RETURN public.word_hunt_error('INVALID_INPUT');
    END IF;
    RETURN jsonb_build_object('session_id', v_session, 'existing', true);
  END IF;

  PERFORM public.word_hunt_expire_sessions_for(p_relationship_id);

  -- One live Word Hunt per couple, matching the Snakes lobby model.
  SELECT id INTO v_session
  FROM public.game_sessions
  WHERE relationship_id = p_relationship_id
    AND game_type = 'word_hunt'
    AND status IN ('invited', 'active')
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_session IS NOT NULL THEN
    RETURN jsonb_build_object('session_id', v_session, 'existing', true);
  END IF;

  -- Shared initiation limiter, counting all games so a couple cannot
  -- spam invitations by rotating between them.
  SELECT count(*) INTO v_recent
  FROM public.game_sessions
  WHERE relationship_id = p_relationship_id
    AND created_at > now() - interval '1 hour';

  IF v_recent >= 5 THEN
    RETURN public.word_hunt_error('RATE_LIMITED');
  END IF;

  SELECT version, words, direction_weights
    INTO v_version, v_words, v_weights
  FROM public.word_hunt_configs
  WHERE retired_at IS NULL
  ORDER BY created_at DESC, version DESC
  LIMIT 1;

  IF v_version IS NULL THEN
    RETURN public.word_hunt_error('NO_PUZZLE');
  END IF;

  -- §6: no word repeats within a couple's recent sessions. Only the last
  -- ten matter -- a couple who play the whole list should not run out of
  -- game, they should just stop seeing the same word twice in a row.
  SELECT COALESCE(array_agg(recent.word), ARRAY[]::text[])
    INTO v_recent_words
  FROM (
    SELECT p.word
    FROM public.word_hunt_puzzles p
    JOIN public.game_sessions s ON s.id = p.session_id
    WHERE s.relationship_id = p_relationship_id
    ORDER BY p.created_at DESC
    LIMIT 10
  ) recent;

  -- The rule itself lives in a pure function so it can be tested without
  -- going through a random draw -- see 20260936170000 for why that
  -- matters. Fallback to the full list is part of it.
  v_pool := public.word_hunt_pool(v_words, v_recent_words);

  v_word := v_pool[1 + floor(random() * cardinality(v_pool))::int];

  INSERT INTO public.game_sessions (
    relationship_id, initiator_id, game_type, status,
    current_round, total_rounds, total_rounds_completed
  )
  VALUES (
    p_relationship_id, v_user, 'word_hunt', 'invited', 1, 1, 0
  )
  RETURNING id INTO v_session;

  -- Raises, and rolls back the session with it, rather than leaving an
  -- invitation nobody can play.
  v_puzzle := public.word_hunt_generate(v_word, v_weights);

  INSERT INTO public.word_hunt_puzzles (
    session_id, word, grid, placement, word_list_version
  )
  VALUES (
    v_session, v_word, v_puzzle->'grid', v_puzzle->'placement', v_version
  );

  INSERT INTO public.session_idempotency_keys (key, session_id)
  VALUES (p_idempotency_key, v_session);

  RETURN jsonb_build_object('session_id', v_session, 'existing', false);
END;
$$;

-- ---------------------------------------------------------------------
-- Accept and decline.
-- ---------------------------------------------------------------------
-- Accepting activates the session but starts NOBODY's clock. Word Hunt
-- never assigns current_turn_user_id: there is no turn.
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

  IF v_session.status IN ('abandoned', 'completed') THEN
    RETURN jsonb_build_object('ok', true, 'existing', true);
  END IF;

  UPDATE public.word_hunt_attempts
     SET status = 'timed_out',
         -- now() is transaction-start time and word_hunt_start writes
         -- started_at from clock_timestamp() after taking the session
         -- lock, so in one transaction now() can precede it and the
         -- finish_after_start CHECK would reject this whole statement.
         finished_at = GREATEST(clock_timestamp(), started_at)
   WHERE session_id = p_session_id AND status = 'in_progress';

  UPDATE public.game_sessions
     SET status = 'abandoned', abandoned_at = now(),
         abandon_reason = COALESCE(abandon_reason, 'user_initiated'),
         current_turn_user_id = NULL
   WHERE id = p_session_id;

  RETURN jsonb_build_object('ok', true, 'existing', false);
END;
$$;

REVOKE ALL ON FUNCTION public.word_hunt_error(text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.word_hunt_is_expired(timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.word_hunt_expire_attempts(uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.word_hunt_maybe_complete(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.word_hunt_expire_sessions_for(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.expire_word_hunt_sessions()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.abandon_word_hunt_on_relationship_change()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.word_hunt_create_session(uuid, text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.word_hunt_accept_session(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.word_hunt_decline_session(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.expire_word_hunt_sessions() TO service_role;
GRANT EXECUTE ON FUNCTION public.word_hunt_create_session(uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.word_hunt_accept_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.word_hunt_decline_session(uuid) TO authenticated;
