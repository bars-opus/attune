-- lib/architecture: fixes onboarding writes that have failed for every
-- account since these four tables were created
-- (20260606120000_attune_core_schema.sql). They got RLS policies
-- (scoped to auth.uid()) but were never GRANTed to the `authenticated`
-- role — RLS only applies after a role has base table privileges, so every
-- write hit 42501 "permission denied for table users" before RLS was even
-- evaluated. public.profiles (a later migration) got this right; these four
-- did not. Grants match each table's actual policy coverage exactly — e.g.
-- relationship_invite_acceptances has only a SELECT policy (writes go
-- through a service-role edge function), so it gets only SELECT.

REVOKE ALL ON public.users FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE ON public.users TO authenticated;

REVOKE ALL ON public.relationships FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE ON public.relationships TO authenticated;

REVOKE ALL ON public.relationship_invite_acceptances FROM PUBLIC, anon;
GRANT SELECT ON public.relationship_invite_acceptances TO authenticated;

REVOKE ALL ON public.onboarding_profiles FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE ON public.onboarding_profiles TO authenticated;
