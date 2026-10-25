-- Spec 1 W1c, migration 6 of 6 (spec §4.7 #6): identity_health.
--   * private.unfinished_signups: the one unfinished-sign-up predicate (batch
--     5 review #1, #7): an Auth user with no public.users row and no activity
--     for 24 hours, activity being the latest of created_at, last_sign_in_at
--     and updated_at. Controller ruling: this narrows spec §4.3's "created
--     more than 24 hours ago", so an old Auth user that is signing in again
--     (signInWithOtp reuses it after a failed code) is never a candidate;
--   * unfinished_signup_candidates(): that predicate, oldest first, 500 a run;
--   * is_unfinished_signup(uuid): the same predicate for one id, which the
--     purge re-checks immediately before each delete;
--   * get_identity_health(): W1 counts only (W6a re-creates it from this live
--     body to add dormancy, parked accounts and hook fail-opens);
--   * the purge-unfinished-signups job (its own cron, spec §4.6), hourly
--     (review #8), so an account idle 24 hours goes within 25.
-- Grants in 20261025100510_identity_health_grants.sql.
BEGIN;

CREATE OR REPLACE VIEW private.unfinished_signups AS
  SELECT a.id, a.created_at
    FROM auth.users AS a
   WHERE greatest(a.created_at, a.last_sign_in_at, a.updated_at) < now() - interval '24 hours'
     AND NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = a.id);

CREATE OR REPLACE FUNCTION public.unfinished_signup_candidates()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT s.id
    FROM private.unfinished_signups AS s
   ORDER BY s.created_at, s.id
   LIMIT 500;
$$;

CREATE OR REPLACE FUNCTION public.is_unfinished_signup(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM private.unfinished_signups AS s WHERE s.id = p_user_id);
$$;

CREATE OR REPLACE FUNCTION public.get_identity_health()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'accounts_without_birth_date', (
      SELECT count(*) FROM public.users AS u
       WHERE NOT EXISTS (SELECT 1 FROM public.account_birthdates AS b WHERE b.user_id = u.id)),
    'accounts_without_path', (SELECT count(*) FROM public.users AS u WHERE u.path IS NULL),
    'holds', jsonb_build_object(
      'age_review', (SELECT count(*) FROM public.account_holds AS h
                      WHERE h.kind = 'age_review' AND h.resolved_at IS NULL),
      'recovery_hold', (SELECT count(*) FROM public.account_holds AS h
                         WHERE h.kind = 'recovery_hold' AND h.resolved_at IS NULL),
      'safety_review', (SELECT count(*) FROM public.account_holds AS h
                         WHERE h.kind = 'safety_review' AND h.resolved_at IS NULL)),
    'unfinished_signups_awaiting_purge', (SELECT count(*) FROM private.unfinished_signups AS s));
$$;

-- Revoked here as well as in the twin (controller ruling after batch 3; the
-- verified_phone precedent): the hosted default privileges grant EXECUTE on
-- a new function, and SELECT on a new view, to anon and authenticated, and a
-- failed or late twin push must not let a client list or probe unfinished
-- Auth accounts or read the counts.
REVOKE ALL ON private.unfinished_signups FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.unfinished_signup_candidates() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.is_unfinished_signup(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_identity_health() FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule('purge-unfinished-signups');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;
SELECT cron.schedule(
  'purge-unfinished-signups',
  '41 * * * *',
  $cron$SELECT public.invoke_edge_function('purge-unfinished-signups')$cron$
);

COMMIT;
