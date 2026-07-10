-- Rewrite complete_withdrawal + fail_withdrawal to use the canonical
-- `wallets` table (after the shop_wallets consolidation in 20260603001000).
--
-- These are called by the process-withdrawal edge function:
--   - On provider success: complete_withdrawal(withdrawal_id, transfer_id)
--   - On provider permanent failure: fail_withdrawal(withdrawal_id, reason)
--   - On exhausted retries: dead_letter_withdrawal (already correct, see
--     20260521000000)
--
-- BUG FIXES vs. the live versions:
--   * `wallets` instead of `shop_wallets`.
--   * `failure_reason` (the column actually in withdrawal_requests per
--     the original migration) instead of the live's `failed_reason`
--     which doesn't exist. The live function has been failing silently
--     on the UPDATE for every failed withdrawal — the row status moves
--     to 'failed' but the reason was never recorded.
--     (If the live `failed_reason` column actually exists from a
--     dashboard alter, this migration is still safe — it just writes
--     the schema-correct column.)
--   * complete_withdrawal: only decrement pending_withdrawals; the
--     balance was already debited at create-time? Re-check below.
--     ACTUALLY the live version decrements balance AND pending here,
--     and the create version only adds to pending. So balance starts
--     unchanged and only drops at complete-time. Preserved.
--
-- CONCURRENCY (checklist 1.6)
--   SELECT … FOR UPDATE on withdrawal_requests prevents two concurrent
--   complete/fail calls on the same withdrawal. The subsequent UPDATE
--   on wallets is a single row, atomic.
--
-- IMMUTABILITY (checklist 2.22)
--   These functions INSERT into withdrawal_audit_log. The immutability
--   trigger added in 20260603001700 forbids UPDATE/DELETE on that
--   table even from SECURITY DEFINER context.

-- ── complete_withdrawal ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.complete_withdrawal(
  p_withdrawal_id        UUID,
  p_provider_transfer_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_shop_id      UUID;
  v_amount       NUMERIC;
  v_current_status TEXT;
BEGIN
  SELECT shop_id, amount, status
    INTO v_shop_id, v_amount, v_current_status
    FROM public.withdrawal_requests
   WHERE id = p_withdrawal_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'withdrawal_request % not found', p_withdrawal_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Idempotency: already-completed call returns without side effect.
  -- Without this guard a webhook replay would double-debit the wallet.
  IF v_current_status = 'completed' THEN
    RETURN;
  END IF;

  IF v_current_status NOT IN ('pending', 'processing', 'retrying') THEN
    RAISE EXCEPTION 'cannot complete withdrawal from status %', v_current_status
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.withdrawal_requests
     SET status               = 'completed',
         provider_transfer_id = p_provider_transfer_id,
         processed_at         = now(),
         completed_at         = now(),
         updated_at           = now()
   WHERE id = p_withdrawal_id;

  UPDATE public.wallets
     SET balance              = balance - v_amount,
         pending_withdrawals  = pending_withdrawals - v_amount,
         total_withdrawn      = total_withdrawn + v_amount,
         updated_at           = now()
   WHERE shop_id = v_shop_id;

  INSERT INTO public.withdrawal_audit_log (
    withdrawal_id, from_status, to_status, changed_by, reason
  ) VALUES (
    p_withdrawal_id, v_current_status, 'completed',
    'system', 'Withdrawal completed successfully'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.complete_withdrawal(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_withdrawal(UUID, TEXT) TO service_role;
COMMENT ON FUNCTION public.complete_withdrawal(UUID, TEXT) IS
  'Marks a withdrawal completed, debits wallets.balance, releases the pending hold, writes audit log. Idempotent on prior completed state. Called by process-withdrawal edge function with service_role JWT.';

-- ── fail_withdrawal ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fail_withdrawal(
  p_withdrawal_id UUID,
  p_failed_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_shop_id        UUID;
  v_amount         NUMERIC;
  v_current_status TEXT;
BEGIN
  SELECT shop_id, amount, status
    INTO v_shop_id, v_amount, v_current_status
    FROM public.withdrawal_requests
   WHERE id = p_withdrawal_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'withdrawal_request % not found', p_withdrawal_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Idempotency: already-failed call returns without side effect.
  IF v_current_status = 'failed' THEN
    RETURN;
  END IF;

  IF v_current_status NOT IN ('pending', 'processing', 'retrying') THEN
    RAISE EXCEPTION 'cannot fail withdrawal from status %', v_current_status
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.withdrawal_requests
     SET status         = 'failed',
         failure_reason = p_failed_reason,
         processed_at   = now(),
         failed_at      = now(),
         updated_at     = now()
   WHERE id = p_withdrawal_id;

  -- Refund: only the pending hold is released; balance was never debited.
  UPDATE public.wallets
     SET pending_withdrawals = GREATEST(0, pending_withdrawals - v_amount),
         updated_at          = now()
   WHERE shop_id = v_shop_id;

  INSERT INTO public.withdrawal_audit_log (
    withdrawal_id, from_status, to_status, changed_by, reason, metadata
  ) VALUES (
    p_withdrawal_id, v_current_status, 'failed',
    'system', 'Withdrawal failed',
    jsonb_build_object('reason', p_failed_reason)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fail_withdrawal(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fail_withdrawal(UUID, TEXT) TO service_role;
COMMENT ON FUNCTION public.fail_withdrawal(UUID, TEXT) IS
  'Marks a withdrawal failed, releases the pending hold on wallets.pending_withdrawals (balance was never debited), writes audit log. Idempotent on prior failed state.';

-- ── dead_letter_withdrawal: was already correct (uses wallets). No
-- changes needed; left in place from 20260521000000.
