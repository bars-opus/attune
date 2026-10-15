-- Planning "Recent" contracts (2026-10-15): the couple's latest plans across
-- every category, newest activity first, paged; never another couple's,
-- never templates, deleted plans or hidden categories.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users (id) VALUES
  ('7f100000-0000-0000-0000-0000000000a1'), ('7f100000-0000-0000-0000-0000000000b2'),
  ('7f100000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7f100000-0000-0000-0000-0000000000a1', '+233270000001', 'Ama'),
  ('7f100000-0000-0000-0000-0000000000b2', '+233270000002', 'Kofi'),
  ('7f100000-0000-0000-0000-0000000000c3', '+233270000003', 'Stranger')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('7f200000-0000-0000-0000-000000000001', '7f100000-0000-0000-0000-0000000000a1',
   '7f100000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.titles(p jsonb) RETURNS text[] LANGUAGE sql AS $$
  SELECT coalesce(array_agg(x->>'title' ORDER BY n), '{}')
  FROM jsonb_array_elements(p->'entries') WITH ORDINALITY AS t(x, n) $$;

-- Two categories (one hidden later), plans by both partners, a template
-- and a deleted plan; activity spread over the last days.
DO $$
DECLARE
  v_rel uuid := '7f200000-0000-0000-0000-000000000001';
  v_icon text := (public.planning_v2_icons())[1];
  v_color text := (public.planning_v2_colors())[1];
  v_trips uuid := '7f300000-0000-0000-0000-000000000001';
  v_home uuid := '7f300000-0000-0000-0000-000000000002';
  v_hidden uuid := '7f300000-0000-0000-0000-000000000003';
BEGIN
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000a1');
  PERFORM public.create_planning_category(v_trips, v_rel, 'Trips', v_icon, v_color);
  PERFORM public.create_planning_category(v_home, v_rel, 'Home', v_icon, v_color);
  PERFORM public.create_planning_category(v_hidden, v_rel, 'Secret', v_icon, v_color);
  PERFORM public.create_planning_entry('7f400000-0000-0000-0000-000000000001', v_trips, 'Lisbon', false, 'GHS');
  PERFORM public.create_planning_entry('7f400000-0000-0000-0000-000000000003', v_trips, 'Old trip', false, 'GHS');
  PERFORM public.create_planning_entry('7f400000-0000-0000-0000-000000000005', v_trips, 'Deleted', false, 'GHS');
  PERFORM public.create_planning_entry('7f400000-0000-0000-0000-000000000006', v_hidden, 'In hidden', false, 'GHS');
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  PERFORM public.create_planning_entry('7f400000-0000-0000-0000-000000000002', v_home, 'Paint the hall', false, 'GHS');
  PERFORM public.create_planning_entry('7f400000-0000-0000-0000-000000000004', v_home, 'Boiler', false, 'GHS');
  PERFORM set_config('request.jwt.claims', '', true);

  UPDATE public.planning_entries SET last_activity_at = now() - interval '1 hour' WHERE id = '7f400000-0000-0000-0000-000000000001';
  UPDATE public.planning_entries SET last_activity_at = now() - interval '2 hours' WHERE id = '7f400000-0000-0000-0000-000000000002';
  UPDATE public.planning_entries SET last_activity_at = now() - interval '3 days', status = 'done' WHERE id = '7f400000-0000-0000-0000-000000000003';
  UPDATE public.planning_entries SET last_activity_at = now() - interval '4 days' WHERE id = '7f400000-0000-0000-0000-000000000004';
  UPDATE public.planning_entries SET last_activity_at = now(), deleted_at = now() WHERE id = '7f400000-0000-0000-0000-000000000005';
  UPDATE public.planning_entries SET last_activity_at = now() WHERE id = '7f400000-0000-0000-0000-000000000006';
  UPDATE public.planning_categories SET hidden_at = now() WHERE id = v_hidden;
  -- A template is never a plan anyone worked on.
  UPDATE public.planning_entries SET last_activity_at = now() WHERE is_template;
END $$;

-- 1. Newest activity first, across categories and partners; with category.
DO $$
DECLARE v jsonb; v_first jsonb;
BEGIN
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000a1');
  v := public.list_planning_recent('7f200000-0000-0000-0000-000000000001', NULL, NULL, 10);
  IF pg_temp.titles(v) <> ARRAY['Lisbon', 'Paint the hall', 'Old trip', 'Boiler'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recent order/content %', pg_temp.titles(v);
  END IF;
  v_first := v->'entries'->0;
  IF v_first->'category'->>'name' <> 'Trips' OR v_first->'category'->>'id' IS NULL
     OR v_first->'category'->>'icon' IS NULL OR v_first->'category'->>'color' IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recent row lacks its category %', v_first;
  END IF;
  IF v->'next_cursor' <> 'null'::jsonb THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a next page after the last'; END IF;
END $$;

-- 2. Pages of two: no overlap, nothing lost, then no next page.
DO $$
DECLARE v1 jsonb; v2 jsonb;
BEGIN
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  v1 := public.list_planning_recent('7f200000-0000-0000-0000-000000000001', NULL, NULL, 2);
  IF pg_temp.titles(v1) <> ARRAY['Lisbon', 'Paint the hall'] OR v1->'next_cursor' = 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: first page %', v1;
  END IF;
  v2 := public.list_planning_recent('7f200000-0000-0000-0000-000000000001',
    (v1->'next_cursor'->>'at')::timestamptz, (v1->'next_cursor'->>'id')::uuid, 2);
  IF pg_temp.titles(v2) <> ARRAY['Old trip', 'Boiler'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: second page %', pg_temp.titles(v2);
  END IF;
END $$;

-- 3. Not for anyone outside the couple.
DO $$
BEGIN
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000c3');
  BEGIN
    PERFORM public.list_planning_recent('7f200000-0000-0000-0000-000000000001', NULL, NULL, 10);
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider read the couple''s recent plans';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'CONTRACT VIOLATED%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 4. Only signed-in members may call it.
DO $$
BEGIN
  IF has_function_privilege('anon', 'public.list_planning_recent(uuid, timestamptz, uuid, integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon may list recent plans';
  END IF;
END $$;

ROLLBACK;
