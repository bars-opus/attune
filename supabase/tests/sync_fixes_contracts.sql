-- supabase/tests/sync_fixes_contracts.sql
-- Cross-spec sync audit (2026-10-18): the places where one spec's rules
-- had not reached another's.
--   C-2  a pause keeps the couple map's story pins (only an ending clears them)
--   I-4  a pause shows the partner no read tick, while the reader's own badge clears
--   I-7  the unread badge reads 0 in the ended window, where nothing can be marked read
--   M-4  deleted messages and system notices are not unread
--   I-8  nobody in an active relationship can join another (the paused case
--        is refused by accept-invite; see below)
--   M-3  only ordinary messages count toward Ask-2
--   M-6  a quiet person sees no win cards
--   M-7  a pause does not cancel a WhatsApp import or its consent
--   M-2  the export names a pause and its reply
--   M-15 no trigger function is callable by clients
--   F-3  the Spec 7/8 writers refuse while their flags are off (Dart audit)
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('9fa00000-0000-0000-0000-0000000000a1'), ('9fa00000-0000-0000-0000-0000000000b2'),
  ('9fa00000-0000-0000-0000-0000000000c3'), ('9fa00000-0000-0000-0000-0000000000d4'),
  ('9fa00000-0000-0000-0000-0000000000e5'), ('9fa00000-0000-0000-0000-0000000000f6')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9fa00000-0000-0000-0000-0000000000a1', '+233599650001', 'Ama'),
  ('9fa00000-0000-0000-0000-0000000000b2', '+233599650002', 'Kofi'),
  ('9fa00000-0000-0000-0000-0000000000c3', '+233599650003', 'Esi'),
  ('9fa00000-0000-0000-0000-0000000000d4', '+233599650004', 'Yaw'),
  ('9fa00000-0000-0000-0000-0000000000e5', '+233599650005', 'Inviter'),
  ('9fa00000-0000-0000-0000-0000000000f6', '+233599650006', 'Free')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('9fa10000-0000-0000-0000-000000000001', '9fa00000-0000-0000-0000-0000000000a1', '9fa00000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE - 60, now() - interval '60 days', now()),
  ('9fa10000-0000-0000-0000-000000000002', '9fa00000-0000-0000-0000-0000000000c3', '9fa00000-0000-0000-0000-0000000000d4', 'active', CURRENT_DATE - 60, now() - interval '60 days', now());

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.refused(p_user uuid, p_sql text, p_code text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_msg text;
BEGIN
  PERFORM pg_temp.as_user(p_user);
  BEGIN
    EXECUTE p_sql;
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: accepted with its flag off: %', p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    RESET ROLE;
    IF v_msg LIKE 'CONTRACT VIOLATED%' OR v_msg <> p_code THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % gave "%" (want %)', p_sql, v_msg, p_code;
    END IF;
  END;
END $$;

-- F-3. Flags off (as seeded): every writer refuses, whatever the client.
UPDATE public.feature_flags SET enabled = false
WHERE key IN ('appreciation_notes', 'share_a_win', 'quiet_states', 'private_safety_check', 'conflict_toolkit');
DO $$
DECLARE
  v_ra uuid := '9fa10000-0000-0000-0000-000000000001';
  v_a uuid := '9fa00000-0000-0000-0000-0000000000a1';
BEGIN
  PERFORM pg_temp.refused(v_a, format('SELECT public.send_appreciation(%L, %L, %L)', v_ra, gen_random_uuid(),
    'I noticed you made tea. Thank you.'), 'appreciation:not_allowed');
  PERFORM pg_temp.refused(v_a, format('SELECT public.share_a_win(%L, %L)', v_ra, 'Got the job'), 'win:not_allowed');
  PERFORM pg_temp.refused(v_a, 'SELECT public.set_my_quiet_state(''hard_time'')', 'quiet:not_allowed');
  PERFORM pg_temp.refused(v_a, format('SELECT public.submit_my_safety_check(%L, %L)', v_ra,
    '{"q1":"no","q2":"no","q3":"no","q4":"no"}'), 'safety_check:not_allowed');
  PERFORM pg_temp.refused(v_a, format('SELECT public.send_pause(%L, %L, 1)', v_ra, gen_random_uuid()), 'pause:not_allowed');
  -- The toolkit needs the safety check's flag too.
  UPDATE public.feature_flags SET enabled = true WHERE key = 'conflict_toolkit';
  PERFORM pg_temp.refused(v_a, format('SELECT public.send_pause(%L, %L, 1)', v_ra, gen_random_uuid()), 'pause:not_allowed');
END $$;
UPDATE public.feature_flags SET enabled = true
WHERE key IN ('appreciation_notes', 'share_a_win', 'quiet_states', 'private_safety_check', 'conflict_toolkit');

CREATE FUNCTION pg_temp.unread(p_user uuid, p_rel uuid) RETURNS int LANGUAGE plpgsql AS $$
DECLARE v int;
BEGIN
  PERFORM pg_temp.as_user(p_user);
  v := public.count_unread_messages(p_rel);
  RESET ROLE;
  RETURN v;
END $$;

DO $$
DECLARE
  v_ra uuid := '9fa10000-0000-0000-0000-000000000001';
  v_rb uuid := '9fa10000-0000-0000-0000-000000000002';
  v_a uuid := '9fa00000-0000-0000-0000-0000000000a1';
  v_b uuid := '9fa00000-0000-0000-0000-0000000000b2';
  v_c uuid := '9fa00000-0000-0000-0000-0000000000c3';
  v_d uuid := '9fa00000-0000-0000-0000-0000000000d4';
  v_e uuid := '9fa00000-0000-0000-0000-0000000000e5';
  v_f uuid := '9fa00000-0000-0000-0000-0000000000f6';
  v_item uuid := '9fa20000-0000-0000-0000-000000000001';
  v_msg uuid; v_n int; v_msg_text text; v_fn text; v_pause uuid; r record; v_rows jsonb;
BEGIN
  -- ---------------------------------------------------------------- C-2
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.story_items (id, client_story_id, relationship_id, author_id, media_type, media_key,
                                  thumbnail_key, media_width, media_height, occurred_on, expires_at)
  VALUES (v_item, gen_random_uuid(), v_ra, v_a, 'image', 'k/1.jpg', 'k/1t.jpg', 100, 100, CURRENT_DATE, now() + interval '1 day');
  INSERT INTO public.story_places (story_item_id, relationship_id, author_id, lat, lng, label)
  VALUES (v_item, v_ra, v_a, 5.6, -0.18, 'Osu');
  SET LOCAL session_replication_role = origin;
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.pause_relationship(v_ra);
  RESET ROLE;
  IF NOT EXISTS (SELECT 1 FROM public.story_places WHERE story_item_id = v_item) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pause deleted the story pins (C-2)';
  END IF;
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.resume_relationship(v_ra);
  RESET ROLE;
  IF NOT EXISTS (SELECT 1 FROM public.story_places WHERE story_item_id = v_item) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the pins did not survive pause and resume';
  END IF;

  -- ---------------------------------------------------------------- I-4
  INSERT INTO public.seen_receipt_prefs (relationship_id, user_id, seen_on) VALUES (v_ra, v_a, true), (v_ra, v_b, true)
  ON CONFLICT DO NOTHING;
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, created_at)
  VALUES (v_ra, v_b, gen_random_uuid(), 'are you there?', now() + interval '1 second')
  RETURNING id INTO v_msg;
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.pause_relationship(v_ra);
  RESET ROLE;
  PERFORM pg_temp.as_user(v_a);
  PERFORM * FROM public.mark_conversation_read(v_ra);
  RESET ROLE;
  SELECT * INTO r FROM public.messages WHERE id = v_msg;
  IF r.read_receipt_at IS NOT NULL OR r.delivered_at IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a tick reached the partner while paused (I-4)';
  END IF;
  IF pg_temp.unread(v_a, v_ra) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: reading while paused left the badge on';
  END IF;
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.resume_relationship(v_ra);
  RESET ROLE;

  -- ---------------------------------------------------------------- M-4
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, created_at)
  VALUES (v_ra, v_b, gen_random_uuid(), 'one ordinary', now() + interval '2 seconds');
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, created_at, deleted_at)
  VALUES (v_ra, v_b, gen_random_uuid(), 'gone', now() + interval '3 seconds', now() + interval '4 seconds');
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, created_at, is_system_notice)
  VALUES (v_ra, v_b, gen_random_uuid(), 'Goal reached: Trip', now() + interval '5 seconds', true);
  IF pg_temp.unread(v_a, v_ra) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: unread counts deleted or notice rows: % (want 1)', pg_temp.unread(v_a, v_ra);
  END IF;

  -- ---------------------------------------------------------------- I-7
  PERFORM pg_temp.as_user(v_c);
  PERFORM public.end_relationship(v_rb);
  RESET ROLE;
  -- A message from before the end, still unread.
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, created_at)
  VALUES (v_rb, v_d, gen_random_uuid(), 'before the end', now() - interval '1 hour');
  SET LOCAL session_replication_role = origin;
  IF pg_temp.unread(v_c, v_rb) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ended window shows an unread badge that cannot clear (I-7)';
  END IF;

  -- ---------------------------------------------------------------- I-8
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at, created_at)
  VALUES ('9fa10000-0000-0000-0000-000000000003', v_e, 'pending', 'SYNCI8A', now() + interval '7 days', now());
  -- Kofi is in an active relationship: he cannot accept.
  BEGIN
    UPDATE public.relationships SET user_b = v_b, status = 'active', invite_code = NULL, invite_accepted_at = now()
    WHERE id = '9fa10000-0000-0000-0000-000000000003';
    RAISE EXCEPTION 'CONTRACT VIOLATED: an active member accepted another invite (I-8)';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg_text = MESSAGE_TEXT;
    IF v_msg_text <> 'relationship:already_open' THEN RAISE; END IF;
  END;
  -- A paused member: the database keeps Spec 3a's Decision 19 (a new
  -- chapter ends and archives the paused one); accept-invite and
  -- create-relationship-invite refuse a paused person, because the app's
  -- accept path has no confirmation step (accept-invite/index.test.ts).
  -- Someone free can.
  UPDATE public.relationships SET user_b = v_f, status = 'active', invite_code = NULL, invite_accepted_at = now()
  WHERE id = '9fa10000-0000-0000-0000-000000000003';

  -- ---------------------------------------------------------------- M-6
  PERFORM pg_temp.as_user(v_b);
  PERFORM public.share_a_win(v_ra, 'Got the job');
  RESET ROLE;
  PERFORM pg_temp.as_user(v_a);
  SELECT count(*) INTO v_n FROM public.list_win_cards(v_ra);
  RESET ROLE;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: fixture: % win cards', v_n; END IF;
  INSERT INTO public.quiet_states (user_id, kind, started_at, until, line_offered)
  SELECT v_a, (SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
               WHERE t.typname = (SELECT udt_name FROM information_schema.columns
                                  WHERE table_name = 'quiet_states' AND column_name = 'kind') LIMIT 1),
         now(), now() + interval '14 days', true
  WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'quiet_states'
                AND column_name = 'kind' AND data_type = 'USER-DEFINED');
  IF NOT EXISTS (SELECT 1 FROM public.quiet_states WHERE user_id = v_a) THEN
    INSERT INTO public.quiet_states (user_id, kind, started_at, until, line_offered)
    VALUES (v_a, 'loss', now(), now() + interval '14 days', true);
  END IF;
  PERFORM pg_temp.as_user(v_a);
  SELECT count(*) INTO v_n FROM public.list_win_cards(v_ra);
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a quiet person sees % win cards (M-6)', v_n; END IF;
  DELETE FROM public.quiet_states WHERE user_id = v_a;

  -- ---------------------------------------------------------------- M-2
  -- (Kofi's earlier fixture lines are moved before the pause, so his reply
  -- is still open.)
  UPDATE public.messages SET created_at = now() - interval '1 minute'
  WHERE relationship_id = v_ra AND sender_id = v_b;
  PERFORM pg_temp.as_user(v_a);
  v_pause := public.send_pause(v_ra, gen_random_uuid(), 1);
  RESET ROLE;
  PERFORM pg_temp.as_user(v_b);
  PERFORM public.send_pause_reply(v_pause, gen_random_uuid());
  RESET ROLE;
  SELECT jsonb_agg(x) INTO v_rows
  FROM public.export_chat_page(v_a, v_ra, NULL, NULL, 500) p, jsonb_array_elements(p.rows) x;
  IF NOT coalesce(v_rows @> '[{"kind":"pause"}]', false) OR NOT coalesce(v_rows @> '[{"kind":"pause_reply"}]', false) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the export does not name a pause and its reply (M-2)';
  END IF;

  -- ---------------------------------------------------------------- M-3
  -- 40 pauses each (typed rows) and a few ordinary messages: not eligible.
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, created_at, sentiment)
  SELECT v_rb, u, gen_random_uuid(), 'hello', now() - (g || ' days')::interval, 'positive'
  FROM generate_series(1, 3) g, unnest(ARRAY[v_c, v_d]) u;
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, created_at, media_type, message_analysis_skipped)
  SELECT v_rb, u, gen_random_uuid(), 'pause', now() - (g || ' hours')::interval, 'pause', true
  FROM generate_series(1, 40) g, unnest(ARRAY[v_c, v_d]) u;
  UPDATE public.relationships SET status = 'active', ended_at = NULL WHERE id = v_rb;
  SET LOCAL session_replication_role = origin;
  IF (SELECT eligible FROM public.ask2_eligibility(v_rb)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: typed rows counted toward Ask-2 (M-3)';
  END IF;

  -- ---------------------------------------------------------------- M-7
  SET LOCAL session_replication_role = replica;
  INSERT INTO public.chat_import_requests (id, relationship_id, uploader_id, approver_id, source, policy_version,
                                           file_fingerprint, parsed_message_count, first_message_at, last_message_at, state)
  VALUES ('9fa30000-0000-0000-0000-000000000001', v_ra, v_a, v_b, 'whatsapp', 'v1', repeat('f', 64), 10,
          now() - interval '9 days', now() - interval '1 day', 'approved');
  SET LOCAL session_replication_role = origin;
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.pause_relationship(v_ra);
  RESET ROLE;
  IF (SELECT state FROM public.chat_import_requests WHERE id = '9fa30000-0000-0000-0000-000000000001') <> 'approved' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pause revoked the import consent (M-7)';
  END IF;
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.end_relationship(v_ra);
  RESET ROLE;
  IF (SELECT state FROM public.chat_import_requests WHERE id = '9fa30000-0000-0000-0000-000000000001') <> 'revoked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ending kept the import consent';
  END IF;
  -- C-2 again: the ending clears the pins.
  IF EXISTS (SELECT 1 FROM public.story_places WHERE story_item_id = v_item) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ending kept the story pins';
  END IF;

  -- ---------------------------------------------------------------- M-15
  FOREACH v_fn IN ARRAY ARRAY['public.sync_dating_pause_on_relationship()', 'public.together_purge_busy_on_end()',
                              'public.together_revoke_feeds_on_end()', 'public.presence_purge_on_relationship_close()',
                              'public.relationship_one_open_chapter_guard()'] LOOP
    IF has_function_privilege('authenticated', v_fn, 'EXECUTE') OR has_function_privilege('anon', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: clients can call %', v_fn;
    END IF;
  END LOOP;
END $$;
ROLLBACK;
