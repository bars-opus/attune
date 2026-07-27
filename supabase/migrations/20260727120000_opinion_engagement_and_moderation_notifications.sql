-- Opinion engagement + moderation notifications (FORUM.md §10, items 1, 2, 3, 7, 8).
--
-- FORUM.md §10 specifies eight notification types for the Opinions/Forums
-- feature. Only #4 (topic activated) was ever built — it lives in the
-- activate-topics edge function and pushes directly via sendOneSignalPush.
-- The other seven were spec'd and never implemented, so today a user who gets
-- liked, commented on, replied to, or moderated hears nothing at all. This
-- migration closes five of those gaps (#1, #2, #3, #7, #8). Items #5 and #6
-- (forum activity / going quiet) are deliberately out of scope here and are
-- being built on a separate track.
--
-- Delivery goes through the established pipeline, not a new one: each hook
-- INSERTs a row into public.scheduled_notifications with notification_type
-- 'immediate' and status 'pending'; the cron-driven
-- process-scheduled-notifications edge function picks it up and calls
-- sendOneSignalPush. That is the same shape used by chat/dating/safety (see
-- 20260705150000_chat_worker_hardening.sql). No pg_net, no trigger-to-HTTP,
-- no new edge function.
--
-- ANONYMITY (FORUM.md §3): this is an anonymous forum. None of the payloads
-- below carry the actor's user_id or author_handle. The recipient learns that
-- something happened to THEIR content, never who did it. The only user_id in
-- play is the recipient's own (scheduled_notifications.user_id, which is the
-- addressing column and never leaves the server). Moderation notices (#7/#8)
-- intentionally address the real account because the content being removed is
-- the recipient's own — FORUM.md §10 states "Send to: real user account
-- (user_id, not anonymous)" for exactly this reason.
--
-- Deep links: metadata carries opinion_id / comment_id so the client can route
-- on tap. The edge function's privacySafeData() allow-list is widened in the
-- same change set to let opinion_id, comment_id and forum_post_id through;
-- everything else stays filtered.

-- ---------------------------------------------------------------------------
-- Shared helper: enqueue one forum notification.
--
-- Factored out so all five call sites below use an identical column list and
-- metadata shape, and so the anonymity rule is enforced in exactly one place:
-- this function's signature has no parameter for an actor id, which makes it
-- structurally impossible for a caller to leak one into the payload.
--
-- private schema (not public) so it is unreachable over PostgREST — it is an
-- internal building block, not an API. SECURITY DEFINER because the callers
-- are themselves SECURITY DEFINER and the invoking end user has no direct
-- INSERT privilege on scheduled_notifications.
-- ---------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.enqueue_forum_notification(
  p_user_id uuid,
  p_title text,
  p_body text,
  p_type text,
  p_opinion_id uuid DEFAULT NULL,
  p_comment_id uuid DEFAULT NULL,
  p_forum_post_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.scheduled_notifications (
    user_id,
    notification_type,
    scheduled_for,
    status,
    metadata,
    created_at,
    updated_at
  )
  VALUES (
    p_user_id,
    'immediate',
    now(),
    'pending',
    -- strip_nulls so absent deep-link ids do not land as JSON nulls; the edge
    -- function's allow-list filter already skips nulls, this keeps the stored
    -- row clean for anyone reading the table directly.
    jsonb_strip_nulls(
      jsonb_build_object(
        'title', p_title,
        'body', p_body,
        'type', p_type,
        'opinion_id', p_opinion_id,
        'comment_id', p_comment_id,
        'forum_post_id', p_forum_post_id
      )
    ),
    now(),
    now()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION private.enqueue_forum_notification(uuid, text, text, text, uuid, uuid, uuid)
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- #1 — "Someone likes your opinion" (FORUM.md §10 item 1)
--
--   Title: "New like"
--   Body:  "Someone liked your opinion"
--   Grouping: after 5 likes in 1 hour -> "5 people liked your opinion"
--   Send to: opinion.user_id
--
-- Hook point: increment_opinion_like_count, which the client already calls
-- after inserting the reaction row (opinion_repository.dart addReaction).
-- Reactions do not go through an RPC of their own — the client writes
-- opinion_reactions directly under RLS — so extending this existing,
-- already-SECURITY-DEFINER counter RPC is the smallest correct diff and needs
-- no client change. The dislike counterpart is deliberately NOT touched:
-- FORUM.md §10 "NEVER NOTIFIED" lists dislikes explicitly.
--
-- Self-like guard is load-bearing, not defensive: opinion_reactions_owner_write
-- only asserts auth.uid() = user_id (the reactor owns their own reaction row);
-- nothing in the schema stops a user reacting to their own opinion. Without
-- the check below, liking your own post would notify you.
--
-- GROUPING: implemented in full, per spec. Rather than emit one push per like,
-- we reuse the still-pending notification row for this opinion when one exists
-- from within the last hour, bumping a like_count counter in its metadata and
-- rewriting the body. Because process-scheduled-notifications only claims rows
-- with status 'pending', updating a pending row is race-safe in the sense that
-- matters here: if the worker already claimed/sent it, the WHERE clause below
-- matches nothing and we insert a fresh row instead — the recipient gets a new
-- notification rather than a silently-swallowed one. The 5-like threshold in
-- the spec is the point at which the copy switches to the plural form; likes
-- 2..4 update the existing pending row without changing the singular copy,
-- which is what "grouped, not five separate pushes" requires.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.increment_opinion_like_count(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_owner_id uuid;
  v_pending_id uuid;
  v_new_id uuid;
  v_group_count int;
BEGIN
  UPDATE public.opinions
  SET like_count = COALESCE(like_count, 0) + 1
  WHERE id = p_opinion_id
  RETURNING user_id INTO v_owner_id;

  -- No such opinion (or already gone): nothing to notify about.
  IF v_owner_id IS NULL THEN
    RETURN;
  END IF;

  -- Never notify someone about their own like.
  IF v_uid IS NULL OR v_owner_id = v_uid THEN
    RETURN;
  END IF;

  -- Look for a still-unsent like notification for this same opinion, raised
  -- within the last hour, to group into.
  SELECT id, COALESCE((metadata ->> 'like_count')::int, 1)
  INTO v_pending_id, v_group_count
  FROM public.scheduled_notifications
  WHERE user_id = v_owner_id
    AND status = 'pending'
    AND metadata ->> 'type' = 'opinion_liked'
    AND metadata ->> 'opinion_id' = p_opinion_id::text
    AND created_at > now() - interval '1 hour'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_pending_id IS NOT NULL THEN
    v_group_count := v_group_count + 1;

    UPDATE public.scheduled_notifications
    SET metadata = metadata
          || jsonb_build_object(
               'like_count', v_group_count,
               'body',
               CASE
                 WHEN v_group_count >= 5
                   THEN v_group_count::text || ' people liked your opinion'
                 ELSE 'Someone liked your opinion'
               END
             ),
        updated_at = now()
    WHERE id = v_pending_id
      AND status = 'pending';

    -- If the row was claimed between the SELECT and the UPDATE, fall through
    -- to a fresh insert so the like is not silently dropped.
    IF FOUND THEN
      RETURN;
    END IF;
  END IF;

  -- Seed the grouping counter on the row we just created. We use the id the
  -- enqueue helper returns rather than re-querying for "the newest matching
  -- row": under two concurrent likes on the same opinion, a re-query could
  -- pick up the other transaction's row and seed the wrong one.
  v_new_id := private.enqueue_forum_notification(
    p_user_id     => v_owner_id,
    p_title       => 'New like',
    p_body        => 'Someone liked your opinion',
    p_type        => 'opinion_liked',
    p_opinion_id  => p_opinion_id
  );

  UPDATE public.scheduled_notifications
  SET metadata = metadata || jsonb_build_object('like_count', 1)
  WHERE id = v_new_id;
END;
$$;

-- Grants restated to match the original definition (CREATE OR REPLACE keeps
-- existing ACLs, but being explicit keeps this migration self-contained if it
-- is ever replayed onto a fresh database).
REVOKE ALL ON FUNCTION public.increment_opinion_like_count(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_opinion_like_count(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- #2 — "Someone comments on your opinion" (FORUM.md §10 item 2)
-- #3 — "Someone replies to your comment"  (FORUM.md §10 item 3)
--
--   #2 Title: "New comment"  Body: first 60 chars of comment + "..."
--      Send to: opinion.user_id (not to commenter themselves)
--   #3 Title: "New reply"    Body: first 60 chars of reply
--      Send to: parent comment's user_id
--
-- Both hook the same RPC (create_opinion_comment) because both are triggered
-- by the same INSERT; #3 additionally requires p_reply_to_comment_id NOT NULL.
-- Full body is restated below because CREATE OR REPLACE replaces the whole
-- function — the pre-existing validation, ban gate, status capture, insert and
-- comment_count bump are carried over verbatim from
-- 20260716140000_forums_opinions_anonymity_hardening.sql and are unchanged.
--
-- Double-send guard: when the opinion author and the parent comment author are
-- the same person (someone replying to a comment the opinion owner left on
-- their own opinion), the spec's two rules would both fire and that person
-- would get two pushes for one comment. We send the reply notification only in
-- that case, since it is the more specific of the two.
--
-- Truncation: "..." is appended only when the content actually exceeds 60
-- characters, so short comments do not get a misleading ellipsis. The body is
-- the comment text itself, which is public forum content the recipient can
-- already read — it carries no identity.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_opinion_comment(
  p_opinion_id uuid,
  p_content text,
  p_reply_to_comment_id uuid DEFAULT NULL,
  p_quoted_text text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_id uuid;
  v_opinion_owner uuid;
  v_parent_author uuid;
  v_preview text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 280 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;

  PERFORM private.assert_can_post(v_uid, 'comment');

  SELECT relationship_status INTO v_status FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.opinion_comments (
    opinion_id, user_id, content, relationship_status_at_post,
    reply_to_comment_id, quoted_text
  )
  VALUES (p_opinion_id, v_uid, p_content, v_status, p_reply_to_comment_id, p_quoted_text)
  RETURNING id INTO v_id;

  UPDATE public.opinions
  SET comment_count = COALESCE(comment_count, 0) + 1
  WHERE id = p_opinion_id
  RETURNING user_id INTO v_opinion_owner;

  -- Shared 60-char preview for both notification bodies (FORUM.md §10).
  v_preview := CASE
    WHEN char_length(p_content) > 60 THEN left(p_content, 60) || '...'
    ELSE p_content
  END;

  IF p_reply_to_comment_id IS NOT NULL THEN
    SELECT user_id INTO v_parent_author
    FROM public.opinion_comments
    WHERE id = p_reply_to_comment_id;
  END IF;

  -- #3: reply to a comment -> notify the parent comment's author.
  IF v_parent_author IS NOT NULL AND v_parent_author <> v_uid THEN
    PERFORM private.enqueue_forum_notification(
      p_user_id    => v_parent_author,
      p_title      => 'New reply',
      p_body       => v_preview,
      p_type       => 'opinion_comment_reply',
      p_opinion_id => p_opinion_id,
      p_comment_id => v_id
    );
  END IF;

  -- #2: new comment -> notify the opinion's author, unless they are the
  -- commenter, or unless they already got the reply notification above.
  IF v_opinion_owner IS NOT NULL
     AND v_opinion_owner <> v_uid
     AND (v_parent_author IS NULL OR v_parent_author <> v_opinion_owner)
  THEN
    PERFORM private.enqueue_forum_notification(
      p_user_id    => v_opinion_owner,
      p_title      => 'New comment',
      p_body       => v_preview,
      p_type       => 'opinion_commented',
      p_opinion_id => p_opinion_id,
      p_comment_id => v_id
    );
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_opinion_comment(uuid, text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_opinion_comment(uuid, text, uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- #7 — "Post removed"    (FORUM.md §10 item 7)
-- #8 — "Posting paused"  (FORUM.md §10 item 8)
--
--   #7 Title: "Post removed"
--      Body:  "One of your posts was removed for violating guidelines."
--   #8 Title: "Posting paused"
--      Body:  "Your posting access is paused for 7 days."
--   Both send to the real user account (user_id, not anonymous).
--
-- Hook point: admin_confirm_content_removal, the service-role-only moderation
-- RPC from 20260722120000_forum_ban_enforcement.sql. It already computes
-- v_author_id, v_new_count and v_ban_until, so both notifications are pure
-- additions to its body. Full body restated because CREATE OR REPLACE replaces
-- the whole function; the service-role gate, the three content-type branches,
-- the idempotent no-op path, the violation counter and the 7-day ban are all
-- carried over verbatim and unchanged.
--
-- RETURN CONTRACT UNCHANGED: still RETURNS TABLE (violation_count int,
-- banned_until timestamptz), still returns (0, NULL) on the no-op path and
-- (v_new_count, v_ban_until) otherwise. The added PERFORM calls discard their
-- result and cannot affect it.
--
-- On the removal that trips the third violation, the author receives BOTH
-- notifications: the removal notice and the ban notice. That is intended per
-- spec — they are distinct facts (this post is gone / your account is paused).
--
-- REVOKE from the original migration still stands; CREATE OR REPLACE preserves
-- ACLs and no new grant is introduced, so this remains service-role only.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_confirm_content_removal(
  p_content_type text,  -- 'opinion' | 'comment' | 'forum_post'
  p_content_id uuid
)
RETURNS TABLE (violation_count int, banned_until timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_author_id uuid;
  v_new_count int;
  v_ban_until timestamptz;
BEGIN
  -- Service-role only: requireServiceRole()-style gate. auth.uid() is NULL
  -- for the service-role key (it bypasses PostgREST's user JWT context
  -- entirely), so a NULL check here would let ANY unauthenticated caller in.
  -- The REVOKE below is the actual enforcement; this defends the intent.
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
    -- Already removed, or content_id did not match content_type — nothing
    -- to attribute a violation to. Not an error: idempotent no-op.
    RETURN QUERY SELECT 0, NULL::timestamptz;
    RETURN;
  END IF;

  UPDATE public.profiles
  SET confirmed_violation_count = confirmed_violation_count + 1
  WHERE id = v_author_id
  RETURNING confirmed_violation_count INTO v_new_count;

  -- #7: the removal itself. Deep-links to the removed item so the client can
  -- show it in context; which id is set depends on the content type.
  PERFORM private.enqueue_forum_notification(
    p_user_id       => v_author_id,
    p_title         => 'Post removed',
    p_body          => 'One of your posts was removed for violating guidelines.',
    p_type          => 'forum_content_removed',
    p_opinion_id    => CASE WHEN p_content_type = 'opinion' THEN p_content_id END,
    p_comment_id    => CASE WHEN p_content_type = 'comment' THEN p_content_id END,
    p_forum_post_id => CASE WHEN p_content_type = 'forum_post' THEN p_content_id END
  );

  IF v_new_count >= 3 THEN
    v_ban_until := now() + interval '7 days';
    UPDATE public.profiles
    SET banned_until = v_ban_until
    WHERE id = v_author_id;

    -- #8: the ban that this removal triggered. No deep link — this is an
    -- account-level notice, not about one piece of content.
    PERFORM private.enqueue_forum_notification(
      p_user_id => v_author_id,
      p_title   => 'Posting paused',
      p_body    => 'Your posting access is paused for 7 days.',
      p_type    => 'forum_posting_banned'
    );
  END IF;

  RETURN QUERY SELECT v_new_count, v_ban_until;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_confirm_content_removal(text, uuid) FROM PUBLIC, anon, authenticated;
-- No GRANT to authenticated: service-role only, matching the auth.role()
-- check above — clients can never call this directly.

-- ---------------------------------------------------------------------------
-- Supporting index for the #1 grouping lookup.
--
-- The grouping SELECT filters pending rows by metadata ->> 'type' and
-- metadata ->> 'opinion_id'. Without an index that is a scan of every pending
-- notification on every like. Partial on status = 'pending' keeps it small —
-- sent rows, which are the overwhelming majority over time, are excluded.
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_scheduled_notifications_pending_opinion
  ON public.scheduled_notifications (
    user_id,
    (metadata ->> 'type'),
    (metadata ->> 'opinion_id'),
    created_at DESC
  )
  WHERE status = 'pending';
