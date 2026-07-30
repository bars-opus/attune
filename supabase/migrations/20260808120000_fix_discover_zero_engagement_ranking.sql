-- Fixes a ranking bug in Discover: private.opinion_rank_score's numerator was
-- ((likes - dislikes) + comments*2 + reposts*2), so a brand-new opinion with
-- zero engagement scored EXACTLY 0 — sorting below any post with net-positive
-- engagement no matter how old, and only above posts with net-negative
-- engagement. A fresh post could land in the middle of the feed, or even
-- below days-old posts, instead of getting any real "recency" lift.
--
-- Fix: add 1 to the numerator (Hacker News/Reddit "hot"-style ranking), so a
-- brand-new post scores 1 * (1 / (hours_since_post + 1)) — a real, decaying
-- score that starts high and sinks over the next few hours as it's overtaken
-- by newer posts or ones gaining actual engagement, rather than starting at
-- the floor. This changes relative ranking for every opinion, not just new
-- ones: a CREATE OR REPLACE on the shared helper is enough since
-- get_discover_opinions calls it live on every read rather than storing a
-- score.
--
-- Signature/return type unchanged, so REPLACE is safe (no DROP needed).

CREATE OR REPLACE FUNCTION private.opinion_rank_score(
  p_like_count int,
  p_dislike_count int,
  p_comment_count int,
  p_repost_count int,
  p_created_at timestamptz
)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    (((p_like_count - p_dislike_count) + (p_comment_count * 2) + (p_repost_count * 2)) + 1)
      * (1.0 / (EXTRACT(EPOCH FROM (now() - p_created_at)) / 3600.0 + 1));
$$;
REVOKE ALL ON FUNCTION private.opinion_rank_score(int, int, int, int, timestamptz) FROM PUBLIC, anon, authenticated;
