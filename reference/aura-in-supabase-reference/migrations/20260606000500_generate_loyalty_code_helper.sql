-- Phase 13 — generate_loyalty_code helper
--
-- Called by the bookings AFTER UPDATE trigger when a client hits an
-- Nth completed booking at the shop. Issues a one-shot loyalty code:
--   * source        = 'loyalty'
--   * target_*      = the booking's client identity
--   * discount_type/value = the shop's active loyalty_rule
--   * valid_to      = now() + 10 years (no-expiry sentinel; the
--                     validate RPC also accepts NULL valid_to but we
--                     keep a literal so the auto-apply ORDER BY can
--                     break ties consistently)
--   * usage_limit   = 1
--   * per_client_max = 1
--
-- Idempotent: returns the existing unredeemed loyalty code if any.
-- Returns NULL when:
--   * Both client identities are NULL (malformed booking), or
--   * The shop has no active loyalty rule.

CREATE OR REPLACE FUNCTION public.generate_loyalty_code(
  p_shop_id          UUID,
  p_user_id          UUID,
  p_guest_profile_id UUID
) RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $function$
DECLARE
  v_rule_type  TEXT;
  v_rule_value NUMERIC;
  v_existing   TEXT;
  v_new_code   TEXT;
BEGIN
  IF p_user_id IS NULL AND p_guest_profile_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Look up the shop's active loyalty rule.
  SELECT discount_type, discount_value
  INTO v_rule_type, v_rule_value
  FROM public.loyalty_rules
  WHERE shop_id = p_shop_id AND is_active = TRUE;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Idempotency: return the existing unredeemed loyalty code if any.
  SELECT code INTO v_existing FROM public.promotions
  WHERE shop_id = p_shop_id
    AND source = 'loyalty'
    AND archived_at IS NULL
    AND COALESCE(target_user_id, target_guest_profile_id)
        = COALESCE(p_user_id, p_guest_profile_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.promotion_redemptions r
      WHERE r.promotion_id = promotions.id
    )
  ORDER BY created_at DESC LIMIT 1;
  IF FOUND THEN
    RETURN v_existing;
  END IF;

  -- Generate. Format: LOYAL + 6 base32-ish chars. Total 11; satisfies
  -- the [A-Z0-9]{3,20} convention even though we don't enforce it as a
  -- CHECK on the code column (the existing schema allows any case).
  v_new_code := upper('LOYAL' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  INSERT INTO public.promotions (
    shop_id, name, code, discount_type, discount_value,
    valid_from, valid_to, usage_limit, is_active,
    source, target_user_id, target_guest_profile_id, per_client_max
  ) VALUES (
    p_shop_id, 'Loyalty reward', v_new_code,
    v_rule_type, v_rule_value,
    now(), now() + INTERVAL '10 years', 1, TRUE,
    'loyalty', p_user_id, p_guest_profile_id, 1
  );

  RETURN v_new_code;
END;
$function$;

REVOKE ALL ON FUNCTION public.generate_loyalty_code(UUID, UUID, UUID) FROM PUBLIC;
-- Intentionally NOT GRANTed to authenticated. Trigger-only.

COMMENT ON FUNCTION public.generate_loyalty_code(UUID, UUID, UUID) IS
  'Phase 13 internal helper. Issues a one-shot loyalty promo code for a (shop, client) pair using the shop active loyalty_rule. Idempotent (reuses existing unredeemed code). TTL is the no-expiry sentinel (now()+10y). SECURITY DEFINER; trigger-only. O(1).';
