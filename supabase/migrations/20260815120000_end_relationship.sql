-- supabase/migrations/20260815120000_end_relationship.sql
--
-- First writer of chat_archived_reason = 'manual_end' — that CHECK value
-- has existed since 20260705120000_chat_system_v1_2.sql but no code path
-- has ever written it until now. See design spec
-- docs/superpowers/specs/2026-08-02-relationship-lifecycle-sync-design.md §3.

CREATE OR REPLACE FUNCTION public.end_relationship(p_relationship_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_relationship public.relationships%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_relationship
  FROM public.relationships
  WHERE id = p_relationship_id
    AND status = 'active'
    AND (user_a = v_user_id OR user_b = v_user_id)
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relationship not found or not active';
  END IF;

  UPDATE public.relationships
  SET status = 'ended',
      ended_at = now(),
      ended_by = v_user_id,
      chat_archived_at = now(),
      chat_archived_reason = 'manual_end'
  WHERE id = p_relationship_id;
END;
$$;

REVOKE ALL ON FUNCTION public.end_relationship(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.end_relationship(uuid) TO authenticated;
