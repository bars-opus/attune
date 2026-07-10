-- redeem_promotion(p_promotion_id UUID, p_booking_id UUID, p_user_id UUID, p_discount_amount NUMERIC) -> UUID
--
-- Atomic counter + ledger replacement for the two-step pattern that
-- exists today (UPDATE promotions.usage_count via RPC, then INSERT
-- into promotion_redemptions). If the old INSERT failed after the
-- counter bump, the counter was over-counted relative to the ledger.
-- This RPC closes the compensating-tx gap (checklist 1.10) by doing
-- both inside one transaction with race-free idempotency.
--
-- Race-free idempotency mechanism:
--   INSERT ... ON CONFLICT (promotion_id, booking_id) DO NOTHING
--   RETURNING id
-- The UNIQUE (promotion_id, booking_id) constraint added in
-- 20260604000100_backfill_tools_screen_drift.sql guarantees that two
-- concurrent inserts collapse to one row. We then bump the counter
-- ONLY when the insert produced a row, so the counter and the ledger
-- stay perfectly in sync.
--
-- Hardening template parity with supabase/migrations/20260603001500_harden_dashboard_rpcs.sql.
--
-- IMPORTANT — ordering is load-bearing. DO NOT MOVE the discount-amount
-- range check above the authz gate. Authz-first matches the template
-- and prevents a non-owner from distinguishing "not your promo" from
-- "your promo, bad amount" via parameter probing.

CREATE OR REPLACE FUNCTION public.redeem_promotion(
  p_promotion_id    UUID,
  p_booking_id      UUID,
  p_user_id         UUID,
  p_discount_amount NUMERIC
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_owns_promo    BOOLEAN;
  v_promo_row     RECORD;
  v_redemption_id UUID;
BEGIN
  -- (1) Input-shape validation (NULL guards).
  -- Shape/type validation is allowed BEFORE authz because it has no
  -- side effect and prevents NULLs from flowing into the EXISTS check
  -- and masquerading as authz failures.
  IF p_promotion_id IS NULL OR p_booking_id IS NULL THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'NULL_NOT_ALLOWED';
  END IF;

  -- (2) Authz FIRST: caller must own the shop that owns this promotion.
  -- Ordering matches the hardening template.
  SELECT EXISTS (
    SELECT 1
    FROM public.promotions p
    JOIN public.shops s ON s.id = p.shop_id
    WHERE p.id = p_promotion_id AND s.user_id = auth.uid()
  ) INTO v_owns_promo;
  IF NOT v_owns_promo THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = '42501';
  END IF;

  -- (3) Range validation AFTER authz (checklist 2.1).
  IF p_discount_amount IS NULL OR p_discount_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_amount'
      USING ERRCODE = '22023', HINT = 'AMOUNT_MUST_BE_POSITIVE';
  END IF;

  -- (4) Lock the promo row and check the usage_limit.
  SELECT * INTO v_promo_row
  FROM public.promotions
  WHERE id = p_promotion_id
  FOR UPDATE;
  IF NOT FOUND THEN
    -- Caught after authz so v_owns_promo proved the row existed —
    -- this branch is defense-in-depth against a concurrent delete.
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_promo_row.usage_limit IS NOT NULL
     AND v_promo_row.usage_count >= v_promo_row.usage_limit THEN
    RAISE EXCEPTION 'limit_reached'
      USING ERRCODE = 'P0001', HINT = 'PROMO_LIMIT_REACHED';
  END IF;

  -- (5) Idempotent insert. The UNIQUE constraint on
  -- (promotion_id, booking_id) from 20260604000100 collapses
  -- concurrent retries to one row.
  INSERT INTO public.promotion_redemptions (
    promotion_id, booking_id, user_id, discount_amount
  ) VALUES (
    p_promotion_id, p_booking_id, p_user_id, p_discount_amount
  )
  ON CONFLICT (promotion_id, booking_id) DO NOTHING
  RETURNING id INTO v_redemption_id;

  -- (6) Bump the counter only on a new row. Idempotent return for
  -- the duplicate path.
  IF v_redemption_id IS NOT NULL THEN
    UPDATE public.promotions
       SET usage_count = usage_count + 1,
           updated_at  = now()
     WHERE id = p_promotion_id;
  ELSE
    SELECT id INTO v_redemption_id
    FROM public.promotion_redemptions
    WHERE promotion_id = p_promotion_id AND booking_id = p_booking_id;
  END IF;

  RETURN v_redemption_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.redeem_promotion(UUID, UUID, UUID, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.redeem_promotion(UUID, UUID, UUID, NUMERIC) TO authenticated;

COMMENT ON FUNCTION public.redeem_promotion(UUID, UUID, UUID, NUMERIC) IS
  'Atomic promotion redemption: locks the promotion row, validates limit, idempotently inserts the redemption ledger row (UNIQUE on (promotion_id, booking_id)), and bumps the usage counter only on a new row. SECURITY DEFINER with promotions->shops.user_id=auth.uid() authz gate. O(1) - two index lookups + one insert + one conditional update.';
