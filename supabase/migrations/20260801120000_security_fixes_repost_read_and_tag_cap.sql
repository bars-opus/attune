-- Two fixes found by an Algorithm Quality Review Checklist v3.1 audit of the
-- forum/opinions migrations from this work session.
--
-- ===========================================================================
-- Fix 1: opinion_reposts granted open SELECT to every authenticated user,
-- exposing the real user_id column (20260728120000_opinion_reposts.sql).
--
-- opinion_author_handle() is a deterministic HMAC(user_id) deliberately never
-- granted to clients, specifically so the handle -> user_id mapping stays
-- one-directional. A client that could SELECT (user_id, opinion_id) from this
-- table, then separately read a feed row's author_handle for a post it knows
-- that user_id reposted, could pair the two and start building a
-- user_id -> author_handle lookup table -- defeating the anonymity model this
-- entire feature set is built on.
--
-- The open read was unnecessary: every actual read path (get_reposted_opinions,
-- the is_reposted_by_me joins, the get_following_opinions UNION) is a
-- SECURITY DEFINER RPC and is unaffected by RLS on the base table. No Dart
-- code calls `.from('opinion_reposts')` directly (grepped). Replacing the
-- open policy with the owner-scoped one every sibling table
-- (opinion_saves, opinion_hides, opinion_mutes) already uses.
-- ===========================================================================

DROP POLICY IF EXISTS opinion_reposts_read ON public.opinion_reposts;

-- Was FOR SELECT TO authenticated USING (true) -- replaced with owner-scoped,
-- folded into the existing ALL policy below rather than kept as a second
-- policy, matching opinion_saves_owner's single-policy shape.
DROP POLICY IF EXISTS opinion_reposts_owner_write ON public.opinion_reposts;
CREATE POLICY opinion_reposts_owner
ON public.opinion_reposts FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Grants unchanged (SELECT, INSERT, DELETE already correct) -- RLS now
-- actually restricts what those grants can reach, which is the fix.

-- ===========================================================================
-- Fix 2: attach_opinion_tags / attach_forum_topic_tags counted only the
-- INPUT array against the 3-tag cap, never the tags already attached
-- (20260731120000_opinion_and_forum_topic_tags.sql). The header comment
-- claimed "caps at 3" but the check never queried opinion_tags/
-- forum_topic_tags, so two sequential calls -- no concurrency needed --
-- could attach 3, then 3 more, then 3 more, unbounded. Fixed to count
-- (existing rows for this post) + (new distinct slugs not already attached),
-- and locks the parent post row for the duration so two concurrent calls
-- from the same author cannot each pass a stale count -- the same
-- SELECT ... FOR UPDATE pattern cast_poll_vote already uses for its own
-- check-then-act vote change.
-- ===========================================================================

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
  v_locked_id uuid;
  v_existing_count int;
  v_new_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_tag_slugs IS NULL OR array_length(p_tag_slugs, 1) IS NULL THEN
    RETURN;
  END IF;

  -- Explicit SELECT ... FOR UPDATE, not a NOT EXISTS(... FOR UPDATE): a
  -- locking clause inside an EXISTS subquery is not guaranteed to hold the
  -- lock, since the row is never actually "returned to the outer query" the
  -- way a plain SELECT's rows are. Locks the opinion row so a second
  -- concurrent attach call from the same author blocks here until this one
  -- commits, rather than both reading the same pre-attach count.
  SELECT id INTO v_locked_id
  FROM public.opinions
  WHERE id = p_opinion_id AND user_id = v_uid
  FOR UPDATE;

  IF v_locked_id IS NULL THEN
    RAISE EXCEPTION 'not_owner' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_existing_count
  FROM public.opinion_tags WHERE opinion_id = p_opinion_id;

  -- Distinct NEW slugs this call would add (already-attached ones are a
  -- no-op via ON CONFLICT below and must not count against the cap again).
  SELECT count(*) INTO v_new_count
  FROM (SELECT DISTINCT slug FROM unnest(p_tag_slugs) AS slug) s
  JOIN public.tags t ON t.slug = s.slug
  WHERE NOT EXISTS (
    SELECT 1 FROM public.opinion_tags ot
    WHERE ot.opinion_id = p_opinion_id AND ot.tag_id = t.id
  );

  IF v_existing_count + v_new_count > 3 THEN
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
  v_locked_id uuid;
  v_existing_count int;
  v_new_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_tag_slugs IS NULL OR array_length(p_tag_slugs, 1) IS NULL THEN
    RETURN;
  END IF;

  -- See attach_opinion_tags for why this is an explicit SELECT ... FOR
  -- UPDATE rather than a NOT EXISTS(... FOR UPDATE).
  SELECT id INTO v_locked_id
  FROM public.forum_topics
  WHERE id = p_topic_id AND submitted_by = v_uid
  FOR UPDATE;

  IF v_locked_id IS NULL THEN
    RAISE EXCEPTION 'not_owner' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_existing_count
  FROM public.forum_topic_tags WHERE topic_id = p_topic_id;

  SELECT count(*) INTO v_new_count
  FROM (SELECT DISTINCT slug FROM unnest(p_tag_slugs) AS slug) s
  JOIN public.tags t ON t.slug = s.slug
  WHERE NOT EXISTS (
    SELECT 1 FROM public.forum_topic_tags ft
    WHERE ft.topic_id = p_topic_id AND ft.tag_id = t.id
  );

  IF v_existing_count + v_new_count > 3 THEN
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
