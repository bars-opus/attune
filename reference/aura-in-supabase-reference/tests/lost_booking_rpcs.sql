-- Manual psql smoke tests for the three lost-booking RPCs introduced
-- in 20260603002000_lost_booking_rpcs.sql.
--
-- pgTAP scaffolding deferred to a future testing-foundation phase.
-- Each snippet below is copy-paste runnable in Supabase Studio (or
-- psql against the staging database). Expected output is documented
-- inline as a SQL comment so a reviewer can verify the assertion
-- without re-deriving it.
--
-- Replace placeholder UUIDs with real values from your environment.

-- Required placeholders:
--   :owner_jwt_sub  → an auth.users.id that owns at least one shop
--   :other_jwt_sub  → an auth.users.id that does NOT own :shop_a
--   :shop_a         → a shop_id owned by :owner_jwt_sub
--   :shop_b         → a shop_id owned by :other_jwt_sub (or any other user)
--
-- The simplest way to impersonate a JWT in Studio is:
--   SET LOCAL "request.jwt.claims" = '{"sub":"<uuid>"}';
-- For raw psql sessions hitting Postgres directly, you can also:
--   SET LOCAL ROLE authenticated;
--   SET LOCAL "request.jwt.claims" = '...';

------------------------------------------------------------------------
-- Section 1. Index plan verification (Task 1.2)
------------------------------------------------------------------------
-- Goal: confirm the realistic access path is idx_bookings_shop_id
-- (shop_id, start_time DESC). SPEC claimed idx_bookings_shop_date_status
-- but that index is keyed on booking_date, not start_time.
-- Run against the largest seed shop available.

SET LOCAL "request.jwt.claims" = '{"sub":":owner_jwt_sub"}';

EXPLAIN ANALYZE
SELECT public.get_lost_booking_summary(':shop_a'::uuid, 7);

-- Expected: a plan node "Index Scan using idx_bookings_shop_id on bookings".
-- If you see "Seq Scan on bookings" on a shop with >50k terminal bookings,
-- STOP and add the partial covering index per RESEARCH §1 in a follow-up
-- migration. Do NOT add it speculatively.

EXPLAIN ANALYZE
SELECT public.get_lost_booking_weekly_series(':shop_a'::uuid, 12);

EXPLAIN ANALYZE
SELECT public.get_lost_booking_offenders(':shop_a'::uuid, 90, 2);

------------------------------------------------------------------------
-- Section 2. Authz isolation (P0-U check 1.4)
------------------------------------------------------------------------
-- Goal: a caller who doesn't own :shop_b gets 'not_found' (42501) — NOT
-- 'invalid_*' (22023) — proving authz runs before range validation.

SET LOCAL "request.jwt.claims" = '{"sub":":owner_jwt_sub"}';
-- :owner_jwt_sub does NOT own :shop_b. Expect: P0001 / 42501 'not_found'.
SELECT public.get_lost_booking_summary(':shop_b'::uuid, 7);
-- ERROR:  not_found
-- (SQLSTATE 42501)

-- And critically: even with an out-of-range argument, authz still wins.
-- Expect: 42501 'not_found' (NOT 22023). Proves authz-first ordering.
SELECT public.get_lost_booking_summary(':shop_b'::uuid, 999);
-- ERROR:  not_found
-- (SQLSTATE 42501)

------------------------------------------------------------------------
-- Section 3. Range validation (checklist 2.5)
------------------------------------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":":owner_jwt_sub"}';

-- Out-of-range period_days.
SELECT public.get_lost_booking_summary(':shop_a'::uuid, 0);    -- 22023 invalid_period
SELECT public.get_lost_booking_summary(':shop_a'::uuid, 91);   -- 22023 invalid_period
SELECT public.get_lost_booking_summary(':shop_a'::uuid, NULL); -- 22023 invalid_period

-- Out-of-range weeks.
SELECT public.get_lost_booking_weekly_series(':shop_a'::uuid, 0);  -- 22023 invalid_weeks
SELECT public.get_lost_booking_weekly_series(':shop_a'::uuid, 53); -- 22023 invalid_weeks

-- Out-of-range lookback_days.
SELECT public.get_lost_booking_offenders(':shop_a'::uuid, 6,   2); -- 22023 invalid_lookback
SELECT public.get_lost_booking_offenders(':shop_a'::uuid, 366, 2); -- 22023 invalid_lookback

-- Out-of-range min_lost.
SELECT public.get_lost_booking_offenders(':shop_a'::uuid, 90, 0);  -- 22023 invalid_min_lost
SELECT public.get_lost_booking_offenders(':shop_a'::uuid, 90, 51); -- 22023 invalid_min_lost

------------------------------------------------------------------------
-- Section 4. Empty-shop sanity (Task 8.2 prep, checklist 6.1)
------------------------------------------------------------------------
-- Goal: a brand-new shop with zero terminal bookings returns a clean
-- zero-shaped result, never NULL or error.
--
-- Create a throwaway test shop, ensure it has no bookings, then call
-- each RPC. (Set up + cleanup wrapped in a transaction so it auto-rolls
-- back on a SAVEPOINT.)
BEGIN;
SET LOCAL "request.jwt.claims" = '{"sub":":owner_jwt_sub"}';
-- Assume :empty_shop exists with no bookings and is owned by :owner_jwt_sub.
SELECT public.get_lost_booking_summary(':empty_shop'::uuid, 7);
-- Expected JSON shape:
-- {
--   "period_days": 7,
--   "window_start": "...",
--   "window_end":   "...",
--   "current":  { "total": 0, "honoured": 0, "cancelled": 0, "no_show": 0, "lost_revenue": 0 },
--   "previous": { "total": 0, "honoured": 0, "cancelled": 0, "no_show": 0 }
-- }

SELECT public.get_lost_booking_weekly_series(':empty_shop'::uuid, 12);
-- Expected: { "weeks": [] }

SELECT public.get_lost_booking_offenders(':empty_shop'::uuid, 90, 2);
-- Expected: { "offenders": [] }
ROLLBACK;

------------------------------------------------------------------------
-- Section 5. last_lost_at fix for no-shows (RESEARCH §3, checklist 6.4)
------------------------------------------------------------------------
-- Goal: prove that a no-show booking's last_lost_at is its updated_at,
-- not NULL — because mark_booking_no_show does NOT set cancelled_at.
--
-- Setup: insert one cancelled booking with a known cancelled_at, then one
-- no-show booking with a LATER updated_at, for the same (shop, user).
-- Run get_lost_booking_offenders; assert last_lost_at == the LATER
-- timestamp. A bug that took MAX(cancelled_at) would return the EARLIER
-- timestamp instead.
--
-- Wrapped in transaction so it auto-rolls back.

BEGIN;
SET LOCAL "request.jwt.claims" = '{"sub":":owner_jwt_sub"}';

-- :test_user is a profiles.id that exists in your env.
INSERT INTO bookings (
  id, shop_id, user_id, slot_id, booking_date,
  start_time, end_time, total_amount, status,
  cancelled_at, updated_at, created_at
) VALUES
  (gen_random_uuid(), ':shop_a'::uuid, ':test_user'::uuid, ':any_slot'::uuid,
   CURRENT_DATE - INTERVAL '10 days',
   now() - INTERVAL '10 days', now() - INTERVAL '10 days' + INTERVAL '1 hour',
   100, 'cancelled',
   now() - INTERVAL '10 days', now() - INTERVAL '10 days', now() - INTERVAL '10 days'),
  (gen_random_uuid(), ':shop_a'::uuid, ':test_user'::uuid, ':any_slot'::uuid,
   CURRENT_DATE - INTERVAL '2 days',
   now() - INTERVAL '2 days', now() - INTERVAL '2 days' + INTERVAL '1 hour',
   150, 'no_show',
   NULL, now() - INTERVAL '1 day', now() - INTERVAL '2 days');

SELECT
  jsonb_array_elements(
    public.get_lost_booking_offenders(':shop_a'::uuid, 90, 2) -> 'offenders'
  ) AS row
FROM (SELECT 1) _
WHERE (jsonb_array_elements(
         public.get_lost_booking_offenders(':shop_a'::uuid, 90, 2) -> 'offenders'
       ) ->> 'client_id') = ':test_user';

-- Expected: a row whose last_lost_at equals the no-show booking's
-- updated_at (now() - 1 day), NOT the cancelled booking's cancelled_at
-- (now() - 10 days). If you get back the older timestamp, the CASE
-- expression in the migration regressed.

ROLLBACK;

------------------------------------------------------------------------
-- Section 6. Same-day, future-dated, owner-cancelled edge cases (6.1)
------------------------------------------------------------------------
-- Goal: bucket-by-start_time semantics — a booking cancelled TODAY for
-- NEXT week falls into NEXT week's bucket, not this week's.

BEGIN;
SET LOCAL "request.jwt.claims" = '{"sub":":owner_jwt_sub"}';

INSERT INTO bookings (
  id, shop_id, user_id, slot_id, booking_date,
  start_time, end_time, total_amount, status,
  cancelled_at, updated_at, created_at
) VALUES
  -- (a) Cancelled TODAY for NEXT week → belongs to next week, not this one.
  (gen_random_uuid(), ':shop_a'::uuid, ':test_user'::uuid, ':any_slot'::uuid,
   CURRENT_DATE + INTERVAL '7 days',
   now() + INTERVAL '7 days', now() + INTERVAL '7 days' + INTERVAL '1 hour',
   100, 'cancelled', now(), now(), now()),
  -- (b) Same-day cancellation → counts in current window.
  (gen_random_uuid(), ':shop_a'::uuid, ':test_user'::uuid, ':any_slot'::uuid,
   CURRENT_DATE,
   now() - INTERVAL '2 hours', now() - INTERVAL '1 hour',
   100, 'cancelled', now() - INTERVAL '30 minutes', now() - INTERVAL '30 minutes', now() - INTERVAL '1 day'),
  -- (c) Owner-initiated cancellation (modelled by a high-volume role) →
  -- still counts. (Actor differentiation is a future RPC; v1 surfaces
  -- the combined rate by design.)
  (gen_random_uuid(), ':shop_a'::uuid, ':test_user'::uuid, ':any_slot'::uuid,
   CURRENT_DATE - INTERVAL '1 day',
   now() - INTERVAL '1 day', now() - INTERVAL '1 day' + INTERVAL '1 hour',
   100, 'cancelled', now() - INTERVAL '1 day', now() - INTERVAL '1 day', now() - INTERVAL '2 days');

SELECT public.get_lost_booking_summary(':shop_a'::uuid, 7);
-- Expected: current.cancelled increments by 2 (bookings b and c).
-- Booking (a) is in the FUTURE so it's NOT in either current or previous
-- window — both windows are bounded by start_time < now().

ROLLBACK;

------------------------------------------------------------------------
-- Notes
------------------------------------------------------------------------
-- 1. Replace :shop_a, :shop_b, :owner_jwt_sub, :other_jwt_sub,
--    :test_user, :any_slot, :empty_shop with real UUIDs from your env.
-- 2. The :owner_jwt_sub UUID must be the auth.users.id, not the
--    profiles.id (they are the same in Supabase, but worth confirming
--    if you've customised auth).
-- 3. If you don't have a real slot UUID, create one via the existing
--    appointment_slots seed flow or pick an existing one with:
--      SELECT id FROM appointment_slots WHERE shop_id = ':shop_a' LIMIT 1;
