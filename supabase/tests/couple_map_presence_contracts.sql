-- supabase/tests/couple_map_presence_contracts.sql
-- Couple Map presence contracts (spec 2026-10-16 §4–§5.1). Every check RAISEs.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users(id) VALUES
  ('7a000000-0000-0000-0000-0000000000a1'), ('7a000000-0000-0000-0000-0000000000b2'),
  ('7a000000-0000-0000-0000-0000000000c3') ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('7a000000-0000-0000-0000-0000000000a1', '+15550007001', 'Ama'),
  ('7a000000-0000-0000-0000-0000000000b2', '+15550007002', 'Kofi'),
  ('7a000000-0000-0000-0000-0000000000c3', '+15550007003', 'Stranger') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships(id, user_a, user_b, status) VALUES
  ('7a100000-0000-0000-0000-000000000001', '7a000000-0000-0000-0000-0000000000a1',
   '7a000000-0000-0000-0000-0000000000b2', 'active') ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- C1. Raw coordinates are gone; cells, a relationship key and pause exist.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'partner_presence'
             AND column_name IN ('latitude', 'longitude')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: raw coordinates are still stored';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns WHERE table_name = 'partner_presence'
      AND column_name IN ('cell_lat', 'cell_lng', 'relationship_id', 'paused_until')) <> 4 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: presence_v2 columns missing';
  END IF;
END $$;

-- C2. Snapping is deterministic and lands on a cell centre.
DO $$
DECLARE a record; b record;
BEGIN
  SELECT * INTO a FROM public.presence_snap_cell(5.5603, -0.2057);
  SELECT * INTO b FROM public.presence_snap_cell(5.5609, -0.2051);
  IF a.cell_lat <> 5.565 OR a.cell_lat <> b.cell_lat OR a.cell_lng <> b.cell_lng THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: snapping not deterministic (% % / % %)', a.cell_lat, a.cell_lng, b.cell_lat, b.cell_lng;
  END IF;
  -- The poles never overflow the coordinate system.
  SELECT * INTO a FROM public.presence_snap_cell(90, 180);
  IF a.cell_lat > 90 OR a.cell_lng > 180 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pole snapped outside range (% %)', a.cell_lat, a.cell_lng;
  END IF;
END $$;

-- C3. Hysteresis: jitter across a boundary keeps the stored cell; a real move changes it.
DO $$
DECLARE c record; moved record;
BEGIN
  -- (5.565, -0.208) is Accra's real cell centre; 5.5599 is ~11 m over its southern edge.
  SELECT * INTO c FROM public.presence_next_cell(5.565, -0.208, 5.5599, -0.2080);
  IF c.cell_lat <> 5.565 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 20 m of jitter flipped the cell to %', c.cell_lat;
  END IF;
  SELECT * INTO moved FROM public.presence_next_cell(5.565, -0.208, 5.5450, -0.2080);
  IF moved.cell_lat = 5.565 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 2 km move kept the old cell';
  END IF;
END $$;

-- C4. Opt-in is explicit: record does nothing without start; start then record shows my cell.
DO $$
DECLARE v_rows int; v_self record;
BEGIN
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', 5.5603, -0.2057, 50, 'Accra', 'Ghana', 'GH', 'Africa/Accra');
  SELECT count(*) INTO v_rows FROM public.partner_presence;
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: sampling created sharing without opt-in'; END IF;
  PERFORM public.start_presence('7a100000-0000-0000-0000-000000000001');
  PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', 5.5603, -0.2057, 50, 'Accra', 'Ghana', 'GH', 'Africa/Accra');
  SELECT * INTO v_self FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'self';
  IF v_self.cell_lat <> 5.565 OR v_self.city <> 'Accra' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: own area missing %', v_self; END IF;
END $$;

-- C5. Symmetry: no partner row until both share; then a rounded distance.
DO $$
DECLARE v_rows int; v_p record;
BEGIN
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a partner who never shared appeared'; END IF;
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000b2');
  PERFORM public.start_presence('7a100000-0000-0000-0000-000000000001');
  PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', 51.5074, -0.1278, 30, 'London', 'United Kingdom', 'GB', 'Europe/London');
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT * INTO v_p FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_p.city <> 'London' OR v_p.distance_km NOT BETWEEN 5000 AND 5200 OR v_p.distance_km % 10 <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: partner row/rounding wrong %', v_p;
  END IF;
END $$;

-- C6. No partner timestamp ever leaves the server; my_paused_until is self-only.
DO $$
DECLARE v_p record;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.routines r
             JOIN information_schema.parameters p ON p.specific_name = r.specific_name
             WHERE r.routine_name = 'couple_map_presence' AND p.parameter_mode = 'OUT'
               AND p.parameter_name IN ('updated_at', 'partner_updated_at', 'self_updated_at')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a timestamp column leaves the server';
  END IF;
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT * INTO v_p FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_p.my_paused_until IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: partner pause time leaked'; END IF;
END $$;

-- C7. Pause is symmetric and indistinguishable from stale; resume needs a fresh sample.
DO $$
DECLARE v_rows int;
BEGIN
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000b2');
  PERFORM public.set_presence_pause('7a100000-0000-0000-0000-000000000001', now() + interval '1 hour');
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a paused partner was visible'; END IF;
  -- Symmetric: Kofi, while paused, doesn't see Ama either.
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the pausing partner could still watch'; END IF;
  -- Resume with no new sample: still nothing (the cell was cleared by pause).
  PERFORM public.set_presence_pause('7a100000-0000-0000-0000-000000000001', NULL);
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: resume showed the pre-pause area'; END IF;
  -- A fresh sample brings it back.
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000b2');
  PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', 51.5074, -0.1278, 30, 'London', 'United Kingdom', 'GB', 'Europe/London');
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_rows <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh sample after resume did not show'; END IF;
END $$;

-- C7b. Defence in depth: a paused row that still holds a cell (race, legacy) still can't watch.
DO $$
DECLARE v_rows int;
BEGIN
  UPDATE public.partner_presence SET paused_until = now() + interval '1 hour'
  WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a paused partner with a stored cell could watch'; END IF;
  UPDATE public.partner_presence SET paused_until = NULL
  WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
END $$;

-- C8. Freshness: fading after 4 h, gone after 8 h; a too-long pause is clamped to 8 h
-- (a device clock a little ahead must not make "8 hours" fail).
DO $$
DECLARE v_p record; v_rows int;
BEGIN
  UPDATE public.partner_presence SET updated_at = now() - interval '5 hours'
  WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT * INTO v_p FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_p.freshness <> 'fading' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: 5 h old should be fading, got %', v_p.freshness; END IF;
  UPDATE public.partner_presence SET updated_at = now() - interval '9 hours'
  WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a 9 h old area was shown'; END IF;
  UPDATE public.partner_presence SET updated_at = now() - interval '2 minutes'
  WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000b2');
  SELECT cell_lat, cell_lng, city INTO v_p FROM public.partner_presence
  WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
  PERFORM public.set_presence_pause('7a100000-0000-0000-0000-000000000001', now() + interval '8 hours 2 seconds');
  IF (SELECT paused_until FROM public.partner_presence WHERE user_id = '7a000000-0000-0000-0000-0000000000b2')
     <> now() + interval '8 hours' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an 8 h pause from a clock 2 s ahead was not clamped to 8 h';
  END IF;
  -- Restore Kofi for the tests below.
  UPDATE public.partner_presence SET paused_until = NULL, cell_lat = v_p.cell_lat, cell_lng = v_p.cell_lng, city = v_p.city
  WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
END $$;

-- C9. Bad input: an unknown zone is stored NULL; coordinates out of range are refused.
-- Low accuracy: a fix consistent with the stored area keeps it (no blinking pin);
-- one that isn't keeps the city only.
DO $$
DECLARE v_self record; v_before record;
BEGIN
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT cell_lat, cell_lng INTO v_before FROM public.partner_presence
  WHERE user_id = '7a000000-0000-0000-0000-0000000000a1';
  IF v_before.cell_lat IS NULL THEN RAISE EXCEPTION 'C9 setup: Ama should have an area'; END IF;
  UPDATE public.partner_presence SET updated_at = now() - interval '2 minutes'
  WHERE user_id = '7a000000-0000-0000-0000-0000000000a1';
  PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', v_before.cell_lat + 0.01, v_before.cell_lng, 3000, 'Accra', 'Ghana', 'GH', 'Africa/Accra');
  SELECT * INTO v_self FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'self';
  IF v_self.cell_lat IS DISTINCT FROM v_before.cell_lat OR v_self.cell_lng IS DISTINCT FROM v_before.cell_lng THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an imprecise fix consistent with the stored area erased it %', v_self;
  END IF;
  UPDATE public.partner_presence SET updated_at = now() - interval '2 minutes'
  WHERE user_id = '7a000000-0000-0000-0000-0000000000a1';
  PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', 6.69, -1.62, 5000, 'Accra', 'Ghana', 'GH', 'BST');
  SELECT * INTO v_self FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'self';
  IF v_self.cell_lat IS NOT NULL OR v_self.city <> 'Accra' OR v_self.utc_offset_minutes IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 5 km accuracy or a bad zone was stored as precise %', v_self;
  END IF;
  BEGIN
    PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', 999, 0, 10, NULL, NULL, NULL, NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: latitude 999 accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'CONTRACT VIOLATED%' THEN RAISE; END IF;
  END;
END $$;

-- C10. Rate limit, outsiders and anon.
DO $$
DECLARE v_before numeric; v_after numeric; v_rows int;
BEGIN
  -- now() is fixed within the test transaction: make the stored update 10 s old.
  UPDATE public.partner_presence SET updated_at = now() - interval '10 seconds'
  WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000b2');
  SELECT cell_lat INTO v_before FROM public.partner_presence WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
  PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', 48.8566, 2.3522, 20, 'Paris', 'France', 'FR', 'Europe/Paris');
  SELECT cell_lat INTO v_after FROM public.partner_presence WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
  IF v_after IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a second record within 60 s was applied'; END IF;
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000c3');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001');
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider read the couple'; END IF;
  IF has_function_privilege('anon', 'public.couple_map_presence(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon may read presence';
  END IF;
END $$;

-- C11. Closing the relationship purges both rows; a pause of the relationship does too.
DO $$
DECLARE v_rows int;
BEGIN
  UPDATE public.relationships SET chat_archived_at = now() WHERE id = '7a100000-0000-0000-0000-000000000001';
  SELECT count(*) INTO v_rows FROM public.partner_presence WHERE relationship_id = '7a100000-0000-0000-0000-000000000001';
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: archiving left % presence rows', v_rows; END IF;
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001');
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an archived couple still reads presence'; END IF;
END $$;

-- C12. Retention: rows untouched for more than 7 days go; fresh ones stay.
DO $$
DECLARE v_rows int;
BEGIN
  INSERT INTO public.relationships(id, user_a, user_b, status) VALUES
    ('7a100000-0000-0000-0000-000000000002', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000c3', 'active');
  INSERT INTO public.partner_presence(user_id, relationship_id, updated_at) VALUES
    ('7a000000-0000-0000-0000-0000000000a1', '7a100000-0000-0000-0000-000000000002', now() - interval '8 days'),
    ('7a000000-0000-0000-0000-0000000000c3', '7a100000-0000-0000-0000-000000000002', now());
  PERFORM public.presence_purge_stale();
  SELECT count(*) INTO v_rows FROM public.partner_presence WHERE relationship_id = '7a100000-0000-0000-0000-000000000002';
  IF v_rows <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: retention kept % rows', v_rows; END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'presence_purge_stale') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: retention job not scheduled';
  END IF;
END $$;

-- C13. The old distance function is retired; the flag ships off; no direct writes.
DO $$
BEGIN
  IF to_regprocedure('public.partner_distance(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: partner_distance still exists';
  END IF;
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'couple_map_enabled') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: couple_map_enabled must exist and be off';
  END IF;
  IF has_table_privilege('authenticated', 'public.partner_presence', 'INSERT')
     OR has_table_privilege('authenticated', 'public.partner_presence', 'UPDATE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients can write presence directly';
  END IF;
END $$;

-- C14. Time zones: IANA names only, checked without scanning pg_timezone_names.
DO $$
BEGIN
  IF NOT public.presence_tz_ok('Africa/Accra') OR NOT public.presence_tz_ok('UTC')
     OR NOT public.presence_tz_ok('America/Argentina/Buenos_Aires') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a real IANA zone was refused';
  END IF;
  IF public.presence_tz_ok('BST') OR public.presence_tz_ok('UTC+3') OR public.presence_tz_ok('Not/AZone')
     OR public.presence_tz_ok(NULL) OR public.presence_tz_ok('') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an abbreviation, POSIX string or unknown zone was accepted';
  END IF;
  -- Single-token legacy zones are refused on purpose (phones report Area/Location).
  IF public.presence_tz_ok('Japan') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a legacy single-token zone was accepted';
  END IF;
  IF position('pg_timezone_names' IN pg_get_functiondef('public.record_presence(uuid,double precision,double precision,double precision,text,text,text,text)'::regprocedure)) > 0
     OR position('pg_timezone_names' IN pg_get_functiondef('public.presence_offset_minutes(text)'::regprocedure)) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: presence still scans pg_timezone_names';
  END IF;
END $$;

ROLLBACK;
