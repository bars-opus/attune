-- ============================================================
-- Booking Schema (canonical foundation)
-- ============================================================
-- Establishes the booking domain in version control. Many of the
-- objects here likely already exist on the production database;
-- this migration is written to be idempotent so it can be applied
-- either to a fresh project or as a "lock-in" against an existing
-- one without dropping data.
--
-- Scope (Phase A):
--   1. Core tables: bookings, booking_services, idempotency_keys.
--   2. CHECK constraints for data integrity (status enum,
--      positive amounts, time ordering, coordinate plausibility).
--   3. Indexes for the access patterns the Dart code uses today
--      (booking_simple view filtering by user/shop/date/status).
--   4. RLS policies — clients see only their bookings, shop owners
--      see only their shop's bookings, workers see only their
--      assigned services. The `bookings` row is the authoritative
--      gate; `booking_services` inherits via FK.
--   5. `booking_simple` denormalized view used by the repository
--      for client/shop calendar queries.
--   6. Idempotency key TTL: 24 h, with a prune function.
--   7. Atomic RPCs that the client already calls:
--        - create_booking_transaction
--        - create_booking_with_conflict_check
--        - check_slot_availability
--        - get_available_workers
--        - generate_available_slots (basic; refined in later phase)
--        - check_shop_hours
--
-- NOT in scope (Phase A): rate limiting, status state machine,
-- length CHECK caps on free-text columns, audit log, distinct-
-- worker constraint, coordinate sanity in RPC layer. Those land
-- in the booking_hardening migration so this file stays a clean
-- "schema-only" baseline reviewers can verify quickly.
-- ============================================================

-- ── 1. Core tables ────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS bookings (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  shop_id             UUID NOT NULL,
  booking_date        TIMESTAMPTZ NOT NULL,
  start_time          TIMESTAMPTZ NOT NULL,
  end_time            TIMESTAMPTZ NOT NULL,
  actual_end_time     TIMESTAMPTZ NOT NULL,
  status              TEXT NOT NULL DEFAULT 'pending',
  total_amount        NUMERIC(12,2) NOT NULL,
  deposit_amount      NUMERIC(12,2) NOT NULL DEFAULT 0,
  platform_fee        NUMERIC(12,2),
  payment_method      TEXT,
  payment_status      TEXT NOT NULL DEFAULT 'unpaid',
  payment_intent_id   TEXT,
  cancellation_reason TEXT,
  cancelled_at        TIMESTAMPTZ,
  -- Service-delivery location for freelancers / mobile services.
  -- For shop-bookings these stay NULL because the shop has its
  -- own canonical location in shop_locations.
  address             TEXT,
  latitude            DOUBLE PRECISION,
  longitude           DOUBLE PRECISION,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS booking_services (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id           UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  slot_id              UUID NOT NULL,
  worker_id            UUID,
  service_name         TEXT,
  worker_name          TEXT,
  price_at_booking     NUMERIC(12,2) NOT NULL,
  duration_minutes     INT NOT NULL,
  start_time           TIMESTAMPTZ,
  end_time             TIMESTAMPTZ,
  special_requirements TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Pre-existing idempotency key table. Stable schema; we only add
-- expiry on top so the table doesn't grow unbounded.
CREATE TABLE IF NOT EXISTS idempotency_keys (
  key         TEXT PRIMARY KEY,
  booking_id  UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '24 hours'
);

-- Add expires_at column if a previous (pre-hardening) version of
-- the table exists without it.
DO $$ BEGIN
  ALTER TABLE idempotency_keys
    ADD COLUMN expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '24 hours';
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- ── 1b. Backfill missing columns on pre-existing tables ──────────
-- These columns were added to the canonical schema above but the
-- remote tables may predate them.
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN address   TEXT;             EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN latitude  DOUBLE PRECISION; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN longitude DOUBLE PRECISION; EXCEPTION WHEN duplicate_column THEN NULL; END $$;

DO $$ BEGIN ALTER TABLE booking_services ADD COLUMN worker_name          TEXT;             EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE booking_services ADD COLUMN start_time           TIMESTAMPTZ;      EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE booking_services ADD COLUMN end_time             TIMESTAMPTZ;      EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE booking_services ADD COLUMN special_requirements TEXT;             EXCEPTION WHEN duplicate_column THEN NULL; END $$;

-- ── 2. Data integrity CHECK constraints ───────────────────────

DO $$ BEGIN
  ALTER TABLE bookings
    ADD CONSTRAINT bookings_status_valid CHECK (
      status IN ('pending','confirmed','cancelled','completed','no_show')
    ),
    ADD CONSTRAINT bookings_payment_status_valid CHECK (
      payment_status IN ('unpaid','paid','refunded','failed')
    ),
    ADD CONSTRAINT bookings_total_nonneg     CHECK (total_amount   >= 0),
    ADD CONSTRAINT bookings_deposit_nonneg   CHECK (deposit_amount >= 0),
    ADD CONSTRAINT bookings_deposit_lte_total CHECK (deposit_amount <= total_amount + 0.01),
    ADD CONSTRAINT bookings_end_after_start  CHECK (end_time > start_time),
    ADD CONSTRAINT bookings_actual_end_sane  CHECK (actual_end_time >= start_time),
    ADD CONSTRAINT bookings_lat_range        CHECK (latitude  IS NULL OR (latitude  BETWEEN  -90  AND  90)),
    ADD CONSTRAINT bookings_lng_range        CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180)),
    -- Reject (0,0) which is a common "uninitialized location" footgun.
    ADD CONSTRAINT bookings_coords_not_null_island CHECK (
      latitude IS NULL OR longitude IS NULL OR NOT (latitude = 0 AND longitude = 0)
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE booking_services
    ADD CONSTRAINT bs_price_nonneg     CHECK (price_at_booking >= 0),
    ADD CONSTRAINT bs_duration_pos     CHECK (duration_minutes > 0),
    ADD CONSTRAINT bs_end_after_start  CHECK (
      end_time IS NULL OR start_time IS NULL OR end_time > start_time
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── 3. Indexes (matched to query patterns) ────────────────────

CREATE INDEX IF NOT EXISTS idx_bookings_user_id          ON bookings (user_id, start_time DESC);
CREATE INDEX IF NOT EXISTS idx_bookings_shop_id          ON bookings (shop_id, start_time DESC);
CREATE INDEX IF NOT EXISTS idx_bookings_status           ON bookings (status);
CREATE INDEX IF NOT EXISTS idx_bookings_booking_date     ON bookings (booking_date);
CREATE INDEX IF NOT EXISTS idx_bookings_created_at       ON bookings (created_at DESC);
-- Composite for the calendar range query (shop_id + date range +
-- status filter) — the dashboard's hottest path.
CREATE INDEX IF NOT EXISTS idx_bookings_shop_date_status
  ON bookings (shop_id, booking_date, status);

CREATE INDEX IF NOT EXISTS idx_booking_services_booking_id  ON booking_services (booking_id);
CREATE INDEX IF NOT EXISTS idx_booking_services_slot_id     ON booking_services (slot_id);
CREATE INDEX IF NOT EXISTS idx_booking_services_worker_id   ON booking_services (worker_id);
-- Worker conflict-check uses (worker_id, start_time, end_time).
CREATE INDEX IF NOT EXISTS idx_booking_services_worker_time ON booking_services (worker_id, start_time, end_time);

CREATE INDEX IF NOT EXISTS idx_idempotency_keys_expires ON idempotency_keys (expires_at);

-- ── 4. Row-level security ─────────────────────────────────────

ALTER TABLE bookings         ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE idempotency_keys ENABLE ROW LEVEL SECURITY;

-- Bookings: clients read their own; shop owners read theirs.
-- (Workers can read services they're assigned to via the
-- booking_services policy below — they don't need access to the
-- parent booking row.)
DROP POLICY IF EXISTS bookings_client_select ON bookings;
CREATE POLICY bookings_client_select ON bookings
  FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS bookings_shop_owner_select ON bookings;
CREATE POLICY bookings_shop_owner_select ON bookings
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM shops s WHERE s.id = bookings.shop_id AND s.user_id = auth.uid()
    )
  );

-- INSERT/UPDATE/DELETE go through SECURITY DEFINER RPCs only.
-- No direct write policies are granted on bookings.

-- booking_services: same visibility as parent booking, plus
-- assigned worker can read their own rows. Workers are linked
-- through the `workers.user_id` column (auth user that owns the
-- worker profile).
DROP POLICY IF EXISTS booking_services_client_select ON booking_services;
CREATE POLICY booking_services_client_select ON booking_services
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM bookings b
      WHERE b.id = booking_services.booking_id
        AND b.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS booking_services_shop_owner_select ON booking_services;
CREATE POLICY booking_services_shop_owner_select ON booking_services
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM bookings b
      JOIN   shops s ON s.id = b.shop_id
      WHERE  b.id = booking_services.booking_id
        AND  s.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS booking_services_worker_select ON booking_services;
CREATE POLICY booking_services_worker_select ON booking_services
  FOR SELECT
  USING (
    booking_services.worker_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM workers w
      WHERE w.id = booking_services.worker_id
        AND w.user_id = auth.uid()
    )
  );

-- Allow the owning client to PATCH free-text fields on their own
-- service rows (special_requirements only). Used by the post-
-- booking "add notes" flow.
DROP POLICY IF EXISTS booking_services_client_update_notes ON booking_services;
CREATE POLICY booking_services_client_update_notes ON booking_services
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM bookings b
      WHERE b.id = booking_services.booking_id
        AND b.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM bookings b
      WHERE b.id = booking_services.booking_id
        AND b.user_id = auth.uid()
    )
  );

-- idempotency_keys: no direct client access. Only RPCs read/write.

-- ── 5. booking_simple denormalized view ───────────────────────
-- The repository's calendar queries join bookings + shop + client
-- + appointment_slots on every call. The view collapses that into
-- a single row per (booking, service) so pagination + filtering
-- stays in the database.

DROP VIEW IF EXISTS booking_simple;
CREATE OR REPLACE VIEW booking_simple AS
SELECT
  bs.id                              AS service_id,
  bs.slot_id,
  bs.service_name,
  bs.worker_id,
  bs.worker_name,
  bs.price_at_booking,
  bs.duration_minutes,
  bs.start_time                      AS service_start_time,
  bs.end_time                        AS service_end_time,
  bs.special_requirements,

  b.id                               AS booking_id,
  b.user_id,
  b.shop_id,
  b.booking_date,
  b.start_time,
  b.end_time,
  b.actual_end_time,
  b.status,
  b.total_amount,
  b.deposit_amount,
  b.platform_fee,
  b.payment_method,
  b.payment_status,
  b.payment_intent_id,
  b.cancellation_reason,
  b.cancelled_at,
  b.address,
  b.latitude,
  b.longitude,
  b.created_at                       AS booking_created_at,
  b.updated_at                       AS booking_updated_at,

  -- Shop summary (small, denormalized)
  s.shop_name,
  s.shop_type,
  s.currency,
  s.shop_logo_url,

  -- Client summary
  p.display_name                     AS client_display_name,
  p.username                         AS client_username,
  p.avatar_url                       AS client_avatar_url
FROM booking_services bs
JOIN bookings b ON b.id = bs.booking_id
LEFT JOIN shops    s ON s.id = b.shop_id
LEFT JOIN profiles p ON p.id = b.user_id;

-- Views inherit RLS from base tables, so client/shop scoping
-- continues to work transparently.

-- ── 6. Idempotency expiry ─────────────────────────────────────

CREATE OR REPLACE FUNCTION prune_booking_idempotency_keys()
RETURNS VOID LANGUAGE SQL AS $$
  DELETE FROM idempotency_keys WHERE expires_at < now();
$$;

-- ── 7. Atomic RPCs ────────────────────────────────────────────
-- Signatures preserved to match the Dart repository as-is. RPCs
-- run with SECURITY DEFINER so they can bypass RLS for the writes
-- they need to do, but each one re-asserts auth.uid() to ensure
-- the caller may only mutate rows that belong to them.

-- 7a. create_booking_transaction —----------------------------
-- Called from supabase_booking_repository.createBooking().
-- Accepts the BookingModel JSON as p_booking and the list of
-- BookingServiceModel JSON as p_services. Worker conflict
-- detection uses tsrange overlap with a SELECT … FOR UPDATE on
-- competing service rows to prevent the obvious race.

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
BEGIN
  -- Replay on duplicate idempotency key.
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

  -- AuthN: the booking row must belong to the caller.
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

  -- Lock conflicting worker rows in deterministic order; raise on
  -- any overlap to prevent double-booking the same worker.
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

  -- Insert parent row.
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
    NULLIF(p_booking->>'address',''),
    NULLIF(p_booking->>'latitude','')::DOUBLE PRECISION,
    NULLIF(p_booking->>'longitude','')::DOUBLE PRECISION,
    now(),
    now()
  )
  RETURNING id INTO v_booking_id;

  -- Insert child rows.
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

  -- Record idempotency key for replay.
  IF p_idempotency_key IS NOT NULL AND length(p_idempotency_key) > 0 THEN
    INSERT INTO idempotency_keys (key, booking_id)
    VALUES (p_idempotency_key, v_booking_id)
    ON CONFLICT (key) DO NOTHING;
  END IF;

  SELECT to_jsonb(b.*) INTO v_result FROM bookings b WHERE b.id = v_booking_id;
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION create_booking_transaction(JSONB, JSONB, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION create_booking_transaction(JSONB, JSONB, TEXT) TO authenticated;

-- 7b. create_booking_with_conflict_check —---------------------
-- Freelancer variant. Single slot, no worker, optional service
-- address. Returns the new booking_id as TEXT (matches existing
-- repository expectation).

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

  -- Conflict check: freelancer can only hold one booking per
  -- overlapping window.
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

  RETURN v_booking_id::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION create_booking_with_conflict_check(
  UUID, UUID, UUID, UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ,
  NUMERIC, NUMERIC, TEXT, DOUBLE PRECISION, DOUBLE PRECISION
) FROM public;
GRANT EXECUTE ON FUNCTION create_booking_with_conflict_check(
  UUID, UUID, UUID, UUID, DATE, TIMESTAMPTZ, TIMESTAMPTZ,
  NUMERIC, NUMERIC, TEXT, DOUBLE PRECISION, DOUBLE PRECISION
) TO authenticated;

-- 7c. check_slot_availability —--------------------------------
-- Returns {available: bool, reason: text} so callers don't have
-- to string-match exceptions for "why not".

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
  SELECT slot_type, COALESCE(max_clients, 1)
    INTO v_slot_type, v_max_clients
  FROM   appointment_slots
  WHERE  id = p_slot_id;

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

REVOKE ALL ON FUNCTION check_slot_availability(UUID, UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ) FROM public;
GRANT EXECUTE ON FUNCTION check_slot_availability(UUID, UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;

-- 7d. get_available_workers —----------------------------------
-- Given a candidate worker_id list and a target window, returns
-- the workers that are *not* booked anywhere in that window.

DROP FUNCTION IF EXISTS get_available_workers(UUID[], TIMESTAMPTZ, TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION get_available_workers(
  p_worker_ids UUID[],
  p_start_time TIMESTAMPTZ,
  p_end_time   TIMESTAMPTZ
)
RETURNS SETOF JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'id',                w.id,
    'shop_id',           w.shop_id,
    'name',              w.name,
    'bio',               w.bio,
    'profile_image_url', w.profile_image_url,
    'specialties',       COALESCE(w.specialties, ARRAY[]::TEXT[]),
    'rating_average',    w.rating_average,
    'is_active',         w.is_active
  )
  FROM   workers w
  WHERE  w.id = ANY (p_worker_ids)
    AND  COALESCE(w.is_active, true) = true
    AND  NOT EXISTS (
      SELECT 1
      FROM   booking_services bs
      JOIN   bookings b ON b.id = bs.booking_id
      WHERE  bs.worker_id = w.id
        AND  b.status NOT IN ('cancelled','no_show')
        AND  tstzrange(bs.start_time, COALESCE(bs.end_time, bs.start_time + (bs.duration_minutes||' minutes')::INTERVAL), '[)')
             && tstzrange(p_start_time, p_end_time, '[)')
    )
    AND  NOT EXISTS (
      SELECT 1
      FROM   worker_unavailability wu
      WHERE  wu.worker_id = w.id
        AND  tstzrange(wu.start_time, wu.end_time, '[)') && tstzrange(p_start_time, p_end_time, '[)')
    );
$$;

REVOKE ALL ON FUNCTION get_available_workers(UUID[], TIMESTAMPTZ, TIMESTAMPTZ) FROM public;
GRANT EXECUTE ON FUNCTION get_available_workers(UUID[], TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;

-- 7e. check_shop_hours —---------------------------------------
-- Returns true iff [p_start_time, p_end_time) falls within the
-- shop's published opening hours for that weekday. Used by the
-- repository's validateBooking() pre-flight.

CREATE OR REPLACE FUNCTION check_shop_hours(
  p_shop_id    UUID,
  p_start_time TIMESTAMPTZ,
  p_end_time   TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dow      INT;
  v_opens    TIME;
  v_closes   TIME;
  v_closed   BOOLEAN;
  v_local_s  TIME;
  v_local_e  TIME;
BEGIN
  v_dow := EXTRACT(DOW FROM p_start_time)::INT;
  SELECT opens_at, closes_at, COALESCE(is_closed, false)
    INTO v_opens, v_closes, v_closed
  FROM   shop_opening_hours
  WHERE  shop_id = p_shop_id AND day_of_week = v_dow
  LIMIT  1;

  IF NOT FOUND OR v_closed THEN
    RETURN FALSE;
  END IF;

  -- Cross-day bookings are not supported; we just compare the
  -- time-of-day portion.
  v_local_s := p_start_time::TIME;
  v_local_e := p_end_time::TIME;

  RETURN v_local_s >= v_opens AND v_local_e <= v_closes;
END;
$$;

REVOKE ALL ON FUNCTION check_shop_hours(UUID, TIMESTAMPTZ, TIMESTAMPTZ) FROM public;
GRANT EXECUTE ON FUNCTION check_shop_hours(UUID, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;

-- Helper: appointment_slots.duration is stored as TEXT (e.g.
-- "30 minutes", "1:00", "01:30:00"). Pull an integer minute count
-- out of it without depending on app-side parsing.
CREATE OR REPLACE FUNCTION extract_duration_minutes(p_duration TEXT)
RETURNS INT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_int INT;
  v_h   INT;
  v_m   INT;
  v_s   INT;
BEGIN
  IF p_duration IS NULL OR length(trim(p_duration)) = 0 THEN
    RETURN 60;
  END IF;

  -- "HH:MM" or "HH:MM:SS" (check this first; "1:30" should yield
  -- 90, not 1).
  IF position(':' IN p_duration) > 0 THEN
    BEGIN
      v_h := split_part(p_duration, ':', 1)::INT;
      v_m := split_part(p_duration, ':', 2)::INT;
      v_s := COALESCE(NULLIF(split_part(p_duration, ':', 3), ''), '0')::INT;
      RETURN v_h * 60 + v_m + (v_s / 60);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  -- "30 minutes", "30 min", "30"
  BEGIN
    v_int := (regexp_match(p_duration, '^\s*(\d+)\s*'))[1]::INT;
  EXCEPTION WHEN OTHERS THEN
    v_int := NULL;
  END;

  RETURN COALESCE(v_int, 60);
END;
$$;

REVOKE ALL ON FUNCTION extract_duration_minutes(TEXT) FROM public;
GRANT EXECUTE ON FUNCTION extract_duration_minutes(TEXT) TO authenticated;

-- 7f. generate_available_slots —-------------------------------
-- Baseline implementation. The previous bespoke version on the
-- production database is replaced here with a function that
-- returns the same row shape the Dart code already maps. It
-- pages through 15-minute intervals between opens_at and
-- closes_at, filtering out windows where any required worker is
-- busy. Group slots return remaining capacity instead of a
-- per-worker breakdown.
--
-- This is the "correct but conservative" version; later phases
-- can swap a more sophisticated allocator without changing the
-- signature.

DROP FUNCTION IF EXISTS generate_available_slots(UUID, DATE, UUID[], INT[], UUID[], INT);
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
BEGIN
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
    v_i := v_i + 1;

    SELECT s.* INTO v_svc
    FROM   appointment_slots s
    WHERE  s.id = v_svc_id;

    IF NOT FOUND THEN CONTINUE; END IF;

    v_buffer  := COALESCE(v_svc.buffer_minutes, p_default_buffer_minutes, 0);
    v_dur_min := extract_duration_minutes(v_svc.duration);

    v_t := (p_date + v_opens)::TIMESTAMPTZ;
    WHILE v_t::TIME <= v_closes - (v_dur_min || ' minutes')::INTERVAL LOOP
      v_end        := v_t + (v_dur_min || ' minutes')::INTERVAL;
      v_actual_end := v_end + (v_buffer || ' minutes')::INTERVAL;

      -- Workers available in this window. For group slots,
      -- requires_worker_selection follows the service config; for
      -- 1-on-1 it's always true.
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

      IF v_svc.slot_type = 'group' THEN
        SELECT count(*) INTO v_taken
        FROM   booking_services bs
        JOIN   bookings b ON b.id = bs.booking_id
        WHERE  bs.slot_id = v_svc.id
          AND  bs.start_time = v_t
          AND  b.status NOT IN ('cancelled','no_show');

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
        -- 1-on-1 / regular slot: need at least one available worker
        -- (or the service doesn't require a worker at all).
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

-- ============================================================
-- End of booking schema migration.
-- ============================================================
