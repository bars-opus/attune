-- Guest read of a single booking by payment_intent_id, via SECURITY DEFINER
-- RPC. Avoids granting anon SELECT on the bookings table directly (which
-- would risk leaking all confirmed bookings if a caller drops the URL
-- filter).
--
-- payment_intent_id is a 100-char deterministic reference (shop_uuid +
-- phone + millisecond timestamp); not enumerable in practice. Returning
-- only {id, status} keeps PII out of the response.

CREATE OR REPLACE FUNCTION get_booking_by_reference(p_reference TEXT)
RETURNS TABLE (id UUID, status TEXT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT b.id, b.status::text
  FROM bookings b
  WHERE b.payment_intent_id = p_reference
    AND b.status = 'confirmed'
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION get_booking_by_reference(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_booking_by_reference(TEXT) TO anon, authenticated, service_role;

COMMENT ON FUNCTION get_booking_by_reference IS
  'Public lookup of a confirmed booking by its payment_intent_id reference. Returns id+status only so the booking success page can stop polling once the webhook commits the row.';
