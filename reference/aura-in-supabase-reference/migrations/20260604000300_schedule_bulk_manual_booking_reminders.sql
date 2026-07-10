-- schedule_bulk_manual_booking_reminders(p_shop_id UUID, p_date DATE) -> INT
--
-- Server-side bulk path. Replaces the loop-of-N-RPC-calls in the
-- current sendBulkReminders implementation. One INSERT ... SELECT
-- statement enqueues a row per confirmed future booking on the given
-- date, returning the count.
--
-- Hardening template parity with supabase/migrations/20260603001500_harden_dashboard_rpcs.sql.
--
-- WHERE filter set (carried over from the single-row RPC for parity):
--   * b.shop_id = p_shop_id           — scope
--   * b.start_time::DATE = p_date     — same day
--   * b.start_time > now()            — past-time guard (R2)
--   * b.status = 'confirmed'          — terminal-state exclusion
--   * b.user_id IS NOT NULL           — guest exclusion
--
-- Note: uses start_time::DATE not a `booking_date` column. The heatmap
-- RPC in 20260603001500 follows the same pattern, and start_time is
-- canonically indexed via idx_bookings_shop_id (shop_id, start_time DESC).
--
-- R3 (accepted): No partial unique index in v1. A second tap will
-- enqueue a second row per booking. OneSignal absorbs the duplicate
-- at the device. P2 follow-up filed in the PR description.

CREATE OR REPLACE FUNCTION public.schedule_bulk_manual_booking_reminders(
  p_shop_id UUID,
  p_date    DATE DEFAULT CURRENT_DATE
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_owns_shop BOOLEAN;
  v_inserted  INT;
BEGIN
  -- Authz FIRST: caller must own the shop.
  SELECT EXISTS (
    SELECT 1 FROM public.shops
    WHERE id = p_shop_id AND user_id = auth.uid()
  ) INTO v_owns_shop;
  IF NOT v_owns_shop THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = '42501';
  END IF;

  -- Range validation AFTER authz.
  IF p_date IS NULL THEN
    RAISE EXCEPTION 'invalid_date' USING ERRCODE = '22023', HINT = 'DATE_REQUIRED';
  END IF;

  WITH inserted AS (
    INSERT INTO public.scheduled_notifications (
      user_id, notification_type, booking_id, shop_id,
      scheduled_for, delivery_channel, metadata
    )
    SELECT
      b.user_id,
      'booking_reminder_manual',
      b.id,
      b.shop_id,
      now(),
      'push',
      jsonb_build_object(
        'title',      'Upcoming appointment',
        'body',       'Your appointment is coming up.',
        'source',     'manual_owner_bulk_send',
        'booking_id', b.id
      )
    FROM public.bookings b
    WHERE b.shop_id            = p_shop_id
      AND b.start_time::DATE   = p_date
      AND b.start_time         > now()
      AND b.status             = 'confirmed'
      AND b.user_id            IS NOT NULL
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_inserted FROM inserted;

  RETURN v_inserted;
END;
$function$;

REVOKE ALL ON FUNCTION public.schedule_bulk_manual_booking_reminders(UUID, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.schedule_bulk_manual_booking_reminders(UUID, DATE) TO authenticated;

COMMENT ON FUNCTION public.schedule_bulk_manual_booking_reminders(UUID, DATE) IS
  'Server-side bulk enqueue of manual push reminders for a shop on a given date. One INSERT ... SELECT statement. Skips guest bookings (user_id IS NULL) and past-start bookings. SECURITY DEFINER with shop ownership gate. O(N) where N = matching bookings, bounded by one day per shop.';
