-- ForumCardSubDetails' For/Against numbers were showing for_posts/against_posts
-- (a count of POSTS on each side), but the card labels them "For"/"Against" as
-- if they were a count of PEOPLE on each side -- those diverge as soon as
-- anyone posts more than once. The actual "who picked which side" data
-- already exists in user_forum_sides (one row per user per topic, side IN
-- ('for','against','browse'), written when a user picks a side on
-- SideSelectionScreen) -- distinct from posting, so this counts everyone who
-- joined a side even before their first post.
--
-- Adds for_people/against_people (DISTINCT user_id per side from
-- user_forum_sides) alongside the existing for_posts/against_posts on every
-- read path a ForumCard can come from: public_forum_topics (getTopicDetails,
-- used by DebateRoomScreen's pinned card) and the three tag-filtered forum
-- RPCs (get_voting_topics_filtered / get_active_forums_filtered /
-- get_quiet_forums_filtered, used by every ForumCard list). for_posts/
-- against_posts are left in place -- still correct for anything that
-- actually wants a post count -- this is additive.
--
-- Each RPC's signature (parameter types) is unchanged, only its RETURNS TABLE
-- column list grows, but Postgres's CREATE OR REPLACE FUNCTION forbids
-- changing a function's return column list in place -- same restriction hit
-- in 20260806120000 for parameter changes, applies equally here. DROP first.

-- CREATE OR REPLACE VIEW treats its column list positionally and refuses to
-- rename/insert a column mid-list (errors "cannot change name of view column
-- ... to ..." if a new column lands before an existing one) -- confirmed
-- against the live remote database, not just the docs. The two new columns
-- go at the very end so every existing column keeps its ordinal position.
CREATE OR REPLACE VIEW public.public_forum_topics AS
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
  ft.created_at,
  COALESCE(sides.for_people, 0) AS for_people,
  COALESCE(sides.against_people, 0) AS against_people
FROM public.forum_topics ft
LEFT JOIN (
  SELECT
    topic_id,
    count(*) FILTER (WHERE side = 'for')::int AS for_people,
    count(*) FILTER (WHERE side = 'against')::int AS against_people
  FROM public.user_forum_sides
  GROUP BY topic_id
) sides ON sides.topic_id = ft.id;

DROP FUNCTION IF EXISTS public.get_voting_topics_filtered(text[]);

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
  for_people int,
  against_people int,
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
    COALESCE(sides.for_people, 0),
    COALESCE(sides.against_people, 0),
    ft.last_post_at,
    ft.activated_at,
    ft.voting_expires_at,
    ft.created_at
  FROM public.forum_topics ft
  LEFT JOIN (
    SELECT
      topic_id,
      count(*) FILTER (WHERE side = 'for')::int AS for_people,
      count(*) FILTER (WHERE side = 'against')::int AS against_people
    FROM public.user_forum_sides
    GROUP BY topic_id
  ) sides ON sides.topic_id = ft.id
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

DROP FUNCTION IF EXISTS public.get_active_forums_filtered(text[]);

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
  for_people int,
  against_people int,
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
    COALESCE(sides.for_people, 0),
    COALESCE(sides.against_people, 0),
    ft.last_post_at,
    ft.activated_at,
    ft.voting_expires_at,
    ft.created_at
  FROM public.forum_topics ft
  LEFT JOIN (
    SELECT
      topic_id,
      count(*) FILTER (WHERE side = 'for')::int AS for_people,
      count(*) FILTER (WHERE side = 'against')::int AS against_people
    FROM public.user_forum_sides
    GROUP BY topic_id
  ) sides ON sides.topic_id = ft.id
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

DROP FUNCTION IF EXISTS public.get_quiet_forums_filtered(text[]);

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
  for_people int,
  against_people int,
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
    COALESCE(sides.for_people, 0),
    COALESCE(sides.against_people, 0),
    ft.last_post_at,
    ft.activated_at,
    ft.voting_expires_at,
    ft.created_at
  FROM public.forum_topics ft
  LEFT JOIN (
    SELECT
      topic_id,
      count(*) FILTER (WHERE side = 'for')::int AS for_people,
      count(*) FILTER (WHERE side = 'against')::int AS against_people
    FROM public.user_forum_sides
    GROUP BY topic_id
  ) sides ON sides.topic_id = ft.id
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
