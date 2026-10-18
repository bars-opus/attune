-- Spec 5 (R5-6): the communication and conflict quizzes wait for clinical
-- sign-off. Seeded off; supabase/sql/dev_enable_spec5_flags.sql turns it on
-- for testing (never a migration).
INSERT INTO public.feature_flags (key, enabled) VALUES ('quiz_clinical_signoff', false)
ON CONFLICT (key) DO NOTHING;
