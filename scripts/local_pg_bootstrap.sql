-- Bootstrap a plain Postgres so Attune's migrations can be applied for
-- CONTRACT TESTING ONLY. This is not a Supabase emulator: it provides
-- just enough of the platform's surface (roles, the auth schema,
-- auth.uid(), and stubs for extensions a stock Postgres lacks) for the
-- schema to build and the RLS/RPC contracts to be exercised.
--
-- Never point this at anything but a throwaway database.

CREATE SCHEMA IF NOT EXISTS extensions;

-- Supabase installs pgcrypto into the `extensions` schema and migrations
-- call it fully qualified (extensions.hmac, extensions.gen_random_uuid).
-- Installing it there rather than in public is what makes those calls
-- resolve.
CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA extensions;

-- Also expose the handful of pgcrypto/uuid functions that unqualified
-- call sites rely on.
CREATE OR REPLACE FUNCTION public.gen_random_uuid()
RETURNS uuid LANGUAGE sql AS $$ SELECT extensions.gen_random_uuid(); $$;

-- Supabase exposes pgcrypto's digest/hmac unqualified as well as under
-- extensions. Migrations and RPCs call both spellings.
CREATE OR REPLACE FUNCTION public.digest(text, text)
RETURNS bytea LANGUAGE sql IMMUTABLE AS $$ SELECT extensions.digest($1, $2); $$;
CREATE OR REPLACE FUNCTION public.digest(bytea, text)
RETURNS bytea LANGUAGE sql IMMUTABLE AS $$ SELECT extensions.digest($1, $2); $$;
CREATE OR REPLACE FUNCTION public.hmac(text, text, text)
RETURNS bytea LANGUAGE sql IMMUTABLE AS $$ SELECT extensions.hmac($1, $2, $3); $$;
CREATE OR REPLACE FUNCTION public.hmac(bytea, bytea, text)
RETURNS bytea LANGUAGE sql IMMUTABLE AS $$ SELECT extensions.hmac($1, $2, $3); $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN BYPASSRLS;
  END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS extensions;

-- Supabase's auth.users. Only the columns migrations reference.
CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text,
  phone text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  banned_until timestamptz,
  last_sign_in_at timestamptz,
  email_confirmed_at timestamptz,
  phone_confirmed_at timestamptz,
  confirmed_at timestamptz,
  is_anonymous boolean NOT NULL DEFAULT false,
  raw_user_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  raw_app_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  aud text,
  role text,
  encrypted_password text,
  invited_at timestamptz,
  confirmation_token text,
  recovery_token text,
  instance_id uuid
);

-- auth.uid() reads the same GUC Supabase's does, so a test can adopt an
-- identity with set_config('request.jwt.claims', '{"sub":"..."}', true)
-- exactly as it would against the real platform.
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT NULLIF(
    NULLIF(current_setting('request.jwt.claims', true), '')::json->>'sub', ''
  )::uuid;
$$;

-- Returns NULL when there is no JWT, matching Supabase. The default must
-- NOT be 'authenticated': guards like dating_former_partner_exclusion's
-- test `auth.role() IS NOT NULL AND auth.role() = 'authenticated'` to mean
-- "a client is calling", and a non-null default makes every backend call
-- look like a client one.
CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT NULLIF(
    NULLIF(current_setting('request.jwt.claims', true), '')::json->>'role', ''
  );
$$;

CREATE OR REPLACE FUNCTION auth.email()
RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT NULLIF(
    NULLIF(current_setting('request.jwt.claims', true), '')::json->>'email', ''
  );
$$;

-- Supabase creates the supabase_realtime publication platform-side and
-- manages its table list from the dashboard, so no migration had ever
-- referenced it -- and on this project it was EMPTY, meaning no
-- postgres_changes event ever reached a client. Chat messages did not
-- appear live; typing did, because typing is a broadcast that never
-- touches Postgres.
--
-- Created empty here, exactly as a fresh Supabase project has it, so
-- 20260931210000 has to do the work and a contract test can prove which
-- tables ended up in it.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

-- Supabase Vault is unavailable in a stock Postgres. The real thing
-- exposes vault.decrypted_secrets as a view over encrypted storage; this
-- stub is a plain table with the same two columns the app reads, so
-- migrations that select from it apply and contract tests can seed a
-- secret to exercise the settings accessor.
--
-- Stubbed at all because the production settings mechanism (ALTER
-- DATABASE ... SET app.settings.*) turned out to be unavailable on a
-- managed project -- the SQL editor's `postgres` role is not the database
-- owner -- so every cron job and enqueue trigger silently no-opped. The
-- harness had no way to notice: it never ran the jobs, and the triggers
-- were written to skip quietly when the settings were absent.
CREATE SCHEMA IF NOT EXISTS vault;

CREATE TABLE IF NOT EXISTS vault.decrypted_secrets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE,
  decrypted_secret text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION vault.create_secret(
  new_secret text,
  new_name text DEFAULT NULL,
  new_description text DEFAULT ''
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO vault.decrypted_secrets (name, decrypted_secret)
  VALUES (new_name, new_secret)
  ON CONFLICT (name) DO UPDATE SET decrypted_secret = EXCLUDED.decrypted_secret
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- pg_cron and pg_net are unavailable in a stock Postgres. Stubbing them
-- lets scheduling migrations apply; the jobs themselves are never
-- exercised by contract tests, which assert schema and authorization.
CREATE SCHEMA IF NOT EXISTS cron;

CREATE TABLE IF NOT EXISTS cron.job (
  jobid bigserial PRIMARY KEY,
  jobname text UNIQUE,
  schedule text,
  command text,
  nodename text NOT NULL DEFAULT 'localhost',
  nodeport int NOT NULL DEFAULT 5432,
  database text NOT NULL DEFAULT current_database(),
  username text NOT NULL DEFAULT current_user,
  active boolean NOT NULL DEFAULT true
);

CREATE OR REPLACE FUNCTION cron.schedule(
  job_name text, schedule text, command text
) RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE v_id bigint;
BEGIN
  INSERT INTO cron.job (jobname, schedule, command)
  VALUES (job_name, schedule, command)
  ON CONFLICT (jobname) DO UPDATE
    SET schedule = EXCLUDED.schedule, command = EXCLUDED.command
  RETURNING jobid INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION cron.unschedule(job_name text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM cron.job WHERE jobname = job_name;
  RETURN true;
END $$;

-- pg_cron's run-history table, read by the scheduled-jobs health view.
CREATE TABLE IF NOT EXISTS cron.job_run_details (
  jobid bigint,
  runid bigserial PRIMARY KEY,
  job_pid int,
  database text,
  username text,
  command text,
  status text,
  return_message text,
  start_time timestamptz,
  end_time timestamptz
);

-- Migrations call both overloads: by name and by jobid.
CREATE OR REPLACE FUNCTION cron.unschedule(job_id bigint)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM cron.job WHERE jobid = job_id;
  RETURN true;
END $$;

CREATE SCHEMA IF NOT EXISTS net;

CREATE OR REPLACE FUNCTION net.http_post(
  url text,
  body jsonb DEFAULT '{}'::jsonb,
  params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{}'::jsonb,
  timeout_milliseconds int DEFAULT 5000
) RETURNS bigint
LANGUAGE sql
AS $$ SELECT 1::bigint; $$;

CREATE SCHEMA IF NOT EXISTS storage;
CREATE TABLE IF NOT EXISTS storage.buckets (
  id text PRIMARY KEY,
  name text NOT NULL,
  public boolean NOT NULL DEFAULT false
);
CREATE TABLE IF NOT EXISTS storage.objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id text REFERENCES storage.buckets(id),
  name text,
  owner uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Supabase refuses direct deletion from storage tables; only the Storage
-- API may remove an object:
--
--   PostgrestException(message: Direct deletion from storage tables is not
--   allowed. Use the Storage API instead., code: 42501)
--
-- Without this guard the harness happily accepted DELETE FROM
-- storage.objects, so three SECURITY DEFINER functions that did exactly
-- that passed every local contract and threw on every real invocation --
-- rolling back the state change that preceded the DELETE in each. This
-- reproduces the platform's refusal so that class of bug fails here first.
CREATE OR REPLACE FUNCTION storage.reject_direct_object_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'Direct deletion from storage tables is not allowed. Use the Storage API instead.'
    USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS reject_direct_object_delete ON storage.objects;
CREATE TRIGGER reject_direct_object_delete
  BEFORE DELETE ON storage.objects
  FOR EACH ROW EXECUTE FUNCTION storage.reject_direct_object_delete();

GRANT USAGE ON SCHEMA public, auth, extensions, storage TO anon, authenticated, service_role;

-- Supabase grants table privileges platform-side, so no migration does it.
-- Without this, `SET LOCAL ROLE authenticated` hits "permission denied"
-- before RLS is ever consulted -- and RLS is the thing under test.
--
-- service_role is deliberately EXCLUDED from these defaults.
--
-- It was included, and that is what hid the project's longest-running
-- fault: 103 public tables had no service_role grant in production, so
-- every Edge Function worker read empty queues through PostgREST (a
-- missing SELECT returns no rows, not an error) while this harness showed
-- them all reachable. Granting service_role here would model a platform
-- behaviour that does NOT exist -- Supabase grants at table creation
-- through its API, and a table created by a migration gets nothing.
--
-- 20260931140000 grants service_role explicitly and sets its own default
-- privileges for tables added later. Leaving it out here is what makes
-- that migration load-bearing: drop it, and service_role_grants_test
-- fails locally instead of a queue silently draining nothing in
-- production.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO authenticated, anon;
