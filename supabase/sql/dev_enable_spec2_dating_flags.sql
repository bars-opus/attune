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
    ('dating_same_gender_matching', true),
    ('dating_age_assurance', true), -- Spec 2 W4a
    ('dating_traveller_detection', true), -- Spec 2 W8b
    ('support_resources_v2', true) -- Spec 2 W6c (T10 fix 1, I-4): Get help's directory
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now();

  -- Spec 2 W5a (§4.9): introductions_v2 active with DEV- review references
  -- Spec 2 W5a (production refuses DEV- references; the owner activates it
  -- Spec 2 W5a there with real ones, the W5 gate). Any other active config retires.
  UPDATE public.dating_algorithm_configs SET state = 'retired', retired_at = now() -- Spec 2 W5a
   WHERE state = 'active' AND version <> 'introductions_v2'; -- Spec 2 W5a
  UPDATE public.dating_algorithm_configs -- Spec 2 W5a
     SET state = 'active', activated_at = coalesce(activated_at, now()), -- Spec 2 W5a
         product_review_ref = coalesce(product_review_ref, 'DEV-product'), clinical_review_ref = coalesce(clinical_review_ref, 'DEV-clinical'), -- Spec 2 W5a
         fairness_review_ref = coalesce(fairness_review_ref, 'DEV-fairness'), safety_review_ref = coalesce(safety_review_ref, 'DEV-safety') -- Spec 2 W5a
   WHERE version = 'introductions_v2' AND state <> 'active'; -- Spec 2 W5a
  -- Spec 2 W6b (§4.9): the chat's v1 lexicon active with a DEV- reference
  -- Spec 2 W6b (production refuses one; the owner activates it there with
  -- Spec 2 W6b the reviewers' reference, the W6 gate).
  IF NOT EXISTS (SELECT 1 FROM public.dating_safety_configs WHERE state = 'active') THEN -- Spec 2 W6b
    UPDATE public.dating_safety_configs -- Spec 2 W6b
       SET state = 'active', review_ref = coalesce(review_ref, 'DEV-safety'), activated_at = now() -- Spec 2 W6b
     WHERE version = 'dating_chat_v1'; -- Spec 2 W6b
  END IF; -- Spec 2 W6b

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
  -- Spec 2 W6 final server fix: every chat push needs the push key (each one fails, counted, without it).
  IF coalesce(public.app_setting('dating_push_key'), '') = '' THEN
    RAISE WARNING 'dev_enable_spec2_dating_flags: dating_push_key is not set; every Dating push (chat, digest, notice) fails until it is';
  END IF;
END $$;
