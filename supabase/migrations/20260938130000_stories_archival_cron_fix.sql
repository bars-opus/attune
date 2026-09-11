-- The story archival cron invokes through app_setting(), like every
-- other scheduled job.
--
-- 20260938090000 wrote its own invoke_story_archival_worker() that read
-- `current_setting('app.settings.supabase_url')` directly. That is the
-- RETIRED pattern: on a managed Supabase project those GUCs are unset,
-- so the function took its `IF ... IS NULL THEN RETURN` branch and did
-- nothing, forever, silently. The archival job would simply never have
-- run in production.
--
-- settings_accessor_test.sql exists precisely to catch this ("a future
-- migration that copies the old pattern from an existing function would
-- reintroduce a silent no-op") and it did catch it.
--
-- public.invoke_edge_function(p_function text) already does this
-- correctly -- it reads through public.app_setting(), which tries Vault
-- first, the only store writable on a managed project. Every other cron
-- in this repo goes through it: compute-pulse, generate-verdict,
-- refresh-love-map. Stories has no reason to be different, so the
-- bespoke function goes away rather than being patched.
SELECT cron.unschedule('invoke-story-archival')
 WHERE EXISTS (
   SELECT 1 FROM cron.job WHERE jobname = 'invoke-story-archival'
 );

DROP FUNCTION IF EXISTS public.invoke_story_archival_worker();

SELECT cron.schedule(
  'invoke-story-archival',
  '20 * * * *',
  $$ SELECT public.invoke_edge_function('process-story-archival'); $$
);
