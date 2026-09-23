-- admit_ai_session_generation: the full spec §6.2 admission sequence,
-- steps 1-5.
--
-- LOCK ORDER (spec §6.2: "relationship transaction advisory lock,
-- requester quota lock when needed, session row lock, request row"):
--
--   1. relationship advisory lock  (pg_advisory_xact_lock, here)
--   2. requester quota advisory lock (taken INSIDE
--      reserve_ai_assistant_quota, on hashtextextended(actor, 4451))
--   3. session row lock            (SELECT ... FOR UPDATE, here)
--   4. request row                 (the INSERT, here)
--
-- Both advisory locks are *xact* locks: once taken they are held to
-- COMMIT/ROLLBACK. reserve_ai_assistant_quota runs inside THIS
-- transaction, so its lock joins this transaction's lock set and the
-- ordering constraint is a whole-transaction one, not a per-statement
-- one. Taking the session row lock before calling the quota RPC --
-- which is what the naive reading of "recheck under the row lock
-- first" produces -- inverts steps 2 and 3 and is a genuine deadlock
-- cycle: T1 holds session S, waits for quota lock U; T2 holds quota
-- lock U, waits for session S. The relationship advisory lock narrows
-- but does not close that window (one user can hold quota lock U while
-- admitting in relationship R1 and contend for a session in R2), so
-- the order below is honored literally.
--
-- Consequently the eligibility checks appear TWICE:
--
--   * Before the quota call, as unlocked PRE-checks. These are correct
--     to read unlocked because the relationship advisory lock is
--     already held, and every mutator of this session (End, source
--     edit, membership change, activation) takes that same
--     relationship lock first per the Global Constraints -- so no
--     conforming writer can change the row between here and the
--     FOR UPDATE below. Their purpose is to avoid consuming a global
--     quota reservation for a request that is already doomed: a
--     reservation is user-visible (it counts against the 20/24h cap)
--     and can only be given back by a separate
--     release_ai_assistant_quota_reservation call, so spending one on
--     a stale-revision or already-busy request would be a real
--     quota leak.
--
--   * After the FOR UPDATE, as the authoritative RE-checks. These are
--     the ones that actually enforce §6.2 step 1/step 3. The row lock,
--     not the relationship lock, is the guarantee the attempt_count
--     read feeding attempt_n is the value being written back, and it
--     is the fence against any non-conforming or future writer. The
--     pre-checks are an optimization; the post-lock checks are the
--     contract.
--
-- A rejection discovered only under the row lock (i.e. after quota was
-- reserved) RAISEs rather than RETURNing, so the whole transaction --
-- including the quota reservation -- rolls back. That is the only way
-- to avoid leaking a reservation for a request that never became an
-- attempt, given the reservation lives in this same transaction. For
-- 'busy'/'limit_reached' the pre-check returns them as normal outcomes
-- in the conforming case, but the post-lock RAISE is reachable: a
-- writer that takes the session row lock without first taking the
-- relationship advisory lock -- the non-conforming writer this fence
-- exists to guard against -- can still land here. Failing with an
-- exception (and rolling back the reservation) rather than returning a
-- declared outcome row is the deliberate fail-closed behavior for that
-- case.
CREATE OR REPLACE FUNCTION public.admit_ai_session_generation(
  p_actor_id uuid,
  p_request_id uuid,
  p_session_id uuid,
  p_expected_revision int,
  p_operation_fingerprint text
) RETURNS TABLE (
  outcome text, request_id uuid, attempt_n int,
  worker_token uuid, lease_deadline timestamptz, retry_after_seconds int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
  v_existing public.ai_session_requests;
  v_relationship_id uuid;
  v_quota record;
  v_next_attempt smallint;
  v_worker_token uuid;
  v_deadline timestamptz;
  v_expires_at timestamptz;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Step 2 (idempotency), checked BEFORE the relationship lock so that
  -- a replay of an already-settled request never contends for the lock
  -- at all. This is a FAST PATH only -- it is repeated under the
  -- relationship lock below, because an unlocked read here can miss a
  -- row that a concurrent admission for this same request_id is about
  -- to commit. Returning 'busy' to a caller replaying its OWN
  -- request_id would violate §6.2 step 2 ("For an existing actor/
  -- request ID, return its state/result ... never a new provider
  -- lease"), so idempotency must be settled before the busy check, on
  -- both sides of the lock.
  SELECT * INTO v_existing FROM public.ai_session_requests WHERE id = p_request_id;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.session_id IS DISTINCT FROM p_session_id
       OR v_existing.actor_id IS DISTINCT FROM p_actor_id
       OR v_existing.operation_fingerprint IS DISTINCT FROM p_operation_fingerprint THEN
      RETURN QUERY SELECT 'conflict'::text, NULL::uuid, NULL::int, NULL::uuid, NULL::timestamptz, NULL::int;
      RETURN;
    END IF;
    RETURN QUERY SELECT 'already_admitted'::text, v_existing.id, v_existing.attempt_n::int,
      v_existing.worker_token, v_existing.lease_deadline, NULL::int;
    RETURN;
  END IF;

  -- Resolve the relationship without any lock, purely to know WHICH
  -- relationship lock to take. A bogus session id fails here before
  -- any lock is taken at all.
  SELECT s.relationship_id INTO v_relationship_id
  FROM public.ai_sessions s WHERE s.id = p_session_id;
  IF v_relationship_id IS NULL THEN
    RAISE EXCEPTION 'UNAVAILABLE';
  END IF;

  -- LOCK 1: the relationship advisory lock.
  PERFORM pg_advisory_xact_lock(hashtext(v_relationship_id::text));

  -- Step 2 again, now under the relationship lock. Every concurrent
  -- admission for this session serializes on that lock, so any request
  -- row a racing caller committed is visible here. Without this
  -- re-check, N concurrent calls sharing one request_id all miss the
  -- row in the unlocked fast path above, and the losers fall through
  -- to the busy check and are told 'busy' about their own admitted
  -- request. Proven by
  -- supabase/tests/ai_session_admit_same_request_concurrent_test.sh,
  -- which fails with 'busy' answers if this block is removed.
  SELECT * INTO v_existing FROM public.ai_session_requests WHERE id = p_request_id;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.session_id IS DISTINCT FROM p_session_id
       OR v_existing.actor_id IS DISTINCT FROM p_actor_id
       OR v_existing.operation_fingerprint IS DISTINCT FROM p_operation_fingerprint THEN
      RETURN QUERY SELECT 'conflict'::text, NULL::uuid, NULL::int, NULL::uuid, NULL::timestamptz, NULL::int;
      RETURN;
    END IF;
    RETURN QUERY SELECT 'already_admitted'::text, v_existing.id, v_existing.attempt_n::int,
      v_existing.worker_token, v_existing.lease_deadline, NULL::int;
    RETURN;
  END IF;

  -- PRE-checks (see the header): everything §6.2 steps 1 and 3 ask
  -- for, read unlocked under the relationship lock, so that a doomed
  -- request never consumes a quota reservation. Re-read after the lock
  -- so these see the post-lock truth, not a pre-lock snapshot.
  SELECT * INTO v_session FROM public.ai_sessions WHERE id = p_session_id;
  IF v_session.id IS NULL OR v_session.state != 'active' THEN
    RAISE EXCEPTION 'UNAVAILABLE';
  END IF;
  IF v_session.revision != p_expected_revision THEN
    RAISE EXCEPTION 'CONTEXT_CHANGED';
  END IF;
  IF v_session.expires_at IS NOT NULL AND v_session.expires_at <= now() THEN
    RAISE EXCEPTION 'UNAVAILABLE';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.ai_session_requests
    WHERE session_id = p_session_id AND state IN ('reserved', 'started')
  ) THEN
    RETURN QUERY SELECT 'busy'::text, NULL::uuid, NULL::int, NULL::uuid, NULL::timestamptz, NULL::int;
    RETURN;
  END IF;
  IF v_session.attempt_count >= 10 THEN
    RETURN QUERY SELECT 'limit_reached'::text, NULL::uuid, NULL::int, NULL::uuid, NULL::timestamptz, NULL::int;
    RETURN;
  END IF;

  -- LOCK 2 (inside the callee): Step 4's global quota reservation,
  -- mode='session' (Plan A Task 1). Must precede the session row lock.
  SELECT * INTO v_quota FROM public.reserve_ai_assistant_quota(
    p_actor_id, p_request_id, v_relationship_id, 'session'
  );
  IF v_quota.outcome = 'rate_limited' THEN
    RETURN QUERY SELECT 'rate_limited'::text, NULL::uuid, NULL::int, NULL::uuid, NULL::timestamptz, v_quota.retry_after_seconds;
    RETURN;
  END IF;
  IF v_quota.outcome != 'reserved' THEN
    RAISE EXCEPTION 'Unexpected quota outcome: %', v_quota.outcome;
  END IF;

  -- LOCK 3: the session row lock. Step 1's authoritative re-check, and
  -- the fence that makes the attempt_count read below safe to
  -- increment.
  SELECT * INTO v_session FROM public.ai_sessions WHERE id = p_session_id FOR UPDATE;
  IF v_session.id IS NULL OR v_session.state != 'active' THEN
    RAISE EXCEPTION 'UNAVAILABLE';
  END IF;
  IF v_session.revision != p_expected_revision THEN
    RAISE EXCEPTION 'CONTEXT_CHANGED';
  END IF;
  IF v_session.expires_at IS NOT NULL AND v_session.expires_at <= now() THEN
    RAISE EXCEPTION 'UNAVAILABLE';
  END IF;

  -- Step 3 re-checked under the row lock.
  IF EXISTS (
    SELECT 1 FROM public.ai_session_requests
    WHERE session_id = p_session_id AND state IN ('reserved', 'started')
  ) THEN
    RAISE EXCEPTION 'BUSY';
  END IF;
  IF v_session.attempt_count >= 10 THEN
    RAISE EXCEPTION 'LIMIT_REACHED';
  END IF;

  v_next_attempt := v_session.attempt_count + 1;
  v_worker_token := gen_random_uuid();
  v_deadline := now() + interval '35 seconds';

  -- Task 1's own column comment: expires_at = min(last_admitted_at +
  -- 15min, activated_at + 60min) once active. last_admitted_at is
  -- being set to now() in this same statement, so the first term is
  -- now() + 15min; activated_at is read from the row already locked
  -- above and is never NULL for an active session (ai_sessions' CHECK
  -- constraint guarantees it).
  v_expires_at := LEAST(
    now() + interval '15 minutes',
    v_session.activated_at + interval '60 minutes'
  );

  UPDATE public.ai_sessions
  SET attempt_count = v_next_attempt,
      last_admitted_at = now(),
      expires_at = v_expires_at
  WHERE id = p_session_id;

  -- LOCK 4 / Step 5: create the request row.
  INSERT INTO public.ai_session_requests (
    id, session_id, actor_id, attempt_n, operation_fingerprint,
    worker_token, generation_epoch, lease_deadline, state
  ) VALUES (
    p_request_id, p_session_id, p_actor_id, v_next_attempt, p_operation_fingerprint,
    v_worker_token, v_session.generation_epoch, v_deadline, 'reserved'
  );

  RETURN QUERY SELECT 'admitted'::text, p_request_id, v_next_attempt::int, v_worker_token, v_deadline, NULL::int;
END;
$$;
REVOKE ALL ON FUNCTION public.admit_ai_session_generation(uuid, uuid, uuid, int, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admit_ai_session_generation(uuid, uuid, uuid, int, text)
  TO service_role;
