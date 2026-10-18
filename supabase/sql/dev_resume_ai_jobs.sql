-- DEV / MANUAL TESTING ONLY. Never a migration; never run against
-- production (Spec 8; plan review M7). Resumes the three AI jobs paused by
-- 20260931150000, exactly as the disabled resume file would; the Verdict
-- cron stays off. This replaces schedule_analyse_message.sql,
-- schedule_analyse_session.sql and schedule_generate_verdict.sql.
-- Re-run safely; undo with the pause migration's cron.unschedule calls.
DO $$
DECLARE
  v_job text;
BEGIN
  FOREACH v_job IN ARRAY ARRAY['analyse-message-backlog', 'analyse-session-sweep', 'compute-pulse-weekly']
  LOOP
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = v_job;
  END LOOP;
END;
$$;

SELECT cron.schedule(
  'analyse-message-backlog', '* * * * *',
  $$ SELECT public.invoke_edge_function('analyse-message'); $$
);

SELECT cron.schedule(
  'analyse-session-sweep', '7,37 * * * *',
  $$ SELECT public.invoke_edge_function('analyse-session'); $$
);

SELECT cron.schedule(
  'compute-pulse-weekly', '0 7 * * 0',
  $$ SELECT public.invoke_edge_function('compute-pulse'); $$
);
