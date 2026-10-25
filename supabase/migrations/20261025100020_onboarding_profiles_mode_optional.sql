-- Spec 1 W1 (batch 4 review #8): onboarding_profiles.mode becomes optional
-- ahead of its drop in 20261025100300_paths_and_home_state.sql, so both
-- builds work in between: the W1b client (which no longer sends mode) never
-- hits 23502 while the column still exists, and an older build that still
-- sends mode keeps working until the drop. It ships in the W1a push; the W1b
-- build is installed next; the drop is pushed with W1b (owner checklist 1).
-- The CHECK (couples/personal) stays and passes NULL. No grants change.
-- Idempotent: a no-op once the column is nullable or gone.
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'onboarding_profiles'
                AND column_name = 'mode' AND is_nullable = 'NO') THEN
    ALTER TABLE public.onboarding_profiles ALTER COLUMN mode DROP NOT NULL;
  END IF;
END $$;

COMMIT;
