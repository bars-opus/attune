-- Spec 3 (forum removal) W2, migration 1 of 4: stop every forum cron.
--
-- By name: 'activate-topics-sweep' and 'forum-quiet-check' (registered by
-- 20260907120000_register_scheduled_jobs.sql) and 'mark-quiet-forums'
-- (production only, registered by hand as jobid 3 and patched by the
-- operator script supabase/sql/patch_mark_quiet_forums_null_last_post.sql).
-- Then by command, so a hand-registered copy under another name goes too.
--
-- Idempotent: a second run finds nothing and does nothing. One DO block, so
-- it is atomic without its own BEGIN/COMMIT. No exception is swallowed: if
-- pg_cron refuses an unschedule, the push fails loudly.
DO $$
DECLARE
  v_name text;
  v_job record;
BEGIN
  FOREACH v_name IN ARRAY ARRAY[
    'activate-topics-sweep',
    'forum-quiet-check',
    'mark-quiet-forums'
  ] LOOP
    FOR v_job IN SELECT j.jobid, j.jobname FROM cron.job j WHERE j.jobname = v_name LOOP
      PERFORM cron.unschedule(v_job.jobid);
      RAISE NOTICE 'forum_retire_scheduled_jobs: unscheduled % (jobid %)',
        v_job.jobname, v_job.jobid;
    END LOOP;
  END LOOP;

  FOR v_job IN
    SELECT j.jobid, j.jobname FROM cron.job j
    WHERE j.command ~* '(activate-topics|forum-quiet-check|forum_topics|mark_quiet_topics|activate_pending_topics|expire_old_topics|notify_quiet_topic)'
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
    RAISE NOTICE 'forum_retire_scheduled_jobs: unscheduled % (jobid %) by its command',
      coalesce(v_job.jobname, '<unnamed>'), v_job.jobid;
  END LOOP;
END
$$;
