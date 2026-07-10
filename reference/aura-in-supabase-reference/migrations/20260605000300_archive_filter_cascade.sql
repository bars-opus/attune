-- Archive filter cascade: patches the three live booking-pipeline RPCs
-- to honor appointment_slots.archived_at IS NULL. Without this, the
-- archive_appointment_slot RPC (20260605000200) is cosmetic — picker
-- queries still surface archived rows and the create RPCs still book
-- against them.
--
-- HIGHEST-RISK DELTA IN PHASE 11. Recreates three functions that are
-- currently running in production. Each body is copied verbatim from
-- its latest CREATE OR REPLACE source in the migration history; the
-- only changes are:
--   * `AND archived_at IS NULL` added to the appointment_slots lookup
--   * `IF v_name IS NULL THEN RAISE EXCEPTION 'archived_slot' …` raise
--     inserted between the SELECT and any subsequent state change, to
--     prevent the function from booking against an archived row.
--
-- Surface inventory (verified 2026-06-04):
--   1. create_booking_with_conflict_check — LIVE version is in
--      20260517020000_booking_hardening.sql:279-378. The earlier
--      version in 20260517010000_booking_schema.sql:494 was
--      superseded; only the hardening version runs in prod.
--   2. check_slot_availability — single version in
--      20260517010000_booking_schema.sql:591-649.
--   3. generate_available_slots — LIVE version is in
--      20260525040000_fix_generate_slots_preselected_direct.sql:18-169.
--      Earlier versions in 010000 and 020525020000 were superseded;
--      only the preselected_direct variant runs in prod.
--
-- The edge function resolve-link/index.ts:125 ships in the same
-- release (separate file, not in this migration).
--
-- Locked correction 4 (from Phase 11 RESEARCH Finding 3): cascade
-- must cover BOTH read paths (check_slot_availability,
-- generate_available_slots) AND create paths
-- (create_booking_with_conflict_check). Without write-side checks, a
-- deep-link race lets a customer book an archived slot.

-- ────────────────────────────────────────────────────────────────────
-- Surface 1 — create_booking_with_conflict_check (LIVE, hardened)
-- ────────────────────────────────────────────────────────────────────
-- Lifted from 20260517020000_booking_hardening.sql:279-378 verbatim.
-- One-line additions:
--   * line ~338 of original: `AND archived_at IS NULL` on the
--     appointment_slots SELECT
--   * post-SELECT: `IF v_name IS NULL THEN RAISE 'archived_slot'`

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

  -- Phase 11 archive filter: archived slots cannot be booked.
  SELECT service_name, price
    INTO v_name, v_price
  FROM   appointment_slots
  WHERE  id = p_slot_id
    AND  archived_at IS NULL;

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'archived_slot'
      USING ERRCODE = 'P0001', HINT = 'SLOT_ARCHIVED';
  END IF;

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

COMMENT ON FUNCTION create_booking_with_conflict_check(UUID,UUID,UUID,UUID,DATE,TIMESTAMPTZ,TIMESTAMPTZ,NUMERIC,NUMERIC,TEXT,DOUBLE PRECISION,DOUBLE PRECISION) IS
  'Phase 11: archived_at IS NULL filter added on appointment_slots lookup. Raises archived_slot (P0001/SLOT_ARCHIVED) before any INSERT if the slot has been archived since the customer opened the picker.';

-- ────────────────────────────────────────────────────────────────────
-- Surface 2 — check_slot_availability
-- ────────────────────────────────────────────────────────────────────
-- Lifted from 20260517010000_booking_schema.sql:591-649 verbatim.
-- One-line additions:
--   * `AND archived_at IS NULL` on the appointment_slots SELECT
--   * post-SELECT IF NOT FOUND clause returns {available:false, reason:'archived'}

CREATE OR REPLACE FUNCTION check_slot_availability(
  p_shop_id    UUID,
  p_slot_id    UUID,
  p_worker_id  UUID,
  p_start_time TIMESTAMPTZ,
  p_end_time   TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
  v_slot_type TEXT;
  v_max_clients INT;
BEGIN
  IF p_end_time <= p_start_time THEN
    RETURN jsonb_build_object('available', false, 'reason', 'invalid_range');
  END IF;

  -- Worker conflict if a worker was requested.
  IF p_worker_id IS NOT NULL THEN
    SELECT count(*) INTO v_count
    FROM   booking_services bs
    JOIN   bookings b ON b.id = bs.booking_id
    WHERE  bs.worker_id = p_worker_id
      AND  b.status NOT IN ('cancelled','no_show')
      AND  tstzrange(bs.start_time, COALESCE(bs.end_time, bs.start_time + (bs.duration_minutes||' minutes')::INTERVAL), '[)')
           && tstzrange(p_start_time, p_end_time, '[)');

    IF v_count > 0 THEN
      RETURN jsonb_build_object('available', false, 'reason', 'worker_busy');
    END IF;
  END IF;

  -- Group-slot capacity check.
  -- Phase 11 archive filter: archived slots report as unavailable.
  SELECT slot_type, COALESCE(max_clients, 1)
    INTO v_slot_type, v_max_clients
  FROM   appointment_slots
  WHERE  id = p_slot_id
    AND  archived_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('available', false, 'reason', 'archived');
  END IF;

  IF v_slot_type = 'group' THEN
    SELECT count(*) INTO v_count
    FROM   booking_services bs
    JOIN   bookings b ON b.id = bs.booking_id
    WHERE  bs.slot_id = p_slot_id
      AND  b.status NOT IN ('cancelled','no_show')
      AND  bs.start_time = p_start_time;

    IF v_count >= v_max_clients THEN
      RETURN jsonb_build_object('available', false, 'reason', 'slot_full');
    END IF;
  END IF;

  RETURN jsonb_build_object('available', true);
END;
$$;

COMMENT ON FUNCTION check_slot_availability(UUID,UUID,UUID,TIMESTAMPTZ,TIMESTAMPTZ) IS
  'Phase 11: archived_at IS NULL filter added on appointment_slots lookup. Returns {available:false, reason:archived} for archived slots so the picker UX stays honest.';

-- ────────────────────────────────────────────────────────────────────
-- Surface 3 — generate_available_slots (LIVE, preselected_direct)
-- ────────────────────────────────────────────────────────────────────
-- Lifted from 20260525040000_fix_generate_slots_preselected_direct.sql:18-169
-- verbatim. Only change is `AND s.archived_at IS NULL` on the
-- appointment_slots SELECT around line 83 of original. The existing
-- `IF NOT FOUND THEN CONTINUE;` already handles the archived-row skip
-- so the SETOF result simply omits archived slots — no behavior
-- regression for non-archived rows.

CREATE OR REPLACE FUNCTION generate_available_slots(
  p_shop_id                 UUID,
  p_date                    DATE,
  p_service_ids             UUID[],
  p_quantities              INT[],
  p_selected_worker_ids     UUID[] DEFAULT NULL,
  p_default_buffer_minutes  INT    DEFAULT NULL
)
RETURNS TABLE (
  slot_id                    UUID,
  service_name               TEXT,
  start_time                 TIMESTAMPTZ,
  end_time                   TIMESTAMPTZ,
  actual_end_time            TIMESTAMPTZ,
  price                      NUMERIC,
  available_workers          JSONB,
  remaining_spots            INT,
  requires_worker_selection  BOOLEAN,
  buffer_minutes             INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dow         INT;
  v_opens       TIME;
  v_closes      TIME;
  v_closed      BOOLEAN;
  v_svc         RECORD;
  v_svc_id      UUID;
  v_qty         INT;
  v_t           TIMESTAMPTZ;
  v_end         TIMESTAMPTZ;
  v_actual_end  TIMESTAMPTZ;
  v_buffer      INT;
  v_workers     JSONB;
  v_capacity    INT;
  v_taken       INT;
  v_dur_min     INT;
  v_i           INT;
  v_use_selected BOOLEAN;
BEGIN
  v_use_selected := (p_selected_worker_ids IS NOT NULL
                     AND cardinality(p_selected_worker_ids) > 0);

  v_dow := EXTRACT(DOW FROM p_date)::INT;
  SELECT opens_at, closes_at, COALESCE(is_closed, false)
    INTO v_opens, v_closes, v_closed
  FROM   shop_opening_hours
  WHERE  shop_id = p_shop_id AND day_of_week = v_dow
  LIMIT  1;

  IF NOT FOUND OR v_closed THEN
    RETURN;
  END IF;

  v_i := 1;
  FOREACH v_svc_id IN ARRAY p_service_ids LOOP
    v_qty := COALESCE(p_quantities[v_i], 1);
    v_i   := v_i + 1;

    -- Phase 11 archive filter: skip archived services entirely.
    SELECT s.* INTO v_svc
    FROM   appointment_slots s
    WHERE  s.id = v_svc_id
      AND  s.archived_at IS NULL;

    IF NOT FOUND THEN CONTINUE; END IF;

    v_buffer  := COALESCE(v_svc.buffer_minutes, p_default_buffer_minutes, 0);
    v_dur_min := extract_duration_minutes(v_svc.duration);

    v_t := (p_date + v_opens)::TIMESTAMPTZ;
    WHILE v_t::TIME <= v_closes - (v_dur_min || ' minutes')::INTERVAL LOOP
      v_end        := v_t + (v_dur_min || ' minutes')::INTERVAL;
      v_actual_end := v_end + (v_buffer || ' minutes')::INTERVAL;

      IF v_use_selected THEN
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id',                w.id,
          'name',              w.name,
          'bio',               w.bio,
          'profile_image_url', w.profile_image_url,
          'specialties',       COALESCE(w.specialties, ARRAY[]::TEXT[]),
          'rating_average',    NULL,
          'is_active',         w.is_active
        )), '[]'::jsonb) INTO v_workers
        FROM workers w
        WHERE w.id = ANY(p_selected_worker_ids)
          AND COALESCE(w.is_active, true) = true;
      ELSE
        SELECT COALESCE(jsonb_agg(w), '[]'::jsonb) INTO v_workers
        FROM (
          SELECT * FROM get_available_workers(
            ARRAY(
              SELECT swa.worker_id
              FROM   slot_worker_assignments swa
              WHERE  swa.slot_id = v_svc.id
            ),
            v_t, v_end
          ) AS w
        ) AS w;
      END IF;

      IF v_svc.slot_type = 'group' THEN
        SELECT count(*) INTO v_taken
        FROM   booking_services bs
        JOIN   bookings b ON b.id = bs.booking_id
        WHERE  bs.slot_id = v_svc.id
          AND  bs.start_time = v_t
          AND  b.status NOT IN ('cancelled', 'no_show');

        v_capacity := COALESCE(v_svc.max_clients, 1);
        IF v_capacity - v_taken >= v_qty THEN
          slot_id                   := v_svc.id;
          service_name              := v_svc.service_name;
          start_time                := v_t;
          end_time                  := v_end;
          actual_end_time           := v_actual_end;
          price                     := COALESCE(v_svc.price, 0);
          available_workers         := v_workers;
          remaining_spots           := v_capacity - v_taken;
          requires_worker_selection := COALESCE(v_svc.select_preferred_worker, false);
          buffer_minutes            := v_buffer;
          RETURN NEXT;
        END IF;
      ELSE
        IF jsonb_array_length(v_workers) > 0
           OR COALESCE(v_svc.select_preferred_worker, false) = false THEN
          slot_id                   := v_svc.id;
          service_name              := v_svc.service_name;
          start_time                := v_t;
          end_time                  := v_end;
          actual_end_time           := v_actual_end;
          price                     := COALESCE(v_svc.price, 0);
          available_workers         := v_workers;
          remaining_spots           := NULL;
          requires_worker_selection := COALESCE(v_svc.select_preferred_worker, false);
          buffer_minutes            := v_buffer;
          RETURN NEXT;
        END IF;
      END IF;

      v_t := v_t + INTERVAL '15 minutes';
    END LOOP;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION generate_available_slots(UUID, DATE, UUID[], INT[], UUID[], INT) FROM public;
GRANT EXECUTE ON FUNCTION generate_available_slots(UUID, DATE, UUID[], INT[], UUID[], INT) TO authenticated;

COMMENT ON FUNCTION generate_available_slots(UUID, DATE, UUID[], INT[], UUID[], INT) IS
  'Phase 11: archived_at IS NULL filter added on appointment_slots lookup. Archived services are silently skipped from the SETOF result via the existing IF NOT FOUND THEN CONTINUE branch.';
