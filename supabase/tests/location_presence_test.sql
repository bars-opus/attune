-- Location presence.
--
-- Attune ships a discreet exit as a permanent constraint and runs
-- coercive-control detection on chat. This feature is designed so it
-- cannot become the thing the rest of the app defends against, and these
-- tests pin the properties that guarantee that -- not the UI copy, which
-- will change, but the rules that make the copy safe.

BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-00000000e001'),
  ('00000000-0000-0000-0000-00000000e002'),
  ('00000000-0000-0000-0000-00000000e003') ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-00000000e001', '+15559990101', 'E1'),
  ('00000000-0000-0000-0000-00000000e002', '+15559990102', 'E2'),
  ('00000000-0000-0000-0000-00000000e003', '+15559990103', 'E3')
  ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000e001';
  b uuid := '00000000-0000-0000-0000-00000000e002';
  c uuid := '00000000-0000-0000-0000-00000000e003';
  v_rel uuid;
  v_km double precision;
  v_rows int;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES (a, b, 'active') RETURNING id INTO v_rel;

  INSERT INTO public.partner_presence(user_id, latitude, longitude, city, timezone)
  VALUES (a, 5.560, -0.205, 'Accra', 'Africa/Accra'),
         (b, 51.507, -0.128, 'London', 'Europe/London');

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);

  SELECT distance_km INTO v_km FROM public.partner_distance(v_rel);
  IF v_km IS NULL OR v_km < 5000 OR v_km > 5200 THEN
    RAISE EXCEPTION 'Accra to London should be ~5100km, got %', v_km;
  END IF;

  -- SYMMETRY. Without this a partner could watch the distance while
  -- withholding their own position -- exactly the asymmetry the feature
  -- exists to avoid.
  UPDATE public.partner_presence SET latitude = NULL, longitude = NULL
  WHERE user_id = a;

  SELECT count(*) INTO v_rows FROM public.partner_distance(v_rel);
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'distance was returned to someone not sharing their own';
  END IF;

  UPDATE public.partner_presence SET latitude = 5.560, longitude = -0.205
  WHERE user_id = a;

  -- STALENESS. A day-old position is a guess, and a confident wrong
  -- number is worse than none.
  UPDATE public.partner_presence SET updated_at = now() - interval '30 hours'
  WHERE user_id = b;

  SELECT count(*) INTO v_rows FROM public.partner_distance(v_rel);
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'a stale position was presented as current';
  END IF;

  UPDATE public.partner_presence SET updated_at = now() WHERE user_id = b;

  -- MEMBERSHIP. Otherwise any authenticated user could pass a
  -- relationship id and learn how far apart that couple is.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', c, 'role', 'authenticated')::text, true);

  SELECT count(*) INTO v_rows FROM public.partner_distance(v_rel);
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'a non-member read a couple''s distance';
  END IF;
END $$;

-- THE CENTRAL GUARANTEE: the function hands back a distance, never a
-- position. If coordinates ever appear in its signature, the ambient row
-- has become a location channel and the whole design is void.
DO $$
DECLARE
  v_cols text;
BEGIN
  SELECT string_agg(p.proargnames[i], ', ') INTO v_cols
  FROM pg_proc p,
       generate_subscripts(p.proargnames, 1) i
  WHERE p.proname = 'partner_distance'
    AND p.pronamespace = 'public'::regnamespace
    AND p.proargnames[i] IN ('latitude', 'longitude',
                             'partner_latitude', 'partner_longitude');

  IF v_cols IS NOT NULL THEN
    RAISE EXCEPTION 'partner_distance returns coordinates: %', v_cols;
  END IF;
END $$;

-- A partner cannot read the presence row directly either: RLS is
-- self-only, so the function is the single path between the two rows.
DO $$
DECLARE
  v_using text;
BEGIN
  SELECT pg_get_expr(polqual, polrelid) INTO v_using
  FROM pg_policy
  WHERE polrelid = 'public.partner_presence'::regclass
    AND polname = 'partner_presence_self';

  IF v_using IS NULL OR v_using NOT LIKE '%auth.uid()%' THEN
    RAISE EXCEPTION 'presence rows must be readable only by their owner';
  END IF;
END $$;

ROLLBACK;
