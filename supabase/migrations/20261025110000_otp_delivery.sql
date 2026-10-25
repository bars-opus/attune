-- Spec 1 W2c, migration 7 (spec §4.7 #7): otp_delivery.
--   * private.otp_delivery_intents: a request to send a number's next code
--     by WhatsApp or a call instead of SMS. Never a requirement (review
--     S-3): honoured only while under 60 s old, within 6 a number an hour,
--     and when every intent for the number in 10 minutes came from one
--     device (its hashed nonce), and only for a number with no account yet
--     (final review I-2): an existing account's code always goes by SMS.
--     Anything doubtful goes by SMS.
--   * private.otp_intent_attempts: the per-IP (10 an hour) and per-number
--     (6 an hour) intent counters, so intents themselves can go after 10
--     minutes. An IP past its limit adds nothing more (review m-3).
--   * private.otp_intent_refusals: a request refused for the number's cap
--     or its IP's limit opposes like a second device (review I-1): that
--     number's codes go by SMS for 10 minutes. One row per number.
--   * private.otp_send_events: the per-number (6 an hour, 15 a day) and
--     per-prefix hourly send limits (counted under the prefix's lock,
--     review m-2); kept 24 hours.
--   * private.otp_hook_deliveries: one delivery per code (review n-4,
--     batch 7 M-1). Auth signs each retry of a hook call afresh (a new
--     webhook-id, the same body), so send-sms-hook keys the delivery, an
--     HMAC of the number and the code, and marks it only after a provider
--     accepted it: a retry or a replay of a sent delivery sends nothing and
--     uses up no limit; the retry of one that sent nothing sends. Kept 10
--     minutes.
--   * private.otp_routes / private.otp_destination_rules: providers by
--     country and channel, and allow/block rules by calling-code prefix
--     (longest match wins; '*' is the default).
--   * public.otp_record_intent, public.otp_take_send_decision,
--     public.otp_hook_delivery_sent, public.otp_mark_hook_delivery_sent:
--     service role only (the otp-delivery-intent and send-sms-hook edge
--     functions);
--     private.otp_purge and its own cron, otp-purge (W2c tables only, §4.6).
-- No phone number is stored anywhere: only HMACs (OTP_HMAC_KEY, held by the
-- edge functions) and SHA-256 hashes.
-- Grants in 20261025110010_otp_delivery_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS private.otp_delivery_intents (
  phone_hmac text NOT NULL CONSTRAINT otp_delivery_intents_phone_hmac_check
    CHECK (phone_hmac ~ '^[0-9a-f]{64}$'),
  channel text NOT NULL CONSTRAINT otp_delivery_intents_channel_check
    CHECK (channel IN ('sms', 'whatsapp', 'voice')),
  platform text NOT NULL CONSTRAINT otp_delivery_intents_platform_check
    CHECK (platform IN ('ios', 'android', 'other')),
  locale text NOT NULL DEFAULT '' CONSTRAINT otp_delivery_intents_locale_check
    CHECK (locale ~ '^[A-Za-z0-9_-]{0,35}$'),
  device_hash text NOT NULL CONSTRAINT otp_delivery_intents_device_hash_check
    CHECK (device_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (phone_hmac, created_at)
);

CREATE TABLE IF NOT EXISTS private.otp_intent_attempts (
  kind text NOT NULL CONSTRAINT otp_intent_attempts_kind_check CHECK (kind IN ('ip', 'number')),
  key_hash text NOT NULL CONSTRAINT otp_intent_attempts_key_hash_check
    CHECK (key_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS otp_intent_attempts_key_idx
  ON private.otp_intent_attempts (kind, key_hash, created_at);

CREATE TABLE IF NOT EXISTS private.otp_intent_refusals (
  phone_hmac text PRIMARY KEY CONSTRAINT otp_intent_refusals_phone_hmac_check
    CHECK (phone_hmac ~ '^[0-9a-f]{64}$'),
  reason text NOT NULL CONSTRAINT otp_intent_refusals_reason_check
    CHECK (reason IN ('number_cap', 'ip_limit')),
  refused_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS otp_intent_refusals_refused_idx ON private.otp_intent_refusals (refused_at);

CREATE TABLE IF NOT EXISTS private.otp_send_events (
  id bigserial PRIMARY KEY,
  phone_hmac text NOT NULL CONSTRAINT otp_send_events_phone_hmac_check
    CHECK (phone_hmac ~ '^[0-9a-f]{64}$'),
  channel text NOT NULL CONSTRAINT otp_send_events_channel_check
    CHECK (channel IN ('sms', 'whatsapp', 'voice')),
  route text NOT NULL,
  country_code text NOT NULL CONSTRAINT otp_send_events_country_check
    CHECK (country_code ~ '^[A-Z]{2}$'),
  rule_prefix text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS otp_send_events_phone_idx ON private.otp_send_events (phone_hmac, created_at);
CREATE INDEX IF NOT EXISTS otp_send_events_prefix_idx ON private.otp_send_events (rule_prefix, created_at);
CREATE INDEX IF NOT EXISTS otp_send_events_created_idx ON private.otp_send_events (created_at);

CREATE TABLE IF NOT EXISTS private.otp_hook_deliveries (
  delivery_hmac text PRIMARY KEY CONSTRAINT otp_hook_deliveries_delivery_hmac_check
    CHECK (delivery_hmac ~ '^[0-9a-f]{64}$'),
  sent_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS otp_hook_deliveries_sent_idx ON private.otp_hook_deliveries (sent_at);

CREATE TABLE IF NOT EXISTS private.otp_routes (
  country_code text NOT NULL CONSTRAINT otp_routes_country_check
    CHECK (country_code ~ '^([A-Z]{2}|\*)$'),
  channel text NOT NULL CONSTRAINT otp_routes_channel_check
    CHECK (channel IN ('sms', 'whatsapp', 'voice')),
  -- One adapter each in supabase/functions/send-sms-hook/providers.ts.
  provider text NOT NULL CONSTRAINT otp_routes_provider_check
    CHECK (provider IN ('twilio', 'arkesel', 'meta')),
  priority smallint NOT NULL DEFAULT 1,
  enabled boolean NOT NULL DEFAULT true,
  PRIMARY KEY (country_code, channel, provider)
);

CREATE TABLE IF NOT EXISTS private.otp_destination_rules (
  calling_code_prefix text PRIMARY KEY CONSTRAINT otp_destination_rules_prefix_check
    CHECK (calling_code_prefix ~ '^(\+[0-9]{1,6}|\*)$'),
  rule text NOT NULL CONSTRAINT otp_destination_rules_rule_check CHECK (rule IN ('allow', 'block')),
  max_sends_per_hour integer CONSTRAINT otp_destination_rules_cap_check
    CHECK (max_sends_per_hour IS NULL OR max_sends_per_hour > 0)
);

-- Routes: Ghana direct first for GH, the global provider everywhere else
-- (spec §4.5). The owner changes these rows, not code, to re-route.
INSERT INTO private.otp_routes (country_code, channel, provider, priority) VALUES
  ('GH', 'sms', 'arkesel', 1),
  ('GH', 'sms', 'twilio', 2),
  ('*', 'sms', 'twilio', 1),
  ('*', 'whatsapp', 'meta', 1),
  ('*', 'voice', 'twilio', 1)
ON CONFLICT (country_code, channel, provider) DO NOTHING;

-- Destinations (spec §4.2): +999 is the parked-number range (W6a); the
-- other blocks are the international premium-rate and satellite ranges
-- toll fraud uses, plus the UK personal-number and premium ranges and the
-- North American 900s. The owner adds the provider's fraud list. Launch
-- countries get explicit hourly caps; every other prefix uses '*'.
INSERT INTO private.otp_destination_rules (calling_code_prefix, rule, max_sends_per_hour) VALUES
  ('+999', 'block', NULL),
  ('+979', 'block', NULL),
  ('+881', 'block', NULL),
  ('+882', 'block', NULL),
  ('+883', 'block', NULL),
  ('+870', 'block', NULL),
  ('+4470', 'block', NULL),
  ('+449', 'block', NULL),
  ('+1900', 'block', NULL),
  ('+233', 'allow', 1000),
  ('+44', 'allow', 1000),
  ('+1', 'allow', 1000),
  ('+234', 'allow', 300),
  ('+254', 'allow', 300),
  ('*', 'allow', 100)
ON CONFLICT (calling_code_prefix) DO NOTHING;

-- One refusal: counted (otp_refused:{reason}) and shaped for the hook.
CREATE OR REPLACE FUNCTION private.otp_refusal(p_reason text, p_wait interval)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM private.bump_metric_internal('otp_refused:' || p_reason);
  RETURN jsonb_build_object(
    'allowed', false,
    'reason', p_reason,
    'channel', NULL,
    'platform', NULL,
    'routes', '[]'::jsonb,
    'retry_after_s', CASE WHEN p_wait IS NULL THEN NULL
                          ELSE greatest(1, ceil(extract(epoch FROM p_wait))::integer) END);
END;
$$;

-- The ordered providers for a channel: the country's own rows first, then
-- the defaults, each provider once.
CREATE OR REPLACE FUNCTION private.otp_routes_for(p_country text, p_channel text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(
    jsonb_agg(jsonb_build_object('channel', p_channel, 'provider', x.provider)
              ORDER BY x.specific DESC, x.priority, x.provider),
    '[]'::jsonb)
    FROM (SELECT DISTINCT ON (r.provider) r.provider, r.priority, (r.country_code <> '*') AS specific
            FROM private.otp_routes AS r
           WHERE r.enabled AND r.channel = p_channel AND r.country_code IN (p_country, '*')
           ORDER BY r.provider, (r.country_code <> '*') DESC, r.priority) AS x;
$$;

-- otp-delivery-intent (spec §4.3 W2c): stores a channel request, unless the
-- IP has made 10 requests this hour or the number already has 6 stored.
-- A refused request marks the number for 10 minutes, so its next code goes
-- by SMS (review I-1: a request someone couldn't make still opposes).
-- Never raises: the endpoint answers 204 whatever happens here.
CREATE OR REPLACE FUNCTION public.otp_record_intent(
  p_phone_hmac text,
  p_channel text,
  p_platform text,
  p_locale text,
  p_device_hash text,
  p_ip_hash text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now constant timestamptz := clock_timestamp();
BEGIN
  IF p_phone_hmac IS NULL OR p_phone_hmac !~ '^[0-9a-f]{64}$'
     OR p_device_hash IS NULL OR p_device_hash !~ '^[0-9a-f]{64}$'
     OR p_channel IS NULL OR p_channel NOT IN ('sms', 'whatsapp', 'voice')
     OR (p_ip_hash IS NOT NULL AND p_ip_hash !~ '^[0-9a-f]{64}$') THEN
    RETURN jsonb_build_object('stored', false, 'reason', 'invalid');
  END IF;

  -- Counted first, at most 10 rows read, and stored only under the limit
  -- (review m-3), under the IP's own lock: a flood from one IP adds nothing
  -- past its 10. Lock order: IP, then number; nothing takes them reversed.
  IF p_ip_hash IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('otp-ip:' || p_ip_hash, 0));
    IF (SELECT count(*) FROM (SELECT 1 FROM private.otp_intent_attempts AS a
                               WHERE a.kind = 'ip' AND a.key_hash = p_ip_hash
                                 AND a.created_at > v_now - interval '1 hour'
                               LIMIT 10) AS recent) >= 10 THEN
      INSERT INTO private.otp_intent_refusals (phone_hmac, reason, refused_at)
      VALUES (p_phone_hmac, 'ip_limit', v_now)
      ON CONFLICT (phone_hmac) DO UPDATE SET reason = excluded.reason, refused_at = excluded.refused_at;
      RETURN jsonb_build_object('stored', false, 'reason', 'ip_limit');
    END IF;
    INSERT INTO private.otp_intent_attempts (kind, key_hash, created_at)
    VALUES ('ip', p_ip_hash, v_now);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('otp:' || p_phone_hmac, 0));
  IF (SELECT count(*) FROM private.otp_intent_attempts AS a
       WHERE a.kind = 'number' AND a.key_hash = p_phone_hmac
         AND a.created_at > v_now - interval '1 hour') >= 6 THEN
    INSERT INTO private.otp_intent_refusals (phone_hmac, reason, refused_at)
    VALUES (p_phone_hmac, 'number_cap', v_now)
    ON CONFLICT (phone_hmac) DO UPDATE SET reason = excluded.reason, refused_at = excluded.refused_at;
    RETURN jsonb_build_object('stored', false, 'reason', 'number_cap');
  END IF;

  DELETE FROM private.otp_delivery_intents AS i
   WHERE i.phone_hmac = p_phone_hmac AND i.created_at < v_now - interval '10 minutes';
  INSERT INTO private.otp_delivery_intents (phone_hmac, channel, platform, locale, device_hash, created_at)
  VALUES (p_phone_hmac,
          p_channel,
          CASE WHEN p_platform IN ('ios', 'android') THEN p_platform ELSE 'other' END,
          left(regexp_replace(coalesce(p_locale, ''), '[^A-Za-z0-9_-]', '', 'g'), 35),
          p_device_hash,
          v_now)
  ON CONFLICT (phone_hmac, created_at) DO NOTHING;
  INSERT INTO private.otp_intent_attempts (kind, key_hash, created_at)
  VALUES ('number', p_phone_hmac, v_now);
  RETURN jsonb_build_object('stored', true);
END;
$$;

-- send-sms-hook (spec §4.3 W2c): may this number get a code now, by which
-- channel, through which providers? The destination rule (longest prefix),
-- then 6 an hour and 15 a day per number, then the prefix's hourly cap,
-- then the channel: the newest intent counts only if it is under 60 s old,
-- every intent for the number in the last 10 minutes has the same device
-- hash, no request for the number was refused in those 10 minutes, and
-- the code opens no existing account; otherwise SMS (review S-3, I-1,
-- final review I-2). Records the send it allows.
--
-- [p_user_id] is the Auth user the code signs in to (the hook's signed
-- payload.user.id; Auth creates the user before it sends a first code). A
-- public.users row for it is an existing account: SMS whatever was asked,
-- since a code others can read (WhatsApp on a linked device, a recycled
-- number's old WhatsApp) must never open one. This, not a phone match: it
-- is exactly the account the code opens, needs no number here, and holds
-- for legacy, changed or released numbers alike. NULL (no user named)
-- counts as an existing account.
--
-- The three-argument draft of this function had no account check; it is
-- dropped so that no overload decides without one.
DROP FUNCTION IF EXISTS public.otp_take_send_decision(text, text, text);
CREATE OR REPLACE FUNCTION public.otp_take_send_decision(
  p_phone_hmac text,
  p_country text,
  p_calling_prefix text,
  p_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now constant timestamptz := clock_timestamp();
  v_country constant text :=
    CASE WHEN upper(coalesce(p_country, '')) ~ '^[A-Z]{2}$' THEN upper(p_country) ELSE 'XX' END;
  v_prefix constant text := coalesce(p_calling_prefix, '');
  v_rule private.otp_destination_rules%ROWTYPE;
  v_rule_prefix text;
  v_cap integer;
  v_count integer;
  v_oldest timestamptz;
  v_newest private.otp_delivery_intents%ROWTYPE;
  v_devices integer;
  v_channel text := 'sms';
  v_platform text := 'other';
  v_routes jsonb;
  v_fallback jsonb := '[]'::jsonb;
BEGIN
  IF p_phone_hmac IS NULL OR p_phone_hmac !~ '^[0-9a-f]{64}$' OR v_prefix !~ '^\+[0-9]{1,15}$' THEN
    RETURN private.otp_refusal('invalid', NULL);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('otp:' || p_phone_hmac, 0));

  SELECT * INTO v_rule FROM private.otp_destination_rules AS r
   WHERE r.calling_code_prefix <> '*'
     AND left(v_prefix, length(r.calling_code_prefix)) = r.calling_code_prefix
   ORDER BY length(r.calling_code_prefix) DESC
   LIMIT 1;
  IF NOT FOUND THEN
    SELECT * INTO v_rule FROM private.otp_destination_rules AS r WHERE r.calling_code_prefix = '*';
  END IF;
  v_rule_prefix := coalesce(v_rule.calling_code_prefix, '*');
  IF v_rule.rule = 'block' THEN
    RETURN private.otp_refusal('blocked', NULL);
  END IF;

  SELECT count(*), min(e.created_at) INTO v_count, v_oldest
    FROM private.otp_send_events AS e
   WHERE e.phone_hmac = p_phone_hmac AND e.created_at > v_now - interval '1 hour';
  IF v_count >= 6 THEN
    RETURN private.otp_refusal('number_hourly', v_oldest + interval '1 hour' - v_now);
  END IF;
  SELECT count(*), min(e.created_at) INTO v_count, v_oldest
    FROM private.otp_send_events AS e
   WHERE e.phone_hmac = p_phone_hmac AND e.created_at > v_now - interval '24 hours';
  IF v_count >= 15 THEN
    RETURN private.otp_refusal('number_daily', v_oldest + interval '24 hours' - v_now);
  END IF;

  v_cap := coalesce(
    v_rule.max_sends_per_hour,
    (SELECT r.max_sends_per_hour FROM private.otp_destination_rules AS r WHERE r.calling_code_prefix = '*'));
  IF v_cap IS NOT NULL THEN
    -- The count and the send recorded below happen under the prefix's own
    -- lock, held to commit, so concurrent sends to one prefix can't all
    -- see room for one (review m-2). Lock order: number, then prefix.
    PERFORM pg_advisory_xact_lock(hashtextextended('otp-prefix:' || v_rule_prefix, 0));
    SELECT count(*), min(e.created_at) INTO v_count, v_oldest
      FROM private.otp_send_events AS e
     WHERE e.rule_prefix = v_rule_prefix AND e.created_at > v_now - interval '1 hour';
    IF v_count >= v_cap THEN
      RETURN private.otp_refusal('prefix_hourly', v_oldest + interval '1 hour' - v_now);
    END IF;
  END IF;

  SELECT * INTO v_newest FROM private.otp_delivery_intents AS i
   WHERE i.phone_hmac = p_phone_hmac AND i.created_at > v_now - interval '10 minutes'
   ORDER BY i.created_at DESC
   LIMIT 1;
  IF FOUND THEN
    v_platform := v_newest.platform;
    SELECT count(DISTINCT i.device_hash) INTO v_devices
      FROM private.otp_delivery_intents AS i
     WHERE i.phone_hmac = p_phone_hmac AND i.created_at > v_now - interval '10 minutes';
    -- A request refused in the last 10 minutes opposes like another device.
    IF EXISTS (SELECT 1 FROM private.otp_intent_refusals AS r
                WHERE r.phone_hmac = p_phone_hmac AND r.refused_at > v_now - interval '10 minutes') THEN
      v_devices := v_devices + 1;
    END IF;
    -- Final review I-2: and only for a number with no account yet.
    IF v_newest.created_at > v_now - interval '60 seconds' AND v_devices = 1
       AND p_user_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user_id) THEN
      v_channel := v_newest.channel;
    END IF;
  END IF;

  v_routes := private.otp_routes_for(v_country, v_channel);
  IF v_channel <> 'sms' AND jsonb_array_length(v_routes) = 0 THEN
    v_channel := 'sms';
    v_routes := private.otp_routes_for(v_country, 'sms');
  END IF;
  IF v_channel <> 'sms' THEN
    v_fallback := private.otp_routes_for(v_country, 'sms');
  END IF;
  IF jsonb_array_length(v_routes) + jsonb_array_length(v_fallback) = 0 THEN
    RETURN private.otp_refusal('no_route', NULL);
  END IF;

  INSERT INTO private.otp_send_events (phone_hmac, channel, route, country_code, rule_prefix, created_at)
  VALUES (p_phone_hmac, v_channel, (v_routes || v_fallback) -> 0 ->> 'provider', v_country, v_rule_prefix, v_now);

  RETURN jsonb_build_object(
    'allowed', true,
    'reason', NULL,
    'channel', v_channel,
    'platform', v_platform,
    'routes', v_routes || v_fallback,
    'retry_after_s', NULL);
END;
$$;

-- send-sms-hook (review n-4, batch 7 M-1): has a provider already accepted
-- this delivery? True when [p_delivery_hmac] (the hook's HMAC of the number
-- and the code) was marked sent in the last 10 minutes: the hook then
-- answers a retry or a replay as sent and sends nothing. Asking never
-- marks, so the retry of an attempt that sent nothing is decided and sent
-- again. A malformed key raises, so the hook fails closed and never takes
-- it for a sent delivery.
CREATE OR REPLACE FUNCTION public.otp_hook_delivery_sent(p_delivery_hmac text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_delivery_hmac IS NULL OR p_delivery_hmac !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'otp_hook_delivery_sent: malformed delivery key' USING ERRCODE = '22023';
  END IF;
  RETURN EXISTS (SELECT 1 FROM private.otp_hook_deliveries AS d
                  WHERE d.delivery_hmac = p_delivery_hmac
                    AND d.sent_at > clock_timestamp() - interval '10 minutes');
END;
$$;

-- send-sms-hook, once a provider accepted the delivery: marks it sent (one
-- row, renewed if it is marked again). Its own short call after the send.
CREATE OR REPLACE FUNCTION public.otp_mark_hook_delivery_sent(p_delivery_hmac text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_delivery_hmac IS NULL OR p_delivery_hmac !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'otp_mark_hook_delivery_sent: malformed delivery key' USING ERRCODE = '22023';
  END IF;
  INSERT INTO private.otp_hook_deliveries AS d (delivery_hmac, sent_at)
  VALUES (p_delivery_hmac, clock_timestamp())
  ON CONFLICT (delivery_hmac) DO UPDATE SET sent_at = excluded.sent_at;
END;
$$;

-- Retention (spec §4.8): intents, refusal marks and sent-delivery marks 10
-- minutes, counters 1 hour, send events 24 hours. Names only W2c tables
-- (§4.6, review I-1).
CREATE OR REPLACE FUNCTION private.otp_purge()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  DELETE FROM private.otp_delivery_intents WHERE created_at < clock_timestamp() - interval '10 minutes';
  DELETE FROM private.otp_intent_attempts WHERE created_at < clock_timestamp() - interval '1 hour';
  DELETE FROM private.otp_intent_refusals WHERE refused_at < clock_timestamp() - interval '10 minutes';
  DELETE FROM private.otp_send_events WHERE created_at < clock_timestamp() - interval '24 hours';
  DELETE FROM private.otp_hook_deliveries WHERE sent_at < clock_timestamp() - interval '10 minutes';
$$;

DO $$
BEGIN
  PERFORM cron.unschedule('otp-purge');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;
SELECT cron.schedule('otp-purge', '13 * * * *', $cron$SELECT private.otp_purge()$cron$);

-- Revoked here as well as in the twin (the W1 precedent): the hosted
-- default privileges grant a new function and a new table to anon and
-- authenticated, and a late twin must not leave a code's channel or a
-- send limit writable by a client.
REVOKE ALL ON private.otp_delivery_intents, private.otp_intent_attempts, private.otp_intent_refusals,
              private.otp_send_events, private.otp_routes, private.otp_destination_rules,
              private.otp_hook_deliveries
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE private.otp_send_events_id_seq FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.otp_refusal(text, interval) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.otp_routes_for(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.otp_purge() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.otp_record_intent(text, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.otp_take_send_decision(text, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.otp_hook_delivery_sent(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.otp_mark_hook_delivery_sent(text) FROM PUBLIC, anon, authenticated;

COMMIT;
