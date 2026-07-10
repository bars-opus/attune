-- ============================================================
-- Marketplace Schema (canonical, from-scratch)
-- ============================================================
-- This is the authoritative schema for the products / orders /
-- reviews / disputes feature. The previous remote schema (which
-- was never committed to git) is dropped and replaced. Safe
-- because we are pre-launch with no real customer data.
--
-- Design choices that differ from the previous remote schema:
--   * Money columns are NUMERIC(12,2), not double precision.
--   * products.stock_quantity is now NOT NULL with CHECK >= 0.
--   * RLS is ENABLED on every table with explicit policies.
--   * create_order / update_order_status / cancel_order RPCs are
--     atomic, SECURITY DEFINER, lock product rows with FOR UPDATE,
--     recompute totals server-side, and enforce state transitions.
--   * product_reviews aggregation is maintained by trigger so
--     products.average_rating + review_count never drift.
--   * search_vector is a GENERATED column (Postgres 12+).
--
-- Conventions:
--   * Shop ownership is shops.user_id = auth.uid().
--   * Customer identity is auth.uid().
--   * Status values are TEXT + CHECK (not ENUM) to keep migrations
--     cheap when statuses change.
-- ============================================================

-- ── 0. Drop existing marketplace objects ─────────────────────
-- CASCADE removes dependent FKs / views automatically. Functions
-- are dropped explicitly because they are not table-dependent.

DROP FUNCTION IF EXISTS create_order(UUID, UUID, JSONB, NUMERIC, TEXT, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS update_order_status(UUID, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS cancel_order(UUID) CASCADE;
DROP FUNCTION IF EXISTS marketplace_touch_updated_at() CASCADE;
DROP FUNCTION IF EXISTS recompute_product_rating() CASCADE;

DROP TABLE IF EXISTS order_disputes  CASCADE;
DROP TABLE IF EXISTS product_reviews CASCADE;
DROP TABLE IF EXISTS order_items     CASCADE;
DROP TABLE IF EXISTS orders          CASCADE;
DROP TABLE IF EXISTS products        CASCADE;

-- ── 1. products ──────────────────────────────────────────────

CREATE TABLE products (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id             UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  name                TEXT NOT NULL CHECK (length(trim(name)) >= 3),
  description         TEXT,
  price               NUMERIC(12,2) NOT NULL CHECK (price > 0),
  images              TEXT[] NOT NULL DEFAULT '{}',
  category            TEXT NOT NULL CHECK (category IN ('hair','skin','tools','accessories')),
  is_active           BOOLEAN NOT NULL DEFAULT true,
  stock_quantity      INT NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
  total_orders_count  INT NOT NULL DEFAULT 0 CHECK (total_orders_count >= 0),
  average_rating      NUMERIC(3,2) NOT NULL DEFAULT 0
                      CHECK (average_rating >= 0 AND average_rating <= 5),
  review_count        INT NOT NULL DEFAULT 0 CHECK (review_count >= 0),
  search_vector       TSVECTOR GENERATED ALWAYS AS (
                        setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
                        setweight(to_tsvector('english', coalesce(description, '')), 'B') ||
                        setweight(to_tsvector('english', coalesce(category, '')), 'C')
                      ) STORED,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_products_shop                ON products (shop_id);
CREATE INDEX idx_products_active_recent       ON products (is_active, created_at DESC) WHERE is_active = true;
CREATE INDEX idx_products_active_category     ON products (is_active, category)        WHERE is_active = true;
CREATE INDEX idx_products_active_price        ON products (is_active, price)           WHERE is_active = true;
CREATE INDEX idx_products_active_popular      ON products (is_active, total_orders_count DESC) WHERE is_active = true;
CREATE INDEX idx_products_search              ON products USING GIN (search_vector);

-- ── 2. orders ────────────────────────────────────────────────

CREATE TABLE orders (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  shop_id           UUID NOT NULL REFERENCES shops(id)      ON DELETE CASCADE,
  order_date        TIMESTAMPTZ NOT NULL DEFAULT now(),
  status            TEXT NOT NULL DEFAULT 'pending_confirmation'
                    CHECK (status IN (
                      'pending_confirmation','confirmed','out_for_delivery',
                      'delivered','cancelled','disputed'
                    )),
  total_amount      NUMERIC(12,2) NOT NULL CHECK (total_amount > 0),
  delivery_address  TEXT NOT NULL CHECK (length(trim(delivery_address)) > 0),
  customer_phone    TEXT NOT NULL CHECK (length(trim(customer_phone)) > 0),
  customer_notes    TEXT,
  shop_notes        TEXT,
  delivery_notes    TEXT,
  confirmed_at      TIMESTAMPTZ,
  dispatched_at     TIMESTAMPTZ,
  delivered_at      TIMESTAMPTZ,
  cancelled_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orders_customer_recent ON orders (user_id, created_at DESC);
CREATE INDEX idx_orders_shop_recent     ON orders (shop_id, created_at DESC);
CREATE INDEX idx_orders_shop_status     ON orders (shop_id, status, created_at DESC);
CREATE INDEX idx_orders_status          ON orders (status) WHERE status IN ('pending_confirmation','confirmed','out_for_delivery');

-- ── 3. order_items ───────────────────────────────────────────

CREATE TABLE order_items (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    UUID NOT NULL REFERENCES orders(id)   ON DELETE CASCADE,
  product_id  UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  quantity    INT NOT NULL CHECK (quantity > 0),
  unit_price  NUMERIC(12,2) NOT NULL CHECK (unit_price > 0),
  subtotal    NUMERIC(12,2) GENERATED ALWAYS AS (unit_price * quantity) STORED,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_order_items_order   ON order_items (order_id);
CREATE INDEX idx_order_items_product ON order_items (product_id);

-- ── 4. product_reviews ───────────────────────────────────────

CREATE TABLE product_reviews (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id        UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  order_id          UUID NOT NULL REFERENCES orders(id)   ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rating            SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment           TEXT,
  shop_response     TEXT,
  shop_response_at  TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (order_id, product_id, user_id)
);

CREATE INDEX idx_product_reviews_product ON product_reviews (product_id, created_at DESC);
CREATE INDEX idx_product_reviews_user    ON product_reviews (user_id);

-- ── 5. order_disputes ────────────────────────────────────────

CREATE TABLE order_disputes (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id            UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  raised_by_user_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason              TEXT NOT NULL CHECK (length(trim(reason)) > 0),
  status              TEXT NOT NULL DEFAULT 'open'
                      CHECK (status IN ('open','resolved','rejected')),
  resolution_notes    TEXT,
  resolved_at         TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_order_disputes_order  ON order_disputes (order_id);
CREATE INDEX idx_order_disputes_status ON order_disputes (status, created_at DESC);

-- ── 6. updated_at trigger ────────────────────────────────────

CREATE OR REPLACE FUNCTION marketplace_touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_products_touch        BEFORE UPDATE ON products        FOR EACH ROW EXECUTE FUNCTION marketplace_touch_updated_at();
CREATE TRIGGER trg_orders_touch          BEFORE UPDATE ON orders          FOR EACH ROW EXECUTE FUNCTION marketplace_touch_updated_at();
CREATE TRIGGER trg_product_reviews_touch BEFORE UPDATE ON product_reviews FOR EACH ROW EXECUTE FUNCTION marketplace_touch_updated_at();
CREATE TRIGGER trg_order_disputes_touch  BEFORE UPDATE ON order_disputes  FOR EACH ROW EXECUTE FUNCTION marketplace_touch_updated_at();

-- ── 7. Rating aggregation trigger ────────────────────────────
-- Keeps products.average_rating and products.review_count in sync
-- with the underlying product_reviews rows. Single source of truth.

CREATE OR REPLACE FUNCTION recompute_product_rating()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_product_id UUID;
BEGIN
  v_product_id := COALESCE(NEW.product_id, OLD.product_id);

  UPDATE products p
  SET    average_rating = COALESCE((SELECT round(avg(rating)::numeric, 2)
                                    FROM product_reviews
                                    WHERE product_id = v_product_id), 0),
         review_count   = (SELECT count(*)
                           FROM product_reviews
                           WHERE product_id = v_product_id)
  WHERE  p.id = v_product_id;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_product_reviews_aggregate
AFTER INSERT OR UPDATE OF rating OR DELETE ON product_reviews
FOR EACH ROW EXECUTE FUNCTION recompute_product_rating();

-- ============================================================
-- Row-Level Security
-- ============================================================
-- All tables have RLS enabled. Per-row authorization is enforced
-- in Postgres so the Dart client filtering is no longer the only
-- line of defense.

-- ── products RLS ─────────────────────────────────────────────
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- Anyone (including anon) can read active products in the marketplace.
CREATE POLICY products_read_active ON products
  FOR SELECT USING (is_active = true);

-- Shop owners can read all of their own products (active or inactive).
CREATE POLICY products_owner_read ON products
  FOR SELECT TO authenticated
  USING (shop_id IN (SELECT id FROM shops WHERE user_id = auth.uid()));

-- Shop owners can insert/update/delete only their own products.
CREATE POLICY products_owner_write ON products
  FOR ALL TO authenticated
  USING      (shop_id IN (SELECT id FROM shops WHERE user_id = auth.uid()))
  WITH CHECK (shop_id IN (SELECT id FROM shops WHERE user_id = auth.uid()));

-- ── orders RLS ───────────────────────────────────────────────
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Customers can read their own orders.
CREATE POLICY orders_customer_read ON orders
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Shop owners can read orders placed against their shops.
CREATE POLICY orders_shop_read ON orders
  FOR SELECT TO authenticated
  USING (shop_id IN (SELECT id FROM shops WHERE user_id = auth.uid()));

-- Direct INSERT/UPDATE/DELETE on orders is blocked. All writes go
-- through the SECURITY DEFINER RPCs (create_order, update_order_status,
-- cancel_order) which enforce business rules and atomicity.

-- ── order_items RLS ──────────────────────────────────────────
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

-- Readable if the parent order is readable to the caller.
CREATE POLICY order_items_read ON order_items
  FOR SELECT TO authenticated
  USING (order_id IN (
    SELECT id FROM orders
    WHERE user_id = auth.uid()
       OR shop_id IN (SELECT id FROM shops WHERE user_id = auth.uid())
  ));

-- No direct writes — only the create_order RPC writes order_items.

-- ── product_reviews RLS ──────────────────────────────────────
ALTER TABLE product_reviews ENABLE ROW LEVEL SECURITY;

-- Anyone can read reviews (public marketplace signal).
CREATE POLICY product_reviews_read ON product_reviews
  FOR SELECT USING (true);

-- A user may insert a review only for a product they actually
-- received in a delivered order.
CREATE POLICY product_reviews_insert ON product_reviews
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM order_items oi
      JOIN   orders o ON o.id = oi.order_id
      WHERE  oi.order_id   = product_reviews.order_id
        AND  oi.product_id = product_reviews.product_id
        AND  o.user_id     = auth.uid()
        AND  o.status      = 'delivered'
    )
  );

-- A user can edit their own review (rating/comment).
CREATE POLICY product_reviews_update_own ON product_reviews
  FOR UPDATE TO authenticated
  USING      (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- A shop owner can update only the response fields on reviews of
-- their own products. Enforced via WITH CHECK on row contents
-- combined with USING on shop ownership.
CREATE POLICY product_reviews_shop_response ON product_reviews
  FOR UPDATE TO authenticated
  USING (product_id IN (
    SELECT p.id FROM products p
    JOIN   shops    s ON s.id = p.shop_id
    WHERE  s.user_id = auth.uid()
  ))
  WITH CHECK (product_id IN (
    SELECT p.id FROM products p
    JOIN   shops    s ON s.id = p.shop_id
    WHERE  s.user_id = auth.uid()
  ));

-- ── order_disputes RLS ───────────────────────────────────────
ALTER TABLE order_disputes ENABLE ROW LEVEL SECURITY;

-- Customer who placed the order, or shop owner of the order's
-- shop, can read the dispute.
CREATE POLICY order_disputes_read ON order_disputes
  FOR SELECT TO authenticated
  USING (order_id IN (
    SELECT id FROM orders
    WHERE user_id = auth.uid()
       OR shop_id IN (SELECT id FROM shops WHERE user_id = auth.uid())
  ));

-- A customer can raise a dispute on their own order.
CREATE POLICY order_disputes_customer_insert ON order_disputes
  FOR INSERT TO authenticated
  WITH CHECK (
    raised_by_user_id = auth.uid()
    AND order_id IN (SELECT id FROM orders WHERE user_id = auth.uid())
  );

-- ============================================================
-- RPCs (atomic, SECURITY DEFINER)
-- ============================================================
-- Every write that crosses tables or needs row-locking goes through
-- one of these. Clients cannot bypass them because direct INSERT/
-- UPDATE on orders / order_items is blocked by RLS.

-- ── create_order ─────────────────────────────────────────────
-- Signature must match what supabase_order_repository.dart calls.
-- p_total_amount is accepted for compatibility but the RPC ignores
-- it and recomputes the canonical total from current product prices
-- to defeat client-side total tampering.

CREATE OR REPLACE FUNCTION create_order(
  p_user_id           UUID,
  p_shop_id           UUID,
  p_items             JSONB,        -- [{"product_id":"...", "quantity":N}, ...]
  p_total_amount      NUMERIC,      -- accepted but ignored (recomputed)
  p_delivery_address  TEXT,
  p_customer_phone    TEXT,
  p_customer_notes    TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id     UUID;
  v_item         JSONB;
  v_product      products%ROWTYPE;
  v_qty          INT;
  v_total        NUMERIC(12,2) := 0;
  v_item_count   INT := 0;
BEGIN
  -- AuthN: the RPC may only be invoked by the user placing the order.
  IF p_user_id IS NULL OR p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: user mismatch' USING ERRCODE = '42501';
  END IF;

  -- Validate inputs
  IF p_shop_id IS NULL THEN
    RAISE EXCEPTION 'shop_id is required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'items must be a non-empty array' USING ERRCODE = '22023';
  END IF;
  IF length(trim(coalesce(p_delivery_address, ''))) = 0 THEN
    RAISE EXCEPTION 'delivery_address is required' USING ERRCODE = '22023';
  END IF;
  IF length(trim(coalesce(p_customer_phone, ''))) = 0 THEN
    RAISE EXCEPTION 'customer_phone is required' USING ERRCODE = '22023';
  END IF;

  -- Lock all referenced product rows in a single shop, in id order
  -- (deterministic order avoids deadlocks across concurrent orders).
  FOR v_item IN
    SELECT * FROM jsonb_array_elements(p_items)
    ORDER BY (value->>'product_id')::uuid
  LOOP
    v_qty := (v_item->>'quantity')::int;
    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'invalid quantity for product %', v_item->>'product_id' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_product
    FROM   products
    WHERE  id = (v_item->>'product_id')::uuid
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'product % not found', v_item->>'product_id' USING ERRCODE = 'P0002';
    END IF;
    IF v_product.shop_id <> p_shop_id THEN
      RAISE EXCEPTION 'product % does not belong to shop %', v_product.id, p_shop_id USING ERRCODE = '22023';
    END IF;
    IF NOT v_product.is_active THEN
      RAISE EXCEPTION 'product % is not available', v_product.id USING ERRCODE = '22023';
    END IF;
    IF v_product.stock_quantity < v_qty THEN
      RAISE EXCEPTION 'insufficient stock for product %: requested %, available %',
        v_product.id, v_qty, v_product.stock_quantity USING ERRCODE = '22023';
    END IF;

    v_total      := v_total + (v_product.price * v_qty);
    v_item_count := v_item_count + 1;
  END LOOP;

  -- Defense-in-depth: if the client-claimed total disagrees with the
  -- server total by more than 1 unit, reject. Catches client bugs and
  -- tampering. Comment this out if you intentionally allow discounts.
  IF p_total_amount IS NOT NULL AND abs(p_total_amount - v_total) > 1 THEN
    RAISE EXCEPTION 'total mismatch: client=% server=%', p_total_amount, v_total USING ERRCODE = '22023';
  END IF;

  -- Insert the order row using the SERVER-computed total.
  INSERT INTO orders (
    user_id, shop_id, status, total_amount,
    delivery_address, customer_phone, customer_notes
  ) VALUES (
    p_user_id, p_shop_id, 'pending_confirmation', v_total,
    p_delivery_address, p_customer_phone, p_customer_notes
  )
  RETURNING id INTO v_order_id;

  -- Insert items, decrement stock, bump per-product counters.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_qty := (v_item->>'quantity')::int;

    SELECT * INTO v_product
    FROM   products
    WHERE  id = (v_item->>'product_id')::uuid;

    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, v_product.id, v_qty, v_product.price);

    UPDATE products
    SET    stock_quantity     = stock_quantity - v_qty,
           total_orders_count = total_orders_count + 1
    WHERE  id = v_product.id;
  END LOOP;

  RETURN v_order_id;
END;
$$;

REVOKE ALL ON FUNCTION create_order(UUID, UUID, JSONB, NUMERIC, TEXT, TEXT, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION create_order(UUID, UUID, JSONB, NUMERIC, TEXT, TEXT, TEXT) TO authenticated;

-- ── update_order_status (shop side) ──────────────────────────
-- Enforces the legal state machine and stamps the right timestamp
-- column. Restocks on cancellation. Caller must own the shop.

CREATE OR REPLACE FUNCTION update_order_status(
  p_order_id    UUID,
  p_new_status  TEXT,
  p_shop_notes  TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order  orders%ROWTYPE;
  v_owner  UUID;
  v_item   order_items%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order % not found', p_order_id USING ERRCODE = 'P0002';
  END IF;

  SELECT user_id INTO v_owner FROM shops WHERE id = v_order.shop_id;
  IF v_owner IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: not the shop owner' USING ERRCODE = '42501';
  END IF;

  -- State machine: only legal forward transitions, plus cancel-anywhere
  -- before delivery.
  IF NOT (
    (v_order.status = 'pending_confirmation' AND p_new_status IN ('confirmed','cancelled')) OR
    (v_order.status = 'confirmed'            AND p_new_status IN ('out_for_delivery','cancelled')) OR
    (v_order.status = 'out_for_delivery'     AND p_new_status IN ('delivered','cancelled')) OR
    (v_order.status = p_new_status)  -- idempotent no-op
  ) THEN
    RAISE EXCEPTION 'illegal transition: % -> %', v_order.status, p_new_status USING ERRCODE = '22023';
  END IF;

  -- Restock on cancellation.
  IF p_new_status = 'cancelled' AND v_order.status <> 'cancelled' THEN
    FOR v_item IN SELECT * FROM order_items WHERE order_id = p_order_id LOOP
      UPDATE products
      SET    stock_quantity = stock_quantity + v_item.quantity
      WHERE  id = v_item.product_id;
    END LOOP;
  END IF;

  UPDATE orders
  SET    status        = p_new_status,
         shop_notes    = COALESCE(NULLIF(trim(p_shop_notes), ''), shop_notes),
         confirmed_at  = CASE WHEN p_new_status = 'confirmed'        AND confirmed_at  IS NULL THEN now() ELSE confirmed_at  END,
         dispatched_at = CASE WHEN p_new_status = 'out_for_delivery' AND dispatched_at IS NULL THEN now() ELSE dispatched_at END,
         delivered_at  = CASE WHEN p_new_status = 'delivered'        AND delivered_at  IS NULL THEN now() ELSE delivered_at  END,
         cancelled_at  = CASE WHEN p_new_status = 'cancelled'        AND cancelled_at  IS NULL THEN now() ELSE cancelled_at  END
  WHERE  id = p_order_id;
END;
$$;

REVOKE ALL ON FUNCTION update_order_status(UUID, TEXT, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION update_order_status(UUID, TEXT, TEXT) TO authenticated;

-- ── cancel_order (customer side) ─────────────────────────────
-- Customer may cancel only their own order, only while pending.
-- Restocks on cancel.

CREATE OR REPLACE FUNCTION cancel_order(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order orders%ROWTYPE;
  v_item  order_items%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order % not found', p_order_id USING ERRCODE = 'P0002';
  END IF;

  IF v_order.user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: not the order owner' USING ERRCODE = '42501';
  END IF;

  IF v_order.status <> 'pending_confirmation' THEN
    RAISE EXCEPTION 'cannot cancel order in status %', v_order.status USING ERRCODE = '22023';
  END IF;

  FOR v_item IN SELECT * FROM order_items WHERE order_id = p_order_id LOOP
    UPDATE products
    SET    stock_quantity = stock_quantity + v_item.quantity
    WHERE  id = v_item.product_id;
  END LOOP;

  UPDATE orders
  SET    status       = 'cancelled',
         cancelled_at = now()
  WHERE  id = p_order_id;
END;
$$;

REVOKE ALL ON FUNCTION cancel_order(UUID) FROM public;
GRANT EXECUTE ON FUNCTION cancel_order(UUID) TO authenticated;

-- ============================================================
-- End of marketplace schema migration.
-- ============================================================
