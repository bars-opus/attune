-- supabase/migrations/20261015140000_planning_recent.sql
--
-- Planning's "Recent": the couple's plans across every category, the most
-- recently worked on first (last_activity_at — an edit, a tick, a photo
-- brings a plan back up), so what they were just doing is one tap away.
-- Read-only; no table changes.
--
-- Same shape and paging as list_planning_entries (keyset on
-- last_activity_at, id), each row the usual entry summary plus its
-- category (id, name, icon, colour) for the row's mark and label. Not
-- included: templates, deleted plans, and plans in hidden or deleted
-- categories (hidden from the home screen, so not surfaced on it either).
-- Done and archived plans stay: they were worked on too.

-- The couple's plans by activity (the per-category index can't serve a
-- read across categories).
CREATE INDEX IF NOT EXISTS planning_entries_recent_idx
  ON public.planning_entries (relationship_id, last_activity_at DESC, id DESC)
  WHERE NOT is_template AND deleted_at IS NULL;

CREATE OR REPLACE FUNCTION public.list_planning_recent(
  p_relationship_id uuid, p_cursor_at timestamptz, p_cursor_id uuid, p_limit int
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_limit   int := greatest(1, least(coalesce(p_limit, 30), 100));
  v_entries jsonb;
  v_next    jsonb := 'null'::jsonb;
BEGIN
  PERFORM public.planning_v2_actor(p_relationship_id);
  IF (p_cursor_at IS NULL) <> (p_cursor_id IS NULL) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"cursor"}');
  END IF;

  WITH page AS (
    SELECT e.id, e.last_activity_at, c.id AS category_id, c.name, c.icon, c.color,
           row_number() OVER (ORDER BY e.last_activity_at DESC, e.id DESC) AS rn
    FROM public.planning_entries e
    JOIN public.planning_categories c
      ON c.id = e.category_id AND c.deleted_at IS NULL AND c.hidden_at IS NULL
    WHERE e.relationship_id = p_relationship_id
      AND NOT e.is_template AND e.deleted_at IS NULL
      AND (p_cursor_at IS NULL OR (e.last_activity_at, e.id) < (p_cursor_at, p_cursor_id))
    ORDER BY e.last_activity_at DESC, e.id DESC
    LIMIT v_limit + 1
  )
  SELECT
    coalesce(jsonb_agg(
      public.planning_v2_entry_summary(p.id) || jsonb_build_object('category', jsonb_build_object(
        'id', p.category_id, 'name', p.name, 'icon', p.icon, 'color', p.color))
      ORDER BY p.rn) FILTER (WHERE p.rn <= v_limit), '[]'::jsonb),
    CASE WHEN max(p.rn) > v_limit THEN
      (SELECT jsonb_build_object('at', q.last_activity_at, 'id', q.id) FROM page q WHERE q.rn = v_limit)
    ELSE 'null'::jsonb END
  INTO v_entries, v_next
  FROM page p;

  RETURN jsonb_build_object('entries', v_entries, 'next_cursor', coalesce(v_next, 'null'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION public.list_planning_recent(uuid, timestamptz, uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_planning_recent(uuid, timestamptz, uuid, int) TO authenticated;
