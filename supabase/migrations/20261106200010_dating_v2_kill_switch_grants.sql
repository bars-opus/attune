-- Spec 2 W1d: grants for 20261106200000_dating_v2_kill_switch.sql. The
-- switch, its helpers, its pending marker, its flag trigger and the country
-- checks are the database's own (they decrypt or decide); publishing and
-- health stay the service role's; exit stays the signed-in app's. The
-- service role is revoked on everything else (batch-2 carry: hosted
-- projects grant every new function to it), so the canary pins it.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.apply_same_gender_switch(text), private.dating_same_gender_flag_off(),
  private.dating_switch_read(bytea), private.dating_switch_identity(uuid, jsonb),
  private.country_config_checks(public.country_safety_config), private.dating_kill_switch_mark(text, text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE private.dating_kill_switch_pending FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.publish_country_config(text, jsonb), public.get_dating_operational_health()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_country_config(text, jsonb), public.get_dating_operational_health() TO service_role;
REVOKE ALL ON FUNCTION public.exit_dating_mode(text, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.exit_dating_mode(text, boolean) TO authenticated;
-- W1 final fix (I-1, M-2): the re-created invalidation and deletion trigger
-- stay the database's own; D3 stays the signed-in app's.
REVOKE ALL ON FUNCTION public.invalidate_dating_for_user(uuid, text), private.dating_carry_on_auth_user_delete()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.save_dating_location(text, text, text, text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.save_dating_location(text, text, text, text, text) TO authenticated;
-- W1 final fix (M-9): the v1 draft writer has no v2 check (flag,
-- eligibility, filter) and reopens an exited or paused enrolment; no API
-- role runs it (W3b drops it; its v1 columns stay, P-22).
REVOKE ALL ON FUNCTION public.save_dating_profile_draft(text, text, text, text, text, integer, integer)
  FROM PUBLIC, anon, authenticated, service_role;
-- W1 final fix (N-I1, M-9 scope): the v1 photo-upload path checks no flag,
-- eligibility, standing or rate limit, and its bucket has no CSAM scan until
-- W3c's inline match, so no API role starts an upload (without an intent
-- the bucket's INSERT policy admits nothing). W3 re-creates both with the
-- v2 checks and the inline match; deleting one's own photo stays.
REVOKE ALL ON FUNCTION public.create_dating_photo_upload_intent(text), public.insert_dating_profile_photo(uuid, smallint)
  FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
