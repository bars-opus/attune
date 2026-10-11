-- Task 4 of the merge-blockers plan: stop ONE orphaned request row from
-- wedging lease reconciliation platform-wide.
-- Spec §6.2, §8.2.2.
--
-- ======================================================================
-- MIGRATION PROVENANCE
--
--   public.reconcile_ai_session_leases()
--     20260953060000  Task 6, original            SUPERSEDED
--     20260953060100  Task 6 fix round 1          SUPERSEDED
--     20260953160000  THIS FILE                   WINS
--
-- Nothing else in this file is redefined. claim_ai_session_dispatch is
-- NOT touched here -- 20260953060100 remains its winning definition,
-- and ai_session_read_authorization_contracts.sql Contract 9 still
-- asserts that body's claim_ai_assistant_provider_start marker. This
-- file adds an EIGHTH marker to Contract 9, for the function below.
-- ======================================================================
--
-- THE DEFECT, both halves measured on a fresh build of this branch
-- before the fix:
--
-- HALF 1 -- no per-row handler, so one bad row rolls back every GOOD
-- row in the same run. The loop called
-- release_ai_assistant_quota_reservation directly in the function body.
-- That RPC raises 'Reservation not found for this actor' when no
-- ai_assistant_usage row exists for (request_id, actor_id). An
-- uncaught RAISE in a plpgsql body aborts the WHOLE transaction, and
-- pg_cron calls this function as one transaction per run. Measured:
-- seeded one orphaned request and one healthy request, both with
-- expired leases, in one run. The run raised, and the healthy row was
-- left at state='reserved' with its usage row still outcome='reserved'
-- -- byte-identical to its BEFORE state. It was resolved and then
-- rolled back.
--
-- The consequence is not "one row is skipped." pg_cron runs this every
-- minute (jobname 'reconcile-ai-session-leases', schedule '* * * * *',
-- verified in cron.job). The scan predicate
-- (state IN ('reserved','started') AND lease_deadline < now()) is NOT
-- time-bounded and has no LIMIT, so once an orphan matches it, it
-- matches on EVERY subsequent run, forever. Every run aborts at that
-- row. So a single orphan permanently starves lease reconciliation for
-- EVERY user on the platform: no expired lease is ever marked 'failed'
-- again (so no session can admit a fresh attempt, since admit's
-- single-outstanding-request gate sees a stuck 'reserved' row) and no
-- never-dispatched quota reservation is ever released again.
--
-- HALF 2 -- it is reachable by SHIPPED SCHEDULED CODE ALONE, with no
-- manual deletion and no operator error. Plan A registers
-- purge_old_ai_assistant_usage() in cron.job (jobname
-- 'purge-ai-assistant-usage', schedule '37 * * * *', per
-- 20260950100000), and that function hard-deletes ai_assistant_usage
-- rows older than 30 days. Nothing prunes ai_session_requests on any
-- schedule. There is no foreign key in EITHER direction between the
-- two tables -- verified by pg_constraint, 0 rows both ways, because
-- ai_assistant_usage is Plan A's ledger shared with the 'assist' and
-- 'understand' modes and is keyed only on request_id. So the purger is
-- free to delete the usage row out from under a surviving request row,
-- and no referential action notices.
--
-- Reproduced WITHOUT a manual DELETE: aged a usage row to 31 days,
-- called the REAL registered purger, and got
-- `request rows=1 usage rows=0` -- a wedging orphan, manufactured
-- entirely by two shipped cron jobs interacting. That is a cross-plan
-- cron interaction, which is why no per-task review saw it: each job is
-- correct in isolation.
--
-- How a request row survives 30 days in a scanned state at all: a
-- 'started' request whose worker died is marked 'failed' by this very
-- reconciler, so the common case self-heals within a minute. The row
-- that survives is one this reconciler never got to -- which, once the
-- first orphan appears, is EVERY row. Half 2 creates the first orphan
-- and Half 1 makes it permanent; together they ratchet.
--
-- ======================================================================
-- THE FIX: per-row fault isolation, the same shape Task 11's two sweeps
-- (purge_expired_ai_sessions and reconcile_ai_session_quota_residue in
-- 20260953110000) already use. That is not a coincidence to imitate --
-- it is precisely WHY neither of those two can wedge this way, and this
-- function was the one unattended per-minute sweep in the schema
-- lacking it.
--
-- Each row's work now happens inside its own BEGIN ... EXCEPTION WHEN
-- OTHERS THEN RAISE WARNING ... END block. The mechanical property this
-- depends on, same as Task 11's note: a plpgsql EXCEPTION block wraps
-- its body in a SUBTRANSACTION, so a failed row rolls back to the start
-- of ITS OWN iteration and cannot leave a half-reconciled request
-- behind, while every row already committed in this run survives.
--
-- The handler is WHEN OTHERS rather than a targeted CONTINUE on the
-- missing-usage case, deliberately. release_ai_assistant_quota_
-- reservation has THREE raise sites ('Not authenticated',
-- 'Reservation not found for this actor', 'Cannot release a reservation
-- whose provider call has started'), and the whole point of this task
-- is that an UNANTICIPATED per-row failure must not be able to starve
-- the platform. A handler that enumerated today's known raises would
-- re-open the identical hole for tomorrow's. It is still narrow in the
-- sense that matters: it re-raises nothing but logs a WARNING naming
-- the request, its state and SQLERRM, so a systematic failure is
-- visible in the cron log rather than silent.
--
-- ======================================================================
-- THE JUDGMENT CALL: an orphaned row is RESOLVED to a terminal state,
-- not skipped forever. Recording the reasoning, because the brief is
-- right that this is a real decision and not an obvious one.
--
-- Skipping forever would be a leak of a different kind. The orphan
-- stays at state='reserved' matching the scan predicate on every run
-- for the life of the database, which (a) accumulates one WARNING per
-- orphan per minute in the cron log -- 1,440/day/orphan, which buries
-- the signal the WARNING exists to provide, and (b) leaves the request
-- row permanently non-terminal, so admit_ai_session_generation's
-- single-outstanding-request gate keeps refusing new attempts on that
-- session forever. The user-visible symptom of Half 1 would survive the
-- fix for that one session.
--
-- Resolving it is SAFE here, and the reason is specific rather than
-- general: for an orphaned row there is no quota accounting left to
-- touch. reserve_ai_assistant_quota counts rows with
-- `created_at >= now() - interval '24 hours'` (verified in the live
-- body), while purge_old_ai_assistant_usage deletes at 30 days. So by
-- the time the purger can orphan a row, that row has been outside the
-- rolling quota window for 29 days. There is no reservation to release,
-- nothing to refund, and nothing that could double-refund: the ledger
-- row the accounting would have operated on does not exist. Marking the
-- request 'failed' touches ONLY this plan's own session bookkeeping.
--
-- So the ordering below is load-bearing: the state UPDATE comes FIRST,
-- then the release attempt. If the release raises, the subtransaction
-- rolls back the UPDATE too -- which is correct for a row whose usage
-- row exists but whose release genuinely failed (quota accounting is
-- unresolved, so the row must stay scannable and be retried). The
-- missing-usage case is therefore handled as its own explicit branch
-- ABOVE the release, where it is provably safe to commit the terminal
-- state: that branch skips the release entirely rather than catching
-- its raise, so the UPDATE commits. The EXCEPTION block remains as the
-- backstop for everything else, including the two other raise sites and
-- anything unanticipated.
--
-- This is the narrowest resolution available. It does NOT prune the
-- request row -- deciding ai_session_requests retention is Plan A/B
-- retention policy, not a fault-isolation fix, and a terminal row is
-- already harmless (it leaves the scan predicate, stops the WARNING
-- spam, and unblocks the session's admit gate). A future pruner can
-- remove terminal rows on its own schedule; it no longer has a
-- correctness obligation to, which is the point.
--
-- ======================================================================
-- LOCK ORDER IS UNCHANGED. The documented order is relationship
-- advisory lock -> quota advisory lock (inside reserve_ai_assistant_
-- quota) -> session row FOR UPDATE -> request row. This function takes
-- the request row only -- a valid PREFIX-free single element it has
-- always taken, via the FOR UPDATE on its scan -- and this file does
-- not add, remove, reorder or re-key a single lock. The FOR UPDATE
-- stays on the same scan over the same predicate. The structural sweep
-- for functions holding two session row-classes without an advisory
-- lock must still return zero rows, and does: this function still
-- touches exactly ONE row-class (ai_session_requests).
--
-- Adding the per-row subtransaction does not widen any lock's hold: row
-- locks taken by the outer FOR UPDATE are held by the OUTER
-- transaction for its whole duration either way, and a subtransaction
-- rollback does not release them. Nothing here changes how long any
-- lock is held or in what order.
CREATE OR REPLACE FUNCTION public.reconcile_ai_session_leases()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.ai_session_requests;
  v_count int := 0;
BEGIN
  FOR v_row IN
    SELECT * FROM public.ai_session_requests
    WHERE state IN ('reserved', 'started') AND lease_deadline < now()
    FOR UPDATE
  LOOP
    -- PER-ROW FAULT ISOLATION (Task 4). One row's failure must never
    -- roll back another row's successful reconciliation, because this
    -- runs unattended every minute and the scan is unbounded -- see the
    -- header. Same shape as purge_expired_ai_sessions and
    -- reconcile_ai_session_quota_residue in 20260953110000.
    BEGIN
      UPDATE public.ai_session_requests
      SET state = 'failed', terminal_code = 'LEASE_EXPIRED'
      WHERE id = v_row.id;

      IF v_row.state = 'reserved' THEN
        -- Never dispatched: no provider-start marker was ever set for
        -- this request_id, so it is safe to release the quota
        -- reservation exactly once via Plan A's release RPC.
        --
        -- ORPHAN BRANCH (Task 4): unless the ai_assistant_usage row is
        -- GONE. Plan A's registered purge_old_ai_assistant_usage()
        -- hard-deletes usage rows at 30 days and nothing prunes
        -- ai_session_requests, with no FK in either direction, so this
        -- is reachable by shipped cron alone. Releasing is then both
        -- impossible and unnecessary: the release RPC would raise
        -- 'Reservation not found for this actor', and there is no quota
        -- to release anyway -- reserve_ai_assistant_quota's rolling
        -- window is 24 hours, so a row the 30-day purger could delete
        -- left that window 29 days ago.
        --
        -- Handled as an explicit branch rather than by catching the
        -- raise, so the terminal-state UPDATE above COMMITS for this
        -- row. Catching it instead would roll the UPDATE back and leave
        -- the row matching the scan predicate forever: one WARNING per
        -- minute per orphan, and the session's admit gate blocked for
        -- good. See the header's judgment-call note.
        IF EXISTS (
          SELECT 1 FROM public.ai_assistant_usage
          WHERE request_id = v_row.id AND user_id = v_row.actor_id
        ) THEN
          PERFORM public.release_ai_assistant_quota_reservation(v_row.actor_id, v_row.id);
        ELSE
          RAISE WARNING
            'reconcile_ai_session_leases: request % has no ai_assistant_usage row for actor % -- resolved to failed/LEASE_EXPIRED with no quota release (orphaned ledger row, expected after Plan A''s 30-day purge_old_ai_assistant_usage)',
            v_row.id, v_row.actor_id;
        END IF;
      END IF;
      -- A request already 'started' has had claim_ai_session_dispatch's
      -- call to claim_ai_assistant_provider_start set the REAL,
      -- write-once ai_assistant_usage.provider_started_at marker for it
      -- (20260953060100: previously this marker was never actually
      -- written by any code path). That marker genuinely makes this
      -- reservation's quota consumption permanent --
      -- release_ai_assistant_quota_reservation's own guard
      -- (provider_started_at IS NOT NULL AND outcome = 'reserved') will
      -- correctly RAISE if anything ever tries to release it. So
      -- reconciliation here only marks the SESSION's own bookkeeping
      -- 'failed' (so a new attempt can be admitted) and deliberately
      -- does not touch the now-permanent quota consumption.
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      -- Backstop for everything the explicit branch above does not
      -- anticipate, including release_ai_assistant_quota_reservation's
      -- other two raise sites. Re-raises nothing, but names the request
      -- and SQLERRM so a SYSTEMATIC failure is loud in the cron log
      -- rather than silent. This row's partial work is rolled back to
      -- the start of its own iteration (plpgsql EXCEPTION blocks are
      -- subtransactions), so it stays scannable and is retried next
      -- run, while every other row in this run survives.
      RAISE WARNING
        'reconcile_ai_session_leases: request % (state %) could not be reconciled (%) -- skipped, will retry next run',
        v_row.id, v_row.state, SQLERRM;
    END;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_ai_session_leases()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_ai_session_leases()
  TO service_role;
