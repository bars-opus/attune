-- Soft delete as an RPC (plan ruling R4): an UPDATE that sets deleted_at
-- only works while PostgREST doesn't read the row back, because the read
-- policy hides deleted rows. The RPC makes it independent of that.
CREATE OR REPLACE FUNCTION public.soft_delete_timeline_event(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.timeline_events
  SET deleted_at = now(), updated_at = now()
  WHERE id = p_event_id
    AND logged_by = auth.uid()
    AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'moment not found' USING ERRCODE = 'P0002';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.soft_delete_timeline_event(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.soft_delete_timeline_event(uuid) TO authenticated;
