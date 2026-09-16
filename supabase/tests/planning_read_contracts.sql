-- Read RPC contracts (Plan A, Task 4).
-- Run: psql -q -d attune_test -f supabase/tests/planning_read_contracts.sql
--
-- Deviations from the task-4 brief's given SQL (see task-4-report.md for
-- full rationale):
--   1. The brief's fixture inserted only into auth.users. relationships
--      .user_a/user_b FK to public.users, not auth.users directly (the
--      same bug Tasks 1, 2, and 3's briefs all had) -- added the
--      matching public.users insert, same shape as
--      planning_schema_contracts.sql / planning_item_contracts.sql /
--      planning_event_note_contracts.sql.
--   2. The brief's content-row ids (v_goal_id, v_child1, v_task_id,
--      v_event_upcoming, v_event_past, v_note_id) used the
--      '88888888-0000-0000-0000-000000000001' through '...000006'
--      prefix/suffix combination, which collides directly with
--      planning_event_note_contracts.sql's v_event_id/v_task_id/
--      v_goal_id/v_goal_child_id/v_other_task_id
--      ('88888888-...0001' through '...0005'). All SQL test files run
--      against the same database without per-file cleanup, so this
--      would silently no-op this file's INSERTs (ON CONFLICT DO
--      NOTHING) against a DIFFERENT row shape from another test's
--      fixture, or make a later assertion pass vacuously against
--      pre-existing data instead of this file's own rows. Remapped
--      this file's content ids to the 'cccccccc-...-0000000000{30..35}'
--      range, which does not collide with existing 'cccccccc-...0003'
--      (planning_schema_contracts.sql) or 'cccccccc-...0020'
--      (planning_event_note_contracts.sql) usages, and matches this
--      file's own '030' relationship/user-id family. No RPC/migration
--      logic changed.
--   3. relationships.user_a/user_b also requires user_a <> user_b
--      (CHECK) -- the brief's v_user_a/v_user_b are already distinct,
--      so no change needed here, but verified against the same class
--      of bug Task 3's brief had.
--   4. The brief's DO block never switched to the `authenticated`
--      role. These seven RPCs are SECURITY INVOKER (by design -- RLS
--      is the sole authority), but this test session's own psql role
--      is this database's table owner, and a table owner bypasses RLS
--      regardless of role-based policies unless FORCE ROW LEVEL
--      SECURITY is set (it isn't, matching every other RLS-protected
--      table in this schema). Without `SET LOCAL ROLE authenticated`,
--      contract 8 (a non-member gets zero rows) failed for real: the
--      non-member's query returned all rows because RLS was not being
--      applied at all, table-owner bypass. Added `SET LOCAL ROLE
--      authenticated` before the first read-RPC call, matching
--      supabase/tests/story_read_contracts.sql's identical pattern for
--      its own SECURITY INVOKER read RPCs. Fixture setup (auth.users/
--      public.users/public.relationships inserts, and the SECURITY
--      DEFINER mutation RPC calls) still runs before the role switch,
--      since those need no RLS exemption and some rely on the calling
--      session being able to write auth.users directly.
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := '11111111-0000-0000-0000-000000000030';
  v_user_a uuid := 'aaaaaaaa-0000-0000-0000-000000000030';
  v_user_b uuid := 'bbbbbbbb-0000-0000-0000-000000000030';
  v_goal_id uuid := 'cccccccc-0000-0000-0000-000000000030';
  v_child1 uuid := 'cccccccc-0000-0000-0000-000000000031';
  v_child2 uuid;
  v_task_id uuid := 'cccccccc-0000-0000-0000-000000000032';
  v_event_upcoming uuid := 'cccccccc-0000-0000-0000-000000000033';
  v_event_past uuid := 'cccccccc-0000-0000-0000-000000000034';
  v_note_id uuid := 'cccccccc-0000-0000-0000-000000000035';
  v_row record;
  v_count int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'a30@t.test'), (v_user_b, 'b30@t.test')
  ON CONFLICT DO NOTHING;
  -- relationships.user_a/user_b FK to public.users (not auth.users
  -- directly) -- see deviation 1 above.
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+10000000030', 'User A30'),
    (v_user_b, '+10000000031', 'User B30')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  PERFORM public.create_planning_goal(v_goal_id, v_child1, v_rel, 'Save for the trip', 'Open account');
  v_child2 := gen_random_uuid();
  PERFORM public.add_planning_goal_task(v_child2, v_goal_id, 'Book flights', NULL, NULL);
  PERFORM public.create_planning_task(v_task_id, v_rel, 'Water the plants', NULL, NULL, '2026-06-01');
  PERFORM public.upsert_planning_event(v_event_upcoming, v_rel, 'Future thing', NULL, '2099-01-01');
  PERFORM public.upsert_planning_event(v_event_past, v_rel, 'Past thing', NULL, '2000-01-01');
  PERFORM public.upsert_planning_note(v_note_id, v_rel, 'Grocery list', 'milk, eggs');

  -- Switch to the `authenticated` role so the SECURITY INVOKER read
  -- RPCs below are actually subject to RLS -- see deviation 4 above.
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 1: list_planning_goals returns the goal with correct
  -- child_count/completed_child_count.
  SELECT * INTO v_row FROM public.list_planning_goals(v_rel, NULL, NULL, 30)
  WHERE id = v_goal_id;
  IF v_row.id IS NULL OR v_row.child_count IS DISTINCT FROM 2
     OR v_row.completed_child_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'EXPLOIT: list_planning_goals returned wrong counts';
  END IF;

  -- Contract 2: list_planning_goal_tasks returns exactly this Goal's
  -- two children, oldest first.
  SELECT count(*) INTO v_count FROM public.list_planning_goal_tasks(v_goal_id, NULL, NULL, 50);
  IF v_count IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'EXPLOIT: list_planning_goal_tasks returned % rows, expected 2', v_count;
  END IF;

  -- Contract 3: list_planning_tasks does NOT include Goal children --
  -- only top-level Tasks.
  IF EXISTS (
    SELECT 1 FROM public.list_planning_tasks(v_rel, NULL, NULL, NULL, 50)
    WHERE id IN (v_child1, v_child2)
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: list_planning_tasks leaked a Goal child as a top-level Task';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.list_planning_tasks(v_rel, NULL, NULL, NULL, 50) WHERE id = v_task_id) THEN
    RAISE EXCEPTION 'EXPLOIT: list_planning_tasks did not return the top-level Task';
  END IF;

  -- Contract 4: upcoming vs past events split correctly on p_today.
  SELECT count(*) INTO v_count FROM public.list_planning_events(v_rel, '2026-01-01'::date, true, NULL, NULL, 50);
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: expected exactly 1 upcoming event, found %', v_count;
  END IF;
  SELECT count(*) INTO v_count FROM public.list_planning_events(v_rel, '2026-01-01'::date, false, NULL, NULL, 50);
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: expected exactly 1 past event, found %', v_count;
  END IF;

  -- Contract 5: p_limit is clamped server-side even if the caller asks
  -- for more than 100.
  SELECT count(*) INTO v_count FROM public.list_planning_notes(v_rel, NULL, NULL, 99999);
  IF v_count > 100 THEN
    RAISE EXCEPTION 'EXPLOIT: p_limit was not clamped to 100';
  END IF;

  -- Contract 6: list_planning_calendar_entries includes the Task's due
  -- date and the upcoming Event's date, within range; rejects a range
  -- over 42 days.
  --
  -- Deviation from the brief: its literal range here was
  -- '2026-05-01'::date to '2026-06-30'::date, which is 60 days --
  -- itself over the 42-day limit list_planning_calendar_entries
  -- enforces, so the brief's own "in range" assertion would always
  -- raise instead of returning a count. Narrowed to a <=42-day window
  -- that still covers the due Task's 2026-06-01 due_date.
  SELECT count(*) INTO v_count FROM public.list_planning_calendar_entries(
    v_rel, '2026-05-15'::date, '2026-06-15'::date);
  IF v_count IS DISTINCT FROM 1 THEN -- only the due Task falls in range
    RAISE EXCEPTION 'EXPLOIT: list_planning_calendar_entries returned % rows, expected 1', v_count;
  END IF;
  BEGIN
    PERFORM public.list_planning_calendar_entries(v_rel, '2026-01-01'::date, '2026-12-31'::date);
    RAISE EXCEPTION 'EXPLOIT: a calendar range over 42 days was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 7: get_planning_summary returns something deterministic
  -- and non-empty for a relationship with content.
  SELECT count(*) INTO v_count FROM public.get_planning_summary(v_rel, '2026-01-01'::date);
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: get_planning_summary did not return exactly one row';
  END IF;

  -- Contract 8: a non-member gets nothing, not an error that leaks
  -- existence.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', gen_random_uuid()), true);
  SELECT count(*) INTO v_count FROM public.list_planning_tasks(v_rel, NULL, NULL, NULL, 50);
  IF v_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a non-member read another couple''s tasks';
  END IF;

  RAISE NOTICE 'planning read contracts: all held';
END $$;
