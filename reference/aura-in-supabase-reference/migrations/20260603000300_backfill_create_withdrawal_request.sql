-- Backfill: create_withdrawal_request — lifted byte-for-byte from live DB.
--
-- ─────────────────────────────────────────────────────────────────
-- WARNING: This RPC has known bugs that this migration intentionally
-- preserves. Do NOT "fix while backfilling" — that changes prod
-- behaviour silently. Fixes belong in a follow-up migration after the
-- audit decisions are made.
-- ─────────────────────────────────────────────────────────────────
--
-- Known issues against checklist v3.1:
--
--  - 2.19 (money correctness): uses DECIMAL/NUMERIC — OK.
--
--  - 1.10 (compensating tx): the wallet table read here is
--    public.shop_wallets, but deposits land in public.wallets via
--    add_wallet_transaction(). The "available balance" check is
--    therefore against a stale or empty `shop_wallets.balance`.
--    See 20260603000100 for the schema-drift note.
--
--  - 2.4 (error messages): RAISE EXCEPTION embeds the actual
--    available + requested amounts ('Insufficient balance.
--    Available: X, Requested: Y'). Supabase forwards this to the
--    client, leaking exact balance to whoever can call the RPC.
--    Tighten to a generic message + log the details server-side.
--
--  - 4.11 (configurable thresholds): GHS 5,000 / 2% fee / GHS 1 min
--    are all hardcoded in code paths. Move to config.
--
--  - 1.6 (concurrency): SELECT … FOR UPDATE on shop_wallets row
--    serialises concurrent withdrawals per shop. ✅
--
--  - 2.21 (webhook/event idempotency): idempotency_key is INSERTed
--    into withdrawal_requests, which has a UNIQUE constraint on
--    that column (per the 20260516120000 migration). A retry with
--    the same key surfaces as a unique-violation PostgrestException,
--    which the Dart repository remaps to a WalletException. The
--    RPC itself does NOT short-circuit on idempotency_key — it
--    relies on the constraint. Consider an explicit
--    `IF EXISTS … RETURN existing_id` to make the retry contract
--    explicit (cheaper, clearer, no constraint-error round-trip).
--
--  - 6.13 (documentation): no inline intent comment in live source.
--    Added the block at the top of this file instead.

CREATE OR REPLACE FUNCTION public.create_withdrawal_request(
  p_shop_id               UUID,
  p_amount                NUMERIC,
  p_payment_provider      TEXT,
  p_transfer_recipient_id TEXT,
  p_idempotency_key       TEXT,
  p_ip_address            TEXT DEFAULT NULL,
  p_user_agent            TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_wallet_balance       DECIMAL;
  v_pending_withdrawals  DECIMAL;
  v_available_balance    DECIMAL;
  v_withdrawal_id        UUID;
  v_fee_amount           DECIMAL;
  v_net_amount           DECIMAL;
BEGIN
  -- 1. Get current wallet state
  SELECT balance, pending_withdrawals
    INTO v_wallet_balance, v_pending_withdrawals
  FROM shop_wallets
  WHERE shop_id = p_shop_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Wallet not found for shop %', p_shop_id;
  END IF;

  -- 2. Calculate available balance
  v_available_balance := v_wallet_balance - v_pending_withdrawals;

  -- 3. Validate balance
  IF v_available_balance < p_amount THEN
    RAISE EXCEPTION 'Insufficient balance. Available: %, Requested: %',
      v_available_balance, p_amount;
  END IF;

  -- 4. Check daily limit
  IF NOT check_daily_withdrawal_limit(p_shop_id, p_amount) THEN
    RAISE EXCEPTION 'Daily withdrawal limit of GHS 5,000 exceeded';
  END IF;

  -- 5. Calculate fees (2% fee, minimum GHS 1)
  v_fee_amount := GREATEST(1, p_amount * 0.02);
  v_net_amount := p_amount - v_fee_amount;

  -- 6. Create withdrawal request
  INSERT INTO withdrawal_requests (
    shop_id,
    amount,
    payment_provider,
    transfer_recipient_id,
    idempotency_key,
    requested_by_ip,
    requested_by_user_agent,
    fee_amount,
    net_amount,
    status
  ) VALUES (
    p_shop_id,
    p_amount,
    p_payment_provider,
    p_transfer_recipient_id,
    p_idempotency_key,
    p_ip_address,
    p_user_agent,
    v_fee_amount,
    v_net_amount,
    'pending'
  )
  RETURNING id INTO v_withdrawal_id;

  -- 7. Update wallet with pending withdrawal
  UPDATE shop_wallets
     SET pending_withdrawals = pending_withdrawals + p_amount,
         updated_at = NOW()
   WHERE shop_id = p_shop_id;

  -- 8. Create audit log entry
  INSERT INTO withdrawal_audit_log (
    withdrawal_id,
    from_status,
    to_status,
    changed_by,
    reason,
    metadata
  ) VALUES (
    v_withdrawal_id,
    NULL,
    'pending',
    p_shop_id::TEXT,
    'Withdrawal request created',
    jsonb_build_object('amount', p_amount, 'fee', v_fee_amount, 'net', v_net_amount)
  );

  RETURN v_withdrawal_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_withdrawal_request(UUID, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_withdrawal_request(UUID, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION public.create_withdrawal_request(UUID, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT) IS
  'Creates a withdrawal_requests row + audit log entry, holds funds on shop_wallets.pending_withdrawals. SECURITY DEFINER. KNOWN BUGS: reads shop_wallets (deposits go to wallets), leaks exact balance in error message, hardcoded fee/limit. See 20260603000300 header.';
