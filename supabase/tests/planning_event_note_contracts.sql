-- Event/link/Note RPC contracts (Plan A, Task 3).
-- Run: psql -q -d attune_test -f supabase/tests/planning_event_note_contracts.sql
--
-- Deviations from the task-3 brief's given SQL (see task-3-report.md for
-- full rationale):
--   1. The brief's fixture inserted only into auth.users. relationships
--      .user_a/user_b FK to public.users, not auth.users directly (the
--      same bug Task 1 and Task 2's briefs both had) -- added the
--      matching public.users insert, same shape as
--      planning_schema_contracts.sql / planning_item_contracts.sql.
--   2. The brief's v_event_id/v_task_id/v_goal_id/v_goal_child_id/
--      v_other_task_id used the '66666666-...' prefix, which collides
--      with planning_schema_contracts.sql's v_immutable_id
--      ('66666666-0000-0000-0000-000000000001'); and v_note_id used
--      '77777777-...', colliding with planning_item_contracts.sql's
--      v_goal_id/v_only_child ('77777777-...0001'/'...0002'). All SQL
--      test files run against the same database without per-file
--      cleanup, so a collision means this file's INSERT silently
--      no-ops (ON CONFLICT DO NOTHING) against a DIFFERENT row shape
--      from another test's fixture, or a later positive assertion
--      passes vacuously against pre-existing data. Remapped this
--      file's own prefixes to '88888888-...' (events/tasks/goals) and
--      '99999999-...' (notes), which are unused elsewhere in
--      supabase/tests/. No RPC/migration logic changed.
--   3. The brief's v_rel_other fixture inserted (v_rel_other, v_user_c,
--      v_user_c, 'active') -- user_a = user_b. relationships has
--      CHECK (user_b IS NULL OR user_a <> user_b), so this row is
--      rejected outright and the whole DO block fails before any
--      contract runs (not a vacuous pass -- an outright crash, but
--      same root cause class as Task 1/2's brief bugs: unverified
--      fixture SQL). Added a second, distinct user (v_user_d) as
--      v_rel_other's user_b, matching the two-distinct-users pattern
--      already used for the "other relationship" fixture in
--      planning_schema_contracts.sql. v_other_task_id is created under
--      v_user_c's session (the only session with access to
--      v_rel_other in this file), then the active session switches
--      back to v_user_a for the rest of the contracts -- the brief's
--      original SQL never switched role before this call either.
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := '11111111-0000-0000-0000-000000000020';
  v_rel_other uuid := '11111111-0000-0000-0000-000000000021';
  v_user_a uuid := 'aaaaaaaa-0000-0000-0000-000000000020';
  v_user_b uuid := 'bbbbbbbb-0000-0000-0000-000000000020';
  v_user_c uuid := 'cccccccc-0000-0000-0000-000000000020';
  v_user_d uuid := 'dddddddd-0000-0000-0000-000000000020';
  v_event_id uuid := '88888888-0000-0000-0000-000000000001';
  v_task_id uuid := '88888888-0000-0000-0000-000000000002';
  v_goal_id uuid := '88888888-0000-0000-0000-000000000003';
  v_goal_child_id uuid := '88888888-0000-0000-0000-000000000004';
  v_other_task_id uuid := '88888888-0000-0000-0000-000000000005';
  v_note_id uuid := '99999999-0000-0000-0000-000000000001';
  v_row public.planning_events;
  v_note_row public.planning_notes;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'a20@t.test'), (v_user_b, 'b20@t.test'), (v_user_c, 'c20@t.test'),
    (v_user_d, 'd20@t.test')
  ON CONFLICT DO NOTHING;
  -- relationships.user_a/user_b FK to public.users (not auth.users
  -- directly) -- same two-table fixture shape as
  -- planning_schema_contracts.sql / planning_item_contracts.sql.
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+10000000020', 'User A20'),
    (v_user_b, '+10000000021', 'User B20'),
    (v_user_c, '+10000000022', 'User C20'),
    (v_user_d, '+10000000023', 'User D20')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active'),
         (v_rel_other, v_user_c, v_user_d, 'active')
  ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Setup: a top-level Task and a Goal (with its own child) in v_rel.
  PERFORM public.create_planning_task(v_task_id, v_rel, 'Buy the gift', NULL, NULL, NULL);
  PERFORM public.create_planning_goal(v_goal_id, v_goal_child_id, v_rel, 'A goal', 'child task');
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_c), true);
  PERFORM public.create_planning_task(v_other_task_id, v_rel_other, 'their task', NULL, NULL, NULL);
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 1: create/edit an Event.
  v_row := public.upsert_planning_event(
    v_event_id, v_rel, 'Sarah''s birthday dinner', 'Try the Italian place',
    '2026-12-25');
  IF v_row.title IS DISTINCT FROM 'Sarah''s birthday dinner' THEN
    RAISE EXCEPTION 'EXPLOIT: upsert_planning_event did not create the expected row';
  END IF;

  -- Contract 2: linking a top-level Task succeeds.
  PERFORM public.link_planning_event_task(v_event_id, v_task_id);
  IF NOT EXISTS (
    SELECT 1 FROM public.planning_event_tasks
    WHERE event_id = v_event_id AND item_id = v_task_id
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: linking a top-level Task did not create a link row';
  END IF;

  -- Contract 3: linking a Goal's CHILD (not top-level) is rejected.
  BEGIN
    PERFORM public.link_planning_event_task(v_event_id, v_goal_child_id);
    RAISE EXCEPTION 'EXPLOIT: a Goal child was linked to an Event';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 4: linking a Task from a DIFFERENT relationship's Event
  -- is structurally impossible (composite FK).
  BEGIN
    PERFORM public.link_planning_event_task(v_event_id, v_other_task_id);
    RAISE EXCEPTION 'EXPLOIT: a cross-relationship Task was linked to an Event';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 5: unlinking removes only the link row, never the Task.
  PERFORM public.unlink_planning_event_task(v_event_id, v_task_id);
  IF EXISTS (
    SELECT 1 FROM public.planning_event_tasks
    WHERE event_id = v_event_id AND item_id = v_task_id
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: unlink did not remove the link row';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.planning_items WHERE id = v_task_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'EXPLOIT: unlinking deleted the Task itself';
  END IF;

  -- Contract 6: deleting the Event removes its link rows but not the
  -- linked Task.
  PERFORM public.link_planning_event_task(v_event_id, v_task_id);
  PERFORM public.delete_planning_event(v_event_id);
  IF EXISTS (SELECT 1 FROM public.planning_event_tasks WHERE event_id = v_event_id) THEN
    RAISE EXCEPTION 'EXPLOIT: deleting the Event left link rows behind';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.planning_items WHERE id = v_task_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'EXPLOIT: deleting the Event deleted the linked Task';
  END IF;

  -- Contract 7: Notes create/edit, and blank body is allowed (title is
  -- required, body may be empty per the schema's DEFAULT '').
  v_note_row := public.upsert_planning_note(v_note_id, v_rel, 'Restaurants to try', '');
  IF v_note_row.title IS DISTINCT FROM 'Restaurants to try' THEN
    RAISE EXCEPTION 'EXPLOIT: upsert_planning_note did not create the expected row';
  END IF;

  -- Contract 8: a non-member cannot read or write across relationships.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_c), true);
  BEGIN
    PERFORM public.upsert_planning_note(gen_random_uuid(), v_rel, 'sneak', '');
    RAISE EXCEPTION 'EXPLOIT: a non-member created a Note in another relationship';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'planning event/note contracts: all held';
END $$;
