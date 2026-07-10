-- Backfill: check_daily_withdrawal_limit(p_shop_id, p_amount) -> BOOLEAN
--
-- STATUS: REVERSE-ENGINEERED, NOT LIFTED FROM PROD.
--
-- The live database is MISSING this function. It is referenced by
-- create_withdrawal_request() with:
--     IF NOT check_daily_withdrawal_limit(p_shop_id, p_amount) THEN
--         RAISE EXCEPTION 'Daily withdrawal limit of GHS 5,000 exceeded';
--
-- That means every call to create_withdrawal_request currently raises
--     ERROR: function check_daily_withdrawal_limit(uuid, numeric) does not exist
-- before it can hit the `IF NOT … THEN` guard. The user-facing Dart code
-- catches this and surfaces it as "Failed to request withdrawal: …" —
-- which is why the audit found stuck-pending withdrawals & a dead-letter
-- banner in the wallet UI. The retry queue (20260521000000) is what
-- patches over this failure.
--
-- This stub implements the 1-withdrawal-per-day-per-shop semantics that
-- the surrounding code expects (see shop_wallets.last_withdrawal_date /
-- total_withdrawn_today columns + the error message itself). Review
-- with product before deploying — limits should be config, not code.
--
-- Checklist gaps this backfill flags but does NOT fix:
--   1.2  Timeouts — none on the RPC; will hold a row lock indefinitely
--        if the caller stalls.
--   2.19 Money as numeric — OK (DECIMAL in/out).
--   3.3  Index — relies on shop_wallets PK; fine.
--   4.11 Configurable thresholds — limit is hardcoded GHS 5,000.
--        Should be in shop_settings or a payment_config table.

CREATE OR REPLACE FUNCTION public.check_daily_withdrawal_limit(
  p_shop_id UUID,
  p_amount  NUMERIC
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_today              DATE := CURRENT_DATE;
  v_last_date          DATE;
  v_total_today        NUMERIC;
  v_daily_limit        NUMERIC := 5000;  -- TODO: move to config
BEGIN
  SELECT last_withdrawal_date, total_withdrawn_today
    INTO v_last_date, v_total_today
  FROM public.shop_wallets
  WHERE shop_id = p_shop_id
  FOR UPDATE;

  IF NOT FOUND THEN
    -- No wallet row yet; first withdrawal counts.
    RETURN p_amount <= v_daily_limit;
  END IF;

  -- Reset counter on a new day.
  IF v_last_date IS NULL OR v_last_date < v_today THEN
    UPDATE public.shop_wallets
       SET last_withdrawal_date  = v_today,
           total_withdrawn_today = p_amount
     WHERE shop_id = p_shop_id;
    RETURN p_amount <= v_daily_limit;
  END IF;

  -- Same day: enforce cumulative cap.
  IF (v_total_today + p_amount) > v_daily_limit THEN
    RETURN FALSE;
  END IF;

  UPDATE public.shop_wallets
     SET total_withdrawn_today = v_total_today + p_amount
   WHERE shop_id = p_shop_id;
  RETURN TRUE;
END;
$function$;

REVOKE ALL ON FUNCTION public.check_daily_withdrawal_limit(UUID, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_daily_withdrawal_limit(UUID, NUMERIC) TO service_role;

COMMENT ON FUNCTION public.check_daily_withdrawal_limit(UUID, NUMERIC) IS
  'Returns TRUE if the requested withdrawal fits inside the per-shop daily cap (default GHS 5000). Mutates shop_wallets counters as a side effect. SECURITY DEFINER. REVERSE-ENGINEERED — verify against product spec before relying on this.';
