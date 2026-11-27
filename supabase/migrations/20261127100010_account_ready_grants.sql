-- Entry gates: grants for 20261127100000_account_ready.sql. The helper is
-- the database's own (invite functions, policies' wrapper); the wrapper is
-- the app's, since write policies evaluate it as the signed-in caller, and
-- also the service role's (harmless: auth.uid() is NULL there, so false).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.account_ready(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.my_account_ready() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_account_ready() TO authenticated, service_role;
COMMIT;
