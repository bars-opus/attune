-- Spec 1 W6c: grants for 20261103120000_child_safety_reports.sql. A report
-- is sent through the RPC only and read by the service role only.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.child_safety_reports FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.child_safety_reports TO service_role;
REVOKE ALL ON FUNCTION public.report_child_safety_concern(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.child_safety_alerts_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_child_safety_alerts_sent(uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.identity_health_w6a() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.report_child_safety_concern(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.child_safety_alerts_due() TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_child_safety_alerts_sent(uuid[]) TO service_role;
COMMIT;
