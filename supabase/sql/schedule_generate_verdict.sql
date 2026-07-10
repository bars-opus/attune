-- Run in Supabase SQL editor after enabling pg_cron and pg_net.
-- Configure app.settings.supabase_url and app.settings.service_role_key first.

SELECT cron.schedule(
  'generate-verdict-monthly',
  '7 0 1 * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/generate-verdict',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', current_setting('app.settings.service_role_key')
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);
