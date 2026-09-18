-- Consent RPC contracts (Plan A, Task 3).
-- Run: psql -q -d attune_test -f supabase/tests/ai_processing_consent_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a3000000-0000-0000-0000-000000000001';
  v_user_a uuid := 'a3000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a3000000-0000-0000-0000-00000000000b';
  v_user_stranger uuid := 'a3000000-0000-0000-0000-00000000000c';
  v_row record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'consent_a@t.test'), (v_user_b, 'consent_b@t.test'),
    (v_user_stranger, 'consent_c@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550003001', 'A'), (v_user_b, '+15550003002', 'B'),
    (v_user_stranger, '+15550003003', 'C')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 1: a non-member cannot record consent for a relationship
  -- they don't belong to.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_stranger), true);
  BEGIN
    PERFORM public.record_ai_processing_consent(v_rel, 'granted', gen_random_uuid());
    RAISE EXCEPTION 'EXPLOIT: a non-member recorded consent';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 2: before either partner grants, status shows neither
  -- granted.
  SELECT * INTO v_row FROM public.get_ai_processing_consent_status(v_rel);
  IF v_row.caller_granted IS DISTINCT FROM false OR v_row.both_granted IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: status showed granted before any consent event';
  END IF;

  -- Contract 3: user_a grants; status shows caller_granted true,
  -- both_granted false (user_b has not granted).
  PERFORM public.record_ai_processing_consent(v_rel, 'granted', gen_random_uuid());
  SELECT * INTO v_row FROM public.get_ai_processing_consent_status(v_rel);
  IF v_row.caller_granted IS DISTINCT FROM true OR v_row.both_granted IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: status wrong after only one partner granted';
  END IF;

  -- Contract 4: user_b grants too; both_granted flips true.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
  PERFORM public.record_ai_processing_consent(v_rel, 'granted', gen_random_uuid());
  SELECT * INTO v_row FROM public.get_ai_processing_consent_status(v_rel);
  IF v_row.both_granted IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: both_granted did not flip true after both partners granted';
  END IF;

  -- Contract 5: status never reveals the PARTNER's own granted state
  -- distinctly from both_granted -- i.e. caller_granted always reflects
  -- the CALLER, not whichever partner happens to be "further along".
  -- Verify by checking user_a's own view still shows their own state
  -- correctly even though user_b granted more recently.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  SELECT * INTO v_row FROM public.get_ai_processing_consent_status(v_rel);
  IF v_row.caller_granted IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: caller_granted did not reflect the calling user''s own event';
  END IF;

  -- Contract 6: withdrawal flips caller_granted back to false and
  -- both_granted back to false.
  PERFORM public.record_ai_processing_consent(v_rel, 'withdrawn', gen_random_uuid());
  SELECT * INTO v_row FROM public.get_ai_processing_consent_status(v_rel);
  IF v_row.caller_granted IS DISTINCT FROM false OR v_row.both_granted IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: withdrawal did not clear caller_granted/both_granted';
  END IF;

  -- Contract 6b: withdrawal by user_a must not affect user_b's own
  -- status. user_b granted (still current, still 'granted') and never
  -- withdrew -- user_b's caller_granted must still read true.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
  SELECT * INTO v_row FROM public.get_ai_processing_consent_status(v_rel);
  IF v_row.caller_granted IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: user_a''s withdrawal leaked into user_b''s own caller_granted';
  END IF;
  IF v_row.both_granted IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: both_granted did not reflect user_a''s withdrawal from user_b''s view';
  END IF;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 7: retrying record_ai_processing_consent with the SAME
  -- idempotency_key is a no-op (the UNIQUE constraint from Task 1 is the
  -- backstop, but the RPC itself must not error on a legitimate client
  -- retry -- it should treat a conflict as "already recorded").
  DECLARE
    v_idem uuid := gen_random_uuid();
  BEGIN
    PERFORM public.record_ai_processing_consent(v_rel, 'granted', v_idem);
    PERFORM public.record_ai_processing_consent(v_rel, 'granted', v_idem);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'EXPLOIT: retrying record_ai_processing_consent with the same idempotency_key errored: %', SQLERRM;
  END;

  -- Contract 8: a non-member cannot read consent status either.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_stranger), true);
  BEGIN
    PERFORM public.get_ai_processing_consent_status(v_rel);
    RAISE EXCEPTION 'EXPLOIT: a non-member read consent status';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 9: a stale grant from a previous policy version must not
  -- count as current. Simulate a version bump by inserting an event
  -- directly at a fabricated older version and a fabricated newer
  -- version, and confirm get_ai_processing_consent_status (which reads
  -- the CURRENT version via ai_current_consent_policy_version()) does
  -- not report the old-version grant as active for either partner.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  DECLARE
    v_rel2 uuid := 'a3000000-0000-0000-0000-000000000002';
    v_current_version text := public.ai_current_consent_policy_version();
  BEGIN
    INSERT INTO public.relationships (id, user_a, user_b, status)
    VALUES (v_rel2, v_user_a, v_user_b, 'active')
    ON CONFLICT DO NOTHING;

    -- Both partners granted, but at a stale version distinct from the
    -- server's current version (simulating "granted under v1, policy
    -- since bumped to v2, neither partner has re-granted").
    INSERT INTO public.ai_processing_consent_events
      (relationship_id, user_id, policy_version, action, idempotency_key)
    VALUES
      (v_rel2, v_user_a, v_current_version || '-stale', 'granted', gen_random_uuid()),
      (v_rel2, v_user_b, v_current_version || '-stale', 'granted', gen_random_uuid());

    SELECT * INTO v_row FROM public.get_ai_processing_consent_status(v_rel2);
    IF v_row.caller_granted IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'EXPLOIT: a stale-version grant counted as caller_granted under the current version';
    END IF;
    IF v_row.both_granted IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'EXPLOIT: a stale-version grant counted toward both_granted under the current version';
    END IF;
    IF v_row.policy_version IS DISTINCT FROM v_current_version THEN
      RAISE EXCEPTION 'EXPLOIT: get_ai_processing_consent_status did not report the server-current policy_version';
    END IF;

    PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
    SELECT * INTO v_row FROM public.get_ai_processing_consent_status(v_rel2);
    IF v_row.caller_granted IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'EXPLOIT: a stale-version grant counted as caller_granted (user_b) under the current version';
    END IF;
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  END;

  RAISE NOTICE 'ai processing consent contracts: all held';
END $$;
