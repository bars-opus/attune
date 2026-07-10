-- rebuild_shop_opening_hours(p_shop_id UUID, p_hours JSONB) -> VOID
--
-- Atomic DELETE + INSERT replacement of a shop's weekly opening hours.
-- Both statements run inside the function's implicit transaction;
-- either both succeed or both roll back, so a mid-save network failure
-- cannot leave the shop with half-written hours. This is the load-
-- bearing differentiator over the existing creation-flow loop at
-- supabase_shop_creation_repository.dart:394-403, which can leave hours
-- half-written on transient errors.
--
-- Hardening template parity with 20260603001500_harden_dashboard_rpcs.sql:
--   * SECURITY DEFINER + SET search_path = public
--   * Authz FIRST via EXISTS shops WHERE user_id = auth.uid()
--   * Range/shape validation second, with HINT codes
--   * REVOKE ALL FROM PUBLIC + GRANT EXECUTE TO authenticated
--   * COMMENT ON FUNCTION with Big-O
--
-- Phase 11 locked corrections applied:
--   1. opens_at / closes_at pass through as TEXT, NOT TIME. The live
--      table stores values like "09:00 AM" — Postgres TIME would reject
--      every existing payload. (Spec §RPC 1 had ::TIME casts; dropped.)
--   5. day_of_week validated BETWEEN 0 AND 7 inclusive. Existing data is
--      mixed (some writers use 0..6 EXTRACT(DOW), most use 1..7), so
--      rejecting either range would break first-save on legacy shops.

CREATE OR REPLACE FUNCTION public.rebuild_shop_opening_hours(
  p_shop_id UUID,
  p_hours   JSONB
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_owns_shop BOOLEAN;
  v_count     INT;
  v_bad_dow   INT;
BEGIN
  -- (1) Authz FIRST. Matches harden_dashboard_rpcs.sql:45-51.
  SELECT EXISTS (
    SELECT 1 FROM public.shops
    WHERE id = p_shop_id AND user_id = auth.uid()
  ) INTO v_owns_shop;
  IF NOT v_owns_shop THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = '42501';
  END IF;

  -- (2) Shape: must be a JSON array of exactly 7 elements.
  IF p_hours IS NULL OR jsonb_typeof(p_hours) <> 'array' THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'HOURS_MUST_BE_ARRAY';
  END IF;
  SELECT jsonb_array_length(p_hours) INTO v_count;
  IF v_count <> 7 THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'EXACTLY_7_DAYS_REQUIRED';
  END IF;

  -- (3) day_of_week range: tolerate legacy 0..6 and current 1..7.
  SELECT MIN((elem->>'day_of_week')::INT) INTO v_bad_dow
  FROM jsonb_array_elements(p_hours) elem
  WHERE (elem->>'day_of_week')::INT NOT BETWEEN 0 AND 7;
  IF v_bad_dow IS NOT NULL THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'DAY_OF_WEEK_OUT_OF_RANGE';
  END IF;

  -- (4) Atomic rebuild. Both statements run in the function's implicit
  -- transaction. NO ::TIME cast — column is TEXT in prod (locked
  -- correction 1). Postgres uses transaction-level snapshot isolation,
  -- so a concurrent reader (e.g. check_shop_hours) sees either the
  -- pre-DELETE state or the post-INSERT state, never the gap.
  --
  -- IMPORTANT (atomicity invariant): a future reviewer MUST NOT split
  -- this DELETE + INSERT pair into two separate RPC calls or move
  -- either statement out of this transaction. The no-partial-write
  -- guarantee depends on both running in one tx.
  DELETE FROM public.shop_opening_hours WHERE shop_id = p_shop_id;
  INSERT INTO public.shop_opening_hours (
    shop_id, day_of_week, opens_at, closes_at, is_closed
  )
  SELECT
    p_shop_id,
    (elem->>'day_of_week')::INT,
    elem->>'opens_at',
    elem->>'closes_at',
    COALESCE((elem->>'is_closed')::BOOLEAN, false)
  FROM jsonb_array_elements(p_hours) AS elem;
END;
$function$;

REVOKE ALL ON FUNCTION public.rebuild_shop_opening_hours(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rebuild_shop_opening_hours(UUID, JSONB) TO authenticated;

COMMENT ON FUNCTION public.rebuild_shop_opening_hours(UUID, JSONB) IS
  'Atomic rebuild of a shop weekly opening hours. DELETE + INSERT in one tx — DO NOT split. SECURITY DEFINER with shops.user_id=auth.uid() gate. Accepts day_of_week BETWEEN 0 AND 7 to tolerate legacy 0-indexed rows. opens_at / closes_at stored as TEXT (existing prod shape). O(1) — bounded at 7 rows per call.';
