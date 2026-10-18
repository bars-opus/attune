-- DEV / MANUAL TESTING ONLY. Never a migration; never run against production
-- without the owner's go-ahead (Spec 8; plan review I5). Turns on the
-- private safety check (with the outside-perspective card) and the conflict
-- toolkit; the toolkit needs both. The hostility signals
-- (chat_hostility_signals_enabled) stay off. Clinician placeholders show as
-- "[DRAFT]" while these are on. Re-run safely; undo by setting false.
INSERT INTO public.feature_flags (key, enabled) VALUES
  ('private_safety_check', true),
  ('conflict_toolkit', true)
ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now();
