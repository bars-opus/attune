-- edit_message / delete_message contracts for Attune Assist messages
-- (AI Assistant Plan A, Task 8). Spec §5.3: Assist messages "may be
-- deleted under the existing five-minute sender rule but may not be
-- edited in place."
--
-- No prior SQL test file covered edit_message/delete_message at all
-- (grepped supabase/tests/ for both names -- only a passing mention in
-- realtime_publication_test.sql, no dedicated contracts file) so this is
-- a new file, not an extension of an existing one.
--
-- Run: psql -q -d attune_test -f supabase/tests/message_edit_delete_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a8000000-0000-0000-0000-000000000001';
  v_user_a uuid := 'a8000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a8000000-0000-0000-0000-00000000000b';
  v_assist_msg uuid;
  v_user_msg uuid;
  v_converted_msg uuid;
  v_item_id uuid;
  v_row record;
  v_count int;
  v_msg record;
  v_link_count int;
  v_item_deleted_at timestamptz;
  v_err_caught boolean;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'ai8_a@t.test'), (v_user_b, 'ai8_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550008001', 'A'), (v_user_b, '+15550008002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -----------------------------------------------------------------------
  -- Contract 1: edit_message on an attune_assist message is rejected
  -- regardless of sender/time-window, with a clear error.
  -----------------------------------------------------------------------
  v_assist_msg := gen_random_uuid();
  INSERT INTO public.messages (
    id, relationship_id, sender_id, client_message_id, content,
    message_origin, assistant_payload, is_system_notice,
    message_analysis_skipped, source, created_at
  ) VALUES (
    v_assist_msg, v_rel, v_user_a, gen_random_uuid(), 'Here is an idea...',
    'attune_assist',
    '{"schema_version":1,"suggested_planning_item":null,"sources":[]}'::jsonb,
    false, true, 'native', now()
  );

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  v_err_caught := false;
  BEGIN
    PERFORM public.edit_message(v_assist_msg, 'edited content');
  EXCEPTION WHEN OTHERS THEN
    v_err_caught := true;
    IF SQLERRM IS DISTINCT FROM 'assist_message_immutable' THEN
      RAISE EXCEPTION 'EXPLOIT: expected assist_message_immutable, got %', SQLERRM;
    END IF;
  END;
  PERFORM set_config('request.jwt.claims', NULL, true);
  IF NOT v_err_caught THEN
    RAISE EXCEPTION 'EXPLOIT: edit_message succeeded on an attune_assist message';
  END IF;

  SELECT content, edited_at INTO v_msg FROM public.messages WHERE id = v_assist_msg;
  IF v_msg.content IS DISTINCT FROM 'Here is an idea...' OR v_msg.edited_at IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: assist message content/edited_at mutated by rejected edit';
  END IF;

  -- Sanity: an ordinary user message is still editable (no regression).
  v_user_msg := gen_random_uuid();
  INSERT INTO public.messages (
    id, relationship_id, sender_id, client_message_id, content,
    is_system_notice, message_analysis_skipped, source, created_at
  ) VALUES (
    v_user_msg, v_rel, v_user_a, gen_random_uuid(), 'hello there',
    false, true, 'native', now()
  );
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  PERFORM public.edit_message(v_user_msg, 'hello there, edited');
  PERFORM set_config('request.jwt.claims', NULL, true);
  SELECT content INTO v_msg FROM public.messages WHERE id = v_user_msg;
  IF v_msg.content IS DISTINCT FROM 'hello there, edited' THEN
    RAISE EXCEPTION 'REGRESSION: edit_message no longer works for ordinary user messages';
  END IF;

  -----------------------------------------------------------------------
  -- Contract 2: delete_message on an attune_assist message, within the
  -- sender/time window, succeeds and in the SAME transaction clears
  -- assistant_payload, resets message_origin to 'user', and deletes the
  -- ai_assist_planning_links row if one exists (none exists yet here).
  -----------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  PERFORM public.delete_message(v_assist_msg);
  PERFORM set_config('request.jwt.claims', NULL, true);

  SELECT * INTO v_msg FROM public.messages WHERE id = v_assist_msg;
  IF v_msg.deleted_at IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: attune_assist message not soft-deleted';
  END IF;
  IF v_msg.assistant_payload IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: assistant_payload not cleared on delete (shape CHECK would fail otherwise)';
  END IF;
  IF v_msg.message_origin IS DISTINCT FROM 'user' THEN
    RAISE EXCEPTION 'EXPLOIT: message_origin not reset to ''user'' on delete, got %', v_msg.message_origin;
  END IF;
  IF v_msg.content IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: content not cleared on delete';
  END IF;

  -----------------------------------------------------------------------
  -- Contract 3: deleting an Assist message whose proposal was already
  -- converted to a Planning item does NOT delete that Planning item.
  -----------------------------------------------------------------------
  v_converted_msg := gen_random_uuid();
  INSERT INTO public.messages (
    id, relationship_id, sender_id, client_message_id, content,
    message_origin, assistant_payload, is_system_notice,
    message_analysis_skipped, source, created_at
  ) VALUES (
    v_converted_msg, v_rel, v_user_a, gen_random_uuid(), 'How about a picnic?',
    'attune_assist',
    '{"schema_version":1,"suggested_planning_item":{"kind":"task","title":"Plan a picnic","event_date":null},"sources":[]}'::jsonb,
    false, true, 'native', now()
  );

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
  SELECT * INTO v_row FROM public.create_planning_from_assist_message(v_converted_msg, NULL, NULL);
  PERFORM set_config('request.jwt.claims', NULL, true);
  v_item_id := v_row.planning_item_id;
  IF v_item_id IS NULL THEN
    RAISE EXCEPTION 'SETUP FAILURE: expected a planning_items row from conversion';
  END IF;

  SELECT count(*) INTO v_link_count FROM public.ai_assist_planning_links
  WHERE message_id = v_converted_msg;
  IF v_link_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'SETUP FAILURE: expected exactly one link row before delete, got %', v_link_count;
  END IF;

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  PERFORM public.delete_message(v_converted_msg);
  PERFORM set_config('request.jwt.claims', NULL, true);

  SELECT deleted_at INTO v_item_deleted_at FROM public.planning_items WHERE id = v_item_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EXPLOIT: planning_items row was hard-deleted when its Assist message was deleted';
  END IF;
  IF v_item_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: planning_items row was soft-deleted when its Assist message was deleted';
  END IF;

  SELECT count(*) INTO v_link_count FROM public.ai_assist_planning_links
  WHERE message_id = v_converted_msg;
  IF v_link_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'EXPLOIT: ai_assist_planning_links row survived the message delete, got count %', v_link_count;
  END IF;

  -----------------------------------------------------------------------
  -- Contract 4: a retried/duplicate delete call on an already-deleted
  -- Assist message is idempotent -- errors cleanly (not_deletable),
  -- does not re-clear an already-cleared link row (there is none left
  -- to re-clear), does not raise an unexpected error.
  -----------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  v_err_caught := false;
  BEGIN
    PERFORM public.delete_message(v_converted_msg);
  EXCEPTION WHEN OTHERS THEN
    v_err_caught := true;
    IF SQLERRM IS DISTINCT FROM 'not_deletable' THEN
      RAISE EXCEPTION 'EXPLOIT: retried delete raised unexpected error %', SQLERRM;
    END IF;
  END;
  PERFORM set_config('request.jwt.claims', NULL, true);
  IF NOT v_err_caught THEN
    RAISE EXCEPTION 'EXPLOIT: retried delete on an already-deleted message did not error';
  END IF;

  -- Still idempotent: no link row exists, no planning_items row touched.
  SELECT count(*) INTO v_link_count FROM public.ai_assist_planning_links
  WHERE message_id = v_converted_msg;
  IF v_link_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'EXPLOIT: retried delete resurrected or duplicated a link row';
  END IF;
  SELECT deleted_at INTO v_item_deleted_at FROM public.planning_items WHERE id = v_item_id;
  IF NOT FOUND OR v_item_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: retried delete affected the planning_items row';
  END IF;

  -- Also retry the delete on the non-converted Assist message from
  -- contract 2 -- confirms the general (no-link-ever-existed) idempotent
  -- path is clean too.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  v_err_caught := false;
  BEGIN
    PERFORM public.delete_message(v_assist_msg);
  EXCEPTION WHEN OTHERS THEN
    v_err_caught := true;
    IF SQLERRM IS DISTINCT FROM 'not_deletable' THEN
      RAISE EXCEPTION 'EXPLOIT: retried delete (no-link case) raised unexpected error %', SQLERRM;
    END IF;
  END;
  PERFORM set_config('request.jwt.claims', NULL, true);
  IF NOT v_err_caught THEN
    RAISE EXCEPTION 'EXPLOIT: retried delete (no-link case) did not error';
  END IF;

  RAISE NOTICE 'message_edit_delete_contracts.sql: all contracts passed';
END $$;
