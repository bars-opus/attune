-- Closes the remaining Algorithm Quality Review Checklist v3.1 gaps flagged
-- as "worth flagging, not blocking" by the two prior audits (the blocking
-- findings from both audits were already fixed in 20260801120000 and
-- 20260802120000). Three fixes:
--
--   1. Discover/Following/tag-browse's ranking formula was copy-pasted
--      verbatim across 6 migrations with zero design rationale anywhere, and
--      repost_count (added this session) was never folded into it despite
--      the comment literally reading "engagement score" -- extracted to one
--      shared function so the next tuning change happens in one place.
--   2. p_limit had no upper bound on any paginated feed RPC -- a client could
--      request p_limit => 1000000. Clamped to 100.
--   3. Batch array-parameter RPCs (get_polls_for_opinions/topics,
--      get_tags_for_opinions/forum_topics) had no bound on array size.
--      Rejected above 100 elements, which is far more than a single feed
--      page (30) ever needs.
--
-- All of the following are CREATE OR REPLACE with UNCHANGED RETURNS TABLE
-- column lists, so no DROP FUNCTION is needed anywhere in this file (the
-- 42P13 "cannot change return type" error only applies when the column list
-- itself changes).

-- ===========================================================================
-- Fix 1: shared ranking score, single source of truth.
--
-- Same curve as every prior copy: (likes - dislikes) + comments*2, decayed by
-- 1 / (hours_since_post + 1) so a brand-new post scores at its raw engagement
-- value and older posts decay toward zero. The +1 is load-bearing (prevents
-- divide-by-zero at age 0), not incidental. repost_count is now added at the
-- same weight as comment_count (x2) -- a repost is a stronger engagement
-- signal than a like (it costs the reposter their own reputation to
-- broadcast), matching how comments were already weighted above raw likes.
-- ===========================================================================

CREATE OR REPLACE FUNCTION private.opinion_rank_score(
  p_like_count int,
  p_dislike_count int,
  p_comment_count int,
  p_repost_count int,
  p_created_at timestamptz
)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    ((p_like_count - p_dislike_count) + (p_comment_count * 2) + (p_repost_count * 2))
      * (1.0 / (EXTRACT(EPOCH FROM (now() - p_created_at)) / 3600.0 + 1));
$$;
REVOKE ALL ON FUNCTION private.opinion_rank_score(int, int, int, int, timestamptz) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- get_discover_opinions: ranking + limit clamp. Body otherwise identical to
-- 20260730130000's version (hide/mute filters, all joins, all columns).
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
  repost_count int,
  created_at timestamptz,
  author_handle text,
  is_mine boolean,
  my_reaction text,
  follower_count int,
  is_saved boolean,
  is_reposted_by_me boolean,
  quoted_opinion_id uuid,
  edited_at timestamptz
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
    o.repost_count,
    o.created_at,
    public.opinion_author_handle(o.user_id) AS author_handle,
    (o.user_id = auth.uid()) AS is_mine,
    r.reaction_type AS my_reaction,
    COALESCE(fc.follower_count, 0) AS follower_count,
    (s.id IS NOT NULL) AS is_saved,
    (rp.id IS NOT NULL) AS is_reposted_by_me,
    o.quoted_opinion_id,
    o.edited_at
  FROM public.opinions o
  LEFT JOIN public.opinion_reactions r
    ON r.opinion_id = o.id AND r.user_id = auth.uid()
  LEFT JOIN public.opinion_follower_counts fc
    ON fc.user_id = o.user_id
  LEFT JOIN public.opinion_saves s
    ON s.opinion_id = o.id AND s.user_id = auth.uid()
  LEFT JOIN public.opinion_reposts rp
    ON rp.opinion_id = o.id AND rp.user_id = auth.uid()
  WHERE o.removed_at IS NULL
    AND o.hidden_pending_review = false
    AND NOT EXISTS (
      SELECT 1 FROM public.opinion_hides h
      WHERE h.user_id = auth.uid() AND h.opinion_id = o.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.opinion_mutes m
      WHERE m.user_id = auth.uid()
        AND m.muted_author_handle = public.opinion_author_handle(o.user_id)
    )
  ORDER BY
    (o.relationship_status_at_post IS DISTINCT FROM (SELECT status FROM me)),
    private.opinion_rank_score(o.like_count, o.dislike_count, o.comment_count, o.repost_count, o.created_at) DESC,
    o.created_at DESC
  LIMIT least(greatest(p_limit, 0), 100)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_discover_opinions(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_discover_opinions(int, int) TO authenticated;

-- ---------------------------------------------------------------------------
-- get_following_opinions: same two fixes. Following is chronological, not
-- ranked by score, so only the limit clamp applies here -- no
-- opinion_rank_score call needed, matching the pre-existing design (a
-- followed author's posts and reposts by people you follow both sort by
-- feed_created_at, not by engagement).
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
  repost_count int,
  created_at timestamptz,
  author_handle text,
  is_mine boolean,
  my_reaction text,
  follower_count int,
  is_saved boolean,
  is_reposted_by_me boolean,
  quoted_opinion_id uuid,
  edited_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  WITH followed_activity AS (
    SELECT o.id, o.created_at AS feed_created_at
    FROM public.opinions o
    JOIN public.opinion_follows f
      ON f.following_id = o.user_id AND f.follower_id = auth.uid()

    UNION

    SELECT rp.opinion_id AS id, rp.created_at AS feed_created_at
    FROM public.opinion_reposts rp
    JOIN public.opinion_follows f
      ON f.following_id = rp.user_id AND f.follower_id = auth.uid()
  ),
  deduped AS (
    SELECT id, max(feed_created_at) AS feed_created_at
    FROM followed_activity
    GROUP BY id
  )
  SELECT
    o.id,
    o.content,
    o.relationship_status_at_post,
    o.like_count,
    o.dislike_count,
    o.comment_count,
    o.repost_count,
    d.feed_created_at AS created_at,
    public.opinion_author_handle(o.user_id) AS author_handle,
    (o.user_id = auth.uid()) AS is_mine,
    r.reaction_type AS my_reaction,
    COALESCE(fc.follower_count, 0) AS follower_count,
    (s.id IS NOT NULL) AS is_saved,
    (rp2.id IS NOT NULL) AS is_reposted_by_me,
    o.quoted_opinion_id,
    o.edited_at
  FROM deduped d
  JOIN public.opinions o ON o.id = d.id
  LEFT JOIN public.opinion_reactions r
    ON r.opinion_id = o.id AND r.user_id = auth.uid()
  LEFT JOIN public.opinion_follower_counts fc
    ON fc.user_id = o.user_id
  LEFT JOIN public.opinion_saves s
    ON s.opinion_id = o.id AND s.user_id = auth.uid()
  LEFT JOIN public.opinion_reposts rp2
    ON rp2.opinion_id = o.id AND rp2.user_id = auth.uid()
  WHERE o.removed_at IS NULL
    AND o.hidden_pending_review = false
    AND NOT EXISTS (
      SELECT 1 FROM public.opinion_hides h
      WHERE h.user_id = auth.uid() AND h.opinion_id = o.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.opinion_mutes m
      WHERE m.user_id = auth.uid()
        AND m.muted_author_handle = public.opinion_author_handle(o.user_id)
    )
  ORDER BY d.feed_created_at DESC
  LIMIT least(greatest(p_limit, 0), 100)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_following_opinions(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_following_opinions(int, int) TO authenticated;

-- ---------------------------------------------------------------------------
-- get_saved_opinions: limit clamp only (ordered by save time, not ranked).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_saved_opinions(
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
  repost_count int,
  created_at timestamptz,
  author_handle text,
  is_mine boolean,
  my_reaction text,
  follower_count int,
  is_saved boolean,
  is_reposted_by_me boolean,
  quoted_opinion_id uuid,
  edited_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  -- Unlike Discover/Following, a hide/mute here does NOT exclude the row --
  -- you explicitly saved this opinion, which is a stronger, more deliberate
  -- signal than a later mute of its author.
  SELECT
    o.id,
    o.content,
    o.relationship_status_at_post,
    o.like_count,
    o.dislike_count,
    o.comment_count,
    o.repost_count,
    o.created_at,
    public.opinion_author_handle(o.user_id) AS author_handle,
    (o.user_id = auth.uid()) AS is_mine,
    r.reaction_type AS my_reaction,
    COALESCE(fc.follower_count, 0) AS follower_count,
    true AS is_saved,
    (rp.id IS NOT NULL) AS is_reposted_by_me,
    o.quoted_opinion_id,
    o.edited_at
  FROM public.opinion_saves s
  JOIN public.opinions o ON o.id = s.opinion_id
  LEFT JOIN public.opinion_reactions r
    ON r.opinion_id = o.id AND r.user_id = auth.uid()
  LEFT JOIN public.opinion_follower_counts fc
    ON fc.user_id = o.user_id
  LEFT JOIN public.opinion_reposts rp
    ON rp.opinion_id = o.id AND rp.user_id = auth.uid()
  WHERE s.user_id = auth.uid()
    AND o.removed_at IS NULL
    AND o.hidden_pending_review = false
  ORDER BY s.created_at DESC
  LIMIT least(greatest(p_limit, 0), 100)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_saved_opinions(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_saved_opinions(int, int) TO authenticated;

-- ---------------------------------------------------------------------------
-- get_reposted_opinions: limit clamp only (ordered by repost time).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_reposted_opinions(
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
  repost_count int,
  created_at timestamptz,
  author_handle text,
  is_mine boolean,
  my_reaction text,
  follower_count int,
  is_saved boolean,
  is_reposted_by_me boolean,
  quoted_opinion_id uuid,
  edited_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  -- Same reasoning as get_saved_opinions: you chose to repost this, so it is
  -- not excluded by a later hide/mute either.
  SELECT
    o.id,
    o.content,
    o.relationship_status_at_post,
    o.like_count,
    o.dislike_count,
    o.comment_count,
    o.repost_count,
    o.created_at,
    public.opinion_author_handle(o.user_id) AS author_handle,
    (o.user_id = auth.uid()) AS is_mine,
    react.reaction_type AS my_reaction,
    COALESCE(fc.follower_count, 0) AS follower_count,
    (s.id IS NOT NULL) AS is_saved,
    true AS is_reposted_by_me,
    o.quoted_opinion_id,
    o.edited_at
  FROM public.opinion_reposts rp
  JOIN public.opinions o ON o.id = rp.opinion_id
  LEFT JOIN public.opinion_reactions react
    ON react.opinion_id = o.id AND react.user_id = auth.uid()
  LEFT JOIN public.opinion_follower_counts fc
    ON fc.user_id = o.user_id
  LEFT JOIN public.opinion_saves s
    ON s.opinion_id = o.id AND s.user_id = auth.uid()
  WHERE rp.user_id = auth.uid()
    AND o.removed_at IS NULL
    AND o.hidden_pending_review = false
  ORDER BY rp.created_at DESC
  LIMIT least(greatest(p_limit, 0), 100)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_reposted_opinions(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_reposted_opinions(int, int) TO authenticated;

-- ---------------------------------------------------------------------------
-- get_opinions_by_tag: limit clamp. Ordered by created_at, not ranked (a tag
-- browse is a filtered timeline, not a ranked feed) -- unchanged from
-- 20260731120000 other than the clamp.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_opinions_by_tag(
  p_tag_slug text,
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
  repost_count int,
  created_at timestamptz,
  author_handle text,
  is_mine boolean,
  my_reaction text,
  follower_count int,
  is_saved boolean,
  is_reposted_by_me boolean,
  quoted_opinion_id uuid,
  edited_at timestamptz
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
    o.repost_count,
    o.created_at,
    public.opinion_author_handle(o.user_id) AS author_handle,
    (o.user_id = auth.uid()) AS is_mine,
    r.reaction_type AS my_reaction,
    COALESCE(fc.follower_count, 0) AS follower_count,
    (s.id IS NOT NULL) AS is_saved,
    (rp.id IS NOT NULL) AS is_reposted_by_me,
    o.quoted_opinion_id,
    o.edited_at
  FROM public.tags t
  JOIN public.opinion_tags ot ON ot.tag_id = t.id
  JOIN public.opinions o ON o.id = ot.opinion_id
  LEFT JOIN public.opinion_reactions r
    ON r.opinion_id = o.id AND r.user_id = auth.uid()
  LEFT JOIN public.opinion_follower_counts fc
    ON fc.user_id = o.user_id
  LEFT JOIN public.opinion_saves s
    ON s.opinion_id = o.id AND s.user_id = auth.uid()
  LEFT JOIN public.opinion_reposts rp
    ON rp.opinion_id = o.id AND rp.user_id = auth.uid()
  WHERE t.slug = p_tag_slug
    AND o.removed_at IS NULL
    AND o.hidden_pending_review = false
    AND NOT EXISTS (
      SELECT 1 FROM public.opinion_hides h
      WHERE h.user_id = auth.uid() AND h.opinion_id = o.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.opinion_mutes m
      WHERE m.user_id = auth.uid()
        AND m.muted_author_handle = public.opinion_author_handle(o.user_id)
    )
  ORDER BY o.created_at DESC
  LIMIT least(greatest(p_limit, 0), 100)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_opinions_by_tag(text, int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_opinions_by_tag(text, int, int) TO authenticated;

-- ---------------------------------------------------------------------------
-- get_forum_topics_by_tag: limit clamp only.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_forum_topics_by_tag(
  p_tag_slug text,
  p_limit int DEFAULT 30,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  content text,
  relationship_status_at_submit text,
  status text,
  upvote_count int,
  downvote_count int,
  seen_count int,
  total_posts int,
  for_posts int,
  against_posts int,
  last_post_at timestamptz,
  activated_at timestamptz,
  voting_expires_at timestamptz,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT
    ft.id,
    ft.content,
    ft.relationship_status_at_submit,
    ft.status,
    ft.upvote_count,
    ft.downvote_count,
    ft.seen_count,
    ft.total_posts,
    ft.for_posts,
    ft.against_posts,
    ft.last_post_at,
    ft.activated_at,
    ft.voting_expires_at,
    ft.created_at
  FROM public.tags t
  JOIN public.forum_topic_tags ftt ON ftt.tag_id = t.id
  JOIN public.forum_topics ft ON ft.id = ftt.topic_id
  WHERE t.slug = p_tag_slug
  ORDER BY ft.created_at DESC
  LIMIT least(greatest(p_limit, 0), 100)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_forum_topics_by_tag(text, int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_forum_topics_by_tag(text, int, int) TO authenticated;

-- ===========================================================================
-- Fix 3: bound the array-parameter batch lookup RPCs. LANGUAGE sql functions
-- cannot RAISE, so these are converted to plpgsql to reject an oversized
-- array outright rather than silently processing it -- 100 is far more than
-- a single feed page (30) ever needs in one batch call.
--
-- Each is preceded by an explicit DROP FUNCTION: whether CREATE OR REPLACE
-- permits changing a function's LANGUAGE (sql -> plpgsql) while keeping name/
-- args/return type identical is not clearly documented, and the parallel
-- case for RETURNS TABLE column changes turned out to require a DROP despite
-- not being on Postgres's documented list of REPLACE restrictions either
-- (see 20260727140000_opinion_saves.sql's header comment on the 42P13
-- error). Not worth re-learning that lesson the same way twice -- the DROP
-- is cheap and removes the ambiguity.
-- ===========================================================================

DROP FUNCTION IF EXISTS public.get_polls_for_opinions(uuid[]);

CREATE OR REPLACE FUNCTION public.get_polls_for_opinions(p_opinion_ids uuid[])
RETURNS TABLE (opinion_id uuid, poll_id uuid, has_voted boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF p_opinion_ids IS NOT NULL AND array_length(p_opinion_ids, 1) > 100 THEN
    RAISE EXCEPTION 'too_many_ids' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  SELECT
    p.opinion_id,
    p.id AS poll_id,
    EXISTS (
      SELECT 1 FROM public.poll_votes v
      WHERE v.poll_id = p.id AND v.user_id = auth.uid()
    ) AS has_voted
  FROM public.post_polls p
  WHERE p.opinion_id = ANY(p_opinion_ids);
END;
$$;
REVOKE ALL ON FUNCTION public.get_polls_for_opinions(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_polls_for_opinions(uuid[]) TO authenticated;

DROP FUNCTION IF EXISTS public.get_polls_for_topics(uuid[]);

CREATE OR REPLACE FUNCTION public.get_polls_for_topics(p_topic_ids uuid[])
RETURNS TABLE (topic_id uuid, poll_id uuid, has_voted boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF p_topic_ids IS NOT NULL AND array_length(p_topic_ids, 1) > 100 THEN
    RAISE EXCEPTION 'too_many_ids' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  SELECT
    p.topic_id,
    p.id AS poll_id,
    EXISTS (
      SELECT 1 FROM public.poll_votes v
      WHERE v.poll_id = p.id AND v.user_id = auth.uid()
    ) AS has_voted
  FROM public.post_polls p
  WHERE p.topic_id = ANY(p_topic_ids);
END;
$$;
REVOKE ALL ON FUNCTION public.get_polls_for_topics(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_polls_for_topics(uuid[]) TO authenticated;

DROP FUNCTION IF EXISTS public.get_tags_for_opinions(uuid[]);

CREATE OR REPLACE FUNCTION public.get_tags_for_opinions(p_opinion_ids uuid[])
RETURNS TABLE (opinion_id uuid, slug text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF p_opinion_ids IS NOT NULL AND array_length(p_opinion_ids, 1) > 100 THEN
    RAISE EXCEPTION 'too_many_ids' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  SELECT ot.opinion_id, t.slug
  FROM public.opinion_tags ot
  JOIN public.tags t ON t.id = ot.tag_id
  WHERE ot.opinion_id = ANY(p_opinion_ids)
  ORDER BY ot.opinion_id, t.slug;
END;
$$;
REVOKE ALL ON FUNCTION public.get_tags_for_opinions(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_tags_for_opinions(uuid[]) TO authenticated;

DROP FUNCTION IF EXISTS public.get_tags_for_forum_topics(uuid[]);

CREATE OR REPLACE FUNCTION public.get_tags_for_forum_topics(p_topic_ids uuid[])
RETURNS TABLE (topic_id uuid, slug text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF p_topic_ids IS NOT NULL AND array_length(p_topic_ids, 1) > 100 THEN
    RAISE EXCEPTION 'too_many_ids' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  SELECT ft.topic_id, t.slug
  FROM public.forum_topic_tags ft
  JOIN public.tags t ON t.id = ft.tag_id
  WHERE ft.topic_id = ANY(p_topic_ids)
  ORDER BY ft.topic_id, t.slug;
END;
$$;
REVOKE ALL ON FUNCTION public.get_tags_for_forum_topics(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_tags_for_forum_topics(uuid[]) TO authenticated;
