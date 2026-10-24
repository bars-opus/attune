-- Spec 3 (forum removal) W2, migration 2 of 4: close every forum RPC, table
-- and view, so an old app build or a stale edge-function deploy fails closed
-- (permission denied) instead of reading, writing or announcing forum content.
--
-- Functions and views: revoked from PUBLIC, anon, authenticated and
-- service_role (defence in depth: a stale activate-topics or
-- forum-quiet-check deploy fails at its first forum RPC, before any push).
--
-- Tables: revoked from PUBLIC, anon and authenticated only. service_role
-- keeps its table grants because supabase/tests/service_role_grants_test.sql
-- requires SELECT and UPDATE on every public table; both forum edge
-- functions push only through the revoked RPCs, so they stay inert. W3
-- drops the tables.
--
-- Deliberately NOT revoked (Spec 3 §4 keep list): public.get_post_poll
-- (uuid, uuid) and its anon grant (guest Opinions polls), forum_reports,
-- post_polls / poll_options / poll_votes, private.enqueue_forum_notification,
-- private.assert_can_post, public.admin_confirm_content_removal, tags and
-- every Opinions RPC.
--
-- Idempotent: REVOKE of a privilege that is not held is a no-op, and a
-- signature or relation that no longer exists is skipped with a NOTICE.
BEGIN;

DO $$
DECLARE
  v_sig text;
  v_rel text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.activate_pending_topics()',
    'public.expire_old_topics()',
    'public.mark_quiet_topics()',
    'public.notify_quiet_topic(uuid)',
    'private.queue_forum_activity_notifications(uuid,uuid)',
    'public.record_forum_topic_visit(uuid)',
    'public.create_forum_post(uuid,text,text,uuid,text)',
    'public.create_forum_topic(text)',
    'public.create_forum_topic_with_poll(text,text[])',
    'public.edit_forum_post(uuid,text)',
    'public.attach_forum_topic_tags(uuid,text[])',
    'public.get_forum_topic_tags(uuid)',
    'public.get_forum_topics_by_tag(text,integer,integer)',
    'public.get_tags_for_forum_topics(uuid[])',
    'public.get_polls_for_topics(uuid[])',
    'public.get_active_forums_filtered(text[])',
    'public.get_quiet_forums_filtered(text[])',
    'public.get_voting_topics_filtered(text[])',
    'public.increment_topic_upvote_count(uuid)',
    'public.decrement_topic_upvote_count(uuid)',
    'public.increment_topic_downvote_count(uuid)',
    'public.decrement_topic_downvote_count(uuid)',
    'public.increment_topic_post_count(uuid,text)',
    'public.decrement_topic_post_count(uuid,text)',
    'public.increment_topic_seen_count(uuid)',
    'public.increment_forum_post_like_count(uuid)',
    'public.decrement_forum_post_like_count(uuid)',
    'public.report_forum_post(uuid,text)',
    'public.report_forum_topic(uuid,text)'
  ] LOOP
    IF pg_catalog.to_regprocedure(v_sig) IS NULL THEN
      RAISE NOTICE 'forum_revoke_client_access: % does not exist, skipped', v_sig;
      CONTINUE;
    END IF;
    EXECUTE format(
      'REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',
      v_sig
    );
  END LOOP;

  FOREACH v_rel IN ARRAY ARRAY[
    'public.forum_topics',
    'public.topic_votes',
    'public.topic_impressions',
    'public.forum_posts',
    'public.forum_post_likes',
    'public.user_forum_sides',
    'public.forum_topic_tags',
    'public.forum_topic_visits'
  ] LOOP
    IF pg_catalog.to_regclass(v_rel) IS NULL THEN
      RAISE NOTICE 'forum_revoke_client_access: % does not exist, skipped', v_rel;
      CONTINUE;
    END IF;
    EXECUTE format('REVOKE ALL ON TABLE %s FROM PUBLIC, anon, authenticated', v_rel);
  END LOOP;

  FOREACH v_rel IN ARRAY ARRAY[
    'public.public_forum_topics',
    'public.public_forum_posts'
  ] LOOP
    IF pg_catalog.to_regclass(v_rel) IS NULL THEN
      RAISE NOTICE 'forum_revoke_client_access: % does not exist, skipped', v_rel;
      CONTINUE;
    END IF;
    EXECUTE format(
      'REVOKE ALL ON TABLE %s FROM PUBLIC, anon, authenticated, service_role',
      v_rel
    );
  END LOOP;
END
$$;

COMMIT;
