-- Phase 13 — booking_loyalty_trigger
--
-- AFTER UPDATE OF status on bookings, WHEN (NEW.status = 'completed').
-- Counts the client's completed bookings at this shop; on every Nth
-- completion (where N = the shop's active loyalty_rule.trigger_visit_count),
-- calls generate_loyalty_code which issues a one-shot promo code.
--
-- Idempotency:
--   * Re-marking-as-completed early-returns (OLD.status = 'completed').
--   * generate_loyalty_code itself has a NOT EXISTS guard on
--     unredeemed loyalty codes; double-fires never duplicate.
--
-- Non-overlapping with Phase 12's trg_bookings_schedule_reminders:
-- that trigger's WHEN clause restricts it to NEW.status='confirmed'.
-- Phase 13's trigger restricts to NEW.status='completed'. The two
-- never fire on the same transition.

CREATE OR REPLACE FUNCTION public.handle_booking_completion_for_loyalty()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_trigger_visit_count INT;
  v_visit_count         INT;
BEGIN
  -- Re-mark-as-completed: no-op.
  IF TG_OP = 'UPDATE' AND OLD.status = 'completed' THEN
    RETURN NEW;
  END IF;

  -- Look up the shop's active loyalty rule.
  SELECT trigger_visit_count INTO v_trigger_visit_count
  FROM public.loyalty_rules
  WHERE shop_id = NEW.shop_id AND is_active = TRUE;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- Count the client's completed bookings at this shop, INCLUDING the
  -- one currently being marked completed. v_visit_count is 1-indexed.
  SELECT COUNT(*) INTO v_visit_count
  FROM public.bookings b
  WHERE b.shop_id = NEW.shop_id
    AND b.status = 'completed'
    AND (
      (NEW.user_id IS NOT NULL AND b.user_id = NEW.user_id) OR
      (NEW.guest_profile_id IS NOT NULL
       AND b.guest_profile_id = NEW.guest_profile_id)
    );

  -- Fire on every Nth completion: on visit 3, 6, 9, ... when N=3.
  IF v_visit_count % v_trigger_visit_count <> 0 THEN
    RETURN NEW;
  END IF;

  -- generate_loyalty_code is idempotent.
  PERFORM public.generate_loyalty_code(
    NEW.shop_id, NEW.user_id, NEW.guest_profile_id
  );

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_bookings_loyalty_visit ON public.bookings;
CREATE TRIGGER trg_bookings_loyalty_visit
  AFTER UPDATE OF status ON public.bookings
  FOR EACH ROW
  WHEN (NEW.status = 'completed')
  EXECUTE FUNCTION public.handle_booking_completion_for_loyalty();

COMMENT ON FUNCTION public.handle_booking_completion_for_loyalty() IS
  'Phase 13: AFTER UPDATE OF status trigger body. Fires only on the completed transition. Idempotent via generate_loyalty_code NOT EXISTS guard. Non-overlapping WHEN clause with trg_bookings_schedule_reminders (confirmed-only). O(client_completed_bookings_at_shop).';
