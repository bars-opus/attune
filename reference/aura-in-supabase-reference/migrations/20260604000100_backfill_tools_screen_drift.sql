-- Backfill: capture four objects that exist in production but were
-- created via the Supabase Dashboard rather than committed migrations.
-- Lifted byte-for-byte from the live prod schema (verified 2026-06-04).
--
-- All blocks use CREATE TABLE IF NOT EXISTS / CREATE OR REPLACE
-- FUNCTION so this migration is a no-op against the live database.
-- The goal is parity for CI / local / staging, not behavior change.
--
-- Note on column types: the user verified each column against
-- information_schema.columns before this migration was written.
-- Specifically:
--   promotions.valid_from / valid_to are DATE (NOT timestamptz)
--   promotion_redemptions.user_id is NULLABLE (guest path)
--   promotion_redemptions has redeemed_at, NOT created_at
--   shop_settings has created_at AND updated_at
--
-- See .planning/phases/10.5-tools-screen-cleanup/10.5-RESEARCH.md and
-- 10.5-PLAN.md for the locked corrections this migration implements.

-- ── promotions ──────────────────────────────────────────────────────
-- Shop-owned coupon codes. RLS scoped to owner via shops.user_id.
CREATE TABLE IF NOT EXISTS public.promotions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id         UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  code            TEXT NOT NULL,
  discount_type   TEXT NOT NULL CHECK (discount_type IN ('percentage','fixed','free_addon')),
  discount_value  NUMERIC NOT NULL,
  valid_from      DATE NOT NULL,
  valid_to        DATE NOT NULL,
  usage_limit     INT,
  usage_count     INT NOT NULL DEFAULT 0,
  is_active       BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (shop_id, code)
);
ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS promotions_owner_all ON public.promotions;
CREATE POLICY promotions_owner_all ON public.promotions
  FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.shops s
    WHERE s.id = promotions.shop_id AND s.user_id = auth.uid()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.shops s
    WHERE s.id = promotions.shop_id AND s.user_id = auth.uid()
  ));

-- ── promotion_redemptions ──────────────────────────────────────────
-- Append-only ledger linking a promo code to the booking that used it.
-- UNIQUE (promotion_id, booking_id) added so redeem_promotion's
-- ON CONFLICT DO NOTHING idempotency works race-free.
CREATE TABLE IF NOT EXISTS public.promotion_redemptions (
  id              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  promotion_id    UUID NOT NULL REFERENCES public.promotions(id) ON DELETE CASCADE,
  booking_id      UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  user_id         UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  discount_amount NUMERIC NOT NULL,
  redeemed_at     TIMESTAMPTZ NULL DEFAULT now()
);
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'promotion_redemptions_promo_booking_uniq'
  ) THEN
    ALTER TABLE public.promotion_redemptions
      ADD CONSTRAINT promotion_redemptions_promo_booking_uniq
      UNIQUE (promotion_id, booking_id);
  END IF;
END $$;
ALTER TABLE public.promotion_redemptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS promotion_redemptions_owner_read ON public.promotion_redemptions;
CREATE POLICY promotion_redemptions_owner_read ON public.promotion_redemptions
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.promotions p
    JOIN public.shops s ON s.id = p.shop_id
    WHERE p.id = promotion_redemptions.promotion_id AND s.user_id = auth.uid()
  ));

-- ── shop_settings ──────────────────────────────────────────────────
-- One row per shop. Currently holds reminder_settings JSONB; future
-- per-shop config will live here too.
CREATE TABLE IF NOT EXISTS public.shop_settings (
  shop_id           UUID NOT NULL PRIMARY KEY REFERENCES public.shops(id) ON DELETE CASCADE,
  reminder_settings JSONB NULL DEFAULT '{}'::jsonb,
  created_at        TIMESTAMPTZ NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NULL DEFAULT now()
);
ALTER TABLE public.shop_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS shop_settings_owner_all ON public.shop_settings;
CREATE POLICY shop_settings_owner_all ON public.shop_settings
  FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.shops s
    WHERE s.id = shop_settings.shop_id AND s.user_id = auth.uid()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.shops s
    WHERE s.id = shop_settings.shop_id AND s.user_id = auth.uid()
  ));

-- ── increment_promotion_usage (deprecated no-op) ───────────────────
-- Retained to avoid breaking stale clients. New code uses
-- redeem_promotion(promotion_id, booking_id, user_id, discount_amount).
CREATE OR REPLACE FUNCTION public.increment_promotion_usage(p_promotion_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  -- No-op. Stale clients that still call this RPC won't 404, but the
  -- counter no longer bumps from this path — redeem_promotion now
  -- owns the atomic counter + ledger insert.
  RETURN;
END;
$function$;

REVOKE ALL ON FUNCTION public.increment_promotion_usage(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_promotion_usage(UUID) TO authenticated;

COMMENT ON FUNCTION public.increment_promotion_usage(UUID) IS
  'DEPRECATED 2026-06-04 — no-op. Use public.redeem_promotion(promotion_id, booking_id, user_id, discount_amount) for atomic counter+ledger. O(1).';
