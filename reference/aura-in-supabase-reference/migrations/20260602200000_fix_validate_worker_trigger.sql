-- Fix validate_worker_belongs_to_shop to allow NULL worker_id.
--
-- The original trigger (added via Supabase dashboard) raised even when
-- NEW.worker_id IS NULL because the NOT EXISTS check looks for
-- `w.id = NEW.worker_id`, which is never true when worker_id is NULL.
-- The web booking flow legitimately sends NULL when the visitor leaves
-- worker on "Any available", and the result was:
--   * booking_services row never inserted (blocked by this trigger);
--   * /booking/[id] showed no services;
--   * Analytics → Services and Workers tabs stayed empty;
--   * Calendar / schedule had no per-worker rows to display.
--
-- The right semantics: skip the shop-membership check when worker_id IS
-- NULL (the booking is service-scoped, not worker-scoped), but still
-- enforce it when worker_id is set.

CREATE OR REPLACE FUNCTION public.validate_worker_belongs_to_shop()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_shop_id UUID;
BEGIN
  -- NULL worker_id means "any available" — no shop check needed.
  IF NEW.worker_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT shop_id INTO v_shop_id
    FROM bookings
   WHERE id = NEW.booking_id;

  IF NOT EXISTS (
    SELECT 1 FROM workers w
     WHERE w.id = NEW.worker_id
       AND w.shop_id = v_shop_id
  ) THEN
    RAISE EXCEPTION 'Worker does not belong to this shop';
  END IF;

  RETURN NEW;
END;
$$;
