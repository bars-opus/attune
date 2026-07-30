-- Tag-filtered Discover (opinions) and Explore (forums) feeds.
--
-- A row of AppFilterChip chips above each feed: "All" (unfiltered) plus every
-- tag in the fixed vocabulary, multi-select, OR-matched -- selecting #love and
-- #dating shows posts carrying EITHER, not both (most posts carry only 1-3
-- tags total under the 3-tag cap, so requiring ALL selected tags would return
-- almost nothing once 2+ chips are picked). The filter narrows WHICH rows
-- appear; it does not change ordering -- Discover keeps its engagement×
-- recency ranking (private.opinion_rank_score) even when tag-filtered, since
-- a filter chip is scoping "Discover", not replacing it with a different,
-- chronological surface (that already exists as the separate tag-browse
-- screen from 20260731120000).
--
-- p_tag_slugs NULL or empty means "All" -- unfiltered, identical to today's
-- behavior. This is a single optional trailing parameter on each function.
--
-- Every function below whose parameter list changes is preceded by an
-- explicit DROP FUNCTION with its OLD signature: adding a parameter --
-- even one with a DEFAULT -- changes a function's argument types, and
-- Postgres's CREATE OR REPLACE FUNCTION docs are explicit that changing
-- argument types this way silently creates a second, distinct overload
-- rather than replacing the original ("It is not possible to change the
-- name or argument types of a function this way"). This is the same class
-- of REPLACE restriction already hit twice this session for RETURNS TABLE
-- column changes and for a LANGUAGE change -- verified against the Postgres
-- docs directly this time rather than assumed.

-- ---------------------------------------------------------------------------
-- get_discover_opinions gains p_tag_slugs. Body otherwise identical to
-- 20260803120000's version (ranking helper, hide/mute filters, all joins).
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.get_discover_opinions(int, int);

CREATE OR REPLACE FUNCTION public.get_discover_opinions(
  p_limit int DEFAULT 30,
  p_offset int DEFAULT 0,
  p_tag_slugs text[] DEFAULT NULL
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
    -- "All" (NULL/empty) skips this filter entirely. Otherwise OR-match: the
    -- opinion must carry AT LEAST ONE of the selected tags.
    AND (
      p_tag_slugs IS NULL OR array_length(p_tag_slugs, 1) IS NULL
      OR EXISTS (
        SELECT 1 FROM public.opinion_tags ot
        JOIN public.tags t ON t.id = ot.tag_id
        WHERE ot.opinion_id = o.id AND t.slug = ANY(p_tag_slugs)
      )
    )
  ORDER BY
    (o.relationship_status_at_post IS DISTINCT FROM (SELECT status FROM me)),
    private.opinion_rank_score(o.like_count, o.dislike_count, o.comment_count, o.repost_count, o.created_at) DESC,
    o.created_at DESC
  LIMIT least(greatest(p_limit, 0), 100)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_discover_opinions(int, int, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_discover_opinions(int, int, text[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- The three forums-explore sections, converted from direct client
-- `.from('public_forum_topics')` queries (in ForumRepository) to RPCs. This
-- conversion is required, not optional: forum_topic_tags has no client grant
-- at all (RPC-only, see 20260731120000), so a tag filter on these lists is
-- only reachable server-side. Column set matches public_forum_topics exactly
-- so TopicModel.fromJson parses these rows unchanged; ordering and the
-- status filter for each list are unchanged from today's client-side query.
--
-- The one behavioral difference from the old direct-query path:
-- get_voting_topics no longer runs activate_pending_topics()/
-- expire_old_topics() as a side effect (ForumRepository.getVotingTopics did
-- this before every fetch). Those are lifecycle sweeps unrelated to reading a
-- list and already run on their own hourly cron (activate-topics, see
-- 20260726... era migrations) -- bundling them into a read was incidental,
-- not a guarantee any caller depends on, and this migration does not
-- reproduce it.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_voting_topics_filtered(p_tag_slugs text[] DEFAULT NULL)
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
  FROM public.forum_topics ft
  WHERE ft.status = 'voting'
    AND (
      p_tag_slugs IS NULL OR array_length(p_tag_slugs, 1) IS NULL
      OR EXISTS (
        SELECT 1 FROM public.forum_topic_tags ftt
        JOIN public.tags t ON t.id = ftt.tag_id
        WHERE ftt.topic_id = ft.id AND t.slug = ANY(p_tag_slugs)
      )
    )
  ORDER BY ft.created_at ASC;
$$;
REVOKE ALL ON FUNCTION public.get_voting_topics_filtered(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_voting_topics_filtered(text[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_active_forums_filtered(p_tag_slugs text[] DEFAULT NULL)
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
  FROM public.forum_topics ft
  WHERE ft.status = 'active'
    AND (
      p_tag_slugs IS NULL OR array_length(p_tag_slugs, 1) IS NULL
      OR EXISTS (
        SELECT 1 FROM public.forum_topic_tags ftt
        JOIN public.tags t ON t.id = ftt.tag_id
        WHERE ftt.topic_id = ft.id AND t.slug = ANY(p_tag_slugs)
      )
    )
  ORDER BY ft.last_post_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_active_forums_filtered(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_active_forums_filtered(text[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_quiet_forums_filtered(p_tag_slugs text[] DEFAULT NULL)
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
  FROM public.forum_topics ft
  WHERE ft.status = 'quiet'
    AND (
      p_tag_slugs IS NULL OR array_length(p_tag_slugs, 1) IS NULL
      OR EXISTS (
        SELECT 1 FROM public.forum_topic_tags ftt
        JOIN public.tags t ON t.id = ftt.tag_id
        WHERE ftt.topic_id = ft.id AND t.slug = ANY(p_tag_slugs)
      )
    )
  ORDER BY ft.last_post_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_quiet_forums_filtered(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_quiet_forums_filtered(text[]) TO authenticated;
