SELECT cron.schedule(
  'process-chat-media',
  '* * * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/process-chat-media',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer '||current_setting('app.settings.service_role_key'),
      'apikey',current_setting('app.settings.service_role_key')
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);

SELECT cron.schedule(
  'recover-stale-chat-workers',
  '*/5 * * * *',
  $$ SELECT * FROM public.recover_stale_chat_worker_leases(); $$
);

SELECT cron.schedule(
  'cleanup-expired-chat-media',
  '17 * * * *',
  $$ SELECT public.cleanup_expired_chat_media_intents(); $$
);
