-- Spec 2 W2: grants for 20261107130000_dating_v2_path_pause.sql.
-- The trigger function is no API role's (the service role included);
-- health keeps its W1 grant (the service role's, for the edge health check);
-- begin, resume and activation (re-created here) stay the app's only; the
-- path-pause helper, eligibility and the gate cron are the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.dating_pause_on_path_change() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_operational_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_dating_operational_health() TO service_role;
REVOKE ALL ON FUNCTION public.begin_dating_enrollment(text, text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.resume_dating_mode(text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.activate_dating_profile(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.begin_dating_enrollment(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resume_dating_mode(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.activate_dating_profile(text) TO authenticated;
REVOKE ALL ON FUNCTION private.dating_apply_path_pause(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_eligibility(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.enforce_dating_lifecycle_gates() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
