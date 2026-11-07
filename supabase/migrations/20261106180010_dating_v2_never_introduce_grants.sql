-- Spec 2 W1d: grants for 20261106180000_dating_v2_never_introduce.sql. The
-- list is no API role's table, the service role's included (batch-9 fix
-- round 1, M-5: SELECT would read every DV victim's list, and INSERT's
-- unique error answers "has X listed this HMAC"); the three RPCs are the
-- app's way in, and any server reader is a SECURITY DEFINER function (the
-- cascade and Task 12's exit delete it). The filter helper, the typed-number
-- normaliser and its trunk table are the database's own. The service role
-- loses EXECUTE on all five functions (hosted projects grant it on every new
-- function), and no column carries its own grant.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_never_introduce FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL (id, owner_user_id, phone_hmac, label, last_two, created_at)
  ON public.dating_never_introduce FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON private.dating_phone_trunk_rules FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_typed_phone_e164(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_never_introduce_excludes(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.add_dating_never_introduce(text, text, text), public.remove_dating_never_introduce(uuid),
  public.list_dating_never_introduce() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.add_dating_never_introduce(text, text, text), public.remove_dating_never_introduce(uuid),
  public.list_dating_never_introduce() TO authenticated;
COMMIT;
