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
    current_setting('request.jwt.claims', true)::json->>'sub', ''
  )::uuid;
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claims', true)::json->>'role', ''),
    'authenticated'
  );
$$;

CREATE OR REPLACE FUNCTION auth.email()
RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT NULLIF(
    current_setting('request.jwt.claims', true)::json->>'email', ''
  );
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

GRANT USAGE ON SCHEMA public, auth, extensions, storage TO anon, authenticated, service_role;

-- Supabase grants table privileges platform-side, so no migration does it.
-- Without this, `SET LOCAL ROLE authenticated` hits "permission denied"
-- before RLS is ever consulted -- and RLS is the thing under test.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO authenticated, service_role, anon;
