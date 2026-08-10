-- OpinionCard renders no tags for a guest, silently — not an error state,
-- because OpinionRepository.withSideData swallows a failed tag lookup on
-- purpose ("tags are decoration, a tag outage must not fail the feed").
-- get_tags_for_opinions was still authenticated-only, so every guest page
-- load's tag merge 42501'd and was quietly discarded, leaving every card
-- untagged.
--
-- This was the one piece missed when opinions/forums were opened up to
-- guests (20260818120000_public_opinion_reads,
-- 20260821120000_public_forum_reads): the sibling get_tags_for_forum_topics
-- and get_quote_counts were already anon-granted, this one was not.
--
-- Same posture as those: SECURITY DEFINER, no user_id, no auth.uid()
-- reference at all — a pure (opinion_id, tag_slug) lookup, safe for anon.

GRANT EXECUTE ON FUNCTION public.get_tags_for_opinions(uuid[]) TO anon;
