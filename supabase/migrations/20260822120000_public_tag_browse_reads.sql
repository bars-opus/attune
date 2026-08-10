-- TagBrowseScreen shows an "access denied" state to guests, not because the
-- screen itself gates on auth (it has no client-side check at all), but
-- because both RPCs behind it are authenticated-only: get_opinions_by_tag
-- and get_forum_topics_by_tag. A guest's call 42501s, which opinionsAsync/
-- topicsAsync then renders as an error state.
--
-- Same posture as the two prior anon-read grants this milestone
-- (20260818120000_public_opinion_reads, 20260821120000_public_forum_reads):
--
--   * get_opinions_by_tag is SECURITY DEFINER, returns only the HMAC'd
--     author_handle (never user_id), and every auth.uid() reference degrades
--     safely to NULL for a guest — is_mine/is_saved/is_reposted_by_me become
--     false, the hide/mute NOT EXISTS filters simply match nothing.
--     removed_at/hidden_pending_review are enforced inside the function
--     body, so moderated content stays hidden from guests too.
--   * get_forum_topics_by_tag is SECURITY DEFINER and returns no per-viewer
--     or user_id column at all — it is a strict subset of what
--     get_active_forums_filtered (already anon-granted) exposes.
--
-- Reads only. Attaching a tag to a new post still requires phone-verified
-- auth in the composer, unaffected by this grant.

GRANT EXECUTE ON FUNCTION public.get_opinions_by_tag(text, int, int) TO anon;
GRANT EXECUTE ON FUNCTION public.get_forum_topics_by_tag(text, int, int) TO anon;
