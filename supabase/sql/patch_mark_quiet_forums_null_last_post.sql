-- supabase/sql/patch_mark_quiet_forums_null_last_post.sql
-- Run once in the Supabase SQL editor.
--
-- Fixes a gap in the pre-existing `mark-quiet-forums` cron job (jobid 3,
-- daily at 1am), discovered while wiring FORUM.md §10 notification #6. That
-- job has no migration or source file anywhere in this repo -- it was
-- registered directly against the database. Its command is:
--
--   UPDATE forum_topics SET status = 'quiet'
--   WHERE status = 'active'
--     AND last_post_at < NOW() - INTERVAL '7 days'
--     AND last_post_at IS NOT NULL;
--
-- The `last_post_at IS NOT NULL` guard means a topic that activated but never
-- received a single post can NEVER go quiet -- last_post_at stays NULL
-- forever, so that row never satisfies the WHERE clause. This patch replaces
-- last_post_at with COALESCE(last_post_at, activated_at), matching the fix
-- already written (but deliberately not scheduled) in
-- public.mark_quiet_topics() -- see
-- supabase/migrations/20260727130000_forum_activity_notifications.sql.
--
-- cron.schedule() with an existing job name updates that job in place; it
-- does not create a duplicate. Interval and time of day are unchanged.

SELECT cron.schedule(
  'mark-quiet-forums',
  '0 1 * * *',
  $$
  UPDATE forum_topics
  SET status = 'quiet'
  WHERE status = 'active'
    AND COALESCE(last_post_at, activated_at) < NOW() - INTERVAL '7 days';
  $$
);

-- Verify: SELECT jobid, jobname, command FROM cron.job WHERE jobname = 'mark-quiet-forums';
