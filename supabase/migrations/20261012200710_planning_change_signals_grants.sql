-- planning_change_signals outlives v1 (the new Planning bumps it for
-- Realtime). Its grants used to be re-applied by the v1 grants migration,
-- whose other tables are now dropped, so they get their own file:
-- authenticated may read (Realtime subscription), never write.
REVOKE ALL ON public.planning_change_signals FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.planning_change_signals TO authenticated;
