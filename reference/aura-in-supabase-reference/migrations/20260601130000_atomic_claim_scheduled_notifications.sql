-- Atomic claim for scheduled_notifications.
--
-- Previously the scheduler did:
--   SELECT * WHERE status='pending' LIMIT 50
--   UPDATE SET status='processing' WHERE id IN (…)
-- Two cron invocations overlapping in the millisecond window between the
-- SELECT and the UPDATE could pick up the same rows and double-send.
--
-- This RPC collapses the two into one statement using FOR UPDATE SKIP LOCKED,
-- which the Supabase JS client cannot express directly.

CREATE OR REPLACE FUNCTION claim_pending_notifications(
  p_limit INT DEFAULT 50,
  p_now   TIMESTAMPTZ DEFAULT NOW()
)
RETURNS SETOF scheduled_notifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE scheduled_notifications sn
  SET status = 'processing',
      updated_at = p_now
  WHERE sn.id IN (
    SELECT id FROM scheduled_notifications
    WHERE status = 'pending'
      AND scheduled_for <= p_now
    ORDER BY scheduled_for
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  )
  RETURNING sn.*;
END;
$$;

REVOKE ALL ON FUNCTION claim_pending_notifications(INT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION claim_pending_notifications(INT, TIMESTAMPTZ) TO service_role;

COMMENT ON FUNCTION claim_pending_notifications IS
  'Atomically claim up to p_limit pending notifications by transitioning their status to processing. Uses FOR UPDATE SKIP LOCKED so concurrent workers cannot claim the same rows.';
