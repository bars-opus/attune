-- Spec 2 W5c: grants for 20261119120000_dating_v2_signals.sql. The queue and
-- the fairness reports are the service role's (W7b's console), never a
-- client's; the signal helpers and the fairness job are the database's
-- own (the job decrypts, S-4); the Other countries read is the app's.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_moderation_cases, public.dating_fairness_reports FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dating_moderation_cases, public.dating_fairness_reports TO service_role;
REVOKE ALL ON FUNCTION private.dating_open_signal_case(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_first_messages(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_dragnet_holds(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_device_accounts_hold(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_run_signals(timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_throttled(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_signal_cleared(uuid, text, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_generation_removed(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_fairness_weekly(date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_abroad_options() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_abroad_options() TO authenticated;
-- Spec 2 W5 final: the re-created partition and the frozen-config trigger are the database's own.
REVOKE ALL ON FUNCTION private.dating_generate_partition(text, text, text, date, timestamptz, text, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_config_active_frozen() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
