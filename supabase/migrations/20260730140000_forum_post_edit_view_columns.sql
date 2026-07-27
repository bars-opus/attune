-- Closes a gap found while wiring FORUM.md §7 "Editing" onto forum posts.
--
-- Forum posts are read through the public_forum_posts VIEW
-- (20260716120000_forums_opinions_launch.sql), never an RPC like every other
-- read path in this feature. The edit-window migration
-- (20260730120000_edit_window_opinions_comments_forum_posts.sql) added
-- edited_at to the underlying forum_posts TABLE and to every opinion-side
-- read RPC, but this view was not part of that migration's scope and was
-- never redefined -- so a forum post's "(edited)" marker had no column to
-- read, and there was no way for a client to know it owns a given post at
-- all (the view projects no user_id-derived column whatsoever).
--
-- Two columns added:
--   * edited_at -- direct passthrough, same as every opinion-side RPC.
--   * is_mine -- (user_id = auth.uid()), the exact pattern every other read
--     path in this feature already uses (get_discover_opinions,
--     get_opinion_comments, etc.) to expose ownership without ever exposing
--     the real user_id itself. A view evaluates auth.uid() per querying
--     session automatically (no SECURITY DEFINER needed, unlike the RPCs --
--     this view was never SECURITY DEFINER and does not need to become one),
--     so this is a live, per-viewer computed column, not a stored one.
--
-- user_id itself is NOT added to the view and must never be -- FORUM.md §3.

CREATE OR REPLACE VIEW public.public_forum_posts AS
SELECT
  id,
  topic_id,
  side,
  content,
  relationship_status_at_post,
  reply_to_post_id,
  quoted_text,
  like_count,
  created_at,
  edited_at,
  (user_id = auth.uid()) AS is_mine
FROM public.forum_posts
WHERE removed_at IS NULL
  AND hidden_pending_review = false;

-- CREATE OR REPLACE VIEW can append trailing columns without a drop (unlike
-- RETURNS TABLE functions, a view is not restricted to appending only -- but
-- appending is what happened here regardless, and Postgres allows changing a
-- view's column list via OR REPLACE as long as existing column
-- names/positions/types are preserved, which they are). The existing GRANT
-- SELECT ON public.public_forum_posts TO authenticated from the launch
-- migration already covers the new columns; no grant change needed.
