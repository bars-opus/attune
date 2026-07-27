-- supabase/sql/schedule_forum_quiet_check.sql
-- Run in Supabase SQL editor after enabling pg_cron and pg_net.
-- Configure app.settings.supabase_url and app.settings.service_role_key first.
--
-- Drives FORUM.md §10 #6 ("Debate going quiet") -- the notify half only.
--
-- The active -> quiet status transition itself (§11 step 35) is NOT done by
-- this job. It's already performed by a pre-existing `mark-quiet-forums`
-- pg_cron job (daily at 1am, no migration/source file in this repo -- found
-- only by querying cron.job; see
-- supabase/sql/patch_mark_quiet_forums_null_last_post.sql for a fix applied
-- to it). This job only polls for topics already sitting at status='quiet'
-- and queues their participant notifications.
--
-- Interval: every 2 hours, offset to :07 so it never lands on the hour and
-- can't collide with activate-topics' hourly run ('23 * * * *'). Since the
-- transition itself only runs once a day, polling for it more often than
-- that buys nothing -- this just bounds how long a topic sits at
-- quiet_notification_sent=false before its participants hear about it.
--
-- Note there is no companion schedule for notification #5 (forum activity):
-- that one is queued synchronously from inside create_forum_post, so it needs no
-- cron of its own. Both #5 and #6 rely on the already-scheduled
-- process-scheduled-notifications job for actual delivery -- see the
-- "process-scheduled-notifications is not currently registered" finding
-- alongside this patch; #5/#6 will queue but not deliver until that's fixed.

SELECT cron.schedule(
  'forum-quiet-check',
  '7 */2 * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/forum-quiet-check',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'apikey', current_setting('app.settings.service_role_key')
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);
