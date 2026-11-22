-- Spec 2 W7a: grants for 20261121100000_dating_v2_reports.sql. The
-- evidence, the case links and the appeals are no API role's, the service
-- role included (the console reaches them through W7b's definer
-- functions); the two report RPCs, the restricted person's read and the
-- appeal are the app's; every helper and the console's decisions are the
-- database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON TABLE public.dating_report_evidence FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.dating_case_matches FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.dating_appeals FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_priority(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_sla_due(text, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_defaults() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_restriction_defaults() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_reporter_tripped(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_excluded(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_snapshot_evidence(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_case(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_corroborated(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_place_restriction(uuid, text, text, text, uuid, uuid, timestamptz, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_file_report(uuid, uuid, text, uuid, uuid, text, text, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_answer(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_release_suspension(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.report_dating_match(text, uuid, text, text, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.report_dating_match(text, uuid, text, text, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.report_dating_introduction(text, uuid, text, text, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.report_dating_introduction(text, uuid, text, text, boolean) TO authenticated;
REVOKE ALL ON FUNCTION private.dating_close_case(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
-- Fix round 1 (I-1, M-1, M-8): the database's own.
REVOKE ALL ON FUNCTION private.dating_report_retrip(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_report_reply(uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_blocked_since(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
-- Fix round 2 (N-1): the database's own.
REVOKE ALL ON FUNCTION private.dating_lock_setup_pair(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
-- Task 2: the restricted person's read and the appeal are the app's; the
-- carry-over, the release cron and the appeal's decision are the database's own.
REVOKE ALL ON FUNCTION private.dating_carry_over(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_release_expired_suspensions() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_appeal_accepted(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_decide_appeal(uuid, uuid, boolean, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_restriction() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_restriction() TO authenticated;
REVOKE ALL ON FUNCTION public.submit_dating_appeal(text, uuid, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.submit_dating_appeal(text, uuid, text) TO authenticated;
-- Task 2 (N2-1): the report's limit read is the database's own.
REVOKE ALL ON FUNCTION private.dating_report_limited(uuid) FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
