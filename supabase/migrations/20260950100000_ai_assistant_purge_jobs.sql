-- AI Assistant Plan A, Task 8: scheduled purge jobs for expired
-- ai_assist_drafts rows and old ai_assistant_usage rows.
--
-- Each purge is its own SECURITY DEFINER, service-role-only-callable
-- function (testable directly via SQL, per the brief), then registered
-- as an hourly cron job following the exact idempotent
-- unschedule-then-schedule pattern established by
-- 20260907120000_register_scheduled_jobs.sql -- not the older
-- supabase/sql/schedule_*.sql hand-run-script pattern, which that
-- migration's own header explains was never provably executed against
-- the live project.
--
-- Cadence: hourly. The purge thresholds are 24 hours and 30 days --
-- nothing here is latency-sensitive the way the outbox workers in
-- 20260907120000 are (registered at */1), so a per-minute job would be
-- needless load for no user-visible benefit.

-- ---------------------------------------------------------------------
-- purge_expired_ai_assist_drafts: hard-deletes ai_assist_drafts rows
-- whose created_at is more than 24 hours old. This is a SEPARATE
-- threshold from expires_at (15 minutes, which only blocks sharing) --
-- a draft older than 15 minutes but younger than 24 hours is left
-- alone. Deleting the draft row never touches a message it was already
-- shared into: shared_message_id's FK is ON DELETE SET NULL (not
-- CASCADE), so the shared messages row survives untouched.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.purge_expired_ai_assist_drafts()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.ai_assist_drafts
  WHERE created_at < now() - interval '24 hours';
END;
$$;

-- Service-role only, matching insert_ai_assist_draft's precedent in
-- 20260950080000: BYPASSRLS grants nothing at the function-privilege
-- level, so an explicit GRANT EXECUTE TO service_role is required for
-- the scheduled job's edge-function-via-service-role call path to reach
-- this function at all, and no authenticated caller should ever be able
-- to trigger a bulk purge directly.
REVOKE ALL ON FUNCTION public.purge_expired_ai_assist_drafts()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_expired_ai_assist_drafts()
  TO service_role;

-- ---------------------------------------------------------------------
-- purge_old_ai_assistant_usage: hard-deletes ai_assistant_usage rows
-- older than 30 days. This ledger only needs to cover the rolling 24h
-- quota window (share_quota_reserve, Task 4); 30 days is a generous
-- retention margin for support/audit lookback without keeping the table
-- growing unbounded forever.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.purge_old_ai_assistant_usage()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.ai_assistant_usage
  WHERE created_at < now() - interval '30 days';
END;
$$;

REVOKE ALL ON FUNCTION public.purge_old_ai_assistant_usage()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_ai_assistant_usage()
  TO service_role;

-- ---------------------------------------------------------------------
-- Register both jobs. Unscheduled first (idempotent: cron.schedule with
-- an existing jobname errors, and re-running this migration must be
-- safe), named explicitly rather than truncating cron.job so unrelated
-- jobs are left untouched -- same style as 20260907120000.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_job text;
BEGIN
  FOREACH v_job IN ARRAY ARRAY[
    'purge-ai-assist-drafts',
    'purge-ai-assistant-usage'
  ]
  LOOP
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = v_job;
  END LOOP;
END;
$$;

-- Pure-SQL maintenance, same category as generate-reminder-notifications
-- in 20260907120000: calls the Postgres function directly rather than
-- an edge function, so no HTTP hop or service-role key is needed for the
-- cron worker itself. (The GRANT EXECUTE ... TO service_role above still
-- matters independently: it is what would let an edge-function-fronted
-- HTTP path call these directly too, if that path is ever added instead
-- of/alongside the direct cron.schedule call used here.)
SELECT cron.schedule(
  'purge-ai-assist-drafts',
  '7 * * * *',
  $$ SELECT public.purge_expired_ai_assist_drafts(); $$
);

SELECT cron.schedule(
  'purge-ai-assistant-usage',
  '37 * * * *',
  $$ SELECT public.purge_old_ai_assistant_usage(); $$
);
