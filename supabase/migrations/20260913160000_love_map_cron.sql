-- Love Map's weekly refresh: opens three new prompts per active couple.
--
-- Monday 09:07. The :07 offset matches every other job here -- cron jobs on
-- the hour contend for the same worker slots.
--
-- Unscheduled first because cron.schedule errors on an existing jobname and
-- re-running a migration must stay safe.
DO $$
BEGIN
  PERFORM cron.unschedule('refresh-love-map-weekly');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

SELECT cron.schedule(
  'refresh-love-map-weekly',
  '7 9 * * 1',
  $$ SELECT public.invoke_edge_function('refresh-love-map'); $$
);
