-- Spec 1 W6b: grants for 20261103110000_birth_date_correction.sql. The two
-- RPCs are the signed-in app's; the rule is server-only.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.birth_date_correction_open(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.correct_my_birth_date(date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_birth_date_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.correct_my_birth_date(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_birth_date_status() TO authenticated;
COMMIT;
