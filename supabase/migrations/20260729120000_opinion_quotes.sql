-- Quote opinions (ATTUNE_MASTER_SPEC.md §8.11 "Quotes", FORUM.md §7 "Quotes
-- (opinions only)").
--
-- A quote is "repost, plus your own opinion." Unlike a repost (a lightweight
-- reference row in opinion_reposts, see 20260728120000_opinion_reposts.sql), a
-- quote IS a full, independent opinion -- own text, own posting-path
-- validation, own like/comment/report/repost counts, own feed placement --
-- that additionally carries a pointer to the opinion it quotes.
--
-- Shape decisions (see ATTUNE_MASTER_SPEC.md §8.11 "Quotes" for full
-- rationale):
--   * quoted_opinion_id lives ON opinions itself (nullable self-referencing
--     FK), not a separate join table -- a quote does not need a second row,
--     it needs one extra column on the row it already is.
--   * Self-quote IS allowed, unlike self-repost. There is no owner check here.
--   * No quote-of-a-quote: quoting a quote re-targets the underlying original
--     at insert time, so quoted_opinion_id can never itself have a non-null
--     quoted_opinion_id. One hop, always.
--   * If the quoted opinion is later removed, the quote is untouched -- only
--     the read path (get_quoted_opinion below) needs to handle a vanished
--     original, by returning nothing rather than erroring.

ALTER TABLE public.opinions
  ADD COLUMN IF NOT EXISTS quoted_opinion_id uuid REFERENCES public.opinions;

-- Serves get_quoted_opinion's per-card lookup and the "re-target to original"
-- resolution in create_opinion_with_quote below.
CREATE INDEX IF NOT EXISTS opinions_quoted_opinion_id_idx
  ON public.opinions (quoted_opinion_id) WHERE quoted_opinion_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Create an opinion that quotes another. Delegates to create_opinion for the
-- base insert (content validation, keyword filter via assert_can_post, §7
-- rate limit/cooldown, ban gate all stay in the one place that already owns
-- them), then attaches the quote reference -- same shape as
-- create_opinion_with_poll in 20260726120000_polls_on_opinions_and_topics.sql.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_opinion_with_quote(
  p_content text,
  p_quoted_opinion_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_target_id uuid;
  v_target_author uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_quoted_opinion_id IS NULL THEN
    RAISE EXCEPTION 'quote_requires_target' USING ERRCODE = '22023';
  END IF;

  -- Resolve to the ORIGINAL. If the caller quoted something that is itself a
  -- quote, re-target to what THAT quotes -- quoted_opinion_id is never
  -- non-null on the row this ends up pointing at, so the chain can never
  -- exceed one hop no matter how many times a quote gets quoted.
  SELECT COALESCE(o.quoted_opinion_id, o.id), COALESCE(orig.user_id, o.user_id)
  INTO v_target_id, v_target_author
  FROM public.opinions o
  LEFT JOIN public.opinions orig ON orig.id = o.quoted_opinion_id
  WHERE o.id = p_quoted_opinion_id;

  -- Deliberately NOT gated on removed_at/hidden_pending_review: unlike
  -- repost_opinion (which refuses to reference something invisible in every
  -- feed), a quote's own text stands on its own even if the original it
  -- references is already gone by the time this call runs -- the read path
  -- (get_quoted_opinion) is what handles a vanished original, not creation.
  IF v_target_id IS NULL THEN
    RAISE EXCEPTION 'opinion_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_id := public.create_opinion(p_content);

  UPDATE public.opinions
  SET quoted_opinion_id = v_target_id
  WHERE id = v_id;

  -- "Someone quoted your opinion" (FORUM.md §10 #10), skipped on self-quote --
  -- spec is explicit that a self-quote does not notify. Same
  -- private.enqueue_forum_notification helper as likes/comments/replies/
  -- reposts, which takes no actor-id parameter -- an anonymity leak here is
  -- structurally inexpressible, not merely a convention to remember.
  IF v_target_author IS NOT NULL AND v_target_author <> v_uid THEN
    PERFORM private.enqueue_forum_notification(
      p_user_id    => v_target_author,
      p_title      => 'New quote',
      p_body       => 'Someone quoted your opinion',
      p_type       => 'opinion_quoted',
      p_opinion_id => v_target_id
    );
  END IF;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_opinion_with_quote(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_opinion_with_quote(text, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Resolve the embedded original for one quote. Returns zero rows if the
-- quote's target has since been removed or deleted -- the client renders "This
-- opinion is no longer available" on an empty result rather than this RPC
-- raising, since a vanished original is an expected steady-state, not an
-- error.
--
-- Returns the SAME shape get_discover_opinions does (minus is_saved/
-- is_reposted_by_me/repost_count's per-viewer variants are still included,
-- since the embedded original is rendered with its own mini engagement state
-- too) so OpinionModel.fromFeedRow parses it unchanged.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_quoted_opinion(p_opinion_id uuid)
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
  is_reposted_by_me boolean
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
    (rp.id IS NOT NULL) AS is_reposted_by_me
  FROM public.opinions o
  LEFT JOIN public.opinion_reactions r
    ON r.opinion_id = o.id AND r.user_id = auth.uid()
  LEFT JOIN public.opinion_follower_counts fc
    ON fc.user_id = o.user_id
  LEFT JOIN public.opinion_saves s
    ON s.opinion_id = o.id AND s.user_id = auth.uid()
  LEFT JOIN public.opinion_reposts rp
    ON rp.opinion_id = o.id AND rp.user_id = auth.uid()
  WHERE o.id = p_opinion_id
    AND o.removed_at IS NULL
    AND o.hidden_pending_review = false;
$$;
REVOKE ALL ON FUNCTION public.get_quoted_opinion(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_quoted_opinion(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Feed RPCs redefined again to carry quoted_opinion_id, so the client knows
-- WHICH opinions are quotes and can fetch their embedded original via
-- get_quoted_opinion above. Same DROP-then-CREATE requirement as every prior
-- RETURNS TABLE change to these functions (42P13).
--
-- Deliberately returns only the id, not the resolved original's content
-- inline: a feed page can be up to 30 rows, and eagerly resolving 30
-- potential quote targets in the feed query itself would turn one query into
-- a query with up to 30 extra joins for a column that is NULL on most rows.
-- The client fetches get_quoted_opinion lazily, only for cards that are
-- actually quotes and actually rendered.
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.get_discover_opinions(int, int);

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
  quoted_opinion_id uuid
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
    o.quoted_opinion_id
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

DROP FUNCTION IF EXISTS public.get_following_opinions(int, int);

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
  quoted_opinion_id uuid
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
    o.quoted_opinion_id
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
  ORDER BY d.feed_created_at DESC
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_following_opinions(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_following_opinions(int, int) TO authenticated;

DROP FUNCTION IF EXISTS public.get_author_opinions(text);

CREATE OR REPLACE FUNCTION public.get_author_opinions(p_author_handle text)
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
  is_saved boolean,
  is_reposted_by_me boolean,
  quoted_opinion_id uuid
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
    p_author_handle AS author_handle,
    (o.user_id = auth.uid()) AS is_mine,
    r.reaction_type AS my_reaction,
    (s.id IS NOT NULL) AS is_saved,
    (rp.id IS NOT NULL) AS is_reposted_by_me,
    o.quoted_opinion_id
  FROM public.opinions o
  LEFT JOIN public.opinion_reactions r
    ON r.opinion_id = o.id AND r.user_id = auth.uid()
  LEFT JOIN public.opinion_saves s
    ON s.opinion_id = o.id AND s.user_id = auth.uid()
  LEFT JOIN public.opinion_reposts rp
    ON rp.opinion_id = o.id AND rp.user_id = auth.uid()
  WHERE public.opinion_author_handle(o.user_id) = p_author_handle
    AND o.removed_at IS NULL
    AND o.hidden_pending_review = false
  ORDER BY o.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_author_opinions(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_author_opinions(text) TO authenticated;

DROP FUNCTION IF EXISTS public.get_saved_opinions(int, int);

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
  quoted_opinion_id uuid
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
    true AS is_saved,
    (rp.id IS NOT NULL) AS is_reposted_by_me,
    o.quoted_opinion_id
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
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_saved_opinions(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_saved_opinions(int, int) TO authenticated;

DROP FUNCTION IF EXISTS public.get_reposted_opinions(int, int);

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
  quoted_opinion_id uuid
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
    true AS is_reposted_by_me,
    o.quoted_opinion_id
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
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_reposted_opinions(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_reposted_opinions(int, int) TO authenticated;
