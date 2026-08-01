-- Dating Mode v1.1 (20260703194500_dating_mode_v1_1.sql) created RLS "owner
-- read" SELECT policies for dating_enrollments, dating_consent_events,
-- dating_profiles, and dating_preferences, but never granted the
-- `authenticated` role table-level SELECT privilege. Postgres checks GRANTs
-- before RLS, so every client select on these tables 403s
-- (permission denied for table dating_enrollments) regardless of the policy.
-- Every other feature in this codebase (healing_journeys, chat_presence,
-- feature_flags, etc.) explicitly grants SELECT to authenticated; this
-- brings the dating owner-read tables in line with that convention.
GRANT SELECT ON public.dating_enrollments TO authenticated;
GRANT SELECT ON public.dating_consent_events TO authenticated;
GRANT SELECT ON public.dating_profiles TO authenticated;
GRANT SELECT ON public.dating_preferences TO authenticated;
