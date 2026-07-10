-- Lost-booking rate metric — three read-only aggregator RPCs powering the
-- new Analytics > Revenue headline card.
--
-- All three follow the hardening template established by
-- 20260603001500_harden_dashboard_rpcs.sql:
--   * SECURITY DEFINER + SET search_path = public
--   * Authz first (EXISTS (SELECT 1 FROM shops WHERE id = p_shop_id AND
--     user_id = auth.uid())) before any input-range validation, so an
--     unauthorized caller can't probe parameter shapes via 22023 vs 42501
--   * Range/argument validation uses 22023 + HINT for every exception
--   * REVOKE ALL FROM PUBLIC + GRANT EXECUTE TO authenticated
--   * Sanitized error messages — no balance/id leakage in exception text
--
-- Definitions (locked in 10-SPEC.md):
--   honoured = bookings.status = 'completed'
--   lost     = bookings.status IN ('cancelled','no_show')
--   universe = bookings whose terminal status is one of the above; we
--              bucket bookings by start_time, NOT cancelled_at, so a
--              cancelled future booking belongs to its scheduled period.
--
-- Guest handling (10-RESEARCH.md §2):
--   Summary and weekly_series include guests (user_id IS NULL) — they're
--   part of the shop's booking population and revenue exposure.
--   Offenders excludes guests — there's no joinable identity to surface.
--
-- last_lost_at fix (10-RESEARCH.md §3):
--   mark_booking_no_show sets only `updated_at`, NOT `cancelled_at`. The
--   offenders RPC's MAX(last_lost_at) therefore uses a CASE expression
--   to pick the right column per status. The naive MAX(cancelled_at)
--   silently dropped every no-show timestamp.
--
-- Big-O (each RPC):
--   O(B) over bookings in the lookback window for the shop. Realistic
--   access path is idx_bookings_shop_id (shop_id, start_time DESC).
--   Verified by 10-PLAN.md Task 1.2's EXPLAIN ANALYZE step at deploy time.

-- ──────────────────────────────────────────────────────────────────────
-- 1. get_lost_booking_summary(shop_id, period_days) -> JSONB
-- ──────────────────────────────────────────────────────────────────────
-- Returns headline KPI + period-over-period delta:
--   {
--     period_days, window_start, window_end,
--     current:  { total, honoured, cancelled, no_show, lost_revenue },
--     previous: { total, honoured, cancelled, no_show }
--   }
CREATE OR REPLACE FUNCTION public.get_lost_booking_summary(
  p_shop_id     UUID,
  p_period_days INTEGER DEFAULT 7
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_owns_shop  BOOLEAN;
  v_now        TIMESTAMPTZ := now();
  v_curr_start TIMESTAMPTZ;
  v_prev_start TIMESTAMPTZ;
  result       JSONB;
BEGIN
  -- Authz first (template rule, prevents parameter-shape probing).
  SELECT EXISTS (
    SELECT 1 FROM shops WHERE id = p_shop_id AND user_id = auth.uid()
  ) INTO v_owns_shop;
  IF NOT v_owns_shop THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = '42501';
  END IF;

  -- Range validation.
  IF p_period_days IS NULL OR p_period_days < 1 OR p_period_days > 90 THEN
    RAISE EXCEPTION 'invalid_period' USING ERRCODE = '22023', HINT = 'RANGE_1_90';
  END IF;

  v_curr_start := v_now - (p_period_days || ' days')::INTERVAL;
  v_prev_start := v_curr_start - (p_period_days || ' days')::INTERVAL;

  WITH buckets AS (
    SELECT
      CASE
        WHEN start_time >= v_curr_start                              THEN 'curr'
        WHEN start_time >= v_prev_start AND start_time < v_curr_start THEN 'prev'
      END AS bucket,
      status,
      total_amount
    FROM bookings
    WHERE shop_id = p_shop_id
      AND start_time >= v_prev_start
      AND start_time <  v_now
      AND status IN ('completed','cancelled','no_show')
  )
  SELECT jsonb_build_object(
    'period_days',  p_period_days,
    'window_start', v_curr_start,
    'window_end',   v_now,
    'current', jsonb_build_object(
      'total',        COUNT(*) FILTER (WHERE bucket = 'curr'),
      'honoured',     COUNT(*) FILTER (WHERE bucket = 'curr' AND status = 'completed'),
      'cancelled',    COUNT(*) FILTER (WHERE bucket = 'curr' AND status = 'cancelled'),
      'no_show',      COUNT(*) FILTER (WHERE bucket = 'curr' AND status = 'no_show'),
      'lost_revenue', COALESCE(
                        SUM(total_amount) FILTER (
                          WHERE bucket = 'curr' AND status IN ('cancelled','no_show')
                        ), 0)
    ),
    'previous', jsonb_build_object(
      'total',     COUNT(*) FILTER (WHERE bucket = 'prev'),
      'honoured',  COUNT(*) FILTER (WHERE bucket = 'prev' AND status = 'completed'),
      'cancelled', COUNT(*) FILTER (WHERE bucket = 'prev' AND status = 'cancelled'),
      'no_show',   COUNT(*) FILTER (WHERE bucket = 'prev' AND status = 'no_show')
    )
  ) INTO result
  FROM buckets;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_lost_booking_summary(UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_lost_booking_summary(UUID, INTEGER) TO authenticated;
COMMENT ON FUNCTION public.get_lost_booking_summary(UUID, INTEGER) IS
  'Lost-booking headline KPI + period-over-period delta. Buckets by start_time. Includes guest bookings. SECURITY DEFINER with auth.uid() ownership check. O(B) over bookings in 2x period window.';

-- ──────────────────────────────────────────────────────────────────────
-- 2. get_lost_booking_weekly_series(shop_id, weeks) -> JSONB
-- ──────────────────────────────────────────────────────────────────────
-- Sparkline data: rate per ISO week, oldest first, last N weeks.
CREATE OR REPLACE FUNCTION public.get_lost_booking_weekly_series(
  p_shop_id UUID,
  p_weeks   INTEGER DEFAULT 12
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_owns_shop BOOLEAN;
  v_start     DATE;
  result      JSONB;
BEGIN
  -- Authz first.
  SELECT EXISTS (
    SELECT 1 FROM shops WHERE id = p_shop_id AND user_id = auth.uid()
  ) INTO v_owns_shop;
  IF NOT v_owns_shop THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = '42501';
  END IF;

  -- Range validation.
  IF p_weeks IS NULL OR p_weeks < 1 OR p_weeks > 52 THEN
    RAISE EXCEPTION 'invalid_weeks' USING ERRCODE = '22023', HINT = 'RANGE_1_52';
  END IF;

  v_start := (CURRENT_DATE - (p_weeks * 7 || ' days')::INTERVAL)::DATE;

  WITH weekly AS (
    SELECT
      EXTRACT(ISOYEAR FROM start_time)::INT AS iso_year,
      EXTRACT(WEEK    FROM start_time)::INT AS iso_week,
      DATE_TRUNC('week', start_time)::DATE  AS week_start,
      COUNT(*)                              AS total,
      COUNT(*) FILTER (WHERE status IN ('cancelled','no_show')) AS lost
    FROM bookings
    WHERE shop_id = p_shop_id
      AND start_time >= v_start
      AND start_time <  now()
      AND status IN ('completed','cancelled','no_show')
    GROUP BY 1, 2, 3
  )
  SELECT jsonb_build_object(
    'weeks', COALESCE(jsonb_agg(
      jsonb_build_object(
        'iso_year',   iso_year,
        'iso_week',   iso_week,
        'start_date', week_start,
        'total',      total,
        'lost',       lost,
        'rate',       ROUND(lost::NUMERIC / NULLIF(total, 0), 4)
      ) ORDER BY iso_year, iso_week
    ), '[]'::jsonb)
  ) INTO result
  FROM weekly;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_lost_booking_weekly_series(UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_lost_booking_weekly_series(UUID, INTEGER) TO authenticated;
COMMENT ON FUNCTION public.get_lost_booking_weekly_series(UUID, INTEGER) IS
  'Per-ISO-week lost-booking rate series for sparkline. Includes guest bookings. Weeks capped at 52. SECURITY DEFINER. O(B) over bookings in window.';

-- ──────────────────────────────────────────────────────────────────────
-- 3. get_lost_booking_offenders(shop_id, lookback_days, min_lost) -> JSONB
-- ──────────────────────────────────────────────────────────────────────
-- Repeat-offender clients in the lookback. Capped at 50 rows.
--
-- last_lost_at uses a CASE per status (RESEARCH §3) because no_show
-- bookings have NO cancelled_at — only updated_at is set by
-- mark_booking_no_show. Naive MAX(cancelled_at) would silently drop
-- every no-show timestamp.
--
-- Guest exclusion is intentional (RESEARCH §2) — guests have no
-- joinable identity to surface. Documented for the next maintainer.
CREATE OR REPLACE FUNCTION public.get_lost_booking_offenders(
  p_shop_id       UUID,
  p_lookback_days INTEGER DEFAULT 90,
  p_min_lost      INTEGER DEFAULT 2
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_owns_shop BOOLEAN;
  v_since     TIMESTAMPTZ;
  result      JSONB;
BEGIN
  -- Authz first.
  SELECT EXISTS (
    SELECT 1 FROM shops WHERE id = p_shop_id AND user_id = auth.uid()
  ) INTO v_owns_shop;
  IF NOT v_owns_shop THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = '42501';
  END IF;

  -- Range validation.
  IF p_lookback_days IS NULL OR p_lookback_days < 7 OR p_lookback_days > 365 THEN
    RAISE EXCEPTION 'invalid_lookback' USING ERRCODE = '22023', HINT = 'RANGE_7_365';
  END IF;
  IF p_min_lost IS NULL OR p_min_lost < 1 OR p_min_lost > 50 THEN
    RAISE EXCEPTION 'invalid_min_lost' USING ERRCODE = '22023', HINT = 'RANGE_1_50';
  END IF;

  v_since := now() - (p_lookback_days || ' days')::INTERVAL;

  -- per_client: aggregate per identified client. Excludes guests
  -- (user_id IS NULL) — see header comment.
  -- top_offenders: cap at 50 rows server-side (checklist 2.5).
  WITH per_client AS (
    SELECT
      b.user_id,
      COUNT(*) AS total_bookings,
      COUNT(*) FILTER (WHERE b.status IN ('cancelled','no_show')) AS lost_bookings,
      MAX(CASE
            WHEN b.status = 'cancelled' THEN b.cancelled_at
            WHEN b.status = 'no_show'   THEN b.updated_at
          END) AS last_lost_at
    FROM bookings b
    WHERE b.shop_id = p_shop_id
      AND b.start_time >= v_since
      AND b.user_id IS NOT NULL
      AND b.status IN ('completed','cancelled','no_show')
    GROUP BY b.user_id
    HAVING COUNT(*) FILTER (WHERE b.status IN ('cancelled','no_show')) >= p_min_lost
  ),
  top_offenders AS (
    SELECT *
    FROM per_client
    ORDER BY lost_bookings DESC, last_lost_at DESC NULLS LAST
    LIMIT 50
  )
  SELECT jsonb_build_object(
    'offenders', COALESCE(jsonb_agg(
      jsonb_build_object(
        'client_id',      t.user_id,
        'display_name',   COALESCE(p.display_name, p.username, 'Client'),
        'avatar_url',     p.avatar_url,
        'total_bookings', t.total_bookings,
        'lost_bookings',  t.lost_bookings,
        'lost_rate',      ROUND(t.lost_bookings::NUMERIC / NULLIF(t.total_bookings, 0), 4),
        'last_lost_at',   t.last_lost_at
      ) ORDER BY t.lost_bookings DESC, t.last_lost_at DESC NULLS LAST
    ), '[]'::jsonb)
  ) INTO result
  FROM top_offenders t
  LEFT JOIN profiles p ON p.id = t.user_id;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_lost_booking_offenders(UUID, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_lost_booking_offenders(UUID, INTEGER, INTEGER) TO authenticated;
COMMENT ON FUNCTION public.get_lost_booking_offenders(UUID, INTEGER, INTEGER) IS
  'Top 50 repeat-offender clients by lost-booking count in the lookback window. Excludes guests by design (no joinable identity). last_lost_at uses status-aware column (cancelled_at for cancellations, updated_at for no_shows). SECURITY DEFINER. O(B + C log C).';
