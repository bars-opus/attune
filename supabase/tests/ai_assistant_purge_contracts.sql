-- purge_expired_ai_assist_drafts / purge_old_ai_assistant_usage
-- contracts (AI Assistant Plan A, Task 8).
-- Run: psql -q -d attune_test -f supabase/tests/ai_assistant_purge_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a8100000-0000-0000-0000-000000000001';
  v_user_a uuid := 'a8100000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a8100000-0000-0000-0000-00000000000b';
  v_old_draft uuid;
  v_fresh_draft uuid;
  v_shared_draft uuid;
  v_shared_msg uuid;
  v_old_usage uuid;
  v_fresh_usage uuid;
  v_count int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_a, 'ai8_purge_a@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO auth.users (id, email) VALUES (v_user_b, 'ai8_purge_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550008101', 'A'), (v_user_b, '+15550008102', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -----------------------------------------------------------------------
  -- Contract 1: a draft with created_at > 24 hours ago is hard-deleted.
  -----------------------------------------------------------------------
  v_old_draft := gen_random_uuid();
  INSERT INTO public.ai_assist_drafts (
    id, relationship_id, requester_id, target_message_id, reply_text,
    assistant_payload, created_at, expires_at
  ) VALUES (
    v_old_draft, v_rel, v_user_a, NULL, 'an old draft reply',
    '{"schema_version":1}'::jsonb,
    now() - interval '25 hours', now() - interval '25 hours' + interval '15 minutes'
  );

  PERFORM public.purge_expired_ai_assist_drafts();

  SELECT count(*) INTO v_count FROM public.ai_assist_drafts WHERE id = v_old_draft;
  IF v_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'EXPLOIT: draft older than 24h was not purged';
  END IF;

  -----------------------------------------------------------------------
  -- Contract 2: a draft with created_at < 24 hours ago is NOT purged,
  -- even though its 15-minute expires_at has already passed. Expiry
  -- blocks sharing only; the 24h mark triggers physical deletion.
  -----------------------------------------------------------------------
  -- Aged 2 hours: well past the 15-minute expires_at (so sharing is
  -- already blocked) but well short of the 24-hour purge mark, and
  -- crucially also past a too-aggressive 1-hour threshold -- this value
  -- is chosen specifically so a mutated 1-hour threshold would wrongly
  -- purge this row and get caught, not just a >=24h mutation.
  v_fresh_draft := gen_random_uuid();
  INSERT INTO public.ai_assist_drafts (
    id, relationship_id, requester_id, target_message_id, reply_text,
    assistant_payload, created_at, expires_at
  ) VALUES (
    v_fresh_draft, v_rel, v_user_a, NULL, 'a fresh but expired draft',
    '{"schema_version":1}'::jsonb,
    now() - interval '2 hours', now() - interval '2 hours' + interval '15 minutes'
  );

  PERFORM public.purge_expired_ai_assist_drafts();

  SELECT count(*) INTO v_count FROM public.ai_assist_drafts WHERE id = v_fresh_draft;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: draft younger than 24h was purged despite its expires_at having passed';
  END IF;

  -----------------------------------------------------------------------
  -- Contract 3: a SHARED draft (shared_message_id set) is still purged
  -- at the same 24h mark, and purging it never touches the shared
  -- messages row (shared_message_id's FK is ON DELETE SET NULL, not
  -- CASCADE).
  -----------------------------------------------------------------------
  v_shared_msg := gen_random_uuid();
  INSERT INTO public.messages (
    id, relationship_id, sender_id, client_message_id, content,
    message_origin, assistant_payload, is_system_notice,
    message_analysis_skipped, source, created_at
  ) VALUES (
    v_shared_msg, v_rel, v_user_a, gen_random_uuid(), 'a shared assist reply',
    'attune_assist', '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb,
    false, true, 'native', now() - interval '25 hours'
  );

  v_shared_draft := gen_random_uuid();
  INSERT INTO public.ai_assist_drafts (
    id, relationship_id, requester_id, target_message_id, reply_text,
    assistant_payload, created_at, expires_at, shared_message_id
  ) VALUES (
    v_shared_draft, v_rel, v_user_a, NULL, 'a shared assist reply',
    '{"schema_version":1}'::jsonb,
    now() - interval '25 hours', now() - interval '25 hours' + interval '15 minutes',
    v_shared_msg
  );

  PERFORM public.purge_expired_ai_assist_drafts();

  SELECT count(*) INTO v_count FROM public.ai_assist_drafts WHERE id = v_shared_draft;
  IF v_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'EXPLOIT: shared draft older than 24h was not purged';
  END IF;

  SELECT count(*) INTO v_count FROM public.messages WHERE id = v_shared_msg;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: purging the draft row deleted (or otherwise removed) the shared messages row';
  END IF;

  -----------------------------------------------------------------------
  -- Contract 4: ai_assistant_usage rows older than 30 days are purged;
  -- rows newer than 30 days are not.
  -----------------------------------------------------------------------
  v_old_usage := gen_random_uuid();
  INSERT INTO public.ai_assistant_usage (
    request_id, user_id, relationship_id, mode, provider_calls, outcome,
    created_at, updated_at
  ) VALUES (
    v_old_usage, v_user_a, v_rel, 'assist', 1, 'succeeded',
    now() - interval '31 days', now() - interval '31 days'
  );

  v_fresh_usage := gen_random_uuid();
  INSERT INTO public.ai_assistant_usage (
    request_id, user_id, relationship_id, mode, provider_calls, outcome,
    created_at, updated_at
  ) VALUES (
    v_fresh_usage, v_user_a, v_rel, 'assist', 1, 'succeeded',
    now() - interval '29 days', now() - interval '29 days'
  );

  PERFORM public.purge_old_ai_assistant_usage();

  SELECT count(*) INTO v_count FROM public.ai_assistant_usage WHERE request_id = v_old_usage;
  IF v_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'EXPLOIT: usage row older than 30 days was not purged';
  END IF;

  SELECT count(*) INTO v_count FROM public.ai_assistant_usage WHERE request_id = v_fresh_usage;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: usage row younger than 30 days was purged';
  END IF;

  RAISE NOTICE 'ai_assistant_purge_contracts.sql: all contracts passed';
END $$;
