-- Spec 7: grants for 20261018140400 (the replaced readers keep theirs).
REVOKE ALL ON FUNCTION public.put_planning_entry_away(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.put_planning_entry_away(uuid) TO authenticated;
