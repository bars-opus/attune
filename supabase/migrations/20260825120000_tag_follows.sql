-- Following a TAG, not a person (ATTUNE_MASTER_SPEC.md §8.11 "Tags",
-- FORUM.md §7). Following now means "authors I follow, plus topics I
-- follow," merged into the existing Following opinions feed.
--
-- Anonymity note: unlike opinion_follows, this table references NO second
-- user. A row is (this viewer, one slug from the fixed vocabulary), so a full
-- dump reveals only "this viewer follows these topics" — never who anyone
-- is, and never an author-plus-tag pairing. The rule this must not break
-- (FORUM.md §7 / tag_browse_screen.dart's own doc comment) is "a tag filter
-- may never be combined with an author filter to narrow in on one person";
-- following a tag adds content to a viewer's own feed and narrows in on no
-- one, so it does not engage that rule. Modeled on opinion_hides/
-- opinion_saves (a viewer-owned private preference) rather than
-- opinion_follows (a relationship to another person).
--
-- Deliberately NO tag_follower_counts view analogous to
-- opinion_follower_counts: nothing in the UI needs "how many people follow
-- #trust," and publishing per-tag follower aggregates would add a
-- correlation surface for no product gain.
CREATE TABLE IF NOT EXISTS public.tag_follows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tag_id uuid NOT NULL REFERENCES public.tags,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, tag_id)
);

-- Covers the feed join (user_id -> tag_ids), the hot path.
CREATE INDEX IF NOT EXISTS tag_follows_user_id_tag_id_idx
  ON public.tag_follows (user_id, tag_id);
-- Covers get_following_opinions' tag branch (tag_id -> matching opinions).
CREATE INDEX IF NOT EXISTS tag_follows_tag_id_idx
  ON public.tag_follows (tag_id);

ALTER TABLE public.tag_follows ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tag_follows_owner ON public.tag_follows;
CREATE POLICY tag_follows_owner
ON public.tag_follows FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

REVOKE ALL ON TABLE public.tag_follows FROM PUBLIC, anon;
GRANT SELECT, INSERT, DELETE ON TABLE public.tag_follows TO authenticated;

-- ---------------------------------------------------------------------------
-- Follow / unfollow, keyed on the slug the client already holds from
-- TagBrowseScreen. Resolves slug -> tag_id here rather than accepting a
-- tag_id, so the client never handles tag uuids (matching every other tag
-- RPC in 20260731120000). An unknown slug raises: unlike
-- attach_opinion_tags — where a stale client's unknown slug must degrade
-- gracefully because the post it's attaching to already exists — following
-- is a standalone deliberate action with nothing else to save, so failing
-- loudly is the honest outcome.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.follow_tag(p_tag_slug text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_tag_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT id INTO v_tag_id FROM public.tags WHERE slug = p_tag_slug;
  IF v_tag_id IS NULL THEN
    RAISE EXCEPTION 'tag_not_found' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.tag_follows (user_id, tag_id)
  VALUES (v_uid, v_tag_id)
  ON CONFLICT (user_id, tag_id) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.follow_tag(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.follow_tag(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.unfollow_tag(p_tag_slug text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- No tag_not_found raise here, mirroring unfollow_opinion_author's silent
  -- no-op on an unresolvable handle: unfollowing something you do not
  -- already follow is already the desired end state.
  DELETE FROM public.tag_follows tf
  USING public.tags t
  WHERE tf.tag_id = t.id
    AND tf.user_id = v_uid
    AND t.slug = p_tag_slug;
END;
$$;
REVOKE ALL ON FUNCTION public.unfollow_tag(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unfollow_tag(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- The caller's followed tags, newest follow first. Backs BOTH a "my followed
-- tags" list AND every is-this-tag-followed check on screen: the whole set
-- is at most ~21 rows (the fixed vocabulary's size), so one call caches the
-- complete answer. This is why there is no is_tag_followed(slug) singular
-- variant — with a bounded vocabulary, a per-chip round trip would be
-- strictly worse than holding the full set, unlike is_following_author where
-- the author space is unbounded.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_followed_tags()
RETURNS TABLE (slug text, created_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT t.slug, tf.created_at
  FROM public.tag_follows tf
  JOIN public.tags t ON t.id = tf.tag_id
  WHERE tf.user_id = auth.uid()
  ORDER BY tf.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_followed_tags() FROM PUBLIC, anon;
-- Not granted to anon: this returns the CALLER's own follow list, which for
-- a guest is always empty (auth.uid() is NULL). Granting it would be
-- harmless but meaningless — the client gates on a null uid client-side
-- first, the same way it already does for followingFeedProvider.
GRANT EXECUTE ON FUNCTION public.get_followed_tags() TO authenticated;

-- ---------------------------------------------------------------------------
-- Following now means "authors I follow, PLUS tags I follow." A third branch
-- on the existing followed_activity UNION, not a separate RPC merged on the
-- client: an opinion can match a followed author AND a followed tag at
-- once, and the deduped CTE below already collapses that to one row. A
-- client-side merge of two independently-paginated streams could not
-- reproduce that — page N of each stream does not compose into page N of
-- the union — so the merge has to happen before LIMIT/OFFSET, i.e. here.
--
-- A tag-matched opinion enters the feed at its OWN created_at, not at the
-- time the tag was followed: following #trust surfaces the existing #trust
-- conversation, the same retroactive posture mute already takes (see
-- 20260730130000).
--
-- matched_tag_slug: NULL when the opinion is present because of a followed
-- AUTHOR (post or repost) — even if it also happens to carry a followed tag,
-- the author-follow is the stronger, more direct explanation and wins. Set
-- to one followed tag's slug only when a tag match is the SOLE reason the
-- opinion is present, so the client can show "why is this here" (a
-- '#slug · followed' badge) without ever implying a stranger's post is here
-- because of who they are.
--
-- Adding matched_tag_slug changes this function's RETURNS TABLE column list,
-- which Postgres will not let CREATE OR REPLACE do in place ("cannot change
-- return type of existing function") — the same restriction
-- 20260806120000_tag_filtered_discover_feeds.sql hit and documented. DROP
-- first, same fix.
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
  edited_at timestamptz,
  matched_tag_slug text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  WITH followed_activity AS (
    SELECT o.id, o.created_at AS feed_created_at, NULL::text AS matched_tag_slug
    FROM public.opinions o
    JOIN public.opinion_follows f
      ON f.following_id = o.user_id AND f.follower_id = auth.uid()

    UNION ALL

    SELECT rp.opinion_id AS id, rp.created_at AS feed_created_at, NULL::text
    FROM public.opinion_reposts rp
    JOIN public.opinion_follows f
      ON f.following_id = rp.user_id AND f.follower_id = auth.uid()

    UNION ALL

    -- Opinions carrying a tag this viewer follows. Joins tag_follows ->
    -- opinion_tags only — never joins opinion author identity to a tag — so
    -- this introduces no author-plus-tag narrowing (the rule tag browse
    -- exists under). The viewer only ever learns "this post carries #x,"
    -- which every feed already tells them via TagChipRow.
    SELECT ot.opinion_id AS id, o2.created_at AS feed_created_at, t.slug
    FROM public.tag_follows tf
    JOIN public.tags t ON t.id = tf.tag_id
    JOIN public.opinion_tags ot ON ot.tag_id = tf.tag_id
    JOIN public.opinions o2 ON o2.id = ot.opinion_id
    WHERE tf.user_id = auth.uid()
  ),
  deduped AS (
    SELECT
      id,
      max(feed_created_at) AS feed_created_at,
      -- See the function-level comment above for the precedence rule this
      -- encodes: any NULL branch (author/repost) suppresses the badge
      -- entirely; only when EVERY contributing branch is tag-based does a
      -- slug survive. min() picks one arbitrarily-but-deterministically
      -- when more than one followed tag matches the same opinion.
      CASE
        WHEN bool_or(matched_tag_slug IS NULL) THEN NULL
        ELSE min(matched_tag_slug)
      END AS matched_tag_slug
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
    o.edited_at,
    d.matched_tag_slug
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
    -- Muting still wins over a tag follow: an explicit per-person mute is a
    -- stronger, more deliberate signal than a broad topical interest, so it
    -- stays in the outer query and applies regardless of which branch(es)
    -- produced this row.
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
