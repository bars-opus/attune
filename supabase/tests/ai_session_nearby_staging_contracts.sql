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
