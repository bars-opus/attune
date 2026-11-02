-- Spec 1 W3c: grants for 20261026100000_journal_reminders.sql. The owner
-- reads their own row (RLS) and writes only through the RPC; the worker
-- (service role) keeps DML; the enqueue function is the cron's and the
-- service role's only (granted explicitly, B6 review N-4).
BEGIN;
REVOKE ALL ON public.journal_reminder_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.journal_reminder_settings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.journal_reminder_settings TO service_role;

REVOKE ALL ON FUNCTION public.set_my_journal_reminder(boolean, smallint, time) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_journal_reminder() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.enqueue_journal_reminders(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_my_journal_reminder(boolean, smallint, time) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_journal_reminder() TO authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_journal_reminders(timestamptz) TO service_role;
COMMIT;
