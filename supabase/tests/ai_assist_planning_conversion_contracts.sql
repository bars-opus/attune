-- Ask Attune "Add to Planning" on the new Planning model (spec §16).
-- Run: psql -q -d attune_planning -f supabase/tests/ai_assist_planning_conversion_contracts.sql
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := 'a7000000-0000-0000-0000-000000000001';
  v_user_a uuid := 'a7000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a7000000-0000-0000-0000-00000000000b';
  v_user_c uuid := 'a7000000-0000-0000-0000-00000000000c';
  v_task_msg uuid := gen_random_uuid();
  v_event_msg uuid := gen_random_uuid();
  v_user_msg uuid := gen_random_uuid();
  v_no_proposal_msg uuid := gen_random_uuid();
  v_edit_msg uuid := gen_random_uuid();
  v_entry uuid;
  v_again uuid;
  v_everyday uuid;
  v_n int;

BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'ai7_a@t.test'), (v_user_b, 'ai7_b@t.test'), (v_user_c, 'ai7_c@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550007001', 'A'), (v_user_b, '+15550007002', 'B'), (v_user_c, '+15550007003', 'C')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active') ON CONFLICT DO NOTHING;

  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content,
    message_origin, assistant_payload, is_system_notice, message_analysis_skipped, source)
  VALUES
    (v_task_msg, v_rel, v_user_a, gen_random_uuid(), 'How about a picnic?', 'attune_assist',
     '{"schema_version":1,"suggested_planning_item":{"kind":"task","title":"Plan a picnic","event_date":null},"sources":[]}',
     false, true, 'native'),
    (v_event_msg, v_rel, v_user_a, gen_random_uuid(), 'Dinner Friday?', 'attune_assist',
     '{"schema_version":1,"suggested_planning_item":{"kind":"event","title":"Dinner at Azmera","event_date":"2026-11-06"},"sources":[]}',
     false, true, 'native'),
    (v_user_msg, v_rel, v_user_a, gen_random_uuid(), 'just me typing', 'user', NULL, false, false, 'native'),
    (v_no_proposal_msg, v_rel, v_user_a, gen_random_uuid(), 'No plan here', 'attune_assist',
     '{"schema_version":1,"suggested_planning_item":null,"sources":[]}', false, true, 'native'),
    (v_edit_msg, v_rel, v_user_a, gen_random_uuid(), 'Book tickets', 'attune_assist',
     '{"schema_version":1,"suggested_planning_item":{"kind":"task","title":"Book tickets","event_date":null},"sources":[]}',
     false, true, 'native');

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 1: a task proposal becomes an Everyday plan holding one to-do.
  SELECT planning_entry_id INTO v_entry FROM public.create_planning_from_assist_message(v_task_msg, NULL, NULL);
  IF v_entry IS NULL THEN RAISE EXCEPTION 'EXPLOIT: task proposal returned no plan'; END IF;
  SELECT c.id INTO v_everyday FROM public.planning_categories c
  WHERE c.relationship_id = v_rel AND c.seed_key = 'everyday';
  IF NOT EXISTS (SELECT 1 FROM public.planning_entries
                 WHERE id = v_entry AND category_id = v_everyday AND title = 'Plan a picnic' AND NOT is_template) THEN
    RAISE EXCEPTION 'EXPLOIT: task plan is not an Everyday plan titled with the task';
  END IF;
  SELECT count(*) INTO v_n FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
  WHERE b.entry_id = v_entry AND b.block_type = 'checklist' AND i.text = 'Plan a picnic' AND i.deleted_at IS NULL;
  IF v_n <> 1 THEN RAISE EXCEPTION 'EXPLOIT: task plan should hold exactly one to-do, got %', v_n; END IF;
  IF (SELECT planning_entry_id FROM public.ai_assist_planning_links WHERE message_id = v_task_msg) IS DISTINCT FROM v_entry THEN
    RAISE EXCEPTION 'EXPLOIT: link row does not point at the created plan';
  END IF;

  -- Contract 2: an event proposal becomes an Everyday plan with a Date block.
  SELECT planning_entry_id INTO v_entry FROM public.create_planning_from_assist_message(v_event_msg, NULL, NULL);
  IF NOT EXISTS (SELECT 1 FROM public.planning_blocks
                 WHERE entry_id = v_entry AND block_type = 'date' AND date_start = '2026-11-06' AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'EXPLOIT: event plan has no Date block on its date';
  END IF;

  -- Contract 3: only Attune Assist messages convert.
  BEGIN
    PERFORM public.create_planning_from_assist_message(v_user_msg, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: a non-Assist message was converted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF; END;

  -- Contract 4: a message without a proposal is refused.
  BEGIN
    PERFORM public.create_planning_from_assist_message(v_no_proposal_msg, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: a message with no proposal was converted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF; END;

  -- Contract 5 (Review Focus 1): converting twice returns the same plan, creates nothing new.
  SELECT count(*) INTO v_n FROM public.planning_entries WHERE relationship_id = v_rel AND NOT is_template;
  SELECT planning_entry_id INTO v_again FROM public.create_planning_from_assist_message(v_task_msg, NULL, NULL);
  IF v_again IS DISTINCT FROM (SELECT planning_entry_id FROM public.ai_assist_planning_links WHERE message_id = v_task_msg) THEN
    RAISE EXCEPTION 'EXPLOIT: a second conversion returned a different plan';
  END IF;
  IF (SELECT count(*) FROM public.planning_entries WHERE relationship_id = v_rel AND NOT is_template) <> v_n THEN
    RAISE EXCEPTION 'EXPLOIT: a second conversion created another plan';
  END IF;

  -- Contract 6: a non-member cannot convert.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_c), true);
  BEGIN
    PERFORM public.create_planning_from_assist_message(v_edit_msg, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: a non-member converted a proposal';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 7: an edited title and date are used; a blank title is refused and leaves nothing behind.
  BEGIN
    PERFORM public.create_planning_from_assist_message(v_edit_msg, '   ', NULL);
    RAISE EXCEPTION 'EXPLOIT: a blank edited title was accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF; END;
  IF EXISTS (SELECT 1 FROM public.ai_assist_planning_links WHERE message_id = v_edit_msg) THEN
    RAISE EXCEPTION 'EXPLOIT: a link row survived a refused conversion';
  END IF;
  SELECT planning_entry_id INTO v_entry
  FROM public.create_planning_from_assist_message(v_edit_msg, 'Book train tickets', '2026-12-01');
  IF NOT EXISTS (SELECT 1 FROM public.planning_entries WHERE id = v_entry AND title = 'Book train tickets') THEN
    RAISE EXCEPTION 'EXPLOIT: edited title not used';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
                 WHERE b.entry_id = v_entry AND i.due_date = '2026-12-01') THEN
    RAISE EXCEPTION 'EXPLOIT: edited date not used as the to-do due date';
  END IF;

  -- Contract 8 (review minor 1): if the plan a suggestion became was deleted,
  -- adding it again makes a fresh plan (and relinks), instead of returning
  -- the dead one forever.
  SELECT planning_entry_id INTO v_entry FROM public.ai_assist_planning_links WHERE message_id = v_task_msg;
  PERFORM public.delete_planning_entry(v_entry);
  -- the chat bubble reads the link to choose "Added" vs "Add": it must go with the plan
  IF EXISTS (SELECT 1 FROM public.ai_assist_planning_links WHERE message_id = v_task_msg) THEN
    RAISE EXCEPTION 'EXPLOIT: the link outlived its deleted plan, so the bubble still says Added';
  END IF;
  SELECT planning_entry_id INTO v_again FROM public.create_planning_from_assist_message(v_task_msg, NULL, NULL);
  IF v_again = v_entry THEN RAISE EXCEPTION 'EXPLOIT: re-adding returned the deleted plan'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.planning_entries WHERE id = v_again AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'EXPLOIT: re-adding did not create a live plan';
  END IF;
  IF (SELECT planning_entry_id FROM public.ai_assist_planning_links WHERE message_id = v_task_msg) <> v_again THEN
    RAISE EXCEPTION 'EXPLOIT: the link still points at the deleted plan';
  END IF;

  RAISE NOTICE 'ai_assist_planning_conversion_contracts: PASS';
END $$;
ROLLBACK;
