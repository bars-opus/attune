-- Canonical add_wallet_transaction RPC.
--
-- An earlier version (added via Supabase dashboard) inserted into
-- wallet_transactions but did NOT update wallets.balance, so the
-- WalletBalanceCard never reflected new deposits even though the
-- transaction list below it showed them. This redefinition does both
-- atomically and is idempotent on `reference` so webhook replays
-- (paystack-webhook + stripe-webhook) cannot double-credit.
--
-- Drop the old definition first because CREATE OR REPLACE FUNCTION
-- can't change the return type, and the dashboard-edited version may
-- have returned a different shape.

DROP FUNCTION IF EXISTS add_wallet_transaction(UUID, NUMERIC, TEXT, UUID, TEXT, TEXT, JSONB);
DROP FUNCTION IF EXISTS add_wallet_transaction(UUID, NUMERIC, TEXT, UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS add_wallet_transaction(UUID, NUMERIC, TEXT, UUID, TEXT);

CREATE OR REPLACE FUNCTION add_wallet_transaction(
  p_shop_id     UUID,
  p_amount      NUMERIC,
  p_type        TEXT,
  p_booking_id  UUID DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_reference   TEXT DEFAULT NULL,
  p_metadata    JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_id   UUID;
  v_transaction_id UUID;
  v_balance_after NUMERIC;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'amount must be positive (use type=withdrawal for debits)';
  END IF;

  IF p_type NOT IN ('deposit', 'withdrawal', 'refund', 'adjustment') THEN
    RAISE EXCEPTION 'invalid transaction type: %', p_type;
  END IF;

  -- Idempotency: if a transaction with this reference already exists for
  -- this shop, short-circuit and return its id. Both Paystack and Stripe
  -- replay events; without this, every replay would re-credit the wallet.
  IF p_reference IS NOT NULL THEN
    SELECT id INTO v_existing_id
    FROM wallet_transactions
    WHERE shop_id = p_shop_id AND reference = p_reference
    LIMIT 1;
    IF v_existing_id IS NOT NULL THEN
      RETURN v_existing_id;
    END IF;
  END IF;

  -- Ensure the wallet exists. The trg_create_wallet_on_shop_insert trigger
  -- (see 20260602180000) covers new shops, but legacy shops created before
  -- that trigger landed may not have one — backfill on first transaction.
  INSERT INTO wallets (shop_id) VALUES (p_shop_id)
    ON CONFLICT (shop_id) DO NOTHING;

  -- Atomic balance update. Lock the wallet row so concurrent calls
  -- serialize. Compute the post-update balance for the audit field.
  UPDATE wallets
     SET balance =
           CASE p_type
             WHEN 'withdrawal' THEN balance - p_amount
             ELSE balance + p_amount
           END,
         total_earned =
           CASE p_type
             WHEN 'deposit'    THEN total_earned + p_amount
             WHEN 'refund'     THEN total_earned + p_amount
             WHEN 'adjustment' THEN total_earned + p_amount
             ELSE total_earned
           END,
         total_withdrawn =
           CASE p_type
             WHEN 'withdrawal' THEN total_withdrawn + p_amount
             ELSE total_withdrawn
           END,
         updated_at = NOW()
   WHERE shop_id = p_shop_id
   RETURNING balance INTO v_balance_after;

  INSERT INTO wallet_transactions (
    shop_id, amount, type, booking_id, description, reference, metadata
  ) VALUES (
    p_shop_id, p_amount, p_type, p_booking_id, p_description, p_reference, p_metadata
  )
  RETURNING id INTO v_transaction_id;

  RETURN v_transaction_id;
END;
$$;

REVOKE ALL ON FUNCTION add_wallet_transaction(UUID, NUMERIC, TEXT, UUID, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION add_wallet_transaction(UUID, NUMERIC, TEXT, UUID, TEXT, TEXT, JSONB) TO service_role;

COMMENT ON FUNCTION add_wallet_transaction IS
  'Atomically insert a wallet_transactions row and update the corresponding wallets totals. Idempotent on (shop_id, reference). All booking webhooks call this; balance integrity depends on it.';

-- Backfill: rebuild wallets.balance / total_earned / total_withdrawn for
-- every shop from the existing wallet_transactions ledger. Covers all
-- bookings made before this fix where the balance never bumped.
WITH agg AS (
  SELECT
    shop_id,
    COALESCE(SUM(CASE
      WHEN type = 'withdrawal' THEN -amount
      ELSE amount
    END), 0) AS new_balance,
    COALESCE(SUM(CASE
      WHEN type IN ('deposit','refund','adjustment') THEN amount
      ELSE 0
    END), 0) AS new_earned,
    COALESCE(SUM(CASE
      WHEN type = 'withdrawal' THEN amount
      ELSE 0
    END), 0) AS new_withdrawn
  FROM wallet_transactions
  GROUP BY shop_id
)
UPDATE wallets w
   SET balance         = GREATEST(agg.new_balance, 0),
       total_earned    = agg.new_earned,
       total_withdrawn = agg.new_withdrawn,
       updated_at      = NOW()
  FROM agg
 WHERE w.shop_id = agg.shop_id
   AND (w.balance         IS DISTINCT FROM GREATEST(agg.new_balance, 0)
     OR w.total_earned    IS DISTINCT FROM agg.new_earned
     OR w.total_withdrawn IS DISTINCT FROM agg.new_withdrawn);
