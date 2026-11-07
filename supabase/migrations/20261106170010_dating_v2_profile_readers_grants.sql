-- Spec 2 W1c: grants for 20261106170000_dating_v2_profile_readers.sql. The
-- writers and the two own-profile readers are the signed-in app's; the
-- service role runs none of them (S-4, batch-2 carry: hosted projects grant
-- every new function to it by default).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION
  public.save_dating_prompts(text, jsonb), public.save_dating_display_name(text, text),
  public.save_dating_family_involvement(text, text), public.save_dating_settings(text, jsonb),
  public.set_dating_open_abroad(text, char(2)[]), public.set_dating_photos_after_mutual(text, boolean),
  public.get_my_dating_profile(), public.get_dating_profile_preview()
  FROM PUBLIC, anon, service_role;
-- Batch 8 fix round 1 (M-1): the text helpers are the database's own.
REVOKE ALL ON FUNCTION private.dating_trim(text), private.dating_has_invisible(text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  public.save_dating_prompts(text, jsonb), public.save_dating_display_name(text, text),
  public.save_dating_family_involvement(text, text), public.save_dating_settings(text, jsonb),
  public.set_dating_open_abroad(text, char(2)[]), public.set_dating_photos_after_mutual(text, boolean),
  public.get_my_dating_profile(), public.get_dating_profile_preview()
  TO authenticated;
COMMIT;
