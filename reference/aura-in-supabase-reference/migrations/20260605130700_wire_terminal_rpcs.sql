-- Phase 12 — wire cancel_and_followup into the three terminal RPCs.
--
-- The three RPCs (cancel_booking, mark_booking_complete,
-- mark_booking_no_show) are CREATE OR REPLACEd in full — Postgres has
-- no partial rewrite. Each body is copied verbatim from
-- 20260517020000_booking_hardening.sql (the canonical Phase 1c bodies)
-- with EXACTLY ONE new statement inserted: a PERFORM
-- public.cancel_and_followup(p_booking_id, '<status>') as the LAST
-- statement before the final SELECT/RETURN.
--
-- Signatures are byte-for-byte preserved. The FOR UPDATE row lock at
-- the top of each function keeps the status flip + followup atomic
-- with the booking row (RESEARCH §4).
--
-- A drift gate in Definition of done verifies the bodies match the
-- originals modulo the one new PERFORM line.

-- ── 1. cancel_booking ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION cancel_booking(
  p_booking_id UUID,
  p_reason     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_owner   UUID;
  v_result  JSONB;
BEGIN
  PERFORM check_rate_limit('cancel_booking', 5, 60);

  IF p_reason IS NOT NULL AND length(p_reason) > 500 THEN
    RAISE EXCEPTION 'cancellation_reason too long' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking % not found', p_booking_id USING ERRCODE = 'P0002';
  END IF;

  -- Either the booking owner or the shop owner may cancel.
  SELECT user_id INTO v_owner FROM shops WHERE id = v_booking.shop_id;
  IF v_booking.user_id IS DISTINCT FROM auth.uid()
     AND v_owner       IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: not booking or shop owner' USING ERRCODE = '42501';
  END IF;

  IF v_booking.status NOT IN ('pending','confirmed') THEN
    RAISE EXCEPTION 'cannot cancel booking in status %', v_booking.status
      USING ERRCODE = '22023';
  END IF;

  UPDATE bookings
  SET    status              = 'cancelled',
         cancellation_reason = NULLIF(trim(coalesce(p_reason, '')), ''),
         cancelled_at        = now(),
         updated_at          = now()
  WHERE  id = p_booking_id;

  INSERT INTO booking_audit_log (actor_id, action, target_table, target_id, details)
  VALUES (auth.uid(), 'booking.cancel', 'bookings', p_booking_id,
          jsonb_build_object('from', v_booking.status));

  -- Phase 12: cancel pending reminders + schedule recovery_checkin.
  PERFORM public.cancel_and_followup(p_booking_id, 'cancelled');

  SELECT to_jsonb(b.*) INTO v_result FROM bookings b WHERE b.id = p_booking_id;
  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION cancel_booking(UUID, TEXT) IS
  'Phase 12: cancel_and_followup wired in after the status UPDATE. Cancels pending reminders and schedules a recovery_checkin (T+7d) atomically with the cancellation.';

-- ── 2. mark_booking_complete ───────────────────────────────────────
CREATE OR REPLACE FUNCTION mark_booking_complete(
  p_booking_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_owner   UUID;
  v_result  JSONB;
BEGIN
  PERFORM check_rate_limit('mark_booking_complete', 60, 60);

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking % not found', p_booking_id USING ERRCODE = 'P0002';
  END IF;

  SELECT user_id INTO v_owner FROM shops WHERE id = v_booking.shop_id;
  IF v_owner IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: not the shop owner' USING ERRCODE = '42501';
  END IF;

  IF v_booking.status NOT IN ('confirmed','completed') THEN
    RAISE EXCEPTION 'cannot complete booking in status %', v_booking.status
      USING ERRCODE = '22023';
  END IF;

  IF v_booking.status <> 'completed' THEN
    UPDATE bookings SET status = 'completed', updated_at = now()
    WHERE  id = p_booking_id;

    INSERT INTO booking_audit_log (actor_id, action, target_table, target_id, details)
    VALUES (auth.uid(), 'booking.complete', 'bookings', p_booking_id,
            jsonb_build_object('from', v_booking.status));

    -- Phase 12: cancel pending reminders + schedule review_request.
    -- Inside the status-change branch so re-marking-as-completed is a no-op.
    PERFORM public.cancel_and_followup(p_booking_id, 'completed');
  END IF;

  SELECT to_jsonb(b.*) INTO v_result FROM bookings b WHERE b.id = p_booking_id;
  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION mark_booking_complete(UUID) IS
  'Phase 12: cancel_and_followup wired in inside the status-change branch (re-marking-as-completed remains a no-op). Cancels pending reminders and schedules a review_request (T+2h).';

-- ── 3. mark_booking_no_show ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION mark_booking_no_show(
  p_booking_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_owner   UUID;
  v_result  JSONB;
BEGIN
  PERFORM check_rate_limit('mark_booking_no_show', 60, 60);

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking % not found', p_booking_id USING ERRCODE = 'P0002';
  END IF;

  SELECT user_id INTO v_owner FROM shops WHERE id = v_booking.shop_id;
  IF v_owner IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: not the shop owner' USING ERRCODE = '42501';
  END IF;

  IF v_booking.status NOT IN ('confirmed','pending','no_show') THEN
    RAISE EXCEPTION 'cannot no-show booking in status %', v_booking.status
      USING ERRCODE = '22023';
  END IF;

  IF v_booking.start_time > now() THEN
    RAISE EXCEPTION 'cannot mark no-show before the booking start time' USING ERRCODE = '22023';
  END IF;

  IF v_booking.status <> 'no_show' THEN
    UPDATE bookings SET status = 'no_show', updated_at = now()
    WHERE  id = p_booking_id;

    INSERT INTO booking_audit_log (actor_id, action, target_table, target_id, details)
    VALUES (auth.uid(), 'booking.no_show', 'bookings', p_booking_id,
            jsonb_build_object('from', v_booking.status));

    -- Phase 12: cancel pending reminders + schedule recovery_checkin.
    -- Inside the status-change branch so re-marking-as-no_show is a no-op.
    PERFORM public.cancel_and_followup(p_booking_id, 'no_show');
  END IF;

  SELECT to_jsonb(b.*) INTO v_result FROM bookings b WHERE b.id = p_booking_id;
  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION mark_booking_no_show(UUID) IS
  'Phase 12: cancel_and_followup wired in inside the status-change branch (re-marking-as-no_show remains a no-op). Cancels pending reminders and schedules a recovery_checkin (T+7d).';
