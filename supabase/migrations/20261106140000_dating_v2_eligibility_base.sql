-- Spec 2 W1b, migration 5 (spec §4.9 W1b #2, §2.1; I-14, A-10, I-4):
--   * dating_eligibility(p_user, p_scope DEFAULT 'candidate') -> the first
--     failing reason or 'eligible', with gates 1-4 and 6 (W2 adds 5, W4b 8,
--     W8b 7): 1 dating_mode_enabled -> feature_unavailable; 2 Spec 1's
--     account_age >= 18, a confirmed Auth phone and EULA v2 ->
--     account_unavailable; 3 dating_account_in_good_standing (W1a: bans,
--     restrictions, enforcement records, Spec 1 holds) ->
--     account_unavailable; 4 dating_has_relationship -> relationship_active;
--     6 the profile's Dating country open (country_closed) and its region
--     open (region_closed). The country is read by name (the column arrives
--     in W1c); with none chosen yet, the 'setup' scope passes gate 6 and the
--     'candidate' scope fails it (a candidate always has one). Server only.
--   * Spec 1's seam private.dating_home_summary(p_user) re-created from its
--     live body (20261025100300): 'enabled' = dating_eligibility(p_user,
--     'setup') <> 'feature_unavailable' (NULL: not enabled); 'enrolled'
--     unchanged; the shape
--     {enabled, enrolled} is kept (A-10).
--   * Fix round 1 (I-1, M-4): gate 1b, the exclusion key is set and its
--     stored fingerprint matches (private.dating_exclusion_key_ready()),
--     else 'feature_unavailable' for everyone, counted as
--     dating.eligibility.key_not_ready; gate 3 also fails a person whose own
--     phone HMAC is NULL. private.dating_exclusion_key_mismatch() is
--     re-created from its live body (20261106110000) without its first-sight
--     seed: an unseeded fingerprint now refuses enrolment, activation and
--     generation (B2 ruling). Seeding is the owner-only
--     private.seed_dating_exclusion_key_fingerprint(), run here when the key
--     exists at apply time; country_config_checks uses the same predicate.
--   * NULL-safe (batch-5 ruling): every gate fails closed when its
--     dependency answers NULL (IS NOT TRUE / IS NOT FALSE), and the seam
--     reads a NULL eligibility as feature_unavailable, never as enabled.
--   * private.country_config_checks re-created from its live body
--     (20261106130000) with one check (batch-2 carry, I-5): a row that opens
--     Dating reports exclusion_key_not_ready unless dating_exclusion_key is
--     set and its stored fingerprint (private.dating_key_fingerprints)
--     matches; publish_country_config enforces it in production, reports it
--     in development. Read only (STABLE): it never seeds the fingerprint.
-- Grants in 20261106140010_dating_v2_eligibility_base_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- Fix round 1 (I-1, M-4): the one "exclusion key ready" predicate, the
-- owner-only seeder, and the mismatch check without its first-sight seed.
CREATE OR REPLACE FUNCTION private.dating_exclusion_key_ready()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  -- The key is set and its stored fingerprint matches it; no key, no stored
  -- fingerprint or a rotated key is not ready. Read only: never seeds.
  SELECT coalesce((SELECT k.fingerprint FROM private.dating_key_fingerprints AS k
                    WHERE k.name = 'dating_exclusion_key')
                  = public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1'), false);
$fn$;

CREATE OR REPLACE FUNCTION private.seed_dating_exclusion_key_fingerprint()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
-- Owner only (no API role; owner checklist items 2 and 11): stores the live
-- key's fingerprint when none is stored. Never replaces a stored one, and
-- the row is never deleted: the key is never rotated or re-keyed (item 11,
-- W1 final fix I-3; a mismatch means the secret changed: put it back).
DECLARE
  v_live constant text := public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1');
  v_stored text;
BEGIN
  IF v_live IS NULL THEN
    RETURN 'missing_key';
  END IF;
  INSERT INTO private.dating_key_fingerprints (name, fingerprint)
  VALUES ('dating_exclusion_key', v_live)
  ON CONFLICT (name) DO NOTHING;
  SELECT k.fingerprint INTO v_stored FROM private.dating_key_fingerprints AS k WHERE k.name = 'dating_exclusion_key';
  RETURN CASE WHEN v_stored = v_live THEN 'ready' ELSE 'mismatch' END;
END;
$fn$;

CREATE OR REPLACE FUNCTION private.dating_exclusion_key_mismatch()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_live constant text := public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1');
  v_stored text;
BEGIN
  IF v_live IS NULL THEN
    RETURN false; -- no key: not a mismatch (generation, deletion and health refuse on a missing key)
  END IF;
  -- Spec 2 W1b (fix round 1, M-4): never seeds; an unseeded fingerprint is a
  -- Spec 2 W1b mismatch (refused, counted) until the owner seeds it.
  SELECT k.fingerprint INTO v_stored FROM private.dating_key_fingerprints AS k WHERE k.name = 'dating_exclusion_key';
  RETURN v_stored IS DISTINCT FROM v_live;
END;
$function$;

-- The key present at apply time is fingerprinted here (as 20261106110000
-- did); a key added later is seeded by the owner (checklist item 2).
DO $seed$
BEGIN
  PERFORM private.seed_dating_exclusion_key_fingerprint();
END $seed$;

CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate')
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_profile jsonb;
  v_country text;
  v_region text;
  v_config public.country_safety_config;
BEGIN
  IF p_scope IS NULL OR p_scope NOT IN ('setup', 'candidate') THEN
    RAISE EXCEPTION 'eligibility:invalid_scope' USING ERRCODE = '22023';
  END IF;
  -- 1. Feature.
  IF public.dating_flag_enabled('dating_mode_enabled') IS NOT TRUE THEN
    RETURN 'feature_unavailable';
  END IF;
  -- 1b. (Fix round 1, I-1) Carried restrictions are readable only under a
  -- set exclusion key whose stored fingerprint matches. Otherwise nobody is
  -- eligible, under the generic system reason (never a personal one),
  -- counted best-effort (a read-only caller can't write; the refusal stands).
  IF private.dating_exclusion_key_ready() IS NOT TRUE THEN
    BEGIN
      PERFORM private.bump_metric_internal('dating.eligibility.key_not_ready');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RETURN 'feature_unavailable';
  END IF;
  -- 2. Account: an adult by Spec 1's DOB, a confirmed phone, EULA v2.
  IF p_user IS NULL
     OR coalesce(public.account_age(p_user), 0) < 18
     OR NOT EXISTS (SELECT 1 FROM auth.users AS a WHERE a.id = p_user AND a.phone_confirmed_at IS NOT NULL)
     OR NOT EXISTS (SELECT 1 FROM public.users AS u
                     WHERE u.id = p_user AND u.eula_accepted_at IS NOT NULL
                       AND coalesce(substring(u.eula_version FROM '^[0-9]{1,3}$')::integer, 0) >= 2) THEN
    RETURN 'account_unavailable';
  END IF;
  -- 3. Standing. (Fix round 1, I-1) A person whose own HMAC can't be
  -- computed under the set key can't be checked against carried records.
  IF public.dating_account_in_good_standing(p_user) IS NOT TRUE
     OR public.dating_phone_hmac_for_user(p_user) IS NULL THEN
    RETURN 'account_unavailable';
  END IF;
  -- 4. Relationship guard.
  IF public.dating_has_relationship(p_user) IS NOT FALSE THEN
    RETURN 'relationship_active';
  END IF;
  -- 6. Country and region.
  SELECT to_jsonb(p) INTO v_profile FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  v_country := v_profile ->> 'country_code';
  v_region := v_profile ->> 'region_code';
  IF v_country IS NULL THEN
    RETURN CASE WHEN p_scope = 'setup' THEN 'eligible' ELSE 'country_closed' END;
  END IF;
  v_config := public.dating_country_config(v_country);
  IF v_config IS NULL OR v_config.dating_enabled IS NOT TRUE THEN
    RETURN 'country_closed';
  END IF;
  IF v_config.open_regions IS NOT NULL
     AND (v_region IS NULL OR (v_region = ANY (v_config.open_regions)) IS NOT TRUE) THEN
    RETURN CASE WHEN v_region IS NULL AND p_scope = 'setup' THEN 'eligible' ELSE 'region_closed' END;
  END IF;
  RETURN 'eligible';
END;
$fn$;

CREATE OR REPLACE FUNCTION private.dating_home_summary(p_user uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'enabled', coalesce(public.dating_eligibility(p_user, 'setup'), 'feature_unavailable') <> 'feature_unavailable', -- Spec 2 W1b (A-10)
    'enrolled', EXISTS (
      SELECT 1 FROM public.dating_enrollments AS e
       WHERE e.user_id = p_user
         AND e.state IN ('profile_draft', 'active', 'paused', 'suspended')));
$function$;

-- Spec 2 W1b (batch-2 carry): the production checks need a ready exclusion key.
CREATE OR REPLACE FUNCTION private.country_config_checks(p_row public.country_safety_config)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE
  v_checks text[] := ARRAY[]::text[];
  v_sg jsonb := p_row.legal_checklist -> 'same_gender_reconsideration';
BEGIN
  IF coalesce(p_row.dating_enabled, true) THEN
    IF coalesce(p_row.legal_checklist, '{}'::jsonb) = '{}'::jsonb
       -- I-3: every country needs the baseline references, whatever else
       -- its checklist holds.
       OR NOT (coalesce(p_row.legal_checklist, '{}'::jsonb)
               ?& ARRAY['dpia', 'pen_test', 'safety_owner_and_moderator', 'reviewer_signoffs'])
       OR EXISTS (SELECT 1 FROM jsonb_each(p_row.legal_checklist) AS e
                   WHERE e.key <> 'same_gender_reconsideration'
                     AND (jsonb_typeof(e.value) <> 'string' OR btrim(e.value #>> '{}') = '')) THEN
      v_checks := array_append(v_checks, 'evidence_missing');
    END IF;
    IF p_row.resources_verified_at IS NULL OR p_row.resources_verified_at < now() - interval '90 days' THEN
      v_checks := array_append(v_checks, 'resources_not_verified');
    END IF;
    -- Spec 2 W1b (batch-2 carry, I-5): Dating opens only under a set key
    -- Spec 2 W1b whose stored fingerprint matches it (no key, no stored
    -- Spec 2 W1b fingerprint or a rotated key: not ready).
    IF private.dating_exclusion_key_ready() IS NOT TRUE THEN -- Spec 2 W1b
      v_checks := array_append(v_checks, 'exclusion_key_not_ready'); -- Spec 2 W1b
    END IF; -- Spec 2 W1b
  END IF;
  IF coalesce(p_row.same_gender_enabled, true) AND coalesce(p_row.tier, 1) IN (1, 2)
     AND (jsonb_typeof(v_sg) IS DISTINCT FROM 'object'
          OR EXISTS (SELECT 1 FROM unnest(ARRAY['legal_opinion', 'lgbtq_consultation', 'tier1_protections']) AS k(key)
                      WHERE jsonb_typeof(v_sg -> k.key) IS DISTINCT FROM 'string'
                         OR btrim(v_sg ->> k.key) = '')) THEN
    v_checks := array_append(v_checks, 'same_gender_reconsideration_missing');
  END IF;
  RETURN v_checks;
END;
$function$;

REVOKE ALL ON FUNCTION public.dating_eligibility(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_home_summary(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.country_config_checks(public.country_safety_config) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_exclusion_key_ready() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.seed_dating_exclusion_key_fingerprint() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_exclusion_key_mismatch() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
