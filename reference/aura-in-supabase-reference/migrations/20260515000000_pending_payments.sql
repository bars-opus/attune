-- pending_payments: holds the full booking payload between payment intent
-- creation and webhook confirmation. The edge functions use service_role so
-- RLS is bypassed; the table is intentionally not readable by user clients.

CREATE TABLE IF NOT EXISTS pending_payments (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key  TEXT NOT NULL UNIQUE,
  shop_id          UUID NOT NULL,
  user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount           NUMERIC(10, 2) NOT NULL,
  payment_intent_id TEXT NOT NULL UNIQUE,
  payment_provider TEXT NOT NULL CHECK (payment_provider IN ('paystack', 'stripe')),
  status           TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'completed', 'failed', 'expired')),
  booking_data     JSONB NOT NULL,
  booking_id       UUID,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at       TIMESTAMPTZ NOT NULL,
  completed_at     TIMESTAMPTZ
);

-- Index for the most common lookup pattern (webhook + verify-payment)
CREATE INDEX IF NOT EXISTS pending_payments_payment_intent_id_idx
  ON pending_payments (payment_intent_id);

CREATE INDEX IF NOT EXISTS pending_payments_user_id_idx
  ON pending_payments (user_id, created_at DESC);

-- Enable RLS — all access goes through service_role (edge functions).
-- User clients must NOT be able to read or write this table.
ALTER TABLE pending_payments ENABLE ROW LEVEL SECURITY;
