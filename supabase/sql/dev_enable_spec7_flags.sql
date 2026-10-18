-- DEV / MANUAL TESTING ONLY. Never a migration; never run against production
-- without the owner's go-ahead (Spec 7; plan review M9). Turns on "I noticed…"
-- notes and the jar, "Share a win", and quiet states (with the "Ask for
-- support" chips). "Hide a period" is a resurfacing control with no flag:
-- it always shows. Re-run safely; undo by setting false.
INSERT INTO public.feature_flags (key, enabled) VALUES
  ('appreciation_notes', true),
  ('share_a_win', true),
  ('quiet_states', true)
ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now();
