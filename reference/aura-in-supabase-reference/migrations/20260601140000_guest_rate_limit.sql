-- Database-backed rate limiting for guest-facing edge functions.
--
-- The guest booking path (resolve-link, lookup-guest, get-slots,
-- create-booking with no JWT) is open to anyone on the internet. Without a
-- rate limit, a single misbehaving client (or an attacker) can:
--   * Burn through Paystack/Stripe checkout quotas with create-booking floods
--   * Enumerate slugs against resolve-link to map every shop in the system
--   * Probe lookup-guest with a list of phone numbers
--
-- This is a simple sliding-window counter keyed by (endpoint, ip). For v1
-- we accept the per-request DB roundtrip; if it becomes a hot spot we'll
-- switch to an in-memory token bucket per region.

CREATE TABLE IF NOT EXISTS rate_limit_events (
  id          BIGSERIAL PRIMARY KEY,
  key         TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS rate_limit_events_key_created_idx
  ON rate_limit_events (key, created_at DESC);

-- Atomic rate-limit check. Counts events in the trailing window, returns
-- TRUE if the caller is under the limit (and records this hit), FALSE if
-- they should be 429'd. Old rows are pruned opportunistically on each call.
--
-- DROP first because an older check_rate_limit with a different return type
-- may exist in some environments (Postgres rejects CREATE OR REPLACE when
-- the return signature changes).
DROP FUNCTION IF EXISTS check_rate_limit(TEXT, INT, INT);

CREATE OR REPLACE FUNCTION check_rate_limit(
  p_key            TEXT,
  p_max            INT,
  p_window_seconds INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count        INT;
  v_window_start TIMESTAMPTZ := NOW() - (p_window_seconds || ' seconds')::INTERVAL;
BEGIN
  -- Opportunistic GC: drop rows older than 10 windows for this key.
  -- Keeps the table size bounded without a separate cron.
  DELETE FROM rate_limit_events
  WHERE key = p_key
    AND created_at < NOW() - (p_window_seconds * 10 || ' seconds')::INTERVAL;

  SELECT COUNT(*) INTO v_count
  FROM rate_limit_events
  WHERE key = p_key
    AND created_at >= v_window_start;

  IF v_count >= p_max THEN
    RETURN FALSE;
  END IF;

  INSERT INTO rate_limit_events (key) VALUES (p_key);
  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION check_rate_limit(TEXT, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION check_rate_limit(TEXT, INT, INT) TO service_role;

COMMENT ON FUNCTION check_rate_limit IS
  'Sliding-window rate limit. Returns TRUE if caller is allowed (and records the hit); FALSE if over the limit. Use key = "<endpoint>:<ip>" convention.';
