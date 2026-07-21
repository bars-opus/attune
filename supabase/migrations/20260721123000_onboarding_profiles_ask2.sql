-- onboarding_profiles.completed_at means "Ask 1 done" for every user today.
-- Couples now need a SEPARATE marker for "Ask 2 done", since Ask 2 happens
-- days after Ask 1 and must not be conflated with it (ATTUNE_MASTER_SPEC.md
-- decision 29). Nullable: absent for personal-mode users (who have no Ask 2)
-- and for couples who haven't reached/finished Ask 2 yet.
ALTER TABLE public.onboarding_profiles
  ADD COLUMN IF NOT EXISTS ask2_completed_at timestamptz;
