-- supabase/tests/chat_push_dedupe_contracts.sql
-- Chat review #17 (07 M-3): a chat outbox job queues at most one push and
-- one in-app notification however often the worker retries, and the
-- overnight collapse (Spec 1b D2) is untouched. Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES ('8d170000-0000-0000-0000-0000000000a1')
ON CONFLICT (id) DO NOTHING;
-- Zone unknown first: daytime behaviour (no deferral) until check 3.
INSERT INTO public.users (id, phone, display_name, timezone)
VALUES ('8d170000-0000-0000-0000-0000000000a1', '+233598170001', 'Dedupe A', NULL)
ON CONFLICT (id) DO UPDATE SET timezone = NULL;

-- Queue a chat push exactly as process-chat-notification-outbox does
-- (enqueuePush: metadata carries type/title/body/relationship_id/outbox_id,
-- no source_key). NULL when the quiet guard collapsed it.
CREATE FUNCTION pg_temp.chat_push(p_outbox text, p_at timestamptz DEFAULT now())
RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata)
  VALUES ('8d170000-0000-0000-0000-0000000000a1', 'immediate', p_at, 'pending',
          jsonb_build_object('type', 'new_message', 'title', 'New message in Attune',
                             'body', 'Open Attune to read it.',
                             'relationship_id', '8d170000-0000-0000-0000-000000000011',
                             'outbox_id', p_outbox))
  RETURNING id $$;

-- 1. The same job twice is one push -- before and after the first was sent.
DO $$
DECLARE v1 uuid; v2 uuid;
BEGIN
  v1 := pg_temp.chat_push('job-1');
  IF v1 IS NULL THEN RAISE EXCEPTION 'fixture broken: the first push did not queue'; END IF;
  BEGIN
    v2 := pg_temp.chat_push('job-1');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retried chat outbox job queued a second push';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  UPDATE public.scheduled_notifications SET status = 'sent' WHERE id = v1;
  BEGIN
    v2 := pg_temp.chat_push('job-1');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retry after the push was sent queued it again';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;

-- 2. Different jobs are different pushes.
DO $$
BEGIN
  PERFORM pg_temp.chat_push('job-2');
  PERFORM pg_temp.chat_push('job-3');
  IF (SELECT count(*) FROM public.scheduled_notifications
      WHERE metadata->>'outbox_id' IN ('job-2', 'job-3')) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two different jobs did not both queue';
  END IF;
END $$;

-- 3. Overnight (Spec 1b D2) still collapses: two jobs at 23:00 Accra make one
--    row at 08:00, and the first job retried at night joins it (no raise).
UPDATE public.users SET timezone = 'Africa/Accra' WHERE id = '8d170000-0000-0000-0000-0000000000a1';
DO $$
DECLARE v_first uuid; v_second uuid; v_retry uuid; v_n int;
BEGIN
  v_first  := pg_temp.chat_push('night-1', '2026-11-10 23:00+00');
  v_second := pg_temp.chat_push('night-2', '2026-11-10 23:05+00');
  v_retry  := pg_temp.chat_push('night-1', '2026-11-10 23:06+00');
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE source_key LIKE 'quiet_chat:8d170000-0000-0000-0000-0000000000a1:%';
  IF v_first IS NULL OR v_second IS NOT NULL OR v_retry IS NOT NULL OR v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the overnight collapse changed (first=% second=% retry=% rows=%)',
      v_first, v_second, v_retry, v_n;
  END IF;
  IF (SELECT scheduled_for FROM public.scheduled_notifications WHERE id = v_first) <> '2026-11-11 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the collapsed push is not at 08:00 local';
  END IF;
  IF (SELECT metadata->>'quiet_count' FROM public.scheduled_notifications WHERE id = v_first) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the later jobs did not join the 08:00 push';
  END IF;
END $$;

-- 4. In-app: one row per (person, job).
DO $$
BEGIN
  INSERT INTO public.in_app_notifications (user_id, title, body, data)
  VALUES ('8d170000-0000-0000-0000-0000000000a1', 'T', 'B', '{"type":"new_message","outbox_id":"job-1"}');
  BEGIN
    INSERT INTO public.in_app_notifications (user_id, title, body, data)
    VALUES ('8d170000-0000-0000-0000-0000000000a1', 'T', 'B', '{"type":"new_message","outbox_id":"job-1"}');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retried job wrote a second in-app notification';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  -- Rows without a job key (every other notification type) are not constrained.
  INSERT INTO public.in_app_notifications (user_id, title, body, data)
  VALUES ('8d170000-0000-0000-0000-0000000000a1', 'T', 'B', '{"type":"invite_accepted"}'),
         ('8d170000-0000-0000-0000-0000000000a1', 'T', 'B', '{"type":"invite_accepted"}');
END $$;

-- 5. Mutation check: without the index, check 1 would be violated.
SAVEPOINT mutate;
DROP INDEX public.scheduled_notifications_chat_outbox_idx;
DO $$
DECLARE v_dup uuid;
BEGIN
  v_dup := pg_temp.chat_push('job-2');
  IF v_dup IS NULL THEN RAISE EXCEPTION 'mutation check broken: the duplicate was not inserted'; END IF;
  RAISE NOTICE 'mutation check: without scheduled_notifications_chat_outbox_idx a retry queued a second push (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate;

-- 6. Mutation check: without the in-app index, check 4 would be violated.
SAVEPOINT mutate_inapp;
DROP INDEX public.in_app_notifications_chat_outbox_idx;
DO $$
BEGIN
  INSERT INTO public.in_app_notifications (user_id, title, body, data)
  VALUES ('8d170000-0000-0000-0000-0000000000a1', 'T', 'B', '{"type":"new_message","outbox_id":"job-1"}');
  RAISE NOTICE 'mutation check: without in_app_notifications_chat_outbox_idx a retry wrote a second in-app row (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_inapp;

DO $$ BEGIN RAISE NOTICE 'chat_push_dedupe_contracts: all held'; END $$;
ROLLBACK;
