-- ============================================================
-- Withdrawal retry queue
-- ============================================================
--
-- Adds retry-with-backoff for transient withdrawal payout failures.
-- New states: `retrying` (will be retried later) and `dead_letter`
-- (retries exhausted — operator must review).
--
-- The wallet stays debited while a withdrawal is in `retrying`. Refund
-- happens only on terminal outcomes (`failed` or `dead_letter`).
--
-- See docs/superpowers/specs/2026-05-21-withdrawal-retry-queue-design.md
-- and docs/runbooks/withdrawal-retry-queue.md for the full design and
-- operator runbook.
-- ============================================================

-- Required extensions (no-op if already enabled)
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ── Extend the status enum ──────────────────────────────────
ALTER TABLE withdrawal_requests
  DROP CONSTRAINT IF EXISTS withdrawal_requests_status_check;

ALTER TABLE withdrawal_requests
  ADD CONSTRAINT withdrawal_requests_status_check
  CHECK (status IN (
    'pending', 'processing', 'completed',
    'retrying',     -- transient failure, will be retried
    'dead_letter',  -- retries exhausted, needs manual review
    'failed',       -- permanent business failure (bad account, declined, etc.)
    'refunded'
  ));

-- ── Retry-tracking columns ──────────────────────────────────
ALTER TABLE withdrawal_requests
  ADD COLUMN IF NOT EXISTS attempt_count       INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS next_attempt_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_error          TEXT,
  ADD COLUMN IF NOT EXISTS dead_letter_reason  TEXT;

-- Partial index for the cron job's "due retries" query
CREATE INDEX IF NOT EXISTS withdrawal_requests_due_retries_idx
  ON withdrawal_requests (next_attempt_at)
  WHERE status = 'retrying';

-- ── RPC: schedule_withdrawal_retry ──────────────────────────
-- Transition pending|processing|retrying → retrying, bump attempt_count.
CREATE OR REPLACE FUNCTION schedule_withdrawal_retry(
  p_withdrawal_id     UUID,
  p_next_attempt_at   TIMESTAMPTZ,
  p_last_error        TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE withdrawal_requests
  SET status          = 'retrying',
      attempt_count   = attempt_count + 1,
      next_attempt_at = p_next_attempt_at,
      last_error      = p_last_error,
      updated_at      = now()
  WHERE id = p_withdrawal_id
    AND status IN ('pending','processing','retrying');
END;
$$;

REVOKE ALL ON FUNCTION schedule_withdrawal_retry(UUID, TIMESTAMPTZ, TEXT) FROM public;

-- ── RPC: dead_letter_withdrawal ─────────────────────────────
-- Transition retrying|processing → dead_letter, refund wallet.
CREATE OR REPLACE FUNCTION dead_letter_withdrawal(
  p_withdrawal_id UUID,
  p_reason        TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shop_id UUID;
  v_amount  NUMERIC;
BEGIN
  UPDATE withdrawal_requests
  SET status              = 'dead_letter',
      dead_letter_reason  = p_reason,
      updated_at          = now()
  WHERE id = p_withdrawal_id
    AND status IN ('retrying','processing')
  RETURNING shop_id, amount INTO v_shop_id, v_amount;

  -- Refund the wallet — same effect as fail_withdrawal's refund.
  IF v_shop_id IS NOT NULL THEN
    UPDATE wallets
    SET balance              = balance + v_amount,
        pending_withdrawals  = GREATEST(0, pending_withdrawals - v_amount),
        updated_at           = now()
    WHERE shop_id = v_shop_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION dead_letter_withdrawal(UUID, TEXT) FROM public;

-- ── Cron worker: trigger_due_withdrawal_retries ─────────────
-- Find due retries, set them back to 'pending', and fire process-withdrawal.
-- Caps fan-out at 20 per tick so a queue burst doesn't overwhelm the function.
CREATE OR REPLACE FUNCTION trigger_due_withdrawal_retries()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec            RECORD;
  v_count          INT := 0;
  v_function_url   TEXT := current_setting('app.settings.process_withdrawal_url', true);
  v_webhook_secret TEXT := current_setting('app.settings.internal_webhook_secret', true);
BEGIN
  IF v_function_url IS NULL OR v_webhook_secret IS NULL THEN
    RAISE WARNING 'trigger_due_withdrawal_retries: missing app.settings configuration (process_withdrawal_url or internal_webhook_secret)';
    RETURN 0;
  END IF;

  FOR v_rec IN
    SELECT id FROM withdrawal_requests
    WHERE status = 'retrying'
      AND next_attempt_at <= now()
    ORDER BY next_attempt_at ASC
    LIMIT 20
  LOOP
    -- Reset to 'pending' so process-withdrawal's existing status guard accepts it.
    UPDATE withdrawal_requests
    SET status = 'pending', updated_at = now()
    WHERE id = v_rec.id AND status = 'retrying';

    PERFORM net.http_post(
      url     := v_function_url,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || v_webhook_secret
      ),
      body    := jsonb_build_object('withdrawal_id', v_rec.id)
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION trigger_due_withdrawal_retries() FROM public;

-- ── Recovery: sweep_stuck_pending_withdrawals ───────────────
-- If the cron marked a row 'pending' but the HTTP call never landed (network
-- failure between cron and edge function), the row stays in 'pending' with
-- no one to pick it up. After 5 minutes, bump it back to 'retrying' for the
-- next cron tick to pick up.
CREATE OR REPLACE FUNCTION sweep_stuck_pending_withdrawals()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  WITH bumped AS (
    UPDATE withdrawal_requests
    SET status          = 'retrying',
        next_attempt_at = now() + interval '1 minute',
        last_error      = COALESCE(last_error, 'stuck in pending — sweep recovered'),
        updated_at      = now()
    WHERE status = 'pending'
      AND attempt_count > 0
      AND updated_at < now() - interval '5 minutes'
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM bumped;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION sweep_stuck_pending_withdrawals() FROM public;

-- ============================================================
-- Cron scheduling lives in the runbook (not the migration) — same pattern
-- as expire_stale_pending_payments. The runbook also sets the required
-- GUCs (app.settings.process_withdrawal_url, app.settings.internal_webhook_secret).
-- ============================================================
