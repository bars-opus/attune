-- Table-level grants for AI Sessions. RLS (previous migration) is the
-- row-level authority; this is the coarser table-level privilege RLS runs
-- on top of.
--
-- All three tables have RLS enabled with zero policies: "no grant" is the
-- enforcement mechanism, not decoration around a REVOKE. All access goes
-- exclusively through SECURITY DEFINER RPCs built in later tasks.
REVOKE ALL ON public.ai_sessions FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.ai_session_approvals FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.ai_session_sources FROM PUBLIC, anon, authenticated;
