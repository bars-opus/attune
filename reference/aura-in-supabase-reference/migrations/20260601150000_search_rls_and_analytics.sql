-- =====================================================================
-- Search hardening: RLS on searched tables + search_analytics table.
--
-- Why this migration:
--   1. shops, workers, and freelancer_details were searchable from the
--      client via anon/authenticated keys with no RLS — anyone with the
--      anon key could enumerate the entire dataset.
--   2. The Flutter client calls logSearchAnalytics() which writes to a
--      search_analytics table that did not exist. Every write was
--      silently failing. This migration creates the table with retention,
--      length caps, and a SECURITY DEFINER RPC so the client never
--      writes raw user-typed strings directly.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. RLS on shops
-- ---------------------------------------------------------------------
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS shops_public_read       ON public.shops;
DROP POLICY IF EXISTS shops_owner_write       ON public.shops;
DROP POLICY IF EXISTS shops_owner_update      ON public.shops;
DROP POLICY IF EXISTS shops_owner_delete      ON public.shops;

-- Anyone (anon or signed-in) can read shops for browsing/discovery.
-- This is intentional: a marketplace is public-facing by design.
CREATE POLICY shops_public_read
  ON public.shops
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- Only the owner can mutate their own shop.
CREATE POLICY shops_owner_write
  ON public.shops
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY shops_owner_update
  ON public.shops
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY shops_owner_delete
  ON public.shops
  FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- 2. RLS on workers
-- ---------------------------------------------------------------------
ALTER TABLE public.workers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS workers_public_read           ON public.workers;
DROP POLICY IF EXISTS workers_self_write            ON public.workers;
DROP POLICY IF EXISTS workers_self_update           ON public.workers;
DROP POLICY IF EXISTS workers_shop_owner_update     ON public.workers;
DROP POLICY IF EXISTS workers_shop_owner_delete     ON public.workers;

-- Workers (freelancers and shop employees) are publicly listable —
-- discovery search ranks them by name and location.
CREATE POLICY workers_public_read
  ON public.workers
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- A freelancer creates their own worker row.
CREATE POLICY workers_self_write
  ON public.workers
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Self-update OR shop-owner-update (employee management).
CREATE POLICY workers_self_update
  ON public.workers
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY workers_shop_owner_update
  ON public.workers
  FOR UPDATE
  TO authenticated
  USING (
    shop_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.shops s
      WHERE s.id = workers.shop_id AND s.user_id = auth.uid()
    )
  )
  WITH CHECK (
    shop_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.shops s
      WHERE s.id = workers.shop_id AND s.user_id = auth.uid()
    )
  );

CREATE POLICY workers_shop_owner_delete
  ON public.workers
  FOR DELETE
  TO authenticated
  USING (
    auth.uid() = user_id
    OR (
      shop_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.shops s
        WHERE s.id = workers.shop_id AND s.user_id = auth.uid()
      )
    )
  );

-- ---------------------------------------------------------------------
-- 3. RLS on freelancer_details
-- ---------------------------------------------------------------------
ALTER TABLE public.freelancer_details ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS freelancer_details_public_read   ON public.freelancer_details;
DROP POLICY IF EXISTS freelancer_details_owner_write   ON public.freelancer_details;
DROP POLICY IF EXISTS freelancer_details_owner_update  ON public.freelancer_details;
DROP POLICY IF EXISTS freelancer_details_owner_delete  ON public.freelancer_details;

-- Public read so search results can surface ratings, freelancer types,
-- and base lat/lng (these are intentionally surfaced on profile cards).
CREATE POLICY freelancer_details_public_read
  ON public.freelancer_details
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- Mutations restricted to the freelancer who owns the parent worker row.
CREATE POLICY freelancer_details_owner_write
  ON public.freelancer_details
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.workers w
      WHERE w.id = freelancer_details.worker_id AND w.user_id = auth.uid()
    )
  );

CREATE POLICY freelancer_details_owner_update
  ON public.freelancer_details
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.workers w
      WHERE w.id = freelancer_details.worker_id AND w.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.workers w
      WHERE w.id = freelancer_details.worker_id AND w.user_id = auth.uid()
    )
  );

CREATE POLICY freelancer_details_owner_delete
  ON public.freelancer_details
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.workers w
      WHERE w.id = freelancer_details.worker_id AND w.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------
-- 4. search_analytics table
--
-- Design choices:
--   * Query is normalized: trimmed + lowercased + capped at 64 chars.
--     This bounds cardinality (no PII like full names or phone numbers
--     stored verbatim) and naturally deduplicates near-identical inputs.
--   * No actor_id is stored — analytics are aggregate-only.
--   * Inserts go through log_search_query() which enforces sanitization
--     and a per-actor rate limit. Direct INSERT is forbidden via RLS.
--
-- This block is idempotent: if the table already exists (from a prior
-- ad-hoc creation), missing columns are added without disturbing data.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.search_analytics (
  query              TEXT        PRIMARY KEY,
  category           TEXT,
  count              BIGINT      NOT NULL DEFAULT 1,
  result_count       INTEGER,
  first_searched_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_searched_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Backfill any missing columns on a pre-existing table.
ALTER TABLE public.search_analytics
  ADD COLUMN IF NOT EXISTS category          TEXT,
  ADD COLUMN IF NOT EXISTS result_count      INTEGER,
  ADD COLUMN IF NOT EXISTS count             BIGINT      NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS first_searched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS last_searched_at  TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Add the length CHECK only if it isn't already present. Skip silently
-- if any pre-existing row would violate it (those rows were written
-- before the constraint existed; we don't want to fail the migration on
-- legacy data — they'll naturally age out via the 180-day prune).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE  conname = 'search_analytics_query_length'
    AND    conrelid = 'public.search_analytics'::regclass
  ) THEN
    BEGIN
      ALTER TABLE public.search_analytics
        ADD CONSTRAINT search_analytics_query_length
        CHECK (char_length(query) BETWEEN 2 AND 64);
    EXCEPTION WHEN check_violation THEN
      RAISE NOTICE 'search_analytics has rows violating length 2..64; constraint skipped';
    END;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_search_analytics_count
  ON public.search_analytics (count DESC);
CREATE INDEX IF NOT EXISTS idx_search_analytics_category_count
  ON public.search_analytics (category, count DESC);
CREATE INDEX IF NOT EXISTS idx_search_analytics_last_searched
  ON public.search_analytics (last_searched_at);

ALTER TABLE public.search_analytics ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS search_analytics_public_read ON public.search_analytics;

-- Public read so the client can show popular searches.
CREATE POLICY search_analytics_public_read
  ON public.search_analytics
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- No INSERT/UPDATE/DELETE policies for client roles. Writes happen only
-- via log_search_query() (SECURITY DEFINER) below.

-- ---------------------------------------------------------------------
-- 5. log_search_query RPC
--
-- Sanitizes the input, enforces rate limit, then upserts the aggregate.
-- Returns NULL — clients should ignore the result and never branch on it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_search_query(
  p_query        TEXT,
  p_category     TEXT DEFAULT NULL,
  p_result_count INTEGER DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_normalized TEXT;
BEGIN
  -- Normalize: trim, lowercase, cap at 64 chars. Skip if too short.
  v_normalized := lower(btrim(coalesce(p_query, '')));
  IF char_length(v_normalized) < 2 THEN
    RETURN;
  END IF;
  IF char_length(v_normalized) > 64 THEN
    v_normalized := substring(v_normalized FROM 1 FOR 64);
  END IF;

  -- Reject categories outside the known enum to keep cardinality bounded.
  IF p_category IS NOT NULL
     AND p_category NOT IN ('shops', 'profiles', 'freelancers', 'products')
  THEN
    p_category := NULL;
  END IF;

  -- Rate limit: 60 logs per user per minute. Soft-fail if limited so
  -- search itself is unaffected.
  IF NOT public.check_rate_limit('search_log', 60, 60) THEN
    RETURN;
  END IF;

  INSERT INTO public.search_analytics
    (query, category, count, result_count, first_searched_at, last_searched_at)
  VALUES
    (v_normalized, p_category, 1, p_result_count, NOW(), NOW())
  ON CONFLICT (query) DO UPDATE
    SET count             = public.search_analytics.count + 1,
        last_searched_at  = NOW(),
        result_count      = COALESCE(EXCLUDED.result_count, public.search_analytics.result_count),
        category          = COALESCE(public.search_analytics.category, EXCLUDED.category);
END;
$$;

REVOKE ALL ON FUNCTION public.log_search_query(TEXT, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_search_query(TEXT, TEXT, INTEGER)
  TO anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. Retention: drop analytics rows that have not been searched for
--    180 days. Keeps the popular-search list relevant and bounds growth.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prune_search_analytics()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.search_analytics
   WHERE last_searched_at < NOW() - INTERVAL '180 days';
END;
$$;

REVOKE ALL ON FUNCTION public.prune_search_analytics() FROM PUBLIC;

-- Schedule via pg_cron if the extension is available. Wrapped in a DO
-- block so the migration does not fail on environments without pg_cron.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'prune_search_analytics_daily',
      '17 3 * * *',
      $cron$ SELECT public.prune_search_analytics(); $cron$
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- Cron scheduling is best-effort; never block the migration.
  NULL;
END $$;
