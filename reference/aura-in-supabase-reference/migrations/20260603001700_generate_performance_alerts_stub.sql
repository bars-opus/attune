-- Provide an honest stub for generate_performance_alerts.
--
-- The Dart AlertsController.generateAlerts() calls this RPC. The live
-- DB doesn't have it, so the call has been failing silently with
-- "function does not exist". The UI catches the error and shows
-- "Failed to load alerts" — which is misleading because the alerts the
-- user already had loaded are fine; only the *regenerate* fails.
--
-- Until product defines the actual alert rules (low-conversion-rate
-- thresholds, churn risk, etc.) this stub returns the current alerts
-- without generating new ones, so the UI is functional and consistent.
--
-- When the rules are defined, replace this body with the real logic
-- (look at performance_alerts.category / severity / threshold for the
-- shape product is expecting). Until then, calling this is a no-op
-- that returns the existing set.
--
-- Checklist mapping:
--   1.4  Authz — ownership check at top ✅
--   2.4  Sanitized error ✅
--   6.13 Documented as stub ✅

CREATE OR REPLACE FUNCTION public.generate_performance_alerts(p_shop_id UUID)
RETURNS SETOF public.performance_alerts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_owns_shop BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.shops
    WHERE id = p_shop_id AND user_id = auth.uid()
  ) INTO v_owns_shop;
  IF NOT v_owns_shop THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = '42501';
  END IF;

  -- STUB: no rule engine yet. Return the existing alert set so the
  -- Dart controller's subsequent loadAlerts() call shows consistent
  -- data. When rules are defined, do the INSERTs above this RETURN.
  RETURN QUERY
    SELECT *
      FROM public.performance_alerts
     WHERE shop_id = p_shop_id
       AND resolved_at IS NULL
     ORDER BY created_at DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.generate_performance_alerts(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_performance_alerts(UUID) TO authenticated;
COMMENT ON FUNCTION public.generate_performance_alerts(UUID) IS
  'STUB: returns existing unresolved alerts for the shop. Real rule-evaluation logic is a product follow-up. SECURITY DEFINER with ownership check.';
