-- DEV / MANUAL TESTING ONLY. Never a migration (spec §2.5, Q19b). Turns every
-- Spec 1 flag on, on the development project only. The guard and the insert
-- are one statement (batch 5 review #5), so when the guard raises
-- env:not_development (the project doesn't read 'development', or
-- supabase_url is configured and doesn't name the development ref, or it
-- can't be read) nothing is turned on, whatever the client does after an
-- error. It never sets attune_environment. Safe to re-run; undo by setting a
-- flag false.
DO $$
BEGIN
  PERFORM private.assert_development_project();

  INSERT INTO public.feature_flags (key, enabled) VALUES
    ('flow_signin_v2', true),
    ('flow_paths_v2', true),
    ('flow_couples_v2', true),
    ('couple_profile', true),
    ('dormancy_rule', true),
    ('platform_age_signals', true),
    ('support_resources_v2', true),
    ('csam_hash_matching', true),
    ('opinions_safety_v1', true),
    ('journal_ai_insights', true),
    ('text_scale_v2', true)
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now();
END $$;
