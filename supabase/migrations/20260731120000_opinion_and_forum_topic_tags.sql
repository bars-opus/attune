-- Tags on opinions and forum topics (ATTUNE_MASTER_SPEC.md §8.11 "Tags",
-- FORUM.md §7 "Tags (opinions and forum topics)").
--
-- A fixed, app-controlled vocabulary of topical chips. NOT freeform: a
-- user-invented tag is a fingerprint (trackable across posts in a way free
-- text is not), so every tag is seeded by this migration, never inserted by
-- a client. Up to 3 tags per post, optional, set at creation, not
-- independently editable after posting.
--
-- Design note on why this is a SEPARATE attach_tags RPC rather than another
-- create_opinion_with_X combinator (following the shape of
-- create_opinion_with_poll / create_opinion_with_quote): those two are
-- mutually exclusive alternatives layered on top of a plain post. Tags are
-- orthogonal metadata that could apply to a plain post, a poll post, OR a
-- quote post alike -- a fourth combinator (create_opinion_with_poll_and_tags,
-- create_opinion_with_quote_and_tags, ...) would multiply combinatorially.
-- Every create_* function already returns the new post's uuid, so the client
-- calls create_opinion[_with_poll|_with_quote](...) exactly as it does today,
-- then calls attach_opinion_tags(new_id, tag_slugs) as a second step. Both
-- calls happen before the post is ever rendered to any other user, so there
-- is no user-visible window where a post exists without its tags.

-- ---------------------------------------------------------------------------
-- Vocabulary. Seeded once, ON CONFLICT DO NOTHING so re-running this
-- migration (or a future migration adding more tags) never duplicates or
-- clobbers an existing tag's id -- opinion_tags/forum_topic_tags reference
-- tags.id, so a changed id would silently orphan every existing tag
-- attachment.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.tags (slug) VALUES
  ('relationship'), ('dating'), ('marriage'), ('situationship'), ('breakup'),
  ('love'), ('healing'), ('trust'), ('jealousy'), ('communication'),
  ('sex'), ('attraction'), ('love language'),
  ('date'), ('long distance'), ('red flags'), ('boundaries'),
  ('vals day'), ('anniversary'),
  ('attachment'), ('self-love')
ON CONFLICT (slug) DO NOTHING;

-- Anyone signed in reads the vocabulary (it's what populates the composer's
-- chip picker and the tag-browse/search surface). No RLS needed for the same
-- reason opinions' public content has none beyond removed_at filtering --
-- this table has no removed_at because a fixed vocabulary is never removed
-- by a user action, only by a future migration.
REVOKE ALL ON TABLE public.tags FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.tags TO authenticated;

-- ---------------------------------------------------------------------------
-- Join tables. Two, not one polymorphic (post_type, post_id) table -- keeps
-- each FK a real REFERENCES constraint instead of an unenforced
-- discriminator column, matching how post_polls uses two nullable FKs rather
-- than a generic content-type system.
--
-- No RLS/direct grants on either: these are populated ONLY by
-- attach_opinion_tags / attach_forum_topic_tags below (SECURITY DEFINER, the
-- same access model as opinion_saves/opinion_reposts' write paths run
-- through their RPCs), and read ONLY by the tag-browse RPCs, which resolve
-- author_handle server-side the same way every other read path already
-- does. A client is never expected to SELECT these tables directly.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.opinion_tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opinion_id uuid NOT NULL REFERENCES public.opinions ON DELETE CASCADE,
  tag_id uuid NOT NULL REFERENCES public.tags,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (opinion_id, tag_id)
);

CREATE INDEX IF NOT EXISTS opinion_tags_tag_id_idx ON public.opinion_tags (tag_id);
CREATE INDEX IF NOT EXISTS opinion_tags_opinion_id_idx ON public.opinion_tags (opinion_id);

CREATE TABLE IF NOT EXISTS public.forum_topic_tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid NOT NULL REFERENCES public.forum_topics ON DELETE CASCADE,
  tag_id uuid NOT NULL REFERENCES public.tags,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (topic_id, tag_id)
);

CREATE INDEX IF NOT EXISTS forum_topic_tags_tag_id_idx ON public.forum_topic_tags (tag_id);
CREATE INDEX IF NOT EXISTS forum_topic_tags_topic_id_idx ON public.forum_topic_tags (topic_id);

REVOKE ALL ON TABLE public.opinion_tags FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.forum_topic_tags FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Attach tags to a just-created opinion. Called once, immediately after
-- create_opinion[_with_poll|_with_quote] returns the new id -- there is no
-- separate "retag" RPC in v1 (see spec: "not independently editable after
-- posting").
--
-- Caps at 3 (a CHECK constraint cannot count sibling rows, so this is
-- enforced here, not in the schema). Silently de-duplicates repeated slugs
-- in the input rather than erroring, and silently ignores any slug not in
-- the fixed vocabulary rather than erroring -- a client sending a slug this
-- version of the app doesn't recognise (e.g. a future app build's tag,
-- talking to an older backend) degrades to "fewer tags attached" rather than
-- failing the whole post, which has already been created by the time this
-- runs.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.attach_opinion_tags(
  p_opinion_id uuid,
  p_tag_slugs text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_tag_slugs IS NULL OR array_length(p_tag_slugs, 1) IS NULL THEN
    RETURN;
  END IF;

  -- Ownership check: only the opinion's author may attach tags to it (tags
  -- are set at creation, so this only ever fires as part of that same flow,
  -- but the check makes the RPC safe to call standalone regardless).
  IF NOT EXISTS (
    SELECT 1 FROM public.opinions WHERE id = p_opinion_id AND user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'not_owner' USING ERRCODE = '42501';
  END IF;

  IF (
    SELECT count(DISTINCT slug) FROM unnest(p_tag_slugs) AS slug
  ) > 3 THEN
    RAISE EXCEPTION 'too_many_tags' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.opinion_tags (opinion_id, tag_id)
  SELECT p_opinion_id, t.id
  FROM (SELECT DISTINCT slug FROM unnest(p_tag_slugs) AS slug) s
  JOIN public.tags t ON t.slug = s.slug
  ON CONFLICT (opinion_id, tag_id) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.attach_opinion_tags(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attach_opinion_tags(uuid, text[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.attach_forum_topic_tags(
  p_topic_id uuid,
  p_tag_slugs text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_tag_slugs IS NULL OR array_length(p_tag_slugs, 1) IS NULL THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.forum_topics WHERE id = p_topic_id AND submitted_by = v_uid
  ) THEN
    RAISE EXCEPTION 'not_owner' USING ERRCODE = '42501';
  END IF;

  IF (
    SELECT count(DISTINCT slug) FROM unnest(p_tag_slugs) AS slug
  ) > 3 THEN
    RAISE EXCEPTION 'too_many_tags' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.forum_topic_tags (topic_id, tag_id)
  SELECT p_topic_id, t.id
  FROM (SELECT DISTINCT slug FROM unnest(p_tag_slugs) AS slug) s
  JOIN public.tags t ON t.slug = s.slug
  ON CONFLICT (topic_id, tag_id) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.attach_forum_topic_tags(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attach_forum_topic_tags(uuid, text[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- Read a post's own tags, for rendering chips on its card. One row per tag,
-- fixed slug list, no pagination needed (max 3 rows ever).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_opinion_tags(p_opinion_id uuid)
RETURNS TABLE (slug text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT t.slug
  FROM public.opinion_tags ot
  JOIN public.tags t ON t.id = ot.tag_id
  WHERE ot.opinion_id = p_opinion_id
  ORDER BY t.slug;
$$;
REVOKE ALL ON FUNCTION public.get_opinion_tags(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_opinion_tags(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_forum_topic_tags(p_topic_id uuid)
RETURNS TABLE (slug text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT t.slug
  FROM public.forum_topic_tags ft
  JOIN public.tags t ON t.id = ft.tag_id
  WHERE ft.topic_id = p_topic_id
  ORDER BY t.slug;
$$;
REVOKE ALL ON FUNCTION public.get_forum_topic_tags(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_forum_topic_tags(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Batch tag lookup for a feed page (avoids N+1 -- one call per rendered
-- page instead of one per card), mirroring get_polls_for_opinions'
-- shape from the polls migration.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_tags_for_opinions(p_opinion_ids uuid[])
RETURNS TABLE (opinion_id uuid, slug text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT ot.opinion_id, t.slug
  FROM public.opinion_tags ot
  JOIN public.tags t ON t.id = ot.tag_id
  WHERE ot.opinion_id = ANY(p_opinion_ids)
  ORDER BY ot.opinion_id, t.slug;
$$;
REVOKE ALL ON FUNCTION public.get_tags_for_opinions(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_tags_for_opinions(uuid[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_tags_for_forum_topics(p_topic_ids uuid[])
RETURNS TABLE (topic_id uuid, slug text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT ft.topic_id, t.slug
  FROM public.forum_topic_tags ft
  JOIN public.tags t ON t.id = ft.tag_id
  WHERE ft.topic_id = ANY(p_topic_ids)
  ORDER BY ft.topic_id, t.slug;
$$;
REVOKE ALL ON FUNCTION public.get_tags_for_forum_topics(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_tags_for_forum_topics(uuid[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- The full fixed vocabulary, for the composer's chip picker and the
-- tag-browse/search surface.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_all_tags()
RETURNS TABLE (slug text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT slug FROM public.tags ORDER BY slug;
$$;
REVOKE ALL ON FUNCTION public.get_all_tags() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_all_tags() TO authenticated;

-- ---------------------------------------------------------------------------
-- Tag browse: every opinion carrying a given tag, most recent first.
-- Deliberately takes ONLY a tag slug -- no author_handle parameter exists
-- anywhere in this file, and none should ever be added. Combining a tag
-- filter with an author filter would let a client narrow in on one person's
-- posts by topic, exactly the deanonymization risk fixed tags exist to
-- avoid (see spec). Same anonymized row shape as get_discover_opinions.
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
    -- Same hide/mute exclusion the passive feeds already apply (see
    -- 20260730130000_opinion_mute_and_hide.sql) -- a tag browse is a passive
    -- discovery surface like Discover/Following, not a deliberate personal
    -- list like Saved/Reposted, so it gets the same filter.
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
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_opinions_by_tag(text, int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_opinions_by_tag(text, int, int) TO authenticated;

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
  -- No is_mine/user_vote/user_side here: this mirrors the plain columns
  -- forum_topics itself carries (no per-viewer reaction join), matching how
  -- the base topic tables expose no anonymized wrapper of their own today --
  -- tag browse for forum topics returns the same shape a direct topic list
  -- already would.
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
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;
REVOKE ALL ON FUNCTION public.get_forum_topics_by_tag(text, int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_forum_topics_by_tag(text, int, int) TO authenticated;
