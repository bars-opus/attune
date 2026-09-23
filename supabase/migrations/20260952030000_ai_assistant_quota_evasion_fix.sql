-- Post-review fix: closes a live quota-evasion gap the final whole-branch
-- review of Plan A found. Both bugs below compound to let a reservation
-- whose provider call actually started still be excluded from the
-- rolling-window count -- exactly what the plan's own Global Constraints
-- forbid: "Once provider_started_at is set, no outcome value may cause
-- the row to be excluded from the rolling-window COUNT ... the exclusion
-- applies only to provider_started_at IS NULL rows."
--
-- BUG 1 -- reserve_ai_assistant_quota's own COUNT predicate (added in
-- 20260952010000) never learned about provider_started_at. It still reads
-- `outcome NOT IN ('rejected', 'cancelled')`, so a row with a started
-- provider call that is later marked 'rejected' or 'cancelled' silently
-- drops out of the count -- even though 20260952020000's
-- release_ai_assistant_quota_reservation and its own test
-- (ai_assistant_quota_release_contracts.sql) already assume, and rely on,
-- the marker-aware predicate below. That test hand-derives the correct
-- predicate inline to check ITS OWN invariant; it never calls
-- reserve_ai_assistant_quota to check that RPC's predicate, which is why
-- five clean per-task reviews all missed this.
--
-- BUG 2 -- mark_ai_assistant_usage_outcome (20260951030000) has no guard
-- preventing a caller from writing 'cancelled' or 'rejected' onto a row
-- whose provider_started_at is already set. This is how the gap is
-- actually reachable in shipped code: ai-assist's handleNearby calls
-- claimProviderStart (succeeds, Gemini is genuinely called), Gemini's
-- response comes back off-allowlist, and the handler calls
-- mark_ai_assistant_usage_outcome(..., 'rejected', ...) -- which today
-- writes it through unconditionally. Combined with Bug 1's predicate, the
-- quota charge for a real, billed provider call vanishes.
--
-- Fix: CREATE OR REPLACE both functions (this migration set is
-- forward-only/additive -- 20260952010000 and 20260951030000 are already
-- applied and are not edited in place):
--   1. reserve_ai_assistant_quota's COUNT predicate becomes marker-aware:
--      a row with provider_started_at IS NOT NULL counts regardless of
--      outcome; the NOT IN exclusion applies only when the marker is
--      still NULL.
--   2. mark_ai_assistant_usage_outcome gains a WHERE-clause guard: when
--      p_outcome is 'cancelled' or 'rejected' -- the only two outcomes
--      the COUNT predicate above ever excludes -- the row must also have
--      provider_started_at IS NULL, or the UPDATE matches no row. A
--      started reservation may still transition to 'succeeded' or
--      'provider_failed' with no new restriction, because neither of
--      those outcomes is in the COUNT's exclusion set in the first place
--      -- they already count today and will continue to. Per this
--      function's existing documented convention, a call that would
--      violate the new rule is a silent no-op, not a raised exception
--      (unlike release_ai_assistant_quota_reservation, which does raise
--      -- a different RPC with different, already-reviewed semantics).

-- 1. Marker-aware COUNT predicate.
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

  -- Marker-aware COUNT predicate (post-review fix): once
  -- provider_started_at is set, the row counts no matter what outcome it
  -- later lands on -- the outcome-based exclusion applies only to rows
  -- whose provider call never started at all.
  SELECT count(*), min(created_at) INTO v_count, v_oldest
  FROM public.ai_assistant_usage u
  WHERE u.user_id = p_actor_id
    AND u.created_at >= now() - interval '24 hours'
    AND (u.provider_started_at IS NOT NULL OR u.outcome NOT IN ('rejected', 'cancelled'));

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
REVOKE ALL ON FUNCTION public.reserve_ai_assistant_quota(uuid, uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_ai_assistant_quota(uuid, uuid, uuid, text)
  TO service_role;

-- 2. Guard mark_ai_assistant_usage_outcome against refunding a started
--    reservation. Only 'cancelled' and 'rejected' are guarded -- those
--    are the only two outcomes the COUNT predicate above ever excludes.
--    'succeeded' and 'provider_failed' are not in that exclusion set, so
--    they already count today regardless of the marker and need no new
--    restriction.
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
    AND outcome = 'reserved'
    -- Post-review fix: 'cancelled'/'rejected' are the two outcomes the
    -- rolling-window COUNT excludes when provider_started_at IS NULL.
    -- Once a provider call has actually started, this row must stay
    -- counted forever, so it may never transition to one of those two
    -- values -- it may still resolve to 'succeeded' or 'provider_failed',
    -- which is why the guard is scoped to exactly these outcomes rather
    -- than a blanket provider_started_at check.
    AND (p_outcome NOT IN ('cancelled', 'rejected') OR provider_started_at IS NULL);
  -- Deliberately silent when no row matched: the row may legitimately be
  -- absent (the caller's own reserve raced and lost), belong to a
  -- different actor, already be terminal (a retried completion), or --
  -- as of this fix -- have a provider-start marker that forbids this
  -- specific outcome. None of those is an error; this function's
  -- established convention is a silent no-op, unlike
  -- release_ai_assistant_quota_reservation's raise-on-violation.
END;
$$;
REVOKE ALL ON FUNCTION public.mark_ai_assistant_usage_outcome(uuid, uuid, text, smallint)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_ai_assistant_usage_outcome(uuid, uuid, text, smallint)
  TO service_role;
