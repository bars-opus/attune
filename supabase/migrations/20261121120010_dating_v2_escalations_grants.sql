-- Spec 2 W7c: grants for 20261121120000_dating_v2_escalations.sql. The
-- escalations and the law-enforcement log are no API role's; the console's
-- functions are the service role's alone (the dating-moderation edge
-- function's; the database refuses all but the safety owner on the log,
-- the summary and the CSAM hold lift); the summary's query and the purge's
-- case check are the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON TABLE public.dating_escalations FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.law_enforcement_requests FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_transparency_summary(date, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_case_needed(uuid, timestamp with time zone) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.moderation_record_escalation(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_record_escalation(uuid, uuid, text, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_le_requests(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_le_requests(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_record_le_request(uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_record_le_request(uuid, uuid, jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_transparency_summary(uuid, date, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_transparency_summary(uuid, date, date) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_csam_holds(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_csam_holds(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_lift_csam_hold(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_lift_csam_hold(uuid, uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_case_escalations(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_case_escalations(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION private.dating_case_awaiting_id(text, timestamp with time zone) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.moderation_close_no_id(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_close_no_id(uuid, uuid) TO service_role;
-- W7 final server fix: the queue by kind (I-3; the 2-argument queue is
-- dropped, so its W7b grant line moved here) is the service role's; the ID
-- check's helpers, the backfill and the SLA alert's request ids are the
-- database's own.
REVOKE ALL ON FUNCTION public.moderation_queue(uuid, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_queue(uuid, integer, text) TO service_role;
REVOKE ALL ON FUNCTION private.dating_id_check_code() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_case_id_check(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_case_id_check_json(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_end_id_check(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_place_id_check(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_backfill_report_cases() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_closer_look_carried(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
-- Round 2 (re-review 1, N-1): Lift the case's holds is the service role's.
REVOKE ALL ON FUNCTION public.moderation_lift_case_holds(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_lift_case_holds(uuid, uuid) TO service_role;
-- Round 4 (N3-1): the orphaned ID check's record test is the database's own.
REVOKE ALL ON FUNCTION private.dating_case_id_record_live(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE private.dating_sla_alert_requests FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
