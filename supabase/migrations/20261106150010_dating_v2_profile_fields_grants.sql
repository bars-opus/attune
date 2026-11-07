-- Spec 2 W1c: grants for 20261106150000_dating_v2_profile_fields.sql.
-- dating_profile_sensitive is no API role's, the service role's included
-- (S-5, §4.2), at table and column level (REVOKE ALL on a table also
-- revokes its column grants; batch-6 fix round 1, I-1); prompts and settings are the service role's (moderation,
-- W7) and no client's; the key and consent helpers are definer-only.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_profile_sensitive FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL (user_id, identity_enc, seeking_enc, faith_enc, marital_enc, key_version, updated_at)
  ON public.dating_profile_sensitive FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON public.dating_prompts, public.dating_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dating_prompts, public.dating_settings TO service_role;
REVOKE ALL ON FUNCTION public.dating_require_trusted_device(), private.dating_field_key_present(),
  private.dating_field_encrypt(jsonb), private.dating_field_decrypt(bytea),
  private.dating_consent_granted(uuid, text), private.dating_profiles_display_name_guard()
  FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
