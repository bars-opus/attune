-- "Who quoted / reposted this" lists, so the quote and repost counts on an
-- opinion card become tappable instead of being decoration with nothing
-- behind them.
--
-- Two functions rather than one:
--
--   * get_quotes_of_opinion returns the quoting OPINIONS — a quote is a full
--     opinion in its own right, so this is a normal feed page and reuses the
--     standard feed shape.
--   * get_reposters_of_opinion returns the ORIGINAL opinion once per reposter,
--     ordered by repost time. A repost has no content of its own, so there is
--     nothing else to render; this mirrors get_author_reposted_opinions
--     (20260804120000), which already returns the reposted opinion rather than
--     a repost row.
--
-- Both keep FORUM.md §3: user_id never leaves the server, only the HMAC'd
-- author_handle, so "who" means an anonymous handle a viewer can already see
-- on any card — not an identity.
--
-- Both are granted to anon for the same reason the feed itself is
-- (20260818120000_public_opinion_reads): the rows are already-public opinions,
-- auth.uid() degrades to NULL, and the moderation filters live in the body.

-- ---------------------------------------------------------------------------
-- Opinions that quote p_opinion_id. Standard feed shape so OpinionModel
-- .fromFeedRow parses it unchanged and OpinionCard renders it as-is.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_quotes_of_opinion(
  p_opinion_id uuid,
  p_limit int DEFAULT 20,
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
    react.reaction_type AS my_reaction,
    COALESCE(fc.follower_count, 0) AS follower_count,
    (s.id IS NOT NULL) AS is_saved,
    (rp.id IS NOT NULL) AS is_reposted_by_me,
    o.quoted_opinion_id,
    o.edited_at
  FROM public.opinions o
  LEFT JOIN public.opinion_reactions react
    ON react.opinion_id = o.id AND react.user_id = auth.uid()
  LEFT JOIN public.opinion_follower_counts fc
    ON fc.user_id = o.user_id
  LEFT JOIN public.opinion_saves s
    ON s.opinion_id = o.id AND s.user_id = auth.uid()
  LEFT JOIN public.opinion_reposts rp
    ON rp.opinion_id = o.id AND rp.user_id = auth.uid()
  WHERE o.quoted_opinion_id = p_opinion_id
    AND o.removed_at IS NULL
    AND o.hidden_pending_review = false
    -- Same hide/mute respect every feed applies: a quote from someone the
    -- viewer muted should not reappear here just because they opened the list.
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

REVOKE ALL ON FUNCTION public.get_quotes_of_opinion(uuid, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_quotes_of_opinion(uuid, int, int)
  TO authenticated, anon;

-- ---------------------------------------------------------------------------
-- Reposters of p_opinion_id: the same opinion repeated once per reposter,
-- carrying that reposter's handle and their repost time.
--
-- author_handle is deliberately the REPOSTER's handle, not the original
-- author's — the list answers "who reposted this", so the handle on each row
-- has to be the person who did it. Everything else stays the original
-- opinion's, since that is the content being shown.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_reposters_of_opinion(
  p_opinion_id uuid,
  p_limit int DEFAULT 20,
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
    -- Repost time, so the list reads newest-reposter-first rather than
    -- repeating the original's age on every row.
    rp.created_at,
    public.opinion_author_handle(rp.user_id) AS author_handle,
    (rp.user_id = auth.uid()) AS is_mine,
    react.reaction_type AS my_reaction,
    COALESCE(fc.follower_count, 0) AS follower_count,
    (s.id IS NOT NULL) AS is_saved,
    (viewer_rp.id IS NOT NULL) AS is_reposted_by_me,
    o.quoted_opinion_id,
    o.edited_at
  FROM public.opinion_reposts rp
  JOIN public.opinions o ON o.id = rp.opinion_id
  LEFT JOIN public.opinion_reactions react
    ON react.opinion_id = o.id AND react.user_id = auth.uid()
  LEFT JOIN public.opinion_follower_counts fc
    ON fc.user_id = rp.user_id
  LEFT JOIN public.opinion_saves s
    ON s.opinion_id = o.id AND s.user_id = auth.uid()
  LEFT JOIN public.opinion_reposts viewer_rp
    ON viewer_rp.opinion_id = o.id AND viewer_rp.user_id = auth.uid()
  WHERE rp.opinion_id = p_opinion_id
    AND o.removed_at IS NULL
    AND o.hidden_pending_review = false
    AND NOT EXISTS (
      SELECT 1 FROM public.opinion_mutes m
      WHERE m.user_id = auth.uid()
        AND m.muted_author_handle = public.opinion_author_handle(rp.user_id)
    )
  ORDER BY rp.created_at DESC
  LIMIT least(greatest(p_limit, 0), 100)
  OFFSET greatest(p_offset, 0);
$$;

REVOKE ALL ON FUNCTION public.get_reposters_of_opinion(uuid, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_reposters_of_opinion(uuid, int, int)
  TO authenticated, anon;
