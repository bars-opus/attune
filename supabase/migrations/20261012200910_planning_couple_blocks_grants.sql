-- Planning P4 server-only tables: re-applied by scripts/local_pg_grants.sql
-- after the harness's blanket grant (the convention since P1).
REVOKE ALL ON public.planning_poll_votes FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_member_settings FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_gallery_templates FROM PUBLIC, anon, authenticated;
