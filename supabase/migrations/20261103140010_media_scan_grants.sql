-- Spec 1 W7b: grants for 20261103140000_media_scan.sql. scan-media and
-- Spec 2's process-dating-photo (service role) work through the functions;
-- the named child-safety contact works safety_escalations (service role,
-- SQL editor; the house rule gives the service role DML on a new public
-- table). No client reaches any of it.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON private.media_scan_queue FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE private.media_scan_queue_id_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON private.media_scan_state FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON public.safety_escalations FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.safety_escalations_id_seq FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.safety_escalations TO service_role;
REVOKE ALL ON FUNCTION private.media_scan_buckets() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.enqueue_media_object(text, text, uuid, text, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.handle_csam_match(text, text, uuid, text, text, boolean, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.expire_media_scan_jobs() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.safety_escalations_due(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.media_scan_retention() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.identity_health_w7b() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.guard_unquarantined_evidence() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.release_guarded_evidence() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.guard_safety_hold_release() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.note_media_scan_enqueue_failure(text, text, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.media_derived_objects(text, text, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.media_derived_from(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.queue_derived_media_deletions(text, text, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.mark_escalation_quarantined(bigint, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.media_scan_enqueue_alerts_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_media_scan_enqueue_alerted(bigint[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_media_scan_jobs(int) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_media_scan(bigint, text, text, text, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_inline_csam_match(text, text, uuid, text, text, boolean, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.csam_escalations_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.scan_failed_escalations_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_safety_escalations_alerted(bigint[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_identity_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_media_scan_jobs(int) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_media_scan(bigint, text, text, text, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_inline_csam_match(text, text, uuid, text, text, boolean, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.csam_escalations_due() TO service_role;
GRANT EXECUTE ON FUNCTION public.scan_failed_escalations_due() TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_safety_escalations_alerted(bigint[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_identity_health() TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_escalation_quarantined(bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.media_scan_enqueue_alerts_due() TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_media_scan_enqueue_alerted(bigint[]) TO service_role;
COMMIT;
