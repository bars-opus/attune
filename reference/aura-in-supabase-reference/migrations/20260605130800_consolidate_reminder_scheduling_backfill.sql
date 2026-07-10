-- Phase 12 — one-time reminder consolidation backfill.
--
-- Ensures every confirmed + future booking has a pending
-- booking_reminder_24h AND booking_reminder_2h row before the webhook
-- diffs (Wave 2 edge-fn deploys) remove the duplicate writers in
-- paystack-webhook / stripe-webhook / verify-payment.
--
-- Without this backfill, any booking confirmed BEFORE Wave 1's trigger
-- landed but AFTER the webhook write would silently lose its reminder
-- coverage when the webhook stops scheduling them.
--
-- Idempotent: the NOT EXISTS guard skips bookings that already have a
-- pending/processing/sent reminder of that type. Safe to re-run.

DO $$
DECLARE
  v_booking RECORD;
  v_24h_count INT := 0;
  v_2h_count  INT := 0;
BEGIN
  -- 24h reminders.
  FOR v_booking IN
    SELECT b.id, b.start_time
    FROM public.bookings b
    WHERE b.status = 'confirmed'
      AND b.start_time > now() + INTERVAL '24 hours'
      AND NOT EXISTS (
        SELECT 1 FROM public.scheduled_notifications s
        WHERE s.booking_id = b.id
          AND s.notification_type = 'booking_reminder_24h'
          AND s.status IN ('pending', 'processing', 'sent')
      )
  LOOP
    PERFORM public.enqueue_booking_reminder(
      v_booking.id, 'booking_reminder_24h',
      v_booking.start_time - INTERVAL '24 hours'
    );
    v_24h_count := v_24h_count + 1;
  END LOOP;

  -- 2h reminders.
  FOR v_booking IN
    SELECT b.id, b.start_time
    FROM public.bookings b
    WHERE b.status = 'confirmed'
      AND b.start_time > now() + INTERVAL '2 hours'
      AND NOT EXISTS (
        SELECT 1 FROM public.scheduled_notifications s
        WHERE s.booking_id = b.id
          AND s.notification_type = 'booking_reminder_2h'
          AND s.status IN ('pending', 'processing', 'sent')
      )
  LOOP
    PERFORM public.enqueue_booking_reminder(
      v_booking.id, 'booking_reminder_2h',
      v_booking.start_time - INTERVAL '2 hours'
    );
    v_2h_count := v_2h_count + 1;
  END LOOP;

  RAISE NOTICE 'Phase 12 backfill: scheduled % new 24h reminders, % new 2h reminders.',
    v_24h_count, v_2h_count;
END $$;
