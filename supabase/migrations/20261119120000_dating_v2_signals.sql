-- supabase/migrations/20261119120000_dating_v2_signals.sql
-- Spec 2 W5c (§4.9 W5c, §4.3, §2.6, §2.8, §5.2 15, §5.9, §5.10, §6.9;
-- carry 17): the moderation queue's table (signals only until W7 adds
-- reports and appeals; no routing column, S-5); the behaviour signals whose
-- inputs exist now: the dragnet (with its throttle to one introduction a
-- day until a moderator decides) and several Dating accounts on one phone;
-- each opens one case and nothing else (never a ban, never a partner told).
-- The dragnet's first-message input comes with W6a's messages: until then
-- it reads "unknown" and the rule waits for it (Ruling R-14). Generation
-- runs the signals before its partitions, never introduces anyone the
-- throttle has used up (filter 15) and caps a throttled person at one a
-- day. The weekly fairness job (aggregates only, n >= 50, flags for the
-- safety owner, no automatic re-weighting) and its cron. The countries a
-- person may open to (the Other countries setting), never one whose
-- same-gender rule refuses their answers. No signal reads country, region,
-- network, phone, name or a prefix. Dating stays off. Idempotent.
-- Spec 2 W5 final (final server review): Other countries runs read-write
-- under PostgREST so its device check refreshes freshness (I-1); health
-- shows the digest's push_key_missing and failed counters (M-5, M-3); the
-- partition's close re-checks filters 2-10 on what it made (M-2); an active
-- config's values are frozen (M-7); the W5 production gate lists every
-- ledger gate (I-2).
BEGIN;
SET LOCAL lock_timeout = '5s';

-- =====================================================================
-- 1. The queue (§4.3): signals now; W7a adds reports and appeals, W7b
--    the console. Whether a case needs a routed reviewer is computed when
--    it is read, never stored (S-5). One open signal case per person and
--    kind.
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.dating_moderation_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('report', 'photo', 'verification', 'signal', 'appeal', 'csam_hit')),
  priority text NOT NULL DEFAULT 'P2' CHECK (priority IN ('P0', 'P1', 'P2', 'P3')),
  target_user_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  target_phone_hmac text CHECK (target_phone_hmac IS NULL OR target_phone_hmac ~ '^[0-9a-f]{64}$'),
  report_id uuid,
  match_id uuid REFERENCES public.dating_matches (id) ON DELETE SET NULL,
  signal_kind text CHECK (signal_kind IS NULL OR signal_kind IN
    ('dragnet', 'duplicate_opener', 'money_asks', 'sexual_pressure', 'location_mismatch', 'device_accounts')),
  state text NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'in_review', 'decided', 'closed')),
  assigned_to uuid,
  sla_due_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  outcome text,
  CHECK ((kind = 'signal') = (signal_kind IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS dating_moderation_cases_open_signal_idx
  ON public.dating_moderation_cases (target_user_id, signal_kind)
  WHERE kind = 'signal' AND state IN ('open', 'in_review');
CREATE INDEX IF NOT EXISTS dating_moderation_cases_state_idx ON public.dating_moderation_cases (state, priority, created_at);
ALTER TABLE public.dating_moderation_cases ENABLE ROW LEVEL SECURITY;
-- The several-accounts signal looks a phone's other accounts up by its hash
-- every tick (the key leads with user_id, so without this it scans).
CREATE INDEX IF NOT EXISTS dating_trusted_devices_hash_idx ON public.dating_trusted_devices (device_hash, verified_at);
-- Fix round 1 (M-2): a deleted account or a purged match nulls its cases
-- through these, never by scanning the queue (cases are kept 2 years,
-- §4.8). Fix round 1 (M-6): a person's cases are also found by the phone's
-- HMAC, so an account deleted and registered again keeps them.
CREATE INDEX IF NOT EXISTS dating_moderation_cases_target_idx ON public.dating_moderation_cases (target_user_id);
CREATE INDEX IF NOT EXISTS dating_moderation_cases_match_idx ON public.dating_moderation_cases (match_id) WHERE match_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS dating_moderation_cases_phone_idx ON public.dating_moderation_cases (target_phone_hmac, signal_kind)
  WHERE kind = 'signal';

-- =====================================================================
-- 2. Fairness reports (§4.3, §5.9): aggregates only, rows only at n >= 50.
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.dating_fairness_reports (
  week date NOT NULL,
  country_code char(2) NOT NULL,
  cohort_key text NOT NULL CHECK (cohort_key ~ '^(region:[A-Z0-9_]{1,16}|age:(18_24|25_34|35_44|45_54|55_plus)|gender:(woman|man|other)|top_decile)$'),
  active_bucket text NOT NULL CHECK (active_bucket IN ('50–99', '100–499', '500+')),
  introductions_per_active numeric NOT NULL,
  mutual_rate numeric,
  flagged boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (week, country_code, cohort_key)
);
ALTER TABLE public.dating_fairness_reports ENABLE ROW LEVEL SECURITY;

-- =====================================================================
-- 3. Signals (§5.10, §2.8). Behaviour only: no signal function reads a
--    country, a region, a network, a phone number or prefix, or a name.
-- =====================================================================
-- One open case per person and kind; true when this call opened it.
-- Fix round 1 (M-1): the person's row is taken as generation takes it, FOR
-- KEY SHARE SKIP LOCKED: an account deletion or a path switch in progress
-- is never waited on (the case opens at a later tick; counted busy), and a
-- person gone meanwhile opens nothing (never a foreign-key error). A case
-- opened still holds that KEY SHARE until the tick commits: the W5a
-- production gate (commit per step) shortens it.
-- Fix round 1 (M-6): one open case per phone (HMAC) and kind as well, so a
-- person who deleted the account and registered again on the same number
-- keeps the open case rather than starting a new one.
CREATE OR REPLACE FUNCTION private.dating_open_signal_case(p_user uuid, p_signal text, p_priority text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid;
  v_hmac text;
BEGIN
  PERFORM 1 FROM public.users AS u WHERE u.id = p_user FOR KEY SHARE SKIP LOCKED;
  IF NOT FOUND THEN
    PERFORM private.bump_metric_internal('dating.signal.busy');
    RETURN false;
  END IF;
  v_hmac := public.dating_phone_hmac_for_user(p_user);
  IF v_hmac IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.dating_moderation_cases AS c
        WHERE c.target_phone_hmac = v_hmac AND c.kind = 'signal' AND c.signal_kind = p_signal
          AND c.state IN ('open', 'in_review')) THEN
    RETURN false;
  END IF;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, signal_kind)
  VALUES ('signal', p_priority, p_user, v_hmac, p_signal)
  ON CONFLICT (target_user_id, signal_kind) WHERE kind = 'signal' AND state IN ('open', 'in_review') DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NOT NULL THEN
    PERFORM private.bump_metric_internal('dating.signal.' || p_signal);
  END IF;
  RETURN v_id IS NOT NULL;
END;
$$;

-- The first messages the person sent in matches made since [p_since]:
-- W6a's messages answer it; until then unknown (NULL), and a rule that
-- needs it waits (Ruling R-14).
CREATE OR REPLACE FUNCTION private.dating_first_messages(p_user uuid, p_since timestamptz)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT NULL::integer;
$$;

-- §5.10 dragnet: >= 15 introductions in 14 days, "Interested" on >= 90%
-- of them, and a first message in <= 20% of the matches they made. An
-- unknown input never holds.
CREATE OR REPLACE FUNCTION private.dating_dragnet_holds(p_user uuid, p_at timestamptz, p_cfg jsonb)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_since constant timestamptz := p_at - make_interval(days => coalesce((p_cfg #>> '{dragnet,window_days}')::int, 14));
  v_intros integer;
  v_interested integer;
  v_matches integer;
  v_first integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE CASE WHEN i.user_low_id = p_user THEN i.low_action ELSE i.high_action END = 'interested')
    INTO v_intros, v_interested
    FROM public.dating_introductions AS i
   WHERE p_user IN (i.user_low_id, i.user_high_id) AND i.created_at > v_since AND i.created_at <= p_at;
  IF v_intros < coalesce((p_cfg #>> '{dragnet,min_intros}')::int, 15)
     OR v_interested < v_intros * coalesce((p_cfg #>> '{dragnet,interested_ratio}')::numeric, 0.9) THEN
    RETURN false;
  END IF;
  SELECT count(*) INTO v_matches
    FROM public.dating_matches AS m JOIN public.dating_introductions AS i ON i.id = m.introduction_id
   WHERE p_user IN (i.user_low_id, i.user_high_id) AND i.created_at > v_since AND i.created_at <= p_at;
  v_first := private.dating_first_messages(p_user, v_since);
  RETURN coalesce(v_matches > 0
                  AND v_first <= v_matches * coalesce((p_cfg #>> '{dragnet,first_message_ratio}')::numeric, 0.2), false);
END;
$$;

-- §5.10, §2.8: two or more Dating activations from one trusted phone in
-- 30 days (the phone that passed each activation's check).
CREATE OR REPLACE FUNCTION private.dating_device_accounts_hold(p_user uuid, p_at timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.dating_trusted_devices AS mine
      JOIN public.dating_trusted_devices AS other
        ON other.device_hash = mine.device_hash AND other.user_id <> mine.user_id
     WHERE mine.user_id = p_user
       AND mine.verified_at > p_at - interval '30 days' AND other.verified_at > p_at - interval '30 days');
$$;

-- Fix round 1 (I-1): a moderator's decision sticks. A case of this kind
-- decided or closed after [p_since] (the start of the rule's window) means
-- the rule is not evaluated again for the person (or their phone) until
-- the whole window postdates that decision: only evidence gathered after
-- it can open a new case.
CREATE OR REPLACE FUNCTION private.dating_signal_cleared(p_user uuid, p_signal text, p_since timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c
                  WHERE c.kind = 'signal' AND c.signal_kind = p_signal AND c.state IN ('decided', 'closed')
                    AND coalesce(c.decided_at, c.created_at) > p_since
                    AND (c.target_user_id = p_user OR c.target_phone_hmac = public.dating_phone_hmac_for_user(p_user)));
$$;

-- Every active person, once per generation tick: open the case a signal
-- calls for. Returns how many cases it opened.
-- Fix round 1 (I-2): each person in a block of their own: an error costs
-- only that person's cases this hour; it is counted (dating.signal.failed,
-- in health, and dating.signal.failed.<sqlstate>; never the message).
-- Fix round 1 (M-7): several accounts on one handset opens at P3 (low
-- priority). Families share handsets (S17): this signal ALONE NEVER
-- SUPPORTS A RESTRICTION; a moderator weighs it only beside other
-- evidence (W7c runbook), and the console shows it as "another account on
-- this handset", never as the other account.
CREATE OR REPLACE FUNCTION private.dating_run_signals(p_at timestamptz, p_cfg jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  r record;
  v_n integer := 0;
  v_drag_since constant timestamptz := p_at - make_interval(days => coalesce((p_cfg #>> '{dragnet,window_days}')::int, 14));
  v_dev_since constant timestamptz := p_at - interval '30 days';
BEGIN
  FOR r IN SELECT e.user_id FROM public.dating_enrollments AS e WHERE e.state = 'active' ORDER BY e.user_id LOOP
    BEGIN
      IF NOT private.dating_signal_cleared(r.user_id, 'dragnet', v_drag_since)
         AND private.dating_dragnet_holds(r.user_id, p_at, p_cfg) AND private.dating_open_signal_case(r.user_id, 'dragnet', 'P2') THEN
        v_n := v_n + 1;
      END IF;
      IF NOT private.dating_signal_cleared(r.user_id, 'device_accounts', v_dev_since)
         AND private.dating_device_accounts_hold(r.user_id, p_at) AND private.dating_open_signal_case(r.user_id, 'device_accounts', 'P3') THEN
        v_n := v_n + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      PERFORM private.bump_metric_internal('dating.signal.failed');
      PERFORM private.bump_metric_internal('dating.signal.failed.' || lower(SQLSTATE));
    END;
  END LOOP;
  RETURN v_n;
END;
$$;

-- A person under an open dragnet case (until a moderator decides).
-- Fix round 1 (M-6): matched by the account or by the phone's HMAC the case
-- carries (§4.3), so deleting and registering again does not escape it.
CREATE OR REPLACE FUNCTION private.dating_throttled(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_moderation_cases AS c
                  WHERE c.kind = 'signal' AND c.signal_kind = 'dragnet' AND c.state IN ('open', 'in_review')
                    AND (c.target_user_id = p_user
                         OR c.target_phone_hmac = public.dating_phone_hmac_for_user(p_user)));
$$;

-- §5.2 15: removed from generation for now. W5c: the dragnet throttle at
-- 0 (today's one introduction made). W7a adds the P1 and uncorroborated
-- P0 report steps here.
CREATE OR REPLACE FUNCTION private.dating_generation_removed(p_user uuid, p_at timestamptz, p_cfg jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.dating_throttled(p_user)
     AND (SELECT count(*) FROM public.dating_introductions AS i
           WHERE p_user IN (i.user_low_id, i.user_high_id)
             AND i.created_at > p_at - interval '20 hours' AND i.created_at <= p_at)
         >= coalesce((p_cfg #>> '{dragnet,throttled_daily_max}')::int, 1);
$$;

-- =====================================================================
-- 4. Fairness (§5.9): per country and audited cohort, introductions per
--    active person and the mutual-interest rate over 4 weeks; a cohort
--    only at n >= 50 (smaller ones are left out, never merged); a flag
--    below 0.8 of the country's rate, or when the top 10% receive more
--    than 25% of the introductions. Gender is decrypted inside the job
--    into a temp table dropped at commit; only aggregates leave. Mondays.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.dating_fairness_weekly(p_week date DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_week constant date := coalesce(p_week, date_trunc('week', now())::date);
  v_from constant timestamptz := v_week::timestamptz - interval '28 days';
  v_to constant timestamptz := v_week::timestamptz;
  v_c record;
  v_k record;
  v_rate numeric;
  v_mutual numeric;
  v_n integer;
  v_total bigint;
  v_top bigint;
  v_rows integer := 0;
  v_identity jsonb;
  v_old boolean;
  v_flag boolean;
  r record;
BEGIN
  DROP TABLE IF EXISTS pg_temp.dating_fair_people;
  CREATE TEMP TABLE dating_fair_people (
    user_id uuid PRIMARY KEY,
    country text NOT NULL,
    region text,
    age_band text,
    gender_group text,
    intros integer NOT NULL,
    matched integer NOT NULL
  ) ON COMMIT DROP;
  FOR r IN
    SELECT p.user_id, p.country_code::text AS country, p.region_code, s.identity_enc, public.account_age(p.user_id) AS age
      FROM public.dating_profiles AS p
      JOIN public.dating_enrollments AS e ON e.user_id = p.user_id AND e.state = 'active'
      LEFT JOIN public.dating_profile_sensitive AS s ON s.user_id = p.user_id
     WHERE p.country_code IS NOT NULL
  LOOP
    -- Fix round 1 (M-5): an unreadable answer is counted and leaves only
    -- that person's gender unknown; they stay in their region and age
    -- cohorts, and every other person's gender is still read.
    BEGIN
      v_identity := private.dating_field_decrypt(r.identity_enc);
    EXCEPTION WHEN OTHERS THEN
      v_identity := NULL;
      PERFORM private.bump_metric_internal('dating.fairness.unreadable');
    END;
    INSERT INTO pg_temp.dating_fair_people
    VALUES (r.user_id, r.country, r.region_code,
            CASE WHEN r.age < 25 THEN '18_24' WHEN r.age < 35 THEN '25_34' WHEN r.age < 45 THEN '35_44'
                 WHEN r.age < 55 THEN '45_54' WHEN r.age >= 55 THEN '55_plus' END,
            -- Fix round 1 (M-4, §5.9): non-binary or a specific term together.
            CASE WHEN v_identity ->> 'specific' IS NOT NULL OR v_identity ->> 'specific_text' IS NOT NULL THEN 'other'
                 WHEN v_identity ->> 'identity' = 'woman' THEN 'woman' WHEN v_identity ->> 'identity' = 'man' THEN 'man'
                 WHEN v_identity ->> 'identity' = 'non_binary' THEN 'other' END,
            (SELECT count(*) FROM public.dating_introductions AS i
              WHERE r.user_id IN (i.user_low_id, i.user_high_id) AND i.created_at >= v_from AND i.created_at < v_to),
            (SELECT count(*) FROM public.dating_introductions AS i
              WHERE r.user_id IN (i.user_low_id, i.user_high_id) AND i.created_at >= v_from AND i.created_at < v_to
                AND i.state = 'matched'));
  END LOOP;
  FOR v_c IN SELECT f.country, count(*) AS n, sum(f.intros) AS intros, sum(f.matched) AS matched
               FROM pg_temp.dating_fair_people AS f GROUP BY f.country HAVING count(*) >= 50 ORDER BY f.country LOOP
    v_rate := v_c.intros::numeric / v_c.n;
    v_mutual := CASE WHEN v_c.intros > 0 THEN v_c.matched::numeric / v_c.intros END;
    FOR v_k IN
      SELECT x.key, count(*) AS n, sum(x.intros) AS intros, sum(x.matched) AS matched
        FROM (SELECT 'region:' || f.region AS key, f.intros, f.matched FROM pg_temp.dating_fair_people AS f
               WHERE f.country = v_c.country AND f.region IS NOT NULL
              UNION ALL
              SELECT 'age:' || f.age_band, f.intros, f.matched FROM pg_temp.dating_fair_people AS f
               WHERE f.country = v_c.country AND f.age_band IS NOT NULL
              UNION ALL
              SELECT 'gender:' || f.gender_group, f.intros, f.matched FROM pg_temp.dating_fair_people AS f
               WHERE f.country = v_c.country AND f.gender_group IS NOT NULL) AS x
       GROUP BY x.key HAVING count(*) >= 50
    LOOP
      SELECT fr.flagged INTO v_old FROM public.dating_fairness_reports AS fr
       WHERE fr.week = v_week AND fr.country_code = v_c.country AND fr.cohort_key = v_k.key;
      INSERT INTO public.dating_fairness_reports AS fr
        (week, country_code, cohort_key, active_bucket, introductions_per_active, mutual_rate, flagged)
      VALUES (v_week, v_c.country, v_k.key,
              CASE WHEN v_k.n >= 500 THEN '500+' WHEN v_k.n >= 100 THEN '100–499' ELSE '50–99' END,
              round(v_k.intros::numeric / v_k.n, 4),
              CASE WHEN v_k.intros > 0 THEN round(v_k.matched::numeric / v_k.intros, 4) END,
              v_k.intros::numeric / v_k.n < 0.8 * v_rate
                OR (v_mutual IS NOT NULL AND v_k.intros > 0 AND v_k.matched::numeric / v_k.intros < 0.8 * v_mutual))
      ON CONFLICT (week, country_code, cohort_key) DO UPDATE
        SET active_bucket = EXCLUDED.active_bucket, introductions_per_active = EXCLUDED.introductions_per_active,
            mutual_rate = EXCLUDED.mutual_rate, flagged = EXCLUDED.flagged, created_at = now()
      RETURNING fr.flagged INTO v_flag;
      -- Fix round 1 (M-5): counted when a row becomes flagged, never again on a rerun.
      IF v_flag AND v_old IS DISTINCT FROM true THEN
        PERFORM private.bump_metric_internal('dating.fairness.flagged');
      END IF;
      v_rows := v_rows + 1;
    END LOOP;
    -- The top 10% of people by introductions, against the country's total.
    v_total := v_c.intros;
    SELECT fr.flagged INTO v_old FROM public.dating_fairness_reports AS fr
     WHERE fr.week = v_week AND fr.country_code = v_c.country AND fr.cohort_key = 'top_decile';
    SELECT coalesce(sum(t.intros), 0) INTO v_top
      FROM (SELECT f.intros FROM pg_temp.dating_fair_people AS f WHERE f.country = v_c.country
             ORDER BY f.intros DESC LIMIT greatest(1, (v_c.n / 10)::int)) AS t;
    INSERT INTO public.dating_fairness_reports AS fr
      (week, country_code, cohort_key, active_bucket, introductions_per_active, mutual_rate, flagged)
    VALUES (v_week, v_c.country, 'top_decile',
            CASE WHEN v_c.n >= 500 THEN '500+' WHEN v_c.n >= 100 THEN '100–499' ELSE '50–99' END,
            CASE WHEN v_total > 0 THEN round(v_top::numeric / v_total, 4) ELSE 0 END, NULL,
            v_total > 0 AND v_top::numeric / v_total > 0.25)
    ON CONFLICT (week, country_code, cohort_key) DO UPDATE
      SET active_bucket = EXCLUDED.active_bucket, introductions_per_active = EXCLUDED.introductions_per_active,
          flagged = EXCLUDED.flagged, created_at = now()
    RETURNING fr.flagged INTO v_flag;
    IF v_flag AND v_old IS DISTINCT FROM true THEN
      PERFORM private.bump_metric_internal('dating.fairness.flagged');
    END IF;
    v_rows := v_rows + 1;
  END LOOP;
  RETURN v_rows;
END;
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-fairness-weekly') THEN
    PERFORM cron.unschedule('dating-fairness-weekly');
  END IF;
  PERFORM cron.schedule('dating-fairness-weekly', '17 4 * * 1', 'SELECT public.dating_fairness_weekly()');
END $$;

-- =====================================================================
-- 5. Other countries (§2.6, §3.12; carry 17): the countries the person
--    may open to, each on or off. Eligible: verified, the age check
--    holding, an account 14+ days old. Never a country whose same-gender
--    rule refuses the person's answers (the writer would refuse it).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.get_dating_abroad_options()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE -- Spec 2 W5 final (I-1): PostgREST runs a STABLE RPC READ ONLY, where the device check's touch of last_seen_at fails and is swallowed
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_p public.dating_profiles;
  v_on text[];
  v_plain boolean;
  v_identity jsonb;
  v_seeking jsonb;
  v_eligible boolean; -- Spec 2 W5 final (abroad list): computed once
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_p.user_id IS NULL OR v_p.country_code IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
  END IF;
  SELECT d.open_abroad::text[] INTO v_on FROM public.dating_preferences AS d WHERE d.user_id = v_user;
  BEGIN
    SELECT private.dating_field_decrypt(s.identity_enc), private.dating_field_decrypt(s.seeking_enc)
      INTO v_identity, v_seeking FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
    v_plain := coalesce(private.dating_profile_plain(v_identity, v_seeking), false);
  EXCEPTION WHEN raise_exception THEN
    v_plain := false;
  END;
  v_eligible := coalesce(v_p.verification_state = 'verified', false) AND coalesce(public.dating_age_gate_holds(v_user), false) -- Spec 2 W5 final (abroad list)
                AND coalesce((SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) <= now() - interval '14 days', false); -- Spec 2 W5 final (abroad list)
  RETURN jsonb_build_object(
    'ok', true,
    'eligible', v_eligible, -- Spec 2 W5 final (abroad list)
    -- Spec 2 W5 final (abroad list): no country for a person who isn't
    -- Spec 2 W5 final eligible: which countries are offered follows the
    -- Spec 2 W5 final same-gender rule, so the list would tell whoever holds
    -- Spec 2 W5 final the phone whether the profile is man-woman (the app
    -- Spec 2 W5 final shows only "Turn off every other country" then).
    'countries', CASE WHEN v_eligible IS NOT TRUE THEN '[]'::jsonb ELSE coalesce(( -- Spec 2 W5 final (abroad list)
      SELECT jsonb_agg(jsonb_build_object('code', c.code, 'on', c.code = ANY (coalesce(v_on, '{}'))) ORDER BY c.code)
        FROM unnest(private.dating_open_countries()) AS c(code)
       WHERE c.code IS DISTINCT FROM v_p.country_code::text
         AND (v_plain OR private.dating_same_gender_on(c.code))), '[]'::jsonb) END); -- Spec 2 W5 final (abroad list)
END;
$$;

-- =====================================================================
-- 6. Functions re-created from their LIVE bodies (Spec 2 W5c lines only).
-- =====================================================================
CREATE OR REPLACE FUNCTION private.dating_capacity(p_user uuid, p_at timestamp with time zone, p_cfg jsonb)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT CASE
    WHEN private.dating_open_chats(p_user, p_at) >= coalesce((p_cfg ->> 'open_chat_pause_at')::int, 3) THEN 0
    ELSE greatest(0, least(
      CASE WHEN private.dating_throttled(p_user) -- Spec 2 W5c (§5.10): the dragnet throttle
           THEN least((p_cfg ->> 'daily_new_max')::int, coalesce((p_cfg #>> '{dragnet,throttled_daily_max}')::int, 1)) -- Spec 2 W5c
           ELSE (p_cfg ->> 'daily_new_max')::int END -- Spec 2 W5c
        - (SELECT count(*)::int FROM public.dating_introductions AS i
            WHERE p_user IN (i.user_low_id, i.user_high_id)
              AND i.created_at > p_at - interval '20 hours' AND i.created_at <= p_at),
      (p_cfg ->> 'waiting_max')::int
        - (SELECT count(*)::int FROM public.dating_introductions AS i
            WHERE p_user IN (i.user_low_id, i.user_high_id)
              AND i.state IN ('generated', 'presented', 'interested')
              AND i.expires_at > p_at
              AND CASE WHEN i.user_low_id = p_user THEN i.low_action IS NULL
                         AND i.visible_from_low + make_interval(days => (p_cfg ->> 'lifetime_days')::int) > p_at
                       ELSE i.high_action IS NULL
                         AND i.visible_from_high + make_interval(days => (p_cfg ->> 'lifetime_days')::int) > p_at END
              -- Task 1 review M-2: a pair a block or the never-introduce list
              -- has ended since (an add changes no introduction, and the act's
              -- invalidate rolls back with its raise) is never read again, so
              -- it holds no waiting slot.
              AND private.dating_pair_safe(i.user_low_id, i.user_high_id,
                    public.dating_phone_hmac_for_user(i.user_low_id), public.dating_phone_hmac_for_user(i.user_high_id))
              -- Fix round 1 (M-7): as the read, a card whose other person is
              -- not a current candidate (paused, unseen for 14 days, left) is
              -- hidden, so it holds no waiting slot either.
              AND public.dating_candidate_is_current(CASE WHEN i.user_low_id = p_user THEN i.user_high_id ELSE i.user_low_id END))))
  END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_person_current(p_user uuid, p_at timestamp with time zone, p_cfg jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT coalesce(public.dating_candidate_is_current(p_user), false)
    AND NOT EXISTS (SELECT 1 FROM public.dating_session_context AS c
                     WHERE c.user_id = p_user AND c.dating_allowed_here IS FALSE)
    AND coalesce(private.dating_cool_off_ends_at(p_user) <= private.dating_first_drop_at(p_user, p_at), false) -- Spec 2 W5c: and
    AND NOT coalesce(private.dating_generation_removed(p_user, p_at, p_cfg), false); -- Spec 2 W5c (§5.2 15)
$function$;

CREATE OR REPLACE FUNCTION public.run_dating_generation_tick(p_now timestamp with time zone DEFAULT now(), p_country text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_version text;
  v_cfg jsonb;
  v_out jsonb := '[]'::jsonb;
  v_c record;
  v_window date;
  v_due timestamptz;
  v_keys text[];
  v_key text;
  v_res jsonb;
  v_full boolean; -- fix round 2 (N-2)
  v_stopped boolean := false;
BEGIN
  IF public.dating_flag_enabled('dating_candidate_generation') IS NOT TRUE THEN
    RETURN private.dating_generation_skip('flag_disabled');
  END IF;
  -- The keys next (W1's guard, in its order: a replaced exclusion key is
  -- counted), then Dating itself, then the config.
  IF private.dating_exclusion_key_mismatch() THEN
    PERFORM private.bump_metric_internal('dating.exclusion_key.mismatch');
    RETURN private.dating_generation_skip('exclusion_key_mismatch');
  END IF;
  IF public.app_setting('dating_exclusion_key') IS NULL OR private.dating_field_key_present() IS NOT TRUE THEN
    RETURN private.dating_generation_skip('missing_key');
  END IF;
  IF private.dating_field_key_usable() IS NOT TRUE THEN
    PERFORM private.bump_metric_internal('dating.field_key.mismatch');
    RETURN private.dating_generation_skip('field_key_mismatch');
  END IF;
  IF public.dating_flag_enabled('dating_mode_enabled') IS NOT TRUE THEN
    RETURN private.dating_generation_skip('flag_disabled');
  END IF;
  SELECT c.o_version, c.o_config INTO v_version, v_cfg FROM private.dating_intro_config() AS c;
  IF v_version IS NULL THEN
    RETURN private.dating_generation_skip('no_active_config');
  END IF;
  BEGIN -- Spec 2 W5c: a signal failure never stops generation (Ruling)
  PERFORM private.dating_run_signals(p_now, v_cfg); -- Spec 2 W5c (§5.10): before any partition
  EXCEPTION WHEN OTHERS THEN -- Spec 2 W5c
    PERFORM private.bump_metric_internal('dating.signal.failed'); -- Spec 2 W5c
  END; -- Spec 2 W5c
  FOR v_c IN
    SELECT c.country_code::text AS country, c.reference_tz, c.generation_hour_utc AS hour
      FROM public.country_safety_config AS c
     WHERE c.is_current AND c.dating_enabled
       AND (p_country IS NULL OR c.country_code::text = p_country)
     ORDER BY c.country_code
  LOOP
    -- The cohort: the country's local date at its latest generation hour
    -- (at that hour, today's; at a later hour, the same one).
    v_due := date_trunc('day', p_now AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + make_interval(hours => v_c.hour);
    IF v_due > p_now THEN
      v_due := v_due - interval '1 day';
    END IF;
    v_window := (v_due AT TIME ZONE v_c.reference_tz)::date;
    v_full := false;
    v_keys := '{}';
    IF v_c.hour = extract(hour FROM p_now AT TIME ZONE 'UTC') THEN
      -- The country's hour: every partition (a new one, or a failed one again).
      v_full := true;
    ELSIF (p_now AT TIME ZONE v_c.reference_tz)::date = v_window THEN
      -- A later hour of the cohort day (§4.6 "whose cohort is not done",
      -- §5.5): its pending and failed partitions, until done or
      -- dead-lettered; and when the cohort has no run at all, every due one.
      v_keys := ARRAY(SELECT r.partition_key FROM public.dating_generation_runs AS r
                       WHERE r.algorithm_version = v_version AND r.cohort_window = v_window::text
                         AND split_part(r.partition_key, ':', 1) = v_c.country
                         AND r.state IN ('pending', 'failed') AND r.attempts < coalesce((v_cfg ->> 'max_attempts')::int, 3)
                       ORDER BY 1);
      v_full := NOT EXISTS (SELECT 1 FROM public.dating_generation_runs AS r
                             WHERE r.algorithm_version = v_version AND r.cohort_window = v_window::text
                               AND split_part(r.partition_key, ':', 1) = v_c.country);
    END IF;
    IF v_full THEN
      IF (SELECT count(*) FROM public.dating_profiles AS p
            JOIN public.dating_enrollments AS e ON e.user_id = p.user_id AND e.state = 'active'
           WHERE p.country_code::text = v_c.country) > (v_cfg ->> 'partition_people_max')::int THEN
        v_keys := ARRAY(SELECT DISTINCT v_c.country || ':' || p.region_code FROM public.dating_profiles AS p
                          JOIN public.dating_enrollments AS e ON e.user_id = p.user_id AND e.state = 'active'
                         WHERE p.country_code::text = v_c.country AND p.region_code IS NOT NULL ORDER BY 1);
      ELSE
        v_keys := ARRAY[v_c.country];
      END IF;
    END IF;
    FOREACH v_key IN ARRAY v_keys LOOP
      IF v_stopped THEN
        -- A key the stopped tick never reached: pending, for a later hour.
        BEGIN
          INSERT INTO public.dating_generation_runs (algorithm_version, cohort_window, state, seed, partition_key, attempts)
          VALUES (v_version, v_window::text, 'pending',
                  encode(extensions.digest(v_version || v_window::text || v_key, 'sha256'), 'hex'), v_key, 0)
          ON CONFLICT (algorithm_version, cohort_window, partition_key) DO NOTHING;
        EXCEPTION WHEN OTHERS THEN
          PERFORM private.bump_metric_internal('dating.generation.failed');
        END;
        CONTINUE;
      END IF;
      BEGIN
        v_res := private.dating_generate_partition(
          v_c.country, nullif(split_part(v_key, ':', 2), ''), v_key, v_window, p_now, v_version, v_cfg);
      EXCEPTION WHEN query_canceled OR OTHERS THEN
        -- The claim itself failed (the partition's own work catches its own),
        -- so no run row is left: one is written pending, for a later hour.
        PERFORM private.bump_metric_internal('dating.generation.failed');
        v_res := jsonb_build_object('partition', v_key, 'error', SQLSTATE);
        BEGIN
          INSERT INTO public.dating_generation_runs AS r (algorithm_version, cohort_window, state, seed, partition_key, attempts)
          VALUES (v_version, v_window::text, 'pending',
                  encode(extensions.digest(v_version || v_window::text || v_key, 'sha256'), 'hex'), v_key, 0)
          ON CONFLICT (algorithm_version, cohort_window, partition_key) DO NOTHING;
        EXCEPTION WHEN OTHERS THEN
          NULL;
        END;
      END;
      v_out := v_out || jsonb_build_array(v_res);
      -- A timeout or a cancel: what is done stays; nothing more starts.
      IF v_res ->> 'error' = '57014' THEN
        v_stopped := true;
      END IF;
    END LOOP;
  END LOOP;
  RETURN jsonb_build_object('runs', v_out);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_dating_operational_health()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'dating_enabled',public.dating_flag_enabled('dating_mode_enabled'),
    'candidate_generation_enabled',public.dating_flag_enabled('dating_candidate_generation'),
    'exclusion_key_present',public.app_setting('dating_exclusion_key') IS NOT NULL,
    'relationships_ended_without_exclusion_24h',(
      SELECT count(*) FROM public.relationships r
      WHERE r.status = 'ended'
        AND r.ended_at >= now() - interval '24 hours'
        AND NOT EXISTS (
          SELECT 1 FROM public.dating_former_partner_exclusions e
          WHERE e.relationship_id = r.id
        )
    ),
    'active_algorithm_versions',(SELECT count(*) FROM public.dating_algorithm_configs WHERE state='active'),
    'introductions_config',(private.dating_intro_config()).o_version, -- Spec 2 W5a (§5.5): NULL = generation refuses
    'generation_by_country',(SELECT coalesce(jsonb_object_agg(x.partition_key, jsonb_build_object( -- Spec 2 W5a (§4.4 health v2)
                               'cohort', x.cohort_window, 'state', x.state, 'attempts', x.attempts)), '{}'::jsonb) -- Spec 2 W5a
                             FROM (SELECT DISTINCT ON (r.partition_key) r.partition_key, r.cohort_window, r.state, r.attempts -- Spec 2 W5a
                                     FROM public.dating_generation_runs AS r WHERE r.created_at >= now() - interval '36 hours' -- Spec 2 W5a
                                    ORDER BY r.partition_key, r.created_at DESC) AS x), -- Spec 2 W5a
    'stuck_generation_runs',(SELECT count(*) FROM public.dating_generation_runs WHERE state='processing' AND started_at < now()-interval '30 minutes'),
    'failed_generation_runs_24h',(SELECT count(*) FROM public.dating_generation_runs WHERE state IN ('failed','dead_letter') AND created_at >= now()-interval '24 hours'),
    'expired_open_introductions',(SELECT count(*) FROM public.dating_introductions WHERE state IN ('generated','presented','interested') AND expires_at <= now()),
    'pending_bio_moderation',(SELECT count(*) FROM public.dating_profiles WHERE moderation_state='pending'),
    'pending_photo_moderation',(SELECT count(*) FROM public.dating_profile_photos WHERE moderation_state='pending'),
    'environment',private.attune_environment(), -- Spec 2 W1d
    'field_key_present',private.dating_field_key_present(), -- Spec 2 W1d
    -- Spec 2 W1d (§2.4): nothing can write an RPC's parameters to the log.
    'log_settings_safe',coalesce(current_setting('log_statement', true) IN ('none', 'ddl')
      AND (current_setting('log_min_duration_statement', true) = '-1'
           OR current_setting('log_parameter_max_length', true) = '0')
      AND current_setting('log_parameter_max_length_on_error', true) = '0', false),
    'enabled_countries',to_jsonb(private.dating_open_countries()), -- Spec 2 W1d
    'age_assurance_mode',private.dating_verification_mode(), -- Spec 2 W4a
    'verification_awaiting_review',(SELECT count(*) FROM public.dating_verification_sessions WHERE state='awaiting_review'), -- Spec 2 W4a
    'verification_oldest_waiting_hours',(SELECT floor(extract(epoch FROM now() - min(coalesce(awaiting_since, updated_at))) / 3600)::int -- Spec 2 W4a (fix round 1, M-8)
                                           FROM public.dating_verification_sessions WHERE state='awaiting_review'), -- Spec 2 W4a
    -- Spec 2 W1d (B2 I-5, B5 M-4, B6 M-5): each key set and its stored
    -- Spec 2 W1d fingerprint equal (read only; never the counting mismatch()).
    'exclusion_key_fingerprint_ok',private.dating_exclusion_key_ready(), -- Spec 2 W1d
    'field_key_fingerprint_ok',private.dating_field_key_ready(), -- Spec 2 W1d
    'safety_counters_7d',(SELECT jsonb_object_agg(k.key, coalesce((SELECT sum(c.count) FROM public.metric_counters c -- Spec 2 W1d
                            WHERE c.key = k.key AND c.day >= (now() AT TIME ZONE 'utc')::date - 6), 0)) -- Spec 2 W1d
      FROM unnest(ARRAY['dating.deletion.uncarried', 'dating.exclusion_key.mismatch', 'dating.exclusion_key.unseeded', -- Spec 2 W1d
                        'dating.eligibility.key_not_ready', 'dating.field_key.mismatch', 'dating.field_key.missing', -- Spec 2 W1d
                        'dating.parked_pause.failed', -- Spec 2 W1d (fix round 1, M-5)
                        'dating.path_pause.failed', 'dating.gates.busy', -- Spec 2 W2
                        'dating.gates.failed', 'dating.gentle_wait.undated', -- Spec 2 W2 (Task 3 carry: W2 batch 1 fix round 1, M-4 and M-3)
                        'dating.path_pause.swept', -- Spec 2 W2 (Task 3 fix round 1, I-1)
                        'dating.gentle_wait.seen', 'dating.gentle_wait.account_deleted_7d', -- Spec 2 W2 (migration 3, §6.9)
                        'dating.gentle_wait.clear_busy', 'dating.gentle_wait.seen_skipped', 'dating.home.unreadable_field', -- Spec 2 W2 (migration 3 fix round 1)
                        'dating.kill_switch.pending', 'dating.kill_switch.unreadable', -- Spec 2 W1d (migration 11)
                        'dating.verify.sweep_failed', 'dating.verify.id_review_expired', -- Spec 2 W4a (fix round 1, M-7)
                        'dating.deletion.prepare_carry_failed', 'dating.deletion.late_carry_failed', -- W1 final fix (M-4); -- Spec 2 W5a: and
                        'dating.generation.skipped', 'dating.generation.failed', 'dating.generation.unreadable', -- Spec 2 W5a
                        'dating.generation.busy', -- Spec 2 W5a (Task 2 fix round 2, N-3); -- Spec 2 W5c: and
                        'dating.signal.failed', 'dating.signal.busy', 'dating.fairness.unreadable', -- Spec 2 W5c (fix round 1, I-2, M-1, M-5); -- Spec 2 W5 final: and
                        'dating.digest.push_key_missing', 'dating.digest.failed']) AS k(key)), -- Spec 2 W5 final (M-5, M-3): a digest that sends nothing is seen
    -- Spec 2 W5a (Task 2 fix round 2, N-3): people left out over the bound, per country, 7 days
    'generation_truncated_7d',(SELECT coalesce(jsonb_object_agg(x.country, x.n), '{}'::jsonb) FROM ( -- Spec 2 W5a
                                 SELECT substr(c.key, char_length('dating.generation.truncated.') + 1) AS country, sum(c.count) AS n -- Spec 2 W5a
                                   FROM public.metric_counters AS c -- Spec 2 W5a
                                  WHERE left(c.key, char_length('dating.generation.truncated.')) = 'dating.generation.truncated.' -- Spec 2 W5a
                                    AND c.day >= (now() AT TIME ZONE 'utc')::date - 6 -- Spec 2 W5a
                                  GROUP BY 1) AS x), -- Spec 2 W5a
    -- W1 final fix (M-4): app deletions refused for a missing exclusion key
    -- W1 final fix (delete-account records prepare's message) in 7 days.
    'deletions_refused_key_missing_7d',(SELECT count(*) FROM public.account_deletion_requests AS r -- W1 final fix (M-4)
                                         WHERE r.completed_at IS NULL AND r.requested_at >= now() - interval '7 days' -- W1 final fix (M-4)
                                           AND r.failure_reason LIKE '%deletion:enforcement_key_missing%'), -- W1 final fix (M-4)
    -- Spec 2 W1d (fix round 1, I-1): every purge still pending, until a switch clears it.
    'kill_switch_pending',(SELECT coalesce(jsonb_agg(jsonb_build_object('scope', k.scope, 'since', k.first_failed_at, -- Spec 2 W1d
                             'sqlstate', k.last_sqlstate, 'attempts', k.attempts) ORDER BY k.scope), '[]'::jsonb) -- Spec 2 W1d
                           FROM private.dating_kill_switch_pending k) -- Spec 2 W1d
  );
$function$;

-- Spec 2 W5 final (M-2): the partition, re-created from its LIVE body (W5a)
-- with only its close step's re-check added (lines marked Spec 2 W5 final).
CREATE OR REPLACE FUNCTION private.dating_generate_partition(p_country text, p_region text, p_key text, p_window date, p_now timestamp with time zone, p_version text, p_cfg jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_seed constant text := encode(extensions.digest(p_version || p_window::text || p_key, 'sha256'), 'hex');
  v_max constant integer := coalesce((p_cfg ->> 'max_attempts')::int, 3);
  v_people_max constant integer := (p_cfg ->> 'partition_people_max')::int;
  v_scan constant integer := (p_cfg ->> 'scan_limit')::int;
  v_fw constant numeric := coalesce((p_cfg #>> '{rank,feasibility_weight}')::numeric, 10);
  v_vw constant numeric := coalesce((p_cfg #>> '{rank,values_weight}')::numeric, 3);
  v_band constant numeric := coalesce((p_cfg #>> '{rank,band_width}')::numeric, 3);
  v_jit constant numeric := coalesce((p_cfg #>> '{rank,jitter}')::numeric, 2.0);
  v_window constant interval := make_interval(days => coalesce((p_cfg #>> '{rank,exposure_window_days}')::int, 7));
  v_life constant interval := make_interval(days => (p_cfg ->> 'lifetime_days')::int);
  v_run public.dating_generation_runs;
  v_u record;
  v_c record;
  v_cap integer;
  v_id uuid;
  v_seq integer := 0;
  v_state text;
  v_person private.dating_gen_person;
  v_n_home integer := 0; -- fix round 1 (I-2): current people loaded, per group
  v_n_abroad integer := 0;
  v_truncated boolean := false;
  v_n integer; -- fix round 1 (M-6): rows locked
  v_lock text;
BEGIN
  INSERT INTO public.dating_generation_runs AS r
    (algorithm_version, cohort_window, state, seed, partition_key, attempts, started_at)
  VALUES (p_version, p_window::text, 'processing', v_seed, p_key, 1, now())
  ON CONFLICT (algorithm_version, cohort_window, partition_key) DO UPDATE
    SET state = 'processing', attempts = r.attempts + 1, started_at = now(), last_error_code = NULL
    WHERE r.state IN ('pending', 'failed') AND r.attempts < v_max
  RETURNING * INTO v_run;
  -- No row: completed, being run, or out of attempts. Never ours (§5.7).
  IF v_run.id IS NULL THEN
    RETURN jsonb_build_object('partition', p_key, 'skipped', 'partition_unavailable');
  END IF;

  BEGIN
    DROP TABLE IF EXISTS pg_temp.dating_gen_people;
    CREATE TEMP TABLE dating_gen_people (
      user_id uuid PRIMARY KEY,
      p private.dating_gen_person NOT NULL,
      home boolean NOT NULL,
      exposure integer NOT NULL,
      capacity integer NOT NULL
    ) ON COMMIT DROP;
    -- The partition's own people, then those elsewhere open to it (§5.5).
    -- Fix round 1 (I-2): each group's bound (partition_people_max) counts
    -- current candidates only, and who falls past it rotates with the
    -- cohort's seed, never the same people every day; a run that leaves
    -- anyone out is counted (dating.generation.truncated.<country>).
    FOR v_u IN
      SELECT x.user_id, x.home
        FROM (SELECT p.user_id, true AS home
                FROM public.dating_profiles AS p
                JOIN public.dating_enrollments AS e ON e.user_id = p.user_id AND e.state = 'active'
               WHERE p.country_code::text = p_country AND (p_region IS NULL OR p.region_code = p_region)
              UNION ALL
              SELECT d.user_id, false
                FROM public.dating_preferences AS d
                JOIN public.dating_profiles AS p ON p.user_id = d.user_id
                JOIN public.dating_enrollments AS e ON e.user_id = d.user_id AND e.state = 'active'
               WHERE p_country = ANY (d.open_abroad::text[]) AND p.country_code::text IS DISTINCT FROM p_country) AS x
       ORDER BY x.home DESC, md5(v_seed || x.user_id::text), x.user_id
    LOOP
      BEGIN
        CONTINUE WHEN private.dating_person_current(v_u.user_id, p_now, p_cfg) IS NOT TRUE;
        IF (v_u.home AND v_n_home >= v_people_max) OR (NOT v_u.home AND v_n_abroad >= v_people_max) THEN
          v_truncated := true;
          CONTINUE;
        END IF;
        v_person := private.dating_person(v_u.user_id, p_now, p_cfg);
        CONTINUE WHEN v_person IS NULL;
        INSERT INTO pg_temp.dating_gen_people (user_id, p, home, exposure, capacity)
        VALUES (v_u.user_id, v_person, v_u.home,
                (SELECT count(*)::int FROM public.dating_introductions AS i
                  WHERE v_u.user_id IN (i.user_low_id, i.user_high_id)
                    AND i.created_at > p_now - v_window AND i.created_at <= p_now),
                private.dating_capacity(v_u.user_id, p_now, p_cfg));
        IF v_u.home THEN
          v_n_home := v_n_home + 1;
        ELSE
          v_n_abroad := v_n_abroad + 1;
        END IF;
      EXCEPTION WHEN raise_exception THEN
        IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
          PERFORM private.bump_metric_internal('dating.generation.unreadable');
        ELSE
          RAISE;
        END IF;
      END;
    END LOOP;
    IF v_truncated THEN
      PERFORM private.bump_metric_internal('dating.generation.truncated.' || lower(p_country));
    END IF;

    -- §5.4 1: fewest introductions in 7 days first, ties by the seed.
    FOR v_u IN
      SELECT g.user_id, g.p FROM pg_temp.dating_gen_people AS g
       WHERE g.home
       ORDER BY g.exposure, md5(v_seed || g.user_id::text), g.user_id
    LOOP
      SELECT g.capacity INTO v_cap FROM pg_temp.dating_gen_people AS g WHERE g.user_id = v_u.user_id;
      CONTINUE WHEN v_cap <= 0;
      FOR v_c IN
        WITH scanned AS MATERIALIZED (
          -- §5.5: at most scan_limit candidates looked at per person.
          SELECT g.user_id, g.p, g.exposure FROM pg_temp.dating_gen_people AS g
           WHERE g.user_id <> v_u.user_id AND g.capacity > 0
             AND (g.p).age BETWEEN (v_u.p).min_age AND (v_u.p).max_age
             AND (v_u.p).age BETWEEN (g.p).min_age AND (g.p).max_age
           ORDER BY g.exposure, md5(v_seed || g.user_id::text), g.user_id
           LIMIT v_scan
        ), admitted AS MATERIALIZED (
          SELECT s.* FROM scanned AS s WHERE private.dating_admits(v_u.p, s.p, p_cfg)
        ), passing AS (
          SELECT a.user_id, a.p, a.exposure,
                 -- §5.4 3: feasibility 0-3
                 (CASE WHEN (v_u.p).intention = (a.p).intention THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).children_want = (a.p).children_want AND (a.p).children_want IN ('yes', 'no') THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).country = (a.p).country AND (v_u.p).region = (a.p).region
                          AND ((v_u.p).side IS NULL OR (a.p).side IS NULL OR (v_u.p).side = (a.p).side) THEN 1 ELSE 0 END) AS f,
                 -- §5.4 4: stated values 0-4
                 (CASE WHEN (v_u.p).intention = 'marriage' AND (a.p).intention = 'marriage'
                         AND (v_u.p).timeline = (a.p).timeline THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).importance = (a.p).importance THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).faith = (a.p).faith AND (a.p).faith <> 'prefer_not_to_say' THEN 1 ELSE 0 END
                  + CASE WHEN (v_u.p).family = (a.p).family THEN 1 ELSE 0 END) AS v,
                 -- §5.4 7: (first 3 bytes of md5(seed || U || c)) mod 1000 / 1000 x 2.0
                 ((('x' || substr(md5(v_seed || v_u.user_id::text || a.user_id::text), 1, 6))::bit(24)::int % 1000)::numeric
                   / 1000 * v_jit) AS jitter
            FROM admitted AS a
           WHERE private.dating_pair_safe(v_u.user_id, a.user_id, (v_u.p).hmac, (a.p).hmac)
             AND private.dating_pair_new(v_u.user_id, a.user_id)
        ), banded AS (
          SELECT x.*, v_fw * x.f + v_vw * x.v AS base, max(v_fw * x.f + v_vw * x.v) OVER () AS best FROM passing AS x
        )
        SELECT b.user_id, b.p, b.f, b.v, b.exposure, b.jitter FROM banded AS b
         WHERE b.base >= b.best - v_band
         ORDER BY b.exposure + b.jitter, md5(v_seed || b.user_id::text), b.user_id
      LOOP
        EXIT WHEN v_cap <= 0;
        CONTINUE WHEN (SELECT g.capacity FROM pg_temp.dating_gen_people AS g WHERE g.user_id = v_c.user_id) <= 0;
        -- Fix round 2 (N-1): both still enrolled at this statement, a plain
        -- re-check. The run never locks an enrolment, so no leave, pause,
        -- resume or switch ever waits on it; the close below and the hourly
        -- sweep (expire_dating_introductions) take what a leave commits
        -- while the run is open. The two users' rows are taken KEY SHARE
        -- SKIP LOCKED, lowest id first: the introduction's own foreign-key
        -- lock, taken without waiting on a deletion in progress (busy:
        -- tried three times, then skipped and counted).
        v_lock := 'gone';
        FOR v_try IN 1..3 LOOP
          v_lock := 'gone';
          EXIT WHEN (SELECT count(*) FROM public.dating_enrollments AS e
                      WHERE e.user_id IN (v_u.user_id, v_c.user_id) AND e.state = 'active') <> 2;
          SELECT count(*) INTO v_n FROM (SELECT 1 FROM public.users AS u WHERE u.id IN (v_u.user_id, v_c.user_id)
                                          ORDER BY u.id FOR KEY SHARE SKIP LOCKED) AS l;
          v_lock := CASE WHEN v_n = 2 THEN 'held' ELSE 'busy' END;
          EXIT WHEN v_lock = 'held' OR v_try = 3;
          PERFORM pg_catalog.pg_sleep(0.05);
        END LOOP;
        IF v_lock = 'busy' THEN
          PERFORM private.bump_metric_internal('dating.generation.busy');
        END IF;
        CONTINUE WHEN v_lock IS DISTINCT FROM 'held';
        v_id := NULL;
        INSERT INTO public.dating_introductions AS i
          (pair_key, user_low_id, user_high_id, state, algorithm_version, cohort_window, partition_key,
           visible_from_low, visible_from_high, expires_at, reasons, rank_detail, created_at)
        SELECT public.dating_pair_key(v_u.user_id, v_c.user_id), least(v_u.user_id, v_c.user_id), greatest(v_u.user_id, v_c.user_id),
               'generated', p_version, p_window, p_key,
               CASE WHEN v_u.user_id < v_c.user_id THEN (v_u.p).visible_from ELSE (v_c.p).visible_from END,
               CASE WHEN v_u.user_id < v_c.user_id THEN (v_c.p).visible_from ELSE (v_u.p).visible_from END,
               greatest((v_u.p).visible_from, (v_c.p).visible_from) + v_life,
               private.dating_reasons(v_u.p, v_c.p),
               jsonb_build_object('f', v_c.f, 'v', v_c.v, 'exposure', v_c.exposure, 'jitter', round(v_c.jitter, 3), 'seq', v_seq + 1),
               p_now
        ON CONFLICT (pair_key) DO NOTHING
        RETURNING i.id INTO v_id;
        CONTINUE WHEN v_id IS NULL;
        v_seq := v_seq + 1;
        v_cap := v_cap - 1;
        UPDATE pg_temp.dating_gen_people AS g SET capacity = g.capacity - 1 WHERE g.user_id IN (v_u.user_id, v_c.user_id);
        -- §5.4 8: the candidate's exposure rises for the rest of the run.
        UPDATE pg_temp.dating_gen_people AS g SET exposure = g.exposure + 1 WHERE g.user_id = v_c.user_id;
      END LOOP;
    END LOOP;

    -- Spec 2 W5 final (M-2): a filter answer changed while the run was open
    -- Spec 2 W5 final (who to meet, the age range, the scope: any of filters
    -- Spec 2 W5 final 2-10) is read again here, and this run's introductions
    -- Spec 2 W5 final the answers now refuse go before they publish. Each
    -- Spec 2 W5 final introduced person is read once (never more than the
    -- Spec 2 W5 final people loaded above), each pair checked by the pure
    -- Spec 2 W5 final filter; an unreadable person fails the partition (retried).
    WITH m AS MATERIALIZED ( -- Spec 2 W5 final (M-2)
      SELECT x.id, private.dating_person(x.id, p_now, p_cfg) AS p -- Spec 2 W5 final (M-2)
        FROM (SELECT DISTINCT u.id FROM public.dating_introductions AS i, -- Spec 2 W5 final (M-2)
                     unnest(ARRAY[i.user_low_id, i.user_high_id]) AS u(id) -- Spec 2 W5 final (M-2)
               WHERE i.created_at = p_now AND i.partition_key = p_key) AS x) -- Spec 2 W5 final (M-2)
    DELETE FROM public.dating_introductions AS i USING m AS a, m AS b -- Spec 2 W5 final (M-2)
     WHERE i.created_at = p_now AND i.partition_key = p_key -- Spec 2 W5 final (M-2)
       AND a.id = i.user_low_id AND b.id = i.user_high_id -- Spec 2 W5 final (M-2)
       AND private.dating_admits(a.p, b.p, p_cfg) IS NOT TRUE; -- Spec 2 W5 final (M-2)
    GET DIAGNOSTICS v_n = ROW_COUNT; -- Spec 2 W5 final (M-2)
    v_seq := v_seq - v_n; -- Spec 2 W5 final (M-2)
    -- Fix round 2 (N-1, N-4): the close. Anyone no longer active by now (a
    -- leave or a pause that committed while the run was open) loses this
    -- run's introductions; what a leave commits after this, the hourly
    -- sweep takes.
    DELETE FROM public.dating_introductions AS i
     WHERE i.created_at = p_now AND i.partition_key = p_key
       AND EXISTS (SELECT 1 FROM unnest(ARRAY[i.user_low_id, i.user_high_id]) AS u(id)
                    WHERE NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = u.id AND e.state = 'active'));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_seq := v_seq - v_n;

    -- §5.6, §6.9: an empty day per person and region; deliveries per country.
    PERFORM private.bump_metric_internal('dating.empty_day.' || lower(p_country) || '.' || lower(coalesce((g.p).region, 'none')))
       FROM pg_temp.dating_gen_people AS g
      WHERE g.home AND NOT EXISTS (SELECT 1 FROM public.dating_introductions AS i
                                    WHERE g.user_id IN (i.user_low_id, i.user_high_id) AND i.created_at = p_now);
    IF v_seq > 0 THEN
      PERFORM private.bump_metric_internal('dating.intros_delivered.' || lower(p_country)) FROM generate_series(1, v_seq);
    END IF;
    UPDATE public.dating_generation_runs SET state = 'completed', completed_at = now() WHERE id = v_run.id;
  EXCEPTION
  -- Fix round 1 (I-1): a statement timeout or a cancel (57014, which OTHERS
  -- never catches) fails this partition only, as any error does; the tick
  -- then starts nothing more, and what it finished stays.
  WHEN query_canceled THEN
    UPDATE public.dating_generation_runs AS r
       SET state = CASE WHEN r.attempts >= v_max THEN 'dead_letter' ELSE 'failed' END,
           last_error_code = '57014', completed_at = now()
     WHERE r.id = v_run.id;
    PERFORM private.bump_metric_internal('dating.generation.failed');
    RETURN jsonb_build_object('partition', p_key, 'error', '57014');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    UPDATE public.dating_generation_runs
       SET state = CASE WHEN attempts >= v_max THEN 'dead_letter' ELSE 'failed' END,
           last_error_code = v_state, completed_at = now()
     WHERE id = v_run.id;
    PERFORM private.bump_metric_internal('dating.generation.failed');
    RETURN jsonb_build_object('partition', p_key, 'error', v_state);
  END;
  RETURN jsonb_build_object('partition', p_key, 'cohort', p_window, 'created', v_seq);
END;
$function$;

-- =====================================================================
-- 6b. Spec 2 W5 final (M-7, §5.11): an active config's values never change
--     in place; any change is a new version (a new row). Its state, its
--     review references and its dates stay writable (retiring it, the
--     production DEV- guard above them).
-- =====================================================================
CREATE OR REPLACE FUNCTION private.dating_config_active_frozen()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF OLD.state = 'active'
     AND (NEW.version IS DISTINCT FROM OLD.version OR NEW.config IS DISTINCT FROM OLD.config
          OR NEW.config_hash IS DISTINCT FROM OLD.config_hash) THEN
    RAISE EXCEPTION 'config:active_frozen' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS dating_config_active_frozen ON public.dating_algorithm_configs;
CREATE TRIGGER dating_config_active_frozen BEFORE UPDATE ON public.dating_algorithm_configs
  FOR EACH ROW EXECUTE FUNCTION private.dating_config_active_frozen();

-- =====================================================================
-- 6c. Spec 2 W5 final (I-2): every W5 production gate the ledger records,
--     in the enforced gate record (a fixed text, so a re-apply is the
--     same; never once a review is recorded against it).
-- =====================================================================
UPDATE private.flag_production_gates
   SET gate = 'Spec 2 W5 gate: dating_exclusion_key provisioned, DV sign-off on never-introduce, introductions_v2 active with real review refs (any change to its values is a new version); W5a: generation commits per partition, and a partition run is measured under ~2 s at the launch partition size; the run cost is optimised before any partition passes ~1,500 people; race case 30''s overlap check is rewritten with that rework; the signals and the digest commit per step too (their lock holds and post-open waits); generation_hour_utc stays aligned across countries, or a publish guard is added before one changes; the field-key rotation must not end every open introduction (the sensitive-row trigger compares ciphertext); freshness through PostgREST verified on the development project (W5 final I-1)'
 WHERE flag_key = 'dating_candidate_generation' AND review_ref IS NULL;

-- =====================================================================
-- 7. Grants (re-asserted by the twin). The queue and the reports are the
--    service role's (W7b's console), never a client's; the signals and the
--    fairness job are the database's own (the job decrypts, S-4); the
--    Other countries read is the app's.
-- =====================================================================
REVOKE ALL ON public.dating_moderation_cases, public.dating_fairness_reports FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dating_moderation_cases, public.dating_fairness_reports TO service_role;
REVOKE ALL ON FUNCTION private.dating_open_signal_case(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_first_messages(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_dragnet_holds(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_device_accounts_hold(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_run_signals(timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_throttled(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_signal_cleared(uuid, text, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_generation_removed(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_fairness_weekly(date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_abroad_options() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_abroad_options() TO authenticated;
REVOKE ALL ON FUNCTION private.dating_generate_partition(text, text, text, date, timestamptz, text, jsonb) FROM PUBLIC, anon, authenticated, service_role; -- Spec 2 W5 final (M-2)
REVOKE ALL ON FUNCTION private.dating_config_active_frozen() FROM PUBLIC, anon, authenticated, service_role; -- Spec 2 W5 final (M-7)
COMMIT;
