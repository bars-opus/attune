-- Repairs two vulnerabilities in the AI assistant quota ledger, found by
-- the 2026-09-22 adversarial review of the AI Sessions spec (finding F08).
-- Both are in shipped code and are independent of whether Sessions is ever
-- built.
--
-- VULNERABILITY 1 -- replay returns an indistinguishable lease.
--
-- reserve_ai_assistant_quota returned the bare string 'reserved' both for
-- a genuinely fresh reservation AND for a replay of a request_id that
-- already existed. The caller could not tell the two apart, so a client
-- replaying one request_id drove a fresh provider call every time while
-- consuming exactly one quota slot. Base spec §7.3 requires the opposite:
-- "exactly the invocation that creates the reservation receives the one
-- provider lease", and replays must return REQUEST_IN_PROGRESS or the
-- existing result -- never a second lease.
--
-- Fixed by making the outcome distinguish the two cases. 'reserved' now
-- means "you hold the lease"; 'already_reserved' means "this request
-- already exists, do not call a provider". The edge functions treat
-- anything other than 'reserved' as "no lease".
--
-- VULNERABILITY 2 -- callers could erase their own consumption.
--
-- mark_ai_assistant_usage_outcome was granted to `authenticated` and wrote
-- any caller-supplied outcome onto the caller's own row. The reservation
-- count excludes 'rejected' and 'cancelled', so any user could call this
-- RPC directly with p_outcome => 'cancelled' and zero out their usage,
-- making the 20-per-24h cap unenforceable.
--
-- Fixed by revoking `authenticated` from both functions and moving them to
-- service_role. The edge functions already build a service-role client
-- (serviceRoleClient() in _shared/attune_auth.ts) for other calls in the
-- same request.
--
-- CONSEQUENCE OF THE service_role MOVE: neither function may rely on
-- auth.uid() any more -- serviceRoleClient() carries the service key, not
-- a user JWT, so auth.uid() is NULL under it. Both functions gain an
-- explicit p_actor_id parameter instead. This is safe ONLY because the
-- edge function's own p_actor_id argument comes from requireUser(req)
-- (verified server-side against Supabase Auth via supabase.auth.getUser),
-- never from the request body -- the same "identity from a verified
-- bearer token, never a client-supplied field" rule the base spec's own
-- P0 findings established for message/relationship IDs. A client cannot
-- reach these functions at all any more (no `authenticated` grant), so
-- there is no path for a caller to supply p_actor_id themselves.
--
-- Outcomes are additionally made monotonic: a terminal outcome cannot be
-- rewritten, so even a compromised worker cannot walk a succeeded row
-- back to 'cancelled'.

-- 1. Distinguish a replay from a fresh lease; take the actor explicitly
--    instead of via auth.uid().
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
  IF p_mode NOT IN ('assist', 'understand') THEN
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

-- 2. Server-only, monotonic outcomes; actor taken explicitly (see note
--    above -- auth.uid() is NULL once called via service_role).
CREATE OR REPLACE FUNCTION public.mark_ai_assistant_usage_outcome(
  p_actor_id uuid, p_request_id uuid, p_outcome text, p_provider_calls smallint
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_outcome NOT IN ('succeeded', 'rejected', 'provider_failed', 'cancelled') THEN
    RAISE EXCEPTION 'Invalid outcome';
  END IF;

  UPDATE public.ai_assistant_usage
  SET outcome = p_outcome, provider_calls = p_provider_calls, updated_at = now()
  WHERE request_id = p_request_id
    AND user_id = p_actor_id
    -- Monotonic: only a still-reserved row may transition. Replaying a
    -- completion is a no-op rather than a rewrite.
    AND outcome = 'reserved';
  -- Deliberately silent when no row matched: the row may legitimately be
  -- absent (the caller's own reserve raced and lost), belong to a
  -- different actor, or already be terminal (a retried completion). None
  -- of those is an error.
END;
$$;

-- 3. Drop the old `authenticated`-callable signatures entirely (the
--    parameter list changed, so the old overload has no replacement to
--    fall back to) and grant only service_role on the new ones.
DROP FUNCTION IF EXISTS public.reserve_ai_assistant_quota(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.mark_ai_assistant_usage_outcome(uuid, text, smallint);

REVOKE ALL ON FUNCTION public.reserve_ai_assistant_quota(uuid, uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_ai_assistant_quota(uuid, uuid, uuid, text)
  TO service_role;

REVOKE ALL ON FUNCTION public.mark_ai_assistant_usage_outcome(uuid, uuid, text, smallint)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_ai_assistant_usage_outcome(uuid, uuid, text, smallint)
  TO service_role;
