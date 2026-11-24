-- Spec 2 W9: grants for 20261123100000_dating_v2_couple_link.sql. The new
-- tables are nobody's (S-5: the service role's neither); the couple link's
-- reads and writes are the app's; the helpers are the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON TABLE public.dating_couple_link_requests FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.couple_how_we_met FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.dating_link_origins FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_link_on() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_link_blocked(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_link_json(public.dating_matches, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_couple_link(uuid, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_couple_link(uuid, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.request_dating_couple_link(text, uuid, boolean, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.request_dating_couple_link(text, uuid, boolean, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.decline_dating_couple_link(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.decline_dating_couple_link(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.cancel_dating_couple_link(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.cancel_dating_couple_link(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.confirm_dating_couple_link(text, uuid, boolean, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.confirm_dating_couple_link(text, uuid, boolean, boolean) TO authenticated;
-- Spec 2 W9 Task 2: the origin, How we met and the offer are the app's;
-- the export's Dating part is the service role's alone (S-4).
REVOKE ALL ON TABLE public.dating_export_reads FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_link_origin(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_link_origin(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_how_we_met(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_how_we_met(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_dating_post_link_offer() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_post_link_offer() TO authenticated;
REVOKE ALL ON FUNCTION public.dismiss_dating_post_link_offer(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.dismiss_dating_post_link_offer(text) TO authenticated;
REVOKE ALL ON FUNCTION public.dating_export_for_job(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dating_export_for_job(uuid) TO service_role;
-- Fix round 1 (C-1; S-4): no API role makes or rewrites an export job (its
-- writers are definer functions); the service role keeps SELECT
-- (get-export-url).
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.data_export_jobs FROM service_role;
COMMIT;
