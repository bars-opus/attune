-- release_ai_assistant_quota_reservation: the exclusive "pre-start
-- release" path. Spec §7.3, §8.2.2.
-- Run: psql -q -d attune_test -f supabase/tests/ai_assistant_quota_release_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a5000000-0000-0000-0000-000000000002';
  v_user_a uuid := 'a5000000-0000-0000-0000-00000000010a';
  v_user_b uuid := 'a5000000-0000-0000-0000-00000000010b';
  v_req_release uuid := 'a5000000-0000-0000-0000-000000000201';
  v_req_started uuid := 'a5000000-0000-0000-0000-000000000202';
  v_row record;
  v_count int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'release_a@t.test'), (v_user_b, 'release_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550950601', 'A'), (v_user_b, '+15550950602', 'B')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -- Contract 1: releasing a never-started reservation excludes it from
  -- the rolling-window count.
  PERFORM public.reserve_ai_assistant_quota(v_user_a, v_req_release, v_rel, 'assist');
  PERFORM public.release_ai_assistant_quota_reservation(v_user_a, v_req_release);
  SELECT count(*) INTO v_count FROM public.ai_assistant_usage u
  WHERE u.user_id = v_user_a AND u.created_at >= now() - interval '24 hours'
    AND (u.provider_started_at IS NOT NULL OR u.outcome NOT IN ('rejected', 'cancelled'));
  IF v_count != 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a released never-started reservation still counts toward quota';
  END IF;

  -- Contract 2: releasing is idempotent -- calling it twice on the same
  -- row does not raise.
  PERFORM public.release_ai_assistant_quota_reservation(v_user_a, v_req_release);

  -- Contract 3: a STARTED reservation can never be released -- this is
  -- the core invariant. Attempting it must raise, and the row must
  -- remain counted afterward.
  PERFORM public.reserve_ai_assistant_quota(v_user_a, v_req_started, v_rel, 'assist');
  PERFORM public.claim_ai_assistant_provider_start(v_user_a, v_req_started);
  BEGIN
    PERFORM public.release_ai_assistant_quota_reservation(v_user_a, v_req_started);
    RAISE EXCEPTION 'EXPLOIT: a started reservation was released -- quota can be evaded post-dispatch';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;
  SELECT * INTO v_row FROM public.ai_assistant_usage WHERE request_id = v_req_started;
  IF v_row.outcome != 'reserved' THEN
    RAISE EXCEPTION 'EXPLOIT: the rejected release attempt still mutated outcome, got %', v_row.outcome;
  END IF;

  -- Contract 4: a non-owner cannot release someone else's reservation.
  BEGIN
    PERFORM public.release_ai_assistant_quota_reservation(v_user_b, v_req_release);
    RAISE EXCEPTION 'EXPLOIT: user_b released user_a''s own reservation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 5: not `authenticated`-callable.
  IF EXISTS (
    SELECT 1 FROM information_schema.role_routine_grants g
    WHERE g.routine_name = 'release_ai_assistant_quota_reservation'
      AND g.grantee = 'authenticated'
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has EXECUTE on release_ai_assistant_quota_reservation';
  END IF;

  RAISE NOTICE 'quota release contracts: all held';
END $$;
