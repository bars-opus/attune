-- supabase/migrations/20261019120115_chat_push_once_per_job_grants.sql
-- Plan 1b final review M3: grants for 20261019120110 (trigger function only).
REVOKE ALL ON FUNCTION public.scheduled_notifications_chat_job_once() FROM PUBLIC, anon, authenticated;
