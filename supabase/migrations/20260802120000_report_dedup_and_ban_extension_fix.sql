-- Three fixes found by an Algorithm Quality Review Checklist v3.1 audit of
-- the report/auto-hide and ban-escalation logic (ATTUNE_MASTER_SPEC.md's
-- required workflow step 4: any feature that "moderates" or "automates a
-- decision" must pass the checklist -- this logic predates the forum/opinion
-- feature work done this session and had never been audited against it).
--
-- ===========================================================================
-- Fix 1 (CRITICAL): report_opinion / report_opinion_comment / report_forum_post
-- / report_forum_topic had no dedup constraint on forum_reports. A single
-- authenticated account could call report_opinion ten times against the same
-- opinion and single-handedly cross the report_count >= 10 auto-hide
-- threshold -- turning a "10 different people flagged this" signal into a
-- one-account censorship primitive. There is no admin UI (moderation is
-- manual SQL-editor work per 20260722120000_forum_ban_enforcement.sql's own
-- header comment), so content hidden this way stays hidden until a human
-- happens to notice.
--
-- Fixed with a partial unique index per content type (topic_id's is included
-- too, even though topics have no auto-hide threshold today, because nothing
-- stopped the same unbounded-report gap there either) plus ON CONFLICT DO
-- NOTHING in each RPC, so a repeat report from the same reporter against the
-- same content is a silent no-op rather than a second row.
-- ===========================================================================

CREATE UNIQUE INDEX IF NOT EXISTS forum_reports_unique_reporter_opinion
  ON public.forum_reports (reported_by, opinion_id) WHERE opinion_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS forum_reports_unique_reporter_comment
  ON public.forum_reports (reported_by, comment_id) WHERE comment_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS forum_reports_unique_reporter_forum_post
  ON public.forum_reports (reported_by, forum_post_id) WHERE forum_post_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS forum_reports_unique_reporter_topic
  ON public.forum_reports (reported_by, topic_id) WHERE topic_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Fix 2 (HIGH): p_reason was unvalidated and unbounded -- COALESCE(p_reason,
-- 'Other') was the only processing, and forum_reports.reason has no length
-- cap. A client could pass a multi-megabyte string that lands verbatim in
-- the moderator's review queue. Now validated against the closed set the
-- report UI actually offers (lib/features/opinions/data/opinion_more_data.dart
-- and the matching forum post/comment report dialogs) -- an unrecognised
-- reason is rejected rather than silently accepted, since accepting one
-- would mean the client and server disagree about what reasons exist.
-- ---------------------------------------------------------------------------

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
    'Other'
  ) THEN
    RAISE EXCEPTION 'invalid_reason' USING ERRCODE = '22023';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION private.assert_valid_report_reason(text) FROM PUBLIC, anon, authenticated;

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
  ON CONFLICT (reported_by, opinion_id) WHERE opinion_id IS NOT NULL DO NOTHING
  RETURNING true INTO v_inserted;

  -- A repeat report from the same account is a silent no-op: the count must
  -- not move a second time for the same reporter.
  IF NOT v_inserted THEN
    RETURN;
  END IF;

  UPDATE public.opinions
  SET report_count = COALESCE(report_count, 0) + 1
  WHERE id = p_opinion_id
  RETURNING report_count INTO v_count;

  IF v_count >= 10 THEN
    UPDATE public.opinions SET hidden_pending_review = true WHERE id = p_opinion_id;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.report_opinion(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_opinion(uuid, text) TO authenticated;

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
  ON CONFLICT (reported_by, comment_id) WHERE comment_id IS NOT NULL DO NOTHING
  RETURNING true INTO v_inserted;

  IF NOT v_inserted THEN
    RETURN;
  END IF;

  UPDATE public.opinion_comments
  SET report_count = COALESCE(report_count, 0) + 1
  WHERE id = p_comment_id
  RETURNING report_count INTO v_count;

  IF v_count >= 10 THEN
    UPDATE public.opinion_comments SET hidden_pending_review = true WHERE id = p_comment_id;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.report_opinion_comment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_opinion_comment(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.report_forum_post(p_forum_post_id uuid, p_reason text DEFAULT 'Other')
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

  INSERT INTO public.forum_reports (reported_by, forum_post_id, reason, priority)
  VALUES (auth.uid(), p_forum_post_id, p_reason, private.is_priority_reason(p_reason))
  ON CONFLICT (reported_by, forum_post_id) WHERE forum_post_id IS NOT NULL DO NOTHING
  RETURNING true INTO v_inserted;

  IF NOT v_inserted THEN
    RETURN;
  END IF;

  UPDATE public.forum_posts
  SET report_count = COALESCE(report_count, 0) + 1
  WHERE id = p_forum_post_id
  RETURNING report_count INTO v_count;

  IF v_count >= 10 THEN
    UPDATE public.forum_posts SET hidden_pending_review = true WHERE id = p_forum_post_id;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.report_forum_post(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_forum_post(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.report_forum_topic(p_topic_id uuid, p_reason text DEFAULT 'Other')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  PERFORM private.assert_valid_report_reason(p_reason);

  INSERT INTO public.forum_reports (reported_by, topic_id, reason, priority)
  VALUES (auth.uid(), p_topic_id, p_reason, private.is_priority_reason(p_reason))
  ON CONFLICT (reported_by, topic_id) WHERE topic_id IS NOT NULL DO NOTHING;
  -- No auto-hide threshold for topics today (none existed before this fix
  -- either) -- this RPC only needed the dedup, not a counter change.
END;
$$;
REVOKE ALL ON FUNCTION public.report_forum_topic(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_forum_topic(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Fix 3 (MEDIUM): admin_confirm_content_removal overwrote banned_until with
-- now() + 7 days on every confirmation past the 3rd violation, rather than
-- extending or preserving whichever is later. A moderator confirming several
-- old items in one sitting resets the clock each time, and confirming
-- removals for content posted before an already-served ban had expired could
-- re-ban a user who was already clear. Fixed to only ever move banned_until
-- forward, never backward -- GREATEST(existing, new) -- so working through a
-- backlog can extend a ban but can never silently shorten or resurrect one
-- inconsistently. Return signature and the per-content idempotency
-- (AND removed_at IS NULL) are unchanged from the original migration.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_confirm_content_removal(
  p_content_type text,
  p_content_id uuid
)
RETURNS TABLE (violation_count int, banned_until timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_author_id uuid;
  v_new_count int;
  v_ban_until timestamptz;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  IF p_content_type = 'opinion' THEN
    UPDATE public.opinions SET removed_at = now()
    WHERE id = p_content_id AND removed_at IS NULL
    RETURNING user_id INTO v_author_id;
  ELSIF p_content_type = 'comment' THEN
    UPDATE public.opinion_comments SET removed_at = now()
    WHERE id = p_content_id AND removed_at IS NULL
    RETURNING user_id INTO v_author_id;
  ELSIF p_content_type = 'forum_post' THEN
    UPDATE public.forum_posts SET removed_at = now()
    WHERE id = p_content_id AND removed_at IS NULL
    RETURNING user_id INTO v_author_id;
  ELSE
    RAISE EXCEPTION 'invalid_content_type' USING ERRCODE = '22023';
  END IF;

  IF v_author_id IS NULL THEN
    RETURN QUERY SELECT 0, NULL::timestamptz;
    RETURN;
  END IF;

  UPDATE public.profiles
  SET confirmed_violation_count = confirmed_violation_count + 1
  WHERE id = v_author_id
  RETURNING confirmed_violation_count INTO v_new_count;

  IF v_new_count >= 3 THEN
    -- Never move the ban backward: a moderator confirming several
    -- violations in one sitting extends the ban past whichever is later
    -- (now, or an existing future banned_until), and never re-shortens or
    -- re-applies a ban that already ran its course before this confirmation.
    SELECT GREATEST(COALESCE(banned_until, now()), now()) + interval '7 days'
    INTO v_ban_until
    FROM public.profiles WHERE id = v_author_id;

    UPDATE public.profiles
    SET banned_until = v_ban_until
    WHERE id = v_author_id;
  END IF;

  RETURN QUERY SELECT v_new_count, v_ban_until;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_confirm_content_removal(text, uuid) FROM PUBLIC, anon, authenticated;
