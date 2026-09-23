-- admit_ai_session_generation: the full §6.2 admission sequence.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_admit_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000008';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000004a';
  v_session uuid;
  v_row record;
  v_row2 record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_a, 'admit_a@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_a, '+15550012001', 'A') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, status) VALUES (v_rel, v_user_a, 'active') ON CONFLICT DO NOTHING;

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
