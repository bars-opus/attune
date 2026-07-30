-- Adds get_author_reposted_opinions, so AnonymousProfileScreen can show a
-- "Reposts" tab when viewing someone ELSE's profile, not just your own.
--
-- get_reposted_opinions (20260803120000) only ever returns the CALLER's own
-- reposts (WHERE user_id = auth.uid()) -- there was no RPC to view another
-- author's repost list at all. Mirrors get_author_opinions's exact pattern
-- for resolving an author: filter by comparing the computed
-- opinion_author_handle() against the caller-supplied handle, never by
-- reverse-resolving a handle back to a user_id (FORUM.md §3 -- the handle ->
-- user_id mapping is one-directional; clients never compute or resolve it).
--
-- is_reposted_by_me here means "did the VIEWER also repost this opinion" --
-- computed fresh via a LEFT JOIN against auth.uid(), unlike
-- get_reposted_opinions where it's hardcoded `true` (there, the list IS your
-- own reposts by construction; here, the list is someone else's, and the
-- viewer's own repost state is a separate, genuine question).

CREATE OR REPLACE FUNCTION public.get_author_reposted_opinions(p_author_handle text)
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
    -- Repost time, not the original opinion's created_at -- matches
    -- get_reposted_opinions and get_following_opinions's UNION: a repost is
    -- ordered by when it was reposted, which is what makes it read as this
    -- author's recent activity rather than the original post's age.
    rp.created_at,
    public.opinion_author_handle(o.user_id) AS author_handle,
    (o.user_id = auth.uid()) AS is_mine,
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
    ON fc.user_id = o.user_id
  LEFT JOIN public.opinion_saves s
    ON s.opinion_id = o.id AND s.user_id = auth.uid()
  LEFT JOIN public.opinion_reposts viewer_rp
    ON viewer_rp.opinion_id = o.id AND viewer_rp.user_id = auth.uid()
  WHERE public.opinion_author_handle(rp.user_id) = p_author_handle
    AND o.removed_at IS NULL
    AND o.hidden_pending_review = false
  ORDER BY rp.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_author_reposted_opinions(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_author_reposted_opinions(text) TO authenticated;
