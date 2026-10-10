-- end_ai_session (synchronous content purge, either-partner-ends, quota
-- release) and share_ai_session_turn (adapts the existing draft/share
-- pipeline). Spec §5.4, §7.3, §8.1, §8.2.2.
--
-- Fixture UUIDs use the b1000000-...-0000000003x range, which a sweep
-- of every existing supabase/tests/*.sql confirmed is unused (the
-- brief's own suggested ...-00000000009a collides with Task 7's
-- ai_session_commit_ideas_contracts.sql). Fix round 1 added
-- ...-000000000036/37/38 for the purge and quota fixtures; those were
-- re-swept against the whole suite before use.
--
-- NEGATIVE-CONTRACT DISCIPLINE (fix round 1, review finding F3): every
-- rejection below asserts on the SPECIFIC error the guard it targets
-- raises, via `EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '<the
-- expected text>' THEN RAISE EXCEPTION 'EXPLOIT: ... wrong error: %'`.
-- The original file used a bare `IF SQLERRM LIKE 'EXPLOIT:%' THEN
-- RAISE; END IF;` which accepted ANY error as proof of the intended
-- rejection -- and four of its ten contracts duly passed with the
-- production logic deleted (an incidental NOT NULL violation, or an
-- earlier guard firing first, stood in for the guard under test). Do
-- not reintroduce that shape.
--
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_end_share_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000030';
  v_user_a uuid := 'b1000000-0000-0000-0000-000000000031';
  v_user_b uuid := 'b1000000-0000-0000-0000-000000000032';
  v_rel2 uuid := 'b1000000-0000-0000-0000-000000000036';
  v_session uuid;
  v_admit record;
  v_message public.messages;
  v_state text;
  v_activated timestamptz;
  v_rev_before int;
  v_rev_after int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'end_a@t.test'), (v_user_b, 'end_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550017001', 'A'), (v_user_b, '+15550017002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  -- A SECOND relationship between the same two users, so contracts that
  -- need a fresh session while another is still active (Contract 1b's
  -- nearby fixture) do not collide with prepare_ai_session's
  -- one-shared-session-per-relationship slot limit.
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel2, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_processing_consent_events (relationship_id, user_id, policy_version, action, idempotency_key)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid()),
    (v_rel2, v_user_a, 'v1', 'granted', gen_random_uuid()),
    (v_rel2, v_user_b, 'v1', 'granted', gen_random_uuid());

  -- ===================================================================
  -- Contract 1: shared session, EITHER partner ends, content purges
  -- synchronously in the same transaction (spec §5.4).
  -- ===================================================================
  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.approve_ai_session_context(v_user_b, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp'
  );
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  PERFORM public.commit_ai_session_ideas_turn(
    v_admit.worker_token, v_admit.request_id, 'an idea', 'a reply', NULL
  );

  SELECT revision INTO v_rev_before FROM public.ai_sessions WHERE id = v_session;

  -- The PARTNER (not the creator) ends it.
  PERFORM public.end_ai_session(v_user_b, v_session);
  IF (SELECT state FROM public.ai_sessions WHERE id = v_session) != 'closed' THEN
    RAISE EXCEPTION 'EXPLOIT: end_ai_session by the non-creator partner did not close the session';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ai_session_turns WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'EXPLOIT: turn content survived end_ai_session -- must purge synchronously';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ai_session_approvals WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'EXPLOIT: approval rows survived end_ai_session';
  END IF;

  -- The epoch advanced, fencing any in-flight worker (spec §6.2).
  IF (SELECT generation_epoch FROM public.ai_sessions WHERE id = v_session) < 1 THEN
    RAISE EXCEPTION 'EXPLOIT: end_ai_session did not advance generation_epoch to fence in-flight workers';
  END IF;

  -- Fix round 1 (F6): `revision` -- ai_sessions' content/optimistic-
  -- concurrency token, bumped by commit_ai_session_ideas_turn and
  -- publish_ai_session_nearby_result on every content change -- must
  -- also advance across the largest content change there is, the
  -- purge. Otherwise a revision-polling client cannot observe it.
  SELECT revision INTO v_rev_after FROM public.ai_sessions WHERE id = v_session;
  IF v_rev_after <= v_rev_before THEN
    RAISE EXCEPTION
      'EXPLOIT: end_ai_session purged the whole transcript without advancing revision (% -> %) -- a revision-polling client cannot observe the purge',
      v_rev_before, v_rev_after;
  END IF;

  -- No client-readable "who ended it" column exists anywhere on
  -- ai_sessions (Global Constraints / spec §5.4).
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'ai_sessions'
      AND (column_name LIKE '%ended_by%' OR column_name LIKE '%closed_by%'
           OR column_name LIKE '%ender%')
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: an attributable "who ended it" column exists on ai_sessions';
  END IF;

  -- Ending an already-closed session is a no-op, not an error.
  PERFORM public.end_ai_session(v_user_a, v_session);

  -- ===================================================================
  -- Contract 1b (fix round 1, F3b/F3c): the sources and staging purges,
  -- against a fixture that ACTUALLY CREATES ROWS IN BOTH.
  --
  -- The original Contract 1 asserted `NOT EXISTS (... ai_session_sources
  -- ...)` and the same for ai_session_staging -- but its fixture was an
  -- 'ideas' session prepared with p_target_message_id = NULL and never
  -- staged, so both tables held zero rows before the end as well as
  -- after. Both assertions were literally `0 = 0`, and deleting either
  -- DELETE statement from end_ai_session left the whole suite passing.
  -- Two of the four tables the Global Constraints require to be purged
  -- in the closing transaction were therefore unverified.
  --
  -- This fixture populates both for real:
  --   * ai_session_sources  -- prepare_ai_session INSERTs a 'target'
  --     source row when p_target_message_id names a live message in the
  --     same relationship.
  --   * ai_session_staging  -- stage_ai_session_nearby_result INSERTs
  --     one for a 'nearby' request in state 'started'.
  -- Both counts are ASSERTED NON-ZERO before the end, so this contract
  -- can never silently decay back into asserting 0 = 0.
  -- ===================================================================
  DECLARE
    v_nearby_session uuid;
    v_nearby_admit record;
    v_target_msg uuid := gen_random_uuid();
    v_sources_before int;
    v_staging_before int;
  BEGIN
    INSERT INTO public.messages (id, relationship_id, sender_id,
      client_message_id, content, source)
    VALUES (v_target_msg, v_rel2, v_user_b, gen_random_uuid(), 'where should we go?', 'native');

    SELECT session_id INTO v_nearby_session FROM public.prepare_ai_session(
      v_user_a, gen_random_uuid(), v_rel2, 'nearby', 'shared', v_target_msg, false
    );
    PERFORM public.approve_ai_session_context(v_user_a, v_nearby_session, 1, 'd', 'v1');
    PERFORM public.approve_ai_session_context(v_user_b, v_nearby_session, 1, 'd', 'v1');
    PERFORM public.activate_ai_session(v_user_a, v_nearby_session, 1);
    SELECT * INTO v_nearby_admit FROM public.admit_ai_session_generation(
      v_user_a, gen_random_uuid(), v_nearby_session, 1, 'nearby:fp'
    );
    PERFORM public.claim_ai_session_dispatch(
      v_nearby_admit.worker_token, v_nearby_admit.request_id
    );
    PERFORM public.stage_ai_session_nearby_result(
      v_nearby_admit.worker_token, v_nearby_admit.request_id,
      'three places nearby', '[{"name":"a cafe"}]'::jsonb
    );

    SELECT count(*) INTO v_sources_before
    FROM public.ai_session_sources WHERE session_id = v_nearby_session;
    SELECT count(*) INTO v_staging_before
    FROM public.ai_session_staging WHERE session_id = v_nearby_session;

    -- Guard the guard: if the fixture stops creating these rows, this
    -- contract must fail loudly rather than quietly assert 0 = 0 again.
    IF v_sources_before = 0 THEN
      RAISE EXCEPTION
        'EXPLOIT (test defect): the purge fixture created no ai_session_sources row, so the sources purge assertion below would be vacuous';
    END IF;
    IF v_staging_before = 0 THEN
      RAISE EXCEPTION
        'EXPLOIT (test defect): the purge fixture created no ai_session_staging row, so the staging purge assertion below would be vacuous';
    END IF;

    PERFORM public.end_ai_session(v_user_b, v_nearby_session);

    IF EXISTS (SELECT 1 FROM public.ai_session_sources WHERE session_id = v_nearby_session) THEN
      RAISE EXCEPTION
        'EXPLOIT: % source row(s) survived end_ai_session -- ai_session_sources must be purged in the closing transaction',
        (SELECT count(*) FROM public.ai_session_sources WHERE session_id = v_nearby_session);
    END IF;
    IF EXISTS (SELECT 1 FROM public.ai_session_staging WHERE session_id = v_nearby_session) THEN
      RAISE EXCEPTION
        'EXPLOIT: % staging row(s) survived end_ai_session -- ai_session_staging must be purged in the closing transaction',
        (SELECT count(*) FROM public.ai_session_staging WHERE session_id = v_nearby_session);
    END IF;
  END;

  -- ===================================================================
  -- Contract 1c (fix round 1, F1 -- Critical): end_ai_session must
  -- RELEASE the global quota reservation of every request it cancels
  -- that was never dispatched, and must LEAVE CHARGED every request
  -- whose provider call had already started.
  --
  -- Before this fix, end_ai_session moved an outstanding request to
  -- state='cancelled' without touching ai_assistant_usage. Because
  -- reserve_ai_assistant_quota's rolling window excludes only
  -- outcome IN ('rejected','cancelled'), a row left at
  -- outcome='reserved' counted against the actor's 20/24h limit
  -- forever; and because reconcile_ai_session_leases scans only
  -- `state IN ('reserved','started')`, a 'cancelled' request was
  -- invisible to the one path that would have released it. Either
  -- partner could therefore burn the CREATOR's entire 24h AI quota with
  -- zero provider calls.
  -- ===================================================================
  DECLARE
    v_q_rel uuid := 'b1000000-0000-0000-0000-000000000037';
    v_q_session uuid;
    v_q_admit record;
    v_usage_outcome text;
    v_usage_marker timestamptz;
    v_counted int;
  BEGIN
    INSERT INTO public.relationships (id, user_a, user_b, status)
    VALUES (v_q_rel, v_user_a, v_user_b, 'active') ON CONFLICT DO NOTHING;
    INSERT INTO public.ai_processing_consent_events (relationship_id, user_id, policy_version, action, idempotency_key)
    VALUES (v_q_rel, v_user_a, 'v1', 'granted', gen_random_uuid()),
           (v_q_rel, v_user_b, 'v1', 'granted', gen_random_uuid());

    -- Case 1: 'reserved' -- admitted but NEVER dispatched. No provider
    -- call was made, so the reservation must be released.
    SELECT session_id INTO v_q_session FROM public.prepare_ai_session(
      v_user_a, gen_random_uuid(), v_q_rel, 'ideas', 'shared', NULL, false
    );
    PERFORM public.approve_ai_session_context(v_user_a, v_q_session, 1, 'd', 'v1');
    PERFORM public.approve_ai_session_context(v_user_b, v_q_session, 1, 'd', 'v1');
    PERFORM public.activate_ai_session(v_user_a, v_q_session, 1);
    SELECT * INTO v_q_admit FROM public.admit_ai_session_generation(
      v_user_a, gen_random_uuid(), v_q_session, 1, 'ideas:quota-reserved'
    );
    IF v_q_admit.request_id IS NULL THEN
      RAISE EXCEPTION 'EXPLOIT (test defect): the quota fixture failed to admit (outcome=%)', v_q_admit.outcome;
    END IF;

    -- Precondition: the reservation exists, unconsumed. If this ever
    -- stops holding, the release assertion below would be vacuous.
    SELECT outcome, provider_started_at INTO v_usage_outcome, v_usage_marker
    FROM public.ai_assistant_usage
    WHERE request_id = v_q_admit.request_id AND user_id = v_user_a;
    IF v_usage_outcome IS DISTINCT FROM 'reserved' OR v_usage_marker IS NOT NULL THEN
      RAISE EXCEPTION
        'EXPLOIT (test defect): expected an unconsumed reservation before the end (outcome=%, provider_started_at=%)',
        v_usage_outcome, v_usage_marker;
    END IF;

    -- The PARTNER ends it -- the weaponizable direction: the ender is
    -- not the actor whose quota is charged.
    PERFORM public.end_ai_session(v_user_b, v_q_session);

    SELECT outcome, provider_started_at INTO v_usage_outcome, v_usage_marker
    FROM public.ai_assistant_usage
    WHERE request_id = v_q_admit.request_id AND user_id = v_user_a;
    IF v_usage_outcome IS DISTINCT FROM 'cancelled' THEN
      RAISE EXCEPTION
        'EXPLOIT: end_ai_session stranded a never-dispatched quota reservation at outcome=% -- it counts against the creator''s 24h limit forever and no reconciler path can ever release it',
        v_usage_outcome;
    END IF;

    -- And prove the consequence that makes it exploitable, not just the
    -- column value: the row must no longer be counted by
    -- reserve_ai_assistant_quota's own rolling-window predicate.
    SELECT count(*) INTO v_counted FROM public.ai_assistant_usage
    WHERE user_id = v_user_a AND request_id = v_q_admit.request_id
      AND (provider_started_at IS NOT NULL OR outcome NOT IN ('rejected', 'cancelled'));
    IF v_counted != 0 THEN
      RAISE EXCEPTION
        'EXPLOIT: the cancelled session''s reservation is still counted against the actor''s rolling quota window';
    END IF;

    -- Case 2: 'started' -- a provider call WAS claimed. This
    -- reservation has legitimately consumed quota (the write-once
    -- ai_assistant_usage.provider_started_at marker is set) and must
    -- stay charged. Releasing it would be a quota-evasion hole in the
    -- opposite direction, and release_ai_assistant_quota_reservation
    -- would RAISE on it.
    SELECT session_id INTO v_q_session FROM public.prepare_ai_session(
      v_user_a, gen_random_uuid(), v_q_rel, 'ideas', 'shared', NULL, false
    );
    PERFORM public.approve_ai_session_context(v_user_a, v_q_session, 1, 'd', 'v1');
    PERFORM public.approve_ai_session_context(v_user_b, v_q_session, 1, 'd', 'v1');
    PERFORM public.activate_ai_session(v_user_a, v_q_session, 1);
    SELECT * INTO v_q_admit FROM public.admit_ai_session_generation(
      v_user_a, gen_random_uuid(), v_q_session, 1, 'ideas:quota-started'
    );
    IF v_q_admit.request_id IS NULL THEN
      RAISE EXCEPTION 'EXPLOIT (test defect): the started-case fixture failed to admit (outcome=%)', v_q_admit.outcome;
    END IF;
    PERFORM public.claim_ai_session_dispatch(v_q_admit.worker_token, v_q_admit.request_id);

    SELECT provider_started_at INTO v_usage_marker FROM public.ai_assistant_usage
    WHERE request_id = v_q_admit.request_id AND user_id = v_user_a;
    IF v_usage_marker IS NULL THEN
      RAISE EXCEPTION
        'EXPLOIT (test defect): the dispatch claim did not set the provider-start marker, so the "stays charged" assertion below would be vacuous';
    END IF;

    PERFORM public.end_ai_session(v_user_b, v_q_session);

    SELECT outcome INTO v_usage_outcome FROM public.ai_assistant_usage
    WHERE request_id = v_q_admit.request_id AND user_id = v_user_a;
    IF v_usage_outcome NOT IN ('reserved', 'succeeded', 'provider_failed') THEN
      RAISE EXCEPTION
        'EXPLOIT: end_ai_session refunded the quota of a request whose provider call had already started (outcome=%) -- a started reservation must stay charged',
        v_usage_outcome;
    END IF;
    SELECT count(*) INTO v_counted FROM public.ai_assistant_usage
    WHERE user_id = v_user_a AND request_id = v_q_admit.request_id
      AND (provider_started_at IS NOT NULL OR outcome NOT IN ('rejected', 'cancelled'));
    IF v_counted != 1 THEN
      RAISE EXCEPTION
        'EXPLOIT: a started request''s reservation stopped counting against the rolling quota window after end_ai_session -- quota evasion via End';
    END IF;

    -- Both requests must be terminal under the closed session either
    -- way (the original Task 9 behaviour, retained).
    IF EXISTS (
      SELECT 1 FROM public.ai_session_requests
      WHERE session_id = v_q_session AND state IN ('reserved', 'started', 'staged')
    ) THEN
      RAISE EXCEPTION 'EXPLOIT: a request row is left in-flight under a closed session';
    END IF;
  END;

  -- ===================================================================
  -- Contract 2: ending a session that is still 'preparing' -- never
  -- activated -- succeeds and leaves activated_at honestly NULL.
  --
  -- This is the Correction-1 regression: Task 1's ORIGINAL CHECK
  -- required activated_at IS NOT NULL for every non-preparing state,
  -- so closing a never-activated session either failed outright or
  -- forced a fake activation timestamp. The loosened 3-way constraint
  -- makes 'closed' honest about whether the session ever activated.
  -- ===================================================================
  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  -- Partner ends it before anyone ever approved/activated.
  PERFORM public.end_ai_session(v_user_b, v_session);
  SELECT state, activated_at INTO v_state, v_activated
  FROM public.ai_sessions WHERE id = v_session;
  IF v_state != 'closed' THEN
    RAISE EXCEPTION 'EXPLOIT: ending a preparing session did not close it (state=%)', v_state;
  END IF;
  IF v_activated IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: closing a never-activated session fabricated an activated_at timestamp';
  END IF;

  -- ===================================================================
  -- Contract 3: a private session may be ended only by its creator.
  -- Asserts the SPECIFIC rejection, not merely "something raised".
  -- ===================================================================
  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  BEGIN
    PERFORM public.end_ai_session(v_user_b, v_session);
    RAISE EXCEPTION 'EXPLOIT: a non-creator ended another member''s PRIVATE session';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%Only the creator may end a private session%' THEN
      RAISE EXCEPTION
        'EXPLOIT: the private-session creator check did not fire -- a different error stood in for it: %', SQLERRM;
    END IF;
  END;
  IF (SELECT state FROM public.ai_sessions WHERE id = v_session) != 'preparing' THEN
    RAISE EXCEPTION 'EXPLOIT: the rejected private end still mutated the session';
  END IF;
  -- The creator can.
  PERFORM public.end_ai_session(v_user_a, v_session);

  -- ===================================================================
  -- Contract 4: a NULL actor is rejected outright, with the specific
  -- 'Not authenticated' raise -- not whatever a NULL happens to break
  -- downstream.
  -- ===================================================================
  BEGIN
    PERFORM public.end_ai_session(NULL, v_session);
    RAISE EXCEPTION 'EXPLOIT: end_ai_session accepted a NULL actor';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%Not authenticated%' THEN
      RAISE EXCEPTION
        'EXPLOIT: end_ai_session''s NULL-actor guard did not fire -- a different error stood in for it: %', SQLERRM;
    END IF;
  END;
  BEGIN
    PERFORM public.share_ai_session_turn(NULL, v_session, 2);
    RAISE EXCEPTION 'EXPLOIT: share_ai_session_turn accepted a NULL actor';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%Not authenticated%' THEN
      RAISE EXCEPTION
        'EXPLOIT: share_ai_session_turn''s NULL-actor guard did not fire -- a different error stood in for it: %', SQLERRM;
    END IF;
  END;

  -- ===================================================================
  -- Contract 5: share a committed Attune turn -> a real chat message
  -- carrying attune_assist provenance, plus a publication mapping row.
  -- ===================================================================
  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(
    v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp2'
  );
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);
  PERFORM public.commit_ai_session_ideas_turn(
    v_admit.worker_token, v_admit.request_id, 'an idea', 'share this reply', NULL
  );

  v_message := public.share_ai_session_turn(v_user_a, v_session, 2);
  IF v_message.content IS DISTINCT FROM 'share this reply' THEN
    RAISE EXCEPTION 'EXPLOIT: shared message content does not match the committed Attune turn';
  END IF;
  IF v_message.message_origin IS DISTINCT FROM 'attune_assist' THEN
    RAISE EXCEPTION 'EXPLOIT: shared message did not carry attune_assist provenance';
  END IF;
  IF v_message.sender_id IS DISTINCT FROM v_user_a THEN
    RAISE EXCEPTION 'EXPLOIT: shared message was not attributed to p_actor_id';
  END IF;
  IF (SELECT count(*) FROM public.ai_session_publications WHERE session_id = v_session) != 1 THEN
    RAISE EXCEPTION 'EXPLOIT: no publication mapping row was created';
  END IF;

  -- The ambient JWT claim must be left exactly as it was found -- the
  -- RPC sets it only to drive share_ai_assist_draft's own auth.uid().
  IF COALESCE(current_setting('request.jwt.claims', true), '') != '' THEN
    RAISE EXCEPTION 'EXPLOIT: share_ai_session_turn leaked an impersonation JWT claim into the session';
  END IF;

  -- Close it out so the next private session can be prepared (one
  -- private session per creator per relationship at a time).
  PERFORM public.end_ai_session(v_user_a, v_session);

  -- ===================================================================
  -- Contract 5b (fix round 1, F2 -- Critical): share_ai_session_turn
  -- must NOT be callable by `authenticated`.
  --
  -- The RPC takes its actor as a PARAMETER and then overwrites
  -- request.jwt.claims with it. Exposed to `authenticated` through
  -- PostgREST that is a confused deputy: any logged-in user could pass
  -- a victim's user id, receive a private session's Attune answer in
  -- the returned public.messages row, and post a chat message into
  -- someone else's relationship under the victim's sender_id. Plan A's
  -- share_ai_assist_draft is safe with an `authenticated` grant only
  -- because it takes no actor parameter and derives auth.uid() itself.
  --
  -- The grant is now service_role-only, matching every other RPC in
  -- this plan and the caller Plan C actually implements
  -- (`service.rpc("share_ai_session_turn", { p_actor_id:
  -- userScoped.user.id, ... })`). As committed, service_role had NO
  -- execute privilege, so the intended caller could not call it at all.
  -- ===================================================================
  IF has_function_privilege('authenticated',
       'public.share_ai_session_turn(uuid, uuid, int)', 'EXECUTE') THEN
    RAISE EXCEPTION
      'EXPLOIT: authenticated has EXECUTE on share_ai_session_turn -- any logged-in user can pass a victim''s p_actor_id, read a private session''s answer, and post chat as them';
  END IF;
  IF has_function_privilege('anon',
       'public.share_ai_session_turn(uuid, uuid, int)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: anon has EXECUTE on share_ai_session_turn';
  END IF;
  IF NOT has_function_privilege('service_role',
       'public.share_ai_session_turn(uuid, uuid, int)', 'EXECUTE') THEN
    RAISE EXCEPTION
      'EXPLOIT: service_role has NO EXECUTE on share_ai_session_turn -- Plan C''s edge function, the intended and only caller, cannot invoke it';
  END IF;
  -- end_ai_session, for symmetry: service_role-only as the brief requires.
  IF has_function_privilege('authenticated',
       'public.end_ai_session(uuid, uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has EXECUTE on end_ai_session';
  END IF;
  IF NOT has_function_privilege('service_role',
       'public.end_ai_session(uuid, uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: service_role has no EXECUTE on end_ai_session';
  END IF;

  -- ===================================================================
  -- Contract 6: sharing a USER-role ordinal (1, not 2) must be rejected
  -- BY THE ROLE CHECK.
  --
  -- Fix round 1 (F3a): the original form of this contract accepted any
  -- error. With the `role != 'attune'` check deleted it still "passed",
  -- because commit_ai_session_ideas_turn writes the user turn's payload
  -- as {'instruction': ...} with no 'reply_text' key, so the delegation
  -- hit a NOT NULL violation on ai_assist_drafts.reply_text instead --
  -- swallowed by `WHEN OTHERS`. The user turn also carries
  -- kind='ideas_answer', so the kind allow-list does not catch it
  -- either: the role check is the ONLY guard, and it was untested.
  --
  -- Two changes make it real: (a) assert the role check's own message,
  -- and (b) first write a 'reply_text' into the USER turn's payload, so
  -- the incidental NOT NULL constraint can no longer fire and stand in
  -- for the guard.
  -- ===================================================================
  DECLARE
    v_session2 uuid;
    v_admit2 record;
  BEGIN
    SELECT session_id INTO v_session2 FROM public.prepare_ai_session(
      v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
    );
    PERFORM public.approve_ai_session_context(v_user_a, v_session2, 1, 'd', 'v1');
    PERFORM public.activate_ai_session(v_user_a, v_session2, 1);
    SELECT * INTO v_admit2 FROM public.admit_ai_session_generation(
      v_user_a, gen_random_uuid(), v_session2, 1, 'ideas:fp3'
    );
    PERFORM public.claim_ai_session_dispatch(v_admit2.worker_token, v_admit2.request_id);
    PERFORM public.commit_ai_session_ideas_turn(
      v_admit2.worker_token, v_admit2.request_id, 'another idea', 'another reply', NULL
    );

    -- Remove the incidental NOT NULL crutch: give the USER turn a
    -- reply_text so that if the role check is ever removed, the share
    -- would SUCCEED (the real exploit) rather than fail on a draft
    -- constraint that has nothing to do with authorship.
    UPDATE public.ai_session_turns
    SET payload = payload || '{"reply_text":"user text masquerading as an Attune answer"}'::jsonb
    WHERE session_id = v_session2 AND ordinal = 1;

    BEGIN
      PERFORM public.share_ai_session_turn(v_user_a, v_session2, 1);
      RAISE EXCEPTION 'EXPLOIT: a user-authored turn (ordinal 1) was shared as if it were an Attune answer';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
      IF SQLERRM NOT LIKE '%Only an Attune-authored turn may be shared%' THEN
        RAISE EXCEPTION
          'EXPLOIT: the role != ''attune'' check did not fire for a user turn -- a different error stood in for it: %', SQLERRM;
      END IF;
    END;

    -- Contract 7: a 'nearby_result' turn is NOT shareable through this
    -- generic path -- Nearby's own requester-only publish path owns
    -- that (spec §8.1). Forge the kind directly on the committed turn.
    UPDATE public.ai_session_turns SET kind = 'nearby_result'
    WHERE session_id = v_session2 AND ordinal = 2;
    BEGIN
      PERFORM public.share_ai_session_turn(v_user_a, v_session2, 2);
      RAISE EXCEPTION 'EXPLOIT: a nearby_result turn was posted through the generic share path';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
      IF SQLERRM NOT LIKE '%cannot be posted to chat: nearby_result%' THEN
        RAISE EXCEPTION
          'EXPLOIT: the kind allow-list did not reject nearby_result -- a different error stood in for it: %', SQLERRM;
      END IF;
    END;

    -- Contract 8: a 'redirect' turn cannot be posted (spec §8.1).
    UPDATE public.ai_session_turns SET kind = 'redirect'
    WHERE session_id = v_session2 AND ordinal = 2;
    BEGIN
      PERFORM public.share_ai_session_turn(v_user_a, v_session2, 2);
      RAISE EXCEPTION 'EXPLOIT: a redirect turn was posted';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
      IF SQLERRM NOT LIKE '%cannot be posted to chat: redirect%' THEN
        RAISE EXCEPTION
          'EXPLOIT: the kind allow-list did not reject redirect -- a different error stood in for it: %', SQLERRM;
      END IF;
    END;

    -- Contract 9: a relationship member who is NOT the private
    -- session's creator cannot share from it.
    UPDATE public.ai_session_turns SET kind = 'ideas_answer'
    WHERE session_id = v_session2 AND ordinal = 2;
    BEGIN
      PERFORM public.share_ai_session_turn(v_user_b, v_session2, 2);
      RAISE EXCEPTION 'EXPLOIT: a non-creator shared from another member''s private session';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
      IF SQLERRM NOT LIKE '%Only the creator may share from a private session%' THEN
        RAISE EXCEPTION
          'EXPLOIT: the private-session creator check did not fire on share -- a different error stood in for it: %', SQLERRM;
      END IF;
    END;

    -- =================================================================
    -- Contract 10: sharing from a CLOSED session is rejected BY THE
    -- STATE GUARD.
    --
    -- Fix round 1 (F3d): the original form called end_ai_session first
    -- and then tried to share -- but the end had already purged the
    -- turns, so `Turn not found` fired whether or not the state guard
    -- existed. Weakening `IF v_session.id IS NULL OR v_session.state !=
    -- 'active'` to `IF v_session.id IS NULL` left the suite passing.
    --
    -- Isolate the guard instead: flip the state to 'closed' DIRECTLY,
    -- leaving the turn in place, so the state check is the only thing
    -- standing between the caller and a successful share. Then assert
    -- its own message.
    -- =================================================================
    UPDATE public.ai_sessions SET state = 'closed' WHERE id = v_session2;
    IF NOT EXISTS (
      SELECT 1 FROM public.ai_session_turns
      WHERE session_id = v_session2 AND ordinal = 2
    ) THEN
      RAISE EXCEPTION
        'EXPLOIT (test defect): the closed-session fixture has no turn left, so "Turn not found" would stand in for the state guard';
    END IF;
    BEGIN
      PERFORM public.share_ai_session_turn(v_user_a, v_session2, 2);
      RAISE EXCEPTION 'EXPLOIT: a turn was shared out of a CLOSED session';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
      IF SQLERRM NOT LIKE '%Session unavailable%' THEN
        RAISE EXCEPTION
          'EXPLOIT: the state != ''active'' share guard did not fire on a closed session -- a different error stood in for it: %', SQLERRM;
      END IF;
    END;

    -- And the real end path still purges that transcript, closed state
    -- and all (end_ai_session is idempotent on an already-closed
    -- session, so drive the purge from an active one).
    UPDATE public.ai_sessions SET state = 'active' WHERE id = v_session2;
    PERFORM public.end_ai_session(v_user_a, v_session2);
    IF EXISTS (SELECT 1 FROM public.ai_session_turns WHERE session_id = v_session2) THEN
      RAISE EXCEPTION 'EXPLOIT: turns survived the end of the closed-session fixture';
    END IF;
  END;

  RAISE NOTICE 'end_ai_session / share_ai_session_turn contracts: all held';
END $$;
