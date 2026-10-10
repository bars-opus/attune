-- commit_ai_session_ideas_turn: atomic two-row insert with correct
-- ordinal parity, idempotent on retry. Spec §6.2 step 5, §7.1.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_commit_ideas_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000009';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000009a';
  v_user_b uuid := 'b1000000-0000-0000-0000-000000000131';
  v_session uuid;
  v_admit record;
  v_row record;
  v_row2 record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_a, 'commit_a@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_a, '+15550015001', 'A') ON CONFLICT DO NOTHING;
  -- FIXTURE COMPLETION (Task 3, merge-blockers plan). This fixture
  -- previously created a ONE-SIDED relationship (user_b NULL) with NO
  -- consent events and still passed, because no dispatch-path RPC in
  -- Plan B ever checked consent -- only the Task 10 read RPCs and
  -- Task 11's Nearby publish did. admit_ai_session_generation now
  -- enforces the membership + AI-processing consent gate spec §7.2
  -- requires (20260953140000), so every admission here needs a real
  -- partner and two current grants.
  --
  -- This is an ADDITION, not a correction: the fixture was incomplete
  -- relative to §7.2, not wrong relative to the code as it then stood.
  -- No assertion below is changed.
  --
  -- A one-sided relationship can never satisfy two-party consent, which
  -- is correct by construction rather than incidental: the gate reads
  -- BOTH r.user_a and r.user_b, and a NULL user_b makes the second
  -- consent lookup filter on `e.user_id = NULL`, match nothing, and
  -- COALESCE(NULL, false) deny. That is the intended semantics for a
  -- relationship with only one member.
  --
  -- clock_timestamp(), never now(): now() is frozen per transaction, so
  -- events written in one DO block would share an identical created_at
  -- and the consent lookup's tiebreak would fall to `id DESC` on a
  -- random uuid, making any consent-ordering assertion a coin flip.
  -- ai_processing_consent_events.idempotency_key is NOT NULL.
  INSERT INTO auth.users (id, email) VALUES (v_user_b, 'admitgate_partner_commit@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_b, '+15550021002', 'B') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_user_a, v_user_b, 'active') ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp');
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);

  -- Contract 1: attempt_n=1 -> ordinals (1, 2).
  SELECT * INTO v_row FROM public.commit_ai_session_ideas_turn(
    v_admit.worker_token, v_admit.request_id, 'brainstorm date ideas', 'a great reply', NULL
  );
  IF v_row.committed IS DISTINCT FROM true OR v_row.user_ordinal != 1 OR v_row.attune_ordinal != 2 THEN
    RAISE EXCEPTION 'EXPLOIT: attempt_n=1 did not produce ordinals (1,2), got committed=% user=% attune=%',
      v_row.committed, v_row.user_ordinal, v_row.attune_ordinal;
  END IF;
  IF (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session) != 2 THEN
    RAISE EXCEPTION 'EXPLOIT: expected exactly 2 turn rows after one committed attempt';
  END IF;
  IF (SELECT role FROM public.ai_session_turns WHERE session_id = v_session AND ordinal = 1) != 'user' THEN
    RAISE EXCEPTION 'EXPLOIT: ordinal 1 is not role=user';
  END IF;
  IF (SELECT role FROM public.ai_session_turns WHERE session_id = v_session AND ordinal = 2) != 'attune' THEN
    RAISE EXCEPTION 'EXPLOIT: ordinal 2 is not role=attune';
  END IF;

  -- Contract 2: retrying the SAME request_id (lost HTTP response) is
  -- idempotent -- same ordinals, no second insert.
  SELECT * INTO v_row2 FROM public.commit_ai_session_ideas_turn(
    v_admit.worker_token, v_admit.request_id, 'brainstorm date ideas', 'a great reply', NULL
  );
  IF v_row2.user_ordinal != v_row.user_ordinal OR v_row2.attune_ordinal != v_row.attune_ordinal THEN
    RAISE EXCEPTION 'EXPLOIT: retrying a committed request produced different ordinals';
  END IF;
  IF (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session) != 2 THEN
    RAISE EXCEPTION 'EXPLOIT: retrying a committed request inserted duplicate turn rows';
  END IF;

  -- Contract 3: a second attempt (attempt_n=2) -> ordinals (3, 4).
  -- Note: expected_revision is 2 here, not 1 -- contract 1's commit
  -- above already advanced ai_sessions.revision from 1 to 2 (brief's
  -- literal sample text used 1 again, which is stale and raises
  -- CONTEXT_CHANGED; this is a test-only correction, not an RPC change).
  DECLARE
    v_admit2 record;
    v_row3 record;
  BEGIN
    SELECT * INTO v_admit2 FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 2, 'ideas:fp-2');
    PERFORM public.claim_ai_session_dispatch(v_admit2.worker_token, v_admit2.request_id);
    SELECT * INTO v_row3 FROM public.commit_ai_session_ideas_turn(
      v_admit2.worker_token, v_admit2.request_id, 'a second instruction', 'a second reply', NULL
    );
    IF v_row3.user_ordinal != 3 OR v_row3.attune_ordinal != 4 THEN
      RAISE EXCEPTION 'EXPLOIT: attempt_n=2 did not produce ordinals (3,4), got user=% attune=%', v_row3.user_ordinal, v_row3.attune_ordinal;
    END IF;
  END;

  RAISE NOTICE 'commit_ai_session_ideas_turn contracts: all held';
END $$;


-- =====================================================================
-- Contract 4 (merge-blocker fix 20260953120000): THE LOCK ORDER,
-- STRUCTURALLY, on the comment-stripped live body.
--
-- THE DEFECT THIS PINS. commit_ai_session_ideas_turn took the
-- ai_session_requests row FOR UPDATE as its FIRST lock and only then
-- touched ai_sessions, and took no relationship advisory lock at all.
-- The order is fixed at relationship advisory lock -> quota advisory
-- lock (inside reserve_ai_assistant_quota, admission path only) ->
-- session row -> request row. end_ai_session, purge_ai_session_content,
-- admit_ai_session_generation and reconcile_ai_session_leases all take
-- that order; this RPC inverted its last two, which deadlocked against
-- every one of them -- measured 10/10 trials against end_ai_session on
-- unmodified shipped code, with the victim alternating between the
-- worker's commit and the user's own End action.
--
-- WHY STRUCTURAL AND NOT BEHAVIOURAL. A deadlock needs two concurrent
-- backends, which a single-transaction SQL contract cannot create --
-- that is exactly why no committed test caught this for eleven task
-- reviews. The behavioural proof is
-- supabase/tests/ai_session_completion_concurrent_test.sh, which races
-- real backends. This contract is the cheap always-on guard that the
-- ORDER has not rotted back, and it runs in the main suite.
--
-- WHY position() AND NOT A PRESENCE CHECK. A presence check passes a
-- body that still contains all three lock statements in the WRONG
-- order -- which is precisely the pre-fix body plus an advisory lock
-- bolted on at the end. Positions are compared so a REORDERING fails
-- with every statement present.
--
-- WHY THE SECOND `FOR UPDATE` AND NOT `FROM public.ai_session_requests`.
-- The fixed body reads ai_session_requests TWICE: once unlocked, at the
-- very top, purely to resolve which relationship and session to lock
-- (it decides nothing -- every guard is evaluated from the locked
-- re-read), and once FOR UPDATE under both locks. So the TABLE NAME now
-- legitimately appears BEFORE the advisory lock, and an assertion keyed
-- on the table name would fail on the correct body. The request ROW
-- LOCK is the second of exactly two FOR UPDATEs; that is what is
-- ordered, and the count is asserted so the marker cannot silently stop
-- discriminating.
--
-- COMMENTS ARE STRIPPED FIRST. pg_get_functiondef() returns them
-- verbatim and 20260953120000's own comments name all three locks in
-- the right order, so an unstripped match would be satisfied by the
-- commentary alone even if every lock were deleted (Task 10's finding
-- N1, measured there on 4/4 structural assertions).
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
BEGIN
  v_def := pg_temp.strip_sql_comments(pg_get_functiondef(
    'public.commit_ai_session_ideas_turn(uuid, uuid, text, text, jsonb)'::regprocedure));

  -- LOCK 1 must exist at all. The superseded body (20260953070000) has
  -- no advisory lock anywhere, so this leg alone catches a full revert.
  v_adv := position('pg_advisory_xact_lock(hashtext(' in v_def);
  IF v_adv = 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: commit_ai_session_ideas_turn takes NO relationship advisory lock. It is the FIRST lock in this plan''s fixed, non-negotiable order, and this RPC races end_ai_session, purge_ai_session_content and admit_ai_session_generation on the same session -- all three of which take it first. Without it this RPC deadlocked against end_ai_session in 10/10 measured trials, killing the user''s own End action in 3 of them. That is Task 7''s superseded body (20260953070000); 20260953120000 WINS.';
  END IF;

  -- Exactly two row locks, in a known order: session row, then request
  -- row. Asserted so the "second FOR UPDATE" marker below cannot
  -- silently stop meaning what it says.
  v_fu_count := (length(v_def) - length(replace(v_def, 'FOR UPDATE', ''))) / length('FOR UPDATE');
  IF v_fu_count <> 2 THEN
    RAISE EXCEPTION
      'SETUP FAILED: commit_ai_session_ideas_turn has % FOR UPDATE clause(s), expected exactly 2 (the ai_sessions row then the ai_session_requests row). This contract''s ordering legs identify the request row lock as the SECOND FOR UPDATE, so they no longer discriminate and must be re-derived.',
      v_fu_count;
  END IF;

  -- LOCK 2: the session row, locked explicitly. The pre-fix body never
  -- locked it explicitly at all -- it acquired it implicitly, via the
  -- ai_session_turns INSERT's FK check taking FOR KEY SHARE on the
  -- parent, which is where the deadlock actually fired (before the
  -- explicit revision bump was ever reached). An explicit FOR UPDATE
  -- taken first subsumes that implicit lock and makes the acquisition
  -- order deterministic instead of statement-order-dependent.
  v_sess_fu := position('FROM public.ai_sessions WHERE id = v_session_id FOR UPDATE' in v_def);
  IF v_sess_fu = 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: commit_ai_session_ideas_turn does not lock the ai_sessions row explicitly. It takes that row''s lock REGARDLESS -- the ai_session_turns INSERT''s FK check takes FOR KEY SHARE on the parent session row, and the revision bump takes it exclusively -- so the only question is in what ORDER. Lock it explicitly, before the request row, or the order is whatever the statement sequence happens to produce, which is the deadlock.';
  END IF;

  -- LOCK 3: the request row. Identified by its own full locked-read
  -- text, so this is an ABSOLUTE position comparable with the two
  -- above -- not an offset into a substring, which would make the
  -- ordering comparison below tautologically true and therefore
  -- vacuous.
  v_req_fu := position('WHERE id = p_request_id AND worker_token = p_worker_token
  FOR UPDATE' in v_def);
  IF v_req_fu = 0 THEN
    RAISE EXCEPTION
      'SETUP FAILED: commit_ai_session_ideas_turn has no `WHERE id = p_request_id AND worker_token = p_worker_token FOR UPDATE` locked read -- the request row is no longer locked under that predicate, or this contract''s marker must be re-derived.';
  END IF;

  -- THE ORDERING ITSELF.
  IF v_adv > v_sess_fu THEN
    RAISE EXCEPTION
      'LOCK ORDER VIOLATED: commit_ai_session_ideas_turn locks the ai_sessions ROW before the relationship advisory lock (advisory at %, session row at %). The order is fixed at relationship -> session row -> request row and must never vary; inverting it deadlocks against end_ai_session, purge_ai_session_content and admit_ai_session_generation, which all take the advisory lock first. A change needing a different order is a plan defect, not a local decision.',
      v_adv, v_sess_fu;
  END IF;
  -- THE INVERSION ITSELF: this is the comparison that fails on the
  -- pre-fix body. Both are absolute positions in the same string, so a
  -- reordering fails here with all three lock statements still present.
  IF v_sess_fu > v_req_fu THEN
    RAISE EXCEPTION
      'LOCK ORDER VIOLATED: commit_ai_session_ideas_turn locks the ai_session_requests row (at %) before the ai_sessions row (at %) -- the exact inversion 20260953120000 exists to fix, which deadlocked against end_ai_session in 10/10 measured trials. The order is fixed at relationship -> session row -> request row.',
      v_req_fu, v_sess_fu;
  END IF;

  -- ANTI-VACUITY, THE OTHER DIRECTION: the advisory lock must be keyed
  -- on the RELATIONSHIP, not on the session or the request. A
  -- per-session key would serialize nothing against end_ai_session's
  -- per-relationship key and the deadlock would come straight back
  -- while every leg above still passed.
  IF v_def !~ 'pg_advisory_xact_lock\(hashtext\(v_relationship_id::text\)\)' THEN
    RAISE EXCEPTION
      'EXPLOIT: commit_ai_session_ideas_turn''s advisory lock is not keyed on hashtext(v_relationship_id::text). end_ai_session, purge_ai_session_content, admit_ai_session_generation and reconcile_ai_session_leases all key on the RELATIONSHIP; a different key serializes against none of them and the deadlock returns.';
  END IF;

  -- THE AUTHENTICATION PREDICATE IS ON THE LOCKED ROW. The marker used
  -- for LOCK 3 above is deliberately the FULL locked read including
  -- `AND worker_token = p_worker_token`, not a bare FOR UPDATE: that
  -- predicate IS this RPC's authentication -- it has no actor parameter
  -- (Global Constraint: validate the actor parameter as the first
  -- statement; here the worker token is validated by the same statement
  -- that authenticates it) -- and it must be enforced on the row the
  -- function ACTS on, not only on the unlocked lock-target pre-read.
  -- A body that locked the request row without re-checking the token
  -- fails the LOCK 3 marker above, by construction.
  --
  -- THE PRE-READ MUST STAY UNLOCKED. If the lock-target lookup ever
  -- acquired a lock of its own it would be a third row lock taken
  -- BEFORE the advisory lock, reintroducing the inversion ahead of
  -- everything this contract checks. The FOR UPDATE count of exactly 2
  -- asserted above is what forbids that.

  RAISE NOTICE 'commit contract 4: lock order relationship -> session row -> request row holds structurally';
END $$;
