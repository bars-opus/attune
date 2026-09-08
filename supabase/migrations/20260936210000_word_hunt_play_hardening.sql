-- Word Hunt review fixes, part three: the play path.
--
-- Finding 4 (session deadline enforced at every entry point) and
-- finding 7 (coordinates validated as integers before casting).

-- ---------------------------------------------------------------------
-- FINDING 7: a decimal or oversized coordinate escaped the error contract.
-- ---------------------------------------------------------------------
-- Submit accepted any JSON `number` and cast its text straight to int, so
--   [[0.5,0],...]                  -> invalid input syntax for type integer
--   [[99999999999999999999,0],...] -> value out of range for type integer
-- reached the client as a raw SQL exception rather than INVALID_INPUT.
-- Not a security hole -- nothing is bypassed -- but it breaks the
-- checklist-2.4 promise that errors never leak internals, and it is the
-- one input path where a hostile client picks the shape.
--
-- A jsonb number is a numeric, so this checks it IS an integer and is in
-- range before any cast happens.
CREATE OR REPLACE FUNCTION public.word_hunt_cell_ordinate(p_value jsonb)
RETURNS int
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v numeric;
BEGIN
  IF p_value IS NULL OR jsonb_typeof(p_value) <> 'number' THEN
    RETURN NULL;
  END IF;
  v := p_value::text::numeric;
  -- Not an integer, or outside the board by any margin. Returning NULL
  -- rather than raising lets the caller answer INVALID_INPUT.
  IF v <> trunc(v) OR v < -1000 OR v > 1000 THEN
    RETURN NULL;
  END IF;
  RETURN v::int;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;

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

  -- FINDING 4: the SESSION deadline, not only the attempt's.
  IF public.word_hunt_expire_session_if_stale(p_session_id) THEN
    RETURN public.word_hunt_state_payload(p_session_id, v_user)
      || jsonb_build_object('hit', false);
  END IF;

  IF public.word_hunt_is_expired(v_attempt.started_at, v_now) THEN
    PERFORM public.word_hunt_expire_attempts(p_session_id, v_now);
    PERFORM public.word_hunt_maybe_complete(p_session_id, v_now);
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
       OR jsonb_array_length(p_cells->k) <> 2 THEN
      RETURN public.word_hunt_error('INVALID_INPUT');
    END IF;

    -- FINDING 7: validated as an integer BEFORE any cast, so a decimal
    -- or an out-of-range value is INVALID_INPUT rather than a raw SQL
    -- exception carrying a Postgres type name to the client.
    r := public.word_hunt_cell_ordinate(p_cells->k->0);
    c := public.word_hunt_cell_ordinate(p_cells->k->1);
    IF r IS NULL OR c IS NULL THEN
      RETURN public.word_hunt_error('INVALID_INPUT');
    END IF;
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

    PERFORM public.word_hunt_maybe_complete(p_session_id, v_now);
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

  v_now := clock_timestamp();
  PERFORM public.word_hunt_expire_attempts(p_session_id, v_now);
  PERFORM public.word_hunt_maybe_complete(p_session_id, v_now);

  -- Idempotent: a concurrent double-tap, a retried request and a
  -- reopened app all resolve to the first started_at. Checked BEFORE the
  -- session-expiry guard so a finished game still returns its result on
  -- the reveal screen rather than SESSION_EXPIRED.
  IF EXISTS (SELECT 1 FROM public.word_hunt_attempts
              WHERE session_id = p_session_id AND user_id = v_user) THEN
    RETURN public.word_hunt_state_payload(p_session_id, v_user);
  END IF;

  -- FINDING 4: an expired session cannot be started, even reached
  -- directly from a notification without passing the lobby.
  IF public.word_hunt_expire_session_if_stale(p_session_id) THEN
    RETURN public.word_hunt_error('SESSION_EXPIRED');
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

  -- First terminal action prevails, so giving up cannot rewrite a word
  -- already found.
  IF v_attempt.status <> 'in_progress' THEN
    RETURN public.word_hunt_state_payload(p_session_id, v_user);
  END IF;

  IF public.word_hunt_expire_session_if_stale(p_session_id) THEN
    RETURN public.word_hunt_state_payload(p_session_id, v_user);
  END IF;

  IF public.word_hunt_is_expired(v_attempt.started_at, v_now) THEN
    PERFORM public.word_hunt_expire_attempts(p_session_id, v_now);
  ELSE
    UPDATE public.word_hunt_attempts
       SET status = 'gave_up', finished_at = v_now
     WHERE session_id = p_session_id AND user_id = v_user;
  END IF;

  PERFORM public.word_hunt_maybe_complete(p_session_id, v_now);

  RETURN public.word_hunt_state_payload(p_session_id, v_user);
END;
$$;

REVOKE ALL ON FUNCTION public.word_hunt_cell_ordinate(jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.word_hunt_start(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.word_hunt_submit(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.word_hunt_give_up(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.word_hunt_start(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.word_hunt_submit(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.word_hunt_give_up(uuid) TO authenticated;
