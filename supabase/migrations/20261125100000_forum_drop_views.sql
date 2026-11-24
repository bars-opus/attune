-- Spec 3 (forum removal) W3, migration 1 of 6: the preflight, then the two
-- forum views. Spec 3 §6.3, §3.9; risks R13-R15. Nothing is dropped unless
-- every check below holds, so a production database that differs from the
-- one this wave was built on stops here, before any data or schema goes:
--   (a) Inventory: every function in public or private that is named for
--       forums or topics, or whose body names a forum relation, topic_id or
--       forum_post_id, is one of the 36 this wave knows (the 29 forum-only
--       functions migration 2 drops, the 3 shared ones migration 5 rewrites
--       or keeps, private.opinion_stamp_backfill (Spec 1 W9d, rewritten in
--       migration 5), the 2 poll functions migration 4 rewrites, and
--       forum_retirement_health (migration 6)); and no function in any other
--       schema (but the system ones and extension members) names a forum
--       relation in its body. Anything extra: stop.
--   (b) Bodies: the five functions this wave re-creates still have the
--       body it was built from (md5 of prosrc), or already the new one (a
--       re-run), and the kept private.enqueue_forum_notification (every
--       Opinions push goes through it; W3 does not re-create it) has its
--       own. Otherwise stop: rebuild migrations 4-5 from
--       pg_get_functiondef on that database (Spec 3 §6.3 "from the live
--       definition").
--   (c) Dependencies: nothing outside the 10 forum relations depends on
--       them or on their row and array types (a view, a policy, a trigger, a
--       key, a column, a function signature) except the three foreign keys
--       migration 3 drops (post_polls_topic_id_fkey,
--       forum_reports_forum_post_id_fkey, forum_reports_topic_id_fkey) and
--       the 29 functions migration 2 drops; and nothing but those 29
--       depends on the 29 functions themselves (a view, a default, a
--       trigger, even one on a forum table: migration 2 drops them first).
--       Everything is dropped RESTRICT anyway.
--   (d) W2 holds: public.forum_retirement_health() reports no forum cron and
--       every Opinions object present (gate (c)); the kept
--       private.enqueue_forum_notification keeps its signature; and no cron
--       job's command names a forum relation or one of the 29 functions
--       (W2's check knows only the crons it retired).
--   (e) Opinions stamps (Spec 1 W9d): an account whose strikes or live ban
--       no stamp covers yet, with a removed forum post, needs that post counted by
--       private.opinion_stamp_backfill() before forum_posts goes (migration
--       3 runs it). That needs dating_exclusion_key: without it, stop.
-- Then: DROP VIEW ... RESTRICT for public_forum_posts and public_forum_topics.
-- Idempotent: a re-run passes (a)-(e) on the dropped schema and drops nothing.
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $$
DECLARE
  -- the 29 forum-only functions (migration 2)
  v_dropped constant text[] := ARRAY[
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
  v_known constant text[] := v_dropped || ARRAY[
    -- shared, kept (migrations 4-6 rewrite all but the notification helper)
    'private.assert_can_post(uuid,text)',
    'public.admin_confirm_content_removal(text,uuid)',
    'private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid)',
    'private.opinion_stamp_backfill()',
    'private.create_poll_for_post(uuid,uuid,uuid,text[])',
    'public.get_post_poll(uuid,uuid)',
    'public.forum_retirement_health()'
  ];
  v_forum_relations constant text[] := ARRAY[
    'public.forum_topics', 'public.topic_votes', 'public.topic_impressions',
    'public.forum_posts', 'public.forum_post_likes', 'public.user_forum_sides',
    'public.forum_topic_tags', 'public.forum_topic_visits',
    'public.public_forum_topics', 'public.public_forum_posts'
  ];
  v_bad text[];
  v_rels oid[];
  v_types oid[];
  v_dropped_oids oid[];
  r record;
  v_md5 text;
  v_n bigint;
BEGIN
  -- (a) The inventory. Case-blind (~*): unquoted names fold to lower case,
  -- so PUBLIC.FORUM_TOPICS in a body reads the same table.
  SELECT pg_catalog.array_agg(p.oid::pg_catalog.regprocedure::text ORDER BY p.oid::pg_catalog.regprocedure::text)
    INTO v_bad
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'private') AND p.prokind IN ('f', 'p')
     AND (p.proname ~* 'forum|topic'
          OR p.prosrc ~* '(forum_topics|forum_posts|topic_votes|topic_impressions|user_forum_sides|forum_post_likes|forum_topic_tags|forum_topic_visits|public_forum|\mtopic_id\M|\mforum_post_id\M)')
     AND p.oid <> ALL (ARRAY(SELECT pg_catalog.to_regprocedure(k) FROM pg_catalog.unnest(v_known) AS k
                              WHERE pg_catalog.to_regprocedure(k) IS NOT NULL));
  -- Any other schema: only a body that names a forum relation (Supabase's
  -- own realtime.topic() and its kin are named for realtime topics), never
  -- the system schemas, temporary ones or an extension's own functions.
  SELECT pg_catalog.array_cat(v_bad, pg_catalog.array_agg(p.oid::pg_catalog.regprocedure::text
                                                          ORDER BY p.oid::pg_catalog.regprocedure::text))
    INTO v_bad
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('public', 'private', 'pg_catalog', 'information_schema')
     AND n.nspname !~ '^pg_(temp|toast)'
     AND p.prosrc ~* '(forum_topics|forum_posts|topic_votes|topic_impressions|user_forum_sides|forum_post_likes|forum_topic_tags|forum_topic_visits|public_forum)'
     AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_depend AS e
                      WHERE e.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass
                        AND e.objid = p.oid AND e.deptype = 'e');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'forum_drop preflight: unexpected forum function(s) %; add them to the drop or the rewrite first', v_bad;
  END IF;

  -- (b) The bodies this wave was built from (before) or wrote (after); the
  -- kept notification helper's is both.
  FOR r IN SELECT * FROM (VALUES
      ('private.assert_can_post(uuid,text)',
       '920660396b7d4e331db2948838f98333', '3cf33d5a02460a23c6ed90160eadaf8e'),
      ('public.admin_confirm_content_removal(text,uuid)',
       'b50fef071e4ef2503f14b16376edb0ea', '86567c9277f9f36ac2377437e986db0d'),
      ('private.opinion_stamp_backfill()',
       '118a2ca9d86ef932e0342867d616ef5c', '936f500d8639e59da292ef061744d796'),
      ('private.create_poll_for_post(uuid,uuid,uuid,text[])',
       '6154f307c3afdb76c0249c2db2ec44f6', '332f6851a5edd7f409ed77fcf4a6a69a'),
      ('public.get_post_poll(uuid,uuid)',
       'dd3f4fc152767cd7b054c8324a46020e', 'b0f239e72b6a09681140d928b1a03cba'),
      ('private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid)',
       '3d57c8b5ca75d1edbe87192d5af837e1', '3d57c8b5ca75d1edbe87192d5af837e1')
    ) AS t(sig, before_md5, after_md5)
  LOOP
    SELECT pg_catalog.md5(p.prosrc) INTO v_md5
      FROM pg_catalog.pg_proc AS p WHERE p.oid = pg_catalog.to_regprocedure(r.sig);
    IF v_md5 IS NULL THEN
      RAISE EXCEPTION 'forum_drop preflight: % is missing', r.sig;
    END IF;
    IF v_md5 <> r.before_md5 AND v_md5 <> r.after_md5 THEN
      RAISE EXCEPTION 'forum_drop preflight: % is not the body this wave was built from (md5 %); rebuild migrations 4-5 from its live definition', r.sig, v_md5;
    END IF;
  END LOOP;

  -- (c) Nothing outside the forum relations depends on them or on their row
  -- and array types, but the three foreign keys migration 3 drops and the
  -- 29 functions migration 2 drops first; and nothing at all but those 29
  -- depends on the 29 (a view, a default, a trigger, a policy).
  v_rels := ARRAY(SELECT pg_catalog.to_regclass(x)::oid FROM pg_catalog.unnest(v_forum_relations) AS x
                   WHERE pg_catalog.to_regclass(x) IS NOT NULL);
  v_types := ARRAY(SELECT t.oid FROM pg_catalog.pg_type AS t WHERE t.typrelid = ANY (v_rels)
                   UNION ALL
                   SELECT t.typarray FROM pg_catalog.pg_type AS t
                    WHERE t.typrelid = ANY (v_rels) AND t.typarray <> 0);
  v_dropped_oids := ARRAY(SELECT pg_catalog.to_regprocedure(k)::oid FROM pg_catalog.unnest(v_dropped) AS k
                           WHERE pg_catalog.to_regprocedure(k) IS NOT NULL);
  SELECT pg_catalog.array_agg(DISTINCT x.what ORDER BY x.what) INTO v_bad
    FROM (
      SELECT CASE d.classid
               WHEN 'pg_catalog.pg_class'::pg_catalog.regclass THEN
                 (SELECT coalesce(i.indrelid, c.oid) FROM pg_catalog.pg_class AS c
                    LEFT JOIN pg_catalog.pg_index AS i ON i.indexrelid = c.oid WHERE c.oid = d.objid)
               WHEN 'pg_catalog.pg_constraint'::pg_catalog.regclass THEN
                 (SELECT c.conrelid FROM pg_catalog.pg_constraint AS c WHERE c.oid = d.objid)
               WHEN 'pg_catalog.pg_rewrite'::pg_catalog.regclass THEN
                 (SELECT w.ev_class FROM pg_catalog.pg_rewrite AS w WHERE w.oid = d.objid)
               WHEN 'pg_catalog.pg_trigger'::pg_catalog.regclass THEN
                 (SELECT t.tgrelid FROM pg_catalog.pg_trigger AS t WHERE t.oid = d.objid)
               WHEN 'pg_catalog.pg_policy'::pg_catalog.regclass THEN
                 (SELECT y.polrelid FROM pg_catalog.pg_policy AS y WHERE y.oid = d.objid)
               WHEN 'pg_catalog.pg_attrdef'::pg_catalog.regclass THEN
                 (SELECT a.adrelid FROM pg_catalog.pg_attrdef AS a WHERE a.oid = d.objid)
             END AS owner_rel,
             pg_catalog.pg_describe_object(d.classid, d.objid, d.objsubid) AS what,
             (d.classid = 'pg_catalog.pg_constraint'::pg_catalog.regclass
              AND (SELECT c.conname FROM pg_catalog.pg_constraint AS c WHERE c.oid = d.objid)
                  IN ('post_polls_topic_id_fkey', 'forum_reports_forum_post_id_fkey', 'forum_reports_topic_id_fkey')) AS expected_fk,
             (d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass) AS on_function
        FROM pg_catalog.pg_depend AS d
       WHERE ((d.refclassid = 'pg_catalog.pg_class'::pg_catalog.regclass AND d.refobjid = ANY (v_rels))
              OR (d.refclassid = 'pg_catalog.pg_type'::pg_catalog.regclass AND d.refobjid = ANY (v_types))
              -- Migration 2 drops the 29 before any forum table goes, so even
              -- a trigger on a forum table that calls one would stop it.
              OR (d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass AND d.refobjid = ANY (v_dropped_oids)))
         AND NOT (d.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass AND d.objid = ANY (v_dropped_oids))
         -- Normal dependencies only: auto ones (indexes, the table's own
         -- constraints, owned sequences, realtime publication membership)
         -- go with the table and never block a RESTRICT drop.
         AND d.deptype = 'n'
    ) AS x
   WHERE NOT x.expected_fk
     AND (x.on_function OR x.owner_rel IS NULL OR x.owner_rel <> ALL (v_rels));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'forum_drop preflight: % depend(s) on the forum schema; remove that dependency first', v_bad;
  END IF;

  -- (d) W2 holds, and the kept helper is where Opinions expects it.
  IF pg_catalog.to_regprocedure('public.forum_retirement_health()') IS NULL THEN
    RAISE EXCEPTION 'forum_drop preflight: Spec 3 W2 is not applied (no forum_retirement_health)';
  END IF;
  SELECT pg_catalog.array_agg(h.check_name || ': ' || h.detail) INTO v_bad
    FROM public.forum_retirement_health() AS h
   WHERE h.check_name IN ('forum_cron_unscheduled', 'opinions_shared_objects_present') AND NOT h.ok;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'forum_drop preflight: Spec 3 W2 does not hold: %', v_bad;
  END IF;
  -- Any cron job, by what it runs (a hand-made one W2's check cannot know).
  IF pg_catalog.to_regclass('cron.job') IS NOT NULL THEN
    SELECT pg_catalog.array_agg(coalesce(j.jobname, '<unnamed>') || ' (jobid ' || j.jobid || ')' ORDER BY j.jobid)
      INTO v_bad
      FROM cron.job AS j
     WHERE j.command ~* ('(forum_topics|forum_posts|topic_votes|topic_impressions|user_forum_sides|forum_post_likes|forum_topic_tags|forum_topic_visits|public_forum|'
                         || (SELECT pg_catalog.string_agg(pg_catalog.split_part(pg_catalog.split_part(k, '(', 1), '.', 2), '|')
                               FROM pg_catalog.unnest(v_dropped) AS k)
                         || ')');
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'forum_drop preflight: cron job(s) % name the forum schema; unschedule them first', v_bad;
    END IF;
  END IF;

  -- (e) Strikes (or a ban) only a removed forum post can stamp wait for the key.
  IF pg_catalog.to_regclass('public.forum_posts') IS NOT NULL THEN
    SELECT pg_catalog.count(*) INTO v_n
      FROM public.profiles AS p
     WHERE (p.confirmed_violation_count
              > coalesce((SELECT sum(s.strikes) FROM private.opinion_enforcement_stamps AS s
                           WHERE s.user_id = p.id), 0)
            -- a live ban no stamp covers (the backfill stamps it too)
            OR (p.banned_until > now()
                AND coalesce((SELECT max(s.ban_until) FROM private.opinion_enforcement_stamps AS s
                               WHERE s.user_id = p.id), '-infinity') < p.banned_until))
       AND EXISTS (SELECT 1 FROM public.forum_posts AS f WHERE f.user_id = p.id AND f.removed_at IS NOT NULL);
    IF v_n > 0 AND public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1') IS NULL THEN
      RAISE EXCEPTION 'forum_drop preflight: % account(s) with a removed forum post wait for their Opinions stamps, and dating_exclusion_key is not set; set it (Vault) and push again (migration 3 runs private.opinion_stamp_backfill() before forum_posts goes)', v_n;
    END IF;
  END IF;
END
$$;

DROP VIEW IF EXISTS public.public_forum_posts RESTRICT;
DROP VIEW IF EXISTS public.public_forum_topics RESTRICT;

COMMIT;
