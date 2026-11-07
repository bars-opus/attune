-- Spec 2 W2: grants for 20261107120000_dating_v2_gentle_wait.sql.
-- The open date, the eligibility, the candidate check and the gate cron are
-- the database's own (no API role, the service role included); the two app
-- RPCs keep exactly their W1 grants (authenticated only); Healing's two
-- functions keep theirs (the app's readiness submit; the internal refresh).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.dating_gentle_wait_opens_at(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_eligibility(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_candidate_is_current(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.enforce_dating_lifecycle_gates() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.begin_dating_enrollment(text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.begin_dating_enrollment(text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_dating_eligibility() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_eligibility() TO authenticated;
-- Fix round 1 (I-1): seal_my_side keeps its Spec 3a grants (the app's, signed in).
REVOKE ALL ON FUNCTION public.seal_my_side(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.seal_my_side(uuid) TO authenticated;
COMMIT;
