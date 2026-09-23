-- approve_ai_session_context / activate_ai_session. Spec §3.2, §4.3, §7.1.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_approve_activate_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000004';
  -- Separate relationship for the digest-mismatch scenario below: the
  -- first shared session (v_shared_session) is activated on v_rel and
  -- stays 'active', and prepare_ai_session's one-shared-slot-per-
  -- relationship rule (Task 3) rejects a second shared prepare on the
  -- SAME relationship while one is still active/preparing. Using a
  -- distinct relationship here isolates the mismatch scenario from that
  -- unrelated slot limit -- no RPC behavior under test is affected.
  v_rel2 uuid := 'b1000000-0000-0000-0000-000000000005';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000003a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000003b';
  v_row record;
  v_private_session uuid;
  v_shared_session uuid;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'appr_a@t.test'), (v_user_b, 'appr_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550011001', 'A'), (v_user_b, '+15550011002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel2, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -- Private: one approval activates it.
  SELECT session_id INTO v_private_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'private', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_private_session, 1, 'digest-a', 'v1');
  SELECT * INTO v_row FROM public.activate_ai_session(v_user_a, v_private_session, 1);
  IF v_row.activated IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: a private session with its own creator''s approval did not activate';
  END IF;

  -- Shared: creator's approval alone is NOT enough.
  SELECT session_id INTO v_shared_session FROM public.prepare_ai_session(
    v_user_a, gen_random_uuid(), v_rel, 'ideas', 'shared', NULL, false
  );
  PERFORM public.approve_ai_session_context(v_user_a, v_shared_session, 1, 'digest-shared', 'v1');
  BEGIN
    PERFORM public.activate_ai_session(v_user_a, v_shared_session, 1);
    RAISE EXCEPTION 'EXPLOIT: a shared session activated with only ONE partner''s approval';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Both approve the SAME digest -> activates.
  PERFORM public.approve_ai_session_context(v_user_b, v_shared_session, 1, 'digest-shared', 'v1');
  SELECT * INTO v_row FROM public.activate_ai_session(v_user_a, v_shared_session, 1);
  IF v_row.activated IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: a shared session with BOTH partners'' approval on the same digest did not activate';
  END IF;

  -- A mismatched digest between partners must not silently activate --
  -- approve_ai_session_context itself does not compare digests across
  -- members (that comparison IS the point: two different digests means
  -- the two partners approved two different snapshots, which can only
  -- happen if the session's own content changed between their two
  -- opens -- a case activate_ai_session must reject explicitly.
  DECLARE
    v_mismatch_session uuid;
  BEGIN
    SELECT session_id INTO v_mismatch_session FROM public.prepare_ai_session(
      v_user_a, gen_random_uuid(), v_rel2, 'ideas', 'shared', NULL, false
    );
    PERFORM public.approve_ai_session_context(v_user_a, v_mismatch_session, 1, 'digest-x', 'v1');
    PERFORM public.approve_ai_session_context(v_user_b, v_mismatch_session, 1, 'digest-y', 'v1');
    BEGIN
      PERFORM public.activate_ai_session(v_user_a, v_mismatch_session, 1);
      RAISE EXCEPTION 'EXPLOIT: a shared session activated despite the two partners approving DIFFERENT digests';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    END;
  END;

  RAISE NOTICE 'approve/activate contracts: all held';
END $$;
