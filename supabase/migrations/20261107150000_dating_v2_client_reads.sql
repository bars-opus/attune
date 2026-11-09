-- Spec 2 W3a, migration 1 (§4.9 W3a; §2.7, §3.1, §3.13, §4.1, §4.4, §4.10;
-- I-4, I-9, R11, R21; plan R-2 to R-7): the neutral me_update push and
-- "Tell me when it's here" (queued by publish_country_config when it opens
-- a country or a region); the four "owner read" policies dropped (their
-- 20260811120000 grants are revoked in the twin; the photo and intent
-- tables wait for W3c, R-2); get_dating_eligibility() dropped (the app's
-- last callers went in Task 2; the lib/ grep test is green); get_dating_home
-- v2 (R-4) and the reflection's Unicode trim, re-created from their live
-- bodies (only the lines marked "-- Spec 2 W3a" differ).
-- Grants in 20261107150010_dating_v2_client_reads_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- 1. The neutral push (§3.13, I-9): every Dating push is me_update, title
--    "Attune", one of two bodies, data {"route": "me"}; the key is opaque.
CREATE OR REPLACE FUNCTION private.dating_push_source_key(p_user uuid, p_purpose text, p_day date)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  -- Its own server secret (§3.13), never the never-introduce key (M-8).
  v_key constant text := public.app_setting('dating_push_key');
BEGIN
  -- Fail closed: with no key nothing is queued; the caller keeps its
  -- requests for the next publish (publish_country_config counts it).
  IF v_key IS NULL THEN
    RAISE EXCEPTION 'dating:push_key_missing' USING ERRCODE = 'P0001';
  END IF;
  -- Fable M4: a keyed hash of who, why and which day; never a match id,
  -- never readable as a person, a country or Dating.
  RETURN 'me_update:' || encode(extensions.hmac(
           p_user::text || '|' || p_purpose || '|' || p_day::text, v_key, 'sha256'), 'hex');
END;
$$;

CREATE OR REPLACE FUNCTION private.dating_queue_me_update(p_user uuid, p_purpose text, p_kind text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_body text;
  v_n integer;
BEGIN
  v_body := CASE p_kind
    WHEN 'notify' THEN 'Something you asked about is ready in Attune.'
    WHEN 'new' THEN 'You have something new in Attune.'
  END;
  IF p_user IS NULL OR p_purpose IS NULL OR v_body IS NULL THEN
    RAISE EXCEPTION 'dating:invalid_push' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.scheduled_notifications
    (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  VALUES (p_user, 'immediate', now(), 'pending',
          jsonb_build_object('type', 'me_update', 'route', 'me', 'title', 'Attune', 'body', v_body),
          private.dating_push_source_key(p_user, p_purpose, (now() AT TIME ZONE 'UTC')::date), now(), now())
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END;
$$;

-- 2. Whether the person has any Dating data to leave or clear (C-2): a
--    profile, an enrolment, a reflection or a notice request (a kept
--    never-introduce list stays until the account is deleted, §3.8, and
--    is not read here). get_dating_home carries it in every state, so
--    Dating settings (Leave, Clear) are always reachable when they matter.
--    It reads only whether the person's own rows exist, never their text.
CREATE OR REPLACE FUNCTION private.dating_has_data(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p_user IS NOT NULL AND (
         EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = p_user)
      OR EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = p_user)
      OR EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections AS r WHERE r.user_id = p_user)
      OR EXISTS (SELECT 1 FROM public.dating_notify_requests AS n WHERE n.user_id = p_user));
$$;

-- 3. "Tell me when it's here" (§2.7, §3.10; R-5, R-6).
CREATE OR REPLACE FUNCTION private.dating_notice_state(p_user uuid, p_country text, p_region text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  -- available: the place itself is closed (a request for an open country,
  -- with Dating off by the global switch, could never fire; R-5).
  SELECT jsonb_build_object(
    'available', coalesce(p_country IS NOT NULL AND private.dating_iso_country(p_country) IS NOT NULL
                   AND NOT coalesce((SELECT c.dating_enabled
                                            AND (p_region IS NULL OR c.open_regions IS NULL OR p_region = ANY (c.open_regions))
                                       FROM public.dating_country_config(p_country) AS c), false), false),
    'requested', EXISTS (SELECT 1 FROM public.dating_notify_requests AS n
                          WHERE n.user_id = p_user AND n.country_code = p_country
                            AND n.region_code IS NOT DISTINCT FROM p_region));
$$;

CREATE OR REPLACE FUNCTION public.request_dating_country_notice(p_country text, p_region text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_code text;
  v_region text;
  v_config public.country_safety_config;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- Fix round 1 (M-5): an adult account only; no birth date is no adult.
  -- Not gated on the Dating switch (R-5: asking works while Dating is off).
  IF coalesce(public.account_age(v_user), 0) < 18 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
  END IF;
  -- Pre-validated: nothing the person typed reaches an error.
  IF p_country IS NULL OR char_length(p_country) > 8 THEN
    RETURN private.dating_invalid('country');
  END IF;
  v_code := upper(btrim(p_country));
  IF v_code !~ '^[A-Z]{2}$' OR private.dating_iso_country(v_code) IS NULL THEN
    RETURN private.dating_invalid('country');
  END IF;
  IF p_region IS NOT NULL AND (char_length(p_region) > 8 OR upper(btrim(p_region)) !~ '^[A-Z0-9]{2,3}$') THEN
    RETURN private.dating_invalid('region');
  END IF;
  v_region := nullif(upper(btrim(coalesce(p_region, ''))), '');
  -- At most 20 a day (M-10): the aggregate can't be inflated from one app.
  -- Fix round 1 (M-6): a double tap waits on the rate-limit row; a
  -- deadlock or lock timeout there is retried (3), then dating:busy, as
  -- every Dating writer (the SQLSTATE, never the raw DETAIL).
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM public.check_dating_rate_limit('notify_request', 20, interval '1 day');
      EXIT;
    EXCEPTION WHEN invalid_parameter_value THEN
      IF SQLERRM = 'rate_limited' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END IF;
      RAISE;
    WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE;
      END IF;
    END;
  END LOOP;
  -- The publisher's own lock first (R-6): a request and a publish that
  -- opens the place serialise, so neither misses the other.
  BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('country_safety_config:' || v_code, 0));
  EXCEPTION WHEN lock_not_available OR query_canceled THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'busy');
  END;
  v_config := public.dating_country_config(v_code);
  IF v_region IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM jsonb_array_elements(coalesce(v_config.region_list, '[]'::jsonb)) AS r
        WHERE r ->> 'code' = v_region) THEN
    RETURN private.dating_invalid('region');
  END IF;
  IF v_config.dating_enabled IS TRUE
     AND (v_region IS NULL OR v_config.open_regions IS NULL OR v_region = ANY (v_config.open_regions)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_open');
  END IF;
  BEGIN
    INSERT INTO public.dating_notify_requests AS n (user_id, country_code, region_code, created_at)
    VALUES (v_user, v_code, v_region, now())
    ON CONFLICT (user_id) DO UPDATE
      SET country_code = EXCLUDED.country_code, region_code = EXCLUDED.region_code, created_at = now();
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure OR query_canceled THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'busy');
  END;
  BEGIN
    PERFORM private.bump_metric_internal('dating.notify.requested');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- Exposure-reducing: never gated, idempotent, never raises for a busy row.
CREATE OR REPLACE FUNCTION public.cancel_dating_country_notice()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '1s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      DELETE FROM public.dating_notify_requests AS n WHERE n.user_id = v_user;
      RETURN jsonb_build_object('ok', true);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure OR query_canceled THEN
      NULL;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- What is open now, told once (publish_country_config calls it in its own
-- transaction, under its own lock, after its kill switch). Fix round 2
-- (RR1-I1): every pending request whose place is open after this publish
-- is told, not only places this publish newly opened: a request is refused
-- while its place is open, so a pending row for an open place is one an
-- earlier opening could not tell (no push key, an error), and the next
-- publish that leaves the place open tells it. A told row is deleted, so
-- nothing is told twice. A country-wide request is told when the country
-- is open (a country with no region list opens with none); a region
-- request when that region is open. The request is forgotten once its push
-- call returns (RR1-M1): a source-key conflict means that exact request
-- (its key names it, fix round 1) was already pushed. p_was_open and
-- p_open_old are kept for the signature (W5b/W6b) and are not read.
CREATE OR REPLACE FUNCTION private.dating_notify_opened(p_country text, p_was_open boolean, p_open_old text[], p_open_new text[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_new constant text[] := coalesce(p_open_new, ARRAY[]::text[]);
  v_open constant boolean := coalesce((public.dating_country_config(p_country)).dating_enabled, false);
  v_req record;
  v_told integer := 0;
BEGIN
  -- Spec 2 W3 final (I-3): told only when Dating is really open there: the
  -- Spec 2 W3 final global switch and the exclusion key as well as the place
  -- Spec 2 W3 final (dating_eligibility gates 1 and 1b). Otherwise every
  -- Spec 2 W3 final request stays, and the gate cron's sweep tells it later.
  IF public.dating_flag_enabled('dating_mode_enabled') IS NOT TRUE -- Spec 2 W3 final (I-3)
     OR private.dating_exclusion_key_ready() IS NOT TRUE THEN -- Spec 2 W3 final (I-3)
    RETURN 0; -- Spec 2 W3 final (I-3)
  END IF; -- Spec 2 W3 final (I-3)
  FOR v_req IN
    SELECT n.user_id, n.region_code, n.created_at FROM public.dating_notify_requests AS n
     WHERE n.country_code = p_country
       AND ((n.region_code IS NULL AND v_open)
            OR (n.region_code IS NOT NULL AND v_open AND n.region_code = ANY (v_new)))
     ORDER BY n.user_id
       FOR UPDATE OF n
  LOOP
    IF private.dating_queue_me_update(v_req.user_id,
         'notify:' || p_country || ':' || coalesce(v_req.region_code, '*') || ':' || extract(epoch FROM v_req.created_at)::text,
         'notify') THEN
      v_told := v_told + 1;
    END IF;
    DELETE FROM public.dating_notify_requests AS d WHERE d.user_id = v_req.user_id;
  END LOOP;
  RETURN v_told;
END;
$$;

-- 3. Re-created from their live bodies.
CREATE OR REPLACE FUNCTION public.publish_country_config(p_country text, p_values jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_code constant text := upper(coalesce(p_country, ''));
  v_allowed constant text[] := ARRAY['tier', 'dating_enabled', 'open_regions', 'same_gender_enabled',
    'region_list', 'faith_list', 'id_documents', 'generation_hour_utc', 'reference_tz',
    'resources_verified_at', 'legal_checklist', 'source_url', 'reviewed_at', 'reviewed_by', 'published_by'];
  v_old public.country_safety_config;
  v_new public.country_safety_config;
  v_codes text[];
  v_checks text[];
  v_check_row public.country_safety_config; -- I-2
  v_switch boolean; -- Spec 2 W1d
  v_affected integer; -- Spec 2 W1d
  v_closing boolean; -- Spec 2 W1d (PF-F1, batch-5 M-3)
  v_open_old text[]; -- Spec 2 W1d
  v_open_new text[]; -- Spec 2 W1d
  v_try integer; -- Spec 2 W1d (fix round 1, I-2)
  v_failed text; -- Spec 2 W1d (fix round 1, I-1)
  v_told integer; -- Spec 2 W3a
BEGIN
  IF v_code !~ '^[A-Z]{2}$' OR private.dating_iso_country(v_code) IS NULL THEN -- I-1
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_country');
  END IF;
  IF jsonb_typeof(p_values) IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_values) AS k WHERE k <> ALL (v_allowed)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:unknown_key');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('country_safety_config:' || v_code, 0));
  SELECT * INTO v_old FROM public.country_safety_config AS c
   WHERE c.country_code = v_code AND c.is_current FOR UPDATE;
  IF NOT FOUND THEN
    v_old := public.dating_country_config(v_code);
  END IF;

  BEGIN
    v_new := jsonb_populate_record(v_old, p_values - 'open_regions');
    IF p_values ? 'open_regions' THEN
      v_new.open_regions := CASE WHEN jsonb_typeof(p_values -> 'open_regions') = 'null' THEN NULL
                                 ELSE ARRAY(SELECT DISTINCT e FROM jsonb_array_elements_text(p_values -> 'open_regions') AS e
                                             ORDER BY e) END; -- M-2: deduplicated
    END IF;
  EXCEPTION WHEN data_exception OR invalid_text_representation OR datatype_mismatch THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END;
  v_new.country_code := v_code;
  v_new.version := v_old.version + 1;
  v_new.is_current := true;
  v_new.published_at := now();
  v_new.published_by := coalesce(nullif(btrim(p_values ->> 'published_by'), ''), 'service_role');
  -- M-3: a country first published as Tier 1/2 starts same-gender off.
  IF v_old.version = 0 AND v_new.tier IN (1, 2) AND NOT p_values ? 'same_gender_enabled' THEN
    v_new.same_gender_enabled := false;
  END IF;

  IF v_new.tier IS NULL OR v_new.tier NOT BETWEEN 1 AND 3
     OR v_new.dating_enabled IS NULL OR v_new.same_gender_enabled IS NULL
     OR v_new.generation_hour_utc IS NULL OR v_new.generation_hour_utc NOT BETWEEN 0 AND 23
     OR v_new.resources_verified_at > now() + interval '1 day' THEN -- M-1
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name = v_new.reference_tz) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_tz');
  END IF;
  IF jsonb_typeof(v_new.region_list) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.faith_list) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.id_documents) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.legal_checklist) IS DISTINCT FROM 'object'
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_new.region_list) AS r
                 WHERE jsonb_typeof(r) <> 'object' OR coalesce(r ->> 'code', '') !~ '^[A-Z0-9]{2,3}$') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_lists');
  END IF;
  -- I-3: the checklist only grows (a dropped key is a dropped obligation).
  IF NOT (v_new.legal_checklist ?& ARRAY(SELECT jsonb_object_keys(v_old.legal_checklist))) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:checklist_keys_removed');
  END IF;
  v_codes := ARRAY(SELECT r ->> 'code' FROM jsonb_array_elements(v_new.region_list) AS r);
  IF cardinality(v_codes) <> (SELECT count(DISTINCT c) FROM unnest(v_codes) AS c)
     OR (v_new.open_regions IS NOT NULL AND NOT v_new.open_regions <@ v_codes)
     OR (v_new.dating_enabled AND cardinality(v_new.open_regions) = 0) THEN -- M-2: open in no region
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_regions');
  END IF;
  -- Spec 2 W1d (PF-F1, batch-5 M-3): an exposure-reducing publish (closing,
  -- Spec 2 W1d narrowing the open regions, tightening the tier, same-gender
  -- Spec 2 W1d off) widens nothing and adds no ID document; a safety
  -- Spec 2 W1d change is never refused for unrelated lapsed evidence.
  v_open_old := CASE WHEN v_old.dating_enabled IS TRUE -- Spec 2 W1d
                     THEN coalesce(v_old.open_regions, ARRAY(SELECT r ->> 'code' FROM jsonb_array_elements(v_old.region_list) AS r)) -- Spec 2 W1d
                     ELSE ARRAY[]::text[] END; -- Spec 2 W1d
  v_open_new := CASE WHEN v_new.dating_enabled THEN coalesce(v_new.open_regions, v_codes) ELSE ARRAY[]::text[] END; -- Spec 2 W1d
  v_closing := v_old.version >= 1 -- Spec 2 W1d
    AND coalesce(v_open_new <@ v_open_old, false) -- Spec 2 W1d: no region newly open
    AND NOT (v_new.dating_enabled AND v_old.dating_enabled IS NOT TRUE) -- Spec 2 W1d
    AND v_new.tier <= v_old.tier -- Spec 2 W1d: 1 is the strictest
    AND NOT (v_new.same_gender_enabled AND v_old.same_gender_enabled IS NOT TRUE) -- Spec 2 W1d
    AND coalesce(v_old.id_documents @> v_new.id_documents, false) -- Spec 2 W1d: no ID document added (fix round 1, M-8)
    AND ((v_old.dating_enabled IS TRUE AND NOT v_new.dating_enabled) -- Spec 2 W1d: and something is reduced
         OR NOT coalesce(v_open_old <@ v_open_new, false) -- Spec 2 W1d
         OR v_new.tier < v_old.tier -- Spec 2 W1d
         OR NOT coalesce(v_new.id_documents @> v_old.id_documents, false) -- Spec 2 W1d: an ID document removed (fix round 1, M-8)
         OR (v_old.same_gender_enabled IS TRUE AND NOT v_new.same_gender_enabled)); -- Spec 2 W1d
  v_closing := coalesce(v_closing, false); -- Spec 2 W1d
  -- M-4: a country that restricts anything needs its calling code, or the
  -- phone fallback can't see it.
  IF (v_new.tier IN (1, 2) OR NOT v_new.same_gender_enabled)
     AND NOT EXISTS (SELECT 1 FROM private.dating_calling_codes AS k WHERE k.country_code = v_code)
     AND NOT v_closing THEN -- Spec 2 W1d: a reduction is still published (reported below)
    RETURN jsonb_build_object('ok', false, 'reason', 'config:no_calling_code');
  END IF;

  -- Same-gender off: the kill switch runs in this transaction (§2.4).
  -- (Not for a country with no row yet: nobody can have it as their Dating country. M-3)
  v_switch := v_old.version >= 1 AND v_old.same_gender_enabled AND NOT v_new.same_gender_enabled; -- Spec 2 W1d

  -- I-2: the reconsideration is checked at the stricter of the old and new
  -- tiers, and a downgrade needs its own review reference.
  v_check_row := v_new;
  v_check_row.tier := least(v_old.tier, v_new.tier);
  v_checks := private.country_config_checks(v_check_row);
  IF v_old.version >= 1 AND v_new.tier > v_old.tier
     AND (jsonb_typeof(v_new.legal_checklist -> 'tier_review') IS DISTINCT FROM 'string'
          OR btrim(v_new.legal_checklist ->> 'tier_review') = ''
          OR v_new.legal_checklist -> 'tier_review' IS NOT DISTINCT FROM v_old.legal_checklist -> 'tier_review') THEN -- W1 final fix (M-7): each downgrade its own review
    v_checks := array_append(v_checks, 'tier_review_missing');
  END IF;
  IF (v_new.tier IN (1, 2) OR NOT v_new.same_gender_enabled) -- Spec 2 W1d
     AND NOT EXISTS (SELECT 1 FROM private.dating_calling_codes AS k WHERE k.country_code = v_code) THEN -- Spec 2 W1d
    v_checks := array_append(v_checks, 'no_calling_code'); -- Spec 2 W1d: only a reduction gets here
  END IF; -- Spec 2 W1d
  IF cardinality(v_checks) > 0 AND private.attune_environment() = 'production'
     AND NOT v_closing THEN -- Spec 2 W1d (PF-F1): the checks are still returned
    RETURN jsonb_build_object('ok', false, 'reason', 'config:production_checks_failed',
                              'checks', to_jsonb(v_checks));
  END IF;

  UPDATE public.country_safety_config AS c SET is_current = false
   WHERE c.country_code = v_code AND c.is_current;
  INSERT INTO public.country_safety_config SELECT v_new.*;
  IF v_switch THEN -- Spec 2 W1d
    -- Spec 2 W1d: the switch is published even if the purge can't run; a
    -- Spec 2 W1d deadlock or lock timeout is retried (fix round 1, I-2), and a
    -- Spec 2 W1d purge that still fails is left pending, visibly (I-1).
    FOR v_try IN 1..3 LOOP -- Spec 2 W1d
      BEGIN -- Spec 2 W1d
        v_affected := public.apply_same_gender_switch(v_code); -- Spec 2 W1d
        v_failed := NULL; -- Spec 2 W1d
        EXIT; -- Spec 2 W1d
      EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W1d
        v_failed := SQLSTATE; -- Spec 2 W1d: its locks are released; the other side finishes; try again
        EXIT WHEN SQLERRM = 'dating:busy'; -- W1 final fix (N-M3): an inner retry already ran
      WHEN OTHERS THEN -- Spec 2 W1d
        v_failed := SQLSTATE; -- Spec 2 W1d
        EXIT; -- Spec 2 W1d
      END; -- Spec 2 W1d
    END LOOP; -- Spec 2 W1d
    IF v_failed IS NOT NULL THEN -- Spec 2 W1d
      v_affected := NULL; -- Spec 2 W1d
      PERFORM private.dating_kill_switch_mark(v_code, v_failed); -- Spec 2 W1d
      RAISE WARNING 'publish_country_config:kill_switch_pending:%; re-run select public.apply_same_gender_switch(''%'');', v_failed, v_code; -- Spec 2 W1d
    END IF; -- Spec 2 W1d
  END IF; -- Spec 2 W1d
  -- Spec 2 W3a (fix round 1, M-7): after the kill switch, so notice rows
  -- Spec 2 W3a are locked last, as exit locks them (no lock cycle).
  -- Spec 2 W3a (§2.7, R-6): "Tell me when it's here": every pending
  -- Spec 2 W3a request whose place is open after this publish is told once,
  -- Spec 2 W3a then forgotten (fix round 2, RR1-I1). A failure here never
  -- Spec 2 W3a stops the publish (its requests stay for the next publish
  -- Spec 2 W3a that leaves the place open).
  IF v_new.dating_enabled THEN -- Spec 2 W3a
    BEGIN -- Spec 2 W3a
      v_told := private.dating_notify_opened(v_code, v_old.dating_enabled IS TRUE, v_open_old, v_open_new); -- Spec 2 W3a
    EXCEPTION WHEN OTHERS THEN -- Spec 2 W3a
      v_told := NULL; -- Spec 2 W3a
      BEGIN PERFORM private.bump_metric_internal('dating.notify.queue_failed'); EXCEPTION WHEN OTHERS THEN NULL; END; -- Spec 2 W3a
    END; -- Spec 2 W3a
  END IF; -- Spec 2 W3a
  RETURN jsonb_build_object('ok', true, 'country', v_code, 'version', v_new.version,
                            'dating_enabled', v_new.dating_enabled,
                            'same_gender_enabled', v_new.same_gender_enabled,
                            'environment', private.attune_environment(),
                            'checks', to_jsonb(v_checks))
         || CASE WHEN v_switch THEN jsonb_build_object('switched', true, 'affected', v_affected) -- Spec 2 W1d
                 ELSE '{}'::jsonb END -- Spec 2 W1d
         || CASE WHEN v_failed IS NOT NULL THEN jsonb_build_object('pending_sqlstate', v_failed) -- Spec 2 W1d (I-1)
                 ELSE '{}'::jsonb END -- Spec 2 W1d -- Spec 2 W3a (no semicolon)
         || CASE WHEN coalesce(v_told, 0) > 0 THEN jsonb_build_object('notified', v_told) -- Spec 2 W3a
                 ELSE '{}'::jsonb END; -- Spec 2 W3a
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_dating_home()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country text;
  v_region text;
  v_config public.country_safety_config;
  v_enrol public.dating_enrollments;
  v_opens timestamptz;
  v_after timestamptz;
  v_err text;
  v_undated boolean; -- Spec 2 W3a (fix round 1, M-2, M-4)
  v_cand text; -- Spec 2 W3a
  v_has jsonb; -- Spec 2 W3a (C-2)
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_has := jsonb_build_object('has_data', private.dating_has_data(v_user)); -- Spec 2 W3a (C-2)
  v_reason := public.dating_eligibility(v_user, 'setup');
  SELECT p.country_code::text, p.region_code INTO v_country, v_region
    FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_reason IS NOT DISTINCT FROM 'feature_unavailable' THEN
    v_country := coalesce(v_country, private.dating_phone_country((SELECT a.phone FROM auth.users AS a WHERE a.id = v_user))); -- Spec 2 W3a
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'feature_unavailable', 'country', v_country, -- Spec 2 W3a (C-2)
      'notify', private.dating_notice_state(v_user, v_country, NULL)); -- Spec 2 W3a (R-4, R-5)
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'reverify_device'); -- Spec 2 W3a (C-2)
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'account_unavailable' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', private.dating_unavailable_state(v_user)); -- Spec 2 W3a (C-2)
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'country_closed' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'country_closed', 'country', v_country, -- Spec 2 W3a (C-2)
      'notify', private.dating_notice_state(v_user, v_country, NULL)); -- Spec 2 W3a
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'region_closed' THEN
    v_config := public.dating_country_config(v_country);
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'region_closed', 'country', v_country, 'region', v_region, -- Spec 2 W3a (C-2)
      'open_regions', to_jsonb(coalesce(v_config.open_regions, ARRAY[]::text[])), -- Spec 2 W3a
      'notify', private.dating_notice_state(v_user, v_country, v_region)); -- Spec 2 W3a
  END IF;
  SELECT * INTO v_enrol FROM public.dating_enrollments AS e WHERE e.user_id = v_user;
  IF v_reason IS NOT DISTINCT FROM 'relationship_active' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || CASE WHEN v_enrol.state = 'paused' -- Spec 2 W3a (C-2)
                THEN jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason, -- Spec 2 W3a (fix round 1, M-3)
                                        'can_resume', false) -- Spec 2 W3a (T4 fix round 1, I-2): a shared space is open now
                     || CASE WHEN v_enrol.pause_reason = 'same_gender_switch' THEN jsonb_build_object('country', v_country) -- Spec 2 W3a
                             ELSE '{}'::jsonb END -- Spec 2 W3a
                ELSE jsonb_build_object('state', 'unavailable') END;
  END IF;
  IF v_reason IS DISTINCT FROM 'eligible' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- an unknown or NULL reason fails closed -- Spec 2 W3a (C-2)
  END IF;
  IF v_enrol.state = 'suspended' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- suspended without a live restriction (W7a routes it) -- Spec 2 W3a (C-2)
  END IF;
  IF v_enrol.state = 'paused' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason, -- Spec 2 W3a (C-2)
      'can_resume', true) -- Spec 2 W3a (T4 fix round 1, I-2): no shared space holds it (a relationship pause after the space ended)
      || CASE WHEN v_enrol.pause_reason = 'same_gender_switch' THEN jsonb_build_object('country', v_country) -- Spec 2 W3a (the §2.4 note)
              ELSE '{}'::jsonb END; -- Spec 2 W3a
  END IF;
  v_opens := private.dating_gentle_wait_opens_at(v_user);
  v_undated := EXISTS (SELECT 1 FROM public.relationships AS r -- Spec 2 W3a (fix round 1, M-2, M-4): an ending with no date
                       WHERE v_user IN (r.user_a, r.user_b) AND r.status = 'ended' AND r.ended_at IS NULL); -- Spec 2 W3a
  IF v_enrol.state = 'active' THEN
    -- Spec 2 W3a (fix round 1, M-2): read here, so a home read never
    -- Spec 2 W3a reaches the candidate check's undated-ending counter.
    IF v_undated THEN -- Spec 2 W3a
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a (M-2)
    END IF; -- Spec 2 W3a (M-2)
    -- Spec 2 W3a (W2 carry): never "you're live" while the candidate check
    -- Spec 2 W3a refuses for anything but the wait (an undated ending, a
    -- Spec 2 W3a path off Dating); the wait itself is the cool-off below.
    v_cand := public.dating_eligibility(v_user, 'candidate'); -- Spec 2 W3a
    IF v_cand IS DISTINCT FROM 'eligible' AND v_cand IS DISTINCT FROM 'gentle_wait' THEN -- Spec 2 W3a
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a
    END IF; -- Spec 2 W3a
    -- The first drop is the later of the open date and the 72 h cool-off
    -- from account creation (§2.1, §2.8).
    v_after := greatest(coalesce(v_opens, '-infinity'::timestamptz),
                        (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours');
    IF v_after > now() THEN
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'cool_off', 'first_drop_at', private.dating_first_drop_at(v_user, v_after)); -- Spec 2 W3a (C-2)
    END IF;
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'active'); -- Spec 2 W3a (C-2)
  END IF;
  IF v_opens IS NOT NULL THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'gentle_wait', 'ended_at', (v_opens AT TIME ZONE 'UTC' - interval '30 days') AT TIME ZONE 'UTC', 'opens_at', v_opens, -- in UTC (a DST change moves nothing) -- Spec 2 W3a (C-2)
                              'next_step', private.dating_next_step(v_user), -- Spec 2 W3a
                              'can_shorten', coalesce(private.dating_gentle_wait_can_shorten(v_user), false), -- Spec 2 W3a (carry 8)
                              'first_drop_at', private.dating_first_drop_at(v_user, greatest(v_opens, now(), -- Spec 2 W3a
                                (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours'))); -- Spec 2 W3a
  END IF;
  IF private.dating_next_step(v_user) IS NOT DISTINCT FROM 'how' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'not_started', -- Spec 2 W3a (D1 line 6)
      'first_drop_at', CASE WHEN v_undated THEN NULL -- Spec 2 W3a (fix round 1, M-4): no date to promise
        ELSE private.dating_first_drop_at(v_user, greatest(now(), -- Spec 2 W3a
        (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours')) END); -- Spec 2 W3a
  END IF;
  RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'setup_in_progress', 'next_step', private.dating_next_step(v_user), -- Spec 2 W3a (C-2)
    'first_drop_at', CASE WHEN v_undated THEN NULL -- Spec 2 W3a (D13; fix round 1, M-4)
      ELSE private.dating_first_drop_at(v_user, greatest(now(), -- Spec 2 W3a
      (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours')) END); -- Spec 2 W3a
EXCEPTION WHEN raise_exception THEN
  -- An unreadable field or a missing field key is no state the person can
  -- act on: the neutral 'unavailable', never a raw error. Anything else raises.
  -- Every re-creation keeps this handler (W4, W5, W7, W8 add decrypting
  -- readers; nothing in v1's call graph decrypts yet). Counted best-effort.
  v_err := SQLERRM;
  IF v_err IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
    BEGIN
      PERFORM private.bump_metric_internal(CASE WHEN v_err = 'dating:field_key_missing'
                                                THEN 'dating.field_key.missing' ELSE 'dating.home.unreadable_field' END);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a (C-2)
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_gentle_wait_reflection(p_answers jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '1s'
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_key text;
  v_value jsonb;
  v_clean jsonb;
  v_reason text;
  v_at timestamptz;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- Pre-validated: no raw constraint error ever reaches the app.
  IF p_answers IS NULL OR jsonb_typeof(p_answers) IS DISTINCT FROM 'object' THEN
    RETURN private.dating_invalid('answers');
  END IF;
  FOR v_key, v_value IN SELECT k, v FROM jsonb_each(p_answers) AS j(k, v) LOOP
    IF v_key NOT IN ('q1', 'q2', 'q3') THEN
      RETURN private.dating_invalid('answers');
    END IF;
    IF jsonb_typeof(v_value) NOT IN ('string', 'null') OR coalesce(char_length(v_value #>> '{}'), 0) > 500 THEN
      RETURN private.dating_invalid(v_key);
    END IF;
  END LOOP;
  v_clean := jsonb_strip_nulls(jsonb_build_object(
    -- Spec 2 W3a (W2 carry): every Unicode space, not only ' '.
    'q1', nullif(private.dating_trim(p_answers ->> 'q1'), ''), -- Spec 2 W3a
    'q2', nullif(private.dating_trim(p_answers ->> 'q2'), ''), -- Spec 2 W3a
    'q3', nullif(private.dating_trim(p_answers ->> 'q3'), ''))); -- Spec 2 W3a
  IF v_clean = '{}'::jsonb THEN
    -- Clearing one's own answers is never gated (exposure-reducing) and never
    -- fails behind a country switch: it takes no advisory lock (no switch
    -- touches this table, and the clear holds only its own row), retries its
    -- one write, and answers busy (counted) rather than raise (review I-1).
    FOR v_try IN 1..3 LOOP -- a lock conflict or a cancel is retried (each attempt its own savepoint)
      BEGIN
        UPDATE public.dating_gentle_wait_reflections AS g SET answers = NULL, saved_at = NULL WHERE g.user_id = v_user;
        RETURN jsonb_build_object('ok', true, 'saved_at', NULL);
      EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure OR query_canceled THEN
        NULL;
      END;
    END LOOP;
    BEGIN
      PERFORM private.bump_metric_internal('dating.gentle_wait.clear_busy');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RETURN jsonb_build_object('ok', false, 'reason', 'busy');
  END IF;
  BEGIN
    v_reason := private.dating_setup_guard(); -- the lock, the trusted device, setup eligibility
  EXCEPTION WHEN lock_not_available OR query_canceled THEN
    RAISE EXCEPTION 'dating:busy' USING ERRCODE = '55P03'; -- waiting behind a switch: the app retries once
  END;
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  v_at := now();
  FOR v_try IN 1..3 LOOP -- a lock conflict is retried (each attempt its own savepoint)
    BEGIN
      INSERT INTO public.dating_gentle_wait_reflections AS g (user_id, answers, saved_at)
      VALUES (v_user, v_clean, v_at)
      ON CONFLICT (user_id) DO UPDATE SET answers = EXCLUDED.answers, saved_at = EXCLUDED.saved_at;
      EXIT;
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'saved_at', v_at);
END;
$function$;

-- 4. No client reads a Dating table (§4.1, R11): the four owner-read policies.
DROP POLICY IF EXISTS "dating enrollments owner read" ON public.dating_enrollments;
DROP POLICY IF EXISTS "dating consent owner read" ON public.dating_consent_events;
DROP POLICY IF EXISTS "dating profiles owner read" ON public.dating_profiles;
DROP POLICY IF EXISTS "dating preferences owner read" ON public.dating_preferences;

-- 5. The shim's last day (I-4, R21).
DROP FUNCTION IF EXISTS public.get_dating_eligibility();

-- 6. Spec 2 W3 final (I-3): the global switch or the exclusion key can come
--    on after a place opened, and no publish follows, so the gate cron
--    (revalidate-dating-lifecycle-gates, every 15 minutes) sweeps: with
--    both on, every published-open country with a waiting request is told
--    through dating_notify_opened under the publisher's own lock (tried,
--    never waited for: a publish in progress tells them itself). Each
--    country in its own block; a failure is counted and left for the next
--    run. Requests for a closed place stay.
CREATE OR REPLACE FUNCTION private.dating_notify_sweep() -- Spec 2 W3 final (I-3)
RETURNS integer -- Spec 2 W3 final (I-3)
LANGUAGE plpgsql -- Spec 2 W3 final (I-3)
SECURITY DEFINER -- Spec 2 W3 final (I-3)
SET search_path = '' -- Spec 2 W3 final (I-3)
SET lock_timeout = '2s' -- Spec 2 W3 final (I-3)
AS $$ -- Spec 2 W3 final (I-3)
DECLARE -- Spec 2 W3 final (I-3)
  v_code text; -- Spec 2 W3 final (I-3)
  v_config public.country_safety_config; -- Spec 2 W3 final (I-3)
  v_open text[]; -- Spec 2 W3 final (I-3)
  v_told integer := 0; -- Spec 2 W3 final (I-3)
BEGIN -- Spec 2 W3 final (I-3)
  IF public.dating_flag_enabled('dating_mode_enabled') IS NOT TRUE -- Spec 2 W3 final (I-3)
     OR private.dating_exclusion_key_ready() IS NOT TRUE THEN -- Spec 2 W3 final (I-3)
    RETURN 0; -- Spec 2 W3 final (I-3)
  END IF; -- Spec 2 W3 final (I-3)
  FOR v_code IN SELECT DISTINCT n.country_code::text FROM public.dating_notify_requests AS n ORDER BY 1 LOOP -- Spec 2 W3 final (I-3)
    BEGIN -- Spec 2 W3 final (I-3)
      IF pg_try_advisory_xact_lock(hashtextextended('country_safety_config:' || v_code, 0)) THEN -- Spec 2 W3 final (I-3)
        v_config := public.dating_country_config(v_code); -- Spec 2 W3 final (I-3)
        IF v_config.dating_enabled IS TRUE THEN -- Spec 2 W3 final (I-3)
          v_open := coalesce(v_config.open_regions, -- Spec 2 W3 final (I-3)
                             ARRAY(SELECT r ->> 'code' FROM jsonb_array_elements(coalesce(v_config.region_list, '[]'::jsonb)) AS r)); -- Spec 2 W3 final (I-3)
          v_told := v_told + coalesce(private.dating_notify_opened(v_code, true, v_open, v_open), 0); -- Spec 2 W3 final (I-3)
        END IF; -- Spec 2 W3 final (I-3)
      END IF; -- Spec 2 W3 final (I-3)
    EXCEPTION WHEN OTHERS THEN -- Spec 2 W3 final (I-3)
      PERFORM private.bump_metric_internal('dating.notify.queue_failed'); -- Spec 2 W3 final (I-3)
    END; -- Spec 2 W3 final (I-3)
  END LOOP; -- Spec 2 W3 final (I-3)
  RETURN v_told; -- Spec 2 W3 final (I-3)
END; -- Spec 2 W3 final (I-3)
$$; -- Spec 2 W3 final (I-3)

-- 7. Spec 2 W3 final (I-3): the gate cron runs the sweep. Re-created from
--    its live body (pg_get_functiondef on attune_spec3a); only the marked
--    lines change; grants are kept (CREATE OR REPLACE).
CREATE OR REPLACE FUNCTION public.enforce_dating_lifecycle_gates()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO '' -- Spec 2 W3 final (I-3): every name below is qualified
AS $function$
DECLARE v_user_id uuid; v_count bigint := 0;
  v_try integer; -- Spec 2 W2
BEGIN
  -- Spec 2 W2 (Task 3 fix round 1, I-1): the path sweep, before the gates.
  -- Spec 2 W2 Whoever is still active, or a draft, on a chosen path other than
  -- Spec 2 W2 Dating or Relationship (a path trigger that failed) is paused with
  -- Spec 2 W2 path_change by the one helper; each person in their own block,
  -- Spec 2 W2 counted; a failure is left for the next run.
  FOR v_user_id IN -- Spec 2 W2
    SELECT e.user_id FROM public.dating_enrollments AS e JOIN public.users AS u ON u.id = e.user_id -- Spec 2 W2
     WHERE e.state IN ('active', 'profile_draft') AND u.path IS NOT NULL AND u.path NOT IN ('dating', 'relationship') -- Spec 2 W2
     ORDER BY e.user_id -- Spec 2 W2
  LOOP -- Spec 2 W2
    BEGIN -- Spec 2 W2
      IF private.dating_apply_path_pause(v_user_id) THEN -- Spec 2 W2
        PERFORM private.bump_metric_internal('dating.path_pause.swept'); -- Spec 2 W2
        v_count := v_count + 1; -- Spec 2 W2
      END IF; -- Spec 2 W2
    EXCEPTION WHEN OTHERS THEN -- Spec 2 W2
      PERFORM private.bump_metric_internal('dating.path_pause.failed'); -- Spec 2 W2
    END; -- Spec 2 W2
  END LOOP; -- Spec 2 W2
  FOR v_user_id IN
    SELECT de.user_id FROM public.dating_enrollments de
    WHERE de.state='active'
    ORDER BY de.user_id -- Spec 2 W2 fix round 1 (M-4): the gates are read per person below; one stable order
  LOOP
    BEGIN -- Spec 2 W2: one person's lock conflict or error never stops the run
      IF public.dating_age_gate_holds(v_user_id) IS NOT TRUE -- Spec 2 W2: NULL-safe
         OR public.dating_account_in_good_standing(v_user_id) IS NOT TRUE -- Spec 2 W2: NULL-safe
         OR public.dating_eligibility(v_user_id, 'setup') IN ('account_unavailable', 'relationship_active') -- Spec 2 W2: the person's own gates 2-4 replace the Healing gate; the gentle wait, a closed country and the feature switch never pause
         OR public.dating_has_relationship(v_user_id) IS NOT FALSE -- Spec 2 W2: NULL-safe
         OR public.dating_profile_ready(v_user_id) IS NOT TRUE THEN -- Spec 2 W2: NULL-safe
        PERFORM private.dating_lock_setup(v_user_id); -- Spec 2 W2: the shared lock order (setup, then same-gender)
        FOR v_try IN 1..3 LOOP -- Spec 2 W2: a lock conflict is retried (each attempt its own savepoint)
          BEGIN -- Spec 2 W2
            UPDATE public.dating_enrollments SET state='paused',paused_at=COALESCE(paused_at,now()),
              pause_reason=COALESCE(pause_reason,'gates'),updated_at=now() -- Spec 2 W2 (W1 B10 M-6): a reason for every pause
              WHERE user_id=v_user_id AND state='active';
            IF FOUND THEN -- Spec 2 W2: counted and invalidated only when it paused
              UPDATE public.dating_profiles SET profile_state='paused',updated_at=now()
                WHERE user_id=v_user_id AND profile_state='active';
              PERFORM public.invalidate_dating_for_user(v_user_id,'scheduled_gate_revalidation');
              v_count := v_count + 1;
            END IF; -- Spec 2 W2
            EXIT; -- Spec 2 W2
          EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W2
            IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- Spec 2 W2
          END; -- Spec 2 W2
        END LOOP; -- Spec 2 W2
      END IF; -- Spec 2 W2
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W2
      PERFORM private.bump_metric_internal('dating.gates.busy'); -- Spec 2 W2: left for the next run, counted
    WHEN OTHERS THEN -- Spec 2 W2 fix round 1 (M-4): one bad row is counted and skipped
      PERFORM private.bump_metric_internal('dating.gates.failed'); -- Spec 2 W2 fix round 1
    END; -- Spec 2 W2
  END LOOP;
  -- Spec 2 W3 final (I-3): "Tell me when it's here" once Dating is really
  -- Spec 2 W3 final on: the switch or the exclusion key turned on after the
  -- Spec 2 W3 final place opened (no publish follows). Its own block: a
  -- Spec 2 W3 final failure is counted and never stops the gates.
  BEGIN -- Spec 2 W3 final (I-3)
    PERFORM private.dating_notify_sweep(); -- Spec 2 W3 final (I-3)
  EXCEPTION WHEN OTHERS THEN -- Spec 2 W3 final (I-3)
    PERFORM private.bump_metric_internal('dating.notify.queue_failed'); -- Spec 2 W3 final (I-3)
  END; -- Spec 2 W3 final (I-3)
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION private.dating_push_source_key(uuid, text, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_queue_me_update(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_notice_state(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_has_data(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_notify_opened(text, boolean, text[], text[]) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_notify_sweep() FROM PUBLIC, anon, authenticated, service_role; -- Spec 2 W3 final (I-3)

COMMIT;
