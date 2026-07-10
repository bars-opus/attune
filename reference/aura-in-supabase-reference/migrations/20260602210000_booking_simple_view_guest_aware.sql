-- Rebuild booking_simple to include guest bookings.
--
-- The original view (added via Supabase dashboard) inner-joined profiles on
-- bookings.user_id, so every guest booking (user_id IS NULL) silently
-- vanished from:
--   * CalendarScreen for shop owners (uses getShopBookings)
--   * CalendarScreen for clients (uses getClientBookings) — guests never had
--     a user-side calendar anyway, this just means no regression there
--   * any other surface that reads booking_simple
--
-- LEFT JOIN profiles + COALESCE to bookings.guest_name / guest_phone keeps
-- the same column shape callers expect (client_display_name, client_username,
-- client_avatar_url) while surfacing guests as first-class rows.

-- DROP first because CREATE OR REPLACE VIEW cannot remove or reorder
-- columns, and the dashboard-edited shape may differ from ours.
DROP VIEW IF EXISTS booking_simple CASCADE;

CREATE VIEW booking_simple AS
SELECT
  b.id                          AS booking_id,
  b.shop_id                     AS shop_id,
  b.user_id                     AS user_id,
  b.guest_profile_id            AS guest_profile_id,
  b.start_time                  AS start_time,
  b.end_time                    AS end_time,
  b.actual_end_time             AS actual_end_time,
  b.booking_date                AS booking_date,
  b.status::text                AS status,
  b.payment_status::text        AS payment_status,
  b.payment_method              AS payment_method,
  b.total_amount                AS total_amount,
  b.deposit_amount              AS deposit_amount,
  b.platform_fee                AS platform_fee,
  b.payment_intent_id           AS payment_intent_id,
  b.cancellation_reason         AS cancellation_reason,
  b.cancelled_at                AS cancelled_at,
  b.created_at                  AS booking_created_at,
  b.updated_at                  AS booking_updated_at,
  b.created_at                  AS created_at,
  -- Client identity: prefer the profile (logged-in user), fall back to the
  -- guest snapshot on the booking row, then a generic label.
  COALESCE(p.display_name, b.guest_name, 'Guest')   AS client_display_name,
  COALESCE(p.username, NULL)                         AS client_username,
  COALESCE(p.avatar_url, NULL)                       AS client_avatar_url,
  -- Per-service join. NULL row when booking_services is empty (which
  -- shouldn't happen post-trigger-fix, but stays defensive).
  bs.id                         AS booking_service_id,
  bs.slot_id                    AS service_id,
  bs.service_name               AS service_name,
  bs.worker_id                  AS worker_id,
  bs.worker_name                AS worker_name,
  bs.price_at_booking           AS price_at_booking,
  bs.duration_minutes           AS duration_minutes,
  bs.start_time                 AS service_start_time
FROM bookings b
LEFT JOIN profiles p          ON p.id = b.user_id
LEFT JOIN booking_services bs ON bs.booking_id = b.id;

-- View inherits RLS from the underlying tables; no extra grants needed.
GRANT SELECT ON booking_simple TO authenticated, service_role;
