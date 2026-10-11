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
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false, NULL
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
  --
  -- The expected_revision comes from `v_row2.session_revision` -- the
  -- value the replay in contract 2 just reported -- NOT from a literal.
  --
  -- It used to be a literal `2`, with a note explaining that 1 "is
  -- stale and raises CONTEXT_CHANGED". Task 2 (20260953170000) replaced
  -- that literal, for a reason measured rather than assumed: a mutant
  -- that made the idempotent-replay path RE-BUMP the revision killed
  -- this contract first, at this line, with a bare `CONTEXT_CHANGED` --
  -- which says nothing about what actually broke and masked the named
  -- assertion in contract 5 that exists to diagnose exactly that defect.
  -- A hardcoded fence is a test asserting a number it computed by hand;
  -- a returned fence is a test asserting the RPC's own answer, and it
  -- fails in the right place with the right message. This is a
  -- test-only change: no assertion below it is altered or removed, and
  -- the value is the same 2 on correct code.
  DECLARE
    v_admit2 record;
    v_row3 record;
  BEGIN
    IF v_row2.session_revision IS NULL THEN
      RAISE EXCEPTION
        'SETUP FAILED: contract 2''s replay reported a NULL session_revision, so contract 3 has no fence to admit on. commit_ai_session_ideas_turn must disclose the current revision even on an idempotent replay (20260953170000).';
    END IF;
    SELECT * INTO v_admit2 FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, v_row2.session_revision, 'ideas:fp-2');
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


-- =====================================================================
-- Contract 5 (Task 2, merge-blocker fix 20260953170000): A GENUINE
-- TWO-TURN IDEAS SESSION DRIVEN ENTIRELY BY RPC RETURN VALUES, WITH NO
-- READ OF public.ai_sessions ANYWHERE.
--
-- THIS IS THE ASSERTION WHOSE ABSENCE HID THE DEFECT, so it is worth
-- being precise about what it proves and what the older contracts do
-- not.
--
-- THE DEFECT. admit_ai_session_generation fences on the session
-- revision: it raises 'CONTEXT_CHANGED' unless p_expected_revision
-- equals ai_sessions.revision. commit_ai_session_ideas_turn bumps that
-- revision as its last write. Until 20260953170000, NO RPC returned
-- it -- verified by catalog query: the only function in this plan whose
-- result type mentioned `revision` was prepare_ai_session, which
-- returns the INITIAL value and is never called again inside a live
-- session. So turn 1 admitted, commit bumped 1->2, and turn 2 had no
-- legitimate way to learn that 2 was now the answer. The branch's
-- stated purpose -- bounded MULTI-TURN AI sessions -- was unreachable
-- by its only intended consumer.
--
-- WHY CONTRACT 3 ABOVE DID NOT CATCH IT. Contract 3 does run a second
-- attempt, and it does pass -- because it hardcodes the literal `2`,
-- with a comment explaining that `1` "is stale and raises
-- CONTEXT_CHANGED". A literal works in a test that knows statically how
-- many turns preceded it. It is exactly the knowledge Plan C's edge
-- function does NOT have: it handles a turn on a session it did not
-- create, whose turn count it cannot know, and it forbids itself raw
-- table reads. Every other committed test in this suite got past turn 1
-- the same way -- a literal, or a direct `SELECT revision FROM
-- public.ai_sessions`. A direct read is not available to a real caller
-- either: public.ai_sessions grants NOTHING to `authenticated` (56
-- combinations asserted at 0 leaked in
-- ai_session_read_authorization_contracts.sql and
-- ai_session_purge_contracts.sql), and reading it with the service role
-- would bypass ALL FOUR of spec §7.2's authorization gates.
--
-- WHAT THIS CONTRACT DOES INSTEAD. It plays the caller. Every revision
-- it feeds to admit comes from a value an RPC RETURNED:
--
--   prepare_ai_session   -> .revision          (turn 1's fence)
--   admit -> claim -> commit_ai_session_ideas_turn
--                        -> .session_revision  (turn 2's fence)
--   admit -> claim -> commit_ai_session_ideas_turn
--                        -> .session_revision  (turn 3's fence)
--
-- It reaches TURN THREE on purpose rather than stopping at two: a
-- single hop could pass by coincidence if session_revision happened to
-- be a constant, or the ordinal, or the attempt number. Three hops with
-- a strictly increasing fence cannot.
--
-- HOW IT FAILS IF REVISION DISCLOSURE IS REMOVED. With
-- session_revision gone from the return shape, `v_commit.session_revision`
-- does not resolve and the block raises at that reference -- which is a
-- real failure but a syntactic one. So the contract does NOT rely on
-- that: it asserts the returned value is NOT NULL and is EXACTLY the
-- value admit then accepts, and it wraps each admit in a handler that
-- converts a 'CONTEXT_CHANGED' into this contract's own named,
-- specific message. Remove the disclosure and substitute a NULL, a
-- stale value, or a constant, and the admit raises CONTEXT_CHANGED and
-- this contract reports exactly which turn could not be reached and
-- with what fence.
--
-- NO READ OF public.ai_sessions. Asserted mechanically, not promised:
-- the final leg greps this very file for the pattern and fails if one
-- appears. That is what makes the contract a proof about the RPC
-- SURFACE rather than about the database.
-- =====================================================================
DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000150';
  v_user_a uuid := 'b1000000-0000-0000-0000-000000000151';
  v_user_b uuid := 'b1000000-0000-0000-0000-000000000152';
  v_session uuid;
  v_prepare record;
  v_admit record;
  v_commit record;
  -- THE ONLY revision state this block keeps. It is seeded from
  -- prepare_ai_session's returned value and thereafter advanced ONLY by
  -- assigning a value a completion RPC returned. It is never read from
  -- a table.
  v_fence int;
  v_turn int;
  v_expect_user int;
  v_expect_attune int;
  v_self text;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'twoturn_a@t.test'), (v_user_b, 'twoturn_b@t.test')
  ON CONFLICT DO NOTHING;
  -- users.phone is UNIQUE and an ON CONFLICT DO NOTHING insert that
  -- silently collides is how several fixture bugs in this plan's
  -- history produced false passes. +1555002200x was swept against the
  -- whole of supabase/ and scripts/ before being chosen, and the
  -- membership assertion below would fail loudly if either row had in
  -- fact been dropped.
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550022001', 'A'), (v_user_b, '+15550022002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  -- admit_ai_session_generation enforces the membership + two-party
  -- AI-processing consent gate (20260953140000, Task 3), so BOTH
  -- partners must hold a current grant or every admit below raises
  -- before it ever reaches the revision fence -- which would make this
  -- contract fail for the wrong reason.
  --
  -- clock_timestamp(), never now(): now() is frozen per transaction, so
  -- two events written in one DO block would share an identical
  -- created_at and the consent lookup's tiebreak would fall to
  -- `id DESC` on a random uuid. ai_processing_consent_events.
  -- idempotency_key is NOT NULL.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  -- FIXTURE ANTI-VACUITY: prove the fixture is actually there. A
  -- silently-collided users insert, or a relationship row that already
  -- existed with different members, would otherwise make the consent
  -- gate deny and every CONTEXT_CHANGED assertion below unreachable --
  -- the contract would fail, but with a message blaming the wrong
  -- thing.
  IF NOT EXISTS (SELECT 1 FROM public.relationships r
                 WHERE r.id = v_rel AND r.user_a = v_user_a AND r.user_b = v_user_b
                   AND r.status = 'active' AND r.chat_archived_at IS NULL) THEN
    RAISE EXCEPTION
      'SETUP FAILED: contract 5''s relationship fixture is not the two active members this contract needs -- most likely a uuid collision with another test file. Every admit below would deny on the membership gate and this contract would report a revision problem it never actually tested.';
  END IF;

  -- ---- TURN 1's FENCE comes from prepare_ai_session, the one RPC that
  -- has always returned a revision. This is the ONLY place the fence is
  -- seeded; everything after it must come from a completion RPC.
  SELECT * INTO v_prepare FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false, NULL
  );
  v_session := v_prepare.session_id;
  v_fence := v_prepare.revision;
  IF v_fence IS NULL THEN
    RAISE EXCEPTION
      'SETUP FAILED: prepare_ai_session returned a NULL revision, so this contract has no legitimate starting fence and cannot distinguish a disclosure defect from a preparation defect.';
  END IF;

  PERFORM public.approve_ai_session_context(v_user_a, v_session, v_fence, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, v_fence);

  -- ---- THREE TURNS, each fenced ONLY on a value an RPC returned.
  FOR v_turn IN 1..3 LOOP
    v_expect_user := (v_turn * 2) - 1;
    v_expect_attune := v_turn * 2;

    -- The admit. If the fence this loop is carrying is stale -- which is
    -- precisely what happens when the revision is not disclosed and the
    -- caller has to guess -- this raises 'CONTEXT_CHANGED'. Caught and
    -- re-raised with a message naming the turn and the fence, because
    -- the bare code says nothing about which hop broke.
    BEGIN
      SELECT * INTO v_admit FROM public.admit_ai_session_generation(
        v_user_a, gen_random_uuid(), v_session, v_fence, 'ideas:twoturn-' || v_turn
      );
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM = 'CONTEXT_CHANGED' THEN
        RAISE EXCEPTION
          'EXPLOIT: TURN % IS UNREACHABLE. admit_ai_session_generation raised CONTEXT_CHANGED on expected_revision=%, and % is the most recent revision any RPC in this plan DISCLOSED to its caller. A multi-turn session is therefore unreachable without reading public.ai_sessions directly -- a raw table read Plan C''s edge function forbids itself, which the table''s grants deny to `authenticated` outright, and which bypasses all four of spec §7.2''s authorization gates. commit_ai_session_ideas_turn must return the revision it bumped (migration 20260953170000).',
          v_turn, v_fence, v_fence;
      END IF;
      RAISE;
    END;
    IF v_admit.outcome IS DISTINCT FROM 'admitted' THEN
      RAISE EXCEPTION 'EXPLOIT: turn % was not admitted (outcome=%) even with a fence this contract obtained from an RPC return value',
        v_turn, v_admit.outcome;
    END IF;

    IF NOT public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id) THEN
      RAISE EXCEPTION 'SETUP FAILED: turn % could not be claimed, so the commit below never runs', v_turn;
    END IF;

    SELECT * INTO v_commit FROM public.commit_ai_session_ideas_turn(
      v_admit.worker_token, v_admit.request_id,
      'instruction ' || v_turn, 'reply ' || v_turn, NULL
    );

    IF v_commit.committed IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'EXPLOIT: turn %''s commit did not report committed=true', v_turn;
    END IF;
    -- Ordinal parity 2n-1 / 2n, both from the same n -- re-asserted here
    -- because this is the only contract that drives three consecutive
    -- real attempts through the real admit, and a fence bug could
    -- otherwise be masked by an attempt counter that silently reset.
    IF v_commit.user_ordinal != v_expect_user OR v_commit.attune_ordinal != v_expect_attune THEN
      RAISE EXCEPTION 'EXPLOIT: turn % produced ordinals (%,%), expected (%,%)',
        v_turn, v_commit.user_ordinal, v_commit.attune_ordinal, v_expect_user, v_expect_attune;
    END IF;

    -- ---- THE DISCLOSURE ITSELF.
    IF v_commit.session_revision IS NULL THEN
      RAISE EXCEPTION
        'EXPLOIT: commit_ai_session_ideas_turn returned a NULL session_revision on turn %. The field exists but carries nothing, so the next admit has no fence and the session is single-turn in practice. 20260953170000 takes the value from the revision bump''s own RETURNING clause, which cannot be NULL for a row that was just updated.',
        v_turn;
    END IF;
    -- It must STRICTLY ADVANCE. A constant, a copy of the ordinal, or a
    -- stale pre-bump read would all satisfy NOT NULL while leaving the
    -- next admit to raise CONTEXT_CHANGED.
    IF v_commit.session_revision <= v_fence THEN
      RAISE EXCEPTION
        'EXPLOIT: commit_ai_session_ideas_turn returned session_revision=% on turn %, which does not advance past the fence % this turn was admitted on. The commit bumps ai_sessions.revision, so the value it discloses must be the POST-bump revision -- a pre-bump read would send the caller back with the same stale fence it already had.',
        v_commit.session_revision, v_turn, v_fence;
    END IF;

    -- ADVANCE THE FENCE USING ONLY THE RETURNED VALUE. This single
    -- assignment is the whole point of the contract: there is no table
    -- read here, and the next iteration's admit will accept this value
    -- or fail.
    v_fence := v_commit.session_revision;
  END LOOP;

  -- Six turn rows: three attempts x two rows, ordinals 1..6 with no
  -- gaps. Proves the three hops were real attempts rather than three
  -- idempotent replays of one.
  IF (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session) != 6 THEN
    RAISE EXCEPTION 'EXPLOIT: three committed attempts did not produce exactly 6 turn rows (got %)',
      (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session);
  END IF;
  IF (SELECT count(DISTINCT ordinal) FROM public.ai_session_turns WHERE session_id = v_session) != 6
     OR (SELECT min(ordinal) FROM public.ai_session_turns WHERE session_id = v_session) != 1
     OR (SELECT max(ordinal) FROM public.ai_session_turns WHERE session_id = v_session) != 6 THEN
    RAISE EXCEPTION 'EXPLOIT: the three attempts did not produce ordinals 1..6 contiguously';
  END IF;

  -- ---- ANTI-VACUITY: THE FENCE MUST HAVE ACTUALLY MOVED. If
  -- ai_sessions.revision never changed, every admit above would have
  -- accepted the SAME value and the loop would pass while proving
  -- nothing about disclosure at all. Compare against the seed from
  -- prepare_ai_session -- still a returned value, not a table read.
  IF v_fence <= v_prepare.revision THEN
    RAISE EXCEPTION
      'SETUP FAILED: after three commits the disclosed revision (%) has not advanced past prepare_ai_session''s initial value (%). Either the commits stopped bumping ai_sessions.revision -- in which case admit''s optimistic fence guards nothing and a stale client would be admitted silently -- or every admit above accepted an unchanging value and this contract proved nothing. Both are defects; neither is this contract passing.',
      v_fence, v_prepare.revision;
  END IF;

  -- ---- THE IDEMPOTENT REPLAY MUST REPORT THE CURRENT REVISION AND NOT
  -- RE-BUMP IT. This is the other half of the fix and it is load-bearing
  -- in the opposite direction: a replay that re-bumped would invalidate
  -- the fence the caller is holding and guarantee CONTEXT_CHANGED on the
  -- next admit -- breaking the very reachability the disclosure exists
  -- to provide, and doing so a different number of times depending on
  -- how often the caller retried a lost response.
  DECLARE
    v_replay record;
  BEGIN
    SELECT * INTO v_replay FROM public.commit_ai_session_ideas_turn(
      v_admit.worker_token, v_admit.request_id,
      'instruction 3', 'reply 3', NULL
    );
    IF v_replay.committed IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'EXPLOIT: replaying a committed request did not report committed=true';
    END IF;
    IF v_replay.user_ordinal != v_commit.user_ordinal
       OR v_replay.attune_ordinal != v_commit.attune_ordinal THEN
      RAISE EXCEPTION 'EXPLOIT: replaying a committed request produced different ordinals';
    END IF;
    IF v_replay.session_revision IS DISTINCT FROM v_fence THEN
      RAISE EXCEPTION
        'EXPLOIT: the idempotent replay of commit_ai_session_ideas_turn reported session_revision=% but the current revision is % -- the replay path RE-BUMPED the revision (or read a stale one). A replay inserts nothing and must bump nothing: it already answered committed=true with the original ordinals, and changing the revision under a caller that is holding % as its fence guarantees CONTEXT_CHANGED on its next admit. That breaks exactly the multi-turn reachability 20260953170000 exists to enable, non-deterministically, as a function of how many times the caller retried.',
        v_replay.session_revision, v_fence, v_fence;
    END IF;
    IF (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session) != 6 THEN
      RAISE EXCEPTION 'EXPLOIT: the replay inserted turn rows';
    END IF;
  END;

  -- ---- A FOURTH TURN STILL WORKS AFTER THE REPLAY. The sharpest
  -- behavioural form of "the replay did not re-bump": take the fence the
  -- replay reported and admit on it. If the replay had bumped, this
  -- raises CONTEXT_CHANGED.
  BEGIN
    SELECT * INTO v_admit FROM public.admit_ai_session_generation(
      v_user_a, gen_random_uuid(), v_session, v_fence, 'ideas:twoturn-after-replay'
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'CONTEXT_CHANGED' THEN
      RAISE EXCEPTION
        'EXPLOIT: after an idempotent REPLAY of an already-committed commit, admit_ai_session_generation raised CONTEXT_CHANGED on the fence the replay itself reported (%). The replay re-bumped the revision, so a caller that retried a lost response is now permanently one revision behind with no way to catch up except a raw ai_sessions read.',
        v_fence;
    END IF;
    RAISE;
  END;
  IF v_admit.outcome IS DISTINCT FROM 'admitted' THEN
    RAISE EXCEPTION 'EXPLOIT: the turn after an idempotent replay was not admitted (outcome=%)', v_admit.outcome;
  END IF;

  RAISE NOTICE 'commit contract 5: a three-turn Ideas session is reachable using ONLY RPC return values (fences %, ..., % from commit''s session_revision); the idempotent replay reports the current revision without re-bumping, and a further turn is admitted on it',
    v_prepare.revision, v_fence;
END $$;


-- =====================================================================
-- Contract 6 (Task 2): CONTRACT 5 MUST NOT READ public.ai_sessions.
--
-- Contract 5's entire value is that it drives a multi-turn session
-- through the RPC SURFACE ONLY. That property is a property of the TEST
-- TEXT, so it is asserted against the test text -- not promised in a
-- comment. Without this leg, the single easiest way to "fix" a failing
-- Contract 5 is to add `SELECT revision FROM public.ai_sessions`, which
-- is exactly the shortcut every other test in this suite took and
-- exactly how the defect stayed hidden for twelve task reviews.
--
-- HOW THE FILE IS READ. pg_read_file() resolves a RELATIVE path against
-- the server's data directory, not the client's working directory, so a
-- relative path here would ALWAYS fail -- and a leg that always skips
-- asserts nothing while looking like it passes. The absolute path is
-- therefore interpolated by psql itself from `pwd` at the top of this
-- block, which keeps the contract correct in any worktree or checkout
-- location without hardcoding one.
--
-- Reading a server-side file needs superuser or pg_read_server_files,
-- which the local runner has and a deployed Supabase role does not. So
-- the read is still wrapped: it SKIPS WITH A LOUD NOTICE that names the
-- reason. A skip is honest. What this contract refuses to do is skip
-- SILENTLY, or skip because of a path bug it could have fixed.
-- =====================================================================
-- psql does NOT interpolate :'var' inside a dollar-quoted body, so the
-- path is handed to the block through a session GUC rather than
-- textually. set_config with is_local=false keeps it for the session;
-- the name is namespaced so it cannot collide with anything real.
\set c6_path `pwd`/supabase/tests/ai_session_commit_ideas_contracts.sql
\o /dev/null
SELECT set_config('attune_test.c6_path', :'c6_path', false);
\o

DO $c6$
DECLARE
  v_path text := current_setting('attune_test.c6_path');
  v_text text;
  v_c5 text;
  v_hits text;
BEGIN
  BEGIN
    v_text := pg_read_file(v_path);
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'commit contract 6: SKIPPED -- reading % needs superuser or pg_read_server_files, which this role lacks. Local-runner guard only; contract 5 itself ran above.', v_path;
    RETURN;
  END;
  IF v_text IS NULL OR length(v_text) < 10000 THEN
    RAISE EXCEPTION
      'SETUP FAILED: contract 6 read % but got % characters, which is not this file. Its no-raw-read assertion would cover the wrong text, so it must not be trusted. (pg_read_file resolves relative paths against the server data directory -- this contract interpolates an absolute path from `pwd` for exactly that reason.)',
      v_path, coalesce(length(v_text), 0);
  END IF;

  -- Isolate contract 5's own region: from its banner to contract 6's.
  v_c5 := substring(v_text from position('Contract 5 (Task 2' in v_text));
  v_c5 := substring(v_c5 for position('Contract 6 (Task 2' in v_c5) - 1);
  IF v_c5 IS NULL OR length(v_c5) < 2000 THEN
    RAISE EXCEPTION
      'SETUP FAILED: contract 6 could not isolate contract 5''s text (got % chars), so its no-raw-read assertion covers the wrong region and must be re-derived.',
      coalesce(length(v_c5), 0);
  END IF;

  -- Strip SQL comments FIRST. Contract 5's own commentary discusses
  -- `SELECT revision FROM public.ai_sessions` at length, explaining why
  -- it must not do that -- so an unstripped match would be satisfied by
  -- the explanation and this leg would fail on correct code. Same
  -- discipline the structural lock contracts use, for the same reason
  -- (Task 10's finding N1).
  v_c5 := pg_temp.strip_sql_comments(v_c5);

  -- Any FROM/JOIN/INTO/UPDATE naming ai_sessions. Deliberately broader
  -- than `SELECT revision`: reading expires_at, state or
  -- context_revision from the table is the same violation wearing a
  -- different column name.
  SELECT string_agg(btrim(m[1]), ' | ') INTO v_hits
  FROM regexp_matches(v_c5,
         '((?:from|join|into|update)[ \t]+(?:public\.)?ai_sessions\M[^\n]*)',
         'gi') AS m;
  IF v_hits IS NOT NULL THEN
    RAISE EXCEPTION
      'EXPLOIT: contract 5 now reads or writes public.ai_sessions directly: %. That contract exists to prove a multi-turn session is reachable through the RPC SURFACE ALONE, which is the one thing Plan C''s edge function can actually do -- it forbids itself raw table reads, public.ai_sessions grants `authenticated` nothing (56 combinations asserted at 0 leaked), and a service-role read bypasses all four of spec 7.2''s authorization gates. A direct read makes the contract pass while the defect (no RPC discloses the revision) is fully present. If the revision genuinely cannot be obtained from a return value, that is the defect reasserting itself -- fix the RPC, not the test.',
      v_hits;
  END IF;

  -- ANTI-VACUITY: the pattern must be able to match. Prove it on a
  -- known-positive string, or a rotted regex makes this leg pass
  -- forever while asserting nothing.
  IF NOT ('  SELECT revision INTO v FROM public.ai_sessions WHERE id = v_session;'
          ~* '(?:from|join|into|update)[ \t]+(?:public\.)?ai_sessions\M') THEN
    RAISE EXCEPTION
      'SETUP FAILED: contract 6''s pattern does not match a known-positive raw read, so it asserts NOTHING. Re-derive it.';
  END IF;
  -- ...and must NOT match the RPC calls contract 5 legitimately makes,
  -- or the contract would be unsatisfiable and someone would delete it.
  IF ('  SELECT * INTO v_admit FROM public.admit_ai_session_generation(a, b, c, d, e);'
      ~* '(?:from|join|into|update)[ \t]+(?:public\.)?ai_sessions\M') THEN
    RAISE EXCEPTION
      'SETUP FAILED: contract 6''s pattern matches an ordinary RPC call, so it is unsatisfiable and would fail on correct code.';
  END IF;
  -- ...and the ISOLATION must really have landed on contract 5: that
  -- region must contain the loop that drives the turns. Without this,
  -- a substring() that silently returned the wrong slice would make the
  -- scan pass over text that was never contract 5.
  IF v_c5 !~ 'v_fence := v_commit\.session_revision' THEN
    RAISE EXCEPTION
      'SETUP FAILED: the isolated region does not contain contract 5''s fence advance (`v_fence := v_commit.session_revision`), so contract 6 scanned the wrong text and its silence means nothing.';
  END IF;

  RAISE NOTICE 'commit contract 6: contract 5 touches public.ai_sessions nowhere -- its three-turn sequence is driven by RPC return values alone';
END $c6$;
