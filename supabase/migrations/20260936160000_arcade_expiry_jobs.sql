-- Schedule the Arcade games' expiry sweeps.
--
-- Word Hunt needs one, and finding that out turned up that SNAKES NEVER
-- GOT ONE EITHER. expire_snakes_sessions() was written, granted to
-- service_role and then never scheduled, so every abandoned board stayed
-- 'active' forever. The visible consequence is not tidiness: one live
-- session per couple is the lobby's rule, so a game somebody walked away
-- from silently blocks every future game between those two people.
--
-- Word Hunt's sweep does one thing more than Snakes': it closes the
-- in-progress ATTEMPTS underneath an expiring session as well as the
-- session itself. An attempt left running under a dead session is
-- neither playable nor finished, and the reveal would never open.
--
-- Cadence is hourly at an offset minute, matching the other reapers.
-- Neither sweep is latency-sensitive -- the 48h/24h thresholds dwarf an
-- hour -- and every game RPC also expires lazily on the way past, so a
-- player who opens a stale game sees the finished state immediately
-- rather than whenever the job next runs. Cron is the backstop for the
-- games nobody opens again.
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
DECLARE
  v_job text;
BEGIN
  FOREACH v_job IN ARRAY ARRAY[
    'expire-snakes-sessions',
    'expire-word-hunt-sessions'
  ]
  LOOP
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = v_job;
  END LOOP;
END;
$$;

SELECT cron.schedule(
  'expire-snakes-sessions',
  '23 * * * *',
  $$ SELECT public.expire_snakes_sessions(); $$
);

SELECT cron.schedule(
  'expire-word-hunt-sessions',
  '27 * * * *',
  $$ SELECT public.expire_word_hunt_sessions(); $$
);
