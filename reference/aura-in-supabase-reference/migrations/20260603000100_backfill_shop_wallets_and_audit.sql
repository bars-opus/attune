-- Backfill: tables that exist in production but were created via the
-- Supabase Dashboard and never committed. Reconstructed from live schema
-- on 2026-06-03 (project kbmjwicdffpuowymkobo).
--
-- SCHEMA DRIFT WARNING — DO NOT MERGE WITHOUT A FOLLOW-UP DECISION
-- ─────────────────────────────────────────────────────────────────
-- We currently have TWO wallet tables in production:
--
--   * public.wallets        — created by migration 20260516120000.
--     Read by Dart WalletBalanceCard, written by add_wallet_transaction()
--     RPC (paystack-webhook + stripe-webhook deposit credits land here).
--
--   * public.shop_wallets   — created via Dashboard, NOT in migrations.
--     Read by check_daily_withdrawal_limit(), written by
--     create_withdrawal_request() RPC (the pending_withdrawals counter
--     for hold/release is here).
--
-- Result: depositing money increments `wallets.balance` but requesting
-- a withdrawal decrements `shop_wallets.pending_withdrawals` from a row
-- whose `balance` may be zero. The withdrawal flow's pre-check ("do we
-- have enough?") reads `shop_wallets.balance` which is never funded by
-- the deposit path. THIS IS A SILENT MONEY-MOVEMENT BUG.
--
-- This migration backfills `shop_wallets` schema as-is so CI / local
-- match prod. It does NOT attempt to merge the two tables — that
-- requires a product-level decision (which is canonical?) and a
-- separate, reviewed migration that reconciles balances before drop.
--
-- See checklist v3.1: 2.19 (money correctness), 6.13 (documentation),
-- 7.2 (static analysis would have caught this), 8.1 (rollback).

-- ─────────────────────────────────────────────────────────────────
-- shop_wallets — parallel wallet table
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.shop_wallets (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id                  UUID NOT NULL UNIQUE REFERENCES public.shops(id) ON DELETE CASCADE,
  balance                  NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  total_earned             NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_earned >= 0),
  total_withdrawn          NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_withdrawn >= 0),
  pending_withdrawals      NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (pending_withdrawals >= 0),
  currency                 TEXT NOT NULL DEFAULT 'GHS',
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_withdrawal_date     DATE,
  total_withdrawn_today    NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_withdrawn_today >= 0)
);

CREATE INDEX IF NOT EXISTS shop_wallets_shop_id_idx
  ON public.shop_wallets (shop_id);

ALTER TABLE public.shop_wallets ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='shop_wallets_owner_read') THEN
    CREATE POLICY shop_wallets_owner_read ON public.shop_wallets
      FOR SELECT TO authenticated
      USING (shop_id IN (SELECT id FROM public.shops WHERE user_id = auth.uid()));
  END IF;
END $$;

COMMENT ON TABLE public.shop_wallets IS
  'DRIFT: parallel to public.wallets. The withdrawal RPC reads/writes this; the deposit RPC reads/writes wallets. Reconcile before next billing cycle.';

-- ─────────────────────────────────────────────────────────────────
-- withdrawal_audit_log — append-only audit trail
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.withdrawal_audit_log (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  withdrawal_id UUID NOT NULL REFERENCES public.withdrawal_requests(id) ON DELETE CASCADE,
  from_status   TEXT,
  to_status     TEXT NOT NULL,
  changed_by    TEXT NOT NULL,
  changed_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  reason        TEXT,
  metadata      JSONB
);

CREATE INDEX IF NOT EXISTS withdrawal_audit_log_withdrawal_idx
  ON public.withdrawal_audit_log (withdrawal_id, changed_at DESC);

ALTER TABLE public.withdrawal_audit_log ENABLE ROW LEVEL SECURITY;

-- Audit log is read by shop owners only via the parent withdrawal.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='withdrawal_audit_log_owner_read') THEN
    CREATE POLICY withdrawal_audit_log_owner_read ON public.withdrawal_audit_log
      FOR SELECT TO authenticated
      USING (withdrawal_id IN (
        SELECT wr.id
        FROM public.withdrawal_requests wr
        JOIN public.shops s ON s.id = wr.shop_id
        WHERE s.user_id = auth.uid()
      ));
  END IF;
END $$;

-- TODO (checklist 2.22 immutability): block UPDATE/DELETE on this table
-- even for service_role. Should be a trigger that raises on TG_OP IN
-- ('UPDATE','DELETE'). Left as-is here to match live behaviour.

COMMENT ON TABLE public.withdrawal_audit_log IS
  'Append-only audit trail for withdrawal_requests state transitions. NOT ENFORCED IMMUTABLE — checklist 2.22 gap.';

-- ─────────────────────────────────────────────────────────────────
-- withdrawal_requests — schema drift reconciliation
-- ─────────────────────────────────────────────────────────────────
-- The migration version of this table (in payment_schema.sql) is missing
-- columns that the live schema has. Add them idempotently so CI matches.
ALTER TABLE public.withdrawal_requests
  ADD COLUMN IF NOT EXISTS payment_method            TEXT,
  ADD COLUMN IF NOT EXISTS account_details           JSONB,
  ADD COLUMN IF NOT EXISTS processed_by              UUID,
  ADD COLUMN IF NOT EXISTS processed_at              TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rejection_reason          TEXT,
  ADD COLUMN IF NOT EXISTS notes                     TEXT,
  ADD COLUMN IF NOT EXISTS requested_by_ip           TEXT,
  ADD COLUMN IF NOT EXISTS requested_by_user_agent   TEXT;

-- The live schema lacks the `payment_provider` NOT NULL constraint that
-- the migration created. The RPC inserts payment_provider but the live
-- column may be nullable. Relax the constraint to match live, but flag.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='withdrawal_requests'
      AND column_name='payment_provider' AND is_nullable='NO'
  ) THEN
    ALTER TABLE public.withdrawal_requests
      ALTER COLUMN payment_provider DROP NOT NULL;
  END IF;
END $$;

COMMENT ON COLUMN public.withdrawal_requests.payment_method IS
  'DRIFT: live schema has this; create_withdrawal_request() does NOT populate it. Investigate before relying on it.';
