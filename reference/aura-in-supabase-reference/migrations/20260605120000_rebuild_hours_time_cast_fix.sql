-- Phase 11 hotfix: rebuild_shop_opening_hours
--
-- Symptom (2026-06-05 UAT):
--   PostgrestException 42804 — column "opens_at" is of type time without
--   time zone but expression is of type text.
--
-- Root cause:
--   The shop_opening_hours table has opens_at / closes_at as
--   `time without time zone` (NOT text, despite the Phase 11 RESEARCH
--   reading of the codebase). The original Phase 11 migration
--   (20260605000100) cast the JSONB value with `elem->>'opens_at'`
--   which returns text, and PG refused the implicit text→time coercion
--   on INSERT.
--
-- Fix:
--   Parse the inbound 12-hour string ('09:00 AM' / '05:00 PM') into a
--   real PG time value via to_timestamp(..., 'HH12:MI AM').
--   Defensive fallback: if the string is already 24h ('09:00'), the
--   regex strips the AM/PM and to_timestamp still works on 'HH24:MI'.
--
-- Tolerance:
--   - Inputs without AM/PM go through the 24h parser.
--   - Inputs with AM/PM go through the 12h parser.
--   - is_closed=true rows skip the parse and write NULL (no-op for the
--     booking flow, which checks is_closed first).

CREATE OR REPLACE FUNCTION public.rebuild_shop_opening_hours(
  p_shop_id UUID,
  p_hours   JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_owner UUID;
  v_count INT;
BEGIN
  -- Authz: caller must own the shop.
  SELECT user_id INTO v_owner FROM public.shops WHERE id = p_shop_id;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'shop_not_found'
      USING ERRCODE = '42501', HINT = 'SHOP_NOT_FOUND';
  END IF;
  IF v_owner <> auth.uid() THEN
    RAISE EXCEPTION 'not_shop_owner'
      USING ERRCODE = '42501', HINT = 'NOT_SHOP_OWNER';
  END IF;

  -- Shape: must be a JSON array.
  IF p_hours IS NULL OR jsonb_typeof(p_hours) <> 'array' THEN
    RAISE EXCEPTION 'invalid_payload'
      USING ERRCODE = '22023', HINT = 'PAYLOAD_NOT_ARRAY';
  END IF;

  -- Shape: exactly 7 rows.
  SELECT jsonb_array_length(p_hours) INTO v_count;
  IF v_count <> 7 THEN
    RAISE EXCEPTION 'invalid_payload'
      USING ERRCODE = '22023', HINT = 'EXACTLY_7_DAYS_REQUIRED';
  END IF;

  -- Shape: every day_of_week must be in [0, 7].
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_hours) AS elem
    WHERE (elem->>'day_of_week')::INT NOT BETWEEN 0 AND 7
  ) THEN
    RAISE EXCEPTION 'invalid_payload'
      USING ERRCODE = '22023', HINT = 'DAY_OF_WEEK_OUT_OF_RANGE';
  END IF;

  -- Atomic rebuild: DELETE + INSERT in one statement-block transaction.
  -- DO NOT split. The no-partial-write guarantee depends on both running
  -- in one tx.
  DELETE FROM public.shop_opening_hours WHERE shop_id = p_shop_id;

  INSERT INTO public.shop_opening_hours (
    shop_id, day_of_week, opens_at, closes_at, is_closed
  )
  SELECT
    p_shop_id,
    (elem->>'day_of_week')::INT,
    -- Parse 12h ("09:00 AM") or 24h ("09:00") into PG time.
    -- Closed days store a placeholder time (00:00) because the column
    -- is NOT NULL. The booking flow checks is_closed FIRST and never
    -- reads opens_at/closes_at for closed rows, so the placeholder is
    -- inert. We deliberately do NOT alter the column's NOT NULL —
    -- other RPCs (check_shop_hours, generate_available_slots) assume
    -- the values are non-null.
    CASE
      WHEN COALESCE((elem->>'is_closed')::BOOLEAN, false) THEN '00:00'::time
      WHEN elem->>'opens_at' ~* '\s(AM|PM)\s*$'
        THEN to_timestamp(elem->>'opens_at', 'HH12:MI AM')::time
      ELSE to_timestamp(elem->>'opens_at', 'HH24:MI')::time
    END,
    CASE
      WHEN COALESCE((elem->>'is_closed')::BOOLEAN, false) THEN '00:00'::time
      WHEN elem->>'closes_at' ~* '\s(AM|PM)\s*$'
        THEN to_timestamp(elem->>'closes_at', 'HH12:MI AM')::time
      ELSE to_timestamp(elem->>'closes_at', 'HH24:MI')::time
    END,
    COALESCE((elem->>'is_closed')::BOOLEAN, false)
  FROM jsonb_array_elements(p_hours) AS elem;
END;
$function$;

REVOKE ALL ON FUNCTION public.rebuild_shop_opening_hours(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rebuild_shop_opening_hours(UUID, JSONB) TO authenticated;

COMMENT ON FUNCTION public.rebuild_shop_opening_hours(UUID, JSONB) IS
  'Atomic rebuild of a shop weekly opening hours. DELETE + INSERT in one tx — DO NOT split. SECURITY DEFINER with shops.user_id=auth.uid() gate. Accepts day_of_week BETWEEN 0 AND 7 to tolerate legacy 0-indexed rows. opens_at/closes_at parsed from 12h ("09:00 AM") or 24h ("09:00") strings into PG time. Closed days store 00:00 placeholders (column is NOT NULL; consumers check is_closed first). O(1) — bounded at 7 rows per call.';
