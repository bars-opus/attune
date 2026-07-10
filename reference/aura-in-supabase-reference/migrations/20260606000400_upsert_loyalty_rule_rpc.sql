-- Phase 13 — upsert_loyalty_rule
--
-- Owner-only RPC. Authz FIRST per the Phase 11 hardening template.
-- Idempotent in the sense that an active rule for the shop is
-- DEACTIVATED before the new one is INSERTed, so the partial unique
-- index (one active rule per shop) is preserved.
--
-- If p_is_active=FALSE, the function still deactivates the existing
-- rule but inserts no replacement — useful for "turn off loyalty"
-- without designing a separate disable RPC.

CREATE OR REPLACE FUNCTION public.upsert_loyalty_rule(
  p_shop_id             UUID,
  p_trigger_visit_count INT,
  p_discount_type       TEXT,
  p_discount_value      NUMERIC,
  p_is_active           BOOLEAN DEFAULT TRUE
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $function$
DECLARE
  v_owns_shop BOOLEAN;
  v_rule_id   UUID;
BEGIN
  IF p_shop_id IS NULL THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'SHOP_ID_NULL';
  END IF;

  -- Authz FIRST.
  SELECT EXISTS (
    SELECT 1 FROM public.shops
    WHERE id = p_shop_id AND user_id = auth.uid()
  ) INTO v_owns_shop;
  IF NOT v_owns_shop THEN
    RAISE EXCEPTION 'not_found'
      USING ERRCODE = '42501', HINT = 'NOT_SHOP_OWNER';
  END IF;

  -- Payload validation.
  IF p_trigger_visit_count IS NULL
     OR p_trigger_visit_count < 2 OR p_trigger_visit_count > 50 THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'TRIGGER_VISIT_COUNT_OUT_OF_RANGE';
  END IF;
  IF p_discount_type NOT IN ('percentage','fixed') THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'INVALID_DISCOUNT_TYPE';
  END IF;
  IF p_discount_value IS NULL OR p_discount_value <= 0 THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'DISCOUNT_VALUE_NOT_POSITIVE';
  END IF;
  IF p_discount_type = 'percentage' AND p_discount_value > 100 THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'PERCENTAGE_OUT_OF_RANGE';
  END IF;

  -- Atomic swap. The partial unique index permits multiple is_active=false
  -- rows, so deactivating an existing rule never collides.
  UPDATE public.loyalty_rules
  SET is_active = FALSE, updated_at = now()
  WHERE shop_id = p_shop_id AND is_active = TRUE;

  IF p_is_active THEN
    INSERT INTO public.loyalty_rules (
      shop_id, trigger_visit_count, discount_type, discount_value, is_active
    ) VALUES (
      p_shop_id, p_trigger_visit_count, p_discount_type, p_discount_value, TRUE
    )
    RETURNING id INTO v_rule_id;
  END IF;

  RETURN v_rule_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.upsert_loyalty_rule(UUID, INT, TEXT, NUMERIC, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_loyalty_rule(UUID, INT, TEXT, NUMERIC, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION public.upsert_loyalty_rule(UUID, INT, TEXT, NUMERIC, BOOLEAN) IS
  'Phase 13 owner-facing loyalty rule upsert. Authz first. Deactivates existing active rule and inserts the new one atomically. SECURITY DEFINER with shops.user_id=auth.uid() gate. O(1).';
