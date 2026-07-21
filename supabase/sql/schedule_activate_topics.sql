-- supabase/sql/schedule_activate_topics.sql
-- Run in Supabase SQL editor after enabling pg_cron and pg_net.
-- Configure app.settings.supabase_url and app.settings.service_role_key first.
--
-- FORUM.md §5.3 requires this to run hourly; no schedule previously existed
-- for this function, so activation only ever happened via the client's
-- opportunistic call to activate_pending_topics() on forum-list load.

SELECT cron.schedule(
  'activate-topics-sweep',
  '23 * * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/activate-topics',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'apikey', current_setting('app.settings.service_role_key')
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);
