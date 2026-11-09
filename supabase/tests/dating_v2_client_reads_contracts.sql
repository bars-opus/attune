-- supabase/tests/dating_v2_client_reads_contracts.sql
-- Spec 2 W3a (§2.7, §3.1, §3.13, §4.1, §4.9 W3a, §4.10; I-4, I-9, R11, R21;
-- carries 4, 7, 8, 9): the client reads no Dating table and the shim is
-- gone (A); get_dating_home v2 (B); "Tell me when it's here" (C); a publish
-- that opens a country or region tells each person once, neutrally (D);
-- the reflection trims every Unicode space (E); every home answer says
-- whether the person has Dating data to leave or clear (F, C-2); a lock
-- wait on the request's rate-limit row is retried, then dating:busy (G);
-- W3 final (I-3): told only when the switch and the exclusion key are on
-- too, and the gate cron's sweep tells the waiting requests then (H).
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_client_reads_contracts.sql
-- Fixture ids 5e300000-0000-0000-0000-0000000000NN; phones 15558706NN.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w3a-reads-key', true);
  -- The push key is its own secret (M-8); section D also runs without it.
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w3a-push-key', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_mode_enabled', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;
SELECT public.publish_country_config('GH', '{"dating_enabled": true, "open_regions": ["AA", "AH"]}') AS gh \gset
SELECT public.publish_country_config('GB', '{"dating_enabled": true}') AS gb \gset

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e300000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;
-- An adult [p_n] on the Dating path whose account is [p_age] old.
CREATE FUNCTION pg_temp.person(p_n text, p_age interval DEFAULT interval '40 days') RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '15558706' || p_n, now(), now() - p_age);
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (pg_temp.id(p_n), '15558706' || p_n, 'Reads ' || p_n, 'dating', now() - p_age, now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (pg_temp.id(p_n), current_date - interval '30 years');
  RETURN pg_temp.id(p_n);
END $$;
CREATE FUNCTION pg_temp.as_person(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;
CREATE FUNCTION pg_temp.as_db() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END $$;
CREATE FUNCTION pg_temp.call(p uuid, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.as_person(p);
  EXECUTE p_sql INTO v;
  PERFORM pg_temp.as_db();
  RETURN v;
END $$;
-- The payloads below are pinned without has_data; section F pins it.
CREATE FUNCTION pg_temp.home(p uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.call(p, 'SELECT public.get_dating_home()') - 'has_data';
$$;
CREATE FUNCTION pg_temp.has_data(p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.call(p, 'SELECT public.get_dating_home()') ->> 'has_data';
$$;
CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0)::bigint;
$$;

-- =====================================================================
-- A. (R11, R21, I-4, A-10, R-2) No client SELECT on the four 20260811120000
--    tables, no owner-read policy, no client-callable invoker reader; the
--    shim is gone and nothing names it; Spec 1's seam still answers.
-- =====================================================================
DO $a$
DECLARE
  v_t text;
  v_got text;
  v_p constant uuid := pg_temp.person('01');
BEGIN
  FOREACH v_t IN ARRAY ARRAY['dating_enrollments', 'dating_consent_events', 'dating_profiles', 'dating_preferences'] LOOP
    IF has_table_privilege('authenticated', 'public.' || v_t, 'SELECT')
       OR has_any_column_privilege('authenticated', 'public.' || v_t, 'SELECT')
       OR has_any_column_privilege('anon', 'public.' || v_t, 'SELECT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a client can still read public.%', v_t;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_policies AS p WHERE p.schemaname = 'public'
              AND p.policyname IN ('dating enrollments owner read', 'dating consent owner read',
                                   'dating profiles owner read', 'dating preferences owner read')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an owner-read policy is still there';
  END IF;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_p, 'profile_draft');
  INSERT INTO public.dating_profiles (user_id, display_name) VALUES (v_p, 'Reads');
  PERFORM pg_temp.as_person(v_p);
  BEGIN
    PERFORM 1 FROM public.dating_profiles LIMIT 1;
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated read dating_profiles directly';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  PERFORM pg_temp.as_db();
  -- A-10: the seam is a definer read, so the revoke doesn't touch it.
  IF pg_temp.call(v_p, 'SELECT public.get_my_home_state()') #>> '{dating,enrolled}' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the revoke get_my_home_state().dating.enrolled is not true';
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_got
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND NOT p.prosecdef AND p.prorettype <> 'trigger'::regtype
     AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
     AND p.prosrc ~ '(dating_enrollments|dating_consent_events|dating_profiles|dating_preferences)';
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: client-callable invoker functions read the revoked tables: %', v_got;
  END IF;
  IF to_regprocedure('public.get_dating_eligibility()') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_proc AS p WHERE p.prosrc ~ 'get_dating_eligibility') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_dating_eligibility() or a caller of it is still there';
  END IF;
  IF pg_get_functiondef('public.request_dating_country_notice(text,text)'::regprocedure)
       !~ 'pg_advisory_xact_lock\(hashtextextended\(''country_safety_config:''' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the notice request does not take the publisher''s lock (R-6)';
  END IF;
  -- Fix round 1 (M-7): the publish locks notice rows after the kill
  -- switch's rows, as exit does (the race script proves it live).
  v_got := pg_get_functiondef('public.publish_country_config(text,jsonb)'::regprocedure);
  IF position('private.dating_notify_opened(' IN v_got) < position('public.apply_same_gender_switch(' IN v_got) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the publish tells before its kill switch (notice rows locked before profiles)';
  END IF;
END $a$;

-- =====================================================================
-- B. get_dating_home v2 (R-4, R-5; carries 4, 8, 9).
-- =====================================================================
DO $b$
DECLARE
  v_new constant uuid := pg_temp.person('10', interval '1 day');
  v_lagos constant uuid := pg_temp.person('11');
  v_volta constant uuid := pg_temp.person('12');
  v_ghana constant uuid := pg_temp.person('13');
  v_wait constant uuid := pg_temp.person('14');
  v_ex constant uuid := pg_temp.person('15');
  v_undated constant uuid := pg_temp.person('16');
  v_ex2 constant uuid := pg_temp.person('17');
  v_switched constant uuid := pg_temp.person('18');
  v_nullreason constant uuid := pg_temp.person('19');
  v_live constant uuid := pg_temp.person('20');
  v_setup constant uuid := pg_temp.person('21');
  v_undated_new constant uuid := pg_temp.person('22');
  v_offpath constant uuid := pg_temp.person('23');
  v_ex3 constant uuid := pg_temp.person('24');
  v_relpaused constant uuid := pg_temp.person('25');
  v_partner constant uuid := pg_temp.person('26');
  v_undated_setup constant uuid := pg_temp.person('27');
  v_ex4 constant uuid := pg_temp.person('28');
  v_relended constant uuid := pg_temp.person('29'); -- Spec 2 W3a (T4 fix round 1, I-2)
  v_relopen constant uuid := pg_temp.person('36'); -- Spec 2 W3a (T4 fix round 1, I-2)
  v_ex5 constant uuid := pg_temp.person('37'); -- Spec 2 W3a (T4 fix round 1, I-2)
  v jsonb;
  v_after timestamptz;
  v_undated_count bigint;
BEGIN
  -- not_started: the first possible drop, 72 h after creation at the latest.
  v := pg_temp.home(v_new);
  v_after := (SELECT u.created_at FROM public.users AS u WHERE u.id = v_new) + interval '72 hours';
  IF v ->> 'state' IS DISTINCT FROM 'not_started'
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k) IS DISTINCT FROM ARRAY['first_drop_at', 'state']
     OR (v ->> 'first_drop_at')::timestamptz < v_after OR (v ->> 'first_drop_at')::timestamptz >= v_after + interval '1 day' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: not_started reads % (72 h after creation: %)', v, v_after;
  END IF;
  -- Closed country and region carry their notice.
  INSERT INTO public.dating_profiles (user_id, display_name, country_code) VALUES (v_lagos, 'Lagos', 'NG');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_volta, 'Volta', 'GH', 'TV');
  IF pg_temp.home(v_lagos) IS DISTINCT FROM
       '{"state": "country_closed", "country": "NG", "notify": {"available": true, "requested": false}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed country reads %', pg_temp.home(v_lagos);
  END IF;
  IF pg_temp.home(v_volta) IS DISTINCT FROM
       '{"state": "region_closed", "country": "GH", "region": "TV", "open_regions": ["AA", "AH"], "notify": {"available": true, "requested": false}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed region reads %', pg_temp.home(v_volta);
  END IF;
  -- R-5: Dating off everywhere; Ghana itself is open, so asking can't fire.
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_ghana, 'Ghana', 'GH', 'AA');
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  v := pg_temp.home(v_ghana);
  IF v IS DISTINCT FROM '{"state": "feature_unavailable", "country": "GH", "notify": {"available": false, "requested": false}}'::jsonb
     OR pg_temp.home(v_lagos) #>> '{notify,available}' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: feature_unavailable reads % (Ghana) / % (Lagos)', v, pg_temp.home(v_lagos);
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  -- gentle_wait: can_shorten (carry 8) and the first drop after the open date.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_wait, v_ex, 'ended', now() - interval '5 days');
  v := pg_temp.home(v_wait);
  IF v ->> 'state' IS DISTINCT FROM 'gentle_wait' OR jsonb_typeof(v -> 'can_shorten') IS DISTINCT FROM 'boolean'
     OR (v ->> 'first_drop_at')::timestamptz < (v ->> 'opens_at')::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: gentle_wait reads %', v;
  END IF;
  -- Carry 4: active, but an ending with no date: never "you're live".
  INSERT INTO public.dating_enrollments (user_id, state, activated_at) VALUES (v_undated, 'active', now());
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, country_code, region_code)
  VALUES (v_undated, 'Undated', 'active', 'GH', 'AA');
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_undated, v_ex2, 'ended', NULL);
  v_undated_count := pg_temp.metric('dating.gentle_wait.undated');
  IF pg_temp.home(v_undated) IS DISTINCT FROM '{"state": "unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: active with an undated ending reads %', pg_temp.home(v_undated);
  END IF;
  -- Fix round 1 (M-2): reading the home counts nothing (the counter is
  -- the candidate check's refusals, not Me opens).
  IF pg_temp.metric('dating.gentle_wait.undated') <> v_undated_count THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: reading the home bumped dating.gentle_wait.undated by %',
      pg_temp.metric('dating.gentle_wait.undated') - v_undated_count;
  END IF;
  -- Carry 4, second cause: active while a path pause waits for the sweep.
  UPDATE public.users SET path = 'just_me' WHERE id = v_offpath;
  INSERT INTO public.dating_enrollments (user_id, state, activated_at) VALUES (v_offpath, 'active', now());
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, country_code, region_code)
  VALUES (v_offpath, 'Off path', 'active', 'GH', 'AA');
  IF pg_temp.home(v_offpath) IS DISTINCT FROM '{"state": "unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: active off the Dating path reads %', pg_temp.home(v_offpath);
  END IF;
  -- setup_in_progress carries the first drop (D13), 72 h after creation at the latest.
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_setup, 'Setup', 'GH', 'AA');
  v := pg_temp.home(v_setup);
  v_after := (SELECT u.created_at FROM public.users AS u WHERE u.id = v_setup) + interval '72 hours';
  IF v ->> 'state' IS DISTINCT FROM 'setup_in_progress' OR v ->> 'next_step' IS DISTINCT FROM 'looking-for'
     OR (v ->> 'first_drop_at')::timestamptz IS NULL OR (v ->> 'first_drop_at')::timestamptz < v_after THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: setup_in_progress reads % (first drop from %)', v, v_after;
  END IF;
  -- Fix round 1 (M-4): an ending with no date promises no first drop.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES
    (v_undated_new, v_ex3, 'ended', NULL), (v_undated_setup, v_ex4, 'ended', NULL);
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_undated_setup, 'Undated setup', 'GH', 'AA');
  IF pg_temp.home(v_undated_new) IS DISTINCT FROM '{"state": "not_started", "first_drop_at": null}'::jsonb
     OR pg_temp.home(v_undated_setup) IS DISTINCT FROM '{"state": "setup_in_progress", "next_step": "looking-for", "first_drop_at": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an undated ending reads % / % (no first drop expected)',
      pg_temp.home(v_undated_new), pg_temp.home(v_undated_setup);
  END IF;
  -- ... while a plain active person is still active.
  INSERT INTO public.dating_enrollments (user_id, state, activated_at) VALUES (v_live, 'active', now());
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, country_code, region_code)
  VALUES (v_live, 'Live', 'active', 'GH', 'AA');
  IF pg_temp.home(v_live) IS DISTINCT FROM '{"state": "active"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a plain active person reads %', pg_temp.home(v_live);
  END IF;
  -- The §2.4 note needs the country; a NULL reason passes through (carry 9).
  INSERT INTO public.dating_enrollments (user_id, state, pause_reason) VALUES
    (v_switched, 'paused', 'same_gender_switch'), (v_nullreason, 'paused', NULL);
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES
    (v_switched, 'Switched', 'GH', 'AA'), (v_nullreason, 'Null', 'GH', 'AA');
  IF pg_temp.home(v_switched) IS DISTINCT FROM '{"state": "paused", "pause_reason": "same_gender_switch", "country": "GH", "can_resume": true}'::jsonb -- Spec 2 W3a (T4 fix round 1, I-2)
     OR pg_temp.home(v_nullreason) IS DISTINCT FROM '{"state": "paused", "pause_reason": null, "can_resume": true}'::jsonb THEN -- Spec 2 W3a (T4 fix round 1, I-2)
    RAISE EXCEPTION 'CONTRACT VIOLATED: paused reads % / %', pg_temp.home(v_switched), pg_temp.home(v_nullreason);
  END IF;
  -- Fix round 1 (M-3): ... and so does a pause read while in a relationship.
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_relpaused, v_partner, 'active');
  INSERT INTO public.dating_enrollments (user_id, state, pause_reason) VALUES (v_relpaused, 'paused', 'same_gender_switch');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_relpaused, 'Rel', 'GH', 'AA');
  IF pg_temp.home(v_relpaused) IS DISTINCT FROM '{"state": "paused", "pause_reason": "same_gender_switch", "country": "GH", "can_resume": false}'::jsonb THEN -- Spec 2 W3a (T4 fix round 1, I-2)
    RAISE EXCEPTION 'CONTRACT VIOLATED: paused in a relationship reads %', pg_temp.home(v_relpaused);
  END IF;
  -- Spec 2 W3a (T4 fix round 1, I-2): a relationship pause says so only
  -- Spec 2 W3a while the shared space is open; once it has ended (no wait
  -- Spec 2 W3a left) the same pause can resume, and says so.
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_relopen, v_ex5, 'active'); -- Spec 2 W3a
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_relended, v_ex5, 'ended', now() - interval '40 days'); -- Spec 2 W3a
  INSERT INTO public.dating_enrollments (user_id, state, pause_reason, activated_at) VALUES -- Spec 2 W3a
    (v_relopen, 'paused', 'relationship', now() - interval '60 days'), (v_relended, 'paused', 'relationship', now() - interval '60 days'); -- Spec 2 W3a
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES -- Spec 2 W3a
    (v_relopen, 'Open', 'GH', 'AA'), (v_relended, 'Ended', 'GH', 'AA'); -- Spec 2 W3a
  IF pg_temp.home(v_relopen) IS DISTINCT FROM '{"state": "paused", "pause_reason": "relationship", "can_resume": false}'::jsonb -- Spec 2 W3a
     OR pg_temp.home(v_relended) IS DISTINCT FROM '{"state": "paused", "pause_reason": "relationship", "can_resume": true}'::jsonb THEN -- Spec 2 W3a
    RAISE EXCEPTION 'CONTRACT VIOLATED: a relationship pause reads % (space open) / % (space ended)', -- Spec 2 W3a
      pg_temp.home(v_relopen), pg_temp.home(v_relended); -- Spec 2 W3a
  END IF; -- Spec 2 W3a
END $b$;

-- =====================================================================
-- C. "Tell me when it's here" (§2.7, §3.10; R-6): signed in only;
--    pre-validated; refused for what is open now; one request per person;
--    cancelling is never gated; counted, aggregate only.
-- =====================================================================
DO $c$
DECLARE
  v_a constant uuid := pg_temp.person('30');
  v_b constant uuid := pg_temp.person('31');
  v_r constant uuid := pg_temp.person('32');
  v_elsewhere constant uuid := pg_temp.person('33');
  v_nobirth constant uuid := pg_temp.person('34');
  v_minor constant uuid := pg_temp.person('35');
  v jsonb;
  v2 jsonb;
  v_msg text;
  v_before bigint := pg_temp.metric('dating.notify.requested');
BEGIN
  BEGIN
    PERFORM public.request_dating_country_notice('NG', NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-out request was taken';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'not_authenticated' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: signed out raised %', v_msg;
    END IF;
  END;
  -- Fix round 1 (M-5): an adult account only (no birth date is no adult).
  DELETE FROM public.account_birthdates WHERE user_id = v_nobirth;
  UPDATE public.account_birthdates SET birth_date = current_date - interval '17 years' WHERE user_id = v_minor;
  v := pg_temp.call(v_nobirth, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  v2 := pg_temp.call(v_minor, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  IF v IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR v2 IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id IN (v_nobirth, v_minor)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a request from no adult reads % / %', v, v2;
  END IF;
  IF pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('G1', NULL)$q$)
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "country"}'::jsonb
     OR pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice(repeat('x', 5000), NULL)$q$)
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "country"}'::jsonb
     OR pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('GH', 'NOPE')$q$)
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "region"}'::jsonb
     OR pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('GH', 'ZZ')$q$)
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "region"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: malformed notice requests are not answered invalid';
  END IF;
  IF pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('GB', NULL)$q$)
       IS DISTINCT FROM '{"ok": false, "reason": "already_open"}'::jsonb
     OR pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('gh', 'aa')$q$)
       IS DISTINCT FROM '{"ok": false, "reason": "already_open"}'::jsonb
     OR pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('GH', NULL)$q$)
       IS DISTINCT FROM '{"ok": false, "reason": "already_open"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a request for something open now was taken';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused request left a row';
  END IF;
  -- Each call is its own statement: a sub-read in the same IF expression
  -- shares one snapshot and would not see the call's write (I-1).
  v := pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  v2 := pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('GH', 'TV')$q$);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR v2 IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT count(*) FROM public.dating_notify_requests WHERE user_id = v_a) <> 1
     OR (SELECT country_code::text || '/' || region_code FROM public.dating_notify_requests WHERE user_id = v_a) IS DISTINCT FROM 'GH/TV' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one request per person, the newest kept';
  END IF;
  IF pg_temp.metric('dating.notify.requested') <> v_before + 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the requests were not counted';
  END IF;
  -- The home says so, to that person only.
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES
    (v_a, 'A', 'GH', 'TV'), (v_b, 'B', 'GH', 'TV');
  -- Fix round 1 (M-9): a request for another place is not this place's.
  PERFORM pg_temp.call(v_elsewhere, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_elsewhere, 'Elsewhere', 'GH', 'TV');
  IF pg_temp.home(v_a) #>> '{notify,requested}' IS DISTINCT FROM 'true'
     OR pg_temp.home(v_b) #>> '{notify,requested}' IS DISTINCT FROM 'false'
     OR pg_temp.home(v_elsewhere) #>> '{notify,requested}' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the notice shows on the wrong person''s home';
  END IF;
  PERFORM pg_temp.call(v_elsewhere, 'SELECT public.cancel_dating_country_notice()');
  -- Cancelling: never gated (Dating off), idempotent.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  v := pg_temp.call(v_a, 'SELECT public.cancel_dating_country_notice()');
  v2 := pg_temp.call(v_a, 'SELECT public.cancel_dating_country_notice()');
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR v2 IS DISTINCT FROM '{"ok": true}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: cancelling failed or was gated';
  END IF;
  v := pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with Dating off an adult''s request reads % (R-5)', v;
  END IF;
  PERFORM pg_temp.call(v_a, 'SELECT public.cancel_dating_country_notice()');
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  -- M-10: at most 20 requests a day, refused ones included (only a
  -- malformed country or a non-adult is answered before the count); the
  -- 21st is refused, calmly.
  FOR i IN 1..20 LOOP
    v := pg_temp.call(v_r, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
    IF v IS DISTINCT FROM '{"ok": true}'::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: request % of 20 refused: %', i, v;
    END IF;
  END LOOP;
  v := pg_temp.call(v_r, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  IF v IS DISTINCT FROM '{"ok": false, "reason": "rate_limited"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 21st request in a day reads %', v;
  END IF;
  PERFORM pg_temp.call(v_r, 'SELECT public.cancel_dating_country_notice()');
END $c$;

-- =====================================================================
-- D. A publish tells every pending request whose place is open after it
--    (fix round 2, RR1-I1): one neutral me_update per request, then the
--    request is forgotten (§2.7, §3.13, I-9); nothing else is queued; the
--    payload and key name nobody and no Dating.
-- =====================================================================
DO $d$
DECLARE
  v_tv constant uuid := pg_temp.person('40');
  v_ng constant uuid := pg_temp.person('41');
  v_stale constant uuid := pg_temp.person('42');
  v_country constant uuid := pg_temp.person('43');
  v_stale_gb constant uuid := pg_temp.person('44');
  v_nokey constant uuid := pg_temp.person('45');
  v_conflict constant uuid := pg_temp.person('46');
  v_failed bigint;
  v_row public.scheduled_notifications;
  v jsonb;
  v2 jsonb;
BEGIN
  PERFORM pg_temp.call(v_tv, $q$SELECT public.request_dating_country_notice('GH', 'TV')$q$);
  PERFORM pg_temp.call(v_ng, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  -- Leftover rows for places already open. A request is refused while its
  -- place is open, so such a row is one an earlier opening could not tell
  -- (no push key, an error; RR1-I1): any publish that leaves the place
  -- open tells it, once, and forgets it; nothing else is queued.
  INSERT INTO public.dating_notify_requests (user_id, country_code, region_code) VALUES
    (v_stale, 'GH', 'AA'), (v_stale_gb, 'GB', NULL);
  v := public.publish_country_config('GH', '{"reviewed_by": "w3a contract"}');
  v2 := public.publish_country_config('GB', '{"reviewed_by": "w3a contract"}');
  IF (v ->> 'notified')::int IS DISTINCT FROM 1 OR (v2 ->> 'notified')::int IS DISTINCT FROM 1
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = v_stale) <> 1
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = v_stale_gb) <> 1
     OR EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id IN (v_stale, v_stale_gb))
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id IN (v_tv, v_ng)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a publish leaving a place open reads % / % (each leftover told once, nothing else)', v, v2;
  END IF;
  -- A republish of an open country with nothing pending queues nothing.
  v := public.publish_country_config('GB', '{"reviewed_by": "w3a contract, again"}');
  IF v ? 'notified'
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id IN (v_stale, v_stale_gb)) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a republish with nothing pending queued %', v;
  END IF;
  -- M-8: with no push key nothing is queued, the publish still succeeds,
  -- the request waits for the next opening, and the failure is counted.
  PERFORM pg_temp.call(v_nokey, $q$SELECT public.request_dating_country_notice('GH', 'WP')$q$);
  v_failed := pg_temp.metric('dating.notify.queue_failed');
  PERFORM set_config('app.settings.dating_push_key', '', true);
  v := public.publish_country_config('GH', '{"open_regions": ["AA", "AH", "WP"]}');
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w3a-push-key', true);
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v ? 'notified'
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = v_nokey)
     OR NOT EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_nokey)
     OR pg_temp.metric('dating.notify.queue_failed') <> v_failed + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with no push key the publish reads % (nothing queued, request kept, counted)', v;
  END IF;
  -- RR1-I1: the key is back and Western stays open: the next publish tells
  -- the request the keyless opening could not, and nothing is left.
  v := public.publish_country_config('GH', '{"reviewed_by": "w3a contract, key back"}');
  IF (v ->> 'notified')::int IS DISTINCT FROM 1
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = v_nokey) <> 1
     OR EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_nokey) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after a keyless opening the republish with the key reads % (1 told, none left)', v;
  END IF;
  v := public.publish_country_config('GH', '{"open_regions": ["AA", "AH", "TV"]}');
  IF (v ->> 'notified')::int IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: opening Volta told % people (1 expected): %', v ->> 'notified', v;
  END IF;
  SELECT * INTO v_row FROM public.scheduled_notifications WHERE user_id = v_tv;
  IF v_row.metadata IS DISTINCT FROM '{"type": "me_update", "route": "me", "title": "Attune", "body": "Something you asked about is ready in Attune."}'::jsonb
     OR v_row.notification_type IS DISTINCT FROM 'immediate' OR v_row.status IS DISTINCT FROM 'pending'
     OR position('dating' IN lower(v_row.metadata::text || v_row.source_key)) > 0
     OR position(v_tv::text IN v_row.source_key) > 0 OR position('GH' IN v_row.source_key) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the queued push is not the neutral me_update: % / %', v_row.metadata, v_row.source_key;
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_tv)
     OR NOT EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_ng)
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = v_ng)
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id IN (v_stale, v_stale_gb, v_nokey)) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the wrong requests were told or forgotten';
  END IF;
  -- Fix round 1 (M-1): told today about Volta, the same person asks about
  -- Western (closed again) and is told when it opens, the same day; a
  -- request is forgotten only once its push is queued.
  v := pg_temp.call(v_tv, $q$SELECT public.request_dating_country_notice('GH', 'WP')$q$);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second request the same day reads %', v;
  END IF;
  v := public.publish_country_config('GH', '{"open_regions": ["AA", "AH", "TV", "WP"]}');
  IF (v ->> 'notified')::int IS DISTINCT FROM 1
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = v_tv AND metadata ->> 'type' = 'me_update') <> 2
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = v_nokey AND metadata ->> 'type' = 'me_update') <> 1
     OR EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id IN (v_tv, v_nokey)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: opening Western the same day reads % (1 told, each pushed once, none left)', v;
  END IF;
  -- RR1-M1: a request whose own push is already queued (its source key
  -- exists) is forgotten, with no second push.
  v := pg_temp.call(v_conflict, $q$SELECT public.request_dating_country_notice('GH', 'BO')$q$);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a request for Bono reads %', v;
  END IF;
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  SELECT n.user_id, 'immediate', now(), 'pending',
         jsonb_build_object('type', 'me_update', 'route', 'me', 'title', 'Attune', 'body', 'Something you asked about is ready in Attune.'),
         private.dating_push_source_key(n.user_id, 'notify:GH:BO:' || extract(epoch FROM n.created_at)::text, (now() AT TIME ZONE 'UTC')::date),
         now(), now()
    FROM public.dating_notify_requests AS n WHERE n.user_id = v_conflict;
  v := public.publish_country_config('GH', '{"open_regions": ["AA", "AH", "TV", "WP", "BO"]}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v ? 'notified'
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = v_conflict) <> 1
     OR EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_conflict) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a request already pushed reads % (forgotten, no second push)', v;
  END IF;
  -- Opening the whole of Nigeria (it has no region list), then closing it.
  PERFORM pg_temp.call(v_country, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  v := public.publish_country_config('NG', '{"dating_enabled": true}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'notified')::int IS DISTINCT FROM 2
     OR EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE country_code = 'NG') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: opening Nigeria reads % (2 told expected)', v;
  END IF;
  v := public.publish_country_config('NG', '{"dating_enabled": false}');
  IF v ? 'notified' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closing publish queued a push';
  END IF;
  -- Closed again: a new request waits, and a republish while closed tells nothing.
  v := pg_temp.call(v_country, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  v2 := public.publish_country_config('NG', '{"reviewed_by": "w3a contract, closed"}');
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR v2 ? 'notified'
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = v_country) <> 1
     OR NOT EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_country) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed country''s republish reads % / % (nothing told, request kept)', v, v2;
  END IF;
  PERFORM pg_temp.call(v_country, 'SELECT public.cancel_dating_country_notice()');
END $d$;

-- =====================================================================
-- E. (W2 carry) The reflection trims every Unicode space: an answer of
--    nothing but spaces is the clear; a padded answer is saved trimmed.
-- =====================================================================
DO $e$
DECLARE
  v_p constant uuid := pg_temp.person('50');
  v jsonb;
BEGIN
  v := pg_temp.call(v_p, $q$SELECT public.save_gentle_wait_reflection(jsonb_build_object('q1', E' Patience \t', 'q2', E'　\n'))$q$);
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR (SELECT answers FROM public.dating_gentle_wait_reflections WHERE user_id = v_p) IS DISTINCT FROM '{"q1": "Patience"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Unicode spaces were kept: % / %', v,
      (SELECT answers FROM public.dating_gentle_wait_reflections WHERE user_id = v_p);
  END IF;
  v := pg_temp.call(v_p, $q$SELECT public.save_gentle_wait_reflection(jsonb_build_object('q1', E'   \t\n'))$q$);
  IF v IS DISTINCT FROM '{"ok": true, "saved_at": null}'::jsonb
     OR (SELECT answers FROM public.dating_gentle_wait_reflections WHERE user_id = v_p) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an answer of Unicode spaces was not the clear: %', v;
  END IF;
END $e$;

-- =====================================================================
-- F. (C-2) has_data in every home answer: no Dating data reads false; a
--    reflection, a notice request or an enrolment reads true, whatever
--    the state (Dating off included), so Leave and Clear stay reachable.
-- =====================================================================
DO $f$
DECLARE
  v_none constant uuid := pg_temp.person('60');
  v_reflect constant uuid := pg_temp.person('61');
  v_notice constant uuid := pg_temp.person('62');
  v_enrolled constant uuid := pg_temp.person('63');
  v_profile constant uuid := pg_temp.person('64');
BEGIN
  -- Fix round 1 (I-1): part-way through D2-D3 there is a profile and no enrolment.
  INSERT INTO public.dating_profiles (user_id, display_name) VALUES (v_profile, 'Profile only');
  PERFORM pg_temp.call(v_reflect, $q$SELECT public.save_gentle_wait_reflection('{"q1": "Patience"}'::jsonb)$q$);
  PERFORM pg_temp.call(v_notice, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  INSERT INTO public.dating_enrollments (user_id) VALUES (v_enrolled);
  IF pg_temp.has_data(v_none) IS DISTINCT FROM 'false'
     OR pg_temp.has_data(v_reflect) IS DISTINCT FROM 'true'
     OR pg_temp.has_data(v_notice) IS DISTINCT FROM 'true'
     OR pg_temp.has_data(v_enrolled) IS DISTINCT FROM 'true'
     OR pg_temp.has_data(v_profile) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: has_data reads % / % / % / % / % (false, true, true, true, true expected)',
      pg_temp.has_data(v_none), pg_temp.has_data(v_reflect), pg_temp.has_data(v_notice), pg_temp.has_data(v_enrolled),
      pg_temp.has_data(v_profile);
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  IF pg_temp.home(v_enrolled) ->> 'state' IS DISTINCT FROM 'feature_unavailable'
     OR pg_temp.has_data(v_enrolled) IS DISTINCT FROM 'true' OR pg_temp.has_data(v_none) IS DISTINCT FROM 'false'
     OR pg_temp.has_data(v_profile) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with Dating off has_data reads % / % / %', pg_temp.has_data(v_enrolled),
      pg_temp.has_data(v_none), pg_temp.has_data(v_profile);
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
END $f$;

-- =====================================================================
-- H. (W3 final, I-3) A request is told only when Dating is really open
--    there: the global switch (dating_mode_enabled) on AND the exclusion
--    key ready, as well as the place. A publish that opens the place while
--    either is off tells nobody and keeps the request; the gate cron's
--    sweep (revalidate-dating-lifecycle-gates) tells it once both are on,
--    once.
-- =====================================================================
DO $h$
DECLARE
  v_ng constant uuid := pg_temp.person('80');
  v_ue constant uuid := pg_temp.person('81');
  v_closed constant uuid := pg_temp.person('82');
  v jsonb;
  v2 jsonb;
BEGIN
  IF pg_temp.call(v_ng, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$) IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.call(v_ue, $q$SELECT public.request_dating_country_notice('GH', 'UE')$q$) IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.call(v_closed, $q$SELECT public.request_dating_country_notice('GH', 'UW')$q$) IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'fixture: the requests were not taken';
  END IF;
  -- The switch off: opening Nigeria tells nobody; the request stays.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  v := public.publish_country_config('NG', '{"dating_enabled": true}');
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v ? 'notified'
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = v_ng)
     OR NOT EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_ng) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with Dating off a publish opening Nigeria reads % (nobody told, the request kept)', v;
  END IF;
  -- The exclusion key not ready (rotated): opening Upper East tells nobody.
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w3-final-rotated-key', true);
  IF private.dating_exclusion_key_ready() IS NOT FALSE THEN
    RAISE EXCEPTION 'fixture: the rotated key still reads ready';
  END IF;
  v := public.publish_country_config('GH', '{"open_regions": ["AA", "AH", "TV", "WP", "BO", "UE"]}');
  PERFORM public.enforce_dating_lifecycle_gates();
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w3a-reads-key', true);
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v ? 'notified'
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id IN (v_ng, v_ue))
     OR (SELECT count(*) FROM public.dating_notify_requests WHERE user_id IN (v_ng, v_ue)) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the exclusion key not ready a publish or the sweep told someone: %', v;
  END IF;
  -- Both on: the gate cron tells each waiting request whose place is open
  -- now, once, and forgets it; a request for a closed region waits.
  IF private.dating_exclusion_key_ready() IS NOT TRUE THEN
    RAISE EXCEPTION 'fixture: the key is not ready again';
  END IF;
  PERFORM public.enforce_dating_lifecycle_gates();
  PERFORM public.enforce_dating_lifecycle_gates();
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = v_ng AND metadata ->> 'type' = 'me_update') <> 1
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = v_ue AND metadata ->> 'type' = 'me_update') <> 1
     OR EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id IN (v_ng, v_ue))
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = v_closed)
     OR NOT EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_closed) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: once Dating is on the sweep told % / % (1 each) and %',
      (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = v_ng),
      (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = v_ue),
      (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = v_closed);
  END IF;
  -- The sweep is the gate cron's.
  IF NOT EXISTS (SELECT 1 FROM cron.job AS j WHERE j.jobname = 'revalidate-dating-lifecycle-gates'
                    AND j.command ~ 'public\.enforce_dating_lifecycle_gates\(\)') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gate cron does not run enforce_dating_lifecycle_gates';
  END IF;
  PERFORM pg_temp.call(v_closed, 'SELECT public.cancel_dating_country_notice()');
  PERFORM public.publish_country_config('NG', '{"dating_enabled": false}');
END $h$;

-- =====================================================================
-- G. (Fix round 1, M-6) A double tap waits on the rate-limit row: a lock
--    timeout or a deadlock there is retried (3), then dating:busy with
--    the SQLSTATE, never the raw error. One connection can't make a real
--    lock wait, so the rate-limit check is replaced, inside this
--    transaction only, by one that fails its first N calls (a sequence
--    counts them: an aborted savepoint keeps nextval). Last section: the
--    ROLLBACK puts the real check back.
-- =====================================================================
CREATE TEMP SEQUENCE t3_rate_calls;
CREATE OR REPLACE FUNCTION public.check_dating_rate_limit(p_operation text, p_limit integer, p_window interval)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fault$
BEGIN
  IF nextval('pg_temp.t3_rate_calls') <= current_setting('t3.fail_n')::integer THEN
    RAISE EXCEPTION 'injected lock wait' USING ERRCODE = current_setting('t3.fail_code');
  END IF;
END $fault$;
DO $g$
DECLARE
  v_p constant uuid := pg_temp.person('70');
  v jsonb;
  v_msg text;
  v_state text;
  v_code text;
BEGIN
  -- Two lock timeouts, then the row is free: the request is taken.
  PERFORM set_config('t3.fail_code', '55P03', true);
  PERFORM set_config('t3.fail_n', '2', true);
  PERFORM setval('pg_temp.t3_rate_calls', 1, false);
  BEGIN
    v := pg_temp.call(v_p, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    RAISE EXCEPTION 'CONTRACT VIOLATED: two lock timeouts on the rate-limit row raised %', v_msg;
  END;
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after two lock timeouts the request reads %', v;
  END IF;
  FOREACH v_code IN ARRAY ARRAY['55P03', '40P01'] LOOP
    PERFORM set_config('t3.fail_code', v_code, true);
    PERFORM set_config('t3.fail_n', '3', true);
    PERFORM setval('pg_temp.t3_rate_calls', 1, false);
    v_msg := NULL;
    BEGIN
      PERFORM pg_temp.call(v_p, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    END;
    IF v_msg IS DISTINCT FROM 'dating:busy' OR v_state IS DISTINCT FROM v_code
       OR currval('pg_temp.t3_rate_calls') <> 3 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % on every try reads % (%) after % tries (dating:busy after 3 expected)',
        v_code, coalesce(v_msg, 'no error'), v_state, currval('pg_temp.t3_rate_calls');
    END IF;
  END LOOP;
END $g$;

ROLLBACK;
