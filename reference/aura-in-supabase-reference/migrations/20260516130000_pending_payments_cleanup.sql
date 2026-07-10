-- ============================================================
-- pending_payments cleanup + race-safety
-- ============================================================
--
-- Two purposes:
--
-- 1. Mark stale `pending` rows as `expired` once `expires_at` is past, so a
--    late-arriving webhook (after the 30-minute window) doesn't create a
--    booking for a slot the user has already lost.
--
-- 2. Add an idempotency-safe trigger that bumps `updated_at` automatically.
--
-- The cleanup is exposed as a SECURITY DEFINER RPC so it can be called from:
--   • A pg_cron schedule  (preferred — runs every minute regardless of traffic)
--   • The webhook handler (cheap defense-in-depth on every event)
--   • A manual ops command
-- ============================================================

CREATE OR REPLACE FUNCTION expire_stale_pending_payments()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  WITH expired AS (
    UPDATE pending_payments
    SET    status     = 'expired',
           updated_at = now()
    WHERE  status     = 'pending'
      AND  expires_at < now()
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM expired;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION expire_stale_pending_payments() FROM public;
-- Service-role only — no GRANT to authenticated.

-- Bump updated_at on every UPDATE (matches the payment-schema convention).
CREATE OR REPLACE FUNCTION pending_payments_touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pending_payments_touch ON pending_payments;
CREATE TRIGGER trg_pending_payments_touch
  BEFORE UPDATE ON pending_payments
  FOR EACH ROW EXECUTE FUNCTION pending_payments_touch_updated_at();

-- ── Optional: schedule the cleanup via pg_cron ─────────────
-- Enable pg_cron in your Supabase project (Database → Extensions), then
-- uncomment the block below. Runs every minute.
--
--   SELECT cron.schedule(
--     'expire-stale-pending-payments',
--     '* * * * *',
--     $$SELECT public.expire_stale_pending_payments();$$
--   );
--
-- If pg_cron is unavailable, call `expire_stale_pending_payments()` at the
-- top of each webhook handler — the cost is negligible (single UPDATE).
