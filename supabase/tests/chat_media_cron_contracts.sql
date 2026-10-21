-- Chat review 2026-10-18 #24: both maintenance jobs were registered as
-- invoke_edge_function('process-chat-media'), which never calls the SQL
-- functions they were meant to run. Requires pg_cron (present locally).
BEGIN;
DO $$
DECLARE v_cmd text;
BEGIN
  -- 1. The stale-lease job calls its SQL function, not the edge function.
  SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'recover-stale-chat-workers';
  IF v_cmd IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recover-stale-chat-workers not scheduled';
  END IF;
  IF v_cmd NOT LIKE '%recover_stale_chat_worker_leases()%' OR v_cmd LIKE '%process-chat-media%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recover-stale-chat-workers runs: %', v_cmd;
  END IF;

  -- 2. The expired-intent cleanup job calls its SQL function.
  SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'cleanup-expired-chat-media';
  IF v_cmd IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: cleanup-expired-chat-media not scheduled';
  END IF;
  IF v_cmd NOT LIKE '%cleanup_expired_chat_media_intents()%' OR v_cmd LIKE '%process-chat-media%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: cleanup-expired-chat-media runs: %', v_cmd;
  END IF;

  -- 3. The media worker itself is still scheduled every minute.
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'process-chat-media'
                 AND command LIKE '%invoke_edge_function(''process-chat-media'')%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: process-chat-media job lost';
  END IF;
END $$;

-- 4. The scheduled commands actually run: exercise each exactly as cron would.
SET LOCAL session_replication_role = replica;
INSERT INTO auth.users (id) VALUES ('c2400000-0000-0000-0000-0000000000a1'), ('c2400000-0000-0000-0000-0000000000b2') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('c2400000-0000-0000-0000-0000000000a1', '+15550002401', 'A'),
  ('c2400000-0000-0000-0000-0000000000b2', '+15550002402', 'B') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status)
VALUES ('c2400000-0000-0000-0000-000000000001', 'c2400000-0000-0000-0000-0000000000a1', 'c2400000-0000-0000-0000-0000000000b2', 'active') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_url, media_type)
VALUES ('c2400000-0000-0000-0000-000000000101', 'c2400000-0000-0000-0000-000000000001', 'c2400000-0000-0000-0000-0000000000a1', gen_random_uuid(), NULL, 'chat-media/c240-stale.jpg', 'image');
DELETE FROM public.message_media_processing_outbox WHERE message_id = 'c2400000-0000-0000-0000-000000000101';
INSERT INTO public.message_media_processing_outbox (message_id, storage_key, state, attempts, processing_started_at)
VALUES ('c2400000-0000-0000-0000-000000000101', 'chat-media/c240-stale.jpg', 'processing', 1, now() - interval '20 minutes');
SET LOCAL session_replication_role = origin;

DO $$
DECLARE v_state text; v_rows int; v_cleaned int;
BEGIN
  EXECUTE (SELECT command FROM cron.job WHERE jobname = 'recover-stale-chat-workers');
  SELECT state INTO v_state FROM public.message_media_processing_outbox
  WHERE message_id = 'c2400000-0000-0000-0000-000000000101';
  IF v_state IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: stale media lease not recovered (state %)', v_state;
  END IF;
  SELECT count(*) INTO v_rows FROM public.recover_stale_chat_worker_leases();
  IF v_rows < 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recover_stale_chat_worker_leases reports % workers', v_rows;
  END IF;

  EXECUTE (SELECT command FROM cron.job WHERE jobname = 'cleanup-expired-chat-media');
  v_cleaned := public.cleanup_expired_chat_media_intents();
  IF v_cleaned IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: cleanup_expired_chat_media_intents returned NULL';
  END IF;
END $$;

-- 5. Mutation check: point the job back at the edge function; contract 1 must fail.
SAVEPOINT mutation;
UPDATE cron.job SET command = $$ SELECT public.invoke_edge_function('process-chat-media'); $$
WHERE jobname = 'recover-stale-chat-workers';
DO $$
DECLARE v_cmd text;
BEGIN
  SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'recover-stale-chat-workers';
  IF v_cmd NOT LIKE '%recover_stale_chat_worker_leases()%' OR v_cmd LIKE '%process-chat-media%' THEN
    RAISE NOTICE 'mutation check: contract 1 would fail with the old command (as intended)';
  ELSE
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 1 passed with the old command';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT mutation;

-- 6. Plan 1b final review carry (M1 / Task 5): the same cron run recovers
--    the PUSH pipeline too. A chat outbox job and a queued push left in
--    'processing' by a killed worker/sender go back to 'pending' after the
--    5-minute lease; a row inside its lease (a live worker) is untouched.
--    Re-sending a recovered scheduled_notifications row cannot double-
--    deliver: the sender's OneSignal Idempotency-Key is hash(row id +
--    target set), unchanged by recovery.
CREATE FUNCTION pg_temp.seed_stranded_push_rows() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  SET LOCAL session_replication_role = replica;
  DELETE FROM public.message_notification_outbox
  WHERE message_id = 'c2400000-0000-0000-0000-000000000101';
  INSERT INTO public.message_notification_outbox
    (id, message_id, relationship_id, recipient_id, sender_id, notification_type,
     state, attempts, processing_started_at)
  VALUES
    ('c2400000-0000-0000-0000-000000000201', 'c2400000-0000-0000-0000-000000000101',
     'c2400000-0000-0000-0000-000000000001', 'c2400000-0000-0000-0000-0000000000b2',
     'c2400000-0000-0000-0000-0000000000a1', 'new_message',
     'processing', 1, now() - interval '20 minutes'),
    ('c2400000-0000-0000-0000-000000000202', 'c2400000-0000-0000-0000-000000000101',
     'c2400000-0000-0000-0000-000000000001', 'c2400000-0000-0000-0000-0000000000b2',
     'c2400000-0000-0000-0000-0000000000a1', 'message_reaction',
     'processing', 1, now() - interval '1 minute');
  DELETE FROM public.scheduled_notifications
  WHERE user_id = 'c2400000-0000-0000-0000-0000000000b2';
  INSERT INTO public.scheduled_notifications
    (id, user_id, notification_type, scheduled_for, status, retry_count, metadata, updated_at)
  VALUES
    ('c2400000-0000-0000-0000-000000000301', 'c2400000-0000-0000-0000-0000000000b2', 'immediate',
     now() - interval '20 minutes', 'processing', 0,
     '{"type":"planning_entry","title":"Your plan","body":"Open Attune to see it."}',
     now() - interval '20 minutes'),
    ('c2400000-0000-0000-0000-000000000302', 'c2400000-0000-0000-0000-0000000000b2', 'immediate',
     now() - interval '1 minute', 'processing', 0,
     '{"type":"planning_entry","title":"Your plan","body":"Open Attune to see it."}',
     now() - interval '1 minute');
  SET LOCAL session_replication_role = origin;
END $$;

CREATE FUNCTION pg_temp.check_push_recovery() RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
  PERFORM pg_temp.seed_stranded_push_rows();
  EXECUTE (SELECT command FROM cron.job WHERE jobname = 'recover-stale-chat-workers');

  SELECT state, processing_started_at, last_error_code INTO r
  FROM public.message_notification_outbox WHERE id = 'c2400000-0000-0000-0000-000000000201';
  IF r.state IS DISTINCT FROM 'pending' OR r.processing_started_at IS NOT NULL
     OR r.last_error_code IS DISTINCT FROM 'stale_lease' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: stranded chat outbox job not recovered: %', row_to_json(r);
  END IF;
  SELECT state INTO r FROM public.message_notification_outbox
  WHERE id = 'c2400000-0000-0000-0000-000000000202';
  IF r.state IS DISTINCT FROM 'processing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chat outbox job inside its lease was taken back (state %)', r.state;
  END IF;

  SELECT status, retry_count, last_error INTO r
  FROM public.scheduled_notifications WHERE id = 'c2400000-0000-0000-0000-000000000301';
  IF r.status IS DISTINCT FROM 'pending' OR r.retry_count <> 1
     OR r.last_error IS DISTINCT FROM 'stale_lease' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: stranded queued push not recovered: %', row_to_json(r);
  END IF;
  SELECT status INTO r FROM public.scheduled_notifications
  WHERE id = 'c2400000-0000-0000-0000-000000000302';
  IF r.status IS DISTINCT FROM 'processing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a queued push inside its lease was taken back (status %)', r.status;
  END IF;

  -- A push that keeps getting stranded stops being retried (5 attempts).
  UPDATE public.scheduled_notifications
     SET status = 'processing', retry_count = 5, updated_at = now() - interval '20 minutes'
   WHERE id = 'c2400000-0000-0000-0000-000000000301';
  PERFORM public.recover_stale_chat_worker_leases();
  IF (SELECT status FROM public.scheduled_notifications
      WHERE id = 'c2400000-0000-0000-0000-000000000301') IS DISTINCT FROM 'failed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a push stranded 5 times was not failed';
  END IF;
END $$;

SELECT pg_temp.check_push_recovery();

-- 7. Mutation check: a recovery without the push branches (what the cron
--    effectively ran before this fix) must trip check 6.
SAVEPOINT mutation_push;
CREATE OR REPLACE FUNCTION public.recover_stale_chat_worker_leases()
RETURNS TABLE(worker text, recovered bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  worker := 'media'; recovered := 0; RETURN NEXT;
END $$;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.check_push_recovery();
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'CONTRACT VIOLATED: stranded chat outbox job not recovered%' THEN RAISE; END IF;
    RAISE NOTICE 'mutation check: without push recovery check 6 fails (as intended)';
    RETURN;
  END;
  RAISE EXCEPTION 'MUTATION NOT DETECTED: check 6 passed without push recovery';
END $$;
ROLLBACK TO SAVEPOINT mutation_push;

-- 8. Mutation check: recovering the chat outbox but not the push queue
--    (the gap plan 1b's review asked about) must trip check 6 too.
SAVEPOINT mutation_queue;
CREATE OR REPLACE FUNCTION public.recover_stale_chat_worker_leases()
RETURNS TABLE(worker text, recovered bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.message_notification_outbox
  SET state = 'pending', processing_started_at = NULL, last_error_code = 'stale_lease'
  WHERE state = 'processing' AND processing_started_at < now() - interval '5 minutes';
  worker := 'notification'; recovered := 0; RETURN NEXT;
END $$;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.check_push_recovery();
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'CONTRACT VIOLATED: stranded queued push not recovered%' THEN RAISE; END IF;
    RAISE NOTICE 'mutation check: without scheduled_notifications recovery check 6 fails (as intended)';
    RETURN;
  END;
  RAISE EXCEPTION 'MUTATION NOT DETECTED: check 6 passed without scheduled_notifications recovery';
END $$;
ROLLBACK TO SAVEPOINT mutation_queue;

DO $$ BEGIN RAISE NOTICE 'chat_media_cron_contracts: all held'; END $$;
ROLLBACK;
