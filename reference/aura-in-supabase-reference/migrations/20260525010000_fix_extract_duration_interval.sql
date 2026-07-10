-- ============================================================
-- Patch: add INTERVAL overload for extract_duration_minutes
-- Deployed: 2026-05-25
--
-- appointment_slots.duration is stored as PostgreSQL INTERVAL,
-- but extract_duration_minutes only accepted TEXT. PostgreSQL
-- routes by argument type (42883 = no matching function signature).
-- Adding an INTERVAL overload that extracts minutes directly.
-- ============================================================

CREATE OR REPLACE FUNCTION extract_duration_minutes(p_duration INTERVAL)
RETURNS INT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT EXTRACT(epoch FROM p_duration)::INT / 60;
$$;
