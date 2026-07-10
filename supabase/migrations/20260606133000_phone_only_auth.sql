-- Attune launch auth is phone OTP only. Public user mirrors must always have
-- a verified phone number from auth.users; email remains absent from launch.

ALTER TABLE public.users
  DROP CONSTRAINT IF EXISTS users_check;

ALTER TABLE public.users
  ALTER COLUMN phone SET NOT NULL;

DROP INDEX IF EXISTS public.idx_users_email;

ALTER TABLE public.users
  DROP COLUMN IF EXISTS email;
