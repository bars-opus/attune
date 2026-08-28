-- Repairs an ordering bug found by running the SQL contract tests against a
-- clean database for the first time.
--
-- 20260705150000_chat_worker_hardening adds notification_settings'
-- chat_message_preview_enabled column, but guards the ALTER on the table
-- already existing. notification_settings is not created until
-- 20260705162000_notification_engine_baseline -- twelve minutes later in
-- migration order -- so on any database built from scratch the guard finds
-- no table, skips silently, and the column is never created.
--
-- This is not merely a test-fixture problem: NotificationRepositoryImpl
-- writes 'chat_message_preview_enabled' in its insert payload, so creating
-- a user's notification settings fails outright wherever the column is
-- missing. Existing deployments that ran the migrations in a different
-- order may already have it, hence IF NOT EXISTS.
ALTER TABLE public.notification_settings
  ADD COLUMN IF NOT EXISTS chat_message_preview_enabled boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.notification_settings.chat_message_preview_enabled IS
  'Whether message text appears in push notifications. Added late: the '
  'original ALTER in 20260705150000 ran before the table existed.';
