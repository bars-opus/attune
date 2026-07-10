-- ============================================================
-- Marketplace — Storage policy + retention jobs
-- ============================================================
-- Closes the last server-side gaps:
--   1. Storage bucket policy for product-images (size cap +
--      MIME whitelist + per-shop folder isolation).
--   2. pg_cron schedule for prune_rate_limit_log.
--   3. Audit log retention (180 days) — long enough for incident
--      forensics, short enough that the table doesn't grow forever.
--
-- The pg_cron and storage bits use extensions that may not be
-- enabled by default. Each section is guarded so the migration
-- still succeeds (with a NOTICE) if an extension is unavailable;
-- you can re-run after enabling.
-- ============================================================

-- ── 1. Ensure required extensions (best-effort) ──────────────

DO $$ BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
EXCEPTION WHEN insufficient_privilege OR feature_not_supported THEN
  RAISE NOTICE 'pg_cron extension not available — schedule cron jobs manually via Dashboard';
END $$;

-- ── 2. Storage bucket policy for product-images ──────────────
-- Path layout: products/<shop_id>/<product_id>/<timestamp>.<ext>
--   (Set by SupabaseProductRepository._validateImageFile.)
-- Policy: a user may insert into / update / delete a file whose
-- second path segment is a shop they own (shops.user_id = auth.uid()).
-- Anyone authenticated may read.

-- Drop any old policies before re-creating so this migration is idempotent.
DROP POLICY IF EXISTS "product_images_select_public"   ON storage.objects;
DROP POLICY IF EXISTS "product_images_insert_owner"    ON storage.objects;
DROP POLICY IF EXISTS "product_images_update_owner"    ON storage.objects;
DROP POLICY IF EXISTS "product_images_delete_owner"    ON storage.objects;

CREATE POLICY "product_images_select_public"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'product-images');

CREATE POLICY "product_images_insert_owner"
  ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'product-images'
    AND (storage.foldername(name))[1] = 'products'  -- enforce path prefix
    AND (storage.foldername(name))[2] IN (          -- shop_id segment
      SELECT id::text FROM public.shops WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "product_images_update_owner"
  ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'product-images'
    AND (storage.foldername(name))[2] IN (
      SELECT id::text FROM public.shops WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "product_images_delete_owner"
  ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'product-images'
    AND (storage.foldername(name))[2] IN (
      SELECT id::text FROM public.shops WHERE user_id = auth.uid()
    )
  );

-- Bucket-level size + MIME limits. If the bucket doesn't exist yet
-- this UPDATE is a no-op; the Dashboard "Create bucket" UI is still
-- the canonical place to provision it.
DO $$ BEGIN
  UPDATE storage.buckets
  SET    file_size_limit = 5 * 1024 * 1024,  -- 5 MB, mirrors client cap
         allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp']
  WHERE  id = 'product-images';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'Could not set bucket limits — set file_size_limit=5MB and allowed_mime_types in Dashboard';
END $$;

-- ── 3. Audit log retention ───────────────────────────────────

CREATE OR REPLACE FUNCTION prune_marketplace_audit_log()
RETURNS VOID LANGUAGE SQL AS $$
  DELETE FROM marketplace_audit_log
  WHERE created_at < now() - INTERVAL '180 days';
$$;

-- ── 4. Schedule the prune jobs via pg_cron ───────────────────

DO $$ BEGIN
  -- Daily at 03:00 UTC. Idempotent — unschedule before re-scheduling.
  PERFORM cron.unschedule('marketplace_prune_rate_limit');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
  PERFORM cron.unschedule('marketplace_prune_audit');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
  PERFORM cron.schedule(
    'marketplace_prune_rate_limit',
    '0 3 * * *',
    $cron$ SELECT public.prune_rate_limit_log(); $cron$
  );
  PERFORM cron.schedule(
    'marketplace_prune_audit',
    '15 3 * * *',
    $cron$ SELECT public.prune_marketplace_audit_log(); $cron$
  );
EXCEPTION WHEN undefined_function OR undefined_table THEN
  RAISE NOTICE 'pg_cron not installed — run prune_rate_limit_log() and prune_marketplace_audit_log() from any scheduler';
END $$;

-- ============================================================
-- End of storage + retention migration.
-- ============================================================
