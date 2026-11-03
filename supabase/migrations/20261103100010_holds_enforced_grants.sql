-- Spec 1 W6a: grants for 20261103100000_holds_enforced.sql. The home state
-- stays the app's; no client deletes a users row (M-6).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.get_my_home_state() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_home_state() TO authenticated;
REVOKE DELETE ON public.users FROM PUBLIC, anon, authenticated;
COMMIT;
