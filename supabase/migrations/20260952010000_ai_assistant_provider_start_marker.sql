-- Adds the provider-start marker this plan's Tasks 2-4 build the
-- exclusive-lease model on top of, and widens `mode` to accept
-- Sessions (Plan B). Spec §7.3, §8.2.2.
--
-- provider_started_at is NULL until a trusted RPC (Task 2's
-- claim_ai_assistant_provider_start) sets it, and is permanent from
-- then on -- Task 2 enforces the write-once rule in application logic
-- (an UPDATE ... WHERE provider_started_at IS NULL guard), since
-- Postgres has no native write-once column constraint.
ALTER TABLE public.ai_assistant_usage
  ADD COLUMN provider_started_at timestamptz;

ALTER TABLE public.ai_assistant_usage
  DROP CONSTRAINT ai_assistant_usage_mode_check;
ALTER TABLE public.ai_assistant_usage
  ADD CONSTRAINT ai_assistant_usage_mode_check
    CHECK (mode IN ('assist', 'understand', 'session'));

-- Update reserve_ai_assistant_quota to accept 'session' mode
CREATE OR REPLACE FUNCTION public.reserve_ai_assistant_quota(
  p_actor_id uuid, p_request_id uuid, p_relationship_id uuid, p_mode text
) RETURNS TABLE (outcome text, retry_after_seconds int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.ai_assistant_usage;
  v_count int;
  v_oldest timestamptz;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_mode NOT IN ('assist', 'understand', 'session') THEN
    RAISE EXCEPTION 'Invalid mode';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = p_actor_id OR r.user_b = p_actor_id)
  ) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  SELECT * INTO v_existing FROM public.ai_assistant_usage WHERE request_id = p_request_id;
  IF v_existing.request_id IS NOT NULL THEN
    IF v_existing.user_id IS DISTINCT FROM p_actor_id OR v_existing.mode IS DISTINCT FROM p_mode THEN
      RAISE EXCEPTION 'A different reservation already exists with this request id';
    END IF;
    -- The lease was granted to the ORIGINAL invocation, not this one.
    -- Returning 'reserved' here is what let one request_id fund unlimited
    -- provider calls.
    RETURN QUERY SELECT 'already_reserved'::text, NULL::int;
    RETURN;
  END IF;

  -- Serialize per-user quota checks. hashtextextended's second argument
  -- is a fixed salt distinguishing this lock's keyspace from any other
  -- advisory-lock use in the codebase.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_actor_id::text, 4451));

  SELECT count(*), min(created_at) INTO v_count, v_oldest
  FROM public.ai_assistant_usage u
  WHERE u.user_id = p_actor_id
    AND u.created_at >= now() - interval '24 hours'
    AND u.outcome NOT IN ('rejected', 'cancelled');

  IF v_count >= 20 THEN
    RETURN QUERY SELECT
      'rate_limited'::text,
      GREATEST(1, CEIL(EXTRACT(EPOCH FROM (v_oldest + interval '24 hours' - now())))::int);
    RETURN;
  END IF;

  INSERT INTO public.ai_assistant_usage
    (request_id, user_id, relationship_id, mode, outcome)
  VALUES (p_request_id, p_actor_id, p_relationship_id, p_mode, 'reserved')
  ON CONFLICT (request_id) DO NOTHING;

  IF NOT FOUND THEN
    -- Another concurrent transaction with the SAME request_id won the
    -- race and inserted first. That invocation holds the lease; this one
    -- does not, so it reports a replay rather than a reservation.
    SELECT * INTO v_existing FROM public.ai_assistant_usage WHERE request_id = p_request_id;
    IF v_existing.user_id IS DISTINCT FROM p_actor_id OR v_existing.mode IS DISTINCT FROM p_mode THEN
      RAISE EXCEPTION 'A different reservation already exists with this request id';
    END IF;
    RETURN QUERY SELECT 'already_reserved'::text, NULL::int;
    RETURN;
  END IF;

  RETURN QUERY SELECT 'reserved'::text, NULL::int;
END;
$$;

-- The single write point for provider_started_at. "true" means THIS
-- call is the one that claimed it -- the caller proceeds to contact the
-- provider. "false" means it was already claimed (by a retry of the
-- same request, or a concurrent duplicate) -- the caller must NOT
-- contact the provider again; per spec §6.2, "Never retry uncertain
-- external calls, even with the same request ID; expose terminal
-- failure instead."
CREATE OR REPLACE FUNCTION public.claim_ai_assistant_provider_start(
  p_actor_id uuid, p_request_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_claimed boolean;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.ai_assistant_usage
    WHERE request_id = p_request_id AND user_id = p_actor_id
  ) THEN
    RAISE EXCEPTION 'Reservation not found for this actor';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.ai_assistant_usage
    WHERE request_id = p_request_id AND user_id = p_actor_id
      AND outcome != 'reserved'
  ) THEN
    RAISE EXCEPTION 'Cannot claim provider start on a terminal reservation';
  END IF;

  UPDATE public.ai_assistant_usage
  SET provider_started_at = now()
  WHERE request_id = p_request_id AND user_id = p_actor_id
    AND provider_started_at IS NULL;
  v_claimed := FOUND;

  RETURN v_claimed;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_ai_assistant_provider_start(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_ai_assistant_provider_start(uuid, uuid)
  TO service_role;
