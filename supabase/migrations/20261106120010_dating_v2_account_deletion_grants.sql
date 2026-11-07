-- Spec 2 W1a: grants for 20261106120000_dating_v2_account_deletion.sql.
-- prepare_account_deletion stays the service role's (delete-account and
-- purge-recovery-holds), as 20261018110100 left it; the carry-over's private
-- table and functions are no API role's (service_role included: hosted
-- projects grant it every new function); the metric tables keep Spec 1's
-- grants (no client reads or writes them).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.prepare_account_deletion(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_account_deletion(uuid) TO service_role;
REVOKE ALL ON TABLE private.dating_restriction_hmacs FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_stamp_restriction_on_insert() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_stamp_restriction_hmacs() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_deletion_carry(uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_carry_on_auth_user_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_restriction_user_immutable() FROM PUBLIC, anon, authenticated, service_role; -- W1 final fix (M-8)
COMMIT;
