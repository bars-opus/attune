-- Spec 2 W1d: grants for 20261106190000_dating_v2_lifecycle.sql. The
-- lifecycle RPCs are the signed-in app's (exit_dating_mode is a new
-- signature, so its grant is new); the hard delete, readiness, the parked
-- trigger, the relationship pause and the field-key fingerprint functions
-- are the database's own (the seeder is the owner's); generation and health
-- stay the service role's. The service role is revoked on everything else
-- (batch-2 carry: hosted projects grant every new function to it), so the
-- canary pins it.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.dating_exit_internal(uuid, boolean), public.dating_profile_complete(uuid),
  public.dating_on_account_parked(), public.dating_profile_ready(uuid), public.pause_dating_for_relationship_user(uuid),
  private.dating_field_key_fingerprint(), private.dating_field_key_ready(), private.dating_field_key_usable(),
  private.seed_dating_field_key_fingerprint(), private.dating_field_encrypt(jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_dating_consent(text, text, text, text, jsonb), public.activate_dating_profile(text),
  public.pause_dating_mode(text), public.resume_dating_mode(text), public.exit_dating_mode(text, boolean)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_consent(text, text, text, text, jsonb), public.activate_dating_profile(text),
  public.pause_dating_mode(text), public.resume_dating_mode(text), public.exit_dating_mode(text, boolean)
  TO authenticated;
REVOKE ALL ON FUNCTION public.run_dating_candidate_generation(text), public.get_dating_operational_health()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_dating_candidate_generation(text), public.get_dating_operational_health() TO service_role;
COMMIT;
