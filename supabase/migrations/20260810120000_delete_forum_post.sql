-- Forum posts had no delete path at all (only edit and report) — unlike
-- opinion comments, which already have deleteComment + a counter-decrement
-- RPC. Adds the forum equivalent so ForumPostBubble's upcoming swipe-to-
-- delete has something to call: forum_posts_owner_update (from
-- 20260716120000) already lets an owner set removed_at client-side, exactly
-- like opinion_comments_owner_update does for comments, so no RLS change is
-- needed there — this migration only adds the counter-decrement RPC.
--
-- Mirrors decrement_opinion_comment_count's shape (GREATEST(..., 0), same
-- SECURITY DEFINER/search_path), but a forum topic tracks three counters
-- where an opinion tracks one: total_posts always decrements, and exactly
-- one of for_posts/against_posts decrements too, chosen by the deleted
-- post's own side — mirrors increment_topic_post_count's CASE pairing in
-- reverse.
CREATE OR REPLACE FUNCTION public.decrement_topic_post_count(
  p_topic_id uuid,
  p_side text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.forum_topics
  SET
    total_posts = GREATEST(COALESCE(total_posts, 0) - 1, 0),
    for_posts = CASE
      WHEN p_side = 'for' THEN GREATEST(COALESCE(for_posts, 0) - 1, 0)
      ELSE COALESCE(for_posts, 0)
    END,
    against_posts = CASE
      WHEN p_side = 'against' THEN GREATEST(COALESCE(against_posts, 0) - 1, 0)
      ELSE COALESCE(against_posts, 0)
    END
  WHERE id = p_topic_id;
END;
$$;
REVOKE ALL ON FUNCTION public.decrement_topic_post_count(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decrement_topic_post_count(uuid, text) TO authenticated;
