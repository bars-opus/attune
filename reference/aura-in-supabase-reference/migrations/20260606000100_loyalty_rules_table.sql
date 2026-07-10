-- Phase 13 — loyalty_rules
--
-- Per-shop loyalty configuration. One active rule per shop enforced
-- by a partial unique index. The bookings AFTER UPDATE trigger
-- (Wave 1) reads this table on each completed booking to decide
-- whether to issue a loyalty code.
--
-- Reuses `discount_type` enum from the existing `promotions` table
-- shape (CHECK on TEXT, not a true enum) so the values pass through
-- unchanged to the generated promotion row.
--
-- RLS: owner-only — same template as wallet, client_notes, etc.

CREATE TABLE IF NOT EXISTS public.loyalty_rules (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id             UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  trigger_visit_count INT NOT NULL CHECK (trigger_visit_count BETWEEN 2 AND 50),
  discount_type       TEXT NOT NULL CHECK (discount_type IN ('percentage','fixed')),
  discount_value      NUMERIC(12,2) NOT NULL CHECK (discount_value > 0),
  is_active           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One active rule per shop. Partial — inactive rules are kept for
-- audit but don't constrain a new active rule.
CREATE UNIQUE INDEX IF NOT EXISTS loyalty_rules_one_active_per_shop
  ON public.loyalty_rules (shop_id) WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_loyalty_rules_shop
  ON public.loyalty_rules (shop_id);

ALTER TABLE public.loyalty_rules ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'loyalty_rules_owner_select') THEN
    CREATE POLICY loyalty_rules_owner_select ON public.loyalty_rules
      FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM public.shops s
                     WHERE s.id = loyalty_rules.shop_id AND s.user_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'loyalty_rules_owner_write') THEN
    CREATE POLICY loyalty_rules_owner_write ON public.loyalty_rules
      FOR ALL TO authenticated
      USING (EXISTS (SELECT 1 FROM public.shops s
                     WHERE s.id = loyalty_rules.shop_id AND s.user_id = auth.uid()))
      WITH CHECK (EXISTS (SELECT 1 FROM public.shops s
                          WHERE s.id = loyalty_rules.shop_id AND s.user_id = auth.uid()));
  END IF;
END $$;

COMMENT ON TABLE public.loyalty_rules IS
  'Per-shop loyalty config. One active row per shop (partial unique index). Every Nth completed booking issues a one-shot loyalty code via the bookings trigger. Phase 13.';
COMMENT ON COLUMN public.loyalty_rules.trigger_visit_count IS
  'N: the loyalty code issues on the Nth completed booking by a client at this shop. 2..50.';
COMMENT ON COLUMN public.loyalty_rules.discount_type IS
  'Inherited shape from promotions.discount_type — percentage or fixed.';
COMMENT ON COLUMN public.loyalty_rules.is_active IS
  'Only the active row is read by the bookings trigger. Owner may keep inactive rows for audit.';
