-- DEV / MANUAL TESTING ONLY. Never a migration (Spec 2 §4.9, R-6, Q19b,
-- I-15). Turns every Spec 2 Dating flag that exists ON, and opens Ghana and
-- the UK for Dating, on the development project only. W4a: also the
-- verification mode (fake locally, sandbox on the project) when none is set. The guard comes
-- first and everything is one statement, so when Spec 1's guard raises
-- env:not_development (the project doesn't read 'development', or
-- supabase_url is set and doesn't name the development ref, or it can't be
-- read) nothing changes. It never sets attune_environment; nothing in Spec
-- 2 does. Safe to re-run (a country already open is not published again).
-- Re-run it after any migration replay: 20260705210000 forces the Dating
-- flags off when it replays (R10). Every later Spec 2 batch extends it.
-- Dating also needs dating_exclusion_key set and its fingerprint seeded
-- (select private.seed_dating_exclusion_key_fingerprint();): until then
-- dating_eligibility answers feature_unavailable for everyone (batch-5 fix
-- round 1, I-1), and this script only warns.
DO $$
DECLARE
  v jsonb;
  v_country text;
BEGIN
  PERFORM private.assert_development_project();

  -- W1a: every Dating flag that exists. W1b: dating_same_gender_matching.
  INSERT INTO public.feature_flags (key, enabled) VALUES
    ('dating_mode_enabled', true),
    ('dating_candidate_generation', true),
    ('dating_match_messaging', true),
    ('dating_profile_photos', true),
    ('dating_alignment_algorithm_v1', true),
    ('dating_same_gender_matching', true),
    ('dating_age_assurance', true) -- Spec 2 W4a
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now();

  -- Spec 2 W4a (§3.3.5, §4.9): the verification mode, only when none is set
  -- Spec 2 W4a (an owner's 'live' or 'sandbox' is kept): 'fake' on a local
  -- Spec 2 W4a database (no project URL), 'sandbox' on the development
  -- Spec 2 W4a project. Vault, which app_setting reads first.
  IF public.app_setting('age_assurance_mode') IS NULL THEN -- Spec 2 W4a
    PERFORM vault.create_secret(CASE WHEN public.app_setting('supabase_url') IS NULL THEN 'fake' ELSE 'sandbox' END, -- Spec 2 W4a
                                'age_assurance_mode', 'Spec 2 W4a: dev verification mode'); -- Spec 2 W4a
  END IF; -- Spec 2 W4a

  -- W1b: Ghana (Greater Accra and Ashanti, as seeded) and the UK open,
  -- only through publish_country_config (nothing writes the table directly).
  FOREACH v_country IN ARRAY ARRAY['GH', 'GB'] LOOP
    IF (public.dating_country_config(v_country)).dating_enabled IS NOT TRUE THEN
      v := public.publish_country_config(v_country,
             '{"dating_enabled": true, "published_by": "dev_enable_spec2_dating_flags"}'::jsonb);
      IF (v ->> 'ok')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'dev_enable_spec2_dating_flags: % was not opened: %', v_country, v;
      END IF;
    END IF;
  END LOOP;

  IF private.dating_exclusion_key_ready() IS NOT TRUE THEN
    RAISE WARNING 'dev_enable_spec2_dating_flags: dating_exclusion_key is not set or its fingerprint is not seeded; Dating stays unavailable until both are (owner checklist items 2 and 11)';
  END IF;
END $$;
