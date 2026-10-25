-- Spec 1 W1c: grants for 20261025100500_identity_health.sql. Service role only.
BEGIN;
REVOKE ALL ON private.unfinished_signups FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.unfinished_signup_candidates() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.is_unfinished_signup(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_identity_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.unfinished_signup_candidates() TO service_role;
GRANT EXECUTE ON FUNCTION public.is_unfinished_signup(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_identity_health() TO service_role;
COMMIT;
