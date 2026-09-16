-- Schema-level contracts for Planning (Plan A, Task 1).
-- Run: psql -q -d attune_test -f supabase/tests/planning_schema_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel_a uuid := '11111111-0000-0000-0000-000000000001';
  v_user_a uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_user_b uuid := 'bbbbbbbb-0000-0000-0000-000000000002';
  v_rel_other uuid := '22222222-0000-0000-0000-000000000002';
  v_user_c uuid := 'cccccccc-0000-0000-0000-000000000003';
  v_user_d uuid := 'dddddddd-0000-0000-0000-000000000004';
  v_goal_id uuid := '33333333-0000-0000-0000-000000000001';
  v_task_id uuid := '33333333-0000-0000-0000-000000000002';
  v_other_goal_id uuid := '44444444-0000-0000-0000-000000000001';
BEGIN
  -- Fixtures: two relationships, four users, one active each.
  -- relationships.user_a/user_b FK to public.users (not auth.users
  -- directly), so both rows are required -- see the ask2_* tests for
  -- the same two-table fixture shape.
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'a@t.test'), (v_user_b, 'b@t.test'),
    (v_user_c, 'c@t.test'), (v_user_d, 'd@t.test')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+10000000001', 'User A'), (v_user_b, '+10000000002', 'User B'),
    (v_user_c, '+10000000003', 'User C'), (v_user_d, '+10000000004', 'User D')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel_a, v_user_a, v_user_b, 'active'),
         (v_rel_other, v_user_c, v_user_d, 'active')
  ON CONFLICT DO NOTHING;

  -- Contract 1: item_kind is stored, not derivable, and immutable in
  -- shape. A Goal row and its Task child.
  INSERT INTO public.planning_items
    (id, relationship_id, created_by, item_kind, title)
  VALUES (v_goal_id, v_rel_a, v_user_a, 'goal', 'Save for the trip');

  INSERT INTO public.planning_items
    (id, relationship_id, created_by, item_kind, parent_goal_id, title)
  VALUES (v_task_id, v_rel_a, v_user_a, 'task', v_goal_id, 'Open savings account');

  -- Contract 2: a Task cannot itself have a child (depth cap).
  BEGIN
    INSERT INTO public.planning_items
      (id, relationship_id, created_by, item_kind, parent_goal_id, title)
    VALUES (gen_random_uuid(), v_rel_a, v_user_a, 'task', v_task_id, 'nested');
    RAISE EXCEPTION 'EXPLOIT: a Task accepted a child (depth cap failed)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    -- expected: the trigger's own RAISE EXCEPTION fired instead.
  END;

  -- Contract 3: a Goal cannot have a parent_goal_id (only a Task can).
  BEGIN
    INSERT INTO public.planning_items
      (id, relationship_id, created_by, item_kind, parent_goal_id, title)
    VALUES (v_other_goal_id, v_rel_a, v_user_a, 'goal', v_goal_id, 'nested goal');
    RAISE EXCEPTION 'EXPLOIT: a Goal accepted a parent_goal_id';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 4: cross-relationship parent link is structurally
  -- impossible, not just RPC-checked. Attempt: a Task in rel_a claims
  -- a parent Goal that belongs to rel_other.
  INSERT INTO public.planning_items
    (id, relationship_id, created_by, item_kind, title)
  VALUES (v_other_goal_id, v_rel_other, v_user_c, 'goal', 'their goal');

  BEGIN
    INSERT INTO public.planning_items
      (id, relationship_id, created_by, item_kind, parent_goal_id, title)
    VALUES (gen_random_uuid(), v_rel_a, v_user_a, 'task', v_other_goal_id, 'cross-couple');
    RAISE EXCEPTION 'EXPLOIT: a cross-relationship parent link was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 5: blank-after-trim title is rejected.
  BEGIN
    INSERT INTO public.planning_items
      (id, relationship_id, created_by, item_kind, title)
    VALUES (gen_random_uuid(), v_rel_a, v_user_a, 'task', '   ');
    RAISE EXCEPTION 'EXPLOIT: a whitespace-only title was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 6: celebrated_at may only be set on a Goal.
  BEGIN
    UPDATE public.planning_items SET celebrated_at = now()
    WHERE id = v_task_id;
    RAISE EXCEPTION 'EXPLOIT: celebrated_at was set on a Task';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 7: updated_at is server-owned and advances on UPDATE,
  -- ignoring anything the caller supplies.
  PERFORM pg_sleep(0.01);
  UPDATE public.planning_items SET note = 'bought the tickets'
  WHERE id = v_task_id;
  IF NOT EXISTS (
    SELECT 1 FROM public.planning_items
    WHERE id = v_task_id AND updated_at > created_at
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: updated_at did not advance on UPDATE';
  END IF;

  -- Contract 8: RLS -- a non-member of rel_a cannot see rel_a's rows.
  -- Must actually switch to the `authenticated` role, not merely set
  -- request.jwt.claims: RLS policies never apply to the table owner
  -- (the role this DO block runs as by default), so without the role
  -- switch this check would silently pass regardless of policy
  -- correctness -- matching the SET LOCAL ROLE pattern
  -- chat_import_contracts.sql already uses for the same reason.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_user_c::text, 'role', 'authenticated')::text,
    true);
  SET LOCAL ROLE authenticated;
  IF EXISTS (
    SELECT 1 FROM public.planning_items WHERE relationship_id = v_rel_a
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: a non-member could read another couple''s planning_items';
  END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', NULL, true);

  -- Contract 9: authenticated has SELECT but no direct write privilege.
  IF has_table_privilege('authenticated', 'public.planning_items', 'INSERT') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has direct INSERT on planning_items';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.planning_items', 'SELECT') THEN
    RAISE EXCEPTION 'authenticated is missing SELECT on planning_items';
  END IF;

  -- Contract 10: planning_change_signals is in the Realtime publication.
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'planning_change_signals'
  ) THEN
    RAISE EXCEPTION 'planning_change_signals was not added to supabase_realtime';
  END IF;

  RAISE NOTICE 'planning schema contracts: all held';
END $$;
