-- ============================================================
-- Patch: create worker_unavailability table
-- Deployed: 2026-05-25
--
-- get_available_workers references this table but it was never
-- created in any migration. When p_worker_ids is empty Postgres
-- short-circuits (w.id = ANY('{}') is always false) so the NOT
-- EXISTS clause is never evaluated — hence no-worker-selected
-- worked fine. When a worker IS selected, Postgres finds the row,
-- evaluates the NOT EXISTS subquery, and fails with 42P01 (relation
-- does not exist).
--
-- This table is also used directly by Dart code in
-- supabase_appointment_worker_repository.dart.
-- ============================================================

CREATE TABLE IF NOT EXISTS worker_unavailability (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id  UUID        NOT NULL,
  start_time TIMESTAMPTZ NOT NULL,
  end_time   TIMESTAMPTZ NOT NULL,
  reason     TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT worker_unavailability_end_after_start CHECK (end_time > start_time)
);

CREATE INDEX IF NOT EXISTS idx_worker_unavailability_worker
  ON worker_unavailability (worker_id, start_time, end_time);
