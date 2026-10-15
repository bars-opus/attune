-- supabase/sql/schedule_generate_reminder_notifications.sql
--
-- Every 15 minutes (since 20261015100000_reminder_delivery_fixes.sql: each
-- partner is told from 09:00 in their own zone; this file used to say daily
-- at 07:00 UTC, and running that would undo it). Calls the RPC directly (not via net.http_post to an
-- edge function) — matches schedule_dating_maintenance.sql's RPC-direct
-- shape, since generate_reminder_notifications() is a plain SQL/plpgsql
-- function with no need for edge-function runtime.
SELECT cron.schedule(
  'generate-reminder-notifications',
  '*/15 * * * *',
  $$ SELECT public.generate_reminder_notifications(); $$
);
