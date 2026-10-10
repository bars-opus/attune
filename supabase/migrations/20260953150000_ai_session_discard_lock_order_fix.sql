-- Task 1 FIX ROUND 1: the lock-order inversion that SURVIVED
-- 20260953120000 -- discard_ai_session_nearby_staging against
-- publish_ai_session_nearby_result, over the ai_session_staging row.
-- Spec §6.1, §7.1, §8.2.2, and the plan's Global Constraints, which fix
-- the lock order and say in those words that a mixed order "is a merge
-- blocker".
--
-- ======================================================================
-- THIS MIGRATION SUPERSEDES ONE EARLIER MIGRATION.
--
-- It re-defines, by CREATE OR REPLACE:
--
--   * public.discard_ai_session_nearby_staging
--       -- originally AND ONLY 20260953080000 (Plan B Task 8).
--
-- Established by grep, not assumed: 20260953080000 holds the sole
-- `CREATE OR REPLACE FUNCTION public.discard_ai_session_nearby_staging`
-- in the whole migration set. The two other migrations that name the
-- function -- 20260953110000 (Task 11) and 20260953120000 (Task 1's
-- lock-order fix) -- mention it only in COMMENTS: 20260953110000 in
-- passing, and 20260953120000's "WHY ONLY THREE FUNCTIONS" block and
-- MIGRATION PROVENANCE table explicitly recording that it left this
-- function alone ("Task 8 20260953080000 <-- STILL WINS"). Neither
-- re-defines it. So the pre-this-file winning definition is Task 8's,
-- and THIS FILE now wins over it.
--
-- It re-defines NOTHING ELSE. In particular it does NOT touch
-- public.publish_ai_session_nearby_result,
-- public.stage_ai_session_nearby_result,
-- public.commit_ai_session_ideas_turn (all three owned by Task 1's
-- 20260953120000), public.end_ai_session, public.purge_ai_session_content,
-- public.purge_expired_ai_sessions or
-- public.admit_ai_session_generation (Task 3's 20260953140000). The
-- defect below is DISCARD's -- it is the only function in the schema
-- that holds two of the three session row-classes while taking no
-- relationship advisory lock -- so the fix belongs here. See
-- "WHY DISCARD AND NOT PUBLISH" below.
--
-- Per this plan's additive-migrations discipline (established by Task
-- 6's fix round 20260953060100 and followed by 20260953090100,
-- 20260953100100, 20260953110000, 20260953120000 and 20260953140000),
-- no earlier migration's logic is edited in place. Later migrations
-- win; the earlier files stay as the record of what shipped when. A
-- MIGRATION PROVENANCE block at the bottom of this file records the new
-- winner, and
-- supabase/tests/ai_session_read_authorization_contracts.sql Contract 9
-- is the executable form of that note.
-- ======================================================================
--
--
-- ======================================================================
-- THE DEFECT: THE DEADLOCK PAIR 20260953120000 DID NOT CLOSE
-- ======================================================================
--
-- Task 1's review (Finding 1, Critical) found that
-- publish_ai_session_nearby_result x discard_ai_session_nearby_staging
-- STILL deadlocks, over the ai_session_staging row, and that Task 1's
-- own report had recorded the pair as fixed.
--
-- The two functions acquire the staging row and the request row in
-- OPPOSITE orders, and discard takes NO relationship advisory lock, so
-- the advisory lock 20260953120000 added to publish SERIALIZES NOTHING
-- against it:
--
--   publish (20260953120000)              discard (20260953080000)
--     pg_advisory_xact_lock(rel)            (NO advisory lock)
--     ai_sessions        FOR UPDATE         (never touches ai_sessions)
--     ai_session_requests FOR UPDATE  <-1   SELECT ai_session_staging
--     SELECT v_staging (UNLOCKED)            (unlocked)
--     ... membership + consent gates ...    DELETE ai_session_staging <-1
--     INSERT ai_session_turns               UPDATE ai_session_requests <-2
--     DELETE ai_session_staging       <-2
--
-- publish: request row -> staging row. discard: staging row -> request
-- row. A textbook cycle. publish holds the request row across ~74 lines
-- (three gate SELECTs among them) before it needs the staging row, which
-- is what makes the window reachable.
--
-- TASK 1'S REASONING FOR LEAVING IT WAS WRONG, and is recorded here so
-- it is not repeated: its Concern 4 argued that "once publish takes the
-- relationship advisory lock first the two serialize on that lock". They
-- do not. discard never takes that lock, so there is nothing for it to
-- serialize on. Its 12 clean post-fix trials were the expected result of
-- a race whose window is SUB-MILLISECOND, not evidence of a fix -- the
-- reviewer got 0/70 the same way before adding load.
--
-- MEASURED, by the reviewer, on the FIXED publish body (20260953120000)
-- against the unmodified discard, real RPCs in two concurrent psql
-- backends, a fresh fixture per trial:
--
--   window                                      trials  deadlocks
--   none, idle server                           30 + 40      0
--   none, 20 additional backends of query load     40      1
--   1 ms gap in discard's DELETE->UPDATE window     15     14
--   10 ms gap                                       15     15
--   50 ms gap                                       15     15
--   250 ms gap                                      20     20
--
-- A 1 ms gap gives 14/15. That is well inside normal scheduler and
-- WAL-flush jitter -- i.e. this is a production deadlock, not a
-- laboratory one. The dispatching agent independently reproduced it at
-- 1/12 with a 10 ms gap.
--
-- THE VICTIM IS THE USER. The reviewer's capture:
--
--   ERROR:  deadlock detected
--   CONTEXT:  while updating tuple (13,49) in relation "ai_session_requests"
--   SQL statement "UPDATE public.ai_session_requests SET state = 'cancelled' WHERE id = p_request_id"
--   PL/pgSQL function discard_ai_session_nearby_staging(uuid,uuid) line 19
--
-- That is the user's own "discard this Nearby result" action failing
-- with a raw SQLSTATE 40P01 -- the same user-facing failure shape the
-- final review's N1 called Critical for end_ai_session, which is the
-- defect 20260953120000 exists to fix.
--
-- NOT A REGRESSION. Pre-fix publish on the identical 1 ms race gave
-- 13/15. The pair was always broken; 20260953120000 neither caused nor
-- worsened it -- it simply did not touch it. It is nonetheless a merge
-- blocker, because it is on the brief's own list of four known
-- deadlocking pairs and was reported as fixed.
--
--
-- ======================================================================
-- WHY DISCARD AND NOT PUBLISH
-- ======================================================================
--
-- The inversion could be closed from either side: give discard the
-- standard prefix, or have publish take the staging row FOR UPDATE where
-- it currently reads it unlocked. Both work. This file takes the FIRST,
-- per the plan ledger's Ruling 7, for three reasons:
--
--   1. It makes discard CONFORM to the documented order, like every
--      other writer in the chain, instead of adding a second lock class
--      to a function that is already correct.
--   2. It removes the ONLY remaining function in the schema that holds
--      two of the three session row-classes with NO advisory lock. The
--      reviewer found this finding by a structural sweep -- enumerate
--      every function that locks or writes ai_sessions /
--      ai_session_requests / ai_session_staging, flag those doing so
--      without the advisory lock -- and that query returned exactly one
--      row, discard, which then raced and confirmed. After this file
--      that query returns ZERO rows, which is what makes the discipline
--      CHECKABLE going forward rather than re-derivable only by racing.
--   3. 20260953120000's three completion RPCs stay byte-identical, so
--      nothing re-opens the verified work of Task 1 or Task 11's
--      consent gate.
--
-- THE KEY IS REACHABLE, verified rather than assumed:
--   ai_session_staging.session_id -> ai_sessions.relationship_id
-- ai_session_staging carries `session_id uuid NOT NULL REFERENCES
-- public.ai_sessions(id)` and PRIMARY KEY (session_id, request_id)
-- (20260953020000), so one lookup off the row discard already reads
-- yields both the session to lock and the relationship to key the
-- advisory lock on. That is the same single lookup publish performs.
--
--
-- ======================================================================
-- THE LOCK ORDER, AND WHAT CHANGED
-- ======================================================================
--
-- The order is fixed, non-negotiable, and identical for every function
-- in this chain:
--
--   1. relationship advisory lock  pg_advisory_xact_lock(hashtext(rel))
--   2. quota advisory lock         (inside reserve_ai_assistant_quota,
--                                   ADMISSION path only -- absent here,
--                                   correctly: discard calls only
--                                   mark_ai_assistant_usage_outcome,
--                                   which takes no advisory lock)
--   3. session row lock            SELECT ... FOR UPDATE on ai_sessions
--   4. request row lock            SELECT ... FOR UPDATE on
--                                  ai_session_requests
--
-- This file gives discard a strict PREFIX of that order (1 -> 3 -> 4,
-- element 2 legitimately absent) -- exactly what end_ai_session,
-- purge_ai_session_content and 20260953120000's three completion RPCs
-- do.
--
-- BEFORE (20260953080000), implicit locks included:
--
--   #  statement                                      lock
--   1  SELECT requester_id FROM ai_session_staging     NONE (unlocked)
--   2  DELETE FROM ai_session_staging                  staging row, FIRST
--   3  UPDATE ai_session_requests                      request row, SECOND
--   4  mark_ai_assistant_usage_outcome                 ai_assistant_usage row
--
--   Advisory locks: NONE. ai_sessions: never locked at all, not even
--   implicitly -- discard only DELETEs from a child table, and a DELETE
--   takes no FK lock on the parent (only an INSERT or a key UPDATE does).
--   Order: staging -> request. That is the inversion.
--
-- AFTER (this file), implicit locks included:
--
--   #  statement                                      lock
--   1  SELECT requester_id, session_id, se.relationship_id
--        FROM ai_session_staging JOIN ai_sessions      NONE (unlocked
--                                                      lock-target lookup)
--   2  pg_advisory_xact_lock(hashtext(rel))            LOCK 1, advisory
--   3  SELECT 1 FROM ai_sessions ... FOR UPDATE        LOCK 2, session row
--   4  SELECT ... FROM ai_session_requests ... FOR UPDATE  LOCK 3, request row
--   5  re-read ai_session_staging under the locks      staging row (now
--                                                      LAST of the three
--                                                      session classes)
--   6  DELETE FROM ai_session_staging                  staging row (held)
--   7  UPDATE ai_session_requests                      request row (held)
--   8  mark_ai_assistant_usage_outcome                 ai_assistant_usage row
--
--   Order: relationship -> session row -> request row -> staging row.
--   The staging row is now acquired AFTER the request row, which is the
--   order publish takes, and both now take the relationship advisory
--   lock FIRST, so they serialize on it before either touches a row.
--
-- THE UNLOCKED PRE-READ DECIDES NOTHING, the same design Task 1's
-- review verified for the three completion RPCs (its §1, six vectors,
-- "No TOCTOU is introduced"). It yields only (session_id,
-- relationship_id) -- lock keys -- plus the idempotent-no-op test on
-- row EXISTENCE. Every value this function ACTS on, the requester_id
-- its authorization compares included, comes from the re-read under the
-- locks at #5. A row that vanishes between #1 and #5 takes the same
-- idempotent RETURN as a row that was already gone at #1; a requester_id
-- that somehow differed would be judged on the locked value. That is why
-- the authorization check moved BELOW the locks rather than staying at
-- the top: under the old body it was the only read, and it was unlocked.
--
-- WHY NOT ALSO LOCK THE STAGING ROW EXPLICITLY FOR UPDATE at #5: the
-- subsequent DELETE takes the row-exclusive lock on exactly that row
-- anyway, and no statement between #5 and #6 can yield. Adding FOR
-- UPDATE would change nothing about the acquisition order while breaking
-- the `FOR UPDATE` count assertion that keeps the structural contract's
-- markers discriminating. The ORDER is what the deadlock turned on and
-- the order is now fixed.
--
--
-- ======================================================================
-- BEHAVIOUR PRESERVED EXACTLY -- NOTHING BUT LOCK ORDER CHANGES
-- ======================================================================
--
--   * RETURNS void                                     unchanged
--   * SECURITY DEFINER, SET search_path = public       unchanged
--   * REVOKE ALL / GRANT EXECUTE TO service_role       unchanged
--   * idempotent silent RETURN when no staging row
--     exists (already discarded / published / expired) unchanged, and
--     now evaluated BOTH on the pre-read and on the locked re-read
--   * requester-only authorization, raising the
--     VERBATIM 'Only the requester may discard their
--     own staged result'                               unchanged text,
--     now judged on the LOCKED read
--   * state = 'cancelled' on ai_session_requests       unchanged
--   * mark_ai_assistant_usage_outcome(..., 'succeeded',
--     2) -- terminal, COUNTED, never a quota refund:
--     provider_started_at is already set (the request
--     reached 'staged' only via
--     claim_ai_session_dispatch), so this outcome must
--     remain counted and must never be
--     'cancelled'/'rejected' (spec §8.2.2)             unchanged
--
-- NO NULL-ACTOR GUARD IS ADDED, deliberately. The Global Constraint
-- requires every SECURITY DEFINER function to validate its actor
-- parameter non-NULL as its first statement; discard has never had an
-- explicit `IF p_actor_id IS NULL` and this file does not add one,
-- because adding a guard is a BEHAVIOUR change (a new raise on a path
-- that currently returns silently) and this fix round is a lock-order
-- fix. The constraint is satisfied in substance rather than in form:
-- with a NULL p_actor_id the authorization comparison
-- `v_actor != p_actor_id` is NULL, so the IF does not take its true
-- branch, falls through, and -- this is the part that matters -- the
-- ensuing mark_ai_assistant_usage_outcome(p_actor_id, ...) raises
-- 'Not authenticated' from ITS first statement before this transaction
-- can commit. A NULL actor therefore cannot discard anything, before or
-- after this file. Recorded as a deliberate non-change, not an
-- oversight; see the task report's concern list.
-- ======================================================================

CREATE OR REPLACE FUNCTION public.discard_ai_session_nearby_staging(
  p_actor_id uuid, p_request_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid;
  v_session_id uuid;
  v_relationship_id uuid;
BEGIN
  -- Lock-target lookup ONLY -- unlocked, and it decides nothing except
  -- which rows to lock and whether there is anything to do at all. The
  -- authorization comparison is NOT made here: it is made on the
  -- re-read under the locks below. This is the same shape
  -- 20260953120000 gave the three completion RPCs, and the same reason
  -- -- the advisory lock needs the relationship id, and the
  -- relationship id is only reachable through the row being discarded.
  --
  -- ai_session_staging.session_id REFERENCES ai_sessions(id) NOT NULL
  -- (20260953020000), so this join is total for any staging row that
  -- exists; a LEFT JOIN would be dead code.
  SELECT st.session_id, se.relationship_id
  INTO v_session_id, v_relationship_id
  FROM public.ai_session_staging st
  JOIN public.ai_sessions se ON se.id = st.session_id
  WHERE st.request_id = p_request_id;

  IF v_session_id IS NULL THEN
    RETURN; -- already discarded/published/expired -- idempotent no-op
  END IF;

  -- LOCK 1: the relationship advisory lock. THE FIX. Without it, this
  -- function serialized against nothing -- publish takes this lock
  -- first and discard took no advisory lock at all, so the two still
  -- formed a cycle over the staging and request rows (14/15 deadlocks
  -- at a 1 ms window). Keyed on the RELATIONSHIP, as every other
  -- function in this chain is: a per-session or per-request key would
  -- serialize against none of them and the deadlock would return.
  PERFORM pg_advisory_xact_lock(hashtext(v_relationship_id::text));

  -- LOCK 2: the session row, before the request row. discard does not
  -- otherwise touch ai_sessions -- it neither updates it nor INSERTs
  -- into a child table, so it takes no implicit FK lock on the parent
  -- either. The lock is taken anyway, and explicitly, so that this
  -- function occupies the documented order at the SAME points as
  -- end_ai_session, purge_ai_session_content and the three completion
  -- RPCs. A participant that skips an element of a lock order is how
  -- the order stops being a total order, which is precisely the defect
  -- being fixed one level up.
  PERFORM 1 FROM public.ai_sessions WHERE id = v_session_id FOR UPDATE;

  -- LOCK 3: the request row. This is the row publish holds across its
  -- gates while waiting for the staging row, and the row the old body
  -- took SECOND (after the staging DELETE) -- the inversion. Taking it
  -- here, under the advisory lock and after the session row, is what
  -- closes the cycle.
  PERFORM 1 FROM public.ai_session_requests WHERE id = p_request_id FOR UPDATE;

  -- The staging row, re-read AUTHORITATIVELY under all three locks.
  -- Everything this function acts on comes from here, not from the
  -- pre-read: the idempotent-no-op test (a row that vanished while this
  -- transaction waited for the locks is indistinguishable from one that
  -- was never there, and takes the same silent RETURN) and the
  -- requester authorization.
  SELECT requester_id INTO v_actor
  FROM public.ai_session_staging WHERE request_id = p_request_id;
  IF v_actor IS NULL THEN
    RETURN; -- already discarded/published/expired -- idempotent no-op
  END IF;
  IF v_actor != p_actor_id THEN
    RAISE EXCEPTION 'Only the requester may discard their own staged result';
  END IF;

  DELETE FROM public.ai_session_staging WHERE request_id = p_request_id;
  -- Terminal, counted, no partner pair (spec §8.2.2) -- NOT a quota
  -- release. provider_started_at is already set for this request (it
  -- reached 'staged' only via claim_ai_session_dispatch), so this
  -- outcome must remain a counted terminal state, never 'cancelled'/
  -- 'rejected'.
  UPDATE public.ai_session_requests SET state = 'cancelled' WHERE id = p_request_id;
  PERFORM public.mark_ai_assistant_usage_outcome(p_actor_id, p_request_id, 'succeeded', 2::smallint);
END;
$$;
REVOKE ALL ON FUNCTION public.discard_ai_session_nearby_staging(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.discard_ai_session_nearby_staging(uuid, uuid)
  TO service_role;


-- ======================================================================
-- MIGRATION PROVENANCE -- see 20260953090100's block for the full
-- table, and 20260953120000's for the completion RPCs. After this file:
--
--   public.discard_ai_session_nearby_staging
--     Task 8   20260953080000_ai_session_nearby_staging_rpcs.sql  (original,
--                and until this file the SOLE definition -- established
--                by grep: 20260953110000 and 20260953120000 name the
--                function only in comments)
--     fix r1   20260953150000  (THIS FILE) <-- WINS
--       Adds the relationship advisory lock, the session row lock and
--       the request row lock, all AHEAD of the staging row -- the
--       documented order, which the original inverted by taking the
--       staging row first and no advisory lock at all. Marker:
--       pg_advisory_xact_lock, which the superseded body does not
--       contain at all. Asserted by
--       supabase/tests/ai_session_nearby_staging_contracts.sql
--       Contract 6 (structural lock order) and
--       supabase/tests/ai_session_read_authorization_contracts.sql
--       Contract 9 (supersession ordering, 7th marker). Raced by
--       supabase/tests/ai_session_completion_concurrent_test.sh
--       (publish x discard, both orderings, with a configurable gap in
--       discard's DELETE->UPDATE window).
--
--   public.commit_ai_session_ideas_turn,
--   public.stage_ai_session_nearby_result,
--   public.publish_ai_session_nearby_result
--     Task 1   20260953120000  <-- STILL WIN (not re-defined here)
--   public.admit_ai_session_generation
--     Task 3   20260953140000  <-- STILL WINS (not re-defined here)
--   public.end_ai_session, public.share_ai_session_turn
--     fix r1   20260953090100  <-- STILL WIN (not re-defined here)
--   public.purge_ai_session_content, public.purge_expired_ai_sessions
--     Task 11  20260953110000  <-- STILL WIN (not re-defined here)
--
-- A future change to discard_ai_session_nearby_staging must be made in a
-- NEW migration that sorts after THIS file, not in 20260953080000. A
-- re-applied 20260953080000, alone and last, would silently revert this
-- fix AND Task 1's stage/publish fix; the structural contracts named
-- above are what fail loudly when that happens.
-- ======================================================================
