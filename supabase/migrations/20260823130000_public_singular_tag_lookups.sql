-- get_opinion_tags and get_forum_topic_tags — the singular, per-item
-- counterparts to the batched get_tags_for_opinions / get_tags_for_forum_topics
-- granted earlier — were still authenticated-only. Both have no Dart caller
-- today (OpinionRepository.getOpinionTags and ForumRepository.getForumTopicTags
-- are dead code), so this closes a landmine for whoever wires either up next
-- rather than fixing a live guest-facing bug.
--
-- Same posture as every other tag grant this milestone: SECURITY DEFINER, no
-- user_id, no auth.uid() reference — a pure (item_id) -> tag slugs lookup.

GRANT EXECUTE ON FUNCTION public.get_opinion_tags(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.get_forum_topic_tags(uuid) TO anon;
