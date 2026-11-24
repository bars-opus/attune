-- Spec 3 (forum removal) W3, migration 3 of 6: the forum rows in kept
-- tables, the three foreign keys into the forum tables, the forum push
-- index, then the 8 forum tables (Spec 3 §6.3 step 3; V6; R14). One
-- transaction. Irreversible: the owner backs up first (W3 Owner checklist).
--   (o)   Opinions stamps first (Spec 1 W9d): while forum_posts exists and
--         an account with a removed forum post holds strikes, or a live
--         ban, no stamp covers, private.opinion_stamp_backfill() (still its pre-W3 body,
--         which counts removed forum posts; migration 5 rewrites it) runs
--         now, or those strikes could never be stamped after the drop. It
--         refuses the migration if the backfill cannot run (-1: no
--         dating_exclusion_key; the preflight's (e) stops earlier);
--   (i)   topic polls (their options and votes cascade); opinion polls stay;
--   (ii)  reports that name only a forum post or topic; every report on an
--         opinion or a comment stays;
--   (iii) every queued, sent or cancelled push of the three retired types
--         (forum_topic_activated, forum_activity, forum_quiet); the two
--         Opinions moderation notices (forum_content_removed,
--         forum_posting_banned) are not these types and stay;
--   (iv)  every foreign key on a kept table that points into a forum table,
--         found in pg_constraint; exactly the three the preflight allows;
--   (v)   idx_scheduled_notifications_forum_activity;
--   (vi)  the tables, RESTRICT, children first.
-- Idempotent: (o) runs only while forum_posts exists, (i) only while
-- post_polls.topic_id exists (migration 4 drops it); everything else is IF
-- EXISTS or finds nothing.
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $$
DECLARE
  v_n bigint;
  r record;
BEGIN
  -- Nested: the inner query names forum_posts, so it runs only while it exists.
  IF pg_catalog.to_regclass('public.forum_posts') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.profiles AS p
                WHERE EXISTS (SELECT 1 FROM public.forum_posts AS f
                               WHERE f.user_id = p.id AND f.removed_at IS NOT NULL)
                  AND (p.confirmed_violation_count
                         > coalesce((SELECT sum(s.strikes) FROM private.opinion_enforcement_stamps AS s
                                      WHERE s.user_id = p.id), 0)
                       -- a live ban no stamp covers (the backfill stamps it too)
                       OR (p.banned_until > now()
                           AND coalesce((SELECT max(s.ban_until) FROM private.opinion_enforcement_stamps AS s
                                          WHERE s.user_id = p.id), '-infinity') < p.banned_until))) THEN
      v_n := private.opinion_stamp_backfill();
      IF v_n < 0 THEN
        RAISE EXCEPTION 'forum_drop_tables: opinion_stamp_backfill() returned -1 (dating_exclusion_key is not set); set it and push again, or strikes from removed forum posts are lost';
      END IF;
      RAISE NOTICE 'forum_drop_tables: % account(s) stamped before forum_posts goes', v_n;
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute
              WHERE attrelid = 'public.post_polls'::pg_catalog.regclass
                AND attname = 'topic_id' AND NOT attisdropped) THEN
    EXECUTE 'DELETE FROM public.post_polls WHERE topic_id IS NOT NULL';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'forum_drop_tables: % topic poll(s) deleted', v_n;
  END IF;

  DELETE FROM public.forum_reports WHERE opinion_id IS NULL AND comment_id IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE 'forum_drop_tables: % forum-only report(s) deleted', v_n;

  DELETE FROM public.scheduled_notifications
   WHERE metadata->>'type' IN ('forum_topic_activated', 'forum_activity', 'forum_quiet');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE 'forum_drop_tables: % retired forum push(es) deleted', v_n;

  FOR r IN
    SELECT c.conname, c.conrelid::pg_catalog.regclass AS on_table
      FROM pg_catalog.pg_constraint AS c
     WHERE c.contype = 'f'
       AND c.confrelid IN (SELECT pg_catalog.to_regclass(x) FROM pg_catalog.unnest(ARRAY[
             'public.forum_topics', 'public.topic_votes', 'public.topic_impressions',
             'public.forum_posts', 'public.forum_post_likes', 'public.user_forum_sides',
             'public.forum_topic_tags', 'public.forum_topic_visits']) AS x)
       AND c.conrelid NOT IN (SELECT pg_catalog.to_regclass(x) FROM pg_catalog.unnest(ARRAY[
             'public.forum_topics', 'public.topic_votes', 'public.topic_impressions',
             'public.forum_posts', 'public.forum_post_likes', 'public.user_forum_sides',
             'public.forum_topic_tags', 'public.forum_topic_visits']) AS x
             WHERE pg_catalog.to_regclass(x) IS NOT NULL)
  LOOP
    IF r.conname NOT IN ('post_polls_topic_id_fkey', 'forum_reports_forum_post_id_fkey',
                         'forum_reports_topic_id_fkey') THEN
      RAISE EXCEPTION 'forum_drop_tables: unexpected foreign key % on % into the forum schema', r.conname, r.on_table;
    END IF;
    EXECUTE pg_catalog.format('ALTER TABLE %s DROP CONSTRAINT %I', r.on_table, r.conname);
    RAISE NOTICE 'forum_drop_tables: dropped % on %', r.conname, r.on_table;
  END LOOP;
END
$$;

DROP INDEX IF EXISTS public.idx_scheduled_notifications_forum_activity;

DROP TABLE IF EXISTS public.forum_post_likes RESTRICT;
DROP TABLE IF EXISTS public.forum_topic_tags RESTRICT;
DROP TABLE IF EXISTS public.forum_topic_visits RESTRICT;
DROP TABLE IF EXISTS public.topic_votes RESTRICT;
DROP TABLE IF EXISTS public.topic_impressions RESTRICT;
DROP TABLE IF EXISTS public.user_forum_sides RESTRICT;
DROP TABLE IF EXISTS public.forum_posts RESTRICT;
DROP TABLE IF EXISTS public.forum_topics RESTRICT;

COMMIT;
