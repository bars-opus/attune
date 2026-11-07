-- Spec 1 W9d: grants for 20261107100000_opinion_enforcement_records.sql.
-- admin_confirm_content_removal and prepare_account_deletion stay the
-- service role's only; the stamps table and every carry helper are no API
-- role's, the service role included (hosted projects grant it every new
-- function; S2 W1 batch-2 carry). enforcement_records keeps Spec 2 W1's
-- grants (unchanged here).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.admin_confirm_content_removal(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_confirm_content_removal(text, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.prepare_account_deletion(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_account_deletion(uuid) TO service_role;
REVOKE ALL ON TABLE private.opinion_enforcement_stamps FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_carry_window() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_stamp_enforcement(uuid, integer, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_stamp_backfill() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_deletion_carry(uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_carry_on_auth_user_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_enforcement_purge() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
