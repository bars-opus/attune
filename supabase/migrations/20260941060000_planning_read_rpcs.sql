-- Read RPCs. SECURITY INVOKER throughout -- RLS (Task 1) remains the
-- sole authority; these functions never bypass it (spec §5, following
-- STORIES.md §5.5's identical reasoning).

CREATE OR REPLACE FUNCTION public.list_planning_goals(
  p_relationship_id uuid, p_after_updated_at timestamptz, p_after_id uuid, p_limit int
) RETURNS TABLE (
  id uuid, title text, note text, completed_at timestamptz,
  updated_at timestamptz, child_count bigint, completed_child_count bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    g.id, g.title, g.note, g.completed_at, g.updated_at,
    count(c.id) AS child_count,
    count(c.id) FILTER (WHERE c.completed_at IS NOT NULL) AS completed_child_count
  FROM public.planning_items g
  LEFT JOIN public.planning_items c
    ON c.parent_goal_id = g.id AND c.deleted_at IS NULL
  WHERE g.relationship_id = p_relationship_id
    AND g.item_kind = 'goal'
    AND g.deleted_at IS NULL
    AND (
      p_after_updated_at IS NULL
      OR (g.updated_at, g.id) < (p_after_updated_at, p_after_id)
    )
  GROUP BY g.id, g.title, g.note, g.completed_at, g.updated_at
  ORDER BY g.updated_at DESC, g.id DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
$$;
REVOKE ALL ON FUNCTION public.list_planning_goals(uuid, timestamptz, uuid, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_planning_goals(uuid, timestamptz, uuid, int)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.list_planning_goal_tasks(
  p_goal_id uuid, p_after_created_at timestamptz, p_after_id uuid, p_limit int
) RETURNS SETOF public.planning_items
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT * FROM public.planning_items
  WHERE parent_goal_id = p_goal_id
    AND deleted_at IS NULL
    AND (
      p_after_created_at IS NULL
      OR (created_at, id) > (p_after_created_at, p_after_id)
    )
  ORDER BY created_at ASC, id ASC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
$$;
REVOKE ALL ON FUNCTION public.list_planning_goal_tasks(uuid, timestamptz, uuid, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_planning_goal_tasks(uuid, timestamptz, uuid, int)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.list_planning_tasks(
  p_relationship_id uuid, p_after_due_date date, p_after_updated_at timestamptz,
  p_after_id uuid, p_limit int
) RETURNS SETOF public.planning_items
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT * FROM public.planning_items
  WHERE relationship_id = p_relationship_id
    AND item_kind = 'task'
    AND parent_goal_id IS NULL
    AND deleted_at IS NULL
    AND (
      p_after_updated_at IS NULL
      OR (
        (completed_at IS NOT NULL),
        COALESCE(due_date, 'infinity'::date),
        updated_at, id
      ) > (
        (SELECT completed_at IS NOT NULL FROM public.planning_items WHERE id = p_after_id),
        (SELECT COALESCE(due_date, 'infinity'::date) FROM public.planning_items WHERE id = p_after_id),
        p_after_updated_at, p_after_id
      )
    )
  ORDER BY (completed_at IS NOT NULL) ASC, COALESCE(due_date, 'infinity'::date) ASC,
           updated_at DESC, id DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
$$;
REVOKE ALL ON FUNCTION public.list_planning_tasks(uuid, date, timestamptz, uuid, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_planning_tasks(uuid, date, timestamptz, uuid, int)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.list_planning_events(
  p_relationship_id uuid, p_today date, p_upcoming boolean,
  p_after_date date, p_after_id uuid, p_limit int
) RETURNS SETOF public.planning_events
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT * FROM public.planning_events
  WHERE relationship_id = p_relationship_id
    AND deleted_at IS NULL
    AND (
      (p_upcoming AND event_date >= p_today)
      OR (NOT p_upcoming AND event_date < p_today)
    )
    AND (
      p_after_date IS NULL
      OR (
        CASE WHEN p_upcoming THEN (event_date, id) > (p_after_date, p_after_id)
             ELSE (event_date, id) < (p_after_date, p_after_id) END
      )
    )
  ORDER BY
    CASE WHEN p_upcoming THEN event_date END ASC,
    CASE WHEN p_upcoming THEN id END ASC,
    CASE WHEN NOT p_upcoming THEN event_date END DESC,
    CASE WHEN NOT p_upcoming THEN id END DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
$$;
REVOKE ALL ON FUNCTION public.list_planning_events(uuid, date, boolean, date, uuid, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_planning_events(uuid, date, boolean, date, uuid, int)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.list_planning_notes(
  p_relationship_id uuid, p_after_updated_at timestamptz, p_after_id uuid, p_limit int
) RETURNS SETOF public.planning_notes
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT * FROM public.planning_notes
  WHERE relationship_id = p_relationship_id
    AND deleted_at IS NULL
    AND (
      p_after_updated_at IS NULL
      OR (updated_at, id) < (p_after_updated_at, p_after_id)
    )
  ORDER BY updated_at DESC, id DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
$$;
REVOKE ALL ON FUNCTION public.list_planning_notes(uuid, timestamptz, uuid, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_planning_notes(uuid, timestamptz, uuid, int)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.list_planning_calendar_entries(
  p_relationship_id uuid, p_start_date date, p_end_date date
) RETURNS TABLE (
  entry_kind text, entry_id uuid, entry_date date, title text, is_complete boolean
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  -- 42 days is the visible calendar grid this is bound to (spec §7);
  -- an unbounded range is a defect here, not a style choice, the same
  -- discipline STORIES.md §5.5 holds every read to.
  IF p_end_date < p_start_date OR p_end_date - p_start_date > 42 THEN
    RAISE EXCEPTION 'Calendar range must be at most 42 days';
  END IF;

  RETURN QUERY
  SELECT 'task'::text, planning_items.id, planning_items.due_date, planning_items.title,
         (planning_items.completed_at IS NOT NULL)
  FROM public.planning_items
  WHERE relationship_id = p_relationship_id
    AND item_kind = 'task'
    AND deleted_at IS NULL
    AND due_date BETWEEN p_start_date AND p_end_date
  UNION ALL
  SELECT 'event'::text, planning_events.id, planning_events.event_date, planning_events.title, false
  FROM public.planning_events
  WHERE relationship_id = p_relationship_id
    AND deleted_at IS NULL
    AND event_date BETWEEN p_start_date AND p_end_date;
END;
$$;
REVOKE ALL ON FUNCTION public.list_planning_calendar_entries(uuid, date, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_planning_calendar_entries(uuid, date, date)
  TO authenticated;

-- Priority order per spec §6.1: overdue Task (nearest-missed first),
-- then Task due today or later (soonest first), then next upcoming
-- Event, then most recently updated live item of any kind, then
-- nothing (empty state is the client's job when this returns 0 rows).
CREATE OR REPLACE FUNCTION public.get_planning_summary(
  p_relationship_id uuid, p_today date
) RETURNS TABLE (
  kind text, id uuid, title text, context_date date
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.planning_items
    WHERE relationship_id = p_relationship_id AND item_kind = 'task'
      AND deleted_at IS NULL AND completed_at IS NULL
      AND due_date IS NOT NULL AND due_date < p_today
  ) THEN
    RETURN QUERY SELECT 'overdue_task'::text, planning_items.id, planning_items.title, planning_items.due_date
      FROM public.planning_items
      WHERE relationship_id = p_relationship_id AND item_kind = 'task'
        AND deleted_at IS NULL AND completed_at IS NULL
        AND due_date IS NOT NULL AND due_date < p_today
      ORDER BY due_date DESC, updated_at DESC, id DESC
      LIMIT 1;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.planning_items
    WHERE relationship_id = p_relationship_id AND item_kind = 'task'
      AND deleted_at IS NULL AND completed_at IS NULL
      AND due_date IS NOT NULL AND due_date >= p_today
  ) THEN
    RETURN QUERY SELECT 'upcoming_task'::text, planning_items.id, planning_items.title, planning_items.due_date
      FROM public.planning_items
      WHERE relationship_id = p_relationship_id AND item_kind = 'task'
        AND deleted_at IS NULL AND completed_at IS NULL
        AND due_date IS NOT NULL AND due_date >= p_today
      ORDER BY due_date ASC, updated_at DESC, id DESC
      LIMIT 1;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.planning_events
    WHERE relationship_id = p_relationship_id AND deleted_at IS NULL
      AND event_date >= p_today
  ) THEN
    RETURN QUERY SELECT 'upcoming_event'::text, planning_events.id, planning_events.title, planning_events.event_date
      FROM public.planning_events
      WHERE relationship_id = p_relationship_id AND deleted_at IS NULL
        AND event_date >= p_today
      ORDER BY event_date ASC, id ASC
      LIMIT 1;
    RETURN;
  END IF;

  -- Most recently updated live item of ANY kind (Goal, Task, Event, or
  -- Note), Goal children excluded since they are not independently
  -- surfaced on the summary row (spec §6.1).
  RETURN QUERY
  SELECT everything.kind, everything.id, everything.title, everything.context_date FROM (
    SELECT 'goal'::text AS kind, planning_items.id, planning_items.title, NULL::date AS context_date, planning_items.updated_at
    FROM public.planning_items
    WHERE relationship_id = p_relationship_id AND item_kind = 'goal' AND deleted_at IS NULL
    UNION ALL
    SELECT 'task'::text, planning_items.id, planning_items.title, planning_items.due_date, planning_items.updated_at
    FROM public.planning_items
    WHERE relationship_id = p_relationship_id AND item_kind = 'task'
      AND parent_goal_id IS NULL AND deleted_at IS NULL
    UNION ALL
    SELECT 'event'::text, planning_events.id, planning_events.title, planning_events.event_date, planning_events.updated_at
    FROM public.planning_events
    WHERE relationship_id = p_relationship_id AND deleted_at IS NULL
    UNION ALL
    SELECT 'note'::text, planning_notes.id, planning_notes.title, NULL::date, planning_notes.updated_at
    FROM public.planning_notes
    WHERE relationship_id = p_relationship_id AND deleted_at IS NULL
  ) everything
  ORDER BY everything.updated_at DESC, everything.id DESC
  LIMIT 1;
END;
$$;
REVOKE ALL ON FUNCTION public.get_planning_summary(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_planning_summary(uuid, date) TO authenticated;
