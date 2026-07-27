-- Repost opinions (ATTUNE_MASTER_SPEC.md §8.11 "Reposts", FORUM.md §7 "Reposts").
--
-- A one-tap "share this as-is" action on an opinion. No commentary, no new
-- free-text surface -- the "strictly text" abuse-reduction principle isn't
-- touched, because reposting adds no text of its own.
--
-- Shape decisions (see ATTUNE_MASTER_SPEC.md §8.11 "Reposts" for the full
-- rationale):
--   * A repost is a REFERENCE row, never a content copy. Likes, comments and
--     report counts always belong to the one original opinion -- mirrors
--     opinion_saves' shape exactly (same columns, same UNIQUE constraint).
--   * No self-repost (checked in the RPC, same gate opinion_reactions_insert_own
--     enforces for reactions).
--   * No repost-of-a-repost: opinion_id always references an ORIGINAL opinion.
--     There is no "reposted_from" chain to resolve -- opinions themselves are
--     never repost rows, so this is true by construction, not by a runtime check.
--   * Un-repost is available any time and never touches the original.
--
-- repost_count is a maintained counter column on opinions, following the exact
-- precedent of like_count/dislike_count/comment_count -- NOT a view like
-- opinion_follower_counts, because a repost count is public feed content
-- (visible to everyone who sees the opinion), not a per-viewer aggregate.
-- opinions_owner_update only allows the AUTHOR to UPDATE their own row via RLS,
-- so a reposter (a different user) cannot write this column directly -- the
-- counter can only move through the SECURITY DEFINER RPCs below, same as every
-- other opinion counter.

ALTER TABLE public.opinions
  ADD COLUMN IF NOT EXISTS repost_count int NOT NULL DEFAULT 0;

-- Reference row. Mirrors opinion_saves' table shape precisely.
CREATE TABLE IF NOT EXISTS public.opinion_reposts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  opinion_id uuid NOT NULL REFERENCES public.opinions(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, opinion_id)
);

-- Feed-join direction (opinion_id leads) for is_reposted_by_me and for the
-- Discover/Following LEFT JOIN below.
CREATE INDEX IF NOT EXISTS opinion_reposts_opinion_id_user_id_idx
  ON public.opinion_reposts (opinion_id, user_id);

-- get_reposted_opinions orders by repost recency.
CREATE INDEX IF NOT EXISTS opinion_reposts_user_id_created_at_idx
  ON public.opinion_reposts (user_id, created_at DESC);

ALTER TABLE public.opinion_reposts ENABLE ROW LEVEL SECURITY;

-- Unlike opinion_saves (which is private to the saver), a repost is public
-- feed content -- other users need to see THAT an opinion was reposted to
-- render it in their own feed timeline. Read is open to any authenticated
-- user; writes stay owner-scoped.
DROP POLICY IF EXISTS opinion_reposts_read ON public.opinion_reposts;
CREATE POLICY opinion_reposts_read
ON public.opinion_reposts FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS opinion_reposts_owner_write ON public.opinion_reposts;
CREATE POLICY opinion_reposts_owner_write
ON public.opinion_reposts FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

REVOKE ALL ON TABLE public.opinion_reposts FROM PUBLIC, anon;
GRANT SELECT, INSERT, DELETE ON TABLE public.opinion_reposts TO authenticated;

-- ---------------------------------------------------------------------------
-- Repost / un-repost. Idempotent in both directions so a double-tap can't
-- error or double-count.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.repost_opinion(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_author_id uuid;
  v_inserted boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- Refuse to repost something the caller cannot read: removed or
  -- pending-review opinions are invisible in every feed, so a repost row
  -- pointing at one would be a permanently orphaned entry in the timeline.
  -- This also gives us the author's id for the self-repost check and the
  -- notification below, in one query.
  SELECT user_id INTO v_author_id
  FROM public.opinions
  WHERE id = p_opinion_id
    AND removed_at IS NULL
    AND hidden_pending_review = false;

  IF v_author_id IS NULL THEN
    RAISE EXCEPTION 'opinion_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_author_id = v_uid THEN
    RAISE EXCEPTION 'cannot_repost_own_opinion' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.opinion_reposts (user_id, opinion_id)
  VALUES (v_uid, p_opinion_id)
  ON CONFLICT (user_id, opinion_id) DO NOTHING
  RETURNING true INTO v_inserted;

  -- Only move the counter and notify on an actual new repost -- ON CONFLICT
  -- DO NOTHING means a double-tap resolves here as v_inserted staying NULL.
  IF v_inserted THEN
    UPDATE public.opinions
    SET repost_count = repost_count + 1
    WHERE id = p_opinion_id;

    -- "Someone reposted your opinion" (FORUM.md §10 #9). Same anonymous
    -- pattern as the like/comment/reply notifications: the recipient learns
    -- it happened, never who. private.enqueue_forum_notification (see
    -- 20260727120000_opinion_engagement_and_moderation_notifications.sql)
    -- takes no actor-id parameter at all -- v_uid (the reposter) is available
    -- in scope here but there is no parameter to pass it through, which makes
    -- an anonymity leak structurally inexpressible at this call site, not
    -- just a convention to remember.
    PERFORM private.enqueue_forum_notification(
      p_user_id    => v_author_id,
      p_title      => 'New repost',
      p_body       => 'Someone reposted your opinion',
      p_type       => 'opinion_reposted',
      p_opinion_id => p_opinion_id
    );
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.repost_opinion(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repost_opinion(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.unrepost_opinion(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_deleted_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- No existence check on the opinion itself: un-reposting one that has
  -- since been removed must still work, otherwise a hidden post's repost row
  -- (and its share of repost_count) could never be cleared.
  DELETE FROM public.opinion_reposts
  WHERE user_id = v_uid AND opinion_id = p_opinion_id
  RETURNING id INTO v_deleted_id;

  -- Only decrement if a row actually existed -- an unrepost on a
  -- not-reposted opinion is a no-op, not a count going negative.
  IF v_deleted_id IS NOT NULL THEN
    UPDATE public.opinions
    SET repost_count = GREATEST(repost_count - 1, 0)
    WHERE id = p_opinion_id;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.unrepost_opinion(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unrepost_opinion(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.is_opinion_reposted(p_opinion_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.opinion_reposts r
    WHERE r.user_id = auth.uid() AND r.opinion_id = p_opinion_id
  );
$$;
REVOKE ALL ON FUNCTION public.is_opinion_reposted(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_opinion_reposted(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- The caller's own reposts, newest repost first. Returns the same column set
-- as get_discover_opinions (plus repost_count, plus is_reposted_by_me) so
-- OpinionModel.fromFeedRow parses it unchanged.
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
    react.reaction_type AS my_reaction,
    COALESCE(fc.follower_count, 0) AS follower_count,
    (s.id IS NOT NULL) AS is_saved,
    true AS is_reposted_by_me
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

-- ---------------------------------------------------------------------------
-- Feed RPCs redefined again to carry repost_count + is_reposted_by_me.
--
-- Same DROP-then-CREATE requirement as opinion_saves' redefinition of these
-- same functions (42P13 "cannot change return type of existing function" --
-- RETURNS TABLE compiles to OUT parameters, which OR REPLACE cannot insert
-- into). Bodies are copied verbatim from
-- 20260727140000_opinion_saves.sql's redefinition, with exactly two
-- additions: repost_count in the SELECT list (a plain column read, no join
-- needed since it lives on opinions itself) and is_reposted_by_me via a new
-- LEFT JOIN against opinion_reposts.
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
  is_reposted_by_me boolean
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

-- Following feed also carries reposts (§8.11 "Feed visibility": a repost
-- surfaces in Discover/Following like a normal feed entry, timestamped at
-- REPOST time). This UNION brings in opinions reposted by someone the caller
-- follows, ordered by repost_created_at rather than the opinion's own
-- created_at -- that's what makes a months-old opinion re-circulate into an
-- active timeline when reposted today, matching the spec's stated purpose.
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
  is_reposted_by_me boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  WITH followed_activity AS (
    -- Original opinions authored by someone the caller follows.
    SELECT o.id, o.created_at AS feed_created_at
    FROM public.opinions o
    JOIN public.opinion_follows f
      ON f.following_id = o.user_id AND f.follower_id = auth.uid()

    UNION

    -- Opinions (by anyone, including non-followed authors) reposted by
    -- someone the caller follows. Ordered by repost time, not the original
    -- opinion's created_at -- see comment above.
    SELECT rp.opinion_id AS id, rp.created_at AS feed_created_at
    FROM public.opinion_reposts rp
    JOIN public.opinion_follows f
      ON f.following_id = rp.user_id AND f.follower_id = auth.uid()
  ),
  -- An opinion can reach this feed via both paths (followed author's own
  -- post, AND reposted by a different followed user) -- collapse to one row
  -- per opinion, keeping the most recent qualifying timestamp so a repost of
  -- an already-followed author's post still bumps it back to the top.
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
    (rp.id IS NOT NULL) AS is_reposted_by_me
  FROM deduped d
  JOIN public.opinions o ON o.id = d.id
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
    p_author_handle AS author_handle,
    (o.user_id = auth.uid()) AS is_mine,
    r.reaction_type AS my_reaction,
    (s.id IS NOT NULL) AS is_saved,
    (rp.id IS NOT NULL) AS is_reposted_by_me
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

-- get_saved_opinions also redefined to carry the two new columns, same reason.
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
    true AS is_saved,
    (rp.id IS NOT NULL) AS is_reposted_by_me
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
