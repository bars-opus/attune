-- The exclusive "admitted, then rejected before any provider call"
-- release path. Spec §7.3: "A terminal failure proven to have no
-- provider-start marker may release global quota once; once either
-- provider is marked started, outcome changes never refund it." Spec
-- §8.2.2's compensation table, row "Admission committed, no provider-
-- start marker": "Terminal cancel/fail releases global reservation
-- exactly once, retains session attempt; no prompt to partner."
--
-- Marks the row 'cancelled' (already excluded from the rolling-window
-- COUNT by reserve_ai_assistant_quota's own predicate) but ONLY when
-- provider_started_at IS NULL -- the WHERE clause below is the entire
-- enforcement of "never after a start marker is set." Idempotent: a
-- second call finds no row still matching
-- (outcome = 'reserved' AND provider_started_at IS NULL) and is a no-op,
-- exactly like mark_ai_assistant_usage_outcome's own silent-no-match
-- convention.
CREATE OR REPLACE FUNCTION public.release_ai_assistant_quota_reservation(
  p_actor_id uuid, p_request_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
      AND provider_started_at IS NOT NULL
      AND outcome = 'reserved'
  ) THEN
    RAISE EXCEPTION 'Cannot release a reservation whose provider call has started';
  END IF;

  UPDATE public.ai_assistant_usage
  SET outcome = 'cancelled', updated_at = now()
  WHERE request_id = p_request_id AND user_id = p_actor_id
    AND outcome = 'reserved'
    AND provider_started_at IS NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.release_ai_assistant_quota_reservation(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_ai_assistant_quota_reservation(uuid, uuid)
  TO service_role;
