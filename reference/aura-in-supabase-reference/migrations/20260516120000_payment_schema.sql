-- ============================================================
-- Payment / Wallet schema (idempotent, source-of-truth)
-- ============================================================
--
-- These tables exist in production but were created out-of-band
-- (no migration file). This migration captures the canonical
-- shape so future environments and CI can replicate it. It uses
-- IF NOT EXISTS / IF EXISTS everywhere so re-running against a
-- live database is safe.
--
-- See PAYMENT_ENGINE.md for the integration guide.
-- ============================================================

-- ── payment_settings ────────────────────────────────────────
-- One row per shop. Stores the provider-specific identifiers
-- needed to route transfers and verify the connection.

CREATE TABLE IF NOT EXISTS payment_settings (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id                     UUID NOT NULL UNIQUE REFERENCES shops(id) ON DELETE CASCADE,
  payment_provider            TEXT CHECK (payment_provider IN ('paystack','stripe','none')),
  paystack_subaccount_code    TEXT,
  paystack_recipient_id       TEXT,
  paystack_verified           BOOLEAN NOT NULL DEFAULT false,
  stripe_account_id           TEXT,
  stripe_verified             BOOLEAN NOT NULL DEFAULT false,
  payout_schedule             TEXT CHECK (payout_schedule IN ('daily','weekly','biweekly','monthly')),
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS payment_settings_shop_id_idx ON payment_settings (shop_id);

ALTER TABLE payment_settings ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'payment_settings_owner_read'
  ) THEN
    CREATE POLICY payment_settings_owner_read ON payment_settings
      FOR SELECT TO authenticated
      USING (shop_id IN (SELECT id FROM shops WHERE user_id = auth.uid()));
  END IF;
END $$;

-- Direct writes blocked — edge functions (service_role) handle all mutations.

-- ── wallets ─────────────────────────────────────────────────
-- One row per shop. Auto-created on first transaction.

CREATE TABLE IF NOT EXISTS wallets (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id               UUID NOT NULL UNIQUE REFERENCES shops(id) ON DELETE CASCADE,
  balance               NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  total_earned          NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_earned >= 0),
  total_withdrawn       NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_withdrawn >= 0),
  pending_withdrawals   NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (pending_withdrawals >= 0),
  currency              TEXT NOT NULL DEFAULT 'GHS',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS wallets_shop_id_idx ON wallets (shop_id);

ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'wallets_owner_read'
  ) THEN
    CREATE POLICY wallets_owner_read ON wallets
      FOR SELECT TO authenticated
      USING (shop_id IN (SELECT id FROM shops WHERE user_id = auth.uid()));
  END IF;
END $$;

-- ── wallet_transactions ─────────────────────────────────────
-- Append-only ledger. Never UPDATE/DELETE; reverse via opposing rows.

CREATE TABLE IF NOT EXISTS wallet_transactions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id         UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  amount          NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  type            TEXT NOT NULL CHECK (type IN ('deposit','withdrawal','refund','adjustment')),
  booking_id      UUID,
  description     TEXT,
  reference       TEXT,
  metadata        JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS wallet_transactions_shop_recent_idx
  ON wallet_transactions (shop_id, created_at DESC);

CREATE INDEX IF NOT EXISTS wallet_transactions_reference_idx
  ON wallet_transactions (reference)
  WHERE reference IS NOT NULL;

ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'wallet_transactions_owner_read'
  ) THEN
    CREATE POLICY wallet_transactions_owner_read ON wallet_transactions
      FOR SELECT TO authenticated
      USING (shop_id IN (SELECT id FROM shops WHERE user_id = auth.uid()));
  END IF;
END $$;

-- ── withdrawal_requests ─────────────────────────────────────
-- Tracks shop payout requests from intake through provider settlement.

CREATE TABLE IF NOT EXISTS withdrawal_requests (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id                 UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  amount                  NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  fee_amount              NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (fee_amount >= 0),
  net_amount              NUMERIC(12,2) NOT NULL CHECK (net_amount > 0),
  status                  TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending','processing','completed','failed','refunded')),
  payment_provider        TEXT NOT NULL CHECK (payment_provider IN ('paystack','stripe')),
  transfer_recipient_id   TEXT NOT NULL,
  provider_transfer_id    TEXT,
  failure_reason          TEXT,
  idempotency_key         TEXT NOT NULL UNIQUE,
  requested_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  processing_started_at   TIMESTAMPTZ,
  completed_at            TIMESTAMPTZ,
  failed_at               TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS withdrawal_requests_shop_recent_idx
  ON withdrawal_requests (shop_id, created_at DESC);

CREATE INDEX IF NOT EXISTS withdrawal_requests_status_idx
  ON withdrawal_requests (status, created_at DESC)
  WHERE status IN ('pending','processing');

ALTER TABLE withdrawal_requests ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'withdrawal_requests_owner_read'
  ) THEN
    CREATE POLICY withdrawal_requests_owner_read ON withdrawal_requests
      FOR SELECT TO authenticated
      USING (shop_id IN (SELECT id FROM shops WHERE user_id = auth.uid()));
  END IF;
END $$;

-- ── updated_at trigger (shared) ─────────────────────────────

CREATE OR REPLACE FUNCTION payment_touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payment_settings_touch     ON payment_settings;
DROP TRIGGER IF EXISTS trg_wallets_touch              ON wallets;
DROP TRIGGER IF EXISTS trg_withdrawal_requests_touch  ON withdrawal_requests;

CREATE TRIGGER trg_payment_settings_touch    BEFORE UPDATE ON payment_settings    FOR EACH ROW EXECUTE FUNCTION payment_touch_updated_at();
CREATE TRIGGER trg_wallets_touch             BEFORE UPDATE ON wallets             FOR EACH ROW EXECUTE FUNCTION payment_touch_updated_at();
CREATE TRIGGER trg_withdrawal_requests_touch BEFORE UPDATE ON withdrawal_requests FOR EACH ROW EXECUTE FUNCTION payment_touch_updated_at();
