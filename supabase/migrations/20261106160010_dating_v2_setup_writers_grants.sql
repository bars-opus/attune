-- Spec 2 W1c: grants for 20261106160000_dating_v2_setup_writers.sql. The
-- D2-D8 writers are the signed-in app's (they take the actor from
-- auth.uid()) and no one else's, the service role included (batch-2
-- carry); their helpers, private.dating_clear_faith (PF-F3) and the two
-- lock helpers (I-5) among them, and batch 8's three (I-2: sorted locks,
-- "plain", the other-countries prune), are the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.dating_setup_guard(), private.dating_ensure_profile(uuid),
  private.dating_same_gender_on(text), private.dating_default_ages(integer), private.dating_invalid(text),
  private.dating_clear_faith(uuid), private.dating_lock_setup(uuid), private.dating_lock_same_gender(text),
  private.dating_lock_same_gender_all(text[]), private.dating_profile_plain(jsonb, jsonb),
  private.dating_prune_unsafe_abroad(uuid), private.dating_lock_setup(uuid, text[]) -- W1 final fix (I-1)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.save_dating_intention(text, text, text, boolean, boolean, text, boolean),
  public.save_dating_location(text, text, text, text, text),
  public.save_dating_identity(text, text, text, text, text[], boolean),
  public.save_dating_who_to_meet(text, text[], integer, integer),
  public.save_dating_children(text, boolean, text, boolean, boolean),
  public.save_dating_faith(text, text, text, text, boolean),
  public.clear_dating_faith(text)
  FROM PUBLIC, anon, service_role;
-- The writers are the signed-in app's only: the service role runs none
-- (S-4: hosted projects grant new functions to the service role by
-- default; the two that decrypt, D5 and D6, above all; batch-2 carry).
GRANT EXECUTE ON FUNCTION
  public.save_dating_intention(text, text, text, boolean, boolean, text, boolean),
  public.save_dating_location(text, text, text, text, text),
  public.save_dating_identity(text, text, text, text, text[], boolean),
  public.save_dating_who_to_meet(text, text[], integer, integer),
  public.save_dating_children(text, boolean, text, boolean, boolean),
  public.save_dating_faith(text, text, text, text, boolean),
  public.clear_dating_faith(text)
  TO authenticated;
COMMIT;
