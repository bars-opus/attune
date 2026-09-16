-- Table-level grants. RLS (previous migration) is the row-level
-- authority; this is the coarser table-level privilege RLS policies
-- run on top of. authenticated gets SELECT only -- no INSERT, UPDATE,
-- or DELETE grant on any of the five tables, matching story_items'
-- shape (STORIES.md §3.3) rather than reminders' fully-open grant,
-- because every Planning mutation goes through a SECURITY DEFINER RPC
-- (spec §4.1/§4.2).
REVOKE ALL ON public.planning_items FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.planning_items TO authenticated;

REVOKE ALL ON public.planning_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.planning_events TO authenticated;

REVOKE ALL ON public.planning_event_tasks FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.planning_event_tasks TO authenticated;

REVOKE ALL ON public.planning_notes FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.planning_notes TO authenticated;

REVOKE ALL ON public.planning_change_signals FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.planning_change_signals TO authenticated;
