-- Let signed-out visitors read forums and browse debate rooms, the same way
-- 20260818120000_public_opinion_reads did for the Opinions feed.
--
-- ForumsSection now renders for guests too (previously it fell back to a
-- read-only ForumScreen placeholder). Explore's three lists, a topic's tags,
-- and a debate room's post thread all need to be anon-readable for that to
-- show real content instead of another placeholder.
--
-- Same anonymity posture as the opinions grant: every function here is
-- SECURITY DEFINER and returns no user_id (public_forum_posts computes
-- is_mine from auth.uid(), which is NULL for anon — a guest sees an
-- unpersonalised thread, not an unfiltered one). Moderation filters
-- (removed_at, hidden_pending_review) live in the view/function body, not in
-- the grant, so they still apply to a guest.
--
-- Deliberately NOT granted here: get_topic_details / public_forum_topics
-- already need anon SELECT for the debate room's own topic header, so no
-- separate decision exists to make there — but ForumInsightScreen (deeper
-- analytics on a topic) is NOT wired to open for a guest at the navigation
-- layer, matching the product decision that guests read forums but do not
-- see forum insights. Also not granted: everything that writes (posting,
-- voting, liking, reporting) or that is inherently the caller's own activity
-- (Contributing), both already correctly gated in the client.

GRANT EXECUTE ON FUNCTION public.get_voting_topics_filtered(text[]) TO anon;
GRANT EXECUTE ON FUNCTION public.get_active_forums_filtered(text[]) TO anon;
GRANT EXECUTE ON FUNCTION public.get_quiet_forums_filtered(text[]) TO anon;
GRANT EXECUTE ON FUNCTION public.get_tags_for_forum_topics(uuid[]) TO anon;

-- Powers the debate room's topic header (topicDetailsProvider) and Explore's
-- three lists (getVotingTopics/getActiveForums/getQuietForums all read this
-- indirectly via the RPCs above, but getTopicDetails reads it directly).
GRANT SELECT ON public.public_forum_topics TO anon;

-- Powers the debate room's post thread (forumPostsProvider).
GRANT SELECT ON public.public_forum_posts TO anon;

-- Powers a topic's poll, if it has one (§8.11) — rendered above the
-- FOR/AGAINST split in the debate room header, same as on an opinion.
GRANT EXECUTE ON FUNCTION public.get_post_poll(uuid, uuid) TO anon;
