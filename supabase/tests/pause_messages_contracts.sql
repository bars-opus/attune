-- supabase/tests/pause_messages_contracts.sql
-- Spec 8 (research 06 B3 (a), 05 Part C; plan review C2, I4, M3): "Take a
-- pause" sends one of three fixed messages as an ordinary message the AI
-- never reads; the partner may answer once, with one fixed line, within an
-- hour and before they have written anything else. Nothing is counted.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('9fd00000-0000-0000-0000-0000000000a1'), ('9fd00000-0000-0000-0000-0000000000b2'),
  ('9fd00000-0000-0000-0000-0000000000c3'), ('9fd00000-0000-0000-0000-0000000000d4'),
  ('9fd00000-0000-0000-0000-0000000000e5')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9fd00000-0000-0000-0000-0000000000a1', '+233599620001', 'Ama'),
  ('9fd00000-0000-0000-0000-0000000000b2', '+233599620002', 'Kofi'),
  ('9fd00000-0000-0000-0000-0000000000c3', '+233599620003', 'Stranger'),
  ('9fd00000-0000-0000-0000-0000000000d4', '+233599620004', 'Pat'),
  ('9fd00000-0000-0000-0000-0000000000e5', '+233599620005', 'Pip')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('9fd10000-0000-0000-0000-000000000001', '9fd00000-0000-0000-0000-0000000000a1', '9fd00000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE - 50, now() - interval '50 days', now()),
  ('9fd10000-0000-0000-0000-000000000002', '9fd00000-0000-0000-0000-0000000000d4', '9fd00000-0000-0000-0000-0000000000e5', 'paused', CURRENT_DATE - 50, now() - interval '50 days', now());

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- Expects the call to raise exactly p_code.
CREATE FUNCTION pg_temp.refused(p_user uuid, p_sql text, p_code text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_msg text;
BEGIN
  PERFORM pg_temp.as_user(p_user);
  BEGIN
    EXECUTE p_sql;
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: accepted: %', p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    RESET ROLE;
    IF v_msg LIKE 'CONTRACT VIOLATED%' OR v_msg <> p_code THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % gave "%" (want %)', p_sql, v_msg, p_code;
    END IF;
  END;
END $$;

CREATE FUNCTION pg_temp.reply_state(p_user uuid, p_pause uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  PERFORM pg_temp.as_user(p_user);
  v := public.pause_reply_state(p_pause);
  RESET ROLE;
  RETURN v;
END $$;

DO $$
DECLARE
  v_rel uuid := '9fd10000-0000-0000-0000-000000000001';
  v_paused uuid := '9fd10000-0000-0000-0000-000000000002';
  v_a uuid := '9fd00000-0000-0000-0000-0000000000a1';
  v_b uuid := '9fd00000-0000-0000-0000-0000000000b2';
  v_c uuid := '9fd00000-0000-0000-0000-0000000000c3';
  v_d uuid := '9fd00000-0000-0000-0000-0000000000d4';
  v_p1 uuid; v_p1b uuid; v_p2 uuid; v_p3 uuid; v_p4 uuid; v_r1 uuid; v_r1b uuid;
  v_plain uuid; r record; v_fn text;
BEGIN
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, created_at)
  VALUES (v_rel, v_a, gen_random_uuid(), 'an ordinary message', now() - interval '20 minutes')
  RETURNING id INTO v_plain;
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'conflict_toolkit') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: conflict_toolkit not seeded off';
  END IF;
  -- The server refuses while the flag is off (sync_fixes_contracts); on
  -- for the rest of this file.
  UPDATE public.feature_flags SET enabled = true WHERE key IN ('conflict_toolkit', 'private_safety_check');
  FOREACH v_fn IN ARRAY ARRAY['public.send_pause(uuid,uuid,integer)',
                              'public.send_pause_reply(uuid,uuid)',
                              'public.pause_reply_state(uuid)'] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: grants on %', v_fn;
    END IF;
  END LOOP;
  -- Nothing counts pauses.
  IF EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace = 'public'::regnamespace
             AND proname ~ 'pause' AND (proname ~ 'count' OR proname ~ 'total' OR proname ~ 'history')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a counting function exists';
  END IF;

  -- 1. Fixed texts only: the client sends a variant, never words.
  PERFORM pg_temp.as_user(v_a);
  v_p1 := public.send_pause(v_rel, '9fd20000-0000-0000-0000-000000000001', 1);
  v_p1b := public.send_pause(v_rel, '9fd20000-0000-0000-0000-000000000001', 1);
  RESET ROLE;
  IF v_p1 IS DISTINCT FROM v_p1b THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: send_pause is not idempotent';
  END IF;
  SELECT * INTO r FROM public.messages WHERE id = v_p1;
  IF r.content <> 'I''m getting flooded. I''m stepping back for 30 minutes, not away from you. I''ll come back.'
     OR r.media_type <> 'pause' OR r.message_analysis_skipped IS NOT TRUE
     OR r.is_system_notice OR r.source <> 'native' OR r.sender_id <> v_a THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pause row %', row_to_json(r);
  END IF;
  PERFORM pg_temp.refused(v_a, format('SELECT public.send_pause(%L, %L, 4)', v_rel, gen_random_uuid()), 'pause:invalid');
  PERFORM pg_temp.refused(v_a, format('SELECT public.send_pause(%L, %L, 0)', v_rel, gen_random_uuid()), 'pause:invalid');
  PERFORM pg_temp.as_user(v_a);
  v_p2 := public.send_pause(v_rel, gen_random_uuid(), 2);
  v_p3 := public.send_pause(v_rel, gen_random_uuid(), 3);
  RESET ROLE;
  -- Ordered in time (one transaction shares now()).
  UPDATE public.messages SET created_at = now() - interval '10 minutes' WHERE id = v_p1;
  UPDATE public.messages SET created_at = now() - interval '9 minutes' WHERE id = v_p2;
  UPDATE public.messages SET created_at = now() - interval '8 minutes' WHERE id = v_p3;
  IF (SELECT count(DISTINCT content) FROM public.messages WHERE id IN (v_p1, v_p2, v_p3)) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the three variants are not three texts';
  END IF;
  -- Each names a return in the 20-45 minute range.
  IF EXISTS (SELECT 1 FROM public.messages WHERE id IN (v_p1, v_p2, v_p3)
             AND content !~ '(20|25|30|35|40|45) minutes') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pause names no return';
  END IF;

  -- 2. Active relationship only; members only.
  PERFORM pg_temp.refused(v_c, format('SELECT public.send_pause(%L, %L, 1)', v_rel, gen_random_uuid()), 'pause:not_allowed');
  PERFORM pg_temp.refused(v_d, format('SELECT public.send_pause(%L, %L, 1)', v_paused, gen_random_uuid()), 'pause:not_allowed');
  UPDATE public.relationships SET chat_archived_at = now() WHERE id = v_rel;
  PERFORM pg_temp.refused(v_a, format('SELECT public.send_pause(%L, %L, 1)', v_rel, gen_random_uuid()), 'pause:not_allowed');
  UPDATE public.relationships SET chat_archived_at = NULL WHERE id = v_rel;

  -- 3. A client cannot forge either type, by insert or by update.
  PERFORM pg_temp.refused(v_a, format(
    'INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, media_type) VALUES (%L, %L, %L, %L, %L)',
    v_rel, v_a, gen_random_uuid(), 'hi', 'pause'), 'pause:server_only');
  PERFORM pg_temp.refused(v_b, format(
    'INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, media_type, reply_to_message_id) VALUES (%L, %L, %L, %L, %L, %L)',
    v_rel, v_b, gen_random_uuid(), 'Okay. I''ll be here.', 'pause_reply', v_p1), 'pause:server_only');
  BEGIN
    UPDATE public.messages SET media_type = 'pause' WHERE id = v_plain;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a message was turned into a pause';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'pause:server_only' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.messages SET media_type = 'pause_reply' WHERE id = v_plain;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a message was turned into a pause reply';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'pause:server_only' THEN RAISE; END IF;
  END;

  -- 4. Never edited.
  PERFORM pg_temp.refused(v_a, format('SELECT public.edit_message(%L, %L)', v_p1, 'changed'), 'not_editable');

  -- 5. The reply: the recipient only, once, with the one fixed line.
  IF pg_temp.reply_state(v_a, v_p1) <> 'unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sender can answer their own pause';
  END IF;
  IF pg_temp.reply_state(v_c, v_p1) <> 'unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider sees a reply state';
  END IF;
  -- p3 is the sender's latest message: only "not your own pause" stops it.
  IF pg_temp.reply_state(v_a, v_p3) <> 'unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sender can answer their latest pause';
  END IF;
  PERFORM pg_temp.refused(v_a, format('SELECT public.send_pause_reply(%L, %L)', v_p3, gen_random_uuid()), 'pause:not_allowed');
  -- The hour, while the recipient has written nothing at all.
  UPDATE public.messages SET created_at = now() - interval '61 minutes' WHERE id = v_p1;
  IF pg_temp.reply_state(v_b, v_p1) <> 'unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: answerable after an hour';
  END IF;
  PERFORM pg_temp.refused(v_b, format('SELECT public.send_pause_reply(%L, %L)', v_p1, gen_random_uuid()), 'pause:not_allowed');
  UPDATE public.messages SET created_at = now() - interval '10 minutes' WHERE id = v_p1;
  IF pg_temp.reply_state(v_b, v_p1) <> 'available' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the recipient cannot answer';
  END IF;
  PERFORM pg_temp.refused(v_a, format('SELECT public.send_pause_reply(%L, %L)', v_p1, gen_random_uuid()), 'pause:not_allowed');
  PERFORM pg_temp.refused(v_c, format('SELECT public.send_pause_reply(%L, %L)', v_p1, gen_random_uuid()), 'pause:not_allowed');
  PERFORM pg_temp.as_user(v_b);
  v_r1 := public.send_pause_reply(v_p1, '9fd20000-0000-0000-0000-0000000000f1');
  v_r1b := public.send_pause_reply(v_p1, '9fd20000-0000-0000-0000-0000000000f1');
  RESET ROLE;
  IF v_r1 IS DISTINCT FROM v_r1b THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: send_pause_reply is not idempotent';
  END IF;
  SELECT * INTO r FROM public.messages WHERE id = v_r1;
  IF r.content <> 'Okay. I''ll be here.' OR r.media_type <> 'pause_reply'
     OR r.reply_to_message_id <> v_p1 OR r.message_analysis_skipped IS NOT TRUE OR r.sender_id <> v_b THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: reply row %', row_to_json(r);
  END IF;
  PERFORM pg_temp.refused(v_b, format('SELECT public.send_pause_reply(%L, %L)', v_p1, gen_random_uuid()), 'pause:not_allowed');
  IF pg_temp.reply_state(v_b, v_p1) <> 'unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second reply is offered';
  END IF;
  PERFORM pg_temp.refused(v_b, format('SELECT public.edit_message(%L, %L)', v_r1, 'changed'), 'not_editable');

  -- 6. Not once the recipient has written anything since the pause
  --    (v_b's reply above was after v_p2 and v_p3 too).
  IF pg_temp.reply_state(v_b, v_p2) <> 'unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: offered after the recipient wrote';
  END IF;
  PERFORM pg_temp.refused(v_b, format('SELECT public.send_pause_reply(%L, %L)', v_p2, gen_random_uuid()), 'pause:not_allowed');

  -- 7. Not after an hour.
  PERFORM pg_temp.as_user(v_a);
  v_p4 := public.send_pause(v_rel, gen_random_uuid(), 1);
  RESET ROLE;
  UPDATE public.messages SET created_at = now() + interval '1 second' WHERE id = v_p4;
  IF pg_temp.reply_state(v_b, v_p4) <> 'available' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh pause is not answerable';
  END IF;
  UPDATE public.messages SET created_at = now() - interval '61 minutes' WHERE id = v_p4;
  IF pg_temp.reply_state(v_b, v_p4) <> 'unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: answerable after an hour';
  END IF;
  PERFORM pg_temp.refused(v_b, format('SELECT public.send_pause_reply(%L, %L)', v_p4, gen_random_uuid()), 'pause:not_allowed');
  UPDATE public.messages SET created_at = now() + interval '1 second' WHERE id = v_p4;

  -- 8. Final review I-5: the reply chip does NOT depend on the recipient's
  --    private check. Gating it let whoever holds her phone probe the check
  --    (send a pause, look for the chip); the fixed, ignorable line is not
  --    a conjoint step worth that tell. Nothing about the check reaches it.
  INSERT INTO public.safety_self_checks (user_id, relationship_id, answered_at, until, positive_until)
  VALUES (v_b, v_rel, now(), now() + interval '180 days', now() + interval '180 days');
  IF pg_temp.reply_state(v_b, v_p4) <> 'available' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the chip reveals the recipient''s positive check (I-5)';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace = 'public'::regnamespace
             AND proname IN ('pause_reply_allowed', 'pause_reply_state', 'send_pause_reply')
             AND prosrc ~ '(safety_self_checks|user_safety_flagged|relationship_ai_suppressed)') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pause function reads safety state';
  END IF;
  -- ...and the sender's tools are untouched by their partner's check (C1).
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.send_pause(v_rel, gen_random_uuid(), 2);
  RESET ROLE;
  DELETE FROM public.safety_self_checks WHERE user_id = v_b;
  -- v_a's new pause is newer than v_p4; v_b has still written nothing.
  IF pg_temp.reply_state(v_b, v_p4) <> 'available' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the chip changed with the check';
  END IF;

  -- 9. A deleted pause cannot be answered.
  UPDATE public.messages SET deleted_at = now() WHERE id = v_p4;
  IF pg_temp.reply_state(v_b, v_p4) <> 'unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted pause is answerable';
  END IF;
  UPDATE public.messages SET deleted_at = NULL WHERE id = v_p4;

  -- 10. Not in an archived chat.
  UPDATE public.relationships SET chat_archived_at = now() WHERE id = v_rel;
  IF pg_temp.reply_state(v_b, v_p4) <> 'unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: answerable in an archived chat';
  END IF;
  UPDATE public.relationships SET chat_archived_at = NULL WHERE id = v_rel;

  -- 11. One reply per pause, even past the RPC.
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public'
                 AND indexname = 'messages_one_pause_reply_idx') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no unique index on pause replies';
  END IF;

  -- 12. Only a pause can be answered this way.
  PERFORM pg_temp.refused(v_b, format('SELECT public.send_pause_reply(%L, %L)', v_plain,
    gen_random_uuid()), 'pause:not_allowed');
END $$;

ROLLBACK;
