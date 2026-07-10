-- Attune core schema: users, relationships, invite acceptance, onboarding.
-- Applies after Supabase Auth is enabled. All app access is governed by RLS.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text UNIQUE,
  phone text UNIQUE,
  display_name text NOT NULL,
  avatar_url text,
  mode text NOT NULL DEFAULT 'personal'
    CHECK (mode IN ('couples', 'personal', 'healing', 'dating')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (email IS NOT NULL OR phone IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS public.relationships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_a uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  user_b uuid REFERENCES public.users(id) ON DELETE SET NULL,
  invite_code text UNIQUE,
  invite_expires_at timestamptz,
  invite_accepted_at timestamptz,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'active', 'paused', 'ended')),
  started_at date,
  created_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  ended_by uuid REFERENCES public.users(id),
  deletion_scheduled_at timestamptz,
  total_sessions int NOT NULL DEFAULT 0,
  message_count int NOT NULL DEFAULT 0,
  games_completed int NOT NULL DEFAULT 0,
  last_overall_pulse int,
  CHECK (user_b IS NULL OR user_a <> user_b),
  CHECK (
    (status = 'pending' AND invite_code IS NOT NULL AND invite_expires_at IS NOT NULL)
    OR (status <> 'pending' AND invite_code IS NULL)
  )
);

-- Stores accepted invite hashes so accept-invite can be idempotent even though
-- relationships.invite_code is cleared after acceptance.
CREATE TABLE IF NOT EXISTS public.relationship_invite_acceptances (
  invite_code_hash text PRIMARY KEY,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  accepted_by uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  accepted_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.onboarding_profiles (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  mode text NOT NULL CHECK (mode IN ('couples', 'personal')),
  attachment_answers jsonb NOT NULL DEFAULT '[]'::jsonb,
  anchors jsonb NOT NULL DEFAULT '[]'::jsonb,
  completed_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_users_phone ON public.users(phone) WHERE phone IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email) WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_relationships_user_a ON public.relationships(user_a);
CREATE INDEX IF NOT EXISTS idx_relationships_user_b ON public.relationships(user_b);
CREATE INDEX IF NOT EXISTS idx_relationships_invite_code
  ON public.relationships(invite_code)
  WHERE invite_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_relationships_pending_invites
  ON public.relationships(user_a, invite_expires_at)
  WHERE status = 'pending' AND invite_code IS NOT NULL;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_users_updated_at ON public.users;
CREATE TRIGGER set_users_updated_at
BEFORE UPDATE ON public.users
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_onboarding_profiles_updated_at ON public.onboarding_profiles;
CREATE TRIGGER set_onboarding_profiles_updated_at
BEFORE UPDATE ON public.onboarding_profiles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.relationship_invite_acceptances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.onboarding_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users read own profile" ON public.users;
CREATE POLICY "users read own profile"
ON public.users FOR SELECT
USING (id = auth.uid());

DROP POLICY IF EXISTS "users insert own profile" ON public.users;
CREATE POLICY "users insert own profile"
ON public.users FOR INSERT
WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "users update own profile" ON public.users;
CREATE POLICY "users update own profile"
ON public.users FOR UPDATE
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "relationship members read" ON public.relationships;
CREATE POLICY "relationship members read"
ON public.relationships FOR SELECT
USING (user_a = auth.uid() OR user_b = auth.uid());

DROP POLICY IF EXISTS "relationship inviter insert" ON public.relationships;
CREATE POLICY "relationship inviter insert"
ON public.relationships FOR INSERT
WITH CHECK (user_a = auth.uid() AND user_b IS NULL AND status = 'pending');

DROP POLICY IF EXISTS "relationship members update limited" ON public.relationships;
CREATE POLICY "relationship members update limited"
ON public.relationships FOR UPDATE
USING (user_a = auth.uid() OR user_b = auth.uid())
WITH CHECK (user_a = auth.uid() OR user_b = auth.uid());

DROP POLICY IF EXISTS "invite acceptances read own" ON public.relationship_invite_acceptances;
CREATE POLICY "invite acceptances read own"
ON public.relationship_invite_acceptances FOR SELECT
USING (accepted_by = auth.uid());

DROP POLICY IF EXISTS "onboarding read own" ON public.onboarding_profiles;
CREATE POLICY "onboarding read own"
ON public.onboarding_profiles FOR SELECT
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "onboarding upsert own" ON public.onboarding_profiles;
CREATE POLICY "onboarding upsert own"
ON public.onboarding_profiles FOR INSERT
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "onboarding update own" ON public.onboarding_profiles;
CREATE POLICY "onboarding update own"
ON public.onboarding_profiles FOR UPDATE
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());
