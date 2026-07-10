-- Phase 13 — validate_and_apply_promo
--
-- The hot path for booking checkout. READ-ONLY: no redemption row
-- written until payment success (webhook calls redeem_promotion later).
--
-- Two invocation modes:
--   * Auto-apply  (p_code = NULL or empty): finds the highest-discount
--     unredeemed silent code for this (shop, client). Returns empty if
--     none. Used by booking_confirmation_screen on mount.
--   * Manual entry (p_code = TEXT): case-insensitive exact lookup +
--     all eligibility checks. Used when the client taps "Apply" on a
--     typed code.
--
-- Returns TABLE(promotion_id, code, amount_off, new_total, source).
-- Empty result = no auto-apply match. Eligibility failures raise
-- 22023 with HINT codes for typed-exception mapping in the Dart layer.
--
-- Discount math is server-authoritative; client treats amount_off and
-- new_total as opaque (no client-side re-derivation).

CREATE OR REPLACE FUNCTION public.validate_and_apply_promo(
  p_shop_id          UUID,
  p_code             TEXT,
  p_user_id          UUID,
  p_guest_profile_id UUID,
  p_booking_total    NUMERIC,
  p_service_ids      UUID[] DEFAULT NULL
) RETURNS TABLE (
  promotion_id  UUID,
  code          TEXT,
  amount_off    NUMERIC,
  new_total     NUMERIC,
  source        TEXT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $function$
DECLARE
  v_promo        RECORD;
  v_redeem_count INT;
  v_amount_off   NUMERIC;
BEGIN
  -- NULL shape validation (no side effects).
  IF p_shop_id IS NULL OR p_booking_total IS NULL THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'SHOP_OR_TOTAL_NULL';
  END IF;
  IF p_user_id IS NULL AND p_guest_profile_id IS NULL THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'CALLER_IDENTITY_REQUIRED';
  END IF;
  IF p_user_id IS NOT NULL AND p_guest_profile_id IS NOT NULL THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'AT_MOST_ONE_OF_USER_OR_GUEST';
  END IF;

  -- Branch: auto-apply silent code vs. manual entry.
  IF p_code IS NULL OR length(trim(p_code)) = 0 THEN
    -- Auto-apply path. Pick highest-discount silent code for this
    -- (shop, client). Tiebreak: sooner-expiring valid_to (protects
    -- the recovery code from being stranded while loyalty sits).
    SELECT p.id, p.code, p.discount_type, p.discount_value, p.valid_to, p.source
    INTO v_promo
    FROM public.promotions p
    WHERE p.shop_id = p_shop_id
      AND p.source IN ('loyalty','recovery')
      AND p.archived_at IS NULL
      AND (p.valid_to IS NULL OR p.valid_to > now())
      AND COALESCE(p.target_user_id, p.target_guest_profile_id)
          = COALESCE(p_user_id, p_guest_profile_id)
      AND NOT EXISTS (
        SELECT 1 FROM public.promotion_redemptions r
        WHERE r.promotion_id = p.id
      )
    ORDER BY
      CASE WHEN p.discount_type = 'percentage'
           THEN LEAST(p_booking_total * p.discount_value / 100.0, p_booking_total)
           WHEN p.discount_type = 'fixed'
           THEN LEAST(p.discount_value, p_booking_total)
           ELSE 0
      END DESC,
      p.valid_to ASC NULLS LAST
    LIMIT 1;

    IF NOT FOUND THEN
      RETURN;  -- empty result; no auto-apply match.
    END IF;
  ELSE
    -- Manual entry. Case-insensitive exact lookup; full eligibility chain.
    SELECT p.id, p.code, p.discount_type, p.discount_value,
           p.valid_from, p.valid_to,
           p.usage_limit, p.usage_count, p.per_client_max, p.min_booking_amount,
           p.service_restriction, p.source,
           p.target_user_id, p.target_guest_profile_id,
           p.is_active, p.archived_at
    INTO v_promo
    FROM public.promotions p
    WHERE p.shop_id = p_shop_id
      AND UPPER(p.code) = UPPER(trim(p_code))
      AND p.archived_at IS NULL;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'not_found'
        USING ERRCODE = '42501', HINT = 'CODE_NOT_FOUND';
    END IF;

    IF v_promo.is_active IS FALSE THEN
      RAISE EXCEPTION 'not_found'
        USING ERRCODE = '42501', HINT = 'CODE_NOT_FOUND';
    END IF;

    -- Validity window.
    IF (v_promo.valid_from IS NOT NULL AND v_promo.valid_from > now())
       OR (v_promo.valid_to IS NOT NULL AND v_promo.valid_to <= now()) THEN
      RAISE EXCEPTION 'invalid_input'
        USING ERRCODE = '22023', HINT = 'CODE_EXPIRED';
    END IF;

    -- Global usage cap (counts redemptions across all clients).
    IF v_promo.usage_limit IS NOT NULL
       AND COALESCE(v_promo.usage_count, 0) >= v_promo.usage_limit THEN
      RAISE EXCEPTION 'invalid_input'
        USING ERRCODE = '22023', HINT = 'CODE_LIMIT_REACHED';
    END IF;

    -- Per-client cap.
    SELECT COUNT(*) INTO v_redeem_count
    FROM public.promotion_redemptions r
    WHERE r.promotion_id = v_promo.id
      AND (
        (p_user_id IS NOT NULL AND r.user_id = p_user_id) OR
        (p_guest_profile_id IS NOT NULL AND r.guest_profile_id = p_guest_profile_id)
      );
    IF v_redeem_count >= v_promo.per_client_max THEN
      RAISE EXCEPTION 'invalid_input'
        USING ERRCODE = '22023', HINT = 'CODE_PER_CLIENT_MAX';
    END IF;

    -- Min booking amount.
    IF v_promo.min_booking_amount IS NOT NULL
       AND p_booking_total < v_promo.min_booking_amount THEN
      RAISE EXCEPTION 'invalid_input'
        USING ERRCODE = '22023', HINT = 'CODE_MIN_AMOUNT_NOT_MET';
    END IF;

    -- Service restriction: at least one booking service must overlap
    -- with the code's restriction array.
    IF v_promo.service_restriction IS NOT NULL
       AND array_length(v_promo.service_restriction, 1) > 0 THEN
      IF p_service_ids IS NULL OR NOT (p_service_ids && v_promo.service_restriction) THEN
        RAISE EXCEPTION 'invalid_input'
          USING ERRCODE = '22023', HINT = 'CODE_SERVICE_NOT_ELIGIBLE';
      END IF;
    END IF;

    -- Wrong-client guard for silent codes that someone tries to type
    -- manually (or that they shared with someone else).
    IF v_promo.source IN ('loyalty','recovery') THEN
      IF COALESCE(v_promo.target_user_id, v_promo.target_guest_profile_id)
         <> COALESCE(p_user_id, p_guest_profile_id) THEN
        RAISE EXCEPTION 'invalid_input'
          USING ERRCODE = '22023', HINT = 'CODE_WRONG_CLIENT';
      END IF;
    END IF;
  END IF;

  -- Discount math (server-authoritative).
  v_amount_off := CASE v_promo.discount_type
    WHEN 'percentage' THEN LEAST(p_booking_total * v_promo.discount_value / 100.0, p_booking_total)
    WHEN 'fixed'      THEN LEAST(v_promo.discount_value, p_booking_total)
    ELSE 0
  END;

  RETURN QUERY SELECT
    v_promo.id,
    v_promo.code,
    v_amount_off,
    GREATEST(p_booking_total - v_amount_off, 0),
    v_promo.source;
END;
$function$;

REVOKE ALL ON FUNCTION public.validate_and_apply_promo(UUID, TEXT, UUID, UUID, NUMERIC, UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_and_apply_promo(UUID, TEXT, UUID, UUID, NUMERIC, UUID[]) TO authenticated;

COMMENT ON FUNCTION public.validate_and_apply_promo(UUID, TEXT, UUID, UUID, NUMERIC, UUID[]) IS
  'Phase 13 checkout hot path. Read-only; no redemption row inserted. Branches on p_code: NULL → highest-discount unredeemed silent code lookup (loyalty/recovery), tiebreak sooner-expiring; TEXT → manual entry with full eligibility chain. Returns (promotion_id, code, amount_off, new_total, source) or raises 22023/HINT for typed-exception mapping. O(1) by partial unique indexes.';
