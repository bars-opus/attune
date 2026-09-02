-- Coordinate range checks (checklist 2.1: input sanitization).
--
-- Latitude 999 was accepted. Nothing in the app sends it, but a bad
-- reading, a unit mix-up, or a client bug would store it and haversine
-- would then return a confident nonsense distance -- "8,000 km apart" to
-- a couple in the same house. A range check turns a silent wrong answer
-- into a rejected write.
--
-- Bounds are the actual limits of the coordinate system rather than
-- anything app-specific, so this can never reject a real place.

ALTER TABLE public.partner_presence
  DROP CONSTRAINT IF EXISTS partner_presence_lat_range;
ALTER TABLE public.partner_presence
  ADD CONSTRAINT partner_presence_lat_range
  CHECK (latitude IS NULL OR (latitude >= -90 AND latitude <= 90));

ALTER TABLE public.partner_presence
  DROP CONSTRAINT IF EXISTS partner_presence_lon_range;
ALTER TABLE public.partner_presence
  ADD CONSTRAINT partner_presence_lon_range
  CHECK (longitude IS NULL OR (longitude >= -180 AND longitude <= 180));

-- Free text that reaches the partner's screen. Bounded so a client bug
-- or a hostile write cannot store an unbounded string.
ALTER TABLE public.partner_presence
  DROP CONSTRAINT IF EXISTS partner_presence_text_lengths;
ALTER TABLE public.partner_presence
  ADD CONSTRAINT partner_presence_text_lengths
  CHECK (
    (city IS NULL OR char_length(city) <= 120)
    AND (country IS NULL OR char_length(country) <= 120)
    AND (country_code IS NULL OR char_length(country_code) <= 8)
    AND (timezone IS NULL OR char_length(timezone) <= 64)
  );

ALTER TABLE public.place_updates
  DROP CONSTRAINT IF EXISTS place_updates_coord_range;
ALTER TABLE public.place_updates
  ADD CONSTRAINT place_updates_coord_range
  CHECK (
    (latitude IS NULL OR (latitude >= -90 AND latitude <= 90))
    AND (longitude IS NULL OR (longitude >= -180 AND longitude <= 180))
  );

ALTER TABLE public.place_updates
  DROP CONSTRAINT IF EXISTS place_updates_place_text_lengths;
ALTER TABLE public.place_updates
  ADD CONSTRAINT place_updates_place_text_lengths
  CHECK (
    (city IS NULL OR char_length(city) <= 120)
    AND (country IS NULL OR char_length(country) <= 120)
  );
