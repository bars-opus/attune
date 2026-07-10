-- Fix P0-U: performance_alerts leaked every shop's data to any
-- authenticated user via a USING (true) SELECT policy.
--
-- Drops the offending policy; the existing "Shop owners can view their
-- alerts" policy already enforces correct scoping by auth.uid().
--
-- Also tightens column nullability that the live schema left loose:
--   is_read     boolean DEFAULT false  → NOT NULL DEFAULT false
--   created_at  timestamptz DEFAULT now() → NOT NULL DEFAULT now()
-- These are checklist 2.1 (input shape) bugs — the controller assumes
-- both fields are present and dereferences them unconditionally.

DROP POLICY IF EXISTS "Allow all authenticated users to view performance alerts"
  ON public.performance_alerts;

-- Backfill any NULLs introduced under the loose schema.
UPDATE public.performance_alerts SET is_read    = FALSE WHERE is_read    IS NULL;
UPDATE public.performance_alerts SET created_at = now() WHERE created_at IS NULL;

ALTER TABLE public.performance_alerts
  ALTER COLUMN is_read    SET NOT NULL,
  ALTER COLUMN created_at SET NOT NULL;

-- Add an FK to shops so orphaned alerts can't exist (defensive — the
-- generate_performance_alerts logic should already only emit valid
-- shop_ids, but RLS + FK is belt-and-braces against a regression).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'performance_alerts_shop_id_fkey'
  ) THEN
    ALTER TABLE public.performance_alerts
      ADD CONSTRAINT performance_alerts_shop_id_fkey
      FOREIGN KEY (shop_id) REFERENCES public.shops(id) ON DELETE CASCADE;
  END IF;
END $$;

COMMENT ON TABLE public.performance_alerts IS
  'Shop performance alerts. RLS-gated by shop ownership via auth.uid(). Read by InsightsScreen.';
