-- supabase/tests/otp_delivery_contracts.sql
-- Spec 1 W2c (§4.2, §4.3 W2c, §7.1, review S-3): phone-code delivery. A
-- channel request is honoured only when fresh, capped and from one device;
-- per-number, per-day and per-prefix limits; blocked destinations; routes
-- by country; one delivery per code (n-4); retention; no client access.
-- One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/otp_delivery_contracts.sql
-- Numbers never appear: fixtures are SHA-256 hex of a label, standing in
-- for the edge functions' HMACs. Every refusal is checked by its reason.
BEGIN;

CREATE FUNCTION pg_temp.h(p text) RETURNS text LANGUAGE sql AS $$
  SELECT encode(extensions.digest(p, 'sha256'), 'hex');
$$;

-- An intent written directly, at a chosen age. (plpgsql, so the helpers
-- can be created before the migration and section A says what is missing.)
CREATE FUNCTION pg_temp.intent(p_number text, p_device text, p_channel text, p_age interval,
                               p_platform text DEFAULT 'android') RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO private.otp_delivery_intents (phone_hmac, channel, platform, locale, device_hash, created_at)
  VALUES (pg_temp.h(p_number), p_channel, p_platform, 'en', pg_temp.h(p_device), clock_timestamp() - p_age);
END $$;

-- A past send, at a chosen age.
CREATE FUNCTION pg_temp.sent(p_number text, p_age interval, p_prefix text DEFAULT '+233') RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO private.otp_send_events (phone_hmac, channel, route, country_code, rule_prefix, created_at)
  VALUES (pg_temp.h(p_number), 'sms', 'twilio', 'GH', p_prefix, clock_timestamp() - p_age);
END $$;

-- The decision for a number with no account yet (a fresh Auth user, no
-- users row), unless [p_user] names one (final review I-2).
CREATE FUNCTION pg_temp.decide(p_number text, p_country text DEFAULT 'GH', p_prefix text DEFAULT '+233244',
                               p_user uuid DEFAULT gen_random_uuid())
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  RETURN public.otp_take_send_decision(pg_temp.h(p_number), p_country, p_prefix, p_user);
END $$;

-- =====================================================================
-- A. Objects and grants: the edge functions' four calls are service role
--    only; tables, the sequence and the helpers are closed to every client
--    (review m-1: every privilege, for anon, authenticated and PUBLIC).
--    Every W2c function is SECURITY DEFINER with search_path '' (batch 7
--    M-2): the service role can't reach private, so an invoker function
--    would refuse every send.
-- =====================================================================
DO $$
DECLARE
  v_role text;
  v_object text;
  v_priv text;
BEGIN
  IF to_regprocedure('public.otp_take_send_decision(text,text,text,uuid)') IS NULL
     OR to_regprocedure('public.otp_record_intent(text,text,text,text,text,text)') IS NULL
     OR to_regprocedure('public.otp_hook_delivery_sent(text)') IS NULL
     OR to_regprocedure('public.otp_mark_hook_delivery_sent(text)') IS NULL
     OR to_regclass('private.otp_hook_deliveries') IS NULL
     OR to_regprocedure('private.otp_purge()') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W2c objects are missing (otp_take_send_decision, otp_record_intent, otp_hook_delivery_sent, otp_mark_hook_delivery_sent, otp_hook_deliveries, otp_purge)';
  END IF;
  IF to_regprocedure('public.otp_claim_hook_delivery(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the claim-before-send otp_claim_hook_delivery still exists (batch 7 M-1)';
  END IF;
  -- Final review I-2: no overload decides without the account the code opens.
  IF to_regprocedure('public.otp_take_send_decision(text,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the three-argument otp_take_send_decision (no account check) still exists (final review I-2)';
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_object
    FROM pg_proc AS p
   WHERE p.oid IN ('public.otp_take_send_decision(text,text,text,uuid)'::regprocedure,
                   'public.otp_record_intent(text,text,text,text,text,text)'::regprocedure,
                   'public.otp_hook_delivery_sent(text)'::regprocedure,
                   'public.otp_mark_hook_delivery_sent(text)'::regprocedure,
                   'private.otp_refusal(text,interval)'::regprocedure,
                   'private.otp_routes_for(text,text)'::regprocedure,
                   'private.otp_purge()'::regprocedure)
     AND (NOT p.prosecdef OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']);
  IF v_object IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W2c functions that are not SECURITY DEFINER with search_path '''': %', v_object;
  END IF;
  IF NOT has_function_privilege('service_role', 'public.otp_take_send_decision(text,text,text,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.otp_record_intent(text,text,text,text,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.otp_hook_delivery_sent(text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.otp_mark_hook_delivery_sent(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: OTP function grants are wrong: service_role cannot call the decisions';
  END IF;
  FOREACH v_object IN ARRAY ARRAY['private.otp_refusal(text,interval)', 'private.otp_routes_for(text,text)',
                                  'private.otp_purge()'] LOOP
    IF has_function_privilege('service_role', v_object, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: OTP function grants are wrong: service_role can call %', v_object;
    END IF;
  END LOOP;
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'public'] LOOP
    FOREACH v_object IN ARRAY ARRAY['public.otp_take_send_decision(text,text,text,uuid)',
                                    'public.otp_record_intent(text,text,text,text,text,text)',
                                    'public.otp_hook_delivery_sent(text)',
                                    'public.otp_mark_hook_delivery_sent(text)',
                                    'private.otp_refusal(text,interval)', 'private.otp_routes_for(text,text)',
                                    'private.otp_purge()'] LOOP
      IF has_function_privilege(v_role, v_object, 'EXECUTE') THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: OTP function grants are wrong: % can call %', v_role, v_object;
      END IF;
    END LOOP;
    FOREACH v_object IN ARRAY ARRAY['private.otp_delivery_intents', 'private.otp_intent_attempts',
                                    'private.otp_intent_refusals', 'private.otp_send_events',
                                    'private.otp_routes', 'private.otp_destination_rules',
                                    'private.otp_hook_deliveries'] LOOP
      FOREACH v_priv IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] LOOP
        IF has_table_privilege(v_role, v_object, v_priv) THEN
          RAISE EXCEPTION 'CONTRACT VIOLATED: a client can reach %: % has %', v_object, v_role, v_priv;
        END IF;
      END LOOP;
    END LOOP;
    FOREACH v_priv IN ARRAY ARRAY['USAGE', 'SELECT', 'UPDATE'] LOOP
      IF has_sequence_privilege(v_role, 'private.otp_send_events_id_seq', v_priv) THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: a client can reach private.otp_send_events_id_seq: % has %', v_role, v_priv;
      END IF;
    END LOOP;
  END LOOP;
END $$;

-- =====================================================================
-- B. Intents (review S-3): a request, never a requirement.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
BEGIN
  -- B1. No intent: SMS, on the country's routes (Ghana direct first).
  v := pg_temp.decide('b1');
  IF NOT (v ->> 'allowed')::boolean OR v ->> 'channel' <> 'sms' OR v ->> 'platform' <> 'other'
     OR v -> 'routes' <> '[{"channel": "sms", "provider": "arkesel"}, {"channel": "sms", "provider": "twilio"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no intent did not mean SMS by the Ghana routes: %', v;
  END IF;

  -- B2. A fresh intent from one device moves the code, with SMS behind it.
  PERFORM pg_temp.intent('b2', 'phone-a', 'whatsapp', interval '5 seconds');
  v := pg_temp.decide('b2', 'GB', '+447911');
  IF v ->> 'channel' <> 'whatsapp' OR v ->> 'platform' <> 'android'
     OR v -> 'routes' <> '[{"channel": "whatsapp", "provider": "meta"}, {"channel": "sms", "provider": "twilio"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh single-device intent was not honoured: %', v;
  END IF;

  -- B3. Older than 60 seconds: SMS (its platform still shapes the text).
  PERFORM pg_temp.intent('b3', 'phone-a', 'voice', interval '90 seconds');
  v := pg_temp.decide('b3');
  IF v ->> 'channel' <> 'sms' OR v ->> 'platform' <> 'android' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stale intent moved the code: %', v;
  END IF;

  -- B4. Two devices asked for one number within 10 minutes: SMS.
  PERFORM pg_temp.intent('b4', 'phone-a', 'sms', interval '5 minutes');
  PERFORM pg_temp.intent('b4', 'stranger', 'whatsapp', interval '3 seconds');
  v := pg_temp.decide('b4');
  IF v ->> 'channel' <> 'sms' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an opposed intent moved the code: %', v;
  END IF;

  -- B5. An intent older than 10 minutes doesn't oppose anything.
  PERFORM pg_temp.intent('b5', 'old-phone', 'sms', interval '11 minutes');
  PERFORM pg_temp.intent('b5', 'phone-a', 'voice', interval '2 seconds');
  v := pg_temp.decide('b5');
  IF v ->> 'channel' <> 'voice'
     OR v -> 'routes' <> '[{"channel": "voice", "provider": "twilio"}, {"channel": "sms", "provider": "arkesel"}, {"channel": "sms", "provider": "twilio"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an expired intent still counted: %', v;
  END IF;
END $$;

DO $$
DECLARE
  v jsonb;
  v_i integer;
BEGIN
  -- B6. The 7th intent for a number in an hour isn't stored, and the send
  --     falls back to SMS (the six stored ones are no longer fresh).
  FOR v_i IN 1..6 LOOP
    v := public.otp_record_intent(pg_temp.h('b6'), 'whatsapp', 'ios', 'en-GB', pg_temp.h('phone-a'), NULL);
    IF NOT (v ->> 'stored')::boolean THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: intent % of 6 was refused: %', v_i, v;
    END IF;
  END LOOP;
  UPDATE private.otp_delivery_intents SET created_at = created_at - interval '2 minutes'
   WHERE phone_hmac = pg_temp.h('b6');
  v := public.otp_record_intent(pg_temp.h('b6'), 'whatsapp', 'ios', 'en-GB', pg_temp.h('phone-a'), NULL);
  IF (v ->> 'stored')::boolean OR v ->> 'reason' <> 'number_cap' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 7th intent in an hour was stored: %', v;
  END IF;
  v := pg_temp.decide('b6');
  IF v ->> 'channel' <> 'sms' OR v ->> 'platform' <> 'ios' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: past the cap the send was not SMS: %', v;
  END IF;

  -- B7. One IP: 10 requests an hour, then nothing is stored.
  FOR v_i IN 1..10 LOOP
    v := public.otp_record_intent(pg_temp.h('b7-' || v_i), 'sms', 'android', 'en', pg_temp.h('d'), pg_temp.h('ip-1'));
  END LOOP;
  v := public.otp_record_intent(pg_temp.h('b7-11'), 'sms', 'android', 'en', pg_temp.h('d'), pg_temp.h('ip-1'));
  IF (v ->> 'stored')::boolean OR v ->> 'reason' <> 'ip_limit' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 11th request from one IP was stored: %', v;
  END IF;

  -- B8. Malformed input is refused quietly, never raised.
  v := public.otp_record_intent('not-a-hash', 'whatsapp', 'ios', 'en', pg_temp.h('d'), NULL);
  IF (v ->> 'stored')::boolean OR v ->> 'reason' <> 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed intent was stored: %', v;
  END IF;
  v := public.otp_record_intent(pg_temp.h('b8'), 'carrier-pigeon', 'ios', 'en', pg_temp.h('d'), NULL);
  IF (v ->> 'stored')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown channel was stored';
  END IF;

  -- B9. A stored locale keeps only safe characters; an unknown platform is "other".
  PERFORM public.otp_record_intent(pg_temp.h('b9'), 'sms', 'symbian', 'en-GB<script>', pg_temp.h('d'), NULL);
  IF NOT EXISTS (SELECT 1 FROM private.otp_delivery_intents
                  WHERE phone_hmac = pg_temp.h('b9') AND platform = 'other' AND locale = 'en-GBscript') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: platform or locale was stored as sent';
  END IF;
END $$;

-- B10 (review I-1). A refused request opposes: a number whose request was
-- refused for its cap or for its IP's limit goes by SMS for 10 minutes,
-- even when every stored intent is one stranger's and fresh.
DO $$
DECLARE
  v jsonb;
  v_i integer;
BEGIN
  -- (a) A stranger fills the number's hourly cap with fresh WhatsApp
  --     requests from one device; the owner's own request is refused.
  FOR v_i IN 1..6 LOOP
    PERFORM public.otp_record_intent(pg_temp.h('b10'), 'whatsapp', 'android', 'en', pg_temp.h('stranger'), NULL);
  END LOOP;
  v := public.otp_record_intent(pg_temp.h('b10'), 'sms', 'ios', 'en', pg_temp.h('owner'), NULL);
  IF (v ->> 'stored')::boolean OR v ->> 'reason' <> 'number_cap' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner''s request past the cap was stored: %', v;
  END IF;
  v := pg_temp.decide('b10');
  IF v ->> 'channel' <> 'sms' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a request refused at the number''s cap did not oppose: %', v;
  END IF;

  -- (b) A shared mobile IP (CGNAT) has used its hour; one fresh stranger
  --     asks for a call; the owner's request from the shared IP is refused.
  FOR v_i IN 1..10 LOOP
    PERFORM public.otp_record_intent(pg_temp.h('b10-other-' || v_i), 'sms', 'android', 'en',
                                     pg_temp.h('someone'), pg_temp.h('cgnat'));
  END LOOP;
  PERFORM public.otp_record_intent(pg_temp.h('b10b'), 'voice', 'android', 'en', pg_temp.h('stranger'), NULL);
  v := public.otp_record_intent(pg_temp.h('b10b'), 'sms', 'ios', 'en', pg_temp.h('owner'), pg_temp.h('cgnat'));
  IF (v ->> 'stored')::boolean OR v ->> 'reason' <> 'ip_limit' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner''s request over the IP limit was stored: %', v;
  END IF;
  v := pg_temp.decide('b10b');
  IF v ->> 'channel' <> 'sms' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a request refused at the IP limit did not oppose: %', v;
  END IF;

  -- (c) The mark lasts 10 minutes: past it, the number's own fresh
  --     single-device request is honoured again.
  INSERT INTO private.otp_intent_refusals (phone_hmac, reason, refused_at)
  VALUES (pg_temp.h('b10c'), 'number_cap', clock_timestamp() - interval '11 minutes');
  PERFORM public.otp_record_intent(pg_temp.h('b10c'), 'whatsapp', 'android', 'en', pg_temp.h('owner'), NULL);
  v := pg_temp.decide('b10c', 'GB', '+447911');
  IF v ->> 'channel' <> 'whatsapp' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an expired refusal still opposed: %', v;
  END IF;
END $$;

-- B11 (review m-3). Past an IP's limit nothing more is stored for it: a
-- flood leaves the IP's 10 rows, not one per request.
DO $$
DECLARE
  v jsonb;
  v_i integer;
  v_rows bigint;
BEGIN
  FOR v_i IN 1..50 LOOP
    v := public.otp_record_intent(pg_temp.h('b11-' || v_i), 'sms', 'android', 'en', pg_temp.h('d'), pg_temp.h('flood'));
  END LOOP;
  SELECT count(*) INTO v_rows FROM private.otp_intent_attempts
   WHERE kind = 'ip' AND key_hash = pg_temp.h('flood');
  IF v ->> 'reason' <> 'ip_limit' OR v_rows <> 10 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a flood from one IP kept % rows for it (last answer %)', v_rows, v;
  END IF;
END $$;

-- B12 (final review I-2, ruling). WhatsApp (or a call) only for a number
-- with no account yet. The account the code would open is Auth's own user
-- (the hook's payload.user.id): a users row means an existing account, and
-- its code goes by SMS whatever was asked, since a code others can read (a
-- linked WhatsApp device, a recycled number) must never open one. No user
-- named at all counts as an existing account.
DO $$
DECLARE
  v jsonb;
  v_existing constant uuid := '5f1a0000-0000-0000-0000-0000000012b1';
  v_new constant uuid := '5f1a0000-0000-0000-0000-0000000012b2';
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at)
  VALUES (v_existing, '+15558120121', now()), (v_new, '+15558120122', now());
  INSERT INTO public.users (id, phone, display_name) VALUES (v_existing, '+15558120121', 'Kofi W2');

  -- (a) An existing account, a fresh single-device WhatsApp intent: SMS,
  --     recorded as SMS, with no WhatsApp route offered.
  PERFORM pg_temp.intent('b12a', 'phone-a', 'whatsapp', interval '5 seconds');
  v := pg_temp.decide('b12a', 'GB', '+447911', v_existing);
  IF NOT (v ->> 'allowed')::boolean OR v ->> 'channel' <> 'sms'
     OR v -> 'routes' <> '[{"channel": "sms", "provider": "twilio"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an existing account''s code did not go by SMS: %', v;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.otp_send_events
                  WHERE phone_hmac = pg_temp.h('b12a') AND channel = 'sms') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an existing account''s send was not recorded as SMS';
  END IF;

  -- (b) A new number (Auth's user, no users row yet), the same intent:
  --     WhatsApp, with SMS behind it.
  PERFORM pg_temp.intent('b12b', 'phone-a', 'whatsapp', interval '5 seconds');
  v := pg_temp.decide('b12b', 'GB', '+447911', v_new);
  IF v ->> 'channel' <> 'whatsapp'
     OR v -> 'routes' <> '[{"channel": "whatsapp", "provider": "meta"}, {"channel": "sms", "provider": "twilio"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new number''s fresh single-device intent was not honoured: %', v;
  END IF;

  -- (c) A call asked for an existing account: SMS too.
  PERFORM pg_temp.intent('b12c', 'phone-a', 'voice', interval '2 seconds');
  v := pg_temp.decide('b12c', 'GH', '+233244', v_existing);
  IF v ->> 'channel' <> 'sms' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a call was chosen for an existing account: %', v;
  END IF;

  -- (d) No user named (an old hook, a payload without one): SMS.
  PERFORM pg_temp.intent('b12d', 'phone-a', 'whatsapp', interval '5 seconds');
  v := pg_temp.decide('b12d', 'GB', '+447911', NULL);
  IF v ->> 'channel' <> 'sms' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a decision with no user named moved the code: %', v;
  END IF;
  v := public.otp_take_send_decision(pg_temp.h('b12d'), 'GB', '+447911');
  IF v ->> 'channel' <> 'sms' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a three-argument call moved the code: %', v;
  END IF;
END $$;

-- =====================================================================
-- C. Limits and destinations.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_i integer;
  v_before bigint;
  v_after bigint;
BEGIN
  -- C1. Six sends an hour per number; the 7th waits for the oldest to age out.
  FOR v_i IN 1..6 LOOP
    PERFORM pg_temp.sent('c1', make_interval(mins => 50 - v_i));
  END LOOP;
  SELECT coalesce(sum(count), 0) INTO v_before FROM public.metric_counters
   WHERE key = 'otp_refused:number_hourly';
  v := pg_temp.decide('c1');
  SELECT coalesce(sum(count), 0) INTO v_after FROM public.metric_counters
   WHERE key = 'otp_refused:number_hourly';
  IF (v ->> 'allowed')::boolean OR v ->> 'reason' <> 'number_hourly'
     OR (v ->> 'retry_after_s')::int NOT BETWEEN 600 AND 780 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 7th send in an hour was not refused with its wait: %', v;
  END IF;
  IF v_after <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refusal did not bump otp_refused:number_hourly';
  END IF;
  IF (SELECT count(*) FROM private.otp_send_events WHERE phone_hmac = pg_temp.h('c1')) <> 6 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused send was recorded';
  END IF;

  -- C2. Fifteen a day per number.
  FOR v_i IN 1..15 LOOP
    PERFORM pg_temp.sent('c2', make_interval(hours => 2 + v_i));
  END LOOP;
  v := pg_temp.decide('c2');
  IF (v ->> 'allowed')::boolean OR v ->> 'reason' <> 'number_daily' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 16th send in a day was not refused: %', v;
  END IF;

  -- C3. A prefix's hourly cap, across numbers.
  INSERT INTO private.otp_destination_rules VALUES ('+299999', 'allow', 2);
  PERFORM pg_temp.sent('c3-a', interval '10 minutes', '+299999');
  PERFORM pg_temp.sent('c3-b', interval '5 minutes', '+299999');
  v := pg_temp.decide('c3-c', 'GL', '+2999991');
  IF (v ->> 'allowed')::boolean OR v ->> 'reason' <> 'prefix_hourly' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a prefix past its hourly cap was sent to: %', v;
  END IF;

  -- C4. +999 (parked numbers) and the longest matching prefix decide.
  v := pg_temp.decide('c4', 'XX', '+999123');
  IF (v ->> 'allowed')::boolean OR v ->> 'reason' <> 'blocked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: +999 was not blocked: %', v;
  END IF;
  v := pg_temp.decide('c4-b', 'GB', '+447012');
  IF (v ->> 'allowed')::boolean OR v ->> 'reason' <> 'blocked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: +4470 was not blocked under +44: %', v;
  END IF;
  v := pg_temp.decide('c4-c', 'GB', '+447911');
  IF NOT (v ->> 'allowed')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a UK mobile was blocked: %', v;
  END IF;

  -- C5. An allowed send is recorded with its route, country and rule.
  IF NOT EXISTS (SELECT 1 FROM private.otp_send_events
                  WHERE phone_hmac = pg_temp.h('c4-c') AND route = 'twilio'
                    AND country_code = 'GB' AND rule_prefix = '+44' AND channel = 'sms') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the allowed send was not recorded as sent';
  END IF;

  -- C6. A switched-off route is skipped; with no SMS route at all, refused.
  UPDATE private.otp_routes SET enabled = false WHERE country_code = 'GH' AND provider = 'arkesel';
  v := pg_temp.decide('c6');
  IF v -> 'routes' <> '[{"channel": "sms", "provider": "twilio"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a disabled route was used: %', v;
  END IF;
  UPDATE private.otp_routes SET enabled = false WHERE channel = 'sms';
  v := pg_temp.decide('c6-b');
  IF (v ->> 'allowed')::boolean OR v ->> 'reason' <> 'no_route' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a send with no route was allowed: %', v;
  END IF;
  UPDATE private.otp_routes SET enabled = true;

  -- C7. A malformed prefix or HMAC is refused, never raised.
  v := public.otp_take_send_decision('nope', 'GH', '+233');
  IF v ->> 'reason' <> 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed decision request was not refused: %', v;
  END IF;
END $$;

-- C8 (review m-2). A prefix's hourly cap is counted, and the send
-- recorded, under that prefix's own lock, held to the end of the
-- transaction: two concurrent sends to one prefix can't both see room for
-- one. The lock is taken before the count, and is held after a decision.
DO $$
DECLARE
  v_def text := pg_get_functiondef('public.otp_take_send_decision(text,text,text,uuid)'::regprocedure);
  v_key bigint := hashtextextended('otp-prefix:+254', 0);
BEGIN
  IF position('pg_advisory_xact_lock(hashtextextended(''otp-prefix:'' || v_rule_prefix, 0))' IN v_def) = 0
     OR position('pg_advisory_xact_lock(hashtextextended(''otp-prefix:'' || v_rule_prefix, 0))' IN v_def)
        > position('WHERE e.rule_prefix = v_rule_prefix' IN v_def) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the prefix cap is not counted under the prefix lock';
  END IF;
  PERFORM pg_temp.decide('c8', 'KE', '+254712');
  IF NOT EXISTS (SELECT 1 FROM pg_locks AS l
                  WHERE l.locktype = 'advisory' AND l.pid = pg_backend_pid() AND l.objsubid = 1
                    AND l.classid::bigint = (v_key >> 32) & 4294967295
                    AND l.objid::bigint = v_key & 4294967295) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the prefix lock is not held after a decision';
  END IF;
END $$;

-- =====================================================================
-- D. Retention and its cron (§4.6, §4.8).
-- =====================================================================
DO $$
BEGIN
  PERFORM pg_temp.intent('d-old', 'x', 'sms', interval '11 minutes');
  PERFORM pg_temp.intent('d-new', 'x', 'sms', interval '1 minute');
  PERFORM pg_temp.sent('d-old', interval '25 hours');
  PERFORM pg_temp.sent('d-new', interval '23 hours');
  INSERT INTO private.otp_intent_attempts VALUES ('ip', pg_temp.h('d-old'), clock_timestamp() - interval '61 minutes');
  INSERT INTO private.otp_intent_refusals VALUES (pg_temp.h('d-old'), 'ip_limit', clock_timestamp() - interval '11 minutes');
  INSERT INTO private.otp_intent_refusals VALUES (pg_temp.h('d-new'), 'ip_limit', clock_timestamp() - interval '1 minute');
  INSERT INTO private.otp_hook_deliveries (delivery_hmac, sent_at)
  VALUES (pg_temp.h('d-old'), clock_timestamp() - interval '11 minutes'),
         (pg_temp.h('d-new'), clock_timestamp() - interval '1 minute');
  PERFORM private.otp_purge();
  IF EXISTS (SELECT 1 FROM private.otp_delivery_intents WHERE phone_hmac = pg_temp.h('d-old'))
     OR NOT EXISTS (SELECT 1 FROM private.otp_delivery_intents WHERE phone_hmac = pg_temp.h('d-new'))
     OR EXISTS (SELECT 1 FROM private.otp_send_events WHERE phone_hmac = pg_temp.h('d-old'))
     OR NOT EXISTS (SELECT 1 FROM private.otp_send_events WHERE phone_hmac = pg_temp.h('d-new'))
     OR EXISTS (SELECT 1 FROM private.otp_intent_attempts WHERE key_hash = pg_temp.h('d-old'))
     OR EXISTS (SELECT 1 FROM private.otp_intent_refusals WHERE phone_hmac = pg_temp.h('d-old'))
     OR NOT EXISTS (SELECT 1 FROM private.otp_intent_refusals WHERE phone_hmac = pg_temp.h('d-new'))
     OR EXISTS (SELECT 1 FROM private.otp_hook_deliveries WHERE delivery_hmac = pg_temp.h('d-old'))
     OR NOT EXISTS (SELECT 1 FROM private.otp_hook_deliveries WHERE delivery_hmac = pg_temp.h('d-new')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: otp_purge kept or removed the wrong rows';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job
                  WHERE jobname = 'otp-purge' AND schedule = '13 * * * *'
                    AND command = 'SELECT private.otp_purge()') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: otp-purge is not scheduled';
  END IF;
END $$;

-- =====================================================================
-- E. One delivery per code (review n-4, batch 7 M-1). Auth signs each retry
--    of a hook call afresh (a new webhook-id, the same body), so
--    send-sms-hook keys the delivery (an HMAC of the number and the code).
--    It is marked sent only after a provider accepted it: a retry or a
--    replay of a sent delivery sends nothing and uses up no limit, and the
--    retry of one that sent nothing is free to send. Called as the service
--    role, the edge functions' only role (M-2).
-- =====================================================================
DO $$
DECLARE
  v_e1 constant text := pg_temp.h('e1');
  v_other constant text := pg_temp.h('e1-other');
  v_gb constant text := pg_temp.h('e1-decision');
  v_sends bigint;
  v_rows bigint;
  v_raised integer := 0;
  v_bad text;
  v jsonb;
BEGIN
  SELECT count(*) INTO v_sends FROM private.otp_send_events;

  -- E1. As the service role: not sent until marked; marked, it is sent;
  --     another delivery is its own; the decision answers too.
  SET LOCAL ROLE service_role;
  IF public.otp_hook_delivery_sent(v_e1) THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a delivery nothing sent counted as sent';
  END IF;
  PERFORM public.otp_mark_hook_delivery_sent(v_e1);
  IF NOT public.otp_hook_delivery_sent(v_e1) THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a marked delivery did not count as sent';
  END IF;
  IF public.otp_hook_delivery_sent(v_other) THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: another delivery counted as sent';
  END IF;
  v := public.otp_take_send_decision(v_gb, 'GB', '+447911');
  RESET ROLE;
  IF NOT (v ->> 'allowed')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role''s decision was refused: %', v;
  END IF;
  v_sends := v_sends + 1;

  -- E2. Asking never marks: a delivery asked about twice is still unsent.
  SELECT count(*) INTO v_rows FROM private.otp_hook_deliveries;
  PERFORM public.otp_hook_delivery_sent(pg_temp.h('e2-asked'));
  PERFORM public.otp_hook_delivery_sent(pg_temp.h('e2-asked'));
  IF (SELECT count(*) FROM private.otp_hook_deliveries) <> v_rows THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: asking whether a delivery was sent marked it';
  END IF;

  -- E3. A mark holds for 10 minutes: at 9 it still counts; past 10 it is
  --     free again; marking again renews it.
  INSERT INTO private.otp_hook_deliveries (delivery_hmac, sent_at)
  VALUES (pg_temp.h('e3-held'), clock_timestamp() - interval '9 minutes'),
         (pg_temp.h('e3-free'), clock_timestamp() - interval '11 minutes');
  IF NOT public.otp_hook_delivery_sent(pg_temp.h('e3-held')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 9-minute-old sent delivery was free';
  END IF;
  IF public.otp_hook_delivery_sent(pg_temp.h('e3-free')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an expired mark still counted';
  END IF;
  PERFORM public.otp_mark_hook_delivery_sent(pg_temp.h('e3-free'));
  IF NOT public.otp_hook_delivery_sent(pg_temp.h('e3-free')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a renewed mark did not count';
  END IF;

  -- E4. Neither call records a send: the limits are the decision's alone.
  IF (SELECT count(*) FROM private.otp_send_events) <> v_sends THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a delivery check or mark recorded a send';
  END IF;

  -- E5. A malformed or missing key raises in both (the hook then fails
  --     closed); it is never answered as a sent delivery.
  FOREACH v_bad IN ARRAY ARRAY['not-a-hash', upper(pg_temp.h('e5')), NULL] LOOP
    BEGIN
      PERFORM public.otp_hook_delivery_sent(v_bad);
    EXCEPTION WHEN invalid_parameter_value THEN
      v_raised := v_raised + 1;
    END;
    BEGIN
      PERFORM public.otp_mark_hook_delivery_sent(v_bad);
    EXCEPTION WHEN invalid_parameter_value THEN
      v_raised := v_raised + 1;
    END;
  END LOOP;
  IF v_raised <> 6 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed delivery key did not raise (% of 6)', v_raised;
  END IF;
END $$;

ROLLBACK;
