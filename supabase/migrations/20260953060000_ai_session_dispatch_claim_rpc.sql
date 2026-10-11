-- claim_ai_session_dispatch / reconcile_ai_session_leases. Spec §6.2, §8.2.2.
CREATE OR REPLACE FUNCTION public.claim_ai_session_dispatch(
  p_worker_token uuid, p_request_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_claimed boolean;
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.ai_session_requests
    WHERE id = p_request_id AND worker_token = p_worker_token
      AND state = 'reserved' AND lease_deadline > now()
  ) THEN
    UPDATE public.ai_session_requests
    SET state = 'started', provider_started_at = now()
    WHERE id = p_request_id AND worker_token = p_worker_token AND state = 'reserved';
    v_claimed := FOUND;
  ELSE
    v_claimed := false;
  END IF;
  RETURN v_claimed;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_ai_session_dispatch(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_ai_session_dispatch(uuid, uuid)
  TO service_role;

-- Sweeps requests whose lease has expired without a completion. A
-- request still in 'reserved' (never dispatched) releases its quota
-- reservation exactly once via Plan A's release RPC, since no
-- provider-start marker was ever set for it (mirrors the guard inside
-- release_ai_assistant_quota_reservation itself -- calling it on an
-- already-started reservation raises, so this function must only call
-- it for the 'reserved' branch below). A request already 'started'
-- (provider call in flight or its result unknown) is left counted, per
-- spec §8.2.2's compensation table -- reconciliation marks it 'failed'
-- for the SESSION's own bookkeeping (so a new attempt can be admitted)
-- without touching its ALREADY-PERMANENT quota consumption.
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
      PERFORM public.release_ai_assistant_quota_reservation(v_row.actor_id, v_row.id);
    END IF;

    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_ai_session_leases()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_ai_session_leases()
  TO service_role;
