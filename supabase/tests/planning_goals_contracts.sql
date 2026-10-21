-- Goals (2026-10-18). A progress bar follows a date (computed
-- date_block_id / target_date, and started_on for its pace); a plan whose
-- only Date block arrives links its countdown and progress to it; the Goals
-- template has a countdown, and a new goal's countdown and progress follow
-- its own Target date.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users (id) VALUES ('7fda0000-0000-0000-0000-0000000000a1'), ('7fda0000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7fda0000-0000-0000-0000-0000000000a1', '+233279980001', 'Ama'),
  ('7fda0000-0000-0000-0000-0000000000b2', '+233279980002', 'Kofi')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('7fdb0000-0000-0000-0000-000000000001', '7fda0000-0000-0000-0000-0000000000a1',
   '7fda0000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.computed(p uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.planning_v2_block_computed(b) FROM public.planning_blocks b WHERE b.id = p $$;
CREATE FUNCTION pg_temp.link(p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT payload ->> 'date_block_id' FROM public.planning_blocks WHERE id = p $$;

-- 1. The Goals template: progress, Target date, a countdown, why, steps;
--    in the template itself, progress and countdown follow Target date.
DO $$
DECLARE v_types text[];
BEGIN
  SELECT array_agg(b ->> 'type' ORDER BY n) INTO v_types
  FROM public.planning_starter_templates, jsonb_array_elements(blocks) WITH ORDINALITY AS t(b, n)
  WHERE seed_key = 'goals';
  IF v_types <> ARRAY['progress', 'date', 'countdown', 'text', 'checklist'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Goals template %', v_types;
  END IF;
END $$;

-- 2. A new goal from the template: its countdown and progress follow its
--    own Target date, which then drives the pace.
DO $$
DECLARE v_cat uuid; v_goal jsonb; v_date uuid; v_cd uuid; v_pr uuid; v jsonb;
BEGIN
  PERFORM pg_temp.as_user('7fda0000-0000-0000-0000-0000000000a1');
  PERFORM public.get_planning_home('7fdb0000-0000-0000-0000-000000000001');
  SELECT id INTO v_cat FROM public.planning_categories
  WHERE relationship_id = '7fdb0000-0000-0000-0000-000000000001' AND seed_key = 'goals';
  v_goal := public.create_planning_entry('7fdd0000-0000-0000-0000-000000000001', v_cat, 'Save for a car', true, 'GHS');
  SELECT id INTO v_date FROM public.planning_blocks WHERE entry_id = '7fdd0000-0000-0000-0000-000000000001' AND block_type = 'date';
  SELECT id INTO v_cd FROM public.planning_blocks WHERE entry_id = '7fdd0000-0000-0000-0000-000000000001' AND block_type = 'countdown';
  SELECT id INTO v_pr FROM public.planning_blocks WHERE entry_id = '7fdd0000-0000-0000-0000-000000000001' AND block_type = 'progress';
  IF v_cd IS NULL OR pg_temp.link(v_cd) IS DISTINCT FROM v_date::text OR pg_temp.link(v_pr) IS DISTINCT FROM v_date::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the new goal''s countdown/progress do not follow its Target date (% % %)',
      v_date, pg_temp.link(v_cd), pg_temp.link(v_pr);
  END IF;
  UPDATE public.planning_blocks SET date_start = current_date + 60 WHERE id = v_date;
  v := pg_temp.computed(v_pr);
  IF (v ->> 'target_date')::date IS DISTINCT FROM current_date + 60
     OR v ->> 'date_block_id' IS DISTINCT FROM v_date::text
     OR (v ->> 'started_on')::date IS DISTINCT FROM current_date THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: progress pace inputs %', v;
  END IF;
  -- Another date added above never pulls them away.
  PERFORM public.add_planning_block(gen_random_uuid(), '7fdd0000-0000-0000-0000-000000000001', 'date',
    '{"title":"Test drive"}', current_date + 5, NULL, NULL);
  IF pg_temp.link(v_cd) IS DISTINCT FROM v_date::text OR pg_temp.link(v_pr) IS DISTINCT FROM v_date::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second date moved the goal''s links';
  END IF;
  IF (pg_temp.computed(v_pr) ->> 'target_date')::date IS DISTINCT FROM current_date + 60 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the pace follows another date %', pg_temp.computed(v_pr);
  END IF;
  -- Its Target date cleared: no due date, never the other date.
  UPDATE public.planning_blocks SET date_start = NULL WHERE id = v_date;
  IF pg_temp.computed(v_pr) ->> 'target_date' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unset Target date borrowed another date %', pg_temp.computed(v_pr);
  END IF;
END $$;

-- 3. A plan's first Date block links the countdown and progress already
--    there; a link may be any date block id, nothing else.
DO $$
DECLARE v_d uuid := gen_random_uuid();
BEGIN
  PERFORM pg_temp.as_user('7fda0000-0000-0000-0000-0000000000a1');
  PERFORM public.create_planning_category('7fdc0000-0000-0000-0000-000000000009', '7fdb0000-0000-0000-0000-000000000001',
    'Plans', (public.planning_v2_icons())[1], (public.planning_v2_colors())[1]);
  PERFORM public.create_planning_entry('7fdd0000-0000-0000-0000-000000000002', '7fdc0000-0000-0000-0000-000000000009', 'Run', false, 'GHS');
  PERFORM public.add_planning_block('7fde0000-0000-0000-0000-000000000001', '7fdd0000-0000-0000-0000-000000000002',
    'progress', '{"mode":"numeric"}', NULL, NULL, NULL);
  PERFORM public.add_planning_block('7fde0000-0000-0000-0000-000000000002', '7fdd0000-0000-0000-0000-000000000002',
    'countdown', '{}', NULL, NULL, NULL);
  IF pg_temp.link('7fde0000-0000-0000-0000-000000000001') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: linked with no date to link to';
  END IF;
  PERFORM public.add_planning_block(v_d, '7fdd0000-0000-0000-0000-000000000002', 'date', '{"title":"Race day"}', NULL, NULL, NULL);
  IF pg_temp.link('7fde0000-0000-0000-0000-000000000001') IS DISTINCT FROM v_d::text
     OR pg_temp.link('7fde0000-0000-0000-0000-000000000002') IS DISTINCT FROM v_d::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first date did not link them';
  END IF;
  BEGIN
    PERFORM public.update_planning_block('7fde0000-0000-0000-0000-000000000001',
      (SELECT version FROM public.planning_blocks WHERE id = '7fde0000-0000-0000-0000-000000000001'),
      '{"mode":"numeric","date_block_id":"soon"}', NULL, NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-uuid date link accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
END $$;

-- 4. "Why this matters to us" is a bold Small line (bodyMedium), not a heading,
--    in the template and, once, in goals still carrying the old heading.
DO $$
DECLARE v_heading jsonb; v_e uuid := '7fdd0000-0000-0000-0000-000000000003'; v_t uuid := gen_random_uuid();
BEGIN
  SELECT b -> 'payload' -> 'delta' INTO v_heading
  FROM public.planning_starter_templates, jsonb_array_elements(blocks) b
  WHERE seed_key = 'goals' AND b ->> 'type' = 'text';
  IF v_heading -> 0 <> '{"insert":"Why this matters to us","attributes":{"bold":true,"size":"small"}}'::jsonb
     OR v_heading -> 1 ? 'attributes' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the template heading %', v_heading;
  END IF;
  -- An older goal with the Heading 2 and its own words under it.
  PERFORM pg_temp.as_user('7fda0000-0000-0000-0000-0000000000a1');
  PERFORM public.create_planning_entry(v_e, (SELECT id FROM public.planning_categories
    WHERE relationship_id = '7fdb0000-0000-0000-0000-000000000001' AND seed_key = 'goals'), 'Old goal', false, 'GHS');
  PERFORM public.add_planning_block(v_t, v_e, 'text',
    '{"delta":[{"insert":"Why this matters to us"},{"insert":"\n","attributes":{"header":2}},{"insert":"Freedom\n"}]}', NULL, NULL, NULL);
  IF public.planning_v2_soften_goal_headings() < 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: nothing softened'; END IF;
  SELECT payload -> 'delta' INTO v_heading FROM public.planning_blocks WHERE id = v_t;
  IF v_heading <> '[{"insert":"Why this matters to us","attributes":{"bold":true,"size":"small"}},{"insert":"\n"},{"insert":"Freedom\n"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the old goal''s heading %', v_heading;
  END IF;
  IF public.planning_v2_soften_goal_headings() <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: not once-only'; END IF;
END $$;

ROLLBACK;
