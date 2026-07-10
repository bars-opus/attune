-- Schedule process-scheduled-notifications via pg_cron.
--
-- Without this, the WhatsApp confirmation / reminder rows that
-- paystack-webhook + stripe-webhook insert into scheduled_notifications
-- sit forever in status=pending. The worker has to be invoked to drain
-- them.
--
-- Runs every minute. The function atomically claims up to 50 rows per
-- invocation (claim_pending_notifications RPC, FOR UPDATE SKIP LOCKED),
-- so overlapping cron runs are safe. WhatsApp confirmations are inserted
-- with scheduled_for = NOW(), so the worst-case delay between payment
-- and confirmation message is ~60s.

DO $$
DECLARE
  v_url     text;
  v_secret  text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron extension not installed — skipping scheduler cron';
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RAISE NOTICE 'pg_net extension not installed — skipping scheduler cron';
    RETURN;
  END IF;

  -- Service role key is needed to invoke the edge function. Stored in
  -- vault.secrets by Supabase under the same name.
  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key'
  LIMIT 1;

  IF v_secret IS NULL THEN
    -- Fallback: read from project_url + service_role via current settings.
    -- On Supabase the project URL is available as a GUC.
    v_secret := current_setting('app.settings.service_role_key', true);
  END IF;

  -- Project URL — derive from the request hostname, or read from settings.
  v_url := current_setting('app.settings.supabase_url', true);
  IF v_url IS NULL OR v_url = '' THEN
    -- Hard-code as a last resort (project ref is stable per environment).
    v_url := 'https://kbmjwicdffpuowymkobo.supabase.co';
  END IF;

  -- Unschedule any existing job with the same name so re-runs of the
  -- migration don't stack duplicates.
  PERFORM cron.unschedule('process-scheduled-notifications')
  WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'process-scheduled-notifications'
  );

  PERFORM cron.schedule(
    'process-scheduled-notifications',
    '* * * * *',  -- every minute
    format($cron$
      SELECT net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 30000
      );
    $cron$, v_url || '/functions/v1/process-scheduled-notifications', v_secret)
  );

  RAISE NOTICE 'Scheduled process-scheduled-notifications every minute';
END $$;
