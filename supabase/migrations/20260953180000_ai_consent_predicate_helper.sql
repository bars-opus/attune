-- Task 5 item 1: extract the two-party consent predicate into one
-- shared helper, and route all four call sites through it.
--
-- THE PROBLEM. After Task 3 the membership+consent gate existed in FOUR
-- byte-identical copies:
--
--   read_ai_session_turns             (20260953100000)
--   read_ai_session_staging           (20260953100100)
--   publish_ai_session_nearby_result  (20260953170000)
--   admit_ai_session_generation       (20260953140000)
--
-- A consent-policy-version bump, a change to what "current" means, or a
-- fix to the two-party rule had to be made correctly in four places. The
-- constant was already shared (ai_current_consent_policy_version()), so
-- the exposure was the QUERY SHAPE, not the version string.
--
-- WHY IT COULD NOT BE SHARED BEFORE. Plan A's
-- get_ai_processing_consent_status(relationship_id) derives its actor
-- from auth.uid() and RAISEs 'Not authenticated' when that is NULL. All
-- four callers here are service_role-only and a service_role connection
-- carries no JWT, so auth.uid() is NULL and calling it would turn every
-- one of them into an unconditional exception. The helper below takes NO
-- actor for exactly that reason.
--
-- WHY THE HELPER RETURNS A BOOLEAN AND NEVER RAISES (Ruling 12). The
-- four sites have TWO failure modes for the SAME condition:
--
--   publish / admit              -> RAISE 'AI processing consent is not
--                                   current for this relationship'
--   read_ai_session_turns        -> RETURN (zero rows)
--   read_ai_session_staging      -> RETURN (zero rows)
--
-- The reads are silent DELIBERATELY: zero-rows-not-raise keeps a
-- partner's "no result" byte-identical to a stranger's, so the RPC is
-- not an existence oracle (see 20260953100000's header). A helper that
-- raised internally would destroy that property; a helper that took a
-- raise-or-return flag would put the choice one indirection away from
-- the function whose security property it is. So the helper answers the
-- QUESTION and each caller keeps its own ANSWER. No caller's observable
-- failure mode changes in this migration.
--
-- WHAT IS *NOT* EXTRACTED, AND WHY. The MEMBERSHIP half stays inline in
-- all four callers. It is actor-dependent -- it asks "is THIS actor a
-- current member", and resolves v_user_a / v_user_b as a side effect --
-- and it has its own two failure modes with its own distinct message
-- ('Not a current member of this relationship'). Folding it in would
-- have meant passing the actor back in, which is the thing that made
-- sharing impossible in the first place. The helper is the part that is
-- genuinely a property of the RELATIONSHIP alone.
--
-- THE QUERY SHAPE IS PRESERVED EXACTLY. The two per-user lookups below
-- are copied verbatim from the canonical
-- get_ai_processing_consent_status, including `ORDER BY e.created_at
-- DESC, e.id DESC LIMIT 1` and the COALESCE(..., false) that makes a
-- MISSING event DENY rather than pass. That shape is what matches the
-- covering index idx_ai_processing_consent_current (relationship_id,
-- user_id, policy_version, created_at DESC, id DESC) -- verified by
-- EXPLAIN to be an Index Scan, not a Seq Scan, which four call sites'
-- performance depends on.
--
-- THE MEMBER LOOKUP IS REPEATED, NOT PASSED IN. The helper re-resolves
-- user_a / user_b from public.relationships itself rather than taking
-- them as parameters. That costs one PK lookup the callers already did,
-- and it buys the property that the helper CANNOT be called with a
-- mismatched pair -- a caller that passed the wrong two user ids would
-- get a confidently wrong answer. It also keeps the signature
-- actor-free and relationship-only, which is the whole point.
--
-- The lookup here deliberately does NOT filter on r.status = 'active'
-- AND r.chat_archived_at IS NULL. That filter is the MEMBERSHIP gate's
-- job and every caller still applies it, ahead of this call, with its
-- own failure mode. Repeating it here would make a dead relationship
-- report "consent not current" instead of "not a member", changing two
-- callers' error messages for the same input.
--
-- A ONE-SIDED RELATIONSHIP DENIES. relationships.user_b is nullable and
-- its FK is ON DELETE SET NULL, so a NULL partner means a DELETED
-- ACCOUNT, not a designed single-member relationship (plan Ruling 10).
-- The v_b lookup then matches nothing, v_b_granted is NULL, and the
-- COALESCE denies -- identical to all four pre-extraction copies, which
-- the plan reviewed and confirmed consistent across them.
--
-- NO LOCK, SO NO LOCK-ORDER CHANGE. This is a plain MVCC read: STABLE,
-- no FOR UPDATE, no advisory lock. It adds no entry to the plan's fixed
-- order (relationship advisory -> quota advisory -> session row ->
-- request row) that Tasks 1 and 2 just fixed. Each caller invokes it in
-- exactly the position its inline copy occupied -- in admit and publish,
-- strictly between the relationship_id resolution and LOCK 1 -- so the
-- gate still holds no lock while it runs.

CREATE OR REPLACE FUNCTION public.ai_consent_granted_for_relationship(
  p_relationship_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_version text := public.ai_current_consent_policy_version();
  v_user_a uuid;
  v_user_b uuid;
  v_a_granted boolean;
  v_b_granted boolean;
BEGIN
  -- No actor parameter to validate. The Global Constraint's non-NULL
  -- actor check belongs to the four callers, each of which performs it
  -- as its own first statement BEFORE reaching this call; this function
  -- answers a question about a RELATIONSHIP and has no actor to check.
  -- A NULL relationship denies, via the member lookup below.
  IF p_relationship_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT r.user_a, r.user_b INTO v_user_a, v_user_b
  FROM public.relationships r
  WHERE r.id = p_relationship_id;

  IF v_user_a IS NULL THEN
    RETURN false;
  END IF;

  -- "Current" for a user = their latest event at the CURRENT policy
  -- version. An event at an older version never counts as granted,
  -- which is what makes a version bump require two fresh grants.
  SELECT (e.action = 'granted') INTO v_a_granted
  FROM public.ai_processing_consent_events e
  WHERE e.relationship_id = p_relationship_id AND e.user_id = v_user_a
    AND e.policy_version = v_version
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;

  SELECT (e.action = 'granted') INTO v_b_granted
  FROM public.ai_processing_consent_events e
  WHERE e.relationship_id = p_relationship_id AND e.user_id = v_user_b
    AND e.policy_version = v_version
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;

  RETURN COALESCE(v_a_granted, false) AND COALESCE(v_b_granted, false);
END;
$$;

REVOKE ALL ON FUNCTION public.ai_consent_granted_for_relationship(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ai_consent_granted_for_relationship(uuid)
  TO service_role;

COMMENT ON FUNCTION public.ai_consent_granted_for_relationship(uuid) IS
  'The two-party AI-processing consent predicate, shared by read_ai_session_turns, read_ai_session_staging, publish_ai_session_nearby_result and admit_ai_session_generation. Returns true only when BOTH relationship members have a ''granted'' event at the CURRENT policy version. Takes no actor (every caller is service_role, where auth.uid() is NULL, which is why Plan A''s get_ai_processing_consent_status cannot be reused) and NEVER raises -- the two read RPCs must return zero rows rather than a distinguishable error, so each caller branches on the boolean and keeps its own failure mode. Does NOT check membership or relationship liveness: that is the caller''s gate, applied before this call, with its own message.';


-- =====================================================================
-- CALL SITE 1 of 4: read_ai_session_turns.
--
-- Supersedes 20260953100000. Failure mode PRESERVED: `RETURN` (zero
-- rows), silently, exactly as before. Everything else in this body --
-- all four gates, their order, the NULL-actor guard first, the final
-- ORDER BY ordinal -- is byte-identical to the superseded definition;
-- only the consent block becomes one call.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.read_ai_session_turns(
  p_actor_id uuid, p_session_id uuid
) RETURNS SETOF public.ai_session_turns
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
  v_user_a uuid;
  v_user_b uuid;
  v_authorized boolean := false;
BEGIN
  IF p_actor_id IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_session FROM public.ai_sessions WHERE id = p_session_id;
  IF v_session.id IS NULL THEN
    RETURN;
  END IF;

  -- Gate 3: unexpired active state.
  IF v_session.state != 'active' THEN
    RETURN;
  END IF;
  IF v_session.expires_at IS NOT NULL AND v_session.expires_at <= now() THEN
    RETURN;
  END IF;

  -- Gate 1: active membership in a live, un-archived relationship.
  SELECT r.user_a, r.user_b INTO v_user_a, v_user_b
  FROM public.relationships r
  WHERE r.id = v_session.relationship_id
    AND r.status = 'active' AND r.chat_archived_at IS NULL
    AND (r.user_a = p_actor_id OR r.user_b = p_actor_id);
  IF v_user_a IS NULL THEN
    RETURN;
  END IF;

  -- Gate 2: current consent from BOTH partners at the current policy
  -- version, via the shared predicate. Silent RETURN, not RAISE.
  IF NOT public.ai_consent_granted_for_relationship(v_session.relationship_id) THEN
    RETURN;
  END IF;

  -- Gate 4: creator (private) or accepted participant (shared).
  IF v_session.visibility = 'private' THEN
    v_authorized := (v_session.creator_id = p_actor_id);
  ELSE
    v_authorized := EXISTS (
      SELECT 1 FROM public.ai_session_approvals a
      WHERE a.session_id = p_session_id
        AND a.member_id = p_actor_id
        AND a.revision = v_session.context_revision
    );
  END IF;

  IF NOT v_authorized THEN
    RETURN;
  END IF;

  RETURN QUERY SELECT * FROM public.ai_session_turns
  WHERE session_id = p_session_id
  ORDER BY ordinal;
END;
$$;
REVOKE ALL ON FUNCTION public.read_ai_session_turns(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_ai_session_turns(uuid, uuid)
  TO service_role;


-- =====================================================================
-- CALL SITE 2 of 4: read_ai_session_staging.
--
-- Supersedes 20260953100100 (which itself superseded 20260953100000).
-- Failure mode PRESERVED: `RETURN` (zero rows), silently.
--
-- The AUTHOR CHECK (`requester_id = p_actor_id`) is preserved in BOTH
-- places it appears -- Gate 0 and the final RETURN QUERY. Spec §7.2
-- requires own staged Nearby to be reachable ONLY through an
-- author-checking RPC, and the read-authorization contract asserts this
-- body still contains it specifically so that a "unification" with
-- read_ai_session_turns cannot drop it. This extraction touches the
-- consent block only; the deliberate asymmetry with
-- read_ai_session_turns (no visibility branch, no approvals lookup, no
-- partner path) is untouched.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.read_ai_session_staging(
  p_actor_id uuid, p_request_id uuid
) RETURNS SETOF public.ai_session_staging
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_session_id uuid;
  v_relationship_id uuid;
  v_user_a uuid;
  v_user_b uuid;
BEGIN
  IF p_actor_id IS NULL THEN
    RETURN;
  END IF;

  -- Gate 0: author. The staging row must exist, be unexpired, and
  -- belong to this actor. Resolved first so the session/relationship
  -- lookups below only ever run for a row the actor already owns.
  SELECT s.session_id INTO v_session_id
  FROM public.ai_session_staging s
  WHERE s.request_id = p_request_id
    AND s.requester_id = p_actor_id
    AND s.expires_at > now();
  IF v_session_id IS NULL THEN
    RETURN;
  END IF;

  SELECT se.relationship_id INTO v_relationship_id
  FROM public.ai_sessions se WHERE se.id = v_session_id;
  IF v_relationship_id IS NULL THEN
    RETURN;
  END IF;

  -- Gate 1: active membership in a live, un-archived relationship.
  SELECT r.user_a, r.user_b INTO v_user_a, v_user_b
  FROM public.relationships r
  WHERE r.id = v_relationship_id
    AND r.status = 'active' AND r.chat_archived_at IS NULL
    AND (r.user_a = p_actor_id OR r.user_b = p_actor_id);
  IF v_user_a IS NULL THEN
    RETURN;
  END IF;

  -- Gate 2: current consent from BOTH partners at the current policy
  -- version, via the shared predicate. Silent RETURN, not RAISE.
  IF NOT public.ai_consent_granted_for_relationship(v_relationship_id) THEN
    RETURN;
  END IF;

  -- Gate 3: own expiry, re-stated on the returned row so the row that
  -- is returned is the row that was authorized -- not merely a row with
  -- the same request_id. request_id is globally unique (it references
  -- ai_session_requests(id), a PK), so this is the same single row.
  RETURN QUERY SELECT * FROM public.ai_session_staging
  WHERE request_id = p_request_id AND requester_id = p_actor_id
    AND expires_at > now();
END;
$$;
REVOKE ALL ON FUNCTION public.read_ai_session_staging(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_ai_session_staging(uuid, uuid)
  TO service_role;


-- =====================================================================
-- CALL SITE 3 of 4: publish_ai_session_nearby_result.
--
-- Supersedes 20260953170000 (Task 2), which built on 20260953120000
-- (Task 1's lock-order fix), which built on 20260953110000 (Task 11's
-- gate), which built on 20260953080000. FIVE definitions now.
--
-- `CREATE OR REPLACE`, NOT `DROP` + `CREATE`. Task 2 had to DROP
-- because it ADDED an OUT parameter (`session_revision`) and
-- CREATE OR REPLACE cannot change a function's return type -- and that
-- DROP reset EXECUTE to PUBLIC by default, a real hazard Task 2 had to
-- close with an explicit REVOKE. This migration changes NO signature
-- and NO return shape, so REPLACE suffices and the grants are never
-- reset in the first place. The REVOKE/GRANT pair below is restated
-- anyway, because it costs nothing and it means this file is correct
-- whether or not a future edit reintroduces a DROP.
--
-- TASK 1'S LOCK ORDER IS PRESERVED EXACTLY, statement for statement:
--   LOCK 1  pg_advisory_xact_lock(hashtext(v_relationship_id::text))
--   LOCK 2  ai_sessions           ... FOR UPDATE
--   LOCK 3  ai_session_requests   ... FOR UPDATE
-- The lock-target lookup still precedes LOCK 1 unlocked, and the
-- consent gate still sits AFTER the row locks exactly where Task 11
-- placed it and Task 1 left it. The gate takes no lock, and this
-- extraction replaces two unlocked SELECTs with one unlocked STABLE
-- function call, so the set of locks held and their order are
-- bit-identical to the superseded body.
--
-- TASK 2'S RETURN SHAPE IS PRESERVED EXACTLY: four columns, with
-- session_revision reported from the bump's own RETURNING on the happy
-- path and from a read of the already-locked session row on the
-- idempotent-replay path. The replay branch still sits BEFORE the
-- consent gate, deliberately (Task 11's placement, re-confirmed by
-- Task 2): a retry of a publish that already succeeded must return its
-- original answer rather than raise.
--
-- Failure mode PRESERVED: RAISE, with both messages verbatim --
-- 'Not a current member of this relationship' and
-- 'AI processing consent is not current for this relationship'.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.publish_ai_session_nearby_result(
  p_actor_id uuid, p_request_id uuid
) RETURNS TABLE (
  committed boolean,
  user_ordinal int,
  attune_ordinal int,
  session_revision int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.ai_session_requests;
  v_staging public.ai_session_staging;
  v_user_ord smallint;
  v_attune_ord smallint;
  v_relationship_id uuid;
  v_session_id uuid;
  v_user_a uuid;
  v_user_b uuid;
  -- Task 2: see commit's note on why this is not named `revision`.
  v_revision int;
BEGIN
  -- FIRST STATEMENT, unchanged: the Global Constraint's NULL-actor
  -- guard. Ahead of the lock-target lookup, as it must be.
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Lock-target lookup ONLY -- unlocked, decides nothing except which
  -- rows to lock. This is Task 11's own `SELECT se.relationship_id`
  -- consent-gate lookup, hoisted to the top by 20260953120000 and
  -- widened by session_id; its 'Session unavailable' raise comes with
  -- it. 'Request not found' is still raised for an unknown request,
  -- from the locked re-read below, so neither message changes meaning.
  SELECT rq.session_id, se.relationship_id
  INTO v_session_id, v_relationship_id
  FROM public.ai_session_requests rq
  LEFT JOIN public.ai_sessions se ON se.id = rq.session_id
  WHERE rq.id = p_request_id;
  IF v_session_id IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;
  IF v_relationship_id IS NULL THEN
    RAISE EXCEPTION 'Session unavailable';
  END IF;

  -- LOCK 1: the relationship advisory lock.
  PERFORM pg_advisory_xact_lock(hashtext(v_relationship_id::text));

  -- LOCK 2: the session row, before the request row.
  PERFORM 1 FROM public.ai_sessions WHERE id = v_session_id FOR UPDATE;

  -- LOCK 3: the request row, re-read authoritatively under both locks.
  SELECT * INTO v_request FROM public.ai_session_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  v_user_ord := (v_request.attempt_n * 2) - 1;
  v_attune_ord := v_request.attempt_n * 2;

  -- Idempotent replay of an already-committed publish, answered BEFORE
  -- the consent gate on purpose. The content is already in the
  -- transcript; re-reporting the ordinals of a write that already
  -- happened discloses nothing new and commits nothing, whereas
  -- raising here would make a retry after a withdrawal look like a
  -- failed publish and could drive a caller to publish again.
  --
  -- Task 2: report the CURRENT revision, UNCHANGED. A replay that
  -- re-bumped would invalidate the fence the caller is holding and
  -- guarantee CONTEXT_CHANGED on its next admit -- breaking the exact
  -- multi-turn reachability this disclosure exists to enable, and doing
  -- so a different number of times depending on how often the caller
  -- retried. The session row is already held FOR UPDATE (LOCK 2), so
  -- this is a read of a locked row, not a new lock, and not a write.
  IF v_request.state = 'committed' THEN
    SELECT s.revision INTO v_revision
    FROM public.ai_sessions s WHERE s.id = v_request.session_id;
    RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int, v_revision;
    RETURN;
  END IF;

  SELECT * INTO v_staging FROM public.ai_session_staging
  WHERE request_id = p_request_id;
  IF v_staging.request_id IS NULL THEN
    RAISE EXCEPTION 'No staged result for this request';
  END IF;
  IF v_staging.requester_id != p_actor_id THEN
    RAISE EXCEPTION 'Only the requester may publish a staged Nearby result';
  END IF;
  IF v_staging.expires_at <= now() THEN
    RAISE EXCEPTION 'Staged result has expired';
  END IF;

  -- ---- TASK 11's ROUTED ITEM 1 STARTS HERE -------------------------
  -- v_relationship_id was resolved by the lock-target lookup above --
  -- the same `SELECT se.relationship_id FROM public.ai_sessions se`
  -- Task 11 performed here, moved earlier because the lock needs it.
  -- Task 5 routed the consent half through the shared predicate; the
  -- membership half and both raise messages are Task 11's verbatim.

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
  -- version, via the shared predicate. RAISE, not silent return --
  -- publish returns a row on every success path, so a silent return
  -- would report failure-as-success to its caller.
  IF NOT public.ai_consent_granted_for_relationship(v_relationship_id) THEN
    RAISE EXCEPTION 'AI processing consent is not current for this relationship';
  END IF;
  -- ---- TASK 11's ROUTED ITEM 1 ENDS HERE ---------------------------

  INSERT INTO public.ai_session_turns (session_id, request_id, ordinal, role, author_id, kind, payload)
  VALUES
    (v_request.session_id, p_request_id, v_user_ord, 'user', v_request.actor_id, 'nearby_result',
     jsonb_build_object('instruction', 'nearby')),
    (v_request.session_id, p_request_id, v_attune_ord, 'attune', NULL, 'nearby_result',
     jsonb_build_object('reply_text', v_staging.reply_text, 'sources', v_staging.sources));

  DELETE FROM public.ai_session_staging WHERE request_id = p_request_id;
  UPDATE public.ai_session_requests SET state = 'committed' WHERE id = p_request_id;
  -- Task 2: bump and disclose in ONE statement. See commit's note.
  UPDATE public.ai_sessions
  SET revision = public.ai_sessions.revision + 1
  WHERE id = v_request.session_id
  RETURNING public.ai_sessions.revision INTO v_revision;
  PERFORM public.mark_ai_assistant_usage_outcome(v_request.actor_id, p_request_id, 'succeeded', 2::smallint);

  RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int, v_revision;
END;
$$;
REVOKE ALL ON FUNCTION public.publish_ai_session_nearby_result(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_ai_session_nearby_result(uuid, uuid)
  TO service_role;


-- =====================================================================
-- CALL SITE 4 of 4: admit_ai_session_generation.
--
-- Supersedes 20260953140000 (Task 3's consent gate), which superseded
-- 20260953050000.
--
-- Failure mode PRESERVED: RAISE, both messages verbatim. admit returns
-- a row on every path -- 'admitted', 'conflict', 'already_admitted',
-- 'busy', 'rate_limited', 'limit_reached' -- so a silent return would
-- report success while admitting nothing. All seven documented outcomes
-- are preserved; this extraction ADDS no refusal and REMOVES none.
--
-- THE GATE STAYS STRICTLY BETWEEN THE relationship_id RESOLUTION AND
-- LOCK 1, where no lock is yet held. admit is the reference
-- implementation of the documented lock order:
--   LOCK 1  pg_advisory_xact_lock (relationship)
--   LOCK 2  reserve_ai_assistant_quota's own advisory lock (in callee)
--   LOCK 3  ai_sessions row FOR UPDATE
--   LOCK 4  the ai_session_requests INSERT
-- The extraction replaces two unlocked SELECTs with one unlocked STABLE
-- call in the same position, so the lock set and its order are
-- unchanged. The NULL-actor guard remains the literal first statement.
--
-- `CREATE OR REPLACE`: no signature or return-shape change, so no DROP
-- and no reset of EXECUTE to PUBLIC.
-- =====================================================================
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
  -- (Task 5 routed its consent half through the shared predicate.)
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
  -- version, via the shared predicate. RAISE, not silent return --
  -- admit returns a row on every path, so a silent return would
  -- report success while admitting nothing.
  IF NOT public.ai_consent_granted_for_relationship(v_relationship_id) THEN
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
-- MIGRATION PROVENANCE -- see 20260953090100's block for the full table,
-- extended by 20260953100100, 20260953120000, 20260953140000,
-- 20260953150000 and 20260953170000. After THIS file:
--
--   public.ai_consent_granted_for_relationship
--     Task 5   20260953180000  (THIS FILE, new -- no predecessor)
--
--   public.read_ai_session_turns
--     Task 10  20260953100000  (original)
--     Task 5   20260953180000  (THIS FILE) <-- WINS
--
--   public.read_ai_session_staging
--     Task 10  20260953100000  (original)
--     fix r1   20260953100100  (added the membership + consent gate)
--     Task 5   20260953180000  (THIS FILE) <-- WINS
--
--   public.publish_ai_session_nearby_result
--     Task 8   20260953080000  (original)
--     Task 11  20260953110000  (added the membership + consent gate)
--     lock fix 20260953120000  (corrected the lock order)
--     Task 2   20260953170000  (added session_revision, via DROP)
--     Task 5   20260953180000  (THIS FILE) <-- WINS   -- FIVE definitions
--
--   public.admit_ai_session_generation
--     Task 5B  20260953050000  (original)
--     Task 3   20260953140000  (added the consent gate)
--     Task 5   20260953180000  (THIS FILE) <-- WINS
--
-- WHAT THE SUPERSESSION MARKERS BECOME. Before this file, Contract 9 in
-- supabase/tests/ai_session_read_authorization_contracts.sql, Contract 11
-- in ai_session_purge_contracts.sql and the structural contract in
-- ai_session_admit_contracts.sql all asserted the live BODY of these
-- functions contains the literal string `ai_processing_consent_events`.
-- That string is the whole point of the extraction: it now lives in ONE
-- place, the helper, so those markers are RE-DERIVED to
-- `ai_consent_granted_for_relationship` -- the call -- and the predicate's
-- internals (two-party lookup, COALESCE-denial, version pinning, the
-- ORDER BY that matches idx_ai_processing_consent_current) are asserted
-- ONCE, against the helper, where they now live. A marker asserting a
-- table name a function no longer names would be a false alarm; a marker
-- asserting the CALL is exactly as sharp, because every superseded body
-- predates the helper's existence and cannot contain its name.
--
-- WHY THE HELPER IS NOT ITSELF A SUPERSESSION HAZARD. It has exactly one
-- definition and no predecessor, so there is no out-of-order re-apply
-- that can revert it. If it were ever dropped, all four callers would
-- fail loudly with `function ... does not exist` rather than silently
-- opening a gate -- which is the opposite of the failure mode Contract 9
-- exists to catch, and strictly safer than four inline copies of which
-- any one could be reverted alone.
-- ======================================================================
