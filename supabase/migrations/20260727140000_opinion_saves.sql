-- Save / bookmark opinions
--
-- Adds a private, per-user bookmark list over opinions. FORUM.md's
-- anonymous-user restriction list treats saving as a verified-user
-- participation action alongside voting and following, so this mirrors the
-- opinion_follows shape rather than inventing a new one:
--
--   * owner-scoped RLS policy (auth.uid() = user_id) so the client may read its
--     own rows directly, exactly as opinion_follows_owner allows, AND
--   * SECURITY DEFINER RPCs for the write path and the anonymized list read,
--     which is where opinion_follows also lives (follow_opinion_author etc.).
--
-- Saves are keyed on a specific opinion_id, so unlike follows there is no
-- handle -> user_id resolution step: the client already holds opinion ids.
--
-- A save is private to the saver. There is no saved_count on opinions and no
-- RPC exposes another user's saves, so bookmarking leaks nothing about the
-- saver to the author (FORUM.md §3: no user_id ever reaches a client).

CREATE TABLE IF NOT EXISTS public.opinion_saves (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  opinion_id uuid NOT NULL REFERENCES public.opinions(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, opinion_id)
);

-- The feed RPCs LEFT JOIN this table once per row on (opinion_id, user_id);
-- the UNIQUE constraint above already indexes (user_id, opinion_id), which
-- serves get_saved_opinions' user_id lookup. This second index serves the
-- feed-join direction, where opinion_id leads.
CREATE INDEX IF NOT EXISTS opinion_saves_opinion_id_user_id_idx
  ON public.opinion_saves (opinion_id, user_id);

-- get_saved_opinions orders by save recency.
CREATE INDEX IF NOT EXISTS opinion_saves_user_id_created_at_idx
  ON public.opinion_saves (user_id, created_at DESC);

ALTER TABLE public.opinion_saves ENABLE ROW LEVEL SECURITY;

-- Mirrors opinion_follows_owner: a user may do anything to their OWN save
-- rows and can neither see nor write anyone else's.
DROP POLICY IF EXISTS opinion_saves_owner ON public.opinion_saves;
CREATE POLICY opinion_saves_owner
ON public.opinion_saves FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Same grant shape as the other opinion tables: anon gets nothing, the
-- authenticated role is filtered by the owner policy above.
REVOKE ALL ON TABLE public.opinion_saves FROM PUBLIC, anon;
GRANT SELECT, INSERT, DELETE ON TABLE public.opinion_saves TO authenticated;

-- ---------------------------------------------------------------------------
-- Save / unsave. Simpler than follow_opinion_author: no handle to resolve.
-- Idempotent in both directions so a double-tap can't error or duplicate.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.save_opinion(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- Refuse to bookmark something the caller cannot read: removed or
  -- pending-review opinions are invisible in every feed, so a save row
  -- pointing at one would be a permanently blank entry in the saved list.
  IF NOT EXISTS (
    SELECT 1 FROM public.opinions o
    WHERE o.id = p_opinion_id
      AND o.removed_at IS NULL
      AND o.hidden_pending_review = false
  ) THEN
    RAISE EXCEPTION 'opinion_not_found' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.opinion_saves (user_id, opinion_id)
  VALUES (auth.uid(), p_opinion_id)
  ON CONFLICT (user_id, opinion_id) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.save_opinion(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_opinion(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.unsave_opinion(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- No existence check: unsaving an opinion that has since been removed must
  -- still work, otherwise a hidden post's row could never be cleared.
  DELETE FROM public.opinion_saves
  WHERE user_id = auth.uid() AND opinion_id = p_opinion_id;
END;
$$;
REVOKE ALL ON FUNCTION public.unsave_opinion(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unsave_opinion(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.is_opinion_saved(p_opinion_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.opinion_saves s
    WHERE s.user_id = auth.uid() AND s.opinion_id = p_opinion_id
  );
$$;
REVOKE ALL ON FUNCTION public.is_opinion_saved(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_opinion_saved(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- The caller's saved opinions, newest save first. Returns the SAME column set
-- as get_discover_opinions so OpinionModel.fromFeedRow parses it unchanged.
-- is_saved is a literal true here: every row in this list is saved by
-- definition, and the join would be redundant.
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
  created_at timestamptz,
  author_handle text,
  is_mine boolean,
  my_reaction text,
  follower_count int,
  is_saved boolean
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
    COALESCE(fc.follower_count, 0) AS follower_count,
    true AS is_saved
  FROM public.opinion_saves s
  JOIN public.opinions o ON o.id = s.opinion_id
  LEFT JOIN public.opinion_reactions r
    ON r.opinion_id = o.id AND r.user_id = auth.uid()
  LEFT JOIN public.opinion_follower_counts fc
    ON fc.user_id = o.user_id
  WHERE s.user_id = auth.uid()
    AND o.removed_at IS NULL
    AND o.hidden_pending_review = false
  ORDER BY s.created_at DESC
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_saved_opinions(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_saved_opinions(int, int) TO authenticated;

-- ---------------------------------------------------------------------------
-- Feed RPCs redefined to carry is_saved.
--
-- These bodies are copied verbatim from
-- 20260716140000_forums_opinions_anonymity_hardening.sql with exactly two
-- additions each: the is_saved column in the RETURNS TABLE / SELECT list, and
-- the LEFT JOIN against opinion_saves. Ordering, filters and every other
-- column are unchanged. Redefining here rather than editing that migration
-- keeps the historical migration immutable.
--
-- CREATE OR REPLACE FUNCTION cannot change a function's output columns —
-- Postgres rejects it with 42P13 "cannot change return type of existing
-- function" because RETURNS TABLE compiles to OUT parameters, and OR REPLACE
-- only allows appending trailing OUT parameters with the exact same names in
-- the exact same order, never inserting a new one in the middle (is_saved
-- lands before no column here, but the safe rule is: any RETURNS TABLE change
-- needs an explicit drop first). Each redefinition below is preceded by a
-- DROP FUNCTION IF EXISTS with the original parameter signature.
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
  created_at timestamptz,
  author_handle text,
  is_mine boolean,
  my_reaction text,
  follower_count int,
  is_saved boolean
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
    COALESCE(fc.follower_count, 0) AS follower_count,
    (s.id IS NOT NULL) AS is_saved
  FROM public.opinions o
  LEFT JOIN public.opinion_reactions r
    ON r.opinion_id = o.id AND r.user_id = auth.uid()
  LEFT JOIN public.opinion_follower_counts fc
    ON fc.user_id = o.user_id
  LEFT JOIN public.opinion_saves s
    ON s.opinion_id = o.id AND s.user_id = auth.uid()
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
  created_at timestamptz,
  author_handle text,
  is_mine boolean,
  my_reaction text,
  follower_count int,
  is_saved boolean
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
    COALESCE(fc.follower_count, 0) AS follower_count,
    (s.id IS NOT NULL) AS is_saved
  FROM public.opinions o
  JOIN public.opinion_follows f
    ON f.following_id = o.user_id AND f.follower_id = auth.uid()
  LEFT JOIN public.opinion_reactions r
    ON r.opinion_id = o.id AND r.user_id = auth.uid()
  LEFT JOIN public.opinion_follower_counts fc
    ON fc.user_id = o.user_id
  LEFT JOIN public.opinion_saves s
    ON s.opinion_id = o.id AND s.user_id = auth.uid()
  WHERE o.removed_at IS NULL
    AND o.hidden_pending_review = false
  ORDER BY o.created_at DESC
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_following_opinions(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_following_opinions(int, int) TO authenticated;

-- get_author_opinions feeds AnonymousProfileScreen, which renders the same
-- OpinionCard as the feeds — and that card now carries a bookmark toggle.
-- Without is_saved here, an opinion you have already saved would render with
-- an empty bookmark on a profile page and re-tapping it would be a silent
-- no-op (save_opinion is ON CONFLICT DO NOTHING). So it gets the column too.
DROP FUNCTION IF EXISTS public.get_author_opinions(text);

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
  my_reaction text,
  is_saved boolean
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
    r.reaction_type AS my_reaction,
    (s.id IS NOT NULL) AS is_saved
  FROM public.opinions o
  LEFT JOIN public.opinion_reactions r
    ON r.opinion_id = o.id AND r.user_id = auth.uid()
  LEFT JOIN public.opinion_saves s
    ON s.opinion_id = o.id AND s.user_id = auth.uid()
  WHERE public.opinion_author_handle(o.user_id) = p_author_handle
    AND o.removed_at IS NULL
    AND o.hidden_pending_review = false
  ORDER BY o.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_author_opinions(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_author_opinions(text) TO authenticated;
