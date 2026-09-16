-- Mutation RPC contracts for Tasks/Goals (Plan A, Task 2).
-- Run: psql -q -d attune_test -f supabase/tests/planning_item_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := '11111111-0000-0000-0000-000000000010';
  v_user_a uuid := 'aaaaaaaa-0000-0000-0000-000000000010';
  v_user_b uuid := 'bbbbbbbb-0000-0000-0000-000000000010';
  v_user_stranger uuid := 'eeeeeeee-0000-0000-0000-000000000010';
  v_goal_id uuid := '33333333-0000-0000-0000-000000000010';
  v_first_task_id uuid := '33333333-0000-0000-0000-000000000011';
  v_second_task_id uuid;
  v_task_id uuid := '33333333-0000-0000-0000-000000000012';
  v_row public.planning_items;
  v_count int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'a10@t.test'), (v_user_b, 'b10@t.test'),
    (v_user_stranger, 'e10@t.test')
  ON CONFLICT DO NOTHING;
  -- relationships.user_a/user_b FK to public.users (not auth.users
  -- directly) -- same two-table fixture shape as planning_schema_contracts.
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+10000000010', 'User A10'),
    (v_user_b, '+10000000011', 'User B10'),
    (v_user_stranger, '+10000000012', 'User E10')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 1: a non-member cannot create anything in this relationship.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_stranger), true);
  BEGIN
    PERFORM public.create_planning_task(
      gen_random_uuid(), v_rel, 'sneak in', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: a non-member created a Task';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 2: create_planning_task creates a top-level, incomplete Task.
  v_row := public.create_planning_task(
    v_task_id, v_rel, 'Book the venue', NULL, NULL, '2026-12-01');
  IF v_row.item_kind IS DISTINCT FROM 'task'
     OR v_row.parent_goal_id IS DISTINCT FROM NULL
     OR v_row.completed_at IS DISTINCT FROM NULL THEN
    RAISE EXCEPTION 'EXPLOIT: create_planning_task did not create a plain, incomplete Task';
  END IF;

  -- Contract 3: create_planning_goal is atomic -- the Goal and its
  -- first child both exist, or (tested via a later contract) neither
  -- does.
  v_row := public.create_planning_goal(
    v_goal_id, v_first_task_id, v_rel, 'Save for the trip',
    'Open savings account');
  IF v_row.item_kind IS DISTINCT FROM 'goal' THEN
    RAISE EXCEPTION 'EXPLOIT: create_planning_goal did not return a Goal row';
  END IF;
  SELECT count(*) INTO v_count FROM public.planning_items
  WHERE parent_goal_id = v_goal_id AND deleted_at IS NULL;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: create_planning_goal did not create exactly one child';
  END IF;

  -- Contract 4: add_planning_goal_task adds an incomplete child and
  -- does not flip the Goal complete.
  v_second_task_id := gen_random_uuid();
  PERFORM public.add_planning_goal_task(
    v_second_task_id, v_goal_id, 'Book flights', NULL, NULL);
  IF EXISTS (
    SELECT 1 FROM public.planning_items
    WHERE id = v_goal_id AND completed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: adding an incomplete child left the Goal complete';
  END IF;

  -- Contract 5: assigned_to must be a member of the relationship.
  BEGIN
    PERFORM public.update_planning_item(
      v_task_id, NULL, NULL, v_user_stranger, NULL);
    RAISE EXCEPTION 'EXPLOIT: a non-member was accepted as an assignee';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 6: set_planning_task_completion on a top-level Task
  -- toggles it and does not touch any Goal.
  v_row := public.set_planning_task_completion(v_task_id, true);
  IF v_row.completed_at IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: completing a Task left completed_at NULL';
  END IF;

  -- Contract 7: completing the LAST incomplete child completes the
  -- Goal and inserts exactly one celebration message.
  PERFORM public.set_planning_task_completion(v_first_task_id, true);
  PERFORM public.set_planning_task_completion(v_second_task_id, true);
  IF NOT EXISTS (
    SELECT 1 FROM public.planning_items
    WHERE id = v_goal_id AND completed_at IS NOT NULL AND celebrated_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: completing every child did not complete/celebrate the Goal';
  END IF;
  SELECT count(*) INTO v_count FROM public.messages
  WHERE relationship_id = v_rel AND is_system_notice
    AND content LIKE '%Save for the trip%';
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: expected exactly one celebration message, found %', v_count;
  END IF;

  -- Contract 8: reopening (uncomplete one child) clears completed_at
  -- but NOT celebrated_at, and recompleting sends NO second message.
  PERFORM public.set_planning_task_completion(v_second_task_id, false);
  IF EXISTS (
    SELECT 1 FROM public.planning_items WHERE id = v_goal_id AND completed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: uncompleting a child left the Goal marked complete';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.planning_items WHERE id = v_goal_id AND celebrated_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: reopening the Goal cleared celebrated_at';
  END IF;
  PERFORM public.set_planning_task_completion(v_second_task_id, true);
  SELECT count(*) INTO v_count FROM public.messages
  WHERE relationship_id = v_rel AND is_system_notice
    AND content LIKE '%Save for the trip%';
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: recompleting the Goal sent a second celebration, found %', v_count;
  END IF;

  -- Contract 9: a retried create with the SAME id and SAME payload
  -- returns the existing row rather than erroring or duplicating it
  -- (spec §3, §9 "Duplicate create retry").
  v_row := public.create_planning_task(
    v_task_id, v_rel, 'Book the venue', NULL, NULL, '2026-12-01');
  IF v_row.id IS DISTINCT FROM v_task_id THEN
    RAISE EXCEPTION 'EXPLOIT: retrying create_planning_task did not return the existing row';
  END IF;
  SELECT count(*) INTO v_count FROM public.planning_items WHERE id = v_task_id;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: retrying create_planning_task duplicated the row, found %', v_count;
  END IF;

  -- Contract 10: reusing the SAME id with a DIFFERENT creator is
  -- rejected outright rather than silently returning someone else's
  -- row (spec §3 "conflicting reuse of an ID is rejected").
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
  BEGIN
    PERFORM public.create_planning_task(
      v_task_id, v_rel, 'A different task', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: create_planning_task returned someone else''s row on id reuse';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 11: the SAME creator reusing the SAME id with a
  -- DIFFERENT title is rejected -- relationship/creator/kind matching
  -- alone is not enough; the payload must match too. Without this
  -- check the earlier retry (contract 9) would have silently
  -- succeeded here as well, returning the ORIGINAL title and quietly
  -- discarding the caller's edit with no error.
  BEGIN
    PERFORM public.create_planning_task(
      v_task_id, v_rel, 'Book a DIFFERENT venue', NULL, NULL, '2026-12-01');
    RAISE EXCEPTION 'EXPLOIT: create_planning_task accepted id reuse with a changed title';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'planning item retry contracts: all held';
END $$;

-- Fresh block: sole-child deletion must go through the RPC to be
-- meaningfully tested (a raw DELETE bypasses the RPC's own check).
DO $$
DECLARE
  v_rel uuid := '11111111-0000-0000-0000-000000000010';
  v_user_a uuid := 'aaaaaaaa-0000-0000-0000-000000000010';
  v_goal_id uuid := '77777777-0000-0000-0000-000000000001';
  v_only_child uuid := '77777777-0000-0000-0000-000000000002';
BEGIN
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  PERFORM public.create_planning_goal(
    v_goal_id, v_only_child, v_rel, 'Solo goal', 'Only task');

  BEGIN
    PERFORM public.delete_planning_item(v_only_child);
    RAISE EXCEPTION 'EXPLOIT: deleting the sole remaining child was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- But deleting the GOAL soft-deletes it and its child atomically.
  PERFORM public.delete_planning_item(v_goal_id);
  IF EXISTS (
    SELECT 1 FROM public.planning_items
    WHERE id IN (v_goal_id, v_only_child) AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: deleting the Goal did not soft-delete its child';
  END IF;

  RAISE NOTICE 'planning item contracts: all held';
END $$;
