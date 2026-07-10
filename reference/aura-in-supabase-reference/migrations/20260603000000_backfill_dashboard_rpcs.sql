-- Backfill: dashboard RPCs that were created via the Supabase Dashboard and
-- are NOT in version control. Lifted byte-for-byte from the live database on
-- 2026-06-03 so applying this migration is a no-op against prod, but new
-- environments (CI, local, staging) finally have the same code paths.
--
-- All four RPCs are SECURITY INVOKER. They rely on caller RLS to scope reads
-- — see the audit notes inline. None of them verify that auth.uid() owns the
-- shop/client being queried; they trust the caller-supplied id. If RLS on
-- the underlying tables (bookings, worker_attendance, booking_services,
-- appointment_slots) is correct, this is safe. If those policies regress,
-- these RPCs become a confused-deputy hole.
--
-- Audit-checklist mapping (v3.1):
--   1.4  Authorization at every resource access — PARTIAL: relies on table RLS
--   1.8  Big-O documented — added below per function
--   2.5  Resource limits — heatmap lacks max-range cap (TODO in code comment)
--   3.3  Indexes — relies on idx_bookings_shop_date_status (already present)
--   6.13 Documentation — added intent + failure modes inline

-- ──────────────────────────────────────────────────────────────────────
-- get_booking_heatmap(shop_id, start_date, end_date) -> jsonb
-- ──────────────────────────────────────────────────────────────────────
-- Aggregates confirmed/completed bookings into a 7×24 heatmap (day-of-week
-- × hour-of-day). Returns shape:
--   { start_date, end_date, max_booking_count, max_occupancy_rate,
--     data_points: [{day_of_week, hour, booking_count, occupancy_rate}, ...] }
--
-- Complexity: O(B) over bookings in range. Bounded by RLS-scoped read of
-- `bookings` (idx_bookings_shop_date_status on shop_id, start_time, status).
--
-- KNOWN GAPS (do not fix in this backfill — separate migration):
--   - No cap on (end_date - start_date). A caller can ask for years of data.
--   - occupancy_rate is hardcoded to 0 (the real calc was never wired up).
--   - SECURITY INVOKER but does not verify caller owns p_shop_id; relies on
--     bookings_shop_owner_select RLS policy to filter the rows.
CREATE OR REPLACE FUNCTION public.get_booking_heatmap(
  p_shop_id    UUID,
  p_start_date DATE,
  p_end_date   DATE
)
RETURNS JSONB
LANGUAGE plpgsql
AS $function$
DECLARE
  result    JSONB;
  max_count INT;
BEGIN
  -- Get max booking count (default to 1 to avoid division by zero)
  SELECT COALESCE(MAX(booking_count), 1) INTO max_count
  FROM (
    SELECT COUNT(*) as booking_count
    FROM bookings
    WHERE shop_id = p_shop_id
      AND start_time::DATE BETWEEN p_start_date AND p_end_date
      AND status IN ('confirmed', 'completed')
    GROUP BY EXTRACT(DOW FROM start_time), EXTRACT(HOUR FROM start_time)
  ) counts;

  -- Build the result
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
          SELECT
            EXTRACT(DOW FROM start_time)::INT as day_of_week,
            EXTRACT(HOUR FROM start_time)::INT as hour,
            COUNT(*) as booking_count
          FROM bookings
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

COMMENT ON FUNCTION public.get_booking_heatmap(UUID, DATE, DATE) IS
  'Returns a 7x24 heatmap of confirmed/completed bookings for the date range. SECURITY INVOKER — relies on bookings RLS for authorization.';

-- ──────────────────────────────────────────────────────────────────────
-- get_client_analytics(client_id) -> jsonb
-- ──────────────────────────────────────────────────────────────────────
-- Returns per-client aggregate: total_bookings, total_spent, avg_value,
-- first/last booking timestamps, and top 3 favorite services.
--
-- Complexity: O(N) over the client's bookings + O(M) over their
-- booking_services. Index idx_bookings_user_id (user_id, start_time DESC)
-- covers the bookings scan.
--
-- KNOWN GAPS:
--   - SECURITY INVOKER; relies on bookings RLS. A shop owner can see every
--     analytics field for any client_id who has ever booked at THEIR shop
--     (because bookings_shop_owner_select grants SELECT on those rows).
--     They cannot see clients who never booked at their shop.
--   - LIMIT 3 on favorite_services is inside an aggregate; per-call
--     subquery returns the global top-3 across all the client's bookings
--     not scoped to a single shop. Verify this matches product intent.
CREATE OR REPLACE FUNCTION public.get_client_analytics(p_client_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
AS $function$
DECLARE
  result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'total_bookings', COUNT(b.id),
    'total_spent', COALESCE(SUM(b.total_amount), 0),
    'average_booking_value', COALESCE(AVG(b.total_amount), 0),
    'first_booking', MIN(b.created_at),
    'last_booking', MAX(b.created_at),
    'favorite_services', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'service_name', s.name,
          'count', COUNT(bs.id)
        )
      )
      FROM booking_services bs
      JOIN appointment_slots s ON bs.slot_id = s.id
      WHERE bs.booking_id IN (SELECT id FROM bookings WHERE user_id = p_client_id)
      GROUP BY s.name
      ORDER BY COUNT(bs.id) DESC
      LIMIT 3
    )
  ) INTO result
  FROM bookings b
  WHERE b.user_id = p_client_id
    AND b.status IN ('confirmed', 'completed');

  RETURN result;
END;
$function$;

COMMENT ON FUNCTION public.get_client_analytics(UUID) IS
  'Per-client booking aggregates + top 3 favorite services. SECURITY INVOKER — bookings RLS gates visibility.';

-- ──────────────────────────────────────────────────────────────────────
-- get_client_stats(shop_id, months DEFAULT 6) -> jsonb
-- ──────────────────────────────────────────────────────────────────────
-- Returns per-shop client cohort stats over the last N months:
-- total_clients, new_clients (booked first time this month), returning,
-- repeat_rate %, active_clients (booked in last 3 months).
--
-- Complexity: O(B) over bookings in window. idx_bookings_shop_id covers it.
--
-- KNOWN GAPS:
--   - SECURITY INVOKER. Caller-supplied p_shop_id. RLS on bookings is the
--     only thing stopping shop A's owner from passing shop B's id.
--   - No upper bound on p_months. A caller can request 240 months.
CREATE OR REPLACE FUNCTION public.get_client_stats(
  p_shop_id UUID,
  p_months  INTEGER DEFAULT 6
)
RETURNS JSONB
LANGUAGE plpgsql
AS $function$
DECLARE
  start_date TIMESTAMP;
  result     JSONB;
BEGIN
  start_date := date_trunc('month', CURRENT_DATE) - (p_months || ' months')::INTERVAL;

  WITH client_activity AS (
    SELECT
      user_id,
      COUNT(*) as booking_count,
      MIN(created_at) as first_booking,
      MAX(created_at) as last_booking
    FROM bookings
    WHERE shop_id = p_shop_id
      AND created_at >= start_date
      AND status IN ('confirmed', 'completed')
    GROUP BY user_id
  )
  SELECT jsonb_build_object(
    'total_clients', COUNT(*),
    'new_clients', COUNT(*) FILTER (WHERE first_booking >= date_trunc('month', CURRENT_DATE)),
    'returning_clients', COUNT(*) FILTER (WHERE booking_count > 1),
    'repeat_rate', ROUND(COUNT(*) FILTER (WHERE booking_count > 1) * 100.0 / NULLIF(COUNT(*), 0), 1),
    'active_clients', COUNT(*) FILTER (WHERE last_booking >= date_trunc('month', CURRENT_DATE) - INTERVAL '3 months')
  ) INTO result
  FROM client_activity;

  RETURN result;
END;
$function$;

COMMENT ON FUNCTION public.get_client_stats(UUID, INTEGER) IS
  'Per-shop client cohort stats over the last N months. SECURITY INVOKER — bookings RLS gates the per-shop scope.';

-- ──────────────────────────────────────────────────────────────────────
-- get_worker_monthly_attendance(worker_id, month DEFAULT today) -> jsonb
-- ──────────────────────────────────────────────────────────────────────
-- Returns per-worker monthly attendance: days_worked, total_hours,
-- on_time_rate %, late_arrivals, absent_days, avg_hours_per_day.
--
-- Complexity: O(D) over the worker's attendance rows in that month.
--
-- KNOWN GAPS:
--   - SECURITY INVOKER, relies on worker_attendance RLS. Confirm that
--     the policy scopes by shop ownership of the worker.
CREATE OR REPLACE FUNCTION public.get_worker_monthly_attendance(
  p_worker_id UUID,
  p_month     DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
AS $function$
DECLARE
  result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'days_worked', COALESCE(COUNT(DISTINCT wa.date), 0),
    'total_hours', COALESCE(SUM(wa.total_hours), 0),
    'on_time_rate', COALESCE(ROUND(
      (COUNT(*) FILTER (WHERE wa.status NOT IN ('late', 'absent'))::DECIMAL
      / NULLIF(COUNT(*), 0) * 100
    ), 1), 0),
    'late_arrivals', COALESCE(COUNT(*) FILTER (WHERE wa.status = 'late'), 0),
    'absent_days', COALESCE(COUNT(*) FILTER (WHERE wa.status = 'absent'), 0),
    'avg_hours_per_day', COALESCE(ROUND(AVG(wa.total_hours), 1), 0)
  )
  INTO result
  FROM worker_attendance wa
  WHERE wa.worker_id = p_worker_id
    AND DATE_TRUNC('month', wa.date) = DATE_TRUNC('month', p_month);

  RETURN result;
END;
$function$;

COMMENT ON FUNCTION public.get_worker_monthly_attendance(UUID, DATE) IS
  'Per-worker monthly attendance summary. SECURITY INVOKER — relies on worker_attendance RLS.';
