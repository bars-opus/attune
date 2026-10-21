-- supabase/migrations/20261019120110_chat_push_once_per_job.sql
--
-- Plan 1b final review M3, reachable once 20261019120100 revives the
-- stale-lease recovery: an overnight chat job folded into the 08:00 push
-- (scheduled_notifications_quiet_guard RETURN NULL, no row written) and
-- then re-run after 08:00 -- its worker killed after the fold and its lease
-- recovered, or reset by hand -- found no quiet window and no row carrying
-- its outbox_id, so scheduled_notifications_chat_outbox_idx let a second
-- banner through for a message the 08:00 push already covered.
--
-- Fix: the job itself records that the queue accepted its push.
-- message_notification_outbox.push_queued_at is stamped in the same
-- statement as the push insert, by a BEFORE INSERT trigger that runs
-- before the quiet guard. Once stamped, a later push for that job is:
--   * left to the unique index when the job's row exists (23505, which the
--     worker already reads as "already queued" -- unchanged behaviour);
--   * dropped (RETURN NULL) when no row exists: the push was folded into an
--     overnight one, so the message is already covered. enqueuePush then
--     resolves false and the worker finishes the job without a wake.
-- A failed insert rolls the stamp back with it, so a genuine retry still
-- queues. No edge-function change.
--
-- Why not "skip pushes for messages older than N hours": a job folded at
-- 07:58 and recovered at 08:05 is minutes old, so no N both catches it and
-- keeps a slow-but-real daytime retry. The stamp is exact.
--
-- Order matters: BEFORE triggers fire in name order and the quiet guard's
-- RETURN NULL skips every later one, so the name must sort before
-- scheduled_notifications_copy_guard / _quiet_guard
-- ('chat_job_once' < 'copy_guard' < 'quiet_guard';
-- chat_push_replay_contracts.sql check 8 proves it).
--
-- Rows whose outbox_id is not a chat outbox job's uuid (no such job) are
-- untouched: the unique index alone applies, as before.
--
-- Product note: a reaction outbox row is reused for a re-react (state back
-- to 'pending'); a re-react whose first push was folded overnight now sends
-- nothing, matching the 1b Task 5 ruling that a re-react does not push again.

ALTER TABLE public.message_notification_outbox
  ADD COLUMN IF NOT EXISTS push_queued_at timestamptz;

COMMENT ON COLUMN public.message_notification_outbox.push_queued_at IS
  'When the push queue first accepted this job''s push (a row written, or folded into an overnight push). Set by scheduled_notifications_chat_job_once; a later push for the job is not queued again.';

CREATE OR REPLACE FUNCTION public.scheduled_notifications_chat_job_once()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key text := NEW.metadata->>'outbox_id';
  v_job uuid;
BEGIN
  IF v_key IS NULL
     OR v_key !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RETURN NEW;
  END IF;
  v_job := v_key::uuid;

  -- First push for this job: stamp it (row-locks the job, so a concurrent
  -- insert for the same job waits here and then sees the stamp).
  UPDATE public.message_notification_outbox
     SET push_queued_at = now()
   WHERE id = v_job AND push_queued_at IS NULL;
  IF FOUND THEN RETURN NEW; END IF;

  -- Not a chat outbox job: nothing to remember.
  IF NOT EXISTS (SELECT 1 FROM public.message_notification_outbox WHERE id = v_job) THEN
    RETURN NEW;
  END IF;

  -- Already accepted and its row is there: the unique index answers.
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications s
             WHERE s.metadata ? 'outbox_id' AND s.metadata->>'outbox_id' = v_key) THEN
    RETURN NEW;
  END IF;

  -- Already accepted and folded into an overnight push: covered.
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS scheduled_notifications_chat_job_once ON public.scheduled_notifications;
CREATE TRIGGER scheduled_notifications_chat_job_once
  BEFORE INSERT ON public.scheduled_notifications
  FOR EACH ROW EXECUTE FUNCTION public.scheduled_notifications_chat_job_once();
