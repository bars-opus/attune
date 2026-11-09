-- Spec 2 W3a: grants for 20261107150000_dating_v2_client_reads.sql.
-- R11: the 20260811120000 client SELECT on the four tables is revoked
-- (table and any column grant); the photo and intent tables keep theirs
-- until W3c moves the storage policies (R-2). The notice RPCs are the
-- app's; the push and notice helpers are no API role's; the re-created
-- functions keep their W1/W2 grants (re-asserted).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE SELECT ON TABLE public.dating_enrollments, public.dating_consent_events,
  public.dating_profiles, public.dating_preferences FROM authenticated, anon;
DO $cols$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT DISTINCT c.table_name, c.column_name, c.grantee
             FROM information_schema.column_privileges AS c
            WHERE c.table_schema = 'public' AND c.privilege_type = 'SELECT'
              AND c.grantee IN ('authenticated', 'anon')
              AND c.table_name IN ('dating_enrollments', 'dating_consent_events', 'dating_profiles', 'dating_preferences') LOOP
    EXECUTE format('REVOKE SELECT (%I) ON TABLE public.%I FROM %I', r.column_name, r.table_name, r.grantee);
  END LOOP;
END $cols$;
REVOKE ALL ON FUNCTION public.request_dating_country_notice(text, text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.cancel_dating_country_notice() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.request_dating_country_notice(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_dating_country_notice() TO authenticated;
REVOKE ALL ON FUNCTION private.dating_push_source_key(uuid, text, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_queue_me_update(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_notice_state(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_has_data(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_notify_opened(text, boolean, text[], text[]) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_notify_sweep() FROM PUBLIC, anon, authenticated, service_role; -- Spec 2 W3 final (I-3): the gate cron's own
REVOKE ALL ON FUNCTION public.get_dating_home() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_home() TO authenticated;
REVOKE ALL ON FUNCTION public.save_gentle_wait_reflection(jsonb) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.save_gentle_wait_reflection(jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.publish_country_config(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_country_config(text, jsonb) TO service_role;
COMMIT;
