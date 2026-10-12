-- Planning v2 table grants (P1 Task 1). Plan ruling R4: no client
-- privileges at all; every read and write is a SECURITY DEFINER RPC.
-- Re-applied by scripts/local_pg_grants.sql after the harness's blanket
-- platform grant, exactly like 20260941030000_planning_table_grants.sql.
REVOKE ALL ON public.planning_categories    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_entries       FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_blocks        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_block_items   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_applied_ops   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.planning_category_seen FROM PUBLIC, anon, authenticated;
