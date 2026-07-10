-- Phase 12 — booking lifecycle triggers
--
-- ONE AFTER INSERT OR UPDATE trigger on bookings, scoped to the
-- transition INTO status = 'confirmed'. Reminder scheduling lives
-- here; terminal-state handling (cancelled / no_show / completed)
-- lives inside the three terminal RPCs via cancel_and_followup
-- (RESEARCH §4 recommendation a — simpler, more explicit, more
-- testable than a generic UPDATE trigger).
--
-- Verified: NO existing triggers on bookings (RESEARCH §15).
-- Zero conflict surface.
--
-- This is THE single source of booking_reminder_24h +
-- booking_reminder_2h rows. Wave 2 migrations remove the duplicated
-- inserts from paystack-webhook, stripe-webhook, verify-payment.

CREATE OR REPLACE FUNCTION public.schedule_booking_reminders()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
  -- Re-confirmation (UPDATE where the row was already confirmed): no-op.
  IF TG_OP = 'UPDATE' AND OLD.status = 'confirmed' THEN
    RETURN NEW;
  END IF;

  -- Past or inside the 2h window: no reminder makes sense.
  IF NEW.start_time <= now() + INTERVAL '2 hours' THEN
    RETURN NEW;
  END IF;

  -- 24h reminder (skipped if start is < 24h out).
  IF NEW.start_time > now() + INTERVAL '24 hours' THEN
    PERFORM public.enqueue_booking_reminder(
      NEW.id, 'booking_reminder_24h',
      NEW.start_time - INTERVAL '24 hours'
    );
  END IF;

  -- 2h reminder (always scheduled when > 2h out).
  PERFORM public.enqueue_booking_reminder(
    NEW.id, 'booking_reminder_2h',
    NEW.start_time - INTERVAL '2 hours'
  );

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_bookings_schedule_reminders ON public.bookings;
CREATE TRIGGER trg_bookings_schedule_reminders
  AFTER INSERT OR UPDATE OF status ON public.bookings
  FOR EACH ROW
  WHEN (NEW.status = 'confirmed')
  EXECUTE FUNCTION public.schedule_booking_reminders();

COMMENT ON FUNCTION public.schedule_booking_reminders() IS
  'Phase 12: single source of booking_reminder_24h + booking_reminder_2h rows. Fires on transition INTO confirmed. Skips rebookings of an already-confirmed booking. O(1) per booking.';
