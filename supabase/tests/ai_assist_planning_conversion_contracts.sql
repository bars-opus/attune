-- create_planning_from_assist_message contracts (Plan A, Task 7). Spec
-- §5.4.
-- Run: psql -q -d attune_test -f supabase/tests/ai_assist_planning_conversion_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a7000000-0000-0000-0000-000000000001';
  v_user_a uuid := 'a7000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a7000000-0000-0000-0000-00000000000b';
  v_user_c uuid := 'a7000000-0000-0000-0000-00000000000c';
  v_task_msg uuid;
  v_event_msg uuid;
  v_user_msg uuid;
  v_no_proposal_msg uuid;
  v_row record;
  v_count int;
  v_link record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'ai7_a@t.test'), (v_user_b, 'ai7_b@t.test'), (v_user_c, 'ai7_c@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550007001', 'A'), (v_user_b, '+15550007002', 'B'),
    (v_user_c, '+15550007003', 'C')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  -- v_user_c is deliberately NOT a member of v_rel -- used for contract 6
  -- (non-member caller rejection).

  -----------------------------------------------------------------------
  -- Contract 1: a shared Assist message's Task proposal creates exactly
  -- one planning_items row and one ai_assist_planning_links row.
  -----------------------------------------------------------------------
  v_task_msg := gen_random_uuid();
  INSERT INTO public.messages (
    id, relationship_id, sender_id, client_message_id, content,
    message_origin, assistant_payload, is_system_notice,
    message_analysis_skipped, source
  ) VALUES (
    v_task_msg, v_rel, v_user_a, gen_random_uuid(), 'How about a picnic?',
    'attune_assist',
    '{"schema_version":1,"suggested_planning_item":{"kind":"task","title":"Plan a picnic","event_date":null},"sources":[]}'::jsonb,
    false, true, 'native'
  );

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
  SELECT * INTO v_row FROM public.create_planning_from_assist_message(v_task_msg, NULL, NULL);
  PERFORM set_config('request.jwt.claims', NULL, true);

  IF v_row.planning_item_id IS NULL OR v_row.planning_event_id IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: task proposal did not return a planning_item_id (item=%, event=%)',
      v_row.planning_item_id, v_row.planning_event_id;
  END IF;
  SELECT count(*) INTO v_count FROM public.planning_items WHERE id = v_row.planning_item_id;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: expected exactly one planning_items row, got %', v_count;
  END IF;
  SELECT count(*) INTO v_count FROM public.ai_assist_planning_links WHERE message_id = v_task_msg;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: expected exactly one ai_assist_planning_links row, got %', v_count;
  END IF;
  SELECT * INTO v_link FROM public.ai_assist_planning_links WHERE message_id = v_task_msg;
  IF v_link.planning_item_id IS DISTINCT FROM v_row.planning_item_id THEN
    RAISE EXCEPTION 'EXPLOIT: link row planning_item_id does not match RPC return';
  END IF;

  -----------------------------------------------------------------------
  -- Contract 2: an Event proposal creates a planning_events row.
  -----------------------------------------------------------------------
  v_event_msg := gen_random_uuid();
  INSERT INTO public.messages (
    id, relationship_id, sender_id, client_message_id, content,
    message_origin, assistant_payload, is_system_notice,
    message_analysis_skipped, source
  ) VALUES (
    v_event_msg, v_rel, v_user_a, gen_random_uuid(), 'Movie night?',
    'attune_assist',
    '{"schema_version":1,"suggested_planning_item":{"kind":"event","title":"Movie night","event_date":"2026-10-01"},"sources":[]}'::jsonb,
    false, true, 'native'
  );

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  SELECT * INTO v_row FROM public.create_planning_from_assist_message(v_event_msg, NULL, NULL);
  PERFORM set_config('request.jwt.claims', NULL, true);

  IF v_row.planning_event_id IS NULL OR v_row.planning_item_id IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: event proposal did not return a planning_event_id (item=%, event=%)',
      v_row.planning_item_id, v_row.planning_event_id;
  END IF;
  SELECT count(*) INTO v_count FROM public.planning_events WHERE id = v_row.planning_event_id;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: expected exactly one planning_events row, got %', v_count;
  END IF;

  -----------------------------------------------------------------------
  -- Contract 3: a message with message_origin != 'attune_assist' is
  -- rejected.
  -----------------------------------------------------------------------
  v_user_msg := gen_random_uuid();
  INSERT INTO public.messages (
    id, relationship_id, sender_id, client_message_id, content, source
  ) VALUES (
    v_user_msg, v_rel, v_user_a, gen_random_uuid(), 'just a regular message', 'native'
  );

  BEGIN
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
    PERFORM public.create_planning_from_assist_message(v_user_msg, NULL, NULL);
    PERFORM set_config('request.jwt.claims', NULL, true);
    RAISE EXCEPTION 'EXPLOIT: a non-attune_assist message was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN
      PERFORM set_config('request.jwt.claims', NULL, true);
      RAISE;
    END IF;
    PERFORM set_config('request.jwt.claims', NULL, true);
  END;

  -----------------------------------------------------------------------
  -- Contract 4: a message with no suggested_planning_item is rejected.
  -----------------------------------------------------------------------
  v_no_proposal_msg := gen_random_uuid();
  INSERT INTO public.messages (
    id, relationship_id, sender_id, client_message_id, content,
    message_origin, assistant_payload, is_system_notice,
    message_analysis_skipped, source
  ) VALUES (
    v_no_proposal_msg, v_rel, v_user_a, gen_random_uuid(), 'Here are a few cafe options nearby: X, Y',
    'attune_assist',
    '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb,
    false, true, 'native'
  );

  BEGIN
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
    PERFORM public.create_planning_from_assist_message(v_no_proposal_msg, NULL, NULL);
    PERFORM set_config('request.jwt.claims', NULL, true);
    RAISE EXCEPTION 'EXPLOIT: a message with no Planning proposal was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN
      PERFORM set_config('request.jwt.claims', NULL, true);
      RAISE;
    END IF;
    PERFORM set_config('request.jwt.claims', NULL, true);
  END;

  -----------------------------------------------------------------------
  -- Contract 5 (sequential half -- the real overlapping-transaction test
  -- is driven separately via two psql processes, see
  -- ai_assist_planning_conversion_race.sh): calling this RPC twice for
  -- the SAME message sequentially creates exactly one Planning entity,
  -- and the second call returns the SAME link, not a new one.
  -----------------------------------------------------------------------
  DECLARE
    v_task_msg_2 uuid := gen_random_uuid();
    v_row2 record;
  BEGIN
    INSERT INTO public.messages (
      id, relationship_id, sender_id, client_message_id, content,
      message_origin, assistant_payload, is_system_notice,
      message_analysis_skipped, source
    ) VALUES (
      v_task_msg_2, v_rel, v_user_a, gen_random_uuid(), 'Plan a hike?',
      'attune_assist',
      '{"schema_version":1,"suggested_planning_item":{"kind":"task","title":"Plan a hike","event_date":null},"sources":[]}'::jsonb,
      false, true, 'native'
    );

    PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
    SELECT * INTO v_row FROM public.create_planning_from_assist_message(v_task_msg_2, NULL, NULL);
    PERFORM set_config('request.jwt.claims', NULL, true);

    PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
    SELECT * INTO v_row2 FROM public.create_planning_from_assist_message(v_task_msg_2, NULL, NULL);
    PERFORM set_config('request.jwt.claims', NULL, true);

    IF v_row2.planning_item_id IS DISTINCT FROM v_row.planning_item_id THEN
      RAISE EXCEPTION 'EXPLOIT: second sequential call for the same message returned a DIFFERENT planning_item_id (% vs %)',
        v_row.planning_item_id, v_row2.planning_item_id;
    END IF;
    SELECT count(*) INTO v_count FROM public.planning_items
    WHERE relationship_id = v_rel AND title = 'Plan a hike';
    IF v_count IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION 'EXPLOIT: two sequential calls created % planning_items rows instead of 1', v_count;
    END IF;
    SELECT count(*) INTO v_count FROM public.ai_assist_planning_links WHERE message_id = v_task_msg_2;
    IF v_count IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION 'EXPLOIT: two sequential calls created % link rows instead of 1', v_count;
    END IF;
  END;

  -----------------------------------------------------------------------
  -- Contract 6: a caller who is not a member of the message's
  -- relationship is rejected.
  -----------------------------------------------------------------------
  BEGIN
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_c), true);
    PERFORM public.create_planning_from_assist_message(v_task_msg, NULL, NULL);
    PERFORM set_config('request.jwt.claims', NULL, true);
    RAISE EXCEPTION 'EXPLOIT: a non-member caller was allowed to convert a Planning proposal';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN
      PERFORM set_config('request.jwt.claims', NULL, true);
      RAISE;
    END IF;
    PERFORM set_config('request.jwt.claims', NULL, true);
  END;

  -----------------------------------------------------------------------
  -- Contract 7: edited title/date are validated through the SAME
  -- constraints Planning's own create_planning_task/upsert_planning_event
  -- RPCs enforce -- a blank-after-trim title is rejected here too.
  -----------------------------------------------------------------------
  DECLARE
    v_task_msg_3 uuid := gen_random_uuid();
  BEGIN
    INSERT INTO public.messages (
      id, relationship_id, sender_id, client_message_id, content,
      message_origin, assistant_payload, is_system_notice,
      message_analysis_skipped, source
    ) VALUES (
      v_task_msg_3, v_rel, v_user_a, gen_random_uuid(), 'Plan a trip?',
      'attune_assist',
      '{"schema_version":1,"suggested_planning_item":{"kind":"task","title":"Plan a trip","event_date":null},"sources":[]}'::jsonb,
      false, true, 'native'
    );

    BEGIN
      PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
      PERFORM public.create_planning_from_assist_message(v_task_msg_3, '   ', NULL);
      PERFORM set_config('request.jwt.claims', NULL, true);
      RAISE EXCEPTION 'EXPLOIT: a blank-after-trim edited title was accepted';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'EXPLOIT:%' THEN
        PERFORM set_config('request.jwt.claims', NULL, true);
        RAISE;
      END IF;
      PERFORM set_config('request.jwt.claims', NULL, true);
    END;

    -- Confirm no orphan row: the blank-title attempt above must not have
    -- created a planning_items row despite raising.
    SELECT count(*) INTO v_count FROM public.planning_items
    WHERE relationship_id = v_rel AND title = '';
    IF v_count IS DISTINCT FROM 0 THEN
      RAISE EXCEPTION 'EXPLOIT: a blank-titled planning_items row was created despite the rejection';
    END IF;
    SELECT count(*) INTO v_count FROM public.ai_assist_planning_links WHERE message_id = v_task_msg_3;
    IF v_count IS DISTINCT FROM 0 THEN
      RAISE EXCEPTION 'EXPLOIT: a link row was created despite the title rejection';
    END IF;

    -- A valid edited title/date DOES take effect.
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
    SELECT * INTO v_row FROM public.create_planning_from_assist_message(v_task_msg_3, '  Plan the Portugal trip  ', '2026-11-15');
    PERFORM set_config('request.jwt.claims', NULL, true);

    IF v_row.planning_item_id IS NULL THEN
      RAISE EXCEPTION 'EXPLOIT: valid edited title/date was rejected';
    END IF;
    SELECT * INTO v_link FROM public.planning_items WHERE id = v_row.planning_item_id;
    IF v_link.title IS DISTINCT FROM 'Plan the Portugal trip' OR v_link.due_date IS DISTINCT FROM '2026-11-15'::date THEN
      RAISE EXCEPTION 'EXPLOIT: edited title/date did not take effect (title=%, due_date=%)',
        v_link.title, v_link.due_date;
    END IF;
  END;

  RAISE NOTICE 'ai assist planning conversion contracts: all held';
END;
$$;
