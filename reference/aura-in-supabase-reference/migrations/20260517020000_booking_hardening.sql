-- ============================================================
-- Booking Hardening
-- ============================================================
-- Adds the security and behavioral guarantees the canonical
-- booking schema deferred to keep the baseline easy to review.
--
-- Builds on:
--   - 20260517010000_booking_schema.sql       (tables, RLS, RPCs)
--   - 20260516000000_marketplace_hardening.sql (check_rate_limit)
--
-- Adds (in this migration):
--   1. Length CHECK caps on every free-text booking column.
--   2. Distinct-worker constraint for group bookings — no single
--      worker can be assigned to two seats in the same group at
--      the same start_time.
--   3. Status state machine: cancel_booking, mark_booking_complete,
--      mark_booking_no_show RPCs that enforce legal transitions
--      (no completing a cancelled booking, etc.) and add audit.
--   4. Rate limits on every mutating booking RPC.
--   5. booking_audit_log table for sensitive operations.
--   6. Length CHECK + sanitization on RPC inputs (cancellation
--      reason, special requirements, service address).
--
-- All changes are safe to re-apply: ADD CONSTRAINT is guarded
-- with DO blocks; CREATE OR REPLACE wins on the RPCs.
-- ============================================================

-- ── 1. Length CHECK caps ─────────────────────────────────────

DO $$ BEGIN
  ALTER TABLE bookings
    ADD CONSTRAINT bookings_cancel_reason_max_length
      CHECK (cancellation_reason IS NULL OR length(cancellation_reason) <= 500),
    ADD CONSTRAINT bookings_address_max_length
      CHECK (address IS NULL OR length(address) <= 500),
    ADD CONSTRAINT bookings_payment_method_max_length
      CHECK (payment_method IS NULL OR length(payment_method) <= 50),
    ADD CONSTRAINT bookings_payment_intent_max_length
      CHECK (payment_intent_id IS NULL OR length(payment_intent_id) <= 200);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE booking_services
    ADD CONSTRAINT bs_service_name_max_length
      CHECK (service_name IS NULL OR length(service_name) <= 200),
    ADD CONSTRAINT bs_worker_name_max_length
      CHECK (worker_name IS NULL OR length(worker_name) <= 200),
    ADD CONSTRAINT bs_special_req_max_length
      CHECK (special_requirements IS NULL OR length(special_requirements) <= 1000);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── 2. Distinct-worker constraint for group bookings ─────────
-- Same worker cannot occupy two seats at the same instant on the
-- same slot. Partial unique index keeps NULL worker_id rows
-- (services that don't require worker selection) unconstrained.

CREATE UNIQUE INDEX IF NOT EXISTS idx_bs_unique_worker_per_start
  ON booking_services (slot_id, worker_id, start_time)
  WHERE worker_id IS NOT NULL AND start_time IS NOT NULL;

-- ── 3. Audit log ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS booking_audit_log (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  action       TEXT NOT NULL,          -- e.g. 'booking.create', 'booking.cancel', 'booking.complete', 'booking.no_show'
  target_table TEXT NOT NULL,
  target_id    UUID NOT NULL,
  details      JSONB NOT NULL DEFAULT '{}',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_booking_audit_actor  ON booking_audit_log (actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_booking_audit_target ON booking_audit_log (target_table, target_id);

ALTER TABLE booking_audit_log ENABLE ROW LEVEL SECURITY;
-- No direct client access; only RPCs write.

-- ── 4. Hardened mutating RPCs ────────────────────────────────

-- 4a. create_booking_transaction — re-declared with the same
-- signature, adding rate limit + length checks + audit. Behavior
-- otherwise identical to the Phase A version. CREATE OR REPLACE
-- wins because parameter types and order are unchanged.

CREATE OR REPLACE FUNCTION create_booking_transaction(
  p_booking          JSONB,
  p_services         JSONB,
  p_idempotency_key  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      UUID;
  v_shop_id      UUID;
  v_booking_id   UUID;
  v_existing     UUID;
  v_service      JSONB;
  v_worker_id    UUID;
  v_start        TIMESTAMPTZ;
  v_end          TIMESTAMPTZ;
  v_result       JSONB;
  v_address      TEXT;
  v_special      TEXT;
  v_svc_count    INT;
  v_worker_seen  UUID[];
  v_iter_worker  UUID;
BEGIN
  -- Replay before charging the rate-limit budget.
  IF p_idempotency_key IS NOT NULL AND length(p_idempotency_key) > 0 THEN
    SELECT booking_id INTO v_existing
    FROM   idempotency_keys
    WHERE  key = p_idempotency_key
      AND  expires_at > now();
    IF v_existing IS NOT NULL THEN
      SELECT to_jsonb(b.*) INTO v_result FROM bookings b WHERE b.id = v_existing;
      RETURN v_result;
    END IF;
  END IF;

  PERFORM check_rate_limit('create_booking', 10, 60);

  v_user_id := (p_booking->>'user_id')::UUID;
  v_shop_id := (p_booking->>'shop_id')::UUID;

  IF v_user_id IS NULL OR v_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: user mismatch' USING ERRCODE = '42501';
  END IF;
  IF v_shop_id IS NULL THEN
    RAISE EXCEPTION 'shop_id is required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_services) <> 'array' OR jsonb_array_length(p_services) = 0 THEN
    RAISE EXCEPTION 'services must be a non-empty array' USING ERRCODE = '22023';
  END IF;
  v_svc_count := jsonb_array_length(p_services);
  IF v_svc_count > 50 THEN
    RAISE EXCEPTION 'too many services in one booking (max 50)' USING ERRCODE = '22023';
  END IF;

  -- Length caps on free-text inputs (defense in depth — table
  -- CHECKs would catch this too, but earlier failure is friendlier).
  v_address := NULLIF(p_booking->>'address','');
  IF v_address IS NOT NULL AND length(v_address) > 500 THEN
    RAISE EXCEPTION 'address too long' USING ERRCODE = '22023';
  END IF;

  -- Distinct-worker check within this booking.
  v_worker_seen := ARRAY[]::UUID[];
  FOR v_service IN SELECT value FROM jsonb_array_elements(p_services) LOOP
    v_iter_worker := NULLIF(v_service->>'worker_id','')::UUID;
    IF v_iter_worker IS NOT NULL THEN
      IF v_iter_worker = ANY (v_worker_seen) THEN
        RAISE EXCEPTION 'worker_id: % assigned to multiple seats in the same booking', v_iter_worker
          USING ERRCODE = '23505';
      END IF;
      v_worker_seen := v_worker_seen || v_iter_worker;
    END IF;
    v_special := NULLIF(v_service->>'special_requirements','');
    IF v_special IS NOT NULL AND length(v_special) > 1000 THEN
      RAISE EXCEPTION 'special_requirements too long' USING ERRCODE = '22023';
    END IF;
  END LOOP;

  -- Worker conflict lock (same as Phase A; not duplicated above).
  FOR v_service IN
    SELECT value
    FROM   jsonb_array_elements(p_services)
    ORDER BY (value->>'slot_id')::uuid,
             COALESCE((value->>'worker_id')::uuid::text, '00000000-0000-0000-0000-000000000000'),
             (value->>'start_time')
  LOOP
    v_worker_id := NULLIF(v_service->>'worker_id','')::UUID;
    v_start     := (v_service->>'start_time')::TIMESTAMPTZ;
    v_end       := COALESCE(
      (v_service->>'end_time')::TIMESTAMPTZ,
      v_start + ((v_service->>'duration_minutes')::INT || ' minutes')::INTERVAL
    );

    IF v_worker_id IS NOT NULL THEN
      PERFORM 1
      FROM   booking_services bs
      JOIN   bookings b ON b.id = bs.booking_id
      WHERE  bs.worker_id = v_worker_id
        AND  b.status NOT IN ('cancelled','no_show')
        AND  tstzrange(bs.start_time, COALESCE(bs.end_time, bs.start_time + (bs.duration_minutes||' minutes')::INTERVAL), '[)')
             && tstzrange(v_start, v_end, '[)')
      FOR UPDATE OF bs;

      IF FOUND THEN
        RAISE EXCEPTION 'worker_id: % unavailable at time: %',
          v_worker_id, v_start
          USING ERRCODE = '23505';
      END IF;
    END IF;
  END LOOP;

  -- Insert booking.
  INSERT INTO bookings (
    id, user_id, shop_id, booking_date,
    start_time, end_time, actual_end_time,
    status, total_amount, deposit_amount, platform_fee,
    payment_method, payment_status, payment_intent_id,
    address, latitude, longitude,
    created_at, updated_at
  ) VALUES (
    COALESCE(NULLIF(p_booking->>'id','')::UUID, gen_random_uuid()),
    v_user_id,
    v_shop_id,
    (p_booking->>'booking_date')::TIMESTAMPTZ,
    (p_booking->>'start_time')::TIMESTAMPTZ,
    (p_booking->>'end_time')::TIMESTAMPTZ,
    COALESCE((p_booking->>'actual_end_time')::TIMESTAMPTZ, (p_booking->>'end_time')::TIMESTAMPTZ),
    COALESCE(NULLIF(p_booking->>'status',''), 'pending'),
    COALESCE((p_booking->>'total_amount')::NUMERIC, 0),
    COALESCE((p_booking->>'deposit_amount')::NUMERIC, 0),
    NULLIF(p_booking->>'platform_fee','')::NUMERIC,
    NULLIF(p_booking->>'payment_method',''),
    COALESCE(NULLIF(p_booking->>'payment_status',''), 'unpaid'),
    NULLIF(p_booking->>'payment_intent_id',''),
    v_address,
    NULLIF(p_booking->>'latitude','')::DOUBLE PRECISION,
    NULLIF(p_booking->>'longitude','')::DOUBLE PRECISION,
    now(),
    now()
  )
  RETURNING id INTO v_booking_id;

  -- Insert booking_services.
  FOR v_service IN SELECT value FROM jsonb_array_elements(p_services) LOOP
    INSERT INTO booking_services (
      id, booking_id, slot_id, worker_id,
      service_name, worker_name,
      price_at_booking, duration_minutes,
      start_time, end_time, special_requirements
    ) VALUES (
      COALESCE(NULLIF(v_service->>'id','')::UUID, gen_random_uuid()),
      v_booking_id,
      (v_service->>'slot_id')::UUID,
      NULLIF(v_service->>'worker_id','')::UUID,
      NULLIF(v_service->>'service_name',''),
      NULLIF(v_service->>'worker_name',''),
      COALESCE((v_service->>'price_at_booking')::NUMERIC, 0),
      (v_service->>'duration_minutes')::INT,
      NULLIF(v_service->>'start_time','')::TIMESTAMPTZ,
      COALESCE(
        NULLIF(v_service->>'end_time','')::TIMESTAMPTZ,
        NULLIF(v_service->>'start_time','')::TIMESTAMPTZ
          + ((v_service->>'duration_minutes')::INT || ' minutes')::INTERVAL
      ),
      NULLIF(v_service->>'special_requirements','')
    );
  END LOOP;

  IF p_idempotency_key IS NOT NULL AND length(p_idempotency_key) > 0 THEN
    INSERT INTO idempotency_keys (key, booking_id)
    VALUES (p_idempotency_key, v_booking_id)
    ON CONFLICT (key) DO NOTHING;
  END IF;

  INSERT INTO booking_audit_log (actor_id, action, target_table, target_id, details)
  VALUES (
    v_user_id, 'booking.create', 'bookings', v_booking_id,
    jsonb_build_object('shop_id', v_shop_id, 'service_count', v_svc_count)
  );

  SELECT to_jsonb(b.*) INTO v_result FROM bookings b WHERE b.id = v_booking_id;
  RETURN v_result;
END;
$$;

-- 4b. create_booking_with_conflict_check — same signature, adds
-- rate limit + length cap + audit.

CREATE OR REPLACE FUNCTION create_booking_with_conflict_check(
  p_user_id            UUID,
  p_shop_id            UUID,
  p_slot_id            UUID,
  p_worker_id          UUID,
  p_booking_date       DATE,
  p_start_time         TIMESTAMPTZ,
  p_end_time           TIMESTAMPTZ,
  p_total_amount       NUMERIC,
  p_deposit_amount     NUMERIC,
  p_service_address    TEXT,
  p_service_latitude   DOUBLE PRECISION,
  p_service_longitude  DOUBLE PRECISION
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking_id UUID;
  v_duration   INT;
  v_price      NUMERIC;
  v_name       TEXT;
BEGIN
  IF p_user_id IS NULL OR p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: user mismatch' USING ERRCODE = '42501';
  END IF;
  IF p_end_time <= p_start_time THEN
    RAISE EXCEPTION 'end_time must be after start_time' USING ERRCODE = '22023';
  END IF;
  IF p_service_address IS NOT NULL AND length(p_service_address) > 500 THEN
    RAISE EXCEPTION 'service_address too long' USING ERRCODE = '22023';
  END IF;
  IF p_service_latitude IS NOT NULL
     AND (p_service_latitude < -90 OR p_service_latitude > 90) THEN
    RAISE EXCEPTION 'invalid latitude' USING ERRCODE = '22023';
  END IF;
  IF p_service_longitude IS NOT NULL
     AND (p_service_longitude < -180 OR p_service_longitude > 180) THEN
    RAISE EXCEPTION 'invalid longitude' USING ERRCODE = '22023';
  END IF;

  PERFORM check_rate_limit('create_booking', 10, 60);

  PERFORM 1
  FROM   bookings b
  WHERE  b.shop_id = p_shop_id
    AND  b.status NOT IN ('cancelled','no_show')
    AND  tstzrange(b.start_time, b.end_time, '[)') && tstzrange(p_start_time, p_end_time, '[)')
  FOR UPDATE OF b;

  IF FOUND THEN
    RAISE EXCEPTION 'SLOT_CONFLICT: % overlaps existing booking', p_start_time
      USING ERRCODE = '23505';
  END IF;

  SELECT service_name, price
    INTO v_name, v_price
  FROM   appointment_slots
  WHERE  id = p_slot_id;

  v_duration := GREATEST(1, EXTRACT(EPOCH FROM (p_end_time - p_start_time))::INT / 60);

  INSERT INTO bookings (
    id, user_id, shop_id, booking_date,
    start_time, end_time, actual_end_time,
    status, total_amount, deposit_amount,
    payment_status, address, latitude, longitude,
    created_at, updated_at
  ) VALUES (
    gen_random_uuid(), p_user_id, p_shop_id, p_booking_date::TIMESTAMPTZ,
    p_start_time, p_end_time, p_end_time,
    'confirmed', COALESCE(p_total_amount, COALESCE(v_price,0)),
    COALESCE(p_deposit_amount, 0),
    'unpaid', NULLIF(p_service_address,''),
    p_service_latitude, p_service_longitude,
    now(), now()
  )
  RETURNING id INTO v_booking_id;

  INSERT INTO booking_services (
    id, booking_id, slot_id, worker_id,
    service_name, price_at_booking, duration_minutes,
    start_time, end_time
  ) VALUES (
    gen_random_uuid(), v_booking_id, p_slot_id, p_worker_id,
    v_name, COALESCE(v_price, 0), v_duration,
    p_start_time, p_end_time
  );

  INSERT INTO booking_audit_log (actor_id, action, target_table, target_id, details)
  VALUES (
    p_user_id, 'booking.create', 'bookings', v_booking_id,
    jsonb_build_object('shop_id', p_shop_id, 'kind', 'freelancer')
  );

  RETURN v_booking_id::TEXT;
END;
$$;

-- 4c. cancel_booking — new RPC enforcing the state machine and
-- ownership rules. Replaces the raw UPDATE path the Dart code
-- currently uses; the repository will be migrated in Phase C.

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

  SELECT to_jsonb(b.*) INTO v_result FROM bookings b WHERE b.id = p_booking_id;
  RETURN v_result;
END;
$$;

-- 4d. mark_booking_complete — shop-owner only, only from
-- confirmed (or already completed for idempotency).

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
  END IF;

  SELECT to_jsonb(b.*) INTO v_result FROM bookings b WHERE b.id = p_booking_id;
  RETURN v_result;
END;
$$;

-- 4e. mark_booking_no_show — shop-owner only, only after the
-- booking's scheduled start time. (Don't no-show a future booking.)

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
  END IF;

  SELECT to_jsonb(b.*) INTO v_result FROM bookings b WHERE b.id = p_booking_id;
  RETURN v_result;
END;
$$;

-- 4f. update_special_requirements — RPC wrapper so we can enforce
-- length cap centrally and audit who edited what. The previous
-- code path went through the booking_services UPDATE RLS policy
-- defined in Phase A; that policy remains in place so existing
-- callers keep working, but new callers should prefer this RPC.

CREATE OR REPLACE FUNCTION update_special_requirements(
  p_booking_service_id UUID,
  p_requirements       TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking_id UUID;
  v_owner      UUID;
BEGIN
  PERFORM check_rate_limit('update_special_requirements', 30, 60);

  IF p_requirements IS NOT NULL AND length(p_requirements) > 1000 THEN
    RAISE EXCEPTION 'special_requirements too long' USING ERRCODE = '22023';
  END IF;

  SELECT bs.booking_id, b.user_id
    INTO v_booking_id, v_owner
  FROM   booking_services bs
  JOIN   bookings b ON b.id = bs.booking_id
  WHERE  bs.id = p_booking_service_id;

  IF v_booking_id IS NULL THEN
    RAISE EXCEPTION 'booking_service % not found', p_booking_service_id USING ERRCODE = 'P0002';
  END IF;
  IF v_owner IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: not the booking owner' USING ERRCODE = '42501';
  END IF;

  UPDATE booking_services
  SET    special_requirements = NULLIF(trim(coalesce(p_requirements, '')), '')
  WHERE  id = p_booking_service_id;

  INSERT INTO booking_audit_log (actor_id, action, target_table, target_id, details)
  VALUES (auth.uid(), 'booking_service.special_requirements.update',
          'booking_services', p_booking_service_id,
          jsonb_build_object('booking_id', v_booking_id));
END;
$$;

-- ── 5. Grants ────────────────────────────────────────────────

REVOKE ALL ON FUNCTION cancel_booking(UUID, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION cancel_booking(UUID, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION mark_booking_complete(UUID) FROM public;
GRANT EXECUTE ON FUNCTION mark_booking_complete(UUID) TO authenticated;

REVOKE ALL ON FUNCTION mark_booking_no_show(UUID) FROM public;
GRANT EXECUTE ON FUNCTION mark_booking_no_show(UUID) TO authenticated;

REVOKE ALL ON FUNCTION update_special_requirements(UUID, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION update_special_requirements(UUID, TEXT) TO authenticated;

-- ============================================================
-- End of booking hardening migration.
-- ============================================================
