-- Schema-level contracts for the AI Assistant tables (Plan A, Task 1).
-- Run: psql -q -d attune_test -f supabase/tests/ai_assistant_schema_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a1000000-0000-0000-0000-000000000001';
  v_user_a uuid := 'a1000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a1000000-0000-0000-0000-00000000000b';
  v_user_c uuid := 'a1000000-0000-0000-0000-00000000000c';
  v_msg_id uuid := 'a1000000-0000-0000-0000-000000000101';
  v_draft_id uuid := 'a1000000-0000-0000-0000-000000000201';
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'aiassist_a@t.test'), (v_user_b, 'aiassist_b@t.test'),
    (v_user_c, 'aiassist_c@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550001001', 'A'), (v_user_b, '+15550001002', 'B'),
    (v_user_c, '+15550001003', 'C')
  ON CONFLICT DO NOTHING;
  -- v_user_c is used later only as a non-member identity for the RLS
  -- negative check (Contract 9) -- it does not need its own
  -- relationship row, and self-pairing a user with themself would
  -- violate relationships_check (user_a <> user_b) regardless.
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -- Contract 1: message_origin defaults to 'user' with no
  -- assistant_payload, and an ordinary insert is unaffected.
  INSERT INTO public.messages (id, relationship_id, sender_id,
    client_message_id, content, source)
  VALUES (v_msg_id, v_rel, v_user_a, gen_random_uuid(),
    'hello (ai_assistant_schema_contracts fixture ' || v_msg_id || ')', 'native');
  IF NOT EXISTS (
    SELECT 1 FROM public.messages
    WHERE id = v_msg_id AND message_origin = 'user' AND assistant_payload IS NULL
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: message_origin/assistant_payload defaults are wrong';
  END IF;

  -- Contract 2: assistant_payload cannot be set while message_origin is
  -- 'user' (shape check).
  BEGIN
    UPDATE public.messages SET assistant_payload = '{"x":1}'::jsonb
    WHERE id = v_msg_id;
    RAISE EXCEPTION 'EXPLOIT: assistant_payload was set on a user-origin message';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 3: message_origin = 'attune_assist' requires a non-null
  -- assistant_payload (the reverse half of the shape check).
  BEGIN
    UPDATE public.messages SET message_origin = 'attune_assist'
    WHERE id = v_msg_id;
    RAISE EXCEPTION 'EXPLOIT: message_origin flipped to attune_assist with no payload';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 4: ai_assist_drafts.expires_at must be exactly created_at +
  -- 15 minutes.
  BEGIN
    INSERT INTO public.ai_assist_drafts
      (id, relationship_id, requester_id, target_message_id, reply_text,
       assistant_payload, created_at, expires_at)
    VALUES (v_draft_id, v_rel, v_user_a, v_msg_id, 'a suggestion',
      '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb,
      now(), now() + interval '20 minutes');
    RAISE EXCEPTION 'EXPLOIT: a draft with the wrong expiry window was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  INSERT INTO public.ai_assist_drafts
    (id, relationship_id, requester_id, target_message_id, reply_text,
     assistant_payload, created_at, expires_at)
  VALUES (v_draft_id, v_rel, v_user_a, v_msg_id, 'a suggestion',
    '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb,
    now(), now() + interval '15 minutes');

  -- Contract 5: blank-after-trim reply_text is rejected.
  BEGIN
    INSERT INTO public.ai_assist_drafts
      (id, relationship_id, requester_id, target_message_id, reply_text,
       assistant_payload, created_at, expires_at)
    VALUES (gen_random_uuid(), v_rel, v_user_a, v_msg_id, '   ',
      '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb,
      now(), now() + interval '15 minutes');
    RAISE EXCEPTION 'EXPLOIT: a whitespace-only draft reply_text was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 6: ai_assistant_usage.provider_calls is bounded 0..2.
  BEGIN
    INSERT INTO public.ai_assistant_usage
      (request_id, user_id, relationship_id, mode, provider_calls, outcome)
    VALUES (gen_random_uuid(), v_user_a, v_rel, 'assist', 3, 'succeeded');
    RAISE EXCEPTION 'EXPLOIT: provider_calls accepted a value outside 0..2';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 7: ai_processing_consent_events enforces one idempotency_key
  -- per user (UNIQUE (user_id, idempotency_key)).
  DECLARE
    v_idem uuid := gen_random_uuid();
  BEGIN
    INSERT INTO public.ai_processing_consent_events
      (relationship_id, user_id, policy_version, action, idempotency_key)
    VALUES (v_rel, v_user_a, 'v1', 'granted', v_idem);
    BEGIN
      INSERT INTO public.ai_processing_consent_events
        (relationship_id, user_id, policy_version, action, idempotency_key)
      VALUES (v_rel, v_user_a, 'v1', 'granted', v_idem);
      RAISE EXCEPTION 'EXPLOIT: a duplicate idempotency_key for the same user was accepted';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    END;
  END;

  -- Contract 8: ai_assist_planning_links always points at a plan
  -- (planning_entry_id NOT NULL, spec §16). A link with no plan is refused.
  BEGIN
    INSERT INTO public.ai_assist_planning_links (message_id, relationship_id, planning_entry_id)
    VALUES (v_msg_id, v_rel, NULL);
    RAISE EXCEPTION 'EXPLOIT: a planning link without a plan was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 9: RLS -- a non-member of rel cannot read
  -- ai_assist_planning_links rows for it. The link needs a real plan of
  -- this couple for its composite FK, created as a member.
  DECLARE
    v_link_msg_id uuid := gen_random_uuid();
    v_plan uuid := gen_random_uuid();
  BEGIN
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
    PERFORM public.get_planning_home(v_rel);
    PERFORM public.create_planning_entry(v_plan,
      (SELECT id FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'everyday'),
      'fixture for ai_assist_planning_links RLS test', false, 'USD');
    PERFORM set_config('request.jwt.claims', NULL, true);
    INSERT INTO public.messages (id, relationship_id, sender_id,
      client_message_id, content, source, message_origin, assistant_payload)
    VALUES (v_link_msg_id, v_rel, v_user_a, gen_random_uuid(), 'ai reply',
      'native', 'attune_assist',
      '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb);
    INSERT INTO public.ai_assist_planning_links (message_id, relationship_id, planning_entry_id)
    VALUES (v_link_msg_id, v_rel, v_plan);
  END;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_c), true);
  IF EXISTS (
    SELECT 1 FROM public.ai_assist_planning_links WHERE relationship_id = v_rel
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: a non-member could read another couple''s ai_assist_planning_links';
  END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', NULL, true);

  -- Contract 10: authenticated has NO direct write privilege on any of
  -- the four new tables, and NO read privilege on the three
  -- SELECT-nothing tables.
  IF has_table_privilege('authenticated', 'public.ai_assist_drafts', 'SELECT')
     OR has_table_privilege('authenticated', 'public.ai_assist_drafts', 'INSERT') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has some privilege on ai_assist_drafts';
  END IF;
  IF has_table_privilege('authenticated', 'public.ai_assistant_usage', 'SELECT') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has SELECT on ai_assistant_usage';
  END IF;
  IF has_table_privilege('authenticated', 'public.ai_processing_consent_events', 'SELECT') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has SELECT on ai_processing_consent_events';
  END IF;
  IF has_table_privilege('authenticated', 'public.ai_assist_planning_links', 'INSERT') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has direct INSERT on ai_assist_planning_links';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.ai_assist_planning_links', 'SELECT') THEN
    RAISE EXCEPTION 'authenticated is missing SELECT on ai_assist_planning_links';
  END IF;

  RAISE NOTICE 'ai assistant schema contracts: all held';
END $$;
