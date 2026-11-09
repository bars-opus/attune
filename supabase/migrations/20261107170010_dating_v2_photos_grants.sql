-- Spec 2 W3c: grants for 20261107170000_dating_v2_photos.sql. R11, R-2: the
-- photo and intent tables lose the client SELECT (table and any column
-- grant). The photo RPCs and the two storage predicates are the app's
-- (the predicates run inside the storage policies as the signed-in role);
-- the CSAM recorder is the service role's alone.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE SELECT ON TABLE public.dating_profile_photos, public.dating_photo_upload_intents FROM authenticated, anon;
DO $cols$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT DISTINCT c.table_name, c.column_name, c.grantee
             FROM information_schema.column_privileges AS c
            WHERE c.table_schema = 'public' AND c.privilege_type = 'SELECT'
              AND c.grantee IN ('authenticated', 'anon')
              AND c.table_name IN ('dating_profile_photos', 'dating_photo_upload_intents') LOOP
    EXECUTE format('REVOKE SELECT (%I) ON TABLE public.%I FROM %I', r.column_name, r.table_name, r.grantee);
  END LOOP;
END $cols$;
REVOKE ALL ON FUNCTION public.create_dating_photo_upload_intent(text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.insert_dating_profile_photo(uuid, smallint) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.list_dating_profile_photos() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.delete_dating_profile_photo(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.reorder_dating_photos(text, uuid[]) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.set_dating_photo_caption(uuid, text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.dating_storage_intent_open(text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.dating_storage_owns(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.create_dating_photo_upload_intent(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.insert_dating_profile_photo(uuid, smallint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_dating_profile_photos() TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_dating_profile_photo(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reorder_dating_photos(text, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_dating_photo_caption(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dating_storage_intent_open(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dating_storage_owns(text) TO authenticated;
REVOKE ALL ON FUNCTION public.record_dating_photo_csam(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_dating_photo_csam(uuid, text) TO service_role;
-- Spec 2 W3c (Task 9, B; R-25): a gone hit's Dating hold is the photo worker's alone.
REVOKE ALL ON FUNCTION public.record_dating_csam_hold(uuid) FROM PUBLIC, anon, authenticated; -- Spec 2 W3c (Task 9, B)
GRANT EXECUTE ON FUNCTION public.record_dating_csam_hold(uuid) TO service_role; -- Spec 2 W3c (Task 9, B)
-- I-14: the orphan sweep is the photo worker's (the service role's) only.
REVOKE ALL ON FUNCTION public.claim_dating_orphan_uploads(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_orphan_scan(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_dating_orphan_uploads(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_orphan_scan(uuid, text) TO service_role;
-- Spec 2 W3c (C, M-11): the photo guard helper and has_data are the
-- database's own (the RPCs and get_dating_home call them).
REVOKE ALL ON FUNCTION private.dating_photo_setup_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_has_data(uuid) FROM PUBLIC, anon, authenticated, service_role;
-- Spec 2 W3c (fix round 1, M-7): the hit-final trigger function is the database's own.
REVOKE ALL ON FUNCTION private.dating_photo_hit_final() FROM PUBLIC, anon, authenticated, service_role;
-- Spec 2 W3 final (M-7, M-3): the photo consent helper and the bucket-limit
-- Spec 2 W3 final helper are the database's own; (M-5) the strip check is the
-- Spec 2 W3 final photo worker's (the service role's) alone.
REVOKE ALL ON FUNCTION private.dating_photo_allowed(uuid) FROM PUBLIC, anon, authenticated, service_role; -- Spec 2 W3 final (M-7)
REVOKE ALL ON FUNCTION private.dating_photo_bucket_limits() FROM PUBLIC, anon, authenticated, service_role; -- Spec 2 W3 final (M-3)
REVOKE ALL ON FUNCTION public.check_dating_photo_strip(uuid, text, text) FROM PUBLIC, anon, authenticated; -- Spec 2 W3 final (M-5)
GRANT EXECUTE ON FUNCTION public.check_dating_photo_strip(uuid, text, text) TO service_role; -- Spec 2 W3 final (M-5)
COMMIT;
