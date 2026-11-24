-- Spec 2 W10: grants for 20261124100000_dating_v2_launch_guards.sql. The
-- readiness and the console's reads are the service role's alone (the
-- owner's SQL editor, dating-moderation); the helpers are the database's
-- own. The five re-created functions keep their grants.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.is_dev_reference(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.is_real_reference(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_launch_gates(text[], public.country_safety_config) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_launch_readiness(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_dating_launch_readiness(text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_launch_readiness(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_launch_readiness(uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_metrics(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_metrics(uuid, integer) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_fairness(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_fairness(uuid, integer) TO service_role;
COMMIT;
