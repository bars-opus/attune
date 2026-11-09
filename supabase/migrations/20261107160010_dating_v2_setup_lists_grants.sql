-- Spec 2 W3b: grants for 20261107160000_dating_v2_setup_lists.sql. The
-- lists RPC is the app's (authenticated only).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.get_dating_setup_lists() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_setup_lists() TO authenticated;
COMMIT;
