-- Merge-blocker fix: the lock-order inversion in the three completion
-- RPCs. Spec §6.2, §7.1, §8.2.2, and the plan's Global Constraints,
-- which fix the lock order and say in those words that a mixed order
-- "is a merge blocker".
--
-- ======================================================================
-- THIS MIGRATION SUPERSEDES PARTS OF THREE EARLIER MIGRATIONS.
--
-- It re-defines, by CREATE OR REPLACE:
--
--   * public.commit_ai_session_ideas_turn    -- originally
--     20260953070000 (Task 7)
--   * public.stage_ai_session_nearby_result  -- originally
--     20260953080000 (Task 8)
--   * public.publish_ai_session_nearby_result -- most recently
--     20260953110000 (Task 11), which itself superseded Task 8's
--     20260953080000 to add the membership + consent gate. THIS FILE
--     BUILDS ON TASK 11's BODY, gate included and gate position
--     preserved -- it does NOT revert to Task 8's.
--
-- It re-defines NOTHING ELSE. In particular it does NOT touch
-- public.end_ai_session, public.purge_ai_session_content,
-- public.purge_expired_ai_sessions or
-- public.discard_ai_session_nearby_staging. The first two already
-- acquire a strict PREFIX of the documented order and are pinned by
-- anti-rot assertions; end_ai_session additionally carries Task 9 fix
-- round 1's Critical F1 quota-release fix. The deadlock documented
-- below is the COMPLETION RPCs' fault, not theirs, and "fixing" it by
-- reordering the conforming side would revert verified work while
-- leaving the inversion in place. See "WHY ONLY THREE FUNCTIONS" below.
--
-- Per this plan's additive-migrations discipline (established by Task
-- 6's fix round 20260953060100 and followed by 20260953090100,
-- 20260953100100 and 20260953110000), no earlier migration's logic is
-- edited in place. Later migrations win; the earlier files stay as the
-- record of what shipped when. A MIGRATION PROVENANCE block at the
-- bottom of this file records the new winners, and
-- supabase/tests/ai_session_read_authorization_contracts.sql Contract 9
-- plus supabase/tests/ai_session_purge_contracts.sql Contract 11 are
-- the executable form of that note.
-- ======================================================================
--
--
-- ======================================================================
-- THE DEFECT: A REAL, REPRODUCED DEADLOCK -- NOT A THEORETICAL ONE
-- ======================================================================
--
-- All three completion RPCs took `SELECT ... FROM ai_session_requests
-- ... FOR UPDATE` as their FIRST lock and only then touched
-- ai_sessions -- the documented order's last two elements inverted --
-- and took NO relationship advisory lock at all. The order is fixed at:
--
--   1. relationship advisory lock  pg_advisory_xact_lock(hashtext(rel))
--   2. quota advisory lock         (inside reserve_ai_assistant_quota,
--                                   admission path only -- absent here)
--   3. session row lock            SELECT ... FOR UPDATE on ai_sessions
--   4. request row lock            SELECT ... FOR UPDATE on
--                                  ai_session_requests
--
-- end_ai_session, purge_ai_session_content, admit_ai_session_generation
-- and reconcile_ai_session_leases all take 1 -> 3 -> 4. These three
-- took 4 -> 3. Two transactions acquiring the same two rows in opposite
-- orders is the textbook deadlock, and it fired on the first attempt.
--
-- MEASURED BEFORE THE FIX, on this file's own parent commit, against
-- the unmodified shipped RPCs, from two concurrent psql backends with
-- NO added sleeps and NO instrumentation, 10 trials per pair per
-- ordering on a freshly built database:
--
--   commit  x end    order A/B: 10/10 deadlocks     B/A: 10/10
--   stage   x end     "         10/10               "    9/10
--   publish x end     "          9/10               "    8/10
--   commit  x purge   "          7/10 (+3 purger)   "    7/10 (+3)
--   stage   x purge   "          7/10 (+3 purger)   "    8/10 (+1)
--   publish x purge   "         10/10 (+4 purger)   "    9/10 (+7)
--
-- The victim ALTERNATES. In the commit x end run, trials 2, 3 and 6
-- killed end_ai_session -- i.e. THE USER'S OWN "End session" ACTION
-- failing with a raw SQLSTATE 40P01 `deadlock detected`, surfaced to
-- the client, for an operation that is supposed to be unconditional for
-- a current member of an active shared session.
--
-- THE PURGER CASE IS WORSE, AND IS WHY THIS IS CRITICAL RATHER THAN
-- MERELY IMPORTANT. purge_expired_ai_sessions wraps each session in a
-- per-session `EXCEPTION WHEN OTHERS` so one wedged session cannot stop
-- the platform's every-minute purge. That handler is correct for its
-- purpose and is NOT changed here, but it SWALLOWED the deadlock into a
-- WARNING: across the 60 purger trials above, 21 runs logged
-- `purge_expired_ai_sessions: session <id> could not be purged
-- (deadlock detected) -- skipped, will retry next run` and left an
-- EXPIRED session at state='active' WITH ITS CONTENT RETAINED. Spec
-- §8.2.3's five-minute purge-lag target and the Global Constraint that
-- session content is deleted in the same transaction that closes the
-- session are both missed, silently, with only a WARNING in the cron
-- log. A hot session can lose that race repeatedly.
--
-- ======================================================================
-- THE MECHANISM IS AN IMPLICIT LOCK, WHICH IS WHY ELEVEN REVIEWS MISSED
-- IT
-- ======================================================================
--
-- The deadlock does NOT fire on the explicit `UPDATE public.ai_sessions
-- SET revision = revision + 1`. It fires EARLIER, on the FK check of
-- the child-table INSERT, which takes FOR KEY SHARE on the parent
-- ai_sessions row:
--
--   CONTEXT: while locking tuple (0,2) in relation "ai_sessions"
--     SQL statement "SELECT 1 FROM ONLY "public"."ai_sessions" x
--                    WHERE "id" OPERATOR(pg_catalog.=) $1 FOR KEY SHARE OF x"
--     SQL statement "INSERT INTO public.ai_session_turns ..."
--
-- Verified by catalog query: ai_session_turns, ai_session_staging,
-- ai_session_requests, ai_session_approvals, ai_session_sources and
-- ai_session_publications ALL carry a FK to ai_sessions, so every
-- INSERT into any of them takes FOR KEY SHARE on the parent session
-- row. Two consequences:
--
--   * The inversion is NOT fixable by dropping or moving the revision
--     bump. The session-row lock is taken by the INSERT whether or not
--     the UPDATE exists.
--
--   * stage_ai_session_nearby_result had NO statement mentioning
--     ai_sessions as a lock target at all -- it only read
--     `SELECT expires_at ... WHERE id = v_request.session_id` without
--     FOR UPDATE -- yet it still took the session row lock, via the
--     ai_session_staging INSERT's FK check. An audit that enumerates
--     explicit FOR UPDATE / UPDATE statements sees stage as taking ONE
--     lock and therefore as trivially unable to deadlock. It takes two.
--     That omission is precisely what the explicit-lock audits in
--     eleven prior reviews missed.
--
-- A lock enumeration for this feature must therefore count implicit
-- parent-row locks taken by child-table INSERTs, not only explicit
-- row locks.
--
-- ======================================================================
-- THE FIX, AND WHY IT IS THIS SHAPE
-- ======================================================================
--
-- Each of the three now:
--
--   1. validates its first-statement parameter (unchanged -- see
--      "FIRST-STATEMENT VALIDATION" below);
--   2. resolves relationship_id and session_id from the request row
--      with a PLAIN, UNLOCKED read (no FOR UPDATE, no lock of any kind);
--   3. takes the relationship advisory lock;
--   4. takes the session row FOR UPDATE;
--   5. takes the request row FOR UPDATE and re-reads it authoritatively
--      under all three locks -- this is the row every subsequent
--      decision is made from;
--   6. proceeds exactly as before.
--
-- WHY THE UNLOCKED PRE-READ IS SAFE, AND WHY IT IS NOT A TOCTOU BUG.
-- Step 2 reads ai_session_requests WITHOUT a lock purely to learn which
-- relationship and session to lock -- it is a lock-target lookup, not
-- an authorization or state decision. NOTHING is decided from it. Every
-- guard (worker_token / actor match, existence, state, ordinals, the
-- consent and membership gates, the staging row) is evaluated in step 5
-- and after, from the row re-read under FOR UPDATE. This is the same
-- two-phase shape end_ai_session and purge_ai_session_content already
-- use: both read ai_sessions.relationship_id unlocked, lock, then
-- re-read the session row FOR UPDATE and re-check its state, with an
-- explicit comment that the unlocked snapshot must not be trusted.
--
-- A request row's session_id is immutable in this schema (no RPC ever
-- updates it; the only writes to it are the INSERT in
-- admit_ai_session_generation), and a session's relationship_id is
-- likewise never updated, so the pre-read cannot send us to the wrong
-- lock. Even if it could, the re-read under lock is what the function
-- acts on.
--
-- WHY THE SESSION ROW IS LOCKED EVEN THOUGH THESE RPCs DO NOT
-- AUTHORIZE ON SESSION STATE. The lock is not there to read state --
-- it is there because these functions WRITE the session row (the
-- revision bump) and take FOR KEY SHARE on it (the child INSERT)
-- regardless. Acquiring it explicitly, FIRST, is what makes the
-- acquisition ORDER deterministic instead of statement-order-dependent.
-- An exclusive FOR UPDATE taken before the implicit FOR KEY SHARE
-- subsumes it: the weaker lock is already held by the same transaction
-- and the FK check does not block.
--
-- WHAT IS DELIBERATELY NOT ADDED: no session-state gate. These RPCs do
-- not currently refuse to complete into a 'closed' session, and this
-- migration does not change that. Adding such a gate would be a
-- behaviour change these three have never had, it would need its own
-- contracts and error messages, and it is not what the deadlock is.
-- The epoch/revision fence the spec describes for that purpose is
-- separately tracked (final review's N3). This migration changes LOCK
-- ORDER AND NOTHING ELSE -- every guard, every error message, every
-- ordinal computation, every returned value and every gate position is
-- preserved byte-for-byte below.
--
-- ======================================================================
-- WHY ONLY THREE FUNCTIONS
-- ======================================================================
--
-- discard_ai_session_nearby_staging is NOT re-defined. The final review
-- lists a `discard x publish` deadlock, which is real, but it is not a
-- session/request inversion: discard touches ai_session_staging and
-- ai_session_requests only, never ai_sessions, and once publish takes
-- the relationship advisory lock FIRST the two serialize on that lock
-- before either reaches a row. Re-measured after this fix (see the
-- trial table in the task report): publish x discard is deadlock-free
-- without touching discard. Giving discard its own advisory lock would
-- be a further change to a function this migration has no finding
-- against; left alone deliberately.
--
-- end_ai_session and purge_ai_session_content already take
-- 1 -> 3 -> 4. They are byte-identical to 20260953090100 and
-- 20260953110000 respectively.
--
-- ======================================================================
-- FIRST-STATEMENT VALIDATION (Global Constraint)
-- ======================================================================
--
-- The Global Constraint requires every SECURITY DEFINER function to
-- validate its actor parameter non-NULL as its first statement. Two of
-- these three are WORKER-TOKEN-authenticated rather than
-- actor-authenticated, so what they validate differs, and this
-- migration preserves exactly what each already had rather than
-- inventing new guards or new messages:
--
--   * commit_ai_session_ideas_turn(p_worker_token, p_request_id, ...)
--     has NO actor parameter. Its first statement is the combined
--     lookup `WHERE id = p_request_id AND worker_token =
--     p_worker_token`, whose failure raises the existing
--     'Request not found for this worker token'. A NULL worker token
--     makes that predicate NULL, matches nothing, and raises -- so the
--     token IS validated non-NULL by the same statement that
--     authenticates it. Unchanged here, and now split across the
--     pre-read (which carries the same AND worker_token = ... predicate)
--     and the locked re-read (which carries it again), so a NULL or
--     wrong token is rejected BEFORE any lock is taken as well as after.
--
--   * stage_ai_session_nearby_result(p_worker_token, p_request_id, ...)
--     is identical in shape, raising its existing
--     'Request not found or not in a stageable state'.
--
--   * publish_ai_session_nearby_result(p_actor_id, p_request_id) DOES
--     take an actor and DOES have the canonical guard
--     `IF p_actor_id IS NULL THEN RAISE EXCEPTION 'Not authenticated';`
--     as its literal first statement. That guard is preserved as the
--     first statement, ahead of the new lock-target lookup.
--
-- ======================================================================
-- PRESERVED EXACTLY (each pinned by an existing or new contract)
-- ======================================================================
--
--   * publish's membership + consent gate AND ITS POSITION: the
--     already-'committed' idempotent replay is still answered BEFORE
--     the gate (deliberate, Task 11 / Task 10's F1 re-review: a
--     post-withdrawal retry of a publish that already happened must not
--     look like a failed publish), there is still NO WRITE before the
--     gate, and both gates still precede the turns INSERT they guard.
--     Pinned structurally by ai_session_purge_contracts.sql Contract 11.
--   * Ordinal parity 2n-1 (user) / 2n (Attune), both derived from the
--     SAME v_request.attempt_n -- never two counters.
--   * Idempotency on retry of the same request_id in all three.
--   * Every error message, verbatim. Several contracts match specific
--     message text; the strings below are unchanged.
--   * Return shapes: (committed, user_ordinal, attune_ordinal) for
--     commit and publish, void for stage.
--   * mark_ai_assistant_usage_outcome's existing arguments, including
--     the mode discriminator (1 for ideas, 2 for nearby).
-- ======================================================================


-- ----------------------------------------------------------------------
-- commit_ai_session_ideas_turn -- lock order corrected.
--
-- LOCK ORDER: relationship advisory lock -> ai_sessions row FOR UPDATE
-- -> ai_session_requests row FOR UPDATE. The ai_session_turns INSERT's
-- implicit FOR KEY SHARE on ai_sessions is subsumed by the FOR UPDATE
-- already held. No quota advisory lock appears in this path and none is
-- needed: that lock lives inside reserve_ai_assistant_quota (the
-- admission path), and mark_ai_assistant_usage_outcome -- the only
-- quota function this path calls -- takes no advisory lock. So this
-- acquires a strict PREFIX of the documented order, exactly as
-- end_ai_session does.
CREATE OR REPLACE FUNCTION public.commit_ai_session_ideas_turn(
  p_worker_token uuid,
  p_request_id uuid,
  p_user_instruction text,
  p_reply_text text,
  p_proposal jsonb
) RETURNS TABLE (committed boolean, user_ordinal int, attune_ordinal int)
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
    -- Idempotent replay: return the same ordinals, insert nothing.
    RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int;
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
  UPDATE public.ai_sessions SET revision = revision + 1 WHERE id = v_request.session_id;

  PERFORM public.mark_ai_assistant_usage_outcome(v_request.actor_id, p_request_id, 'succeeded', 1::smallint);

  RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int;
END;
$$;
REVOKE ALL ON FUNCTION public.commit_ai_session_ideas_turn(uuid, uuid, text, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_ai_session_ideas_turn(uuid, uuid, text, text, jsonb)
  TO service_role;


-- ----------------------------------------------------------------------
-- stage_ai_session_nearby_result -- lock order corrected.
--
-- This is the one where the inversion was INVISIBLE to an explicit-lock
-- audit: the superseded body took the request row FOR UPDATE, then read
-- ai_sessions.expires_at with a PLAIN unlocked SELECT, and its only
-- session-row lock was the implicit FOR KEY SHARE taken by the
-- ai_session_staging INSERT's FK check. One explicit lock, two actual
-- locks, inverted.
--
-- The session row's FOR UPDATE now does double duty: it takes LOCK 2
-- and reads expires_at in the same statement, so there is no second,
-- unlocked read of the same row to drift from it.
CREATE OR REPLACE FUNCTION public.stage_ai_session_nearby_result(
  p_worker_token uuid, p_request_id uuid, p_reply_text text, p_sources jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.ai_session_requests;
  v_session_expiry timestamptz;
  v_session_id uuid;
  v_relationship_id uuid;
BEGIN
  -- Lock-target lookup ONLY -- unlocked, decides nothing. Same
  -- worker_token predicate and same message as the re-read below.
  SELECT rq.session_id, se.relationship_id
  INTO v_session_id, v_relationship_id
  FROM public.ai_session_requests rq
  JOIN public.ai_sessions se ON se.id = rq.session_id
  WHERE rq.id = p_request_id AND rq.worker_token = p_worker_token;
  IF v_relationship_id IS NULL THEN
    RAISE EXCEPTION 'Request not found or not in a stageable state';
  END IF;

  -- LOCK 1: the relationship advisory lock.
  PERFORM pg_advisory_xact_lock(hashtext(v_relationship_id::text));

  -- LOCK 2: the session row, FOR UPDATE -- and the expires_at read in
  -- the same statement, under the lock. The superseded body read
  -- expires_at unlocked AFTER taking the request row, which was both
  -- the inversion and an unlocked read of a row this transaction goes
  -- on to lock implicitly anyway.
  SELECT s.expires_at INTO v_session_expiry
  FROM public.ai_sessions s WHERE s.id = v_session_id FOR UPDATE;

  -- LOCK 3: the request row, re-read authoritatively under both locks
  -- above. The state check is made from THIS row.
  SELECT * INTO v_request FROM public.ai_session_requests
  WHERE id = p_request_id AND worker_token = p_worker_token
  FOR UPDATE;
  IF v_request.id IS NULL OR v_request.state != 'started' THEN
    RAISE EXCEPTION 'Request not found or not in a stageable state';
  END IF;

  INSERT INTO public.ai_session_staging (session_id, request_id, requester_id, reply_text, sources, expires_at)
  VALUES (
    v_request.session_id, p_request_id, v_request.actor_id, p_reply_text, p_sources,
    LEAST(now() + interval '2 minutes', COALESCE(v_session_expiry, now() + interval '2 minutes'))
  )
  ON CONFLICT (session_id, request_id) DO NOTHING;

  UPDATE public.ai_session_requests SET state = 'staged' WHERE id = p_request_id;
END;
$$;
REVOKE ALL ON FUNCTION public.stage_ai_session_nearby_result(uuid, uuid, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.stage_ai_session_nearby_result(uuid, uuid, text, jsonb)
  TO service_role;


-- ----------------------------------------------------------------------
-- publish_ai_session_nearby_result -- lock order corrected, Task 11's
-- membership + consent gate and its POSITION preserved exactly.
--
-- This body is Task 11's (20260953110000), with the lock sequence
-- inserted ahead of the request-row read and NOTHING ELSE changed:
--
--   * `IF p_actor_id IS NULL THEN RAISE 'Not authenticated'` is STILL
--     the literal first statement.
--   * The already-'committed' idempotent replay is STILL answered
--     BEFORE the membership and consent gates (Task 11 / Task 10's F1
--     re-review: deliberate, so a post-withdrawal retry of a publish
--     that already happened does not look like a failed publish and
--     drive the caller to publish again). There is STILL no write of
--     any kind before the gates.
--   * Both gates STILL precede the ai_session_turns INSERT they guard
--     (pinned structurally by ai_session_purge_contracts.sql Contract
--     11, which compares positions on the comment-stripped live body).
--   * The author check `v_staging.requester_id != p_actor_id` is STILL
--     present and STILL ahead of the gates (spec §7.2's asymmetry).
--   * Every error message is verbatim.
--
-- Task 11 already performed a `SELECT se.relationship_id FROM
-- public.ai_sessions se` lookup for its consent gate, in the middle of
-- the function. That lookup MOVES to the top -- it is now the
-- lock-target lookup -- and v_relationship_id is reused by the gates
-- unchanged, so the gates read exactly the value they read before. The
-- 'Session unavailable' raise that guarded a NULL relationship moves
-- with it and keeps its message.
CREATE OR REPLACE FUNCTION public.publish_ai_session_nearby_result(
  p_actor_id uuid, p_request_id uuid
) RETURNS TABLE (committed boolean, user_ordinal int, attune_ordinal int)
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
BEGIN
  -- FIRST STATEMENT, unchanged: the Global Constraint's NULL-actor
  -- guard. Ahead of the lock-target lookup, as it must be.
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Lock-target lookup ONLY -- unlocked, decides nothing except which
  -- rows to lock. This is Task 11's own `SELECT se.relationship_id`
  -- consent-gate lookup, hoisted to the top and widened by session_id;
  -- its 'Session unavailable' raise comes with it. 'Request not found'
  -- is still raised for an unknown request, from the locked re-read
  -- below, so neither message changes meaning.
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
  IF v_request.state = 'committed' THEN
    RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int;
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
  UPDATE public.ai_sessions SET revision = revision + 1 WHERE id = v_request.session_id;
  PERFORM public.mark_ai_assistant_usage_outcome(v_request.actor_id, p_request_id, 'succeeded', 2::smallint);

  RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int;
END;
$$;
REVOKE ALL ON FUNCTION public.publish_ai_session_nearby_result(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_ai_session_nearby_result(uuid, uuid)
  TO service_role;


-- ======================================================================
-- MIGRATION PROVENANCE -- see 20260953090100's block for the full
-- table. After this file:
--
--   public.commit_ai_session_ideas_turn
--     Task 7   20260953070000_ai_session_commit_ideas_rpc.sql  (original)
--     lock fix 20260953120000  (THIS FILE) <-- WINS
--       Adds the relationship advisory lock and the session row lock,
--       both AHEAD of the request row -- the documented order, which
--       the original inverted. Marker: pg_advisory_xact_lock, which the
--       superseded body does not contain at all.
--
--   public.stage_ai_session_nearby_result
--     Task 8   20260953080000_ai_session_nearby_staging_rpcs.sql (original)
--     lock fix 20260953120000  (THIS FILE) <-- WINS
--       Same correction. Marker: pg_advisory_xact_lock, absent from the
--       superseded body; and the expires_at read is now FOR UPDATE.
--
--   public.publish_ai_session_nearby_result
--     Task 8   20260953080000  (original)
--     Task 11  20260953110000  (added the membership + consent gate)
--     lock fix 20260953120000  (THIS FILE) <-- WINS
--       Builds on Task 11's body: the gate and its pre-gate idempotent
--       replay position are PRESERVED, and the lock sequence is added
--       ahead of the request-row read. Two markers now discriminate:
--       pg_advisory_xact_lock (this file) AND
--       ai_processing_consent_events (Task 11's gate, which must NOT
--       have been lost). ai_session_purge_contracts.sql Contract 11
--       asserts the second and the gate's position;
--       ai_session_read_authorization_contracts.sql Contract 9 and the
--       new lock-order contracts in
--       ai_session_commit_ideas_contracts.sql and
--       ai_session_nearby_staging_contracts.sql assert the first.
--
--   public.discard_ai_session_nearby_staging
--     Task 8   20260953080000  <-- STILL WINS (not re-defined here;
--                                  see "WHY ONLY THREE FUNCTIONS")
--   public.end_ai_session, public.share_ai_session_turn
--     fix r1   20260953090100  <-- STILL WIN (not re-defined here)
--   public.purge_ai_session_content, public.purge_expired_ai_sessions
--     Task 11  20260953110000  <-- STILL WIN (not re-defined here)
--
-- A future change to any function above must be made in a NEW migration
-- that sorts after the winning file, not in the original. A re-applied
-- 20260953070000, 20260953080000 or 20260953110000, alone and last,
-- would silently revert this lock-order fix; the structural contracts
-- named above are what fail loudly when that happens.
-- ======================================================================
