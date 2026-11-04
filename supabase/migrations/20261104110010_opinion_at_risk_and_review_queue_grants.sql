-- Spec 1 W9b: grants for 20261104110000_opinion_at_risk_and_review_queue.sql.
-- The two report RPCs keep their live grants (signed-in only); review queue
-- v0 is the service role's (and the SQL editor's) only; forum_reports is
-- written only by the report RPCs (fix round 1, C-1); report_count moves
-- only through the report RPCs (batch-6 ruling: the unowned
-- increment_opinion_report_count loses its client EXECUTE).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.assert_valid_report_reason(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.is_priority_reason(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.report_opinion(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.report_opinion_comment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_opinion(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_opinion_comment(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_list_priority_reports(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_priority_reports(int) TO service_role;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.forum_reports FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.increment_opinion_report_count(uuid) FROM PUBLIC, anon, authenticated;
COMMIT;
