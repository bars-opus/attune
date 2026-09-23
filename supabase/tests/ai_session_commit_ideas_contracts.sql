-- commit_ai_session_ideas_turn: atomic two-row insert with correct
-- ordinal parity, idempotent on retry. Spec §6.2 step 5, §7.1.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_commit_ideas_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000008';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000007a';
  v_session uuid;
  v_admit record;
  v_row record;
  v_row2 record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_a, 'commit_a@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_a, '+15550015001', 'A') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, status) VALUES (v_rel, v_user_a, 'active') ON CONFLICT DO NOTHING;

  SELECT session_id INTO v_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_session, 1, 'd', 'v1');
  PERFORM public.activate_ai_session(v_user_a, v_session, 1);
  SELECT * INTO v_admit FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 1, 'ideas:fp');
  PERFORM public.claim_ai_session_dispatch(v_admit.worker_token, v_admit.request_id);

  -- Contract 1: attempt_n=1 -> ordinals (1, 2).
  SELECT * INTO v_row FROM public.commit_ai_session_ideas_turn(
    v_admit.worker_token, v_admit.request_id, 'brainstorm date ideas', 'a great reply', NULL
  );
  IF v_row.committed IS DISTINCT FROM true OR v_row.user_ordinal != 1 OR v_row.attune_ordinal != 2 THEN
    RAISE EXCEPTION 'EXPLOIT: attempt_n=1 did not produce ordinals (1,2), got committed=% user=% attune=%',
      v_row.committed, v_row.user_ordinal, v_row.attune_ordinal;
  END IF;
  IF (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session) != 2 THEN
    RAISE EXCEPTION 'EXPLOIT: expected exactly 2 turn rows after one committed attempt';
  END IF;
  IF (SELECT role FROM public.ai_session_turns WHERE session_id = v_session AND ordinal = 1) != 'user' THEN
    RAISE EXCEPTION 'EXPLOIT: ordinal 1 is not role=user';
  END IF;
  IF (SELECT role FROM public.ai_session_turns WHERE session_id = v_session AND ordinal = 2) != 'attune' THEN
    RAISE EXCEPTION 'EXPLOIT: ordinal 2 is not role=attune';
  END IF;

  -- Contract 2: retrying the SAME request_id (lost HTTP response) is
  -- idempotent -- same ordinals, no second insert.
  SELECT * INTO v_row2 FROM public.commit_ai_session_ideas_turn(
    v_admit.worker_token, v_admit.request_id, 'brainstorm date ideas', 'a great reply', NULL
  );
  IF v_row2.user_ordinal != v_row.user_ordinal OR v_row2.attune_ordinal != v_row.attune_ordinal THEN
    RAISE EXCEPTION 'EXPLOIT: retrying a committed request produced different ordinals';
  END IF;
  IF (SELECT count(*) FROM public.ai_session_turns WHERE session_id = v_session) != 2 THEN
    RAISE EXCEPTION 'EXPLOIT: retrying a committed request inserted duplicate turn rows';
  END IF;

  -- Contract 3: a second attempt (attempt_n=2) -> ordinals (3, 4).
  -- Note: expected_revision is 2 here, not 1 -- contract 1's commit
  -- above already advanced ai_sessions.revision from 1 to 2 (brief's
  -- literal sample text used 1 again, which is stale and raises
  -- CONTEXT_CHANGED; this is a test-only correction, not an RPC change).
  DECLARE
    v_admit2 record;
    v_row3 record;
  BEGIN
    SELECT * INTO v_admit2 FROM public.admit_ai_session_generation(v_user_a, gen_random_uuid(), v_session, 2, 'ideas:fp-2');
    PERFORM public.claim_ai_session_dispatch(v_admit2.worker_token, v_admit2.request_id);
    SELECT * INTO v_row3 FROM public.commit_ai_session_ideas_turn(
      v_admit2.worker_token, v_admit2.request_id, 'a second instruction', 'a second reply', NULL
    );
    IF v_row3.user_ordinal != 3 OR v_row3.attune_ordinal != 4 THEN
      RAISE EXCEPTION 'EXPLOIT: attempt_n=2 did not produce ordinals (3,4), got user=% attune=%', v_row3.user_ordinal, v_row3.attune_ordinal;
    END IF;
  END;

  RAISE NOTICE 'commit_ai_session_ideas_turn contracts: all held';
END $$;
