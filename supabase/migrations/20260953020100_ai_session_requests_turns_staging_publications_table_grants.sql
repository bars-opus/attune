-- Table-level grants for AI Session requests, turns, staging, and publications.
-- RLS (previous migration) is the row-level authority; this is the coarser
-- table-level privilege RLS runs on top of.
--
-- All four tables have RLS enabled with zero policies: "no grant" is the
-- enforcement mechanism, not decoration around a REVOKE. All access goes
-- exclusively through SECURITY DEFINER RPCs built in later tasks.
REVOKE ALL ON public.ai_session_requests FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.ai_session_turns FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.ai_session_staging FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.ai_session_publications FROM PUBLIC, anon, authenticated;
