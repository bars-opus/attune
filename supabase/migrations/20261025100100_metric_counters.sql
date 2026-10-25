-- Spec 1 W1b, migration 2 of 6 (spec §4.7 #2): metric storage (§4.2, §4.3
-- W1b; cross-spec review S-2). Aggregates only: a day, a key, a count; never
-- a user id, an answer, a gender, a preference, a faith or an age signal.
--   * server prefixes (metric_key_prefixes) are bumped only by definer
--     functions (private.bump_metric_internal) and service-role edge
--     functions (bump_metric_server);
--   * a client (bump_metric) may bump only an exact listed key
--     (metric_client_keys), and anon only an anon_ok pre-auth key;
--   * at most 5,000 distinct keys per UTC day: past the cap a new key is not
--     created and metric_cap_reached moves instead;
--   * a metric never fails its caller;
--   * a key never carries an id or a phone number: no uuid shape (dashed or
--     not) and no run of 7+ digits (batch 3 fix round 1, M-5).
-- First in W1b because the next two migrations bump metrics.
-- Grants in 20261025100110_metric_counters_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.metric_counters (
  day date NOT NULL,
  key text NOT NULL CONSTRAINT metric_counters_key_check
    CHECK (key ~ '^[a-z0-9_:>.-]{1,80}$' AND key !~ '[0-9]([-._:>]?[0-9]){6,}' AND key !~ '[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}'),
  count bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (day, key)
);
CREATE TABLE IF NOT EXISTS public.metric_key_prefixes (
  prefix text PRIMARY KEY CONSTRAINT metric_key_prefixes_prefix_check CHECK (prefix ~ '^[a-z0-9_:>.-]{1,80}$'),
  owner_spec text NOT NULL
);
CREATE TABLE IF NOT EXISTS public.metric_client_keys (
  key text PRIMARY KEY CONSTRAINT metric_client_keys_key_check CHECK (key ~ '^[a-z0-9_:>.-]{1,80}$'),
  anon_ok boolean NOT NULL DEFAULT false,
  owner_spec text NOT NULL
);
-- Re-asserted so a table created before the id/phone rule gets it too.
ALTER TABLE public.metric_counters DROP CONSTRAINT IF EXISTS metric_counters_key_check;
ALTER TABLE public.metric_counters ADD CONSTRAINT metric_counters_key_check
  CHECK (key ~ '^[a-z0-9_:>.-]{1,80}$' AND key !~ '[0-9]([-._:>]?[0-9]){6,}' AND key !~ '[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}');
ALTER TABLE public.metric_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.metric_key_prefixes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.metric_client_keys ENABLE ROW LEVEL SECURITY;

-- Server prefixes (spec §4.3 W1b seeds). Spec 2 adds 'dating.'.
INSERT INTO public.metric_key_prefixes (prefix, owner_spec) VALUES
  ('signup_completed', 'spec1'),
  ('path_chosen:', 'spec1'),
  ('path_switch_7d:', 'spec1'),
  ('path_switch_30d:', 'spec1'),
  ('invite_accepted', 'spec1'),
  ('otp_sent:', 'spec1'),
  ('otp_refused:', 'spec1'),
  ('dormancy_', 'spec1'),
  ('support_card_shown:journal', 'spec1'),
  ('auth_hook_fail_open', 'spec1')
ON CONFLICT (prefix) DO NOTHING;

-- Exact client keys; anon_ok only for the pre-auth funnel. Kept in step with
-- lib/core/metrics/metric_counter.dart (test/core/metrics/metric_counter_test.dart).
INSERT INTO public.metric_client_keys (key, anon_ok, owner_spec) VALUES
  ('welcome_preview:relationship', true, 'spec1'),
  ('welcome_preview:dating', true, 'spec1'),
  ('welcome_preview:just_me', true, 'spec1'),
  ('guest_age_ok', true, 'spec1'),
  ('signup_started', true, 'spec1'),
  ('signup_step:name', true, 'spec1'),
  ('signup_step:dob', true, 'spec1'),
  ('signup_step:phone', true, 'spec1'),
  ('signup_age_stop', true, 'spec1'),
  ('push_ask_shown:r2', false, 'spec1'),
  ('push_ask_shown:r4', false, 'spec1'),
  ('push_ask_shown:j3', false, 'spec1'),
  ('push_ask_granted:r2', false, 'spec1'),
  ('push_ask_granted:r4', false, 'spec1'),
  ('push_ask_granted:j3', false, 'spec1'),
  ('invite_shared:whatsapp', false, 'spec1'),
  ('invite_shared:share', false, 'spec1'),
  ('invite_shared:qr', false, 'spec1'),
  ('invite_shared:copy', false, 'spec1'),
  ('invite_new_day7', false, 'spec1'),
  ('invite_day30_shown', false, 'spec1'),
  ('opinion_blocked:contact_info', false, 'spec1'),
  ('opinion_blocked:slur', false, 'spec1'),
  ('opinion_blocked:explicit', false, 'spec1'),
  ('support_link_opened:opinions', false, 'spec1'),
  ('support_link_opened:journal', false, 'spec1')
ON CONFLICT (key) DO NOTHING;

-- The one capped writer. Callers decide whether a key may be bumped; this
-- only checks the pattern and the daily row cap. Never raises.
CREATE OR REPLACE FUNCTION private.metric_increment(p_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_day constant date := (now() AT TIME ZONE 'utc')::date;
BEGIN
  IF p_key IS NULL OR p_key !~ '^[a-z0-9_:>.-]{1,80}$'
     OR p_key ~ '[0-9]([-._:>]?[0-9]){6,}' OR p_key ~ '[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}' THEN
    RETURN;
  END IF;
  UPDATE public.metric_counters AS c SET count = c.count + 1
   WHERE c.day = v_day AND c.key = p_key;
  IF FOUND THEN
    RETURN;
  END IF;
  IF p_key <> 'metric_cap_reached'
     AND (SELECT count(*) FROM public.metric_counters AS c
           WHERE c.day = v_day AND c.key <> 'metric_cap_reached') >= 5000 THEN
    INSERT INTO public.metric_counters AS c (day, key, count)
    VALUES (v_day, 'metric_cap_reached', 1)
    ON CONFLICT (day, key) DO UPDATE SET count = c.count + 1;
    RETURN;
  END IF;
  INSERT INTO public.metric_counters AS c (day, key, count)
  VALUES (v_day, p_key, 1)
  ON CONFLICT (day, key) DO UPDATE SET count = c.count + 1;
EXCEPTION WHEN OTHERS THEN
  -- A metric never fails its caller (spec §4.3 W1b).
  RETURN;
END;
$$;

-- Definer callers: the key must start with a server prefix.
CREATE OR REPLACE FUNCTION private.bump_metric_internal(p_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_key IS NULL OR p_key !~ '^[a-z0-9_:>.-]{1,80}$'
     OR p_key ~ '[0-9]([-._:>]?[0-9]){6,}' OR p_key ~ '[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}' THEN
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.metric_key_prefixes AS k
                  WHERE left(p_key, char_length(k.prefix)) = k.prefix) THEN
    RETURN;
  END IF;
  PERFORM private.metric_increment(p_key);
EXCEPTION WHEN OTHERS THEN
  RETURN;
END;
$$;

-- Edge functions (service role): the same rule.
CREATE OR REPLACE FUNCTION public.bump_metric_server(p_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM private.bump_metric_internal(p_key);
END;
$$;

-- Clients: exact listed keys only; anon only anon_ok ones. Anything else is
-- ignored silently. Client counts are advisory: nothing decides on them.
CREATE OR REPLACE FUNCTION public.bump_metric(p_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_anon_ok boolean;
BEGIN
  SELECT k.anon_ok INTO v_anon_ok FROM public.metric_client_keys AS k WHERE k.key = p_key;
  IF NOT FOUND THEN
    RETURN;
  END IF;
  IF auth.uid() IS NULL AND NOT v_anon_ok THEN
    RETURN;
  END IF;
  PERFORM private.metric_increment(p_key);
EXCEPTION WHEN OTHERS THEN
  RETURN;
END;
$$;

-- Service role only; a cell under 50 is blank (spec §4.1 rule 4).
CREATE OR REPLACE VIEW public.metric_counters_report AS
  SELECT c.day, c.key, CASE WHEN c.count >= 50 THEN c.count END AS count
    FROM public.metric_counters AS c;

-- Revoked here as well as in the twin (the verified_phone precedent; batch 2
-- review M3): the hosted default privileges grant EXECUTE on a new function
-- and SELECT on a new view to anon and authenticated, and a failed or late
-- twin push must not leave a server metric writer or the report open.
REVOKE ALL ON FUNCTION private.metric_increment(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.bump_metric_internal(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bump_metric_server(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.metric_counters_report FROM PUBLIC, anon, authenticated;

-- Retention: 400 days, its own job (spec §4.6).
DO $$
BEGIN
  PERFORM cron.unschedule('metric-counters-retention');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;
SELECT cron.schedule(
  'metric-counters-retention',
  '12 4 * * *',
  $cron$DELETE FROM public.metric_counters WHERE day < current_date - 400$cron$
);

COMMIT;
