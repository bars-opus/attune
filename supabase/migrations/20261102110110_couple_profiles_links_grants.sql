-- Spec 1 W5: grants for 20261102110100_couple_profiles_links.sql, the
-- four re-created functions' grants exactly as before: the accept and the
-- bundle are the service role's (accept-invite, the export worker); the
-- path writer and one relationship's export are server-only.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.accept_relationship_invite_v2(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_relationship_invite_v2(uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.set_user_path_internal(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_relationship(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.export_bundle(uuid, uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.export_bundle(uuid, uuid[]) TO service_role;
COMMIT;
