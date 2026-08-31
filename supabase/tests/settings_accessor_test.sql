-- The deployment settings accessor.
--
-- Every cron job and every enqueue trigger reaches the Edge Functions
-- through these two values. They used to come from app.settings.*, set
-- with ALTER DATABASE -- which cannot be run on a managed Supabase
-- project, because the SQL editor's `postgres` role is not the database
-- owner. The setting was therefore never present in production: all 21
-- cron jobs failed on every run, and the enqueue triggers, which skip
-- silently when the value is NULL, no-opped for the project's entire
-- lifetime with nothing to show for it.
--
-- These tests exist because that failure was invisible. Cron failures go
-- to cron.job_run_details, which nothing reads, and the triggers were
-- written to swallow errors so a missing secret could not break a
-- user-facing INSERT. The schema was correct throughout.

BEGIN;

-- A clean slate: other tests may have seeded secrets.
DELETE FROM vault.decrypted_secrets WHERE name IN ('supabase_url', 'service_role_key');

-- An unset secret must return NULL rather than raising: the enqueue
-- triggers call this inline on a user's INSERT, and an exception there
-- would fail the message send itself.
DO $$
BEGIN
  IF public.app_setting('supabase_url') IS NOT NULL THEN
    RAISE EXCEPTION 'unset secret should read NULL';
  END IF;
END $$;

-- Reads back what Vault holds.
SELECT vault.create_secret('https://demo.supabase.co', 'supabase_url');
DO $$
BEGIN
  IF public.app_setting('supabase_url') <> 'https://demo.supabase.co' THEN
    RAISE EXCEPTION 'vault secret not read back';
  END IF;
END $$;

-- An empty secret counts as unset, not as a usable value: posting to
-- '/functions/v1/...' with an empty host would be a silent 404 loop.
UPDATE vault.decrypted_secrets SET decrypted_secret = '' WHERE name = 'supabase_url';
DO $$
BEGIN
  IF public.app_setting('supabase_url') IS NOT NULL THEN
    RAISE EXCEPTION 'empty secret should read NULL';
  END IF;
END $$;

-- Misconfiguration must be LOUD on the cron path, which is the opposite
-- of the trigger path. A job that posts to 'null/functions/v1/x' logs a
-- successful run, which is exactly how this went unnoticed; raising puts
-- the cause in cron.job_run_details instead.
DELETE FROM vault.decrypted_secrets WHERE name IN ('supabase_url', 'service_role_key');
DO $$
DECLARE
  v_raised boolean := false;
BEGIN
  BEGIN
    PERFORM public.invoke_edge_function('any-fn');
  EXCEPTION WHEN OTHERS THEN
    v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'invoke_edge_function must raise when unconfigured';
  END IF;
END $$;

-- No live definition may still read the retired GUC. This is the
-- regression guard: a future migration that copies the old pattern from
-- an existing function would reintroduce a silent no-op.
DO $$
DECLARE
  v_stale text;
BEGIN
  SELECT string_agg(p.proname, ', ') INTO v_stale
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosrc LIKE '%current_setting(''app.settings%'
    AND p.proname <> 'app_setting';

  IF v_stale IS NOT NULL THEN
    RAISE EXCEPTION 'these still read app.settings.* directly: %', v_stale;
  END IF;
END $$;

ROLLBACK;
