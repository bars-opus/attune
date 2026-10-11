-- Nearby staging: stage -> publish (or discard). Requester-only
-- publish; discard never refunds quota. Spec §6.1, §7.1, §8.2.2.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_nearby_staging_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000020';
  v_user_a uuid := 'b1000000-0000-0000-0000-000000000021';
  v_user_b uuid := 'b1000000-0000-0000-0000-000000000022';
  v_session uuid;
  v_admit record;
  v_row record;
  v_usage_after text;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'stage_a@t.test'), (v_user_b, 'stage_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550016001', 'A'), (v_user_b, '+15550016002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  -- BOTH partners grant AI-processing consent at the current policy
  -- version. Added by Task 11: publish_ai_session_nearby_result now
  -- enforces the membership + consent gate that spec §7.2 requires and
  -- that it never had (20260953110000, routed from Task 10's Ruling 8
  -- -- the WRITE leg of the leak Task 10's F1 closed on the read side).
  --
  -- This fixture previously set up NO consent at all and still passed,
  -- because no write-path RPC in this plan has ever checked consent --
  -- only the Task 10 read RPCs did. That is why this setup is an
  -- addition rather than a correction: the fixture was incomplete
  -- relative to §7.2, not wrong relative to the code as it then stood.
  --
  -- clock_timestamp(), never now(): now() is frozen per transaction, so
  -- events written in one DO block would share an identical created_at
  -- and the consent lookup's tiebreak would fall to `id DESC` on a
  -- random uuid, making any consent-ordering assertion a coin flip.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'nearby', 'shared', NULL, false, NULL
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'nearby:fp');
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);

  -- Contract 1: staging succeeds; no turn rows exist yet.
  PERFORM public.stage_ai_session_nearby_result(
    v_admit.worker_token, v_admit.request_id, 'three places nearby', '[]'::jsonb
  );
  IF (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session) != 0 THEN
    RAISE EXCEPTION 'EXPLOIT: staging inserted turn rows before publication';
  END IF;
  IF (SELECT state FROM public.ai_session_requests WHERE id = v_admit.request_id) != 'staged' THEN
    RAISE EXCEPTION 'EXPLOIT: request state did not advance to staged';
  END IF;

  -- Contract 2: the PARTNER cannot publish someone else's staged Nearby
  -- result (spec §6.1: only the requester may disclose).
  --
  -- ============ LEDGER CORRECTION -- DO NOT "FIX" THIS ============
  -- The PREDECESSOR plan's Ruling 11 recorded this contract as a BARE
  -- `EXCEPTION WHEN OTHERS` -- a seventh vacuous test. THAT RULING WAS
  -- WRONG. The handler below carries
  -- `IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;`, which is this
  -- suite's standard anti-vacuity guard: the EXPLOIT raise two lines up
  -- fires if the partner's publish SUCCEEDS, and the guard re-raises it
  -- rather than letting the handler swallow it. Without the guard this
  -- contract would pass whether the publish was refused or accepted;
  -- with it, only a refusal passes.
  --
  -- The final whole-branch review MUTATION-PROVED this (an unguarded
  -- copy of the handler lets the exploit through; this one does not)
  -- and audited all 11 plan test files: 28 handlers, EVERY ONE
  -- message-checked or re-raise-guarded. Re-audited by Task 5 of the
  -- merge-blocker plan across 14 files and 52 handlers, same result --
  -- the apparent exceptions are all comments mentioning the string,
  -- structural assertions ABOUT handlers, or over-restriction legs that
  -- raise EXPLOIT unconditionally because the call they wrap is
  -- supposed to SUCCEED.
  --
  -- Recorded here, at the contract itself, so nobody spends a cycle
  -- "fixing" a non-defect on the strength of a superseded ruling. If
  -- you arrived here from Ruling 11: there is no defect. The discipline
  -- holds branch-wide.
  -- ===============================================================
  BEGIN
    PERFORM public.publish_ai_session_nearby_result(v_user_b, v_admit.request_id);
    RAISE EXCEPTION 'EXPLOIT: the non-requester partner published a staged Nearby result';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 3: the requester publishes successfully -> exactly 2 turn
  -- rows at ordinals (1,2), staging row removed.
  SELECT * INTO v_row FROM public.publish_ai_session_nearby_result(v_user_a, v_admit.request_id);
  IF v_row.committed IS DISTINCT FROM true OR v_row.user_ordinal != 1 OR v_row.attune_ordinal != 2 THEN
    RAISE EXCEPTION 'EXPLOIT: publish did not produce ordinals (1,2)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ai_session_staging WHERE request_id = v_admit.request_id) THEN
    RAISE EXCEPTION 'EXPLOIT: staging row survived publication';
  END IF;

  -- Contract 4: discard never refunds quota -- attempt an admission,
  -- stage, discard, and confirm the reservation is still counted
  -- (outcome NOT 'cancelled'/'rejected').
  DECLARE
    v_admit2 record;
  BEGIN
    -- The expected_revision comes from `v_row.session_revision` -- the
    -- value contract 3's publish just returned -- NOT from a literal.
    -- It used to be a literal `2`, with a note that contract 3's
    -- publish "bumped ai_sessions.revision from 1 to 2". Task 2
    -- (20260953170000) replaced it: a hardcoded fence is a test
    -- asserting a number it computed by hand, and when a mutant makes
    -- the revision move unexpectedly such a line dies with a bare
    -- `CONTEXT_CHANGED` that diagnoses nothing. A returned fence
    -- asserts the RPC's own answer and fails in the right place. This
    -- is a test-only change -- no assertion here is altered, and the
    -- value is the same 2 on correct code.
    IF v_row.session_revision IS NULL THEN
      RAISE EXCEPTION
        'SETUP FAILED: contract 3''s publish reported a NULL session_revision, so contract 4 has no fence to admit on. publish_ai_session_nearby_result must disclose the revision it bumped (20260953170000).';
    END IF;
    SELECT * INTO v_admit2 FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, v_row.session_revision, 'nearby:fp-2');
    PERFORM public.claim_ai_session_dispatch(v_admit2.worker_token, v_admit2.request_id);
    PERFORM public.stage_ai_session_nearby_result(v_admit2.worker_token, v_admit2.request_id, 'more places', '[]'::jsonb);
    PERFORM public.discard_ai_session_nearby_staging(v_user_a, v_admit2.request_id);
    SELECT outcome INTO v_usage_after FROM public.ai_assistant_usage WHERE request_id = v_admit2.request_id;
    IF v_usage_after IN ('rejected', 'cancelled') THEN
      RAISE EXCEPTION 'EXPLOIT: discarding a staged Nearby result refunded its already-started quota reservation';
    END IF;
  END;

  RAISE NOTICE 'Nearby staging/publish/discard contracts: all held';
END $$;


-- =====================================================================
-- Contract 5 (merge-blocker fix 20260953120000): THE LOCK ORDER of
-- stage_ai_session_nearby_result AND publish_ai_session_nearby_result,
-- STRUCTURALLY, on the comment-stripped live bodies.
--
-- THE DEFECT THIS PINS. Both took the ai_session_requests row FOR
-- UPDATE as their FIRST lock and only then touched ai_sessions, and
-- took no relationship advisory lock at all. The order is fixed at
-- relationship advisory lock -> quota advisory lock (inside
-- reserve_ai_assistant_quota, admission path only) -> session row ->
-- request row, and end_ai_session, purge_ai_session_content,
-- admit_ai_session_generation and reconcile_ai_session_leases all
-- follow it. Measured on the unmodified shipped bodies, two concurrent
-- backends, no sleeps: stage x end_ai_session deadlocked 10/10 and
-- 9/10 by ordering, publish x end 9/10 and 8/10, stage x
-- purge_expired_ai_sessions 7/10 and 8/10, publish x purge 10/10 and
-- 9/10. In 21 of the 60 purger trials across all three RPCs, the
-- purger's per-session EXCEPTION WHEN OTHERS swallowed the deadlock
-- into a WARNING and left an EXPIRED session at state='active' with
-- its content RETAINED -- spec 8.2.3's five-minute purge-lag target
-- missed silently.
--
-- STAGE IS THE CASE AN EXPLICIT-LOCK AUDIT CANNOT SEE, which is why
-- it gets its own commentary. The superseded body contained NO
-- statement that locked ai_sessions: it read
-- `SELECT expires_at FROM public.ai_sessions WHERE id = ...` with no
-- FOR UPDATE and never updated that table. An audit enumerating
-- explicit FOR UPDATE / UPDATE statements therefore saw stage as
-- taking exactly ONE lock -- and a function holding one lock cannot
-- deadlock. It took TWO: the ai_session_staging INSERT's FK check
-- takes FOR KEY SHARE on the parent ai_sessions row (verified by
-- catalog query -- ai_session_staging, ai_session_turns,
-- ai_session_requests, ai_session_approvals, ai_session_sources and
-- ai_session_publications all carry a FK to ai_sessions). That
-- implicit parent-row lock, acquired AFTER the request row, is the
-- inversion, and it is where the deadlock actually fired. Any lock
-- enumeration for this feature must count implicit parent-row locks
-- taken by child-table INSERTs.
--
-- WHY STRUCTURAL AND NOT BEHAVIOURAL. A deadlock needs two concurrent
-- backends, which a single-transaction SQL contract cannot create --
-- exactly why no committed test caught this for eleven task reviews.
-- The behavioural proof is
-- supabase/tests/ai_session_completion_concurrent_test.sh. This is the
-- cheap always-on guard that the ORDER has not rotted back.
--
-- WHY position() AND NOT A PRESENCE CHECK. A presence check passes a
-- body that contains all three lock statements in the WRONG order --
-- the pre-fix body with an advisory lock bolted on at the end.
--
-- WHY NOT `FROM public.ai_session_requests` AS THE REQUEST MARKER.
-- Both fixed bodies read ai_session_requests TWICE: once unlocked, at
-- the top, purely to resolve which relationship and session to lock
-- (it decides nothing -- every guard is evaluated from the locked
-- re-read), and once FOR UPDATE under both locks. The table name now
-- legitimately appears BEFORE the advisory lock, so a name-keyed
-- assertion would fail on the CORRECT body. Each request-row marker
-- below is the full locked read, giving an absolute position
-- comparable with the others; and the FOR UPDATE count is asserted at
-- exactly 2 so neither marker can silently stop discriminating, and so
-- a lock added to the unlocked pre-read (a third row lock ahead of the
-- advisory lock) fails loudly.
--
-- COMMENTS ARE STRIPPED FIRST. pg_get_functiondef() returns them
-- verbatim and 20260953120000's own comments name all three locks in
-- order, so an unstripped match would be satisfied by the commentary
-- alone even if every lock were deleted (Task 10's finding N1,
-- measured there on 4/4 structural assertions).
-- =====================================================================
CREATE OR REPLACE FUNCTION pg_temp.strip_sql_comments(p_def text)
RETURNS text LANGUAGE sql IMMUTABLE AS $strip$
  SELECT regexp_replace(
           regexp_replace(p_def, '--[^\n]*', '', 'g'),
           '/\*.*?\*/', '', 'gs');
$strip$;

DO $$
DECLARE
  v_def text;
  v_adv int;
  v_sess_fu int;
  v_req_fu int;
  v_fu_count int;
  v_insert int;
BEGIN
  -- ---- stage_ai_session_nearby_result --------------------------------
  v_def := pg_temp.strip_sql_comments(pg_get_functiondef(
    'public.stage_ai_session_nearby_result(uuid, uuid, text, jsonb)'::regprocedure));

  v_adv := position('pg_advisory_xact_lock(hashtext(' in v_def);
  IF v_adv = 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: stage_ai_session_nearby_result takes NO relationship advisory lock. It is the FIRST lock in this plan''s fixed, non-negotiable order, and this RPC races end_ai_session, purge_ai_session_content and admit_ai_session_generation on the same session -- all of which take it first. Without it, stage deadlocked against end_ai_session in 10/10 measured trials. That is Task 8''s superseded body (20260953080000); 20260953120000 WINS.';
  END IF;

  v_fu_count := (length(v_def) - length(replace(v_def, 'FOR UPDATE', ''))) / length('FOR UPDATE');
  IF v_fu_count <> 2 THEN
    RAISE EXCEPTION
      'SETUP FAILED: stage_ai_session_nearby_result has % FOR UPDATE clause(s), expected exactly 2 (the ai_sessions row then the ai_session_requests row). The ordering legs below identify each row lock by its own locked-read text, and a changed count means one of them no longer discriminates, or a THIRD row lock was added -- possibly ahead of the advisory lock, which would reintroduce the inversion. Re-derive the markers.',
      v_fu_count;
  END IF;

  -- LOCK 2: the session row. The FOR UPDATE and the expires_at read are
  -- ONE statement on purpose -- the superseded body read expires_at
  -- unlocked, AFTER taking the request row, which was both the
  -- inversion and an unlocked read of a row the transaction goes on to
  -- lock implicitly anyway.
  v_sess_fu := position('FROM public.ai_sessions s WHERE s.id = v_session_id FOR UPDATE' in v_def);
  IF v_sess_fu = 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: stage_ai_session_nearby_result does not lock the ai_sessions row explicitly. It takes that row''s lock REGARDLESS -- the ai_session_staging INSERT''s FK check takes FOR KEY SHARE on the parent session row -- so the only question is in what ORDER, and an unlocked `SELECT expires_at` leaves that order to be whatever the statement sequence produces. That is the deadlock, and it is invisible to an audit that counts only explicit locks.';
  END IF;

  -- LOCK 3: the request row, by its full locked-read text (absolute
  -- position, comparable with the two above).
  v_req_fu := position('WHERE id = p_request_id AND worker_token = p_worker_token
  FOR UPDATE' in v_def);
  IF v_req_fu = 0 THEN
    RAISE EXCEPTION
      'SETUP FAILED: stage_ai_session_nearby_result has no `WHERE id = p_request_id AND worker_token = p_worker_token FOR UPDATE` locked read. That predicate IS this RPC''s authentication -- it has no actor parameter -- and it must be enforced on the row the function ACTS on, not only on the unlocked lock-target pre-read. Re-derive the marker if the read was legitimately reshaped.';
  END IF;

  IF v_adv > v_sess_fu THEN
    RAISE EXCEPTION
      'LOCK ORDER VIOLATED: stage_ai_session_nearby_result locks the ai_sessions ROW (at %) before the relationship advisory lock (at %). The order is fixed at relationship -> session row -> request row and must never vary; inverting it deadlocks against every RPC that takes the advisory lock first. A change needing a different order is a plan defect, not a local decision.',
      v_sess_fu, v_adv;
  END IF;
  IF v_sess_fu > v_req_fu THEN
    RAISE EXCEPTION
      'LOCK ORDER VIOLATED: stage_ai_session_nearby_result locks the ai_session_requests row (at %) before the ai_sessions row (at %) -- the exact inversion 20260953120000 exists to fix. The order is fixed at relationship -> session row -> request row.',
      v_req_fu, v_sess_fu;
  END IF;

  -- The session row lock must precede the child INSERT whose FK check
  -- would otherwise be what first locks the parent. This is the leg
  -- that specifically encodes the implicit-lock mechanism.
  v_insert := position('INSERT INTO public.ai_session_staging' in v_def);
  IF v_insert = 0 THEN
    RAISE EXCEPTION
      'SETUP FAILED: the ai_session_staging INSERT is absent from stage_ai_session_nearby_result -- the implicit-parent-lock ordering leg below no longer discriminates';
  END IF;
  IF v_sess_fu > v_insert THEN
    RAISE EXCEPTION
      'LOCK ORDER VIOLATED: stage_ai_session_nearby_result''s explicit ai_sessions row lock (at %) comes AFTER the ai_session_staging INSERT (at %). That INSERT''s FK check takes FOR KEY SHARE on the parent ai_sessions row, so the session row is first locked THERE -- after the request row -- which is the inversion with the explicit lock present but useless.',
      v_sess_fu, v_insert;
  END IF;

  IF v_def !~ 'pg_advisory_xact_lock\(hashtext\(v_relationship_id::text\)\)' THEN
    RAISE EXCEPTION
      'EXPLOIT: stage_ai_session_nearby_result''s advisory lock is not keyed on hashtext(v_relationship_id::text). Every other RPC in this chain keys on the RELATIONSHIP; a per-session or per-request key serializes against none of them and the deadlock returns.';
  END IF;

  -- ---- publish_ai_session_nearby_result ------------------------------
  v_def := pg_temp.strip_sql_comments(pg_get_functiondef(
    'public.publish_ai_session_nearby_result(uuid, uuid)'::regprocedure));

  v_adv := position('pg_advisory_xact_lock(hashtext(' in v_def);
  IF v_adv = 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: publish_ai_session_nearby_result takes NO relationship advisory lock. Without it, publish deadlocked against end_ai_session in 9/10 measured trials and against purge_expired_ai_sessions in 10/10 -- the purger losing 4 of those, each leaving an expired session active with content retained. That is Task 11''s pre-lock-fix body (20260953110000); 20260953120000 WINS.';
  END IF;

  v_fu_count := (length(v_def) - length(replace(v_def, 'FOR UPDATE', ''))) / length('FOR UPDATE');
  IF v_fu_count <> 2 THEN
    RAISE EXCEPTION
      'SETUP FAILED: publish_ai_session_nearby_result has % FOR UPDATE clause(s), expected exactly 2 (the ai_sessions row then the ai_session_requests row). See the stage leg above for why a changed count must be re-derived rather than accommodated.',
      v_fu_count;
  END IF;

  v_sess_fu := position('FROM public.ai_sessions WHERE id = v_session_id FOR UPDATE' in v_def);
  IF v_sess_fu = 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: publish_ai_session_nearby_result does not lock the ai_sessions row explicitly. It takes that row''s lock REGARDLESS -- the ai_session_turns INSERT''s FK check takes FOR KEY SHARE on the parent, and the revision bump takes it exclusively -- so the only question is ORDER. Lock it explicitly, before the request row.';
  END IF;

  v_req_fu := position('FROM public.ai_session_requests WHERE id = p_request_id FOR UPDATE' in v_def);
  IF v_req_fu = 0 THEN
    RAISE EXCEPTION
      'SETUP FAILED: publish_ai_session_nearby_result has no `FROM public.ai_session_requests WHERE id = p_request_id FOR UPDATE` locked read -- re-derive this contract''s request-row marker.';
  END IF;

  IF v_adv > v_sess_fu THEN
    RAISE EXCEPTION
      'LOCK ORDER VIOLATED: publish_ai_session_nearby_result locks the ai_sessions ROW (at %) before the relationship advisory lock (at %). The order is fixed at relationship -> session row -> request row.',
      v_sess_fu, v_adv;
  END IF;
  IF v_sess_fu > v_req_fu THEN
    RAISE EXCEPTION
      'LOCK ORDER VIOLATED: publish_ai_session_nearby_result locks the ai_session_requests row (at %) before the ai_sessions row (at %) -- the exact inversion 20260953120000 exists to fix.',
      v_req_fu, v_sess_fu;
  END IF;

  IF v_def !~ 'pg_advisory_xact_lock\(hashtext\(v_relationship_id::text\)\)' THEN
    RAISE EXCEPTION
      'EXPLOIT: publish_ai_session_nearby_result''s advisory lock is not keyed on hashtext(v_relationship_id::text) -- it serializes against nothing else in this chain.';
  END IF;

  -- ANTI-REGRESSION ON THE THING THE LOCK FIX MUST NOT HAVE BROKEN.
  -- 20260953120000 hoisted Task 11's `SELECT se.relationship_id FROM
  -- public.ai_sessions se` consent-gate lookup to the top, because the
  -- advisory lock needs it. The whole gate must still be there, must
  -- still read the hoisted value, and -- the part ordering cannot be
  -- taken on trust -- the NULL-actor guard must still be the FIRST
  -- statement, ahead of the new lookup. ai_session_purge_contracts.sql
  -- Contract 11 pins the gate's position relative to the turns INSERT;
  -- this pins it relative to the locks the fix introduced.
  IF v_def !~ 'IF p_actor_id IS NULL THEN' THEN
    RAISE EXCEPTION
      'EXPLOIT: publish_ai_session_nearby_result lost its NULL-actor guard. Global Constraint: every SECURITY DEFINER function validates its actor parameter non-NULL as its FIRST statement -- and the lock-order fix added a lock-target lookup ahead of everything, which is exactly the kind of edit that displaces it.';
  END IF;
  IF position('IF p_actor_id IS NULL THEN' in v_def) > v_adv THEN
    RAISE EXCEPTION
      'EXPLOIT: publish_ai_session_nearby_result''s NULL-actor guard (at %) now sits AFTER the relationship advisory lock (at %). It must remain the FIRST statement: a NULL actor must be refused before the function takes a lock on anything, let alone resolves a relationship to lock.',
      position('IF p_actor_id IS NULL THEN' in v_def), v_adv;
  END IF;
  -- TASK 5 RE-DERIVED THIS MARKER. It used to assert the inline
  -- `COALESCE(v_a_granted, false) AND COALESCE(v_b_granted, false)`.
  -- 20260953180000 extracted the two-party predicate into the shared
  -- public.ai_consent_granted_for_relationship, so the COALESCE now
  -- lives in the helper -- where it is asserted ONCE, by Contract 10 of
  -- ai_session_read_authorization_contracts.sql. The marker here becomes
  -- the CALL, which is exactly as sharp: every superseded body of
  -- publish (20260953080000, 20260953110000, 20260953120000,
  -- 20260953170000) predates the helper and cannot name it, so a
  -- re-apply of any of them still fails this leg.
  IF v_def !~ 'ai_consent_granted_for_relationship' THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: publish_ai_session_nearby_result no longer enforces the both-partner consent gate -- it does not call public.ai_consent_granted_for_relationship (nor, per the companion leg below, does it carry the pre-Task-5 inline predicate). 20260953120000 BUILDS ON Task 11''s 20260953110000 and 20260953180000 BUILDS ON Task 2''s 20260953170000; every one of them must preserve that gate. A lock-order fix or a refactor that reverted to Task 8''s pre-gate body would commit a staged Nearby result into the permanent transcript after a partner withdrew AI-processing consent.';
  END IF;
  -- ANTI-VACUITY, and the reason this is two legs and not one: a body
  -- that called the helper and then IGNORED its answer would pass the
  -- leg above. The gate must RAISE on a false answer.
  IF v_def !~ 'IF NOT public\.ai_consent_granted_for_relationship\(v_relationship_id\) THEN' THEN
    RAISE EXCEPTION
      'EXPLOIT: publish_ai_session_nearby_result calls public.ai_consent_granted_for_relationship but does not branch on it as `IF NOT ... THEN`. Calling the predicate and discarding its answer is indistinguishable from having no gate at all.';
  END IF;
  IF v_def !~ 'v_relationship_id uuid' OR v_def !~ 'WHERE r\.id = v_relationship_id' THEN
    RAISE EXCEPTION
      'EXPLOIT: publish_ai_session_nearby_result''s membership gate no longer reads v_relationship_id -- the value the lock-order fix hoisted to the top for the advisory lock is the SAME value the gate must compare against. A gate reading a different (or NULL) relationship denies or permits by accident.';
  END IF;

  RAISE NOTICE 'nearby contract 5: stage and publish both lock relationship -> session row -> request row; publish''s consent gate and first-statement actor guard intact';
END $$;


-- =====================================================================
-- Contract 6 (Task 1 FIX ROUND 1, migration 20260953150000): THE LOCK
-- ORDER of discard_ai_session_nearby_staging, STRUCTURALLY, on the
-- comment-stripped live body.
--
-- THE DEFECT THIS PINS. Task 1's review (Finding 1, Critical) found
-- that publish_ai_session_nearby_result x
-- discard_ai_session_nearby_staging STILL deadlocked after
-- 20260953120000 -- and that Task 1's report had recorded the pair as
-- fixed, on reasoning that does not hold. Task 8's superseded discard
-- (20260953080000) ran:
--
--   SELECT requester_id FROM ai_session_staging   (unlocked)
--   DELETE FROM ai_session_staging                (staging row, FIRST)
--   UPDATE ai_session_requests                    (request row, SECOND)
--
-- with NO relationship advisory lock at all, while publish takes the
-- advisory lock, the session row, the request row, and only ~74 lines
-- later the staging row. Opposite orders over the same two rows. The
-- advisory lock 20260953120000 added to publish SERIALIZED NOTHING
-- against discard, because discard never took it -- which is exactly
-- the reasoning error Task 1's Concern 4 made, and is why a
-- PRESENCE-only check on publish's side could never have caught this.
--
-- MEASURED on the FIXED publish against the UNFIXED discard, real RPCs
-- in two concurrent psql backends, fresh fixture per trial, a gap
-- inserted in discard's DELETE->UPDATE window:
--
--   none, idle server        30 + 40 trials   0 deadlocks
--   none, 20-backend load         40 trials   1
--   1 ms gap                      15 trials  14
--   10 ms gap                     15 trials  15
--   50 ms gap                     15 trials  15
--   250 ms gap                    20 trials  20
--
-- The captured victim was the DISCARD side:
--   ERROR: deadlock detected
--   CONTEXT: while updating tuple in relation "ai_session_requests"
--   PL/pgSQL function discard_ai_session_nearby_staging line 19
-- i.e. the user's own "discard this Nearby result" failing with a raw
-- SQLSTATE 40P01 -- the same user-facing shape the final review's N1
-- called Critical for end_ai_session.
--
-- NOT A REGRESSION: pre-fix publish on the identical 1 ms race gave
-- 13/15. The pair was always broken and 20260953120000 did not touch
-- it. It is a merge blocker anyway, being on the brief's own list of
-- four known deadlocking pairs and recorded as fixed.
--
-- WHY DISCARD WAS THE ONE TO FIX. The reviewer found this finding by a
-- STRUCTURAL SWEEP rather than by guessing: enumerate every function
-- that locks or writes ai_sessions / ai_session_requests /
-- ai_session_staging, and flag those doing so WITHOUT the relationship
-- advisory lock. A function holding only ONE of the three row-classes
-- cannot deadlock on them; one holding TWO without the advisory lock is
-- a candidate. That query returned exactly ONE row --
-- discard_ai_session_nearby_staging -- and that row predicted the
-- finding, which the race then confirmed. Re-run after 20260953150000,
-- the query returns ZERO rows. THAT is what this contract protects: the
-- property that makes the lock discipline checkable by query instead of
-- re-derivable only by racing.
--
-- WHY STRUCTURAL AND NOT BEHAVIOURAL. A deadlock needs two concurrent
-- backends, which a single-transaction SQL contract cannot create --
-- exactly why no committed test caught this for twelve task reviews.
-- The behavioural proof is
-- supabase/tests/ai_session_completion_concurrent_test.sh, whose
-- publish x discard section runs both orderings at a configurable gap
-- in discard's DELETE->UPDATE window (the gap is not optional: the
-- window is sub-millisecond on the real bodies, so a tight-only race
-- reports green against the BROKEN body, which is how Task 1's 12
-- clean trials happened). This is the cheap always-on guard that the
-- ORDER has not rotted back.
--
-- WHY position() AND NOT A PRESENCE CHECK. A presence check passes a
-- body that contains all three lock statements in the WRONG order --
-- the pre-fix body with an advisory lock bolted on at the end, or the
-- advisory lock moved below the row locks. The ordering legs below are
-- what make a REORDERING with every statement present fail.
--
-- COMMENTS ARE STRIPPED FIRST. pg_get_functiondef() returns them
-- verbatim and 20260953150000's own comments name all three locks in
-- the correct order, so an unstripped match would be satisfied by the
-- commentary alone even if every lock were deleted (Task 10's finding
-- N1, measured there on 4/4 structural assertions).
-- =====================================================================
DO $$
DECLARE
  v_def text;
  v_adv int;
  v_sess_fu int;
  v_req_fu int;
  v_fu_count int;
  v_staging_del int;
  v_req_upd int;
  v_locked_read int;
BEGIN
  v_def := pg_temp.strip_sql_comments(pg_get_functiondef(
    'public.discard_ai_session_nearby_staging(uuid, uuid)'::regprocedure));

  -- ---- LOCK 1: the relationship advisory lock. THE FIX. -------------
  v_adv := position('pg_advisory_xact_lock(hashtext(' in v_def);
  IF v_adv = 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: discard_ai_session_nearby_staging takes NO relationship advisory lock. It is the FIRST lock in this plan''s fixed, non-negotiable order. Without it this function was the ONLY one in the schema holding two of the three session row-classes with no advisory lock, and it deadlocked against the FIXED publish_ai_session_nearby_result in 14/15 measured trials at a 1 ms window -- the victim being the user''s own "discard this Nearby result" failing with a raw SQLSTATE 40P01. That is Task 8''s superseded body (20260953080000); 20260953150000 WINS.';
  END IF;

  IF v_def !~ 'pg_advisory_xact_lock\(hashtext\(v_relationship_id::text\)\)' THEN
    RAISE EXCEPTION
      'EXPLOIT: discard_ai_session_nearby_staging''s advisory lock is not keyed on hashtext(v_relationship_id::text). Every other RPC in this chain keys on the RELATIONSHIP; a per-session, per-request or per-staging-row key serializes against NONE of them and the publish x discard deadlock returns in full. The key is the whole point of the lock.';
  END IF;

  -- ---- RULING 14: the NULL-actor guard must be the LITERAL FIRST
  -- statement, ahead of the lock-target lookup and the locks.
  --
  -- Global Constraint: every SECURITY DEFINER function in this plan
  -- validates its actor parameter non-NULL as its FIRST statement.
  -- Before 20260953190000, discard was the one function satisfying that
  -- only INDIRECTLY: `v_actor != p_actor_id` is NULL when p_actor_id is
  -- NULL, so the requester check fell THROUGH, the staging DELETE and
  -- the request UPDATE both ran, and the refusal came afterwards from
  -- mark_ai_assistant_usage_outcome -- correct by plpgsql's
  -- subtransaction rollback rather than by construction. MEASURED both
  -- ways on a fresh database before the change.
  --
  -- Asserted by POSITION, not presence: a guard added BELOW the
  -- lock-target lookup, or below the advisory lock, still "contains"
  -- the string while performing work before authorizing it.
  IF position('IF p_actor_id IS NULL THEN' in v_def) = 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: discard_ai_session_nearby_staging has no explicit `IF p_actor_id IS NULL` guard. Global Constraint: every SECURITY DEFINER function in this plan validates its actor parameter non-NULL as its FIRST statement. Without it a NULL actor reaches the staging DELETE and the request UPDATE and is refused only afterwards, indirectly, by mark_ai_assistant_usage_outcome -- two unauthorized writes undone by rollback instead of never attempted. 20260953190000 WINS over 20260953150000.';
  END IF;
  IF position('IF p_actor_id IS NULL THEN' in v_def) > v_adv THEN
    RAISE EXCEPTION
      'EXPLOIT: discard_ai_session_nearby_staging''s NULL-actor guard (at %) sits AFTER the relationship advisory lock (at %). It must be the FIRST statement: a NULL actor must be refused before the function resolves a relationship, takes a lock, or touches a row.',
      position('IF p_actor_id IS NULL THEN' in v_def), v_adv;
  END IF;
  IF position('IF p_actor_id IS NULL THEN' in v_def)
     > position('FROM public.ai_session_staging st' in v_def) THEN
    RAISE EXCEPTION
      'EXPLOIT: discard_ai_session_nearby_staging''s NULL-actor guard sits AFTER its lock-target lookup. "First statement" means ahead of every read, not merely ahead of the locks: the lookup is what makes the no-staging-row case return silently, so a guard below it leaves a NULL actor silently accepted on exactly that path.';
  END IF;

  -- ---- The FOR UPDATE count, so neither row marker can silently stop
  -- discriminating, and so a THIRD row lock -- possibly ahead of the
  -- advisory lock -- fails loudly rather than being accommodated.
  v_fu_count := (length(v_def) - length(replace(v_def, 'FOR UPDATE', ''))) / length('FOR UPDATE');
  IF v_fu_count <> 2 THEN
    RAISE EXCEPTION
      'SETUP FAILED: discard_ai_session_nearby_staging has % FOR UPDATE clause(s), expected exactly 2 (the ai_sessions row then the ai_session_requests row). The ordering legs below identify each row lock by its own locked-read text, and a changed count means one of them no longer discriminates, or a THIRD row lock was added. Re-derive the markers rather than relaxing the count.',
      v_fu_count;
  END IF;

  -- ---- LOCK 2: the session row, before the request row. -------------
  -- discard does not otherwise touch ai_sessions: it neither UPDATEs it
  -- nor INSERTs into a child table, and a child-table DELETE takes NO
  -- lock on the FK parent (verified by query: a DELETE from a child
  -- leaves zero locks on the parent relation, whereas an INSERT takes
  -- RowShareLock). So unlike stage and publish, this lock is not
  -- subsuming an implicit one -- it is taken so that discard occupies
  -- the documented order at the SAME points as every other
  -- participant. A participant that SKIPS an element of a lock order is
  -- how the order stops being a total order, which is the defect one
  -- level up.
  v_sess_fu := position('FROM public.ai_sessions WHERE id = v_session_id FOR UPDATE' in v_def);
  IF v_sess_fu = 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: discard_ai_session_nearby_staging does not lock the ai_sessions row. The documented order is relationship advisory -> session row -> request row, and every other function in this chain takes the session row at that point. Dropping it here reintroduces a participant that holds the request and staging rows while holding no session lock, which is a partial order, not a total one.';
  END IF;

  -- ---- LOCK 3: the request row, by its full locked-read text. -------
  -- This is the row publish holds across its three gate SELECTs while
  -- waiting for the staging row, and the row the superseded body took
  -- SECOND, after the staging DELETE -- the inversion itself.
  v_req_fu := position('FROM public.ai_session_requests WHERE id = p_request_id FOR UPDATE' in v_def);
  IF v_req_fu = 0 THEN
    RAISE EXCEPTION
      'SETUP FAILED: discard_ai_session_nearby_staging has no `FROM public.ai_session_requests WHERE id = p_request_id FOR UPDATE` locked read -- re-derive this contract''s request-row marker. The request row MUST be taken explicitly and BEFORE the staging DELETE: the superseded body acquired it only implicitly, via its `UPDATE ai_session_requests` AFTER the DELETE, which is the exact inversion 20260953150000 exists to fix.';
  END IF;

  -- ---- THE ORDERING LEGS. These are what a presence check misses. ---
  IF v_adv > v_sess_fu THEN
    RAISE EXCEPTION
      'LOCK ORDER VIOLATED: discard_ai_session_nearby_staging locks the ai_sessions ROW (at %) before the relationship advisory lock (at %). The order is fixed at relationship -> session row -> request row and must never vary; inverting it deadlocks against every RPC that takes the advisory lock first. A change needing a different order is a plan defect, not a local decision.',
      v_sess_fu, v_adv;
  END IF;
  IF v_sess_fu > v_req_fu THEN
    RAISE EXCEPTION
      'LOCK ORDER VIOLATED: discard_ai_session_nearby_staging locks the ai_session_requests row (at %) before the ai_sessions row (at %). The order is fixed at relationship -> session row -> request row.',
      v_req_fu, v_sess_fu;
  END IF;

  -- ---- THE STAGING ROW MUST COME LAST. ------------------------------
  -- This is the leg that specifically encodes Finding 1's cycle. The
  -- staging DELETE is where discard acquires the staging row, and
  -- publish acquires it LAST, after the request row. If discard takes
  -- it before the request row -- as the superseded body did -- the two
  -- functions acquire the same two rows in opposite orders and the
  -- deadlock is back even with all three locks above present and in
  -- order.
  v_staging_del := position('DELETE FROM public.ai_session_staging' in v_def);
  IF v_staging_del = 0 THEN
    RAISE EXCEPTION
      'SETUP FAILED: the ai_session_staging DELETE is absent from discard_ai_session_nearby_staging -- the staging-row ordering leg below no longer discriminates, and discarding no longer discards.';
  END IF;
  IF v_req_fu > v_staging_del THEN
    RAISE EXCEPTION
      'LOCK ORDER VIOLATED: discard_ai_session_nearby_staging acquires the ai_session_staging row (its DELETE, at %) BEFORE the ai_session_requests row (at %). publish_ai_session_nearby_result acquires those two rows in the OPPOSITE order -- request row first, staging row ~74 lines later, after its membership and consent gates -- so this is Finding 1''s cycle exactly: 14/15 deadlocks at a 1 ms window, 15/15 at 10 ms, with the user''s own discard action as the victim. The staging row MUST be acquired after the request row.',
      v_staging_del, v_req_fu;
  END IF;

  -- ---- ANTI-REGRESSION: WHAT THE LOCK FIX MUST NOT HAVE BROKEN. ----
  -- 20260953150000 moved the requester authorization check from the top
  -- of the function (where it was the only read, and unlocked) to BELOW
  -- the three locks, so it is judged on the authoritative re-read. The
  -- check must still exist, must still raise its VERBATIM message, and
  -- must still sit BEFORE the DELETE it guards -- a lock-order edit
  -- that reordered statements is exactly the kind that could displace
  -- it past the write.
  IF v_def !~ 'Only the requester may discard their own staged result' THEN
    RAISE EXCEPTION
      'EXPLOIT: discard_ai_session_nearby_staging lost its requester-only authorization raise. Spec 8.2.2: only the requester may discard their own staged Nearby result. 20260953150000 is a LOCK ORDER fix and must preserve this check verbatim -- moving it below the locks (so it reads the authoritative row) must not be allowed to become deleting it.';
  END IF;
  v_locked_read := position('IF v_actor != p_actor_id THEN' in v_def);
  IF v_locked_read = 0 THEN
    RAISE EXCEPTION
      'SETUP FAILED: discard_ai_session_nearby_staging has no `IF v_actor != p_actor_id THEN` comparison -- re-derive this contract''s authorization marker.';
  END IF;
  IF v_locked_read > v_staging_del THEN
    RAISE EXCEPTION
      'EXPLOIT: discard_ai_session_nearby_staging''s requester authorization check (at %) now sits AFTER the ai_session_staging DELETE (at %). The check must precede the write it guards, or a non-requester''s discard destroys the staged result and only then raises -- and the raise is what rolls it back, which is defence by accident rather than by design.',
      v_locked_read, v_staging_del;
  END IF;

  -- The authorization must be judged on a read taken UNDER the locks,
  -- not on the unlocked lock-target pre-read. This is the TOCTOU leg:
  -- the pre-read exists ONLY to resolve which rows to lock (the same
  -- design Task 1's review verified for the three completion RPCs
  -- across six vectors), so the value the check compares must come
  -- from after the request-row lock.
  IF position('SELECT requester_id INTO v_actor' in v_def) < v_req_fu THEN
    RAISE EXCEPTION
      'EXPLOIT: discard_ai_session_nearby_staging reads requester_id BEFORE it takes the request row lock, and judges authorization on that unlocked value. The unlocked pre-read exists ONLY to resolve the advisory-lock key and the session to lock -- it must decide nothing. Every value this function ACTS on must come from the re-read under the locks.';
  END IF;

  -- The quota outcome must still be the COUNTED terminal state. Spec
  -- 8.2.2: discard is terminal and counted, never a refund --
  -- provider_started_at is already set (the request reached 'staged'
  -- only via claim_ai_session_dispatch), so 'cancelled'/'rejected' here
  -- would hand back quota for a provider call that really happened.
  -- Contract 4 above asserts this behaviourally; this is the cheap
  -- structural twin, because a lock-order edit rewrites the statement
  -- sequence around it.
  IF v_def !~ 'mark_ai_assistant_usage_outcome\(p_actor_id, p_request_id, ''succeeded'', 2::smallint\)' THEN
    RAISE EXCEPTION
      'EXPLOIT: discard_ai_session_nearby_staging no longer marks its quota outcome ''succeeded'' with 2 provider calls. Spec 8.2.2: discard is a TERMINAL, COUNTED outcome and never a quota refund. A ''cancelled''/''rejected'' outcome here refunds quota for a provider call that already ran.';
  END IF;
  v_req_upd := position('UPDATE public.ai_session_requests SET state = ''cancelled''' in v_def);
  IF v_req_upd = 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: discard_ai_session_nearby_staging no longer sets the request state to ''cancelled''. A discarded Nearby result must leave its request in a terminal state, or the reconciler and the purger both see a request still in flight.';
  END IF;

  RAISE NOTICE 'nearby contract 6: discard_ai_session_nearby_staging locks relationship -> session row -> request row -> staging row; requester authorization judged under the locks and before the DELETE; counted quota outcome intact';
END $$;


-- =====================================================================
-- Contract 7 (Task 1 FIX ROUND 1, Ruling 8 -- review Finding 2, Low /
-- latent): ai_session_requests.session_id IS IMMUTABLE, AND THE WHOLE
-- LOCK-ORDER FIX RESTS ON THAT.
--
-- THE COUPLING. commit_ai_session_ideas_turn and
-- publish_ai_session_nearby_result take the session row FOR UPDATE
-- keyed on v_session_id -- a value from the UNLOCKED lock-target
-- pre-read -- and then WRITE using v_request.session_id, a value from
-- the LOCKED re-read. Two different variables. They are equal only
-- because nothing in the schema writes ai_session_requests.session_id
-- and the table carries no triggers.
--
-- Today that is verified, from both directions, and has zero impact:
-- the reviewer grepped every migration for an UPDATE of that column
-- (zero hits) and queried pg_trigger (empty). But NOTHING ASSERTED IT,
-- and if a future migration ever made session_id mutable -- or added a
-- trigger that rewrote it -- then commit and publish would LOCK SESSION
-- A AND WRITE TO SESSION B. The advisory lock would be keyed on the
-- wrong relationship, the session row lock would be on the wrong row,
-- and the deadlock the whole of 20260953120000 and 20260953150000
-- exists to fix would be back, in a form no lock-order contract would
-- detect, because every lock would still be present and in order.
--
-- THE ASSERTION. Rather than assert the absence of a writer by grepping
-- SQL text (which cannot see a future migration, and which a contract
-- cannot do at all), this asserts the two structural facts that make
-- the column immutable IN THE LIVE DATABASE:
--
--   1. No trigger on ai_session_requests can rewrite it. Checked by
--      catalog query, not by reading files.
--   2. No SECURITY DEFINER function in public writes it. Checked
--      against every function body in the schema, comment-stripped --
--      so a writer added by any future migration fails this contract
--      the moment it lands, which is the whole point.
--
-- WHY NOT JUST LOCK ON v_request.session_id. That is the other half of
-- Ruling 8's option and it would also close the coupling -- but it
-- cannot be done without a NEW definition of the two completion RPCs,
-- which this fix round is explicitly forbidden to touch (their lock
-- order is verified work, and re-opening them to fix a Low/latent
-- finding would risk the Critical one). Locking on the pre-read value
-- is also unavoidable in part: the advisory lock must be taken BEFORE
-- the locked re-read, so its key can only ever come from the pre-read.
-- The assertion is therefore the correct shape of fix here, and it
-- defends BOTH variables at once.
-- =====================================================================
DO $$
DECLARE
  v_trigger_count int;
  v_writers text;
BEGIN
  -- ---- 1. No non-internal trigger on ai_session_requests. ----------
  -- tgisinternal = false excludes the FK enforcement triggers, which
  -- cannot rewrite a column.
  SELECT count(*) INTO v_trigger_count
  FROM pg_trigger t
  WHERE t.tgrelid = 'public.ai_session_requests'::regclass
    AND t.tgisinternal = false;
  IF v_trigger_count <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: ai_session_requests now carries % non-internal trigger(s). commit_ai_session_ideas_turn and publish_ai_session_nearby_result lock the session row keyed on v_session_id (the unlocked pre-read) and write using v_request.session_id (the locked re-read); those are two different variables, equal ONLY because session_id is immutable. A trigger that rewrites session_id makes them disagree, and the two RPCs would then LOCK ONE SESSION AND WRITE TO ANOTHER -- the advisory lock keyed on the wrong relationship, every lock still present and in order, and no lock-order contract able to see it. If the trigger genuinely cannot touch session_id, narrow this assertion deliberately rather than deleting it.',
      v_trigger_count;
  END IF;

  -- ---- 2. No function in public writes ai_session_requests.session_id.
  -- Comment-stripped, because pg_get_functiondef returns comments
  -- verbatim and several migrations DISCUSS session_id at length.
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_writers
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prokind = 'f'
    AND pg_temp.strip_sql_comments(pg_get_functiondef(p.oid))
          ~ 'UPDATE\s+(public\.)?ai_session_requests\s+SET[^;]*\msession_id\M\s*=';
  IF v_writers IS NOT NULL THEN
    RAISE EXCEPTION
      'EXPLOIT: these function(s) now WRITE ai_session_requests.session_id: %. That column must stay immutable. commit_ai_session_ideas_turn and publish_ai_session_nearby_result lock the session row keyed on v_session_id (from the UNLOCKED lock-target pre-read) and then write using v_request.session_id (from the LOCKED re-read) -- two different variables whose equality is an invariant of the SCHEMA, not of the code. Make session_id mutable and those RPCs lock session A while writing to session B: the relationship advisory lock keyed on the wrong relationship, the session row FOR UPDATE on the wrong row, and the publish/commit x end/purge deadlock that 20260953120000 exists to fix silently restored with every lock statement still present and in the documented order. Either keep the column immutable, or re-define both RPCs to lock on v_request.session_id in a new migration.',
      v_writers;
  END IF;

  -- ---- ANTI-VACUITY. The regex above must actually be capable of
  -- matching a writer. A pattern that matched nothing -- because the
  -- table name changed, or the regex rotted -- would make leg 2 pass
  -- forever while asserting nothing. Prove it fires on a known-positive
  -- string before trusting its silence on the real bodies.
  IF NOT ('UPDATE public.ai_session_requests SET session_id = $1 WHERE id = $2;'
          ~ 'UPDATE\s+(public\.)?ai_session_requests\s+SET[^;]*\msession_id\M\s*=') THEN
    RAISE EXCEPTION
      'SETUP FAILED: Contract 7''s session_id-writer pattern does not match a known-positive writer, so leg 2 above asserts NOTHING and would pass against a schema full of writers. Re-derive the pattern.';
  END IF;
  -- ...and must NOT match the read-only uses that legitimately exist,
  -- or the contract would be unsatisfiable and someone would delete it.
  IF ('UPDATE public.ai_session_requests SET state = ''cancelled'' WHERE id = p_request_id;'
      ~ 'UPDATE\s+(public\.)?ai_session_requests\s+SET[^;]*\msession_id\M\s*=') THEN
    RAISE EXCEPTION
      'SETUP FAILED: Contract 7''s session_id-writer pattern matches an ordinary state UPDATE that does not touch session_id. It is over-broad and would fail on correct code.';
  END IF;

  RAISE NOTICE 'nearby contract 7 (ruling 8): ai_session_requests.session_id is immutable -- 0 non-internal triggers, 0 function writers -- so the completion RPCs'' pre-read lock key and locked write target cannot diverge';
END $$;


-- =====================================================================
-- Contract 8 (Task 2, merge-blocker fix 20260953170000): A GENUINE
-- MULTI-TURN NEARBY SESSION DRIVEN ENTIRELY BY RPC RETURN VALUES, WITH
-- NO READ OF public.ai_sessions ANYWHERE.
--
-- The Nearby twin of ai_session_commit_ideas_contracts.sql's Contract
-- 5, and it is NOT redundant with it: the Nearby path has FOUR hops
-- rather than three (admit -> claim -> stage -> publish), the revision
-- bump happens in PUBLISH rather than in the function that first wrote
-- content, and stage_ai_session_nearby_result RETURNS void and bumps
-- nothing. So the disclosure point for this path is publish, and that
-- had to be verified on the real sequence rather than inferred from the
-- Ideas one.
--
-- THE DEFECT. admit_ai_session_generation refuses an admission unless
-- p_expected_revision equals ai_sessions.revision.
-- publish_ai_session_nearby_result bumps that revision as its last
-- write and, until 20260953170000, returned only
-- (committed, user_ordinal, attune_ordinal). So turn 2 of a Nearby
-- session had no legitimate way to learn its fence.
--
-- WHY CONTRACT 4 ABOVE DID NOT CATCH IT. Contract 4 does perform a
-- second admission -- with a hardcoded literal `2` and a comment
-- saying "contract 3's publish bumped ai_sessions.revision from 1 to
-- 2". That is knowledge a test has statically and a real caller does
-- not. Plan C's edge function handles a turn on a session it did not
-- create, cannot know its turn count, and forbids itself raw table
-- reads -- and public.ai_sessions grants `authenticated` nothing (56
-- combinations asserted at 0 leaked), so a direct read is not merely
-- discouraged, it is denied; doing it with the service role instead
-- would bypass all four of spec 7.2's authorization gates.
--
-- THE SHAPE OF THE PROOF. Every revision fed to admit comes from a
-- value an RPC RETURNED:
--
--   prepare_ai_session -> .revision             (turn 1's fence)
--   admit -> claim -> stage -> publish
--                      -> .session_revision     (turn 2's fence)
--   admit -> claim -> stage -> publish
--                      -> .session_revision     (turn 3's fence)
--
-- Three hops, not two, so a session_revision that happened to be a
-- constant, the ordinal, or the attempt number cannot pass.
--
-- IT ALSO PROVES stage DISCLOSES NOTHING AND NEEDS NOT TO. stage is
-- called on every turn below and its return value is never used for a
-- fence, because it has none -- it RETURNS void. If a future change
-- moved the revision bump into stage, this contract's publish-side
-- assertions would fail (publish would report an unadvanced revision),
-- which is the correct outcome: the disclosure must live with the bump.
--
-- A SHARED SESSION IS USED, not a private one, because Nearby's own
-- fixture above uses 'shared' and both partners must approve the
-- context. prepare_ai_session forbids two concurrent SHARED sessions
-- per relationship, so this contract uses its OWN relationship rather
-- than reusing the one above -- otherwise the two shared sessions would
-- collide and this contract would fail on preparation rather than on
-- anything it means to test.
-- =====================================================================
DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000153';
  v_user_a uuid := 'b1000000-0000-0000-0000-000000000154';
  v_user_b uuid := 'b1000000-0000-0000-0000-000000000155';
  v_session uuid;
  v_prepare record;
  v_admit record;
  v_pub record;
  -- The ONLY revision state this block keeps: seeded from
  -- prepare_ai_session's returned value, thereafter advanced ONLY by
  -- assigning a value publish returned. Never read from a table.
  v_fence int;
  v_turn int;
  v_expect_user int;
  v_expect_attune int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'nearbyturn_a@t.test'), (v_user_b, 'nearbyturn_b@t.test')
  ON CONFLICT DO NOTHING;
  -- users.phone is UNIQUE and a silently-colliding ON CONFLICT DO
  -- NOTHING insert is how several fixture bugs in this plan's history
  -- produced false passes. +1555002200x was swept against the whole of
  -- supabase/ and scripts/ before being chosen, and the fixture
  -- assertion below fails loudly if either row was in fact dropped.
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550022003', 'A'), (v_user_b, '+15550022004', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  -- BOTH partners must hold a current grant: admit enforces the
  -- membership + two-party consent gate (20260953140000) and publish
  -- enforces it again (20260953110000), so without both grants every
  -- turn below fails before it reaches the revision fence -- and this
  -- contract would fail for the wrong reason.
  --
  -- clock_timestamp(), never now(): now() is frozen per transaction, so
  -- events written in one DO block would share an identical created_at
  -- and the consent lookup's tiebreak would fall to `id DESC` on a
  -- random uuid. idempotency_key is NOT NULL.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  IF NOT EXISTS (SELECT 1 FROM public.relationships r
                 WHERE r.id = v_rel AND r.user_a = v_user_a AND r.user_b = v_user_b
                   AND r.status = 'active' AND r.chat_archived_at IS NULL) THEN
    RAISE EXCEPTION
      'SETUP FAILED: contract 8''s relationship fixture is not the two active members this contract needs -- most likely a uuid collision with another test file. Every admit and publish below would deny on the membership gate and this contract would report a revision problem it never tested.';
  END IF;

  -- ---- TURN 1's FENCE from prepare_ai_session, the one RPC that has
  -- always disclosed a revision. The ONLY seed; everything after it must
  -- come from publish.
  SELECT * INTO v_prepare FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'nearby', 'shared', NULL, false, NULL
  );
  v_session := v_prepare.session_id;
  v_fence := v_prepare.revision;
  IF v_fence IS NULL THEN
    RAISE EXCEPTION
      'SETUP FAILED: prepare_ai_session returned a NULL revision, so this contract has no legitimate starting fence.';
  END IF;

  PERFORM public.approve_ai_session_context(v_user_a, v_session, v_fence, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_session, v_fence, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, v_fence);

  FOR v_turn IN 1..3 LOOP
    v_expect_user := (v_turn * 2) - 1;
    v_expect_attune := v_turn * 2;

    BEGIN
      SELECT * INTO v_admit FROM public.admit_ai_session_generation(
        v_user_a, gen_random_uuid(), v_session, v_fence, 'nearby:multiturn-' || v_turn
      );
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM = 'CONTEXT_CHANGED' THEN
        RAISE EXCEPTION
          'EXPLOIT: NEARBY TURN % IS UNREACHABLE. admit_ai_session_generation raised CONTEXT_CHANGED on expected_revision=%, and % is the most recent revision any RPC in this plan DISCLOSED. publish_ai_session_nearby_result bumps ai_sessions.revision and must RETURN it (migration 20260953170000); stage_ai_session_nearby_result cannot supply it -- it RETURNS void and bumps nothing. Without the disclosure the only route to the next fence is a raw public.ai_sessions read, which Plan C''s edge function forbids itself, which the table''s grants deny to `authenticated`, and which bypasses all four of spec 7.2''s authorization gates.',
          v_turn, v_fence, v_fence;
      END IF;
      RAISE;
    END;
    IF v_admit.outcome IS DISTINCT FROM 'admitted' THEN
      RAISE EXCEPTION 'EXPLOIT: Nearby turn % was not admitted (outcome=%) even with a fence obtained from an RPC return value',
        v_turn, v_admit.outcome;
    END IF;

    IF NOT public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id) THEN
      RAISE EXCEPTION 'SETUP FAILED: Nearby turn % could not be claimed', v_turn;
    END IF;

    -- stage. Returns void -- there is no fence to take from here, which
    -- is the point: the Nearby path's disclosure point is publish,
    -- because publish is what bumps.
    PERFORM public.stage_ai_session_nearby_result(
      v_admit.worker_token, v_admit.request_id, 'places for turn ' || v_turn, '[]'::jsonb
    );
    IF (SELECT state FROM public.ai_session_requests WHERE id = v_admit.request_id) != 'staged' THEN
      RAISE EXCEPTION 'SETUP FAILED: Nearby turn % did not reach state=staged, so the publish below tests nothing', v_turn;
    END IF;

    SELECT * INTO v_pub FROM public.publish_ai_session_nearby_result(v_user_a, v_admit.request_id);

    IF v_pub.committed IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'EXPLOIT: Nearby turn %''s publish did not report committed=true', v_turn;
    END IF;
    IF v_pub.user_ordinal != v_expect_user OR v_pub.attune_ordinal != v_expect_attune THEN
      RAISE EXCEPTION 'EXPLOIT: Nearby turn % produced ordinals (%,%), expected (%,%)',
        v_turn, v_pub.user_ordinal, v_pub.attune_ordinal, v_expect_user, v_expect_attune;
    END IF;

    -- ---- THE DISCLOSURE ITSELF.
    IF v_pub.session_revision IS NULL THEN
      RAISE EXCEPTION
        'EXPLOIT: publish_ai_session_nearby_result returned a NULL session_revision on Nearby turn %. The field exists but carries nothing, so the next admit has no fence and the Nearby session is single-turn in practice. 20260953170000 takes the value from the revision bump''s own RETURNING clause, which cannot be NULL for a row that was just updated.',
        v_turn;
    END IF;
    IF v_pub.session_revision <= v_fence THEN
      RAISE EXCEPTION
        'EXPLOIT: publish_ai_session_nearby_result returned session_revision=% on Nearby turn %, which does not advance past the fence % this turn was admitted on. publish bumps ai_sessions.revision, so the value it discloses must be the POST-bump revision -- a pre-bump read sends the caller back with the stale fence it already had.',
        v_pub.session_revision, v_turn, v_fence;
    END IF;

    -- ADVANCE USING ONLY THE RETURNED VALUE. No table read here; the
    -- next iteration's admit accepts this value or fails.
    v_fence := v_pub.session_revision;
  END LOOP;

  IF (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session) != 6 THEN
    RAISE EXCEPTION 'EXPLOIT: three published Nearby turns did not produce exactly 6 turn rows (got %)',
      (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session);
  END IF;
  IF (SELECT count(DISTINCT ordinal) FROM public.ai_session_turns WHERE session_id = v_session) != 6
     OR (SELECT min(ordinal) FROM public.ai_session_turns WHERE session_id = v_session) != 1
     OR (SELECT max(ordinal) FROM public.ai_session_turns WHERE session_id = v_session) != 6 THEN
    RAISE EXCEPTION 'EXPLOIT: the three Nearby turns did not produce ordinals 1..6 contiguously';
  END IF;

  -- ANTI-VACUITY: the fence must have actually moved, or every admit
  -- above accepted the same value and this contract proved nothing.
  IF v_fence <= v_prepare.revision THEN
    RAISE EXCEPTION
      'SETUP FAILED: after three publishes the disclosed revision (%) has not advanced past prepare_ai_session''s initial value (%). Either publish stopped bumping ai_sessions.revision -- in which case admit''s optimistic fence guards nothing -- or every admit accepted an unchanging value and this contract proved nothing.',
      v_fence, v_prepare.revision;
  END IF;

  -- ---- THE IDEMPOTENT REPLAY MUST REPORT THE CURRENT REVISION WITHOUT
  -- RE-BUMPING, AND MUST STILL BE ANSWERED BEFORE THE CONSENT GATE.
  -- publish's replay branch sits ahead of the membership and consent
  -- gates on purpose (Task 11's design, verified by Task 10's
  -- re-review), so Task 2's addition to that branch must be a READ of
  -- the already-locked session row -- never a write, and never a bump.
  -- A replay that re-bumped would invalidate the fence the caller holds
  -- and guarantee CONTEXT_CHANGED on its next admit, a different number
  -- of times depending on how often it retried.
  DECLARE
    v_replay record;
  BEGIN
    SELECT * INTO v_replay FROM public.publish_ai_session_nearby_result(v_user_a, v_admit.request_id);
    IF v_replay.committed IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'EXPLOIT: replaying a committed publish did not report committed=true';
    END IF;
    IF v_replay.user_ordinal != v_pub.user_ordinal
       OR v_replay.attune_ordinal != v_pub.attune_ordinal THEN
      RAISE EXCEPTION 'EXPLOIT: replaying a committed publish produced different ordinals';
    END IF;
    IF v_replay.session_revision IS DISTINCT FROM v_fence THEN
      RAISE EXCEPTION
        'EXPLOIT: the idempotent replay of publish_ai_session_nearby_result reported session_revision=% but the current revision is % -- the replay path RE-BUMPED the revision (or read a stale one). A replay inserts nothing and must bump nothing: it already answered committed=true with the original ordinals, and moving the revision under a caller holding % as its fence guarantees CONTEXT_CHANGED on its next admit. That breaks the exact multi-turn reachability 20260953170000 exists to enable, non-deterministically.',
        v_replay.session_revision, v_fence, v_fence;
    END IF;
    IF (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session) != 6 THEN
      RAISE EXCEPTION 'EXPLOIT: the publish replay inserted turn rows';
    END IF;
  END;

  -- ---- THE REPLAY IS STILL ANSWERED BEFORE THE CONSENT GATE, with the
  -- revision disclosure in place. Withdraw a partner's consent, replay,
  -- and require the SAME answer including the SAME unchanged revision.
  -- This is Task 11's design restated as a Task 2 assertion: if the
  -- revision read had been placed after the gates, this replay would
  -- raise instead -- and a caller retrying a lost response would be
  -- told its successful publish had failed.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES (v_rel, v_user_b, 'v1', 'withdrawn', gen_random_uuid(), clock_timestamp());
  DECLARE
    v_replay2 record;
  BEGIN
    SELECT * INTO v_replay2 FROM public.publish_ai_session_nearby_result(v_user_a, v_admit.request_id);
    IF v_replay2.committed IS DISTINCT FROM true
       OR v_replay2.user_ordinal != v_pub.user_ordinal
       OR v_replay2.attune_ordinal != v_pub.attune_ordinal THEN
      RAISE EXCEPTION
        'EXPLOIT: after a consent withdrawal, the replay of an ALREADY-COMMITTED publish no longer returns its original answer. Task 11 placed that replay branch BEFORE the consent gate precisely so a retry of a publish that already happened does not look like a failure and drive the caller to publish again. Task 2''s revision read must sit INSIDE that branch, not after the gates.';
    END IF;
    IF v_replay2.session_revision IS DISTINCT FROM v_fence THEN
      RAISE EXCEPTION
        'EXPLOIT: the post-withdrawal replay reported session_revision=% instead of the unchanged %. The replay path must report the CURRENT revision and bump nothing, whatever the consent state.',
        v_replay2.session_revision, v_fence;
    END IF;
  END;
  -- A FRESH publish must still be refused by the gate -- otherwise the
  -- assertion above would be proving that the gate is gone rather than
  -- that the replay precedes it.
  DECLARE
    v_admit3 record;
  BEGIN
    BEGIN
      SELECT * INTO v_admit3 FROM public.admit_ai_session_generation(
        v_user_a, gen_random_uuid(), v_session, v_fence, 'nearby:after-withdrawal'
      );
      RAISE EXCEPTION 'EXPLOIT: a NEW admission succeeded after a partner withdrew AI-processing consent -- the gate the replay assertion above relies on is not there, so that assertion proved nothing.';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
      IF SQLERRM != 'AI processing consent is not current for this relationship' THEN
        RAISE EXCEPTION
          'EXPLOIT: a new admission after a consent withdrawal failed with "%" instead of the expected "AI processing consent is not current for this relationship". The replay-precedes-the-gate assertion above needs the gate to be the thing that refuses a FRESH request; a different error means something else refused it and the asymmetry is unproven.',
          SQLERRM;
      END IF;
    END;
  END;

  -- Restore consent so this fixture leaves the relationship in the
  -- state it found it, for any later contract in this file.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  RAISE NOTICE 'nearby contract 8: a three-turn Nearby session is reachable using ONLY RPC return values (fences %, ..., % from publish''s session_revision); the idempotent replay reports the current revision without re-bumping and is still answered ahead of the consent gate, while a fresh admission is refused',
    v_prepare.revision, v_fence;
END $$;


-- =====================================================================
-- Contract 9 (Task 2): CONTRACT 8 MUST NOT READ public.ai_sessions.
--
-- The Nearby twin of ai_session_commit_ideas_contracts.sql's Contract
-- 6, and necessary for the same reason: Contract 8's whole value is
-- that it drives a multi-turn Nearby session through the RPC SURFACE
-- ALONE, and the single easiest way to "fix" a failing Contract 8 is to
-- add `SELECT revision FROM public.ai_sessions` -- the shortcut every
-- pre-existing test in this suite took, and how the defect stayed
-- hidden for twelve task reviews. A property of the test TEXT is
-- asserted against the test text, not promised in a comment.
--
-- pg_read_file() resolves a relative path against the server's DATA
-- DIRECTORY, not the client's cwd, so a relative path would always fail
-- and this leg would always skip while looking like it passed. The
-- absolute path is interpolated by psql from `pwd`, and handed to the
-- block through a session GUC because psql does NOT interpolate :'var'
-- inside a dollar-quoted body.
-- =====================================================================
\set c9_path `pwd`/supabase/tests/ai_session_nearby_staging_contracts.sql
\o /dev/null
SELECT set_config('attune_test.c9_path', :'c9_path', false);
\o

DO $c9$
DECLARE
  v_path text := current_setting('attune_test.c9_path');
  v_text text;
  v_c8 text;
  v_hits text;
BEGIN
  BEGIN
    v_text := pg_read_file(v_path);
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'nearby contract 9: SKIPPED -- reading % needs superuser or pg_read_server_files, which this role lacks. Local-runner guard only; contract 8 itself ran above.', v_path;
    RETURN;
  END;
  IF v_text IS NULL OR length(v_text) < 10000 THEN
    RAISE EXCEPTION
      'SETUP FAILED: contract 9 read % but got % characters, which is not this file, so its no-raw-read assertion covers the wrong text.',
      v_path, coalesce(length(v_text), 0);
  END IF;

  v_c8 := substring(v_text from position('Contract 8 (Task 2' in v_text));
  v_c8 := substring(v_c8 for position('Contract 9 (Task 2' in v_c8) - 1);
  IF v_c8 IS NULL OR length(v_c8) < 2000 THEN
    RAISE EXCEPTION
      'SETUP FAILED: contract 9 could not isolate contract 8''s text (got % chars); its assertion covers the wrong region and must be re-derived.',
      coalesce(length(v_c8), 0);
  END IF;

  -- Strip comments FIRST: contract 8's own commentary discusses
  -- `SELECT revision FROM public.ai_sessions` while explaining why it
  -- must not do that, so an unstripped match would fail on correct code.
  v_c8 := pg_temp.strip_sql_comments(v_c8);

  SELECT string_agg(btrim(m[1]), ' | ') INTO v_hits
  FROM regexp_matches(v_c8,
         '((?:from|join|into|update)[ \t]+(?:public\.)?ai_sessions\M[^\n]*)',
         'gi') AS m;
  IF v_hits IS NOT NULL THEN
    RAISE EXCEPTION
      'EXPLOIT: contract 8 now reads or writes public.ai_sessions directly: %. It exists to prove a multi-turn Nearby session is reachable through the RPC SURFACE ALONE -- the one thing Plan C''s edge function can do, since it forbids itself raw table reads, public.ai_sessions grants `authenticated` nothing, and a service-role read bypasses all four of spec 7.2''s gates. A direct read makes the contract pass while the defect is fully present. If the revision cannot be had from a return value, that is the defect reasserting itself -- fix the RPC, not the test.',
      v_hits;
  END IF;

  IF NOT ('  SELECT revision INTO v FROM public.ai_sessions WHERE id = v_session;'
          ~* '(?:from|join|into|update)[ \t]+(?:public\.)?ai_sessions\M') THEN
    RAISE EXCEPTION
      'SETUP FAILED: contract 9''s pattern does not match a known-positive raw read, so it asserts NOTHING. Re-derive it.';
  END IF;
  IF ('  SELECT * INTO v_admit FROM public.admit_ai_session_generation(a, b, c, d, e);'
      ~* '(?:from|join|into|update)[ \t]+(?:public\.)?ai_sessions\M') THEN
    RAISE EXCEPTION
      'SETUP FAILED: contract 9''s pattern matches an ordinary RPC call, so it is unsatisfiable.';
  END IF;
  IF v_c8 !~ 'v_fence := v_pub\.session_revision' THEN
    RAISE EXCEPTION
      'SETUP FAILED: the isolated region does not contain contract 8''s fence advance (`v_fence := v_pub.session_revision`), so contract 9 scanned the wrong text and its silence means nothing.';
  END IF;

  RAISE NOTICE 'nearby contract 9: contract 8 touches public.ai_sessions nowhere -- its three-turn Nearby sequence is driven by RPC return values alone';
END $c9$;
