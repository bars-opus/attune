-- 20260724120000_grant_missing_core_table_privileges.sql revoked ALL on
-- these four tables from PUBLIC/anon and granted `authenticated` only,
-- assuming service_role either bypassed the grant requirement or already
-- had implicit access through PUBLIC. Revoking from PUBLIC removed that
-- implicit path, so every service-role edge function writing to these
-- tables (create-relationship-invite, accept-invite, onboarding functions)
-- has 403'd with `permission denied for table users` since that migration
-- — RLS is bypassed for service_role, but base table privileges are
-- checked before RLS regardless of role. Grants match the writes each
-- edge function actually performs.
GRANT SELECT, INSERT, UPDATE ON public.users TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.relationships TO service_role;
GRANT SELECT, INSERT ON public.relationship_invite_acceptances TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.onboarding_profiles TO service_role;
