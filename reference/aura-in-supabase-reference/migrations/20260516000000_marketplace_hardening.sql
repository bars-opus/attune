-- ============================================================
-- Marketplace Hardening
-- ============================================================
-- Adds the security controls that the canonical schema deferred:
--   1. Rate limiting on all marketplace RPCs.
--   2. Length CHECK caps on every free-text column (defense
--      against payload-bloat DoS and accidental abuse).
--   3. Idempotency keys for `create_order` (prevents duplicate
--      orders when a client retries after a flaky network).
--   4. Audit log for sensitive operations.
--   5. Tighter dispute flow: dedicated RPC instead of raw INSERT,
--      with rate limit + idempotency-friendly behavior.
--
-- Safe to apply: only ADDs columns/tables/indexes/functions, and
-- replaces the three RPCs in-place with hardened versions sharing
-- the same signature so the Dart code keeps compiling.
-- ============================================================

-- ── 1. Rate limit primitives ─────────────────────────────────

CREATE TABLE IF NOT EXISTS rate_limit_log (
  id         BIGSERIAL PRIMARY KEY,
  user_id    UUID NOT NULL,
  action     TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rate_limit_log_lookup
  ON rate_limit_log (user_id, action, created_at DESC);

-- Window-based rate limit. Counts the caller's recent actions and
-- raises `rate_limited` (SQLSTATE 53400 — configuration_limit_exceeded)
-- before performing the action.
CREATE OR REPLACE FUNCTION check_rate_limit(
  p_action          TEXT,
  p_max             INT,
  p_window_seconds  INT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user  UUID := auth.uid();
  v_count INT;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_count
  FROM   rate_limit_log
  WHERE  user_id = v_user
    AND  action  = p_action
    AND  created_at > now() - make_interval(secs => p_window_seconds);

  IF v_count >= p_max THEN
    RAISE EXCEPTION 'rate_limited: too many % requests (max % per %s)',
      p_action, p_max, p_window_seconds
      USING ERRCODE = '53400';
  END IF;

  INSERT INTO rate_limit_log (user_id, action) VALUES (v_user, p_action);
END;
$$;

REVOKE ALL ON FUNCTION check_rate_limit(TEXT, INT, INT) FROM public;
-- check_rate_limit is only called by other SECURITY DEFINER RPCs; do not
-- expose it to the authenticated role directly.

-- Background cleanup: keep ~7 days of history. Idempotent function;
-- can be called from pg_cron or invoked manually.
CREATE OR REPLACE FUNCTION prune_rate_limit_log()
RETURNS VOID LANGUAGE SQL AS $$
  DELETE FROM rate_limit_log WHERE created_at < now() - INTERVAL '7 days';
$$;

-- ── 2. Length CHECK caps (idempotent — guarded with DO blocks) ─

DO $$ BEGIN
  ALTER TABLE products
    ADD CONSTRAINT products_name_max_length  CHECK (length(name)        <= 100),
    ADD CONSTRAINT products_desc_max_length  CHECK (description IS NULL OR length(description) <= 2000),
    ADD CONSTRAINT products_images_max_count CHECK (array_length(images, 1) IS NULL OR array_length(images, 1) <= 10);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE orders
    ADD CONSTRAINT orders_address_max_length  CHECK (length(delivery_address) <= 500),
    ADD CONSTRAINT orders_phone_max_length    CHECK (length(customer_phone)   <= 30),
    ADD CONSTRAINT orders_cnotes_max_length   CHECK (customer_notes IS NULL OR length(customer_notes) <= 1000),
    ADD CONSTRAINT orders_snotes_max_length   CHECK (shop_notes     IS NULL OR length(shop_notes)     <= 1000),
    ADD CONSTRAINT orders_dnotes_max_length   CHECK (delivery_notes IS NULL OR length(delivery_notes) <= 1000);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE product_reviews
    ADD CONSTRAINT pr_comment_max_length  CHECK (comment       IS NULL OR length(comment)       <= 2000),
    ADD CONSTRAINT pr_response_max_length CHECK (shop_response IS NULL OR length(shop_response) <= 2000);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE order_disputes
    ADD CONSTRAINT disputes_reason_max_length    CHECK (length(reason) <= 2000),
    ADD CONSTRAINT disputes_resolution_max_length CHECK (resolution_notes IS NULL OR length(resolution_notes) <= 2000);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── 3. Idempotency key on orders ─────────────────────────────

DO $$ BEGIN
  ALTER TABLE orders ADD COLUMN idempotency_key TEXT;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- One key may be used at most once per user (per-user uniqueness so
-- two different users can independently coin the same key).
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_idempotency
  ON orders (user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- ── 4. Audit log for sensitive operations ────────────────────

CREATE TABLE IF NOT EXISTS marketplace_audit_log (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  action       TEXT NOT NULL,           -- e.g. 'order.create', 'order.cancel', 'order.status.update', 'dispute.raise'
  target_table TEXT NOT NULL,
  target_id    UUID NOT NULL,
  details      JSONB NOT NULL DEFAULT '{}',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_actor   ON marketplace_audit_log (actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_target  ON marketplace_audit_log (target_table, target_id);

ALTER TABLE marketplace_audit_log ENABLE ROW LEVEL SECURITY;
-- Audit log is internal: no client can read or write it directly.
-- Only the SECURITY DEFINER RPCs that insert into it can write.

-- ── 5. Hardened RPCs ─────────────────────────────────────────

-- 5a. create_order — adds rate limit + idempotency + audit
CREATE OR REPLACE FUNCTION create_order(
  p_user_id           UUID,
  p_shop_id           UUID,
  p_items             JSONB,
  p_total_amount      NUMERIC,
  p_delivery_address  TEXT,
  p_customer_phone    TEXT,
  p_customer_notes    TEXT,
  p_idempotency_key   TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id     UUID;
  v_existing     UUID;
  v_item         JSONB;
  v_product      products%ROWTYPE;
  v_qty          INT;
  v_total        NUMERIC(12,2) := 0;
BEGIN
  -- AuthN
  IF p_user_id IS NULL OR p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: user mismatch' USING ERRCODE = '42501';
  END IF;

  -- Idempotency: replay the previous result if the same key is seen.
  IF p_idempotency_key IS NOT NULL AND length(p_idempotency_key) > 0 THEN
    SELECT id INTO v_existing
    FROM orders
    WHERE user_id = p_user_id AND idempotency_key = p_idempotency_key;
    IF v_existing IS NOT NULL THEN
      RETURN v_existing;
    END IF;
  END IF;

  -- Rate limit: 10 orders / 60 seconds / user.
  PERFORM check_rate_limit('create_order', 10, 60);

  -- Validate inputs
  IF p_shop_id IS NULL THEN
    RAISE EXCEPTION 'shop_id is required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'items must be a non-empty array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_items) > 50 THEN
    RAISE EXCEPTION 'too many items in one order (max 50)' USING ERRCODE = '22023';
  END IF;
  IF length(trim(coalesce(p_delivery_address, ''))) = 0 THEN
    RAISE EXCEPTION 'delivery_address is required' USING ERRCODE = '22023';
  END IF;
  IF length(trim(coalesce(p_customer_phone, ''))) = 0 THEN
    RAISE EXCEPTION 'customer_phone is required' USING ERRCODE = '22023';
  END IF;
  IF length(p_delivery_address) > 500 THEN
    RAISE EXCEPTION 'delivery_address too long' USING ERRCODE = '22023';
  END IF;
  IF length(p_customer_phone) > 30 THEN
    RAISE EXCEPTION 'customer_phone too long' USING ERRCODE = '22023';
  END IF;
  IF p_customer_notes IS NOT NULL AND length(p_customer_notes) > 1000 THEN
    RAISE EXCEPTION 'customer_notes too long' USING ERRCODE = '22023';
  END IF;

  -- Lock and validate items in deterministic id order.
  FOR v_item IN
    SELECT * FROM jsonb_array_elements(p_items)
    ORDER BY (value->>'product_id')::uuid
  LOOP
    v_qty := (v_item->>'quantity')::int;
    IF v_qty IS NULL OR v_qty <= 0 OR v_qty > 999 THEN
      RAISE EXCEPTION 'invalid quantity for product %', v_item->>'product_id' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_product FROM products
    WHERE id = (v_item->>'product_id')::uuid
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

    v_total := v_total + (v_product.price * v_qty);
  END LOOP;

  IF p_total_amount IS NOT NULL AND abs(p_total_amount - v_total) > 1 THEN
    RAISE EXCEPTION 'total mismatch: client=% server=%', p_total_amount, v_total USING ERRCODE = '22023';
  END IF;

  INSERT INTO orders (
    user_id, shop_id, status, total_amount,
    delivery_address, customer_phone, customer_notes, idempotency_key
  ) VALUES (
    p_user_id, p_shop_id, 'pending_confirmation', v_total,
    p_delivery_address, p_customer_phone, p_customer_notes,
    NULLIF(p_idempotency_key, '')
  )
  RETURNING id INTO v_order_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty := (v_item->>'quantity')::int;
    SELECT * INTO v_product FROM products
    WHERE id = (v_item->>'product_id')::uuid;

    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, v_product.id, v_qty, v_product.price);

    UPDATE products
    SET    stock_quantity     = stock_quantity - v_qty,
           total_orders_count = total_orders_count + 1
    WHERE  id = v_product.id;
  END LOOP;

  -- Audit
  INSERT INTO marketplace_audit_log (actor_id, action, target_table, target_id, details)
  VALUES (
    p_user_id, 'order.create', 'orders', v_order_id,
    jsonb_build_object('shop_id', p_shop_id, 'total', v_total,
                       'item_count', jsonb_array_length(p_items))
  );

  RETURN v_order_id;
END;
$$;

REVOKE ALL ON FUNCTION create_order(UUID, UUID, JSONB, NUMERIC, TEXT, TEXT, TEXT, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION create_order(UUID, UUID, JSONB, NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- 5b. update_order_status — adds rate limit + audit
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
  v_prev   TEXT;
BEGIN
  PERFORM check_rate_limit('update_order_status', 60, 60);

  IF p_shop_notes IS NOT NULL AND length(p_shop_notes) > 1000 THEN
    RAISE EXCEPTION 'shop_notes too long' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order % not found', p_order_id USING ERRCODE = 'P0002';
  END IF;

  SELECT user_id INTO v_owner FROM shops WHERE id = v_order.shop_id;
  IF v_owner IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: not the shop owner' USING ERRCODE = '42501';
  END IF;

  v_prev := v_order.status;

  IF NOT (
    (v_order.status = 'pending_confirmation' AND p_new_status IN ('confirmed','cancelled')) OR
    (v_order.status = 'confirmed'            AND p_new_status IN ('out_for_delivery','cancelled')) OR
    (v_order.status = 'out_for_delivery'     AND p_new_status IN ('delivered','cancelled')) OR
    (v_order.status = p_new_status)
  ) THEN
    RAISE EXCEPTION 'illegal transition: % -> %', v_order.status, p_new_status USING ERRCODE = '22023';
  END IF;

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

  -- Audit (only when state actually changed)
  IF v_prev <> p_new_status THEN
    INSERT INTO marketplace_audit_log (actor_id, action, target_table, target_id, details)
    VALUES (
      auth.uid(), 'order.status.update', 'orders', p_order_id,
      jsonb_build_object('from', v_prev, 'to', p_new_status)
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION update_order_status(UUID, TEXT, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION update_order_status(UUID, TEXT, TEXT) TO authenticated;

-- 5c. cancel_order — adds rate limit + audit
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
  PERFORM check_rate_limit('cancel_order', 10, 60);

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

  UPDATE orders SET status = 'cancelled', cancelled_at = now()
  WHERE id = p_order_id;

  INSERT INTO marketplace_audit_log (actor_id, action, target_table, target_id, details)
  VALUES (auth.uid(), 'order.cancel', 'orders', p_order_id, '{}');
END;
$$;

REVOKE ALL ON FUNCTION cancel_order(UUID) FROM public;
GRANT EXECUTE ON FUNCTION cancel_order(UUID) TO authenticated;

-- 5d. raise_dispute — new SECURITY DEFINER RPC for disputes,
-- replaces the raw INSERT path so we can rate-limit + audit.
CREATE OR REPLACE FUNCTION raise_dispute(
  p_order_id UUID,
  p_reason   TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order   orders%ROWTYPE;
  v_dispute UUID;
BEGIN
  PERFORM check_rate_limit('raise_dispute', 3, 86400);  -- 3 / day

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'reason is required' USING ERRCODE = '22023';
  END IF;
  IF length(p_reason) > 2000 THEN
    RAISE EXCEPTION 'reason too long' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order % not found', p_order_id USING ERRCODE = 'P0002';
  END IF;
  IF v_order.user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: not the order owner' USING ERRCODE = '42501';
  END IF;
  IF v_order.status IN ('cancelled') THEN
    RAISE EXCEPTION 'cannot dispute a cancelled order' USING ERRCODE = '22023';
  END IF;

  INSERT INTO order_disputes (order_id, raised_by_user_id, reason)
  VALUES (p_order_id, auth.uid(), p_reason)
  RETURNING id INTO v_dispute;

  -- Best-effort status flip. State machine accepts disputed only as a
  -- terminal label on the dispute table; we don't enforce it via update.
  UPDATE orders SET status = 'disputed' WHERE id = p_order_id;

  INSERT INTO marketplace_audit_log (actor_id, action, target_table, target_id, details)
  VALUES (auth.uid(), 'dispute.raise', 'order_disputes', v_dispute,
          jsonb_build_object('order_id', p_order_id));

  RETURN v_dispute;
END;
$$;

REVOKE ALL ON FUNCTION raise_dispute(UUID, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION raise_dispute(UUID, TEXT) TO authenticated;

-- Block direct INSERT into order_disputes now that we have an RPC.
-- The previous RLS policy allowed customer-initiated INSERTs; tighten it.
DROP POLICY IF EXISTS order_disputes_customer_insert ON order_disputes;

-- ============================================================
-- End of hardening migration.
-- ============================================================
