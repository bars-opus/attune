-- ============================================================
-- payment_audit_log
-- ============================================================
--
-- Append-only ledger of sensitive payment operations. Captures
-- enough context to answer "who did what, when, and what changed"
-- without leaking PII into the table itself.
--
-- Insert path goes through the SECURITY DEFINER `record_payment_audit`
-- RPC so callers can't fabricate `actor_user_id` or `created_at`.
-- ============================================================

CREATE TABLE IF NOT EXISTS payment_audit_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  action          TEXT NOT NULL CHECK (length(action) BETWEEN 1 AND 64),
  actor_user_id   UUID,
  shop_id         UUID,
  target_id       TEXT,
  outcome         TEXT NOT NULL CHECK (outcome IN ('success','failure','denied')),
  context         JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS payment_audit_log_recent_idx
  ON payment_audit_log (created_at DESC);

CREATE INDEX IF NOT EXISTS payment_audit_log_actor_idx
  ON payment_audit_log (actor_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS payment_audit_log_shop_idx
  ON payment_audit_log (shop_id, created_at DESC);

CREATE INDEX IF NOT EXISTS payment_audit_log_action_idx
  ON payment_audit_log (action, created_at DESC);

ALTER TABLE payment_audit_log ENABLE ROW LEVEL SECURITY;

-- Shop owners can read their own shop's audit trail.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'payment_audit_log_owner_read'
  ) THEN
    CREATE POLICY payment_audit_log_owner_read ON payment_audit_log
      FOR SELECT TO authenticated
      USING (
        shop_id IN (SELECT id FROM shops WHERE user_id = auth.uid())
        OR actor_user_id = auth.uid()
      );
  END IF;
END $$;

-- No direct writes — only via record_payment_audit().

-- ── record_payment_audit RPC ────────────────────────────────
-- Called by service_role from edge functions. Hard-enforces the
-- enum on `outcome`, caps `context` size, and stamps created_at.

CREATE OR REPLACE FUNCTION record_payment_audit(
  p_action        TEXT,
  p_actor_user_id UUID,
  p_shop_id       UUID,
  p_target_id     TEXT,
  p_outcome       TEXT,
  p_context       JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_outcome NOT IN ('success','failure','denied') THEN
    RAISE EXCEPTION 'invalid outcome: %', p_outcome USING ERRCODE = '22023';
  END IF;
  IF length(coalesce(p_action,'')) = 0 OR length(p_action) > 64 THEN
    RAISE EXCEPTION 'invalid action length' USING ERRCODE = '22023';
  END IF;
  -- Defensively cap the context payload at ~8 KB.
  IF octet_length(coalesce(p_context::text, '{}')) > 8192 THEN
    RAISE EXCEPTION 'context too large' USING ERRCODE = '22023';
  END IF;

  INSERT INTO payment_audit_log (
    action, actor_user_id, shop_id, target_id, outcome, context, created_at
  )
  VALUES (
    p_action, p_actor_user_id, p_shop_id, p_target_id, p_outcome,
    coalesce(p_context, '{}'::jsonb), now()
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION record_payment_audit(TEXT, UUID, UUID, TEXT, TEXT, JSONB) FROM public;
-- service_role only — no GRANT.
