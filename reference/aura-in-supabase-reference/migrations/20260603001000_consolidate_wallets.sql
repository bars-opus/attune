-- Consolidate shop_wallets into wallets (the canonical table).
--
-- WHY ──────────────────────────────────────────────────────────────
-- Investigation confirmed `wallets` is canonical:
--   * Deposits land in `wallets` (paystack-webhook + stripe-webhook +
--     verify-payment all call add_wallet_transaction → wallets).
--   * The UI WalletBalanceCard reads `wallets`.
--   * The retry queue's refund path (dead_letter_withdrawal) updates
--     `wallets`.
--   * The process-withdrawal edge function reads `wallets`.
--
-- `shop_wallets` is touched only by the three withdrawal RPCs
-- (create_withdrawal_request, complete_withdrawal, fail_withdrawal)
-- and the missing check_daily_withdrawal_limit. They were written
-- against a ghost table and have been silently desynced from the
-- real wallet ever since.
--
-- LIVE STATE (verified 2026-06-03):
--   * shop_wallets has 4 rows; 2 have non-zero balance; 0 pending;
--     0 daily-counter activity. Last update 2026-06-02.
--   * Those non-zero balances are stale — they represent the OLD
--     view of money from before deposits started flowing exclusively
--     to `wallets`. The canonical balance for those shops is in
--     `wallets`. We do NOT merge shop_wallets.balance into wallets,
--     because that would double-count.
--
-- WHAT THIS MIGRATION DOES
--   1. Adds `last_withdrawal_date` and `total_withdrawn_today` columns
--      to `wallets` (the only state shop_wallets carried that wasn't
--      already in wallets) so the rewritten withdrawal RPCs in
--      20260603001100 / 200 / 300 have a place to read/write them.
--   2. Does NOT migrate balance/total_earned/total_withdrawn — those
--      are already authoritative in `wallets` via add_wallet_transaction.
--   3. Drops `shop_wallets` so no future code path can accidentally
--      target it.
--
-- ROLLBACK
--   Tier 2 manual: `DROP COLUMN` the new wallets columns; recreate
--   shop_wallets from 20260603000100. No money state is destroyed by
--   this migration — only stale ledger state.

-- ── 1. Add daily-limit tracking columns to canonical wallets table.
ALTER TABLE public.wallets
  ADD COLUMN IF NOT EXISTS last_withdrawal_date  DATE,
  ADD COLUMN IF NOT EXISTS total_withdrawn_today NUMERIC(12,2)
       NOT NULL DEFAULT 0 CHECK (total_withdrawn_today >= 0);

COMMENT ON COLUMN public.wallets.last_withdrawal_date IS
  'Day of the most recent withdrawal. Paired with total_withdrawn_today to enforce the per-shop daily cap. Reset on first withdrawal of a new day by check_daily_withdrawal_limit.';

COMMENT ON COLUMN public.wallets.total_withdrawn_today IS
  'Sum of withdrawal amounts requested today (UTC). Reset to the new request amount when last_withdrawal_date rolls to today. Read/written by check_daily_withdrawal_limit.';

-- ── 2. Sanity: confirm we're not about to lose pending state.
DO $$
DECLARE
  v_pending NUMERIC;
BEGIN
  SELECT COALESCE(SUM(pending_withdrawals), 0)
    INTO v_pending
    FROM public.shop_wallets;
  IF v_pending > 0 THEN
    RAISE EXCEPTION
      'Abort: shop_wallets has % in pending_withdrawals. Reconcile by hand before dropping (see runbook for manual SQL).',
      v_pending;
  END IF;
END $$;

-- ── 3. Drop the ghost table.
-- Policies and indexes go with it. Any code that still references
-- shop_wallets will fail loudly at deploy/CI rather than silently
-- desync from wallets.
DROP TABLE IF EXISTS public.shop_wallets CASCADE;

COMMENT ON TABLE public.wallets IS
  'Canonical wallet table per shop. Funded by add_wallet_transaction (deposits/refunds/adjustments) and decremented by complete_withdrawal (debits). Holds pending_withdrawals between create_withdrawal_request and complete/fail_withdrawal. Daily-cap state in last_withdrawal_date/total_withdrawn_today.';
