-- Grants for 20261018170000. The seen marks are read and written only by
-- the Planning RPCs (SECURITY DEFINER); the replaced RPCs keep their grants.
REVOKE ALL ON public.planning_entry_seen FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_entry_summary(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_planning_entry(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_planning_home(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_planning_entry(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_planning_home(uuid) TO authenticated;
