-- Table columns can carry a hint (2026-10-18): a short example shown in an
-- empty field. The templates' tables get theirs, the Wishlist's "Where"
-- becomes "Where to buy", and tables still exactly as a template made them
-- are given the same, once. Any other table is left alone.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users (id) VALUES ('7fca0000-0000-0000-0000-0000000000a1'), ('7fca0000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7fca0000-0000-0000-0000-0000000000a1', '+233279970001', 'Ama'),
  ('7fca0000-0000-0000-0000-0000000000b2', '+233279970002', 'Kofi')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('7fcb0000-0000-0000-0000-000000000001', '7fca0000-0000-0000-0000-0000000000a1',
   '7fca0000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.cols(p uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT payload -> 'columns' FROM public.planning_blocks WHERE id = p $$;

DO $$
DECLARE v_e uuid := '7fcd0000-0000-0000-0000-000000000001';
BEGIN
  PERFORM pg_temp.as_user('7fca0000-0000-0000-0000-0000000000a1');
  PERFORM public.create_planning_category('7fcc0000-0000-0000-0000-000000000001', '7fcb0000-0000-0000-0000-000000000001',
    'Wishes', (public.planning_v2_icons())[1], (public.planning_v2_colors())[1]);
  PERFORM public.create_planning_entry(v_e, '7fcc0000-0000-0000-0000-000000000001', 'Things', false, 'GHS');
  -- Exactly as the old Wishlist template made it.
  PERFORM public.add_planning_block('7fce0000-0000-0000-0000-000000000001', v_e, 'table',
    '{"title":"Wishlist","columns":[{"key":"c0","label":"Item","type":"text"},{"key":"c1","label":"Price","type":"money"},{"key":"c2","label":"Where","type":"text"},{"key":"c3","label":"Got it","type":"check"}]}',
    NULL, NULL, NULL);
  -- A Wishlist the couple reshaped: left alone.
  PERFORM public.add_planning_block('7fce0000-0000-0000-0000-000000000002', v_e, 'table',
    '{"title":"Wishlist","columns":[{"key":"c0","label":"Item","type":"text"},{"key":"c2","label":"Where","type":"text"}]}',
    NULL, NULL, NULL);
END $$;

-- 1. A column may carry a short hint; nothing too long, nothing but text.
DO $$
BEGIN
  PERFORM pg_temp.as_user('7fca0000-0000-0000-0000-0000000000a1');
  PERFORM public.add_planning_block(gen_random_uuid(), '7fcd0000-0000-0000-0000-000000000001', 'table',
    '{"columns":[{"key":"c0","label":"Chore","type":"text","hint":"Take out the bins"}]}', NULL, NULL, NULL);
  BEGIN
    PERFORM public.add_planning_block(gen_random_uuid(), '7fcd0000-0000-0000-0000-000000000001', 'table',
      jsonb_build_object('columns', jsonb_build_array(jsonb_build_object('key','c0','label','Chore','type','text','hint', repeat('x', 61)))),
      NULL, NULL, NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 61-character hint accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.add_planning_block(gen_random_uuid(), '7fcd0000-0000-0000-0000-000000000001', 'table',
      '{"columns":[{"key":"c0","label":"Chore","type":"text","hint":5}]}', NULL, NULL, NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a number accepted as a hint';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
END $$;

-- 2. The templates carry their hints, and the Wishlist says where to buy.
DO $$
DECLARE v jsonb;
BEGIN
  SELECT b -> 'payload' -> 'columns' INTO v FROM public.planning_starter_templates, jsonb_array_elements(blocks) b
  WHERE seed_key = 'wishlist' AND b ->> 'type' = 'table';
  IF v -> 2 <> '{"key":"c2","label":"Where to buy","type":"text","hint":"Shop or website"}'::jsonb
     OR v -> 0 ->> 'hint' IS DISTINCT FROM 'Headphones' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Wishlist template %', v;
  END IF;
  SELECT b -> 'payload' -> 'columns' INTO v FROM public.planning_starter_templates, jsonb_array_elements(blocks) b
  WHERE seed_key = 'trips' AND b ->> 'type' = 'table';
  IF v -> 0 ->> 'hint' IS DISTINCT FROM 'Mon' OR v -> 2 ->> 'hint' IS DISTINCT FROM 'Old town' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Itinerary template %', v;
  END IF;
  SELECT b -> 'payload' -> 'columns' INTO v FROM public.planning_gallery_templates, jsonb_array_elements(blocks) b
  WHERE key = 'moving_house' AND b ->> 'type' = 'table';
  IF v -> 0 ->> 'hint' IS DISTINCT FROM 'Kitchen' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Rooms template %', v; END IF;
END $$;

-- 3. Existing tables exactly as a template made them get the same, once;
--    a reshaped one is left alone; their rows are untouched.
DO $$
DECLARE v jsonb;
BEGIN
  IF public.planning_v2_hint_template_tables() < 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: nothing hinted'; END IF;
  v := pg_temp.cols('7fce0000-0000-0000-0000-000000000001');
  IF v -> 2 ->> 'label' IS DISTINCT FROM 'Where to buy' OR v -> 2 ->> 'hint' IS DISTINCT FROM 'Shop or website' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the old Wishlist table %', v;
  END IF;
  IF pg_temp.cols('7fce0000-0000-0000-0000-000000000002') -> 1 ->> 'label' <> 'Where'
     OR pg_temp.cols('7fce0000-0000-0000-0000-000000000002') -> 1 ? 'hint' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reshaped table was changed';
  END IF;
  IF public.planning_v2_hint_template_tables() <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: hinting is not once-only'; END IF;
END $$;

ROLLBACK;
