-- Atomic quota ledger. Spec §7.3. "One database operation" means the
-- INSERT ... ON CONFLICT DO NOTHING pattern below runs as a single
-- statement -- the row-lock implicit in that statement is what
-- serializes concurrent callers with the SAME request_id.
--
-- The window-count SELECT below is a different story: it is NOT safe to
-- leave unlocked. Under READ COMMITTED (Postgres's default), two
-- concurrent callers with the SAME user but DIFFERENT request_ids can
-- both run the COUNT while the user is at 19, both see 19 (< 20), both
-- pass the check, and both INSERT distinct rows -- landing the user at
-- 21, over the cap. This was caught by an actual two-session concurrent
-- test (see task-4-report.md), not just a sequential "insert 20 then
-- check the 21st fails" test, which cannot see this class of bug.
-- pg_advisory_xact_lock on the user id serializes reservation attempts
-- for that user for the rest of this transaction (released automatically
-- at COMMIT/ROLLBACK), so the count each caller sees is always accurate
-- as of the moment it actually gets to check. It does NOT serialize
-- different users against each other (advisory locks are keyed, so
-- unrelated users proceed concurrently), matching the per-user quota
-- being the point of contention, not a global one.
CREATE OR REPLACE FUNCTION public.reserve_ai_assistant_quota(
  p_request_id uuid, p_relationship_id uuid, p_mode text
) RETURNS TABLE (outcome text, retry_after_seconds int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_existing public.ai_assistant_usage;
  v_count int;
  v_oldest timestamptz;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_mode NOT IN ('assist', 'understand') THEN
    RAISE EXCEPTION 'Invalid mode';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = v_actor OR r.user_b = v_actor)
  ) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  SELECT * INTO v_existing FROM public.ai_assistant_usage WHERE request_id = p_request_id;
  IF v_existing.request_id IS NOT NULL THEN
    IF v_existing.user_id IS DISTINCT FROM v_actor OR v_existing.mode IS DISTINCT FROM p_mode THEN
      RAISE EXCEPTION 'A different reservation already exists with this request id';
    END IF;
    RETURN QUERY SELECT 'reserved'::text, NULL::int;
    RETURN;
  END IF;

  -- Serialize per-user quota checks. hashtextextended's second argument
  -- is a fixed salt distinguishing this lock's keyspace from any other
  -- advisory-lock use in the codebase.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_actor::text, 4451));

  SELECT count(*), min(created_at) INTO v_count, v_oldest
  FROM public.ai_assistant_usage u
  WHERE u.user_id = v_actor
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
  VALUES (p_request_id, v_actor, p_relationship_id, p_mode, 'reserved')
  ON CONFLICT (request_id) DO NOTHING;

  IF NOT FOUND THEN
    -- Another concurrent transaction with the SAME request_id won the
    -- race and inserted first (or already exists after our snapshot was
    -- taken) -- re-read what actually landed and return it as our own
    -- outcome, honoring the idempotency contract instead of erroring.
    SELECT * INTO v_existing FROM public.ai_assistant_usage WHERE request_id = p_request_id;
    IF v_existing.user_id IS DISTINCT FROM v_actor OR v_existing.mode IS DISTINCT FROM p_mode THEN
      RAISE EXCEPTION 'A different reservation already exists with this request id';
    END IF;
    RETURN QUERY SELECT 'reserved'::text, NULL::int;
    RETURN;
  END IF;

  RETURN QUERY SELECT 'reserved'::text, NULL::int;
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_ai_assistant_quota(uuid, uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_ai_assistant_quota(uuid, uuid, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_ai_assistant_usage_outcome(
  p_request_id uuid, p_outcome text, p_provider_calls smallint
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  UPDATE public.ai_assistant_usage
  SET outcome = p_outcome, provider_calls = p_provider_calls, updated_at = now()
  WHERE request_id = p_request_id AND user_id = v_actor;
  -- Deliberately silent (no exception) if no row matched -- this can
  -- legitimately happen if a client calls this after its own reserve
  -- call raced/failed; the caller has no reservation to update in that
  -- case, which is not itself an error.
END;
$$;
REVOKE ALL ON FUNCTION public.mark_ai_assistant_usage_outcome(uuid, text, smallint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_ai_assistant_usage_outcome(uuid, text, smallint)
  TO authenticated;
