-- Countdown and Progress links (2026-10-18). Each reports what it follows
-- (computed date_block_id / checklist_block_id), and existing unlinked ones
-- are pinned once to what they show now, so adding or reordering blocks
-- never moves them. A trip still waiting on its poll stays unlinked.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users (id) VALUES ('7fba0000-0000-0000-0000-0000000000a1'), ('7fba0000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7fba0000-0000-0000-0000-0000000000a1', '+233279960001', 'Ama'),
  ('7fba0000-0000-0000-0000-0000000000b2', '+233279960002', 'Kofi')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('7fbb0000-0000-0000-0000-000000000001', '7fba0000-0000-0000-0000-0000000000a1',
   '7fba0000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.computed(p_block uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.planning_v2_block_computed(b) FROM public.planning_blocks b WHERE b.id = p_block $$;
CREATE FUNCTION pg_temp.link(p_block uuid, p_key text) RETURNS text LANGUAGE sql AS $$
  SELECT payload ->> p_key FROM public.planning_blocks WHERE id = p_block $$;

-- Trip: two dates (Trip dates first), an unlinked countdown, two checklists
-- (Packing first) and an unlinked checklist progress. Plan 2: a poll and a
-- countdown, no date yet.
DO $$
DECLARE v_e uuid := '7fbd0000-0000-0000-0000-000000000001'; v_p uuid := '7fbd0000-0000-0000-0000-000000000002';
BEGIN
  PERFORM pg_temp.as_user('7fba0000-0000-0000-0000-0000000000a1');
  PERFORM public.create_planning_category('7fbc0000-0000-0000-0000-000000000001', '7fbb0000-0000-0000-0000-000000000001',
    'Trips', (public.planning_v2_icons())[1], (public.planning_v2_colors())[1]);
  PERFORM public.create_planning_entry(v_e, '7fbc0000-0000-0000-0000-000000000001', 'Lisbon', false, 'GHS');
  PERFORM public.create_planning_entry(v_p, '7fbc0000-0000-0000-0000-000000000001', 'Somewhere', false, 'GHS');
  PERFORM public.add_planning_block('7fbe0000-0000-0000-0000-0000000000d1', v_e, 'date', '{"title":"Trip dates"}', current_date + 30, current_date + 37, NULL);
  PERFORM public.add_planning_block('7fbe0000-0000-0000-0000-0000000000d2', v_e, 'date', '{"title":"Book by"}', current_date + 5, NULL,
    '7fbe0000-0000-0000-0000-0000000000d1');
  PERFORM public.add_planning_block('7fbe0000-0000-0000-0000-0000000000c1', v_e, 'countdown', '{}', NULL, NULL,
    '7fbe0000-0000-0000-0000-0000000000d2');
  PERFORM public.add_planning_block('7fbe0000-0000-0000-0000-0000000000a1', v_e, 'checklist', '{"title":"Packing"}', NULL, NULL,
    '7fbe0000-0000-0000-0000-0000000000c1');
  PERFORM public.add_planning_block('7fbe0000-0000-0000-0000-0000000000a2', v_e, 'checklist', '{"title":"Before we go"}', NULL, NULL,
    '7fbe0000-0000-0000-0000-0000000000a1');
  PERFORM public.add_planning_block('7fbe0000-0000-0000-0000-0000000000f1', v_e, 'progress', '{"mode":"checklist"}', NULL, NULL,
    '7fbe0000-0000-0000-0000-0000000000a2');
  PERFORM public.add_planning_block('7fbe0000-0000-0000-0000-0000000000e1', v_p, 'date_poll', '{}', NULL, NULL, NULL);
  PERFORM public.add_planning_block('7fbe0000-0000-0000-0000-0000000000e2', v_p, 'countdown', '{}', NULL, NULL,
    '7fbe0000-0000-0000-0000-0000000000e1');
END $$;

-- 1. Each says what it follows: unlinked, the first date / checklist.
DO $$
DECLARE v jsonb;
BEGIN
  v := pg_temp.computed('7fbe0000-0000-0000-0000-0000000000c1');
  IF v ->> 'date_block_id' IS DISTINCT FROM '7fbe0000-0000-0000-0000-0000000000d1'
     OR (v ->> 'target_date')::date IS DISTINCT FROM current_date + 30 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: countdown does not say what it counts to %', v;
  END IF;
  v := pg_temp.computed('7fbe0000-0000-0000-0000-0000000000f1');
  IF v ->> 'checklist_block_id' IS DISTINCT FROM '7fbe0000-0000-0000-0000-0000000000a1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: progress does not say what it tracks %', v;
  END IF;
  IF pg_temp.computed('7fbe0000-0000-0000-0000-0000000000e2') ->> 'date_block_id' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a countdown with no date names one';
  END IF;
END $$;

-- 2. Pinning: unlinked ones follow what they show now; reordering after
--    never moves them; the trip waiting on its poll stays unlinked, and
--    picks up the date once the poll is locked.
DO $$
DECLARE v_n int; v_opt uuid := gen_random_uuid();
BEGIN
  v_n := public.planning_v2_pin_block_links();
  IF v_n < 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: pinned % blocks, expected the countdown and progress', v_n; END IF;
  IF pg_temp.link('7fbe0000-0000-0000-0000-0000000000c1', 'date_block_id') IS DISTINCT FROM '7fbe0000-0000-0000-0000-0000000000d1'
     OR pg_temp.link('7fbe0000-0000-0000-0000-0000000000f1', 'checklist_block_id') IS DISTINCT FROM '7fbe0000-0000-0000-0000-0000000000a1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: not pinned to what they showed';
  END IF;
  IF pg_temp.link('7fbe0000-0000-0000-0000-0000000000e2', 'date_block_id') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a countdown with no date yet was pinned';
  END IF;
  -- "Book by" and "Before we go" move to the top.
  UPDATE public.planning_blocks SET sort_key = '0V' WHERE id IN ('7fbe0000-0000-0000-0000-0000000000d2', '7fbe0000-0000-0000-0000-0000000000a2');
  IF (pg_temp.computed('7fbe0000-0000-0000-0000-0000000000c1') ->> 'target_date')::date IS DISTINCT FROM current_date + 30
     OR pg_temp.computed('7fbe0000-0000-0000-0000-0000000000f1') ->> 'checklist_block_id' IS DISTINCT FROM '7fbe0000-0000-0000-0000-0000000000a1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: reordering moved a pinned countdown or progress';
  END IF;
  -- The poll gets a date and is locked: the countdown counts to it.
  PERFORM pg_temp.as_user('7fba0000-0000-0000-0000-0000000000a1');
  PERFORM public.save_planning_rich_item(v_opt, '7fbe0000-0000-0000-0000-0000000000e1', NULL,
    jsonb_build_object('date_start', (current_date + 60)::text), NULL);
  -- Both say yes, then it can be locked.
  PERFORM public.vote_planning_poll(v_opt, true);
  PERFORM pg_temp.as_user('7fba0000-0000-0000-0000-0000000000b2');
  PERFORM public.vote_planning_poll(v_opt, true);
  PERFORM public.lock_planning_poll('7fbe0000-0000-0000-0000-0000000000e1', v_opt);
  IF (pg_temp.computed('7fbe0000-0000-0000-0000-0000000000e2') ->> 'target_date')::date IS DISTINCT FROM current_date + 60 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the trip''s countdown missed its locked date %', pg_temp.computed('7fbe0000-0000-0000-0000-0000000000e2');
  END IF;
  IF public.planning_v2_pin_block_links() <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second run should pin only the trip''s countdown, now it has a date';
  END IF;
  IF public.planning_v2_pin_block_links() <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: pinning is not idempotent'; END IF;
END $$;

ROLLBACK;
