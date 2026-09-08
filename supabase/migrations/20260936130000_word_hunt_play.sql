-- Word Hunt: start, submit, give up, and the disclosure boundary.
--
-- The single rule that shapes every function here: NO PARTNER TIMING OR
-- OUTCOME IS DISCLOSED UNTIL BOTH ATTEMPTS ARE TERMINAL. Leaking each
-- time as that player finished -- which the spec's first draft did --
-- lets the second player start already knowing the number to beat, and a
-- number to beat is a different game from the one described.

-- ---------------------------------------------------------------------
-- The reveal payload, built in one place.
-- ---------------------------------------------------------------------
-- Called by every RPC that returns state, so the boundary is decided
-- once. Assumes the caller has already authorized v_user as a member.
CREATE OR REPLACE FUNCTION public.word_hunt_state_payload(
  p_session_id uuid,
  p_user uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
  v_puzzle public.word_hunt_puzzles%ROWTYPE;
  v_mine public.word_hunt_attempts%ROWTYPE;
  v_theirs public.word_hunt_attempts%ROWTYPE;
  v_partner uuid;
  v_session_over boolean;
  v_both_terminal boolean;
  v_out jsonb;
BEGIN
  SELECT * INTO v_session FROM public.game_sessions WHERE id = p_session_id;
  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;
  SELECT * INTO v_puzzle FROM public.word_hunt_puzzles
  WHERE session_id = p_session_id;

  v_partner := CASE WHEN v_rel.user_a = p_user THEN v_rel.user_b
                    ELSE v_rel.user_a END;

  SELECT * INTO v_mine FROM public.word_hunt_attempts
  WHERE session_id = p_session_id AND user_id = p_user;
  SELECT * INTO v_theirs FROM public.word_hunt_attempts
  WHERE session_id = p_session_id AND user_id = v_partner;

  v_session_over := v_session.status IN ('completed', 'abandoned');

  -- An absent partner has no attempt row and never will once the session
  -- is over -- that is "did not play", not "did not find it", and no
  -- synthetic row is invented to say so.
  v_both_terminal :=
    v_session_over
    OR (v_mine.user_id IS NOT NULL AND v_mine.status <> 'in_progress'
        AND v_theirs.user_id IS NOT NULL
        AND v_theirs.status <> 'in_progress');

  v_out := jsonb_build_object(
    'session_id', v_session.id,
    'relationship_id', v_session.relationship_id,
    'initiator_id', v_session.initiator_id,
    'status', v_session.status,
    'user_a', v_rel.user_a,
    'user_b', v_rel.user_b,
    'partner_id', v_partner,
    'created_at', v_session.created_at,
    'word_length', char_length(v_puzzle.word),
    -- The client seeds its display clock from the difference between
    -- these two, then advances it with a monotonic stopwatch. The device
    -- wall clock is never trusted, and the display estimate is always
    -- replaced by the stored server result at the end.
    'server_observed_at', clock_timestamp(),
    'both_terminal', v_both_terminal
  );

  -- §10: the grid and the word are withheld until the caller has started,
  -- so a player cannot study the puzzle off the clock.
  IF v_mine.user_id IS NOT NULL THEN
    v_out := v_out || jsonb_build_object(
      'grid', v_puzzle.grid,
      'word', v_puzzle.word,
      'my_status', v_mine.status,
      'my_started_at', v_mine.started_at,
      'my_finished_at', v_mine.finished_at,
      'my_elapsed_ms', v_mine.elapsed_ms,
      'my_deadline_at', v_mine.started_at + interval '10 minutes'
    );
  END IF;

  -- Partner timing: only once both are terminal. The key is absent
  -- entirely rather than null, so a client cannot distinguish "withheld"
  -- from "not yet" by looking at the shape of the response.
  IF v_both_terminal THEN
    IF v_theirs.user_id IS NOT NULL THEN
      v_out := v_out || jsonb_build_object(
        'partner_status', v_theirs.status,
        'partner_elapsed_ms', v_theirs.elapsed_ms
      );
    ELSE
      v_out := v_out || jsonb_build_object('partner_status', 'did_not_play');
    END IF;

    -- The placement is shown to BOTH players at the end, including
    -- whoever did not find it (§13.3): never learning where the word was
    -- is maddening rather than kind.
    v_out := v_out || jsonb_build_object('placement', v_puzzle.placement);
  END IF;

  RETURN v_out;
END;
$$;

-- ---------------------------------------------------------------------
-- Membership check, shared.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.word_hunt_authorize(
  p_session_id uuid,
  p_user uuid
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
BEGIN
  IF p_user IS NULL THEN
    RETURN 'UNAUTHORIZED';
  END IF;

  SELECT * INTO v_session FROM public.game_sessions
  WHERE id = p_session_id AND game_type = 'word_hunt';
  IF NOT FOUND THEN
    RETURN 'NOT_FOUND';
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;
  IF NOT FOUND OR (v_rel.user_a <> p_user AND v_rel.user_b <> p_user) THEN
    RETURN 'FORBIDDEN';
  END IF;

  RETURN 'OK';
END;
$$;

-- ---------------------------------------------------------------------
-- Start.
-- ---------------------------------------------------------------------
-- The clock and the puzzle commit in ONE transaction. Fetching the grid
-- before the clock has committed would let a client study the puzzle and
-- start the timer afterwards, which is the whole fairness model gone.
--
-- A transaction cannot guarantee the response reaches the device. If it
-- is lost the clock still runs, and the retry returns the original
-- timestamp and the same puzzle rather than a fresh start -- the honest
-- outcome, since the server genuinely did start.
CREATE OR REPLACE FUNCTION public.word_hunt_start(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_auth text;
  v_session public.game_sessions%ROWTYPE;
  v_now timestamptz;
BEGIN
  v_auth := public.word_hunt_authorize(p_session_id, v_user);
  IF v_auth <> 'OK' THEN
    RETURN public.word_hunt_error(v_auth);
  END IF;

  SELECT * INTO v_session FROM public.game_sessions
  WHERE id = p_session_id FOR UPDATE;

  -- Post-lock: now() is transaction-start time and could predate the
  -- wait for this lock.
  v_now := clock_timestamp();
  PERFORM public.word_hunt_expire_attempts(p_session_id, v_now);
  PERFORM public.word_hunt_maybe_complete(p_session_id);

  -- Idempotent: a concurrent double-tap, a retried request and a
  -- reopened app all resolve to the first started_at. If the existing
  -- attempt is already terminal this returns the stored state rather
  -- than reopening it.
  IF EXISTS (SELECT 1 FROM public.word_hunt_attempts
              WHERE session_id = p_session_id AND user_id = v_user) THEN
    RETURN public.word_hunt_state_payload(p_session_id, v_user);
  END IF;

  IF v_session.status = 'invited' THEN
    RETURN public.word_hunt_error('NOT_STARTED');
  END IF;
  IF v_session.status <> 'active' THEN
    RETURN public.word_hunt_error('SESSION_EXPIRED');
  END IF;

  INSERT INTO public.word_hunt_attempts (session_id, user_id, started_at)
  VALUES (p_session_id, v_user, v_now)
  ON CONFLICT (session_id, user_id) DO NOTHING;

  RETURN public.word_hunt_state_payload(p_session_id, v_user);
END;
$$;

-- ---------------------------------------------------------------------
-- Submit.
-- ---------------------------------------------------------------------
-- Validated as a DRAG, not a set of cells. A set comparison would accept
-- the right letters selected in a scattered order, which is not the game
-- and would also accept a solver that never drew a line.
CREATE OR REPLACE FUNCTION public.word_hunt_submit(
  p_session_id uuid,
  p_cells jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_auth text;
  v_now timestamptz;
  v_attempt public.word_hunt_attempts%ROWTYPE;
  v_puzzle public.word_hunt_puzzles%ROWTYPE;
  v_len int;
  v_n int;
  k int;
  r int; c int; pr int; pc int; dr int; dc int;
  v_forward boolean := true;
  v_reverse boolean := true;
  v_hit boolean;
  v_elapsed int;
BEGIN
  v_auth := public.word_hunt_authorize(p_session_id, v_user);
  IF v_auth <> 'OK' THEN
    RETURN public.word_hunt_error(v_auth);
  END IF;

  PERFORM 1 FROM public.game_sessions WHERE id = p_session_id FOR UPDATE;
  v_now := clock_timestamp();

  SELECT * INTO v_attempt FROM public.word_hunt_attempts
  WHERE session_id = p_session_id AND user_id = v_user
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.word_hunt_error('NOT_STARTED');
  END IF;

  -- IDEMPOTENCY FIRST, before expiry, rate limit and terminal rejection:
  -- a retry of a committed terminal action must return its stored result,
  -- not an error about the state that action itself produced.
  IF v_attempt.status <> 'in_progress' THEN
    RETURN public.word_hunt_state_payload(p_session_id, v_user)
      || jsonb_build_object('hit', v_attempt.status = 'found');
  END IF;

  IF public.word_hunt_is_expired(v_attempt.started_at, v_now) THEN
    PERFORM public.word_hunt_expire_attempts(p_session_id, v_now);
    PERFORM public.word_hunt_maybe_complete(p_session_id);
    RETURN public.word_hunt_state_payload(p_session_id, v_user)
      || jsonb_build_object('hit', false);
  END IF;

  -- Abuse protection, not an anti-cheat claim: a modified client can
  -- solve the grid locally without guessing at all (§5.2).
  IF v_attempt.last_submission_at IS NOT NULL
     AND v_now - v_attempt.last_submission_at < interval '300 milliseconds' THEN
    RETURN public.word_hunt_error('RATE_LIMITED');
  END IF;

  SELECT * INTO v_puzzle FROM public.word_hunt_puzzles
  WHERE session_id = p_session_id;
  IF NOT FOUND THEN
    RETURN public.word_hunt_error('NO_PUZZLE');
  END IF;
  v_len := char_length(v_puzzle.word);

  IF p_cells IS NULL OR jsonb_typeof(p_cells) <> 'array' THEN
    RETURN public.word_hunt_error('INVALID_INPUT');
  END IF;

  v_n := jsonb_array_length(p_cells);
  IF v_n <> v_len THEN
    RETURN public.word_hunt_error('INVALID_INPUT');
  END IF;

  -- Structure: exactly length(word) in-bounds cells, each one step from
  -- the last in a single fixed direction. Distinctness follows from a
  -- non-zero fixed step, so it needs no separate pass.
  FOR k IN 0..v_n - 1 LOOP
    IF jsonb_typeof(p_cells->k) <> 'array'
       OR jsonb_array_length(p_cells->k) <> 2
       OR jsonb_typeof(p_cells->k->0) <> 'number'
       OR jsonb_typeof(p_cells->k->1) <> 'number' THEN
      RETURN public.word_hunt_error('INVALID_INPUT');
    END IF;
    r := (p_cells->k->>0)::int;
    c := (p_cells->k->>1)::int;
    IF r < 0 OR r > 9 OR c < 0 OR c > 9 THEN
      RETURN public.word_hunt_error('INVALID_INPUT');
    END IF;

    IF k = 1 THEN
      dr := r - pr; dc := c - pc;
      IF (dr = 0 AND dc = 0) OR abs(dr) > 1 OR abs(dc) > 1 THEN
        RETURN public.word_hunt_error('INVALID_INPUT');
      END IF;
    ELSIF k > 1 AND (r - pr <> dr OR c - pc <> dc) THEN
      RETURN public.word_hunt_error('INVALID_INPUT');
    END IF;

    -- The word may be dragged from either end, so both readings are
    -- checked in the same pass.
    IF r <> (v_puzzle.placement->k->>0)::int
       OR c <> (v_puzzle.placement->k->>1)::int THEN
      v_forward := false;
    END IF;
    IF r <> (v_puzzle.placement->(v_n - 1 - k)->>0)::int
       OR c <> (v_puzzle.placement->(v_n - 1 - k)->>1)::int THEN
      v_reverse := false;
    END IF;

    pr := r; pc := c;
  END LOOP;

  v_hit := v_forward OR v_reverse;

  IF v_hit THEN
    v_elapsed := floor(
      extract(epoch FROM (v_now - v_attempt.started_at)) * 1000)::int;
    UPDATE public.word_hunt_attempts
       SET status = 'found',
           finished_at = v_now,
           elapsed_ms = GREATEST(LEAST(v_elapsed, 599999), 0),
           last_submission_at = v_now,
           submission_count = submission_count + 1
     WHERE session_id = p_session_id AND user_id = v_user;

    PERFORM public.word_hunt_maybe_complete(p_session_id);
  ELSE
    -- A wrong guess costs nothing and says nothing (§7.2). The counters
    -- move so the limiter has something to read; the player sees only
    -- the pill animate off.
    UPDATE public.word_hunt_attempts
       SET last_submission_at = v_now,
           submission_count = submission_count + 1
     WHERE session_id = p_session_id AND user_id = v_user;
  END IF;

  RETURN public.word_hunt_state_payload(p_session_id, v_user)
    || jsonb_build_object('hit', v_hit);
END;
$$;

-- ---------------------------------------------------------------------
-- Give up.
-- ---------------------------------------------------------------------
-- There is no cost to this: no score, no streak, no record. Staring at a
-- grid you cannot solve while your partner waits is the harm the button
-- prevents (§3.1).
CREATE OR REPLACE FUNCTION public.word_hunt_give_up(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_auth text;
  v_now timestamptz;
  v_attempt public.word_hunt_attempts%ROWTYPE;
BEGIN
  v_auth := public.word_hunt_authorize(p_session_id, v_user);
  IF v_auth <> 'OK' THEN
    RETURN public.word_hunt_error(v_auth);
  END IF;

  PERFORM 1 FROM public.game_sessions WHERE id = p_session_id FOR UPDATE;
  v_now := clock_timestamp();

  SELECT * INTO v_attempt FROM public.word_hunt_attempts
  WHERE session_id = p_session_id AND user_id = v_user
  FOR UPDATE;

  -- Giving up from the lobby must not silently start and finish a clock.
  IF NOT FOUND THEN
    RETURN public.word_hunt_error('NOT_STARTED');
  END IF;

  -- First terminal action prevails. A submit and a give-up racing each
  -- other are serialised by the session lock, and the loser of that race
  -- finds the attempt already terminal and returns its stored state --
  -- so giving up cannot rewrite a word you already found.
  IF v_attempt.status <> 'in_progress' THEN
    RETURN public.word_hunt_state_payload(p_session_id, v_user);
  END IF;

  IF public.word_hunt_is_expired(v_attempt.started_at, v_now) THEN
    PERFORM public.word_hunt_expire_attempts(p_session_id, v_now);
  ELSE
    UPDATE public.word_hunt_attempts
       SET status = 'gave_up', finished_at = v_now
     WHERE session_id = p_session_id AND user_id = v_user;
  END IF;

  PERFORM public.word_hunt_maybe_complete(p_session_id);

  RETURN public.word_hunt_state_payload(p_session_id, v_user);
END;
$$;

-- ---------------------------------------------------------------------
-- State.
-- ---------------------------------------------------------------------
-- Volatile rather than stable: it performs lazy expiry, which is a write.
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
  v_overdue boolean;
BEGIN
  v_auth := public.word_hunt_authorize(p_session_id, v_user);
  IF v_auth <> 'OK' THEN
    RETURN public.word_hunt_error(v_auth);
  END IF;

  -- A read locks only when it has expiry work to do, so opening a
  -- finished game does not queue behind another player's submission.
  SELECT EXISTS (
    SELECT 1 FROM public.word_hunt_attempts
    WHERE session_id = p_session_id
      AND status = 'in_progress'
      AND public.word_hunt_is_expired(started_at, clock_timestamp())
  ) INTO v_overdue;

  IF v_overdue THEN
    PERFORM 1 FROM public.game_sessions WHERE id = p_session_id FOR UPDATE;
    v_now := clock_timestamp();
    PERFORM public.word_hunt_expire_attempts(p_session_id, v_now);
    PERFORM public.word_hunt_maybe_complete(p_session_id);
  END IF;

  RETURN public.word_hunt_state_payload(p_session_id, v_user);
END;
$$;

-- ---------------------------------------------------------------------
-- Active session lookup, for the lobby.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_active_word_hunt_session(
  p_relationship_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session uuid;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.word_hunt_error('UNAUTHORIZED');
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

  PERFORM public.word_hunt_expire_sessions_for(p_relationship_id);

  SELECT id INTO v_session
    FROM public.game_sessions
   WHERE relationship_id = p_relationship_id
     AND game_type = 'word_hunt'
     AND status IN ('invited', 'active')
   ORDER BY created_at DESC
   LIMIT 1;

  IF v_session IS NULL THEN
    RETURN jsonb_build_object('session_id', NULL);
  END IF;

  RETURN public.get_word_hunt_state(v_session);
END;
$$;

REVOKE ALL ON FUNCTION public.word_hunt_state_payload(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.word_hunt_authorize(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.word_hunt_start(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.word_hunt_submit(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.word_hunt_give_up(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_word_hunt_state(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_active_word_hunt_session(uuid)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.word_hunt_start(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.word_hunt_submit(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.word_hunt_give_up(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_word_hunt_state(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_active_word_hunt_session(uuid)
  TO authenticated;
