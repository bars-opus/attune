-- Operational visibility for the scheduled jobs registered in
-- 20260907120000.
--
-- Those jobs were previously defined only as hand-run scripts, and the
-- reason that went unnoticed for so long is that there was no way to ask
-- the system what it believes it is running: cron.job and
-- cron.job_run_details live in the cron schema, which is not exposed
-- through PostgREST and is unreadable by anon/authenticated. A silently
-- unregistered job and a silently failing one look identical from the
-- outside — both are just "nothing happened".
--
-- This adds a service-role-only view of both, so a deploy can be verified
-- and a broken schedule can be seen rather than inferred from missing
-- data. Checklist 4.9/4.12: every failure mode needs to be observable.

CREATE OR REPLACE FUNCTION public.scheduled_jobs_health()
RETURNS TABLE (
  jobname text,
  schedule text,
  active boolean,
  last_status text,
  last_run_started_at timestamptz,
  last_run_message text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, cron
AS $$
  SELECT
    j.jobname::text,
    j.schedule::text,
    j.active,
    r.status::text,
    r.start_time,
    -- Truncated: return_message can contain a full error body, and this is
    -- an operational read, not a log sink (§10 / checklist 4.4).
    left(r.return_message, 200)::text
  FROM cron.job j
  LEFT JOIN LATERAL (
    SELECT status, start_time, return_message
    FROM cron.job_run_details d
    WHERE d.jobid = j.jobid
    ORDER BY d.start_time DESC
    LIMIT 1
  ) r ON true
  ORDER BY j.jobname;
$$;

-- Service-role only. The schedule reveals the system's internal cadence
-- and the messages can carry failure detail, neither of which belongs to
-- an end user.
REVOKE ALL ON FUNCTION public.scheduled_jobs_health() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scheduled_jobs_health() TO service_role;
