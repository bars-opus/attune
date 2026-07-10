-- Backfill: performance_alerts table — lifted from live DB on 2026-06-03.
--
-- ─────────────────────────────────────────────────────────────────
-- SECURITY GAP — this migration preserves a 🔴 P0-U leak
-- ─────────────────────────────────────────────────────────────────
-- The live policy "Allow all authenticated users to view performance
-- alerts" uses USING (true), meaning ANY signed-in user can read
-- EVERY shop's alerts. That is a confirmed authorization bug. It is
-- preserved here byte-for-byte because changing it in a backfill
-- would be a silent behaviour change. Fix in a follow-up migration:
--
--   DROP POLICY "Allow all authenticated users to view performance alerts"
--     ON public.performance_alerts;
--
-- The other two policies ("Shop owners can view their alerts" /
-- "Shop owners can update their alerts") correctly scope by
-- shop ownership and should remain.
--
-- Checklist v3.1 mapping:
--   1.4  Authorization at every access point — FAIL (USING (true))
--   2.4  Error messages don't leak — N/A (table, not RPC)
--   3.3  Indexes — pkey + shop_id + is_read + created_at ✅
--   4.4  PII in logs — `message`/`title` are user-facing strings;
--        scrub before log shipping.

CREATE TABLE IF NOT EXISTS public.performance_alerts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id           UUID NOT NULL,
  category          TEXT NOT NULL,
  severity          TEXT NOT NULL,
  title             TEXT NOT NULL,
  message           TEXT NOT NULL,
  current_value     NUMERIC,
  threshold         NUMERIC,
  suggested_action  TEXT,
  is_read           BOOLEAN DEFAULT FALSE,
  created_at        TIMESTAMPTZ DEFAULT now(),
  resolved_at       TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_performance_alerts_shop_id
  ON public.performance_alerts USING btree (shop_id);

CREATE INDEX IF NOT EXISTS idx_performance_alerts_is_read
  ON public.performance_alerts USING btree (is_read);

CREATE INDEX IF NOT EXISTS idx_performance_alerts_created_at
  ON public.performance_alerts USING btree (created_at);

-- Note: live schema has NO FK on shop_id and NO NOT NULL on is_read /
-- created_at / resolved_at except as defaults. Reproduced exactly.

ALTER TABLE public.performance_alerts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname='Allow all authenticated users to view performance alerts'
  ) THEN
    -- 🔴 P0-U LEAK — see header. Preserved for parity with prod.
    CREATE POLICY "Allow all authenticated users to view performance alerts"
      ON public.performance_alerts
      FOR SELECT
      TO authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname='Shop owners can view their alerts'
  ) THEN
    CREATE POLICY "Shop owners can view their alerts"
      ON public.performance_alerts
      FOR SELECT
      TO authenticated
      USING (shop_id IN (SELECT id FROM public.shops WHERE user_id = auth.uid()));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname='Shop owners can update their alerts'
  ) THEN
    CREATE POLICY "Shop owners can update their alerts"
      ON public.performance_alerts
      FOR UPDATE
      TO authenticated
      USING (shop_id IN (SELECT id FROM public.shops WHERE user_id = auth.uid()));
  END IF;
END $$;

COMMENT ON TABLE public.performance_alerts IS
  'Shop performance alerts surface in InsightsScreen. RLS POLICY GAP: USING (true) SELECT policy leaks every shop''s alerts to any authenticated user. Fix in a follow-up migration.';
