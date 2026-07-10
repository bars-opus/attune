-- archive_appointment_slot(p_slot_id UUID) -> VOID
--
-- Soft-delete a single service (appointment_slots row) by setting
-- archived_at = now(). Hard delete is impossible because existing
-- bookings reference the slot via booking_services.slot_id FK; the
-- soft-delete pattern lets the row stay queryable for historical
-- reports while excluding it from forward-looking booking flows.
--
-- Depends on 20260605000050 (archived_at column).
-- Hardening template parity with 20260603001500_harden_dashboard_rpcs.sql.
--
-- Idempotency: the UPDATE includes WHERE archived_at IS NULL, so a
-- second call on an already-archived slot is a silent no-op (zero rows
-- affected). Caller gets the same VOID return. This matches the
-- redeem_promotion pattern from Phase 10.5.

CREATE OR REPLACE FUNCTION public.archive_appointment_slot(
  p_slot_id UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_owns_shop BOOLEAN;
BEGIN
  -- (1) Input-shape validation. NULL guard before authz so a malformed
  -- payload is distinguishable from an authz failure.
  IF p_slot_id IS NULL THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023', HINT = 'NULL_NOT_ALLOWED';
  END IF;

  -- (2) Authz: caller must own the shop that owns this slot.
  SELECT EXISTS (
    SELECT 1
    FROM public.appointment_slots s
    JOIN public.shops sh ON sh.id = s.shop_id
    WHERE s.id = p_slot_id AND sh.user_id = auth.uid()
  ) INTO v_owns_shop;
  IF NOT v_owns_shop THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = '42501';
  END IF;

  -- (3) Idempotent soft-delete. Re-archive is a silent no-op.
  UPDATE public.appointment_slots
     SET archived_at = now()
   WHERE id = p_slot_id
     AND archived_at IS NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public.archive_appointment_slot(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.archive_appointment_slot(UUID) TO authenticated;

COMMENT ON FUNCTION public.archive_appointment_slot(UUID) IS
  'Soft-delete an appointment slot by setting archived_at. SECURITY DEFINER with appointment_slots->shops.user_id=auth.uid() gate. Idempotent (WHERE archived_at IS NULL). O(1).';
