-- Phase 12 — cancel_and_followup helper
--
-- Called from the three terminal-state booking RPCs (cancel_booking,
-- mark_booking_complete, mark_booking_no_show) to:
--   1. Cancel any pending reminders for the booking.
--   2. Schedule the next-stage row:
--        completed → review_request at now()+2h
--        cancelled/no_show → recovery_checkin at now()+7d
--
-- The recovery_checkin path swallows unique_violation. That's the
-- idempotency contract: re-invoking this function for the same booking
-- (re-cancellation, double webhook fire, retry storm) is a no-op rather
-- than a duplicate insert. The partial unique index (added in Wave 3
-- migration 130900) is the actual cooldown enforcer; this EXCEPTION
-- handler is what makes the swallow narrowly-scoped. All other errors
-- propagate to the caller for transaction rollback.

CREATE OR REPLACE FUNCTION public.cancel_and_followup(
  p_booking_id      UUID,
  p_terminal_status TEXT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $function$
BEGIN
  IF p_terminal_status NOT IN ('cancelled', 'no_show', 'completed') THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'UNKNOWN_TERMINAL_STATUS';
  END IF;

  -- 1. Cancel any pending reminders for this booking.
  PERFORM public.cancel_booking_notifications(p_booking_id);

  -- 2. Schedule the follow-up.
  IF p_terminal_status = 'completed' THEN
    PERFORM public.enqueue_booking_reminder(
      p_booking_id, 'review_request', now() + INTERVAL '2 hours'
    );
  ELSE
    -- cancelled or no_show → recovery_checkin at T+7d, guarded by the
    -- 30-day partial unique index from Wave 3 migration 130900.
    BEGIN
      PERFORM public.enqueue_booking_reminder(
        p_booking_id, 'recovery_checkin', now() + INTERVAL '7 days'
      );
    EXCEPTION WHEN unique_violation THEN
      -- Cool-down window suppressed the new row. No-op.
      NULL;
    END;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.cancel_and_followup(UUID, TEXT) FROM PUBLIC;
-- Intentionally NOT GRANTed to authenticated. Called only from the
-- three terminal-state RPCs (which are themselves SECURITY DEFINER).

COMMENT ON FUNCTION public.cancel_and_followup(UUID, TEXT) IS
  'Idempotent terminal-status handler. Cancels pending reminders, schedules the next-stage row (review_request for completed; recovery_checkin for cancelled/no_show). SECURITY DEFINER; called from cancel_booking / mark_booking_complete / mark_booking_no_show. The narrowly-scoped EXCEPTION WHEN unique_violation block is the idempotency contract: re-invoking this function for the same booking (re-cancellation, double webhook fire, retry storm) is a no-op rather than a duplicate insert. All other errors propagate to the caller for transaction rollback. O(reminders for booking). Phase 12.';
