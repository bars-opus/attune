-- supabase/migrations/20261017120100_seen_receipts_table_grants.sql
-- seen_receipt_prefs is RPC-only. Repeated here so scripts/local_pg_grants.sql
-- can replay it after its blanket grant (same pattern as together/planning).
REVOKE ALL ON public.seen_receipt_prefs FROM PUBLIC, anon, authenticated;
