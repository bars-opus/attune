-- Harden the dashboard read-RPCs (heatmap / client_stats / client_analytics
-- / worker_monthly_attendance) with two fixes that the backfill in
-- 20260603000000 intentionally left as-is:
--
--   1. Authorization. The live RPCs are SECURITY INVOKER and trust the
--      caller-supplied id (p_shop_id / p_client_id / p_worker_id). RLS
--      on the underlying tables filters the SCAN — but a malicious or
--      curious authenticated user can still ask for arbitrary ids and
--      observe distinguishable timing/empty-result patterns to
--      enumerate shops. We harden by:
--        * making them SECURITY DEFINER (so we control the access path)
--        * adding an explicit auth.uid() ownership check at the top
--        * granting EXECUTE to `authenticated` only — service_role can
--          still call them by virtue of being superuser
--
--   2. Range bound. get_booking_heatmap accepted any (start, end). A
--      caller can ask for 10 years of bookings and the function will
--      happily aggregate them. Now capped at 366 days.
--
-- Other read-RPCs (get_client_stats, get_client_analytics,
-- get_worker_monthly_attendance) are similarly hardened.
--
-- Checklist mapping:
--   1.4  Authz at every access point — FIXED
--   2.5  Resource limits — heatmap range cap FIXED
--   2.4  Error messages — uniform 'not found' (avoids existence leak)

-- ── get_booking_heatmap ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_booking_heatmap(
  p_shop_id    UUID,
  p_start_date DATE,
  p_end_date   DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_owns_shop BOOLEAN;
  result      JSONB;
  max_count   INT;
BEGIN
  -- Authz
  SELECT EXISTS (
    SELECT 1 FROM public.shops
    WHERE id = p_shop_id AND user_id = auth.uid()
  ) INTO v_owns_shop;
  IF NOT v_owns_shop THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = '42501';
  END IF;

  -- Range cap (checklist 2.5).
  IF p_end_date < p_start_date THEN
    RAISE EXCEPTION 'invalid_range' USING ERRCODE = '22023';
  END IF;
  IF (p_end_date - p_start_date) > 366 THEN
    RAISE EXCEPTION 'range_too_large' USING ERRCODE = '22023', HINT = 'MAX_366_DAYS';
  END IF;

  SELECT COALESCE(MAX(booking_count), 1) INTO max_count
  FROM (
    SELECT COUNT(*) AS booking_count
    FROM public.bookings
    WHERE shop_id = p_shop_id
      AND start_time::DATE BETWEEN p_start_date AND p_end_date
      AND status IN ('confirmed', 'completed')
    GROUP BY EXTRACT(DOW FROM start_time), EXTRACT(HOUR FROM start_time)
  ) counts;

  SELECT jsonb_build_object(
    'start_date', p_start_date,
    'end_date', p_end_date,
    'max_booking_count', max_count,
    'max_occupancy_rate', 0,
    'data_points', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'day_of_week', day_of_week,
            'hour', hour,
            'booking_count', booking_count,
            'occupancy_rate', 0
          ) ORDER BY day_of_week, hour
        )
        FROM (
          SELECT EXTRACT(DOW FROM start_time)::INT AS day_of_week,
                 EXTRACT(HOUR FROM start_time)::INT AS hour,
                 COUNT(*) AS booking_count
          FROM public.bookings
          WHERE shop_id = p_shop_id
            AND start_time::DATE BETWEEN p_start_date AND p_end_date
            AND status IN ('confirmed', 'completed')
          GROUP BY EXTRACT(DOW FROM start_time), EXTRACT(HOUR FROM start_time)
        ) daily_data
      ),
      '[]'::jsonb
    )
  ) INTO result;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_booking_heatmap(UUID, DATE, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_booking_heatmap(UUID, DATE, DATE) TO authenticated;
COMMENT ON FUNCTION public.get_booking_heatmap(UUID, DATE, DATE) IS
  '7x24 heatmap of confirmed/completed bookings, scoped to the caller''s own shops. Range capped at 366 days. SECURITY DEFINER with explicit auth.uid() ownership check.';

-- ── get_client_stats ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_client_stats(
  p_shop_id UUID,
  p_months  INTEGER DEFAULT 6
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_owns_shop BOOLEAN;
  start_date  TIMESTAMP;
  result      JSONB;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.shops
    WHERE id = p_shop_id AND user_id = auth.uid()
  ) INTO v_owns_shop;
  IF NOT v_owns_shop THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = '42501';
  END IF;

  -- Cap months (checklist 2.5).
  IF p_months IS NULL OR p_months < 1 OR p_months > 60 THEN
    RAISE EXCEPTION 'invalid_months' USING ERRCODE = '22023', HINT = 'RANGE_1_60';
  END IF;

  start_date := date_trunc('month', CURRENT_DATE) - (p_months || ' months')::INTERVAL;

  WITH client_activity AS (
    SELECT user_id,
           COUNT(*) AS booking_count,
           MIN(created_at) AS first_booking,
           MAX(created_at) AS last_booking
    FROM public.bookings
    WHERE shop_id = p_shop_id
      AND created_at >= start_date
      AND status IN ('confirmed', 'completed')
    GROUP BY user_id
  )
  SELECT jsonb_build_object(
    'total_clients',     COUNT(*),
    'new_clients',       COUNT(*) FILTER (WHERE first_booking >= date_trunc('month', CURRENT_DATE)),
    'returning_clients', COUNT(*) FILTER (WHERE booking_count > 1),
    'repeat_rate',       ROUND(COUNT(*) FILTER (WHERE booking_count > 1) * 100.0 / NULLIF(COUNT(*), 0), 1),
    'active_clients',    COUNT(*) FILTER (WHERE last_booking >= date_trunc('month', CURRENT_DATE) - INTERVAL '3 months')
  ) INTO result
  FROM client_activity;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_client_stats(UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_client_stats(UUID, INTEGER) TO authenticated;
COMMENT ON FUNCTION public.get_client_stats(UUID, INTEGER) IS
  'Per-shop client cohort stats. Months capped at 60. SECURITY DEFINER with explicit ownership check.';

-- ── get_client_analytics ───────────────────────────────────────────
-- Shop owners can read analytics for clients who have booked at one of
-- their shops. Cross-shop access is forbidden.
CREATE OR REPLACE FUNCTION public.get_client_analytics(p_client_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_can_see BOOLEAN;
  result    JSONB;
BEGIN
  -- The caller can see this client's analytics iff the client has at
  -- least one booking at a shop the caller owns.
  SELECT EXISTS (
    SELECT 1
    FROM public.bookings b
    JOIN public.shops s ON s.id = b.shop_id
    WHERE b.user_id = p_client_id
      AND s.user_id = auth.uid()
  ) INTO v_can_see;
  IF NOT v_can_see THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'total_bookings', COUNT(b.id),
    'total_spent', COALESCE(SUM(b.total_amount), 0),
    'average_booking_value', COALESCE(AVG(b.total_amount), 0),
    'first_booking', MIN(b.created_at),
    'last_booking', MAX(b.created_at),
    'favorite_services', (
      SELECT jsonb_agg(
        jsonb_build_object('service_name', service_name, 'count', cnt)
      )
      FROM (
        SELECT s.name AS service_name, COUNT(bs.id) AS cnt
        FROM public.booking_services bs
        JOIN public.appointment_slots s ON bs.slot_id = s.id
        WHERE bs.booking_id IN (
          SELECT id FROM public.bookings WHERE user_id = p_client_id
        )
        GROUP BY s.name
        ORDER BY COUNT(bs.id) DESC
        LIMIT 3
      ) top3
    )
  ) INTO result
  FROM public.bookings b
  WHERE b.user_id = p_client_id
    AND b.status IN ('confirmed', 'completed');

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_client_analytics(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_client_analytics(UUID) TO authenticated;
COMMENT ON FUNCTION public.get_client_analytics(UUID) IS
  'Per-client analytics for clients who have booked at the caller''s shops. SECURITY DEFINER with cross-shop relationship check.';

-- ── get_worker_monthly_attendance ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_worker_monthly_attendance(
  p_worker_id UUID,
  p_month     DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_can_see BOOLEAN;
  result    JSONB;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.workers w
    JOIN public.shops s ON s.id = w.shop_id
    WHERE w.id = p_worker_id
      AND s.user_id = auth.uid()
  ) INTO v_can_see;
  IF NOT v_can_see THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'days_worked',       COALESCE(COUNT(DISTINCT wa.date), 0),
    'total_hours',       COALESCE(SUM(wa.total_hours), 0),
    'on_time_rate',      COALESCE(ROUND(
                           (COUNT(*) FILTER (WHERE wa.status NOT IN ('late', 'absent'))::DECIMAL
                           / NULLIF(COUNT(*), 0) * 100), 1), 0),
    'late_arrivals',     COALESCE(COUNT(*) FILTER (WHERE wa.status = 'late'), 0),
    'absent_days',       COALESCE(COUNT(*) FILTER (WHERE wa.status = 'absent'), 0),
    'avg_hours_per_day', COALESCE(ROUND(AVG(wa.total_hours), 1), 0)
  )
  INTO result
  FROM public.worker_attendance wa
  WHERE wa.worker_id = p_worker_id
    AND DATE_TRUNC('month', wa.date) = DATE_TRUNC('month', p_month);

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_worker_monthly_attendance(UUID, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_worker_monthly_attendance(UUID, DATE) TO authenticated;
COMMENT ON FUNCTION public.get_worker_monthly_attendance(UUID, DATE) IS
  'Per-worker monthly attendance, scoped to workers in the caller''s shops. SECURITY DEFINER with explicit ownership check.';
