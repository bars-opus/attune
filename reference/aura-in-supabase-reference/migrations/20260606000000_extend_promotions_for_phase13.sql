-- Phase 13 — extend existing `promotions` + `promotion_redemptions`.
--
-- The existing tables (from 20260604000100) get the columns Phase 13
-- needs for silent codes (source, target_user_id, target_guest_profile_id),
-- richer eligibility (per_client_max, min_booking_amount,
-- service_restriction), soft-delete (archived_at), and TIMESTAMPTZ
-- precision on validity (was DATE). All adds idempotent.
--
-- Constraint swap: the globally-unique `promotions_code_key` (verified
-- 2026-06-06) is dropped and replaced with per-shop UNIQUE
-- (shop_id, UPPER(code)) WHERE archived_at IS NULL. Pre-flight check
-- confirmed zero duplicate codes across shops on the live DB.
--
-- RLS swap: the broad owner_all policy is replaced with 4 scoped
-- policies. Direct INSERT/UPDATE/DELETE restricted to owner_defined
-- rows; system codes (loyalty/recovery) only writable by SECURITY
-- DEFINER helpers (which bypass RLS). Closes the fabrication surface
-- where an owner could otherwise mint a loyalty code targeting any
-- arbitrary auth.uid() they like.

-- 1. Widen valid_from / valid_to from DATE to TIMESTAMPTZ. Existing
-- data coerces cleanly (date → midnight UTC). Owner UI continues to
-- write dates; PG implicitly upcasts.
DO $$ BEGIN
  IF (SELECT data_type FROM information_schema.columns
      WHERE table_name = 'promotions' AND column_name = 'valid_from') = 'date' THEN
    ALTER TABLE public.promotions
      ALTER COLUMN valid_from TYPE TIMESTAMPTZ USING valid_from::TIMESTAMPTZ,
      ALTER COLUMN valid_to   TYPE TIMESTAMPTZ USING valid_to::TIMESTAMPTZ;
  END IF;
END $$;

-- 2. Add the new columns. All idempotent.
ALTER TABLE public.promotions
  ADD COLUMN IF NOT EXISTS per_client_max          INT NOT NULL DEFAULT 1
    CHECK (per_client_max >= 1),
  ADD COLUMN IF NOT EXISTS min_booking_amount      NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS service_restriction     UUID[],
  ADD COLUMN IF NOT EXISTS source                  TEXT NOT NULL DEFAULT 'owner_defined'
    CHECK (source IN ('owner_defined','loyalty','recovery')),
  ADD COLUMN IF NOT EXISTS target_user_id          UUID
    REFERENCES auth.users(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS target_guest_profile_id UUID
    REFERENCES public.guest_profiles(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS archived_at             TIMESTAMPTZ;

-- 3. XOR constraint on target_*. Owner_defined rows have both NULL;
-- loyalty / recovery rows have exactly one set. Locks the silent-code
-- identity contract.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'promotions_target_xor_check'
      AND conrelid = 'public.promotions'::regclass
  ) THEN
    ALTER TABLE public.promotions ADD CONSTRAINT promotions_target_xor_check
      CHECK (
        source = 'owner_defined'
        OR (
          source IN ('loyalty', 'recovery')
          AND ((target_user_id IS NOT NULL) <> (target_guest_profile_id IS NOT NULL))
        )
      );
  END IF;
END $$;

-- 4. Constraint swap: drop the global UNIQUE on code, replace with
-- per-shop UNIQUE on (shop_id, UPPER(code)) WHERE archived_at IS NULL.
-- The partial predicate lets owners re-issue a code text after
-- archiving the old one. Pre-flight verified zero collisions.
ALTER TABLE public.promotions DROP CONSTRAINT IF EXISTS promotions_code_key;

CREATE UNIQUE INDEX IF NOT EXISTS promotions_shop_code_unique
  ON public.promotions (shop_id, UPPER(code))
  WHERE archived_at IS NULL;

-- 5. Silent-code auto-apply lookup index. The validate RPC's NULL-code
-- branch reads at most one matching silent code per (shop, client) +
-- this index makes the lookup O(log n).
CREATE UNIQUE INDEX IF NOT EXISTS promotions_silent_target_uniq
  ON public.promotions (shop_id, COALESCE(target_user_id, target_guest_profile_id), source)
  WHERE source IN ('loyalty','recovery') AND archived_at IS NULL;

-- 6. promotion_redemptions: make user_id nullable, add guest_profile_id,
-- enforce at-most-one identity. The "both NULL" branch is allowed for
-- pre-identity-resolution rows (shouldn't happen in v1; defence in depth).
ALTER TABLE public.promotion_redemptions
  ALTER COLUMN user_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS guest_profile_id UUID
    REFERENCES public.guest_profiles(id) ON DELETE SET NULL;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'promotion_redemptions_identity_check'
      AND conrelid = 'public.promotion_redemptions'::regclass
  ) THEN
    ALTER TABLE public.promotion_redemptions ADD CONSTRAINT promotion_redemptions_identity_check
      CHECK (
        -- At most one of (user_id, guest_profile_id) is non-null.
        (user_id IS NULL) OR (guest_profile_id IS NULL)
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS promotion_redemptions_promo_user
  ON public.promotion_redemptions (promotion_id, user_id)
  WHERE user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS promotion_redemptions_promo_guest
  ON public.promotion_redemptions (promotion_id, guest_profile_id)
  WHERE guest_profile_id IS NOT NULL;

-- 7. RLS tightening: replace the broad owner_all policy with four
-- scoped policies. Direct INSERT/UPDATE/DELETE restricted to
-- owner_defined rows; system codes (loyalty/recovery) can only be
-- written by SECURITY DEFINER helpers (which bypass RLS).
--
-- This closes the surface where an owner could otherwise INSERT a
-- source='loyalty' row with target_user_id=<arbitrary>, fabricating a
-- discount targeting any client.
DROP POLICY IF EXISTS promotions_owner_all ON public.promotions;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'promotions_owner_select') THEN
    CREATE POLICY promotions_owner_select ON public.promotions
      FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM public.shops s
                     WHERE s.id = promotions.shop_id AND s.user_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'promotions_owner_write_owner_defined') THEN
    CREATE POLICY promotions_owner_write_owner_defined ON public.promotions
      FOR INSERT TO authenticated
      WITH CHECK (
        source = 'owner_defined'
        AND EXISTS (SELECT 1 FROM public.shops s
                    WHERE s.id = promotions.shop_id AND s.user_id = auth.uid())
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'promotions_owner_update_owner_defined') THEN
    CREATE POLICY promotions_owner_update_owner_defined ON public.promotions
      FOR UPDATE TO authenticated
      USING (source = 'owner_defined'
             AND EXISTS (SELECT 1 FROM public.shops s
                         WHERE s.id = promotions.shop_id AND s.user_id = auth.uid()))
      WITH CHECK (source = 'owner_defined');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'promotions_owner_delete_owner_defined') THEN
    CREATE POLICY promotions_owner_delete_owner_defined ON public.promotions
      FOR DELETE TO authenticated
      USING (source = 'owner_defined'
             AND EXISTS (SELECT 1 FROM public.shops s
                         WHERE s.id = promotions.shop_id AND s.user_id = auth.uid()));
  END IF;
END $$;

COMMENT ON COLUMN public.promotions.source IS
  'owner_defined: owner-authored code via PromotionsScreen. loyalty: trigger-generated on Nth completed booking. recovery: helper-generated by enqueue_booking_reminder. Phase 13.';
COMMENT ON COLUMN public.promotions.target_user_id IS
  'Set only for source in (loyalty, recovery). Silent codes restricted to this client.';
COMMENT ON COLUMN public.promotions.target_guest_profile_id IS
  'Guest counterpart of target_user_id. Mutually exclusive — XOR check enforced.';
COMMENT ON COLUMN public.promotions.archived_at IS
  'Soft-delete timestamp. NULL = active. Set by archive_promo flow; lets the partial-unique index free up the code text for re-issue.';
COMMENT ON COLUMN public.promotions.per_client_max IS
  'Max redemptions per client. Defaults to 1; system codes (loyalty/recovery) always 1.';
COMMENT ON COLUMN public.promotions.min_booking_amount IS
  'Minimum total_amount for the discount to apply. NULL = no floor.';
COMMENT ON COLUMN public.promotions.service_restriction IS
  'Array of appointment_slots.id; the booking must include at least one of these for the discount to apply. NULL = any service.';
