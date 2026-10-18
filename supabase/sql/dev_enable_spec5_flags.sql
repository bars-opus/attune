-- DEV / MANUAL TESTING ONLY. Never a migration; never run against production
-- without the owner's go-ahead (Spec 5, R5-6: the owner's "flag everything on
-- for testing"). Turns on the features that ship behind a flag so the whole
-- app can be tested end to end. Re-run safely; undo by setting false.
INSERT INTO public.feature_flags (key, enabled) VALUES
  ('quiz_clinical_signoff', true),
  ('couple_map_enabled', true)
ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now();
