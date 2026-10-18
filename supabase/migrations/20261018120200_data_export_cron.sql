-- Spec 3c: run the export worker every 2 minutes, but only when a job is
-- waiting (queued, or left building by a crashed run), so an idle day costs
-- no function calls; up to four workers at once (re-review I5).
DO $$
BEGIN
  PERFORM cron.unschedule('build-data-exports');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

SELECT cron.schedule(
  'build-data-exports',
  '*/2 * * * *',
  $$
  -- Through the vault-backed helper (20260931120000), never the retired
  -- database settings, which the hosted project cannot set (sync audit C-1).
  SELECT public.invoke_edge_function('build-data-exports')
  FROM generate_series(1, (
    SELECT least(4, count(*))::int FROM public.data_export_jobs j
    WHERE j.status = 'queued'
       OR (j.status = 'building' AND j.claimed_at < now() - interval '15 minutes')
  ));
  $$
);
