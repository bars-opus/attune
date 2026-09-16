-- Mutation RPCs for planning_items (Tasks and Goals).
-- Spec: docs/superpowers/specs/2026-09-14-planning-design.md §4.2, §4.3.

CREATE OR REPLACE FUNCTION public.planning_is_active_member(
  p_relationship_id uuid, p_user_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = p_user_id OR r.user_b = p_user_id)
  );
$$;
REVOKE ALL ON FUNCTION public.planning_is_active_member(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

-- Internal helper: recomputes and, if needed, transitions a Goal's
-- completed_at, and sends the one-time celebration message. Never
-- callable by a client directly -- only the public RPCs below call it,
-- and always with the Goal row already locked FOR UPDATE by the
-- caller (see each public RPC's own lock).
CREATE OR REPLACE FUNCTION public.reconcile_planning_goal(
  p_goal_id uuid, p_actor_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_goal public.planning_items;
  v_live_count int;
  v_incomplete_count int;
  v_now timestamptz := statement_timestamp();
  v_message_id uuid;
BEGIN
  SELECT * INTO v_goal FROM public.planning_items
  WHERE id = p_goal_id AND item_kind = 'goal';
  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT count(*),
         count(*) FILTER (WHERE completed_at IS NULL)
    INTO v_live_count, v_incomplete_count
  FROM public.planning_items
  WHERE parent_goal_id = p_goal_id AND deleted_at IS NULL;

  IF v_live_count = 0 THEN
    -- Should not happen under the invariants this plan enforces
    -- (Goal creation always seeds one child; sole-child delete is
    -- rejected). Defensive: never mark an empty Goal complete.
    RETURN;
  END IF;

  IF v_incomplete_count > 0 THEN
    IF v_goal.completed_at IS NOT NULL THEN
      UPDATE public.planning_items SET completed_at = NULL
      WHERE id = p_goal_id;
    END IF;
    RETURN;
  END IF;

  -- Every live child is complete.
  IF v_goal.completed_at IS NULL THEN
    UPDATE public.planning_items SET completed_at = v_now
    WHERE id = p_goal_id;
  END IF;

  -- Celebration: exactly once, ever, guarded by celebrated_at.
  IF v_goal.celebrated_at IS NULL THEN
    v_message_id := gen_random_uuid();
    INSERT INTO public.messages (
      id, relationship_id, sender_id, client_message_id, content,
      is_system_notice, message_analysis_skipped, source, created_at
    ) VALUES (
      v_message_id, v_goal.relationship_id, p_actor_id, gen_random_uuid(),
      '🎉 Goal completed: ' || v_goal.title,
      true, true, 'native', v_now
    );
    UPDATE public.planning_items SET celebrated_at = v_now
    WHERE id = p_goal_id;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_planning_goal(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.bump_planning_signal(
  p_relationship_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.planning_change_signals (relationship_id, version, updated_at)
  VALUES (p_relationship_id, 1, now())
  ON CONFLICT (relationship_id) DO UPDATE
    SET version = planning_change_signals.version + 1, updated_at = now();
END;
$$;
REVOKE ALL ON FUNCTION public.bump_planning_signal(uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_planning_task(
  p_id uuid, p_relationship_id uuid, p_title text, p_note text,
  p_assigned_to uuid, p_due_date date
) RETURNS public.planning_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_items;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.planning_is_active_member(p_relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;
  IF p_assigned_to IS NOT NULL
     AND NOT public.planning_is_active_member(p_relationship_id, p_assigned_to) THEN
    RAISE EXCEPTION 'Assignee must be a member of this relationship';
  END IF;

  INSERT INTO public.planning_items (
    id, relationship_id, created_by, item_kind, title, note,
    assigned_to, due_date
  ) VALUES (
    p_id, p_relationship_id, v_actor, 'task', btrim(p_title), p_note,
    p_assigned_to, p_due_date
  )
  ON CONFLICT (id) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    -- A retry matches ONLY when relationship, creator, kind, AND the
    -- normalized create payload all match (spec §3, "A retry returns
    -- the existing row only when ... match; conflicting reuse of an
    -- ID is rejected"). Matching only on relationship/creator/kind
    -- would silently accept a retry that also changed the title/note/
    -- assignee/due_date, returning the ORIGINAL row while discarding
    -- the caller's new values with no error -- a client that thought
    -- its edit landed would be wrong with no signal it failed.
    SELECT * INTO v_row FROM public.planning_items
    WHERE id = p_id AND relationship_id = p_relationship_id
      AND created_by = v_actor AND item_kind = 'task'
      AND title = btrim(p_title)
      -- IS NOT DISTINCT FROM, not =: two NULLs (both callers omitted
      -- an optional field) must count as matching, and = against NULL
      -- is never true -- the exact NULL-blind trap this project has
      -- shipped before.
      AND note IS NOT DISTINCT FROM p_note
      AND assigned_to IS NOT DISTINCT FROM p_assigned_to
      AND due_date IS NOT DISTINCT FROM p_due_date;
    IF v_row.id IS NULL THEN
      RAISE EXCEPTION 'A different item already exists with this id';
    END IF;
    RETURN v_row;
  END IF;

  PERFORM public.bump_planning_signal(p_relationship_id);
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.create_planning_task(uuid, uuid, text, text, uuid, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_planning_task(uuid, uuid, text, text, uuid, date)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.create_planning_goal(
  p_goal_id uuid, p_first_task_id uuid, p_relationship_id uuid,
  p_goal_title text, p_first_task_title text
) RETURNS public.planning_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_goal public.planning_items;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.planning_is_active_member(p_relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;
  IF p_goal_id = p_first_task_id THEN
    RAISE EXCEPTION 'A Goal and its first Task must have different ids';
  END IF;

  -- Atomic with the first child: no code path can produce a
  -- zero-child Goal (spec §3.1.0b in the earlier draft; this RPC is
  -- the enforcement).
  INSERT INTO public.planning_items (id, relationship_id, created_by, item_kind, title)
  VALUES (p_goal_id, p_relationship_id, v_actor, 'goal', btrim(p_goal_title))
  ON CONFLICT (id) DO NOTHING
  RETURNING * INTO v_goal;

  IF v_goal.id IS NULL THEN
    -- Same payload-match requirement as create_planning_task: a retry
    -- matches only when the normalized title matches too, not merely
    -- relationship/creator/kind (spec §3).
    SELECT * INTO v_goal FROM public.planning_items
    WHERE id = p_goal_id AND relationship_id = p_relationship_id
      AND created_by = v_actor AND item_kind = 'goal'
      AND title = btrim(p_goal_title);
    IF v_goal.id IS NULL THEN
      RAISE EXCEPTION 'A different item already exists with this id';
    END IF;
    -- The Goal row matches, but ALSO require its first-task pairing
    -- to match -- a retry that reused p_goal_id with a genuinely new
    -- p_first_task_id (a client bug, not a legitimate retry) must not
    -- silently succeed and leave that new task id never created.
    IF NOT EXISTS (
      SELECT 1 FROM public.planning_items
      WHERE id = p_first_task_id AND parent_goal_id = p_goal_id
        AND title = btrim(p_first_task_title)
    ) THEN
      RAISE EXCEPTION 'A different item already exists with this id';
    END IF;
    RETURN v_goal;
  END IF;

  INSERT INTO public.planning_items (
    id, relationship_id, created_by, item_kind, parent_goal_id, title
  ) VALUES (
    p_first_task_id, p_relationship_id, v_actor, 'task', p_goal_id,
    btrim(p_first_task_title)
  );

  PERFORM public.bump_planning_signal(p_relationship_id);
  RETURN v_goal;
END;
$$;
REVOKE ALL ON FUNCTION public.create_planning_goal(uuid, uuid, uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_planning_goal(uuid, uuid, uuid, text, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.add_planning_goal_task(
  p_task_id uuid, p_goal_id uuid, p_title text, p_note text, p_due_date date
) RETURNS public.planning_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_goal public.planning_items;
  v_live_count int;
  v_row public.planning_items;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Lock the Goal row before counting -- this, together with the same
  -- lock in set_planning_task_completion and delete_planning_item, is
  -- what makes two partners' concurrent edits to the same Goal
  -- serialize instead of race (spec §4.3, §9).
  SELECT * INTO v_goal FROM public.planning_items
  WHERE id = p_goal_id AND item_kind = 'goal' AND deleted_at IS NULL
  FOR UPDATE;
  IF v_goal.id IS NULL THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;
  IF NOT public.planning_is_active_member(v_goal.relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  SELECT count(*) INTO v_live_count FROM public.planning_items
  WHERE parent_goal_id = p_goal_id AND deleted_at IS NULL;
  IF v_live_count >= 100 THEN
    RAISE EXCEPTION 'A Goal may have at most 100 tasks';
  END IF;

  INSERT INTO public.planning_items (
    id, relationship_id, created_by, item_kind, parent_goal_id, title, note, due_date
  ) VALUES (
    p_task_id, v_goal.relationship_id, v_actor, 'task', p_goal_id,
    btrim(p_title), p_note, p_due_date
  )
  ON CONFLICT (id) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    SELECT * INTO v_row FROM public.planning_items WHERE id = p_task_id;
    RETURN v_row;
  END IF;

  PERFORM public.reconcile_planning_goal(p_goal_id, v_actor);
  PERFORM public.bump_planning_signal(v_goal.relationship_id);

  SELECT * INTO v_row FROM public.planning_items WHERE id = p_task_id;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.add_planning_goal_task(uuid, uuid, text, text, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_planning_goal_task(uuid, uuid, text, text, date)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.update_planning_item(
  p_id uuid, p_title text, p_note text, p_assigned_to uuid, p_due_date date
) RETURNS public.planning_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_items;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.planning_items
  WHERE id = p_id AND deleted_at IS NULL
  FOR UPDATE;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;
  IF NOT public.planning_is_active_member(v_row.relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;
  -- assigned_to/due_date are Task-only fields; the CHECK constraint on
  -- the table also enforces this, but failing early here gives a
  -- clearer error than a bubbled-up constraint violation.
  IF v_row.item_kind = 'goal' AND (p_assigned_to IS NOT NULL OR p_due_date IS NOT NULL) THEN
    RAISE EXCEPTION 'A Goal cannot have an assignee or a due date';
  END IF;
  IF p_assigned_to IS NOT NULL
     AND NOT public.planning_is_active_member(v_row.relationship_id, p_assigned_to) THEN
    RAISE EXCEPTION 'Assignee must be a member of this relationship';
  END IF;

  UPDATE public.planning_items
  SET title = COALESCE(btrim(p_title), title),
      note = p_note,
      assigned_to = p_assigned_to,
      due_date = p_due_date
  WHERE id = p_id
  RETURNING * INTO v_row;

  PERFORM public.bump_planning_signal(v_row.relationship_id);
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.update_planning_item(uuid, text, text, uuid, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_planning_item(uuid, text, text, uuid, date)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.set_planning_task_completion(
  p_task_id uuid, p_is_complete boolean
) RETURNS public.planning_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_items;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.planning_items
  WHERE id = p_task_id AND item_kind = 'task' AND deleted_at IS NULL
  FOR UPDATE;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;
  IF NOT public.planning_is_active_member(v_row.relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  UPDATE public.planning_items
  SET completed_at = CASE WHEN p_is_complete THEN statement_timestamp() ELSE NULL END
  WHERE id = p_task_id
  RETURNING * INTO v_row;

  IF v_row.parent_goal_id IS NOT NULL THEN
    -- Lock the parent Goal too, inside this same transaction, before
    -- reconciling -- this is what serializes two partners completing
    -- the last two tasks of the same Goal at the same instant.
    PERFORM 1 FROM public.planning_items WHERE id = v_row.parent_goal_id FOR UPDATE;
    PERFORM public.reconcile_planning_goal(v_row.parent_goal_id, v_actor);
  END IF;

  PERFORM public.bump_planning_signal(v_row.relationship_id);
  SELECT * INTO v_row FROM public.planning_items WHERE id = p_task_id;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.set_planning_task_completion(uuid, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_planning_task_completion(uuid, boolean)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_planning_item(
  p_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_items;
  v_sibling_live_count int;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.planning_items WHERE id = p_id FOR UPDATE;
  IF v_row.id IS NULL THEN
    RETURN true; -- idempotent: already gone
  END IF;
  IF v_row.deleted_at IS NOT NULL THEN
    RETURN true; -- idempotent: already soft-deleted
  END IF;
  IF NOT public.planning_is_active_member(v_row.relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  IF v_row.item_kind = 'task' AND v_row.parent_goal_id IS NOT NULL THEN
    PERFORM 1 FROM public.planning_items WHERE id = v_row.parent_goal_id FOR UPDATE;
    SELECT count(*) INTO v_sibling_live_count
    FROM public.planning_items
    WHERE parent_goal_id = v_row.parent_goal_id AND deleted_at IS NULL;
    IF v_sibling_live_count <= 1 THEN
      RAISE EXCEPTION 'Delete the goal instead, or add another task first';
    END IF;
  END IF;

  -- Soft delete never fires an FK cascade -- clean up dependent rows
  -- explicitly.
  DELETE FROM public.planning_event_tasks WHERE item_id = p_id;

  IF v_row.item_kind = 'goal' THEN
    UPDATE public.planning_items SET deleted_at = now()
    WHERE (id = p_id OR parent_goal_id = p_id) AND deleted_at IS NULL;
    DELETE FROM public.planning_event_tasks
    WHERE item_id IN (
      SELECT id FROM public.planning_items WHERE parent_goal_id = p_id
    );
  ELSE
    UPDATE public.planning_items SET deleted_at = now() WHERE id = p_id;
    IF v_row.parent_goal_id IS NOT NULL THEN
      PERFORM public.reconcile_planning_goal(v_row.parent_goal_id, v_actor);
    END IF;
  END IF;

  PERFORM public.bump_planning_signal(v_row.relationship_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_planning_item(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_planning_item(uuid)
  TO authenticated;
