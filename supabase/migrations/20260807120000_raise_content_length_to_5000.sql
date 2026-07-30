-- Raises the content-length cap from 280 to 5000 characters on opinions,
-- opinion_comments, and forum_posts (and their edit RPCs) — 280 ("tweet"
-- length) was too tight for a relationship story, and a reply should be
-- able to match the length of what it's replying to. forum_topics.content
-- (the topic TITLE, capped at 120) is a different field and is
-- deliberately NOT touched here — a debatable topic is meant to stay a
-- short prompt, not the essay itself.
--
-- Every function body below is reproduced verbatim from its actual winning
-- definition (the last CREATE OR REPLACE for that name, in migration
-- timestamp order) with ONLY the "> 280" bound changed to "> 5000" — no
-- other logic, column, or error-code change. Winning definitions, verified
-- by reading each file directly rather than assumed from name:
--   create_opinion         — 20260716140000 (only definition)
--   create_opinion_comment — 20260727120000 (supersedes 20260716140000)
--   create_forum_post      — 20260727130000 (supersedes 20260716140000)
--   edit_opinion / edit_opinion_comment / edit_forum_post
--                           — 20260730120000 (only definitions)
--
-- Table CHECK constraints were created unnamed in the original launch
-- migration (20260716120000), so Postgres auto-named them
-- <table>_content_check — ALTER TABLE ... DROP CONSTRAINT needs that name.

ALTER TABLE public.opinions
  DROP CONSTRAINT opinions_content_check,
  ADD CONSTRAINT opinions_content_check CHECK (char_length(content) <= 5000);

ALTER TABLE public.opinion_comments
  DROP CONSTRAINT opinion_comments_content_check,
  ADD CONSTRAINT opinion_comments_content_check CHECK (char_length(content) <= 5000);

ALTER TABLE public.forum_posts
  DROP CONSTRAINT forum_posts_content_check,
  ADD CONSTRAINT forum_posts_content_check CHECK (char_length(content) <= 5000);

-- ---------------------------------------------------------------------------
-- create_opinion — verbatim from 20260716140000_forums_opinions_anonymity_hardening.sql
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_opinion(p_content text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 5000 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;

  PERFORM private.assert_can_post(v_uid, 'opinion');

  SELECT relationship_status INTO v_status FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.opinions (user_id, content, relationship_status_at_post)
  VALUES (v_uid, p_content, v_status)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_opinion(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_opinion(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- create_opinion_comment — verbatim from
-- 20260727120000_opinion_engagement_and_moderation_notifications.sql
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
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 5000 THEN
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
-- create_forum_post — verbatim from
-- 20260727130000_forum_activity_notifications.sql
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_forum_post(
  p_topic_id uuid,
  p_side text,
  p_content text,
  p_reply_to_post_id uuid DEFAULT NULL,
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
  v_count int;
  v_last timestamptz;
  v_banned_until timestamptz;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_side NOT IN ('for', 'against') THEN
    RAISE EXCEPTION 'invalid_side' USING ERRCODE = '22023';
  END IF;
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 5000 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;

  -- Ban gate.
  SELECT banned_until INTO v_banned_until FROM public.profiles WHERE id = v_uid;
  IF v_banned_until IS NOT NULL AND v_banned_until > now() THEN
    RAISE EXCEPTION 'posting_banned' USING ERRCODE = '42501';
  END IF;

  -- Per-forum limit: 10 posts / 24h in THIS topic, 30s cooldown in this topic.
  SELECT count(*), max(created_at) INTO v_count, v_last
  FROM public.forum_posts
  WHERE user_id = v_uid AND topic_id = p_topic_id
    AND created_at > now() - interval '24 hours';
  IF v_count >= 10 THEN RAISE EXCEPTION 'daily_limit' USING ERRCODE = '53400'; END IF;
  IF v_last IS NOT NULL AND v_last > now() - interval '30 seconds' THEN
    RAISE EXCEPTION 'cooldown' USING ERRCODE = '53400';
  END IF;

  SELECT relationship_status INTO v_status FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.forum_posts (
    topic_id, user_id, side, content, relationship_status_at_post,
    reply_to_post_id, quoted_text
  )
  VALUES (p_topic_id, v_uid, p_side, p_content, v_status, p_reply_to_post_id, p_quoted_text)
  RETURNING id INTO v_id;

  UPDATE public.forum_topics
  SET total_posts = COALESCE(total_posts, 0) + 1,
      for_posts = for_posts + CASE WHEN p_side = 'for' THEN 1 ELSE 0 END,
      against_posts = against_posts + CASE WHEN p_side = 'against' THEN 1 ELSE 0 END,
      last_post_at = now()
  WHERE id = p_topic_id;

  -- Posting is itself a visit: bump the poster's watermark so the post they
  -- just wrote never counts toward their own "new posts since last visit".
  INSERT INTO public.forum_topic_visits (topic_id, user_id, last_visited_at)
  VALUES (p_topic_id, v_uid, now())
  ON CONFLICT (topic_id, user_id)
  DO UPDATE SET last_visited_at = now();

  -- §10 #5. Never let a notification failure lose the post.
  BEGIN
    PERFORM private.queue_forum_activity_notifications(p_topic_id, v_uid);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'queue_forum_activity_notifications failed for topic %: %',
      p_topic_id, SQLERRM;
  END;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_forum_post(uuid, text, text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_forum_post(uuid, text, text, uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- edit_opinion / edit_opinion_comment / edit_forum_post — verbatim from
-- 20260730120000_edit_window_opinions_comments_forum_posts.sql
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.edit_opinion(
  p_opinion_id uuid,
  p_content text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_updated_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 5000 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;

  UPDATE public.opinions
  SET content = p_content, edited_at = now()
  WHERE id = p_opinion_id
    AND user_id = v_uid
    AND removed_at IS NULL
    AND created_at > now() - interval '15 minutes'
  RETURNING id INTO v_updated_id;

  -- Covers three distinct cases with one message, deliberately: wrong owner,
  -- already removed, and window expired all mean the same thing to the
  -- caller -- "you cannot edit this right now" -- and none should leak which
  -- specific reason applies (e.g. distinguishing "not yours" from "removed"
  -- would confirm to a non-owner that a specific opinion exists and its
  -- moderation state, which is not this RPC's business to reveal).
  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'not_editable' USING ERRCODE = '42501';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.edit_opinion(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.edit_opinion(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.edit_opinion_comment(
  p_comment_id uuid,
  p_content text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_updated_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 5000 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;

  UPDATE public.opinion_comments
  SET content = p_content, edited_at = now()
  WHERE id = p_comment_id
    AND user_id = v_uid
    AND removed_at IS NULL
    AND created_at > now() - interval '15 minutes'
  RETURNING id INTO v_updated_id;

  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'not_editable' USING ERRCODE = '42501';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.edit_opinion_comment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.edit_opinion_comment(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.edit_forum_post(
  p_forum_post_id uuid,
  p_content text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_updated_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 5000 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;

  UPDATE public.forum_posts
  SET content = p_content, edited_at = now()
  WHERE id = p_forum_post_id
    AND user_id = v_uid
    AND removed_at IS NULL
    AND created_at > now() - interval '15 minutes'
  RETURNING id INTO v_updated_id;

  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'not_editable' USING ERRCODE = '42501';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.edit_forum_post(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.edit_forum_post(uuid, text) TO authenticated;
