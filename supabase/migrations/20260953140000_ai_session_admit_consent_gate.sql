-- Task 3 of the merge-blockers plan: the membership + AI-processing
-- consent gate on the DISPATCH path. Spec §7.2.
--
-- ======================================================================
-- THIS MIGRATION SUPERSEDES ONE EARLIER MIGRATION.
--
-- It re-defines, by CREATE OR REPLACE:
--
--   * public.admit_ai_session_generation
--       -- originally AND ONLY 20260953050000 (Plan B Task 5).
--
-- That is established by grep rather than assumed: 20260953050000 holds
-- the sole `CREATE OR REPLACE FUNCTION
-- public.admit_ai_session_generation` in the whole migration set. The
-- five other migrations that name the function
-- (20260953030000, 20260953060100, 20260953090000, 20260953090100,
-- 20260953120000 -- Task 1's lock-order fix) mention it only in
-- COMMENTS, as the reference implementation of the documented lock
-- order. None re-defines it. So the pre-this-file winning definition is
-- 20260953050000's, and this file now wins over it.
--
-- Per this plan's additive-migrations discipline (established by
-- 20260953060100 and followed by 20260953090100, 20260953100100,
-- 20260953110000 and 20260953120000), no earlier migration's logic is
-- edited in place. Later migrations win; the earlier files are kept as
-- the historical record of what shipped when.
--
-- Nothing in Task 1's 20260953120000 is touched here. That file owns
-- commit_ai_session_ideas_turn, stage_ai_session_nearby_result and
-- publish_ai_session_nearby_result; this file owns
-- admit_ai_session_generation and nothing else. The two sets are
-- disjoint.
-- ======================================================================
--
-- THE DEFECT THIS CLOSES (Critical).
--
-- Of the 18 functions in Plan B, three checked AI-processing consent:
-- read_ai_session_turns and read_ai_session_staging (Task 10 +
-- 20260953100100), and publish_ai_session_nearby_result (Task 11's
-- routed item 1, 20260953110000). The entire DISPATCH path was ungated.
--
-- Reproduced live on a clean database, twice -- once with ZERO consent
-- events on the relationship, once with granted-then-withdrawn:
--
--   prepare_ai_session       -> session created
--   approve_ai_session_context -> approved
--   activate_ai_session      -> active
--   admit_ai_session_generation -> outcome 'admitted'
--   claim_ai_session_dispatch   -> true
--   commit_ai_session_ideas_turn -> committed, ordinals 1/2
--   ai_session_turns          -> 2 rows written
--
-- with `SELECT count(*) FROM ai_processing_consent_events WHERE
-- relationship_id = <rel>` returning 0 throughout.
--
-- WHY `claim` IS THE STEP THAT MATTERS, not the transcript write.
-- claim_ai_session_dispatch's only purpose is to set the write-once
-- provider-start marker immediately before the edge function calls
-- Gemini (see 20260952010000 and 20260953060100). A successful claim IS
-- the backend's authorization to make that provider HTTP call. So the
-- real exposure is not merely that a transcript gets written for a
-- non-consenting couple -- it is that the couple's APPROVED CHAT
-- CLIPPINGS ARE TRANSMITTED TO A THIRD-PARTY AI PROVIDER AFTER CONSENT
-- WAS WITHDRAWN. That is the materially worse half, and no gate in the
-- plan touched it.
--
-- ONE RPC IS SUFFICIENT, AND THAT WAS VERIFIED RATHER THAN ASSUMED.
--
--   1. admit resolves v_relationship_id from the bare session id BEFORE
--      it takes any lock -- the `SELECT s.relationship_id ... FROM
--      ai_sessions s WHERE s.id = p_session_id` immediately followed by
--      `PERFORM pg_advisory_xact_lock(hashtext(v_relationship_id::
--      text))`. So the relationship is already known at the point this
--      gate fires, and NO LOCK IS HELD YET. The gate therefore adds no
--      lock, takes no lock, and cannot change the lock order. See
--      "LOCK ORDER IS UNCHANGED" below.
--
--   2. claim_ai_session_dispatch's own UPDATE ... WHERE clause is
--      `id = p_request_id AND worker_token = p_worker_token AND
--      state = 'reserved' AND lease_deadline > now()`. The ONLY code in
--      the schema that inserts an ai_session_requests row with
--      state = 'reserved' and a worker_token is admit's final INSERT
--      (verified by catalog grep across every function body: no other
--      function writes state='reserved' with a worker_token). A request
--      admit refused does not exist, so claim's UPDATE matches zero
--      rows and returns false -- which means NO PROVIDER CALL IS
--      AUTHORIZED. And commit_ai_session_ideas_turn /
--      stage_ai_session_nearby_result / publish_ai_session_nearby_result
--      all key off that same request row, so they are unreachable too.
--      The gate is therefore INHERITED TRANSITIVELY by the whole
--      dispatch path from one choke point.
--
-- This is the single-choke-point architecture the predecessor plan's
-- Ruling 9 declined to choose unilaterally: gate admission, not seven
-- RPCs.
--
-- ---------------------------------------------------------------------
-- WHY NOT CALL get_ai_processing_consent_status.
--
-- Plan A's canonical reader derives its actor from auth.uid() and
-- RAISEs 'Not authenticated' when it is NULL (20260950040000). Every
-- caller of admit_ai_session_generation is Plan C's edge function on a
-- service_role connection, which carries no JWT, so auth.uid() is NULL
-- and that call would make EVERY admission throw -- turning a Critical
-- consent hole into a Critical total outage. This was verified during
-- the predecessor plan's Task 10 and is why the read RPCs inline the
-- predicate instead. Same reason applies verbatim here.
--
-- ---------------------------------------------------------------------
-- THE PREDICATE IS LIFTED VERBATIM. THIS IS THE FOURTH COPY.
--
-- The membership lookup and the two consent lookups below are
-- byte-identical in shape to 20260953100100's read_ai_session_staging
-- (which the predecessor plan's review confirmed byte-identical to
-- read_ai_session_turns in 20260953100000, and to canonical
-- get_ai_processing_consent_status -- same predicates, same
-- `ORDER BY e.created_at DESC, e.id DESC LIMIT 1`, same
-- `COALESCE(a,false) AND COALESCE(b,false)`), and to
-- 20260953110000's publish_ai_session_nearby_result. It exactly matches
-- the covering index idx_ai_processing_consent_current
-- (relationship_id, user_id, policy_version, created_at DESC, id DESC).
--
-- A NEW predicate shape here would be a latent divergence. Inventing one
-- is explicitly not done. There are now FOUR copies:
--
--   read_ai_session_turns             20260953100000
--   read_ai_session_staging           20260953100100
--   publish_ai_session_nearby_result  20260953110000
--   admit_ai_session_generation       20260953140000  (THIS FILE)
--
-- Task 5 of this plan extracts a shared no-actor helper across all four.
-- This copy is kept TEXTUALLY IDENTICAL to the others precisely so that
-- extraction stays mechanical.
--
-- Unlike publish (whose routed-item note recorded that the predicate
-- does not lift literally because publish resolves only session_id),
-- admit DOES already resolve relationship_id, so the relationship
-- lookup line the publish gate had to prepend is not needed here. What
-- is lifted is the membership lookup and the consent pair, unchanged.
--
-- ---------------------------------------------------------------------
-- FAILURE MODE: RAISE, NOT SILENT RETURN.
--
-- The read RPCs are deliberately silent (`RETURN`, zero rows) so they
-- are not existence oracles. That reasoning does NOT transfer here, for
-- the same reason Task 11 gave for publish: admit RETURNS A ROW on every
-- path and RAISEs on every rejection it cannot express as a declared
-- outcome. A verbatim `RETURN;` would hand the caller an empty rowset,
-- which the edge function cannot distinguish from a malformed response,
-- and would report success while admitting nothing -- worse than either
-- option. And unlike 'busy' / 'rate_limited' / 'limit_reached' /
-- 'conflict', a consent denial is NOT a transient outcome the caller
-- should retry or surface as a queue state; it is a hard refusal.
--
-- The message chosen is the EXISTING one, verbatim:
--
--     'AI processing consent is not current for this relationship'
--
-- -- byte-identical to the message publish_ai_session_nearby_result
-- already raises for this exact condition (20260953110000). A new
-- wording would make the same refusal look like two different failures
-- to Plan C and Plan D. The membership refusal likewise reuses publish's
-- 'Not a current member of this relationship'.
--
-- Note the asymmetry with admit's other raises ('UNAVAILABLE',
-- 'CONTEXT_CHANGED', 'BUSY', 'LIMIT_REACHED'): those are machine codes
-- the edge function maps to client states. The consent refusal is not
-- one of those states -- it is the consent-gate vocabulary Plan B
-- already established on the publish and read paths -- so it joins THAT
-- family, not the admission-outcome family. Consistency with the gate's
-- own existing message is what matters for Task 5's extraction.
--
-- ---------------------------------------------------------------------
-- LOCK ORDER IS UNCHANGED. The documented order (Global Constraint, and
-- this function is its reference implementation) is:
--
--   1. relationship advisory lock (pg_advisory_xact_lock, here)
--   2. requester quota advisory lock (INSIDE reserve_ai_assistant_quota)
--   3. session row lock (SELECT ... FOR UPDATE, here)
--   4. request row (the INSERT, here)
--
-- The gate is inserted strictly BETWEEN the relationship_id resolution
-- and step 1's pg_advisory_xact_lock. At that point this transaction
-- holds NO lock of any kind. The gate's three statements are plain
-- SELECTs against relationships and ai_processing_consent_events with
-- no FOR UPDATE, FOR SHARE or advisory lock, so they acquire no lock
-- beyond the ordinary MVCC snapshot read. Positions 1-4 and the
-- non-obvious quota-before-session-row step are byte-identical to
-- 20260953050000.
--
-- Reading consent unlocked is correct for the same reason admit's
-- existing PRE-checks are correct to read unlocked, and is in fact
-- strictly safer: consent is an append-only event log
-- (ai_processing_consent_events has no UPDATE or DELETE path in Plan A
-- outside the purge), and the only consequence of racing a withdrawal
-- that commits microseconds after this read is an admission whose
-- provider call was authorized by a consent state that was current when
-- it was read. No lock can close that window -- the withdrawal is a
-- separate user action in a separate transaction -- and the reconciler
-- plus the read gates bound its effect. Taking a lock here would buy
-- nothing and would risk the order this function is the reference for.
--
-- ---------------------------------------------------------------------
-- EVERYTHING ELSE IS PRESERVED BYTE-FOR-BYTE from 20260953050000:
--
--   * the NULL-actor guard stays LITERALLY FIRST, ahead of this gate
--     (Global Constraint: every SECURITY DEFINER function validates its
--     actor parameter non-NULL as its first statement);
--   * both idempotency blocks (the unlocked fast path and the
--     under-the-relationship-lock re-check) and their 'conflict' /
--     'already_admitted' return shapes -- NOTE both sit BEFORE the gate,
--     deliberately: see "WHERE THE GATE SITS RELATIVE TO IDEMPOTENCY";
--   * the 'CONTEXT_CHANGED' raise on a stale revision;
--   * the 'busy' return and the 'BUSY' raise (the idempotent
--     single-outstanding-request-per-session gate);
--   * the 'rate_limited' return with retry_after_seconds, and
--     'limit_reached' / 'LIMIT_REACHED';
--   * 'UNAVAILABLE' on a bogus/closed/expired session;
--   * the PRE-check / post-FOR UPDATE RE-check duplication and the
--     reason a post-lock rejection RAISEs (so the quota reservation
--     rolls back rather than leaking);
--   * the expires_at computation, the attempt_count increment, the
--     generation_epoch copy, and the operation_fingerprint rule -- the
--     fingerprint is still carried through from the parameter and this
--     function still never incorporates location into it.
--
-- WHERE THE GATE SITS RELATIVE TO IDEMPOTENCY -- deliberate, and the
-- same call publish made. Both idempotency blocks answer BEFORE the
-- gate. A replay of an ALREADY-ADMITTED request_id after a withdrawal
-- therefore still returns 'already_admitted' with its original
-- attempt_n/worker_token rather than raising. That is correct and is not
-- a hole:
--
--   * it commits nothing and admits nothing -- it re-reports the state
--     of an admission that already happened;
--   * raising instead would make a legitimate retry-after-timeout look
--     like a failed admission and could drive the edge function to admit
--     AGAIN, which is precisely the §6.2 step 2 violation ("never a new
--     provider lease" for an existing request id) the idempotency blocks
--     exist to prevent;
--   * it does not re-authorize a provider call that was not already
--     authorized: the worker_token it echoes is one claim already
--     consumed (claim's own `state = 'reserved'` predicate fails on the
--     second claim), or whose lease has expired, in which case claim's
--     `lease_deadline > now()` fails. Either way no FRESH provider call
--     is unlocked by the replay.
--
-- A NEW request_id -- the only thing that can unlock a new provider call
-- -- always reaches the gate.
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
  v_user_a uuid;
  v_user_b uuid;
  v_version text := public.ai_current_consent_policy_version();
  v_a_granted boolean;
  v_b_granted boolean;
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

  -- ---- TASK 3 CONSENT GATE STARTS HERE ----------------------------
  -- Positioned strictly between the relationship_id resolution above
  -- and LOCK 1 below: the relationship is known, and this transaction
  -- holds no lock yet, so this adds no lock and changes no lock order.
  -- See "LOCK ORDER IS UNCHANGED" in this file's header.

  -- Gate: active membership in a live, un-archived relationship.
  SELECT r.user_a, r.user_b INTO v_user_a, v_user_b
  FROM public.relationships r
  WHERE r.id = v_relationship_id
    AND r.status = 'active' AND r.chat_archived_at IS NULL
    AND (r.user_a = p_actor_id OR r.user_b = p_actor_id);
  IF v_user_a IS NULL THEN
    RAISE EXCEPTION 'Not a current member of this relationship';
  END IF;

  -- Gate: current consent from BOTH partners at the current policy
  -- version. An event at an older version never counts as granted,
  -- which is what makes a version bump require two fresh grants.
  SELECT (e.action = 'granted') INTO v_a_granted
  FROM public.ai_processing_consent_events e
  WHERE e.relationship_id = v_relationship_id AND e.user_id = v_user_a
    AND e.policy_version = v_version
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;

  SELECT (e.action = 'granted') INTO v_b_granted
  FROM public.ai_processing_consent_events e
  WHERE e.relationship_id = v_relationship_id AND e.user_id = v_user_b
    AND e.policy_version = v_version
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;

  IF NOT (COALESCE(v_a_granted, false) AND COALESCE(v_b_granted, false)) THEN
    RAISE EXCEPTION 'AI processing consent is not current for this relationship';
  END IF;
  -- ---- TASK 3 CONSENT GATE ENDS HERE ------------------------------

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

-- ======================================================================
-- MIGRATION PROVENANCE -- see 20260953090100's own block for the full
-- table, extended by 20260953100100 and 20260953120000. After this file,
-- the authoritative definition of the admission RPC is:
--
--   public.admit_ai_session_generation  Task 5   20260953140000
--                                       (THIS FILE, superseding
--                                        20260953050000)
--
-- supabase/tests/ai_session_read_authorization_contracts.sql Contract 9
-- is extended by this task to cover this supersession: it asserts the
-- LIVE body (pg_get_functiondef, comment-stripped) of
-- admit_ai_session_generation carries the consent-gate marker that only
-- THIS definition has, so a future out-of-order re-apply of
-- 20260953050000 cannot silently revert the gate and ship green.
--
-- The marker is the RAISE of
-- 'AI processing consent is not current for this relationship', chosen
-- because it is the specific semantic difference this supersession
-- exists to deliver -- not an incidental string, and not something a
-- reformat of the superseded body could reintroduce.
-- ======================================================================
