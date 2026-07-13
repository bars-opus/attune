-- public.profiles — the public-facing identity surface (ONB-2).
--
-- This table is written/read by ~35 call sites across onboarding, forums,
-- opinions, moderation, location, games and notifications — but it was never
-- created by ANY migration. Verified against the live database:
--
--   GET /rest/v1/profiles -> 404 PGRST205
--   "Could not find the table 'public.profiles' in the schema cache"
--
-- Consequence before this migration: OnboardingSubmissionService.submit()
-- upserts users -> profiles -> onboarding_profiles; the profiles upsert 404s,
-- the exception propagates, and EVERY user's remote onboarding fails. They all
-- silently fell into the "saved locally, we'll sync later" path, so no user's
-- mode / attachment answers / anchors ever reached the server. Every other
-- profiles reader (partner names in games, forum authors, block lists) was
-- equally broken.
--
-- Distinction from public.users:
--   * public.users     — private account record (own-row RLS, phone, mode).
--   * public.profiles  — PUBLIC identity (display name, avatar, bio). Readable
--                        by any authenticated user, writable only by its owner.
--     Games/forums/moderation legitimately read OTHER users' rows here (partner
--     display names, post authors), which is why the read policy is not
--     own-row. No phone or other PII belongs in this table.

CREATE TABLE IF NOT EXISTS public.profiles (
  -- Keyed by auth.uid() — every call site does .eq('id', <user id>).
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username text UNIQUE,
  display_name text,
  avatar_url text,
  bio text,
  relationship_status text
    CHECK (relationship_status IS NULL
           OR relationship_status IN ('single', 'taken')),
  preferred_location text,
  last_location_update timestamptz,
  -- Push routing token (notification engine).
  onesignal_player_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (username IS NULL OR char_length(username) BETWEEN 1 AND 40),
  CHECK (display_name IS NULL OR char_length(display_name) <= 80),
  CHECK (bio IS NULL OR char_length(bio) <= 500)
);

CREATE INDEX IF NOT EXISTS idx_profiles_username
  ON public.profiles(username) WHERE username IS NOT NULL;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- READ: any authenticated user may read any profile. This is the public
-- identity surface — games resolve a partner's display name, forums resolve a
-- post author, moderation resolves a blocked account. Anonymous users are NOT
-- granted read (Opinions browsing renders author names through its own
-- surfaces); tighten or widen here rather than in the client.
DROP POLICY IF EXISTS "profiles readable by authenticated" ON public.profiles;
CREATE POLICY "profiles readable by authenticated"
ON public.profiles FOR SELECT TO authenticated
USING (true);

-- WRITE: owner only. A client can never author another user's identity.
DROP POLICY IF EXISTS "profiles insert own" ON public.profiles;
CREATE POLICY "profiles insert own"
ON public.profiles FOR INSERT TO authenticated
WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "profiles update own" ON public.profiles;
CREATE POLICY "profiles update own"
ON public.profiles FOR UPDATE TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "profiles delete own" ON public.profiles;
CREATE POLICY "profiles delete own"
ON public.profiles FOR DELETE TO authenticated
USING (id = auth.uid());

REVOKE ALL ON public.profiles FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;

-- Keep updated_at honest on every write.
CREATE OR REPLACE FUNCTION public.touch_profiles_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_updated_at ON public.profiles;
CREATE TRIGGER trg_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.touch_profiles_updated_at();

-- Backfill identity for accounts that already completed onboarding into
-- public.users before this table existed, so existing users are not invisible
-- to forums/games/moderation.
INSERT INTO public.profiles (id, display_name, created_at, updated_at)
SELECT u.id, u.display_name, now(), now()
FROM public.users u
ON CONFLICT (id) DO NOTHING;
