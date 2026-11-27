-- Entry gates (2026-11-27 audit, gap 3): record_eula_acceptance no longer
-- creates accounts. Live body: 20260817120000_eula_acceptance.sql
-- (INSERT ... ON CONFLICT DO UPDATE with display_name '', any version).
-- Now:
--   * never inserts a public.users row: complete_sign_up is the only
--     writer that makes one (D8). No row: 'eula:no_account', nothing
--     written. The app's callers (A5c "accept updated terms",
--     home_state_service / account_service) only run for an account that
--     has one; the legacy OnboardingFlow EulaGate, which ran before any
--     account existed, now gets the refusal (audit gap 4: that gate is to
--     be retired client-side).
--   * the version must be a 1-3 digit number >= 2 (the current EULA, as
--     complete_sign_up requires it): otherwise 'eula:version_not_current'.
--     NULL/blank keeps its existing 'version_required'.
--   * consent never goes down (as complete_sign_up's upsert): a stored
--     version at or above this one keeps its version and time.
--   * search_path 'public' becomes '' (every name qualified); the phone
--     lookup that only fed the insert is gone.
-- Returns the stored acceptance time, as before (timestamptz).
-- Grants in 20261127100050_record_eula_acceptance_update_only_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.record_eula_acceptance(p_version text)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id constant uuid := auth.uid();
  v_version integer;
  v_at timestamptz;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_version IS NULL OR btrim(p_version) = '' THEN
    RAISE EXCEPTION 'version_required';
  END IF;
  IF btrim(p_version) !~ '^[0-9]{1,3}$' THEN
    RAISE EXCEPTION 'eula:version_not_current';
  END IF;
  v_version := btrim(p_version)::integer;
  IF v_version < 2 THEN
    RAISE EXCEPTION 'eula:version_not_current';
  END IF;

  UPDATE public.users AS u
     SET eula_accepted_at = CASE WHEN coalesce(substring(u.eula_version FROM '^[0-9]{1,3}$')::integer, -1) < v_version
                                   OR u.eula_accepted_at IS NULL
                                 THEN now() ELSE u.eula_accepted_at END,
         eula_version = CASE WHEN coalesce(substring(u.eula_version FROM '^[0-9]{1,3}$')::integer, -1) < v_version
                             THEN v_version::text ELSE u.eula_version END
   WHERE u.id = v_user_id
  RETURNING u.eula_accepted_at INTO v_at;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'eula:no_account';
  END IF;

  RETURN v_at;
END;
$$;

COMMIT;
