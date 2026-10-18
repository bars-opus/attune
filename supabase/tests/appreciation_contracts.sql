-- supabase/tests/appreciation_contracts.sql
-- Spec 7 (research 06 B1; plan review C2, I4, I7, I8, M7): an "I noticed…"
-- note is an ordinary message in one of two fixed forms, sent only into an
-- active relationship, never edited; the jar is the recipient's alone,
-- follows the chapter gate, and counts nothing.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('9fc00000-0000-0000-0000-0000000000a1'), ('9fc00000-0000-0000-0000-0000000000b2'),
  ('9fc00000-0000-0000-0000-0000000000c3'), ('9fc00000-0000-0000-0000-0000000000d4'),
  ('9fc00000-0000-0000-0000-0000000000e5')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9fc00000-0000-0000-0000-0000000000a1', '+233599610001', 'Ama'),
  ('9fc00000-0000-0000-0000-0000000000b2', '+233599610002', 'Kofi'),
  ('9fc00000-0000-0000-0000-0000000000c3', '+233599610003', 'Stranger'),
  ('9fc00000-0000-0000-0000-0000000000d4', '+233599610004', 'Pat'),
  ('9fc00000-0000-0000-0000-0000000000e5', '+233599610005', 'Pip')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('9fc10000-0000-0000-0000-000000000001', '9fc00000-0000-0000-0000-0000000000a1', '9fc00000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE - 50, now() - interval '50 days', now()),
  ('9fc10000-0000-0000-0000-000000000002', '9fc00000-0000-0000-0000-0000000000d4', '9fc00000-0000-0000-0000-0000000000e5', 'paused', CURRENT_DATE - 50, now() - interval '50 days', now());

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

DO $$
DECLARE
  v_rel uuid := '9fc10000-0000-0000-0000-000000000001';
  v_a uuid := '9fc00000-0000-0000-0000-0000000000a1';
  v_b uuid := '9fc00000-0000-0000-0000-0000000000b2';
  v_c uuid := '9fc00000-0000-0000-0000-0000000000c3';
  v_d uuid := '9fc00000-0000-0000-0000-0000000000d4';
  v_cid uuid := '9fc20000-0000-0000-0000-000000000001';
  v_id uuid; v_id2 uuid; v_id3 uuid; v_plain uuid; r record; v_n int; v_fn text;
BEGIN
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'appreciation_notes') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: appreciation_notes not seeded off';
  END IF;
  -- The server refuses while the flag is off (sync_fixes_contracts); on
  -- for the rest of this file.
  UPDATE public.feature_flags SET enabled = true WHERE key IN ('appreciation_notes');
  FOREACH v_fn IN ARRAY ARRAY['public.send_appreciation(uuid,uuid,text)', 'public.save_to_my_jar(uuid)',
                              'public.list_my_jar_ids()',
                              'public.remove_from_my_jar(uuid)', 'public.list_my_jar()'] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: grants on %', v_fn;
    END IF;
  END LOOP;
  IF has_table_privilege('authenticated', 'public.appreciation_jar', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients read the jar table directly';
  END IF;
  -- M15: nothing counts.
  IF EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace = 'public'::regnamespace
             AND (proname ~ 'jar' OR proname ~ 'appreciation') AND (proname ~ 'count' OR proname ~ 'total')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a counting function exists';
  END IF;

  -- 1. The two fixed forms; an ordinary message; idempotent (I7, I8).
  PERFORM pg_temp.as_user(v_a);
  v_id := public.send_appreciation(v_rel, v_cid, 'I noticed you remembered Mum''s appointment. Thank you.');
  v_id2 := public.send_appreciation(v_rel, v_cid, 'I noticed you remembered Mum''s appointment. Thank you.');
  v_id3 := public.send_appreciation(v_rel, gen_random_uuid(), 'Thankful for you because you made tea.');
  RESET ROLE;
  SELECT * INTO r FROM public.messages WHERE id = v_id;
  IF v_id IS DISTINCT FROM v_id2 OR (SELECT count(*) FROM public.messages WHERE client_message_id = v_cid) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeat send made a second note';
  END IF;
  IF r.media_type <> 'appreciation' OR r.sender_id <> v_a OR r.source <> 'native' OR r.is_system_notice
     -- Sync audit I-5: no Pulse or AI input (Spec 7 line 36, Spec 8 I8).
     OR NOT r.message_analysis_skipped OR r.content <> 'I noticed you remembered Mum''s appointment. Thank you.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the stored note: %', row_to_json(r);
  END IF;
  IF (SELECT media_type FROM public.messages WHERE id = v_id3) <> 'appreciation' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the thankful form was not kept';
  END IF;

  -- 2. Anything else is refused.
  PERFORM pg_temp.refused(v_a, format('SELECT public.send_appreciation(%L, gen_random_uuid(), %L)', v_rel, 'hello'), 'appreciation:invalid');
  PERFORM pg_temp.refused(v_a, format('SELECT public.send_appreciation(%L, gen_random_uuid(), %L)', v_rel, 'I noticed you . Thank you.'), 'appreciation:invalid');
  PERFORM pg_temp.refused(v_a, format('SELECT public.send_appreciation(%L, gen_random_uuid(), %L)', v_rel, 'I noticed you ' || repeat('x', 300) || '. Thank you.'), 'appreciation:invalid');
  PERFORM pg_temp.refused(v_a, format('SELECT public.send_appreciation(%L, gen_random_uuid(), %L)', v_rel, E'I noticed you did\nthat. Thank you.'), 'appreciation:invalid');
  PERFORM pg_temp.refused(v_c, format('SELECT public.send_appreciation(%L, gen_random_uuid(), %L)', v_rel, 'I noticed you smiled. Thank you.'), 'appreciation:not_allowed');
  PERFORM pg_temp.refused(v_d, format('SELECT public.send_appreciation(%L, gen_random_uuid(), %L)',
    '9fc10000-0000-0000-0000-000000000002', 'I noticed you smiled. Thank you.'), 'appreciation:not_allowed');

  -- 2b. Only send_appreciation makes a note (final review I-1), and never
  -- into an archived chat (M-3).
  PERFORM pg_temp.as_user(v_a);
  BEGIN
    INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, media_type)
    VALUES (v_rel, v_a, gen_random_uuid(), 'Forged praise', 'appreciation');
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client wrote a note directly (I-1)';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    IF SQLERRM LIKE 'CONTRACT VIOLATED%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.messages SET media_type = 'appreciation' WHERE id = v_id3;
    UPDATE public.messages SET media_type = 'appreciation'
    WHERE relationship_id = v_rel AND media_type IS NULL AND content IS NOT NULL;
    IF FOUND THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a message was turned into a note (I-1)'; END IF;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'CONTRACT VIOLATED%' THEN RAISE; END IF;
  END;
  UPDATE public.relationships SET chat_archived_at = now() WHERE id = v_rel;
  PERFORM pg_temp.refused(v_a, format('SELECT public.send_appreciation(%L, gen_random_uuid(), %L)', v_rel, 'I noticed you smiled. Thank you.'), 'appreciation:not_allowed');
  PERFORM pg_temp.refused(v_b, format('SELECT public.save_to_my_jar(%L)', v_id), 'jar:not_allowed');
  UPDATE public.relationships SET chat_archived_at = NULL WHERE id = v_rel;

  -- 3. Never edited under the leaf (I4); deleting works.
  PERFORM pg_temp.refused(v_a, format('SELECT public.edit_message(%L, %L)', v_id, 'I noticed you were rude. Thank you.'), 'not_editable');

  -- 4. The jar: the recipient's, once, gated, removable.
  PERFORM pg_temp.as_user(v_b);
  PERFORM public.save_to_my_jar(v_id);
  PERFORM public.save_to_my_jar(v_id);
  SELECT count(*) INTO v_n FROM public.list_my_jar();
  SELECT * INTO r FROM public.list_my_jar() LIMIT 1;
  RESET ROLE;
  IF v_n <> 1 OR r.message_id <> v_id OR r.relationship_id <> v_rel OR r.content NOT LIKE 'I noticed you%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the recipient''s jar: % (%)', v_n, row_to_json(r);
  END IF;
  -- M-7: the chat reads only which notes are kept, not their text.
  PERFORM pg_temp.as_user(v_b);
  IF (SELECT array_agg(x) FROM public.list_my_jar_ids() x) IS DISTINCT FROM ARRAY[v_id] THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: list_my_jar_ids';
  END IF;
  RESET ROLE;
  PERFORM pg_temp.refused(v_a, format('SELECT public.save_to_my_jar(%L)', v_id), 'jar:not_allowed');
  PERFORM pg_temp.refused(v_c, format('SELECT public.save_to_my_jar(%L)', v_id), 'jar:not_allowed');
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content)
  VALUES (v_rel, v_a, gen_random_uuid(), 'just a message') RETURNING id INTO v_plain;
  PERFORM pg_temp.refused(v_b, format('SELECT public.save_to_my_jar(%L)', v_plain), 'jar:not_allowed');
  PERFORM pg_temp.as_user(v_a);
  SELECT count(*) INTO v_n FROM public.list_my_jar();
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the sender sees the recipient''s jar'; END IF;

  -- 5. A deleted note leaves the jar (M7).
  PERFORM pg_temp.as_user(v_b);
  PERFORM public.save_to_my_jar(v_id3);
  RESET ROLE;
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.delete_message(v_id3);
  RESET ROLE;
  PERFORM pg_temp.as_user(v_b);
  SELECT count(*) INTO v_n FROM public.list_my_jar();
  PERFORM public.remove_from_my_jar(v_id);
  IF (SELECT count(*) FROM public.list_my_jar()) <> 0 OR v_n <> 1 THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: delete / remove: %', v_n;
  END IF;
  PERFORM public.save_to_my_jar(v_id);
  RESET ROLE;

  -- 6. The chapter gate (C2): gone after the 30-day window, and after a seal.
  UPDATE public.relationships SET status = 'ended', ended_at = now() - interval '31 days' WHERE id = v_rel;
  PERFORM pg_temp.as_user(v_b);
  SELECT count(*) INTO v_n FROM public.list_my_jar();
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the jar outlives the chapter window'; END IF;
  UPDATE public.relationships SET ended_at = now() - interval '2 days' WHERE id = v_rel;
  PERFORM pg_temp.as_user(v_b);
  SELECT count(*) INTO v_n FROM public.list_my_jar();
  PERFORM public.seal_my_side(v_rel);
  SELECT count(*) INTO r FROM public.list_my_jar();
  RESET ROLE;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the jar is gone inside the 30-day window'; END IF;
  PERFORM pg_temp.as_user(v_b);
  SELECT count(*) INTO v_n FROM public.list_my_jar();
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the jar outlives a seal'; END IF;
END $$;
DO $$ BEGIN RAISE NOTICE 'appreciation_contracts: all held'; END $$;
ROLLBACK;
