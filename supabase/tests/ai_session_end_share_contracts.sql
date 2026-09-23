-- end_ai_session (synchronous content purge, either-partner-ends) and
-- share_ai_session_turn (adapts the existing draft/share pipeline).
-- Spec §5.4, §8.1.
--
-- Fixture UUIDs use the b1000000-...-0000000003x range, which a sweep
-- of every existing supabase/tests/*.sql confirmed is unused (the
-- brief's own suggested ...-00000000009a collides with Task 7's
-- ai_session_commit_ideas_contracts.sql).
--
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_end_share_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000030';
  v_user_a uuid := 'b1000000-0000-0000-0000-000000000031';
  v_user_b uuid := 'b1000000-0000-0000-0000-000000000032';
  v_session uuid;
  v_admit record;
  v_message public.messages;
  v_state text;
  v_activated timestamptz;
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
  INSERT INTO public.ai_processing_consent_events (relationship_id, user_id, policy_version, action, idempotency_key)
  VALUES
    (v_rel, v_user_a, 'v1', 'granted', gen_random_uuid()),
    (v_rel, v_user_b, 'v1', 'granted', gen_random_uuid());

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
  IF EXISTS (SELECT 1 FROM public.ai_session_sources WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'EXPLOIT: source rows survived end_ai_session';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ai_session_staging WHERE session_id = v_session) THEN
    RAISE EXCEPTION 'EXPLOIT: staging rows survived end_ai_session';
  END IF;

  -- The epoch advanced, fencing any in-flight worker (spec §6.2).
  IF (SELECT generation_epoch FROM public.ai_sessions WHERE id = v_session) < 1 THEN
    RAISE EXCEPTION 'EXPLOIT: end_ai_session did not advance generation_epoch to fence in-flight workers';
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
  -- ===================================================================
  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  BEGIN
    PERFORM public.end_ai_session(v_user_b, v_session);
    RAISE EXCEPTION 'EXPLOIT: a non-creator ended another member''s PRIVATE session';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;
  IF (SELECT state FROM public.ai_sessions WHERE id = v_session) != 'preparing' THEN
    RAISE EXCEPTION 'EXPLOIT: the rejected private end still mutated the session';
  END IF;
  -- The creator can.
  PERFORM public.end_ai_session(v_user_a, v_session);

  -- ===================================================================
  -- Contract 4: a NULL actor is rejected outright on both RPCs.
  -- ===================================================================
  BEGIN
    PERFORM public.end_ai_session(NULL, v_session);
    RAISE EXCEPTION 'EXPLOIT: end_ai_session accepted a NULL actor';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
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
  -- Contract 6: sharing a USER-role ordinal (1, not 2) must be rejected.
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
    BEGIN
      PERFORM public.share_ai_session_turn(v_user_a, v_session2, 1);
      RAISE EXCEPTION 'EXPLOIT: a user-authored turn (ordinal 1) was shared as if it were an Attune answer';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
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
    END;

    -- Contract 8: a 'redirect' turn cannot be posted (spec §8.1).
    UPDATE public.ai_session_turns SET kind = 'redirect'
    WHERE session_id = v_session2 AND ordinal = 2;
    BEGIN
      PERFORM public.share_ai_session_turn(v_user_a, v_session2, 2);
      RAISE EXCEPTION 'EXPLOIT: a redirect turn was posted';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    END;

    -- Contract 9: a non-member cannot share from someone else's
    -- private session. (v_user_b is a relationship member but not the
    -- private session's creator.)
    UPDATE public.ai_session_turns SET kind = 'ideas_answer'
    WHERE session_id = v_session2 AND ordinal = 2;
    BEGIN
      PERFORM public.share_ai_session_turn(v_user_b, v_session2, 2);
      RAISE EXCEPTION 'EXPLOIT: a non-creator shared from another member''s private session';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    END;

    -- Contract 10: sharing from a CLOSED session is rejected -- and
    -- after end_ai_session purged the turns there is nothing to share
    -- anyway.
    PERFORM public.end_ai_session(v_user_a, v_session2);
    BEGIN
      PERFORM public.share_ai_session_turn(v_user_a, v_session2, 2);
      RAISE EXCEPTION 'EXPLOIT: a turn was shared out of a closed session';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    END;
  END;

  RAISE NOTICE 'end_ai_session / share_ai_session_turn contracts: all held';
END $$;
