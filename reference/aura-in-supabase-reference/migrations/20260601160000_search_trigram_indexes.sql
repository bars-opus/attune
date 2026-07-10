-- =====================================================================
-- Search performance: pg_trgm + GIN trigram indexes for ILIKE queries.
--
-- Without these, every ILIKE '%foo%' is a sequential scan. With them,
-- Postgres can use the index for substring matches in O(log n)-ish time
-- on rows where the trigrams of the pattern are present.
--
-- The indexes use gin_trgm_ops so both ILIKE and pg_trgm operators
-- (similarity, %, <%) are supported for future ranking.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Shops: searched by shop_name
CREATE INDEX IF NOT EXISTS idx_shops_shop_name_trgm
  ON public.shops
  USING GIN (shop_name gin_trgm_ops);

-- Workers: searched by name (freelancer + employee discovery)
CREATE INDEX IF NOT EXISTS idx_workers_name_trgm
  ON public.workers
  USING GIN (name gin_trgm_ops);

-- Profiles: searched by username, display_name, bio
CREATE INDEX IF NOT EXISTS idx_profiles_username_trgm
  ON public.profiles
  USING GIN (username gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_profiles_display_name_trgm
  ON public.profiles
  USING GIN (display_name gin_trgm_ops);

-- Bio is large free-text; the index is bigger and slower to maintain
-- but ILIKE on it without an index is genuinely catastrophic at scale.
-- If write throughput on profiles becomes a problem, drop this one
-- first and limit search to username + display_name.
CREATE INDEX IF NOT EXISTS idx_profiles_bio_trgm
  ON public.profiles
  USING GIN (bio gin_trgm_ops);
