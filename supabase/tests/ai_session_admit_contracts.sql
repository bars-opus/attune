-- admit_ai_session_generation: the full §6.2 admission sequence.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_admit_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000008';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000004a';
  v_user_b uuid := 'b1000000-0000-0000-0000-000000000130';
  v_session uuid;
  v_row record;
  v_row2 record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_a, 'admit_a@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_a, '+15550012001', 'A') ON CONFLICT DO NOTHING;
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
  INSERT INTO auth.users (id, email) VALUES (v_user_b, 'admitgate_partner_admit@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_b, '+15550021001', 'B') ON CONFLICT DO NOTHING;
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

  -- Contract 1: a fresh admission succeeds, attempt_n=1, ordinals
  -- would be (1,2) -- proven indirectly via attempt_n here; Task 8's
  -- own test proves the ordinal pair itself once turns are committed.
  SELECT * INTO v_row FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp-1'
  );
  IF v_row.outcome IS DISTINCT FROM 'admitted' OR v_row.attempt_n IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: fresh admission did not succeed with attempt_n=1, got outcome=% attempt_n=%', v_row.outcome, v_row.attempt_n;
  END IF;

  -- Contract 2: a SECOND admission for the SAME session while the
  -- first is still in-flight (state='reserved', no completion yet) is
  -- rejected as 'busy' -- one in-flight attempt per session (spec §6.2
  -- step 3).
  SELECT * INTO v_row2 FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp-2'
  );
  IF v_row2.outcome IS DISTINCT FROM 'busy' THEN
    RAISE EXCEPTION 'EXPLOIT: a second admission was allowed while the first attempt is still in-flight, got %', v_row2.outcome;
  END IF;

  -- Contract 3: replaying the SAME request_id as Contract 1 returns
  -- 'already_admitted' with the SAME attempt_n/worker_token, not a
  -- fresh admission (idempotency).
  SELECT * INTO v_row2 FROM public.admit_ai_session_generation(
    v_user_a, v_row.request_id, v_session, 1, 'ideas:fp-1'
  );
  IF v_row2.outcome IS DISTINCT FROM 'already_admitted'
     OR v_row2.attempt_n IS DISTINCT FROM v_row.attempt_n
     OR v_row2.worker_token IS DISTINCT FROM v_row.worker_token THEN
    RAISE EXCEPTION 'EXPLOIT: replaying the same request_id did not return the SAME attempt/worker_token';
  END IF;

  -- Contract 4: replaying the SAME request_id with a DIFFERENT
  -- operation_fingerprint is a conflict (spec §6.2 step 2: "Conflicting
  -- operation/session/non-location payload reuse fails").
  SELECT * INTO v_row2 FROM public.admit_ai_session_generation(
    v_user_a, v_row.request_id, v_session, 1, 'ideas:fp-DIFFERENT'
  );
  IF v_row2.outcome IS DISTINCT FROM 'conflict' THEN
    RAISE EXCEPTION 'EXPLOIT: replaying the same request_id with a different fingerprint was accepted, got %', v_row2.outcome;
  END IF;

  -- Contract 5: a stale expected_revision is rejected before quota is
  -- touched.
  BEGIN
    PERFORM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 999, 'ideas:fp-stale');
    RAISE EXCEPTION 'EXPLOIT: a stale expected_revision was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'admit_ai_session_generation contracts: all held';
END $$;

-- =====================================================================
-- TASK 3 (merge-blockers plan): THE MEMBERSHIP + AI-PROCESSING CONSENT
-- GATE ON admit_ai_session_generation. Spec §7.2, migration
-- 20260953140000.
--
-- WHAT WAS WRONG (Critical). Of Plan B's 18 functions, three checked
-- consent: the two Task 10 read RPCs and Task 11's Nearby publish. The
-- entire DISPATCH path was ungated, so with ZERO consent events -- or
-- after a granted-then-withdrawn -- the whole chain
--
--   prepare -> approve -> activate -> admit -> claim -> commit
--
-- succeeded and the Ideas transcript was written. Reproduced live twice
-- on a clean database before this gate landed.
--
-- WHY THE GATE GOES ON admit AND NOWHERE ELSE. The step that actually
-- matters is claim_ai_session_dispatch: its only purpose is setting the
-- write-once provider-start marker immediately before the edge function
-- calls Gemini, so a successful claim IS the authorization to transmit
-- the couple's approved chat clippings to a third-party AI provider.
-- claim's own UPDATE requires a request row at state='reserved' with a
-- matching worker_token and an unexpired lease -- and admit's final
-- INSERT is the ONLY code in the schema that creates such a row
-- (verified by catalog query over every function body: admit is the
-- sole INSERT INTO ai_session_requests, and the only writer of
-- worker_token; claim/commit/stage merely read it in WHERE clauses). So
-- gating admit makes claim, and therefore commit/stage/publish
-- downstream of it, INHERIT the gate transitively from one choke point.
-- Contract 6e below proves that transitivity behaviourally rather than
-- by argument.
--
-- THESE CONTRACTS DENY WITH A REPLACEMENT CONSENTING MEMBER, NEVER BY
-- NULLING ONE. Nulling a relationship member is SELF-DEFEATING for a
-- consent contract: the gate reads r.user_a/r.user_b to decide WHOSE
-- consent to look up, so a NULL member empties the consent lookup and
-- the contract would pass against a genuinely exploitable mutant (the
-- predecessor plan's Task 10 was bitten by exactly this, twice). Every
-- denial below is produced by WITHDRAWING or WITHHOLDING consent on a
-- fully-populated two-member relationship.
--
-- Every consent event uses clock_timestamp(), never now(): now() is
-- frozen per transaction, so events written in one DO block share an
-- identical created_at and the gate's `ORDER BY e.created_at DESC,
-- e.id DESC` tiebreak falls to a random uuid -- intermittently green.
-- idempotency_key is NOT NULL.
-- =====================================================================
DO $$
DECLARE
  -- Contract 6a/6d/6e fixture: the WITHDRAWING couple.
  v_rel_w uuid := 'b1000000-0000-0000-0000-000000000135';
  v_w_a uuid := 'b1000000-0000-0000-0000-000000000136';
  v_w_b uuid := 'b1000000-0000-0000-0000-000000000137';
  -- Contract 6b fixture: the couple that NEVER granted.
  v_rel_n uuid := 'b1000000-0000-0000-0000-000000000138';
  v_n_a uuid := 'b1000000-0000-0000-0000-000000000139';
  v_n_b uuid := 'b1000000-0000-0000-0000-00000000013a';
  -- Contract 6c fixture: the couple that BOTH granted (over-restriction).
  v_rel_g uuid := 'b1000000-0000-0000-0000-00000000013b';
  v_g_a uuid := 'b1000000-0000-0000-0000-00000000013c';
  v_g_b uuid := 'b1000000-0000-0000-0000-00000000013d';
  v_session uuid;
  v_req uuid;
  v_row record;
  v_msg text;
  v_claim boolean;
  v_reserved int;
BEGIN
  -- ---- fixtures -----------------------------------------------------
  INSERT INTO auth.users (id, email) VALUES
    (v_w_a, 'admitgate_w_a@t.test'), (v_w_b, 'admitgate_w_b@t.test'),
    (v_n_a, 'admitgate_n_a@t.test'), (v_n_b, 'admitgate_n_b@t.test'),
    (v_g_a, 'admitgate_g_a@t.test'), (v_g_b, 'admitgate_g_b@t.test');
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_w_a, '+15550021011', 'WA'), (v_w_b, '+15550021012', 'WB'),
    (v_n_a, '+15550021013', 'NA'), (v_n_b, '+15550021014', 'NB'),
    (v_g_a, '+15550021015', 'GA'), (v_g_b, '+15550021016', 'GB');
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
    (v_rel_w, v_w_a, v_w_b, 'active'),
    (v_rel_n, v_n_a, v_n_b, 'active'),
    (v_rel_g, v_g_a, v_g_b, 'active');

  -- The withdrawing couple: both grant, then user B withdraws. Note
  -- user B -- the PARTNER, not the actor -- so this also proves the
  -- gate is two-party and not merely a self-consent check.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel_w, v_w_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel_w, v_w_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel_w, v_w_b, 'v1', 'withdrawn', gen_random_uuid(), clock_timestamp());

  -- The granting couple: both grant and stay granted.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel_g, v_g_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel_g, v_g_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  -- The never-granted couple gets NO consent events at all. Asserted
  -- rather than assumed, so a future fixture edit that accidentally
  -- grants here cannot turn Contract 6b vacuous.
  IF (SELECT count(*) FROM public.ai_processing_consent_events
      WHERE relationship_id = v_rel_n) <> 0 THEN
    RAISE EXCEPTION 'SETUP FAILED: the never-granted fixture has consent events, so Contract 6b would not test what it claims';
  END IF;

  -- ---- Contract 6a: ONE PARTNER HAS WITHDRAWN -> admit RAISES -------
  -- The exact scenario of the live repro's second form. The actor
  -- (user A) still consents; the partner withdrew. Denied.
  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_w_a, gen_random_uuid(), v_rel_w, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_w_a, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_w_a, v_session, 1);
  v_req := gen_random_uuid();
  BEGIN
    PERFORM public.admit_ai_session_generation(v_w_a, v_req, v_session, 1, 'ideas:fp-withdrawn');
    RAISE EXCEPTION 'EXPLOIT: admit succeeded after a partner WITHDREW AI-processing consent. A successful admission is what makes claim_ai_session_dispatch reachable, and claim is the authorization to transmit this couple''s chat clippings to a third-party AI provider.';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    v_msg := SQLERRM;
    -- SPECIFIC message, not "any error": a vacuous handler here would
    -- be satisfied by an unrelated failure (a typo'd column, a missing
    -- fixture row) and would pass against a body with no gate at all.
    IF v_msg IS DISTINCT FROM 'AI processing consent is not current for this relationship' THEN
      RAISE EXCEPTION 'EXPLOIT: admit failed after withdrawal, but with the WRONG error -- got %. The consent gate must raise exactly ''AI processing consent is not current for this relationship'' (the message publish_ai_session_nearby_result already uses for this condition); anything else means the refusal came from somewhere other than the gate.', v_msg;
    END IF;
  END;

  -- ---- Contract 6e: claim IS CONSEQUENTLY UNREACHABLE --------------
  -- The transitivity the one-RPC fix rests on, proven behaviourally.
  -- A refused admission leaves NO request row, so claim's
  -- `state = 'reserved' AND worker_token = ... AND lease_deadline >
  -- now()` matches nothing and returns false -- i.e. no provider call
  -- is authorized. Asserted on BOTH legs: the absent row AND claim's
  -- own answer, because either one alone could be satisfied for the
  -- wrong reason.
  SELECT count(*) INTO v_reserved FROM public.ai_session_requests
  WHERE session_id = v_session;
  IF v_reserved <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a refused admission still left % ai_session_requests row(s) behind. claim_ai_session_dispatch keys off exactly such a row, so the gate would be bypassable one call downstream.', v_reserved;
  END IF;
  SELECT public.claim_ai_session_dispatch(gen_random_uuid(), v_req) INTO v_claim;
  IF v_claim IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: claim_ai_session_dispatch returned % for a request the consent gate refused to admit. A true claim sets the provider-start marker and authorizes the Gemini call.', v_claim;
  END IF;

  -- ---- Contract 6b: CONSENT NEVER GRANTED -> admit RAISES ----------
  -- The live repro's first form (zero consent events). Distinct from 6a
  -- because the gate's COALESCE(...,false) is what denies here -- the
  -- lookups return NULL rather than false -- and a mutant that only
  -- handled an explicit 'withdrawn' row would pass 6a and fail this.
  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_n_a, gen_random_uuid(), v_rel_n, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_n_a, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_n_a, v_session, 1);
  BEGIN
    PERFORM public.admit_ai_session_generation(v_n_a, gen_random_uuid(), v_session, 1, 'ideas:fp-never');
    RAISE EXCEPTION 'EXPLOIT: admit succeeded for a couple that NEVER granted AI-processing consent (zero consent events on the relationship).';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    v_msg := SQLERRM;
    IF v_msg IS DISTINCT FROM 'AI processing consent is not current for this relationship' THEN
      RAISE EXCEPTION 'EXPLOIT: admit failed for a never-consenting couple, but with the WRONG error -- got %. Expected exactly ''AI processing consent is not current for this relationship''.', v_msg;
    END IF;
  END;

  -- ---- Contract 6c: BOTH GRANTED -> admit STILL SUCCEEDS -----------
  -- THE OVER-RESTRICTION DIRECTION, and the one most likely to be
  -- missed: a gate that denies too much is as much a defect as one that
  -- denies too little, and it would take the entire AI-session feature
  -- offline for every consenting couple. Nothing else in this file
  -- covers it, because every other admission here runs on a fixture
  -- that the gate has to let through for unrelated reasons.
  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_g_a, gen_random_uuid(), v_rel_g, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_g_a, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_g_a, v_session, 1);
  SELECT * INTO v_row FROM public.admit_ai_session_generation(
    v_g_a, gen_random_uuid(), v_session, 1, 'ideas:fp-granted'
  );
  IF v_row.outcome IS DISTINCT FROM 'admitted' OR v_row.attempt_n IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT (OVER-RESTRICTION): both partners granted current AI-processing consent, yet admit did not admit -- got outcome=% attempt_n=%. The consent gate must subtract access from the non-consenting, never from the consenting.', v_row.outcome, v_row.attempt_n;
  END IF;
  -- And the admission is REAL, not just a row shape: claim must now
  -- succeed on the token it returned. This is the positive counterpart
  -- of 6e, and it is what makes 6e non-vacuous -- without it, a body
  -- that admitted but wrote no request row would pass both.
  SELECT public.claim_ai_session_dispatch(v_row.worker_token, v_row.request_id) INTO v_claim;
  IF v_claim IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT (OVER-RESTRICTION): a fully-consenting admission returned ''admitted'' but claim_ai_session_dispatch then returned %, so no provider call could ever be made for a consenting couple.', v_claim;
  END IF;

  -- ---- Contract 6d: WITHDRAW THEN RE-GRANT -> admit SUCCEEDS -------
  -- Consent is an append-only event log and the gate reads only the
  -- LATEST event per user at the current policy version. So a
  -- withdrawal must be REVERSIBLE inside the same session window: the
  -- partner who withdrew in Contract 6a re-grants, and admission works
  -- again on the SAME relationship and SAME session. This kills a
  -- plausible wrong implementation -- "deny if ANY withdrawal event
  -- exists" -- which would pass 6a, 6b and 6c and permanently brick
  -- every couple who ever toggled the setting off and on.
  --
  -- clock_timestamp() is load-bearing here specifically: the re-grant
  -- must sort AFTER the withdrawal in `ORDER BY e.created_at DESC,
  -- e.id DESC`, and under a frozen now() it would tie and the winner
  -- would be a random uuid.
  --
  -- This contract REUSES Contract 6a's session rather than preparing a
  -- fresh one, and that is deliberate on two counts. First it is
  -- necessary: 6a's session is still state='active' -- the consent
  -- refusal admitted nothing and therefore closed nothing -- and
  -- prepare_ai_session raises 'A private session is already pending or
  -- active for this creator' for a second private session on the same
  -- creator/relationship. Second, and more importantly, it is STRONGER:
  -- it proves the re-grant restores admission on THE VERY SESSION the
  -- withdrawal blocked, inside the same session window, rather than
  -- only on a fresh one. v_session still holds it, and its revision is
  -- still 1 because a refused admission bumps nothing.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel_w, v_w_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());
  -- Prove the re-grant really is the latest event for that user, so a
  -- tie would fail LOUDLY here rather than flaking in the admission.
  IF (SELECT e.action FROM public.ai_processing_consent_events e
      WHERE e.relationship_id = v_rel_w AND e.user_id = v_w_b
        AND e.policy_version = 'v1'
      ORDER BY e.created_at DESC, e.id DESC LIMIT 1) IS DISTINCT FROM 'granted' THEN
    RAISE EXCEPTION 'SETUP FAILED: the re-grant did not land as the latest consent event for the withdrawing partner (created_at tie?). Contract 6d cannot discriminate.';
  END IF;
  -- Re-assert the preconditions this contract depends on, so that if a
  -- future edit to 6a changes them this fails LOUDLY here rather than
  -- degrading into a test of something else.
  SELECT s.id INTO v_session FROM public.ai_sessions s
  WHERE s.relationship_id = v_rel_w AND s.state = 'active';
  IF v_session IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: Contract 6a''s session is no longer active, so Contract 6d cannot prove the re-grant restores admission on the session the withdrawal blocked.';
  END IF;
  IF (SELECT s.revision FROM public.ai_sessions s WHERE s.id = v_session) <> 1 THEN
    RAISE EXCEPTION 'SETUP FAILED: Contract 6a''s session revision is no longer 1, so the consent refusal mutated session state it should not have touched.';
  END IF;
  SELECT * INTO v_row FROM public.admit_ai_session_generation(
    v_w_a, gen_random_uuid(), v_session, 1, 'ideas:fp-regranted'
  );
  IF v_row.outcome IS DISTINCT FROM 'admitted' THEN
    RAISE EXCEPTION 'EXPLOIT (OVER-RESTRICTION): after the withdrawing partner RE-GRANTED, admit still refused -- got %. The gate must read the latest consent event, not the existence of any withdrawal.', v_row.outcome;
  END IF;

  RAISE NOTICE 'admit_ai_session_generation consent gate (Task 3): 6a withdrawn denied, 6b never-granted denied, 6c both-granted still admits, 6d re-grant restores, 6e claim unreachable after refusal';
END $$;

-- =====================================================================
-- STRUCTURAL: the gate's own guards, asserted on the LIVE body.
--
-- Comments are STRIPPED first. pg_get_functiondef() returns comments
-- verbatim, so a plain text match is satisfied by a guard that was
-- commented out -- which is exactly how a mutant survives a structural
-- check. pg_temp.strip_sql_comments() is reused from
-- ai_session_read_authorization_contracts.sql; it is defined locally
-- here because pg_temp does not survive across psql invocations and
-- each test file is run on its own connection.
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
BEGIN
  v_def := pg_temp.strip_sql_comments(pg_get_functiondef(
    'public.admit_ai_session_generation(uuid, uuid, uuid, int, text)'::regprocedure));

  -- The NULL-actor guard must remain LITERALLY FIRST, ahead of the
  -- consent gate (Global Constraint: every SECURITY DEFINER function in
  -- this plan validates its actor parameter non-NULL as its first
  -- statement). Asserted by POSITION, not presence: a gate inserted
  -- above it would still "contain" both strings.
  IF position('IF p_actor_id IS NULL THEN' in v_def) = 0 THEN
    RAISE EXCEPTION 'EXPLOIT: admit_ai_session_generation has no explicit `IF p_actor_id IS NULL` guard.';
  END IF;
  -- TASK 5 RE-DERIVED: the gate's position marker was the literal table
  -- name; 20260953180000 moved the predicate into the shared
  -- public.ai_consent_granted_for_relationship, so the gate is now
  -- located by the CALL.
  IF position('ai_consent_granted_for_relationship' in v_def) = 0 THEN
    RAISE EXCEPTION 'EXPLOIT: admit_ai_session_generation does not call public.ai_consent_granted_for_relationship -- its consent gate is gone. 20260953180000 routes it through the shared predicate; a body without that call enforces no consent at all.';
  END IF;
  IF position('IF p_actor_id IS NULL THEN' in v_def)
     > position('ai_consent_granted_for_relationship' in v_def) THEN
    RAISE EXCEPTION 'EXPLOIT: the NULL-actor guard no longer precedes the consent gate in admit_ai_session_generation. The Global Constraint requires it to be the FIRST statement.';
  END IF;

  -- THE GATE MUST PRECEDE THE ADVISORY LOCK. This is the lock-order
  -- claim the whole task rests on, and it is asserted structurally
  -- because no behavioural test can see it: the gate reads no locked
  -- row, so moving it after the lock changes nothing observable in a
  -- single-connection test while silently making the gate hold the
  -- relationship lock for the duration of three extra SELECTs -- and,
  -- worse, inviting a future edit to add a FOR UPDATE there and invert
  -- the documented order (relationship advisory -> quota advisory ->
  -- session row -> request row).
  IF position('pg_advisory_xact_lock' in v_def) = 0 THEN
    RAISE EXCEPTION 'EXPLOIT: admit_ai_session_generation no longer takes pg_advisory_xact_lock -- LOCK 1 of the documented order is gone.';
  END IF;
  IF position('ai_consent_granted_for_relationship' in v_def)
     > position('pg_advisory_xact_lock' in v_def) THEN
    RAISE EXCEPTION 'EXPLOIT: the consent gate in admit_ai_session_generation now sits AFTER pg_advisory_xact_lock. It must slot between the relationship_id resolution and LOCK 1, where no lock is yet held, so that it adds no lock and cannot perturb the documented lock order.';
  END IF;

  -- The gate must BRANCH on the predicate, not merely call it. A body
  -- that called the helper and ignored the answer would satisfy the
  -- position legs above while enforcing nothing.
  IF v_def !~ 'IF NOT public\.ai_consent_granted_for_relationship\(v_relationship_id\) THEN' THEN
    RAISE EXCEPTION 'EXPLOIT: admit_ai_session_generation does not branch on the consent predicate as `IF NOT public.ai_consent_granted_for_relationship(v_relationship_id) THEN`. Calling it and discarding its answer is indistinguishable from having no gate.';
  END IF;

  -- The gate must take no lock of its own. The helper is STABLE and
  -- lock-free (asserted against the helper itself by Contract 10 of
  -- ai_session_read_authorization_contracts.sql); what is asserted here
  -- is that admit did not reintroduce a locking consent read alongside
  -- the call.
  IF v_def ~ 'FROM public\.ai_processing_consent_events[^;]*FOR (UPDATE|SHARE|NO KEY UPDATE|KEY SHARE)' THEN
    RAISE EXCEPTION 'EXPLOIT: the consent gate now takes a row lock on ai_processing_consent_events. It must be a plain MVCC read; a lock here is outside the documented order.';
  END IF;

  -- TASK 5: the two-party rule, the COALESCE-denial, the LATEST-event
  -- ORDER BY and the policy-version pin used to be asserted HERE, on
  -- admit's own inline copy. 20260953180000 moved the predicate into
  -- public.ai_consent_granted_for_relationship, so those four legs moved
  -- with it -- they are asserted ONCE, against the helper, by Contract 10
  -- of ai_session_read_authorization_contracts.sql, instead of four times
  -- across four callers that could drift apart. Re-asserting them here
  -- would be asserting the absence of code that is correctly absent.
  --
  -- What this contract keeps is the part that is still admit's own
  -- responsibility: that it CALLS the predicate, BRANCHES on it, RAISES
  -- rather than returning silently, and does so between the
  -- relationship_id resolution and LOCK 1.
  IF v_def !~ 'AI processing consent is not current for this relationship' THEN
    RAISE EXCEPTION 'EXPLOIT: admit_ai_session_generation no longer raises ''AI processing consent is not current for this relationship''. admit returns a row on EVERY path, so a silent return would report success while admitting nothing -- the gate must RAISE.';
  END IF;

  -- The active-membership half of the gate.
  IF v_def !~ 'r\.status = ''active'' AND r\.chat_archived_at IS NULL' THEN
    RAISE EXCEPTION 'EXPLOIT: admit_ai_session_generation has no active-membership gate (r.status = ''active'' AND r.chat_archived_at IS NULL).';
  END IF;

  -- Anti-vacuity on the preservation side: the admission outcomes
  -- existing contracts and Plan C depend on must all still be present.
  -- A "simplification" that satisfied every marker above while dropping
  -- one of these would pass this contract and break the caller.
  IF v_def !~ '''CONTEXT_CHANGED''' OR v_def !~ '''busy''' OR v_def !~ '''rate_limited'''
     OR v_def !~ '''already_admitted''' OR v_def !~ '''conflict'''
     OR v_def !~ '''limit_reached''' OR v_def !~ '''UNAVAILABLE''' THEN
    RAISE EXCEPTION 'EXPLOIT: admit_ai_session_generation lost one of its documented outcomes (CONTEXT_CHANGED / busy / rate_limited / already_admitted / conflict / limit_reached / UNAVAILABLE). The consent gate must ADD a refusal, not replace the admission protocol.';
  END IF;
  -- operation_fingerprint never includes location (Global Constraint):
  -- the function must carry the parameter through untouched and never
  -- compose a fingerprint from location columns.
  IF v_def ~ 'p_operation_fingerprint[^;]*(lat|lng|latitude|longitude|geo|location)' THEN
    RAISE EXCEPTION 'EXPLOIT: operation_fingerprint now incorporates location. Global Constraint: operation_fingerprint never includes location.';
  END IF;

  RAISE NOTICE 'admit_ai_session_generation gate structure: NULL-actor guard first, gate before LOCK 1, lock-free, two-party, COALESCE-denying, version-pinned, all outcomes preserved';
END $$;
