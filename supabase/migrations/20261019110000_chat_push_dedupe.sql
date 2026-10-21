-- supabase/migrations/20261019110000_chat_push_dedupe.sql
--
-- Chat review #17 (07 M-3): one push per chat outbox job, whatever the
-- worker's retries do. process-chat-notification-outbox queued its push,
-- then marked the job done; a failure between the two put the job back to
-- pending and the retry queued a second push with a new id (the OneSignal
-- Idempotency-Key is per queued row, so it did not help). The outbox id
-- already travels in metadata; it is now unique there, and the worker
-- treats a duplicate as "already queued". Same for the in-app copy.
--
-- Why not source_key: scheduled_notifications_quiet_guard keeps an
-- inserter's own source_key and then does NOT collapse that push into the
-- one 08:00 overnight push (quiet_hours_contracts.sql check 10; Spec 1b
-- owner decision D2). A metadata key leaves the collapse untouched: the
-- collapsed row keeps the first job's outbox_id, later jobs return NULL
-- from the guard (no row, no conflict), and a retried first job at night
-- joins the existing row before the index is consulted.
--
-- History first: any double pushes already queued would block the index.
-- The oldest row per job is kept (that is the one that was sent).
DELETE FROM public.scheduled_notifications s
USING public.scheduled_notifications k
WHERE s.metadata ? 'outbox_id' AND k.metadata ? 'outbox_id'
  AND s.metadata->>'outbox_id' = k.metadata->>'outbox_id'
  AND s.id <> k.id
  AND (s.created_at, s.id) > (k.created_at, k.id);

DELETE FROM public.in_app_notifications s
USING public.in_app_notifications k
WHERE s.data ? 'outbox_id' AND k.data ? 'outbox_id'
  AND s.user_id = k.user_id
  AND s.data->>'outbox_id' = k.data->>'outbox_id'
  AND s.id <> k.id
  AND (s.created_at, s.id) > (k.created_at, k.id);

CREATE UNIQUE INDEX IF NOT EXISTS scheduled_notifications_chat_outbox_idx
  ON public.scheduled_notifications ((metadata->>'outbox_id'))
  WHERE metadata ? 'outbox_id';

CREATE UNIQUE INDEX IF NOT EXISTS in_app_notifications_chat_outbox_idx
  ON public.in_app_notifications (user_id, (data->>'outbox_id'))
  WHERE data ? 'outbox_id';
