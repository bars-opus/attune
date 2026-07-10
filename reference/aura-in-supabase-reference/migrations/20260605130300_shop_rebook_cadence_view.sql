-- Phase 12 — shop_rebook_cadence materialized view
--
-- Per-shop median booking gap (days). Computed over completed bookings
-- per repeat-client. Floor 7d, ceiling 90d, default 30d when sample
-- size < 5 (RESEARCH §8). Recomputed nightly via pg_cron.
--
-- UNIQUE index on shop_id is required for REFRESH ... CONCURRENTLY.
--
-- Consumed by enqueue_rebook_nudges() at Phase 12 Wave 3.

CREATE MATERIALIZED VIEW IF NOT EXISTS public.shop_rebook_cadence AS
WITH client_intervals AS (
  SELECT
    b.shop_id,
    COALESCE(b.user_id::text, b.guest_profile_id::text) AS client_id,
    b.start_time,
    EXTRACT(EPOCH FROM (
      b.start_time - LAG(b.start_time) OVER (
        PARTITION BY b.shop_id, COALESCE(b.user_id::text, b.guest_profile_id::text)
        ORDER BY b.start_time
      )
    )) / 86400.0 AS gap_days
  FROM public.bookings b
  WHERE b.status = 'completed'
),
shop_gaps AS (
  SELECT shop_id, gap_days
  FROM client_intervals
  WHERE gap_days IS NOT NULL
    AND gap_days BETWEEN 1 AND 180   -- drop outliers
)
SELECT
  s.id AS shop_id,
  CASE
    WHEN COUNT(g.gap_days) < 5 THEN 30
    ELSE GREATEST(7, LEAST(90,
      (percentile_cont(0.5) WITHIN GROUP (ORDER BY g.gap_days))::int))
  END AS median_gap_days,
  COUNT(g.gap_days) AS sample_size
FROM public.shops s
LEFT JOIN shop_gaps g ON g.shop_id = s.id
GROUP BY s.id;

CREATE UNIQUE INDEX IF NOT EXISTS shop_rebook_cadence_pk
  ON public.shop_rebook_cadence (shop_id);

COMMENT ON MATERIALIZED VIEW public.shop_rebook_cadence IS
  'Per-shop median booking gap (days). Floor 7d, ceiling 90d, default 30d when <5 samples. Recomputed nightly by pg_cron. Consumed by enqueue_rebook_nudges. Phase 12.';

-- Nightly refresh. Guard pg_cron extension presence (RESEARCH §14
-- confirmed installed in dev).
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'refresh-shop-rebook-cadence',
      '15 3 * * *',
      $cron$REFRESH MATERIALIZED VIEW CONCURRENTLY public.shop_rebook_cadence$cron$
    );
  ELSE
    RAISE NOTICE 'pg_cron not installed — refresh-shop-rebook-cadence not scheduled';
  END IF;
END $$;
