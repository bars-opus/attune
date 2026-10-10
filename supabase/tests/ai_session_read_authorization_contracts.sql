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
  v_session uuid;
  v_shared uuid;
  v_nearby uuid;
  v_admit record;
  v_nearby_admit record;
  v_count int;
  v_partner_count int;
  v_stranger_count int;
  v_def text;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'read_a@t.test'), (v_user_b, 'read_b@t.test'),
    (v_stranger, 'read_stranger@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550020001', 'A'), (v_user_b, '+15550020002', 'B'),
    (v_stranger, '+15550020003', 'S')
  ON CONFLICT DO NOTHING;

  -- SETUP GUARD (Task 9's precedent): turn a silently-dropped fixture
  -- into a legible failure instead of a mystery downstream. A phone or
  -- email collision with another test file makes the ON CONFLICT above
  -- drop the row, and every contract after it then fails for the wrong
  -- reason.
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
    SELECT pg_get_functiondef(v_fn::regprocedure) INTO v_def;
    IF v_def !~ 'IF p_actor_id IS NULL THEN' THEN
      RAISE EXCEPTION
        'EXPLOIT: % has no explicit `IF p_actor_id IS NULL` guard. Every SECURITY DEFINER function in this plan must validate its actor parameter as its first statement (Global Constraint). A later gate may happen to cover for its absence today -- that is not the same as the guard being there.', v_fn;
    END IF;
  END LOOP;

  RAISE NOTICE 'read RPC privileges: service_role-only, SECURITY DEFINER, search_path pinned, STABLE';
END $$;

-- =====================================================================
-- Contract 9: MIGRATION-SUPERSESSION ORDERING (Task 9 re-review,
-- deferred note 2 -- carried into Task 10 as the next task to add a
-- migration).
--
-- THE GAP THIS CLOSES: three functions in this plan are defined TWICE,
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
  v_def := pg_get_functiondef(
    'public.prepare_ai_session(uuid, uuid, uuid, text, text, uuid, boolean)'::regprocedure);
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
  v_def := pg_get_functiondef('public.end_ai_session(uuid, uuid)'::regprocedure);
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
  v_def := pg_get_functiondef('public.claim_ai_session_dispatch(uuid, uuid)'::regprocedure);
  IF v_def !~ 'claim_ai_assistant_provider_start' THEN
    RAISE EXCEPTION
      'SUPERSESSION REVERTED: the live claim_ai_session_dispatch never calls claim_ai_assistant_provider_start, so the write-once ai_assistant_usage.provider_started_at marker is never set. That is Task 6''s superseded body (20260953060000); 20260953060100 WINS. Re-apply migrations in order.';
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

  RAISE NOTICE 'migration supersession ordering: 4 superseded definitions all still superseded';
END $$;
