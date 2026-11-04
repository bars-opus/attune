-- Spec 1 W9b, migration 17 (spec §4.7 #17): the "Someone may be at risk"
-- report reason and review queue v0.
--   * private.assert_valid_report_reason and private.is_priority_reason
--     re-created from their live bodies (20260802120000 and
--     20260716140000) with the one new reason added: valid, and priority.
--   * report_opinion and report_opinion_comment re-created from their live
--     bodies (20260802120000), adding only: an at-risk report is recorded
--     (priority) and never moves report_count, so it can never auto-hide
--     the post (D13: hiding a help-seeking post cuts the person off). Their
--     search_path (public, private) and grants are kept as live.
--     Two more changes in each (owner ruling (a) and pre-flight PF-C1,
--     2026-11-04), marked "Spec 1 W9b":
--       - a repeat report from the same account on the same item no longer
--         moves report_count (the live "IF NOT v_inserted" never fired:
--         ON CONFLICT DO NOTHING ... RETURNING INTO leaves v_inserted NULL,
--         and NOT NULL is not true), so one account can never auto-hide a
--         post. Not gated: it is the live comment's stated intent;
--       - an at-risk report is never dropped: an earlier report from the
--         same account on the same item (any other reason, or an at-risk
--         report a person already reviewed) is upgraded to the at-risk
--         reason (priority, pending, reviewed_at NULL, created_at now(), so
--         it is back in review queue v0), and report_count is not moved
--         again. A later ordinary report never downgrades an at-risk one,
--         and a repeat while it is pending changes nothing.
--     Every reason in the list reaches the server from both RPCs whatever
--     opinions_safety_v1 is (owner ruling (c): the app sends every comment
--     reason behind the flag, Task 8).
--   * admin_list_priority_reports(p_limit) (service role): pending priority
--     reports, at-risk first, then oldest first (batch-4 fix round 1, I-1:
--     someone who may be in danger now is never listed behind a backlog of
--     older priority reports), with the reason and a 280-character
--     excerpt; the named daily reviewer works it from the SQL editor (the
--     W9b gate). It never names the reporter.
--   * forum_reports is written only by the report RPCs (batch-4 fix round
--     1, C-1): the 20260716 INSERT grant to authenticated let any signed-in
--     account plant rows with any reason, priority and created_at, so a
--     backdated priority row would sit at the head of the queue and push
--     real at-risk reports off it. No client or edge function writes the
--     table (the app reports through report_opinion and
--     report_opinion_comment, both SECURITY DEFINER, owner-run), so INSERT,
--     UPDATE, DELETE and TRUNCATE are revoked from PUBLIC, anon and
--     authenticated. Not gated: legitimate behaviour is unchanged. SELECT
--     stays as it is (the forum_reports_no_read policy returns nothing).
--   * private.is_priority_reason loses its default PUBLIC execute (only
--     the owner-run report RPCs call it).
--   * public.increment_opinion_report_count(uuid) (20260716120000) loses
--     EXECUTE for PUBLIC, anon and authenticated (batch-6 ruling): it is
--     SECURITY DEFINER with no owner check and raises any post's
--     report_count without a report row, so one account could bring a
--     post to the auto-hide threshold, past owner ruling (a). The app has
--     not called it since 2026-07-17 (87b4173a; that call never matched
--     its parameter name) and no function calls it. Not gated.
-- Not gated: the server accepts the reason whatever opinions_safety_v1 is;
-- only the app offers it, and only with the flag on (plan P-12).
-- Nothing here tells the reported person anything.
-- Grants in 20261104110010_opinion_at_risk_and_review_queue_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private.assert_valid_report_reason(p_reason text)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_reason IS NULL OR p_reason NOT IN (
    'Identifies a real person',
    'Harmful or dangerous content',
    'Explicit sexual content',
    'Hate speech or discrimination',
    'Spam',
    'Other',
    'Someone may be at risk' -- Spec 1 W9b
  ) THEN
    RAISE EXCEPTION 'invalid_reason' USING ERRCODE = '22023';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION private.is_priority_reason(p_reason text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT p_reason IN (
    'Identifies a real person',
    'Harmful or dangerous content',
    'Hate speech or discrimination',
    'Someone may be at risk' -- Spec 1 W9b
  );
$function$;

CREATE OR REPLACE FUNCTION public.report_opinion(p_opinion_id uuid, p_reason text DEFAULT 'Other')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_count int;
  v_inserted boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  PERFORM private.assert_valid_report_reason(p_reason);

  INSERT INTO public.forum_reports (reported_by, opinion_id, reason, priority)
  VALUES (auth.uid(), p_opinion_id, p_reason, private.is_priority_reason(p_reason))
  ON CONFLICT (reported_by, opinion_id) WHERE opinion_id IS NOT NULL DO UPDATE -- Spec 1 W9b (PF-C1)
    SET reason = EXCLUDED.reason, priority = true, status = 'pending', reviewed_at = NULL, created_at = now()
    WHERE EXCLUDED.reason = 'Someone may be at risk'
      AND (forum_reports.reason <> EXCLUDED.reason OR forum_reports.status IN ('reviewed_kept', 'reviewed_removed'))
  RETURNING true INTO v_inserted;

  -- A repeat report from the same account is a silent no-op: the count must
  -- not move a second time for the same reporter.
  IF v_inserted IS NOT TRUE THEN -- Spec 1 W9b (owner a)
    RETURN;
  END IF;
  -- Spec 1 W9b (D13): an at-risk report reaches a person, never auto-hide.
  IF p_reason = 'Someone may be at risk' THEN RETURN; END IF;

  UPDATE public.opinions
  SET report_count = COALESCE(report_count, 0) + 1
  WHERE id = p_opinion_id
  RETURNING report_count INTO v_count;

  IF v_count >= 10 THEN
    UPDATE public.opinions SET hidden_pending_review = true WHERE id = p_opinion_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.report_opinion_comment(p_comment_id uuid, p_reason text DEFAULT 'Other')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_count int;
  v_inserted boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  PERFORM private.assert_valid_report_reason(p_reason);

  INSERT INTO public.forum_reports (reported_by, comment_id, reason, priority)
  VALUES (auth.uid(), p_comment_id, p_reason, private.is_priority_reason(p_reason))
  ON CONFLICT (reported_by, comment_id) WHERE comment_id IS NOT NULL DO UPDATE -- Spec 1 W9b (PF-C1)
    SET reason = EXCLUDED.reason, priority = true, status = 'pending', reviewed_at = NULL, created_at = now()
    WHERE EXCLUDED.reason = 'Someone may be at risk'
      AND (forum_reports.reason <> EXCLUDED.reason OR forum_reports.status IN ('reviewed_kept', 'reviewed_removed'))
  RETURNING true INTO v_inserted;

  IF v_inserted IS NOT TRUE THEN -- Spec 1 W9b (owner a)
    RETURN;
  END IF;
  -- Spec 1 W9b (D13): an at-risk report reaches a person, never auto-hide.
  IF p_reason = 'Someone may be at risk' THEN RETURN; END IF;

  UPDATE public.opinion_comments
  SET report_count = COALESCE(report_count, 0) + 1
  WHERE id = p_comment_id
  RETURNING report_count INTO v_count;

  IF v_count >= 10 THEN
    UPDATE public.opinion_comments SET hidden_pending_review = true WHERE id = p_comment_id;
  END IF;
END;
$$;

-- Review queue v0 (spec §4.3 W9b).
CREATE OR REPLACE FUNCTION public.admin_list_priority_reports(p_limit int DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_limit constant int := least(greatest(coalesce(p_limit, 50), 1), 200);
BEGIN
  -- As admin_confirm_content_removal: a client JWT is refused; the
  -- service role and the SQL editor (no JWT, so no role) pass. EXECUTE is
  -- the service role's only.
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(q.item ORDER BY q.at_risk DESC, q.created_at, q.id) -- Spec 1 W9b (fix round 1, I-1)
      FROM (
        SELECT r.created_at, r.id, (r.reason = 'Someone may be at risk') AS at_risk,
               jsonb_build_object(
                 'report_id', r.id,
                 'reason', r.reason,
                 'reported_at', r.created_at,
                 'content_type', CASE WHEN r.opinion_id IS NOT NULL THEN 'opinion' ELSE 'comment' END,
                 'content_id', coalesce(r.opinion_id, r.comment_id),
                 'opinion_id', coalesce(r.opinion_id, c.opinion_id), -- W9 final M-9: a comment's post, for context
                 'excerpt', left(coalesce(o.content, c.content), 280),
                 'content_removed', coalesce(o.removed_at, c.removed_at) IS NOT NULL,
                 'hidden_pending_review', coalesce(o.hidden_pending_review, c.hidden_pending_review, false)
               ) AS item
          FROM public.forum_reports AS r
          LEFT JOIN public.opinions AS o ON o.id = r.opinion_id
          LEFT JOIN public.opinion_comments AS c ON c.id = r.comment_id
         WHERE r.priority
           AND r.status = 'pending'
           AND (r.opinion_id IS NOT NULL OR r.comment_id IS NOT NULL)
         ORDER BY (r.reason = 'Someone may be at risk') DESC, r.created_at, r.id
         LIMIT v_limit
      ) AS q
  ), '[]'::jsonb);
END;
$fn$;

REVOKE ALL ON FUNCTION private.assert_valid_report_reason(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.is_priority_reason(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.report_opinion(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.report_opinion_comment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_opinion(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_opinion_comment(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_list_priority_reports(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_priority_reports(int) TO service_role;
-- Fix round 1 (C-1): the report RPCs are forum_reports' only writers.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.forum_reports FROM PUBLIC, anon, authenticated;
-- Batch-6 ruling: report_count moves only through the report RPCs.
REVOKE ALL ON FUNCTION public.increment_opinion_report_count(uuid) FROM PUBLIC, anon, authenticated;

COMMIT;
