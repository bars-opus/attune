-- Fix round 1 for Task 6 (claim_ai_session_dispatch / reconcile_ai_session_leases).
-- Spec §6.2, §8.2.2.
--
-- Review finding: the original claim_ai_session_dispatch (see
-- 20260953060000_ai_session_dispatch_claim_rpc.sql) only set the
-- SESSION-local ai_session_requests.provider_started_at. It never
-- called Plan A's claim_ai_assistant_provider_start, so
-- ai_assistant_usage.provider_started_at -- the write-once marker that
-- release_ai_assistant_quota_reservation checks before refusing to
-- release a reservation, and that makes a reservation's quota
-- consumption permanent regardless of its later outcome -- was never
-- set for ANY session request. reconcile_ai_session_leases's own
-- comment described that permanence as already real; it was aspirational.
--
-- Fix: after successfully claiming the session-local row (state
-- 'reserved' -> 'started'), call claim_ai_assistant_provider_start
-- using the actor_id already stored on the matched ai_session_requests
-- row (the RPC's own signature is unchanged -- Plan C calls it with
-- only (worker_token, request_id) -- so actor_id is read from the row,
-- not added as a new parameter). Both writes happen in the same
-- transaction as this function body, so a later failure in the same
-- transaction rolls back the session-local state and the ledger marker
-- together.
--
-- Why this call cannot legitimately raise here: claim_ai_assistant_
-- provider_start raises only if (a) no ai_assistant_usage row exists
-- for (request_id, user_id=actor_id), or (b) that row's outcome is not
-- 'reserved'. Task 5's admit_ai_session_generation reserves quota via
-- reserve_ai_assistant_quota(p_actor_id, p_request_id, ...) with this
-- exact request_id and actor_id in the SAME admission transaction that
-- inserts the ai_session_requests row -- so by the time a claim here
-- matches state = 'reserved', the ai_assistant_usage row is guaranteed
-- to exist for that (request_id, actor_id) with outcome = 'reserved'
-- and provider_started_at IS NULL. Nothing transitions that usage row
-- to a terminal outcome while ai_session_requests.state is still
-- 'reserved' (release_ai_assistant_quota_reservation only runs from
-- reconcile_ai_session_leases's 'reserved' branch, which is mutually
-- exclusive with a dispatch claim succeeding, since claiming atomically
-- moves state out of 'reserved' first). A double-claim (already-set
-- provider_started_at) can't reach this call either, since the
-- session-local UPDATE's own WHERE state = 'reserved' guard already
-- fences a second claim before this call would run.
CREATE OR REPLACE FUNCTION public.claim_ai_session_dispatch(
  p_worker_token uuid, p_request_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_claimed boolean;
  v_actor_id uuid;
BEGIN
  UPDATE public.ai_session_requests
  SET state = 'started', provider_started_at = now()
  WHERE id = p_request_id AND worker_token = p_worker_token
    AND state = 'reserved' AND lease_deadline > now()
  RETURNING actor_id INTO v_actor_id;

  v_claimed := FOUND;

  IF v_claimed THEN
    PERFORM public.claim_ai_assistant_provider_start(v_actor_id, p_request_id);
  END IF;

  RETURN v_claimed;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_ai_session_dispatch(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_ai_session_dispatch(uuid, uuid)
  TO service_role;

-- Comment-only fix: describe the NOW-real guarantee. No logic change --
-- the 'reserved' branch below still calls release_ai_assistant_quota_
-- reservation exactly as before; that call was always correct, it's
-- the 'started' branch's PROTECTION that was previously aspirational
-- and is now actually enforced by the fix above.
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
    UPDATE public.ai_session_requests
    SET state = 'failed', terminal_code = 'LEASE_EXPIRED'
    WHERE id = v_row.id;

    IF v_row.state = 'reserved' THEN
      -- Never dispatched: no provider-start marker was ever set for
      -- this request_id, so it is safe to release the quota
      -- reservation exactly once via Plan A's release RPC.
      PERFORM public.release_ai_assistant_quota_reservation(v_row.actor_id, v_row.id);
    END IF;
    -- A request already 'started' has had claim_ai_session_dispatch's
    -- call to claim_ai_assistant_provider_start set the REAL,
    -- write-once ai_assistant_usage.provider_started_at marker for it
    -- (fix round 1: previously this marker was never actually written
    -- by any code path). That marker now genuinely makes this
    -- reservation's quota consumption permanent --
    -- release_ai_assistant_quota_reservation's own guard
    -- (provider_started_at IS NOT NULL AND outcome = 'reserved') will
    -- correctly RAISE if anything ever tries to release it. So
    -- reconciliation here only marks the SESSION's own bookkeeping
    -- 'failed' (so a new attempt can be admitted) and deliberately
    -- does not touch the now-permanent quota consumption.
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_ai_session_leases()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_ai_session_leases()
  TO service_role;
