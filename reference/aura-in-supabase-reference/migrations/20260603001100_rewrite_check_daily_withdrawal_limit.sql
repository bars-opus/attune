-- Rewrite check_daily_withdrawal_limit to read/write the canonical
-- `wallets` table (after the shop_wallets consolidation in 20260603001000).
--
-- Behavioural contract (UNCHANGED from the reverse-engineered stub):
--   * Returns TRUE if the requested withdrawal fits inside the per-shop
--     daily cap (5_000 in the wallet's currency).
--   * Mutates wallets.last_withdrawal_date + wallets.total_withdrawn_today
--     as a side effect — so this MUST be called inside the same
--     transaction as the withdrawal_requests INSERT, or the counter
--     drifts on failures.
--   * SECURITY DEFINER — callable only from service_role-context
--     functions (create_withdrawal_request).
--
-- Checklist mapping (delta vs. 20260603000200):
--   1.4  Authz — SECURITY DEFINER + REVOKE/GRANT to service_role only ✅
--   1.6  Concurrency — SELECT … FOR UPDATE serializes per-shop ✅
--   2.4  Error messages — no exceptions raised, returns boolean ✅
--   2.19 Money — NUMERIC throughout ✅
--   4.11 Configurable threshold — TODO: move daily_limit to payment_config
--        or shop_settings. For now hardcoded to match prior behaviour.

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
  v_today        DATE := CURRENT_DATE;
  v_last_date    DATE;
  v_total_today  NUMERIC;
  v_daily_limit  NUMERIC := 5000;  -- TODO: source from shop_settings or payment_config
BEGIN
  SELECT last_withdrawal_date, total_withdrawn_today
    INTO v_last_date, v_total_today
  FROM public.wallets
  WHERE shop_id = p_shop_id
  FOR UPDATE;

  IF NOT FOUND THEN
    -- No wallet row → no deposits yet → caller (create_withdrawal_request)
    -- will fail its own balance check. Return TRUE so the daily-cap step
    -- isn't the one that errors out; caller decides what message to surface.
    RETURN p_amount <= v_daily_limit;
  END IF;

  -- New day → reset and apply.
  IF v_last_date IS NULL OR v_last_date < v_today THEN
    IF p_amount > v_daily_limit THEN
      RETURN FALSE;
    END IF;
    UPDATE public.wallets
       SET last_withdrawal_date  = v_today,
           total_withdrawn_today = p_amount,
           updated_at            = now()
     WHERE shop_id = p_shop_id;
    RETURN TRUE;
  END IF;

  -- Same day → enforce cumulative cap.
  IF (v_total_today + p_amount) > v_daily_limit THEN
    RETURN FALSE;
  END IF;

  UPDATE public.wallets
     SET total_withdrawn_today = v_total_today + p_amount,
         updated_at            = now()
   WHERE shop_id = p_shop_id;
  RETURN TRUE;
END;
$function$;

REVOKE ALL ON FUNCTION public.check_daily_withdrawal_limit(UUID, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_daily_withdrawal_limit(UUID, NUMERIC) TO service_role;

COMMENT ON FUNCTION public.check_daily_withdrawal_limit(UUID, NUMERIC) IS
  'Returns TRUE if a withdrawal of p_amount fits inside the per-shop daily cap (5000). Mutates wallets.last_withdrawal_date and wallets.total_withdrawn_today as side effects. SECURITY DEFINER. Called by create_withdrawal_request inside the same transaction.';
