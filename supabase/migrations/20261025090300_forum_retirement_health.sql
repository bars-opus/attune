-- Spec 3 (forum removal) W2, migration 4 of 4: forum_retirement_health(), the
-- on-demand proof that the forum producers are shut (Spec 3 D9). Run it from
-- the SQL editor; supabase/tests/forum_retirement_contracts.sql runs it too.
-- Not a cron: cron failures here go unread (20260931120000).
--
-- Missing objects resolve through to_regprocedure / to_regclass, so the same
-- function stays valid after W3 drops the forum schema. Same posture as
-- scheduled_jobs_health(): service role only.
BEGIN;

CREATE OR REPLACE FUNCTION public.forum_retirement_health()
RETURNS TABLE (check_name text, ok boolean, detail text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_forum_rpcs constant text[] := ARRAY[
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
  ];
  v_forum_relations constant text[] := ARRAY[
    'public.forum_topics',
    'public.topic_votes',
    'public.topic_impressions',
    'public.forum_posts',
    'public.forum_post_likes',
    'public.user_forum_sides',
    'public.forum_topic_tags',
    'public.forum_topic_visits',
    'public.public_forum_topics',
    'public.public_forum_posts'
  ];
  v_kept_relations constant text[] := ARRAY[
    'public.forum_reports',
    'public.post_polls',
    'public.poll_options',
    'public.poll_votes',
    'public.tags',
    'public.opinion_tags',
    'public.tag_follows'
  ];
  v_kept_functions constant text[] := ARRAY[
    'private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid)',
    'private.assert_can_post(uuid,text)',
    'public.admin_confirm_content_removal(text,uuid)'
  ];
  v_name text;
  v_fn regprocedure;
  v_rel regclass;
  v_bad text[];
BEGIN
  -- 1. No forum cron, by name or by what it runs.
  SELECT pg_catalog.array_agg(
           coalesce(j.jobname, '<unnamed>') || ' (jobid ' || j.jobid || ')'
           ORDER BY j.jobid)
    INTO v_bad
    FROM cron.job j
   WHERE j.jobname IN ('activate-topics-sweep', 'forum-quiet-check', 'mark-quiet-forums')
      OR j.command ~* '(activate-topics|forum-quiet-check|forum_topics|mark_quiet_topics|activate_pending_topics|expire_old_topics|notify_quiet_topic)';
  check_name := 'forum_cron_unscheduled';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;

  -- 2. No retired forum push waiting to go out or going out.
  SELECT pg_catalog.array_agg(DISTINCT (s.metadata->>'type') || ' ' || s.status)
    INTO v_bad
    FROM public.scheduled_notifications s
   WHERE s.status IN ('pending', 'processing')
     AND s.metadata->>'type' IN ('forum_topic_activated', 'forum_activity', 'forum_quiet');
  check_name := 'forum_pushes_not_queued';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;

  -- 3. No forum RPC a client can execute (a dropped one passes).
  v_bad := NULL;
  FOREACH v_name IN ARRAY v_forum_rpcs LOOP
    v_fn := pg_catalog.to_regprocedure(v_name);
    IF v_fn IS NOT NULL
       AND (pg_catalog.has_function_privilege('anon', v_fn, 'EXECUTE')
            OR pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE')) THEN
      v_bad := pg_catalog.array_append(v_bad, v_name);
    END IF;
  END LOOP;
  check_name := 'forum_rpcs_closed_to_clients';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;

  -- 4. No forum table or view a client can read or write (a dropped one passes).
  v_bad := NULL;
  FOREACH v_name IN ARRAY v_forum_relations LOOP
    v_rel := pg_catalog.to_regclass(v_name);
    IF v_rel IS NOT NULL
       AND (pg_catalog.has_table_privilege('anon', v_rel, 'SELECT, INSERT, UPDATE, DELETE')
            OR pg_catalog.has_table_privilege('authenticated', v_rel, 'SELECT, INSERT, UPDATE, DELETE')) THEN
      v_bad := pg_catalog.array_append(v_bad, v_name);
    END IF;
  END LOOP;
  check_name := 'forum_tables_closed_to_clients';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;

  -- 5. Everything Opinions shares with the old forum schema is still there,
  -- including guest polls.
  v_bad := NULL;
  FOREACH v_name IN ARRAY v_kept_relations LOOP
    IF pg_catalog.to_regclass(v_name) IS NULL THEN
      v_bad := pg_catalog.array_append(v_bad, v_name || ' missing');
    END IF;
  END LOOP;
  FOREACH v_name IN ARRAY v_kept_functions LOOP
    IF pg_catalog.to_regprocedure(v_name) IS NULL THEN
      v_bad := pg_catalog.array_append(v_bad, v_name || ' missing');
    END IF;
  END LOOP;
  v_fn := pg_catalog.to_regprocedure('public.get_post_poll(uuid,uuid)');
  IF v_fn IS NULL
     OR NOT pg_catalog.has_function_privilege('anon', v_fn, 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    v_bad := pg_catalog.array_append(v_bad, 'get_post_poll(uuid,uuid) not executable by anon and authenticated');
  END IF;
  v_fn := pg_catalog.to_regprocedure('public.create_opinion_with_poll(text,text[])');
  IF v_fn IS NULL
     OR NOT pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    v_bad := pg_catalog.array_append(v_bad, 'create_opinion_with_poll(text,text[]) not executable by authenticated');
  END IF;
  check_name := 'opinions_shared_objects_present';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;
END;
$$;

-- Service role only: it names the system's jobs and queue state.
REVOKE ALL ON FUNCTION public.forum_retirement_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.forum_retirement_health() TO service_role;

COMMIT;
