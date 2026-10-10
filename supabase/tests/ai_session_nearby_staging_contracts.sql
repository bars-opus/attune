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
    v_user_a, gen_random_uuid(), v_rel, 'nearby', 'shared', NULL, false
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
    -- Note: expected_revision is 2 here, not 1 -- contract 3's publish
    -- bumped ai_sessions.revision from 1 to 2.
    SELECT * INTO v_admit2 FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 2, 'nearby:fp-2');
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
  IF v_def !~ 'COALESCE\(v_a_granted, false\) AND COALESCE\(v_b_granted, false\)' THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: publish_ai_session_nearby_result no longer enforces the both-partner consent gate. 20260953120000 BUILDS ON Task 11''s 20260953110000 and must preserve that gate; a lock-order fix that reverted to Task 8''s pre-gate body would commit a staged Nearby result into the permanent transcript after a partner withdrew AI-processing consent.';
  END IF;
  IF v_def !~ 'v_relationship_id uuid' OR v_def !~ 'WHERE r\.id = v_relationship_id' THEN
    RAISE EXCEPTION
      'EXPLOIT: publish_ai_session_nearby_result''s membership gate no longer reads v_relationship_id -- the value the lock-order fix hoisted to the top for the advisory lock is the SAME value the gate must compare against. A gate reading a different (or NULL) relationship denies or permits by accident.';
  END IF;

  RAISE NOTICE 'nearby contract 5: stage and publish both lock relationship -> session row -> request row; publish''s consent gate and first-statement actor guard intact';
END $$;
