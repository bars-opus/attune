-- supabase/migrations/20260528120000_link_booking_guest_support.sql
--
-- Schema support for guest (anonymous) bookings via aura-in-web.vercel.app/book/<slug>.
-- All changes are additive and idempotent.
--
-- Freelancers note: "freelancer" is not a separate table; it is workers.is_freelancer.
-- All booking targets are shops. The web layer renders the freelancer flow when the
-- resolved shop has a freelancer worker (queried at resolve time).

-- ────────────────────────────────────────────────────────────────────────────
-- NEW TABLE: guest_profiles
-- Phone-keyed identity for unauthenticated bookers.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS guest_profiles (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone         text UNIQUE NOT NULL,
  name          text NOT NULL,
  locale        text DEFAULT 'en',
  last_seen_at  timestamptz DEFAULT now(),
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS guest_profiles_phone_idx
  ON guest_profiles (phone);

ALTER TABLE guest_profiles ENABLE ROW LEVEL SECURITY;
-- No policies = no public access. service_role bypasses.

-- ────────────────────────────────────────────────────────────────────────────
-- NEW TABLE: guest_booking_history
-- Compact log of (guest, service, shop) for prefill ordering.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS guest_booking_history (
  guest_profile_id uuid REFERENCES guest_profiles(id) ON DELETE CASCADE,
  service_name     text NOT NULL,
  shop_id          uuid,
  booked_at        timestamptz DEFAULT now(),
  PRIMARY KEY (guest_profile_id, booked_at)
);

CREATE INDEX IF NOT EXISTS guest_booking_history_lookup_idx
  ON guest_booking_history (guest_profile_id, booked_at DESC);

ALTER TABLE guest_booking_history ENABLE ROW LEVEL SECURITY;

-- ────────────────────────────────────────────────────────────────────────────
-- EXTEND bookings: guest support + delivery channel + freelancer client address
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE bookings ALTER COLUMN user_id DROP NOT NULL;

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS guest_profile_id    uuid REFERENCES guest_profiles(id),
  ADD COLUMN IF NOT EXISTS guest_name          text,
  ADD COLUMN IF NOT EXISTS guest_phone         text,
  ADD COLUMN IF NOT EXISTS client_address      text,
  ADD COLUMN IF NOT EXISTS client_address_lat  double precision,
  ADD COLUMN IF NOT EXISTS client_address_lng  double precision,
  ADD COLUMN IF NOT EXISTS delivery_channel    text NOT NULL DEFAULT 'push'
    CHECK (delivery_channel IN ('push', 'whatsapp', 'none'));

-- Enforce: exactly one of user_id or guest_profile_id is non-null.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'bookings_user_or_guest_chk'
  ) THEN
    ALTER TABLE bookings ADD CONSTRAINT bookings_user_or_guest_chk CHECK (
      (user_id IS NOT NULL AND guest_profile_id IS NULL) OR
      (user_id IS NULL AND guest_profile_id IS NOT NULL)
    );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS bookings_guest_profile_idx
  ON bookings (guest_profile_id);

-- ────────────────────────────────────────────────────────────────────────────
-- EXTEND shops: cached booking_slug for fast resolve-link lookup.
-- (No freelancers table — all booking targets are shops.)
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE shops
  ADD COLUMN IF NOT EXISTS booking_slug text UNIQUE;

-- ────────────────────────────────────────────────────────────────────────────
-- EXTEND scheduled_notifications: delivery channel + WhatsApp template fields
-- + guest reference.
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE scheduled_notifications
  ALTER COLUMN user_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS guest_profile_id  uuid REFERENCES guest_profiles(id),
  ADD COLUMN IF NOT EXISTS delivery_channel  text NOT NULL DEFAULT 'push'
    CHECK (delivery_channel IN ('push', 'whatsapp')),
  ADD COLUMN IF NOT EXISTS whatsapp_template text,
  ADD COLUMN IF NOT EXISTS whatsapp_params   jsonb;

-- ────────────────────────────────────────────────────────────────────────────
-- EXTEND pending_payments: delivery channel + guest reference.
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE pending_payments
  ADD COLUMN IF NOT EXISTS delivery_channel  text NOT NULL DEFAULT 'push'
    CHECK (delivery_channel IN ('push', 'whatsapp')),
  ADD COLUMN IF NOT EXISTS guest_profile_id  uuid REFERENCES guest_profiles(id);

-- pending_payments.user_id must be nullable for the guest path; guests
-- have no auth user. The matching guest_profile_id was added above; at
-- least one of user_id / guest_profile_id must be present at write time
-- (enforced in application code, not via DB constraint, since
-- pending_payments is a short-lived staging table).
ALTER TABLE pending_payments ALTER COLUMN user_id DROP NOT NULL;

-- ────────────────────────────────────────────────────────────────────────────
-- TRIGGER: keep shops.booking_slug in sync with short_links.
-- The authoritative slug lives in short_links; this column is a denormalized
-- copy for fast resolve-link lookups (no join needed).
--
-- Freelancers note: a freelancer's booking link is generated as a regular
-- shop link (link_type='shop', target_id=their shop id). Per-worker links
-- (link_type='worker') are not used for the booking flow in v1.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION sync_booking_slug_to_shop()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Clear cache if the link was previously an active shop link AND it is now
  -- deactivated, retargeted, retyped, or re-slugged. Use OLD.target_id /
  -- OLD.slug to clear the previously-cached value. Guard with
  -- booking_slug = OLD.slug so we don't clobber a newer active link.
  IF TG_OP = 'UPDATE'
     AND OLD.link_type = 'shop'
     AND OLD.is_active = true
     AND (
          NEW.is_active = false
       OR NEW.link_type <> 'shop'
       OR NEW.target_id <> OLD.target_id
       OR NEW.slug <> OLD.slug
     ) THEN
    UPDATE shops
       SET booking_slug = NULL
     WHERE id = OLD.target_id::uuid
       AND booking_slug = OLD.slug;
  END IF;

  -- Set cache on the current (new) target if it is an active shop link.
  IF NEW.link_type = 'shop' AND NEW.is_active = true THEN
    UPDATE shops SET booking_slug = NEW.slug WHERE id = NEW.target_id::uuid;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS short_links_sync_booking_slug_ins ON short_links;
CREATE TRIGGER short_links_sync_booking_slug_ins
  AFTER INSERT ON short_links
  FOR EACH ROW
  EXECUTE FUNCTION sync_booking_slug_to_shop();

DROP TRIGGER IF EXISTS short_links_sync_booking_slug_upd ON short_links;
CREATE TRIGGER short_links_sync_booking_slug_upd
  AFTER UPDATE OF slug, target_id, link_type, is_active ON short_links
  FOR EACH ROW
  EXECUTE FUNCTION sync_booking_slug_to_shop();

-- One-time backfill of existing shop short_links (no-op for fresh installs)
DO $$
DECLARE
  link record;
BEGIN
  FOR link IN
    SELECT slug, target_id
    FROM short_links
    WHERE link_type = 'shop'
      AND is_active = true
  LOOP
    UPDATE shops SET booking_slug = link.slug WHERE id = link.target_id::uuid;
  END LOOP;
END $$;

-- End of guest support migration.
