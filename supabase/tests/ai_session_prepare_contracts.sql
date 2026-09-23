-- prepare_ai_session: idempotent creation, one-pending-slot enforcement,
-- expired-slot reclamation. Spec §3.2.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_prepare_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000003';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000002a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000002b';
  v_key_1 uuid := gen_random_uuid();
  v_row record;
  v_session_1 uuid;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'prep_a@t.test'), (v_user_b, 'prep_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550010001', 'A'), (v_user_b, '+15550010002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -- Contract 1: a fresh prepare succeeds and returns created=true.
  SELECT * INTO v_row FROM public.prepare_ai_session(
    v_user_a, v_key_1, v_rel, 'ideas', 'private', NULL, false
  );
  IF v_row.created IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: a fresh prepare did not report created=true';
  END IF;
  v_session_1 := v_row.session_id;

  -- Contract 2: replaying the SAME idempotency key returns the SAME
  -- session_id with created=false, not a second row.
  SELECT * INTO v_row FROM public.prepare_ai_session(
    v_user_a, v_key_1, v_rel, 'ideas', 'private', NULL, false
  );
  IF v_row.session_id IS DISTINCT FROM v_session_1 OR v_row.created IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: replaying the same idempotency key created a second session';
  END IF;

  -- Contract 3: a SECOND private prepare by the SAME creator, with a
  -- DIFFERENT idempotency key, while the first is still preparing,
  -- is rejected (one pending private session per creator).
  BEGIN
    PERFORM public.prepare_ai_session(v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false);
    RAISE EXCEPTION 'EXPLOIT: a second concurrent private preparing session was allowed for the same creator';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 4: user_b's OWN private session slot is independent of
  -- user_a's -- the limit is per-creator, not per-relationship, for
  -- the private case.
  PERFORM public.prepare_ai_session(v_user_b, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false);

  -- Contract 5: an expired preparing session is reclaimed -- backdate
  -- the first session's deadline into the past, then prove a new
  -- private prepare by user_a now succeeds.
  UPDATE public.ai_sessions SET preparation_deadline = now() - interval '1 minute'
  WHERE id = v_session_1;
  PERFORM public.prepare_ai_session(v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false);
  IF (SELECT state FROM public.ai_sessions WHERE id = v_session_1) != 'closed' THEN
    RAISE EXCEPTION 'EXPLOIT: the expired preparing session was not reclaimed (closed) before the new one was allowed';
  END IF;

  RAISE NOTICE 'prepare_ai_session contracts: all held';
END $$;
