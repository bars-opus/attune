-- supabase/tests/read_receipt_contracts.sql
-- Chat receipts (Spec 1a Task 3): the recipient's read marker lives in
-- message_reads (not published, not client-readable); read_receipt_at is the
-- sender's tick and is written only while "Show when we've seen things" is
-- on; while off a read changes NO row of messages (realtime emits no event);
-- analysis columns are never client-readable (SOUL §8). Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('5c100000-0000-0000-0000-0000000000a1'),
  ('5c100000-0000-0000-0000-0000000000b2'),
  ('5c100000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('5c100000-0000-0000-0000-0000000000a1', '+233599300001', 'Tick A'),
  ('5c100000-0000-0000-0000-0000000000b2', '+233599300002', 'Tick B'),
  ('5c100000-0000-0000-0000-0000000000c3', '+233599300003', 'Tick C')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('5c200000-0000-0000-0000-000000000001', '5c100000-0000-0000-0000-0000000000a1',
   '5c100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now(), '2026-11-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING;
-- Two unread from A, one from B, and one legacy imported row from A that
-- carries read_at (the import worker's shape) and must count as read.
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, delivered_at, read_at, message_analysis_done, safety_processed_at) VALUES
  ('5c300000-0000-0000-0000-000000000001', '5c200000-0000-0000-0000-000000000001',
   '5c100000-0000-0000-0000-0000000000a1', '5c400000-0000-0000-0000-000000000001', 'one from A', now(), NULL, true, now()),
  ('5c300000-0000-0000-0000-000000000002', '5c200000-0000-0000-0000-000000000001',
   '5c100000-0000-0000-0000-0000000000a1', '5c400000-0000-0000-0000-000000000002', 'two from A', NULL, NULL, true, now()),
  ('5c300000-0000-0000-0000-000000000003', '5c200000-0000-0000-0000-000000000001',
   '5c100000-0000-0000-0000-0000000000b2', '5c400000-0000-0000-0000-000000000003', 'one from B', now(), NULL, true, now()),
  ('5c300000-0000-0000-0000-000000000004', '5c200000-0000-0000-0000-000000000001',
   '5c100000-0000-0000-0000-0000000000a1', '5c400000-0000-0000-0000-000000000004', 'imported from A', now(), now(), true, now())
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;
-- A fingerprint of every messages row of the fixture couple: system column
-- xmin (changes on ANY update, even one that writes the same values) plus
-- the row contents.
CREATE FUNCTION pg_temp.messages_fingerprint() RETURNS text LANGUAGE sql AS $$
  SELECT string_agg(m.xmin::text || ':' || md5(m::text), '|' ORDER BY m.id)
  FROM public.messages m WHERE m.relationship_id = '5c200000-0000-0000-0000-000000000001' $$;

-- 1. The client SELECT allowlist is exactly the Dart _messageColumns plus
--    nothing; message_reads has no client grant and is not published.
DO $$
DECLARE
  v_allow text[] := ARRAY[
    'id','relationship_id','sender_id','client_message_id','content','created_at',
    'sort_at','game_session_id','delivered_at','read_receipt_at','media_url',
    'media_thumbnail_url','media_type','media_duration_ms','media_waveform',
    'media_width','media_height','source','reply_to_message_id','quoted_text',
    'deleted_at','edited_at','is_view_once','viewed_at','is_system_notice',
    'streak_views_remaining','story_item_id','message_origin','assistant_payload',
    -- Chat robustness plan 1a (20261019100000/100010): the sync cursor
    -- reads updated_at to pick up edits, deletes and receipts on any row.
    'updated_at'];
  v_private text[] := ARRAY[
    'read_at','tone_score','nvc_violations','bid_type','sentiment',
    'message_analysis_done','message_analysis_skipped','included_in_session_id',
    'safety_processed_at','safety_error_at','safety_error_code',
    'import_job_id','source_line_number'];
  v_actual text[];
  v_col text;
BEGIN
  IF has_table_privilege('authenticated', 'public.messages', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated holds table-level SELECT on messages (20260914130000 shape)';
  END IF;
  IF has_table_privilege('authenticated', 'public.messages', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.messages', 'DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated holds UPDATE or DELETE on messages';
  END IF;
  IF NOT has_any_column_privilege('authenticated', 'public.messages', 'INSERT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the INSERT column allowlist (20260939020000) is gone';
  END IF;
  FOREACH v_col IN ARRAY v_private LOOP
    IF has_column_privilege('authenticated', 'public.messages', v_col, 'SELECT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated can select messages.%', v_col;
    END IF;
  END LOOP;
  SELECT array_agg(column_name::text ORDER BY column_name) INTO v_actual
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'messages'
    AND has_column_privilege('authenticated', 'public.messages', column_name::text, 'SELECT');
  IF v_actual IS DISTINCT FROM (SELECT array_agg(c ORDER BY c) FROM unnest(v_allow) AS c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: selectable columns % differ from the allowlist', v_actual;
  END IF;
  IF has_column_privilege('anon', 'public.messages', 'content', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can select messages.content';
  END IF;
  IF has_table_privilege('authenticated', 'public.message_reads', 'SELECT')
     OR has_any_column_privilege('authenticated', 'public.message_reads', 'SELECT')
     OR has_table_privilege('authenticated', 'public.message_reads', 'INSERT')
     OR has_table_privilege('anon', 'public.message_reads', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client role can reach message_reads';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_publication_tables
             WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'message_reads') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: message_reads is published (the read moment would stream)';
  END IF;
END $$;

-- 2. A member selecting read_at or an analysis column is refused with 42501,
--    even on their own message; the allowlist shape still works.
DO $$
DECLARE v_sql text; v_dummy text;
BEGIN
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000a1');
  FOREACH v_sql IN ARRAY ARRAY[
    $q$SELECT read_at::text FROM public.messages WHERE id = '5c300000-0000-0000-0000-000000000001'$q$,
    $q$SELECT tone_score::text FROM public.messages WHERE id = '5c300000-0000-0000-0000-000000000003'$q$,
    $q$SELECT nvc_violations::text FROM public.messages WHERE id = '5c300000-0000-0000-0000-000000000003'$q$,
    $q$SELECT bid_type::text FROM public.messages WHERE id = '5c300000-0000-0000-0000-000000000003'$q$,
    $q$SELECT sentiment::text FROM public.messages WHERE id = '5c300000-0000-0000-0000-000000000003'$q$,
    $q$SELECT count(*)::text FROM public.messages WHERE relationship_id = '5c200000-0000-0000-0000-000000000001' AND read_at IS NULL$q$,
    $q$SELECT count(*)::text FROM public.message_reads$q$
  ] LOOP
    BEGIN
      EXECUTE v_sql INTO v_dummy;
      RAISE EXCEPTION 'CONTRACT VIOLATED: a member ran: %', v_sql;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
  PERFORM id, relationship_id, sender_id, client_message_id, content, created_at,
          sort_at, game_session_id, delivered_at, read_receipt_at, media_url,
          media_thumbnail_url, media_type, media_duration_ms, media_waveform,
          media_width, media_height, source, reply_to_message_id, quoted_text,
          deleted_at, edited_at, is_view_once, viewed_at, is_system_notice,
          streak_views_remaining, story_item_id, message_origin, assistant_payload
  FROM public.messages WHERE relationship_id = '5c200000-0000-0000-0000-000000000001';
  RESET ROLE;
END $$;

-- 3. While receipts are off (no prefs rows for this couple): the badge
--    counts and clears, the legacy imported row counts as read, and a read
--    changes NO row of messages -- no realtime event (Review Focus 6).
DO $$
DECLARE v int; v_before text; v_after text; v_marked int;
BEGIN
  IF NOT has_function_privilege('authenticated', 'public.count_unread_messages(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated cannot execute count_unread_messages';
  END IF;
  IF has_function_privilege('anon', 'public.count_unread_messages(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can execute count_unread_messages';
  END IF;
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000b2');
  v := public.count_unread_messages('5c200000-0000-0000-0000-000000000001');
  IF v <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: B expected 2 unread (imported row excluded), got %', v; END IF;
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000a1');
  v := public.count_unread_messages('5c200000-0000-0000-0000-000000000001');
  IF v <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: A expected 1 unread, got %', v; END IF;
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000c3');
  v := public.count_unread_messages('5c200000-0000-0000-0000-000000000001');
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider counted % unread', v; END IF;

  RESET ROLE;
  v_before := pg_temp.messages_fingerprint();
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_marked FROM public.mark_conversation_read('5c200000-0000-0000-0000-000000000001');
  IF v_marked <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: mark_conversation_read marked % rows, expected 2', v_marked; END IF;
  v := public.count_unread_messages('5c200000-0000-0000-0000-000000000001');
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: B still has % unread after reading (receipts off)', v; END IF;
  -- Replay marks nothing more.
  SELECT count(*) INTO v_marked FROM public.mark_conversation_read('5c200000-0000-0000-0000-000000000001');
  IF v_marked <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed read marked % rows', v_marked; END IF;
  RESET ROLE;
  v_after := pg_temp.messages_fingerprint();
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a read while receipts were off changed a messages row (realtime would have fired)';
  END IF;
  IF (SELECT count(*) FROM public.message_reads
      WHERE reader_id = '5c100000-0000-0000-0000-0000000000b2') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the private marker was not written';
  END IF;
  IF EXISTS (SELECT 1 FROM public.messages
             WHERE relationship_id = '5c200000-0000-0000-0000-000000000001' AND read_receipt_at IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: read_receipt_at was written while receipts were off';
  END IF;
  -- The undelivered row stays undelivered: a read while off is not a
  -- delivery either (that comes from the device's own delivery RPCs).
  IF (SELECT delivered_at FROM public.messages WHERE id = '5c300000-0000-0000-0000-000000000002') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a read while off produced a delivery tick';
  END IF;
END $$;

-- 4. While on: the tick is written (and implies delivery); the recipient's
--    count is unaffected by the setting; archived chats count nothing.
DO $$
DECLARE v int; v_fp text;
BEGIN
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, message_analysis_done, safety_processed_at)
  VALUES ('5c300000-0000-0000-0000-000000000005', '5c200000-0000-0000-0000-000000000001',
          '5c100000-0000-0000-0000-0000000000a1', '5c400000-0000-0000-0000-000000000005', 'three from A', true, now())
  ON CONFLICT (id) DO NOTHING;
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_seen_receipts('5c200000-0000-0000-0000-000000000001', true);
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000b2');
  PERFORM public.set_seen_receipts('5c200000-0000-0000-0000-000000000001', true);
  v := public.count_unread_messages('5c200000-0000-0000-0000-000000000001');
  IF v <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: B expected 1 unread, got %', v; END IF;
  PERFORM public.mark_conversation_read('5c200000-0000-0000-0000-000000000001');
  v := public.count_unread_messages('5c200000-0000-0000-0000-000000000001');
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: B still has % unread after reading (receipts on)', v; END IF;
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000a1');
  IF (SELECT read_receipt_at IS NULL OR delivered_at IS NULL FROM public.messages
      WHERE id = '5c300000-0000-0000-0000-000000000005') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a read while on did not produce a receipt that implies delivery';
  END IF;
  -- The two messages read while off stay without a tick, now and forever.
  IF EXISTS (SELECT 1 FROM public.messages WHERE id IN
             ('5c300000-0000-0000-0000-000000000001', '5c300000-0000-0000-0000-000000000002')
             AND read_receipt_at IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning receipts on revealed reads made while off';
  END IF;
  RESET ROLE;
  UPDATE public.relationships SET chat_archived_at = now(), chat_archived_reason = 'manual_end'
   WHERE id = '5c200000-0000-0000-0000-000000000001';
  PERFORM pg_temp.as_user('5c100000-0000-0000-0000-0000000000a1');
  v := public.count_unread_messages('5c200000-0000-0000-0000-000000000001');
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an archived chat still counts % unread', v; END IF;
  RESET ROLE;
  RAISE NOTICE 'read_receipt_contracts: all held';
END $$;

ROLLBACK;
