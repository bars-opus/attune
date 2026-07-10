-- ============================================================
-- Patch: fix get_available_workers column bugs
-- Deployed: 2026-05-25
--
-- Two bugs introduced in 20260517010000_booking_schema.sql:
--   1. w.rating_average — column does not exist on workers table.
--      Rating is computed from reviews, not stored on the row.
--      Fixed: emit NULL so the Dart WorkerDTO nullable field works.
--   2. bs.end_time — booking_services has no end_time column.
--      The window is start_time + duration_minutes.
--      Fixed: compute end from start_time + duration_minutes directly.
-- ============================================================

CREATE OR REPLACE FUNCTION get_available_workers(
  p_worker_ids UUID[],
  p_start_time TIMESTAMPTZ,
  p_end_time   TIMESTAMPTZ
)
RETURNS SETOF JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'id',                w.id,
    'name',              w.name,
    'bio',               w.bio,
    'profile_image_url', w.profile_image_url,
    'specialties',       COALESCE(w.specialties, ARRAY[]::TEXT[]),
    'rating_average',    NULL,
    'is_active',         w.is_active
  )
  FROM   workers w
  WHERE  w.id = ANY (p_worker_ids)
    AND  COALESCE(w.is_active, true) = true
    AND  NOT EXISTS (
      SELECT 1
      FROM   booking_services bs
      JOIN   bookings b ON b.id = bs.booking_id
      WHERE  bs.worker_id = w.id
        AND  b.status NOT IN ('cancelled', 'no_show')
        AND  tstzrange(
               bs.start_time,
               bs.start_time + (bs.duration_minutes || ' minutes')::INTERVAL,
               '[)'
             ) && tstzrange(p_start_time, p_end_time, '[)')
    )
    AND  NOT EXISTS (
      SELECT 1
      FROM   worker_unavailability wu
      WHERE  wu.worker_id = w.id
        AND  tstzrange(wu.start_time, wu.end_time, '[)') && tstzrange(p_start_time, p_end_time, '[)')
    );
$$;

REVOKE ALL ON FUNCTION get_available_workers(UUID[], TIMESTAMPTZ, TIMESTAMPTZ) FROM public;
GRANT EXECUTE ON FUNCTION get_available_workers(UUID[], TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
