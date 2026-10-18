-- supabase/migrations/20261017150100_pulse_privacy_table_grants.sql
-- Replayed by scripts/local_pg_grants.sql after its blanket grant.
REVOKE ALL ON public.pulse_private_scores FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.pulse_private_scores TO authenticated;
REVOKE ALL ON public.pulse_recompute_limits FROM PUBLIC, anon, authenticated;
