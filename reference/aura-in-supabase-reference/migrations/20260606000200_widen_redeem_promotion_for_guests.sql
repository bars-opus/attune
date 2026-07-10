-- Phase 13 — widen redeem_promotion to accept guest_profile_id.
--
-- The body is byte-for-byte the existing 20260604000400 shape with one
-- VALUES tuple addition (guest_profile_id) and a defensive NULL-shape
-- check at the top.
--
-- IMPORTANT — function signature change:
--   Old: redeem_promotion(UUID, UUID, UUID, NUMERIC)
--   New: redeem_promotion(UUID, UUID, UUID, NUMERIC, UUID DEFAULT NULL)
-- Postgres treats these as DIFFERENT functions by signature. The old
-- 4-arg variant must be explicitly DROPped — CREATE OR REPLACE only
-- replaces a function with the same exact signature. Without the
-- DROP, the old 4-arg version (and its GRANT EXECUTE TO authenticated)
-- would linger, leaving the redemption-fabrication surface wide open.

-- Step 1: drop the legacy 4-arg signature.
DROP FUNCTION IF EXISTS public.redeem_promotion(UUID, UUID, UUID, NUMERIC);

-- Step 2: create the widened 5-arg version.
CREATE OR REPLACE FUNCTION public.redeem_promotion(
  p_promotion_id     UUID,
  p_booking_id       UUID,
  p_user_id          UUID,
  p_discount_amount  NUMERIC,
  p_guest_profile_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $function$
DECLARE
  v_redemption_id UUID;
BEGIN
  -- NULL shape validation (no side effects; precedes authz).
  IF p_promotion_id IS NULL OR p_booking_id IS NULL THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'PROMOTION_OR_BOOKING_NULL';
  END IF;

  -- At-most-one identity (the table CHECK also enforces this).
  IF p_user_id IS NOT NULL AND p_guest_profile_id IS NOT NULL THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'AT_MOST_ONE_OF_USER_OR_GUEST';
  END IF;

  -- Atomic insert; rely on UNIQUE(promotion_id, booking_id) for idempotency.
  INSERT INTO public.promotion_redemptions (
    promotion_id, booking_id, user_id, guest_profile_id, discount_amount, redeemed_at
  ) VALUES (
    p_promotion_id, p_booking_id, p_user_id, p_guest_profile_id, p_discount_amount, now()
  )
  ON CONFLICT (promotion_id, booking_id) DO NOTHING
  RETURNING id INTO v_redemption_id;

  -- If the conflict path fired, fetch the existing redemption id.
  IF v_redemption_id IS NULL THEN
    SELECT id INTO v_redemption_id FROM public.promotion_redemptions
    WHERE promotion_id = p_promotion_id AND booking_id = p_booking_id;
    RETURN v_redemption_id;  -- idempotent no-op.
  END IF;

  -- Counter bump (only on first insert).
  UPDATE public.promotions
  SET usage_count = COALESCE(usage_count, 0) + 1
  WHERE id = p_promotion_id;

  RETURN v_redemption_id;
END;
$function$;

-- REVOKE the broad authenticated grant — webhooks call with
-- service_role only. Closes the redemption-fabrication surface
-- (RESEARCH §18).
REVOKE ALL ON FUNCTION public.redeem_promotion(UUID, UUID, UUID, NUMERIC, UUID) FROM PUBLIC;
-- Intentionally NOT GRANTed to authenticated.

COMMENT ON FUNCTION public.redeem_promotion(UUID, UUID, UUID, NUMERIC, UUID) IS
  'Phase 13: widened to accept guest_profile_id. Idempotent insert + counter bump. SECURITY DEFINER; service_role-only (revoked from authenticated to close the fabrication surface). O(1).';
