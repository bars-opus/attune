-- Forums & Opinions launch hardening
--
-- Closes four launch blockers found auditing the feature against FORUM.md:
--   1. Anonymity leak: clients read base tables and received user_id, which
--      §3 forbids ("user_id is NEVER exposed in any API response to clients").
--   2. N+1 feed loads: the discover feed did one extra query PER opinion to fetch
--      user_id, plus one per opinion for the caller's reaction.
--   3. Auto-hide never fired: report counters incremented but never flipped
--      hidden_pending_review at the §8 threshold of 10.
--   4. No server-side posting limits / ban enforcement (§7): inserts went direct,
--      so spam limits, cooldowns, and 7-day bans were unenforceable.
--
-- Strategy: an opaque, stable per-author handle (HMAC of user_id with a server
-- secret) lets the client group an author's posts and drive Follow WITHOUT ever
-- learning the real user_id. Feed RPCs return that handle + is_mine + the
-- caller's own reaction in ONE query. Follow/unfollow resolve the handle back to
-- a user_id server-side. All state mutation that needs limits goes through RPCs.

-- ---------------------------------------------------------------------------
-- Author handle: HMAC(user_id, secret). Deterministic per user, non-reversible
-- for clients. The secret lives in a private schema table, never exposed.
-- ---------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS private.app_secrets (
  name text PRIMARY KEY,
  value text NOT NULL
);

-- Seed a random handle secret once; never overwrite (rotating it would break
-- follow relationships, which key on the handle).
--
-- Seed generation runs at TOP LEVEL, where the migration runner does not pin
-- search_path to public, so pgcrypto's gen_random_bytes() is not resolvable by
-- bare name (it lives in public on this project but is not on the default path
-- for a raw statement). gen_random_uuid() is a core built-in with no schema
-- dependency; two of them concatenated give 256 bits of entropy — ample for an
-- HMAC key, and portable across environments.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
INSERT INTO private.app_secrets (name, value)
VALUES (
  'opinion_author_handle_key',
  replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')
)
ON CONFLICT (name) DO NOTHING;

-- 'extensions' is on the search_path because Supabase installs pgcrypto there,
-- so hmac()/digest() resolve. (The dating migration's bare-hmac assumption that
-- pgcrypto lives in public does not hold on this project.)
CREATE OR REPLACE FUNCTION public.opinion_author_handle(p_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private, extensions
AS $$
  SELECT encode(
    extensions.hmac(p_user_id::text, (SELECT value FROM private.app_secrets WHERE name = 'opinion_author_handle_key'), 'sha256'),
    'hex'
  );
$$;
REVOKE ALL ON FUNCTION public.opinion_author_handle(uuid) FROM PUBLIC, anon;
-- Not granted to authenticated: clients never compute handles themselves, they
-- only receive them from the feed RPCs. This keeps the mapping one-directional.

-- ---------------------------------------------------------------------------
-- Posting limits + ban gate (§7, §8). One helper, called by every insert RPC.
-- Raises with a stable ERRCODE so the client maps it to a friendly message.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.assert_can_post(
  p_user_id uuid,
  p_kind text  -- 'opinion' | 'comment' | 'forum_post' | 'topic'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_banned_until timestamptz;
  v_count int;
  v_last timestamptz;
BEGIN
  -- Ban gate: banned users may read but not post.
  SELECT banned_until INTO v_banned_until FROM public.profiles WHERE id = p_user_id;
  IF v_banned_until IS NOT NULL AND v_banned_until > now() THEN
    RAISE EXCEPTION 'posting_banned' USING ERRCODE = '42501';
  END IF;

  IF p_kind = 'opinion' THEN
    -- 5 per 24h, 60s cooldown.
    SELECT count(*), max(created_at) INTO v_count, v_last
    FROM public.opinions
    WHERE user_id = p_user_id AND created_at > now() - interval '24 hours';
    IF v_count >= 5 THEN RAISE EXCEPTION 'daily_limit' USING ERRCODE = '53400'; END IF;
    IF v_last IS NOT NULL AND v_last > now() - interval '60 seconds' THEN
      RAISE EXCEPTION 'cooldown' USING ERRCODE = '53400';
    END IF;

  ELSIF p_kind = 'comment' THEN
    -- 20 per 24h.
    SELECT count(*) INTO v_count
    FROM public.opinion_comments
    WHERE user_id = p_user_id AND created_at > now() - interval '24 hours';
    IF v_count >= 20 THEN RAISE EXCEPTION 'daily_limit' USING ERRCODE = '53400'; END IF;

  ELSIF p_kind = 'topic' THEN
    -- 3 submissions per 7 days.
    SELECT count(*) INTO v_count
    FROM public.forum_topics
    WHERE submitted_by = p_user_id AND created_at > now() - interval '7 days';
    IF v_count >= 3 THEN RAISE EXCEPTION 'daily_limit' USING ERRCODE = '53400'; END IF;
  END IF;
  -- forum_post per-forum limits are enforced in create_forum_post (needs topic_id).
END;
$$;
REVOKE ALL ON FUNCTION private.assert_can_post(uuid, text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Anonymized discover feed. One query: no user_id, no N+1. Server-side ordering
-- per §4.1 (same relationship_status first, then engagement × recency).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_discover_opinions(
  p_limit int DEFAULT 30,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  content text,
  relationship_status_at_post text,
  like_count int,
  dislike_count int,
  comment_count int,
  created_at timestamptz,
  author_handle text,
  is_mine boolean,
  my_reaction text,
  follower_count int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  WITH me AS (
    SELECT relationship_status AS status FROM public.profiles WHERE id = auth.uid()
  )
  SELECT
    o.id,
    o.content,
    o.relationship_status_at_post,
    o.like_count,
    o.dislike_count,
    o.comment_count,
    o.created_at,
    public.opinion_author_handle(o.user_id) AS author_handle,
    (o.user_id = auth.uid()) AS is_mine,
    r.reaction_type AS my_reaction,
    COALESCE(fc.follower_count, 0) AS follower_count
  FROM public.opinions o
  LEFT JOIN public.opinion_reactions r
    ON r.opinion_id = o.id AND r.user_id = auth.uid()
  LEFT JOIN public.opinion_follower_counts fc
    ON fc.user_id = o.user_id
  WHERE o.removed_at IS NULL
    AND o.hidden_pending_review = false
  ORDER BY
    -- 1. same relationship_status first
    (o.relationship_status_at_post IS DISTINCT FROM (SELECT status FROM me)),
    -- 2. engagement score × recency weight
    ((o.like_count - o.dislike_count) + (o.comment_count * 2))
      * (1.0 / (EXTRACT(EPOCH FROM (now() - o.created_at)) / 3600.0 + 1)) DESC,
    o.created_at DESC
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_discover_opinions(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_discover_opinions(int, int) TO authenticated;

-- ---------------------------------------------------------------------------
-- Anonymized following feed (chronological, §4.1).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_following_opinions(
  p_limit int DEFAULT 30,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  content text,
  relationship_status_at_post text,
  like_count int,
  dislike_count int,
  comment_count int,
  created_at timestamptz,
  author_handle text,
  is_mine boolean,
  my_reaction text,
  follower_count int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT
    o.id,
    o.content,
    o.relationship_status_at_post,
    o.like_count,
    o.dislike_count,
    o.comment_count,
    o.created_at,
    public.opinion_author_handle(o.user_id) AS author_handle,
    (o.user_id = auth.uid()) AS is_mine,
    r.reaction_type AS my_reaction,
    COALESCE(fc.follower_count, 0) AS follower_count
  FROM public.opinions o
  JOIN public.opinion_follows f
    ON f.following_id = o.user_id AND f.follower_id = auth.uid()
  LEFT JOIN public.opinion_reactions r
    ON r.opinion_id = o.id AND r.user_id = auth.uid()
  LEFT JOIN public.opinion_follower_counts fc
    ON fc.user_id = o.user_id
  WHERE o.removed_at IS NULL
    AND o.hidden_pending_review = false
  ORDER BY o.created_at DESC
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_following_opinions(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_following_opinions(int, int) TO authenticated;

-- ---------------------------------------------------------------------------
-- Anonymized comment thread for one opinion.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_opinion_comments(p_opinion_id uuid)
RETURNS TABLE (
  id uuid,
  opinion_id uuid,
  content text,
  relationship_status_at_post text,
  quoted_text text,
  reply_to_comment_id uuid,
  like_count int,
  created_at timestamptz,
  author_handle text,
  is_mine boolean,
  liked_by_me boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT
    c.id,
    c.opinion_id,
    c.content,
    c.relationship_status_at_post,
    c.quoted_text,
    c.reply_to_comment_id,
    c.like_count,
    c.created_at,
    public.opinion_author_handle(c.user_id) AS author_handle,
    (c.user_id = auth.uid()) AS is_mine,
    (cl.user_id IS NOT NULL) AS liked_by_me
  FROM public.opinion_comments c
  LEFT JOIN public.comment_likes cl
    ON cl.comment_id = c.id AND cl.user_id = auth.uid()
  WHERE c.opinion_id = p_opinion_id
    AND c.removed_at IS NULL
    AND c.hidden_pending_review = false
  ORDER BY c.created_at ASC;
$$;
REVOKE ALL ON FUNCTION public.get_opinion_comments(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_opinion_comments(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Anonymous author profile: an author's opinions + follower count + status, by
-- opaque handle. Powers the anonymous profile screen without a real user_id.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_author_opinions(p_author_handle text)
RETURNS TABLE (
  id uuid,
  content text,
  relationship_status_at_post text,
  like_count int,
  dislike_count int,
  comment_count int,
  created_at timestamptz,
  author_handle text,
  is_mine boolean,
  my_reaction text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT
    o.id,
    o.content,
    o.relationship_status_at_post,
    o.like_count,
    o.dislike_count,
    o.comment_count,
    o.created_at,
    p_author_handle AS author_handle,
    (o.user_id = auth.uid()) AS is_mine,
    r.reaction_type AS my_reaction
  FROM public.opinions o
  LEFT JOIN public.opinion_reactions r
    ON r.opinion_id = o.id AND r.user_id = auth.uid()
  WHERE public.opinion_author_handle(o.user_id) = p_author_handle
    AND o.removed_at IS NULL
    AND o.hidden_pending_review = false
  ORDER BY o.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_author_opinions(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_author_opinions(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_author_profile(p_author_handle text)
RETURNS TABLE (
  relationship_status text,
  follower_count int,
  is_mine boolean,
  is_following boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT
    pr.relationship_status,
    (SELECT count(*)::int FROM public.opinion_follows f WHERE f.following_id = u.id),
    (u.id = auth.uid()) AS is_mine,
    EXISTS (
      SELECT 1 FROM public.opinion_follows f
      WHERE f.follower_id = auth.uid() AND f.following_id = u.id
    ) AS is_following
  FROM auth.users u
  LEFT JOIN public.profiles pr ON pr.id = u.id
  WHERE public.opinion_author_handle(u.id) = p_author_handle
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.get_author_profile(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_author_profile(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Follow / unfollow by opaque handle. Resolves handle -> user_id server-side so
-- the client never needs the real id. Self-follow is rejected.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.follow_opinion_author(p_author_handle text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_target uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- Resolve the handle. There is no reverse index; scan is acceptable at launch
  -- scale and keeps the mapping server-only. (Optimizable later with a stored
  -- handle column if the user base grows.)
  SELECT id INTO v_target
  FROM auth.users
  WHERE public.opinion_author_handle(id) = p_author_handle
  LIMIT 1;

  IF v_target IS NULL THEN
    RAISE EXCEPTION 'author_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_target = auth.uid() THEN
    RAISE EXCEPTION 'cannot_follow_self' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.opinion_follows (follower_id, following_id)
  VALUES (auth.uid(), v_target)
  ON CONFLICT (follower_id, following_id) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.follow_opinion_author(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.follow_opinion_author(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.unfollow_opinion_author(p_author_handle text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_target uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT id INTO v_target
  FROM auth.users
  WHERE public.opinion_author_handle(id) = p_author_handle
  LIMIT 1;

  IF v_target IS NULL THEN RETURN; END IF;

  DELETE FROM public.opinion_follows
  WHERE follower_id = auth.uid() AND following_id = v_target;
END;
$$;
REVOKE ALL ON FUNCTION public.unfollow_opinion_author(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unfollow_opinion_author(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.is_following_author(p_author_handle text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.opinion_follows f
    JOIN auth.users u ON u.id = f.following_id
    WHERE f.follower_id = auth.uid()
      AND public.opinion_author_handle(u.id) = p_author_handle
  );
$$;
REVOKE ALL ON FUNCTION public.is_following_author(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_following_author(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Rate-limited insert RPCs. These replace direct client INSERTs so §7 limits and
-- the ban gate are actually enforced. relationship_status is captured here from
-- the profile (§3), never trusted from the client.
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
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 280 THEN
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
  WHERE id = p_opinion_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_opinion_comment(uuid, text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_opinion_comment(uuid, text, uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Forum post creation with ban gate + per-forum rate limit (§7: 10/forum/24h,
-- 30s cooldown). relationship_status captured server-side. Topic activity
-- counters (last_post_at) are bumped here so the topic lifecycle stays correct.
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
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 280 THEN
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

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_forum_post(uuid, text, text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_forum_post(uuid, text, text, uuid, text) TO authenticated;

-- Topic submission with §7 limit (3 / 7 days) + ban gate.
CREATE OR REPLACE FUNCTION public.create_forum_topic(p_content text)
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
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 120 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;

  PERFORM private.assert_can_post(v_uid, 'topic');

  SELECT relationship_status INTO v_status FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.forum_topics (submitted_by, relationship_status_at_submit, content)
  VALUES (v_uid, v_status, p_content)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_forum_topic(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_forum_topic(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Auto-hide at report threshold (§8). Report RPCs now record the report AND flip
-- hidden_pending_review once report_count reaches 10. Replaces the bare
-- counter-increment functions the client used before.
-- ---------------------------------------------------------------------------

-- Priority reasons trigger the §8 2-hour SLA queue (priority = true).
CREATE OR REPLACE FUNCTION private.is_priority_reason(p_reason text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_reason IN (
    'Identifies a real person',
    'Harmful or dangerous content',
    'Hate speech or discrimination'
  );
$$;

CREATE OR REPLACE FUNCTION public.report_opinion(p_opinion_id uuid, p_reason text DEFAULT 'Other')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_count int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;

  INSERT INTO public.forum_reports (reported_by, opinion_id, reason, priority)
  VALUES (auth.uid(), p_opinion_id, COALESCE(p_reason, 'Other'), private.is_priority_reason(p_reason));

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
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;

  INSERT INTO public.forum_reports (reported_by, comment_id, reason, priority)
  VALUES (auth.uid(), p_comment_id, COALESCE(p_reason, 'Other'), private.is_priority_reason(p_reason));

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
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;

  INSERT INTO public.forum_reports (reported_by, forum_post_id, reason, priority)
  VALUES (auth.uid(), p_forum_post_id, COALESCE(p_reason, 'Other'), private.is_priority_reason(p_reason));

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
  INSERT INTO public.forum_reports (reported_by, topic_id, reason, priority)
  VALUES (auth.uid(), p_topic_id, COALESCE(p_reason, 'Other'), private.is_priority_reason(p_reason));
END;
$$;
REVOKE ALL ON FUNCTION public.report_forum_topic(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_forum_topic(uuid, text) TO authenticated;
