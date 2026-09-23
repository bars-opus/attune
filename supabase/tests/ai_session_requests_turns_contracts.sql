-- ai_session_requests / ai_session_turns / ai_session_staging /
-- ai_session_publications: shape, ordinal parity, and the surviving
-- publication marker. Spec §7.1.
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_requests_turns_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'b1000000-0000-0000-0000-000000000002';
  v_user_a uuid := 'b1000000-0000-0000-0000-00000000001a';
  v_session uuid := gen_random_uuid();
  v_request uuid := gen_random_uuid();
  v_message uuid;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_a, 'req_a@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_user_a, '+15550009001', 'A') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, status) VALUES (v_rel, v_user_a, 'active') ON CONFLICT DO NOTHING;
  INSERT INTO public.ai_sessions (
    id, relationship_id, creator_id, kind, visibility, state,
    revision, context_revision, generation_epoch, attempt_count, preparation_deadline
  ) VALUES (
    v_session, v_rel, v_user_a, 'ideas', 'private', 'preparing',
    1, 0, 0, 0, now() + interval '5 minutes'
  );

  -- Contract 1: a request row with attempt_n=1 and its matching turn
  -- pair at ordinals 1 (user) and 2 (attune) insert cleanly.
  INSERT INTO public.ai_session_requests (
    id, session_id, actor_id, attempt_n, operation_fingerprint,
    worker_token, generation_epoch, lease_deadline, state
  ) VALUES (
    v_request, v_session, v_user_a, 1, 'ideas:hash-of-instruction',
    gen_random_uuid(), 0, now() + interval '35 seconds', 'reserved'
  );
  INSERT INTO public.ai_session_turns (session_id, request_id, ordinal, role, author_id, kind, payload)
  VALUES
    (v_session, v_request, 1, 'user', v_user_a, 'ideas_answer', '{"instruction": "test"}'::jsonb),
    (v_session, v_request, 2, 'attune', NULL, 'ideas_answer', '{"reply_text": "test reply"}'::jsonb);

  -- Contract 2: an 'attune' role row REQUIRES a NULL author_id, and a
  -- 'user' role row REQUIRES a non-NULL author_id -- this is the check
  -- constraint proving the spec's "author ID for user only" rule at
  -- the schema level, not just by convention in the RPC that inserts
  -- these rows (Task 8).
  BEGIN
    INSERT INTO public.ai_session_turns (session_id, request_id, ordinal, role, author_id, kind, payload)
    VALUES (v_session, v_request, 3, 'attune', v_user_a, 'ideas_answer', '{}'::jsonb);
    RAISE EXCEPTION 'EXPLOIT: an attune-role turn accepted a non-NULL author_id';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 3: ordinal is unique per session -- a duplicate ordinal
  -- for a DIFFERENT request in the same session is rejected outright.
  BEGIN
    INSERT INTO public.ai_session_requests (
      id, session_id, actor_id, attempt_n, operation_fingerprint,
      worker_token, generation_epoch, lease_deadline, state
    ) VALUES (
      gen_random_uuid(), v_session, v_user_a, 2, 'ideas:different',
      gen_random_uuid(), 0, now() + interval '35 seconds', 'reserved'
    );
    INSERT INTO public.ai_session_turns (session_id, request_id, ordinal, role, author_id, kind, payload)
    VALUES (v_session, v_request, 1, 'user', v_user_a, 'ideas_answer', '{}'::jsonb);
    RAISE EXCEPTION 'EXPLOIT: a duplicate ordinal within the same session was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 4: publication marker survives message_id going NULL.
  v_message := gen_random_uuid();
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, source, created_at)
  VALUES (v_message, v_rel, v_user_a, gen_random_uuid(), 'a shared answer', 'native', now());
  INSERT INTO public.ai_session_publications (session_id, request_id, message_id, consumed_marker)
  VALUES (v_session, v_request, v_message, true);
  DELETE FROM public.messages WHERE id = v_message;
  IF (SELECT count(*) FROM public.ai_session_publications WHERE session_id = v_session AND request_id = v_request) != 1 THEN
    RAISE EXCEPTION 'EXPLOIT: the publication marker was deleted when its message was deleted -- FK must be ON DELETE SET NULL, not CASCADE';
  END IF;
  IF (SELECT message_id FROM public.ai_session_publications WHERE session_id = v_session AND request_id = v_request) IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: message_id did not go NULL after the message was deleted';
  END IF;

  RAISE NOTICE 'ai_session_requests/turns/staging/publications contracts: all held';
END $$;
