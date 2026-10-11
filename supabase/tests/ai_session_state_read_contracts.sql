-- The POLLED session-state surface (Plan D Task 8, Gate 1).
-- Spec §4.3, §6.1 (as amended), §6.2, §7.2, §8.1. Ruling 1, Ruling 6.
--
-- public.read_ai_session_state is what makes polling `session_revision`
-- -- §6.1-as-amended's sanctioned invalidation mechanism -- actually
-- implementable. Before it, the revision reached ONLY the actor who
-- caused the bump, so the PARTNER, the one party that cannot learn of a
-- change from its own response, had nothing to read. Migration
-- 20260953200600 carries the design argument; this file is its
-- executable half.
--
-- THE TWO CONTRACTS THAT MATTER MOST, stated up front because
-- everything else here supports them:
--
--   Contract 2 -- A PARTNER CAN READ THE REVISION. Not an assertion
--   about the function's text: the partner actually calls it and gets a
--   specific number, measured against the creator's own answer and
--   against the row.
--
--   Contract 7 -- THE POLLED VALUE DOES NOT MOVE ON A SAFETY REFUSAL,
--   with a PRECONDITION proving the refusal really happened. This is
--   Ruling 6. A field that moved on a refusal when the revision did not
--   would reintroduce exactly the disclosure Ruling 6 prevents, and
--   polling would become a safety side channel rather than a
--   notification.
--
-- FIXTURE UUIDs / PHONES: the b8000000-...-00000000080a/b/c range,
-- relationship ...-00000000000b in the b8000000 namespace, and the
-- +1555008000x phone block. All swept across supabase/ and scripts/
-- (0 hits each) before use, because public.users.phone is UNIQUE and a
-- collision makes an ON CONFLICT DO NOTHING insert SILENTLY DROP --
-- the failure that left an earlier task's concurrency script dead on
-- arrival. Each is uuid-cast-validated by being declared as uuid below.
--
-- NON-VACUITY DISCIPLINE (the rule this suite earned): this RPC returns
-- ZERO ROWS rather than raising, so the trap is a contract that passes
-- for the WRONG REASON -- asserting "no answer" against a fixture that
-- never had an answer to give. EVERY zero-row contract below therefore
-- FIRST proves the authorized reader gets a real answer from that SAME
-- fixture, so a zero can only mean "the gate fired".
--
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_state_read_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b8000000-0000-0000-0000-00000000000b';
  v_user_a uuid := 'b8000000-0000-0000-0000-00000000080a';
  v_user_b uuid := 'b8000000-0000-0000-0000-00000000080b';
  v_stranger uuid := 'b8000000-0000-0000-0000-00000000080c';
  v_private uuid;
  v_shared uuid;
  v_admit record;
  v_state record;
  v_partner record;
  v_creator record;
  v_count int;
  v_partner_count int;
  v_stranger_count int;
  v_row_revision int;
  v_before int;
  v_after int;
  v_before_state text;
  v_after_state text;
  v_request_state text;
  v_terminal text;
  v_def text;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'state_a@t.test'), (v_user_b, 'state_b@t.test'),
    (v_stranger, 'state_s@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550080001', 'A'), (v_user_b, '+15550080002', 'B'),
    (v_stranger, '+15550080003', 'S')
  ON CONFLICT DO NOTHING;

  -- SETUP GUARD: turn a silently-dropped fixture into a legible failure
  -- rather than a mystery three contracts later.
  IF (SELECT count(*) FROM public.users
      WHERE id IN (v_user_a, v_user_b, v_stranger)) != 3 THEN
    RAISE EXCEPTION
      'SETUP FAILED: not all three fixture users exist -- a phone/email unique collision with another test file silently dropped an ON CONFLICT DO NOTHING insert';
  END IF;

  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  IF NOT EXISTS (SELECT 1 FROM public.relationships
                 WHERE id = v_rel AND user_a = v_user_a AND user_b = v_user_b) THEN
    RAISE EXCEPTION
      'SETUP FAILED: relationship % is not the fixture pair -- UUID collision with another test file', v_rel;
  END IF;

  -- Consent from BOTH partners at the current policy version, inserted
  -- directly because record_ai_processing_consent derives its actor
  -- from auth.uid() (unset here).
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid());

  -- ===================================================================
  -- Contract 1: THE PREPARING STATE IS READABLE. This is the single
  -- property that made shape (b) necessary rather than merely tidier,
  -- so it is asserted first.
  --
  -- read_ai_session_turns' gate 3 is `IF v_session.state != 'active'
  -- THEN RETURN`, so for a PREPARING session it reports nothing and
  -- handleRead cannot distinguish that from a stranger's nothing. A
  -- revision attached to THAT response would therefore be absent during
  -- exactly the preparing -> active wait a partner polls for. This
  -- function must answer during `preparing`, and here it does.
  -- ===================================================================
  SELECT session_id INTO v_shared FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false, NULL
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_shared, 1, 'd', 'v1');

  -- The session is still PREPARING: only one of the two partners has
  -- approved, which is precisely the `waitingForPartner` wait.
  SELECT state INTO v_before_state FROM public.ai_sessions WHERE id = v_shared;
  IF v_before_state != 'preparing' THEN
    RAISE EXCEPTION
      'SETUP FAILED: the one-approval shared session is in state "%", expected "preparing" -- Contract 1 is not testing the wait it claims to',
      v_before_state;
  END IF;

  SELECT * INTO v_state FROM public.read_ai_session_state(v_user_a, v_shared);
  IF v_state.state IS DISTINCT FROM 'preparing' THEN
    RAISE EXCEPTION
      'EXPLOIT: read_ai_session_state reported "%" for a PREPARING session (expected "preparing"). If it reports nothing, the function has inherited read_ai_session_turns'' `state != ''active''` gate -- and the preparing -> active transition a waiting partner polls for becomes unobservable, which is the whole reason this RPC exists instead of a field on `read`.',
      COALESCE(v_state.state, 'NOTHING');
  END IF;

  -- THE CONTROL that makes the line above meaningful rather than a
  -- restatement of the fixture: the CONTENT read really does refuse
  -- this same session. Without this, Contract 1 would pass against a
  -- hypothetical world where `read` had worked all along.
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_turns(v_user_a, v_shared);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'SETUP FAILED: read_ai_session_turns returned % rows for a PREPARING session, so its state gate is not firing and Contract 1 proves nothing about the difference between the two surfaces',
      v_count;
  END IF;

  -- ===================================================================
  -- Contract 2: *** A PARTNER CAN READ THE REVISION. *** GATE 1.
  --
  -- The defect this task exists to fix, measured from the partner's own
  -- side. `session_revision` reached only the actor who CAUSED a bump
  -- (generate's and publish_nearby's success bodies), and the two
  -- partner-readable surfaces -- read_ai_session_turns and
  -- read_ai_session_staging -- carry no revision at all. So the partner
  -- had NOTHING to poll.
  --
  -- Asserted as a SPECIFIC NUMBER against the row, in both actors'
  -- hands, not as "the partner got something".
  -- ===================================================================
  PERFORM public.approve_ai_session_context(v_user_b, v_shared, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_shared, 1);

  SELECT revision INTO v_row_revision FROM public.ai_sessions WHERE id = v_shared;

  SELECT * INTO v_partner FROM public.read_ai_session_state(v_user_b, v_shared);
  IF v_partner.revision IS NULL THEN
    RAISE EXCEPTION
      'GATE 1 NOT CLOSED: the PARTNER (user_b) read NOTHING from read_ai_session_state on an active shared session they approved. The partner is the party that needs to poll and cannot learn the revision any other way -- this is the exact defect Task 8 exists to fix.';
  END IF;
  IF v_partner.revision != v_row_revision THEN
    RAISE EXCEPTION
      'EXPLOIT: the partner read revision % but ai_sessions.revision is % -- a polling partner comparing a wrong number against generate''s expected_revision fence would be permanently stale or permanently retrying',
      v_partner.revision, v_row_revision;
  END IF;
  IF v_partner.state IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION
      'EXPLOIT: the partner read state "%" for an ACTIVATED session (expected "active") -- the waitingForPartner wait would never terminate',
      COALESCE(v_partner.state, 'NOTHING');
  END IF;

  -- BOTH PARTIES SEE THE SAME THING. A function that answered the
  -- creator correctly and the partner with a stale or zero value would
  -- pass the legs above if they were written against the creator only
  -- -- which is how this defect survived Plan C in the first place.
  SELECT * INTO v_creator FROM public.read_ai_session_state(v_user_a, v_shared);
  IF v_creator.revision != v_partner.revision
     OR v_creator.state IS DISTINCT FROM v_partner.state THEN
    RAISE EXCEPTION
      'EXPLOIT: creator reads (rev %, state %) but partner reads (rev %, state %) on the SAME shared session -- the two parties cannot agree on what is stale',
      v_creator.revision, v_creator.state, v_partner.revision, v_partner.state;
  END IF;

  -- ===================================================================
  -- Contract 3: THE REVISION THE PARTNER READS TRACKS A BUMP THE
  -- PARTNER DID NOT CAUSE. Contract 2 proves the partner can read a
  -- number; this proves the number is LIVE for them.
  --
  -- user_a generates and commits. The commit bumps the revision and
  -- tells user_a. Nothing tells user_b -- which is the whole problem --
  -- so user_b's POLL must now report the new value.
  -- ===================================================================
  SELECT revision INTO v_before FROM public.ai_sessions WHERE id = v_shared;
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_shared, v_before, 'ideas:fp'
  );
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  PERFORM public.commit_ai_session_ideas_turn(
    v_admit.worker_token, v_admit.request_id, 'partner q', 'partner reply', NULL
  );
  SELECT revision INTO v_after FROM public.ai_sessions WHERE id = v_shared;

  IF v_after = v_before THEN
    RAISE EXCEPTION
      'SETUP FAILED: committing a turn did not bump the revision (still %), so Contract 3 cannot show a partner observing a bump',
      v_after;
  END IF;

  SELECT * INTO v_partner FROM public.read_ai_session_state(v_user_b, v_shared);
  IF v_partner.revision != v_after THEN
    RAISE EXCEPTION
      'EXPLOIT: user_a committed a turn moving the revision % -> %, but the PARTNER''s poll still reports % -- the partner cannot observe a change they did not cause, which is exactly what the poll is for',
      v_before, v_after, v_partner.revision;
  END IF;

  -- ===================================================================
  -- Contract 4: SILENCE, AND NOT AN EXISTENCE ORACLE. A stranger, a
  -- nonexistent session and a NULL actor all read NOTHING, and the
  -- stranger's nothing is identical to a non-approver's nothing.
  --
  -- This matters MORE on a polled surface than on a one-shot read: a
  -- poll probes repeatedly and for free, so a distinguishable answer
  -- here would be a cheap, automatable existence oracle over every
  -- session id a caller cared to try.
  -- ===================================================================
  -- The non-vacuity anchor: an authorized reader gets a real answer
  -- from this same fixture (established by Contracts 2-3 above, and
  -- re-measured here so this contract stands on its own).
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_state(v_user_b, v_shared);
  IF v_count != 1 THEN
    RAISE EXCEPTION
      'SETUP FAILED: the authorized partner got % rows, so the zeros below would not measure a gate', v_count;
  END IF;

  SELECT count(*) INTO v_stranger_count
  FROM public.read_ai_session_state(v_stranger, v_shared);
  IF v_stranger_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a non-member stranger read % rows of session state', v_stranger_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.read_ai_session_state(v_user_b, gen_random_uuid());
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: reading a NONEXISTENT session returned % rows -- a poll is an existence oracle', v_count;
  END IF;

  -- The two must be IDENTICAL: "no such session" must not be
  -- distinguishable from "not authorized" (§3.1's TARGET_UNAVAILABLE
  -- precedent). A change that made one RAISE while the other returned
  -- empty passes both legs above and fails only here.
  IF v_stranger_count != v_count THEN
    RAISE EXCEPTION
      'EXPLOIT: a stranger''s result (% rows) and a nonexistent session''s result (% rows) differ -- read_ai_session_state is an existence oracle',
      v_stranger_count, v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.read_ai_session_state(NULL, v_shared);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a NULL actor read % rows (and did not raise, which is correct -- but it must read nothing)', v_count;
  END IF;

  -- ===================================================================
  -- Contract 5: THE FOUR AUTHORIZATION GATES STILL FIRE. This surface
  -- discloses no content, which is why gate 3 is loosened -- and that
  -- is exactly why the OTHER three must be shown to be intact, rather
  -- than assumed to have come along with the copied body.
  -- ===================================================================
  -- 5a: CONSENT. A withdrawal stops the poll immediately, not merely
  -- new generations.
  --
  -- `created_at` IS SET EXPLICITLY ON EVERY ROW HERE, and that is not
  -- tidiness. The consent gate reads the latest event per user with
  -- `ORDER BY e.created_at DESC, e.id DESC LIMIT 1`, `created_at`
  -- DEFAULTs to `now()`, and `now()` is FIXED FOR A WHOLE TRANSACTION --
  -- so every consent row this file inserts shares one timestamp and the
  -- tie breaks on `id`, which is a `uuid` (verified against
  -- information_schema), i.e. RANDOM. A withdrawal inserted with the
  -- default would therefore win the ordering only about half the time,
  -- and this contract would FLAKE rather than fail. Found by this
  -- contract failing on its first run with the function behaving
  -- correctly. Explicit, separated timestamps make "latest" mean
  -- insertion order.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES (v_rel, v_user_b, 'v1', 'withdrawn', gen_random_uuid(), clock_timestamp());

  -- Non-vacuity for the leg below: prove the withdrawal is actually the
  -- latest event the gate will see, so a zero cannot mean "the insert
  -- lost the ordering".
  IF (SELECT action FROM public.ai_processing_consent_events
      WHERE relationship_id = v_rel AND user_id = v_user_b
        AND policy_version = 'v1'
      ORDER BY created_at DESC, id DESC LIMIT 1) != 'withdrawn' THEN
    RAISE EXCEPTION
      'SETUP FAILED: the withdrawal is not the latest consent event for user_b, so 5a would measure an ordering accident rather than the consent gate';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.read_ai_session_state(v_user_a, v_shared);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the creator polled % rows after the PARTNER withdrew consent -- consent is a BOTH-partners gate and a withdrawal must stop the poll',
      v_count;
  END IF;
  -- Restore, and prove the restore brings the answer back: that is what
  -- shows the zero above was caused by consent and nothing else.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_state(v_user_a, v_shared);
  IF v_count != 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: restoring consent did not restore the poll (% rows) -- 5a''s zero was not caused by the consent gate', v_count;
  END IF;

  -- 5b: MEMBERSHIP. Access does not outlive the relationship.
  UPDATE public.relationships SET status = 'ended' WHERE id = v_rel;
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_state(v_user_a, v_shared);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: polled % rows on an ENDED relationship -- session state outlived the relationship', v_count;
  END IF;
  UPDATE public.relationships SET status = 'active' WHERE id = v_rel;

  -- And chat-archived, which is a separate conjunct of the same gate.
  UPDATE public.relationships SET chat_archived_at = now() WHERE id = v_rel;
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_state(v_user_a, v_shared);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: polled % rows on a CHAT-ARCHIVED relationship', v_count;
  END IF;
  UPDATE public.relationships SET chat_archived_at = NULL WHERE id = v_rel;

  -- 5c: PER-VISIBILITY AUTHORIZATION. A PRIVATE session is readable by
  -- its creator and by NOBODY else -- the partner included. The poll
  -- must not become the surface that discloses a private session's
  -- existence and liveness to the partner.
  SELECT session_id INTO v_private FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false, NULL
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_private, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_private, 1);

  SELECT count(*) INTO v_count
  FROM public.read_ai_session_state(v_user_a, v_private);
  IF v_count != 1 THEN
    RAISE EXCEPTION
      'SETUP FAILED: the creator cannot poll their own private session (% rows), so 5c''s zero below would be vacuous', v_count;
  END IF;

  SELECT count(*) INTO v_partner_count
  FROM public.read_ai_session_state(v_user_b, v_private);
  IF v_partner_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the PARTNER polled % rows of a PRIVATE session''s state. A private session is invisible to the partner through EVERY surface -- a revision they can watch tick is a disclosure that the session exists and is being used.',
      v_partner_count;
  END IF;

  -- Identical to a stranger's, so the partner cannot infer existence
  -- from the SHAPE of their refusal either.
  SELECT count(*) INTO v_stranger_count
  FROM public.read_ai_session_state(v_stranger, v_private);
  IF v_partner_count != v_stranger_count THEN
    RAISE EXCEPTION
      'EXPLOIT: on a PRIVATE session the partner reads % rows and a stranger reads % -- the difference tells the partner the session exists',
      v_partner_count, v_stranger_count;
  END IF;

  -- 5d: a SHARED session's approver must hold an approval at the
  -- CURRENT context_revision. A stale approval does not carry over.
  UPDATE public.ai_session_approvals SET revision = revision - 1
  WHERE session_id = v_shared AND member_id = v_user_b;
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_state(v_user_b, v_shared);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a partner holding an approval at a SUPERSEDED context_revision polled % rows -- re-approval is not being required', v_count;
  END IF;
  UPDATE public.ai_session_approvals SET revision = revision + 1
  WHERE session_id = v_shared AND member_id = v_user_b;

  -- ===================================================================
  -- Contract 6: EXPIRY IS ENFORCED FOR BOTH CLOCKS. Gate 3 is loosened
  -- on `state`, NOT on time -- a stale sheet must not keep polling a
  -- session whose lifetime has run out.
  --
  -- A session has TWO clocks and a single-clock check would leave one
  -- hole: preparation_deadline governs `preparing` (where expires_at is
  -- still NULL, since it is set at activation) and expires_at governs
  -- `active`. Both legs are asserted.
  -- ===================================================================
  UPDATE public.ai_sessions SET expires_at = now() - interval '1 second'
  WHERE id = v_shared;
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_state(v_user_b, v_shared);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: polled % rows on an EXPIRED active session -- the expiry leg of gate 3 did not fire', v_count;
  END IF;
  UPDATE public.ai_sessions SET expires_at = now() + interval '10 minutes'
  WHERE id = v_shared;
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_state(v_user_b, v_shared);
  IF v_count != 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: restoring expires_at did not restore the poll (% rows) -- Contract 6''s zero was not caused by expiry', v_count;
  END IF;

  -- The PREPARING clock. A timed-out preparing session has expires_at
  -- NULL, so only preparation_deadline can refuse it; a function
  -- checking expires_at alone would report this one forever.
  --
  -- 5c's private session is ended first: prepare_ai_session enforces
  -- ONE pending-or-active private session per creator ("A private
  -- session is already pending or active for this creator"), so a
  -- second prepare here would raise rather than test anything.
  PERFORM public.end_ai_session(v_user_a, v_private);
  SELECT session_id INTO v_private FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false, NULL
  );
  IF (SELECT expires_at FROM public.ai_sessions WHERE id = v_private) IS NOT NULL THEN
    RAISE EXCEPTION
      'SETUP FAILED: a freshly prepared session already has expires_at set, so the preparation_deadline leg below is not testing the hole it claims to';
  END IF;
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_state(v_user_a, v_private);
  IF v_count != 1 THEN
    RAISE EXCEPTION
      'SETUP FAILED: the creator cannot poll a live PREPARING session (% rows)', v_count;
  END IF;
  UPDATE public.ai_sessions
  SET preparation_deadline = now() - interval '1 second'
  WHERE id = v_private;
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_state(v_user_a, v_private);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: polled % rows on a PREPARING session past its preparation_deadline. expires_at is NULL until activation, so checking only expires_at leaves a timed-out preparing session pollable forever.',
      v_count;
  END IF;

  -- ===================================================================
  -- Contract 7: *** THE POLLED VALUE DOES NOT MOVE ON A SAFETY
  -- REFUSAL. *** RULING 6.
  --
  -- Ruling 6: `generate` returns two `kind: "redirect"` shapes sharing
  -- the kind AND the reason set, and NOTHING may let a caller
  -- distinguish them. Task 4 verified ai_sessions.revision is NOT
  -- bumped on a refusal -- which is what makes polling the revision
  -- safe rather than a disclosure. The edge function says so in its own
  -- words at handleGenerate's redirect branch: "bumping the revision
  -- for 'unsupported' but not 'unsafe_to_assist' discloses the detector
  -- to a partner polling session_revision -- §8.1 forbids exactly
  -- that".
  --
  -- HOW A SAFETY REFUSAL IS DRIVEN HERE, and why this is the real
  -- thing. The safety DETECTOR lives in the edge function
  -- (ai_session_safety.ts), not in SQL, so a SQL contract cannot run
  -- the corpus. What it CAN do -- and what actually matters for this
  -- surface -- is reproduce the exact DATABASE DISPOSITION a refusal
  -- leaves behind, which is fully specified and is the only thing a
  -- poller can see:
  --
  --   the request is ADMITTED, then DISPATCHED, then settled via
  --   settle_ai_session_request WITHOUT commit_ai_session_ideas_turn
  --   ever being called.
  --
  -- That is byte-for-byte the disposition of a safety refusal, because
  -- settle_ai_session_request TAKES NO REASON PARAMETER -- by
  -- construction, so that a safety refusal, a validator rejection and a
  -- provider failure write the IDENTICAL row (20260953200400). There is
  -- no "safety" variant of this call to make, which is precisely the
  -- property being relied on: if this contract can be written at all,
  -- the refusal is indistinguishable from its siblings.
  --
  -- THE PRECONDITION is asserted, not assumed: the request really
  -- reached a dispatched state and really settled terminally, so a
  -- passing contract cannot mean "nothing happened".
  -- ===================================================================
  -- A fresh shared session, so this contract's revision arithmetic
  -- starts from a known point rather than from whatever Contracts 3-6
  -- left behind. The previous one is ended first: prepare_ai_session
  -- enforces ONE pending-or-active shared session per RELATIONSHIP.
  PERFORM public.end_ai_session(v_user_a, v_shared);
  SELECT session_id INTO v_shared FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false, NULL
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_shared, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_shared, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_shared, 1);

  -- The partner's polled value BEFORE the refused attempt. Read through
  -- the RPC as the PARTNER, which is the party Ruling 6 protects: the
  -- disclosure would be to them.
  SELECT * INTO v_state FROM public.read_ai_session_state(v_user_b, v_shared);
  v_before := v_state.revision;
  v_before_state := v_state.state;
  IF v_before IS NULL THEN
    RAISE EXCEPTION
      'SETUP FAILED: the partner cannot poll before the refusal, so Contract 7 would compare two NULLs and pass vacuously';
  END IF;

  -- Drive the refused attempt as user_a: admit, dispatch, settle, NEVER
  -- commit.
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_shared, v_before, 'ideas:refused'
  );
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);

  -- PRECONDITION 1: the attempt really was dispatched. If the admit or
  -- the claim had failed, everything below would be measuring an
  -- attempt that never happened.
  SELECT state INTO v_request_state
  FROM public.ai_session_requests WHERE id = v_admit.request_id;
  IF v_request_state != 'started' THEN
    RAISE EXCEPTION
      'PRECONDITION FAILED: the request is in state "%" after claim_ai_session_dispatch, expected "started". Contract 7 must measure a REAL dispatched attempt, or its "revision unchanged" result is just "nothing was attempted".',
      v_request_state;
  END IF;

  PERFORM public.settle_ai_session_request(v_user_a, v_admit.request_id);

  -- PRECONDITION 2: the refusal really happened -- the request reached
  -- its TERMINAL failed disposition, and did so with the generic
  -- terminal code every commits-nothing path shares.
  SELECT state, terminal_code INTO v_request_state, v_terminal
  FROM public.ai_session_requests WHERE id = v_admit.request_id;
  IF v_request_state != 'failed' THEN
    RAISE EXCEPTION
      'PRECONDITION FAILED: the settled request is in state "%", expected "failed" -- the refusal did not actually conclude', v_request_state;
  END IF;
  IF v_terminal != 'REQUEST_FAILED' THEN
    RAISE EXCEPTION
      'PRECONDITION FAILED: the settled request carries terminal_code "%", expected "REQUEST_FAILED". If a safety path ever gets its OWN terminal code, the refusal stops being indistinguishable from a provider failure and this contract''s premise is void.',
      v_terminal;
  END IF;

  -- PRECONDITION 3: nothing was committed. A refusal that had somehow
  -- committed a turn would legitimately bump the revision, and the
  -- assertion below would then be testing the wrong world.
  IF EXISTS (SELECT 1 FROM public.ai_session_turns WHERE session_id = v_shared) THEN
    RAISE EXCEPTION
      'PRECONDITION FAILED: a turn exists on the refused session -- the refusal committed content, so "the revision did not move" is not the property under test';
  END IF;

  -- *** THE ASSERTION. *** Both polled fields are unchanged, read
  -- through the RPC as the partner.
  SELECT * INTO v_state FROM public.read_ai_session_state(v_user_b, v_shared);
  v_after := v_state.revision;
  v_after_state := v_state.state;

  IF v_after != v_before THEN
    RAISE EXCEPTION
      'RULING 6 VIOLATED: the partner''s polled REVISION moved % -> % across a safety refusal. A refusal must leave the revision untouched -- a revision that moves on a refusal but not on nothing lets a partner detect that a refusal occurred, which is the disclosure Ruling 6 exists to prevent (§8.1).',
      v_before, v_after;
  END IF;
  IF v_after_state IS DISTINCT FROM v_before_state THEN
    RAISE EXCEPTION
      'RULING 6 VIOLATED: the partner''s polled STATE moved "%" -> "%" across a safety refusal. Every field on this surface must be unmoved by a refusal, not merely the revision -- a state that moved while the revision did not would be the same disclosure wearing a different field name.',
      v_before_state, v_after_state;
  END IF;

  -- AND THE CONTROL that stops the two legs above from being vacuous:
  -- this same fixture's revision DOES move for a real commit. Without
  -- this, a function that returned a frozen constant -- or an RPC that
  -- had silently stopped reporting the revision at all -- would pass
  -- Contract 7 perfectly.
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_shared, v_before, 'ideas:allowed'
  );
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  PERFORM public.commit_ai_session_ideas_turn(
    v_admit.worker_token, v_admit.request_id, 'allowed q', 'allowed reply', NULL
  );
  SELECT * INTO v_state FROM public.read_ai_session_state(v_user_b, v_shared);
  IF v_state.revision = v_before THEN
    RAISE EXCEPTION
      'VACUOUS CONTRACT 7: the polled revision is still % after a COMMITTED turn, so "unchanged across a refusal" measured a value that never changes at all. The refusal legs above prove nothing.',
      v_before;
  END IF;

  -- ===================================================================
  -- Contract 8: `closed` IS REPORTED EXPLICITLY, and it is the ONLY
  -- evidence of ending this surface offers.
  --
  -- end_ai_session sets state = 'closed' and bumps the revision in one
  -- statement, commented "advance `revision` so a revision-polling
  -- client can observe the purge (F6)" -- i.e. the schema was built
  -- anticipating this poll. The client must learn ending from an
  -- EXPLICIT 'closed' and never from silence, because silence is also
  -- what a stranger, a withdrawal and an expiry produce.
  -- ===================================================================
  PERFORM public.end_ai_session(v_user_a, v_shared);
  SELECT * INTO v_state FROM public.read_ai_session_state(v_user_b, v_shared);
  IF v_state.state IS DISTINCT FROM 'closed' THEN
    RAISE EXCEPTION
      'EXPLOIT: after end_ai_session the partner''s poll reports "%" rather than "closed". If it reports NOTHING, ending is indistinguishable from a withdrawal, an expiry or a stranger''s refusal -- and the client, which must never read silence as "ended" (§7.2), can never learn the session ended at all.',
      COALESCE(v_state.state, 'NOTHING');
  END IF;

  -- 8b: THE CLOSED FALLBACK DOES NOT WIDEN THE PRIVATE CASE. Gate 4
  -- falls back to relationship membership for a CLOSED SHARED session,
  -- because §5.4's purge deletes the approvals rows the gate otherwise
  -- matches on. That fallback is inside the shared branch only, and this
  -- leg is what stops a future simplification from hoisting it: a
  -- partner must not learn that a PRIVATE session existed, in any state.
  SELECT session_id INTO v_private FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false, NULL
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_private, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_private, 1);
  PERFORM public.end_ai_session(v_user_a, v_private);

  -- The CREATOR still learns their own private session closed: the
  -- non-vacuity anchor, and a property in its own right (their sheet
  -- must terminate too).
  SELECT * INTO v_state FROM public.read_ai_session_state(v_user_a, v_private);
  IF v_state.state IS DISTINCT FROM 'closed' THEN
    RAISE EXCEPTION
      'EXPLOIT: the creator of a CLOSED PRIVATE session polls "%" rather than "closed" -- their own sheet can never terminate',
      COALESCE(v_state.state, 'NOTHING');
  END IF;

  -- The PARTNER learns nothing, exactly as for a live private session.
  SELECT count(*) INTO v_partner_count
  FROM public.read_ai_session_state(v_user_b, v_private);
  IF v_partner_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the PARTNER polled % rows of a CLOSED PRIVATE session. The closed-state fallback to relationship membership must apply to SHARED sessions only -- applied to a private one it discloses that the creator ran a private session, which is invisible to the partner through every surface.',
      v_partner_count;
  END IF;

  -- ===================================================================
  -- Contract 9: THE RETURN SHAPE IS EXACTLY TWO COLUMNS, asserted from
  -- the CATALOG rather than from the body text.
  --
  -- This is the structural half of Ruling 6 and it is the contract that
  -- catches a FUTURE author. Every omission argued in 20260953200600 is
  -- a field someone could add in one line -- and `attempt_count` and
  -- `last_admitted_at` in particular MOVE ON A REFUSAL (a refusal is
  -- ADMITTED before it is refused), so either one would hand a polling
  -- partner "something was attempted and nothing committed": a refusal
  -- with the serial numbers filed off.
  --
  -- Read from pg_get_function_result, NOT by grepping the definition:
  -- the catalog reports the DECLARED result type, so a column added to
  -- RETURNS TABLE fails here and cannot be satisfied by a comment or a
  -- reformat.
  -- ===================================================================
  SELECT pg_get_function_result(
    'public.read_ai_session_state(uuid, uuid)'::regprocedure
  ) INTO v_def;
  IF v_def != 'TABLE(revision integer, state text)' THEN
    RAISE EXCEPTION
      'UNREVIEWED DISCLOSURE: read_ai_session_state now returns "%", not TABLE(revision integer, state text). Every column here is session state leaving the server for a POLLING client, and adding one is a Ruling 6 decision that must be argued in a migration. attempt_count and last_admitted_at MOVE ON A SAFETY REFUSAL while the revision does not -- adding either discloses the safety detector to a partner (§8.1), which is the disclosure this whole surface is shaped to avoid.',
      v_def;
  END IF;

  -- ===================================================================
  -- Contract 10: PRIVILEGES AND PROPERTIES. service_role only,
  -- SECURITY DEFINER, search_path pinned, STABLE, and NO LOCKS.
  -- ===================================================================
  IF has_function_privilege('authenticated',
       'public.read_ai_session_state(uuid, uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION
      'EXPLOIT: `authenticated` can EXECUTE read_ai_session_state. The actor id is a PARAMETER, so a direct client grant lets any caller pass any user id and poll any session that user could -- the edge function''s verified JWT is the only thing that makes p_actor_id trustworthy.';
  END IF;
  IF has_function_privilege('anon',
       'public.read_ai_session_state(uuid, uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION
      'EXPLOIT: `anon` can EXECUTE read_ai_session_state';
  END IF;
  IF NOT has_function_privilege('service_role',
       'public.read_ai_session_state(uuid, uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION
      'BROKEN: service_role cannot EXECUTE read_ai_session_state -- the edge function is its only caller and the poll is dead';
  END IF;

  SELECT pg_get_functiondef('public.read_ai_session_state(uuid, uuid)'::regprocedure)
  INTO v_def;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid = 'public.read_ai_session_state(uuid, uuid)'::regprocedure
      AND p.prosecdef
      AND p.provolatile = 's'
      AND p.proconfig @> ARRAY['search_path=public']
  ) THEN
    RAISE EXCEPTION
      'BROKEN: read_ai_session_state is not SECURITY DEFINER + STABLE + search_path=public. DEFINER is what lets it reach tables with zero policies; STABLE is what keeps it out of the plan''s lock order; the pinned search_path is what stops a mutable one resolving its table references elsewhere.';
  END IF;

  -- NO LOCKS, and this is load-bearing for the reviewer's structural
  -- sweep rather than a style note. That sweep enumerates every function
  -- locking or writing ai_sessions / ai_session_requests /
  -- ai_session_staging and flags those holding TWO OR MORE of the three
  -- row-classes WITHOUT the relationship advisory lock; it must keep
  -- returning ZERO rows. This function holds ZERO row-classes, so it
  -- cannot appear in that sweep under any reading of it -- a stronger
  -- statement than "it appears and is benign". A FOR UPDATE added here
  -- would put a STABLE read into the lock order at a point no writer
  -- takes, which is how a total order becomes partial.
  IF v_def ~* 'FOR UPDATE' THEN
    RAISE EXCEPTION
      'EXPLOIT: read_ai_session_state takes a ROW LOCK. It must be a plain MVCC read: a polled read that locks serializes every poll behind every write for no correctness gain, and it enters this plan''s fixed lock order (relationship advisory -> quota advisory -> session row -> request row) at a point no writer shares.';
  END IF;
  IF v_def ~* 'pg_advisory' THEN
    RAISE EXCEPTION
      'EXPLOIT: read_ai_session_state takes an ADVISORY lock -- a read-only poll must take none, and this one would serialize against every generation on the relationship';
  END IF;

  -- It must not reference the request or staging tables AT ALL. This is
  -- the structural form of Ruling 6's omissions: a body that never names
  -- ai_session_requests cannot report a field from it, however a future
  -- author words the SELECT.
  IF v_def ~ 'ai_session_requests' THEN
    RAISE EXCEPTION
      'UNREVIEWED DISCLOSURE: read_ai_session_state references ai_session_requests. No request field may reach this polled surface: 20260953200400 deliberately made a safety refusal, a validator rejection and a provider failure write a BYTE-IDENTICAL row, and exposing that row here would turn any future divergence into a one-line safety disclosure through a surface already being polled.';
  END IF;
  IF v_def ~ 'ai_session_staging' THEN
    RAISE EXCEPTION
      'UNREVIEWED DISCLOSURE: read_ai_session_state references ai_session_staging -- staged Nearby content is requester-private and reachable only through its own author-checking RPC (§7.2)';
  END IF;

  -- The NULL-actor guard is the FIRST statement (Global Constraint),
  -- asserted by POSITION rather than presence: a guard added below the
  -- session lookup still "contains" the string while having already
  -- done work.
  --
  -- THIS STRUCTURAL ASSERTION IS THE ONLY THING THAT CATCHES THE GUARD
  -- BEING REMOVED, and that was MEASURED rather than assumed. Deleting
  -- the guard entirely and re-running Contract 4's behavioural NULL leg
  -- gives 0 rows anyway -- `r.user_a = NULL` is NULL, so the membership
  -- lookup finds nothing and the denial happens INCIDENTALLY, two gates
  -- later than it should. That is review finding F3's exact shape: the
  -- behaviour is right for the wrong reason, and it stops being right
  -- the moment any downstream gate is relaxed. So the behavioural leg
  -- in Contract 4 is NOT redundant with this one and neither replaces
  -- the other: that one proves a NULL actor reads nothing today, this
  -- one proves it is refused BY CONSTRUCTION.
  IF position('IF p_actor_id IS NULL THEN' in v_def) = 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: read_ai_session_state has no explicit `IF p_actor_id IS NULL` guard. Global Constraint: every SECURITY DEFINER function in this plan validates its actor parameter non-NULL as its FIRST statement.';
  END IF;
  IF position('IF p_actor_id IS NULL THEN' in v_def)
     > position('FROM public.ai_sessions WHERE id = p_session_id' in v_def) THEN
    RAISE EXCEPTION
      'EXPLOIT: read_ai_session_state''s NULL-actor guard sits AFTER its session lookup. "First statement" means ahead of every read, not merely ahead of the answer.';
  END IF;

  -- The explicit membership bail-out (review finding F3), the same
  -- structural assertion the sibling read RPCs carry: the membership
  -- gate must deny on its own rather than relying on the consent gate
  -- downstream to deny incidentally for it.
  IF v_def !~ 'IF v_user_a IS NULL THEN' THEN
    RAISE EXCEPTION
      'EXPLOIT: read_ai_session_state has no explicit `IF v_user_a IS NULL` bail-out after its membership lookup. Without it a non-member falls through to two consent lookups keyed on NULL, which deny only INCIDENTALLY -- relax the consent rule to per-actor and that denial disappears silently.';
  END IF;

  RAISE NOTICE 'polled session state: partner-readable, refusal-invariant, two columns, service_role-only, lockless';

  -- Leave no fixture behind: this file runs inside the shared
  -- attune_test database alongside 60 others.
  RAISE EXCEPTION 'rollback_state_read_contracts';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'rollback_state_read_contracts' THEN RAISE; END IF;
END $$;
