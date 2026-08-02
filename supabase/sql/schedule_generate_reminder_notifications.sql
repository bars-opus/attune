-- supabase/sql/schedule_generate_reminder_notifications.sql
--
-- Daily at 07:00 UTC. Calls the RPC directly (not via net.http_post to an
-- edge function) — matches schedule_dating_maintenance.sql's RPC-direct
-- shape, since generate_reminder_notifications() is a plain SQL/plpgsql
-- function with no need for edge-function runtime.
SELECT cron.schedule(
  'generate-reminder-notifications',
  '0 7 * * *',
  $$ SELECT public.generate_reminder_notifications(); $$
);
