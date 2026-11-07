-- Spec 2 W1a: grants for 20261106100000_dating_v2_phone_hmac.sql. The HMAC
-- helpers, the predicate and the recompute are the database's own; the
-- recorder and the backfill stay the service role's (as live); no client
-- reaches any of them.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.dating_phone_canonical(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_phone_hmac_for_user(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_former_partner_excluded(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_dating_former_partner_exclusion(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.backfill_dating_former_partner_exclusions() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.dating_recompute_former_partner_exclusions() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_former_partner_exclusion(uuid, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.backfill_dating_former_partner_exclusions() TO service_role;
COMMIT;
