-- Draft insertion (service-role only) and share RPC contracts (Plan A,
-- Task 6). Spec §5.3, §7.2.
-- Run: psql -q -d attune_test -f supabase/tests/ai_assist_draft_share_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a6000000-0000-0000-0000-000000000001';
  v_user_a uuid := 'a6000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a6000000-0000-0000-0000-00000000000b';
  v_user_c uuid := 'a6000000-0000-0000-0000-00000000000c';
  v_target_msg uuid := 'a6000000-0000-0000-0000-000000000101';
  v_draft uuid;
  v_row record;
  v_msg record;
  v_count int;
  v_argtypes text;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'ai6_a@t.test'), (v_user_b, 'ai6_b@t.test'), (v_user_c, 'ai6_c@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550006001', 'A'), (v_user_b, '+15550006002', 'B'),
    (v_user_c, '+15550006003', 'C')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.messages (id, relationship_id, sender_id,
    client_message_id, content, source)
  VALUES (v_target_msg, v_rel, v_user_b, gen_random_uuid(), 'want to get dinner?', 'native')
  ON CONFLICT DO NOTHING;

  -- Both partners must have current consent for share_ai_assist_draft to
  -- succeed at all -- grant it up front for both, using the real RPC so
  -- this fixture exercises the same path production does.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  PERFORM public.record_ai_processing_consent(v_rel, 'granted', gen_random_uuid());
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
  PERFORM public.record_ai_processing_consent(v_rel, 'granted', gen_random_uuid());
  PERFORM set_config('request.jwt.claims', NULL, true);

  -----------------------------------------------------------------------
  -- Contract 1: insert_ai_assist_draft is only callable by the service
  -- role / table owner -- a direct authenticated-role call is rejected.
  -----------------------------------------------------------------------
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
    PERFORM public.insert_ai_assist_draft(
      gen_random_uuid(), v_rel, v_user_a, v_target_msg, 'a client-supplied reply',
      '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb
    );
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', NULL, true);
    RAISE EXCEPTION 'EXPLOIT: authenticated could call insert_ai_assist_draft directly';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN
      RESET ROLE;
      PERFORM set_config('request.jwt.claims', NULL, true);
      RAISE;
    END IF;
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', NULL, true);
  END;

  -----------------------------------------------------------------------
  -- Contract 2: a fresh, unexpired draft can be shared by its own
  -- requester, producing exactly one messages row with the right
  -- provenance and the draft's own content verbatim.
  -----------------------------------------------------------------------
  v_draft := gen_random_uuid();
  PERFORM public.insert_ai_assist_draft(
    v_draft, v_rel, v_user_a, v_target_msg, 'How about that new ramen place?',
    '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb
  );

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  SELECT * INTO v_row FROM public.share_ai_assist_draft(v_draft);
  PERFORM set_config('request.jwt.claims', NULL, true);

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: share_ai_assist_draft did not return a message row';
  END IF;
  IF v_row.message_origin IS DISTINCT FROM 'attune_assist'
     OR v_row.message_analysis_skipped IS DISTINCT FROM true
     OR v_row.content IS DISTINCT FROM 'How about that new ramen place?' THEN
    RAISE EXCEPTION 'EXPLOIT: shared message provenance/content is wrong: origin=%, skipped=%, content=%',
      v_row.message_origin, v_row.message_analysis_skipped, v_row.content;
  END IF;
  SELECT count(*) INTO v_count FROM public.messages
  WHERE relationship_id = v_rel AND message_origin = 'attune_assist';
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: sharing did not produce exactly one attune_assist message, got %', v_count;
  END IF;

  -----------------------------------------------------------------------
  -- Contract 3: share_ai_assist_draft is rejected for anyone other than
  -- the draft's own requester_id.
  -----------------------------------------------------------------------
  DECLARE
    v_draft3 uuid := gen_random_uuid();
  BEGIN
    PERFORM public.insert_ai_assist_draft(
      v_draft3, v_rel, v_user_a, v_target_msg, 'a suggestion for A only',
      '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb
    );
    BEGIN
      PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
      PERFORM public.share_ai_assist_draft(v_draft3);
      PERFORM set_config('request.jwt.claims', NULL, true);
      RAISE EXCEPTION 'EXPLOIT: user_b shared user_a''s draft';
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('request.jwt.claims', NULL, true);
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    END;
    IF EXISTS (SELECT 1 FROM public.ai_assist_drafts WHERE id = v_draft3 AND shared_message_id IS NOT NULL) THEN
      RAISE EXCEPTION 'EXPLOIT: wrong-requester share attempt still marked the draft shared';
    END IF;
  END;

  -----------------------------------------------------------------------
  -- Contract 4: share_ai_assist_draft is rejected once expires_at has
  -- passed. insert_ai_assist_draft always stamps now()+15min, so seed
  -- this one directly to backdate created_at/expires_at.
  -----------------------------------------------------------------------
  DECLARE
    v_draft4 uuid := gen_random_uuid();
  BEGIN
    INSERT INTO public.ai_assist_drafts
      (id, relationship_id, requester_id, target_message_id, reply_text,
       assistant_payload, created_at, expires_at)
    VALUES (v_draft4, v_rel, v_user_a, v_target_msg, 'an expired suggestion',
      '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb,
      now() - interval '20 minutes', now() - interval '5 minutes');

    BEGIN
      PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
      PERFORM public.share_ai_assist_draft(v_draft4);
      PERFORM set_config('request.jwt.claims', NULL, true);
      RAISE EXCEPTION 'EXPLOIT: an expired draft was shared';
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('request.jwt.claims', NULL, true);
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    END;
  END;

  -----------------------------------------------------------------------
  -- Contract 5: share_ai_assist_draft is rejected if the relationship is
  -- no longer active/unarchived at share time.
  -----------------------------------------------------------------------
  DECLARE
    v_rel5 uuid := gen_random_uuid();
    v_target5 uuid := gen_random_uuid();
    v_draft5 uuid := gen_random_uuid();
  BEGIN
    INSERT INTO public.relationships (id, user_a, user_b, status)
    VALUES (v_rel5, v_user_a, v_user_b, 'active');
    INSERT INTO public.messages (id, relationship_id, sender_id,
      client_message_id, content, source)
    VALUES (v_target5, v_rel5, v_user_b, gen_random_uuid(), 'plan something?', 'native');

    PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
    PERFORM public.record_ai_processing_consent(v_rel5, 'granted', gen_random_uuid());
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
    PERFORM public.record_ai_processing_consent(v_rel5, 'granted', gen_random_uuid());
    PERFORM set_config('request.jwt.claims', NULL, true);

    PERFORM public.insert_ai_assist_draft(
      v_draft5, v_rel5, v_user_a, v_target5, 'a suggestion before archiving',
      '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb
    );

    UPDATE public.relationships SET chat_archived_at = now() WHERE id = v_rel5;

    BEGIN
      PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
      PERFORM public.share_ai_assist_draft(v_draft5);
      PERFORM set_config('request.jwt.claims', NULL, true);
      RAISE EXCEPTION 'EXPLOIT: a draft was shared after its relationship was archived';
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('request.jwt.claims', NULL, true);
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    END;
  END;

  -----------------------------------------------------------------------
  -- Contract 6: share_ai_assist_draft is rejected if the target message
  -- was deleted after the draft was created but before Share was tapped.
  -----------------------------------------------------------------------
  DECLARE
    v_target6 uuid := gen_random_uuid();
    v_draft6 uuid := gen_random_uuid();
  BEGIN
    INSERT INTO public.messages (id, relationship_id, sender_id,
      client_message_id, content, source)
    VALUES (v_target6, v_rel, v_user_b, gen_random_uuid(), 'to be deleted', 'native');
    PERFORM public.insert_ai_assist_draft(
      v_draft6, v_rel, v_user_a, v_target6, 'a suggestion whose target vanishes',
      '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb
    );
    UPDATE public.messages SET deleted_at = now() WHERE id = v_target6;

    BEGIN
      PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
      PERFORM public.share_ai_assist_draft(v_draft6);
      PERFORM set_config('request.jwt.claims', NULL, true);
      RAISE EXCEPTION 'EXPLOIT: a draft was shared after its target message was deleted';
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('request.jwt.claims', NULL, true);
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    END;
  END;

  -----------------------------------------------------------------------
  -- Contract 7: share_ai_assist_draft is rejected if dual consent is not
  -- currently granted (only one partner has granted, or neither).
  -----------------------------------------------------------------------
  DECLARE
    v_rel7 uuid := gen_random_uuid();
    v_target7 uuid := gen_random_uuid();
    v_draft7 uuid := gen_random_uuid();
  BEGIN
    INSERT INTO public.relationships (id, user_a, user_b, status)
    VALUES (v_rel7, v_user_a, v_user_b, 'active');
    INSERT INTO public.messages (id, relationship_id, sender_id,
      client_message_id, content, source)
    VALUES (v_target7, v_rel7, v_user_b, gen_random_uuid(), 'no consent yet', 'native');

    -- Only user_a has granted; user_b never has for this relationship.
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
    PERFORM public.record_ai_processing_consent(v_rel7, 'granted', gen_random_uuid());
    PERFORM set_config('request.jwt.claims', NULL, true);

    PERFORM public.insert_ai_assist_draft(
      v_draft7, v_rel7, v_user_a, v_target7, 'a suggestion with one-sided consent',
      '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb
    );

    BEGIN
      PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
      PERFORM public.share_ai_assist_draft(v_draft7);
      PERFORM set_config('request.jwt.claims', NULL, true);
      RAISE EXCEPTION 'EXPLOIT: a draft was shared with only one-sided AI-processing consent';
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('request.jwt.claims', NULL, true);
      IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    END;
  END;

  -----------------------------------------------------------------------
  -- Contract 8: calling share_ai_assist_draft twice on the SAME
  -- already-shared draft returns the SAME existing message idempotently
  -- rather than erroring or creating a second message. (v_draft/v_row
  -- from contract 2 above.)
  -----------------------------------------------------------------------
  DECLARE
    v_row8 record;
  BEGIN
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
    SELECT * INTO v_row8 FROM public.share_ai_assist_draft(v_draft);
    PERFORM set_config('request.jwt.claims', NULL, true);
    IF v_row8.id IS DISTINCT FROM v_row.id THEN
      RAISE EXCEPTION 'EXPLOIT: re-sharing an already-shared draft returned a different message id';
    END IF;
    SELECT count(*) INTO v_count FROM public.messages
    WHERE relationship_id = v_rel AND message_origin = 'attune_assist';
    IF v_count IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION 'EXPLOIT: re-sharing an already-shared draft created a second message, count=%', v_count;
    END IF;
  END;

  -----------------------------------------------------------------------
  -- Contract 9: sharing inserts a row that also satisfies the ordinary
  -- enqueue_message_downstream_work trigger's own effects -- a
  -- message_safety_outbox row now exists for the new message, proving
  -- deterministic safety was not bypassed for AI-authored content.
  -----------------------------------------------------------------------
  IF NOT EXISTS (
    SELECT 1 FROM public.message_safety_outbox WHERE message_id = v_row.id
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: sharing an assist draft did not enqueue a message_safety_outbox row';
  END IF;

  -----------------------------------------------------------------------
  -- Contract 10: share_ai_assist_draft never accepts a client-supplied
  -- replacement reply_text/assistant_payload parameter at all -- the
  -- function signature itself only takes p_draft_id.
  -----------------------------------------------------------------------
  SELECT pg_get_function_arguments(p.oid) INTO v_argtypes
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'share_ai_assist_draft';
  IF v_argtypes IS DISTINCT FROM 'p_draft_id uuid' THEN
    RAISE EXCEPTION 'EXPLOIT: share_ai_assist_draft''s signature is not exactly (p_draft_id uuid), got (%)', v_argtypes;
  END IF;

  RAISE NOTICE 'ai assist draft share contracts: all held';
END $$;
