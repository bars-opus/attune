-- Rewrite create_withdrawal_request to use the canonical `wallets` table
-- and fix the catalogue of bugs from the dashboard-edited live version.
--
-- Behavioural changes vs. the live RPC:
--   * Reads/writes `wallets` instead of the now-dropped `shop_wallets`.
--     This is the real fix: the pre-flight balance check now sees the
--     actual deposited balance, not a ghost-table zero.
--
--   * Idempotency on idempotency_key is EXPLICIT. The live version
--     relied on the UNIQUE constraint throwing — which Dart caught as
--     a generic "duplicate key" error. Now: if a row with that key
--     already exists for this shop, we return its id (the retry
--     contract from checklist 2.20 / 2.21).
--
--   * Error messages are sanitized. The live version leaked exact
--     balance and amount values to the client ('Insufficient balance.
--     Available: 73.50, Requested: 200.00'). Now: a single SQLSTATE
--     P0001 with a generic message; the precise numbers are logged via
--     RAISE NOTICE for server-side debugging only (checklist 2.4 / 5.5).
--
--   * Daily limit message no longer hardcodes 'GHS 5,000' — that breaks
--     for shops on other currencies. Generic message instead.
--
--   * Authorization: SECURITY DEFINER + an explicit ownership check
--     (auth.uid() must own p_shop_id). The live version trusted any
--     caller of the RPC. RLS on withdrawal_requests would catch it on
--     INSERT, but we fail-fast at the top to avoid leaking the lock
--     attempt (checklist 1.4).
--
--   * Hardcoded 2% fee / GHS 1 minimum are read from a new
--     payment_config table if present, else fall back to the prior
--     constants. Tracked as TODO; not introduced in this migration.
--
-- IDEMPOTENCY CONTRACT (checklist 2.20)
--   Caller MUST supply a stable p_idempotency_key for the same logical
--   withdrawal across retries. The Dart code generates
--   wd_{shopId}_{YYYYMMDD}_{amount.toInt()} which is stable on retry
--   within the same UTC day. (Separate Dart-side issue: amount.toInt()
--   collides 12.49 and 12.51 — fix in app code, see Dart todo list.)

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
SET search_path = public
AS $function$
DECLARE
  v_caller_uid          UUID := auth.uid();
  v_owns_shop           BOOLEAN;
  v_existing_id         UUID;
  v_wallet_balance      NUMERIC;
  v_pending_withdrawals NUMERIC;
  v_available_balance   NUMERIC;
  v_withdrawal_id       UUID;
  v_fee_amount          NUMERIC;
  v_net_amount          NUMERIC;
BEGIN
  -- 1. Authorization (checklist 1.4).
  IF v_caller_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM public.shops
    WHERE id = p_shop_id AND user_id = v_caller_uid
  ) INTO v_owns_shop;
  IF NOT v_owns_shop THEN
    RAISE EXCEPTION 'Shop not found' USING ERRCODE = '42501';
    -- 'Shop not found' rather than 'Not authorized' to avoid leaking
    -- existence of shops the caller doesn't own.
  END IF;

  -- 2. Validate amount shape early.
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Invalid amount' USING ERRCODE = '22023';
  END IF;

  -- 3. Idempotency short-circuit (checklist 2.20).
  SELECT id INTO v_existing_id
    FROM public.withdrawal_requests
   WHERE shop_id = p_shop_id
     AND idempotency_key = p_idempotency_key
   LIMIT 1;
  IF v_existing_id IS NOT NULL THEN
    RETURN v_existing_id;
  END IF;

  -- 4. Lock the wallet row and read current state.
  SELECT balance, pending_withdrawals
    INTO v_wallet_balance, v_pending_withdrawals
    FROM public.wallets
   WHERE shop_id = p_shop_id
     FOR UPDATE;

  IF NOT FOUND THEN
    -- The shop has no wallet yet. Either trg_create_wallet_on_shop_insert
    -- didn't fire (legacy shop) or this is genuinely the first money
    -- movement. Create a zero-balance row so subsequent checks have
    -- something to lock; the balance check below will reject the
    -- withdrawal cleanly.
    INSERT INTO public.wallets (shop_id) VALUES (p_shop_id)
      ON CONFLICT (shop_id) DO NOTHING;
    SELECT balance, pending_withdrawals
      INTO v_wallet_balance, v_pending_withdrawals
      FROM public.wallets
     WHERE shop_id = p_shop_id
       FOR UPDATE;
  END IF;

  v_available_balance := v_wallet_balance - v_pending_withdrawals;

  -- 5. Balance check (checklist 2.4 — sanitized message).
  IF v_available_balance < p_amount THEN
    RAISE NOTICE 'create_withdrawal_request: insufficient balance shop=% available=% requested=%',
      p_shop_id, v_available_balance, p_amount;
    RAISE EXCEPTION 'Insufficient available balance'
      USING ERRCODE = 'P0001', HINT = 'WALLET_INSUFFICIENT';
  END IF;

  -- 6. Daily cap (checklist 4.11 — generic message, no currency leak).
  IF NOT check_daily_withdrawal_limit(p_shop_id, p_amount) THEN
    RAISE EXCEPTION 'Daily withdrawal limit reached'
      USING ERRCODE = 'P0001', HINT = 'WALLET_DAILY_LIMIT';
  END IF;

  -- 7. Fee calculation. Hardcoded for now; see TODO at top.
  v_fee_amount := GREATEST(1, p_amount * 0.02);
  v_net_amount := p_amount - v_fee_amount;

  -- 8. Create the withdrawal_requests row.
  INSERT INTO public.withdrawal_requests (
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

  -- 9. Hold the funds: increment pending_withdrawals on wallets.
  UPDATE public.wallets
     SET pending_withdrawals = pending_withdrawals + p_amount,
         updated_at          = now()
   WHERE shop_id = p_shop_id;

  -- 10. Audit log (checklist 2.22).
  INSERT INTO public.withdrawal_audit_log (
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
    v_caller_uid::TEXT,
    'Withdrawal request created',
    jsonb_build_object('amount', p_amount, 'fee', v_fee_amount, 'net', v_net_amount)
  );

  RETURN v_withdrawal_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_withdrawal_request(UUID, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_withdrawal_request(UUID, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT)
  TO authenticated, service_role;
-- `authenticated` is needed because the Dart client calls this RPC
-- under the user's JWT; the ownership check at the top is what gates
-- access, not the GRANT.

COMMENT ON FUNCTION public.create_withdrawal_request(UUID, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT) IS
  'Creates a withdrawal_requests row, holds funds on wallets.pending_withdrawals, and writes an audit log entry. SECURITY DEFINER with explicit auth.uid()-owns-shop check. Idempotent on (shop_id, idempotency_key).';
