-- Authorized reads (Task 10). Spec §7.2, §11 item 5.
--
-- A private session's content is invisible to the partner through EVERY
-- surface, not just the obvious one -- and a non-member's zero-row
-- result is indistinguishable from the partner's zero-row result, so
-- neither read is an existence oracle.
--
-- FIXTURE UUIDs: the b1000000-...-00000000010a/b/c range plus
-- relationship ...-00000000000b. A sweep of every supabase/tests/*.sql
-- (including the four *.sh concurrency scripts) confirmed all four are
-- unused, and each was uuid-cast-validated before use. The brief's own
-- sample literals were MALFORMED (11 hex digits in the final group
-- where 12 are required) and would have raised `invalid input syntax
-- for type uuid` on the first run -- the padded forms here are the
-- corrected ones.
--
-- FIXTURE PHONES: the brief's sample used '+15550018001'/'+15550018002',
-- which are ALREADY CLAIMED by ai_session_end_admit_concurrent_test.sh.
-- public.users.phone is UNIQUE, so the brief's `ON CONFLICT DO NOTHING`
-- insert would have SILENTLY DROPPED -- the exact failure mode that
-- left Task 5's concurrency script non-functional from the day it was
-- committed. Moved to the genuinely free +1555002000x block.
--
-- NEGATIVE-CONTRACT DISCIPLINE (Task 9 review finding F3): these read
-- RPCs return ZERO ROWS rather than raising, so the vacuous-handler
-- trap takes a different shape here than in Task 9's file -- there is
-- no `EXCEPTION WHEN OTHERS` to weaken. The equivalent trap is a
-- contract that would pass for the WRONG REASON: asserting "0 rows"
-- against a fixture that has no rows to read in the first place. Every
-- zero-row contract below therefore FIRST proves the authorized reader
-- gets a non-zero count from that same fixture, so a 0 can only mean
-- "the gate fired", never "there was nothing there".
--
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_read_authorization_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-00000000000b';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000010a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000010b';
  v_stranger uuid := 'b1000000-0000-0000-0000-00000000010c';
  -- Contract 5d's forged-approval outsider (fix round 1, review finding
  -- F2). A FOURTH user, distinct from v_stranger, because 5b leaves
  -- v_stranger deliberately approval-free: that is exactly what makes
  -- 5b a Gate 4 probe rather than a Gate 1 probe, and giving it an
  -- approval row would destroy the distinction 5d exists to draw.
  -- Fixture sweep: ...-00000000010d is unused across every
  -- supabase/**/*.sql and every scripts/*.sh (...-00000000011a is
  -- RESERVED for Task 11 and deliberately not taken here), and
  -- +15550020004 is unused across the whole suite -- public.users.phone
  -- is UNIQUE, and a collision would make the ON CONFLICT DO NOTHING
  -- insert below silently drop. Both uuid-cast-validated.
  v_outsider uuid := 'b1000000-0000-0000-0000-00000000010d';
  v_session uuid;
  v_shared uuid;
  v_nearby uuid;
  v_shared_nearby uuid;
  v_admit record;
  v_nearby_admit record;
  v_shared_admit record;
  v_count int;
  v_partner_count int;
  v_stranger_count int;
  v_def text;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'read_a@t.test'), (v_user_b, 'read_b@t.test'),
    (v_stranger, 'read_stranger@t.test'),
    (v_outsider, 'read_outsider@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550020001', 'A'), (v_user_b, '+15550020002', 'B'),
    (v_stranger, '+15550020003', 'S'),
    (v_outsider, '+15550020004', 'O')
  ON CONFLICT DO NOTHING;

  -- SETUP GUARD (Task 9's precedent): turn a silently-dropped fixture
  -- into a legible failure instead of a mystery downstream. A phone or
  -- email collision with another test file makes the ON CONFLICT above
  -- drop the row, and every contract after it then fails for the wrong
  -- reason.
  IF (SELECT count(*) FROM public.users
      WHERE id IN (v_user_a, v_user_b, v_stranger, v_outsider)) != 4 THEN
    RAISE EXCEPTION
      'SETUP FAILED: not all four fixture users exist -- a phone/email unique collision with another test file silently dropped an ON CONFLICT DO NOTHING insert';
  END IF;

  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  IF NOT EXISTS (SELECT 1 FROM public.relationships
                 WHERE id = v_rel AND user_a = v_user_a AND user_b = v_user_b) THEN
    RAISE EXCEPTION
      'SETUP FAILED: relationship % is not the fixture pair -- UUID collision with another test file', v_rel;
  END IF;

  -- Consent from BOTH partners at the current policy version. Inserted
  -- directly rather than via record_ai_processing_consent, which
  -- derives its actor from auth.uid() (unset here) -- the same approach
  -- ai_session_end_share_contracts.sql takes.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid());

  -- ===================================================================
  -- Contract 1: a PRIVATE session's turns are readable by the creator
  -- and by NOBODY else -- not the partner, not a stranger.
  -- ===================================================================
  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp'
  );
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  PERFORM public.commit_ai_session_ideas_turn(
    v_admit.worker_token, v_admit.request_id, 'private idea', 'private reply', NULL
  );

  -- 1a: the creator reads their own private session's turns. This is
  -- the non-vacuity anchor for 1b and 1c: it proves the fixture HAS
  -- readable content, so their zeros measure the gate, not an empty
  -- table. Ordinal parity is 2n-1 / 2n for attempt n, so attempt 1
  -- yields exactly 2 rows.
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_a, v_session);
  IF v_count != 2 THEN
    RAISE EXCEPTION
      'EXPLOIT: the creator could not read their own private session''s turns, got % rows (expected 2)', v_count;
  END IF;

  -- 1b: the PARTNER -- a real, current member of the same relationship,
  -- just not this session's creator -- reads ZERO rows. Not an error,
  -- not a partial result, exactly zero.
  SELECT count(*) INTO v_partner_count
  FROM public.read_ai_session_turns(v_user_b, v_session);
  IF v_partner_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the non-creator partner read % rows from a private session -- expected 0', v_partner_count;
  END IF;

  -- 1c: a stranger -- not a member of this relationship at all -- also
  -- reads zero.
  SELECT count(*) INTO v_stranger_count
  FROM public.read_ai_session_turns(v_stranger, v_session);
  IF v_stranger_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a non-member stranger read % rows from a private session', v_stranger_count;
  END IF;

  -- 1d: NOT AN EXISTENCE ORACLE. The partner's result and the
  -- stranger's result must be byte-identical, so neither can tell from
  -- the response whether a private session exists on a relationship
  -- they are (or are not) a member of. This is spec §3.1's
  -- TARGET_UNAVAILABLE precedent applied to session reads. A future
  -- change that made one of these RAISE while the other returned empty
  -- would pass 1b and 1c individually and fail only here.
  IF v_partner_count != v_stranger_count THEN
    RAISE EXCEPTION
      'EXPLOIT: the partner''s result (% rows) and the stranger''s result (% rows) differ -- the read RPC is an existence oracle',
      v_partner_count, v_stranger_count;
  END IF;

  -- 1e: reading a session id that does not exist AT ALL must also be
  -- silent and identical -- no error distinguishing "no such session"
  -- from "not authorized".
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_turns(v_user_a, gen_random_uuid());
  IF v_count != 0 THEN
    RAISE EXCEPTION 'EXPLOIT: reading a nonexistent session returned % rows', v_count;
  END IF;

  -- 1f: a NULL actor reads nothing and does not raise.
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_turns(NULL, v_session);
  IF v_count != 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a NULL actor read % rows', v_count;
  END IF;

  -- ===================================================================
  -- Contract 2: the UNEXPIRED-ACTIVE-STATE gate. The creator who could
  -- read a moment ago reads zero once the session expires, and zero
  -- again once it closes.
  -- ===================================================================
  UPDATE public.ai_sessions SET expires_at = now() - interval '1 second'
  WHERE id = v_session;
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_a, v_session);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the creator read % rows from an EXPIRED session -- the unexpired-state gate did not fire', v_count;
  END IF;

  -- Restore the expiry and confirm the read comes back: this proves the
  -- zero above was caused by the expiry and nothing else.
  UPDATE public.ai_sessions SET expires_at = now() + interval '10 minutes'
  WHERE id = v_session;
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_a, v_session);
  IF v_count != 2 THEN
    RAISE EXCEPTION
      'EXPLOIT: restoring the expiry did not restore the read (% rows) -- Contract 2''s zero was not caused by expiry', v_count;
  END IF;

  -- A non-active state ('preparing' or 'closed') also reads zero. Set
  -- directly rather than via end_ai_session, because end purges the
  -- turns synchronously -- which would make this contract vacuous
  -- (zero because the rows are gone, not because the gate fired). The
  -- point here is that the STATE gate alone suffices even with content
  -- still present.
  UPDATE public.ai_sessions SET state = 'closed' WHERE id = v_session;
  IF NOT EXISTS (SELECT 1 FROM public.ai_session_turns WHERE session_id = v_session) THEN
    RAISE EXCEPTION
      'SETUP FAILED: Contract 2''s closed-state check needs turns still present to be non-vacuous';
  END IF;
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_a, v_session);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the creator read % rows from a CLOSED session whose turns had not yet been purged', v_count;
  END IF;
  UPDATE public.ai_sessions SET state = 'active' WHERE id = v_session;

  -- ===================================================================
  -- Contract 3: the ACTIVE-MEMBERSHIP gate (a gate the brief's own
  -- sample SQL omitted while its interface text required it). A creator
  -- whose relationship has since ended, or been chat-archived, reads
  -- zero -- content access does not outlive the relationship.
  -- ===================================================================
  UPDATE public.relationships SET status = 'ended' WHERE id = v_rel;
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_a, v_session);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the creator read % rows after the relationship ENDED -- the active-membership gate did not fire', v_count;
  END IF;
  UPDATE public.relationships SET status = 'active' WHERE id = v_rel;

  UPDATE public.relationships SET chat_archived_at = now() WHERE id = v_rel;
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_a, v_session);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the creator read % rows from an ARCHIVED relationship''s session', v_count;
  END IF;
  UPDATE public.relationships SET chat_archived_at = NULL WHERE id = v_rel;

  -- Membership restored -> the read returns, proving both zeros above
  -- were caused by the membership gate.
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_a, v_session);
  IF v_count != 2 THEN
    RAISE EXCEPTION
      'EXPLOIT: restoring the relationship did not restore the read (% rows) -- Contract 3''s zeros were not caused by membership', v_count;
  END IF;

  -- ===================================================================
  -- Contract 4: the CURRENT-CONSENT gate (also omitted from the brief's
  -- sample SQL, also required by its interface text and spec §7.2).
  -- Either partner withdrawing stops the OTHER partner's reads -- a
  -- withdrawal is effective on reads immediately, not only on new
  -- generations.
  -- ===================================================================
  -- B withdraws. A is the creator and still consents, but consent is a
  -- BOTH-partners property.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES (v_rel, v_user_b, 'v1', 'withdrawn', gen_random_uuid(), clock_timestamp());
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_a, v_session);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the creator read % rows after the PARTNER withdrew AI-processing consent -- the consent gate did not fire', v_count;
  END IF;

  -- B re-grants -> reads resume, proving the zero was the consent gate.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_a, v_session);
  IF v_count != 2 THEN
    RAISE EXCEPTION
      'EXPLOIT: re-granting consent did not restore the read (% rows) -- Contract 4''s zero was not caused by consent', v_count;
  END IF;

  -- A consent event at a DIFFERENT (stale) policy version never counts
  -- as granted. Withdrawing at the current version and granting at an
  -- old one must leave the read closed -- this is what makes a policy
  -- version bump require two FRESH grants (spec §7.2).
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_b, 'v1', 'withdrawn', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v0-stale', 'granted', gen_random_uuid(), clock_timestamp());
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_a, v_session);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a consent grant at a STALE policy version satisfied the consent gate (% rows read)', v_count;
  END IF;
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());

  -- Close this private session so the shared fixture below is not
  -- blocked by any slot limit, and so it stops interfering.
  UPDATE public.ai_sessions SET state = 'closed' WHERE id = v_session;

  -- ===================================================================
  -- Contract 5: a SHARED session is readable by an ACCEPTED participant
  -- -- meaning one holding an ai_session_approvals row at the session's
  -- CURRENT context_revision -- and not by a non-member.
  -- ===================================================================
  SELECT session_id INTO v_shared FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_shared, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_shared, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_shared, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_shared, 1, 'ideas:fp'
  );
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  PERFORM public.commit_ai_session_ideas_turn(
    v_admit.worker_token, v_admit.request_id, 'shared idea', 'shared reply', NULL
  );

  -- 5a: BOTH accepted participants read the shared session -- including
  -- the partner who is NOT the creator. This is the mirror image of
  -- Contract 1b and is what proves 1b measures visibility rather than
  -- a blanket creator-only rule.
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_a, v_shared);
  IF v_count != 2 THEN
    RAISE EXCEPTION
      'EXPLOIT: the creator could not read their own SHARED session (% rows)', v_count;
  END IF;
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_b, v_shared);
  IF v_count != 2 THEN
    RAISE EXCEPTION
      'EXPLOIT: an ACCEPTED participant could not read the shared session (% rows, expected 2) -- the shared-visibility path is broken', v_count;
  END IF;

  -- 5b: a stranger reads zero from a SHARED session too.
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_stranger, v_shared);
  IF v_count != 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a stranger read % rows from a shared session', v_count;
  END IF;

  -- 5c: approval at the WRONG revision does not grant access. Advancing
  -- the session's context_revision past B's approval must close B out,
  -- while A -- the creator, whose access on a shared session ALSO comes
  -- only from the approvals table -- is closed out identically. This is
  -- the contract that proves the revision predicate is load-bearing
  -- rather than decorative.
  UPDATE public.ai_sessions SET context_revision = context_revision + 1
  WHERE id = v_shared;
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_b, v_shared);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a participant whose approval is at a STALE context_revision read % rows from a shared session', v_count;
  END IF;
  UPDATE public.ai_sessions SET context_revision = context_revision - 1
  WHERE id = v_shared;
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_b, v_shared);
  IF v_count != 2 THEN
    RAISE EXCEPTION
      'EXPLOIT: restoring context_revision did not restore the read (% rows) -- Contract 5c''s zero was not caused by the revision predicate', v_count;
  END IF;

  -- 5d: AN APPROVAL ROW IS NOT MEMBERSHIP. A total outsider -- not a
  -- member of this relationship or any related one -- who holds an
  -- ai_session_approvals row at the session's CURRENT context_revision
  -- still reads ZERO rows from the shared session, because Gate 1's
  -- ACTOR predicate denies them before Gate 4's approvals lookup is
  -- ever consulted.
  --
  -- WHY THIS CONTRACT EXISTS (fix round 1, review finding F2,
  -- Important). Gate 1 in read_ai_session_turns is
  --
  --   AND r.status = 'active' AND r.chat_archived_at IS NULL     <- liveness
  --   AND (r.user_a = p_actor_id OR r.user_b = p_actor_id)        <- actor
  --
  -- and before this contract, the ACTOR half had ZERO coverage: the
  -- reviewer deleted it and all four contract blocks passed silently
  -- while the mutant served an outsider the full 2-row transcript. The
  -- two contracts that LOOK like they cover it each stop one step short,
  -- and the distinction is worth spelling out because it is subtle:
  --
  --   * Contract 3 mutates relationships.status and chat_archived_at
  --     only, so it exercises Gate 1's LIVENESS half. Deleting the actor
  --     predicate leaves liveness intact, so 3 passes.
  --   * Contract 5b probes v_stranger against this same shared session,
  --     but v_stranger holds NO approval row -- so 5b's zero is produced
  --     by GATE 4 (the approvals EXISTS), not Gate 1. 5b passes
  --     identically with the actor predicate removed. The contract that
  --     reads as "a non-member cannot read" is in fact asserting "a
  --     non-approver cannot read".
  --
  -- This contract is the one that separates them, by making the outsider
  -- satisfy Gate 4 and letting only Gate 1 stand in the way. It is also
  -- what makes Gate 1 INDEPENDENTLY LOAD-BEARING rather than incidentally
  -- covered by the consent gate downstream -- see the note under the
  -- restore leg below (review finding F3, Minor).
  --
  -- The forged row USED to be insertable outright, because
  -- ai_session_approvals had no FK or CHECK tying member_id to the
  -- session's relationship (member_id references users(id) only). That
  -- structural gap was carried to Task 11 as a defence-in-depth item
  -- and TASK 11 HAS NOW CLOSED IT: 20260953110000 adds the
  -- trg_ai_session_approvals_membership BEFORE INSERT trigger, which
  -- rejects exactly this row (asserted from the write side by
  -- ai_session_purge_contracts.sql Contract 7).
  --
  -- THE TRIGGER IS DISABLED FOR THIS ONE INSERT, DELIBERATELY, AND THE
  -- ASSERTIONS BELOW ARE UNCHANGED. The two defences answer different
  -- questions and both must stay proven:
  --
  --   * Task 11's trigger proves the forged row cannot be CREATED.
  --   * This contract proves the forged row cannot be USED -- that
  --     Gate 1's actor predicate in read_ai_session_turns denies it
  --     independently, on its own, without relying on the trigger.
  --
  -- Collapsing the second into the first would be a regression dressed
  -- up as cleanup: it would delete the only coverage of Gate 1's actor
  -- predicate (review finding F2) and leave the read path trusting a
  -- write-side constraint it cannot see. Defence in depth means each
  -- layer is tested with the others assumed absent, so this contract
  -- deliberately manufactures the state the trigger now prevents. The
  -- trigger is re-enabled immediately after the insert, so every
  -- subsequent write in this file -- including the legitimate
  -- approvals in the restore leg -- is still trigger-checked.
  ALTER TABLE public.ai_session_approvals DISABLE TRIGGER trg_ai_session_approvals_membership;
  INSERT INTO public.ai_session_approvals
    (session_id, member_id, revision, digest, policy_version)
  SELECT v_shared, v_outsider, s.context_revision, 'd', 'v1'
  FROM public.ai_sessions s WHERE s.id = v_shared;
  ALTER TABLE public.ai_session_approvals ENABLE TRIGGER trg_ai_session_approvals_membership;
  -- Non-vacuity on the disable itself: the forged row must actually be
  -- there. A silently-failed insert would make 5d's zero below mean
  -- "no approval row" rather than "approval row denied by Gate 1",
  -- which is 5b's assertion, not this one's.
  IF NOT EXISTS (
    SELECT 1 FROM public.ai_session_approvals
    WHERE session_id = v_shared AND member_id = v_outsider
  ) THEN
    RAISE EXCEPTION
      'SETUP FAILED: Contract 5d could not manufacture the forged approval row even with trg_ai_session_approvals_membership disabled -- Gate 1''s actor predicate would then be asserted against a row that does not exist, degenerating this contract into a copy of 5b';
  END IF;
  -- Non-vacuity: the forged row must really satisfy Gate 4, otherwise
  -- this contract degenerates into a second copy of 5b.
  IF NOT EXISTS (
    SELECT 1 FROM public.ai_session_approvals a
    JOIN public.ai_sessions s ON s.id = a.session_id
    WHERE a.session_id = v_shared AND a.member_id = v_outsider
      AND a.revision = s.context_revision
  ) THEN
    RAISE EXCEPTION
      'SETUP FAILED: Contract 5d''s forged approval row is not at the session''s current context_revision, so it would be denied by Gate 4 and this contract would duplicate 5b instead of isolating Gate 1';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = v_rel AND (r.user_a = v_outsider OR r.user_b = v_outsider)
  ) THEN
    RAISE EXCEPTION
      'SETUP FAILED: Contract 5d''s outsider is a member of the fixture relationship, so Gate 1 would pass and this contract would assert nothing';
  END IF;

  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_outsider, v_shared);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a NON-MEMBER holding an ai_session_approvals row at the session''s CURRENT context_revision read % rows of a shared session''s transcript -- the active-membership gate''s ACTOR predicate (r.user_a = p_actor_id OR r.user_b = p_actor_id) did not fire. An approval row is not membership: ai_session_approvals has no FK tying member_id to the relationship, so Gate 1 is the only check standing between a stray approval and the full transcript.', v_count;
  END IF;

  -- Restore half, matching this file's non-vacuity discipline: with the
  -- forged row gone, the LEGITIMATE participant still reads 2, proving
  -- 5d's zero came from the outsider's non-membership and not from the
  -- insert having broken the fixture.
  DELETE FROM public.ai_session_approvals
  WHERE session_id = v_shared AND member_id = v_outsider;
  SELECT count(*) INTO v_count FROM public.read_ai_session_turns(v_user_b, v_shared);
  IF v_count != 2 THEN
    RAISE EXCEPTION
      'EXPLOIT: removing the forged approval row broke the legitimate participant''s read (% rows, expected 2) -- Contract 5d''s zero was not caused by non-membership', v_count;
  END IF;

  -- A NOTE ON F3 (Minor), AND WHY IT IS *NOT* COVERED BY 5d. The review
  -- that produced 5d predicted that this contract would also kill the
  -- deletion of Gate 1's `IF v_user_a IS NULL THEN RETURN` guard. It
  -- does NOT -- measured, not assumed: with the guard deleted and 5d
  -- present, the whole file still passes.
  --
  -- The mechanism is worth recording, because the prediction is a
  -- natural one. With the guard gone, the outsider's membership lookup
  -- finds no row, so v_user_a and v_user_b stay NULL; the two consent
  -- lookups then filter on `e.user_id = NULL`, match nothing, leave
  -- v_a_granted/v_b_granted NULL, and
  -- `COALESCE(NULL,false) AND COALESCE(NULL,false)` denies ONE GATE
  -- LATER. So 5d's zero still appears -- produced by Gate 2 instead of
  -- Gate 1. 5d isolates Gate 1 from Gate 4 (which is what F2 needed);
  -- it cannot isolate Gate 1 from Gate 2, because the mutation that
  -- removes the guard also empties the inputs Gate 2 depends on.
  --
  -- That is exactly why the guard needs the STRUCTURAL assertion in
  -- Contract 8 below rather than a behavioural one: the membership gate
  -- is not independently load-bearing today, its denial being produced
  -- downstream, and if the consent rule were ever relaxed to per-actor
  -- -- the kind of change a policy revision invites -- Gate 1 would
  -- silently become dead code with nothing firing. This is the same
  -- argument Contract 8 already makes for the NULL-actor guard
  -- (M16/M17), applied to the second gate it turns out to hold for.


  -- ===================================================================
  -- Contract 6: read_ai_session_staging is AUTHOR-CHECKING -- requester
  -- only, never a shared read, even on a SHARED session whose turns
  -- both partners can read (Contract 5a). This asymmetry is the whole
  -- point of spec §7.2's "own staged Nearby is accessible only through
  -- an author-checking RPC, never a shared SELECT policy".
  -- ===================================================================
  SELECT session_id INTO v_nearby FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'nearby', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_nearby, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_nearby, 1);
  SELECT * INTO v_nearby_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_nearby, 1, 'nearby:fp'
  );
  PERFORM public.claim_ai_session_dispatch(
    v_nearby_admit.worker_token, v_nearby_admit.request_id
  );
  PERFORM public.stage_ai_session_nearby_result(
    v_nearby_admit.worker_token, v_nearby_admit.request_id,
    'a staged nearby suggestion', '[]'::jsonb
  );

  -- 6a: the requester reads their own staging row. Non-vacuity anchor
  -- for 6b and 6c.
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_user_a, v_nearby_admit.request_id);
  IF v_count != 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: the requester could not read their own staged Nearby result (% rows, expected 1)', v_count;
  END IF;

  -- 6b: the PARTNER -- a current member of the same relationship --
  -- reads zero. Staging is requester-private by construction.
  SELECT count(*) INTO v_partner_count
  FROM public.read_ai_session_staging(v_user_b, v_nearby_admit.request_id);
  IF v_partner_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the partner read % rows of the requester''s staged Nearby result -- staging must be author-checked', v_partner_count;
  END IF;

  -- 6c: a stranger reads zero, identically to the partner -- staging is
  -- not an existence oracle either.
  SELECT count(*) INTO v_stranger_count
  FROM public.read_ai_session_staging(v_stranger, v_nearby_admit.request_id);
  IF v_stranger_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a stranger read % rows of a staged Nearby result', v_stranger_count;
  END IF;
  IF v_partner_count != v_stranger_count THEN
    RAISE EXCEPTION
      'EXPLOIT: staging reads distinguish the partner (%) from a stranger (%) -- existence oracle',
      v_partner_count, v_stranger_count;
  END IF;

  -- 6d: an EXPIRED staging row is unreadable even by its own requester,
  -- independent of Task 11's backstop purger.
  UPDATE public.ai_session_staging SET expires_at = now() - interval '1 second'
  WHERE request_id = v_nearby_admit.request_id;
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_user_a, v_nearby_admit.request_id);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the requester read % rows of an EXPIRED staging row -- the expiry gate did not fire', v_count;
  END IF;
  UPDATE public.ai_session_staging SET expires_at = now() + interval '2 minutes'
  WHERE request_id = v_nearby_admit.request_id;
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_user_a, v_nearby_admit.request_id);
  IF v_count != 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: restoring expires_at did not restore the staging read (% rows) -- 6d''s zero was not caused by expiry', v_count;
  END IF;

  -- 6e: a NULL actor reads no staging.
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(NULL, v_nearby_admit.request_id);
  IF v_count != 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a NULL actor read % staging rows', v_count;
  END IF;

  -- ===================================================================
  -- Contracts 6f-6i: THE CONTENT-READ GATES ON STAGING (fix round 1,
  -- review finding F1, Important).
  --
  -- Spec §7.2: "Content reads require active membership, current
  -- consent, unexpired active state and creator (private) or accepted
  -- participant (shared). […] Own staged Nearby is accessible only
  -- through an author-checking RPC, never a shared SELECT policy."
  -- A staged Nearby reply IS content derived from the relationship's
  -- data, so the author-check clause adds the author requirement ON TOP
  -- OF the content-read requirements rather than replacing them. As
  -- shipped in 20260953100000, read_ai_session_staging enforced the
  -- author check and its own expiry and NOTHING else -- so a staged
  -- result stayed readable for up to two minutes after the partner
  -- withdrew AI-processing consent, after the relationship ended, after
  -- chat archive, and after the actor was removed from the
  -- relationship. 20260953100100 adds the membership and consent gates,
  -- reusing read_ai_session_turns' byte-identical predicate shape.
  --
  -- Each contract below follows the file's zero-row discipline: break
  -- ONE piece of state, assert 0, restore it, assert 1 again -- so a
  -- zero can only mean "that gate fired", never "the row was gone".
  --
  -- WHAT IS DELIBERATELY NOT ASSERTED HERE: a session-STATE gate.
  -- read_ai_session_turns' Gate 3 (state = 'active' AND unexpired) has
  -- no staging counterpart, and that is correct rather than an
  -- oversight -- see 20260953100100's comment. end_ai_session purges
  -- ai_session_staging synchronously in the transaction that closes the
  -- session (Global Constraint), prepare_ai_session's only other close
  -- path touches 'preparing' sessions that cannot hold staging rows, and
  -- stage_ai_session_nearby_result caps expires_at at LEAST(now() + 2
  -- minutes, session.expires_at) so 6d's own-expiry check subsumes the
  -- session's. Both broken-state variants are reachable only by direct
  -- UPDATE, i.e. already past the trust boundary.
  -- ===================================================================

  -- 6f: CONSENT. The partner withdraws AI-processing consent -> the
  -- REQUESTER can no longer read their OWN staged result. This is F1's
  -- headline scenario, and the gate that makes a withdrawal effective
  -- immediately on staged reads rather than only on new generations.
  -- clock_timestamp() (not now()) because now() is frozen for the whole
  -- transaction: with equal created_at the consent lookup's tiebreak
  -- falls to a RANDOM gen_random_uuid() id, making this contract pass
  -- or fail by coin flip. Contract 4 already uses clock_timestamp() for
  -- exactly this reason.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES (v_rel, v_user_b, 'v1', 'withdrawn', gen_random_uuid(), clock_timestamp());
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_user_a, v_nearby_admit.request_id);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the requester read % rows of their own staged Nearby result after the PARTNER withdrew AI-processing consent -- the consent gate on read_ai_session_staging did not fire. A staged reply is AI-derived content about the relationship; this plan''s premise is that consent gates content, so a post-withdrawal read is a consent violation even for the actor''s own result (review finding F1).', v_count;
  END IF;
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_user_a, v_nearby_admit.request_id);
  IF v_count != 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: re-granting consent did not restore the staging read (% rows) -- 6f''s zero was not caused by the consent gate', v_count;
  END IF;

  -- 6g: STALE POLICY VERSION. A grant at an OLD policy version never
  -- satisfies the gate, so a version bump requires two FRESH grants on
  -- the staging path exactly as it does on the turns path (Contract 4's
  -- third leg). Without this, the consent gate could be satisfied by
  -- dropping the policy_version predicate and 6f would still pass.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES
    (v_rel, v_user_b, 'v1', 'withdrawn', gen_random_uuid(), clock_timestamp()),
    (v_rel, v_user_b, 'v0-stale', 'granted', gen_random_uuid(), clock_timestamp());
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_user_a, v_nearby_admit.request_id);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a consent grant at a STALE policy version satisfied read_ai_session_staging''s consent gate (% rows read)', v_count;
  END IF;
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid(), clock_timestamp());
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_user_a, v_nearby_admit.request_id);
  IF v_count != 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: re-granting at the current version did not restore the staging read (% rows) -- 6g''s zero was not caused by the policy_version predicate', v_count;
  END IF;

  -- 6h: MEMBERSHIP LIVENESS. Ending the relationship, and separately
  -- archiving the chat, each closes the staging read. Both are
  -- user-initiated and instantaneous, and NOTHING in the schema
  -- cascades either to an in-flight session -- no trigger, RPC or cron
  -- closes a session on relationship end, and Task 11's purger is
  -- purely time-based. That is precisely why the gate has to live here.
  UPDATE public.relationships SET status = 'ended' WHERE id = v_rel;
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_user_a, v_nearby_admit.request_id);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the requester read % rows of a staged Nearby result after the relationship ENDED -- the active-membership gate on read_ai_session_staging did not fire', v_count;
  END IF;
  UPDATE public.relationships SET status = 'active' WHERE id = v_rel;
  UPDATE public.relationships SET chat_archived_at = now() WHERE id = v_rel;
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_user_a, v_nearby_admit.request_id);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the requester read % rows of a staged Nearby result after the chat was ARCHIVED -- the active-membership gate on read_ai_session_staging did not fire', v_count;
  END IF;
  UPDATE public.relationships SET chat_archived_at = NULL WHERE id = v_rel;
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_user_a, v_nearby_admit.request_id);
  IF v_count != 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: restoring the relationship did not restore the staging read (% rows) -- 6h''s zeros were not caused by the membership gate', v_count;
  END IF;

  -- 6i: MEMBERSHIP, ACTOR HALF. The requester is REMOVED from the
  -- relationship while their staged result is still unexpired. The
  -- requester must stop reading their own staged content the moment
  -- they are no longer a member -- membership, not authorship, is what
  -- the consent was given under.
  --
  -- THE REQUESTER IS *REPLACED* BY ANOTHER CONSENTING USER, NOT SET TO
  -- NULL, AND THAT DETAIL IS THE WHOLE CONTRACT. Setting user_a = NULL
  -- is the obvious way to write this, is reachable in production
  -- (relationships.user_a/user_b are ON DELETE SET NULL), and is
  -- USELESS as a test of the actor predicate: a NULL member also
  -- empties the consent lookup downstream -- `e.user_id = NULL` matches
  -- nothing, COALESCE(...,false) denies -- so the zero appears whether
  -- the actor predicate is present or not. Mutation testing proved
  -- exactly that: deleting
  -- `AND (r.user_a = p_actor_id OR r.user_b = p_actor_id)` from
  -- read_ai_session_staging's membership lookup SURVIVED the NULL form
  -- of this contract, while an ex-member read their staged content.
  --
  -- Swapping in v_outsider -- who holds a current-version consent grant
  -- on this relationship -- keeps the relationship active with TWO
  -- CONSENTING members, so Gate 2 PASSES and cannot cover. The only
  -- thing left to deny the ex-requester is the actor predicate itself.
  -- (This is the staging-side twin of Contract 5d's reasoning for the
  -- turns RPC, and of the F3 note under it.)
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES (v_rel, v_outsider, 'v1', 'granted', gen_random_uuid(), clock_timestamp());
  UPDATE public.relationships SET user_a = v_outsider WHERE id = v_rel;
  -- Non-vacuity: the consent gate must still be SATISFIED for the
  -- relationship's two current members, or this degenerates into 6f.
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = v_rel AND r.user_a IS NOT NULL AND r.user_b IS NOT NULL
      AND r.status = 'active' AND r.chat_archived_at IS NULL
  ) THEN
    RAISE EXCEPTION
      'SETUP FAILED: Contract 6i needs the relationship LIVE with two non-NULL members after the swap, so the consent gate passes and only the actor predicate can deny';
  END IF;
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_outsider, v_nearby_admit.request_id);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'SETUP FAILED: Contract 6i''s replacement member read % rows of the ex-member''s staging -- the author check is broken, which would mask what 6i measures', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_user_a, v_nearby_admit.request_id);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: a requester REMOVED from the relationship -- replaced by another member who still consents, so the consent gate PASSES -- read % rows of their own staged Nearby result. The active-membership gate''s ACTOR predicate (r.user_a = p_actor_id OR r.user_b = p_actor_id) on read_ai_session_staging did not fire. Authorship is not membership: consent was given by the relationship, and leaving it ends the read.', v_count;
  END IF;
  UPDATE public.relationships SET user_a = v_user_a WHERE id = v_rel;
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_user_a, v_nearby_admit.request_id);
  IF v_count != 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: restoring membership did not restore the staging read (% rows) -- 6i''s zero was not caused by the actor predicate', v_count;
  END IF;

  -- 6j: THE ASYMMETRY SURVIVES THE FIX. The gates added by
  -- 20260953100100 can only ever REMOVE access from the requester; they
  -- must never grant it to anyone else. Re-assert, AFTER all of the
  -- above, that the partner and a stranger still read zero and still
  -- read the SAME zero -- the property 6b/6c establish, re-checked
  -- against the new code path so a future refactor that reaches for the
  -- turns RPC's visibility/approvals branches cannot widen staging.
  SELECT count(*) INTO v_partner_count
  FROM public.read_ai_session_staging(v_user_b, v_nearby_admit.request_id);
  SELECT count(*) INTO v_stranger_count
  FROM public.read_ai_session_staging(v_stranger, v_nearby_admit.request_id);
  IF v_partner_count != 0 OR v_stranger_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: adding the content-read gates WIDENED staging -- the partner read % rows and a stranger read % rows, both must be 0. Staging is requester-private by construction (spec §7.2); the new gates must subtract access, never add a partner path.',
      v_partner_count, v_stranger_count;
  END IF;
  IF v_partner_count != v_stranger_count THEN
    RAISE EXCEPTION
      'EXPLOIT: staging reads distinguish the partner (%) from a stranger (%) after the gate change -- existence oracle',
      v_partner_count, v_stranger_count;
  END IF;

  -- ===================================================================
  -- Contract 6k: THE ASYMMETRY IN ITS STRONGEST FORM -- an actor who
  -- passes EVERY gate on read_ai_session_turns for a session still
  -- reads ZERO of the other member's staging on that same session.
  --
  -- 6b/6c prove the partner is denied on a PRIVATE session, where the
  -- partner is denied by read_ai_session_turns too -- so they do not
  -- isolate the asymmetry from the ordinary private-session denial.
  -- This contract does: a SHARED nearby session, created and approved
  -- by A, where B is the one who REQUESTS the generation. A holds a
  -- current-revision approval row, so A is fully authorized for the
  -- session's turns and reads them. A must still read zero of B's
  -- staged result.
  --
  -- This is the property that would break if a future refactor
  -- "unified" the two read RPCs by giving staging the turns RPC's
  -- visibility/approvals branch -- a plausible refactor, since fix
  -- round 1 deliberately copied that RPC's Gate 1 and Gate 2 predicates
  -- into staging. The gates copied must stay SUBTRACTIVE.
  -- ===================================================================
  -- Close Contract 5's shared session first: prepare_ai_session allows
  -- one pending-or-active SHARED session per relationship, and Contract
  -- 5's is still active. Same housekeeping the file already does for
  -- Contract 1's private session before Contract 5.
  UPDATE public.ai_sessions SET state = 'closed' WHERE id = v_shared;
  SELECT session_id INTO v_shared_nearby FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'nearby', 'shared', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_shared_nearby, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_shared_nearby, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_shared_nearby, 1);
  -- B, not the creator, requests the generation -- so B owns the
  -- staging row.
  SELECT * INTO v_shared_admit FROM public.admit_ai_session_generation(
    v_user_b, gen_random_uuid(), v_shared_nearby, 1, 'nearby:fp2'
  );
  PERFORM public.claim_ai_session_dispatch(
    v_shared_admit.worker_token, v_shared_admit.request_id
  );
  PERFORM public.stage_ai_session_nearby_result(
    v_shared_admit.worker_token, v_shared_admit.request_id,
    'B''s own staged nearby suggestion', '[]'::jsonb
  );
  IF NOT EXISTS (
    SELECT 1 FROM public.ai_session_staging
    WHERE request_id = v_shared_admit.request_id AND requester_id = v_user_b
  ) THEN
    RAISE EXCEPTION
      'SETUP FAILED: Contract 6k''s staging row is not owned by B, so the creator-vs-requester asymmetry it asserts is not set up';
  END IF;

  -- Non-vacuity anchor: B reads their own staging.
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_user_b, v_shared_admit.request_id);
  IF v_count != 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: the requester could not read their own staged result on a SHARED session (% rows, expected 1)', v_count;
  END IF;

  -- Prove A really is authorized for this session's TURNS, so 6k's zero
  -- below is the asymmetry and not an ordinary denial. A committed turn
  -- is inserted directly: the nearby flow STAGES rather than commits,
  -- and publish_ai_session_nearby_result is the requester's own RPC
  -- (Task 8's surface), which would conflate the two things being
  -- measured here.
  INSERT INTO public.ai_session_turns
    (session_id, request_id, ordinal, role, kind, payload)
  VALUES (v_shared_nearby, v_shared_admit.request_id, 1, 'attune',
          'nearby_result', '{"probe":"6k"}'::jsonb);
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_turns(v_user_a, v_shared_nearby);
  IF v_count != 1 THEN
    RAISE EXCEPTION
      'SETUP FAILED: Contract 6k''s creator cannot read the shared session''s turns (% rows, expected 1), so the asymmetry assertion below would pass for the wrong reason -- a blanket denial rather than a staging-specific one', v_count;
  END IF;

  -- THE ASSERTION: fully authorized for the turns, zero for the staging.
  SELECT count(*) INTO v_count
  FROM public.read_ai_session_staging(v_user_a, v_shared_admit.request_id);
  IF v_count != 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: the CREATOR of a shared session -- who passes every gate on read_ai_session_turns and reads that session''s transcript -- read % rows of the OTHER member''s staged Nearby result. Staging is requester-private by construction (spec §7.2: "own staged Nearby is accessible only through an author-checking RPC, never a shared SELECT policy"). The content-read gates fix round 1 copied from read_ai_session_turns must SUBTRACT access from the requester, never extend it to an approved participant.', v_count;
  END IF;

  RAISE NOTICE 'read authorization contracts: all held';
END $$;

-- =====================================================================
-- Contract 7: THE RLS-ENUMERATION CONTRACT (spec §11 item 5; this
-- plan's first Global Constraint).
--
-- "No table in this plan grants direct SELECT/INSERT/UPDATE/DELETE to
-- `authenticated`. Every legitimate access is a narrow SECURITY
-- DEFINER RPC or a security-invoker view backed by RLS."
--
-- This block is the proof. It is deliberately ENUMERATIVE rather than
-- a hand-written list of checks: it loops over every table this plan
-- creates and every one of the four DML privileges, so a future table
-- or a future stray GRANT is caught without anyone remembering to
-- extend the test. Proven by query (has_table_privilege /
-- pg_proc.proconfig / has_function_privilege), never by reading SQL.
--
-- RLS-enabled-with-zero-policies is asserted too, because the two
-- mechanisms protect against different mistakes: a grant without RLS
-- opens the table outright, while RLS with a permissive policy would
-- open it the moment someone added a grant.
--
-- KNOWN LIMITATION OF THE LOCAL HARNESS (pre-existing; affects Task 1's
-- contract test identically, and production not at all). Mutation
-- testing this contract turned up a survivor worth recording:
-- scripts/local_pg_grants.sql re-applies (\i) the two AI Sessions
-- REVOKE migrations AFTER every migration has run, to undo the blanket
-- `GRANT ... ON ALL TABLES IN SCHEMA public TO authenticated` it needs
-- in order to emulate Supabase's platform-side grants. That replay
-- therefore SCRUBS any stray grant a migration file adds to these seven
-- tables -- from ANY migration, including one sorting after the REVOKE
-- files -- before this test ever runs. So in the local harness the
-- privilege half of this contract cannot catch a stray grant that
-- arrives inside a migration; it catches one applied at any later point
-- (verified by applying exactly that grant post-setup, which fails this
-- block with its specific message). In production there is no replay,
-- so a stray grant in a migration stands and IS caught here. The RLS
-- and zero-policy halves are unaffected and catch their mutants in both
-- environments. Do not "fix" this by reordering the harness: the replay
-- is what makes every other table-grant contract in the suite honest.
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
  t text;
  p text;
  r text;
  v_policy_count int;
  v_rls boolean;
  v_checked int := 0;
BEGIN
  FOREACH t IN ARRAY v_tables LOOP
    -- The table must exist, or this whole contract would pass vacuously
    -- on a typo.
    IF NOT EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = t AND c.relkind = 'r'
    ) THEN
      RAISE EXCEPTION
        'SETUP FAILED: table public.% does not exist -- the enumeration contract would have passed vacuously', t;
    END IF;

    FOREACH r IN ARRAY v_roles LOOP
      FOREACH p IN ARRAY v_privs LOOP
        IF has_table_privilege(r, 'public.' || t, p) THEN
          RAISE EXCEPTION
            'EXPLOIT: role % has direct % on public.% -- this plan grants NO table-level DML to % ; every access must be a SECURITY DEFINER RPC',
            r, p, t, r;
        END IF;
        v_checked := v_checked + 1;
      END LOOP;
    END LOOP;

    -- RLS enabled...
    SELECT c.relrowsecurity INTO v_rls
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = t;
    IF NOT v_rls THEN
      RAISE EXCEPTION 'EXPLOIT: RLS is NOT enabled on public.%', t;
    END IF;

    -- ...with zero policies. "No grant" is the enforcement mechanism,
    -- and RLS with no policy is the belt to that braces: if a grant
    -- ever appears, a zero-policy table still denies every row.
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

  RAISE NOTICE 'RLS enumeration: % privilege combinations all denied, 7 tables RLS-on with zero policies', v_checked;
END $$;

-- =====================================================================
-- Contract 8: the read RPCs' own privileges and hardening, by query.
-- =====================================================================
-- Strip SQL comments from a function definition before any structural
-- assertion matches against it. pg_get_functiondef() returns comments
-- verbatim, so a plain substring match is satisfied by a guard that has
-- been COMMENTED OUT -- the assertion passes while the guard is gone
-- (review finding N1: measured on all four structural assertions, 4/4
-- guard deletions undetected when the text was left in a comment).
-- Stripping line comments first, then block comments, makes every
-- structural assertion in this file match only executable text.
CREATE OR REPLACE FUNCTION pg_temp.strip_sql_comments(p_def text)
RETURNS text LANGUAGE sql IMMUTABLE AS $strip$
  SELECT regexp_replace(
           regexp_replace(p_def, '--[^\n]*', '', 'g'),
           '/\*.*?\*/', '', 'gs');
$strip$;

DO $$
DECLARE
  v_fn text;
  v_fns text[] := ARRAY[
    'public.read_ai_session_turns(uuid, uuid)',
    'public.read_ai_session_staging(uuid, uuid)'
  ];
  v_config text[];
  v_secdef boolean;
  v_volatile char;
  v_def text;
BEGIN
  FOREACH v_fn IN ARRAY v_fns LOOP
    -- service_role (Plan C's edge function) is the one and only caller.
    IF NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION
        'EXPLOIT: service_role has NO EXECUTE on % -- Plan C''s edge function, the intended and only caller, cannot invoke it', v_fn;
    END IF;
    -- These RPCs take their actor as a PARAMETER and trust it. Exposed
    -- to `authenticated` through PostgREST that is a confused deputy:
    -- any logged-in user could pass a victim's id and read a private
    -- session's transcript. This is precisely Task 9's F2 (Critical)
    -- on share_ai_session_turn, and the same reasoning binds here.
    IF has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION
        'EXPLOIT: authenticated has EXECUTE on % -- it trusts p_actor_id, so any logged-in user could pass a victim''s id and read a private session''s content', v_fn;
    END IF;
    IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'EXPLOIT: anon has EXECUTE on %', v_fn;
    END IF;

    SELECT p.prosecdef, p.proconfig, p.provolatile
    INTO v_secdef, v_config, v_volatile
    FROM pg_proc p WHERE p.oid = v_fn::regprocedure;

    IF NOT v_secdef THEN
      RAISE EXCEPTION
        'EXPLOIT: % is not SECURITY DEFINER -- its tables grant nothing to any client role, so an invoker-rights function would read nothing at all', v_fn;
    END IF;
    -- Global Constraint: every new SECURITY DEFINER function sets
    -- search_path. Without it, a caller-controlled search_path can
    -- shadow public.ai_session_turns and hijack a definer-rights body.
    IF v_config IS NULL OR NOT ('search_path=public' = ANY (v_config)) THEN
      RAISE EXCEPTION
        'EXPLOIT: % is SECURITY DEFINER without `SET search_path = public` (proconfig = %) -- search-path hijacking',
        v_fn, COALESCE(v_config::text, 'NULL');
    END IF;
    -- STABLE, not VOLATILE: these are read paths and must not be able
    -- to mutate. 's' = stable, 'i' = immutable, 'v' = volatile.
    IF v_volatile = 'v' THEN
      RAISE EXCEPTION
        'EXPLOIT: % is VOLATILE -- a read RPC must be STABLE so it cannot write', v_fn;
    END IF;

    -- Global Constraint: every new SECURITY DEFINER function "validates
    -- its actor parameter is non-NULL as its first statement".
    --
    -- Asserted STRUCTURALLY, on the live body, rather than behaviourally
    -- -- and that choice is deliberate, because mutation testing proved
    -- a behavioural assertion cannot see this. Deleting the NULL check
    -- from read_ai_session_turns changes NOTHING observable: a NULL
    -- actor is already stopped one gate later, since `r.user_a =
    -- p_actor_id` is NULL (not true) for a NULL actor, so the
    -- membership lookup finds no row and the function returns empty
    -- anyway. The behavioural contract (1f) therefore SURVIVES that
    -- mutation, correctly -- the function's behaviour is genuinely
    -- unchanged. But the constraint is about the function's SHAPE, not
    -- only its behaviour: the explicit check is defence-in-depth that
    -- must survive a future refactor which reorders or replaces the
    -- gate that currently happens to cover for it. Only a structural
    -- assertion can enforce that.
    SELECT pg_temp.strip_sql_comments(pg_get_functiondef(v_fn::regprocedure)) INTO v_def;
    IF v_def !~ 'IF p_actor_id IS NULL THEN' THEN
      RAISE EXCEPTION
        'EXPLOIT: % has no explicit `IF p_actor_id IS NULL` guard. Every SECURITY DEFINER function in this plan must validate its actor parameter as its first statement (Global Constraint). A later gate may happen to cover for its absence today -- that is not the same as the guard being there.', v_fn;
    END IF;

    -- THE MEMBERSHIP GATE'S OWN GUARD (fix round 1, review finding F3,
    -- Minor). Both read RPCs resolve the session's relationship members
    -- into v_user_a/v_user_b through a membership lookup that already
    -- carries the actor predicate, then bail out if v_user_a came back
    -- NULL. Deleting that bail-out changes NOTHING observable, and the
    -- reason is the same shape as the NULL-actor guard above: the two
    -- consent lookups downstream then filter on `e.user_id = NULL`,
    -- match nothing, and COALESCE(...,false) denies one gate later.
    --
    -- Asserted structurally because a behavioural assertion provably
    -- cannot see it. This was MEASURED, not assumed: Contract 5d --
    -- which was added in this same fix round specifically to cover
    -- Gate 1's actor predicate, and which DOES kill that mutation --
    -- SURVIVES the guard's deletion, because the mutation that removes
    -- the guard also empties the inputs the covering gate reads. See
    -- the extended note at Contract 5d.
    --
    -- The constraint being enforced is independence: the membership
    -- gate must DENY ON ITS OWN, not by borrowing the consent gate's
    -- denial. Today it borrows. If the consent rule were ever relaxed
    -- to per-actor rather than both-partner, Gate 1 would become dead
    -- code and the membership denial would vanish with no contract
    -- firing. The guard's presence is the only thing a test can hold on
    -- to until that independence is real.
    IF v_def !~ 'IF v_user_a IS NULL THEN' THEN
      RAISE EXCEPTION
        'EXPLOIT: % has no explicit `IF v_user_a IS NULL` bail-out after its membership lookup. The membership gate must deny on its own rather than relying on the consent gate downstream to deny for it: with this guard gone, a non-member falls through to two consent lookups keyed on NULL, which deny only incidentally. Relax the consent rule to per-actor and that incidental denial disappears. (Review finding F3; behaviourally invisible, which is why this assertion is structural.)', v_fn;
    END IF;
  END LOOP;

  RAISE NOTICE 'read RPC privileges: service_role-only, SECURITY DEFINER, search_path pinned, STABLE';
END $$;

-- =====================================================================
-- Contract 9: MIGRATION-SUPERSESSION ORDERING (Task 9 re-review,
-- deferred note 2 -- carried into Task 10 as the next task to add a
-- migration).
--
-- THE GAP THIS CLOSES: four functions in this plan are defined TWICE,
-- in an original migration and again in a later one that wins. Nothing
-- previously enforced the ORDERING. Re-applying a superseded file alone,
-- last -- a plausible accident during a manual repair, a cherry-pick, or
-- a hand-run of one migration -- silently REVERTS the winning
-- definition, and the entire 56-file suite still passes, because every
-- other contract exercises behaviour both versions happen to share.
--
-- THE MECHANISM: assert the LIVE body (pg_get_functiondef) of each
-- superseded function carries a marker that ONLY its winning definition
-- has. This is cheap, needs no fixtures, and fails loudly on exactly
-- the accident described. See the MIGRATION PROVENANCE block in
-- 20260953090100_ai_session_end_share_fix.sql for which file wins for
-- each function; this contract is the executable form of that note.
--
-- WHY THESE MARKERS: each is the specific semantic difference the
-- supersession exists to deliver, not an incidental string. A marker
-- that merely differed in whitespace or a comment would pass on a
-- reverted body that was later reformatted; these three cannot.
-- =====================================================================
DO $$
DECLARE
  v_def text;
BEGIN
  -- ---- prepare_ai_session: Task 9's 20260953090000 WINS over Task 3's
  -- 20260953030000. Marker: Task 3's reclaim UPDATE stamped a FAKE
  -- `activated_at = now()` to satisfy Task 1's original 2-way CHECK;
  -- Task 9 loosened that CHECK and removed the fabricated timestamp, so
  -- the winning body closes expired preparing sessions WITHOUT it.
  -- Re-applying Task 3's file last would put the fake stamp back.
  v_def := pg_temp.strip_sql_comments(pg_get_functiondef(
    'public.prepare_ai_session(uuid, uuid, uuid, text, text, uuid, boolean)'::regprocedure));
  IF v_def ~ 'SET state = ''closed'', activated_at = now\(\)' THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: the live prepare_ai_session stamps a FAKE activated_at on its expired-slot reclaim. That is Task 3''s superseded body (20260953030000); Task 9''s 20260953090000 WINS and removed it. Re-apply migrations in order, or add a NEW migration that sorts after the winner.';
  END IF;
  IF v_def !~ 'SET state = ''closed''' THEN
    RAISE EXCEPTION
      'SETUP FAILED: the live prepare_ai_session has no expired-slot reclaim UPDATE at all -- this contract''s marker no longer discriminates and must be re-derived';
  END IF;

  -- ---- end_ai_session: fix round 1's 20260953090100 WINS over Task
  -- 9's 20260953090000. Marker: the F1 (Critical) fix is the call to
  -- release_ai_assistant_quota_reservation. The superseded body has NO
  -- such call -- that WAS the bug: either partner could burn the
  -- creator's entire 24h AI quota with zero provider calls.
  v_def := pg_temp.strip_sql_comments(pg_get_functiondef('public.end_ai_session(uuid, uuid)'::regprocedure));
  IF v_def !~ 'release_ai_assistant_quota_reservation' THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: the live end_ai_session never calls release_ai_assistant_quota_reservation. That is Task 9''s superseded body (20260953090000), which stranded the quota reservation (review finding F1, Critical -- partner-weaponizable quota DoS); 20260953090100 WINS. Re-apply migrations in order.';
  END IF;

  -- ---- claim_ai_session_dispatch: fix round 1's 20260953060100 WINS
  -- over Task 6's 20260953060000. Marker: the call to
  -- claim_ai_assistant_provider_start, the single write point for the
  -- write-once ai_assistant_usage.provider_started_at ledger marker.
  -- The superseded body set only the session-local bookkeeping column,
  -- so NO path ever set the real marker and a consumed reservation
  -- could still be released.
  v_def := pg_temp.strip_sql_comments(pg_get_functiondef('public.claim_ai_session_dispatch(uuid, uuid)'::regprocedure));
  IF v_def !~ 'claim_ai_assistant_provider_start' THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: the live claim_ai_session_dispatch never calls claim_ai_assistant_provider_start, so the write-once ai_assistant_usage.provider_started_at marker is never set. That is Task 6''s superseded body (20260953060000); 20260953060100 WINS. Re-apply migrations in order.';
  END IF;

  -- ---- read_ai_session_staging: fix round 1's 20260953100100 WINS
  -- over Task 10's 20260953100000. Marker: the consent gate. The
  -- superseded body gated ONLY on the author check and its own expiry,
  -- so a staged Nearby result stayed readable for up to two minutes
  -- after the partner withdrew AI-processing consent, after the
  -- relationship ended, after chat archive, and after the actor was
  -- removed from the relationship (review finding F1, Important). The
  -- winning body reads ai_processing_consent_events; the superseded one
  -- never mentions that table at all, which makes this the sharpest
  -- possible marker -- it cannot be satisfied by a reformat.
  v_def := pg_temp.strip_sql_comments(pg_get_functiondef('public.read_ai_session_staging(uuid, uuid)'::regprocedure));
  IF v_def !~ 'ai_processing_consent_events' THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: the live read_ai_session_staging never reads ai_processing_consent_events, so it enforces no consent gate. That is Task 10''s superseded body (20260953100000), which kept a staged Nearby result readable for ~2 minutes after consent withdrawal, relationship end, chat archive and actor removal (review finding F1, Important); 20260953100100 WINS. Re-apply migrations in order, or add a NEW migration that sorts after the winner.';
  END IF;
  IF v_def !~ 'r\.status = ''active'' AND r\.chat_archived_at IS NULL' THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: the live read_ai_session_staging has no active-membership gate. That is Task 10''s superseded body (20260953100000); 20260953100100 WINS (review finding F1).';
  END IF;
  -- Anti-vacuity on the asymmetry side: the winning body must STILL be
  -- author-checked. A future "unification" with read_ai_session_turns
  -- that satisfied both markers above while dropping requester_id would
  -- pass this contract's first two legs and break spec §7.2's core
  -- asymmetry, so assert the author check is still present too.
  IF v_def !~ 'requester_id = p_actor_id' THEN
    RAISE EXCEPTION
      'SUPERSESSION BROKEN FORWARD: the live read_ai_session_staging no longer checks requester_id = p_actor_id. Spec §7.2 requires own staged Nearby to be reachable ONLY through an author-checking RPC; the content-read gates 20260953100100 added must SUBTRACT access from the requester, never replace the author check.';
  END IF;

  -- ---- share_ai_session_turn: fix round 1's 20260953090100 WINS over
  -- Task 9's 20260953090000. The bodies are IDENTICAL; only the GRANT
  -- moved (authenticated -> service_role), so there is no body marker
  -- to assert. The grant itself is the marker, and
  -- ai_session_end_share_contracts.sql Contract 5b already asserts it
  -- by has_function_privilege in all three directions. Recorded here so
  -- a future reader does not mistake the omission for an oversight.
  IF has_function_privilege('authenticated',
       'public.share_ai_session_turn(uuid, uuid, int)', 'EXECUTE') THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: authenticated has EXECUTE on share_ai_session_turn. That is Task 9''s superseded GRANT (20260953090000), an actor-impersonation hole (review finding F2, Critical); 20260953090100 WINS with service_role-only.';
  END IF;

  -- ---- admit_ai_session_generation: Task 3 of the merge-blockers
  -- plan, 20260953140000, WINS over Plan B Task 5's 20260953050000
  -- (which was, until this file, the SOLE definition -- established by
  -- grep: the five other migrations naming the function mention it only
  -- in comments). Marker: the consent gate. The superseded body checked
  -- no consent at all, so with zero consent events -- or after a
  -- granted-then-withdrawn -- prepare/approve/activate/admit/claim/
  -- commit ALL succeeded and the Ideas transcript was written.
  --
  -- This marker guards the worst reversion in the plan. admit is the
  -- single choke point the whole dispatch path inherits its consent gate
  -- from: claim_ai_session_dispatch requires a request row at
  -- state='reserved' with a worker_token, and admit's INSERT is the only
  -- code that creates one. So re-applying 20260953050000 last does not
  -- degrade one RPC -- it re-opens the ENTIRE write path, and a
  -- successful claim is the authorization to transmit the couple's chat
  -- clippings to a third-party AI provider.
  --
  -- The superseded body never mentions ai_processing_consent_events,
  -- which makes this the sharpest possible marker: it cannot be
  -- satisfied by a reformat or a comment.
  v_def := pg_temp.strip_sql_comments(pg_get_functiondef(
    'public.admit_ai_session_generation(uuid, uuid, uuid, int, text)'::regprocedure));
  IF v_def !~ 'ai_processing_consent_events' THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: the live admit_ai_session_generation never reads ai_processing_consent_events, so it enforces no consent gate. That is Plan B Task 5''s superseded body (20260953050000), under which a couple''s chat clippings could be transmitted to a third-party AI provider after consent was withdrawn (Critical); 20260953140000 WINS. Re-apply migrations in order, or add a NEW migration that sorts after the winner.';
  END IF;
  IF v_def !~ 'AI processing consent is not current for this relationship' THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: the live admit_ai_session_generation does not raise ''AI processing consent is not current for this relationship''. 20260953140000 WINS over 20260953050000 and its gate must RAISE -- admit returns a row on every path, so a silent return would report success while admitting nothing.';
  END IF;
  -- Anti-vacuity / broken-forward: the gate must sit BEFORE LOCK 1.
  -- admit is the reference implementation of the documented lock order
  -- (relationship advisory -> quota advisory -> session row -> request
  -- row), so a gate that drifted below pg_advisory_xact_lock would
  -- satisfy both markers above while widening the window the
  -- relationship lock is held.
  IF position('ai_processing_consent_events' in v_def)
     > position('pg_advisory_xact_lock' in v_def) THEN
    RAISE EXCEPTION
      'SUPERSESSION BROKEN FORWARD: the consent gate in admit_ai_session_generation now sits AFTER pg_advisory_xact_lock. 20260953140000 places it between the relationship_id resolution and LOCK 1 precisely so it holds no lock and cannot perturb the documented lock order that this function is the reference for.';
  END IF;

  -- ---- discard_ai_session_nearby_staging: Task 1 FIX ROUND 1 of the
  -- merge-blockers plan, 20260953150000, WINS over Plan B Task 8's
  -- 20260953080000 (which was, until that file, the SOLE definition --
  -- established by grep: the two other migrations naming the function,
  -- 20260953110000 and Task 1's 20260953120000, mention it only in
  -- comments, the latter explicitly recording that it left this
  -- function alone). Marker: the relationship advisory lock, which the
  -- superseded body does not contain at all.
  --
  -- This marker guards the fix for Task 1 review Finding 1 (Critical).
  -- The superseded body took the ai_session_staging row FIRST (its
  -- DELETE) and the ai_session_requests row SECOND, with NO advisory
  -- lock, while publish_ai_session_nearby_result takes the advisory
  -- lock, the session row, the request row, and only ~74 lines later
  -- the staging row. Opposite orders over the same two rows, and no
  -- advisory lock on the discard side for publish's to serialize
  -- against -- so Task 1's own fix to publish closed nothing here.
  -- Measured against the FIXED publish: 14/15 deadlocks at a 1 ms gap
  -- in discard's DELETE->UPDATE window, 15/15 at 10 ms, 20/20 at
  -- 250 ms, and 1/40 with NO gap at all under ordinary load. The
  -- captured victim was the DISCARD side -- the user's own "discard
  -- this Nearby result" failing with a raw SQLSTATE 40P01.
  --
  -- Re-applying 20260953080000 last is the specific accident this
  -- catches, and it is a worse accident than most: that file defines
  -- THREE functions, so re-applying it reverts this fix AND Task 1's
  -- stage/publish lock-order fix in 20260953120000 at the same time.
  v_def := pg_temp.strip_sql_comments(pg_get_functiondef(
    'public.discard_ai_session_nearby_staging(uuid, uuid)'::regprocedure));
  IF v_def !~ 'pg_advisory_xact_lock' THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: the live discard_ai_session_nearby_staging takes NO relationship advisory lock. That is Plan B Task 8''s superseded body (20260953080000), which deadlocked against the fixed publish_ai_session_nearby_result in 14/15 trials at a 1 ms window, the victim being the user''s own discard action failing with a raw SQLSTATE 40P01 (Task 1 review Finding 1, Critical); 20260953150000 WINS. Note 20260953080000 also defines stage_ai_session_nearby_result and publish_ai_session_nearby_result, so re-applying it last reverts Task 1''s 20260953120000 too. Re-apply migrations in order, or add a NEW migration that sorts after the winner.';
  END IF;
  -- Anti-vacuity / broken-forward: the advisory lock must sit BEFORE
  -- the staging DELETE that is discard's whole purpose. A body that
  -- took the lock afterwards would satisfy the marker above while
  -- leaving the cycle wide open -- every statement present, only
  -- reordered, which is the mutation class a presence check survives.
  IF position('pg_advisory_xact_lock' in v_def)
     > position('DELETE FROM public.ai_session_staging' in v_def) THEN
    RAISE EXCEPTION
      'SUPERSESSION BROKEN FORWARD: discard_ai_session_nearby_staging''s relationship advisory lock now sits AFTER its ai_session_staging DELETE. 20260953150000 takes it FIRST, before any row, precisely so publish and discard serialize on it before either touches the staging or request rows. Taking it after the DELETE serializes nothing and restores Finding 1''s deadlock with the lock statement still present.';
  END IF;

  -- ---- reconcile_ai_session_leases: Task 4 of the merge-blockers
  -- plan, 20260953160000, WINS over Task 6's 20260953060000 AND over
  -- Task 6 fix round 1's 20260953060100 -- the only function in this
  -- plan with THREE definitions, so there are two distinct reverting
  -- accidents to catch here, not one. (Established by grep: the five
  -- other migrations naming the function mention it only in comments.)
  -- Marker: the per-row EXCEPTION handler.
  --
  -- Both superseded bodies call release_ai_assistant_quota_reservation
  -- directly in the function body, with NO handler of any kind. That
  -- RPC raises 'Reservation not found for this actor' when the
  -- ai_assistant_usage row is missing, and an uncaught RAISE aborts the
  -- WHOLE transaction -- which for this function is the whole cron run.
  -- Measured on the superseded body: one orphaned request plus one
  -- healthy request in a single run left the HEALTHY row at
  -- state='reserved', usage outcome='reserved', byte-identical to its
  -- BEFORE state. It was resolved and then rolled back.
  --
  -- This marker guards a PLATFORM-WIDE availability property, which is
  -- what makes it worth asserting structurally rather than only
  -- behaviourally. pg_cron runs this every minute and the scan
  -- predicate is unbounded with no LIMIT, so an orphan matches on every
  -- subsequent run forever: reverting either superseded file means no
  -- expired lease is EVER marked 'failed' again for ANY user, and no
  -- never-dispatched quota reservation is ever released again. And the
  -- orphan needs no operator error to appear -- Plan A's registered
  -- purge_old_ai_assistant_usage() manufactures one at 30 days, with no
  -- FK in either direction to stop it.
  v_def := pg_temp.strip_sql_comments(pg_get_functiondef(
    'public.reconcile_ai_session_leases()'::regprocedure));
  IF v_def !~ 'EXCEPTION WHEN OTHERS THEN' THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: the live reconcile_ai_session_leases has NO per-row EXCEPTION handler, so one orphaned request row aborts the entire cron run and rolls back every healthy row reconciled alongside it. That is Task 6''s superseded body (20260953060000) or its fix round 1 (20260953060100); 20260953160000 WINS. Because pg_cron runs this every minute over an unbounded scan, a single orphan -- which Plan A''s registered 30-day purge_old_ai_assistant_usage() creates on its own -- then starves lease reconciliation platform-wide forever. Re-apply migrations in order, or add a NEW migration that sorts after the winner.';
  END IF;
  -- Anti-vacuity leg 1: the handler must be INSIDE the loop. A body
  -- that wrapped the whole FOR loop in one EXCEPTION block would
  -- satisfy the marker above -- every statement present -- while
  -- restoring the exact defect: the first orphan would still roll back
  -- every healthy row in the run, just quietly, with the WARNING
  -- replacing the ERROR. That is the mutation class a presence check
  -- survives, so compare positions.
  --
  -- Bounded on BOTH sides. position() returns the FIRST match, so
  -- position('LOOP') is the FOR loop's opening LOOP (verified: 378,
  -- vs 1576 for 'END LOOP' on the winning body). Asserting only
  -- "after the opening LOOP" would pass a handler placed after
  -- END LOOP, which is the outside-the-loop mutant this leg exists to
  -- kill; asserting only "before END LOOP" would pass one placed
  -- before the loop. Both bounds are needed.
  IF position('EXCEPTION WHEN OTHERS THEN' in v_def)
       < position('LOOP' in v_def)
     OR position('EXCEPTION WHEN OTHERS THEN' in v_def)
       > position('END LOOP' in v_def) THEN
    RAISE EXCEPTION
      'SUPERSESSION BROKEN FORWARD: reconcile_ai_session_leases''s EXCEPTION handler now sits OUTSIDE its FOR loop. 20260953160000 puts a BEGIN...EXCEPTION block INSIDE the loop body precisely so a plpgsql subtransaction scopes each failure to its own iteration. A handler wrapping the whole loop still rolls back every healthy row the run had already reconciled -- the original defect, with a WARNING instead of an ERROR.';
  END IF;
  -- Anti-vacuity leg 2: the orphan case must be an EXPLICIT branch that
  -- SKIPS the release, not merely something the handler catches. If
  -- release_ai_assistant_quota_reservation were called unconditionally
  -- and its raise caught, the subtransaction would roll back the
  -- terminal-state UPDATE too, leaving the orphan matching the scan
  -- predicate forever: one WARNING per minute per orphan, and that
  -- session's admit gate blocked for good. The EXISTS guard on
  -- ai_assistant_usage is what makes the terminal state COMMIT.
  IF v_def !~ 'EXISTS \(\s*SELECT 1 FROM public\.ai_assistant_usage' THEN
    RAISE EXCEPTION
      'SUPERSESSION BROKEN FORWARD: reconcile_ai_session_leases no longer guards its release call with an EXISTS check on ai_assistant_usage. 20260953160000 handles the missing-usage case as an explicit branch that SKIPS the release, so the terminal-state UPDATE commits and the orphan leaves the scan predicate. Relying on the EXCEPTION handler to catch the raise instead rolls that UPDATE back and re-wedges the row forever.';
  END IF;
  -- Anti-vacuity leg 3: the release must still HAPPEN on the healthy
  -- path. A "fix" that dropped the release call entirely would satisfy
  -- every leg above while re-opening the F1 quota-stranding leak that
  -- 20260953090100 exists to fix.
  IF v_def !~ 'release_ai_assistant_quota_reservation' THEN
    RAISE EXCEPTION
      'SUPERSESSION BROKEN FORWARD: reconcile_ai_session_leases no longer calls release_ai_assistant_quota_reservation at all. Fault isolation must SKIP the release for an orphan, never remove it for every row -- dropping it strands the quota reservation of every never-dispatched request, which is review finding F1 (Critical) again.';
  END IF;

  RAISE NOTICE 'migration supersession ordering: 8 superseded definitions all still superseded';
END $$;
