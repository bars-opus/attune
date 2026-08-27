-- Register every scheduled job as a deployed artifact.
--
-- supabase/sql/schedule_*.sql defines 16 cron jobs, but those are
-- operator-run scripts: nothing proves they were ever executed against the
-- live project, and in fact only two jobs existed there
-- ('analyse-session-sweep', registered by 20260830120000, and
-- 'expire_paint_ball'). Everything else — pulse computation, verdict
-- generation, notification dispatch, the chat media/safety/notification
-- workers, forum and dating maintenance — had a function but no scheduler,
-- so it only ever ran if a user action happened to trigger it. §7's
-- "Weekly, every Sunday, cron runs at :07" and §8.5's monthly verdict were
-- simply not happening.
--
-- 20260830120000 made that exact argument for analyse-session and moved it
-- into a migration. This does the same for the remaining jobs, so the
-- schedule is reviewable, versioned, and deployed with the code rather
-- than depending on someone having pasted a script into the SQL editor.
--
-- Every job is unscheduled first: cron.schedule with an existing jobname
-- errors, and re-running a migration must be safe.

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Idempotency: drop any prior registration of the jobs below (whether from
-- a hand-run script or an earlier run of this migration) before recreating
-- them. Named explicitly rather than truncating cron.job, so unrelated
-- jobs registered elsewhere ('analyse-session-sweep', 'expire_paint_ball')
-- are left untouched.
DO $$
DECLARE
  v_job text;
BEGIN
  FOREACH v_job IN ARRAY ARRAY[
    'compute-pulse-weekly',
    'generate-verdict-monthly',
    'process-scheduled-notifications',
    'process-chat-notification-outbox',
    'process-chat-safety-outbox',
    'process-chat-media',
    'recover-stale-chat-workers',
    'cleanup-expired-chat-media',
    'analyse-message-backlog',
    'activate-topics-sweep',
    'evaluate-ask2-eligibility-sweep',
    'forum-quiet-check',
    'expire-thirty-six-chapters',
    'generate-reminder-notifications',
    'expire-dating-introductions',
    'revalidate-dating-lifecycle-gates'
  ]
  LOOP
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = v_job;
  END LOOP;
END;
$$;

-- Posts to an edge function with service-role credentials.
--
-- Factored out because the same 12-line net.http_post block was repeated in
-- every one of the 14 scripts, with drift already visible between copies
-- (seven omitted the 'Bearer ' prefix, and only some sent an apikey
-- header). One definition means one place to fix.
CREATE OR REPLACE FUNCTION public.invoke_edge_function(p_function text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM net.http_post(
    url := current_setting('app.settings.supabase_url')
           || '/functions/v1/' || p_function,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      -- 'Bearer ' prefix included: the gateway accepts a raw key today,
      -- but the prefix is what every HTTP client and the edge runtime's
      -- own requireServiceRole() expect, and the working
      -- analyse-session-sweep job already sends it.
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'apikey', current_setting('app.settings.service_role_key')
    ),
    body := '{}'::jsonb
  );
END;
$$;

REVOKE ALL ON FUNCTION public.invoke_edge_function(text) FROM PUBLIC;

-- ---------------------------------------------------------------------
-- Core intelligence pipeline
-- ---------------------------------------------------------------------

-- §7: "Weekly, every Sunday. Cron runs at :07 offset." Sunday is dow 0.
-- Without this, pulse_scores only ever changed when a client explicitly
-- asked for a recompute.
SELECT cron.schedule(
  'compute-pulse-weekly',
  '7 0 * * 0',
  $$ SELECT public.invoke_edge_function('compute-pulse'); $$
);

-- §8.5 monthly verdict, 00:07 on the 1st. verdict_service.dart's comment
-- ("the persisted job remains available for the scheduled worker") assumed
-- this existed; it did not, so an un-opened verdict was never generated.
SELECT cron.schedule(
  'generate-verdict-monthly',
  '7 0 1 * *',
  $$ SELECT public.invoke_edge_function('generate-verdict'); $$
);

-- Layer 1 message analysis backlog drain.
SELECT cron.schedule(
  'analyse-message-backlog',
  '* * * * *',
  $$ SELECT public.invoke_edge_function('analyse-message'); $$
);

-- ---------------------------------------------------------------------
-- Delivery workers
--
-- Every-minute cadence: these drain outbox tables, so latency here is
-- user-visible (a safety notification or push that arrives an hour late
-- has largely missed its purpose). Each function is a no-op when its
-- outbox is empty.
-- ---------------------------------------------------------------------

SELECT cron.schedule(
  'process-scheduled-notifications',
  '* * * * *',
  $$ SELECT public.invoke_edge_function('process-scheduled-notifications'); $$
);

SELECT cron.schedule(
  'process-chat-notification-outbox',
  '* * * * *',
  $$ SELECT public.invoke_edge_function('process-chat-notification-outbox'); $$
);

-- §8.7 safety notifications. The highest-priority worker in this file:
-- until now nothing drained the safety outbox on a schedule.
SELECT cron.schedule(
  'process-chat-safety-outbox',
  '* * * * *',
  $$ SELECT public.invoke_edge_function('process-chat-safety-outbox'); $$
);

SELECT cron.schedule(
  'process-chat-media',
  '* * * * *',
  $$ SELECT public.invoke_edge_function('process-chat-media'); $$
);

-- Media worker maintenance, preserved from
-- supabase/sql/schedule_process_chat_media.sql: the same function also
-- recovers rows stranded by a crashed worker and clears expired media.
SELECT cron.schedule(
  'recover-stale-chat-workers',
  '*/5 * * * *',
  $$ SELECT public.invoke_edge_function('process-chat-media'); $$
);

SELECT cron.schedule(
  'cleanup-expired-chat-media',
  '17 * * * *',
  $$ SELECT public.invoke_edge_function('process-chat-media'); $$
);

-- ---------------------------------------------------------------------
-- Feature maintenance
-- ---------------------------------------------------------------------

SELECT cron.schedule(
  'activate-topics-sweep',
  '23 * * * *',
  $$ SELECT public.invoke_edge_function('activate-topics'); $$
);

SELECT cron.schedule(
  'evaluate-ask2-eligibility-sweep',
  '17 * * * *',
  $$ SELECT public.invoke_edge_function('evaluate-ask2-eligibility'); $$
);

SELECT cron.schedule(
  'forum-quiet-check',
  '7 */2 * * *',
  $$ SELECT public.invoke_edge_function('forum-quiet-check'); $$
);

SELECT cron.schedule(
  'expire-thirty-six-chapters',
  '0 * * * *',
  $$ SELECT public.invoke_edge_function('expire-thirty-six-chapters'); $$
);

-- ---------------------------------------------------------------------
-- Pure-SQL maintenance
--
-- These call Postgres functions directly rather than an edge function, so
-- they need no HTTP hop and no service-role key.
-- ---------------------------------------------------------------------

SELECT cron.schedule(
  'generate-reminder-notifications',
  '0 7 * * *',
  $$ SELECT public.generate_reminder_notifications(); $$
);

-- Dating maintenance stays scheduled even though the dating_* feature
-- flags are off: these functions EXPIRE and REVALIDATE state. If dating is
-- ever enabled, having had the reapers running means there is no backlog
-- of stale introductions to work through, and while it is off they are
-- no-ops over an empty table.
SELECT cron.schedule(
  'expire-dating-introductions',
  '17 * * * *',
  $$ SELECT public.expire_dating_introductions(); $$
);

SELECT cron.schedule(
  'revalidate-dating-lifecycle-gates',
  '*/15 * * * *',
  $$ SELECT public.enforce_dating_lifecycle_gates(); $$
);
