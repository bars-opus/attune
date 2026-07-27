-- Editing within 15 minutes of posting, for opinions, comments, and forum
-- posts (ATTUNE_MASTER_SPEC.md §8.11 "Editing", FORUM.md §7 "Editing").
--
-- One window, one rule, applied identically to all three content types via
-- three small RPCs that share the same shape rather than one polymorphic
-- function -- the three tables (opinions, opinion_comments, forum_posts)
-- are not a shared inheritance hierarchy in this schema, so a single
-- function would need dynamic SQL (EXECUTE format(...)) to target the right
-- table, trading a little duplication for avoiding that.
--
-- Validation note: "same validation as posting" is, as of this migration,
-- exactly the length/blank check every create_* RPC already runs --
-- ATTUNE_MASTER_SPEC.md's "Layer 1 keyword filter" is a documented design
-- intent that is NOT YET IMPLEMENTED anywhere in this codebase (grepped:
-- no such function exists). These edit RPCs intentionally do not invent a
-- keyword filter that posting itself does not enforce -- that would make
-- editing stricter than posting, which is not the spec's intent ("the same
-- checks a new post does"). When Layer 1 is built, wire it into
-- create_opinion/create_opinion_comment/create_forum_post AND these three
-- edit RPCs together, in the same migration, so they cannot drift.
--
-- Moderation independence: none of these RPCs touch report_count or
-- hidden_pending_review. The edit window is purely time-based
-- (created_at + 15 minutes); a post already under review can still be
-- edited within its window, and editing never resets what was already
-- accumulating.

ALTER TABLE public.opinions
  ADD COLUMN IF NOT EXISTS edited_at timestamptz;
ALTER TABLE public.opinion_comments
  ADD COLUMN IF NOT EXISTS edited_at timestamptz;
ALTER TABLE public.forum_posts
  ADD COLUMN IF NOT EXISTS edited_at timestamptz;

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
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 280 THEN
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

-- ---------------------------------------------------------------------------
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
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 280 THEN
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

-- ---------------------------------------------------------------------------
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
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 280 THEN
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

-- ---------------------------------------------------------------------------
-- Feed/read RPCs redefined to carry edited_at, so the client can render the
-- "(edited)" marker. Same DROP-then-CREATE requirement as every prior
-- RETURNS TABLE change to these functions (42P13 "cannot change return type
-- of existing function").
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
  ORDER BY
    (o.relationship_status_at_post IS DISTINCT FROM (SELECT status FROM me)),
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
    p_author_handle AS author_handle,
    (o.user_id = auth.uid()) AS is_mine,
    r.reaction_type AS my_reaction,
    (s.id IS NOT NULL) AS is_saved,
    (rp.id IS NOT NULL) AS is_reposted_by_me,
    o.quoted_opinion_id,
    o.edited_at
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
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_reposted_opinions(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_reposted_opinions(int, int) TO authenticated;

-- get_quoted_opinion also redefined so an embedded original's own
-- "(edited)" marker renders correctly too.
DROP FUNCTION IF EXISTS public.get_quoted_opinion(uuid);

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
  is_reposted_by_me boolean,
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
  WHERE o.id = p_opinion_id
    AND o.removed_at IS NULL
    AND o.hidden_pending_review = false;
$$;
REVOKE ALL ON FUNCTION public.get_quoted_opinion(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_quoted_opinion(uuid) TO authenticated;

-- get_opinion_comments redefined so comment cards can show "(edited)" too.
DROP FUNCTION IF EXISTS public.get_opinion_comments(uuid);

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
  liked_by_me boolean,
  edited_at timestamptz
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
    (cl.user_id IS NOT NULL) AS liked_by_me,
    c.edited_at
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
