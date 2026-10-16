-- supabase/migrations/20261016100000_presence_v2.sql
--
-- Couple Map, Phase 0 (spec 2026-10-16 §4–§5.1). Presence becomes
-- relationship-scoped, stored only as a snapped ~1 km cell, written only
-- through RPCs, paused silently and symmetrically, and read through one
-- function that never returns a partner timestamp or anything finer than a
-- cell. Existing rows are dropped: nothing renders them, and users opt in
-- again. partner_distance is retired (the dual clock moves to
-- couple_map_presence).

-- The feature's numbers, in one place (checklist 4.11).
CREATE OR REPLACE FUNCTION public.presence_config(p_key text)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_key
    WHEN 'cell_deg' THEN 0.01
    WHEN 'hysteresis_m' THEN 300
    WHEN 'accuracy_cutoff_m' THEN 2000
    WHEN 'fading_after_h' THEN 4
    WHEN 'stale_after_h' THEN 8
    WHEN 'max_pause_h' THEN 8
    WHEN 'rate_limit_s' THEN 60
    WHEN 'retention_days' THEN 7
  END
$$;

DROP FUNCTION IF EXISTS public.partner_distance(uuid);
DROP TABLE IF EXISTS public.partner_presence;

CREATE TABLE public.partner_presence (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  -- The snapped cell centre, never a raw point. NULL while paused or
  -- when only a city is known (accuracy worse than the cutoff).
  cell_lat numeric(6, 3),
  cell_lng numeric(6, 3),
  city text,
  country text,
  country_code text,
  timezone text,
  paused_until timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, relationship_id),
  CONSTRAINT partner_presence_cell_paired CHECK ((cell_lat IS NULL) = (cell_lng IS NULL)),
  CONSTRAINT partner_presence_cell_range CHECK (
    cell_lat IS NULL OR (cell_lat BETWEEN -90 AND 90 AND cell_lng BETWEEN -180 AND 180)),
  CONSTRAINT partner_presence_text_lengths CHECK (
    (city IS NULL OR char_length(city) <= 120)
    AND (country IS NULL OR char_length(country) <= 120)
    AND (country_code IS NULL OR char_length(country_code) <= 8)
    AND (timezone IS NULL OR char_length(timezone) <= 64))
);
CREATE INDEX partner_presence_relationship_idx ON public.partner_presence (relationship_id);
CREATE INDEX partner_presence_updated_idx ON public.partner_presence (updated_at);

ALTER TABLE public.partner_presence ENABLE ROW LEVEL SECURITY;
CREATE POLICY partner_presence_self ON public.partner_presence
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY partner_presence_self_delete ON public.partner_presence
  FOR DELETE TO authenticated USING (user_id = auth.uid());
REVOKE ALL ON public.partner_presence FROM PUBLIC, anon, authenticated;
GRANT SELECT, DELETE ON public.partner_presence TO authenticated;

-- A deterministic ~1 km grid. The longitude step comes from the snapped
-- latitude BAND, so the index can't drift within a band.
CREATE OR REPLACE FUNCTION public.presence_snap_cell(
  p_lat double precision, p_lng double precision,
  OUT cell_lat numeric, OUT cell_lng numeric)
LANGUAGE sql IMMUTABLE AS $$
  WITH b AS (
    SELECT least(floor(p_lat / 0.01), 8999) AS lat_idx
  ), band AS (
    SELECT lat_idx * 0.01 + 0.005 AS band_lat FROM b
  ), step AS (
    SELECT band_lat, 0.01 / greatest(cos(radians(band_lat)), 0.2) AS lng_step FROM band
  )
  SELECT round(band_lat::numeric, 3),
         round(least(greatest(
           floor((p_lng + 180) / lng_step) * lng_step + lng_step / 2 - 180, -180), 180)::numeric, 3)
  FROM step
$$;

-- The next cell to store: the new one only when the raw point is more than
-- the hysteresis distance outside the stored cell, so GPS noise at a
-- boundary never flips the pin (which would reveal movement).
CREATE OR REPLACE FUNCTION public.presence_next_cell(
  p_old_lat numeric, p_old_lng numeric, p_lat double precision, p_lng double precision,
  OUT cell_lat numeric, OUT cell_lng numeric)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_new record;
  v_half_lng double precision;
  v_near_lat double precision;
  v_near_lng double precision;
BEGIN
  SELECT * INTO v_new FROM public.presence_snap_cell(p_lat, p_lng);
  IF p_old_lat IS NULL OR (v_new.cell_lat = p_old_lat AND v_new.cell_lng = p_old_lng) THEN
    cell_lat := v_new.cell_lat; cell_lng := v_new.cell_lng; RETURN;
  END IF;
  v_half_lng := (0.01 / greatest(cos(radians(p_old_lat::double precision)), 0.2)) / 2;
  v_near_lat := least(greatest(p_lat, p_old_lat - 0.005), p_old_lat + 0.005);
  v_near_lng := least(greatest(p_lng, p_old_lng - v_half_lng), p_old_lng + v_half_lng);
  IF public.haversine_km(p_lat::numeric, p_lng::numeric, v_near_lat::numeric, v_near_lng::numeric) * 1000
       > public.presence_config('hysteresis_m') THEN
    cell_lat := v_new.cell_lat; cell_lng := v_new.cell_lng;
  ELSE
    cell_lat := p_old_lat; cell_lng := p_old_lng;
  END IF;
END
$$;

-- Membership of an ACTIVE, unarchived relationship (paused or ended
-- relationships share nothing; the purge trigger clears them).
CREATE OR REPLACE FUNCTION public.presence_partner_of(p_relationship_id uuid, p_user uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN r.user_a = p_user THEN r.user_b WHEN r.user_b = p_user THEN r.user_a END
  FROM public.relationships r
  WHERE r.id = p_relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
    AND (r.user_a = p_user OR r.user_b = p_user)
$$;
REVOKE ALL ON FUNCTION public.presence_partner_of(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.presence_fail(p_code text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'presence:%', p_code USING ERRCODE = 'P0001'; END $$;
REVOKE ALL ON FUNCTION public.presence_fail(text) FROM PUBLIC, anon, authenticated;

-- Opting in creates the (empty) row; sampling only ever updates it.
CREATE OR REPLACE FUNCTION public.start_presence(p_relationship_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR public.presence_partner_of(p_relationship_id, auth.uid()) IS NULL THEN
    PERFORM public.presence_fail('not_found');
  END IF;
  INSERT INTO public.partner_presence (user_id, relationship_id)
  VALUES (auth.uid(), p_relationship_id) ON CONFLICT (user_id, relationship_id) DO NOTHING;
END $$;

-- Turning sharing off deletes the row, silently.
CREATE OR REPLACE FUNCTION public.stop_presence(p_relationship_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN PERFORM public.presence_fail('not_found'); END IF;
  DELETE FROM public.partner_presence WHERE user_id = auth.uid() AND relationship_id = p_relationship_id;
END $$;

-- An IANA zone ("Africa/Accra", "UTC"), checked by trying it: no scan of
-- pg_timezone_names (tens of ms per call). Abbreviations like "BST" are
-- ambiguous (and AT TIME ZONE accepts them), POSIX strings like "UTC+3"
-- have the sign backwards, and single-token legacy names ("Japan", "GB",
-- "EST5EDT") are refused on purpose: phones report Area/Location.
CREATE OR REPLACE FUNCTION public.presence_tz_ok(p_tz text)
RETURNS boolean LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF p_tz IS NULL OR p_tz !~ '^([A-Za-z_]+(/[A-Za-z0-9_+-]+)+|UTC|GMT)$' THEN
    RETURN false;
  END IF;
  PERFORM now() AT TIME ZONE p_tz;
  RETURN true;
EXCEPTION WHEN invalid_parameter_value THEN
  RETURN false;
END $$;
REVOKE ALL ON FUNCTION public.presence_tz_ok(text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.record_presence(
  p_relationship_id uuid, p_lat double precision, p_lng double precision, p_accuracy_m double precision,
  p_city text, p_country text, p_country_code text, p_timezone text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_row public.partner_presence;
  v_cell record;
  v_tz text;
  v_precise boolean;
  v_lat numeric;
  v_lng numeric;
BEGIN
  IF v_me IS NULL OR public.presence_partner_of(p_relationship_id, v_me) IS NULL THEN
    PERFORM public.presence_fail('not_found');
  END IF;
  IF p_lat IS NULL OR p_lng IS NULL OR p_lat NOT BETWEEN -90 AND 90 OR p_lng NOT BETWEEN -180 AND 180
     OR p_accuracy_m IS NULL OR p_accuracy_m < 0 THEN
    PERFORM public.presence_fail('invalid_input');
  END IF;
  SELECT * INTO v_row FROM public.partner_presence
  WHERE user_id = v_me AND relationship_id = p_relationship_id FOR UPDATE;
  -- Not opted in: sampling never creates sharing.
  IF NOT FOUND THEN RETURN; END IF;
  -- Paused: nothing is recorded.
  IF v_row.paused_until IS NOT NULL AND v_row.paused_until > now() THEN RETURN; END IF;
  -- Rate limit (checklist 3.8), only once an area is stored.
  IF v_row.cell_lat IS NOT NULL
     AND v_row.updated_at > now() - make_interval(secs => public.presence_config('rate_limit_s')::int) THEN
    RETURN;
  END IF;
  v_tz := CASE WHEN public.presence_tz_ok(p_timezone) THEN p_timezone END;
  v_precise := p_accuracy_m <= public.presence_config('accuracy_cutoff_m');
  IF v_precise THEN
    SELECT * INTO v_cell FROM public.presence_next_cell(v_row.cell_lat, v_row.cell_lng, p_lat, p_lng);
    v_lat := v_cell.cell_lat;
    v_lng := v_cell.cell_lng;
  ELSIF v_row.cell_lat IS NOT NULL
        AND public.haversine_km(v_row.cell_lat, v_row.cell_lng, p_lat::numeric, p_lng::numeric) * 1000 <= p_accuracy_m THEN
    -- Too vague to place, but consistent with the stored area: keep it, so
    -- one cell-tower fix doesn't make the pin blink out (which would read
    -- like a pause).
    v_lat := v_row.cell_lat;
    v_lng := v_row.cell_lng;
  END IF;
  UPDATE public.partner_presence SET
    cell_lat = v_lat,
    cell_lng = v_lng,
    city = left(p_city, 120), country = left(p_country, 120), country_code = left(p_country_code, 8),
    timezone = v_tz, paused_until = NULL, updated_at = now()
  WHERE user_id = v_me AND relationship_id = p_relationship_id;
END $$;

-- Pause clears the area, so a resume can't show the pre-pause cell.
CREATE OR REPLACE FUNCTION public.set_presence_pause(p_relationship_id uuid, p_until timestamptz)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN PERFORM public.presence_fail('not_found'); END IF;
  IF p_until IS NOT NULL AND p_until <> 'infinity'::timestamptz AND p_until <= now() THEN
    PERFORM public.presence_fail('invalid_input');
  END IF;
  -- Clamped rather than refused: the end is computed on the device, whose
  -- clock may run a little ahead of ours.
  IF p_until IS NOT NULL AND p_until <> 'infinity'::timestamptz THEN
    p_until := least(p_until, now() + make_interval(hours => public.presence_config('max_pause_h')::int));
  END IF;
  UPDATE public.partner_presence SET
    paused_until = p_until,
    cell_lat = CASE WHEN p_until IS NULL THEN cell_lat END,
    cell_lng = CASE WHEN p_until IS NULL THEN cell_lng END,
    city = CASE WHEN p_until IS NULL THEN city END,
    country = CASE WHEN p_until IS NULL THEN country END,
    country_code = CASE WHEN p_until IS NULL THEN country_code END
  WHERE user_id = auth.uid() AND relationship_id = p_relationship_id;
  IF NOT FOUND THEN PERFORM public.presence_fail('not_sharing'); END IF;
END $$;

-- Minutes ahead of UTC for an IANA zone, now (NULL if unknown).
CREATE OR REPLACE FUNCTION public.presence_offset_minutes(p_tz text)
RETURNS int LANGUAGE sql STABLE AS $$
  SELECT (extract(epoch FROM (now() AT TIME ZONE p_tz) - (now() AT TIME ZONE 'UTC')) / 60)::int
  WHERE public.presence_tz_ok(p_tz)
$$;
REVOKE ALL ON FUNCTION public.presence_offset_minutes(text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.couple_map_presence(p_relationship_id uuid)
RETURNS TABLE (who text, cell_lat numeric, cell_lng numeric, city text, country text,
               utc_offset_minutes int, freshness text, my_paused_until timestamptz,
               distance_km int, together boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_partner uuid;
  s public.partner_presence;
  o public.partner_presence;
  v_km double precision;
  v_step double precision;
BEGIN
  IF v_me IS NULL THEN RETURN; END IF;
  v_partner := public.presence_partner_of(p_relationship_id, v_me);
  IF v_partner IS NULL THEN RETURN; END IF;
  SELECT * INTO s FROM public.partner_presence WHERE user_id = v_me AND relationship_id = p_relationship_id;
  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY SELECT 'self'::text, s.cell_lat, s.cell_lng, s.city, s.country,
    public.presence_offset_minutes(s.timezone),
    CASE WHEN s.updated_at > now() - make_interval(hours => public.presence_config('fading_after_h')::int)
         THEN 'fresh' ELSE 'fading' END,
    CASE WHEN s.paused_until > now() THEN s.paused_until END,
    NULL::int, NULL::boolean;

  -- Symmetric: I see my partner only while I share, unpaused, with a fresh cell — and so do they.
  IF s.cell_lat IS NULL OR (s.paused_until IS NOT NULL AND s.paused_until > now())
     OR s.updated_at <= now() - make_interval(hours => public.presence_config('stale_after_h')::int) THEN
    RETURN;
  END IF;
  SELECT * INTO o FROM public.partner_presence WHERE user_id = v_partner AND relationship_id = p_relationship_id;
  IF NOT FOUND OR o.cell_lat IS NULL OR (o.paused_until IS NOT NULL AND o.paused_until > now())
     OR o.updated_at <= now() - make_interval(hours => public.presence_config('stale_after_h')::int) THEN
    RETURN;
  END IF;
  v_km := public.haversine_km(s.cell_lat, s.cell_lng, o.cell_lat, o.cell_lng);
  v_step := 0.01 / greatest(cos(radians(s.cell_lat::double precision)), 0.2);
  RETURN QUERY SELECT 'partner'::text, o.cell_lat, o.cell_lng, o.city, o.country,
    public.presence_offset_minutes(o.timezone),
    CASE WHEN o.updated_at > now() - make_interval(hours => public.presence_config('fading_after_h')::int)
         THEN 'fresh' ELSE 'fading' END,
    NULL::timestamptz,
    CASE WHEN v_km < 50 THEN greatest(2, (round(v_km / 5) * 5)::int) ELSE (round(v_km / 10) * 10)::int END,
    (abs(s.cell_lat - o.cell_lat) <= 0.0101 AND abs(s.cell_lng - o.cell_lng) <= v_step * 1.01);
END $$;

REVOKE ALL ON FUNCTION public.start_presence(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.stop_presence(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_presence(uuid, double precision, double precision, double precision, text, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_presence_pause(uuid, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.couple_map_presence(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_presence(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.stop_presence(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_presence(uuid, double precision, double precision, double precision, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_presence_pause(uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.couple_map_presence(uuid) TO authenticated;

-- Closing the relationship (ended, paused or archived) purges its presence.
CREATE OR REPLACE FUNCTION public.presence_purge_on_relationship_close()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'active')
     OR (OLD.chat_archived_at IS NULL AND NEW.chat_archived_at IS NOT NULL) THEN
    DELETE FROM public.partner_presence WHERE relationship_id = NEW.id;
  END IF;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.presence_purge_on_relationship_close() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS presence_purge_on_relationship_close ON public.relationships;
CREATE TRIGGER presence_purge_on_relationship_close
  AFTER UPDATE OF status, chat_archived_at ON public.relationships
  FOR EACH ROW EXECUTE FUNCTION public.presence_purge_on_relationship_close();

CREATE OR REPLACE FUNCTION public.presence_purge_stale()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  DELETE FROM public.partner_presence
  WHERE updated_at < now() - make_interval(days => public.presence_config('retention_days')::int);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.presence_purge_stale() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'presence_purge_stale'; END $$;
SELECT cron.schedule('presence_purge_stale', '17 * * * *', $$ SELECT public.presence_purge_stale(); $$);

INSERT INTO public.feature_flags (key, enabled) VALUES ('couple_map_enabled', false)
ON CONFLICT (key) DO NOTHING;
