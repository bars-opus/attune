-- Task 11: the every-minute reconciler/purger, its cron registration,
-- the WRITE leg of the consent gate, and the two defence-in-depth
-- invariants routed here from Tasks 6/9/10's reviews.
-- Spec §8.2.3, §7.2, §5.4, §7.3, §3.2.
--
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_purge_contracts.sql
--
-- ---------------------------------------------------------------------
-- FIXTURE UUIDS. The b1000000-...-0000000011x / ...-00000000012x range,
-- swept against every supabase/tests/*.sql and supabase/migrations/
-- *.sql before use (this plan has hit SIX fixture-collision bugs; one
-- left a Task 5 script non-functional from the day it was committed).
-- The relationship id ...-00000000000c comes from this task's brief and
-- was re-confirmed unused.
--
-- NOTE ON THE BRIEF'S OWN FIXTURE: the brief's literal
-- 'b1000000-0000-0000-0000-0000000011a' is MALFORMED -- 11 hex digits
-- in the final group where 12 are required -- and raises `invalid input
-- syntax for type uuid`. Reproduced before deviating. The padded form
-- ...-00000000011a is used throughout.
--
-- users.phone is UNIQUE and every insert below uses ON CONFLICT DO
-- NOTHING, so a collision would SILENTLY DROP the row and leave this
-- file asserting against someone else's fixtures. Phones use the
-- +1555011000x block (swept, unused), and the setup guard at the top of
-- the first block turns any silent drop into a legible SETUP FAILED
-- rather than a confusing downstream failure.
--
-- ---------------------------------------------------------------------
-- NEGATIVE-CONTRACT DISCIPLINE. Every rejection below asserts the
-- SPECIFIC error its target guard raises, via `EXCEPTION WHEN OTHERS
-- THEN IF SQLERRM NOT LIKE '<expected>' THEN RAISE EXCEPTION
-- 'EXPLOIT: ... wrong error: %'`. A bare "any error" assertion is
-- forbidden by this plan's Global Constraints: four of Task 9's ten
-- contracts once passed with the production logic deleted because an
-- incidental NOT NULL violation stood in for the guard under test.
--
-- CONSENT-EVENT ORDERING. Every consent insert uses clock_timestamp(),
-- never now(). now() is frozen per transaction, so two events written
-- in one DO block share an identical created_at and the lookup's
-- tiebreak falls to `id DESC` on a random uuid -- making any such
-- contract intermittently green.
--
-- DENIAL BY REPLACEMENT, NEVER BY NULLING A MEMBER. On these RPCs a
-- contract that denies by setting relationships.user_a = NULL is
-- SELF-DEFEATING: the consent gate reads those same columns, so a NULL
-- member empties the consent lookup and the contract passes against a
-- mutant that is genuinely exploitable (Task 10 hit this twice). Every
-- membership denial below swaps in a REPLACEMENT CONSENTING MEMBER so
-- only the predicate under test can deny.
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on

-- Strip SQL comments from a function definition before any structural
-- assertion matches against it. pg_get_functiondef() returns comments
-- VERBATIM, so a plain substring match is satisfied by a guard that has
-- been COMMENTED OUT -- the assertion passes while the guard is gone
-- (Task 10 review finding N1: measured, 4/4 guard deletions undetected
-- when the text was left in a comment). Same helper, same reason, as
-- ai_session_read_authorization_contracts.sql.
CREATE OR REPLACE FUNCTION pg_temp.strip_sql_comments(p_def text)
RETURNS text LANGUAGE sql IMMUTABLE AS $strip$
  SELECT regexp_replace(
           regexp_replace(p_def, '--[^\n]*', '', 'g'),
           '/\*.*?\*/', '', 'gs');
$strip$;


-- =====================================================================
-- Contract 1: purge_expired_ai_sessions catches an ACTIVE session whose
-- expiry passed with no further activity to trigger anything else, and
-- purges its content in the same transaction that closes it.
-- Spec §8.2.3.
-- =====================================================================
DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-00000000000c';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000011a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000011b';
  v_session uuid;
  v_admit record;
  v_purged int;
  v_rev_before int;
  v_rev_after int;
  v_epoch_before int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 't11_purge_a@t.test'), (v_user_b, 't11_purge_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550110001', 'A'), (v_user_b, '+15550110002', 'B')
  ON CONFLICT DO NOTHING;

  -- SETUP GUARD. users.phone is UNIQUE; an ON CONFLICT DO NOTHING
  -- insert whose phone is already taken by another test file's fixture
  -- silently drops, and every assertion below would then be running
  -- against a user that does not exist. Fail loudly and specifically
  -- instead -- this is the exact mechanism that killed Task 5's
  -- concurrency script.
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_user_a)
     OR NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_user_b) THEN
    RAISE EXCEPTION
      'SETUP FAILED: a fixture user was silently dropped by ON CONFLICT DO NOTHING -- its phone (+15550110001/2) or id collides with another test file. Re-sweep the fixture range before trusting any assertion in this file.';
  END IF;

  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  IF v_session IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: prepare_ai_session returned no session -- a slot limit or an unmet gate, not a purge defect';
  END IF;
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp'
  );
  IF v_admit.request_id IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: the purge fixture failed to admit (outcome=%)', v_admit.outcome;
  END IF;
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  PERFORM public.commit_ai_session_ideas_turn(
    v_admit.worker_token, v_admit.request_id, 'an idea', 'a reply', NULL
  );

  -- NON-VACUITY ANCHOR. Assert the content EXISTS before the purge, so
  -- the post-purge zeroes below prove the purge ran rather than that
  -- the fixture never created anything. This is the anchor the plan's
  -- own history says four contracts went without.
  IF NOT EXISTS (SELECT 1 FROM public.ai_session_turns WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'SETUP FAILED: no turn content exists before the purge -- every post-purge assertion would pass vacuously';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ai_session_approvals WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'SETUP FAILED: no approval rows exist before the purge -- the approvals assertion would pass vacuously';
  END IF;

  SELECT revision, generation_epoch INTO v_rev_before, v_epoch_before
  FROM public.ai_sessions WHERE id = v_session;

  -- Force this session well past expiry with no further calls. This is
  -- exactly the shape nothing else catches: no admission, no
  -- completion and no End will ever run on this relationship again.
  UPDATE public.ai_sessions
  SET last_admitted_at = now() - interval '1 hour',
      expires_at = now() - interval '45 minutes'
  WHERE id = v_session;

  SELECT public.purge_expired_ai_sessions() INTO v_purged;
  IF v_purged < 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: purge_expired_ai_sessions did not purge the one expired session, reported % purged -- an expired session''s content survives indefinitely when nothing else closes it (spec §8.2.3)',
      v_purged;
  END IF;
  IF (SELECT state FROM public.ai_sessions WHERE id = v_session) != 'closed' THEN
    RAISE EXCEPTION 'EXPLOIT: an expired session was not closed by the purge job';
  END IF;

  -- The content is GONE, in the same transaction that closed it
  -- (Global Constraints / spec §5.4). All four session-scoped tables,
  -- each asserted separately with its own message: a single combined
  -- assertion cannot say WHICH table leaked.
  IF EXISTS (SELECT 1 FROM public.ai_session_turns WHERE session_id = v_session) THEN
    RAISE EXCEPTION
      'EXPLOIT: % turn row(s) survived the expiry purge -- transcript content outlives its own session',
      (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session);
  END IF;
  IF EXISTS (SELECT 1 FROM public.ai_session_sources WHERE session_id = v_session) THEN
    RAISE EXCEPTION
      'EXPLOIT: % source row(s) survived the expiry purge -- approved message clippings outlive their session',
      (SELECT count(*) FROM public.ai_session_sources WHERE session_id = v_session);
  END IF;
  IF EXISTS (SELECT 1 FROM public.ai_session_approvals WHERE session_id = v_session) THEN
    RAISE EXCEPTION
      'EXPLOIT: % approval row(s) survived the expiry purge',
      (SELECT count(*) FROM public.ai_session_approvals WHERE session_id = v_session);
  END IF;
  IF EXISTS (SELECT 1 FROM public.ai_session_staging WHERE session_id = v_session) THEN
    RAISE EXCEPTION
      'EXPLOIT: % staging row(s) survived the expiry purge',
      (SELECT count(*) FROM public.ai_session_staging WHERE session_id = v_session);
  END IF;

  -- The epoch advanced (fencing any in-flight worker, spec §6.2) and
  -- `revision` advanced (so the purge is observable to a
  -- revision-polling client) -- identical to end_ai_session's own
  -- post-conditions, because the purger shares its closure primitive.
  SELECT revision, generation_epoch INTO v_rev_after, v_purged
  FROM public.ai_sessions WHERE id = v_session;
  IF v_purged <= v_epoch_before THEN
    RAISE EXCEPTION
      'EXPLOIT: the expiry purge did not advance generation_epoch (% -> %) -- an in-flight worker is not fenced',
      v_epoch_before, v_purged;
  END IF;
  IF v_rev_after <= v_rev_before THEN
    RAISE EXCEPTION
      'EXPLOIT: the expiry purge deleted the whole transcript without advancing revision (% -> %) -- a revision-polling client cannot observe it',
      v_rev_before, v_rev_after;
  END IF;

  -- No client-readable "who ended it" column was introduced by the
  -- system-purge path either (Global Constraints / spec §5.4). A
  -- system purge is recorded exactly as a user close is.
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'ai_sessions'
      AND (column_name LIKE '%ended_by%' OR column_name LIKE '%closed_by%'
           OR column_name LIKE '%ender%' OR column_name LIKE '%purged_by%')
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: an attributable "who ended it" column exists on ai_sessions';
  END IF;

  RAISE NOTICE 'purge contract 1: expired ACTIVE session purged, content gone, epoch+revision advanced';
END $$;


-- =====================================================================
-- Contract 1b (TASK 11 FINDING F1): the purger's QUOTA-RESOLUTION LOOP,
-- executed for real -- a session purged with a genuinely `reserved`
-- request still outstanding.
--
-- THE GAP THIS CLOSES. Contract 1 commits its turn before forcing
-- expiry, so by purge time the request is `committed` -- OUTSIDE the
-- three states (reserved / started / staged) the loop scans. MEASURED
-- on both purge sites: `0 requests in reserved/started/staged at purge
-- time`. The loop was therefore never behaviourally executed by any
-- contract in the plan, and TWO mutants survived the whole suite:
--
--   M-A  release for ALL THREE states, not just 'reserved'. A 'started'
--        or 'staged' request has its write-once
--        ai_assistant_usage.provider_started_at set by
--        claim_ai_session_dispatch (20260953060100), so
--        release_ai_assistant_quota_reservation RAISES 'Cannot release
--        a reservation whose provider call has started'.
--   M-B  key the release on the SESSION's creator_id instead of the
--        ROW's own actor_id. The usage row is keyed (request_id,
--        user_id), so for a request admitted by the non-creator partner
--        the lookup misses and the RPC RAISES 'Reservation not found
--        for this actor'. Contract 1c is the leg that catches this one.
--
-- WHY THESE FAIL *WORSE* THAN A QUOTA HOLE, which is why this contract
-- exists rather than being filed. The raise propagates out of
-- purge_ai_session_content into purge_expired_ai_sessions' deliberate
-- per-session EXCEPTION handler, which swallows it into a WARNING. The
-- session is then NEVER PURGED -- it stays 'active' past expiry with
-- its full transcript, its approved message clippings and its staged
-- results retained INDEFINITELY, and the only trace is a line in the
-- cron log. That is a content-retention failure of the Global
-- Constraint ("session content is deleted in the SAME transaction that
-- closes the session"), not merely a leaked quota reservation.
--
-- HOW A `reserved` REQUEST IS PRODUCED HONESTLY. admit_ai_session_
-- generation creates the row in state 'reserved' and
-- reserve_ai_assistant_quota creates the matching ai_assistant_usage
-- row with outcome='reserved' and provider_started_at NULL. This
-- contract then does NOT call claim_ai_session_dispatch -- the one step
-- that would set the provider marker and move the row to 'started'.
-- Nothing is hand-written into either table: the fixture is the real
-- admission path stopped one step short, which is also the real
-- production shape (a worker that was admitted and then died).
-- =====================================================================
DO $$
DECLARE
  v_rel uuid := 'b1050000-0000-4000-8000-00000000000c';
  v_user_a uuid := 'b1050000-0000-4000-8000-0000000000aa';
  v_user_b uuid := 'b1050000-0000-4000-8000-0000000000bb';
  v_session uuid;
  v_admit record;
  v_purged int;
  v_state text;
  v_terminal text;
  v_outcome text;
  v_started timestamptz;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 't5_f1_reserved_a@t.test'), (v_user_b, 't5_f1_reserved_b@t.test');
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550512001', 'F1 Reserved A'), (v_user_b, '+15550512002', 'F1 Reserved B');
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active');
  -- Task 3's consent gate: BOTH partners, granted, at the current
  -- version. clock_timestamp() not now(): every row in one DO block
  -- shares a frozen now(), which makes the predicate's
  -- `ORDER BY created_at DESC, id DESC` tiebreak on a random uuid and
  -- the contract go intermittently green.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  IF v_session IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: prepare_ai_session returned no session';
  END IF;
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);

  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_session, 1, 'ideas:f1-reserved'
  );
  IF v_admit.request_id IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: the F1 fixture failed to admit (outcome=%)', v_admit.outcome;
  END IF;

  -- DELIBERATELY NO claim_ai_session_dispatch. The request stays
  -- 'reserved' and its usage row keeps provider_started_at NULL.

  -- NON-VACUITY ANCHORS. Without these the whole contract passes
  -- against a fixture that produced no reserved request at all -- which
  -- is EXACTLY the defect being closed (Contract 1 passes that way
  -- today).
  SELECT state INTO v_state FROM public.ai_session_requests WHERE id = v_admit.request_id;
  IF v_state IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION
      'SETUP FAILED: the request is in state % , not ''reserved'', at purge time. This contract exists BECAUSE no other contract reaches the purger''s quota loop; if the fixture does not produce a reserved request the loop is still never executed and every assertion below is vacuous.',
      COALESCE(v_state, '<missing>');
  END IF;
  SELECT outcome, provider_started_at INTO v_outcome, v_started
  FROM public.ai_assistant_usage WHERE request_id = v_admit.request_id;
  IF v_outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION
      'SETUP FAILED: the ai_assistant_usage row for this request has outcome % , not ''reserved'' -- the quota release assertion below would not discriminate',
      COALESCE(v_outcome, '<missing row>');
  END IF;
  IF v_started IS NOT NULL THEN
    RAISE EXCEPTION
      'SETUP FAILED: provider_started_at is already set on a request that was never dispatched -- the reservation is not genuinely unconsumed and the release would legitimately refuse';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ai_session_approvals WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'SETUP FAILED: no approval rows exist before the purge -- the content assertions would pass vacuously';
  END IF;

  -- Force expiry with the request still outstanding.
  UPDATE public.ai_sessions
  SET last_admitted_at = now() - interval '1 hour',
      expires_at = now() - interval '45 minutes'
  WHERE id = v_session;

  SELECT public.purge_expired_ai_sessions() INTO v_purged;

  -- LEG 1 -- THE ONE BOTH MUTANTS FAIL. Either mutant raises inside
  -- purge_ai_session_content, the per-session handler swallows it into
  -- a WARNING, and the session is simply never purged. This leg is
  -- therefore the content-retention assertion, not a quota assertion.
  IF v_purged < 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: purge_expired_ai_sessions reported % purged for an expired session with an outstanding RESERVED request. The quota-resolution loop raised and purge_expired_ai_sessions'' per-session EXCEPTION handler swallowed it into a WARNING, so the session was NEVER PURGED -- its transcript, its approved message clippings and its staged results are retained INDEFINITELY and the only trace is a cron-log line. Two known mutants do exactly this: releasing for all three states (''Cannot release a reservation whose provider call has started'') and keying the release on creator_id instead of the row''s own actor_id (''Reservation not found for this actor'').',
      v_purged;
  END IF;
  IF (SELECT state FROM public.ai_sessions WHERE id = v_session) != 'closed' THEN
    RAISE EXCEPTION
      'EXPLOIT: the expired session with an outstanding RESERVED request was not closed. See the message above: a raise in the quota loop is swallowed into a WARNING and the session is retained.';
  END IF;

  -- LEG 2: the content really is gone (Global Constraint). Asserted
  -- separately from LEG 1 because a purge that closed the session but
  -- aborted mid-loop would satisfy LEG 1 alone.
  IF EXISTS (SELECT 1 FROM public.ai_session_turns WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'EXPLOIT: turn row(s) survived the purge of a session with a reserved request';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ai_session_sources WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'EXPLOIT: source row(s) -- approved message clippings -- survived the purge of a session with a reserved request';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ai_session_approvals WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'EXPLOIT: approval row(s) survived the purge of a session with a reserved request';
  END IF;

  -- LEG 3: the request row was RESOLVED, not left dangling in a state
  -- the lease reconciler keeps scanning forever.
  SELECT state, terminal_code INTO v_state, v_terminal
  FROM public.ai_session_requests WHERE id = v_admit.request_id;
  IF v_state IS DISTINCT FROM 'cancelled' THEN
    RAISE EXCEPTION
      'EXPLOIT: the outstanding request is in state % after its session was purged, not ''cancelled''. It must leave the states the reconciler scans in the SAME transaction, or reconcile_ai_session_leases scans a request whose session no longer has content, once a minute, forever.',
      COALESCE(v_state, '<deleted>');
  END IF;
  IF v_terminal IS DISTINCT FROM 'session_ended' THEN
    RAISE EXCEPTION
      'EXPLOIT: the cancelled request''s terminal_code is % , not ''session_ended''. The purger must record WHY the request ended, and ''session_ended'' is the code end_ai_session uses for the identical transition -- a system purge is recorded exactly as a user close is.',
      COALESCE(v_terminal, '<null>');
  END IF;

  -- LEG 4: THE QUOTA WAS ACTUALLY RELEASED. This is the leg that makes
  -- the loop's PURPOSE non-vacuous: a purge that cancelled the request
  -- but skipped the release would pass legs 1-3 and silently charge the
  -- actor for a generation that never reached a provider.
  SELECT outcome, provider_started_at INTO v_outcome, v_started
  FROM public.ai_assistant_usage WHERE request_id = v_admit.request_id;
  IF v_outcome IS DISTINCT FROM 'cancelled' THEN
    RAISE EXCEPTION
      'EXPLOIT: the ai_assistant_usage row for a RESERVED request purged with its session has outcome % , expected ''cancelled''. The reservation was never dispatched (provider_started_at IS NULL), so it is genuinely unconsumed and must be released: left at ''reserved'' it counts against the actor''s rolling quota permanently, for a generation that never reached a provider.',
      COALESCE(v_outcome, '<missing row>');
  END IF;
  IF v_started IS NOT NULL THEN
    RAISE EXCEPTION
      'EXPLOIT: provider_started_at was SET on a request that was never dispatched. The marker is write-once and means "this generation was genuinely charged"; setting it on the purge path makes an abandoned reservation permanently unreleasable.';
  END IF;

  RAISE NOTICE 'purge contract 1b (F1): the quota-resolution loop RAN -- reserved request cancelled, reservation released, session purged';
END $$;


-- =====================================================================
-- Contract 1c (TASK 11 FINDING F1, the MIS-KEYING leg): a session
-- purged with a reserved request admitted by the NON-CREATOR PARTNER.
--
-- WHY THIS LEG IS SEPARATE FROM 1b. In 1b the creator and the admitting
-- actor are the SAME user, so a mutant that keyed the release on the
-- session's creator_id instead of the request row's own actor_id reads
-- the same uuid and passes. This contract is the one where those two
-- uuids DIFFER: a SHARED session is prepared by user A, and user B --
-- the partner, not the creator -- admits the generation. The usage row
-- is then keyed (request_id, user_id = B), while creator_id is A.
--
-- Under the mis-keying mutant, release_ai_assistant_quota_reservation(A,
-- request) finds no row for A and raises 'Reservation not found for this
-- actor'. The per-session handler swallows it and THE SESSION IS NEVER
-- PURGED -- the same content-retention failure as 1b, reached by the
-- other mutant.
--
-- This is also the production-realistic shape: a shared session exists
-- precisely so BOTH partners can generate on it, so the non-creator
-- admitting is ordinary use, not an edge case.
--
-- NOTE ON THE FIXTURE: a SHARED session is required (prepare_ai_session
-- forbids two concurrent shared sessions per relationship, so this
-- contract uses its own relationship rather than sharing 1b's), and the
-- partner must hold an approval at the current revision to admit.
-- =====================================================================
DO $$
DECLARE
  v_rel uuid := 'b1051000-0000-4000-8000-00000000000c';
  v_creator uuid := 'b1051000-0000-4000-8000-0000000000aa';
  v_partner uuid := 'b1051000-0000-4000-8000-0000000000bb';
  v_session uuid;
  v_admit record;
  v_purged int;
  v_state text;
  v_outcome text;
  v_usage_user uuid;
  v_req_actor uuid;
  v_creator_col uuid;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_creator, 't5_f1_partner_c@t.test'), (v_partner, 't5_f1_partner_p@t.test');
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_creator, '+15550513001', 'F1 Creator'), (v_partner, '+15550513002', 'F1 Partner');
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_creator, v_partner, 'active');
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_creator, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_partner, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  -- SHARED, created by v_creator.
  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_creator, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  IF v_session IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: prepare_ai_session returned no shared session';
  END IF;
  PERFORM public.approve_ai_session_context(v_creator, v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_partner, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_creator, v_session, 1);

  -- THE PARTNER admits -- NOT the creator. This is the whole point.
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_partner, gen_random_uuid(), v_session, 1, 'ideas:f1-partner'
  );
  IF v_admit.request_id IS NULL THEN
    RAISE EXCEPTION
      'SETUP FAILED: the non-creator PARTNER could not admit on a shared session (outcome=%). A shared session exists so BOTH partners can generate; if the partner cannot admit, this contract cannot set up the creator_id != actor_id divergence it exists to test.',
      v_admit.outcome;
  END IF;

  -- No dispatch: the request stays 'reserved'.

  -- NON-VACUITY: the two uuids MUST differ, or the mis-keying mutant
  -- reads the same value and this contract degenerates into 1b.
  SELECT creator_id INTO v_creator_col FROM public.ai_sessions WHERE id = v_session;
  SELECT actor_id, state INTO v_req_actor, v_state
  FROM public.ai_session_requests WHERE id = v_admit.request_id;
  SELECT user_id, outcome INTO v_usage_user, v_outcome
  FROM public.ai_assistant_usage WHERE request_id = v_admit.request_id;

  IF v_creator_col IS NOT DISTINCT FROM v_req_actor THEN
    RAISE EXCEPTION
      'SETUP FAILED: the session''s creator_id (%) equals the request''s actor_id (%), so a mutant keying the quota release on creator_id would read the SAME uuid and this contract would not discriminate. The whole purpose of this leg is the divergence.',
      v_creator_col, v_req_actor;
  END IF;
  IF v_usage_user IS DISTINCT FROM v_req_actor THEN
    RAISE EXCEPTION
      'SETUP FAILED: the ai_assistant_usage row is keyed on user_id=% but the request''s actor_id is %. The charged actor must be whoever admitted the generation, or the release cannot be keyed on it.',
      v_usage_user, v_req_actor;
  END IF;
  IF v_state IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'SETUP FAILED: the partner''s request is in state %, not ''reserved''', COALESCE(v_state,'<missing>');
  END IF;
  IF v_outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'SETUP FAILED: the partner''s usage row has outcome %, not ''reserved''', COALESCE(v_outcome,'<missing>');
  END IF;

  UPDATE public.ai_sessions
  SET last_admitted_at = now() - interval '1 hour',
      expires_at = now() - interval '45 minutes'
  WHERE id = v_session;

  SELECT public.purge_expired_ai_sessions() INTO v_purged;

  IF v_purged < 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: purge_expired_ai_sessions reported % purged for an expired shared session whose outstanding RESERVED request was admitted by the NON-CREATOR partner. A quota release keyed on the session''s creator_id instead of the request row''s own actor_id finds no ai_assistant_usage row for the creator and raises ''Reservation not found for this actor''; the per-session EXCEPTION handler swallows that into a WARNING and THE SESSION IS NEVER PURGED -- transcript, approved clippings and staged results retained indefinitely. The charged actor is whoever ADMITTED the generation, never the session''s creator.',
      v_purged;
  END IF;
  IF (SELECT state FROM public.ai_sessions WHERE id = v_session) != 'closed' THEN
    RAISE EXCEPTION 'EXPLOIT: the expired shared session with a partner-admitted reserved request was not closed -- see the message above.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ai_session_turns WHERE session_id = v_session)
     OR EXISTS (SELECT 1 FROM public.ai_session_sources WHERE session_id = v_session)
     OR EXISTS (SELECT 1 FROM public.ai_session_approvals WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'EXPLOIT: content survived the purge of a shared session with a partner-admitted reserved request';
  END IF;

  -- The PARTNER's reservation was released -- keyed on the row's own
  -- actor_id, which is the partner, not the creator.
  SELECT outcome INTO v_outcome
  FROM public.ai_assistant_usage WHERE request_id = v_admit.request_id;
  IF v_outcome IS DISTINCT FROM 'cancelled' THEN
    RAISE EXCEPTION
      'EXPLOIT: the NON-CREATOR partner''s unconsumed reservation is still % after their session was purged, expected ''cancelled''. The release must be keyed on the request row''s own actor_id; keyed on the session''s creator_id it either raises (wedging the purge entirely) or silently releases nothing and charges the partner for a generation that never reached a provider.',
      COALESCE(v_outcome, '<missing row>');
  END IF;
  -- And the CREATOR, who admitted nothing, has no usage row invented
  -- for them.
  IF EXISTS (
    SELECT 1 FROM public.ai_assistant_usage
    WHERE request_id = v_admit.request_id AND user_id = v_creator
  ) THEN
    RAISE EXCEPTION
      'EXPLOIT: an ai_assistant_usage row exists for the session CREATOR on a request the PARTNER admitted. Quota is charged to the actor who admitted, never to the session owner.';
  END IF;

  RAISE NOTICE 'purge contract 1c (F1 mis-keying): partner-admitted reserved request released on its OWN actor_id, session purged';
END $$;


-- =====================================================================
-- Contract 1d (TASK 11 FINDING F1, the OVER-RELEASE leg): a session
-- purged with a `started` request, whose reservation is LEGITIMATELY
-- CONSUMED and must stay charged.
--
-- WHY THIS LEG IS SEPARATE FROM 1b AND 1c. Both of those produce a
-- `reserved` request, so the mutant that releases for ALL THREE states
-- (reserved / started / staged) behaves identically to the correct body
-- on their fixtures and SURVIVES them -- measured. The mutant only
-- misbehaves when a `started` or `staged` request is present at purge
-- time, because claim_ai_session_dispatch has by then set the
-- write-once ai_assistant_usage.provider_started_at marker
-- (20260953060100), and release_ai_assistant_quota_reservation refuses
-- such a row with 'Cannot release a reservation whose provider call has
-- started'. That raise propagates into purge_expired_ai_sessions'
-- per-session EXCEPTION handler, is swallowed into a WARNING, and THE
-- SESSION IS NEVER PURGED.
--
-- So this contract is the third of three, and the three together pin
-- the loop's state discrimination from both sides:
--
--   1b  'reserved'  -> MUST release   (under-release mutant dies)
--   1c  'reserved', non-creator actor -> keyed on the ROW's actor_id
--   1d  'started'   -> MUST NOT release (over-release mutant dies)
--
-- THE CORRECTNESS BEING ASSERTED IS NOT "the quota is leaked". A
-- `started` request reached a provider, so the generation was really
-- paid for and the charge is correct -- Plan A's write-once marker
-- exists to make that irreversible. What this contract asserts is that
-- the purger RECOGNISES that and purges anyway, rather than trying to
-- un-charge a consumed reservation and wedging itself on the refusal.
-- =====================================================================
DO $$
DECLARE
  v_rel uuid := 'b1052000-0000-4000-8000-00000000000c';
  v_user_a uuid := 'b1052000-0000-4000-8000-0000000000aa';
  v_user_b uuid := 'b1052000-0000-4000-8000-0000000000bb';
  v_session uuid;
  v_admit record;
  v_purged int;
  v_state text;
  v_terminal text;
  v_outcome text;
  v_started timestamptz;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 't5_f1_started_a@t.test'), (v_user_b, 't5_f1_started_b@t.test');
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550514001', 'F1 Started A'), (v_user_b, '+15550514002', 'F1 Started B');
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active');
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  IF v_session IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: prepare_ai_session returned no session';
  END IF;
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_session, 1, 'ideas:f1-started'
  );
  IF v_admit.request_id IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: the F1 started fixture failed to admit (outcome=%)', v_admit.outcome;
  END IF;

  -- THE ONE STEP 1b AND 1c DELIBERATELY OMIT: dispatch. This moves the
  -- request to 'started' and sets the write-once provider marker, and
  -- it is the real path -- nothing is hand-written into either table.
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);

  -- ...and NO commit. The worker died mid-generation, which is the
  -- production shape that leaves a 'started' request at purge time.

  -- NON-VACUITY ANCHORS. Without these, a fixture that failed to reach
  -- 'started' would leave the over-release mutant alive -- exactly how
  -- it survived 1b and 1c.
  SELECT state INTO v_state FROM public.ai_session_requests WHERE id = v_admit.request_id;
  IF v_state IS DISTINCT FROM 'started' THEN
    RAISE EXCEPTION
      'SETUP FAILED: the request is in state % , not ''started'', at purge time. This contract exists ONLY to kill the mutant that releases for all three states, and that mutant misbehaves ONLY on a started/staged request -- a fixture that did not reach ''started'' leaves it alive.',
      COALESCE(v_state, '<missing>');
  END IF;
  SELECT outcome, provider_started_at INTO v_outcome, v_started
  FROM public.ai_assistant_usage WHERE request_id = v_admit.request_id;
  IF v_started IS NULL THEN
    RAISE EXCEPTION
      'SETUP FAILED: ai_assistant_usage.provider_started_at is NULL on a DISPATCHED request. That write-once marker is what makes the reservation legitimately consumed and unreleasable; without it the over-release mutant does not raise and this contract does not discriminate.';
  END IF;
  IF v_outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION
      'SETUP FAILED: the dispatched request''s usage row has outcome % , expected ''reserved'' (in flight, marker set) -- the refusal this contract relies on is keyed on exactly that combination',
      COALESCE(v_outcome, '<missing row>');
  END IF;

  UPDATE public.ai_sessions
  SET last_admitted_at = now() - interval '1 hour',
      expires_at = now() - interval '45 minutes'
  WHERE id = v_session;

  SELECT public.purge_expired_ai_sessions() INTO v_purged;

  -- THE LEG THAT KILLS THE OVER-RELEASE MUTANT.
  IF v_purged < 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: purge_expired_ai_sessions reported % purged for an expired session with a STARTED request. A loop that calls release_ai_assistant_quota_reservation for all three scanned states hits ''Cannot release a reservation whose provider call has started'' -- claim_ai_session_dispatch already set the write-once provider marker -- and that raise is swallowed by the per-session EXCEPTION handler into a WARNING, so THE SESSION IS NEVER PURGED and its content is retained indefinitely. A started request is LEGITIMATELY charged; it must be excluded from the release, not passed to it.',
      v_purged;
  END IF;
  IF (SELECT state FROM public.ai_sessions WHERE id = v_session) != 'closed' THEN
    RAISE EXCEPTION 'EXPLOIT: the expired session with a STARTED request was not closed -- see the message above.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ai_session_turns WHERE session_id = v_session)
     OR EXISTS (SELECT 1 FROM public.ai_session_sources WHERE session_id = v_session)
     OR EXISTS (SELECT 1 FROM public.ai_session_approvals WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'EXPLOIT: content survived the purge of a session with a STARTED request';
  END IF;

  -- The request is resolved, like every other outstanding state.
  SELECT state, terminal_code INTO v_state, v_terminal
  FROM public.ai_session_requests WHERE id = v_admit.request_id;
  IF v_state IS DISTINCT FROM 'cancelled' OR v_terminal IS DISTINCT FROM 'session_ended' THEN
    RAISE EXCEPTION
      'EXPLOIT: the STARTED request is state=% terminal_code=% after its session was purged, expected cancelled/session_ended. Being legitimately charged does not exempt it from leaving the states the reconciler scans.',
      COALESCE(v_state,'<deleted>'), COALESCE(v_terminal,'<null>');
  END IF;

  -- AND THE CHARGE STANDS. This is the other half of the
  -- discrimination: a purge that "helpfully" released a consumed
  -- reservation would hand back quota for a generation the provider was
  -- really paid for.
  SELECT outcome, provider_started_at INTO v_outcome, v_started
  FROM public.ai_assistant_usage WHERE request_id = v_admit.request_id;
  IF v_outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION
      'EXPLOIT: the STARTED request''s reservation was changed to % by the purge. Its provider call really happened (provider_started_at is set, write-once), so the quota is legitimately consumed and must stay charged -- releasing it refunds a generation that was paid for.',
      COALESCE(v_outcome, '<missing row>');
  END IF;
  IF v_started IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: the purge CLEARED the write-once provider_started_at marker. It is write-once by design: once a provider call has started, nothing may make the reservation look unconsumed again.';
  END IF;

  RAISE NOTICE 'purge contract 1d (F1 over-release): started request cancelled, reservation correctly LEFT CHARGED, session purged';
END $$;


-- =====================================================================
-- Contract 2: the PREPARING arm -- a session past its
-- preparation_deadline that Task 3's reclaim-on-prepare never catches.
--
-- This arm is the one that needs its own contract most. Task 3's
-- reclaim fires ONLY inside prepare_ai_session, and only for the SAME
-- creator on the SAME relationship -- so a pair that simply never
-- prepares again leaves the row and its approved source clippings
-- behind indefinitely. Asserting the active arm alone would leave this
-- entirely unproven.
-- =====================================================================
DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-00000000011c';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000011a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000011b';
  v_session uuid;
  v_purged int;
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  IF v_session IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: prepare_ai_session returned no session for the preparing-arm fixture';
  END IF;
  -- Approve, but never activate: the session stays 'preparing' with
  -- real approval content attached.
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');

  IF NOT EXISTS (SELECT 1 FROM public.ai_session_approvals WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'SETUP FAILED: the preparing fixture has no approval content -- the purge assertion would be vacuous';
  END IF;
  IF (SELECT state FROM public.ai_sessions WHERE id = v_session) != 'preparing' THEN
    RAISE EXCEPTION 'SETUP FAILED: the preparing fixture is not in state preparing';
  END IF;

  UPDATE public.ai_sessions
  SET preparation_deadline = now() - interval '30 minutes'
  WHERE id = v_session;

  SELECT public.purge_expired_ai_sessions() INTO v_purged;
  IF v_purged < 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: purge_expired_ai_sessions ignored a PREPARING session past its preparation_deadline (reported % purged). Task 3''s reclaim-on-prepare only fires when the same creator prepares again on the same relationship, so a pair that never prepares again keeps its approved source clippings forever (spec §8.2.3).',
      v_purged;
  END IF;
  IF (SELECT state FROM public.ai_sessions WHERE id = v_session) != 'closed' THEN
    RAISE EXCEPTION 'EXPLOIT: an expired PREPARING session was not closed by the purge job';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ai_session_approvals WHERE session_id = v_session) THEN
    RAISE EXCEPTION
      'EXPLOIT: % approval row(s) survived the purge of an expired PREPARING session',
      (SELECT count(*) FROM public.ai_session_approvals WHERE session_id = v_session);
  END IF;

  RAISE NOTICE 'purge contract 2: expired PREPARING session purged, approval content gone';
END $$;


-- =====================================================================
-- Contract 3: the purger does NOT touch a session that is still live,
-- and is idempotent.
--
-- The over-restriction direction. A purger that closed live sessions
-- would pass every assertion in Contracts 1 and 2 while destroying
-- working sessions, so this is not optional coverage.
-- =====================================================================
DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-00000000011d';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000011a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000011b';
  v_session uuid;
  v_state text;
  v_rev_before int;
  v_rev_after int;
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  -- Comfortably live, in both directions the purger scans.
  UPDATE public.ai_sessions
  SET expires_at = now() + interval '10 minutes',
      preparation_deadline = now() + interval '10 minutes'
  WHERE id = v_session;

  SELECT revision INTO v_rev_before FROM public.ai_sessions WHERE id = v_session;
  PERFORM public.purge_expired_ai_sessions();
  SELECT state, revision INTO v_state, v_rev_after
  FROM public.ai_sessions WHERE id = v_session;

  IF v_state != 'active' THEN
    RAISE EXCEPTION
      'EXPLOIT: the purge job closed a LIVE unexpired session (state is now %) -- it must purge only sessions past their own expiry',
      v_state;
  END IF;
  -- Not merely "still active": not mutated AT ALL. A purger that bumped
  -- the revision of every live session would break admission's
  -- expected_revision check on every working session once a minute.
  IF v_rev_after != v_rev_before THEN
    RAISE EXCEPTION
      'EXPLOIT: the purge job mutated a LIVE session''s revision (% -> %) -- admission''s expected_revision check would fail on every working session once a minute',
      v_rev_before, v_rev_after;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ai_session_approvals WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'EXPLOIT: the purge job deleted a LIVE session''s approval content';
  END IF;

  -- Idempotent: a second run with nothing new to purge neither errors
  -- nor reports work it did not do. The job runs every minute forever,
  -- so this is its normal steady state, not an edge case.
  IF public.purge_expired_ai_sessions() != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a second purge run reported % purged with nothing newly expired -- the job double-counts, so its purge-lag metric cannot be trusted',
      public.purge_expired_ai_sessions();
  END IF;

  -- The primitive itself is idempotent on an already-closed session,
  -- and reports false rather than counting phantom work.
  PERFORM public.end_ai_session(v_user_a, v_session);
  IF public.purge_ai_session_content(v_session) THEN
    RAISE EXCEPTION
      'EXPLOIT: purge_ai_session_content reported TRUE for an already-closed session -- the purger''s count would include sessions it did not purge';
  END IF;

  RAISE NOTICE 'purge contract 3: live sessions untouched and unmutated, purge idempotent';
END $$;


-- =====================================================================
-- Contract 4 (ROUTED ITEM 2): end_ai_session's idempotency is STABILITY,
-- not merely "no error".
--
-- Task 9's re-review found that removing end_ai_session's closed-state
-- early return SURVIVES the whole suite: the existing contract only
-- calls it twice and checks nothing raised. Benign today (it re-bumps
-- revision/epoch and cannot double-release, because the release RPC's
-- `WHERE outcome='reserved'` is idempotent), but unasserted. A second
-- end on an already-closed session must not advance revision or
-- generation_epoch.
-- =====================================================================
DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-00000000011e';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000011a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000011b';
  v_session uuid;
  v_rev1 int; v_epoch1 int;
  v_rev2 int; v_epoch2 int;
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);

  PERFORM public.end_ai_session(v_user_a, v_session);
  SELECT revision, generation_epoch INTO v_rev1, v_epoch1
  FROM public.ai_sessions WHERE id = v_session;

  -- The SECOND end. Not "does it raise" -- does it MUTATE.
  PERFORM public.end_ai_session(v_user_a, v_session);
  SELECT revision, generation_epoch INTO v_rev2, v_epoch2
  FROM public.ai_sessions WHERE id = v_session;

  IF v_rev2 != v_rev1 THEN
    RAISE EXCEPTION
      'EXPLOIT: a second end_ai_session on an already-closed session advanced revision (% -> %). Its closed-state early return is gone, so End is no longer idempotent: every repeated End invalidates a revision-polling client''s token and, were the release RPC ever made non-idempotent, would double-release quota.',
      v_rev1, v_rev2;
  END IF;
  IF v_epoch2 != v_epoch1 THEN
    RAISE EXCEPTION
      'EXPLOIT: a second end_ai_session on an already-closed session advanced generation_epoch (% -> %) -- its closed-state early return is gone',
      v_epoch1, v_epoch2;
  END IF;

  -- The same stability property on the purger's own primitive: it
  -- shares the early return, and a system job that runs every minute
  -- must not re-bump every closed session forever.
  PERFORM public.purge_ai_session_content(v_session);
  SELECT revision, generation_epoch INTO v_rev2, v_epoch2
  FROM public.ai_sessions WHERE id = v_session;
  IF v_rev2 != v_rev1 OR v_epoch2 != v_epoch1 THEN
    RAISE EXCEPTION
      'EXPLOIT: purge_ai_session_content mutated an already-closed session (revision % -> %, epoch % -> %) -- the every-minute job would re-bump every closed session forever',
      v_rev1, v_rev2, v_epoch1, v_epoch2;
  END IF;

  RAISE NOTICE 'purge contract 4 (routed item 2): end_ai_session idempotency is stable, not merely silent';
END $$;


-- =====================================================================
-- Contract 5 (ROUTED ITEM 3): the quota-residue sweep detects and
-- RESOLVES an ai_assistant_usage row left at outcome='reserved' AND
-- provider_started_at IS NULL under a TERMINAL request row.
--
-- That is precisely the shape of the F1 quota-stranding leak Task 9
-- fixed in code: the usage row counts against the actor's rolling
-- window forever (the window excludes only outcome IN
-- ('rejected','cancelled')) while no reconciler path can reach it
-- (reconcile_ai_session_leases scans only state IN
-- ('reserved','started')). Nothing enforced it at the DB level.
-- =====================================================================
DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-00000000011f';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000011a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000011b';
  v_session uuid;
  v_admit record;
  v_swept int;
  v_outcome text;
  v_counted int;
  v_marker timestamptz;
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_session, 1, 'ideas:residue'
  );
  IF v_admit.request_id IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: the residue fixture failed to admit (outcome=%)', v_admit.outcome;
  END IF;

  -- Manufacture the residue by direct UPDATE -- the request reaches a
  -- terminal state while its reservation is left unresolved. This is
  -- the state the F1 bug produced through end_ai_session, and which
  -- any FUTURE code path that forgets the release would reproduce; the
  -- sweep exists precisely because no single guard can prevent every
  -- such path.
  UPDATE public.ai_session_requests
  SET state = 'cancelled', terminal_code = 'manufactured_residue'
  WHERE id = v_admit.request_id;

  -- NON-VACUITY ANCHOR: the residue really is in the leaking shape,
  -- and really is counted against the actor's window, BEFORE the sweep.
  SELECT outcome, provider_started_at INTO v_outcome, v_marker
  FROM public.ai_assistant_usage WHERE request_id = v_admit.request_id;
  IF v_outcome IS DISTINCT FROM 'reserved' OR v_marker IS NOT NULL THEN
    RAISE EXCEPTION
      'SETUP FAILED: the manufactured residue is not in the stranding shape (outcome=%, provider_started_at=%) -- the sweep assertion would be vacuous',
      v_outcome, v_marker;
  END IF;
  SELECT count(*) INTO v_counted FROM public.ai_assistant_usage
  WHERE request_id = v_admit.request_id
    AND (provider_started_at IS NOT NULL OR outcome NOT IN ('rejected', 'cancelled'));
  IF v_counted != 1 THEN
    RAISE EXCEPTION
      'SETUP FAILED: the manufactured residue is not counted against the rolling quota window before the sweep -- there is nothing for the sweep to fix';
  END IF;

  SELECT public.reconcile_ai_session_quota_residue() INTO v_swept;
  IF v_swept < 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: reconcile_ai_session_quota_residue ignored a reservation stranded at outcome=''reserved'' with provider_started_at IS NULL under a TERMINAL request row (reported % swept). That is the exact shape of the F1 quota-stranding leak: it counts against the actor''s 20-per-24h window forever and reconcile_ai_session_leases can never reach it.',
      v_swept;
  END IF;

  SELECT outcome INTO v_outcome FROM public.ai_assistant_usage
  WHERE request_id = v_admit.request_id;
  IF v_outcome IS DISTINCT FROM 'cancelled' THEN
    RAISE EXCEPTION
      'EXPLOIT: the residue sweep ran but left the reservation at outcome=% -- detecting the residue without resolving it leaves the quota burned',
      v_outcome;
  END IF;
  SELECT count(*) INTO v_counted FROM public.ai_assistant_usage
  WHERE request_id = v_admit.request_id
    AND (provider_started_at IS NOT NULL OR outcome NOT IN ('rejected', 'cancelled'));
  IF v_counted != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the swept reservation is STILL counted against the actor''s rolling quota window -- the sweep changed the outcome without freeing the quota';
  END IF;

  -- Idempotent: it runs every minute, so a second pass over resolved
  -- residue must report zero rather than re-counting.
  IF public.reconcile_ai_session_quota_residue() != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the residue sweep re-counted already-resolved residue -- its metric cannot be trusted and it rewrites rows every minute forever';
  END IF;

  RAISE NOTICE 'purge contract 5 (routed item 3): stranded reservation detected, released, and quota freed';
END $$;


-- =====================================================================
-- Contract 5b (ROUTED ITEM 3, the over-restriction direction): the
-- sweep must NOT release a reservation whose provider call started, and
-- must NOT touch Plan A's non-session ledger rows.
--
-- A sweep that released a CONSUMED reservation would be a quota-evasion
-- hole -- strictly worse than the stranding it fixes, because a user
-- could burn provider calls for free. And one that touched
-- mode='assist'/'understand' rows would corrupt Plan A's ledger, where
-- a reservation with no ai_session_requests row is NORMAL by design.
-- =====================================================================
DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000120';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000011a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000011b';
  v_session uuid;
  v_admit record;
  v_outcome text;
  v_assist_request uuid := 'b1000000-0000-0000-0000-000000000121';
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_session, 1, 'ideas:consumed'
  );
  -- Dispatch it: claim_ai_session_dispatch sets the write-once
  -- ai_assistant_usage.provider_started_at marker, so this reservation
  -- has LEGITIMATELY consumed quota.
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  IF (SELECT provider_started_at FROM public.ai_assistant_usage
      WHERE request_id = v_admit.request_id) IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: the consumed fixture has no provider-start marker -- the over-restriction assertion would be vacuous';
  END IF;
  -- Now strand it in a terminal request state, which is what makes it
  -- a candidate for the sweep's scan at all.
  UPDATE public.ai_session_requests
  SET state = 'failed', terminal_code = 'manufactured'
  WHERE id = v_admit.request_id;

  -- A mode='assist' reservation with NO ai_session_requests row: Plan
  -- A's normal shape, and the orphan arm of the sweep's scan must not
  -- claim it.
  INSERT INTO public.ai_assistant_usage
    (request_id, user_id, relationship_id, mode, outcome, provider_calls)
  VALUES (v_assist_request, v_user_a, v_rel, 'assist', 'reserved', 0)
  ON CONFLICT DO NOTHING;
  IF NOT EXISTS (SELECT 1 FROM public.ai_assistant_usage WHERE request_id = v_assist_request) THEN
    RAISE EXCEPTION 'SETUP FAILED: the Plan A ledger fixture was silently dropped -- the mode-scoping assertion would be vacuous';
  END IF;

  PERFORM public.reconcile_ai_session_quota_residue();

  SELECT outcome INTO v_outcome FROM public.ai_assistant_usage
  WHERE request_id = v_admit.request_id;
  IF v_outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION
      'EXPLOIT: the residue sweep released a reservation whose provider call HAD STARTED (outcome is now %). That is a quota-evasion hole -- a user could burn real provider calls and have the charge swept away a minute later, which is strictly worse than the stranding the sweep exists to fix.',
      v_outcome;
  END IF;

  SELECT outcome INTO v_outcome FROM public.ai_assistant_usage
  WHERE request_id = v_assist_request;
  IF v_outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION
      'EXPLOIT: the residue sweep touched a mode=''assist'' ledger row (outcome is now %). Plan A''s assist/understand reservations have NO ai_session_requests row BY DESIGN, so an unscoped orphan sweep would cancel every in-flight Plan A reservation on the platform once a minute.',
      v_outcome;
  END IF;

  RAISE NOTICE 'purge contract 5b (routed item 3): consumed reservations stay charged, Plan A ledger untouched';
END $$;


-- =====================================================================
-- Contract 6 (ROUTED ITEM 1): publish_ai_session_nearby_result refuses
-- to commit a staged Nearby result after AI-processing consent is
-- withdrawn -- and the refusal is a RAISE, not a silent no-op.
--
-- This is the WRITE leg of the leak Task 10's F1 closed on the read
-- side. It is strictly worse than the read leak it mirrors: the read
-- leak made content READABLE for ~2 minutes post-withdrawal, while this
-- one COMMITS it into the permanent transcript.
--
-- THE FAILURE MODE IS ASSERTED AS AN EXCEPTION, DELIBERATELY. The read
-- RPCs are silent by design (zero rows); this one RAISEs on every other
-- rejection and returns (committed, user_ordinal, attune_ordinal). A
-- verbatim `RETURN;` would hand the caller zero rows -- read as neither
-- success nor failure, and as a NULL `committed` by a caller doing
-- `SELECT committed FROM ...`. Reporting success while committing
-- nothing is worse than either option, so a zero-count assertion here
-- would be asserting the wrong contract.
-- =====================================================================
DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000122';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000011a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000011b';
  v_session uuid;
  v_admit record;
  v_committed boolean;
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
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
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_session, 1, 'nearby:withdrawn'
  );
  IF v_admit.request_id IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: the publish-gate fixture failed to admit (outcome=%)', v_admit.outcome;
  END IF;
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  PERFORM public.stage_ai_session_nearby_result(
    v_admit.worker_token, v_admit.request_id, 'a nearby reply', '[]'::jsonb
  );
  IF NOT EXISTS (SELECT 1 FROM public.ai_session_staging WHERE request_id = v_admit.request_id) THEN
    RAISE EXCEPTION 'SETUP FAILED: nothing was staged -- the publish-gate assertion would be vacuous';
  END IF;

  -- B WITHDRAWS CONSENT. clock_timestamp(), not now(): now() is frozen
  -- per transaction, so this event would tie with the grants above and
  -- the lookup's `id DESC` tiebreak on a random uuid would make this
  -- contract a coin flip.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES (v_rel, v_user_b, 'v1', 'withdrawn', gen_random_uuid(), clock_timestamp());

  BEGIN
    SELECT committed INTO v_committed FROM public.publish_ai_session_nearby_result(
      v_user_a, v_admit.request_id
    );
    RAISE EXCEPTION
      'EXPLOIT: publish_ai_session_nearby_result COMMITTED a staged Nearby result after the partner withdrew AI-processing consent (committed=%). The content is now permanently in the session transcript -- strictly worse than Task 10''s F1 read leak, which merely kept it readable for ~2 minutes.',
      v_committed;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%AI processing consent is not current for this relationship%' THEN
      RAISE EXCEPTION
        'EXPLOIT: publish''s consent gate did not fire -- a DIFFERENT error stood in for it: %. The contract must prove the consent gate denied the publish, not that something somewhere failed.',
        SQLERRM;
    END IF;
  END;

  -- THE REFUSAL WAS REAL: nothing was committed and the request is
  -- still publishable if consent returns.
  --
  -- A LIMITATION WORTH STATING PRECISELY, BECAUSE IT WAS MEASURED.
  -- These two assertions CANNOT detect a gate placed AFTER the turns
  -- INSERT. A plpgsql BEGIN ... EXCEPTION block is an implicit
  -- subtransaction, so when the gate raises, everything the function
  -- wrote in that call is rolled back to the start of the call --
  -- whether the gate sat before the INSERT or after it. Proven
  -- directly: an INSERT followed by a RAISE inside an exception block
  -- leaves 0 rows. So a mutant that moves the gate below the INSERT
  -- (mutation M7) is behaviourally INVISIBLE from inside one
  -- transaction and survives this leg.
  --
  -- That is not a hole in the production logic -- the rollback is real,
  -- so a late gate still commits nothing -- but gate ORDER is still
  -- worth pinning, because the ordering is what keeps it that way: a
  -- future refactor that moved the INSERT into its own committed
  -- subtransaction, or added a non-transactional side effect (a
  -- net.http_post, a NOTIFY, a sequence bump) between the INSERT and a
  -- late gate, would leak for real. Contract 11 therefore asserts the
  -- gate's POSITION structurally, which is the only assertion that can
  -- see it. These two behavioural checks are kept because they prove
  -- the complementary thing a structural check cannot: that the
  -- rollback actually happened and the request stayed publishable.
  IF EXISTS (SELECT 1 FROM public.ai_session_turns WHERE request_id = v_admit.request_id) THEN
    RAISE EXCEPTION
      'EXPLOIT: % turn row(s) survived the consent gate''s raise -- the publish is not atomic, so a denied publish still committed content',
      (SELECT count(*) FROM public.ai_session_turns WHERE request_id = v_admit.request_id);
  END IF;
  IF (SELECT state FROM public.ai_session_requests WHERE id = v_admit.request_id) = 'committed' THEN
    RAISE EXCEPTION 'EXPLOIT: the request was marked committed despite the consent gate raising';
  END IF;

  -- RE-GRANT RESTORES THE PUBLISH. The over-restriction direction: a
  -- gate that denied permanently would pass every assertion above
  -- while breaking the legitimate path, and the staging row is
  -- deliberately left in place for exactly this case.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  -- Wrapped, so an over-restrictive gate fails with a message that
  -- NAMES the over-restriction rather than letting the RPC's own raise
  -- propagate as a bare 'consent is not current'. A gate that denies
  -- unconditionally (mutation M6) dies here, and the diagnosis must not
  -- require reading the stack: a bare propagated error from this line
  -- looks identical to a fixture that simply failed to grant consent.
  BEGIN
    SELECT committed INTO v_committed FROM public.publish_ai_session_nearby_result(
      v_user_a, v_admit.request_id
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION
      'EXPLOIT (over-restriction): publish was REJECTED although both partners hold current consent and the actor is the staging row''s requester -- the new gate denies more than spec §7.2 requires, which breaks the legitimate Nearby publish path entirely. The RPC raised: %',
      SQLERRM;
  END;
  IF v_committed IS NOT TRUE THEN
    RAISE EXCEPTION
      'EXPLOIT (over-restriction): the consent gate denied a publish with CURRENT consent from both partners (committed=%) -- the gate must subtract access only where spec §7.2 requires',
      v_committed;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ai_session_turns WHERE request_id = v_admit.request_id) THEN
    RAISE EXCEPTION 'EXPLOIT (over-restriction): the re-granted publish reported committed but wrote no turns';
  END IF;

  RAISE NOTICE 'purge contract 6 (routed item 1): publish denied post-withdrawal with its own specific raise, restored on re-grant';
END $$;


-- =====================================================================
-- Contract 6b (ROUTED ITEM 1): the MEMBERSHIP half of publish's new
-- gate, denied by a REPLACEMENT CONSENTING MEMBER rather than by a NULL.
--
-- Denying by nulling a relationship member is SELF-DEFEATING on these
-- RPCs: the consent gate reads user_a/user_b, so a NULL member empties
-- the consent lookup and the contract passes against a mutant that is
-- genuinely exploitable (Task 10 hit this twice). The ex-member is
-- REPLACED by a third, fully consenting member here, so consent is
-- current for the relationship's CURRENT pair and only the membership
-- actor predicate can deny.
-- =====================================================================
DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000123';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000011a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000011b';
  v_user_c uuid := 'b1000000-0000-0000-0000-000000000124';
  v_session uuid;
  v_admit record;
  v_committed boolean;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_c, 't11_purge_c@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_c, '+15550110003', 'C')
  ON CONFLICT DO NOTHING;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_user_c) THEN
    RAISE EXCEPTION
      'SETUP FAILED: the replacement member fixture was silently dropped (phone +15550110003 collides) -- this contract would then deny by a NULL member, which is the self-defeating shape it exists to avoid.';
  END IF;

  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    -- C consents UP FRONT, so that after the swap the relationship's
    -- current pair (C, B) both have current consent and the consent
    -- gate CANNOT be what denies A.
    (v_rel, v_user_c, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'nearby', 'shared', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_session, 1, 'nearby:exmember'
  );
  IF v_admit.request_id IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: the membership-gate fixture failed to admit (outcome=%)', v_admit.outcome;
  END IF;
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  PERFORM public.stage_ai_session_nearby_result(
    v_admit.worker_token, v_admit.request_id, 'a nearby reply', '[]'::jsonb
  );

  -- A is REPLACED by C. A still owns the staging row (so the author
  -- check still passes and cannot be what denies), and the current
  -- pair (C, B) both consent (so the consent gate cannot be what
  -- denies). Only the membership actor predicate is left.
  UPDATE public.relationships SET user_a = v_user_c WHERE id = v_rel;

  BEGIN
    SELECT committed INTO v_committed FROM public.publish_ai_session_nearby_result(
      v_user_a, v_admit.request_id
    );
    RAISE EXCEPTION
      'EXPLOIT: an ex-member who was REPLACED in the relationship still published their staged Nearby result into the transcript (committed=%) -- publish''s membership actor predicate is missing or dead',
      v_committed;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%Not a current member of this relationship%' THEN
      RAISE EXCEPTION
        'EXPLOIT: publish''s membership gate did not fire -- a DIFFERENT error stood in for it: %', SQLERRM;
    END IF;
  END;
  IF EXISTS (SELECT 1 FROM public.ai_session_turns WHERE request_id = v_admit.request_id) THEN
    RAISE EXCEPTION 'EXPLOIT: turns were written despite the membership gate raising';
  END IF;

  -- The LIVENESS half of the same gate, on a relationship whose
  -- membership is intact: archive the chat and the publish must still
  -- be denied. Restore A first so membership is not what denies.
  UPDATE public.relationships SET user_a = v_user_a, chat_archived_at = now() WHERE id = v_rel;
  BEGIN
    SELECT committed INTO v_committed FROM public.publish_ai_session_nearby_result(
      v_user_a, v_admit.request_id
    );
    RAISE EXCEPTION
      'EXPLOIT: a staged Nearby result was published into an ARCHIVED chat (committed=%) -- publish''s liveness gate (status active, chat_archived_at IS NULL) is missing',
      v_committed;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%Not a current member of this relationship%' THEN
      RAISE EXCEPTION
        'EXPLOIT: publish''s liveness gate did not fire on an archived chat -- a DIFFERENT error stood in for it: %', SQLERRM;
    END IF;
  END;

  RAISE NOTICE 'purge contract 6b (routed item 1): ex-member and archived-chat publishes both denied by the membership gate';
END $$;


-- =====================================================================
-- Contract 7 (ROUTED ITEM 4): ai_session_approvals.member_id must be a
-- member of the session's relationship.
--
-- Until now nothing tied them, which is why Gate 1's actor predicate in
-- read_ai_session_turns was the ONLY thing stopping a non-member holding
-- a forged approval row at the current context_revision from reading a
-- full shared transcript (Task 10's F2). This makes the forged row
-- impossible to create, so the read gate and the write constraint are
-- independent defences rather than one.
-- =====================================================================
DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000125';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000011a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000011b';
  v_outsider uuid := 'b1000000-0000-0000-0000-000000000126';
  v_session uuid;
  -- TASK 11 F4: a SECOND relationship and session, on which v_user_a is
  -- NOT a member, so the `UPDATE OF session_id` forgery leg below has
  -- somewhere illegitimate to repoint a legitimate approval.
  v_rel_other uuid := 'b1000000-0000-0000-0000-000000000127';
  v_third uuid := 'b1000000-0000-0000-0000-000000000128';
  v_other_session uuid;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_outsider, 't11_purge_out@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_outsider, '+15550110004', 'OUT')
  ON CONFLICT DO NOTHING;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_outsider) THEN
    RAISE EXCEPTION 'SETUP FAILED: the outsider fixture was silently dropped (phone +15550110004 collides) -- the forged-approval assertion would be vacuous';
  END IF;
  INSERT INTO auth.users (id, email) VALUES (v_third, 't5_f4_third@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_third, '+15550110007', 'THIRD')
  ON CONFLICT DO NOTHING;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_third) THEN
    RAISE EXCEPTION 'SETUP FAILED: the F4 third-party fixture was silently dropped (phone +15550110007 collides) -- the session_id UPDATE forgery leg would be vacuous';
  END IF;

  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  IF v_session IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: prepare_ai_session returned no session for the approvals-constraint fixture';
  END IF;

  -- TASK 11 F4 SETUP: the OTHER relationship's session. v_outsider and
  -- v_third are its members, so v_user_a is NOT -- which is what makes
  -- repointing v_user_a's approval at it a forgery. PRIVATE visibility,
  -- because prepare_ai_session forbids two concurrent SHARED sessions
  -- per relationship and this is a different relationship anyway; a
  -- private session is enough, since the trigger reads only
  -- ai_sessions.relationship_id.
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel_other, v_outsider, v_third, 'active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel_other, v_outsider, 'v1', 'granted', gen_random_uuid(), clock_timestamp()),
    (v_rel_other, v_third, 'v1', 'granted', gen_random_uuid(), clock_timestamp());
  SELECT session_id INTO v_other_session FROM public.prepare_ai_session(
    v_outsider, gen_random_uuid(), v_rel_other, 'ideas', 'private', NULL, false
  );
  IF v_other_session IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILED: could not prepare the OTHER relationship''s session -- the session_id UPDATE forgery leg has nowhere to repoint and would be vacuous';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = v_rel_other AND (r.user_a = v_user_a OR r.user_b = v_user_a)
  ) THEN
    RAISE EXCEPTION 'SETUP FAILED: v_user_a IS a member of the other relationship, so repointing their approval at its session would be legitimate and the forgery leg would not discriminate';
  END IF;

  -- THE FORGERY: a direct INSERT of an approval row for a user who has
  -- nothing to do with this relationship. This is the write that
  -- Task 10's F2 exploit depended on, and only service_role/superuser
  -- can reach it (no table grants, RLS on, zero policies).
  BEGIN
    INSERT INTO public.ai_session_approvals
      (session_id, member_id, revision, digest, policy_version)
    VALUES (v_session, v_outsider, 1, 'd', 'v1');
    RAISE EXCEPTION
      'EXPLOIT: an approval row was forged for a user who is not a member of the session''s relationship. That row is exactly the F2 exploit''s input: with it, the actor predicate in read_ai_session_turns'' Gate 1 is the SINGLE remaining thing standing between an outsider and a full shared transcript.';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%is not a member of session%' THEN
      RAISE EXCEPTION
        'EXPLOIT: the approvals membership constraint did not fire -- a DIFFERENT error stood in for it: %. A FK or NOT NULL violation is not proof that the relationship constraint exists.',
        SQLERRM;
    END IF;
  END;
  IF EXISTS (
    SELECT 1 FROM public.ai_session_approvals
    WHERE session_id = v_session AND member_id = v_outsider
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: the forged approval row was committed despite the constraint raising';
  END IF;

  -- THE OVER-RESTRICTION DIRECTION. Both real members must still be
  -- able to approve -- through the RPC and, since the constraint is a
  -- trigger on the table, by direct insert too.
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_session, 1, 'd', 'v1');
  IF (SELECT count(*) FROM public.ai_session_approvals WHERE session_id = v_session) != 2 THEN
    RAISE EXCEPTION
      'EXPLOIT (over-restriction): the approvals membership constraint blocked a legitimate approval -- % row(s) exist where 2 are expected',
      (SELECT count(*) FROM public.ai_session_approvals WHERE session_id = v_session);
  END IF;

  -- ---- TASK 11 FINDING F4: THE **UPDATE** ARM ---------------------
  --
  -- THE GAP THIS CLOSES. The trigger is
  -- `BEFORE INSERT OR UPDATE OF member_id, session_id`, but every
  -- assertion above drives it through INSERT only. MEASURED: narrowing
  -- the trigger to `BEFORE INSERT` passes the entire suite, and the
  -- UPDATE forgery was then reconstructed live on that mutant --
  -- insert a legitimate approval, then repoint its member_id at an
  -- outsider. The row that results is byte-identical to the forged
  -- INSERT the leg above rejects, so the whole INSERT-side guard is
  -- bypassable by anyone who can write the table at all (service_role,
  -- a migration, Plan C's edge function, an operator).
  --
  -- WHY member_id AND session_id BOTH. The trigger names both columns
  -- in its `UPDATE OF` list, and each is a distinct forgery:
  --   * repointing member_id   -> grants an OUTSIDER read access to
  --                               this session's turns via Gate 4's
  --                               approvals lookup.
  --   * repointing session_id  -> moves a legitimate member's approval
  --                               onto ANOTHER relationship's session,
  --                               where they are not a member.
  -- A trigger narrowed to `UPDATE OF member_id` alone would pass the
  -- first leg and fail the second, so both are asserted separately.
  --
  -- THE FORGERY TARGET. v_outsider is a real user who is NOT a member
  -- of this session's relationship -- the same actor the INSERT leg
  -- above uses. Denying by nulling a member would be self-defeating
  -- here for the usual reason (the trigger reads relationships.user_a /
  -- user_b, so a NULL member empties its own lookup), so the denial is
  -- asserted against a REPLACEMENT non-member, never an absent one.
  BEGIN
    UPDATE public.ai_session_approvals
    SET member_id = v_outsider
    WHERE session_id = v_session AND member_id = v_user_a;
    RAISE EXCEPTION
      'EXPLOIT: a legitimate approval row was UPDATEd to point at an OUTSIDER (member_id -> a non-member of this session''s relationship) and the membership trigger did not fire. The resulting row is byte-identical to the forged INSERT this contract rejects above, so the entire INSERT-side guard is bypassable in two statements: insert legitimately, then repoint. That row satisfies read_ai_session_turns'' Gate 4 (an approvals row at the session''s current context_revision) and hands an outsider the couple''s transcript. The trigger must be BEFORE INSERT **OR UPDATE OF member_id, session_id** -- narrowing it to BEFORE INSERT passes every other assertion in this suite.';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    -- ANTI-VACUITY: assert the SPECIFIC error, never "any error". A
    -- deadlock, a permission error or an FK violation must not read as
    -- a kill -- the plan's history has six vacuous tests in it.
    IF SQLERRM NOT LIKE '%is not a member of session%' THEN
      RAISE EXCEPTION
        'SETUP FAILED: the member_id UPDATE forgery was refused, but by the WRONG error -- expected the membership trigger''s "... is not a member of session ...", got: %. The contract would otherwise pass on an incidental failure rather than on the guard it exists to prove.',
        SQLERRM;
    END IF;
  END;

  -- The legitimate row is UNTOUCHED -- the trigger refused the
  -- statement, it did not partially apply it.
  IF NOT EXISTS (
    SELECT 1 FROM public.ai_session_approvals
    WHERE session_id = v_session AND member_id = v_user_a AND revision = 1
  ) THEN
    RAISE EXCEPTION
      'EXPLOIT: the rejected member_id UPDATE removed or altered the legitimate approval row it targeted. A BEFORE trigger that raises must leave the row exactly as it was.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.ai_session_approvals
    WHERE session_id = v_session AND member_id = v_outsider
  ) THEN
    RAISE EXCEPTION
      'EXPLOIT: an approval row for the OUTSIDER exists after the UPDATE was supposedly refused.';
  END IF;

  -- THE session_id LEG. Move a legitimate member's approval onto a
  -- session belonging to a relationship they are not party to. v_other
  -- is that session, built on v_rel_other below.
  BEGIN
    UPDATE public.ai_session_approvals
    SET session_id = v_other_session
    WHERE session_id = v_session AND member_id = v_user_a AND revision = 1;
    RAISE EXCEPTION
      'EXPLOIT: a legitimate approval row was UPDATEd to point at a session on a DIFFERENT relationship (session_id -> a session whose relationship this member is not party to) and the membership trigger did not fire. The trigger lists session_id in its `UPDATE OF` clause precisely because repointing it forges exactly the cross-relationship approval the INSERT leg rejects -- a trigger narrowed to `UPDATE OF member_id` alone would pass the leg above and fail here.';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%is not a member of session%' THEN
      RAISE EXCEPTION
        'SETUP FAILED: the session_id UPDATE forgery was refused, but by the WRONG error -- expected the membership trigger''s "... is not a member of session ...", got: %',
        SQLERRM;
    END IF;
  END;
  IF EXISTS (
    SELECT 1 FROM public.ai_session_approvals
    WHERE session_id = v_other_session AND member_id = v_user_a
  ) THEN
    RAISE EXCEPTION
      'EXPLOIT: the approval row was moved onto the other relationship''s session despite the refusal.';
  END IF;

  -- OVER-RESTRICTION, the other direction: a LEGITIMATE update that
  -- changes neither forged column must still succeed. A trigger that
  -- raised on every UPDATE would pass both legs above while making the
  -- table effectively append-only -- and the purge path, re-approval
  -- and any operator repair would break.
  BEGIN
    UPDATE public.ai_session_approvals
    SET digest = 'd-rewritten'
    WHERE session_id = v_session AND member_id = v_user_a AND revision = 1;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION
      'EXPLOIT (over-restriction): the membership trigger rejected a legitimate UPDATE that touched neither member_id nor session_id (it rewrote digest). The trigger''s `UPDATE OF member_id, session_id` clause must scope it to the two columns that can forge membership; firing on every UPDATE makes the table append-only. It raised: %',
      SQLERRM;
  END;
  IF (SELECT digest FROM public.ai_session_approvals
      WHERE session_id = v_session AND member_id = v_user_a AND revision = 1) != 'd-rewritten' THEN
    RAISE EXCEPTION
      'SETUP FAILED: the legitimate digest UPDATE did not apply, so the over-restriction assertion proved nothing';
  END IF;
  -- ...and a self-UPDATE that REWRITES member_id to the SAME legitimate
  -- member must pass: the trigger fires (member_id is in its UPDATE OF
  -- list) and must find that member IS a member.
  BEGIN
    UPDATE public.ai_session_approvals
    SET member_id = v_user_a
    WHERE session_id = v_session AND member_id = v_user_a AND revision = 1;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION
      'EXPLOIT (over-restriction): the membership trigger rejected an UPDATE that set member_id to the SAME, legitimate member. It must validate the NEW value against relationship membership, not reject change as such. It raised: %',
      SQLERRM;
  END;

  -- THE TRIGGER MUST ENFORCE *MEMBERSHIP*, NOT *LIVENESS*.
  --
  -- This is the one distinction the trigger's design turns on, and it
  -- needs its own assertion because the obvious way to write the
  -- trigger -- copying approve_ai_session_context's own predicate,
  -- which requires `status = 'active' AND chat_archived_at IS NULL` --
  -- is subtly wrong here. An approval is a HISTORICAL FACT about who
  -- approved a context snapshot. The fact that a relationship was later
  -- archived or ended must not retroactively make that row
  -- unwritable, because the write paths the RPC does not mediate
  -- (Plan C's edge function, a migration, a backfill, an operator
  -- repair) legitimately touch sessions on relationships that have
  -- since changed state. Liveness is, and stays, the READ RPCs' Gate 1
  -- -- which Task 10 proved denies an ex-member even while they hold a
  -- valid current-revision approval.
  --
  -- Asserted on a direct INSERT for a REAL member of an ARCHIVED
  -- relationship. That path is specifically chosen because it is the
  -- only one that discriminates: approve_ai_session_context ALREADY
  -- requires active+unarchived, so a liveness-requiring trigger is
  -- invisible through the RPC (measured -- mutation M14, which adds
  -- `status='active' AND chat_archived_at IS NULL` to the trigger,
  -- survives every assertion that goes through the RPC). It is also
  -- why this is not asserted via the purge: the trigger is BEFORE
  -- INSERT OR UPDATE and never fires on DELETE, so no trigger
  -- predicate whatsoever can block the synchronous purge, and an
  -- assertion that checked the purge here could never fail.
  UPDATE public.relationships SET chat_archived_at = now() WHERE id = v_rel;
  BEGIN
    INSERT INTO public.ai_session_approvals
      (session_id, member_id, revision, digest, policy_version)
    VALUES (v_session, v_user_a, 99, 'd-historical', 'v1');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION
      'EXPLOIT (over-restriction): the approvals membership trigger rejected a REAL member''s approval row because the relationship is archived. It must constrain MEMBERSHIP only -- an approval is a historical fact, and liveness belongs to the read RPCs'' Gate 1, not to this write constraint. The trigger raised: %',
      SQLERRM;
  END;
  IF NOT EXISTS (
    SELECT 1 FROM public.ai_session_approvals
    WHERE session_id = v_session AND member_id = v_user_a AND revision = 99
  ) THEN
    RAISE EXCEPTION
      'SETUP FAILED: the historical-approval row was not written, so the membership-not-liveness assertion proved nothing';
  END IF;
  DELETE FROM public.ai_session_approvals
  WHERE session_id = v_session AND member_id = v_user_a AND revision = 99;
  UPDATE public.relationships SET chat_archived_at = NULL WHERE id = v_rel;

  -- And the purge still removes every approval row, on a relationship
  -- that has since ENDED. Not a trigger assertion (see above -- the
  -- trigger cannot fire on DELETE); this is the Global Constraint that
  -- session-scoped content dies with its session, re-checked on the
  -- one table this task added a trigger to.
  UPDATE public.relationships SET status = 'ended' WHERE id = v_rel;
  PERFORM public.end_ai_session(v_user_a, v_session);
  IF EXISTS (SELECT 1 FROM public.ai_session_approvals WHERE session_id = v_session) THEN
    RAISE EXCEPTION
      'EXPLOIT: % approval row(s) survived the close of a session on an ENDED relationship -- session-scoped content must die with its session',
      (SELECT count(*) FROM public.ai_session_approvals WHERE session_id = v_session);
  END IF;
  UPDATE public.relationships SET status = 'active' WHERE id = v_rel;

  RAISE NOTICE 'purge contract 7 (routed item 4): forged cross-relationship approval rejected; membership-not-liveness held; legitimate approvals and the purge unaffected';
END $$;


-- =====================================================================
-- Contract 8: privileges, hardening and the lock order, BY QUERY.
--
-- Proven by catalog query (has_function_privilege, pg_proc.proconfig,
-- pg_get_functiondef), never by reading the migration.
-- =====================================================================
DO $$
DECLARE
  v_fn text;
  v_fns text[] := ARRAY[
    'public.purge_ai_session_content(uuid)',
    'public.purge_expired_ai_sessions(int)',
    'public.reconcile_ai_session_quota_residue()',
    'public.publish_ai_session_nearby_result(uuid, uuid)'
  ];
  v_config text[];
  v_secdef boolean;
  v_def text;
BEGIN
  FOREACH v_fn IN ARRAY v_fns LOOP
    -- service_role (the cron job and Plan C's edge function) is the one
    -- and only caller.
    IF NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION
        'EXPLOIT: service_role has NO EXECUTE on % -- the cron job and Plan C''s edge function, the intended and only callers, cannot invoke it', v_fn;
    END IF;
    -- These are SECURITY DEFINER functions that bypass RLS entirely.
    -- A grant to authenticated or anon would expose the purge and the
    -- quota sweep to any logged-in client.
    IF has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION
        'EXPLOIT: authenticated has EXECUTE on % -- any logged-in client could purge sessions or rewrite the quota ledger directly', v_fn;
    END IF;
    IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'EXPLOIT: anon has EXECUTE on %', v_fn;
    END IF;

    SELECT p.prosecdef, p.proconfig INTO v_secdef, v_config
    FROM pg_proc p WHERE p.oid = v_fn::regprocedure;
    IF NOT v_secdef THEN
      RAISE EXCEPTION 'EXPLOIT: % is not SECURITY DEFINER', v_fn;
    END IF;
    -- Global Constraint: every new SECURITY DEFINER function sets
    -- search_path. Without it, a caller-controlled search_path can
    -- shadow public.* with its own tables inside a definer context.
    IF v_config IS NULL OR NOT ('search_path=public' = ANY (v_config)) THEN
      RAISE EXCEPTION
        'EXPLOIT: % does not SET search_path = public (proconfig = %) -- a caller-controlled search_path can shadow public objects inside a SECURITY DEFINER body',
        v_fn, COALESCE(v_config::text, 'NULL');
    END IF;
  END LOOP;

  -- The trigger function too: it is SECURITY DEFINER and must be
  -- unreachable as a direct call.
  IF has_function_privilege('authenticated',
       'public.assert_ai_session_approval_membership()', 'EXECUTE')
     OR has_function_privilege('anon',
       'public.assert_ai_session_approval_membership()', 'EXECUTE') THEN
    RAISE EXCEPTION
      'EXPLOIT: a client role has EXECUTE on the approvals membership trigger function';
  END IF;

  -- ---- THE LOCK ORDER (Global Constraints / spec §6.2) --------------
  -- The reconciler acquires MULTIPLE locks, so the fixed order binds it
  -- directly: relationship advisory lock -> session row lock -> request
  -- row lock. Asserted on the live body's POSITIONS, so a reordering
  -- fails even though all three statements are still present -- a mere
  -- presence check would pass a body that locked the session row first
  -- and then the relationship, which is the deadlock shape.
  --
  -- Comments are stripped FIRST. pg_get_functiondef returns them
  -- verbatim, and this migration's own comments name all three locks in
  -- order, so an unstripped match would be satisfied by the commentary
  -- alone even if every lock were deleted (Task 10's N1, measured).
  v_def := pg_temp.strip_sql_comments(
    pg_get_functiondef('public.purge_ai_session_content(uuid)'::regprocedure));

  IF v_def !~ 'pg_advisory_xact_lock\(hashtext\(' THEN
    RAISE EXCEPTION
      'EXPLOIT: purge_ai_session_content takes NO relationship advisory lock. It is the FIRST lock in this plan''s fixed, non-negotiable order, and the every-minute purger races user-initiated End and admission on the same session.';
  END IF;
  IF v_def !~ 'FOR UPDATE' THEN
    RAISE EXCEPTION
      'EXPLOIT: purge_ai_session_content takes no row lock at all -- it reads the session state it acts on without FOR UPDATE, so a racing admission can revive a session between the scan and the purge';
  END IF;
  IF position('pg_advisory_xact_lock' in v_def)
     > position('FROM public.ai_sessions
  WHERE id = p_session_id FOR UPDATE' in v_def) THEN
    RAISE EXCEPTION
      'LOCK ORDER VIOLATED: purge_ai_session_content locks the ai_sessions ROW before the relationship advisory lock. The order is fixed at relationship -> session row -> request row and must never vary; inverting it deadlocks against end_ai_session and admit_ai_session_generation, which both take the advisory lock first. A change needing a different order is a plan defect, not a local decision.';
  END IF;
  IF position('FROM public.ai_sessions
  WHERE id = p_session_id FOR UPDATE' in v_def)
     > position('FROM public.ai_session_requests' in v_def) THEN
    RAISE EXCEPTION
      'LOCK ORDER VIOLATED: purge_ai_session_content locks ai_session_requests rows before the ai_sessions row. The order is fixed at relationship -> session row -> request row.';
  END IF;

  -- ---- THE SHARED-PRIMITIVE EQUIVALENCE ----------------------------
  -- end_ai_session keeps its own copy of the closure logic (it is
  -- deliberately NOT re-defined by this migration -- see that file's
  -- "WHY end_ai_session IS NOT WIDENED" block). This asserts the two
  -- paths cannot silently diverge: the primitive must purge all four
  -- session-scoped tables and must resolve quota the same way.
  IF v_def !~ 'DELETE FROM public\.ai_session_turns'
     OR v_def !~ 'DELETE FROM public\.ai_session_sources'
     OR v_def !~ 'DELETE FROM public\.ai_session_approvals'
     OR v_def !~ 'DELETE FROM public\.ai_session_staging' THEN
    RAISE EXCEPTION
      'EXPLOIT: purge_ai_session_content does not delete all four session-scoped content tables. Global Constraint: every session-scoped table''s primary content is deleted in the SAME transaction that closes the session. The two closure paths have diverged.';
  END IF;
  IF v_def !~ 'release_ai_assistant_quota_reservation' THEN
    RAISE EXCEPTION
      'EXPLOIT: purge_ai_session_content never releases a never-dispatched quota reservation. That is review finding F1''s exact shape (Critical): the reservation sits at outcome=''reserved'' forever, counted against the actor''s rolling window and unreachable by reconcile_ai_session_leases.';
  END IF;

  -- end_ai_session must STILL be the authorized path, and must STILL
  -- reject a NULL actor as its first statement (Global Constraint).
  -- This migration's brief instructed widening it to accept a NULL
  -- actor; that was declined, and this assertion is what keeps the
  -- decline from silently rotting.
  v_def := pg_temp.strip_sql_comments(
    pg_get_functiondef('public.end_ai_session(uuid, uuid)'::regprocedure));
  IF v_def !~ 'IF p_actor_id IS NULL THEN' THEN
    RAISE EXCEPTION
      'EXPLOIT: end_ai_session no longer has an unconditional NULL-actor guard. Global Constraint: every SECURITY DEFINER function validates its actor parameter non-NULL as its FIRST statement. The system purge path must reach purge_ai_session_content directly, never through a NULL-actor hole in a user-facing RPC.';
  END IF;
  IF v_def ~ 'v_is_system_purge' THEN
    RAISE EXCEPTION
      'EXPLOIT: end_ai_session has acquired a conditional system-purge bypass of its NULL-actor guard. That reverts to this task''s brief-suggested body, which also drops the relationship advisory lock, the quota-release loop (F1, Critical) and the revision bump (F6).';
  END IF;

  RAISE NOTICE 'purge contract 8: privileges, search_path, lock order and closure equivalence all hold by query';
END $$;


-- =====================================================================
-- Contract 9: the cron registration, BY CATALOG QUERY.
--
-- Verified against cron.job rather than by trusting that the migration
-- ran. The brief's own cadence requirement is asserted literally:
-- '* * * * *', NOT the hourly cadence Plan A's ai_assist_drafts purge
-- uses, because spec §8.2.3 sets a five-minute purge-lag target that an
-- hourly job misses by an order of magnitude.
--
-- LOCAL HARNESS LIMITATION, STATED EXPLICITLY. pg_cron is not available
-- in a stock Postgres, so scripts/local_pg_bootstrap.sql STUBS it: a
-- real cron.job table plus cron.schedule/cron.unschedule functions that
-- write to it. Registration is therefore genuinely verifiable here --
-- the job rows, their schedules, their commands and their active flag
-- are all real -- but NO SCHEDULER EXISTS, so this contract cannot
-- observe a job actually firing. What that leaves unproven locally:
-- that pg_cron parses these schedules, that the background worker is
-- running, and that the job's own role can execute the function. The
-- command strings below are asserted to be executable SQL naming
-- functions that exist with a service_role grant, which is the closest
-- local proxy; end-to-end firing is a deployment-time check.
-- =====================================================================
DO $$
DECLARE
  v_job text;
  v_expected text[][] := ARRAY[
    ARRAY['purge-ai-sessions', 'purge_expired_ai_sessions'],
    ARRAY['reconcile-ai-session-leases', 'reconcile_ai_session_leases'],
    ARRAY['reconcile-ai-session-quota-residue', 'reconcile_ai_session_quota_residue']
  ];
  v_fn text;
  v_schedule text;
  v_command text;
  v_active boolean;
  i int;
BEGIN
  -- The stub must at least exist, or every assertion here is vacuous.
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'cron' AND c.relname = 'job'
  ) THEN
    RAISE EXCEPTION
      'SETUP FAILED: cron.job does not exist, so the cron registration cannot be verified at all. In the local harness it is stubbed by scripts/local_pg_bootstrap.sql; in production pg_cron provides it.';
  END IF;

  FOR i IN 1 .. array_length(v_expected, 1) LOOP
    v_job := v_expected[i][1];
    v_fn  := v_expected[i][2];

    SELECT j.schedule, j.command, j.active
    INTO v_schedule, v_command, v_active
    FROM cron.job j WHERE j.jobname = v_job;

    IF v_schedule IS NULL THEN
      RAISE EXCEPTION
        'EXPLOIT: cron job "%" is NOT REGISTERED in cron.job. The migration''s cron.schedule call did not take effect, so nothing runs this job and the five-minute purge-lag target of spec §8.2.3 is missed by infinity, not by a margin.',
        v_job;
    END IF;

    IF v_schedule != '* * * * *' THEN
      RAISE EXCEPTION
        'EXPLOIT: cron job "%" is scheduled "%", not "* * * * *". Spec §8.2.3 requires an every-minute cadence with an operational target of deletion within five minutes of logical expiry; Plan A''s hourly ai_assist_drafts purge cadence cannot meet it.',
        v_job, v_schedule;
    END IF;

    IF NOT v_active THEN
      RAISE EXCEPTION
        'EXPLOIT: cron job "%" is registered but INACTIVE -- it is registered and will never fire, which is the most misleading of all the failure modes here',
        v_job;
    END IF;

    -- The command must actually call the function it claims to. A job
    -- registered with the right name and cadence but the wrong (or a
    -- nonexistent) function would satisfy every assertion above.
    IF v_command !~ v_fn THEN
      RAISE EXCEPTION
        'EXPLOIT: cron job "%" does not call public.% -- its command is: %',
        v_job, v_fn, v_command;
    END IF;
  END LOOP;

  -- Every scheduled function EXISTS and is EXECUTABLE BY service_role.
  -- A job whose command names a function that does not exist, or that
  -- its role cannot execute, fails silently once a minute forever --
  -- which is exactly how this codebase's 16 unregistered jobs went
  -- unnoticed (see 20260907120000's header).
  IF NOT has_function_privilege('service_role',
       'public.purge_expired_ai_sessions(int)', 'EXECUTE')
     OR NOT has_function_privilege('service_role',
       'public.reconcile_ai_session_leases()', 'EXECUTE')
     OR NOT has_function_privilege('service_role',
       'public.reconcile_ai_session_quota_residue()', 'EXECUTE') THEN
    RAISE EXCEPTION
      'EXPLOIT: a scheduled function is not executable by service_role -- the cron job would fail every minute, silently';
  END IF;

  -- purge_expired_ai_sessions is scheduled with NO arguments, so it
  -- must be callable that way: its p_limit parameter needs a DEFAULT.
  -- Without one the job errors every minute while the function itself
  -- tests green.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'purge_expired_ai_sessions'
      AND p.pronargdefaults >= 1
  ) THEN
    RAISE EXCEPTION
      'EXPLOIT: purge_expired_ai_sessions has no parameter DEFAULT, but the cron job calls it with no arguments -- the scheduled job would error every minute while every direct-call test passed';
  END IF;

  -- None of the three jobs may route through an HTTP hop. Global
  -- Constraint: no SQL transaction may span a provider HTTP call, and a
  -- job wrapped in invoke_edge_function would do exactly that.
  IF EXISTS (
    SELECT 1 FROM cron.job
    WHERE jobname IN ('purge-ai-sessions', 'reconcile-ai-session-leases',
                      'reconcile-ai-session-quota-residue')
      AND (command ~ 'invoke_edge_function' OR command ~ 'http')
  ) THEN
    RAISE EXCEPTION
      'EXPLOIT: an AI-session maintenance job invokes an edge function. Global Constraint: no SQL transaction may span a provider HTTP call; these three jobs must call Postgres functions directly.';
  END IF;

  -- ANTI-COLLISION: this migration must not have unscheduled or
  -- overwritten a job belonging to another feature. The unschedule loop
  -- names three jobs explicitly rather than truncating cron.job, and
  -- this is what proves the discipline held.
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'process-chat-safety-outbox') THEN
    RAISE EXCEPTION
      'EXPLOIT: the AI-session cron registration removed the process-chat-safety-outbox job -- the unschedule loop is truncating cron.job instead of naming its own three jobs';
  END IF;

  RAISE NOTICE 'purge contract 9: 3 cron jobs registered, every-minute, active, direct-SQL, unrelated jobs intact (NOTE: registration verified; no scheduler exists in the local harness, so firing is a deployment-time check)';
END $$;


-- =====================================================================
-- Contract 10: the Global Constraint this whole plan rests on, re-run
-- after this task's new trigger and new functions.
--
-- All 7 session tables x {authenticated, anon} x
-- {SELECT, INSERT, UPDATE, DELETE} = 56 combinations, every one denied,
-- RLS on, zero policies. Re-asserted here rather than left to Task 10's
-- file because this task adds a TRIGGER to ai_session_approvals, and
-- the reflex when a trigger blocks a write is to "just grant" its way
-- around it.
--
-- Known limitation (pre-existing, affects Task 1's and Task 10's
-- identical blocks): scripts/local_pg_grants.sql replays the REVOKE
-- migrations after every migration, so locally this cannot catch a
-- stray grant arriving INSIDE a migration. In production there is no
-- replay and it is caught. The RLS and zero-policy halves are
-- unaffected in both environments.
-- =====================================================================
DO $$
DECLARE
  v_tables text[] := ARRAY[
    'ai_sessions', 'ai_session_approvals', 'ai_session_sources',
    'ai_session_requests', 'ai_session_turns', 'ai_session_staging',
    'ai_session_publications'
  ];
  v_privs text[] := ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'];
  v_roles text[] := ARRAY['authenticated', 'anon'];
  t text; p text; r text;
  v_policy_count int;
  v_rls boolean;
  v_checked int := 0;
BEGIN
  FOREACH t IN ARRAY v_tables LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = t AND c.relkind = 'r'
    ) THEN
      RAISE EXCEPTION
        'SETUP FAILED: table public.% does not exist -- the enumeration would have passed vacuously', t;
    END IF;
    FOREACH r IN ARRAY v_roles LOOP
      FOREACH p IN ARRAY v_privs LOOP
        IF has_table_privilege(r, 'public.' || t, p) THEN
          RAISE EXCEPTION
            'EXPLOIT: role % has direct % on public.% -- this plan grants NO table-level DML to %; every access must be a SECURITY DEFINER RPC',
            r, p, t, r;
        END IF;
        v_checked := v_checked + 1;
      END LOOP;
    END LOOP;

    SELECT c.relrowsecurity INTO v_rls
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = t;
    IF NOT v_rls THEN
      RAISE EXCEPTION 'EXPLOIT: RLS is NOT enabled on public.%', t;
    END IF;

    SELECT count(*) INTO v_policy_count
    FROM pg_policies WHERE schemaname = 'public' AND tablename = t;
    IF v_policy_count != 0 THEN
      RAISE EXCEPTION
        'EXPLOIT: public.% has % RLS policies -- this plan''s tables must have ZERO; a policy plus a future grant is an open table',
        t, v_policy_count;
    END IF;
  END LOOP;

  IF v_checked != 56 THEN
    RAISE EXCEPTION
      'SETUP FAILED: the enumeration checked % (role, privilege, table) combinations, expected 56 (7 tables x 2 roles x 4 privileges) -- the loop did not run over what it claims',
      v_checked;
  END IF;

  RAISE NOTICE 'purge contract 10: % privilege combinations all denied, 7 tables RLS-on with zero policies', v_checked;
END $$;


-- =====================================================================
-- Contract 11: the supersession marker for
-- publish_ai_session_nearby_result.
--
-- This task's migration (20260953110000) supersedes Task 8's
-- 20260953080000 for this function. Re-applying Task 8's file alone,
-- last, would silently revert the consent gate and the ENTIRE suite
-- would still pass -- which is exactly the failure mode Task 10's
-- Contract 9 exists to catch for the other four superseded
-- definitions. Added here for the fifth.
--
-- The marker is ai_processing_consent_events: the superseded body never
-- mentions that table at all, so the assertion cannot be satisfied by a
-- reformat. Comments are stripped first, for the usual reason.
-- =====================================================================
DO $$
DECLARE
  v_def text;
BEGIN
  v_def := pg_temp.strip_sql_comments(pg_get_functiondef(
    'public.publish_ai_session_nearby_result(uuid, uuid)'::regprocedure));

  -- TASK 5 RE-DERIVED THIS MARKER. It used to assert the literal table
  -- name `ai_processing_consent_events` in publish's own body.
  -- 20260953180000 extracted the predicate into the shared
  -- public.ai_consent_granted_for_relationship, so publish no longer
  -- names that table -- it names the helper. The marker is just as
  -- sharp: every superseded body (20260953080000, 20260953110000,
  -- 20260953120000, 20260953170000) predates the helper and cannot
  -- contain its name, so each one still fails this leg if re-applied
  -- last. The predicate's own internals are asserted ONCE against the
  -- helper, by Contract 10 of
  -- ai_session_read_authorization_contracts.sql.
  IF v_def !~ 'IF NOT public\.ai_consent_granted_for_relationship\(v_relationship_id\) THEN' THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: the live publish_ai_session_nearby_result does not gate on public.ai_consent_granted_for_relationship, so it enforces no consent gate. That is Task 8''s superseded body (20260953080000), which committed a staged Nearby result into the permanent transcript after a partner withdrew AI-processing consent; 20260953180000 WINS (over 20260953170000, 20260953120000 and 20260953110000). Re-apply migrations in order, or add a NEW migration that sorts after the winner.';
  END IF;
  IF v_def !~ 'r\.status = ''active'' AND r\.chat_archived_at IS NULL' THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: the live publish_ai_session_nearby_result has no active-membership gate. That is Task 8''s superseded body (20260953080000); 20260953110000 WINS.';
  END IF;
  -- Anti-vacuity / broken-forward: the gates ADDED must not have
  -- replaced the author check they were layered on top of. A future
  -- "unification" that satisfied both markers above while dropping
  -- requester_id would let either partner publish the other's staged
  -- result, breaking spec §7.2's asymmetry.
  IF v_def !~ 'v_staging\.requester_id != p_actor_id' THEN
    RAISE EXCEPTION
      'SUPERSESSION BROKEN FORWARD: the live publish_ai_session_nearby_result no longer checks that the actor is the staging row''s requester. The consent and membership gates added by 20260953110000 must SUBTRACT access from the requester, never replace the author check (spec §7.2).';
  END IF;

  -- ---- GATE ORDER, STRUCTURALLY --------------------------------------
  -- Both new gates must appear BEFORE the turns INSERT they guard.
  --
  -- Asserted structurally because a behavioural assertion provably
  -- CANNOT see this, and that was measured rather than assumed. A
  -- plpgsql BEGIN ... EXCEPTION block is an implicit subtransaction, so
  -- a gate that raises AFTER the INSERT still rolls the INSERT back:
  -- from inside one transaction, a late gate and an early gate are
  -- byte-identical in their observable effects (verified -- an INSERT
  -- then a RAISE inside an exception block leaves 0 rows, and mutation
  -- M7, which moves the consent gate below the INSERT, survives every
  -- behavioural leg of Contract 6).
  --
  -- The constraint being enforced is that the gate guards the write
  -- rather than merely accompanying it. Today a late gate is saved by
  -- the rollback; it would stop being saved the moment anything
  -- non-transactional, or anything in its own committed subtransaction,
  -- landed between the INSERT and the gate. Pinning the order means
  -- that refactor fails here instead of leaking in production.
  --
  -- Comments are stripped first: pg_get_functiondef returns them
  -- verbatim, and this function's own commentary names the gates and
  -- the INSERT, so an unstripped position comparison would be measuring
  -- the prose (Task 10's finding N1).
  -- TASK 5 RE-DERIVED: the gate's position marker was its inline
  -- COALESCE; 20260953180000 moved the predicate into the shared
  -- public.ai_consent_granted_for_relationship, so the gate is located
  -- by the CALL. The COALESCE itself is asserted against the helper, by
  -- Contract 10 of ai_session_read_authorization_contracts.sql.
  IF position('ai_consent_granted_for_relationship' in v_def) = 0 THEN
    RAISE EXCEPTION
      'SETUP FAILED: the consent-gate marker public.ai_consent_granted_for_relationship is absent from the live publish_ai_session_nearby_result, so the gate-order assertion below no longer discriminates and must be re-derived';
  END IF;
  IF position('INSERT INTO public.ai_session_turns' in v_def) = 0 THEN
    RAISE EXCEPTION
      'SETUP FAILED: the turns INSERT is absent from the live publish_ai_session_nearby_result -- the gate-order assertion no longer discriminates';
  END IF;
  IF position('ai_consent_granted_for_relationship' in v_def)
     > position('INSERT INTO public.ai_session_turns' in v_def) THEN
    RAISE EXCEPTION
      'EXPLOIT: publish_ai_session_nearby_result''s CONSENT gate sits AFTER the turns INSERT it is supposed to guard. It is saved today only by plpgsql''s subtransaction rollback -- not by the gate -- so any future non-transactional side effect or committed subtransaction between the INSERT and the gate makes a post-withdrawal publish leak for real. The gate must precede the write.';
  END IF;
  IF position('r.status = ''active'' AND r.chat_archived_at IS NULL' in v_def)
     > position('INSERT INTO public.ai_session_turns' in v_def) THEN
    RAISE EXCEPTION
      'EXPLOIT: publish_ai_session_nearby_result''s MEMBERSHIP gate sits AFTER the turns INSERT it is supposed to guard -- see the consent-gate message above for why the rollback is not a substitute for ordering.';
  END IF;

  RAISE NOTICE 'purge contract 11: publish supersession intact, both new gates precede the write they guard';
END $$;

DO $$ BEGIN
  RAISE NOTICE 'session purge contracts: all held';
END $$;
