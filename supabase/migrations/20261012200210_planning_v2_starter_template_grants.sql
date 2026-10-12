-- Planning v2 starter definitions: server-only. Re-applied by
-- scripts/local_pg_grants.sql after the harness's blanket grant.
REVOKE ALL ON public.planning_starter_templates FROM PUBLIC, anon, authenticated;
