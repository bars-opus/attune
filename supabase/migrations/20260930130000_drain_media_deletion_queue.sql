-- Schedules the drain for media_deletion_queue.
--
-- 20260930120000 stopped the viewer RPCs deleting from storage.objects --
-- the platform refuses it (42501), and because the DELETE followed the
-- state change, the exception rolled back the whole view. The RPCs now
-- record what should go; nothing removed it.
--
-- Until this runs, a spent streak is unreachable through the app (its
-- streak_clips rows are gone, so there is nothing to sign a URL for) but
-- the object itself still sits in the bucket. "Destroyed after viewing" is
-- a promise this makes true.
--
-- Every 10 minutes rather than hourly: the gap between "the user watched
-- it" and "the file is gone" is the window this feature exists to close,
-- and the drain is cheap when the queue is empty (one indexed read on
-- media_deletion_queue_pending_idx).
DO $$
BEGIN
  PERFORM cron.unschedule('drain-media-deletion-queue');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

SELECT cron.schedule(
  'drain-media-deletion-queue',
  '*/10 * * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/process-media-deletion-queue',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'apikey', current_setting('app.settings.service_role_key')
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);
