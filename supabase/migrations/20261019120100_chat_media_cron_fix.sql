-- Chat review 2026-10-18 #24: 20260907120000 registered
-- 'recover-stale-chat-workers' and 'cleanup-expired-chat-media' as
-- invoke_edge_function('process-chat-media'). That worker never calls
-- recover_stale_chat_worker_leases() or cleanup_expired_chat_media_intents(),
-- so stranded 'processing' rows were never recovered and abandoned upload
-- intents' objects were never swept. Both are SECURITY DEFINER SQL
-- functions: schedule them directly (no HTTP hop, no service-role key),
-- like the pure-SQL maintenance block at the end of 20260907120000.
--
-- recover_stale_chat_worker_leases() (20260705200000) already covers the
-- push pipeline as well as media: message_safety_outbox,
-- message_notification_outbox, message_media_processing_outbox and
-- scheduled_notifications rows left in 'processing' for more than 5
-- minutes go back to 'pending' (dead_letter / failed after 5 attempts).
-- Reviving this job is what makes that recovery run at all (plan 1b final
-- review M1 carry).
--
-- Idempotent: unschedule by name first (cron.schedule errors on a
-- duplicate jobname). Guarded so a database without pg_cron (a bare local
-- scratch DB) applies the migration without error — the hosted project
-- has pg_cron from 20260907120000.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron not installed; chat media maintenance jobs not scheduled here';
    RETURN;
  END IF;

  PERFORM cron.unschedule(jobid) FROM cron.job
  WHERE jobname IN ('recover-stale-chat-workers', 'cleanup-expired-chat-media');

  PERFORM cron.schedule(
    'recover-stale-chat-workers',
    '*/5 * * * *',
    'SELECT * FROM public.recover_stale_chat_worker_leases();'
  );

  PERFORM cron.schedule(
    'cleanup-expired-chat-media',
    '17 * * * *',
    'SELECT public.cleanup_expired_chat_media_intents();'
  );
END $$;
