-- Table-level grants. RLS (previous migration) is the row-level
-- authority; this is the coarser table-level privilege RLS runs on top
-- of.
REVOKE ALL ON public.ai_assist_drafts FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.ai_assistant_usage FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.ai_processing_consent_events FROM PUBLIC, anon, authenticated;

REVOKE ALL ON public.ai_assist_planning_links FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ai_assist_planning_links TO authenticated;
