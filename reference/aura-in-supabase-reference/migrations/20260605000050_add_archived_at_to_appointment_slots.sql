-- Add soft-delete column on appointment_slots, plus a partial index that
-- keeps the filter-cascade queries (see 20260605000300) fast by
-- pre-pruning archived rows. Idempotent via IF NOT EXISTS.
--
-- Phase 11 locked correction 3: `is_active` is formally deprecated.
-- The legacy column at appointment_slots.is_active is referenced by
-- create-booking/index.ts:610 but its filter has been commented out
-- since the function shipped. We do NOT touch it. New code reads and
-- writes `archived_at` exclusively.

ALTER TABLE public.appointment_slots
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

-- Partial index: every cascaded SELECT in 20260605000300 carries
-- `archived_at IS NULL`, and ServiceManagementScreen's list view (Dart
-- side) also filters on it. A partial index on shop_id keeps these
-- queries O(active-rows) without bloating the index with archived rows.
CREATE INDEX IF NOT EXISTS idx_appointment_slots_active
  ON public.appointment_slots (shop_id)
  WHERE archived_at IS NULL;

COMMENT ON COLUMN public.appointment_slots.archived_at IS
  'Soft-delete timestamp. NULL = active. Set by archive_appointment_slot RPC. is_active is deprecated as of 2026-06-05; do not use.';
