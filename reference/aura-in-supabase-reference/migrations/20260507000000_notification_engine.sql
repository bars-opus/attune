-- ============================================================
-- Notification Engine — Database Schema
-- ============================================================
-- Run once against any Supabase project to enable the full
-- notification engine. Tables are prefixed to avoid collisions
-- with your existing schema.
--
-- Extension required: postgis (for geo-notifications).
--   enable via: Dashboard → Database → Extensions → PostGIS
--   or: CREATE EXTENSION IF NOT EXISTS postgis;
-- ============================================================

-- ── 1. Scheduled Notifications ───────────────────────────────────────────────
-- Drives push delivery. The process-scheduled-notifications edge function
-- polls this table (cron, every minute) and delivers via OneSignal.
-- "Immediate" pushes are inserted with scheduled_for = now().

CREATE TABLE IF NOT EXISTS scheduled_notifications (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  notification_type TEXT NOT NULL,          -- e.g. 'booking_reminder_24h', 'immediate'
  booking_id        UUID,                   -- optional reference
  shop_id           UUID,                   -- optional reference
  scheduled_for     TIMESTAMPTZ NOT NULL,
  status            TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','processing','sent','failed','skipped','cancelled')),
  retry_count       INT NOT NULL DEFAULT 0,
  last_error        TEXT,
  metadata          JSONB NOT NULL DEFAULT '{}',  -- must contain {title, body, ...}
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sched_notif_pending
  ON scheduled_notifications (scheduled_for)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_sched_notif_user
  ON scheduled_notifications (user_id);

-- Cancel all pending notifications for a booking (called on booking cancel/update).
CREATE OR REPLACE FUNCTION cancel_booking_notifications(p_booking_id UUID)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_count INT;
BEGIN
  UPDATE scheduled_notifications
  SET    status     = 'cancelled',
         updated_at = now()
  WHERE  booking_id = p_booking_id
    AND  status     = 'pending';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- ── 2. In-App Notifications ───────────────────────────────────────────────────
-- The notification inbox in the Flutter app reads from this table.
-- Insert rows here from database triggers, edge functions, or scheduled jobs.

CREATE TABLE IF NOT EXISTS in_app_notifications (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title      TEXT NOT NULL,
  body       TEXT NOT NULL,
  data       JSONB DEFAULT '{}',    -- arbitrary payload (type, booking_id, shop_id…)
  is_read    BOOLEAN NOT NULL DEFAULT false,
  read_at    TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_in_app_notif_user
  ON in_app_notifications (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_in_app_notif_unread
  ON in_app_notifications (user_id)
  WHERE is_read = false;

-- Row-Level Security
ALTER TABLE in_app_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_own_notifications" ON in_app_notifications;
CREATE POLICY "users_own_notifications" ON in_app_notifications
  FOR ALL USING (auth.uid() = user_id);

-- ── 3. Notification Settings ──────────────────────────────────────────────────
-- Per-user opt-in/out preferences. The edge function checks push_enabled
-- before delivering. Flutter settings screen reads/writes this table.

CREATE TABLE IF NOT EXISTS notification_settings (
  user_id                   UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  push_enabled              BOOLEAN NOT NULL DEFAULT true,
  email_enabled             BOOLEAN NOT NULL DEFAULT false,
  marketing_enabled         BOOLEAN NOT NULL DEFAULT true,
  booking_reminders_enabled BOOLEAN NOT NULL DEFAULT true,
  new_shops_nearby_enabled  BOOLEAN NOT NULL DEFAULT true,
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE notification_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_own_settings" ON notification_settings;
CREATE POLICY "users_own_settings" ON notification_settings
  FOR ALL USING (auth.uid() = user_id);

-- Auto-create default settings row when a user signs up.
CREATE OR REPLACE FUNCTION create_default_notification_settings()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO notification_settings (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_notification_settings ON auth.users;
CREATE TRIGGER on_auth_user_created_notification_settings
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION create_default_notification_settings();

-- ── 4. Push Tokens (optional — OneSignal manages its own device registry) ────
-- Store tokens here if you want to support non-OneSignal delivery or to
-- deactivate tokens on logout without going through OneSignal's API.

CREATE TABLE IF NOT EXISTS push_tokens (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token      TEXT NOT NULL UNIQUE,
  platform   TEXT NOT NULL CHECK (platform IN ('ios','android','web')),
  is_active  BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_push_tokens_user
  ON push_tokens (user_id)
  WHERE is_active = true;

ALTER TABLE push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_own_tokens" ON push_tokens;
CREATE POLICY "users_own_tokens" ON push_tokens
  FOR ALL USING (auth.uid() = user_id);

-- ── 5. User Locations (geo-notifications) ────────────────────────────────────
-- Store last-known device location for "new shop nearby" style notifications.
-- Requires PostGIS extension.

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS user_locations (
  user_id    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  latitude   DOUBLE PRECISION NOT NULL,
  longitude  DOUBLE PRECISION NOT NULL,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE user_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_own_location" ON user_locations;
CREATE POLICY "users_own_location" ON user_locations
  FOR ALL USING (auth.uid() = user_id);

-- Returns user IDs within radius_km kilometres of (shop_lat, shop_lng).
-- Uses PostGIS geography ST_DWithin (radius in metres).
CREATE OR REPLACE FUNCTION get_nearby_users(
  shop_lat  DOUBLE PRECISION,
  shop_lng  DOUBLE PRECISION,
  radius_km DOUBLE PRECISION DEFAULT 10
)
RETURNS TABLE (user_id UUID) LANGUAGE sql STABLE AS $$
  SELECT ul.user_id
  FROM   user_locations ul
  WHERE  ul.is_active = true
    AND  ST_DWithin(
           ST_SetSRID(ST_MakePoint(ul.longitude, ul.latitude), 4326)::geography,
           ST_SetSRID(ST_MakePoint(shop_lng, shop_lat), 4326)::geography,
           radius_km * 1000
         );
$$;
