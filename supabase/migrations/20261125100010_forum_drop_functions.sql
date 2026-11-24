-- Spec 3 (forum removal) W3, migration 2 of 6: the 29 forum-only functions
-- (Spec 3 §3.9), closed to every role since W2 (20261025090100). This also
-- removes the realtime senders of topic-counts:<id> and post-counts:<id>.
-- RESTRICT: an unexpected dependency fails loudly instead of cascading.
-- Kept (Spec 3 §4): private.enqueue_forum_notification, private.assert_can_post,
-- public.admin_confirm_content_removal, public.get_post_poll (and its anon
-- grant), private.create_poll_for_post, every poll, tag and Opinions RPC.
-- Idempotent: IF EXISTS.
BEGIN;
SET LOCAL lock_timeout = '5s';

DROP FUNCTION IF EXISTS public.activate_pending_topics() RESTRICT;
DROP FUNCTION IF EXISTS public.expire_old_topics() RESTRICT;
DROP FUNCTION IF EXISTS public.mark_quiet_topics() RESTRICT;
DROP FUNCTION IF EXISTS public.notify_quiet_topic(uuid) RESTRICT;
DROP FUNCTION IF EXISTS private.queue_forum_activity_notifications(uuid, uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.record_forum_topic_visit(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.create_forum_post(uuid, text, text, uuid, text) RESTRICT;
DROP FUNCTION IF EXISTS public.create_forum_topic(text) RESTRICT;
DROP FUNCTION IF EXISTS public.create_forum_topic_with_poll(text, text[]) RESTRICT;
DROP FUNCTION IF EXISTS public.edit_forum_post(uuid, text) RESTRICT;
DROP FUNCTION IF EXISTS public.attach_forum_topic_tags(uuid, text[]) RESTRICT;
DROP FUNCTION IF EXISTS public.get_forum_topic_tags(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.get_forum_topics_by_tag(text, integer, integer) RESTRICT;
DROP FUNCTION IF EXISTS public.get_tags_for_forum_topics(uuid[]) RESTRICT;
DROP FUNCTION IF EXISTS public.get_polls_for_topics(uuid[]) RESTRICT;
DROP FUNCTION IF EXISTS public.get_active_forums_filtered(text[]) RESTRICT;
DROP FUNCTION IF EXISTS public.get_quiet_forums_filtered(text[]) RESTRICT;
DROP FUNCTION IF EXISTS public.get_voting_topics_filtered(text[]) RESTRICT;
DROP FUNCTION IF EXISTS public.increment_topic_upvote_count(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.decrement_topic_upvote_count(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.increment_topic_downvote_count(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.decrement_topic_downvote_count(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.increment_topic_post_count(uuid, text) RESTRICT;
DROP FUNCTION IF EXISTS public.decrement_topic_post_count(uuid, text) RESTRICT;
DROP FUNCTION IF EXISTS public.increment_topic_seen_count(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.increment_forum_post_like_count(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.decrement_forum_post_like_count(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.report_forum_post(uuid, text) RESTRICT;
DROP FUNCTION IF EXISTS public.report_forum_topic(uuid, text) RESTRICT;

COMMIT;
