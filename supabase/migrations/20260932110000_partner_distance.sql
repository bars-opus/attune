-- Distance between partners, computed server-side.
--
-- The client never receives its partner's coordinates. This function is
-- the ONLY path between the two presence rows, and it returns a distance
-- and a coarse place -- never a position. That is what stops the ambient
-- row being a location channel.

-- Great-circle distance in kilometres. Plain haversine: PostGIS is not
-- installed, and at the precision this feature shows (buckets, and travel
-- times rounded to 5 minutes) the ellipsoid correction is far below the
-- resolution anyone sees.
CREATE OR REPLACE FUNCTION public.haversine_km(
  lat1 numeric, lon1 numeric, lat2 numeric, lon2 numeric
)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 6371 * 2 * asin(
    sqrt(
      power(sin(radians(lat2 - lat1) / 2), 2)
      + cos(radians(lat1)) * cos(radians(lat2))
        * power(sin(radians(lon2 - lon1) / 2), 2)
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.partner_distance(
  p_relationship_id uuid
)
RETURNS TABLE (
  distance_km double precision,
  partner_city text,
  partner_country text,
  partner_timezone text,
  partner_updated_at timestamptz,
  self_updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_partner uuid;
  v_self public.partner_presence%ROWTYPE;
  v_other public.partner_presence%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  -- Membership first: without this, any authenticated user could pass a
  -- relationship id and learn how far apart that couple is. Returns no
  -- row rather than raising, so a caller cannot tell "not a member" from
  -- "no location shared".
  SELECT CASE
           WHEN r.user_a = v_user_id THEN r.user_b
           WHEN r.user_b = v_user_id THEN r.user_a
         END
  INTO v_partner
  FROM public.relationships r
  WHERE r.id = p_relationship_id
    AND r.chat_archived_at IS NULL
    AND (r.user_a = v_user_id OR r.user_b = v_user_id);

  IF v_partner IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_self FROM public.partner_presence WHERE user_id = v_user_id;
  SELECT * INTO v_other FROM public.partner_presence WHERE user_id = v_partner;

  -- Symmetric by construction: no distance unless BOTH have shared. You
  -- cannot see how far away your partner is while withholding your own
  -- position, which would be exactly the asymmetry this feature exists to
  -- avoid.
  IF v_self.latitude IS NULL OR v_other.latitude IS NULL THEN
    RETURN;
  END IF;

  -- A stale position must never be presented as current. Beyond a day it
  -- is a guess, and a confident wrong number is worse than none.
  IF v_other.updated_at < now() - interval '24 hours' THEN
    RETURN;
  END IF;

  RETURN QUERY SELECT
    public.haversine_km(
      v_self.latitude, v_self.longitude,
      v_other.latitude, v_other.longitude
    ),
    v_other.city,
    v_other.country,
    v_other.timezone,
    v_other.updated_at,
    v_self.updated_at;
END;
$$;

REVOKE ALL ON FUNCTION public.partner_distance(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.partner_distance(uuid) TO authenticated;

COMMENT ON FUNCTION public.partner_distance(uuid) IS
  'Distance in km between the caller and their partner, with the partner''s '
  'coarse city and timezone. Never returns coordinates. Returns no row '
  'unless both partners have shared and the partner''s position is fresh.';
