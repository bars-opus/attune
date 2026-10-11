-- Merge-blocker fix (Task 2 of the 2026-10-10 merge-blockers plan):
-- RETURN THE SESSION REVISION FROM THE TWO COMPLETION RPCs THAT BUMP
-- IT, so a bounded multi-turn AI session is actually reachable by its
-- only intended consumer. Spec §6.2, §7.1; final-branch-review N2.
--
-- ======================================================================
-- THE DEFECT.
--
-- admit_ai_session_generation (20260953140000, lines 384 and 422)
-- refuses an admission unless p_expected_revision equals the session's
-- CURRENT ai_sessions.revision:
--
--     IF v_session.revision != p_expected_revision THEN
--       RAISE EXCEPTION 'CONTEXT_CHANGED';
--     END IF;
--
-- That is the optimistic fence spec §6.2 asks for, and it is correct.
-- But commit_ai_session_ideas_turn and
-- publish_ai_session_nearby_result BOTH bump that revision as their
-- last write:
--
--     UPDATE public.ai_sessions SET revision = revision + 1 WHERE ...
--
-- and NEITHER returned it. Verified by catalog query before this file:
-- the ONLY function in this plan whose result type mentions `revision`
-- was prepare_ai_session, which returns the INITIAL value only and is
-- never called again inside a live session.
--
-- So the sequence the whole branch exists to support --
--
--     turn 1: admit(expected_revision=1) -> claim -> commit   (rev 1->2)
--     turn 2: admit(expected_revision=?)
--
-- -- is UNREACHABLE. Turn 2 must pass 2, and nothing told the caller
-- that 2 is the answer. Every committed test in this suite got past
-- turn 1 by doing `SELECT revision FROM public.ai_sessions` directly:
--
--   * ai_session_commit_ideas_contracts.sql Contract 3 hardcodes a
--     literal 2 with a comment explaining that 1 "is stale and raises
--     CONTEXT_CHANGED".
--   * ai_session_nearby_staging_contracts.sql Contract 4 does the same.
--
-- A literal works in a test that knows how many turns preceded it. It
-- is not available to Plan C's edge function, which (a) forbids itself
-- raw table reads and (b) cannot know the turn count of a session it
-- did not create. And a raw `SELECT ... FROM public.ai_sessions` is not
-- an option even if Plan C relaxed that rule: the table grants nothing
-- to `authenticated` (asserted at 56 combinations / 0 leaked by
-- ai_session_read_authorization_contracts.sql and
-- ai_session_purge_contracts.sql), and reading it with the service role
-- would bypass ALL FOUR of spec §7.2's authorization gates.
--
-- ======================================================================
-- THE FIX, AND WHY THIS SHAPE (the user's recorded decision, Option A).
--
-- Return the NEW revision from the two RPCs that bump it. The caller
-- that CAUSED the bump learns the result atomically, in the same
-- transaction and the same round trip, with no second RPC and no new
-- read surface.
--
-- Option B -- a gated read_ai_session_state RPC returning revision plus
-- request state -- was considered and NOT chosen for this plan. It
-- remains the right fix for a DIFFERENT gap this file does not close: a
-- client that loses its HTTP response has no way to learn what
-- happened. The two are not mutually exclusive; B belongs in Plan C's
-- own plan, next to the error handling that needs it. Nothing here
-- forecloses it.
--
-- WHY NOT A SEPARATE `revision` OUT PARAMETER ON admit INSTEAD. admit
-- already returns six fields and is the function doing the FENCING; a
-- fence that also told you the value to fence on would defeat itself
-- (the caller would just echo it back and the stale-context check would
-- never fire). The bump sites are the correct disclosure points.
--
-- WHY THE FIELD IS NAMED `session_revision` AND NOT `revision`. Inside
-- a plpgsql function whose RETURNS TABLE declares an OUT column named
-- `revision`, that name shadows `ai_sessions.revision` in any
-- unqualified reference -- and this body's bump statement is
-- `SET revision = revision + 1`, which would then resolve the
-- right-hand `revision` to the OUT variable (NULL) rather than the
-- column. Postgres would either error on the ambiguity or, worse,
-- silently bump to NULL. The statement is written with an explicit
-- table qualification below regardless, but the distinct field name
-- removes the hazard by construction rather than by care. It also
-- reads correctly at the call site: `session_revision` is the
-- session's revision, not the request's or the turn's.
--
-- ======================================================================
-- THIS MIGRATION SUPERSEDES PARTS OF ONE EARLIER MIGRATION.
--
-- It re-defines, by CREATE OR REPLACE, exactly TWO functions:
--
--   * public.commit_ai_session_ideas_turn
--   * public.publish_ai_session_nearby_result
--
-- BOTH BODIES ARE TAKEN FROM 20260953120000 (Task 1 of this plan, the
-- completion lock-order fix) AND ARE OTHERWISE UNCHANGED. This is the
-- supersession hazard the plan's pre-flight Ruling 1 called out
-- explicitly, so it is worth being exact about what was and was not
-- carried over:
--
--   * Task 1's LOCK ORDER is preserved statement-for-statement in both:
--     relationship advisory lock -> ai_sessions row FOR UPDATE ->
--     ai_session_requests row FOR UPDATE, with the unlocked
--     lock-target pre-read ahead of all three and deciding nothing.
--     Reverting to the pre-Task-1 bodies would reintroduce a Critical
--     deadlock that reproduced 14/15 at a 1 ms race window.
--   * Task 11's membership + consent gate in publish is preserved,
--     INCLUDING ITS POSITION: `IF p_actor_id IS NULL` is still the
--     literal first statement, and the already-'committed' idempotent
--     replay is still answered BEFORE the gates.
--   * Every error message is verbatim.
--   * The FOR UPDATE count in each body is still exactly 2.
--
-- It re-defines NOTHING ELSE. In particular it does NOT touch
-- public.stage_ai_session_nearby_result (also defined by 20260953120000
-- -- see "WHY STAGE IS NOT HERE" below),
-- public.admit_ai_session_generation (20260953140000's consent gate and
-- lock order are untouched), public.discard_ai_session_nearby_staging
-- (20260953150000), public.reconcile_ai_session_leases
-- (20260953160000), public.end_ai_session,
-- public.purge_ai_session_content, public.purge_expired_ai_sessions or
-- public.reconcile_ai_session_quota_residue.
--
-- WHY STAGE IS NOT HERE. stage_ai_session_nearby_result does not bump
-- ai_sessions.revision -- it writes the ai_session_staging row and sets
-- the request to 'staged', and the revision bump for the Nearby path
-- happens later, in publish. It also RETURNS void, so it has no return
-- shape to extend. Nothing about this task requires touching it, and
-- re-defining it would mean re-asserting Task 1's lock-order fix on a
-- third body for no behavioural gain. The Nearby two-turn sequence
-- therefore learns its new revision from publish, which is the call
-- that actually caused the bump -- which is the correct disclosure
-- point under Option A's own rule.
--
-- ======================================================================
-- THE IDEMPOTENT-REPLAY PATHS REPORT THE CURRENT REVISION AND DO NOT
-- RE-BUMP. This is load-bearing, not a detail.
--
-- Both functions have a replay path for an already-'committed' request
-- (the lost-HTTP-response retry). Those paths insert nothing and must
-- bump nothing -- a replay that re-bumped would invalidate the fence
-- the caller is holding and turn a successful retry into a guaranteed
-- CONTEXT_CHANGED on the next admit, breaking the very multi-turn
-- reachability this file exists to deliver. Worse, it would do so
-- non-deterministically, depending on how many times the caller
-- retried.
--
-- So each replay path reads the CURRENT revision and returns it:
--
--     SELECT s.revision INTO v_revision
--     FROM public.ai_sessions s WHERE s.id = v_request.session_id;
--
-- The session row is already held FOR UPDATE at that point (LOCK 2), so
-- this read is under the lock and cannot drift. It is a READ of a
-- locked row, not a new lock, so the FOR UPDATE count stays at 2 and
-- the structural lock-order contracts are unaffected.
--
-- In publish this read sits in the replay branch, which is BEFORE the
-- membership and consent gates -- deliberately, preserving Task 11's
-- design as Task 10's re-review verified it (replay returns
-- committed=t with the original ordinals and the revision UNCHANGED,
-- 2->2). Disclosing an integer counter for a write that already
-- happened and is already in the transcript discloses nothing the
-- caller does not already hold, and the alternative -- raising, or
-- gating the replay -- is what Task 11 rejected for good reasons that
-- have not changed.
--
-- ON THE HAPPY PATH the bump and the disclosure are ONE statement:
--
--     UPDATE public.ai_sessions SET revision = public.ai_sessions.revision + 1
--     WHERE id = v_request.session_id
--     RETURNING public.ai_sessions.revision INTO v_revision;
--
-- RETURNING on the UPDATE, not a follow-up SELECT. There is no window
-- between the bump and the read in which anything could intervene --
-- not because the lock makes a follow-up SELECT unsafe (it does not;
-- the row is held FOR UPDATE), but because one statement cannot
-- disagree with itself, and this value is the one the caller will fence
-- its next admit on.
--
-- ======================================================================
-- RETURN SHAPES: BEFORE AND AFTER.
--
--   commit_ai_session_ideas_turn(uuid, uuid, text, text, jsonb)
--     BEFORE: TABLE (committed boolean, user_ordinal int, attune_ordinal int)
--     AFTER:  TABLE (committed boolean, user_ordinal int, attune_ordinal int,
--                    session_revision int)
--
--   publish_ai_session_nearby_result(uuid, uuid)
--     BEFORE: TABLE (committed boolean, user_ordinal int, attune_ordinal int)
--     AFTER:  TABLE (committed boolean, user_ordinal int, attune_ordinal int,
--                    session_revision int)
--
-- STRICTLY ADDITIVE AT THE CALL SITE, AND APPENDED LAST. Every
-- pre-existing field keeps its name, its type and its ORDINAL POSITION,
-- so a caller selecting by name is unaffected and a caller selecting
-- positionally is unaffected for the three columns it already knew. The
-- argument lists do not change, so no overload is created.
--
-- BUT A `DROP FUNCTION` IS REQUIRED, AND THAT IS NOT OPTIONAL.
-- CREATE OR REPLACE FUNCTION CANNOT add an OUT parameter -- not even at
-- the end. Measured on this project's Postgres (17.11) rather than
-- assumed:
--
--   ERROR:  cannot change return type of existing function
--   DETAIL:  Row type defined by OUT parameters is different.
--   HINT:  Use DROP FUNCTION commit_ai_session_ideas_turn(...) first.
--
-- A RETURNS TABLE column IS an OUT parameter, and the composite row
-- type it defines is part of what CREATE OR REPLACE refuses to change.
-- So each function below is DROPped and re-created. Three consequences,
-- all handled explicitly:
--
--   1. ATOMICITY OF THE DROP+CREATE, STATED HONESTLY. On Supabase each
--      migration file is applied inside one transaction, and DDL in
--      Postgres is transactional, so in deployment there is no window
--      in which these functions do not exist for any other session:
--      either both the DROP and the CREATE commit, or neither does.
--
--      The LOCAL runner (scripts/local_pg_setup.sh) is different, and
--      this file does NOT paper over it: it invokes
--      `psql -v ON_ERROR_STOP=1 -f <file>` with no explicit BEGIN, so
--      psql is in AUTOCOMMIT and each statement commits on its own. If
--      the CREATE below failed, the DROP would already have committed
--      and the function would be gone. That is acceptable here and
--      only here, because that runner drops and recreates the whole
--      database from migrations on every invocation, so there is no
--      state to corrupt and the next run is clean.
--
--      No explicit BEGIN/COMMIT is added to close that local gap. No
--      other migration in this project uses one (verified by grep: 0 of
--      272), and a COMMIT in the middle of a file that Supabase has
--      already wrapped in a transaction would commit that outer
--      transaction early -- trading a harmless local-rebuild gap for a
--      real deployment hazard in every file that followed the pattern.
--
--   2. THE ACL IS DESTROYED BY THE DROP AND MUST BE RE-GRANTED. This is
--      the real hazard of the DROP, not the atomicity: a dropped
--      function takes its ACL with it, and a re-created function
--      defaults to EXECUTE for PUBLIC. Leaving the GRANT off would
--      hand `anon` and `authenticated` EXECUTE on two SECURITY DEFINER
--      functions that write the permanent transcript -- a far worse
--      defect than the one this file fixes. So REVOKE ALL FROM PUBLIC,
--      anon, authenticated and GRANT EXECUTE TO service_role are
--      re-stated after each CREATE below, exactly as 20260953120000
--      stated them, and service_role_grants_test.sql plus
--      ai_session_read_authorization_contracts.sql Contract 9 assert
--      the result independently.
--
--   3. `DROP FUNCTION` WITHOUT `IF EXISTS` IS DELIBERATE. If either
--      function is somehow absent when this file runs, the migration
--      must FAIL LOUDLY rather than quietly create a function whose
--      predecessor's lock-order and consent-gate history is unknown.
--      And `CASCADE` is NOT used: nothing in the schema depends on
--      these functions (no views, no other function's return type, no
--      default expression -- verified by catalog query on
--      pg_depend before writing this), so a RESTRICT drop that
--      unexpectedly fails is information, not an obstacle.
--
-- PLAN C AND PLAN D MUST MATCH THIS. Both plans' sample code destructures
-- the commit/publish result. Neither reads `session_revision` today
-- because it did not exist; both must thread it into the NEXT admit's
-- p_expected_revision instead of guessing, and Plan C must delete any
-- raw `ai_sessions` read it was going to add to compensate.
-- ======================================================================


-- ----------------------------------------------------------------------
-- commit_ai_session_ideas_turn -- Task 1's body (20260953120000) with
-- the session revision added to the return shape. The lock sequence,
-- the unlocked lock-target pre-read, the ordinal parity derivation, the
-- idempotent replay and every error message are unchanged.
--
-- LOCK ORDER (unchanged from 20260953120000): relationship advisory
-- lock -> ai_sessions row FOR UPDATE -> ai_session_requests row FOR
-- UPDATE. The ai_session_turns INSERT's implicit FOR KEY SHARE on
-- ai_sessions is subsumed by the FOR UPDATE already held. No quota
-- advisory lock appears in this path and none is needed: that lock
-- lives inside reserve_ai_assistant_quota (the admission path), and
-- mark_ai_assistant_usage_outcome -- the only quota function this path
-- calls -- takes no advisory lock. So this acquires a strict PREFIX of
-- the documented order, exactly as end_ai_session does.
--
-- DROP first: CREATE OR REPLACE cannot add an OUT parameter. No
-- IF EXISTS and no CASCADE -- see "A `DROP FUNCTION` IS REQUIRED"
-- above. The GRANT is re-stated after the CREATE because the DROP takes
-- the ACL with it.
DROP FUNCTION public.commit_ai_session_ideas_turn(uuid, uuid, text, text, jsonb);
CREATE FUNCTION public.commit_ai_session_ideas_turn(
  p_worker_token uuid,
  p_request_id uuid,
  p_user_instruction text,
  p_reply_text text,
  p_proposal jsonb
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
  v_user_ord smallint;
  v_attune_ord smallint;
  v_session_id uuid;
  v_relationship_id uuid;
  -- Task 2: the value this RPC now discloses. Named v_revision rather
  -- than reusing the OUT column name, so no unqualified reference in
  -- this body can resolve to the wrong thing.
  v_revision int;
BEGIN
  -- Lock-target lookup ONLY: which relationship and session must be
  -- locked. Unlocked on purpose, decides nothing. It carries the same
  -- worker_token predicate as the authoritative re-read below, so a
  -- NULL or wrong token is rejected with the SAME message before any
  -- lock is taken.
  SELECT rq.session_id, se.relationship_id
  INTO v_session_id, v_relationship_id
  FROM public.ai_session_requests rq
  JOIN public.ai_sessions se ON se.id = rq.session_id
  WHERE rq.id = p_request_id AND rq.worker_token = p_worker_token;
  IF v_relationship_id IS NULL THEN
    RAISE EXCEPTION 'Request not found for this worker token';
  END IF;

  -- LOCK 1: the relationship advisory lock, first and always. Same
  -- hashtext(relationship_id::text) key end_ai_session,
  -- purge_ai_session_content, admit_ai_session_generation and
  -- reconcile_ai_session_leases use, so all five serialize here.
  PERFORM pg_advisory_xact_lock(hashtext(v_relationship_id::text));

  -- LOCK 2: the session row. Taken explicitly and BEFORE the request
  -- row so that this function's acquisition order is deterministic
  -- rather than a side effect of where the turns INSERT happens to sit.
  -- The INSERT's implicit FOR KEY SHARE is subsumed by this FOR UPDATE.
  PERFORM 1 FROM public.ai_sessions WHERE id = v_session_id FOR UPDATE;

  -- LOCK 3: the request row, re-read authoritatively under all the
  -- locks above. EVERY decision below is made from THIS row, not from
  -- the unlocked pre-read.
  SELECT * INTO v_request FROM public.ai_session_requests
  WHERE id = p_request_id AND worker_token = p_worker_token
  FOR UPDATE;
  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Request not found for this worker token';
  END IF;

  -- Ordinal parity: 2n-1 for the user turn, 2n for Attune's, both from
  -- the SAME attempt_n. One counter, never two.
  v_user_ord := (v_request.attempt_n * 2) - 1;
  v_attune_ord := v_request.attempt_n * 2;

  IF v_request.state = 'committed' THEN
    -- Idempotent replay: return the same ordinals, insert nothing, and
    -- BUMP NOTHING. Task 2: report the CURRENT revision so a caller
    -- that lost its response can still fence its next admit. The
    -- session row is already held FOR UPDATE (LOCK 2), so this read
    -- cannot drift; it is a read of a locked row, not a new lock.
    SELECT s.revision INTO v_revision
    FROM public.ai_sessions s WHERE s.id = v_request.session_id;
    RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int, v_revision;
    RETURN;
  END IF;
  IF v_request.state != 'started' THEN
    RAISE EXCEPTION 'Request is not in a committable state: %', v_request.state;
  END IF;

  INSERT INTO public.ai_session_turns (session_id, request_id, ordinal, role, author_id, kind, payload)
  VALUES
    (v_request.session_id, p_request_id, v_user_ord, 'user', v_request.actor_id, 'ideas_answer',
     jsonb_build_object('instruction', p_user_instruction)),
    (v_request.session_id, p_request_id, v_attune_ord, 'attune', NULL, 'ideas_answer',
     jsonb_build_object('reply_text', p_reply_text, 'suggested_planning_item', p_proposal));

  UPDATE public.ai_session_requests SET state = 'committed' WHERE id = p_request_id;
  -- Task 2: the bump and its disclosure are ONE statement. RETURNING,
  -- not a follow-up SELECT -- one statement cannot disagree with
  -- itself, and this integer is what the caller will fence its next
  -- admit_ai_session_generation on. The column references are
  -- table-qualified so neither side can resolve to the OUT column.
  UPDATE public.ai_sessions
  SET revision = public.ai_sessions.revision + 1
  WHERE id = v_request.session_id
  RETURNING public.ai_sessions.revision INTO v_revision;

  PERFORM public.mark_ai_assistant_usage_outcome(v_request.actor_id, p_request_id, 'succeeded', 1::smallint);

  RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int, v_revision;
END;
$$;
REVOKE ALL ON FUNCTION public.commit_ai_session_ideas_turn(uuid, uuid, text, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_ai_session_ideas_turn(uuid, uuid, text, text, jsonb)
  TO service_role;


-- ----------------------------------------------------------------------
-- publish_ai_session_nearby_result -- Task 1's body (20260953120000)
-- with the session revision added to the return shape. Task 11's
-- membership + consent gate, its POSITION, and the pre-gate idempotent
-- replay are all preserved exactly:
--
--   * `IF p_actor_id IS NULL THEN RAISE 'Not authenticated'` is STILL
--     the literal first statement.
--   * The already-'committed' idempotent replay is STILL answered
--     BEFORE the membership and consent gates (Task 11 / Task 10's F1
--     re-review: deliberate, so a post-withdrawal retry of a publish
--     that already happened does not look like a failed publish and
--     drive the caller to publish again). The ONLY thing Task 2 adds
--     to that branch is a READ of the session row this transaction
--     already holds FOR UPDATE. There is STILL no WRITE of any kind
--     before the gates.
--   * Both gates STILL precede the ai_session_turns INSERT they guard
--     (pinned structurally by ai_session_purge_contracts.sql Contract
--     11, which compares positions on the comment-stripped live body).
--   * The author check `v_staging.requester_id != p_actor_id` is STILL
--     present and STILL ahead of the gates (spec §7.2's asymmetry).
--   * The lock sequence is STILL relationship advisory -> session row
--     -> request row, with exactly 2 FOR UPDATEs.
--   * Every error message is verbatim.
--
-- DROP first, for the same reason and with the same no-IF-EXISTS,
-- no-CASCADE discipline as commit above.
DROP FUNCTION public.publish_ai_session_nearby_result(uuid, uuid);
CREATE FUNCTION public.publish_ai_session_nearby_result(
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
  v_version text := public.ai_current_consent_policy_version();
  v_a_granted boolean;
  v_b_granted boolean;
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
  -- The gates below are byte-identical to Task 11's.

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


-- ======================================================================
-- MIGRATION PROVENANCE -- see 20260953090100's block for the full
-- table and 20260953120000's for the completion RPCs' lock-order
-- history. After this file:
--
--   public.commit_ai_session_ideas_turn
--     Task 7   20260953070000_ai_session_commit_ideas_rpc.sql  (original)
--     lock fix 20260953120000_ai_session_completion_lock_order_fix.sql
--     Task 2   20260953170000  (THIS FILE) <-- WINS
--       BUILDS ON 20260953120000's body. Adds `session_revision int` to
--       the return shape as a FOURTH, APPENDED column, disclosed from
--       the revision bump's own RETURNING on the happy path and from a
--       read of the already-locked session row on the idempotent-replay
--       path. TWO markers now discriminate: `session_revision` (this
--       file) AND `pg_advisory_xact_lock` (20260953120000's lock-order
--       fix, which must NOT have been lost).
--
--   public.publish_ai_session_nearby_result
--     Task 8   20260953080000  (original)
--     Task 11  20260953110000  (added the membership + consent gate)
--     lock fix 20260953120000  (corrected the lock order)
--     Task 2   20260953170000  (THIS FILE) <-- WINS
--       BUILDS ON 20260953120000's body, which itself built on Task
--       11's. Same additive return-shape change. THREE markers now
--       discriminate: `session_revision` (this file),
--       `pg_advisory_xact_lock` (20260953120000) AND
--       `ai_processing_consent_events` (Task 11's gate). Re-applying
--       any of 20260953080000, 20260953110000 or 20260953120000 alone
--       and last reverts a DIFFERENT subset of those three, which is
--       why all three are asserted separately rather than as one check.
--
--   public.stage_ai_session_nearby_result
--     lock fix 20260953120000  <-- STILL WINS (not re-defined here; it
--                                  does not bump the revision and
--                                  RETURNS void -- see "WHY STAGE IS
--                                  NOT HERE" above)
--   public.admit_ai_session_generation
--     Task 3   20260953140000  <-- STILL WINS (not re-defined here)
--   public.discard_ai_session_nearby_staging
--     T1 fix r1 20260953150000 <-- STILL WINS (not re-defined here)
--   public.reconcile_ai_session_leases
--     Task 4   20260953160000  <-- STILL WINS (not re-defined here)
--   public.end_ai_session, public.share_ai_session_turn
--     fix r1   20260953090100  <-- STILL WIN (not re-defined here)
--   public.purge_ai_session_content, public.purge_expired_ai_sessions
--     Task 11  20260953110000  <-- STILL WIN (not re-defined here)
--
-- A future change to any function above must be made in a NEW migration
-- that sorts after the winning file, not in the original. A re-applied
-- 20260953070000, 20260953080000, 20260953110000 or 20260953120000,
-- alone and last, would silently revert part of this plan;
-- ai_session_read_authorization_contracts.sql Contract 9 (now TEN
-- superseded definitions) is what fails loudly when that happens.
-- ======================================================================
