-- Per-plan "new from your partner" (2026-10-18): a plan is new to someone
-- when their partner made its latest change after they last opened it.
-- Opening a plan (get_planning_entry) marks it seen. The category dot means
-- "a plan in here is new to you"; a plan put away never lights it.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users (id) VALUES
  ('7f5a0000-0000-0000-0000-0000000000a1'), ('7f5a0000-0000-0000-0000-0000000000b2'),
  ('7f5a0000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7f5a0000-0000-0000-0000-0000000000a1', '+233279900001', 'Ama'),
  ('7f5a0000-0000-0000-0000-0000000000b2', '+233279900002', 'Kofi'),
  ('7f5a0000-0000-0000-0000-0000000000c3', '+233279900003', 'Stranger')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('7f5b0000-0000-0000-0000-000000000001', '7f5a0000-0000-0000-0000-0000000000a1',
   '7f5a0000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
-- has_new of a plan in Recent, as the current user.
CREATE FUNCTION pg_temp.recent_new(p_title text) RETURNS boolean LANGUAGE sql AS $$
  SELECT (x->>'has_new')::boolean
  FROM jsonb_array_elements(public.list_planning_recent('7f5b0000-0000-0000-0000-000000000001', NULL, NULL, 50)->'entries') x
  WHERE x->>'title' = p_title $$;
-- has_new of a plan in its category's open list (pinned or not).
CREATE FUNCTION pg_temp.list_new(p_title text) RETURNS boolean LANGUAGE sql AS $$
  SELECT (x->>'has_new')::boolean
  FROM (SELECT public.list_planning_entries('7f5c0000-0000-0000-0000-000000000001', 'open', NULL, NULL, 50) AS v) l,
       jsonb_array_elements((l.v->'entries') || coalesce(l.v->'pinned', '[]'::jsonb)) x
  WHERE x->>'title' = p_title $$;
-- The Trips category's dot on the home screen.
CREATE FUNCTION pg_temp.home_new() RETURNS boolean LANGUAGE sql AS $$
  SELECT (c->>'has_new')::boolean
  FROM jsonb_array_elements(public.get_planning_home('7f5b0000-0000-0000-0000-000000000001')->'categories') c
  WHERE c->>'id' = '7f5c0000-0000-0000-0000-000000000001' $$;

-- Kofi starts two trips; Ama hasn't opened either.
DO $$
DECLARE
  v_rel uuid := '7f5b0000-0000-0000-0000-000000000001';
BEGIN
  PERFORM pg_temp.as_user('7f5a0000-0000-0000-0000-0000000000a1');
  PERFORM public.create_planning_category('7f5c0000-0000-0000-0000-000000000001', v_rel, 'Trips',
    (public.planning_v2_icons())[1], (public.planning_v2_colors())[1]);
  PERFORM pg_temp.as_user('7f5a0000-0000-0000-0000-0000000000b2');
  PERFORM public.create_planning_entry('7f5d0000-0000-0000-0000-000000000001',
    '7f5c0000-0000-0000-0000-000000000001', 'Lisbon', false, 'GHS');
  PERFORM public.create_planning_entry('7f5d0000-0000-0000-0000-000000000002',
    '7f5c0000-0000-0000-0000-000000000001', 'Accra', false, 'GHS');
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 1. New to Ama everywhere it shows; never new to Kofi, who made it.
DO $$
BEGIN
  PERFORM pg_temp.as_user('7f5a0000-0000-0000-0000-0000000000a1');
  IF pg_temp.recent_new('Lisbon') IS NOT TRUE THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Recent does not mark Kofi''s plan new for Ama'; END IF;
  IF pg_temp.list_new('Lisbon') IS NOT TRUE THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the category list does not mark it new'; END IF;
  IF pg_temp.home_new() IS NOT TRUE THEN RAISE EXCEPTION 'CONTRACT VIOLATED: no category dot for Ama'; END IF;
  PERFORM pg_temp.as_user('7f5a0000-0000-0000-0000-0000000000b2');
  IF pg_temp.recent_new('Lisbon') IS NOT FALSE OR pg_temp.list_new('Lisbon') IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Kofi''s own plan is new to him';
  END IF;
  IF pg_temp.home_new() IS NOT FALSE THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Kofi gets a dot for his own plans'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 2. Opening one plan clears that plan only; the category keeps its dot
--    while the other is still unopened, and loses it once both are.
DO $$
BEGIN
  PERFORM pg_temp.as_user('7f5a0000-0000-0000-0000-0000000000a1');
  PERFORM public.get_planning_entry('7f5d0000-0000-0000-0000-000000000001');
  IF pg_temp.recent_new('Lisbon') IS NOT FALSE OR pg_temp.list_new('Lisbon') IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an opened plan is still new';
  END IF;
  IF pg_temp.recent_new('Accra') IS NOT TRUE THEN RAISE EXCEPTION 'CONTRACT VIOLATED: opening one plan cleared another'; END IF;
  IF pg_temp.home_new() IS NOT TRUE THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the dot went while a plan is still unopened'; END IF;
  PERFORM public.get_planning_entry('7f5d0000-0000-0000-0000-000000000002');
  IF pg_temp.home_new() IS NOT FALSE THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the dot stayed after every plan was opened'; END IF;
  -- Opening the category itself no longer clears anything: the plan does.
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 3. A later change by Kofi makes it new again; Ama's own change does not
--    make it new to her, and does make it new to Kofi.
DO $$
DECLARE v_block uuid := gen_random_uuid();
BEGIN
  PERFORM pg_temp.as_user('7f5a0000-0000-0000-0000-0000000000b2');
  PERFORM public.update_planning_entry('7f5d0000-0000-0000-0000-000000000001', 'Lisbon in May', 'active');
  PERFORM pg_temp.as_user('7f5a0000-0000-0000-0000-0000000000a1');
  IF pg_temp.recent_new('Lisbon in May') IS NOT TRUE THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh change by Kofi is not new'; END IF;
  PERFORM public.get_planning_entry('7f5d0000-0000-0000-0000-000000000001');
  PERFORM public.update_planning_entry('7f5d0000-0000-0000-0000-000000000001', 'Lisbon in June', 'active');
  IF pg_temp.recent_new('Lisbon in June') IS NOT FALSE THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Ama''s own change is new to her'; END IF;
  PERFORM pg_temp.as_user('7f5a0000-0000-0000-0000-0000000000b2');
  IF pg_temp.recent_new('Lisbon in June') IS NOT TRUE THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Ama''s change is not new to Kofi'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 4. Put away gently: a plan put away never lights the category dot.
DO $$
BEGIN
  PERFORM pg_temp.as_user('7f5a0000-0000-0000-0000-0000000000b2');
  PERFORM public.update_planning_entry('7f5d0000-0000-0000-0000-000000000002', 'Accra again', 'active');
  PERFORM public.put_planning_entry_away('7f5d0000-0000-0000-0000-000000000002');
  PERFORM pg_temp.as_user('7f5a0000-0000-0000-0000-0000000000a1');
  -- Lisbon was last changed by Ama, so only the put-away plan could light it.
  IF pg_temp.home_new() IS NOT FALSE THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a plan put away lit the dot'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 5. An outsider can't open the plan, and leaves no seen mark trying.
DO $$
BEGIN
  PERFORM pg_temp.as_user('7f5a0000-0000-0000-0000-0000000000c3');
  BEGIN
    PERFORM public.get_planning_entry('7f5d0000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider opened the plan';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'CONTRACT VIOLATED%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
  IF EXISTS (SELECT 1 FROM public.planning_entry_seen WHERE user_id = '7f5a0000-0000-0000-0000-0000000000c3') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider left a seen mark';
  END IF;
END $$;

-- 6. Nobody reads or writes the seen marks directly.
DO $$
BEGIN
  IF has_table_privilege('authenticated', 'public.planning_entry_seen', 'SELECT')
     OR has_table_privilege('authenticated', 'public.planning_entry_seen', 'INSERT')
     OR has_table_privilege('anon', 'public.planning_entry_seen', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: planning_entry_seen is directly accessible';
  END IF;
END $$;

ROLLBACK;
