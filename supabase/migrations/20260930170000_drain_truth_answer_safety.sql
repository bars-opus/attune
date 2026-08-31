-- Drains the truth-answer safety outbox.
--
-- Without this the trigger queues rows nobody reads, which is worse than
-- no safety net: it looks implemented.
--
-- Every 2 minutes rather than the deletion queue's 10. The reader may be
-- looking at the answer within seconds, and resources arriving after they
-- have moved on are resources that did not help.
DO $$
BEGIN
  PERFORM cron.unschedule('drain-truth-answer-safety');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

SELECT cron.schedule(
  'drain-truth-answer-safety',
  '*/2 * * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/process-truth-answer-safety',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'apikey', current_setting('app.settings.service_role_key')
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);
