-- supabase/tests/chat_push_replay_contracts.sql
--
-- Plan 1b final review M3 (revived by #24's stale-lease recovery): a chat
-- outbox job whose push the quiet guard folded into the overnight 08:00
-- push must not queue a second push when it is re-run after 08:00
-- (recovered from a stranded 'processing' lease, or reset by hand). The
-- folded job wrote no row, so scheduled_notifications_chat_outbox_idx
-- never saw its id; message_notification_outbox.push_queued_at now
-- records that the queue accepted the job's push (written OR folded), and
-- a later push for that job is dropped. Every check RAISEs.
BEGIN;

SET LOCAL session_replication_role = replica;
INSERT INTO auth.users (id) VALUES
  ('c2410000-0000-0000-0000-0000000000a1'), ('c2410000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
-- B (the recipient) lives in Accra (UTC+0): 23:00 UTC is quiet, 09:00 is not.
INSERT INTO public.users (id, phone, display_name, timezone) VALUES
  ('c2410000-0000-0000-0000-0000000000a1', '+15550002411', 'Replay A', NULL),
  ('c2410000-0000-0000-0000-0000000000b2', '+15550002412', 'Replay B', 'Africa/Accra')
ON CONFLICT (id) DO UPDATE SET timezone = EXCLUDED.timezone;
INSERT INTO public.relationships (id, user_a, user_b, status)
VALUES ('c2410000-0000-0000-0000-000000000001', 'c2410000-0000-0000-0000-0000000000a1',
        'c2410000-0000-0000-0000-0000000000b2', 'active')
ON CONFLICT (id) DO NOTHING;
-- One message and one outbox job per case (the outbox is unique per
-- recipient/message/type). Job ids end in the message's number.
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content)
SELECT ('c2410000-0000-0000-0000-00000000010' || n)::uuid, 'c2410000-0000-0000-0000-000000000001',
       'c2410000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'm' || n
FROM generate_series(1, 6) n;
INSERT INTO public.message_notification_outbox
  (id, message_id, relationship_id, recipient_id, sender_id, notification_type, state, attempts)
SELECT ('c2410000-0000-0000-0000-00000000020' || n)::uuid,
       ('c2410000-0000-0000-0000-00000000010' || n)::uuid, 'c2410000-0000-0000-0000-000000000001',
       'c2410000-0000-0000-0000-0000000000b2', 'c2410000-0000-0000-0000-0000000000a1',
       'new_message', 'processing', 1
FROM generate_series(1, 6) n;
SET LOCAL session_replication_role = origin;

-- Queue a chat push exactly as process-chat-notification-outbox does
-- (enqueuePush: no source_key, outbox_id in metadata). NULL when no row
-- was written. p_at stands in for the worker's now().
CREATE FUNCTION pg_temp.chat_push(p_job int, p_at timestamptz)
RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata)
  VALUES ('c2410000-0000-0000-0000-0000000000b2', 'immediate', p_at, 'pending',
          jsonb_build_object('type', 'new_message', 'title', 'New message in Attune',
                             'body', 'Open Attune to read it.',
                             'relationship_id', 'c2410000-0000-0000-0000-000000000001',
                             'outbox_id', 'c2410000-0000-0000-0000-00000000020' || p_job))
  RETURNING id $$;

CREATE FUNCTION pg_temp.pushes_for(p_job int) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM public.scheduled_notifications
  WHERE metadata->>'outbox_id' = 'c2410000-0000-0000-0000-00000000020' || p_job $$;

CREATE FUNCTION pg_temp.queued_pushes() RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM public.scheduled_notifications
  WHERE user_id = 'c2410000-0000-0000-0000-0000000000b2' AND status <> 'cancelled' $$;

-- 1. Overnight: job 1 makes the 08:00 push, job 2 folds into it; 08:00 sends it.
DO $$
DECLARE v_first uuid; v_second uuid;
BEGIN
  v_first  := pg_temp.chat_push(1, '2026-11-10 23:00+00');
  v_second := pg_temp.chat_push(2, '2026-11-10 23:05+00');
  IF v_first IS NULL OR v_second IS NOT NULL OR pg_temp.queued_pushes() <> 1 THEN
    RAISE EXCEPTION 'fixture broken: the overnight collapse did not happen (first=% second=% rows=%)',
      v_first, v_second, pg_temp.queued_pushes();
  END IF;
  UPDATE public.scheduled_notifications SET status = 'sent' WHERE id = v_first;
END $$;

-- 2. M3: job 2 re-run at 09:00 (after the 08:00 push covered it) queues nothing.
CREATE FUNCTION pg_temp.check_folded_replay(p_job int, p_at timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  v := pg_temp.chat_push(p_job, p_at);
  IF v IS NOT NULL OR pg_temp.pushes_for(p_job) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a folded overnight job re-run after 08:00 queued a second push';
  END IF;
END $$;
DO $$
DECLARE v_before bigint := pg_temp.queued_pushes();
BEGIN
  PERFORM pg_temp.check_folded_replay(2, '2026-11-11 09:00+00');
  IF pg_temp.queued_pushes() <> v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the replay changed the queue (% -> %)', v_before, pg_temp.queued_pushes();
  END IF;
END $$;

-- 3. Unchanged: job 1 re-run in the day still meets the unique index
--    (the worker reads 23505 as "already queued").
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.chat_push(1, '2026-11-11 09:01+00');
    RAISE EXCEPTION 'CONTRACT VIOLATED: the job that owns the 08:00 push queued a second one';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;

-- 4. Unchanged: a fresh daytime job queues its push; its retry hits the index.
DO $$
BEGIN
  IF pg_temp.chat_push(3, '2026-11-11 09:10+00') IS NULL OR pg_temp.pushes_for(3) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh daytime job did not queue its push';
  END IF;
  BEGIN
    PERFORM pg_temp.chat_push(3, '2026-11-11 09:11+00');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retried daytime job queued a second push';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;

-- 5. The marker: set for every job whose push the queue accepted, written
--    or folded; unset for a job that never queued one.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.message_notification_outbox
             WHERE id IN ('c2410000-0000-0000-0000-000000000201', 'c2410000-0000-0000-0000-000000000202',
                          'c2410000-0000-0000-0000-000000000203')
               AND push_queued_at IS NULL)
     OR (SELECT push_queued_at FROM public.message_notification_outbox
         WHERE id = 'c2410000-0000-0000-0000-000000000206') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: push_queued_at does not track queued jobs';
  END IF;
END $$;

-- 6. A failed insert leaves no marker (it rolls back with the statement),
--    so the job's retry still queues its push.
DO $$
DECLARE v_dummy int;
BEGIN
  BEGIN
    INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata)
    VALUES ('c2410000-0000-0000-0000-0000000000b2', 'immediate', '2026-11-11 09:20+00', 'pending',
            jsonb_build_object('type', 'new_message', 'title', 'New message in Attune',
                               'body', 'Open Attune to read it.',
                               'relationship_id', 'c2410000-0000-0000-0000-000000000001',
                               'outbox_id', 'c2410000-0000-0000-0000-000000000206'))
    RETURNING 1 / 0 INTO STRICT v_dummy;
  EXCEPTION WHEN division_by_zero THEN NULL;
  END;
  IF (SELECT push_queued_at FROM public.message_notification_outbox
      WHERE id = 'c2410000-0000-0000-0000-000000000206') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed push insert left the job marked';
  END IF;
  IF pg_temp.chat_push(6, '2026-11-11 09:21+00') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the retry after a failed insert queued nothing';
  END IF;
END $$;

-- 7. Mutation check: without the trigger, check 2 is violated.
SAVEPOINT mutate_drop;
DROP TRIGGER scheduled_notifications_chat_job_once ON public.scheduled_notifications;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.check_folded_replay(2, '2026-11-11 09:00+00');
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'CONTRACT VIOLATED: a folded overnight job%' THEN RAISE; END IF;
    RAISE NOTICE 'mutation check: without scheduled_notifications_chat_job_once a folded job re-pushes (as intended)';
    RETURN;
  END;
  RAISE EXCEPTION 'MUTATION NOT DETECTED: check 2 passed without the trigger';
END $$;
ROLLBACK TO SAVEPOINT mutate_drop;

-- 8. Mutation check: the marker must be written BEFORE the quiet guard
--    runs (BEFORE triggers fire in name order; the guard's RETURN NULL
--    skips every later one). Renamed to sort after it, a fresh overnight
--    fold is not recorded and its daytime replay re-pushes.
SAVEPOINT mutate_order;
ALTER TRIGGER scheduled_notifications_chat_job_once ON public.scheduled_notifications
  RENAME TO scheduled_notifications_zz_chat_job_once;
DO $$
BEGIN
  IF pg_temp.chat_push(4, '2026-11-11 23:00+00') IS NULL
     OR pg_temp.chat_push(5, '2026-11-11 23:05+00') IS NOT NULL THEN
    RAISE EXCEPTION 'mutation check broken: the second overnight collapse did not happen';
  END IF;
  BEGIN
    PERFORM pg_temp.check_folded_replay(5, '2026-11-12 09:00+00');
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'CONTRACT VIOLATED: a folded overnight job%' THEN RAISE; END IF;
    RAISE NOTICE 'mutation check: a marker written after the quiet guard misses the fold (as intended)';
    RETURN;
  END;
  RAISE EXCEPTION 'MUTATION NOT DETECTED: check 2 passed with the trigger after the quiet guard';
END $$;
ROLLBACK TO SAVEPOINT mutate_order;

-- 9. The same second night with the trigger in place holds (control for 8).
DO $$
BEGIN
  IF pg_temp.chat_push(4, '2026-11-11 23:00+00') IS NULL
     OR pg_temp.chat_push(5, '2026-11-11 23:05+00') IS NOT NULL THEN
    RAISE EXCEPTION 'fixture broken: the second overnight collapse did not happen';
  END IF;
  PERFORM pg_temp.check_folded_replay(5, '2026-11-12 09:00+00');
END $$;

DO $$ BEGIN RAISE NOTICE 'chat_push_replay_contracts: all held'; END $$;
ROLLBACK;
