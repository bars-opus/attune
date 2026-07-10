-- Phase 13 — generate_recovery_code helper
--
-- Called by enqueue_booking_reminder when type = 'recovery_checkin'.
-- Issues a 30-day recovery code:
--   * source        = 'recovery'
--   * target_*      = the booking's client identity
--   * discount_type/value = the shop's active loyalty_rule (reused)
--   * valid_to      = now() + 30 days
--   * usage_limit   = 1
--   * per_client_max = 1
--
-- Idempotent: returns the existing unredeemed recovery code if any
-- (still within validity window).
-- Returns NULL when:
--   * Both client identities are NULL, or
--   * The shop has no active loyalty rule. The caller composes a
--     text-only message in that case (no hardcoded fallback discount).

CREATE OR REPLACE FUNCTION public.generate_recovery_code(
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

  -- Idempotency: reuse a still-valid unredeemed recovery code if any.
  SELECT code INTO v_existing FROM public.promotions
  WHERE shop_id = p_shop_id
    AND source = 'recovery'
    AND archived_at IS NULL
    AND valid_to > now()
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

  -- Look up the shop's active loyalty rule. If absent, return NULL.
  -- LOCKED decision: no hardcoded fallback discount; caller composes
  -- text-only message.
  SELECT discount_type, discount_value
  INTO v_rule_type, v_rule_value
  FROM public.loyalty_rules
  WHERE shop_id = p_shop_id AND is_active = TRUE;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  v_new_code := upper('RECOVER' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 5));

  INSERT INTO public.promotions (
    shop_id, name, code, discount_type, discount_value,
    valid_from, valid_to, usage_limit, is_active,
    source, target_user_id, target_guest_profile_id, per_client_max
  ) VALUES (
    p_shop_id, 'Recovery offer', v_new_code,
    v_rule_type, v_rule_value,
    now(), now() + INTERVAL '30 days', 1, TRUE,
    'recovery', p_user_id, p_guest_profile_id, 1
  );

  RETURN v_new_code;
END;
$function$;

REVOKE ALL ON FUNCTION public.generate_recovery_code(UUID, UUID, UUID) FROM PUBLIC;
-- Intentionally NOT GRANTed to authenticated. Called only from
-- enqueue_booking_reminder.

COMMENT ON FUNCTION public.generate_recovery_code(UUID, UUID, UUID) IS
  'Phase 13 internal helper. Issues a 30-day recovery promo code for a (shop, client) pair. Discount kind/value reused from the shop active loyalty_rule; returns NULL when no rule (recovery_checkin message stays text-only). Idempotent. SECURITY DEFINER; called only from enqueue_booking_reminder. O(1).';
