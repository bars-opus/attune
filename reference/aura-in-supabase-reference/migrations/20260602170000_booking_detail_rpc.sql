-- Public RPC for the /booking/[id] booking-detail page.
--
-- Returns the booking row plus joined shop + services as JSON so the web
-- layer renders in a single round trip. Anon-safe: returns only fields a
-- guest themselves already submitted, plus shop public-profile fields.
-- The guest's phone is redacted server-side. Bookings can only be looked
-- up by their UUID (not enumerable in practice — 122 bits of entropy).
--
-- Unlike get_booking_by_reference (which returns just id+status for the
-- payment success poll), this is the richer payload used by the actual
-- detail page accessible from the WhatsApp deep link.

CREATE OR REPLACE FUNCTION get_booking_detail(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
  v_shop    RECORD;
  v_services JSONB;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_id AND status = 'confirmed' LIMIT 1;
  IF v_booking.id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT shop_name, shop_type, shop_logo_url, address, country
    INTO v_shop
    FROM shops
   WHERE id = v_booking.shop_id;

  -- Aggregate the per-service rows (may be empty if booking_services failed
  -- to insert — known issue for v1 with the worker validation trigger).
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'name', bs.service_name,
        'duration_minutes', bs.duration_minutes,
        'price', bs.price_at_booking,
        'worker_name', bs.worker_name,
        'start_time', bs.start_time
      ) ORDER BY bs.start_time NULLS LAST
    ),
    '[]'::jsonb
  ) INTO v_services
  FROM booking_services bs
  WHERE bs.booking_id = p_id;

  RETURN jsonb_build_object(
    'id',              v_booking.id,
    'status',          v_booking.status::text,
    'start_time',      v_booking.start_time,
    'end_time',        v_booking.end_time,
    'total_amount',    v_booking.total_amount,
    'deposit_amount',  v_booking.deposit_amount,
    'platform_fee',    v_booking.platform_fee,
    'guest_name',      v_booking.guest_name,
    -- Redact phone for display: +233****1544 style.
    'guest_phone_masked',
      CASE
        WHEN v_booking.guest_phone IS NULL THEN NULL
        WHEN length(v_booking.guest_phone) < 6 THEN '[REDACTED]'
        ELSE substr(v_booking.guest_phone, 1, 4) ||
             '****' ||
             right(v_booking.guest_phone, 4)
      END,
    'client_address',  v_booking.client_address,
    'shop', CASE WHEN v_shop.shop_name IS NULL THEN NULL ELSE jsonb_build_object(
      'name',     v_shop.shop_name,
      'type',     v_shop.shop_type,
      'logo_url', v_shop.shop_logo_url,
      'address',  v_shop.address,
      'country',  v_shop.country
    ) END,
    'services', v_services
  );
END;
$$;

REVOKE ALL ON FUNCTION get_booking_detail(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_booking_detail(UUID) TO anon, authenticated, service_role;

COMMENT ON FUNCTION get_booking_detail IS
  'Public lookup of a confirmed booking detail by UUID. Phone is redacted; only fields the guest themselves submitted + shop public-profile fields are returned. Used by /booking/[id] page reachable from the WhatsApp link.';
