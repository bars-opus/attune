-- Mute and hide (ATTUNE_MASTER_SPEC.md §8.11 "Muting and hiding", FORUM.md §7
-- "Mute / hide (opinions)").
--
-- A quieter alternative to Report for "not for me" -- no moderation
-- implication, no effect on counts, no notification to the affected author.
-- Two independent mechanisms:
--   * opinion_hides: per-post, dismisses one opinion from the caller's feeds.
--   * opinion_mutes: per-author, keyed on author_handle (NEVER user_id --
--     storing a real user_id in a client-writable, viewer-owned table would
--     let a client that already knows one handle's user_id correlate it
--     against other tables; keeping the mute list itself handle-only means
--     even a full dump of this table reveals nothing beyond "this viewer
--     muted these handles," never who those handles are). Muting is
--     resolved back to a user_id only inside the feed RPCs, server-side,
--     the same one-directional resolution follow_opinion_author already
--     uses -- never exposed to any client.
--
-- Mute is retroactive: it hides the muted author's EXISTING posts too, not
-- just future ones. This is enforced by joining opinion_mutes into the feed
-- queries via the author_handle function, not by a one-time backfill -- a
-- backfill would need to re-run every time a new post landed, whereas a join
-- is correct at query time by construction and needs no maintenance.

CREATE TABLE IF NOT EXISTS public.opinion_hides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  opinion_id uuid NOT NULL REFERENCES public.opinions(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, opinion_id)
);

CREATE INDEX IF NOT EXISTS opinion_hides_user_id_opinion_id_idx
  ON public.opinion_hides (user_id, opinion_id);

ALTER TABLE public.opinion_hides ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS opinion_hides_owner ON public.opinion_hides;
CREATE POLICY opinion_hides_owner
ON public.opinion_hides FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

REVOKE ALL ON TABLE public.opinion_hides FROM PUBLIC, anon;
GRANT SELECT, INSERT, DELETE ON TABLE public.opinion_hides TO authenticated;

CREATE TABLE IF NOT EXISTS public.opinion_mutes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  muted_author_handle text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, muted_author_handle)
);

CREATE INDEX IF NOT EXISTS opinion_mutes_user_id_handle_idx
  ON public.opinion_mutes (user_id, muted_author_handle);

ALTER TABLE public.opinion_mutes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS opinion_mutes_owner ON public.opinion_mutes;
CREATE POLICY opinion_mutes_owner
ON public.opinion_mutes FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

REVOKE ALL ON TABLE public.opinion_mutes FROM PUBLIC, anon;
GRANT SELECT, INSERT, DELETE ON TABLE public.opinion_mutes TO authenticated;

-- ---------------------------------------------------------------------------
-- Hide / unhide / list-hidden-ids. Client-writable directly via the RLS
-- policy above (mirrors opinion_saves' owner-scoped-RLS-plus-thin-RPC shape),
-- but exposed as RPCs anyway for the same reason saves are: a stable call
-- surface the client depends on rather than raw table access sprinkled
-- through the repository, and idempotent INSERT/DELETE so a double-tap can't
-- error.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.hide_opinion(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.opinion_hides (user_id, opinion_id)
  VALUES (auth.uid(), p_opinion_id)
  ON CONFLICT (user_id, opinion_id) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.hide_opinion(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.hide_opinion(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.unhide_opinion(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.opinion_hides
  WHERE user_id = auth.uid() AND opinion_id = p_opinion_id;
END;
$$;
REVOKE ALL ON FUNCTION public.unhide_opinion(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unhide_opinion(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Mute / unmute / is-muted. Keyed on the handle the client already holds
-- (from an opinion's author_handle field) -- no resolution step needed here,
-- unlike follow_opinion_author, because muting never needs the real
-- user_id: it only ever needs to compare a stored handle string against
-- opinion_author_handle(o.user_id) computed fresh per row in the feed
-- queries below.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.mute_opinion_author(p_author_handle text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_author_handle IS NULL OR btrim(p_author_handle) = '' THEN
    RAISE EXCEPTION 'invalid_handle' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.opinion_mutes (user_id, muted_author_handle)
  VALUES (auth.uid(), p_author_handle)
  ON CONFLICT (user_id, muted_author_handle) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.mute_opinion_author(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mute_opinion_author(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.unmute_opinion_author(p_author_handle text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.opinion_mutes
  WHERE user_id = auth.uid() AND muted_author_handle = p_author_handle;
END;
$$;
REVOKE ALL ON FUNCTION public.unmute_opinion_author(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unmute_opinion_author(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_muted_authors()
RETURNS TABLE (author_handle text, muted_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT muted_author_handle, created_at
  FROM public.opinion_mutes
  WHERE user_id = auth.uid()
  ORDER BY created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_muted_authors() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_muted_authors() TO authenticated;

-- ---------------------------------------------------------------------------
-- Feed RPCs redefined again, this time to EXCLUDE hidden/muted content
-- rather than to add a column. Every feed a viewer reads (Discover,
-- Following, Saved, Reposted) gets both filters; get_author_opinions and
-- get_quoted_opinion do NOT -- deliberately. Visiting an author's profile
-- page after muting them, or seeing a quote's embedded original, are
-- explicit lookups by id/handle, not passive feed consumption -- muting is a
-- feed-level filter (per the spec), not a block, so it should not make
-- content the viewer specifically navigated to disappear.
--
-- Same DROP-then-CREATE requirement as every prior RETURNS TABLE change
-- (42P13). No column changes here, only a WHERE clause addition, so
-- REPLACE would actually be legal this time -- but the DROP is kept anyway
-- for consistency with the rest of this migration series and so this
-- migration's shape doesn't depend on the reader remembering which changes
-- do and don't require it.
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
    -- Hide/mute filters. NOT EXISTS rather than a LEFT JOIN + IS NULL: this
    -- viewer's hide list and mute list are both small and this reads more
    -- directly as "exclude rows matching either condition."
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
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_following_opinions(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_following_opinions(int, int) TO authenticated;

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
  -- Unlike Discover/Following, a hide/mute here does NOT exclude the row --
  -- you explicitly saved this opinion, which is a stronger, more deliberate
  -- signal than a later mute of its author. Muting stops NEW content from a
  -- muted author surfacing passively; it does not retroactively strip
  -- something you chose to keep. is_saved is already `true` for every row
  -- here, so the "retroactively hides existing posts" rule from the spec
  -- applies to passive feeds (Discover/Following), not to a deliberate save.
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
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_reposted_opinions(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_reposted_opinions(int, int) TO authenticated;
