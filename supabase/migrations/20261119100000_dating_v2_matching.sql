-- supabase/migrations/20261119100000_dating_v2_matching.sql
-- Spec 2 W5a (§4.9 W5a, §4.3, §4.10, §5.1-§5.4, §5.7, §5.11; R12; carries
-- 1-4, 6-8, 10): matching v2. The v1 trait objects go (snapshots, the
-- alignment and similarity functions, the v1 generators, the v1 match read,
-- the flag dating_alignment_algorithm_v1); introductions get their v2
-- columns and one row per pair ever (UNIQUE (pair_key)); matches get
-- pair_key (filled by a trigger, so no insert can leave it out); the
-- introductions_v2 config (§5.11) is seeded as a draft with a CHECK that
-- daily_new_max is 1-3, waiting_max 1-6, cool_off_hours at least 72 and
-- lifetime_days at least 1, and a production guard refuses
-- to activate a config whose review references start DEV-; the hard filters
-- are rewritten over one person row (private.dating_gen_person), so the
-- single-pair predicate and the generation run (Task 2's section) share
-- one implementation of §5.2; the 72 h cool-off is a function
-- (dating_cool_off_ends_at, carry 1); the functions that named a dropped
-- object are re-created from their live bodies (marked -- Spec 2 W5a).
-- Dating stays off: nothing here turns a flag on or activates a config.
-- Idempotent: applied twice, the second run changes nothing.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- =====================================================================
-- 1. The v1 trait objects (§4.10 Remove [W5]). No client calls any of
--    them (lib/ has no caller; the W5a contract greps). The weekly
--    generation cron goes now; Task 2's section schedules the hourly tick.
-- =====================================================================
DROP FUNCTION IF EXISTS public.generate_dating_candidates_for_user(uuid, text, text, text);
DROP FUNCTION IF EXISTS public.run_dating_candidate_generation(text);
DROP FUNCTION IF EXISTS public.build_dating_feature_snapshot(uuid, text);
DROP FUNCTION IF EXISTS public.dating_has_historical_consent(uuid);
DROP FUNCTION IF EXISTS public.dating_normalize_scalar(numeric, numeric, numeric);
DROP FUNCTION IF EXISTS public.dating_alignment_score(jsonb, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.dating_alignment_reasons(jsonb, jsonb);
DROP FUNCTION IF EXISTS public.dating_component_similarity(numeric, numeric);
DROP FUNCTION IF EXISTS public.dating_set_similarity(jsonb, jsonb);
-- Carry 8 (W4 M-3): the v1 match read sent another person's name to any
-- phone; it has no caller, so it goes (W6a builds get_my_dating_matches(boolean)).
DROP FUNCTION IF EXISTS public.get_my_dating_matches(integer);
DELETE FROM public.feature_flags WHERE key = 'dating_alignment_algorithm_v1';
DELETE FROM private.flag_production_gates WHERE flag_key = 'dating_alignment_algorithm_v1';
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-candidate-generation') THEN
    PERFORM cron.unschedule('dating-candidate-generation');
  END IF;
END $$;

-- =====================================================================
-- 2. Introductions v2 (§4.3): no band, no summaries, no score, no
--    snapshots; the cohort, the partition, when each side sees it, the
--    reason ids (<= 3) and the internal rank detail (never returned).
--    One introduction per pair, ever (filter 14).
-- =====================================================================
ALTER TABLE public.dating_introductions
  DROP COLUMN IF EXISTS display_band,
  DROP COLUMN IF EXISTS explanation_features,
  DROP COLUMN IF EXISTS low_summary,
  DROP COLUMN IF EXISTS high_summary,
  DROP COLUMN IF EXISTS internal_score,
  DROP COLUMN IF EXISTS snapshot_low_id,
  DROP COLUMN IF EXISTS snapshot_high_id,
  ADD COLUMN IF NOT EXISTS cohort_window date,
  ADD COLUMN IF NOT EXISTS partition_key text,
  ADD COLUMN IF NOT EXISTS visible_from_low timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS visible_from_high timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS reasons text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS rank_detail jsonb;
DROP TABLE IF EXISTS public.dating_feature_snapshots;
DROP INDEX IF EXISTS public.dating_introductions_pair_algorithm_created_idx;
-- Dating has never been on in production; a development database keeps
-- the newest row of a pair.
DELETE FROM public.dating_introductions AS i
 USING public.dating_introductions AS j
 WHERE i.pair_key = j.pair_key AND (i.created_at, i.id) < (j.created_at, j.id);
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'dating_introductions_pair_key_key') THEN
    ALTER TABLE public.dating_introductions ADD CONSTRAINT dating_introductions_pair_key_key UNIQUE (pair_key);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'dating_introductions_v2_check') THEN
    ALTER TABLE public.dating_introductions ADD CONSTRAINT dating_introductions_v2_check CHECK (
      cardinality(reasons) <= 3 AND array_position(reasons, NULL) IS NULL
      AND (partition_key IS NULL OR partition_key ~ '^[A-Z]{2}(:[A-Z0-9_]{1,16})?$'));
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS dating_intro_high_idx ON public.dating_introductions (user_high_id, created_at DESC);

-- =====================================================================
-- 3. Matches carry their pair (§4.3; fixes §4.10's first latent fault):
--    filled from the introduction or the two members on insert, so no
--    writer can leave it out; a member's deletion keeps it.
-- =====================================================================
ALTER TABLE public.dating_matches ADD COLUMN IF NOT EXISTS pair_key text;
UPDATE public.dating_matches AS m
   SET pair_key = coalesce(
     (SELECT i.pair_key FROM public.dating_introductions AS i WHERE i.id = m.introduction_id),
     CASE WHEN m.user_low_id IS NOT NULL AND m.user_high_id IS NOT NULL
          THEN public.dating_pair_key(m.user_low_id, m.user_high_id) END,
     'gone:' || m.id::text)
 WHERE m.pair_key IS NULL;
CREATE OR REPLACE FUNCTION private.dating_matches_pair_key()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  NEW.pair_key := coalesce(NEW.pair_key,
    (SELECT i.pair_key FROM public.dating_introductions AS i WHERE i.id = NEW.introduction_id),
    CASE WHEN NEW.user_low_id IS NOT NULL AND NEW.user_high_id IS NOT NULL
         THEN public.dating_pair_key(NEW.user_low_id, NEW.user_high_id) END);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS dating_matches_pair_key ON public.dating_matches;
CREATE TRIGGER dating_matches_pair_key BEFORE INSERT ON public.dating_matches
  FOR EACH ROW EXECUTE FUNCTION private.dating_matches_pair_key();
ALTER TABLE public.dating_matches ALTER COLUMN pair_key SET NOT NULL;
CREATE INDEX IF NOT EXISTS dating_matches_pair_key_idx ON public.dating_matches (pair_key);

-- =====================================================================
-- 4. The introductions_v2 config (§5.11): a draft until reviewed (the W5
--    gate activates it with real references; the dev script with DEV-
--    ones). alignment_v1 is retired. daily_new_max can never exceed 3
--    (Q14; mutant 20) and waiting_max 6. The cool-off is never under the
--    72 h of §2.8 (a trust rule) and an introduction lives at least a day
--    (fix round 1, M-6); a value that is not a plain number is refused by
--    the same CHECK (a fixed 23514, never a cast error). In production a
--    config whose review references start DEV- (any case, any padding)
--    can't be made active.
-- =====================================================================
-- Re-created on every run (the table holds a handful of rows), so a
-- database that has an earlier form of the CHECK gets this one.
ALTER TABLE public.dating_algorithm_configs DROP CONSTRAINT IF EXISTS dating_algorithm_configs_caps_check;
ALTER TABLE public.dating_algorithm_configs ADD CONSTRAINT dating_algorithm_configs_caps_check CHECK (
  (NOT (config ? 'daily_new_max') OR coalesce(config ->> 'daily_new_max' ~ '^[1-3]$', false))
  AND (NOT (config ? 'waiting_max') OR coalesce(config ->> 'waiting_max' ~ '^[1-6]$', false))
  AND (NOT (config ? 'cool_off_hours') OR CASE WHEN config ->> 'cool_off_hours' ~ '^[0-9]{1,3}$'
                                               THEN (config ->> 'cool_off_hours')::int >= 72 ELSE false END)
  AND (NOT (config ? 'lifetime_days') OR CASE WHEN config ->> 'lifetime_days' ~ '^[0-9]{1,2}$'
                                              THEN (config ->> 'lifetime_days')::int >= 1 ELSE false END));
UPDATE public.dating_algorithm_configs
   SET state = 'retired', retired_at = coalesce(retired_at, now())
 WHERE version = 'alignment_v1' AND state <> 'retired';
INSERT INTO public.dating_algorithm_configs (version, state, config, config_hash)
SELECT 'introductions_v2', 'draft', c.v, encode(extensions.digest(c.v::text, 'sha256'), 'hex')
  FROM (SELECT '{
    "daily_new_max": 3,
    "waiting_max": 6,
    "open_chat_pause_at": 3,
    "open_chat_active_days": 14,
    "lifetime_days": 7,
    "cool_off_hours": 72,
    "cross_border_min_account_days": 14,
    "photos_after_mutual_min_account_days": 30,
    "context_fresh_days": 14,
    "same_gender_context_fresh_days": 7,
    "rank": {"feasibility_weight": 10, "values_weight": 3, "band_width": 3,
             "exposure_window_days": 7, "jitter": 2.0},
    "intention_matrix": {
      "marriage": ["marriage", "committed"],
      "committed": ["marriage", "committed", "companionship", "not_sure"],
      "companionship": ["committed", "companionship", "not_sure"],
      "not_sure": ["committed", "companionship", "not_sure"]
    },
    "default_ages": {"young_until": 20, "young_plus": 7, "minus": 5, "plus": 5},
    "dragnet": {"min_intros": 15, "window_days": 14, "interested_ratio": 0.9,
                "first_message_ratio": 0.2, "throttled_daily_max": 1},
    "reasons_max": 3,
    "partition_people_max": 5000,
    "scan_limit": 500,
    "max_attempts": 3
  }'::jsonb AS v) AS c
ON CONFLICT (version) DO NOTHING;

CREATE OR REPLACE FUNCTION private.dating_config_review_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.state = 'active' AND private.attune_environment() IS NOT DISTINCT FROM 'production'
     AND EXISTS (SELECT 1 FROM unnest(ARRAY[NEW.product_review_ref, NEW.clinical_review_ref,
                                            NEW.fairness_review_ref, NEW.safety_review_ref]) AS r(ref)
                  -- fix round 1 (M-7): 'dev-x' and ' DEV-x' are DEV- references too
                  WHERE upper(btrim(r.ref, E' \t\r\n')) LIKE 'DEV-%') THEN
    RAISE EXCEPTION 'config:dev_review_ref' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS dating_config_review_guard ON public.dating_algorithm_configs;
CREATE TRIGGER dating_config_review_guard BEFORE INSERT OR UPDATE ON public.dating_algorithm_configs
  FOR EACH ROW EXECUTE FUNCTION private.dating_config_review_guard();

-- The active introductions config, only when its shape is the §5.11 one
-- (else NULL: generation refuses with no_active_config, the filters admit
-- nobody).
CREATE OR REPLACE FUNCTION private.dating_intro_config(OUT o_version text, OUT o_config jsonb)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT c.version, c.config
    FROM public.dating_algorithm_configs AS c
   WHERE c.state = 'active' AND c.version LIKE 'introductions\_v%'
     AND jsonb_typeof(c.config -> 'intention_matrix') = 'object'
     AND jsonb_typeof(c.config -> 'rank') = 'object'
     AND coalesce(c.config ->> 'daily_new_max' ~ '^[1-3]$', false)
     AND coalesce(c.config ->> 'waiting_max' ~ '^[1-6]$', false)
     AND coalesce(c.config ->> 'lifetime_days' ~ '^[0-9]{1,2}$', false)
     AND coalesce(c.config ->> 'cool_off_hours' ~ '^[0-9]{1,3}$', false)
     AND coalesce(c.config ->> 'scan_limit' ~ '^[0-9]{1,4}$', false)
     AND coalesce(c.config ->> 'partition_people_max' ~ '^[0-9]{1,5}$', false)
   ORDER BY c.activated_at DESC NULLS LAST
   LIMIT 1;
$$;

-- =====================================================================
-- 5. The person, the pair and the hard filters (§5.1, §5.2).
-- =====================================================================
-- Carry 1 (W2 final M-5): no introduction is visible before account
-- creation + the cool-off (§2.8, 72 h). NULL for no account: never over.
CREATE OR REPLACE FUNCTION private.dating_cool_off_ends_at(p_user uuid)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT u.created_at + make_interval(hours => coalesce(((private.dating_intro_config()).o_config ->> 'cool_off_hours')::int, 72))
    FROM public.users AS u WHERE u.id = p_user;
$$;

-- §2.3 freshness (Ruling R-3): the last time the person used Dating, the
-- later of the session context check (W8b's device check writes it) and
-- the trusted phone's last use (written at most once a day by every
-- device-checked call, W4b). NULL: never fresh.
CREATE OR REPLACE FUNCTION private.dating_last_seen_at(p_user uuid)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT nullif(greatest(coalesce((SELECT c.checked_at FROM public.dating_session_context AS c WHERE c.user_id = p_user), '-infinity'),
                         coalesce((SELECT max(d.last_seen_at) FROM public.dating_trusted_devices AS d WHERE d.user_id = p_user), '-infinity')),
                '-infinity'::timestamptz);
$$;

-- §2.4: a pair is man-woman when one identity is woman and the other man.
CREATE OR REPLACE FUNCTION private.dating_pair_is_man_woman(p_a text, p_b text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT coalesce((p_a = 'woman' AND p_b = 'man') OR (p_a = 'man' AND p_b = 'woman'), false);
$$;

-- One person as generation sees them (§5.1): decrypted only inside a
-- definer function, held only in a transaction's temp table or a local
-- variable, never stored or returned to anyone.
DO $$
BEGIN
  IF to_regtype('private.dating_gen_person') IS NULL THEN
    CREATE TYPE private.dating_gen_person AS (
      user_id uuid,
      country text,
      region text,
      side text,
      scope text,
      open_abroad text[],
      age integer,
      min_age integer,
      max_age integer,
      identity text,
      pools text[],
      seeking text[],
      intention text,
      timeline text,
      timeline_visible boolean,
      intention_open text[],
      children_have boolean,
      children_want text,
      want_must_match boolean,
      exclude_parents boolean,
      faith text,
      importance text,
      faith_visible boolean,
      family text,
      same_gender_ok boolean,
      abroad_ok boolean,
      hmac text,
      visible_from timestamptz
    );
  END IF;
END $$;

-- The person's row at [p_at] under [p_cfg]; raises dating:field_* on an
-- unreadable answer (callers skip that person).
CREATE OR REPLACE FUNCTION private.dating_person(p_user uuid, p_at timestamptz, p_cfg jsonb)
RETURNS private.dating_gen_person
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v private.dating_gen_person;
  v_p public.dating_profiles;
  v_d public.dating_preferences;
  v_identity jsonb;
  v_seeking jsonb;
  v_faith jsonb;
BEGIN
  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  SELECT * INTO v_d FROM public.dating_preferences AS d WHERE d.user_id = p_user;
  IF v_p.user_id IS NULL OR v_d.user_id IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT private.dating_field_decrypt(s.identity_enc), private.dating_field_decrypt(s.seeking_enc),
         private.dating_field_decrypt(s.faith_enc)
    INTO v_identity, v_seeking, v_faith
    FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user;
  v.user_id := p_user;
  v.country := v_p.country_code::text;
  v.region := v_p.region_code;
  v.side := v_p.side_code;
  v.scope := v_d.region_scope;
  v.open_abroad := v_d.open_abroad::text[];
  v.age := public.account_age(p_user);
  v.min_age := v_d.min_age;
  v.max_age := v_d.max_age;
  v.identity := v_identity ->> 'identity';
  v.pools := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(v_identity -> 'pools') = 'array'
                                                          THEN v_identity -> 'pools' END));
  v.seeking := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(v_seeking -> 'seeking') = 'array'
                                                            THEN v_seeking -> 'seeking' END));
  -- Carry 2 (W1 B7 M-4): no identity or no who-to-meet is never introducible.
  IF v.identity IS NULL OR cardinality(v.pools) = 0 THEN
    v.pools := NULL;
  END IF;
  IF cardinality(v.seeking) = 0 THEN
    v.seeking := NULL;
  END IF;
  v.intention := v_p.intention;
  v.timeline := v_p.marriage_timeline;
  v.timeline_visible := v_p.timeline_visible;
  v.intention_open := coalesce(v_d.intention_open,
    ARRAY(SELECT jsonb_array_elements_text(p_cfg -> 'intention_matrix' -> v_p.intention)));
  v.children_have := v_p.children_have;
  v.children_want := v_p.children_want;
  v.want_must_match := v_d.want_must_match;
  v.exclude_parents := v_d.exclude_parents;
  v.faith := v_faith ->> 'faith';
  v.importance := v_faith ->> 'importance';
  v.faith_visible := v_p.faith_visible;
  v.family := v_p.family_involvement;
  -- §5.2 filter 4: the global flag, the person's Dating country, and a
  -- fresh context that allows it where they are (fail closed: no context,
  -- no same-gender introduction; W8b writes the context).
  v.same_gender_ok := coalesce(private.dating_same_gender_on(v.country), false)
    AND EXISTS (SELECT 1 FROM public.dating_session_context AS c
                 WHERE c.user_id = p_user AND c.same_gender_allowed_here
                   AND c.checked_at >= p_at - make_interval(days => coalesce((p_cfg ->> 'same_gender_context_fresh_days')::int, 7)));
  -- §2.6: an account at least 14 days old may be introduced across borders.
  v.abroad_ok := coalesce((SELECT u.created_at FROM public.users AS u WHERE u.id = p_user)
                          <= p_at - make_interval(days => coalesce((p_cfg ->> 'cross_border_min_account_days')::int, 14)), false);
  v.hmac := public.dating_phone_hmac_for_user(p_user);
  v.visible_from := private.dating_first_drop_at(p_user, p_at);
  RETURN v;
END;
$$;

-- §5.2 filter 1 at [p_at]: a current candidate (eligibility, both checks,
-- an active enrolment, a ready profile, seen in Dating within 14 days:
-- dating_candidate_is_current), not hidden by travel, and the cool-off
-- over by the next drop.
CREATE OR REPLACE FUNCTION private.dating_person_current(p_user uuid, p_at timestamptz, p_cfg jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(public.dating_candidate_is_current(p_user), false)
    AND NOT EXISTS (SELECT 1 FROM public.dating_session_context AS c
                     WHERE c.user_id = p_user AND c.dating_allowed_here IS FALSE)
    AND coalesce(private.dating_cool_off_ends_at(p_user) <= private.dating_first_drop_at(p_user, p_at), false);
$$;

-- §5.2 filters 2-10, in both directions, over two person rows. Pure: one
-- implementation for the single-pair predicate and for generation's set.
-- Any NULL answer admits nobody (carry 2).
CREATE OR REPLACE FUNCTION private.dating_admits(a private.dating_gen_person, b private.dating_gen_person, p_cfg jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT coalesce(
    a.user_id <> b.user_id
    -- 2. each age within the other's range
    AND b.age BETWEEN a.min_age AND a.max_age
    AND a.age BETWEEN b.min_age AND b.max_age
    -- 3. each seeking set meets the other's pools
    AND a.seeking && b.pools
    AND b.seeking && a.pools
    -- 4. not man-woman: both allowed (flag, country, fresh context)
    AND (private.dating_pair_is_man_woman(a.identity, b.identity) OR (a.same_gender_ok AND b.same_gender_ok))
    -- 5, 6. the same country and inside each one's scope; or across
    -- borders, each open to the other's country, both accounts 14+ days
    AND CASE WHEN a.country = b.country THEN
          (a.scope = 'country' OR b.region = a.region)
          AND (a.scope IS DISTINCT FROM 'side' OR a.side IS NULL OR b.side = a.side)
          AND (b.scope = 'country' OR a.region = b.region)
          AND (b.scope IS DISTINCT FROM 'side' OR b.side IS NULL OR a.side = b.side)
        ELSE b.country = ANY (a.open_abroad) AND a.country = ANY (b.open_abroad) AND a.abroad_ok AND b.abroad_ok
        END
    -- 7. the intention matrix and each one's intentions open to
    AND (p_cfg -> 'intention_matrix' -> a.intention) ? b.intention
    AND b.intention = ANY (a.intention_open)
    AND (p_cfg -> 'intention_matrix' -> b.intention) ? a.intention
    AND a.intention = ANY (b.intention_open)
    -- 8. must match on wanting children: never yes against no
    AND NOT (a.want_must_match AND ((a.children_want = 'yes' AND b.children_want = 'no') OR (a.children_want = 'no' AND b.children_want = 'yes')))
    AND NOT (b.want_must_match AND ((b.children_want = 'yes' AND a.children_want = 'no') OR (b.children_want = 'no' AND a.children_want = 'yes')))
    -- 9. no parents for someone who excludes them
    AND NOT (a.exclude_parents AND b.children_have)
    AND NOT (b.exclude_parents AND a.children_have)
    -- 10. "must share" faith: the other stated the same tradition
    AND (a.importance IS DISTINCT FROM 'must_share' OR (b.faith IS NOT NULL AND b.faith <> 'prefer_not_to_say' AND b.faith = a.faith))
    AND (b.importance IS DISTINCT FROM 'must_share' OR (a.faith IS NOT NULL AND a.faith <> 'prefer_not_to_say' AND a.faith = b.faith)),
    false);
$$;

-- §5.2 filters 11-13, both directions: no block (by id or by phone HMAC),
-- not former partners, and neither number on the other's never-introduce
-- list (kept rows included: they stay enforced forever, carry 4). A
-- missing HMAC is never safe.
CREATE OR REPLACE FUNCTION private.dating_pair_safe(p_a uuid, p_b uuid, p_ha text, p_hb text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p_ha IS NOT NULL AND p_hb IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.dating_blocks AS b
                     WHERE (b.blocker_user_id = p_a AND b.blocked_user_id = p_b)
                        OR (b.blocker_user_id = p_b AND b.blocked_user_id = p_a))
    AND NOT EXISTS (SELECT 1 FROM public.dating_block_hmacs AS h
                     WHERE (h.blocker_hmac = p_ha AND h.blocked_hmac = p_hb)
                        OR (h.blocker_hmac = p_hb AND h.blocked_hmac = p_ha))
    AND public.dating_former_partner_excluded(p_a, p_b) IS FALSE
    AND public.dating_never_introduce_excludes(p_a, p_b) IS FALSE;
$$;

-- §5.2 filter 14: never introduced before (an earlier match always had an
-- introduction; a match's own pair_key covers one whose introduction went).
CREATE OR REPLACE FUNCTION private.dating_pair_new(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT NOT EXISTS (SELECT 1 FROM public.dating_introductions AS i WHERE i.pair_key = public.dating_pair_key(p_a, p_b))
     AND NOT EXISTS (SELECT 1 FROM public.dating_matches AS m WHERE m.pair_key = public.dating_pair_key(p_a, p_b));
$$;

-- §5.2, rewritten (§4.10; fixes the pair_key fault): true only if every
-- filter holds for (a, b) and for (b, a), now, under the active config.
DROP FUNCTION IF EXISTS public.dating_pair_passes_hard_filters(uuid, uuid);
CREATE FUNCTION public.dating_pair_passes_hard_filters(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_cfg constant jsonb := (private.dating_intro_config()).o_config;
  v_at constant timestamptz := now();
  v_a private.dating_gen_person;
  v_b private.dating_gen_person;
BEGIN
  IF p_a IS NULL OR p_b IS NULL OR p_a = p_b OR v_cfg IS NULL THEN
    RETURN false;
  END IF;
  -- 1, 15 (W5c adds the moderation removal to the person check).
  IF private.dating_person_current(p_a, v_at, v_cfg) IS NOT TRUE
     OR private.dating_person_current(p_b, v_at, v_cfg) IS NOT TRUE THEN
    RETURN false;
  END IF;
  v_a := private.dating_person(p_a, v_at, v_cfg);
  v_b := private.dating_person(p_b, v_at, v_cfg);
  RETURN coalesce(private.dating_admits(v_a, v_b, v_cfg)
                  AND private.dating_pair_safe(p_a, p_b, v_a.hmac, v_b.hmac)
                  AND private.dating_pair_new(p_a, p_b), false);
EXCEPTION WHEN raise_exception THEN
  -- An unreadable answer or a missing field key admits nobody.
  IF SQLERRM IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
    RETURN false;
  END IF;
  RAISE;
END;
$$;

-- =====================================================================
-- 6. Functions re-created from their LIVE bodies (Spec 2 W5a lines only).
-- =====================================================================
DROP FUNCTION IF EXISTS public.get_my_dating_introductions(integer);
CREATE OR REPLACE FUNCTION public.act_on_dating_introduction(p_idempotency_key text, p_introduction_id uuid, p_action text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_intro public.dating_introductions%ROWTYPE;
  v_match_id uuid;
  v_active_algorithm text;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF p_action NOT IN ('interested','passed') THEN RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023'; END IF;
  PERFORM public.check_dating_rate_limit('interest_action',30,interval '1 day');
  IF NOT public.dating_flag_enabled('dating_mode_enabled') THEN
    RAISE EXCEPTION 'dating_unavailable' USING ERRCODE='22023';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN -- Spec 2 W5a (carry 8): the caller's own phone, before anything
    RAISE EXCEPTION 'reverify_device' USING ERRCODE = '42501'; -- Spec 2 W5a
  END IF; -- Spec 2 W5a

  SELECT * INTO v_intro FROM public.dating_introductions
  WHERE id=p_introduction_id AND v_user_id IN (user_low_id,user_high_id)
  FOR UPDATE;
  IF NOT FOUND OR v_intro.expires_at<=now()
     OR v_intro.state NOT IN ('generated','presented','interested')
     OR now() < (CASE WHEN v_intro.user_low_id = v_user_id THEN v_intro.visible_from_low ELSE v_intro.visible_from_high END) THEN -- Spec 2 W5a: not before this side's drop
    RAISE EXCEPTION 'introduction_unavailable' USING ERRCODE='22023';
  END IF;
  IF NOT public.dating_candidate_is_current(v_intro.user_low_id)
     OR NOT public.dating_candidate_is_current(v_intro.user_high_id)
     OR EXISTS(SELECT 1 FROM public.dating_blocks b WHERE b.pair_key=v_intro.pair_key)
     -- DATING-C4: former-partner exclusion (survives re-registration by phone-HMAC).
     OR public.dating_former_partner_excluded(v_intro.user_low_id, v_intro.user_high_id)
     OR private.dating_pair_safe(v_intro.user_low_id, v_intro.user_high_id, -- Spec 2 W5a (carry 4): blocks by HMAC, never-introduce (kept rows too)
          public.dating_phone_hmac_for_user(v_intro.user_low_id), public.dating_phone_hmac_for_user(v_intro.user_high_id)) IS NOT TRUE THEN -- Spec 2 W5a
    UPDATE public.dating_introductions SET state='invalidated' WHERE id=v_intro.id;
    RAISE EXCEPTION 'introduction_unavailable' USING ERRCODE='22023';
  END IF;
  IF NOT public.claim_dating_idempotency('act_on_dating_introduction',p_idempotency_key) THEN RETURN; END IF;

  INSERT INTO public.dating_interest_actions(introduction_id,actor_user_id,action,idempotency_key,acted_at)
  VALUES(v_intro.id,v_user_id,p_action,p_idempotency_key,now())
  ON CONFLICT(introduction_id,actor_user_id) DO NOTHING;

  IF v_intro.user_low_id=v_user_id THEN
    UPDATE public.dating_introductions SET low_action=p_action,state=CASE
      WHEN p_action='passed' THEN 'passed'
      WHEN high_action='interested' THEN 'matched'
      ELSE 'interested' END WHERE id=v_intro.id;
  ELSE
    UPDATE public.dating_introductions SET high_action=p_action,state=CASE
      WHEN p_action='passed' THEN 'passed'
      WHEN low_action='interested' THEN 'matched'
      ELSE 'interested' END WHERE id=v_intro.id;
  END IF;

  SELECT * INTO v_intro FROM public.dating_introductions WHERE id=v_intro.id;
  IF v_intro.low_action='interested' AND v_intro.high_action='interested' THEN
    INSERT INTO public.dating_matches(introduction_id,user_low_id,user_high_id,state,matched_at,created_at)
    VALUES(v_intro.id,v_intro.user_low_id,v_intro.user_high_id,'active',now(),now())
    ON CONFLICT(introduction_id) DO NOTHING RETURNING id INTO v_match_id;
    -- Spec 2 W5a (§3.13, §4.10): no push; the match moment shows in Dating (W5b)
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_dating_introductions(p_limit integer DEFAULT 20)
 RETURNS TABLE(id uuid, display_name text, state text, expires_at timestamp with time zone, created_at timestamp with time zone, has_acted boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT di.id,dp.display_name, -- Spec 2 W5a: no region code, intention text, summary, band or features
    CASE
      WHEN (CASE WHEN di.user_low_id=auth.uid() THEN di.low_action ELSE di.high_action END) = 'interested'
        THEN 'awaiting_response'
      ELSE 'open'
    END AS state,
    di.expires_at,di.created_at,
    EXISTS(SELECT 1 FROM public.dating_interest_actions a WHERE a.introduction_id=di.id AND a.actor_user_id=auth.uid())
  FROM public.dating_introductions di
  JOIN public.dating_profiles dp ON dp.user_id=CASE WHEN di.user_low_id=auth.uid() THEN di.user_high_id ELSE di.user_low_id END
  WHERE public.dating_flag_enabled('dating_mode_enabled')
    AND public.dating_require_trusted_device() -- Spec 2 W5a (carry 8)
    AND now() >= CASE WHEN di.user_low_id=auth.uid() THEN di.visible_from_low ELSE di.visible_from_high END -- Spec 2 W5a
    AND auth.uid() IN (di.user_low_id,di.user_high_id)
    AND di.state IN ('generated','presented','interested')
    AND di.expires_at>now()
    AND dp.profile_state='active' AND dp.moderation_state='approved'
    AND public.dating_candidate_is_current(di.user_low_id)
    AND public.dating_candidate_is_current(di.user_high_id)
    AND NOT EXISTS(SELECT 1 FROM public.dating_blocks b WHERE b.pair_key=di.pair_key)
    -- DATING-C4: never surface an introduction between recorded former partners.
    AND NOT public.dating_former_partner_excluded(di.user_low_id, di.user_high_id)
    AND private.dating_pair_safe(di.user_low_id, di.user_high_id, public.dating_phone_hmac_for_user(di.user_low_id), -- Spec 2 W5a (carry 4)
                                 public.dating_phone_hmac_for_user(di.user_high_id)) -- Spec 2 W5a
  ORDER BY di.created_at DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,20),1),20);
$function$;

CREATE OR REPLACE FUNCTION private.dating_exit_internal(p_user uuid, p_keep_never_introduce boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_found boolean;
  v_exited_at timestamptz;
BEGIN
  IF p_user IS NULL THEN
    RETURN;
  END IF;
  -- The row order: the enrolment before the profile (as activation, the
  -- pauses and the parked trigger).
  SELECT e.exited_at INTO v_exited_at FROM public.dating_enrollments AS e WHERE e.user_id = p_user FOR UPDATE;
  v_found := FOUND;
  -- Uploads never attached go with their storage objects; photo rows queue
  -- their own objects (dating_photos_queue_media_before_delete). Both go
  -- through queue_media_deletion, so the CSAM evidence guard holds back an
  -- object under an open, unquarantined match.
  PERFORM public.queue_media_deletion('dating-profile-photos', i.storage_key)
     FROM public.dating_photo_upload_intents AS i WHERE i.user_id = p_user -- Spec 2 W3c (Task 9 fix round 1, I-1): an intent names its photo's object
      AND NOT EXISTS (SELECT 1 FROM public.dating_profile_photos AS f -- Spec 2 W3c (Task 9 fix round 1, I-1)
                       WHERE f.storage_key = i.storage_key AND f.csam_state = 'hit'); -- Spec 2 W3c (Task 9 fix round 1, I-1): not a hit's
  DELETE FROM public.dating_photo_upload_intents AS i WHERE i.user_id = p_user;
  DELETE FROM public.dating_profile_photos AS f WHERE f.user_id = p_user;
  DELETE FROM public.dating_prompts AS q WHERE q.user_id = p_user;
  DELETE FROM public.dating_settings AS t WHERE t.user_id = p_user;
  DELETE FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user;
  DELETE FROM public.dating_preferences AS d WHERE d.user_id = p_user;
  DELETE FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  DELETE FROM public.dating_date_reflections AS r WHERE r.author_user_id = p_user;
  DELETE FROM public.dating_session_context AS c WHERE c.user_id = p_user;
  DELETE FROM public.dating_notify_requests AS n WHERE n.user_id = p_user;
  IF to_regclass('public.dating_gentle_wait_reflections') IS NOT NULL THEN -- W2's table
    EXECUTE 'DELETE FROM public.dating_gentle_wait_reflections WHERE user_id = $1' USING p_user;
  END IF;
  IF NOT coalesce(p_keep_never_introduce, false) THEN
    DELETE FROM public.dating_never_introduce AS n WHERE n.owner_user_id = p_user;
  ELSE -- Spec 2 W4b (fix rounds 1-2, C-1): kept, never shown again, its label gone
    UPDATE public.dating_never_introduce AS n SET kept_at = coalesce(n.kept_at, now()), shown_at = NULL, label = NULL -- Spec 2 W4b
     WHERE n.owner_user_id = p_user; -- Spec 2 W4b
  END IF;
  -- Spec 2 W4a: the verification sessions go, a human review's photos with
  -- Spec 2 W4a them (queued, as every Dating object), and the identity
  -- Spec 2 W4a result, which covered the photos deleted above. -- Spec 2 W4 final
  -- Spec 2 W4 final (I-1a ruling): an age pass goes too (it belongs to the
  -- Spec 2 W4 final face that earned it; a new setup checks the age again);
  -- Spec 2 W4 final a fail (and Spec 1's hold) stays while the account exists.
  PERFORM public.queue_media_deletion('dating-verification-review', o.name) -- Spec 2 W4a
     FROM storage.objects AS o -- Spec 2 W4a
    WHERE o.bucket_id = 'dating-verification-review' -- Spec 2 W4a
      AND split_part(o.name, '/', 1) IN (SELECT vs.id::text FROM public.dating_verification_sessions AS vs -- Spec 2 W4a
                                          WHERE vs.user_id = p_user); -- Spec 2 W4a
  DELETE FROM public.dating_verification_sessions AS vs WHERE vs.user_id = p_user; -- Spec 2 W4a
  DELETE FROM public.dating_trusted_devices AS td WHERE td.user_id = p_user; -- Spec 2 W4b (§3.3.4): leaving unbinds every phone
  UPDATE public.dating_age_verifications AS av -- Spec 2 W4a
     SET identity_method = NULL, identity_result = NULL, identity_vendor = NULL, -- Spec 2 W4a
         identity_decided_at = NULL, decided_by = NULL, updated_at = now() -- Spec 2 W4a
   WHERE av.user_id = p_user AND av.identity_result IS NOT NULL; -- Spec 2 W4a
  UPDATE public.dating_age_verifications AS av -- Spec 2 W4 final (I-1a)
     SET age_method = NULL, age_result = NULL, challenge_age = NULL, age_vendor = NULL, age_decided_at = NULL, -- Spec 2 W4 final (I-1a)
         updated_at = now() -- Spec 2 W4 final (I-1a)
   WHERE av.user_id = p_user AND av.age_result = 'pass' AND av.revoked_at IS NULL; -- Spec 2 W4 final (I-1a): a fail stays
  -- Conversations close for both and stay sealed for the evidence window.
  UPDATE public.dating_matches AS m
     SET state = 'closed', closed_reason = 'exit', closed_at = coalesce(m.closed_at, now()),
         evidence_until = now() + interval '30 days'
   WHERE p_user IN (m.user_low_id, m.user_high_id) AND m.state = 'active';
  -- Introductions go (their interest actions cascade; a match keeps its row).
  DELETE FROM public.dating_introductions AS i WHERE p_user IN (i.user_low_id, i.user_high_id);
  -- Spec 2 W5a: the trait snapshots are gone (§4.10)
  -- "When you left" (§3.8; fix round 1, I-1): every consent whose latest
  -- event is a grant is withdrawn now, on the server's clock, so coming back
  -- needs D4 again. Kept with the consents (Q17 exception 3). A second exit
  -- finds nothing standing and writes nothing (M-2).
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT p_user, 'exit:' || l.purpose || ':' || replace(gen_random_uuid()::text, '-', ''), l.purpose, 'withdrawn',
         l.policy_version, clock_timestamp()
    FROM (SELECT DISTINCT ON (c.purpose) c.purpose, c.action, c.policy_version
            FROM public.dating_consent_events AS c
           WHERE c.user_id = p_user
           ORDER BY c.purpose, c.occurred_at DESC, c.created_at DESC, (c.action = 'withdrawn') DESC) AS l
   WHERE l.action = 'granted';
  -- A suspension stays (only the data goes); a second exit keeps the first
  -- "when you left" (M-2).
  UPDATE public.dating_enrollments AS e
     SET state = CASE WHEN e.state = 'suspended' THEN 'suspended' ELSE 'exited' END,
         exited_at = coalesce(e.exited_at, now()), paused_at = NULL, pause_reason = NULL, updated_at = now()
   WHERE e.user_id = p_user;
  IF v_found AND v_exited_at IS NULL THEN
    PERFORM private.bump_metric_internal('dating.exit');
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE -- W1 final fix (I-1)
  v_try integer; -- W1 final fix (I-1)
BEGIN
  FOR v_try IN 1..3 LOOP -- W1 final fix (I-1)
  BEGIN -- W1 final fix (I-1)
  -- Spec 2 W5a: the trait snapshots are gone (§4.10)

  UPDATE public.dating_introductions
  SET state = 'invalidated'
  WHERE (user_low_id = p_user_id OR user_high_id = p_user_id)
    AND state IN ('generated', 'presented', 'interested');

  -- Close existing active matches ONLY for reasons that are genuinely an exit
  -- from Dating: leaving (exit), terms/opt-in withdrawal (dating_consent_withdrawn
  -- — this ALSO sets profile_state='exited', so it must close matches too, per
  -- re-review DATING-H5a; note Spec §3.3/:113 "matches remain on withdrawal"
  -- governs HISTORICAL-DATA consent only, not terms/opt-in), suspension
  -- (account_restricted), and profile deletion. Pause, HISTORICAL-consent
  -- withdrawal, profile edits, and scheduled revalidation deliberately PRESERVE
  -- matches (Spec §14 :612 pause; :113 historical-consent).
  IF p_reason IN (
    'exit', 'dating_consent_withdrawn', 'account_restricted', 'profile_deleted', -- Spec 2 W4a
    'age_review', 'age_verification_invalid' -- Spec 2 W4a (§6.3, §4.10): every match closes
  ) THEN
    UPDATE public.dating_matches
    SET state = 'closed',
        closed_at = COALESCE(closed_at, now()), -- Spec 2 W4a
        closed_reason = CASE WHEN p_reason IN ('age_review', 'age_verification_invalid') THEN p_reason ELSE closed_reason END, -- Spec 2 W4a
        evidence_until = CASE WHEN p_reason IN ('age_review', 'age_verification_invalid') -- Spec 2 W4a
                              THEN now() + interval '30 days' ELSE evidence_until END -- Spec 2 W4a (§4.8)
    WHERE (user_low_id = p_user_id OR user_high_id = p_user_id)
      AND state = 'active';
  END IF;
  EXIT; -- W1 final fix (I-1)
  EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- W1 final fix (I-1)
    IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- W1 final fix (N-M3): an inner retry already ran: no nesting -- W1 final fix (I-1)
  END; -- W1 final fix (I-1)
  END LOOP; -- W1 final fix (I-1)
END;
$function$;

CREATE OR REPLACE FUNCTION public.expire_dating_introductions()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_count bigint;
  v_life constant interval := make_interval(days => coalesce(((private.dating_intro_config()).o_config ->> 'lifetime_days')::int, 7)); -- Spec 2 W5a
BEGIN
  UPDATE public.dating_introductions SET state='expired'
  WHERE state IN ('generated','presented','interested') -- Spec 2 W5a
    AND (expires_at<=now() -- Spec 2 W5a (§5.3): the later side's seven days
         OR (low_action IS NULL AND visible_from_low + v_life <= now()) -- Spec 2 W5a: or a side's own, unanswered
         OR (high_action IS NULL AND visible_from_high + v_life <= now())); -- Spec 2 W5a
  GET DIAGNOSTICS v_count=ROW_COUNT;
  -- Spec 2 W5a (Task 2 fix round 2, N-1): a person who left while a generation run was
  -- Spec 2 W5a open (it never waits on a leave) loses that run's introductions here, as
  -- Spec 2 W5a leaving's own go (§3.8): every introduction of someone exited or not enrolled.
  DELETE FROM public.dating_introductions AS i -- Spec 2 W5a
   WHERE NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = i.user_low_id AND e.state <> 'exited') -- Spec 2 W5a
      OR NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = i.user_high_id AND e.state <> 'exited'); -- Spec 2 W5a
  RETURN v_count;
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
                        'dating.generation.busy']) AS k(key)), -- Spec 2 W5a (Task 2 fix round 2, N-3)
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

CREATE OR REPLACE FUNCTION public.dating_candidate_is_current(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce(public.dating_eligibility(p_user_id) = 'eligible', false) -- Spec 2 W2: gates 1-6 (flag, standing, relationship, gentle wait, country) replace the flag, Healing, standing and relationship lines
    AND coalesce(public.dating_age_gate_holds(p_user_id), false) -- Spec 2 W2: NULL-safe
    AND EXISTS (
      SELECT 1 FROM public.dating_enrollments de
      WHERE de.user_id = p_user_id AND de.state = 'active'
    )
    AND coalesce(public.dating_profile_ready(p_user_id), false) -- Spec 2 W2: NULL-safe; -- Spec 2 W5a: and
    AND coalesce(private.dating_last_seen_at(p_user_id) >= now() - make_interval(days => -- Spec 2 W5a (§2.3): fresh, else out of others' days
          coalesce(((private.dating_intro_config()).o_config ->> 'context_fresh_days')::int, 14)), false); -- Spec 2 W5a
$function$;

CREATE OR REPLACE FUNCTION private.dating_first_drop_at(p_user uuid, p_after timestamp with time zone)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_tz text;
  v_drop time;
  v_at timestamptz;
  v_drop_tz text; -- Spec 2 W5a
BEGIN
  SELECT coalesce((public.dating_country_config(p.country_code::text)).reference_tz, 'UTC')
    INTO v_tz FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  SELECT u.timezone INTO v_drop_tz FROM public.users AS u WHERE u.id = p_user; -- Spec 2 W5a (§5.3): users.timezone first
  v_tz := coalesce(CASE WHEN public.presence_tz_ok(v_drop_tz) -- Spec 2 W5a fix round 1 (M-1): the column's own validator, no zone-list scan
                        THEN v_drop_tz END, v_tz, 'UTC'); -- Spec 2 W5a: an unknown zone is never used
  SELECT t.drop_time INTO v_drop FROM public.dating_settings AS t WHERE t.user_id = p_user;
  v_drop := coalesce(v_drop, time '19:00');
  v_at := ((p_after AT TIME ZONE v_tz)::date + v_drop) AT TIME ZONE v_tz;
  IF v_at < p_after THEN
    v_at := (((p_after AT TIME ZONE v_tz)::date + 1) + v_drop) AT TIME ZONE v_tz;
  END IF;
  RETURN v_at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_dating_verification()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_state jsonb;
  v_profile public.dating_profiles;
  v_session public.dating_verification_sessions;
  v_open boolean;
  v_country text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    SELECT * INTO v_session FROM public.dating_verification_sessions AS s
     WHERE s.user_id = v_user AND s.kind = 'reverify'
       AND s.device_hash IS NOT DISTINCT FROM private.dating_request_device_hash()
       AND coalesce(s.awaiting_since, s.created_at) > now() - interval '72 hours' -- Spec 2 W5a (carry 10): as the sweep
     ORDER BY s.created_at DESC LIMIT 1;
    RETURN jsonb_build_object('ok', true, 'device', 'untrusted',
      'available', private.dating_verification_available(),
      'session', CASE WHEN v_session.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', v_session.id, 'kind', v_session.kind, 'step', v_session.step, 'state', v_session.state,
        'attempts', v_session.attempts, 'outcome', v_session.outcome,
        'open', v_session.state IN ('started', 'awaiting_review') AND (v_session.state = 'awaiting_review' OR v_session.expires_at > now()),
        'gestures', to_jsonb(v_session.gestures)) END);
  END IF;
  v_state := private.dating_verification_state(v_user);
  SELECT * INTO v_profile FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  SELECT * INTO v_session FROM public.dating_verification_sessions AS s
   WHERE s.user_id = v_user AND s.kind = 'activation' AND s.created_at > now() - interval '7 days'
   ORDER BY (s.state IN ('started', 'awaiting_review')) DESC, s.created_at DESC LIMIT 1;
  v_open := v_session.id IS NOT NULL AND (v_session.state = 'awaiting_review'
            OR (v_session.state = 'started' AND v_session.expires_at > now()));
  v_country := v_profile.country_code::text;
  RETURN jsonb_build_object(
    'ok', true,
    'device', 'trusted',
    'available', private.dating_verification_available(),
    'age', CASE WHEN v_state ->> 'age' IS NOT NULL THEN v_state ->> 'age'
                WHEN v_open AND v_session.step = 'id' AND v_session.state = 'awaiting_review' THEN 'review' END,
    'identity', CASE WHEN v_state ->> 'identity' = 'pass' AND v_profile.verification_state = 'verified' THEN 'pass'
                     WHEN v_open AND v_session.step = 'human' AND v_session.state = 'awaiting_review' THEN 'review'
                     WHEN v_state ->> 'identity' = 'fail' THEN 'fail' END,
    'session', CASE WHEN v_session.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_session.id, 'kind', v_session.kind, 'step', v_session.step, 'state', v_session.state,
      'attempts', v_session.attempts, 'outcome', v_session.outcome, 'position', v_session.outcome_position,
      'open', v_open, 'gestures', to_jsonb(v_session.gestures)) END,
    'id_documents', coalesce((SELECT jsonb_agg(jsonb_build_object('code', d ->> 'code', 'name_key', d ->> 'name_key'))
                                FROM jsonb_array_elements(coalesce((public.dating_country_config(v_country)).id_documents, '[]'::jsonb)) AS d), '[]'::jsonb),
    'photos_ready', (SELECT count(*) FROM public.dating_profile_photos AS f
                      WHERE f.user_id = v_user AND f.moderation_state = 'approved') >= 2);
END;
$function$;


-- =====================================================================
-- 7. Generation v2 (§5.3-§5.8): the hourly tick.
-- =====================================================================
-- §5.3 open_chats: active matches where neither said "We met" and either a
-- message in the last 14 days or under 7 days old. W5 has no messages and
-- no "We met" yet (W6a and W6c re-create this): an active match under 7 days.
CREATE OR REPLACE FUNCTION private.dating_open_chats(p_user uuid, p_at timestamptz)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT count(*)::integer FROM public.dating_matches AS m
   WHERE m.state = 'active' AND p_user IN (m.user_low_id, m.user_high_id)
     AND m.matched_at > p_at - interval '7 days';
$$;

-- §5.3 capacity: 0 at 3 open chats; else min(3 - today, 6 - waiting),
-- floored at 0. today counts the last 20 hours (one run per country a
-- day; a second partition never counts twice); waiting counts cards the
-- person can still answer. (W5c adds the dragnet throttle here.)
CREATE OR REPLACE FUNCTION private.dating_capacity(p_user uuid, p_at timestamptz, p_cfg jsonb)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN private.dating_open_chats(p_user, p_at) >= coalesce((p_cfg ->> 'open_chat_pause_at')::int, 3) THEN 0
    ELSE greatest(0, least(
      (p_cfg ->> 'daily_new_max')::int
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
$$;

-- §5.8: up to three reason ids, from what both stated and may show, in
-- the spec's order; faith only when both show it; family is shared ground.
-- No reason: same_region, or across_borders; never a field's value.
CREATE OR REPLACE FUNCTION private.dating_reasons(a private.dating_gen_person, b private.dating_gen_person)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  WITH r(n, id) AS (VALUES
    (1, CASE WHEN a.intention = 'marriage' AND b.intention = 'marriage' AND a.timeline = b.timeline
              AND a.timeline_visible AND b.timeline_visible THEN 'same_intention_timeline' END),
    -- Fix round 1 (M-4): a NULL timeline is not the same timeline.
    (2, CASE WHEN a.intention = b.intention
              AND NOT coalesce(a.intention = 'marriage' AND a.timeline = b.timeline AND a.timeline_visible AND b.timeline_visible, false)
              THEN 'same_intention' END),
    (3, CASE WHEN a.intention <> b.intention AND a.intention IN ('marriage', 'committed')
              AND b.intention IN ('marriage', 'committed') THEN 'compatible_intention' END),
    (4, CASE WHEN a.children_want = 'yes' AND b.children_want = 'yes' THEN 'children_want_yes'
             WHEN a.children_want = 'no' AND b.children_want = 'no' THEN 'children_want_no' END),
    (5, CASE WHEN a.children_have AND b.children_have THEN 'children_have_both' END),
    (6, CASE WHEN a.faith_visible AND b.faith_visible AND a.faith = b.faith
              AND a.faith NOT IN ('none', 'other', 'prefer_not_to_say') THEN 'same_faith' END),
    (7, CASE WHEN a.faith_visible AND b.faith_visible AND a.importance = 'must_share'
              AND b.importance = 'must_share' THEN 'faith_matters' END),
    (8, CASE WHEN a.family = b.family THEN 'family_same_' || a.family END),
    (9, CASE WHEN a.country = b.country AND a.region = b.region AND a.side IS NOT NULL AND a.side = b.side THEN 'same_side'
             WHEN a.country = b.country AND a.region = b.region THEN 'same_region' END)),
  picked AS (SELECT coalesce(array_agg(r.id ORDER BY r.n) FILTER (WHERE r.id IS NOT NULL), '{}') AS ids FROM r)
  SELECT CASE WHEN cardinality(p.ids) > 0 THEN p.ids[1:3]
              WHEN a.country IS DISTINCT FROM b.country THEN ARRAY['across_borders']
              ELSE '{}'::text[] END
    FROM picked AS p;
$$;

-- A refusal before any work (§5.5): counted for health, never raised.
CREATE OR REPLACE FUNCTION private.dating_generation_skip(p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM private.bump_metric_internal('dating.generation.skipped');
  RETURN jsonb_build_object('skipped', p_reason);
END;
$$;

-- One partition's run (§5.4, §5.5, §5.7): claimed once per (version,
-- cohort, partition); people decrypted into a temp table dropped at commit
-- (§4.2: plaintext never reaches WAL); ordered by recent exposure, then a
-- seeded hash; each takes candidates in the best band, ordered by exposure
-- plus bounded jitter. A failure rolls the partition back (nothing half
-- published) and dead-letters it after max_attempts.
CREATE OR REPLACE FUNCTION private.dating_generate_partition(
  p_country text, p_region text, p_key text, p_window date, p_now timestamptz, p_version text, p_cfg jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
$$;

-- The hourly tick (§4.6, §5.5): every country whose generation hour is
-- now's UTC hour, its cohort the country's local date; a country larger
-- than partition_people_max splits by region (GH:AA). Refuses before any
-- work when Dating or generation is off, no reviewed config is active, or
-- a key is missing or replaced. Fix round 1 (I-1): at every later hour
-- until the country's next generation hour, the same cohort's failed
-- partitions run again (until done, or dead-lettered after max_attempts);
-- each partition is its own subtransaction, so one that fails or times
-- out never undoes another; after a timeout or a cancel nothing more starts.
-- Fix round 2 (N-2): every due partition runs within its cohort day. A key
-- a stopped tick never reached, or whose claim failed, is left pending; a
-- later hour of the cohort day runs pending and failed partitions, and
-- every due one when the cohort has no run at all (a missed tick). Before
-- the generation hour nothing runs.
CREATE OR REPLACE FUNCTION public.run_dating_generation_tick(p_now timestamptz DEFAULT now(), p_country text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
$$;

-- =====================================================================
-- 8. The cron (§4.6): hourly at :17, replacing the weekly v1 job.
-- =====================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-candidate-generation') THEN
    PERFORM cron.unschedule('dating-candidate-generation');
  END IF;
  PERFORM cron.schedule('dating-candidate-generation', '17 * * * *', 'SELECT public.run_dating_generation_tick()');
END $$;
REVOKE ALL ON FUNCTION private.dating_open_chats(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_capacity(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_reasons(private.dating_gen_person, private.dating_gen_person) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_generation_skip(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_generate_partition(text, text, text, date, timestamptz, text, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.run_dating_generation_tick(timestamptz, text) FROM PUBLIC, anon, authenticated, service_role;

-- =====================================================================
-- 9. Grants (re-asserted by the twin). Every helper is the database's
--    own, the service role included; the v1 introductions read stays the
--    app's until W5b replaces it; the hard-filter predicate is no API
--    role's (as before).
-- =====================================================================
REVOKE ALL ON FUNCTION private.dating_matches_pair_key() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_config_review_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_intro_config() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_cool_off_ends_at(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_last_seen_at(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_is_man_woman(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_person(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_person_current(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_admits(private.dating_gen_person, private.dating_gen_person, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_safe(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_new(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_pair_passes_hard_filters(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_introductions(integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_introductions(integer) TO authenticated;
COMMIT;
