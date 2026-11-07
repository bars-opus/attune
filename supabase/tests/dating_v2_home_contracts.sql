-- supabase/tests/dating_v2_home_contracts.sql
-- Spec 2 W2 (§3.1, §3.2 D0, §4.3, §4.4, §6.9; I-4, A-10): get_dating_home
-- v1 names every state the person is in from their own data only (A), the
-- setup resume step (B), the cool-off and the first drop (C), never a
-- report or a block (D); the gentle-wait reflection is the author's alone,
-- pre-validated, never gated to clear (E), and its two counters (F);
-- the W2 Task 4 carries (H: unreadable fields, UTC dates, column grants,
-- health, the bounded retry, honest standing).
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_home_contracts.sql
-- Fixture ids 5e2f0000-0000-0000-0000-0000000000NN; phones 15558705NN.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w2-home-key', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_mode_enabled', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;
SELECT public.publish_country_config('GH', '{"dating_enabled": true}') AS gh \gset
SELECT public.publish_country_config('GB', '{"dating_enabled": true}') AS gb \gset

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e2f0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;
-- An adult [p_n] on the Dating path whose account is [p_age] old.
CREATE FUNCTION pg_temp.person(p_n text, p_age interval DEFAULT interval '40 days') RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '15558705' || p_n, now(), now() - p_age);
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (pg_temp.id(p_n), '15558705' || p_n, 'Home ' || p_n, 'dating', now() - p_age, now(), '2');
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
CREATE FUNCTION pg_temp.home(p uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.as_person(p);
  v := public.get_dating_home();
  PERFORM pg_temp.as_db();
  RETURN v;
END $$;
CREATE FUNCTION pg_temp.state(p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.home(p) ->> 'state';
$$;
CREATE FUNCTION pg_temp.save(p uuid, p_answers jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.as_person(p);
  v := public.save_gentle_wait_reflection(p_answers);
  PERFORM pg_temp.as_db();
  RETURN v;
END $$;
CREATE FUNCTION pg_temp.reflection(p uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.as_person(p);
  v := public.get_my_gentle_wait_reflection();
  PERFORM pg_temp.as_db();
  RETURN v;
END $$;
CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0)::bigint;
$$;
-- Runs [p_setup] then returns [p_probe]'s value, undoing both.
CREATE FUNCTION pg_temp.probe(p_setup text[], p_probe text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
  v_sql text;
BEGIN
  BEGIN
    FOREACH v_sql IN ARRAY p_setup LOOP
      EXECUTE v_sql;
    END LOOP;
    EXECUTE p_probe INTO v;
    RAISE EXCEPTION 'w2:probe_undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'w2:probe_undo' THEN
      RAISE;
    END IF;
  END;
  RETURN coalesce(v, '<NULL>');
END $$;

-- =====================================================================
-- A. Every state, with exactly the data that state needs.
-- =====================================================================
DO $a$
DECLARE
  v_new constant uuid := pg_temp.person('01');
  v_young constant uuid := pg_temp.person('02');
  v_eula1 constant uuid := pg_temp.person('03');
  v_suspended constant uuid := pg_temp.person('04');
  v_held constant uuid := pg_temp.person('05');
  v_safety constant uuid := pg_temp.person('06');
  v_age constant uuid := pg_temp.person('07');
  v_lagos constant uuid := pg_temp.person('08');
  v_volta constant uuid := pg_temp.person('09');
  v_inviter constant uuid := pg_temp.person('10');
  v_coupled constant uuid := pg_temp.person('11');
  v_partner constant uuid := pg_temp.person('12');
  v_wait constant uuid := pg_temp.person('13');
  v_ex constant uuid := pg_temp.person('14');
  v_paused constant uuid := pg_temp.person('15');
  v_lifted constant uuid := pg_temp.person('16');
  v_left constant uuid := pg_temp.person('17');
  v_ended timestamptz;
  v jsonb;
  v_msg text;
BEGIN
  IF has_function_privilege('anon', 'public.get_dating_home()', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.get_dating_home()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_dating_home()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_dating_home is not the app''s alone';
  END IF;
  BEGIN
    PERFORM public.get_dating_home();
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_dating_home answered without a signed-in person';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'not_authenticated' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: signed out, get_dating_home raised %', v_msg;
    END IF;
  END;

  IF pg_temp.home(v_new) IS DISTINCT FROM '{"state": "not_started"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: nothing set up is %', pg_temp.home(v_new);
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  IF pg_temp.home(v_new) IS DISTINCT FROM '{"state": "feature_unavailable", "country": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with Dating off the home is %', pg_temp.home(v_new);
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';

  -- The person's own standing (gates 2 and 3), most serious first.
  UPDATE public.account_birthdates SET birth_date = current_date - interval '17 years' WHERE user_id = v_young;
  UPDATE public.users SET eula_version = '1' WHERE id = v_eula1;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_suspended, 'suspended');
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_held, 'moderation_hold');
  PERFORM public.place_account_hold(v_safety, 'safety_review', 'spec2-w2-home');
  PERFORM public.place_account_hold(v_age, 'age_review', 'spec2-w2-home');
  IF pg_temp.home(v_young) IS DISTINCT FROM '{"state": "unavailable"}'::jsonb
     OR pg_temp.home(v_eula1) IS DISTINCT FROM '{"state": "unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 or EULA v1 account is % / %', pg_temp.home(v_young), pg_temp.home(v_eula1);
  END IF;
  IF pg_temp.home(v_suspended) IS DISTINCT FROM '{"state": "restricted"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a suspended account is %', pg_temp.home(v_suspended);
  END IF;
  IF pg_temp.home(v_held) IS DISTINCT FROM '{"state": "hold"}'::jsonb OR pg_temp.home(v_safety) IS DISTINCT FROM '{"state": "hold"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an interim or safety hold is % / %', pg_temp.home(v_held), pg_temp.home(v_safety);
  END IF;
  IF pg_temp.home(v_age) IS DISTINCT FROM '{"state": "age_review"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an age review is %', pg_temp.home(v_age);
  END IF;
  -- A lifted suspension is no restriction: the age review shows.
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, lifted_at) VALUES (v_age, 'suspended', now());
  IF pg_temp.state(v_age) IS DISTINCT FROM 'age_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a lifted suspension still reads as %', pg_temp.state(v_age);
  END IF;
  -- A suspension outranks a hold.
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_held, 'suspended');
  IF pg_temp.state(v_held) IS DISTINCT FROM 'restricted' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a suspension and a hold read as %', pg_temp.state(v_held);
  END IF;

  -- The country and region (gate 6).
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES
    (v_lagos, 'Lagos', 'NG', NULL), (v_volta, 'Volta', 'GH', 'TV');
  IF pg_temp.home(v_lagos) IS DISTINCT FROM '{"state": "country_closed", "country": "NG"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed country is %', pg_temp.home(v_lagos);
  END IF;
  IF pg_temp.home(v_volta) IS DISTINCT FROM '{"state": "region_closed", "country": "GH", "region": "TV", "open_regions": ["AA", "AH"]}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed region is %', pg_temp.home(v_volta);
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  IF pg_temp.home(v_lagos) IS DISTINCT FROM '{"state": "feature_unavailable", "country": "NG"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with Dating off a person with a Dating country sees %', pg_temp.home(v_lagos);
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';

  -- The relationship guard (gate 4): paused if enrolled, else unavailable.
  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)
  VALUES (v_inviter, NULL, 'pending', 'W2HOME01', now() + interval '1 day');
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_coupled, 'active');
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_coupled, v_partner, 'active');
  IF pg_temp.home(v_inviter) IS DISTINCT FROM '{"state": "unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inviter never enrolled is %', pg_temp.home(v_inviter);
  END IF;
  IF pg_temp.home(v_coupled) IS DISTINCT FROM '{"state": "paused", "pause_reason": "relationship"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an enrolled person who entered a relationship is %', pg_temp.home(v_coupled);
  END IF;

  -- The gentle wait: the dates and where setup would resume.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_wait, v_ex, 'ended', now() - interval '10 days')
  RETURNING ended_at INTO v_ended;
  IF pg_temp.home(v_wait) IS DISTINCT FROM jsonb_build_object('state', 'gentle_wait', 'ended_at', v_ended,
                                                             'opens_at', v_ended + interval '30 days', 'next_step', 'how') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gentle wait is %', pg_temp.home(v_wait);
  END IF;
  INSERT INTO public.dating_profiles (user_id, display_name, intention, not_married_attested_at, attestation_version)
  VALUES (v_wait, 'Waits', 'marriage', now(), '2026-10-v1');
  IF pg_temp.home(v_wait) ->> 'state' IS DISTINCT FROM 'gentle_wait' OR pg_temp.home(v_wait) ->> 'next_step' IS DISTINCT FROM 'where' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: setting up during the wait is %', pg_temp.home(v_wait);
  END IF;
  -- Paused (own reason), and exited, and suspended without a live restriction.
  INSERT INTO public.dating_enrollments (user_id, state, pause_reason, paused_at) VALUES (v_paused, 'paused', 'user', now());
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_left, 'exited');
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_lifted, 'suspended');
  IF pg_temp.home(v_paused) IS DISTINCT FROM '{"state": "paused", "pause_reason": "user"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused person is %', pg_temp.home(v_paused);
  END IF;
  IF pg_temp.home(v_left) IS DISTINCT FROM '{"state": "not_started"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person who left Dating is %', pg_temp.home(v_left);
  END IF;
  IF pg_temp.home(v_lifted) IS DISTINCT FROM '{"state": "unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a suspended enrolment with no live restriction is %', pg_temp.home(v_lifted);
  END IF;
END $a$;

-- A2. Fail closed: an untrusted device, a key that isn't ready, an
--     unknown or NULL eligibility reason.
DO $a2$
DECLARE
  v_new constant uuid := pg_temp.id('01');
  v text;
BEGIN
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    format('SELECT pg_temp.home(%L)::text', v_new));
  IF v IS DISTINCT FROM '{"state": "reverify_device"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an untrusted device (NULL) saw %', v;
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION private.dating_exclusion_key_ready() RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT false $f$$s$],
    format('SELECT pg_temp.home(%L)::text', v_new));
  IF v IS DISTINCT FROM '{"state": "feature_unavailable", "country": null}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without a ready exclusion key the home is %', v;
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate') RETURNS text LANGUAGE sql STABLE AS $f$ SELECT 'some_new_gate'::text $f$$s$],
    format('SELECT pg_temp.home(%L)::text', v_new));
  IF v IS DISTINCT FROM '{"state": "unavailable"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown eligibility reason gave %', v;
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate') RETURNS text LANGUAGE sql STABLE AS $f$ SELECT NULL::text $f$$s$],
    format('SELECT pg_temp.home(%L)::text', v_new));
  IF v IS DISTINCT FROM '{"state": "unavailable"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL eligibility reason gave %', v;
  END IF;
END $a2$;

-- =====================================================================
-- B. Setup resumes at the first step not done (§3.2, §3.14 step names);
--    faith (D8) is optional.
-- =====================================================================
DO $b$
DECLARE
  v constant uuid := pg_temp.person('20');
  v_step text;
BEGIN
  INSERT INTO public.dating_profiles (user_id, display_name) VALUES (v, 'Steps');
  IF pg_temp.home(v) IS DISTINCT FROM '{"state": "setup_in_progress", "next_step": "looking-for"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bare profile resumes at %', pg_temp.home(v);
  END IF;
  UPDATE public.dating_profiles SET intention = 'committed' WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'looking-for' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an intention without the attestation resumes at %', v_step;
  END IF;
  UPDATE public.dating_profiles SET not_married_attested_at = now(), attestation_version = '2026-10-v1' WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'where' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D2 setup resumes at %', v_step; END IF;
  UPDATE public.dating_profiles SET country_code = 'GH' WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'where' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a country without a region resumes at %', v_step; END IF;
  UPDATE public.dating_profiles SET region_code = 'AA' WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'privacy' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D3 setup resumes at %', v_step; END IF;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v, 'profile_draft');
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v, 'w2-home-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in']) AS p;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'privacy' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: without the special-category consent setup resumes at %', v_step; END IF;
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v, 'w2-home-special', 'special_category_profile', 'granted', 'dating-2.0', clock_timestamp());
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'you' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D4 setup resumes at %', v_step; END IF;
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc) VALUES (v, '\x01'::bytea);
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'meet' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D5 setup resumes at %', v_step; END IF;
  UPDATE public.dating_profile_sensitive SET seeking_enc = '\x01'::bytea WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'children' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D6 setup resumes at %', v_step; END IF;
  UPDATE public.dating_profiles SET children_have = false, children_want = 'open' WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'photos' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D7 (faith optional) setup resumes at %', v_step; END IF;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state) VALUES
    (v, 'w2-home/' || v || '-1.jpg', 1, 'approved'), (v, 'w2-home/' || v || '-2.jpg', 2, 'pending');
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'photos' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: one approved photo resumes at %', v_step; END IF;
  UPDATE public.dating_profile_photos SET moderation_state = 'approved' WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'prompts' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D9 setup resumes at %', v_step; END IF;
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer) VALUES
    (v, 1, 'perfect_sunday', 'A long walk and jollof.'), (v, 2, 'ask_me_about', 'The best chalet in Kumasi.');
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'verify' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D10 setup resumes at %', v_step; END IF;
  UPDATE public.dating_profiles SET verification_state = 'verified' WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'verify' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: verified without the age check resumes at %', v_step; END IF;
  INSERT INTO public.dating_age_verifications (user_id, birth_date, verification_method, verified_at)
  VALUES (v, current_date - interval '30 years', 'test', now());
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'preview' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D11 setup resumes at %', v_step; END IF;
  -- Each helper is the database's own.
  IF has_function_privilege('authenticated', 'private.dating_next_step(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.dating_unavailable_state(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.dating_first_drop_at(uuid,timestamptz)', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.dating_next_step(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a home helper is callable by an API role';
  END IF;
END $b$;

-- =====================================================================
-- C. Active: the first drop is the later of the open date and 72 h from
--    account creation, at the person's drop time in the country's zone.
-- =====================================================================
DO $c$
DECLARE
  v_fresh constant uuid := pg_temp.person('30', interval '1 day');
  v_london constant uuid := pg_temp.person('31', interval '2 days');
  v_waiting constant uuid := pg_temp.person('32');
  v_ex constant uuid := pg_temp.person('33');
  v_open constant uuid := pg_temp.person('34');
  v_lagos constant uuid := pg_temp.person('36');
  v_after timestamptz;
  v jsonb;
  v_at timestamptz;
BEGIN
  INSERT INTO public.dating_enrollments (user_id, state, activated_at) VALUES
    (v_fresh, 'active', now()), (v_london, 'active', now()), (v_waiting, 'active', now()), (v_open, 'active', now());
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, country_code, region_code) VALUES
    (v_fresh, 'Fresh', 'active', 'GH', 'AA'), (v_london, 'London', 'active', 'GB', 'TLI'),
    (v_waiting, 'Waiting', 'active', 'GH', 'AH'), (v_open, 'Open', 'active', 'GH', 'AA');
  INSERT INTO public.dating_settings (user_id, drop_time) VALUES (v_fresh, '22:00'), (v_london, '07:30');
  -- 72 h from creation, Accra, 22:00.
  v := pg_temp.home(v_fresh);
  v_after := (SELECT u.created_at FROM public.users AS u WHERE u.id = v_fresh) + interval '72 hours';
  v_at := (v ->> 'first_drop_at')::timestamptz;
  IF v ->> 'state' IS DISTINCT FROM 'cool_off' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k) IS DISTINCT FROM ARRAY['first_drop_at', 'state']
     OR v_at < v_after OR v_at >= v_after + interval '1 day'
     OR (v_at AT TIME ZONE 'Africa/Accra')::time IS DISTINCT FROM time '22:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the cool-off from account creation reads % (72 h after creation: %)', v, v_after;
  END IF;
  -- London's own clock (summer or winter time), 07:30.
  v := pg_temp.home(v_london);
  v_after := (SELECT u.created_at FROM public.users AS u WHERE u.id = v_london) + interval '72 hours';
  v_at := (v ->> 'first_drop_at')::timestamptz;
  IF v ->> 'state' IS DISTINCT FROM 'cool_off' OR v_at < v_after OR v_at >= v_after + interval '1 day'
     OR (v_at AT TIME ZONE 'Europe/London')::time IS DISTINCT FROM time '07:30' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a London first drop reads % (after %)', v, v_after;
  END IF;
  -- Activated during the wait: the open date decides, at the default 19:00.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_waiting, v_ex, 'ended', now() - interval '20 days');
  v_after := private.dating_gentle_wait_opens_at(v_waiting);
  v := pg_temp.home(v_waiting);
  v_at := (v ->> 'first_drop_at')::timestamptz;
  IF v ->> 'state' IS DISTINCT FROM 'cool_off' OR v_at < v_after OR v_at >= v_after + interval '1 day'
     OR (v_at AT TIME ZONE 'Africa/Accra')::time IS DISTINCT FROM time '19:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: activated during the wait the home reads % (open date %)', v, v_after;
  END IF;
  IF pg_temp.home(v_open) IS DISTINCT FROM '{"state": "active"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: past both dates the home is %', pg_temp.home(v_open);
  END IF;
  -- A zone away from UTC: Lagos (UTC+1), the default 19:00 (the helper).
  PERFORM public.publish_country_config('NG', '{"reference_tz": "Africa/Lagos"}');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code) VALUES (v_lagos, 'Lagos', 'NG');
  v_at := private.dating_first_drop_at(v_lagos, timestamptz '2026-11-10 17:30:00+00');
  IF v_at IS DISTINCT FROM timestamptz '2026-11-10 18:00:00+00'
     OR private.dating_first_drop_at(v_lagos, timestamptz '2026-11-10 18:30:00+00') IS DISTINCT FROM timestamptz '2026-11-11 18:00:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first drop ignores the country''s zone (%)', v_at;
  END IF;
END $c$;

-- =====================================================================
-- D. Nothing tells a reported or blocked person anything: a report about
--    the person and a block of them change nothing in their home.
-- =====================================================================
DO $d$
DECLARE
  v_target constant uuid := pg_temp.id('34');
  v_reporter constant uuid := pg_temp.person('35');
  v_before jsonb;
BEGIN
  v_before := pg_temp.home(v_target);
  INSERT INTO public.dating_reports (reporter_user_id, target_user_id, category) VALUES (v_reporter, v_target, 'harassment');
  INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key)
  VALUES (v_reporter, v_target, public.dating_pair_key(v_reporter, v_target));
  IF pg_temp.home(v_target) IS DISTINCT FROM v_before OR v_before IS DISTINCT FROM '{"state": "active"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report or a block showed in the person''s home (% -> %)', v_before, pg_temp.home(v_target);
  END IF;
END $d$;

-- =====================================================================
-- E. The reflection: the author's alone, pre-validated, never gated to
--    clear; trimmed; blank answers dropped.
-- =====================================================================
DO $e$
DECLARE
  v_wait constant uuid := pg_temp.id('13');
  v_other constant uuid := pg_temp.id('01');
  v_young constant uuid := pg_temp.id('02');
  v jsonb;
  v_msg text;
BEGIN
  IF has_table_privilege('authenticated', 'public.dating_gentle_wait_reflections', 'SELECT')
     OR has_table_privilege('anon', 'public.dating_gentle_wait_reflections', 'SELECT')
     OR has_table_privilege('service_role', 'public.dating_gentle_wait_reflections', 'SELECT')
     OR NOT (SELECT c.relrowsecurity FROM pg_class AS c WHERE c.oid = 'public.dating_gentle_wait_reflections'::regclass) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reflections table is readable by an API role, or RLS is off';
  END IF;
  -- Invalid input is answered, never raised, and nothing is stored. (Each
  -- write and the read that checks it are separate statements.)
  v := jsonb_build_array(pg_temp.save(v_wait, NULL), pg_temp.save(v_wait, '["a"]'), pg_temp.save(v_wait, '{"q4": "x"}'),
                         pg_temp.save(v_wait, '{"q1": 7}'), pg_temp.save(v_wait, jsonb_build_object('q2', repeat('é', 501))));
  IF v IS DISTINCT FROM '[{"ok": false, "field": "answers", "reason": "invalid"}, {"ok": false, "field": "answers", "reason": "invalid"},
                          {"ok": false, "field": "answers", "reason": "invalid"}, {"ok": false, "field": "q1", "reason": "invalid"},
                          {"ok": false, "field": "q2", "reason": "invalid"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: invalid reflections were answered %', v;
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections WHERE user_id = v_wait) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an invalid reflection was stored';
  END IF;
  v := pg_temp.save(v_wait, jsonb_build_object('q1', '  To listen first.  ', 'q2', '', 'q3', repeat('é', 500)));
  IF v ->> 'ok' IS DISTINCT FROM 'true' OR v ->> 'saved_at' IS NULL
     OR (SELECT g.answers FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_wait)
        IS DISTINCT FROM jsonb_build_object('q1', 'To listen first.', 'q3', repeat('é', 500)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a valid reflection saved as % / %', v,
      (SELECT g.answers FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_wait);
  END IF;
  v := pg_temp.reflection(v_wait);
  IF v -> 'answers' IS DISTINCT FROM jsonb_build_object('q1', 'To listen first.', 'q3', repeat('é', 500))
     OR v ->> 'ok' IS DISTINCT FROM 'true' OR v -> 'saved_at' = 'null'::jsonb
     OR (v ->> 'opens_at')::timestamptz IS DISTINCT FROM private.dating_gentle_wait_opens_at(v_wait)
     OR (v ->> 'ended_at')::timestamptz IS DISTINCT FROM private.dating_gentle_wait_opens_at(v_wait) - interval '30 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author reads %', v;
  END IF;
  -- Someone else reads only their own (nothing).
  v := pg_temp.reflection(v_other);
  IF v IS DISTINCT FROM '{"ok": true, "answers": {}, "ended_at": null, "opens_at": null, "saved_at": null, "can_shorten": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another person read %', v;
  END IF;
  -- Saving needs setup eligibility (an under-18 account, Dating off).
  v := pg_temp.save(v_young, '{"q1": "Something"}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections WHERE user_id = v_young) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 account saved a reflection (%)', v;
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  v := pg_temp.save(v_wait, '{"q1": "Changed"}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR (SELECT g.answers ->> 'q1' FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_wait) IS DISTINCT FROM 'To listen first.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reflection was saved with Dating off (%)', v;
  END IF;
  -- Clearing one's own answers is never gated (exposure-reducing).
  v := pg_temp.save(v_wait, '{"q1": " ", "q2": null}');
  IF v IS DISTINCT FROM '{"ok": true, "saved_at": null}'::jsonb
     OR (SELECT g.answers FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_wait) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clearing a reflection with Dating off did not clear it (%)', v;
  END IF;
  -- (Fix round 1, M-2) A clear leaves no saved time behind.
  IF (SELECT g.saved_at FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_wait) IS NOT NULL
     OR pg_temp.reflection(v_wait) -> 'saved_at' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clearing a reflection left a saved time (%)', pg_temp.reflection(v_wait);
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  -- The table refuses a malformed row even from a definer (defence in depth).
  BEGIN
    INSERT INTO public.dating_gentle_wait_reflections (user_id, answers) VALUES (v_other, '{"q9": "x"}');
    RAISE EXCEPTION 'CONTRACT VIOLATED: the table took a malformed reflection';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END $e$;

-- E2. An untrusted device can't save or read answers, but can clear them;
--     both RPCs take the setup lock before writing.
DO $e2$
DECLARE
  v_wait constant uuid := pg_temp.id('13');
  v text;
  v_src text;
BEGIN
  PERFORM pg_temp.save(v_wait, '{"q2": "Kindness"}');
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT false $f$$s$],
    format($q$SELECT pg_temp.save(%L, '{"q1": "New"}')::text || ' ' || pg_temp.reflection(%L)::text$q$, v_wait, v_wait)); -- both refuse: nothing to see
  IF v IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"} {"ok": false, "reason": "reverify_device"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an untrusted device saved or read a reflection (%)', v;
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT false $f$$s$],
    format($q$SELECT pg_temp.save(%L, '{}')::text$q$, v_wait));
  IF v IS DISTINCT FROM '{"ok": true, "saved_at": null}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an untrusted device could not clear its own reflection (%)', v;
  END IF;
  -- (Fix round 1, review I-1/I-2) Saving answers takes the setup guard (the
  -- lock order) before its write; clearing and opening D0 never wait for an
  -- advisory lock (D0 marks the view only under a free try-lock). The race
  -- script proves the behaviour behind a switch; these are the tripwires.
  v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'public.save_gentle_wait_reflection(jsonb)'::regprocedure);
  IF position('private.dating_setup_guard()' IN v_src) = 0
     OR position('private.dating_setup_guard()' IN v_src) > position('INSERT INTO public.dating_gentle_wait_reflections' IN v_src)
     OR position('dating_lock_setup' IN v_src) > 0 OR position('pg_advisory' IN v_src) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: saving does not take the setup guard first, or clearing takes an advisory lock';
  END IF;
  v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'public.get_my_gentle_wait_reflection()'::regprocedure);
  IF position('pg_catalog.pg_try_advisory_xact_lock(' IN v_src) = 0
     OR position('pg_catalog.pg_try_advisory_xact_lock(' IN v_src) > position('INSERT INTO public.dating_gentle_wait_reflections' IN v_src)
     OR position('dating_lock_setup' IN v_src) > 0 OR position('pg_advisory_xact_lock' IN v_src) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: opening D0 does not mark the view under a free try-lock only';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc AS p
              WHERE p.oid IN ('public.save_gentle_wait_reflection(jsonb)'::regprocedure, 'public.get_my_gentle_wait_reflection()'::regprocedure)
                AND 'lock_timeout=1s' <> ALL (coalesce(p.proconfig, ARRAY[]::text[]))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reflection RPC can wait longer than 1s for a lock';
  END IF;
  IF has_function_privilege('anon', 'public.save_gentle_wait_reflection(jsonb)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.save_gentle_wait_reflection(jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_my_gentle_wait_reflection()', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.get_my_gentle_wait_reflection()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.save_gentle_wait_reflection(jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_my_gentle_wait_reflection()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reflection RPCs are not the app''s alone';
  END IF;
END $e2$;

-- =====================================================================
-- F. The two §6.9 counters: D0 opened during a wait (once per ending, not
--    outside a wait, not with Dating off), and an account deleted within
--    7 days of that. Exit deletes the reflection.
-- =====================================================================
DO $f$
DECLARE
  v_seer constant uuid := pg_temp.person('40');
  v_ex constant uuid := pg_temp.person('41');
  v_ex2 constant uuid := pg_temp.person('42');
  v_outside constant uuid := pg_temp.id('01');
  v_gone constant uuid := pg_temp.person('43');
  v_old constant uuid := pg_temp.person('44');
  v_ex3 constant uuid := pg_temp.person('45');
  v_leaver constant uuid := pg_temp.id('13');
  v_both_a constant uuid := pg_temp.person('80');
  v_both_b constant uuid := pg_temp.person('81');
  v_lone constant uuid := pg_temp.person('82');
  v_lone_ex constant uuid := pg_temp.person('83');
  v_seen bigint := pg_temp.metric('dating.gentle_wait.seen');
  v_deleted bigint := pg_temp.metric('dating.gentle_wait.account_deleted_7d');
BEGIN
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES
    (v_seer, v_ex, 'ended', now() - interval '25 days'),
    (v_gone, v_ex3, 'ended', now() - interval '3 days'),
    (v_old, v_ex3, 'ended', now() - interval '12 days');
  PERFORM pg_temp.reflection(v_seer);
  PERFORM pg_temp.reflection(v_seer);
  PERFORM pg_temp.reflection(v_outside);
  IF pg_temp.metric('dating.gentle_wait.seen') IS DISTINCT FROM v_seen + 1
     OR (SELECT g.seen_at FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_seer) IS NULL
     OR EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections WHERE user_id = v_outside) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D0 seen counted % times (expected once, and never outside a wait)',
      pg_temp.metric('dating.gentle_wait.seen') - v_seen;
  END IF;
  -- A later ending (another relationship) counts again.
  UPDATE public.dating_gentle_wait_reflections SET seen_at = now() - interval '24 days' WHERE user_id = v_seer;
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_seer, v_ex2, 'ended', now() - interval '1 day');
  PERFORM pg_temp.reflection(v_seer);
  IF pg_temp.metric('dating.gentle_wait.seen') IS DISTINCT FROM v_seen + 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new ending was not counted as a new view';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  PERFORM pg_temp.reflection(v_gone);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  IF pg_temp.metric('dating.gentle_wait.seen') IS DISTINCT FROM v_seen + 2
     OR EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections WHERE user_id = v_gone) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D0 was counted as seen with Dating off';
  END IF;
  -- Deleted 2 days after D0: counted. Deleted 8 days after: not.
  PERFORM pg_temp.reflection(v_gone);
  UPDATE public.dating_gentle_wait_reflections SET seen_at = now() - interval '2 days' WHERE user_id = v_gone;
  PERFORM pg_temp.reflection(v_old);
  UPDATE public.dating_gentle_wait_reflections SET seen_at = now() - interval '8 days' WHERE user_id = v_old;
  DELETE FROM auth.users WHERE id IN (v_gone, v_old);
  IF pg_temp.metric('dating.gentle_wait.account_deleted_7d') IS DISTINCT FROM v_deleted + 1
     OR EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections WHERE user_id IN (v_gone, v_old)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: deletions after D0 counted % (expected 1: within 7 days only), or a reflection outlived its account',
      pg_temp.metric('dating.gentle_wait.account_deleted_7d') - v_deleted;
  END IF;
  -- (Final review M-4) D0 hears whether closing the space together can
  -- still end the wait: yes while both accounts exist, no once the former
  -- partner's is deleted, and no outside a wait.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES
    (v_both_a, v_both_b, 'ended', now() - interval '6 days'),
    (v_lone, v_lone_ex, 'ended', now() - interval '6 days');
  DELETE FROM auth.users WHERE id = v_lone_ex;
  IF pg_temp.reflection(v_both_a) -> 'can_shorten' IS DISTINCT FROM 'true'::jsonb
     OR pg_temp.reflection(v_lone) -> 'can_shorten' IS DISTINCT FROM 'false'::jsonb
     OR pg_temp.reflection(v_outside) -> 'can_shorten' IS DISTINCT FROM 'false'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D0''s can_shorten gave %, %, % (expected true, false, false)',
      pg_temp.reflection(v_both_a) -> 'can_shorten', pg_temp.reflection(v_lone) -> 'can_shorten',
      pg_temp.reflection(v_outside) -> 'can_shorten';
  END IF;
  -- Exit deletes it (W1d's exit names this table).
  PERFORM pg_temp.save(v_leaver, '{"q1": "Leaving"}');
  PERFORM private.dating_exit_internal(v_leaver, false);
  IF EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections WHERE user_id = v_leaver) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit kept the gentle-wait reflection';
  END IF;
END $f$;

-- =====================================================================
-- G. (A-10) Spec 1's seam is unchanged by W2: exactly {enabled, enrolled}.
-- =====================================================================
DO $g$
DECLARE
  v jsonb := private.dating_home_summary(pg_temp.id('15'));
BEGIN
  IF v IS DISTINCT FROM '{"enabled": true, "enrolled": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_home_summary is %', v;
  END IF;
END $g$;

-- =====================================================================
-- H. (W2 Task 4 carries) The home reads fail closed on an unreadable
--    field or a missing field key; every date it and D0 show is computed
--    in UTC (a summer-time change moves nothing); no API role holds a
--    column of the reflections table; health shows the gentle-wait
--    counters; both reflection writers take the bounded retry; the
--    person's standing is named honestly (H0: only a live restriction, a
--    live Dating record or an Auth ban is "restricted"). Fix round 1: the
--    clear works for anyone, any time (H7); a deletion is never blocked by
--    its counter (H8); exactly four functions read the reflections (H9).
-- =====================================================================
-- [p]'s home, or the error it raised (the caller's role restored).
CREATE FUNCTION pg_temp.home_or_error(p uuid) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  RETURN pg_temp.home(p)::text;
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.as_db();
  RETURN 'raised ' || SQLERRM;
END $$;
-- Saves (or reads, with p_answers NULL) as [p], then, in later statements,
-- what was stored and how many writes were tried (the stand-in's sequence).
CREATE FUNCTION pg_temp.write_story(p uuid, p_answers jsonb) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  BEGIN
    IF p_answers IS NULL THEN
      v := (pg_temp.reflection(p) ->> 'ok');
    ELSE
      v := pg_temp.save(p, p_answers)::text;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.as_db();
    v := 'raised ' || SQLERRM;
  END;
  RETURN v || ' / ' || coalesce((SELECT g.answers ->> 'q1' FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = p), '-')
           || ' / ' || CASE WHEN (SELECT g.seen_at FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = p) IS NULL
                            THEN 'unseen' ELSE 'seen' END
           || ' / ' || (SELECT s.last_value FROM pg_temp.w2_conflicts AS s);
END $$;

-- [p]'s home and then (a later statement) the counter [p_key].
CREATE FUNCTION pg_temp.home_and_metric(p uuid, p_key text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  v := pg_temp.home_or_error(p);
  RETURN v || ' / ' || pg_temp.metric(p_key);
END $$;
-- write_story, then (a later statement) the counter [p_key].
CREATE FUNCTION pg_temp.write_story_m(p uuid, p_answers jsonb, p_key text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  v := pg_temp.write_story(p, p_answers);
  RETURN v || ' / ' || pg_temp.metric(p_key);
END $$;
-- Deletes [p]'s account; says whether it went.
CREATE FUNCTION pg_temp.delete_story(p uuid) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    DELETE FROM auth.users WHERE id = p;
  EXCEPTION WHEN OTHERS THEN
    RETURN 'blocked: ' || SQLERRM;
  END;
  RETURN CASE WHEN EXISTS (SELECT 1 FROM auth.users WHERE id = p) THEN 'kept' ELSE 'deleted' END;
END $$;

DO $h0$
DECLARE
  v_ban constant uuid := pg_temp.person('55');
  v_record constant uuid := pg_temp.person('56');
  v_record_old constant uuid := pg_temp.person('57');
  v_opinions constant uuid := pg_temp.person('58');
  v_ended constant uuid := pg_temp.person('59');
  v_lifted constant uuid := pg_temp.person('60');
  v_resolved constant uuid := pg_temp.person('61');
  v_future constant uuid := pg_temp.person('62');
  v_got text;
BEGIN
  UPDATE auth.users SET banned_until = now() + interval '1 day' WHERE id = v_ban;
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, purge_after)
  VALUES (public.dating_phone_hmac_for_user(v_record), 'dating', 'suspended', now() + interval '1 day');
  -- Each of these has only EULA v1 against it (gate 2): whatever else it
  -- has is spent, not Dating's, or not yet started, so it is "unavailable".
  UPDATE public.users SET eula_version = '1' WHERE id IN (v_record_old, v_opinions, v_ended, v_lifted, v_resolved, v_future);
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, effect_until, purge_after) VALUES
    (public.dating_phone_hmac_for_user(v_record_old), 'dating', 'suspended', now() - interval '1 hour', now() + interval '1 day'),
    (public.dating_phone_hmac_for_user(v_opinions), 'opinions', 'opinions_standing', NULL, now() + interval '1 day');
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, starts_at, ends_at, lifted_at) VALUES
    (v_ended, 'suspended', now() - interval '2 days', now() - interval '1 day', NULL),
    (v_lifted, 'moderation_hold', now() - interval '2 days', NULL, now() - interval '1 day'),
    (v_future, 'suspended', now() + interval '1 day', NULL, NULL);
  PERFORM public.place_account_hold(v_resolved, 'age_review', 'spec2-w2-home');
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'spec2-w2-home' WHERE user_id = v_resolved;
  v_got := concat_ws(',', pg_temp.state(v_ban), pg_temp.state(v_record), pg_temp.state(v_record_old), pg_temp.state(v_opinions),
                     pg_temp.state(v_ended), pg_temp.state(v_lifted), pg_temp.state(v_resolved), pg_temp.state(v_future));
  IF v_got IS DISTINCT FROM 'restricted,restricted,unavailable,unavailable,unavailable,unavailable,unavailable,unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ban, record, spent record, Opinions record, ended suspension, lifted hold, resolved age hold, future suspension read %', v_got;
  END IF;
END $h0$;

DO $h$
DECLARE
  v_new constant uuid := pg_temp.id('01');
  v_dst constant uuid := pg_temp.person('50');
  v_dst_ex constant uuid := pg_temp.person('51');
  v_retry constant uuid := pg_temp.person('52');
  v_retry_ex constant uuid := pg_temp.person('53');
  v_both constant uuid := pg_temp.person('54');
  v_tz constant text := current_setting('TimeZone');
  v_doy integer;
  v_zone text;
  v_ended timestamptz;
  v jsonb;
  v_r jsonb;
  v_t text;
  v_seen bigint;
  v_skipped bigint;
  -- A stand-in that refuses the first [n] reflection writes with a lock
  -- conflict (55P03), counted in a temp sequence (subtransactions roll
  -- back GUCs, not sequences).
  v_stub constant text := $s$CREATE FUNCTION pg_temp.w2_conflict() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
  IF nextval('pg_temp.w2_conflicts') <= %s THEN
    RAISE EXCEPTION 'w2 stand-in conflict' USING ERRCODE = %L;
  END IF;
  RETURN NEW;
END $f$$s$;
  v_trigger constant text := 'CREATE TRIGGER w2_conflict BEFORE INSERT OR UPDATE ON public.dating_gentle_wait_reflections '
                             'FOR EACH ROW EXECUTE FUNCTION pg_temp.w2_conflict()';
BEGIN
  -- 1. An unreadable field or a missing field key is "unavailable", never a
  --    raw error; any other error still raises (never hidden as a state).
  v_seen := pg_temp.metric('dating.home.unreadable_field');
  v_t := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION private.dating_next_step(p_user uuid) RETURNS text LANGUAGE plpgsql STABLE AS $f$ BEGIN RAISE EXCEPTION 'dating:field_decrypt_failed'; END $f$$s$],
    format($q$SELECT pg_temp.home_and_metric(%L, 'dating.home.unreadable_field')$q$, v_new));
  IF v_t IS DISTINCT FROM format('{"state": "unavailable"} / %s', v_seen + 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable field gave the home % (counted before: %)', v_t, v_seen;
  END IF;
  v_seen := pg_temp.metric('dating.field_key.missing');
  v_t := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION private.dating_next_step(p_user uuid) RETURNS text LANGUAGE plpgsql STABLE AS $f$ BEGIN RAISE EXCEPTION 'dating:field_key_missing'; END $f$$s$],
    format($q$SELECT pg_temp.home_and_metric(%L, 'dating.field_key.missing')$q$, v_new));
  IF v_t IS DISTINCT FROM format('{"state": "unavailable"} / %s', v_seen + 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a missing field key gave the home % (counted before: %)', v_t, v_seen;
  END IF;
  v_t := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION private.dating_next_step(p_user uuid) RETURNS text LANGUAGE plpgsql STABLE AS $f$ BEGIN RAISE EXCEPTION 'dating:some_other_failure'; END $f$$s$],
    format('SELECT pg_temp.home_or_error(%L)', v_new));
  IF v_t IS DISTINCT FROM 'raised dating:some_other_failure' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unexpected error was hidden as %', v_t;
  END IF;

  -- 2. A hold is generic on the wire: a safety hold beside an age review
  --    still reads "hold" (the hold's kind is never sent).
  PERFORM public.place_account_hold(v_both, 'safety_review', 'spec2-w2-home');
  PERFORM public.place_account_hold(v_both, 'age_review', 'spec2-w2-home');
  IF pg_temp.home(v_both) IS DISTINCT FROM '{"state": "hold"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a safety hold beside an age review reads %', pg_temp.home(v_both);
  END IF;

  -- 3. (Batch 1 carry) A summer-time change inside the window: a zone whose
  --    DST starts today (POSIX rule, any date of the year) moves neither the
  --    home's dates nor D0's.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at)
  VALUES (v_dst, v_dst_ex, 'ended', now() - interval '10 days') RETURNING ended_at INTO v_ended;
  v_doy := extract(doy FROM now() AT TIME ZONE 'utc')::integer - 1;
  v_zone := format('WGA0WGB,%s/0,%s/0', v_doy, (v_doy + 180) % 365);
  PERFORM set_config('TimeZone', v_zone, true);
  IF v_ended + interval '30 days' = v_ended + interval '720 hours' THEN
    PERFORM set_config('TimeZone', v_tz, true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: test setup: zone % has no change inside the window', v_zone;
  END IF;
  v := pg_temp.home(v_dst);
  v_r := pg_temp.reflection(v_dst);
  PERFORM set_config('TimeZone', v_tz, true);
  IF v ->> 'state' IS DISTINCT FROM 'gentle_wait'
     OR (v ->> 'ended_at')::timestamptz IS DISTINCT FROM v_ended
     OR (v ->> 'opens_at')::timestamptz IS DISTINCT FROM v_ended + interval '720 hours' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: across a summer-time change the home reads % (ended %)', v, v_ended;
  END IF;
  IF (v_r ->> 'ended_at')::timestamptz IS DISTINCT FROM v_ended
     OR (v_r ->> 'opens_at')::timestamptz IS DISTINCT FROM v_ended + interval '720 hours' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: across a summer-time change D0 reads % (ended %)', v_r, v_ended;
  END IF;
  --    Seen half an hour after this ending: opening D0 again in that zone
  --    is the same ending (not a new view).
  UPDATE public.dating_gentle_wait_reflections SET seen_at = v_ended + interval '30 minutes' WHERE user_id = v_dst;
  v_seen := pg_temp.metric('dating.gentle_wait.seen');
  v_skipped := pg_temp.metric('dating.gentle_wait.seen_skipped');
  PERFORM set_config('TimeZone', v_zone, true);
  PERFORM pg_temp.reflection(v_dst);
  PERFORM set_config('TimeZone', v_tz, true);
  IF pg_temp.metric('dating.gentle_wait.seen') IS DISTINCT FROM v_seen
     OR pg_temp.metric('dating.gentle_wait.seen_skipped') IS DISTINCT FROM v_skipped -- (fix round 1) an already-seen view is no skip
     OR (SELECT g.seen_at FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_dst) IS DISTINCT FROM v_ended + interval '30 minutes' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: across a summer-time change a view after the ending counted as a new one';
  END IF;

  -- 4. No API role holds the reflections table or any of its columns.
  IF EXISTS (SELECT 1 FROM unnest(ARRAY['anon', 'authenticated', 'service_role']) AS r(role)
              WHERE has_any_column_privilege(r.role, 'public.dating_gentle_wait_reflections', 'SELECT')
                 OR has_any_column_privilege(r.role, 'public.dating_gentle_wait_reflections', 'INSERT')
                 OR has_any_column_privilege(r.role, 'public.dating_gentle_wait_reflections', 'UPDATE')
                 OR has_any_column_privilege(r.role, 'public.dating_gentle_wait_reflections', 'REFERENCES')
                 OR has_table_privilege(r.role, 'public.dating_gentle_wait_reflections', 'DELETE')
                 OR has_table_privilege(r.role, 'public.dating_gentle_wait_reflections', 'TRUNCATE')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an API role holds the reflections table or one of its columns';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(ARRAY['anon', 'authenticated', 'service_role']) AS r(role),
                           unnest(ARRAY['private.dating_next_step(uuid)', 'private.dating_unavailable_state(uuid)',
                                        'private.dating_first_drop_at(uuid,timestamptz)']) AS f(sig)
              WHERE has_function_privilege(r.role, f.sig, 'EXECUTE')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a home helper is executable by an API role';
  END IF;

  -- 5. Health shows the gentle-wait counters (7 days), beside the gate and
  --    undated counters.
  v := public.get_dating_operational_health() -> 'safety_counters_7d';
  IF NOT (v ?& ARRAY['dating.gentle_wait.seen', 'dating.gentle_wait.account_deleted_7d', 'dating.gates.failed', 'dating.gentle_wait.undated',
                     'dating.gentle_wait.clear_busy', 'dating.gentle_wait.seen_skipped', 'dating.home.unreadable_field', 'dating.field_key.missing'])
     OR (v ->> 'dating.gentle_wait.seen')::bigint IS DISTINCT FROM
        (SELECT coalesce(sum(c.count), 0) FROM public.metric_counters AS c
          WHERE c.key = 'dating.gentle_wait.seen' AND c.day >= (now() AT TIME ZONE 'utc')::date - 6)
     OR (v ->> 'dating.gentle_wait.account_deleted_7d')::bigint IS DISTINCT FROM
        (SELECT coalesce(sum(c.count), 0) FROM public.metric_counters AS c
          WHERE c.key = 'dating.gentle_wait.account_deleted_7d' AND c.day >= (now() AT TIME ZONE 'utc')::date - 6)
     OR (v ->> 'dating.gentle_wait.seen')::bigint < 1 OR (v ->> 'dating.gentle_wait.account_deleted_7d')::bigint < 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not show the gentle-wait counters: %', v;
  END IF;

  -- 6. The bounded retry. Saving: two conflicts are absorbed; a third is
  --    dating:busy and nothing changes. Clearing: two conflicts are absorbed.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at)
  VALUES (v_retry, v_retry_ex, 'ended', now() - interval '5 days');
  v_t := pg_temp.probe(ARRAY['CREATE TEMP SEQUENCE w2_conflicts', format(v_stub, 2, '55P03'), v_trigger],
    format($q$SELECT pg_temp.write_story(%L, '{"q1": "Retry"}')$q$, v_retry));
  IF v_t NOT LIKE '{"ok": true, "saved_at": "%"} / Retry / unseen / 3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: saving through two lock conflicts gave %', v_t;
  END IF;
  PERFORM pg_temp.save(v_retry, '{"q1": "Kept"}');
  v_t := pg_temp.probe(ARRAY['CREATE TEMP SEQUENCE w2_conflicts', format(v_stub, 1000, '55P03'), v_trigger],
    format($q$SELECT pg_temp.write_story(%L, '{"q1": "Lost"}')$q$, v_retry));
  IF v_t IS DISTINCT FROM 'raised dating:busy / Kept / unseen / 3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: saving through endless lock conflicts gave %', v_t;
  END IF;
  --    (Fix round 1, I-1) Saving answers waits behind a switch at most its
  --    1s lock_timeout, then answers dating:busy (the app retries once).
  v_t := pg_temp.probe(ARRAY['CREATE TEMP SEQUENCE w2_conflicts',
    $s$CREATE OR REPLACE FUNCTION private.dating_setup_guard() RETURNS text LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION 'w2 stand-in lock wait' USING ERRCODE = '55P03'; END $f$$s$],
    format($q$SELECT pg_temp.write_story(%L, '{"q1": "Lost"}')$q$, v_retry));
  IF v_t IS DISTINCT FROM 'raised dating:busy / Kept / unseen / 1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: saving behind a lock wait gave %', v_t;
  END IF;
  v_t := pg_temp.probe(ARRAY['CREATE TEMP SEQUENCE w2_conflicts', format(v_stub, 2, '55P03'), v_trigger],
    format($q$SELECT pg_temp.write_story(%L, '{}')$q$, v_retry));
  IF v_t IS DISTINCT FROM '{"ok": true, "saved_at": null} / - / unseen / 3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clearing through two lock conflicts gave %', v_t;
  END IF;
  --    (Fix round 1, I-1) A cancel (a statement timeout) is retried too;
  --    endless conflicts answer busy, counted, never raised.
  v_t := pg_temp.probe(ARRAY['CREATE TEMP SEQUENCE w2_conflicts', format(v_stub, 2, '57014'), v_trigger],
    format($q$SELECT pg_temp.write_story(%L, '{}')$q$, v_retry));
  IF v_t IS DISTINCT FROM '{"ok": true, "saved_at": null} / - / unseen / 3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clearing through two cancels gave %', v_t;
  END IF;
  v_seen := pg_temp.metric('dating.gentle_wait.clear_busy');
  v_t := pg_temp.probe(ARRAY['CREATE TEMP SEQUENCE w2_conflicts', format(v_stub, 1000, '55P03'), v_trigger],
    format($q$SELECT pg_temp.write_story_m(%L, '{}', 'dating.gentle_wait.clear_busy')$q$, v_retry));
  IF v_t IS DISTINCT FROM format('{"ok": false, "reason": "busy"} / Kept / unseen / 3 / %s', v_seen + 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clearing through endless lock conflicts gave % (busy before: %)', v_t, v_seen;
  END IF;
  --    Opening D0: two conflicts are absorbed and the view counted once;
  --    endless conflicts leave the view uncounted and D0 still opens.
  v_seen := pg_temp.metric('dating.gentle_wait.seen');
  v_t := pg_temp.probe(ARRAY['CREATE TEMP SEQUENCE w2_conflicts', format(v_stub, 1000, '55P03'), v_trigger],
    format($q$SELECT pg_temp.write_story_m(%L, NULL, 'dating.gentle_wait.seen')$q$, v_retry));
  IF v_t IS DISTINCT FROM format('true / Kept / unseen / 3 / %s', v_seen) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: opening D0 through endless lock conflicts gave % (seen before: %)', v_t, v_seen;
  END IF;
  v_seen := pg_temp.metric('dating.gentle_wait.seen_skipped');
  v_t := pg_temp.probe(ARRAY['CREATE TEMP SEQUENCE w2_conflicts', format(v_stub, 1000, '57014'), v_trigger],
    format($q$SELECT pg_temp.write_story_m(%L, NULL, 'dating.gentle_wait.seen_skipped')$q$, v_retry));
  IF v_t IS DISTINCT FROM format('true / Kept / unseen / 3 / %s', v_seen + 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a view D0 could not mark (endless cancels) gave % (skipped before: %)', v_t, v_seen;
  END IF;
  v_t := pg_temp.probe(ARRAY['CREATE TEMP SEQUENCE w2_conflicts', format(v_stub, 2, '55P03'), v_trigger],
    format($q$SELECT pg_temp.write_story(%L, NULL)$q$, v_retry));
  IF v_t IS DISTINCT FROM 'true / Kept / seen / 4' THEN -- the third try's insert, then its update
    RAISE EXCEPTION 'CONTRACT VIOLATED: opening D0 through two lock conflicts gave %', v_t;
  END IF;
END $h$;

-- H7. (Fix round 1, I-4 ruling) Clearing works at any time, inside or
--     outside the wait, for anyone with a reflection: after the wait, never
--     set up, not eligible (EULA v1), a closed country, Dating off; and a
--     clear with nothing stored stores nothing.
DO $h7$
DECLARE
  v_after constant uuid := pg_temp.person('63');
  v_after_ex constant uuid := pg_temp.person('64');
  v_never constant uuid := pg_temp.person('65');
  v_eula constant uuid := pg_temp.person('66');
  v_closed constant uuid := pg_temp.person('67');
  v_off constant uuid := pg_temp.person('68');
  v_none constant uuid := pg_temp.person('69');
  v_got text := '';
  v_p uuid;
BEGIN
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_after, v_after_ex, 'ended', now() - interval '40 days');
  UPDATE public.users SET eula_version = '1' WHERE id = v_eula;
  INSERT INTO public.dating_profiles (user_id, display_name, country_code) VALUES (v_closed, 'Closed', 'NG');
  INSERT INTO public.dating_gentle_wait_reflections (user_id, answers, saved_at, seen_at)
  SELECT p, '{"q1": "Still mine"}', now() - interval '35 days', now() - interval '36 days'
    FROM unnest(ARRAY[v_after, v_never, v_eula, v_closed, v_off]) AS p;
  IF pg_temp.state(v_after) IS DISTINCT FROM 'not_started' OR pg_temp.state(v_eula) IS DISTINCT FROM 'unavailable'
     OR pg_temp.state(v_closed) IS DISTINCT FROM 'country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: test setup: H7 states are % / % / %', pg_temp.state(v_after), pg_temp.state(v_eula), pg_temp.state(v_closed);
  END IF;
  FOREACH v_p IN ARRAY ARRAY[v_after, v_never, v_eula, v_closed, v_off, v_none] LOOP
    IF v_p = v_off THEN
      UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
    END IF;
    v_got := v_got || pg_temp.save(v_p, '{"q1": "", "q2": "  "}')::text || ';';
    UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  END LOOP;
  IF v_got IS DISTINCT FROM repeat('{"ok": true, "saved_at": null};', 6)
     OR EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections AS g
                 WHERE g.user_id IN (v_after, v_never, v_eula, v_closed, v_off) AND (g.answers IS NOT NULL OR g.saved_at IS NOT NULL))
     OR EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_none) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clearing outside the wait answered %', v_got;
  END IF;
  IF pg_temp.reflection(v_never) IS DISTINCT FROM '{"ok": true, "answers": {}, "ended_at": null, "opens_at": null, "saved_at": null, "can_shorten": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after a clear outside the wait D0 reads %', pg_temp.reflection(v_never);
  END IF;
END $h7$;

-- H8. (Fix round 1, M-1) The evasion counter never blocks a deletion: with
--     the counter itself failing, the account still goes.
DO $h8$
DECLARE
  v_gone constant uuid := pg_temp.person('70');
  v_t text;
BEGIN
  INSERT INTO public.dating_gentle_wait_reflections (user_id, seen_at) VALUES (v_gone, now() - interval '1 day');
  v_t := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION private.bump_metric_internal(p_key text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  IF p_key = 'dating.gentle_wait.account_deleted_7d' THEN
    RAISE EXCEPTION 'w2 stand-in: the counter fails';
  END IF;
END $f$$s$],
    format('SELECT pg_temp.delete_story(%L)', v_gone));
  IF v_t IS DISTINCT FROM 'deleted' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing evasion counter blocked a deletion (%)', v_t;
  END IF;
END $h8$;

-- H9. (Fix round 1, M-8) Exactly four functions read or write the
--     reflections: the two RPCs, exit and the deletion trigger. A new reader
--     (an export, an AI path) is a reviewed change, never a silent one.
DO $h9$
DECLARE
  v text := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text)
               FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
              WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname NOT LIKE 'pg_temp%'
                AND p.prosrc LIKE '%dating_gentle_wait_reflections%');
BEGIN
  IF v IS DISTINCT FROM 'get_my_gentle_wait_reflection(), private.dating_carry_on_auth_user_delete(), '
                        'private.dating_exit_internal(uuid,boolean), save_gentle_wait_reflection(jsonb)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the functions reaching the reflections changed: %', v;
  END IF;
END $h9$;

DO $$ BEGIN RAISE NOTICE 'dating_v2_home_contracts: all held'; END $$;
ROLLBACK;
