-- Phase 12 — enqueue_rebook_nudges() + partial unique index + pg_cron.
--
-- Nightly: emit one rebook_nudge per (shop, client) where
--   * last completed booking + shop median gap == today
--   * no future pending/confirmed booking on the books
--   * no rebook_nudge sent in the last 30 days
--
-- Idempotency = belt + suspenders:
--   1. Partial unique index on (shop_id, COALESCE(user_id, guest_profile_id),
--      notification_type, scheduled_for::date) WHERE notification_type IN
--      ('rebook_nudge', 'recovery_checkin') AND status IN ('pending', 'processing').
--      Catches same-day re-runs at the index layer.
--   2. NOT EXISTS clause for the 30-day cooldown. Catches across-day repeats.
--
-- Partial-index conflict target: use the index name (ON CONFLICT ON
-- CONSTRAINT requires a constraint name — partial unique indexes don't
-- generate constraints, so we use INSERT ... ON CONFLICT with the
-- column list. Postgres correctly matches the partial index because
-- the inserted row's notification_type satisfies the index predicate.

-- ── Partial unique index (idempotency layer 1) ──
-- The `(timestamptz::date)` cast is STABLE (depends on session
-- timezone), and Postgres rejects STABLE expressions in index columns.
-- Pin the timezone explicitly via `AT TIME ZONE 'UTC'` — the resulting
-- `timestamp → date` cast is IMMUTABLE. UTC matches the cron schedule
-- (03:30 UTC), so same-day dedupe lines up with the cron run window.
CREATE UNIQUE INDEX IF NOT EXISTS scheduled_notifications_rebook_idem
  ON public.scheduled_notifications (
    shop_id,
    COALESCE(user_id, guest_profile_id),
    notification_type,
    ((scheduled_for AT TIME ZONE 'UTC')::date)
  )
  WHERE notification_type IN ('rebook_nudge', 'recovery_checkin')
    AND status IN ('pending', 'processing');

-- ── The cron-only RPC ──
CREATE OR REPLACE FUNCTION public.enqueue_rebook_nudges()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $function$
DECLARE
  v_inserted INTEGER := 0;
BEGIN
  WITH eligible AS (
    SELECT
      b.shop_id,
      b.user_id,
      b.guest_profile_id,
      MAX(b.start_time) AS last_completed_at
    FROM public.bookings b
    WHERE b.status = 'completed'
    GROUP BY b.shop_id, b.user_id, b.guest_profile_id
  ),
  due AS (
    SELECT e.*, c.median_gap_days
    FROM eligible e
    JOIN public.shop_rebook_cadence c USING (shop_id)
    WHERE (e.last_completed_at::date + (c.median_gap_days || ' days')::interval)::date
            = current_date
      -- No future booking already on the books for this (shop, client).
      AND NOT EXISTS (
        SELECT 1 FROM public.bookings fb
        WHERE fb.shop_id = e.shop_id
          AND fb.start_time > now()
          AND fb.status IN ('pending', 'confirmed')
          AND (
            (fb.user_id IS NOT NULL AND fb.user_id = e.user_id)
            OR
            (fb.guest_profile_id IS NOT NULL AND fb.guest_profile_id = e.guest_profile_id)
          )
      )
      -- 30-day cooldown for rebook_nudge.
      AND NOT EXISTS (
        SELECT 1 FROM public.scheduled_notifications s
        WHERE s.shop_id = e.shop_id
          AND COALESCE(s.user_id, s.guest_profile_id)
              = COALESCE(e.user_id, e.guest_profile_id)
          AND s.notification_type = 'rebook_nudge'
          AND s.scheduled_for > now() - INTERVAL '30 days'
      )
  )
  INSERT INTO public.scheduled_notifications (
    user_id, guest_profile_id, shop_id,
    notification_type, scheduled_for, delivery_channel,
    whatsapp_template, whatsapp_params, status, metadata
  )
  SELECT
    d.user_id,
    d.guest_profile_id,
    d.shop_id,
    'rebook_nudge',
    now() + INTERVAL '1 hour',
    CASE WHEN d.user_id IS NOT NULL THEN 'push' ELSE 'whatsapp' END,
    CASE WHEN d.user_id IS NOT NULL THEN NULL ELSE 'rebook_nudge_v1' END,
    CASE WHEN d.user_id IS NOT NULL
         THEN NULL
         ELSE jsonb_build_object(
                '1', COALESCE(
                       (SELECT gp.name FROM public.guest_profiles gp WHERE gp.id = d.guest_profile_id),
                       'there'),
                '2', (SELECT sh.shop_name FROM public.shops sh WHERE sh.id = d.shop_id))
    END,
    'pending',
    jsonb_build_object(
      'title', 'Time for your next visit?',
      'body',  'It''s been a while since your last visit to ' ||
               (SELECT sh.shop_name FROM public.shops sh WHERE sh.id = d.shop_id) || '.',
      'shop_name', (SELECT sh.shop_name FROM public.shops sh WHERE sh.id = d.shop_id)
    )
  FROM due d
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted;
END;
$function$;

REVOKE ALL ON FUNCTION public.enqueue_rebook_nudges() FROM PUBLIC;
-- Intentionally NOT GRANTed to authenticated. Cron-only.

COMMENT ON FUNCTION public.enqueue_rebook_nudges() IS
  'Nightly: emit one rebook_nudge per (shop, client) where last-completed + shop median gap == today, no future booking on books, no rebook_nudge in last 30d. Idempotent via partial unique index + 30d EXISTS guard. O(completed_bookings per shop). Phase 12.';

-- ── Schedule nightly at 03:30 UTC (after the cadence refresh at 03:15) ──
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'enqueue-rebook-nudges',
      '30 3 * * *',
      $cron$SELECT public.enqueue_rebook_nudges()$cron$
    );
  ELSE
    RAISE NOTICE 'pg_cron not installed — enqueue-rebook-nudges not scheduled';
  END IF;
END $$;
