-- schedule_manual_booking_reminder(p_booking_id UUID) -> UUID
--
-- Replaces the ghost `send-reminder` edge function the Tools tab's
-- "Send manual reminder" used to call. Instead of an edge function,
-- we drop a single row into scheduled_notifications; the existing
-- process-scheduled-notifications cron worker picks it up within
-- ~60 seconds and dispatches via OneSignal push.
--
-- Hardening template parity with supabase/migrations/20260603001500_harden_dashboard_rpcs.sql:
--   * SECURITY DEFINER + SET search_path = public
--   * Authz FIRST via bookings.shop_id -> shops.user_id = auth.uid()
--   * Sanitized errors with HINT codes
--   * REVOKE ALL FROM PUBLIC + GRANT EXECUTE TO authenticated
--   * COMMENT ON FUNCTION with Big-O
--
-- Guards:
--   1. Booking exists + caller owns the shop.
--   2. Booking has a user_id (guest bookings cannot receive push).
--   3. Booking.start_time is in the future (don't ping a customer mid-haircut).
--
-- Idempotency: NOT enforced at the RPC layer in v1. A second tap
-- enqueues a second row; OneSignal absorbs the duplicate at the device.
-- See PR description for the P2 follow-up adding a partial unique index.

CREATE OR REPLACE FUNCTION public.schedule_manual_booking_reminder(
  p_booking_id UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_booking_user_id  UUID;
  v_booking_shop_id  UUID;
  v_booking_start    TIMESTAMPTZ;
  v_shop_owner_id    UUID;
  v_notification_id  UUID;
BEGIN
  -- Load booking + shop owner in a single SELECT. Empty row -> 42501.
  SELECT b.user_id, b.shop_id, b.start_time, s.user_id
    INTO v_booking_user_id, v_booking_shop_id, v_booking_start, v_shop_owner_id
  FROM public.bookings b
  JOIN public.shops s ON s.id = b.shop_id
  WHERE b.id = p_booking_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_shop_owner_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = '42501';
  END IF;

  -- Guest bookings (user_id NULL) cannot receive push. The WhatsApp
  -- path requires a phone + template — out of scope for this RPC.
  IF v_booking_user_id IS NULL THEN
    RAISE EXCEPTION 'guest_booking_not_supported'
      USING ERRCODE = 'P0001', HINT = 'NO_PUSH_FOR_GUEST';
  END IF;

  -- Past-time guard: don't fire a "your appointment is coming up"
  -- to a customer whose appointment has already started.
  IF v_booking_start <= now() THEN
    RAISE EXCEPTION 'booking_in_past'
      USING ERRCODE = 'P0001', HINT = 'BOOKING_ALREADY_STARTED';
  END IF;

  INSERT INTO public.scheduled_notifications (
    user_id, notification_type, booking_id, shop_id,
    scheduled_for, delivery_channel, metadata
  ) VALUES (
    v_booking_user_id,
    'booking_reminder_manual',
    p_booking_id,
    v_booking_shop_id,
    now(),
    'push',
    jsonb_build_object(
      'title',      'Upcoming appointment',
      'body',       'Your appointment is coming up.',
      'source',     'manual_owner_send',
      'booking_id', p_booking_id
    )
  )
  RETURNING id INTO v_notification_id;

  RETURN v_notification_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.schedule_manual_booking_reminder(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.schedule_manual_booking_reminder(UUID) TO authenticated;

COMMENT ON FUNCTION public.schedule_manual_booking_reminder(UUID) IS
  'Schedule a single manual push reminder for a booking. SECURITY DEFINER with bookings->shops.user_id=auth.uid() authz gate, guest-booking + past-time guards, explicit delivery_channel=push. O(1) - single index lookup + single insert.';
