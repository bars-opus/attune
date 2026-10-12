-- Planning P3 server-only tables: re-applied by scripts/local_pg_grants.sql
-- after the harness's blanket grant (the convention since P1).
REVOKE ALL ON public.planning_expense_events FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_link_previews FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_link_preview_requests FROM PUBLIC, anon, authenticated;
