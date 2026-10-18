-- supabase/tests/read_watermark_contracts.sql
-- Unread scans stay bounded (Spec 1a final review I2): messages.read_at is
-- never written for native messages any more, so "read_at IS NULL" no longer
-- narrows count_unread_messages / mark_conversation_read to the unread few.
-- A per-reader watermark (message_read_marks, server-only, unpublished)
-- limits both to messages created after it, less a safety margin. created_at
-- is server-set (no client INSERT grant), so nothing older than the margin
-- can still be unread. Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('6a100000-0000-0000-0000-0000000000a1'),
  ('6a100000-0000-0000-0000-0000000000b2'),
  ('6a100000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('6a100000-0000-0000-0000-0000000000a1', '+233599310001', 'Mark A'),
  ('6a100000-0000-0000-0000-0000000000b2', '+233599310002', 'Mark B'),
  ('6a100000-0000-0000-0000-0000000000c3', '+233599310003', 'Mark C')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('6a200000-0000-0000-0000-000000000001', '6a100000-0000-0000-0000-0000000000a1',
   '6a100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now(), '2026-11-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING;
-- Three unread from B to A, a day old.
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, created_at, sort_at, message_analysis_done, safety_processed_at) VALUES
  ('6a300000-0000-0000-0000-000000000001', '6a200000-0000-0000-0000-000000000001',
   '6a100000-0000-0000-0000-0000000000b2', '6a400000-0000-0000-0000-000000000001', 'b1', now() - interval '1 day', now() - interval '1 day', true, now()),
  ('6a300000-0000-0000-0000-000000000002', '6a200000-0000-0000-0000-000000000001',
   '6a100000-0000-0000-0000-0000000000b2', '6a400000-0000-0000-0000-000000000002', 'b2', now() - interval '23 hours', now() - interval '23 hours', true, now()),
  ('6a300000-0000-0000-0000-000000000003', '6a200000-0000-0000-0000-000000000001',
   '6a100000-0000-0000-0000-0000000000b2', '6a400000-0000-0000-0000-000000000003', 'b3', now() - interval '22 hours', now() - interval '22 hours', true, now())
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- 1. The watermark table is server-only and unpublished.
DO $$
BEGIN
  IF to_regclass('public.message_read_marks') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: message_read_marks does not exist';
  END IF;
  IF has_table_privilege('authenticated', 'public.message_read_marks', 'SELECT')
     OR has_table_privilege('authenticated', 'public.message_read_marks', 'INSERT')
     OR has_table_privilege('authenticated', 'public.message_read_marks', 'UPDATE')
     OR has_table_privilege('anon', 'public.message_read_marks', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients can reach message_read_marks';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_publication_tables
             WHERE pubname = 'supabase_realtime' AND tablename = 'message_read_marks') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: message_read_marks is published';
  END IF;
END $$;

-- 2. A read moves A's watermark to the newest message it marked; the badge
--    clears.
DO $$
DECLARE v int; v_mark timestamptz; v_newest timestamptz;
BEGIN
  PERFORM pg_temp.as_user('6a100000-0000-0000-0000-0000000000a1');
  IF public.count_unread_messages('6a200000-0000-0000-0000-000000000001') <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: A should start with 3 unread';
  END IF;
  PERFORM count(*) FROM public.mark_conversation_read('6a200000-0000-0000-0000-000000000001');
  v := public.count_unread_messages('6a200000-0000-0000-0000-000000000001');
  RESET ROLE;
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % unread after a read', v; END IF;
  SELECT read_through INTO v_mark FROM public.message_read_marks
   WHERE relationship_id = '6a200000-0000-0000-0000-000000000001'
     AND reader_id = '6a100000-0000-0000-0000-0000000000a1';
  SELECT max(created_at) INTO v_newest FROM public.messages
   WHERE relationship_id = '6a200000-0000-0000-0000-000000000001';
  IF v_mark IS DISTINCT FROM v_newest THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: watermark % is not the newest marked message %', v_mark, v_newest;
  END IF;
  IF EXISTS (SELECT 1 FROM public.message_read_marks
             WHERE reader_id = '6a100000-0000-0000-0000-0000000000b2') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: B got a watermark from A''s read';
  END IF;
END $$;

-- 3. The scan is bounded: a row older than watermark − margin is outside it
--    (it cannot be genuinely unread: created_at is server-set); a row inside
--    the margin and a new row both count; a new read clears them and never
--    moves the watermark backwards.
DO $$
DECLARE v int; v_mark timestamptz; v_after timestamptz;
BEGIN
  SELECT read_through INTO v_mark FROM public.message_read_marks
   WHERE relationship_id = '6a200000-0000-0000-0000-000000000001'
     AND reader_id = '6a100000-0000-0000-0000-0000000000a1';
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, created_at, sort_at, message_analysis_done, safety_processed_at) VALUES
    ('6a300000-0000-0000-0000-000000000004', '6a200000-0000-0000-0000-000000000001',
     '6a100000-0000-0000-0000-0000000000b2', '6a400000-0000-0000-0000-000000000004', 'old', v_mark - interval '1 hour', v_mark - interval '1 hour', true, now()),
    ('6a300000-0000-0000-0000-000000000005', '6a200000-0000-0000-0000-000000000001',
     '6a100000-0000-0000-0000-0000000000b2', '6a400000-0000-0000-0000-000000000005', 'in margin', v_mark - interval '1 minute', v_mark - interval '1 minute', true, now()),
    ('6a300000-0000-0000-0000-000000000006', '6a200000-0000-0000-0000-000000000001',
     '6a100000-0000-0000-0000-0000000000b2', '6a400000-0000-0000-0000-000000000006', 'new', now(), now(), true, now());
  PERFORM pg_temp.as_user('6a100000-0000-0000-0000-0000000000a1');
  v := public.count_unread_messages('6a200000-0000-0000-0000-000000000001');
  IF v <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expected 2 unread inside the bounded window, got %', v;
  END IF;
  PERFORM count(*) FROM public.mark_conversation_read('6a200000-0000-0000-0000-000000000001');
  v := public.count_unread_messages('6a200000-0000-0000-0000-000000000001');
  RESET ROLE;
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % unread after the second read', v; END IF;
  IF EXISTS (SELECT 1 FROM public.message_reads WHERE message_id = '6a300000-0000-0000-0000-000000000004') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mark_conversation_read scanned below the watermark margin';
  END IF;
  SELECT read_through INTO v_after FROM public.message_read_marks
   WHERE relationship_id = '6a200000-0000-0000-0000-000000000001'
     AND reader_id = '6a100000-0000-0000-0000-0000000000a1';
  IF v_after < v_mark THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the watermark moved backwards'; END IF;
END $$;

-- 4. Outsiders get nothing and set no watermark.
DO $$
DECLARE v int;
BEGIN
  PERFORM pg_temp.as_user('6a100000-0000-0000-0000-0000000000c3');
  v := public.count_unread_messages('6a200000-0000-0000-0000-000000000001');
  PERFORM count(*) FROM public.mark_conversation_read('6a200000-0000-0000-0000-000000000001');
  RESET ROLE;
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider counts % unread', v; END IF;
  IF EXISTS (SELECT 1 FROM public.message_read_marks WHERE reader_id = '6a100000-0000-0000-0000-0000000000c3') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider set a watermark';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'read_watermark_contracts: all held'; END $$;
ROLLBACK;
