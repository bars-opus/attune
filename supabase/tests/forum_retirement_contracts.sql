-- supabase/tests/forum_retirement_contracts.sql
-- Spec 3 (forum removal) §7.3: the forum producers are shut and shown to be
-- shut, and Opinions (polls, tags, reports, bans, notifications) behaves
-- exactly as before. W2 sections A-E; W3 adds F. Fixture ids use the
-- 9f3a0000- prefix and phones +1555094xxxx (both free on attune_spec3a).
-- Every failure names the offending job, push, grant or behaviour.
BEGIN;

-- ---------------------------------------------------------------------
-- A. Crons: no forum job by name or by what it runs.
-- ---------------------------------------------------------------------
DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(coalesce(jobname, '<unnamed>') || ' (jobid ' || jobid || ')', ', ')
    INTO v_bad
    FROM cron.job
   WHERE jobname IN ('activate-topics-sweep', 'forum-quiet-check', 'mark-quiet-forums')
      OR command ~* '(activate-topics|forum-quiet-check|forum_topics|mark_quiet_topics|activate_pending_topics|expire_old_topics|notify_quiet_topic)';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: forum cron still scheduled: %', v_bad;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- B. Grants: no client can run a forum RPC or touch a forum relation.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_sig text;
  v_rel text;
  v_role text;
  v_priv text;
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
    IF to_regprocedure(v_sig) IS NULL THEN CONTINUE; END IF;
    -- service_role too: a stale edge-function deploy fails at its first RPC.
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
      IF has_function_privilege(v_role, v_sig, 'EXECUTE') THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % can still execute %', v_role, v_sig;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH v_rel IN ARRAY ARRAY[
    'public.forum_topics', 'public.topic_votes', 'public.topic_impressions',
    'public.forum_posts', 'public.forum_post_likes', 'public.user_forum_sides',
    'public.forum_topic_tags', 'public.forum_topic_visits',
    'public.public_forum_topics', 'public.public_forum_posts'
  ] LOOP
    IF to_regclass(v_rel) IS NULL THEN CONTINUE; END IF;
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
      FOREACH v_priv IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'] LOOP
        IF has_table_privilege(v_role, v_rel, v_priv) THEN
          RAISE EXCEPTION 'CONTRACT VIOLATED: % still has % on %', v_role, v_priv, v_rel;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  -- The two views carry no service_role grant either.
  FOREACH v_rel IN ARRAY ARRAY['public.public_forum_topics', 'public.public_forum_posts'] LOOP
    IF to_regclass(v_rel) IS NOT NULL
       AND has_table_privilege('service_role', v_rel, 'SELECT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: service_role can still read %', v_rel;
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- C. Pushes: no retired forum push is waiting, and the health check
-- notices one that is.
-- ---------------------------------------------------------------------
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE status IN ('pending', 'processing')
     AND metadata->>'type' IN ('forum_topic_activated', 'forum_activity', 'forum_quiet');
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % forum pushes still queued', v_n;
  END IF;
END $$;

INSERT INTO auth.users (id) VALUES ('9f3a0000-0000-0000-0000-0000000000c1')
ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  v_user constant uuid := '9f3a0000-0000-0000-0000-0000000000c1';
  v_id uuid;
BEGIN
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata)
  VALUES (v_user, 'immediate', now(), 'pending',
          jsonb_build_object('type', 'forum_quiet', 'title', 'Forum check', 'body', 'Tap me',
                             'topic_id', gen_random_uuid()::text))
  RETURNING id INTO v_id;
  IF (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'forum_pushes_not_queued') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check missed a pending forum push';
  END IF;
  UPDATE public.scheduled_notifications SET status = 'cancelled' WHERE id = v_id;
  IF NOT (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'forum_pushes_not_queued') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check still sees a cancelled forum push';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- Health: every W2 check is ok, the cron and Opinions checks really look,
-- and only the service role can run it.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_bad text;
  v_job bigint;
BEGIN
  SELECT string_agg(check_name || ': ' || detail, '; ') INTO v_bad
    FROM public.forum_retirement_health() WHERE NOT ok;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: forum_retirement_health not ok: %', v_bad;
  END IF;
  -- By name, not by count: W3 adds two more checks.
  IF (SELECT count(*) FROM public.forum_retirement_health()
       WHERE check_name IN ('forum_cron_unscheduled', 'forum_pushes_not_queued',
                            'forum_rpcs_closed_to_clients', 'forum_tables_closed_to_clients',
                            'opinions_shared_objects_present')) <> 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W2 forum_retirement_health check is missing';
  END IF;

  -- The production-only nightly sweep, registered again by hand.
  v_job := cron.schedule('mark-quiet-forums', '0 1 * * *', 'select 1');
  IF (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'forum_cron_unscheduled') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check missed mark-quiet-forums';
  END IF;
  PERFORM cron.unschedule(v_job);
  -- A copy under another name is caught by what it runs.
  v_job := cron.schedule('nightly-cleanup-copy', '0 2 * * *',
    $cmd$UPDATE public.forum_topics SET status = 'quiet' WHERE false$cmd$);
  IF (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'forum_cron_unscheduled') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check missed a renamed forum job';
  END IF;
  PERFORM cron.unschedule(v_job);
  IF NOT (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'forum_cron_unscheduled') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the cron check stayed red after unscheduling';
  END IF;

  -- The Opinions sentinel really looks: guest polls losing their grant
  -- turns it red (restored at once; everything here rolls back anyway).
  REVOKE EXECUTE ON FUNCTION public.get_post_poll(uuid, uuid) FROM anon;
  IF (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'opinions_shared_objects_present') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check missed get_post_poll losing its anon grant';
  END IF;
  GRANT EXECUTE ON FUNCTION public.get_post_poll(uuid, uuid) TO anon;

  IF has_function_privilege('anon', 'public.forum_retirement_health()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.forum_retirement_health()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.forum_retirement_health()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: forum_retirement_health is not service-role only';
  END IF;
  IF NOT (SELECT coalesce(p.proconfig, '{}') @> ARRAY['search_path=""']
            FROM pg_proc p WHERE p.oid = 'public.forum_retirement_health()'::regprocedure) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: forum_retirement_health has a non-empty search_path';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- D. Keep-list sentinels: what Opinions uses is still open.
-- ---------------------------------------------------------------------
DO $$
DECLARE v_sig text;
BEGIN
  -- Guest Opinions polls: the only anon grant on get_post_poll lives in a
  -- forum migration (20260821120000:40). Spec 3 V3.
  IF NOT has_function_privilege('anon', 'public.get_post_poll(uuid,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_post_poll(uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_post_poll lost its anon or authenticated grant';
  END IF;
  FOREACH v_sig IN ARRAY ARRAY[
    'public.get_discover_opinions(integer,integer,text[])',
    'public.get_opinion_comments(uuid)',
    'public.get_all_tags()',
    'public.get_tags_for_opinions(uuid[])',
    'public.get_opinions_by_tag(text,integer,integer)',
    'public.get_opinion_tags(uuid)'
  ] LOOP
    IF NOT has_function_privilege('anon', v_sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: guests can no longer run %', v_sig;
    END IF;
  END LOOP;
  FOREACH v_sig IN ARRAY ARRAY[
    'public.create_opinion(text)',
    'public.create_opinion_comment(uuid,text,uuid,text)',
    'public.create_opinion_with_poll(text,text[])',
    'public.cast_poll_vote(uuid)',
    'public.retract_poll_vote(uuid)',
    'public.get_polls_for_opinions(uuid[])',
    'public.report_opinion(uuid,text)',
    'public.report_opinion_comment(uuid,text)'
  ] LOOP
    IF NOT has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: signed-in users can no longer run %', v_sig;
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- E. Opinions behaviour: limits, comments, reports, polls (guest and
-- voter), strikes, the ban gate and Opinions notifications are unchanged.
-- A writes; B reports and votes; C posts the poll.
-- ---------------------------------------------------------------------
INSERT INTO auth.users (id) VALUES
  ('9f3a0000-0000-0000-0000-00000000000a'),
  ('9f3a0000-0000-0000-0000-00000000000b'),
  ('9f3a0000-0000-0000-0000-00000000000c')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9f3a0000-0000-0000-0000-00000000000a', '+15550940001', 'Spec3 A'),
  ('9f3a0000-0000-0000-0000-00000000000b', '+15550940002', 'Spec3 B'),
  ('9f3a0000-0000-0000-0000-00000000000c', '+15550940003', 'Spec3 C')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id) VALUES
  ('9f3a0000-0000-0000-0000-00000000000a'),
  ('9f3a0000-0000-0000-0000-00000000000b'),
  ('9f3a0000-0000-0000-0000-00000000000c')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.as_anon() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
END $$;

-- The connecting (owner) role with a service-role JWT: how the SQL editor
-- and edge functions reach admin_confirm_content_removal.
CREATE FUNCTION pg_temp.as_service() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
END $$;

DO $$
DECLARE
  v_a constant uuid := '9f3a0000-0000-0000-0000-00000000000a';
  v_b constant uuid := '9f3a0000-0000-0000-0000-00000000000b';
  v_c constant uuid := '9f3a0000-0000-0000-0000-00000000000c';
  v_o1 uuid;
  v_o2 uuid;
  v_poll_opinion uuid;
  v_comment uuid;
  v_yes uuid;
  v_n int;
  v_visible int;
  v_msg text;
  r record;
BEGIN
  -- A posts; an immediate second post hits the 60 s cooldown (assert_can_post).
  PERFORM pg_temp.as_user(v_a);
  v_o1 := public.create_opinion('Spec 3 contract: trust is built in small moments.');
  BEGIN
    PERFORM public.create_opinion('Spec 3 contract: a second post, too soon.');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second opinion inside 60 s was accepted';
  EXCEPTION WHEN SQLSTATE '53400' THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'cooldown' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: expected cooldown, got %', v_msg;
    END IF;
  END;
  v_comment := public.create_opinion_comment(v_o1, 'Spec 3 contract: A replies to themselves.');
  RESET ROLE;
  IF v_o1 IS NULL OR v_comment IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: create_opinion or create_opinion_comment returned null';
  END IF;

  -- B reports the opinion twice (deduplicated) and the comment once.
  PERFORM pg_temp.as_user(v_b);
  PERFORM public.report_opinion(v_o1, 'Spam');
  PERFORM public.report_opinion(v_o1, 'Spam');
  PERFORM public.report_opinion_comment(v_comment, 'Spam');
  RESET ROLE;
  SELECT count(*) INTO v_n FROM public.forum_reports WHERE reported_by = v_b AND opinion_id = v_o1;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % opinion reports from one reporter, expected 1', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.forum_reports WHERE reported_by = v_b AND comment_id = v_comment;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % comment reports, expected 1', v_n;
  END IF;

  -- C posts an opinion with a poll.
  PERFORM pg_temp.as_user(v_c);
  v_poll_opinion := public.create_opinion_with_poll('Spec 3 contract: do you text first?', ARRAY['Yes', 'No']);
  RESET ROLE;
  SELECT count(*) INTO v_n FROM public.post_polls WHERE opinion_id = v_poll_opinion;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: create_opinion_with_poll made % polls, expected 1', v_n;
  END IF;

  -- A guest sees the poll with its counts hidden.
  PERFORM pg_temp.as_anon();
  SELECT count(*), count(vote_count) INTO v_n, v_visible
    FROM public.get_post_poll(p_opinion_id => v_poll_opinion);
  RESET ROLE;
  IF v_n <> 2 OR v_visible <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: guest poll read gave % rows, % visible counts', v_n, v_visible;
  END IF;

  -- B votes Yes and then sees the counts.
  SELECT o.id INTO v_yes FROM public.poll_options o
    JOIN public.post_polls p ON p.id = o.poll_id
   WHERE p.opinion_id = v_poll_opinion AND o.label = 'Yes';
  PERFORM pg_temp.as_user(v_b);
  PERFORM public.cast_poll_vote(v_yes);
  SELECT * INTO r FROM public.get_post_poll(p_opinion_id => v_poll_opinion) WHERE option_id = v_yes;
  RESET ROLE;
  IF r.vote_count IS DISTINCT FROM 1 OR r.has_voted IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after voting B saw vote_count %, has_voted %', r.vote_count, r.has_voted;
  END IF;

  -- Confirmed removals count strikes. Strikes 1 and 2 only: the live
  -- function raises 42702 ("banned_until" is ambiguous) at strike 3, a
  -- pre-existing Opinions defect this spec does not change (plan finding
  -- F-2). The ban gate itself is checked below with a ban set directly.
  INSERT INTO public.opinions (user_id, content) VALUES (v_a, 'Spec 3 contract: strike two.') RETURNING id INTO v_o2;
  PERFORM pg_temp.as_service();
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o1);
  IF r.violation_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: first removal gave violation_count %', r.violation_count;
  END IF;
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o2);
  IF r.violation_count IS DISTINCT FROM 2 OR r.banned_until IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: second removal gave violation_count %, banned_until %',
      r.violation_count, r.banned_until;
  END IF;
  IF (SELECT removed_at FROM public.opinions WHERE id = v_o1) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a confirmed removal left the opinion visible';
  END IF;
  RESET ROLE;
  UPDATE public.profiles SET banned_until = now() + interval '7 days' WHERE id = v_a;

  -- A banned author cannot post (the assert_can_post ban gate).
  PERFORM pg_temp.as_user(v_a);
  BEGIN
    PERFORM public.create_opinion('Spec 3 contract: posting while banned.');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a banned author posted';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'posting_banned' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: expected posting_banned, got %', v_msg;
    END IF;
  END;
  RESET ROLE;

  -- Opinions notifications still go through the kept "forum" helper.
  PERFORM private.enqueue_forum_notification(
    p_user_id => v_a, p_title => 't', p_body => 'b',
    p_type => 'opinion_liked', p_opinion_id => v_poll_opinion);
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE user_id = v_a AND status = 'pending' AND metadata->>'type' = 'opinion_liked';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % opinion_liked pushes queued for A, expected 1', v_n;
  END IF;
END $$;
RESET ROLE;

DO $$ BEGIN RAISE NOTICE 'forum_retirement_contracts: all held'; END $$;
ROLLBACK;
