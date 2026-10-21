-- supabase/migrations/20261019120050_retire_stranded_push_leases.sql
--
-- One-time, before 20261019120100 revives 'recover-stale-chat-workers'.
-- That job has run the media edge function instead of
-- recover_stale_chat_worker_leases() since 20260907120000, so any chat push
-- job or queued push stranded in 'processing' since then is still there.
-- Its first real run would put every one of them back to 'pending' and the
-- workers would send them: "New message in Attune" for messages weeks old,
-- reminders for days already gone.
--
-- A row that has been 'processing' for over an hour predates working
-- recovery (from now on nothing stays there past ~10 minutes), and a push
-- that late is noise, so it is retired instead of recovered. Rows inside
-- the hour are left for the normal 5-minute recovery. Media and safety
-- outboxes are not touched: re-running those is useful, not noisy.
-- Re-running this migration only retires what has been stranded > 1 hour,
-- which the recovery job would otherwise have recovered — harmless.

UPDATE public.message_notification_outbox
   SET state = 'dead_letter',
       processing_started_at = NULL,
       last_error_code = 'stale_lease_retired',
       completed_at = now()
 WHERE state = 'processing'
   AND processing_started_at < now() - interval '1 hour';

UPDATE public.scheduled_notifications
   SET status = 'failed',
       last_error = 'stale_lease_retired',
       updated_at = now()
 WHERE status = 'processing'
   AND updated_at < now() - interval '1 hour';
