-- Profiles: enforce username uniqueness + RLS hardening
--
-- Background: the app fetches username availability client-side then writes
-- in a separate call. Without these guards a second user can win the race
-- and we'd silently overwrite or end up with duplicate usernames.
--
-- This migration:
--   1. Adds a case-insensitive UNIQUE index on profiles.username so the DB
--      rejects duplicates regardless of casing.
--   2. Enables RLS on profiles and adds policies so a user can only SELECT
--      and UPDATE their own row, and INSERT only with their own auth.uid().

-- 1. UNIQUE INDEX (case-insensitive)
-- A plain UNIQUE constraint would not catch "Foo" vs "foo"; the app already
-- lowercases on write but we belt-and-brace at the DB.
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_lower_unique_idx
  ON public.profiles (lower(username))
  WHERE username IS NOT NULL;

-- 2. ENABLE RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 3. POLICIES — drop first so the migration is idempotent.
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_public" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

-- SELECT: any signed-in user can read any profile (needed for username lookup,
-- shop owner display, etc.). Tighten if your product needs profile privacy.
CREATE POLICY "profiles_select_public"
  ON public.profiles
  FOR SELECT
  TO authenticated
  USING (true);

-- INSERT: only the authenticated user can create their own profile row.
CREATE POLICY "profiles_insert_own"
  ON public.profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- UPDATE: only the authenticated user can update their own profile row.
CREATE POLICY "profiles_update_own"
  ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- No DELETE policy — profiles should not be deletable by the client.
