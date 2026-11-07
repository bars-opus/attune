-- Spec 2 W1b: grants for 20261106140000_dating_v2_eligibility_base.sql.
-- All three are the database's own: clients see eligibility only through
-- get_dating_home() (W2), the summary through Spec 1's get_my_home_state(),
-- and the country checks through publish_country_config (a definer).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.dating_eligibility(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_home_summary(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.country_config_checks(public.country_safety_config) FROM PUBLIC, anon, authenticated, service_role;
-- Fix round 1: the key-readiness predicate, the owner-only seeder and the
-- mismatch check are no API role's (the seeder is the owner's alone, M-4).
REVOKE ALL ON FUNCTION private.dating_exclusion_key_ready() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.seed_dating_exclusion_key_fingerprint() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_exclusion_key_mismatch() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
