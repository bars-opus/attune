-- supabase/tests/dating_v2_setup_contracts.sql
-- Spec 2 W1c (W3b and W3c extend it) (§2.4, §3.2, §4.4, §7.1, §7.5; plan
-- P-26): the setup writers and the own-profile readers. Off-country
-- same-gender answers return not_available, raise nothing and change no
-- row (A, mutants 4 and 7); D2 (B), D3 (C), D5-D6 on-country (D), D7-D8
-- (E), D10 and D12 (F, W1c migration 8), settings, other countries and
-- photos after mutual (G, migration 8), the readers (H, migration 8), the
-- guards (I), and no field key (J).
-- Batch 7 adds: D5's free text filtered (D, PF-F7), marriage history
-- without the D4 consent (D, I-4), the shared faith clear (E2, PF-F3), the
-- guard's NULL and device branches (I), the enrolment never reopened (K),
-- and an unreadable value or a missing key mid-write answering
-- unavailable (J2, J3).
-- Fix round 1 adds: the locks (0, I-5), the off-country seeking clear
-- (A2, I-4), marriage visibility and the filtered default name (B, I-2,
-- I-3), Skip never gated (E3, I-1), replays after the key is gone (J,
-- M-1), the reviewer's survivors (M-2) and no answer ever raising (L).
-- Batch 8 (Task 10) adds: D10 and D12 malformed input, slurs, control
-- characters and the setup-start counter (F2); settings, other countries
-- and photos-after-mutual edges and refusals (G2); no photo before mutual
-- interest (G3); the readers' own row, exact card keys, device, no key and
-- unreadable values (H2); the Task 10 writers in I and L.
-- Batch 8 fix round 1 adds: a bystander no writer touches (F0, I-3);
-- exposure-reducing changes never gated (G4, I-1); other countries never
-- include a country whose same-gender rule excludes the profile, and D3,
-- D5, D6 remove unsafe ones (C, G5, I-2); cross-user reads and the card's
-- nested keys (H3, I-4); every photo reader allow-listed (G3, I-5);
-- Unicode spaces and invisible controls (F2, M-1); replays (G2, G4, G5,
-- M-3); a wider storage probe (G3, M-10); more people in L (M-11).
-- Batch 9 (Task 11) adds: the never-introduce writers and list in L.
-- Batch 10 (Task 12) adds: L2 (the lifecycle RPCs and the consent writer
-- swept the same way: only their own named refusals, never a DETAIL); G3
-- names exit's hard delete and readiness's completeness.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_setup_contracts.sql
-- Fixture ids 5e2d0000-0000-0000-0000-0000000000NN; phones 15558703NN.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1c-contract-field-key-0123456789abcdef', true);
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1c-contract-exclusion-key', true);
  PERFORM set_config('app.settings.attune_environment', '', true);
  -- Batch 5 (I-1): nobody is eligible until the exclusion key's fingerprint is seeded.
  IF private.seed_dating_exclusion_key_fingerprint() IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'fixture: the exclusion key fingerprint was not seeded';
  END IF;
  -- PF-F7: a placeholder slur term (the filter's own list holds no real one here).
  INSERT INTO private.content_filter_terms (family, term, match_mode, locale, source, review_ref)
  VALUES ('slur', private.match_form('zzwonecunkind'), 'token', 'en', 'reviewed', 'contract fixture');
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  PERFORM public.publish_country_config('GH', '{"dating_enabled": true, "faith_list": [
      {"code": "christian", "name_key": "dating_faith_christian", "denominations": [
         {"code": "catholic", "name_key": "dating_denomination_catholic"}]},
      {"code": "muslim", "name_key": "dating_faith_muslim", "denominations": []}]}');
  PERFORM public.publish_country_config('GB', '{"dating_enabled": true}');
END $$;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e2d0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

-- An eligible adult [p_n], [p_age] years old, account [p_days] days old,
-- with the D4 consents (and faith's) granted.
CREATE FUNCTION pg_temp.person(p_n text, p_age int DEFAULT 30, p_days int DEFAULT 40) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '15558703' || p_n, now(), now() - make_interval(days => p_days));
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (pg_temp.id(p_n), '15558703' || p_n, 'Ama Person ' || p_n, 'dating', now() - make_interval(days => p_days), now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (pg_temp.id(p_n), current_date - make_interval(years => p_age) - interval '10 days');
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT pg_temp.id(p_n), 'consent-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile', 'special_category_faith']) AS p;
  RETURN pg_temp.id(p_n);
END $$;

-- [p_sql] (a writer returning jsonb) as [p_user].
CREATE FUNCTION pg_temp.call(p_user uuid, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  EXECUTE p_sql INTO v;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.key(p text) RETURNS text LANGUAGE sql AS $$
  SELECT 'w1c-' || p || '-' || replace(gen_random_uuid()::text, '-', '');
$$;

-- Everything a person's Dating rows hold, for "nothing changed" checks.
CREATE FUNCTION pg_temp.snapshot(p_user uuid) RETURNS text LANGUAGE sql AS $$
  SELECT md5(concat_ws('|',
    (SELECT to_jsonb(p) - 'updated_at' FROM public.dating_profiles AS p WHERE p.user_id = p_user),
    (SELECT encode(s.identity_enc, 'hex') || encode(coalesce(s.seeking_enc, ''), 'hex') FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user),
    (SELECT to_jsonb(d) - 'updated_at' FROM public.dating_preferences AS d WHERE d.user_id = p_user),
    (SELECT string_agg(to_jsonb(q)::text, ';' ORDER BY q.position) FROM public.dating_prompts AS q WHERE q.user_id = p_user),
    (SELECT to_jsonb(t) - 'updated_at' FROM public.dating_settings AS t WHERE t.user_id = p_user),
    (SELECT count(*) FROM public.dating_rpc_idempotency AS i WHERE i.user_id = p_user),
    (SELECT sum(c.count) FROM public.metric_counters AS c WHERE c.key LIKE 'dating.%')));
$$;

CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce(sum(c.count), 0) FROM public.metric_counters AS c WHERE c.key = p_key;
$$;

-- Does this session hold the two-key advisory lock (hashtext(ns), hashtext(key)) in [p_mode]?
CREATE FUNCTION pg_temp.holds(p_ns text, p_key text, p_mode text) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM pg_locks AS l
                  WHERE l.locktype = 'advisory' AND l.pid = pg_backend_pid() AND l.granted AND l.objsubid = 2
                    AND l.mode = p_mode
                    AND l.classid::bigint = (hashtext(p_ns)::bigint + 4294967296) % 4294967296
                    AND l.objid::bigint = (hashtext(p_key)::bigint + 4294967296) % 4294967296);
$$;

-- A person through D2 and D3 in [p_country] / [p_region].
CREATE FUNCTION pg_temp.located(p_n text, p_country text, p_region text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.person(p_n);
  v jsonb;
BEGIN
  v := pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', pg_temp.key('d2')));
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'fixture: D2 failed %', v; END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, %L, %L, NULL, ''region'')', pg_temp.key('d3'), p_country, p_region));
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'fixture: D3 failed %', v; END IF;
  RETURN v_u;
END $$;

-- B8 fix round 1 (I-3): every Dating row of one person (no global
-- counter), for "another person's rows are untouched" checks.
CREATE FUNCTION pg_temp.rows_of(p_user uuid) RETURNS text LANGUAGE sql AS $$
  SELECT md5(concat_ws('|',
    (SELECT to_jsonb(p) - 'updated_at' FROM public.dating_profiles AS p WHERE p.user_id = p_user),
    (SELECT to_jsonb(s) - 'updated_at' FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user),
    (SELECT to_jsonb(d) - 'updated_at' FROM public.dating_preferences AS d WHERE d.user_id = p_user),
    (SELECT to_jsonb(t) - 'updated_at' FROM public.dating_settings AS t WHERE t.user_id = p_user),
    (SELECT string_agg(to_jsonb(q)::text, ';' ORDER BY q.position) FROM public.dating_prompts AS q WHERE q.user_id = p_user),
    (SELECT string_agg(f.id || f.storage_key || f.moderation_state, ';' ORDER BY f.position) FROM public.dating_profile_photos AS f WHERE f.user_id = p_user),
    (SELECT to_jsonb(e) - 'updated_at' FROM public.dating_enrollments AS e WHERE e.user_id = p_user),
    (SELECT count(*) FROM public.dating_rpc_idempotency AS i WHERE i.user_id = p_user)));
$$;

-- B8 fix round 1: a person through D2-D6 in [p_country] as [p_identity]
-- (extra pools, a specific term) meeting [p_seeking], verified, with the
-- age gate, 40 days old: ready for other countries.
CREATE FUNCTION pg_temp.ready(p_n text, p_country text, p_region text, p_identity text, p_seeking text[],
                              p_pools text[] DEFAULT NULL, p_specific text DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.located(p_n, p_country, p_region);
  v jsonb;
BEGIN
  v := pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, %L, %L, NULL, %L::text[], false)',
                                pg_temp.key('d5'), p_identity, p_specific, p_pools));
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'fixture: D5 failed %', v; END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, %L::text[], 25, 40)', pg_temp.key('d6'), p_seeking));
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'fixture: D6 failed %', v; END IF;
  UPDATE public.dating_profiles SET verification_state = 'verified' WHERE user_id = v_u;
  INSERT INTO public.dating_age_verifications (user_id, birth_date, verification_method, verified_at)
  VALUES (v_u, current_date - interval '30 years', 'contract', now());
  RETURN v_u;
END $$;

-- =====================================================================
-- 0. Locks (I-5): every setup step holds the person's setup lock
--    (exclusive), so one person's steps run one at a time; D5 and D6 hold
--    the Dating country's same-gender lock (shared; Task 13's kill switch
--    takes it exclusive) and lock the profile row. Run first: transaction
--    locks stay held until the ROLLBACK.
-- =====================================================================
DO $$
DECLARE
  v_gh constant uuid := pg_temp.person('30');
  v_gb uuid;
  v_xmax text;
BEGIN
  IF pg_temp.holds('dating_setup', v_gh::text, 'ExclusiveLock') THEN
    RAISE EXCEPTION 'fixture: the setup lock is held before any step';
  END IF;
  PERFORM pg_temp.call(v_gh, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', pg_temp.key('d2')));
  IF NOT pg_temp.holds('dating_setup', v_gh::text, 'ExclusiveLock') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a setup step ran without the person''s setup lock';
  END IF;
  IF pg_temp.holds('dating_same_gender', 'GH', 'ShareLock') THEN
    RAISE EXCEPTION 'fixture: the GH same-gender lock is held before D3';
  END IF;
  PERFORM pg_temp.call(v_gh, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''region'')', pg_temp.key('d3')));
  -- W1 final fix (I-1): D3 takes its new country's same-gender lock (shared)
  -- with the setup lock, before any row (the person had no country yet).
  IF NOT pg_temp.holds('dating_same_gender', 'GH', 'ShareLock') OR pg_temp.holds('dating_same_gender', 'GH', 'ExclusiveLock') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D3 moved into Ghana without its shared same-gender lock';
  END IF;
  PERFORM pg_temp.call(v_gh, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, false)', pg_temp.key('d5')));
  IF NOT pg_temp.holds('dating_same_gender', 'GH', 'ShareLock') OR pg_temp.holds('dating_same_gender', 'GH', 'ExclusiveLock') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D5 decided same-gender without the country''s shared same-gender lock';
  END IF;
  -- D6 on its own: the profile and identity written directly (no D3 or D5,
  -- so no GB lock and no row lock is held before it).
  v_gb := pg_temp.person('31');
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_gb, 'profile_draft');
  INSERT INTO public.dating_profiles (user_id, display_name, moderation_state, country_code, region_code)
  VALUES (v_gb, 'Ama Person 31', 'approved', 'GB', 'TLI');
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc)
  VALUES (v_gb, private.dating_field_encrypt('{"identity": "woman", "specific": null, "specific_text": null, "pronouns": null, "pools": ["woman"]}'));
  SELECT xmax::text INTO v_xmax FROM public.dating_profiles WHERE user_id = v_gb;
  IF pg_temp.holds('dating_same_gender', 'GB', 'ShareLock') OR v_xmax IS DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'fixture: the GB lock or a profile row lock is held before D6 (xmax %)', v_xmax;
  END IF;
  IF pg_temp.call(v_gb, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)', pg_temp.key('d6')))
       IS DISTINCT FROM '{"ok": true, "next_step": "children"}'::jsonb THEN
    RAISE EXCEPTION 'fixture: D6 failed';
  END IF;
  IF NOT pg_temp.holds('dating_same_gender', 'GB', 'ShareLock') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D6 decided same-gender without the country''s shared same-gender lock';
  END IF;
  IF (SELECT xmax::text FROM public.dating_profiles WHERE user_id = v_gb) IS NOT DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D6 did not lock the profile row (its country) before deciding';
  END IF;
END $$;

-- D3, D5 and D8 lock the profile row before deciding: each refusal below
-- returns after the lock and before any write, so the row's xmax shows
-- the lock alone. Skip holds the setup lock too.
DO $$
DECLARE
  v_d3 constant uuid := pg_temp.person('44');
  v_d5 constant uuid := pg_temp.person('45');
  v_d8 constant uuid := pg_temp.person('46');
  v_skip constant uuid := pg_temp.person('43');
  v_x uuid;
  v_got jsonb;
BEGIN
  FOREACH v_x IN ARRAY ARRAY[v_d3, v_d5, v_d8] LOOP
    INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_x, 'profile_draft');
    INSERT INTO public.dating_profiles (user_id, display_name, moderation_state, country_code, region_code, country_changed_at)
    VALUES (v_x, 'Ama Person', 'approved', 'GH', 'AA', now());
    INSERT INTO public.dating_profile_sensitive (user_id) VALUES (v_x);
  END LOOP;
  IF (SELECT count(*) FROM public.dating_profiles WHERE user_id IN (v_d3, v_d5, v_d8) AND xmax::text = '0') IS DISTINCT FROM 3::bigint THEN
    RAISE EXCEPTION 'fixture: a lock-probe profile row is locked before its step';
  END IF;
  v_got := jsonb_build_array(
    pg_temp.call(v_d3, format('SELECT public.save_dating_location(%L, ''GB'', ''TLI'', NULL, ''region'')', pg_temp.key('lk'))),
    pg_temp.call(v_d5, format('SELECT public.save_dating_identity(%L, ''non_binary'', NULL, NULL, NULL, false)', pg_temp.key('lk'))),
    pg_temp.call(v_d8, format('SELECT public.save_dating_faith(%L, ''hindu'', NULL, ''must_share'', false)', pg_temp.key('lk'))));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "country_change_limited"}, {"ok": false, "reason": "not_available"},
                              {"ok": false, "reason": "invalid", "field": "faith"}]'::jsonb THEN
    RAISE EXCEPTION 'fixture: the lock probes were not refused as expected: %', v_got;
  END IF;
  IF (SELECT xmax::text FROM public.dating_profiles WHERE user_id = v_d3) = '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D3 did not lock the profile row before the country-change limit';
  END IF;
  IF (SELECT xmax::text FROM public.dating_profiles WHERE user_id = v_d5) = '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D5 did not lock the profile row before deciding same-gender';
  END IF;
  IF (SELECT xmax::text FROM public.dating_profiles WHERE user_id = v_d8) = '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D8 did not lock the profile row before reading the country''s faith list';
  END IF;
  PERFORM pg_temp.call(v_skip, format('SELECT public.clear_dating_faith(%L)', pg_temp.key('lk')));
  IF NOT pg_temp.holds('dating_setup', v_skip::text, 'ExclusiveLock') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Skip ran without the person''s setup lock';
  END IF;
END $$;

-- =====================================================================
-- A. Off-country (§2.4, mutants 4 and 7): a same-gender answer in Ghana
--    is not_available, raises nothing, changes nothing, counts nothing.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('01', 'GH', 'AA');
  v_before text;
  v jsonb;
  v_case text;
BEGIN
  v := pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''man'', NULL, NULL, NULL, false)', pg_temp.key('d5')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "meet"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Man was refused in Ghana: %', v;
  END IF;
  IF (SELECT gender_visible FROM public.dating_profiles WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D5 showed the gender although p_visible was false';
  END IF;
  v_before := pg_temp.snapshot(v_u);
  FOREACH v_case IN ARRAY ARRAY[
    'SELECT public.save_dating_identity(%L, ''non_binary'', NULL, NULL, NULL, false)',
    'SELECT public.save_dating_identity(%L, ''non_binary'', NULL, NULL, ARRAY[''woman''], true)',
    'SELECT public.save_dating_identity(%L, ''woman'', ''trans_woman'', NULL, NULL, false)',
    'SELECT public.save_dating_identity(%L, ''man'', NULL, ''they/them'', NULL, false)',
    'SELECT public.save_dating_identity(%L, ''man'', NULL, NULL, ARRAY[''man''], false)',
    'SELECT public.save_dating_identity(%L, ''man'', ''zero two four four one two'', ''three four five six'', NULL, false)',
    'SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)',
    'SELECT public.save_dating_who_to_meet(%L, ARRAY[''man'', ''woman'', ''non_binary''], 25, 35)'] LOOP
    BEGIN
      v := pg_temp.call(v_u, format(v_case, pg_temp.key('off')));
    EXCEPTION WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: an off-country same-gender answer raised (%): %', SQLERRM, v_case;
    END;
    IF v IS DISTINCT FROM '{"ok": false, "reason": "not_available"}'::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: an off-country same-gender answer was not refused with not_available (%): %', v_case, v;
    END IF;
    IF pg_temp.snapshot(v_u) IS DISTINCT FROM v_before THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: an off-country same-gender answer changed a row or a counter (%)', v_case;
    END IF;
  END LOOP;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman''], 25, 35)', pg_temp.key('d6')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "children"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a man meeting women was refused in Ghana: %', v;
  END IF;
  -- The global flag off makes every country off, the UK included.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  IF NOT EXISTS (SELECT 1 FROM public.country_safety_config WHERE country_code = 'GB' AND is_current AND same_gender_enabled) THEN
    RAISE EXCEPTION 'fixture: GB should allow same-gender';
  END IF;
END $$;

-- A2 (I-4). Off-country, a changed identity asks who-to-meet again: a
--    man seeking women who becomes a woman keeps no seeking answer (a
--    woman seeking women would be stored in Ghana); the same identity
--    re-saved keeps it.
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('32', 'GH', 'AA');
BEGIN
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''man'', NULL, NULL, NULL, true)', pg_temp.key('d5')));
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman''], 25, 35)', pg_temp.key('d6')));
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''man'', NULL, NULL, NULL, true)', pg_temp.key('d5same')));
  IF (SELECT seeking_enc IS NULL FROM public.dating_profile_sensitive WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-saving the same identity off-country cleared who-to-meet';
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, true)', pg_temp.key('d5chg')))
       IS DISTINCT FROM '{"ok": true, "next_step": "meet"}'::jsonb THEN
    RAISE EXCEPTION 'fixture: D5 woman failed';
  END IF;
  IF (SELECT seeking_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: off-country, a changed identity kept who-to-meet (a same-gender seeking stored in Ghana)';
  END IF;
END $$;

DO $$
DECLARE
  v_uk constant uuid := pg_temp.located('02', 'GB', 'TLI');
  v jsonb;
BEGIN
  v := pg_temp.call(v_uk, format('SELECT public.save_dating_identity(%L, ''non_binary'', NULL, NULL, NULL, false)', pg_temp.key('d5')));
  IF v IS DISTINCT FROM '{"ok": false, "reason": "not_available"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with dating_same_gender_matching off, the UK took a non-binary identity: %', v;
  END IF;
END $$;

-- =====================================================================
-- B. D2: intention, timeline, the attestation (re-asked on every change),
--    the enrolment and profile rows, the counters.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.person('03');
  v jsonb;
  v_started bigint := pg_temp.metric('dating.setup.started');
  v_k constant text := pg_temp.key('d2');
BEGIN
  IF pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''casual'', NULL, true, true, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "intention"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''committed'', ''few_years'', true, true, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "timeline"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''marriage'', ''soon'', true, true, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "timeline"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''marriage'', NULL, true, false, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "attestation"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''marriage'', NULL, true, true, ''separated'', false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "marital"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, NULL, NULL, true, true, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "intention"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, NULL, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "attestation"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D2 validation is wrong (intention enum, timeline only with marriage, attestation required, marital values)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_u) OR EXISTS (SELECT 1 FROM public.dating_enrollments WHERE user_id = v_u)
     OR EXISTS (SELECT 1 FROM public.dating_rpc_idempotency WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused D2 wrote a row or claimed its idempotency key';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''marriage'', ''within_two_years'', false, true, ''divorced'', true)', v_k));
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''marriage'', ''within_two_years'', false, true, ''divorced'', true)', v_k));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "where"}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.dating_enrollments WHERE user_id = v_u AND state = 'profile_draft')
     OR NOT EXISTS (SELECT 1 FROM public.dating_profiles
                     WHERE user_id = v_u AND intention = 'marriage' AND marriage_timeline = 'within_two_years'
                       AND NOT timeline_visible AND marital_visible AND attestation_version = '2026-10-v1'
                       AND not_married_attested_at IS NOT NULL AND display_name = 'Ama Person 03'
                       AND moderation_state = 'approved') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D2 did not create the enrolment and profile as answered: %', v;
  END IF;
  IF pg_temp.metric('dating.setup.started') IS DISTINCT FROM v_started + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating.setup.started was not counted once (a repeated key counts nothing)';
  END IF;
  IF position('divorced' IN encode((SELECT marital_enc FROM public.dating_profile_sensitive WHERE user_id = v_u), 'escape')) IS DISTINCT FROM 0
     OR private.dating_field_decrypt((SELECT marital_enc FROM public.dating_profile_sensitive WHERE user_id = v_u))
          IS DISTINCT FROM '{"marital": "divorced"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: marriage history is not stored encrypted';
  END IF;
  -- I-2: "show" with no marriage answer, or with "never", shows nothing,
  -- and is an answer, never a raised constraint error.
  BEGIN
    v := pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, true)', pg_temp.key('vis')));
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: D2 raised % for "show marriage history" with no answer', SQLSTATE;
  END;
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "where"}'::jsonb
     OR (SELECT marital_visible FROM public.dating_profiles WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D2 with no marriage answer did not save with marital_visible false: %', v;
  END IF;
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''marriage'', NULL, true, true, ''never'', true)', pg_temp.key('never')));
  IF (SELECT marital_visible FROM public.dating_profiles WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "never married" was shown on the profile';
  END IF;
END $$;

-- B2 (I-3, M-3). The default Dating name copied from the account name goes
-- through the content filter (contact details, slurs, explicit); a hit
-- falls back to "Me" (D12 asks); a cut name never ends in a space. The
-- first step that creates the profile counts dating.setup.started, D3 and
-- D7 included.
DO $$
DECLARE
  v_contact constant uuid := pg_temp.person('33');
  v_unkind constant uuid := pg_temp.person('34');
  v_long constant uuid := pg_temp.person('35');
  v_d7 constant uuid := pg_temp.person('36');
  v_d3 constant uuid := pg_temp.person('37');
  v_started bigint;
BEGIN
  UPDATE public.users SET display_name = 'Kofi 0244123456' WHERE id = v_contact;
  UPDATE public.users SET display_name = 'Ama zzwonecunkind' WHERE id = v_unkind;
  UPDATE public.users SET display_name = repeat('a', 29) || ' Mensah' WHERE id = v_long;
  PERFORM pg_temp.call(v_contact, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', pg_temp.key('d2')));
  PERFORM pg_temp.call(v_unkind, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', pg_temp.key('d2')));
  PERFORM pg_temp.call(v_long, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', pg_temp.key('d2')));
  IF (SELECT display_name FROM public.dating_profiles WHERE user_id = v_contact) IS DISTINCT FROM 'Me'
     OR (SELECT display_name FROM public.dating_profiles WHERE user_id = v_unkind) IS DISTINCT FROM 'Me' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the default Dating name was copied unfiltered (contact details or an unkind word)';
  END IF;
  IF (SELECT display_name FROM public.dating_profiles WHERE user_id = v_long) IS DISTINCT FROM repeat('a', 29) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the cut default name was not trimmed: %', (SELECT display_name FROM public.dating_profiles WHERE user_id = v_long);
  END IF;
  v_started := pg_temp.metric('dating.setup.started');
  IF pg_temp.call(v_d7, format('SELECT public.save_dating_children(%L, false, ''yes'', false, false)', pg_temp.key('d7')))
       IS DISTINCT FROM '{"ok": true, "next_step": "faith"}'::jsonb THEN
    RAISE EXCEPTION 'fixture: D7 first failed';
  END IF;
  IF pg_temp.metric('dating.setup.started') IS DISTINCT FROM v_started + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a setup started at D7 was not counted';
  END IF;
  IF pg_temp.call(v_d3, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''region'')', pg_temp.key('d3')))
       IS DISTINCT FROM '{"ok": true, "next_step": "privacy"}'::jsonb THEN
    RAISE EXCEPTION 'fixture: D3 first failed';
  END IF;
  IF pg_temp.metric('dating.setup.started') IS DISTINCT FROM v_started + 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a setup started at D3 was not counted';
  END IF;
END $$;

-- =====================================================================
-- C. D3: open countries and regions only; sides; scope; one country
--    change per 30 days, which asks D5 and D6 again.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.person('04');
  v jsonb;
BEGIN
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', pg_temp.key('d2')));
  IF pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''NG'', ''LA'', NULL, ''region'')', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "country_closed"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''TV'', NULL, ''region'')', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "region_closed"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''XX'', NULL, ''region'')', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "region"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', ''kumasi'', ''side'')', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "side"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''side'')', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "scope"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D3 accepted a closed country or region, a foreign side, or side scope without a side';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', ''tema'', ''side'')', pg_temp.key('d3')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "privacy"}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_u AND country_code = 'GH'
                      AND region_code = 'AA' AND side_code = 'tema' AND country_changed_at IS NULL)
     OR (SELECT region_scope || ':' || min_age || '-' || max_age FROM public.dating_preferences WHERE user_id = v_u) IS DISTINCT FROM 'side:25-35' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D3 did not save the place, the scope and the default ages: %', v;
  END IF;
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, true)', pg_temp.key('d5')));
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)', pg_temp.key('d6')));
  -- A move to the UK: allowed once, and D5 and D6 are asked again; the UK
  -- leaves "open to other countries".
  -- B8 I-2: and every other country where same-gender is off (NG, closed)
  -- goes, since gender and who-to-meet are unknown again; a same-gender-on
  -- country (IE, opened here with the flag on) stays.
  PERFORM public.publish_country_config('IE', '{"dating_enabled": true, "same_gender_enabled": true}');
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  UPDATE public.dating_preferences SET open_abroad = '{GB,IE,NG}' WHERE user_id = v_u;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GB'', ''TLI'', NULL, ''region'')', pg_temp.key('d3b')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "privacy"}'::jsonb
     OR (SELECT identity_enc IS NOT NULL OR seeking_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_u)
     OR (SELECT gender_visible OR country_changed_at IS NULL FROM public.dating_profiles WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a country change kept the gender and who-to-meet answers: %', v;
  END IF;
  IF (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_u) IS DISTINCT FROM '{IE}'::char(2)[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the new Dating country stayed in open_abroad: %', (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_u);
  END IF;
  -- W1d: the flag goes off after the check (turning it off is the kill
  -- switch, which takes IE out of this not-plain person's list too).
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  IF pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''region'')', pg_temp.key('d3c')))
       IS DISTINCT FROM '{"ok": false, "reason": "country_change_limited"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second country change within 30 days was allowed';
  END IF;
  UPDATE public.dating_profiles SET country_changed_at = now() - interval '29 days' WHERE user_id = v_u;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''region'')', pg_temp.key('d3d')))
       IS DISTINCT FROM '{"ok": false, "reason": "country_change_limited"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a country change 29 days after the last was allowed';
  END IF;
  UPDATE public.dating_profiles SET country_changed_at = now() - interval '31 days' WHERE user_id = v_u;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''region'')', pg_temp.key('d3e')))
       IS DISTINCT FROM '{"ok": true, "next_step": "privacy"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a country change 31 days after the last was refused';
  END IF;
END $$;

-- =====================================================================
-- D. D5-D6 where same-gender is on (the UK, flag on): the full set;
--    "Everyone" stored explicitly; the D4 consent is required.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('05', 'GB', 'TLD');
  v_noconsent constant uuid := pg_temp.located('06', 'GB', 'TLD');
  v jsonb;
  v_before text;
BEGIN
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  v := pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''non_binary'', ''Two spirit'', ''they/them'', ARRAY[''woman'', ''man'', ''woman''], true)', pg_temp.key('d5')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "meet"}'::jsonb
     OR private.dating_field_decrypt((SELECT identity_enc FROM public.dating_profile_sensitive WHERE user_id = v_u))
          IS DISTINCT FROM '{"identity": "non_binary", "specific": null, "specific_text": "Two spirit", "pronouns": "they/them", "pools": ["non_binary", "man", "woman"]}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the UK refused or mis-stored a non-binary identity: %', v;
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, ARRAY[''man''], false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "pools"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', ''123'', NULL, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "specific"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''other'', NULL, NULL, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "identity"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, NULL, NULL, NULL, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "identity"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D5 validation is wrong';
  END IF;
  -- PF-F7: pronouns are letters, '/', space and hyphen; the specific term
  -- and the pronouns go through the content filter after the off-country
  -- refusal and the validation; a hit (contact_details, unkind) stores,
  -- claims and counts nothing.
  v_before := pg_temp.snapshot(v_u);
  IF pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, ''she/her 2'', NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "pronouns"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, ''she.her'', NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "pronouns"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, ''she_her'', NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "pronouns"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, '' / '', NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "pronouns"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', ''zero two four four one two'', ''three four five six'', NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "contact_details"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''non_binary'', ''zzwonecunkind'', NULL, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "unkind"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, ''zzwonecunkind'', NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "unkind"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D5 free text was not validated or filtered (pronouns letters, slash, space, hyphen; contact_details; unkind)';
  END IF;
  IF pg_temp.snapshot(v_u) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a filtered or invalid D5 answer stored, claimed or counted something';
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''non_binary'', ''Two-spirit'', ''xe / xem'', NULL, true)', pg_temp.key('d5b')))
       IS DISTINCT FROM '{"ok": true, "next_step": "meet"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clean D5 free text (letters, slash, space, hyphen) was refused';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman'', ''non_binary'', ''man''], 18, 99)', pg_temp.key('d6')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "children"}'::jsonb
     OR private.dating_field_decrypt((SELECT seeking_enc FROM public.dating_profile_sensitive WHERE user_id = v_u))
          IS DISTINCT FROM '{"seeking": ["man", "non_binary", "woman"]}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "Everyone" was not stored as the explicit full set: %', v;
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman'', ''man''], 25, 35)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "seeking"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman''], 17, 35)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "ages"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman''], 40, 30)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "ages"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman''], 30, 100)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "ages"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, NULL, 25, 35)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "seeking"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[NULL]::text[], 25, 35)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "seeking"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman''], NULL, 35)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "ages"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D6 accepted a partial set or an age outside 18-99';
  END IF;
  -- Same-gender is never NULL (Task 13's kill switch reads it in a WHERE).
  IF private.dating_same_gender_on('GB') IS DISTINCT FROM true OR private.dating_same_gender_on('GH') IS DISTINCT FROM false
     OR private.dating_same_gender_on('XX') IS DISTINCT FROM false OR private.dating_same_gender_on(NULL) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_same_gender_on is not a plain true or false';
  END IF;
  IF private.dating_default_ages(18) IS DISTINCT FROM ARRAY[18, 25] OR private.dating_default_ages(20) IS DISTINCT FROM ARRAY[18, 27]
     OR private.dating_default_ages(21) IS DISTINCT FROM ARRAY[18, 26] OR private.dating_default_ages(40) IS DISTINCT FROM ARRAY[35, 45]
     OR private.dating_default_ages(97) IS DISTINCT FROM ARRAY[92, 99] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the default age ranges are wrong';
  END IF;
  -- Without the D4 consent, D5 and D6 write nothing.
  DELETE FROM public.dating_consent_events WHERE user_id = v_noconsent AND purpose = 'special_category_profile';
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_noconsent, 'consent-withdrawn', 'special_category_profile', 'withdrawn', 'dating-2.0', clock_timestamp());
  IF pg_temp.call(v_noconsent, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "consent_required"}'::jsonb
     OR pg_temp.call(v_noconsent, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "consent_required"}'::jsonb
     OR (SELECT identity_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_noconsent) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a special-category answer was saved without the special_category_profile consent';
  END IF;
  -- I-4 (provisional, counsel confirms): marriage history is not Art. 9, so
  -- D2 saves it before (and without) the D4 consent; still encrypted.
  v := pg_temp.call(v_noconsent, format('SELECT public.save_dating_intention(%L, ''marriage'', NULL, true, true, ''widowed'', true)', pg_temp.key('d2i4')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "where"}'::jsonb
     OR private.dating_field_decrypt((SELECT marital_enc FROM public.dating_profile_sensitive WHERE user_id = v_noconsent))
          IS DISTINCT FROM '{"marital": "widowed"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D2 refused marriage history without the special_category_profile consent (I-4): %', v;
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
END $$;

-- =====================================================================
-- E. D7 (no "seek parents" anywhere) and D8 (the country's list, both
--    consents, "must share" stored, Skip clears).
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('07', 'GH', 'AH');
  v jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname ~ '^save_dating_' AND pg_get_function_arguments(oid) ~* 'seek.*parent|parent.*seek') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a setup writer offers seeking parents (10 S22)';
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_children(%L, NULL, ''yes'', false, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "have"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_children(%L, true, ''maybe'', false, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "want"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D7 validation is wrong';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_children(%L, true, ''open'', true, true)', pg_temp.key('d7')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "faith"}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_u AND children_have AND children_want = 'open')
     OR NOT EXISTS (SELECT 1 FROM public.dating_preferences WHERE user_id = v_u AND want_must_match AND exclude_parents) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D7 was not saved: %', v;
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''hindu'', NULL, ''must_share'', false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "faith"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''muslim'', ''catholic'', ''must_share'', false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "denomination"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''christian'', NULL, ''a lot'', false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "importance"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D8 accepted a faith outside the country''s list, a foreign denomination or an unknown importance';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''christian'', ''catholic'', ''must_share'', true)', pg_temp.key('d8')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "photos"}'::jsonb
     OR private.dating_field_decrypt((SELECT faith_enc FROM public.dating_profile_sensitive WHERE user_id = v_u))
          IS DISTINCT FROM '{"faith": "christian", "denomination": "catholic", "importance": "must_share"}'::jsonb
     OR NOT (SELECT faith_visible FROM public.dating_profiles WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "must share" was not stored: %', v;
  END IF;
  -- Without the special_category_profile consent (the faith one granted): refused.
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'consent-profile-withdrawn', 'special_category_profile', 'withdrawn', 'dating-2.0', clock_timestamp());
  IF pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''muslim'', NULL, ''nice_to_share'', false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "consent_required"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: faith was saved without the special_category_profile consent';
  END IF;
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'consent-profile-regranted', 'special_category_profile', 'granted', 'dating-2.0', clock_timestamp());
  -- Without the faith consent: refused.
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'consent-faith-withdrawn', 'special_category_faith', 'withdrawn', 'dating-2.0', clock_timestamp());
  IF pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''muslim'', NULL, ''nice_to_share'', false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "consent_required"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: faith was saved without the special_category_faith consent';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.clear_dating_faith(%L)', pg_temp.key('d8skip')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "photos"}'::jsonb
     OR (SELECT faith_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_u)
     OR (SELECT faith_visible FROM public.dating_profiles WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Skip left a faith answer stored';
  END IF;
END $$;

-- =====================================================================
-- E3. Skip is never gated (W1 B7 ruling, I-1): removing one's own faith
--     answer works when the country has closed and under a restriction.
-- =====================================================================
DO $$
DECLARE
  v_closed constant uuid := pg_temp.located('39', 'GH', 'AA');
  v_restricted constant uuid := pg_temp.located('40', 'GH', 'AA');
  v_x uuid;
  v jsonb;
BEGIN
  FOREACH v_x IN ARRAY ARRAY[v_closed, v_restricted] LOOP
    IF pg_temp.call(v_x, format('SELECT public.save_dating_faith(%L, ''christian'', NULL, ''must_share'', true)', pg_temp.key('d8')))
         IS DISTINCT FROM '{"ok": true, "next_step": "photos"}'::jsonb THEN
      RAISE EXCEPTION 'fixture: D8 failed';
    END IF;
  END LOOP;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_restricted, 'suspended');
  IF public.dating_eligibility(v_restricted, 'setup') IS NOT DISTINCT FROM 'eligible' THEN
    RAISE EXCEPTION 'fixture: the restricted person is still eligible';
  END IF;
  v := pg_temp.call(v_restricted, format('SELECT public.clear_dating_faith(%L)', pg_temp.key('skip')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "photos"}'::jsonb
     OR (SELECT faith_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_restricted) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restricted person could not remove their faith answer: %', v;
  END IF;
  PERFORM public.publish_country_config('GH', '{"dating_enabled": false}');
  v := pg_temp.call(v_closed, format('SELECT public.clear_dating_faith(%L)', pg_temp.key('skip')));
  PERFORM public.publish_country_config('GH', '{"dating_enabled": true}');
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "photos"}'::jsonb
     OR (SELECT faith_enc IS NOT NULL OR faith_visible FROM public.dating_profile_sensitive JOIN public.dating_profiles USING (user_id)
          WHERE user_id = v_closed) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the country closed, Skip did not remove the faith answer: %', v;
  END IF;
END $$;

-- =====================================================================
-- E2. private.dating_clear_faith (PF-F3, owner 2026-11-06; Task 12's
--     faith-only withdrawal calls it): the faith answer and what matching
--     derives from it, nothing else, that person only, no API role.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('08', 'GH', 'AA');
  v_other constant uuid := pg_temp.located('09', 'GH', 'AA');
  v_rest text;
  v_other_before text;
  v_x uuid;
BEGIN
  FOREACH v_x IN ARRAY ARRAY[v_u, v_other] LOOP
    PERFORM pg_temp.call(v_x, format('SELECT public.save_dating_intention(%L, ''marriage'', NULL, true, true, ''divorced'', true)', pg_temp.key('d2f')));
    PERFORM pg_temp.call(v_x, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, true)', pg_temp.key('d5f')));
    PERFORM pg_temp.call(v_x, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)', pg_temp.key('d6f')));
    PERFORM pg_temp.call(v_x, format('SELECT public.save_dating_children(%L, false, ''yes'', true, false)', pg_temp.key('d7f')));
    IF pg_temp.call(v_x, format('SELECT public.save_dating_faith(%L, ''muslim'', NULL, ''nice_to_share'', true)', pg_temp.key('d8f')))
         IS DISTINCT FROM '{"ok": true, "next_step": "photos"}'::jsonb THEN
      RAISE EXCEPTION 'fixture: D8 failed';
    END IF;
  END LOOP;
  -- Everything except the faith answer and its visibility (and the row's
  -- bookkeeping: updated_at, profile_version).
  SELECT md5(concat_ws('|',
      (SELECT to_jsonb(p) - ARRAY['updated_at', 'profile_version', 'faith_visible'] FROM public.dating_profiles AS p WHERE p.user_id = v_u),
      (SELECT encode(s.identity_enc, 'hex') || encode(s.seeking_enc, 'hex') || encode(s.marital_enc, 'hex') || s.key_version
         FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_u),
      (SELECT to_jsonb(d) - 'updated_at' FROM public.dating_preferences AS d WHERE d.user_id = v_u),
      (SELECT to_jsonb(e) - ARRAY['updated_at', 'state_version'] FROM public.dating_enrollments AS e WHERE e.user_id = v_u),
      (SELECT count(*) FROM public.dating_consent_events AS c WHERE c.user_id = v_u),
      (SELECT count(*) FROM public.dating_rpc_idempotency AS i WHERE i.user_id = v_u)))
    INTO v_rest;
  v_other_before := pg_temp.snapshot(v_other);
  PERFORM private.dating_clear_faith(v_u);
  PERFORM private.dating_clear_faith(NULL);
  IF (SELECT faith_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_u)
     OR (SELECT faith_visible FROM public.dating_profiles WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_clear_faith left the faith answer or its visibility';
  END IF;
  IF md5(concat_ws('|',
      (SELECT to_jsonb(p) - ARRAY['updated_at', 'profile_version', 'faith_visible'] FROM public.dating_profiles AS p WHERE p.user_id = v_u),
      (SELECT encode(s.identity_enc, 'hex') || encode(s.seeking_enc, 'hex') || encode(s.marital_enc, 'hex') || s.key_version
         FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_u),
      (SELECT to_jsonb(d) - 'updated_at' FROM public.dating_preferences AS d WHERE d.user_id = v_u),
      (SELECT to_jsonb(e) - ARRAY['updated_at', 'state_version'] FROM public.dating_enrollments AS e WHERE e.user_id = v_u),
      (SELECT count(*) FROM public.dating_consent_events AS c WHERE c.user_id = v_u),
      (SELECT count(*) FROM public.dating_rpc_idempotency AS i WHERE i.user_id = v_u))) IS DISTINCT FROM v_rest THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_clear_faith changed something other than the faith answer';
  END IF;
  IF pg_temp.snapshot(v_other) IS DISTINCT FROM v_other_before
     OR (SELECT faith_enc IS NULL OR NOT p.faith_visible FROM public.dating_profile_sensitive AS s
           JOIN public.dating_profiles AS p USING (user_id) WHERE s.user_id = v_other) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_clear_faith touched another person''s answers';
  END IF;
  IF has_function_privilege('authenticated', 'private.dating_clear_faith(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'private.dating_clear_faith(uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.dating_clear_faith(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an API role can run dating_clear_faith';
  END IF;
END $$;

-- =====================================================================
-- F0. (B8 fix round 1, I-3) A bystander with every Task 10 row: no writer
--    or reader in F to L touches another person's rows (checked after H3
--    and after L).
-- =====================================================================
CREATE TEMP TABLE bystander (user_id uuid, rows text);
DO $$
DECLARE
  v_b constant uuid := pg_temp.ready('73', 'GH', 'AA', 'woman', ARRAY['man']);
  v jsonb := '[]'::jsonb;
BEGIN
  v := v || jsonb_build_array(pg_temp.call(v_b, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('d10'),
         '[{"prompt_id": "feel_at_home", "answer": "Sunday lunch with everyone."}, {"prompt_id": "small_thing", "answer": "Fresh bread, warm."}]')));
  v := v || jsonb_build_array(pg_temp.call(v_b, format('SELECT public.save_dating_display_name(%L, ''Efua'')', pg_temp.key('d12'))));
  v := v || jsonb_build_array(pg_temp.call(v_b, format('SELECT public.save_dating_family_involvement(%L, ''early'')', pg_temp.key('f'))));
  v := v || jsonb_build_array(pg_temp.call(v_b, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('s'),
         '{"drop_time": "20:30", "digest_push": true, "show_when_away": true}')));
  v := v || jsonb_build_array(pg_temp.call(v_b, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])', pg_temp.key('ab'))));
  v := v || jsonb_build_array(pg_temp.call(v_b, format('SELECT public.set_dating_photos_after_mutual(%L, true)', pg_temp.key('pm'))));
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v) AS e WHERE e ->> 'ok' IS DISTINCT FROM 'true') THEN
    RAISE EXCEPTION 'fixture: the bystander''s steps failed: %', v;
  END IF;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state)
  VALUES (v_b, 'dating-photos/' || md5('bystander') || '.jpg', 1, 'approved');
  INSERT INTO bystander VALUES (v_b, pg_temp.rows_of(v_b));
END $$;
-- A second bystander with the opposite values (photos after mutual off,
-- settings at their defaults, no other countries), so a mass write of
-- either value shows.
DO $$
DECLARE
  v_c constant uuid := pg_temp.ready('92', 'GH', 'AA', 'man', ARRAY['woman']);
BEGIN
  IF pg_temp.call(v_c, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('s'), '{"drop_time": "19:00"}'))
       IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'fixture: the second bystander''s settings failed';
  END IF;
  INSERT INTO bystander VALUES (v_c, pg_temp.rows_of(v_c));
END $$;

-- =====================================================================
-- F. D10 prompts (both filters) and D12 the name.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('48', 'GH', 'AA');
  v jsonb;
BEGIN
  IF pg_temp.call(v_u, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('x'),
         '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof with my sisters."}]'))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "prompts"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('x'),
         '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}, {"prompt_id": "perfect_sunday", "answer": "Again the same one."}]'))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "prompts"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('x'),
         '[{"prompt_id": "perfect_sunday", "answer": "Church."}, {"prompt_id": "ask_me_about", "answer": "My grandmother''s garden."}]'))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "answer", "position": 1}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('x'),
         '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}, {"prompt_id": "ask_me_about", "answer": "Call me on 024 412 3456 any time"}]'))
       IS DISTINCT FROM '{"ok": false, "reason": "contact_details", "position": 2}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D10 accepted one prompt, a repeated prompt, a short answer or contact details';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('d10'),
         '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}, {"prompt_id": "ask_me_about", "answer": "  My grandmother''s garden.  "}]'));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "verify"}'::jsonb
     OR (SELECT string_agg(prompt_id || '=' || answer, ';' ORDER BY position) FROM public.dating_prompts WHERE user_id = v_u)
          IS DISTINCT FROM 'perfect_sunday=Church, then jollof.;ask_me_about=My grandmother''s garden.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D10 did not save the answers: %', v;
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('x'), '   '))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "name"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('x'), repeat('a', 31)))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "name"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('x'), 'Ama 0244123456'))
       IS DISTINCT FROM '{"ok": false, "reason": "contact_details"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D12 name rules are wrong (1-30 characters, no contact details)';
  END IF;
  -- Names in any script count characters, not bytes: Arabic and an emoji
  -- name fit; 31 characters don't.
  v := pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('ar'), U&'\0623\0645\064A\0646\0629'));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "preview"}'::jsonb
     OR (SELECT display_name FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM U&'\0623\0645\064A\0646\0629' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an Arabic first name was refused: %', v;
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('em'), 'Kofi ' || U&'\+01F33B'))
       IS DISTINCT FROM '{"ok": true, "next_step": "preview"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('x'), repeat(U&'\0623', 31)))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "name"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a name was measured in bytes, not characters';
  END IF;
  -- (One statement sees one snapshot: the write and its read are separate.)
  v := pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('d12'), ' Ama '));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "preview"}'::jsonb
     OR (SELECT display_name FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM 'Ama' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D12 did not save the trimmed name: %', v;
  END IF;
END $$;
-- =====================================================================
-- F2. (Batch 8 rulings) D10 and D12 refuse malformed input as invalid and
--    never raise (B7: no constraint error may echo input); a slur is
--    unkind; the name goes through every filter family (as Task 9's
--    default name), and no control character; a refusal writes nothing; a
--    step that starts a setup is counted.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('51', 'GH', 'AA');
  v_ok constant text := '{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}';
  v_before text;
  v jsonb;
  v_case text[];
  v_cases constant text[] := ARRAY[
    ['NULL', '{"ok": false, "reason": "invalid", "field": "prompts"}'],
    ['''{"prompt_id": "perfect_sunday"}''', '{"ok": false, "reason": "invalid", "field": "prompts"}'],
    ['''"Church, then jollof."''', '{"ok": false, "reason": "invalid", "field": "prompts"}'],
    ['''[1, 2]''', '{"ok": false, "reason": "invalid", "field": "prompts"}'],
    ['''[null, null]''', '{"ok": false, "reason": "invalid", "field": "prompts"}'],
    [quote_literal('[' || v_ok || ', {"prompt_id": "favourite_film", "answer": "Something long enough."}]'), '{"ok": false, "reason": "invalid", "field": "prompts"}'],
    [quote_literal('[' || v_ok || ', {"answer": "Something long enough."}]'), '{"ok": false, "reason": "invalid", "field": "prompts"}'],
    [quote_literal('[' || v_ok || ', {"prompt_id": ["ask_me_about"], "answer": "Something long enough."}]'), '{"ok": false, "reason": "invalid", "field": "prompts"}'],
    [quote_literal('[' || v_ok || ', {"prompt_id": "ask_me_about", "answer": "Something long."}, {"prompt_id": "place_love", "answer": "Something long."}, {"prompt_id": "small_thing", "answer": "Something long."}]'), '{"ok": false, "reason": "invalid", "field": "prompts"}'],
    [quote_literal('[' || v_ok || ', {"prompt_id": "ask_me_about", "answer": 12345678901}]'), '{"ok": false, "reason": "invalid", "field": "answer", "position": 2}'],
    [quote_literal('[' || v_ok || ', {"prompt_id": "ask_me_about", "answer": ["My grandmother''s garden."]}]'), '{"ok": false, "reason": "invalid", "field": "answer", "position": 2}'],
    [quote_literal('[' || v_ok || ', {"prompt_id": "ask_me_about", "answer": null}]'), '{"ok": false, "reason": "invalid", "field": "answer", "position": 2}'],
    [quote_literal('[' || v_ok || ', {"prompt_id": "ask_me_about"}]'), '{"ok": false, "reason": "invalid", "field": "answer", "position": 2}'],
    [quote_literal('[' || v_ok || ', {"prompt_id": "ask_me_about", "answer": "   short     "}]'), '{"ok": false, "reason": "invalid", "field": "answer", "position": 2}'],
    [quote_literal('[' || v_ok || ', {"prompt_id": "ask_me_about", "answer": "' || repeat('a', 201) || '"}]'), '{"ok": false, "reason": "invalid", "field": "answer", "position": 2}'],
    [quote_literal('[{"prompt_id": "ask_me_about", "answer": "' || repeat('a', 5000) || '"}, ' || v_ok || ']'), '{"ok": false, "reason": "invalid", "field": "answer", "position": 1}'],
    [quote_literal('[' || v_ok || ', {"prompt_id": "ask_me_about", "answer": "Ask me about zzwonecunkind things"}]'), '{"ok": false, "reason": "unkind", "position": 2}'],
    [quote_literal('[{"prompt_id": "ask_me_about", "answer": "WhatsApp me: zero two four four one two three four five six"}, ' || v_ok || ']'), '{"ok": false, "reason": "contact_details", "position": 1}'],
    -- Fix round 1 (M-1): Unicode spaces only, no letter or digit, a bidi override.
    [quote_literal('[' || v_ok || ', {"prompt_id": "ask_me_about", "answer": "' || repeat(U&'\00A0', 12) || '"}]'), '{"ok": false, "reason": "invalid", "field": "answer", "position": 2}'],
    [quote_literal('[' || v_ok || ', {"prompt_id": "ask_me_about", "answer": "' || U&'\3000\3000short\3000\3000\3000\3000' || '"}]'), '{"ok": false, "reason": "invalid", "field": "answer", "position": 2}'],
    [quote_literal('[' || v_ok || ', {"prompt_id": "ask_me_about", "answer": "' || repeat('.', 12) || '"}]'), '{"ok": false, "reason": "invalid", "field": "answer", "position": 2}'],
    [quote_literal('[' || v_ok || ', {"prompt_id": "ask_me_about", "answer": "' || U&'Ask me about \202Eanything' || '"}]'), '{"ok": false, "reason": "invalid", "field": "answer", "position": 2}']];
  v_prompts text;
  v_name text;
  v_fresh uuid;
  v_n int := 60;
  v_start bigint;
  v_step text;
BEGIN
  IF pg_temp.call(v_u, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('d10'),
       '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}, {"prompt_id": "ask_me_about", "answer": "My grandmother''s garden."}, {"prompt_id": "place_love", "answer": "The beach at Busua."}]'))
       IS DISTINCT FROM '{"ok": true, "next_step": "verify"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('d12'), 'Esi'))
       IS DISTINCT FROM '{"ok": true, "next_step": "preview"}'::jsonb THEN
    RAISE EXCEPTION 'fixture: F2 could not save three prompts and a name';
  END IF;
  -- Saving two after three replaces them all (never a third left behind).
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('d10'),
       '[{"prompt_id": "place_love", "answer": "The beach at Busua."}, {"prompt_id": "small_thing", "answer": "Fresh bread, warm."}]'));
  IF (SELECT string_agg(position || prompt_id, ';' ORDER BY position) FROM public.dating_prompts WHERE user_id = v_u)
       IS DISTINCT FROM '1place_love;2small_thing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D10 kept an old answer next to the new ones';
  END IF;
  v_prompts := (SELECT string_agg(position || prompt_id || answer || moderation_state, ';' ORDER BY position) FROM public.dating_prompts WHERE user_id = v_u);
  v_before := pg_temp.snapshot(v_u);
  FOREACH v_case SLICE 1 IN ARRAY v_cases LOOP
    BEGIN
      v := pg_temp.call(v_u, format('SELECT public.save_dating_prompts(%L, %s)', pg_temp.key('f2'), v_case[1]));
    EXCEPTION WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: D10 raised (% %) for %', SQLSTATE, SQLERRM, left(v_case[1], 80);
    END;
    IF v IS DISTINCT FROM v_case[2]::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: D10 answered % for %, expected %', v, left(v_case[1], 80), v_case[2];
    END IF;
  END LOOP;
  IF pg_temp.snapshot(v_u) IS DISTINCT FROM v_before
     OR (SELECT string_agg(position || prompt_id || answer || moderation_state, ';' ORDER BY position) FROM public.dating_prompts WHERE user_id = v_u)
          IS DISTINCT FROM v_prompts THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused D10 answer changed a row, a claim or a counter';
  END IF;

  -- D12: NULL, control characters, an unkind word (every filter family).
  FOREACH v_case SLICE 1 IN ARRAY ARRAY[
      ['NULL', '{"ok": false, "reason": "invalid", "field": "name"}'],
      [quote_literal(E'Esi\nKofi'), '{"ok": false, "reason": "invalid", "field": "name"}'],
      [quote_literal(E'Esi\tA'), '{"ok": false, "reason": "invalid", "field": "name"}'],
      [quote_literal(repeat('x', 5000)), '{"ok": false, "reason": "invalid", "field": "name"}'],
      ['''zzwonecunkind''', '{"ok": false, "reason": "unkind"}'],
      ['''Esi zzwonecunkind''', '{"ok": false, "reason": "unkind"}'],
      ['''Esi esi@example.com''', '{"ok": false, "reason": "contact_details"}'],
      -- Fix round 1 (M-1): Unicode spaces only, invisible or bidi controls, no letter.
      [quote_literal(U&'\3000'), '{"ok": false, "reason": "invalid", "field": "name"}'],
      [quote_literal(U&'\00A0\00A0'), '{"ok": false, "reason": "invalid", "field": "name"}'],
      [quote_literal(U&'Esi\202E'), '{"ok": false, "reason": "invalid", "field": "name"}'],
      [quote_literal(U&'E\200Bsi'), '{"ok": false, "reason": "invalid", "field": "name"}'],
      [quote_literal(U&'\2067Esi'), '{"ok": false, "reason": "invalid", "field": "name"}'],
      [quote_literal(U&'\+01F33B'), '{"ok": false, "reason": "invalid", "field": "name"}'],
      ['''123''', '{"ok": false, "reason": "invalid", "field": "name"}']] LOOP
    BEGIN
      v := pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %s)', pg_temp.key('f2'), v_case[1]));
    EXCEPTION WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: D12 raised (% %) for %', SQLSTATE, SQLERRM, left(v_case[1], 80);
    END;
    IF v IS DISTINCT FROM v_case[2]::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: D12 answered % for %, expected %', v, left(v_case[1], 80), v_case[2];
    END IF;
  END LOOP;
  IF pg_temp.snapshot(v_u) IS DISTINCT FROM v_before
     OR (SELECT display_name FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM 'Esi' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused D12 name changed a row, a claim or a counter';
  END IF;
  -- 30 characters after trimming fits (the guard trigger's rule).
  IF pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('f2'), '  ' || repeat('b', 30) || '  '))
       IS DISTINCT FROM '{"ok": true, "next_step": "preview"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 30-character name (padded) was refused';
  END IF;
  -- M-1: Unicode spaces are trimmed like ASCII ones.
  v := pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('f2'), U&'\00A0Esi\3000'));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "preview"}'::jsonb
     OR (SELECT display_name FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM 'Esi' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a name padded with Unicode spaces was refused or stored untrimmed: %', v;
  END IF;

  -- A step that starts a setup is counted (as D2, D3, D7, D8): D10, D12,
  -- the family question and photos after mutual interest each start one.
  FOREACH v_step IN ARRAY ARRAY[
      format('SELECT public.save_dating_prompts(%%L, %L)', '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}, {"prompt_id": "ask_me_about", "answer": "My grandmother''s garden."}]'),
      'SELECT public.save_dating_display_name(%L, ''Abena'')',
      'SELECT public.save_dating_family_involvement(%L, ''when_serious'')',
      -- (Turning photos after mutual interest ON reduces exposure: it never
      -- starts a setup, B8 I-1; OFF is the full step.)
      'SELECT public.set_dating_photos_after_mutual(%L, false)'] LOOP
    v_n := v_n + 1;
    v_fresh := pg_temp.person(v_n::text);
    v_start := pg_temp.metric('dating.setup.started');
    v := pg_temp.call(v_fresh, format(v_step, pg_temp.key('st')));
    IF (v ->> 'ok')::boolean IS NOT TRUE OR NOT EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_fresh) THEN
      RAISE EXCEPTION 'fixture: a first step failed: % (%)', v, v_step;
    END IF;
    IF pg_temp.metric('dating.setup.started') IS DISTINCT FROM v_start + 1 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a setup started at % was not counted', left(v_step, 50);
    END IF;
  END LOOP;
END $$;
-- =====================================================================
-- G. Settings; other countries (verified and 14+ days only); photos
--    after mutual interest (from day 30); the family question.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('49', 'GH', 'AA');
  v_new constant uuid := pg_temp.person('50', 30, 5);
  v jsonb;
BEGIN
  IF pg_temp.call(v_u, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('x'), '{"drop_time": "06:30"}'))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "drop_time"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('x'), '{"drop_time": "19:15"}'))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "drop_time"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('x'), '{"theme": "dark"}'))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "settings"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: settings accepted a time outside 07:00-22:00 in 30-minute steps, or an unknown key';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('s'), '{"drop_time": "21:30", "digest_push": true}'));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT drop_time::text || digest_push::text || chat_push::text FROM public.dating_settings WHERE user_id = v_u) IS DISTINCT FROM '21:30:00truetrue' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: settings were not saved: %', v;
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "not_yet"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GH'']::char(2)[])', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "countries"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''NG'']::char(2)[])', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "countries"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: other countries were allowed before verification, or for one''s own or a closed country';
  END IF;
  UPDATE public.dating_profiles SET verification_state = 'verified' WHERE user_id = v_u;
  INSERT INTO public.dating_age_verifications (user_id, birth_date, verification_method, verified_at)
  VALUES (v_u, current_date - interval '30 years', 'contract', now());
  -- (B8 I-2: a plain profile, woman meeting men; the UK is same-gender off
  -- here, with the global flag off.)
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, false)', pg_temp.key('d5')));
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)', pg_temp.key('d6')));
  v := pg_temp.call(v_u, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''gb'']::char(2)[])', pg_temp.key('ab')));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_u) IS DISTINCT FROM ARRAY['GB']::char(2)[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a verified 40-day account could not open to the UK';
  END IF;
  IF pg_temp.call(v_new, format('SELECT public.set_dating_photos_after_mutual(%L, true)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "not_yet"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.set_dating_photos_after_mutual(%L, true)', pg_temp.key('pm')))
       IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photos after mutual interest is wrong before or after account day 30';
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_family_involvement(%L, ''soon'')', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "family_involvement"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_family_involvement(%L, ''early'')', pg_temp.key('f')))
       IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the family question is wrong';
  END IF;
END $$;
-- =====================================================================
-- G2. (Batch 8 rulings) Settings, other countries and photos after
--    mutual interest refuse malformed input as invalid and never raise;
--    NULL is never an answer; the time limits hold at their edges; a
--    refusal writes nothing.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('52', 'GH', 'AA');
  v_young constant uuid := pg_temp.located('53', 'GH', 'AA');
  v_case text[];
  v jsonb;
  v_settings text;
  v_before text;
  v_x uuid;
  v_k text;
BEGIN
  IF pg_temp.call(v_u, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('s'), '{"drop_time": "07:00", "data_saver": true}'))
       IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('s'), '{"chat_push": false}'))
       IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 07:00 or a partial settings save was refused';
  END IF;
  -- (One statement sees one snapshot: the writes and their read are separate.)
  IF (SELECT drop_time::text || data_saver::text || chat_push::text || digest_push::text || show_when_away::text
        FROM public.dating_settings WHERE user_id = v_u) IS DISTINCT FROM '07:00:00truefalsefalsefalse' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a partial settings save changed the keys it did not name';
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('s'), '{"drop_time": "22:00"}'))
       IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the last drop time, 22:00, was refused';
  END IF;
  IF (SELECT drop_time::text || data_saver::text || chat_push::text || digest_push::text || show_when_away::text
        FROM public.dating_settings WHERE user_id = v_u) IS DISTINCT FROM '22:00:00truefalsefalsefalse' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: saving the drop time alone reset another setting';
  END IF;
  -- M-3: a used key replayed with other values changes nothing.
  v_k := pg_temp.key('rp');
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_settings(%L, %L)', v_k, '{"drop_time": "21:00"}'));
  v := pg_temp.call(v_u, format('SELECT public.save_dating_settings(%L, %L)', v_k, '{"drop_time": "08:00"}'));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT to_char(drop_time, 'HH24:MI') FROM public.dating_settings WHERE user_id = v_u) IS DISTINCT FROM '21:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed settings key wrote again: %', v;
  END IF;
  v_settings := (SELECT to_jsonb(s)::text FROM public.dating_settings AS s WHERE s.user_id = v_u);
  v_before := pg_temp.snapshot(v_u);
  FOREACH v_case SLICE 1 IN ARRAY ARRAY[
      ['NULL', '{"ok": false, "reason": "invalid", "field": "settings"}'],
      ['''[]''', '{"ok": false, "reason": "invalid", "field": "settings"}'],
      ['''"drop_time"''', '{"ok": false, "reason": "invalid", "field": "settings"}'],
      ['''{"data_saver": "yes"}''', '{"ok": false, "reason": "invalid", "field": "settings"}'],
      ['''{"data_saver": null}''', '{"ok": false, "reason": "invalid", "field": "settings"}'],
      ['''{"chat_push": 1}''', '{"ok": false, "reason": "invalid", "field": "settings"}'],
      [quote_literal(jsonb_build_object(repeat('k', 5000), true)::text), '{"ok": false, "reason": "invalid", "field": "settings"}'],
      ['''{"drop_time": null}''', '{"ok": false, "reason": "invalid", "field": "drop_time"}'],
      ['''{"drop_time": 1930}''', '{"ok": false, "reason": "invalid", "field": "drop_time"}'],
      ['''{"drop_time": "22:30"}''', '{"ok": false, "reason": "invalid", "field": "drop_time"}'],
      ['''{"drop_time": "06:30"}''', '{"ok": false, "reason": "invalid", "field": "drop_time"}'],
      ['''{"drop_time": "19:00:30"}''', '{"ok": false, "reason": "invalid", "field": "drop_time"}'],
      ['''{"drop_time": "7:00"}''', '{"ok": false, "reason": "invalid", "field": "drop_time"}'],
      [quote_literal(jsonb_build_object('drop_time', repeat('1', 5000))::text), '{"ok": false, "reason": "invalid", "field": "drop_time"}'],
      ['''{"drop_time": "19:30", "theme": "dark"}''', '{"ok": false, "reason": "invalid", "field": "settings"}']] LOOP
    BEGIN
      v := pg_temp.call(v_u, format('SELECT public.save_dating_settings(%L, %s)', pg_temp.key('g2'), v_case[1]));
    EXCEPTION WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: settings raised (% %) for %', SQLSTATE, SQLERRM, left(v_case[1], 80);
    END;
    IF v IS DISTINCT FROM v_case[2]::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: settings answered % for %, expected %', v, left(v_case[1], 80), v_case[2];
    END IF;
  END LOOP;
  IF (SELECT to_jsonb(s)::text FROM public.dating_settings AS s WHERE s.user_id = v_u) IS DISTINCT FROM v_settings
     OR pg_temp.snapshot(v_u) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused settings save changed a row, a claim or a counter';
  END IF;

  -- Other countries: verified (and the age gate), 14+ days; malformed
  -- codes, NULLs, more than ten and NULL itself are invalid.
  UPDATE public.dating_profiles SET verification_state = 'verified' WHERE user_id IN (v_u, v_young);
  INSERT INTO public.dating_age_verifications (user_id, birth_date, verification_method, verified_at)
  VALUES (v_young, current_date - interval '30 years', 'contract', now());
  -- (B8 I-2: a plain profile, so the UK, same-gender off here, may see it.)
  PERFORM pg_temp.call(v_young, format('SELECT public.save_dating_identity(%L, ''man'', NULL, NULL, NULL, false)', pg_temp.key('d5')));
  PERFORM pg_temp.call(v_young, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman''], 25, 35)', pg_temp.key('d6')));
  UPDATE public.users SET created_at = now() - interval '13 days' WHERE id = v_young;
  IF pg_temp.call(v_young, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "not_yet"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 13-day-old verified account could open to other countries';
  END IF;
  UPDATE public.users SET created_at = now() - interval '15 days' WHERE id = v_young;
  IF pg_temp.call(v_young, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])', pg_temp.key('ab')))
       IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 15-day-old verified account could not open to other countries';
  END IF;
  -- v_u is verified but has no age verification: the age gate refuses.
  IF pg_temp.call(v_u, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "not_yet"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: other countries opened without the age gate';
  END IF;
  v_before := pg_temp.snapshot(v_young);
  FOREACH v_case SLICE 1 IN ARRAY ARRAY[
      ['NULL', '{"ok": false, "reason": "invalid", "field": "countries"}'],
      ['ARRAY[NULL]::char(2)[]', '{"ok": false, "reason": "invalid", "field": "countries"}'],
      ['ARRAY[''GB'', NULL]::char(2)[]', '{"ok": false, "reason": "invalid", "field": "countries"}'],
      ['ARRAY[''G'']::char(2)[]', '{"ok": false, "reason": "invalid", "field": "countries"}'],
      ['ARRAY[''G1'']::char(2)[]', '{"ok": false, "reason": "invalid", "field": "countries"}'],
      ['ARRAY[''GBR'']', '{"ok": false, "reason": "invalid", "field": "countries"}'],
      ['ARRAY[' || quote_literal('GB' || repeat('x', 4998)) || ']', '{"ok": false, "reason": "invalid", "field": "countries"}'],
      ['array_fill(''GB''::char(2), ARRAY[11])', '{"ok": false, "reason": "invalid", "field": "countries"}'],
      ['array_fill(''GB''::char(2), ARRAY[5000])', '{"ok": false, "reason": "invalid", "field": "countries"}'],
      ['ARRAY[''XX'']::char(2)[]', '{"ok": false, "reason": "invalid", "field": "countries"}']] LOOP
    BEGIN
      v := pg_temp.call(v_young, format('SELECT public.set_dating_open_abroad(%L, %s)', pg_temp.key('g2'), v_case[1]));
    EXCEPTION WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: other countries raised (% %) for %', SQLSTATE, SQLERRM, left(v_case[1], 80);
    END;
    IF v IS DISTINCT FROM v_case[2]::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: other countries answered % for %, expected %', v, left(v_case[1], 80), v_case[2];
    END IF;
  END LOOP;
  IF pg_temp.snapshot(v_young) IS DISTINCT FROM v_before
     OR (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_young) IS DISTINCT FROM ARRAY['GB']::char(2)[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused other-countries answer changed a row, a claim or a counter';
  END IF;
  -- Closing other countries is always allowed (less exposure), even unverified.
  -- (One statement sees one snapshot: each write and its read are separate.)
  UPDATE public.dating_profiles SET verification_state = 'pending' WHERE user_id = v_young;
  -- (Adding a country, IE, opened in C: keeping {GB} is a subset, B8 I-1.)
  IF pg_temp.call(v_young, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'', ''IE'']::char(2)[])', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "not_yet"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unverified account (age gate held, 15 days) could open to other countries';
  END IF;
  v := pg_temp.call(v_young, format('SELECT public.set_dating_open_abroad(%L, ARRAY[]::char(2)[])', pg_temp.key('cl')));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_young) IS DISTINCT FROM ARRAY[]::char(2)[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unverified person could not close other countries: %', v;
  END IF;

  -- Photos after mutual interest: from account day 30; NULL is invalid;
  -- turning it off is always allowed.
  UPDATE public.users SET created_at = now() - interval '29 days' WHERE id = v_young;
  v := jsonb_build_array(pg_temp.call(v_young, format('SELECT public.set_dating_photos_after_mutual(%L, true)', pg_temp.key('x'))));
  v := v || jsonb_build_array(pg_temp.call(v_young, format('SELECT public.set_dating_photos_after_mutual(%L, false)', pg_temp.key('off'))));
  v := v || jsonb_build_array(pg_temp.call(v_young, format('SELECT public.set_dating_photos_after_mutual(%L, NULL)', pg_temp.key('x'))));
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "not_yet"}, {"ok": true}, {"ok": false, "reason": "invalid", "field": "on"}]'::jsonb
     OR (SELECT photos_after_mutual FROM public.dating_profiles WHERE user_id = v_young) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photos after mutual interest opened before day 30, or refused off or NULL wrongly: %', v;
  END IF;
  UPDATE public.users SET created_at = now() - interval '31 days' WHERE id = v_young;
  v := pg_temp.call(v_young, format('SELECT public.set_dating_photos_after_mutual(%L, true)', pg_temp.key('on')));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT photos_after_mutual FROM public.dating_profiles WHERE user_id = v_young) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photos after mutual interest was refused on day 31: %', v;
  END IF;

  -- The family question: NULL clears it; anything else is refused unchanged.
  v := jsonb_build_array(pg_temp.call(v_u, format('SELECT public.save_dating_family_involvement(%L, ''our_decision'')', pg_temp.key('f'))));
  v := v || jsonb_build_array(pg_temp.call(v_u, format('SELECT public.save_dating_family_involvement(%L, %L)', pg_temp.key('x'), repeat('e', 5000))));
  IF v IS DISTINCT FROM '[{"ok": true}, {"ok": false, "reason": "invalid", "field": "family_involvement"}]'::jsonb
     OR (SELECT family_involvement FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM 'our_decision' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the family question saved a value outside its list: %', v;
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_family_involvement(%L, NULL)', pg_temp.key('f')));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT family_involvement FROM public.dating_profiles WHERE user_id = v_u) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the family question could not be cleared: %', v;
  END IF;
END $$;

-- A Dating country but no preferences row (written directly): other
-- countries answer invalid and claim nothing. An under-18 account: every
-- Task 10 writer answers not_eligible and writes nothing (the guard).
DO $$
DECLARE
  v_noprefs constant uuid := pg_temp.person('66');
  v_young constant uuid := pg_temp.person('65', 17);
  v_lock constant uuid := pg_temp.person('67');
  v_nocountry constant uuid := pg_temp.person('68');
  v_got jsonb := '[]'::jsonb;
  v_call text;
BEGIN
  -- Other countries lock the profile row before deciding (its country and
  -- verification): the profile is written directly (no earlier lock), and
  -- the refusal (no age gate) returns before any write, so xmax shows the
  -- lock alone.
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_lock, 'profile_draft');
  INSERT INTO public.dating_profiles (user_id, display_name, moderation_state, country_code, region_code, verification_state)
  VALUES (v_lock, 'Ama Person 67', 'approved', 'GH', 'AA', 'verified');
  INSERT INTO public.dating_preferences (user_id, min_age, max_age) VALUES (v_lock, 25, 35);
  IF (SELECT xmax::text FROM public.dating_profiles WHERE user_id = v_lock) IS DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'fixture: the lock probe''s profile row is locked before the step';
  END IF;
  IF pg_temp.call(v_lock, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])', pg_temp.key('lk')))
       IS DISTINCT FROM '{"ok": false, "reason": "not_yet"}'::jsonb THEN
    RAISE EXCEPTION 'fixture: the lock probe was not refused as not_yet';
  END IF;
  IF (SELECT xmax::text FROM public.dating_profiles WHERE user_id = v_lock) IS NOT DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: other countries decided without locking the profile row';
  END IF;
  -- D7 first: a preferences row, but no Dating country yet: invalid.
  PERFORM pg_temp.call(v_nocountry, format('SELECT public.save_dating_children(%L, false, ''yes'', false, false)', pg_temp.key('d7')));
  IF NOT EXISTS (SELECT 1 FROM public.dating_preferences WHERE user_id = v_nocountry)
     OR (SELECT country_code FROM public.dating_profiles WHERE user_id = v_nocountry) IS NOT NULL THEN
    RAISE EXCEPTION 'fixture: the no-country person has no preferences row, or has a country';
  END IF;
  IF pg_temp.call(v_nocountry, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])', pg_temp.key('nc')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "countries"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: other countries opened for a person with no Dating country';
  END IF;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_noprefs, 'profile_draft');
  INSERT INTO public.dating_profiles (user_id, display_name, moderation_state, country_code, region_code, verification_state)
  VALUES (v_noprefs, 'Ama Person 66', 'approved', 'GH', 'AA', 'verified');
  INSERT INTO public.dating_age_verifications (user_id, birth_date, verification_method, verified_at)
  VALUES (v_noprefs, current_date - interval '30 years', 'contract', now());
  IF pg_temp.call(v_noprefs, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])', pg_temp.key('np')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "countries"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_rpc_idempotency WHERE user_id = v_noprefs) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: other countries without a preferences row did not answer invalid, or claimed the key';
  END IF;
  FOREACH v_call IN ARRAY ARRAY[
      format('SELECT public.save_dating_prompts(%%L, %L)', '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}, {"prompt_id": "ask_me_about", "answer": "Ask me about Busua."}]'),
      'SELECT public.save_dating_display_name(%L, ''Ama'')',
      'SELECT public.save_dating_family_involvement(%L, ''early'')',
      'SELECT public.save_dating_settings(%L, ''{"digest_push": true}'')',
      'SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])',
      'SELECT public.set_dating_photos_after_mutual(%L, false)'] LOOP
    v_got := v_got || pg_temp.call(v_young, format(v_call, pg_temp.key('u18')));
  END LOOP;
  -- B8 I-1: the exposure-reducing changes answer ok and, with no Dating
  -- profile, write nothing but their claim (no profile, settings,
  -- enrolment or prompt row).
  FOREACH v_call IN ARRAY ARRAY[
      'SELECT public.set_dating_open_abroad(%L, ARRAY[]::char(2)[])',
      'SELECT public.save_dating_settings(%L, ''{"chat_push": false}'')',
      'SELECT public.set_dating_photos_after_mutual(%L, true)'] LOOP
    v_got := v_got || pg_temp.call(v_young, format(v_call, pg_temp.key('u18')));
  END LOOP;
  IF v_got IS DISTINCT FROM (SELECT jsonb_agg('{"ok": false, "reason": "not_eligible"}'::jsonb) FROM generate_series(1, 6))
                            || '[{"ok": true}, {"ok": true}, {"ok": true}]'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_young)
     OR EXISTS (SELECT 1 FROM public.dating_settings WHERE user_id = v_young)
     OR EXISTS (SELECT 1 FROM public.dating_prompts WHERE user_id = v_young)
     OR EXISTS (SELECT 1 FROM public.dating_enrollments WHERE user_id = v_young)
     OR (SELECT count(*) FROM public.dating_rpc_idempotency WHERE user_id = v_young) IS DISTINCT FROM 3::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Task 10 writer went past the setup guard for an under-18 account: %', v_got;
  END IF;
END $$;

-- =====================================================================
-- G3. (Batch 8 ruling; fix round 1: I-5, M-10) Photos after mutual
--    interest: no photo path or URL reaches anyone before mutual interest.
--    The preview (exactly what others see) lists no photo when it is on
--    and never a storage path; anon and a stranger read, update and delete
--    no photo row or stored object (production-format keys, hosted
--    grants); and every function in any schema that reads the photo table
--    or the bucket, whoever may run it, is allow-listed with its roles (a
--    W5 card reader or dating_photo_keys_for_viewer must be added here,
--    deliberately, with its photos-after-mutual rule).
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('54', 'GH', 'AA');
  v_stranger constant uuid := pg_temp.person('55');
  v_key1 constant text := 'dating-photos/' || md5('g3-one') || '.jpg';
  v_key2 constant text := 'dating-photos/' || md5('g3-two') || '.jpg';
  v_photo uuid;
  v jsonb;
  v_read bigint;
  v_upd bigint;
  v_del bigint;
  v_got text;
  v_case text;
  v_role text;
  v_x uuid;
BEGIN
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state)
  VALUES (v_u, v_key1, 1, 'approved') RETURNING id INTO v_photo;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state)
  VALUES (v_u, v_key2, 2, 'pending');
  INSERT INTO storage.objects (bucket_id, name, owner)
  VALUES ('dating-profile-photos', v_key1, v_u);
  v := pg_temp.call(v_u, 'SELECT public.get_dating_profile_preview()');
  IF v #> '{card,photos}' IS DISTINCT FROM jsonb_build_array(jsonb_build_object('id', v_photo, 'position', 1))
     OR v #> '{card,photos_after_mutual}' IS DISTINCT FROM 'false'::jsonb
     OR position(md5('g3-one') IN v::text) > 0 OR position('dating-photos' IN v::text) > 0
     OR position('dating-profile-photos' IN v::text) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the preview does not list exactly the approved photo slots, or shows a path: %', v;
  END IF;
  UPDATE public.dating_profiles SET photos_after_mutual = true WHERE user_id = v_u;
  v := pg_temp.call(v_u, 'SELECT public.get_dating_profile_preview()');
  IF v #> '{card,photos}' IS DISTINCT FROM '[]'::jsonb
     OR v #> '{card,photos_after_mutual}' IS DISTINCT FROM 'true'::jsonb
     OR position(md5('g3-one') IN v::text) > 0 OR position(v_photo::text IN v::text) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with photos after mutual interest the preview still shows a photo: %', v;
  END IF;
  -- anon and a stranger: nothing read, updated or deleted; the owner reads
  -- their row, the other row and the object (so the probe reads for real)
  -- and, with no policy for it, updates and deletes nothing either. Hosted
  -- projects grant these to the API roles (rolled back).
  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
  GRANT SELECT, UPDATE, DELETE ON storage.objects TO anon, authenticated;
  FOREACH v_case IN ARRAY ARRAY['anon:' || v_stranger, 'authenticated:' || v_stranger, 'authenticated:' || v_u] LOOP
    v_role := split_part(v_case, ':', 1);
    v_x := split_part(v_case, ':', 2)::uuid;
    EXECUTE format('SET LOCAL ROLE %I', v_role);
    PERFORM set_config('request.jwt.claim.sub', v_x::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_x, 'role', v_role)::text, true);
    v_read := (SELECT count(*) FROM storage.objects WHERE bucket_id = 'dating-profile-photos' AND name = v_key1);
    IF v_role = 'authenticated' THEN
      v_read := v_read + (SELECT count(*) FROM public.dating_profile_photos WHERE user_id = v_u);
    END IF;
    WITH u AS (UPDATE storage.objects SET metadata = '{"w1c": true}'::jsonb
                WHERE bucket_id = 'dating-profile-photos' AND name = v_key1 RETURNING 1)
    SELECT count(*) INTO v_upd FROM u;
    WITH d AS (DELETE FROM storage.objects WHERE bucket_id = 'dating-profile-photos' AND name = v_key1 RETURNING 1)
    SELECT count(*) INTO v_del FROM d;
    RESET ROLE;
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '', true);
    IF v_read IS DISTINCT FROM (CASE WHEN v_x = v_u THEN 3 ELSE 0 END)::bigint OR v_upd <> 0 OR v_del <> 0 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % (%) reads % / updates % / deletes % Dating photo rows and objects (stranger 0/0/0, owner 3/0/0)',
        v_role, CASE WHEN v_x = v_u THEN 'the owner' ELSE 'a stranger' END, v_read, v_upd, v_del;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM storage.objects WHERE name = v_key1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client removed a Dating photo object';
  END IF;
  -- I-5: every function in any schema that reads the photo table or the
  -- bucket, with the API roles that may run it (service-role and trigger
  -- functions included). Each today is the owner's own, or the database's.
  SELECT string_agg(x, '; ' ORDER BY x COLLATE "C") INTO v_got
    FROM (SELECT n.nspname || '.' || p.proname || '(' || oidvectortypes(p.proargtypes) || '):'
                 || concat_ws(',', CASE WHEN has_function_privilege('anon', p.oid, 'EXECUTE') THEN 'anon' END,
                                   CASE WHEN has_function_privilege('authenticated', p.oid, 'EXECUTE') THEN 'authenticated' END,
                                   CASE WHEN has_function_privilege('service_role', p.oid, 'EXECUTE') THEN 'service_role' END) AS x
            FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
           WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname !~ '^pg_'
             AND (p.prosrc ~ 'dating_profile_photos' OR p.prosrc ~ 'dating-profile-photos')) AS s;
  -- W1 final fix (N-I1): the two v1 upload writers are no API role's.
  -- Spec 2 W1d (Task 12): delete_dating_profile is gone; exit's hard delete
  -- (queues the photos) and readiness's completeness (counts them) are the
  -- database's own.
  IF v_got IS DISTINCT FROM 'private.dating_exit_internal(uuid, boolean):; public.create_dating_photo_upload_intent(text):; public.dating_photos_queue_media_before_delete():; public.dating_profile_complete(uuid):; public.delete_dating_profile_photo(uuid):authenticated; public.get_dating_operational_health():service_role; public.get_dating_profile_preview():authenticated; public.insert_dating_profile_photo(uuid, smallint):; public.list_dating_profile_photos():authenticated; public.prepare_account_deletion(uuid):service_role' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the functions reading Dating photos changed (review photos after mutual interest): %', v_got;
  END IF;
END $$;

-- =====================================================================
-- G4. (W1 B8 ruling, I-1) Exposure-reducing changes are never gated by the
--    setup guard: with the Dating country closed, under a restriction and
--    with Dating off, closing other countries (a subset of the stored
--    list), pushes and show-when-away off with data saver on, and photos
--    after mutual interest on each answer ok and change the row; anything
--    else still answers not_eligible; no enrolment reopens, no counter
--    moves. The reducing branch claims its key too (replays change nothing).
-- =====================================================================
DO $$
DECLARE
  v_state text;
  v_n int := 73;
  v_x uuid;
  v_enrol text;
  v_count numeric;
  v_got jsonb;
  v_r uuid;
  v_k text;
BEGIN
  FOREACH v_state IN ARRAY ARRAY['closed', 'restricted', 'dating_off'] LOOP
    v_n := v_n + 1;
    v_x := pg_temp.ready(v_n::text, 'GH', 'AA', 'woman', ARRAY['man']);
    IF pg_temp.call(v_x, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'', ''IE'']::char(2)[])', pg_temp.key('ab')))
         IS DISTINCT FROM '{"ok": true}'::jsonb
       OR pg_temp.call(v_x, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('s'),
            '{"digest_push": true, "show_when_away": true, "data_saver": false}')) IS DISTINCT FROM '{"ok": true}'::jsonb THEN
      RAISE EXCEPTION 'fixture: G4 % could not open other countries or save settings', v_state;
    END IF;
    IF v_state = 'closed' THEN
      PERFORM public.publish_country_config('GH', '{"dating_enabled": false}');
    ELSIF v_state = 'restricted' THEN
      INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_x, 'suspended');
    ELSE
      UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
    END IF;
    IF public.dating_eligibility(v_x, 'setup') IS NOT DISTINCT FROM 'eligible' THEN
      RAISE EXCEPTION 'fixture: the G4 % person is still eligible', v_state;
    END IF;
    v_enrol := (SELECT state FROM public.dating_enrollments WHERE user_id = v_x);
    v_count := (SELECT coalesce(sum(c.count), 0) FROM public.metric_counters AS c WHERE c.key LIKE 'dating.%');
    -- Not reducing: still the full guard.
    v_got := jsonb_build_array(pg_temp.call(v_x, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'', ''IE'', ''NG'']::char(2)[])', pg_temp.key('nr'))));
    v_got := v_got || jsonb_build_array(pg_temp.call(v_x, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('nr'), '{"drop_time": "20:00"}')));
    v_got := v_got || jsonb_build_array(pg_temp.call(v_x, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('nr'), '{"chat_push": true}')));
    v_got := v_got || jsonb_build_array(pg_temp.call(v_x, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('nr'), '{"chat_push": false, "drop_time": "20:00"}')));
    v_got := v_got || jsonb_build_array(pg_temp.call(v_x, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('nr'), '{"data_saver": false}')));
    v_got := v_got || jsonb_build_array(pg_temp.call(v_x, format('SELECT public.set_dating_photos_after_mutual(%L, false)', pg_temp.key('nr'))));
    IF v_got IS DISTINCT FROM (SELECT jsonb_agg('{"ok": false, "reason": "not_eligible"}'::jsonb) FROM generate_series(1, 6)) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % : a change that does not reduce exposure went past the setup guard: %', v_state, v_got;
    END IF;
    -- Reducing: ok, and the row changes.
    v_got := jsonb_build_array(pg_temp.call(v_x, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''ie'', ''IE'']::char(2)[])', pg_temp.key('rd'))));
    IF (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_x) IS DISTINCT FROM '{IE}'::char(2)[] THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % : keeping IE of {GB,IE} did not store {IE}: %', v_state, v_got;
    END IF;
    v_got := v_got || jsonb_build_array(pg_temp.call(v_x, format('SELECT public.set_dating_open_abroad(%L, ARRAY[]::char(2)[])', pg_temp.key('rd'))));
    v_got := v_got || jsonb_build_array(pg_temp.call(v_x, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('rd'),
                 '{"chat_push": false, "digest_push": false, "show_when_away": false, "data_saver": true}')));
    v_got := v_got || jsonb_build_array(pg_temp.call(v_x, format('SELECT public.set_dating_photos_after_mutual(%L, true)', pg_temp.key('rd'))));
    IF v_got IS DISTINCT FROM (SELECT jsonb_agg('{"ok": true}'::jsonb) FROM generate_series(1, 4)) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % : an exposure-reducing change was gated: %', v_state, v_got;
    END IF;
    IF (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_x) IS DISTINCT FROM '{}'::char(2)[]
       OR (SELECT digest_push::text || chat_push::text || show_when_away::text || data_saver::text || to_char(drop_time, 'HH24:MI')
             FROM public.dating_settings WHERE user_id = v_x) IS DISTINCT FROM 'falsefalsefalsetrue19:00'
       OR (SELECT photos_after_mutual FROM public.dating_profiles WHERE user_id = v_x) IS NOT TRUE THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % : an exposure-reducing change answered ok but did not change the row', v_state;
    END IF;
    IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_x) IS DISTINCT FROM v_enrol
       OR (SELECT coalesce(sum(c.count), 0) FROM public.metric_counters AS c WHERE c.key LIKE 'dating.%') IS DISTINCT FROM v_count THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % : an exposure-reducing change reopened the enrolment or moved a counter', v_state;
    END IF;
    IF v_state = 'closed' THEN
      PERFORM public.publish_country_config('GH', '{"dating_enabled": true}');
    ELSIF v_state = 'dating_off' THEN
      UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
    END IF;
  END LOOP;

  -- The reducing branch claims its key: a replay changes nothing.
  v_r := pg_temp.ready('77', 'GH', 'AA', 'man', ARRAY['woman']);
  PERFORM pg_temp.call(v_r, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])', pg_temp.key('ab')));
  PERFORM pg_temp.call(v_r, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('s'), '{"digest_push": true}'));
  v_k := pg_temp.key('rp');
  PERFORM pg_temp.call(v_r, format('SELECT public.set_dating_open_abroad(%L, ARRAY[]::char(2)[])', v_k || 'a'));
  PERFORM pg_temp.call(v_r, format('SELECT public.save_dating_settings(%L, %L)', v_k || 's', '{"chat_push": false}'));
  PERFORM pg_temp.call(v_r, format('SELECT public.set_dating_photos_after_mutual(%L, true)', v_k || 'p'));
  PERFORM pg_temp.call(v_r, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])', pg_temp.key('ab')));
  PERFORM pg_temp.call(v_r, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('s'), '{"chat_push": true}'));
  PERFORM pg_temp.call(v_r, format('SELECT public.set_dating_photos_after_mutual(%L, false)', pg_temp.key('p')));
  v_got := jsonb_build_array(pg_temp.call(v_r, format('SELECT public.set_dating_open_abroad(%L, ARRAY[]::char(2)[])', v_k || 'a')));
  v_got := v_got || jsonb_build_array(pg_temp.call(v_r, format('SELECT public.save_dating_settings(%L, %L)', v_k || 's', '{"chat_push": false}')));
  v_got := v_got || jsonb_build_array(pg_temp.call(v_r, format('SELECT public.set_dating_photos_after_mutual(%L, true)', v_k || 'p')));
  IF v_got IS DISTINCT FROM '[{"ok": true}, {"ok": true}, {"ok": true}]'::jsonb
     OR (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_r) IS DISTINCT FROM '{GB}'::char(2)[]
     OR (SELECT chat_push FROM public.dating_settings WHERE user_id = v_r) IS NOT TRUE
     OR (SELECT photos_after_mutual FROM public.dating_profiles WHERE user_id = v_r) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed exposure-reducing key changed a row again: %', v_got;
  END IF;
  -- The reducing branch of other countries locks the profile row too
  -- (written directly, so no earlier lock; a no-op close writes nothing).
  v_r := pg_temp.person('90');
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_r, 'profile_draft');
  INSERT INTO public.dating_profiles (user_id, display_name, moderation_state, country_code, region_code)
  VALUES (v_r, 'Ama Person 90', 'approved', 'GH', 'AA');
  INSERT INTO public.dating_preferences (user_id, min_age, max_age) VALUES (v_r, 25, 35);
  IF (SELECT xmax::text FROM public.dating_profiles WHERE user_id = v_r) IS DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'fixture: the G4 lock probe''s row is locked before the step';
  END IF;
  PERFORM pg_temp.call(v_r, format('SELECT public.set_dating_open_abroad(%L, ARRAY[]::char(2)[])', pg_temp.key('lk')));
  IF (SELECT xmax::text FROM public.dating_profiles WHERE user_id = v_r) IS NOT DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: closing other countries did not lock the profile row';
  END IF;
  -- Lock order (setup, same-gender, row): a call that is not a subset takes
  -- no row lock before the guard and the same-gender locks, so one the
  -- guard refuses leaves the row unlocked (under-18, written directly).
  v_r := pg_temp.person('93', 17);
  INSERT INTO public.dating_profiles (user_id, display_name, moderation_state, country_code, region_code)
  VALUES (v_r, 'Ama Person 93', 'approved', 'GH', 'AA');
  INSERT INTO public.dating_preferences (user_id, min_age, max_age) VALUES (v_r, 25, 35);
  v_got := pg_temp.call(v_r, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])', pg_temp.key('lo')));
  IF v_got IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR (SELECT xmax::text FROM public.dating_profiles WHERE user_id = v_r) IS DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: other countries locked the profile row before the same-gender locks (or answered %)', v_got;
  END IF;
  -- M-2: settings belong to a Dating profile: none yet is invalid, no row.
  v_r := pg_temp.person('91');
  v_got := pg_temp.call(v_r, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('s'), '{"drop_time": "20:00"}'));
  IF v_got IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "profile"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_settings WHERE user_id = v_r) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: settings were saved for a person with no Dating profile: %', v_got;
  END IF;
END $$;

-- =====================================================================
-- G5. (W1 B8 ruling, I-2) Other countries never include a country whose
--    same-gender rule excludes the person's profile. Only a plain profile
--    (woman or man, nothing more, meeting only the opposite) may open to a
--    same-gender-off country; anything else, unknown included, is
--    not_available (no raise, no claim, no row, no counter); an unreadable
--    profile or no key is unavailable. A later D5 or D6 answer that is not
--    plain removes the unsafe countries and keeps the safe ones (D3: C).
--    Every writer takes the targets' shared same-gender locks.
-- =====================================================================
DO $$
DECLARE
  v_nb uuid;
  v_trans uuid;
  v_none uuid;
  v_plain uuid;
  v_bad uuid;
  v_lk uuid;
  v_nbw uuid;
  v_x uuid;
  v_before text;
  v jsonb;
  v_k text;
  v_key constant text := current_setting('app.settings.dating_field_key');
BEGIN
  -- The flag on: GB and IE (opened in C) are same-gender on; GH is off.
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  v_nb := pg_temp.ready('78', 'GB', 'TLD', 'non_binary', ARRAY['man', 'non_binary', 'woman'], ARRAY['woman']);
  v_trans := pg_temp.ready('79', 'GB', 'TLD', 'woman', ARRAY['man'], NULL, 'trans_woman');
  v_none := pg_temp.located('80', 'GB', 'TLD');
  UPDATE public.dating_profiles SET verification_state = 'verified' WHERE user_id = v_none;
  INSERT INTO public.dating_age_verifications (user_id, birth_date, verification_method, verified_at)
  VALUES (v_none, current_date - interval '30 years', 'contract', now());
  v_plain := pg_temp.ready('81', 'GB', 'TLD', 'woman', ARRAY['man']);
  v_bad := pg_temp.ready('82', 'GB', 'TLD', 'woman', ARRAY['man']);
  v_lk := pg_temp.ready('85', 'GB', 'TLD', 'woman', ARRAY['man']);
  -- Non-binary with no extra pool, meeting women: still not plain.
  v_nbw := pg_temp.ready('94', 'GB', 'TLD', 'non_binary', ARRAY['woman']);

  -- (a) Not plain (or unknown): not_available for any same-gender-off target.
  FOREACH v_x IN ARRAY ARRAY[v_nb, v_trans, v_none, v_nbw] LOOP
    v_before := pg_temp.rows_of(v_x) || (SELECT coalesce(sum(c.count), 0) FROM public.metric_counters AS c WHERE c.key LIKE 'dating.%');
    v := jsonb_build_array(pg_temp.call(v_x, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GH'']::char(2)[])', pg_temp.key('sg'))));
    v := v || jsonb_build_array(pg_temp.call(v_x, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GH'', ''IE'']::char(2)[])', pg_temp.key('sg'))));
    IF v IS DISTINCT FROM '[{"ok": false, "reason": "not_available"}, {"ok": false, "reason": "not_available"}]'::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a profile that is not plain could open to a same-gender-off country: %', v;
    END IF;
    IF pg_temp.rows_of(v_x) || (SELECT coalesce(sum(c.count), 0) FROM public.metric_counters AS c WHERE c.key LIKE 'dating.%')
         IS DISTINCT FROM v_before THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a not_available other-countries answer claimed, stored or counted something';
    END IF;
  END LOOP;
  -- A same-gender-on country is fine for anyone.
  v := pg_temp.call(v_nb, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''IE'']::char(2)[])', pg_temp.key('ie')));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_nb) IS DISTINCT FROM '{IE}'::char(2)[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-binary person could not open to a same-gender-on country: %', v;
  END IF;
  -- Plain: allowed (and de-duplicated, upper-cased; M-3).
  v_k := pg_temp.key('pl');
  v := pg_temp.call(v_plain, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GH'', ''gh'', ''IE'']::char(2)[])', v_k));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_plain) IS DISTINCT FROM '{GH,IE}'::char(2)[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a plain profile could not open to {GH,IE} (de-duplicated): %', v;
  END IF;
  -- M-3: closed, then the used key replayed (the full path, every check
  -- passing) changes nothing; then opened again.
  PERFORM pg_temp.call(v_plain, format('SELECT public.set_dating_open_abroad(%L, ARRAY[]::char(2)[])', pg_temp.key('cl')));
  v := pg_temp.call(v_plain, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GH'', ''IE'']::char(2)[])', v_k));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_plain) IS DISTINCT FROM '{}'::char(2)[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed other-countries key wrote again: %', v;
  END IF;
  PERFORM pg_temp.call(v_plain, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GH'', ''IE'']::char(2)[])', pg_temp.key('pl')));

  -- (b) D6 to everyone: GH (off) goes, IE (on) stays.
  PERFORM pg_temp.call(v_plain, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man'', ''non_binary'', ''woman''], 25, 40)', pg_temp.key('d6')));
  IF (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_plain) IS DISTINCT FROM '{IE}'::char(2)[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after D6 to everyone the same-gender-off country stayed (or the safe one went): %',
      (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_plain);
  END IF;
  -- Back to plain, GH again; then D5 non-binary: GH goes, IE stays.
  PERFORM pg_temp.call(v_plain, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 40)', pg_temp.key('d6')));
  v := pg_temp.call(v_plain, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GH'', ''IE'']::char(2)[])', pg_temp.key('pl')));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'fixture: the plain person could not reopen GH: %', v;
  END IF;
  PERFORM pg_temp.call(v_plain, format('SELECT public.save_dating_identity(%L, ''non_binary'', NULL, NULL, NULL, false)', pg_temp.key('d5')));
  IF (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_plain) IS DISTINCT FROM '{IE}'::char(2)[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after D5 non-binary the same-gender-off country stayed (or the safe one went): %',
      (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_plain);
  END IF;

  -- No key, and an unreadable identity: unavailable, nothing claimed.
  v_before := pg_temp.rows_of(v_bad);
  PERFORM set_config('app.settings.dating_field_key', '', true);
  v := jsonb_build_array(pg_temp.call(v_bad, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GH'']::char(2)[])', pg_temp.key('nk'))));
  PERFORM set_config('app.settings.dating_field_key', v_key, true);
  IF pg_temp.rows_of(v_bad) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: other countries without the key claimed or stored something';
  END IF;
  UPDATE public.dating_profile_sensitive SET identity_enc = '\x02'::bytea || substring(identity_enc FROM 2) WHERE user_id = v_bad;
  v_before := pg_temp.rows_of(v_bad);
  v := v || jsonb_build_array(pg_temp.call(v_bad, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GH'']::char(2)[])', pg_temp.key('ur'))));
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"}]'::jsonb
     OR pg_temp.rows_of(v_bad) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: other countries without the key or over an unreadable profile did not answer unavailable with nothing claimed: %', v;
  END IF;

  -- Locks: each writer takes its targets' shared same-gender locks (codes
  -- no other section locks: KE, ZA, TZ, UG).
  IF pg_temp.holds('dating_same_gender', 'KE', 'ShareLock') OR pg_temp.holds('dating_same_gender', 'ZA', 'ShareLock')
     OR pg_temp.holds('dating_same_gender', 'TZ', 'ShareLock') OR pg_temp.holds('dating_same_gender', 'UG', 'ShareLock') THEN
    RAISE EXCEPTION 'fixture: a G5 probe country is locked before its step';
  END IF;
  v := pg_temp.call(v_lk, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''KE'']::char(2)[])', pg_temp.key('lk')));
  IF v IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "countries"}'::jsonb
     OR NOT pg_temp.holds('dating_same_gender', 'KE', 'ShareLock') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: other countries decided without the target''s shared same-gender lock: %', v;
  END IF;
  UPDATE public.dating_preferences SET open_abroad = '{ZA}' WHERE user_id = v_lk;
  PERFORM pg_temp.call(v_lk, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, false)', pg_temp.key('d5')));
  IF NOT pg_temp.holds('dating_same_gender', 'ZA', 'ShareLock') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D5 did not take its other countries'' shared same-gender locks';
  END IF;
  UPDATE public.dating_preferences SET open_abroad = '{TZ}' WHERE user_id = v_lk;
  PERFORM pg_temp.call(v_lk, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 40)', pg_temp.key('d6')));
  IF NOT pg_temp.holds('dating_same_gender', 'TZ', 'ShareLock') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D6 did not take its other countries'' shared same-gender locks';
  END IF;
  UPDATE public.dating_preferences SET open_abroad = '{UG}' WHERE user_id = v_lk;
  PERFORM pg_temp.call(v_lk, format('SELECT public.save_dating_location(%L, ''GB'', ''TLD'', NULL, ''region'')', pg_temp.key('d3')));
  IF NOT pg_temp.holds('dating_same_gender', 'UG', 'ShareLock') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D3 did not take its other countries'' shared same-gender locks';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
END $$;

-- =====================================================================
-- H. The readers: own profile decrypted; the preview is the card others
--    see, never who you'd like to meet, the side, the DOB or hidden fields.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('11', 'GH', 'AA');
  v jsonb;
BEGIN
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', ''accra'', ''region'')', pg_temp.key('d3')));
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, false)', pg_temp.key('d5')));
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 28, 40)', pg_temp.key('d6')));
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''christian'', NULL, ''nice_to_share'', false)', pg_temp.key('d8')));
  v := pg_temp.call(v_u, 'SELECT public.get_my_dating_profile()');
  IF v #>> '{profile,identity,identity}' IS DISTINCT FROM 'woman' OR v #> '{profile,seeking}' IS DISTINCT FROM '["man"]'::jsonb
     OR v #>> '{profile,faith,importance}' IS DISTINCT FROM 'nice_to_share' OR v #>> '{profile,side_code}' IS DISTINCT FROM 'accra'
     OR v #> '{profile,preferences,min_age}' IS DISTINCT FROM '28'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_my_dating_profile did not return the person''s own answers: %', v;
  END IF;
  v := pg_temp.call(v_u, 'SELECT public.get_dating_profile_preview()');
  IF v #>> '{card,display_name}' IS DISTINCT FROM 'Ama Person 11' OR (v #>> '{card,age}')::int IS DISTINCT FROM 30
     OR v #>> '{card,region_name_key}' IS DISTINCT FROM 'dating_region_gh_aa'
     OR v::text ~* '(seeking|accra|side|birth|"man"|nice_to_share|christian)'
     OR v #> '{card,gender}' IS DISTINCT FROM 'null'::jsonb OR v #> '{card,faith}' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the preview shows something others must never see: %', v;
  END IF;
  UPDATE public.dating_profiles SET gender_visible = true, faith_visible = true WHERE user_id = v_u;
  v := pg_temp.call(v_u, 'SELECT public.get_dating_profile_preview()');
  IF v #>> '{card,gender,identity}' IS DISTINCT FROM 'woman' OR v #>> '{card,faith,faith}' IS DISTINCT FROM 'christian'
     OR v::text ~* '(seeking|importance|nice_to_share)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the preview does not show exactly what the person chose to show: %', v;
  END IF;
END $$;
-- =====================================================================
-- H2. (Batch 8 rulings) The readers: each decrypts the caller's own row
--    only; the preview's keys are exactly the card's (nothing only the
--    owner sees), the timeline and "Divorced" / "Widowed" only when shown,
--    approved prompts only; no profile answers null; an untrusted device
--    (false or NULL) answers reverify_device; an unreadable value or a
--    missing key answers unavailable and never raises (batch-6 carry);
--    only the signed-in app runs them (not the service role, S-4).
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.located('56', 'GH', 'AA');
  v_b constant uuid := pg_temp.located('57', 'GH', 'AH');
  v_none constant uuid := pg_temp.person('58');
  v_anon_msg text;
  v jsonb;
  v_got jsonb := '[]'::jsonb;
BEGIN
  PERFORM pg_temp.call(v_a, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, true)', pg_temp.key('d5')));
  PERFORM pg_temp.call(v_a, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 28, 40)', pg_temp.key('d6')));
  PERFORM pg_temp.call(v_b, format('SELECT public.save_dating_intention(%L, ''marriage'', ''within_two_years'', false, true, ''divorced'', true)', pg_temp.key('d2')));
  PERFORM pg_temp.call(v_b, format('SELECT public.save_dating_identity(%L, ''man'', NULL, NULL, NULL, false)', pg_temp.key('d5')));
  PERFORM pg_temp.call(v_b, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman''], 25, 45)', pg_temp.key('d6')));
  PERFORM pg_temp.call(v_b, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('d10'),
    '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}, {"prompt_id": "ask_me_about", "answer": "My grandmother''s garden."}]'));
  -- Each person's own answers, never the other's.
  v := pg_temp.call(v_a, 'SELECT public.get_my_dating_profile()');
  IF v #>> '{profile,identity,identity}' IS DISTINCT FROM 'woman' OR v #> '{profile,seeking}' IS DISTINCT FROM '["man"]'::jsonb
     OR v #> '{profile,marital}' IS DISTINCT FROM 'null'::jsonb OR v #>> '{profile,region_code}' IS DISTINCT FROM 'AA' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_my_dating_profile did not return the caller''s own row: %', v;
  END IF;
  -- A's preview after B's writes: still A's own row (shown gender).
  v := pg_temp.call(v_a, 'SELECT public.get_dating_profile_preview()');
  IF v #>> '{card,gender,identity}' IS DISTINCT FROM 'woman' OR v #>> '{card,region_code}' IS DISTINCT FROM 'AA' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_dating_profile_preview did not read the caller''s own row: %', v;
  END IF;
  v := pg_temp.call(v_b, 'SELECT public.get_my_dating_profile()');
  IF v #>> '{profile,identity,identity}' IS DISTINCT FROM 'man' OR v #> '{profile,seeking}' IS DISTINCT FROM '["woman"]'::jsonb
     OR v #>> '{profile,marital}' IS DISTINCT FROM 'divorced' OR v #>> '{profile,region_code}' IS DISTINCT FROM 'AH'
     OR jsonb_array_length(v #> '{profile,prompts}') IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_my_dating_profile did not return the caller''s own row: %', v;
  END IF;
  -- The preview: exactly the card's keys; the hidden timeline stays hidden,
  -- the shown "Divorced" shows, a removed prompt is gone.
  UPDATE public.dating_prompts SET moderation_state = 'removed' WHERE user_id = v_b AND position = 2;
  v := pg_temp.call(v_b, 'SELECT public.get_dating_profile_preview()');
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v -> 'card') AS k)
       IS DISTINCT FROM ARRAY['age', 'children_have', 'children_want', 'display_name', 'faith', 'gender', 'intention', 'marital',
                              'marriage_timeline', 'photos', 'photos_after_mutual', 'prompts', 'pronouns', 'region_code', 'region_name_key']
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k) IS DISTINCT FROM ARRAY['card', 'ok'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the preview holds a key the card does not: %', v;
  END IF;
  IF v #> '{card,marriage_timeline}' IS DISTINCT FROM 'null'::jsonb OR v #>> '{card,marital}' IS DISTINCT FROM 'divorced'
     OR v #>> '{card,intention}' IS DISTINCT FROM 'marriage' OR v #> '{card,gender}' IS DISTINCT FROM 'null'::jsonb
     OR v #> '{card,prompts}' IS DISTINCT FROM '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}]'::jsonb
     OR v::text ~* '(woman|within_two_years|grandmother)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the preview shows a hidden timeline, a hidden gender or a removed prompt, or hides "Divorced": %', v;
  END IF;
  UPDATE public.dating_profiles SET timeline_visible = true, marital_visible = false WHERE user_id = v_b;
  v := pg_temp.call(v_b, 'SELECT public.get_dating_profile_preview()');
  IF v #>> '{card,marriage_timeline}' IS DISTINCT FROM 'within_two_years' OR v #> '{card,marital}' IS DISTINCT FROM 'null'::jsonb
     OR v::text ~* 'divorced' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the preview hides a shown timeline or shows a hidden marriage history: %', v;
  END IF;
  -- "Never married" is never shown, even on a row marked visible.
  PERFORM pg_temp.call(v_b, format('SELECT public.save_dating_intention(%L, ''marriage'', ''within_two_years'', true, true, ''never'', false)', pg_temp.key('d2n')));
  UPDATE public.dating_profiles SET marital_visible = true WHERE user_id = v_b;
  v := pg_temp.call(v_b, 'SELECT public.get_dating_profile_preview()');
  IF v #> '{card,marital}' IS DISTINCT FROM 'null'::jsonb OR v::text ~* '"never"' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the preview shows "never married": %', v;
  END IF;
  -- No Dating profile yet: null, not an error.
  IF pg_temp.call(v_none, 'SELECT public.get_my_dating_profile()') IS DISTINCT FROM '{"ok": true, "profile": null}'::jsonb
     OR pg_temp.call(v_none, 'SELECT public.get_dating_profile_preview()') IS DISTINCT FROM '{"ok": true, "card": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the readers did not answer null for a person with no Dating profile';
  END IF;
  -- Not signed in: not_authenticated (42501), like every Dating RPC.
  BEGIN
    PERFORM public.get_my_dating_profile();
    v_anon_msg := 'answered';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_anon_msg = MESSAGE_TEXT;
  END;
  BEGIN
    PERFORM public.get_dating_profile_preview();
    v_anon_msg := v_anon_msg || '/answered';
  EXCEPTION WHEN insufficient_privilege THEN
    v_anon_msg := v_anon_msg || '/' || SQLERRM;
  END;
  IF v_anon_msg IS DISTINCT FROM 'not_authenticated/not_authenticated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reader answered without a signed-in user: %', v_anon_msg;
  END IF;
  -- Grants: the signed-in app only.
  IF EXISTS (SELECT 1 FROM unnest(ARRAY['public.get_my_dating_profile()', 'public.get_dating_profile_preview()']) AS f
              WHERE has_function_privilege('service_role', f, 'EXECUTE') OR has_function_privilege('anon', f, 'EXECUTE')
                 OR NOT has_function_privilege('authenticated', f, 'EXECUTE')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reader is executable by the wrong role';
  END IF;

  -- An untrusted device (false, NULL): reverify_device from both readers.
  BEGIN
    CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $stub$ SELECT false $stub$;
    v_got := v_got || jsonb_build_array(pg_temp.call(v_a, 'SELECT public.get_my_dating_profile()'),
                                        pg_temp.call(v_a, 'SELECT public.get_dating_profile_preview()'));
    CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $stub$ SELECT NULL::boolean $stub$;
    v_got := v_got || jsonb_build_array(pg_temp.call(v_a, 'SELECT public.get_my_dating_profile()'),
                                        pg_temp.call(v_a, 'SELECT public.get_dating_profile_preview()'));
    RAISE SQLSTATE 'W1C99';
  EXCEPTION WHEN SQLSTATE 'W1C99' THEN
    NULL;
  END;
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "reverify_device"}, {"ok": false, "reason": "reverify_device"},
                              {"ok": false, "reason": "reverify_device"}, {"ok": false, "reason": "reverify_device"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reader answered on an untrusted device: %', v_got;
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RAISE EXCEPTION 'fixture: the device stub was not rolled back';
  END IF;
END $$;

-- The readers without the key, with an unreadable value, and with a key
-- lost after the presence check: unavailable, never a raise; and without
-- the key, a preview that shows nothing encrypted still answers.
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('59', 'GH', 'AA');
  v_plain constant uuid := pg_temp.located('60', 'GH', 'AA');
  v_key constant text := current_setting('app.settings.dating_field_key');
  v_got jsonb;
  v jsonb;
BEGIN
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, false)', pg_temp.key('d5')));
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''christian'', NULL, ''must_share'', false)', pg_temp.key('d8')));
  -- No key: the own profile (it holds encrypted answers) and a preview that
  -- shows faith are unavailable; a preview showing nothing encrypted, and a
  -- profile with nothing encrypted, still answer.
  PERFORM set_config('app.settings.dating_field_key', '', true);
  BEGIN
    v_got := jsonb_build_array(pg_temp.call(v_u, 'SELECT public.get_my_dating_profile()'));
    UPDATE public.dating_profiles SET faith_visible = true WHERE user_id = v_u;
    v_got := v_got || jsonb_build_array(pg_temp.call(v_u, 'SELECT public.get_dating_profile_preview()'));
    UPDATE public.dating_profiles SET faith_visible = false WHERE user_id = v_u;
    v_got := v_got || jsonb_build_array(pg_temp.call(v_u, 'SELECT public.get_dating_profile_preview()') ->> 'ok',
                                        pg_temp.call(v_plain, 'SELECT public.get_my_dating_profile()') ->> 'ok');
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    PERFORM set_config('app.settings.dating_field_key', v_key, true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: without dating_field_key a reader raised (%)', SQLERRM;
  END;
  PERFORM set_config('app.settings.dating_field_key', v_key, true);
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"}, "true", "true"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without dating_field_key a reader did not fail closed (or refused needlessly): %', v_got;
  END IF;

  -- An unreadable stored value (unknown version, then tampered): the own
  -- profile and a preview that shows it are unavailable; a preview that
  -- does not show it still answers.
  UPDATE public.dating_profile_sensitive SET identity_enc = '\x02'::bytea || substring(identity_enc FROM 2) WHERE user_id = v_u;
  UPDATE public.dating_profile_sensitive SET faith_enc = set_byte(faith_enc, octet_length(faith_enc) - 3, get_byte(faith_enc, octet_length(faith_enc) - 3) # 1)
   WHERE user_id = v_u;
  BEGIN
    v_got := jsonb_build_array(pg_temp.call(v_u, 'SELECT public.get_my_dating_profile()'),
                               pg_temp.call(v_u, 'SELECT public.get_dating_profile_preview()') ->> 'ok');
    UPDATE public.dating_profiles SET gender_visible = true WHERE user_id = v_u;
    v_got := v_got || jsonb_build_array(pg_temp.call(v_u, 'SELECT public.get_dating_profile_preview()'));
    UPDATE public.dating_profiles SET gender_visible = false, faith_visible = true WHERE user_id = v_u;
    v_got := v_got || jsonb_build_array(pg_temp.call(v_u, 'SELECT public.get_dating_profile_preview()'));
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable stored answer made a reader raise (%)', SQLERRM;
  END;
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "unavailable"}, "true", {"ok": false, "reason": "unavailable"},
                              {"ok": false, "reason": "unavailable"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable stored answer did not make a reader answer unavailable: %', v_got;
  END IF;

  -- The key lost after the presence check (key_present() stubbed true over
  -- an empty key, so decrypt raises field_key_missing): unavailable.
  UPDATE public.dating_profile_sensitive SET identity_enc = NULL, faith_enc = NULL WHERE user_id = v_u;
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, true)', pg_temp.key('d5b')));
  v_got := '[]'::jsonb;
  BEGIN
    CREATE OR REPLACE FUNCTION private.dating_field_key_present() RETURNS boolean
      LANGUAGE sql STABLE SET search_path = '' AS $stub$ SELECT true $stub$;
    PERFORM set_config('app.settings.dating_field_key', '', true);
    BEGIN
      v_got := jsonb_build_array(pg_temp.call(v_u, 'SELECT public.get_my_dating_profile()'),
                                 pg_temp.call(v_u, 'SELECT public.get_dating_profile_preview()'));
    EXCEPTION WHEN OTHERS THEN
      v_got := to_jsonb('raised: ' || SQLERRM);
    END;
    RAISE SQLSTATE 'W1C99';
  EXCEPTION WHEN SQLSTATE 'W1C99' THEN
    NULL;
  END;
  RESET ROLE;
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a key lost mid-read did not answer unavailable: %', v_got;
  END IF;
  IF private.dating_field_key_present() IS NOT TRUE OR current_setting('app.settings.dating_field_key') IS DISTINCT FROM v_key THEN
    RAISE EXCEPTION 'fixture: the key stub was not rolled back';
  END IF;
  v := pg_temp.call(v_u, 'SELECT public.get_dating_profile_preview()');
  IF v #>> '{card,gender,identity}' IS DISTINCT FROM 'woman' THEN
    RAISE EXCEPTION 'fixture: the H2 preview does not read after the stubs: %', v;
  END IF;
END $$;
-- =====================================================================
-- H3. (B8 fix round 1, I-4) The readers never read another person's rows
--    (settings, photos), and the card's nested values hold exactly their
--    keys: never the "introduce me to" pools or anything only the owner
--    sees.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('83', 'GH', 'AA', 'woman', ARRAY['man']);
  v_b constant uuid := pg_temp.ready('84', 'GH', 'AA', 'man', ARRAY['woman']);
  v_nb uuid;
  v_pa uuid;
  v jsonb;
BEGIN
  PERFORM pg_temp.call(v_a, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('s'), '{"drop_time": "08:00"}'));
  PERFORM pg_temp.call(v_b, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('s'), '{"drop_time": "21:00", "data_saver": true}'));
  PERFORM pg_temp.call(v_a, format('SELECT public.save_dating_faith(%L, ''christian'', ''catholic'', ''must_share'', true)', pg_temp.key('d8')));
  PERFORM pg_temp.call(v_a, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('d10'),
    '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}, {"prompt_id": "ask_me_about", "answer": "Ask me about Busua."}]'));
  UPDATE public.dating_profiles SET gender_visible = true WHERE user_id = v_a;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state)
  VALUES (v_a, 'dating-photos/' || md5('h3-a-1') || '.jpg', 1, 'approved') RETURNING id INTO v_pa;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state)
  VALUES (v_b, 'dating-photos/' || md5('h3-b-1') || '.jpg', 1, 'approved'), (v_b, 'dating-photos/' || md5('h3-b-2') || '.jpg', 2, 'approved');
  v := pg_temp.call(v_a, 'SELECT public.get_my_dating_profile()');
  IF v #> '{profile,settings}' IS DISTINCT FROM
       '{"drop_time": "08:00", "data_saver": false, "digest_push": false, "chat_push": true, "show_when_away": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_my_dating_profile returned settings that are not the caller''s: %', v #> '{profile,settings}';
  END IF;
  v := pg_temp.call(v_a, 'SELECT public.get_dating_profile_preview()');
  IF v #> '{card,photos}' IS DISTINCT FROM jsonb_build_array(jsonb_build_object('id', v_pa, 'position', 1)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the preview lists photos that are not the caller''s: %', v #> '{card,photos}';
  END IF;
  -- The nested keys, exactly.
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v #> '{card,gender}') AS k) IS DISTINCT FROM ARRAY['identity', 'specific', 'specific_text']
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v #> '{card,faith}') AS k) IS DISTINCT FROM ARRAY['denomination', 'faith']
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v #> '{card,photos}') AS f
                 WHERE (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(f) AS k) IS DISTINCT FROM ARRAY['id', 'position'])
     OR jsonb_array_length(v #> '{card,prompts}') IS DISTINCT FROM 2
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v #> '{card,prompts}') AS q
                 WHERE (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(q) AS k) IS DISTINCT FROM ARRAY['answer', 'prompt_id'])
     OR v #>> '{card,faith,denomination}' IS DISTINCT FROM 'catholic' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a nested card value holds a key it must not (or lacks one): %', v;
  END IF;
  -- A non-binary person also introduced to women: the card never says so.
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  v_nb := pg_temp.ready('86', 'GB', 'TLD', 'non_binary', ARRAY['man', 'non_binary', 'woman'], ARRAY['woman']);
  UPDATE public.dating_profiles SET gender_visible = true WHERE user_id = v_nb;
  v := pg_temp.call(v_nb, 'SELECT public.get_dating_profile_preview()');
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  IF v #>> '{card,gender,identity}' IS DISTINCT FROM 'non_binary' OR v::text ~ '(pools|"woman")' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the card shows the "introduce me to" pools: %', v;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM bystander AS b WHERE pg_temp.rows_of(b.user_id) IS DISTINCT FROM b.rows) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a writer or reader changed another person''s rows (the bystander, after %)', 'F to H3';
  END IF;
END $$;

-- =====================================================================
-- I. The guards: signed in; eligible to set up (opaque not_eligible).
-- =====================================================================
DO $$
DECLARE
  v_young constant uuid := pg_temp.person('12', 17);
  v_mid uuid;
  v jsonb;
  v_msg text;
BEGIN
  IF pg_temp.call(v_young, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR pg_temp.call(v_young, format('SELECT public.save_dating_children(%L, false, ''yes'', false, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_enrollments WHERE user_id = v_young) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 account could start Dating setup';
  END IF;
  -- Ghana closes mid-setup: the next step answers not_eligible and writes nothing.
  v_mid := pg_temp.located('14', 'GH', 'AA');
  PERFORM public.publish_country_config('GH', '{"dating_enabled": false}');
  v := pg_temp.call(v_mid, format('SELECT public.save_dating_children(%L, false, ''yes'', false, false)', pg_temp.key('mid')));
  PERFORM public.publish_country_config('GH', '{"dating_enabled": true}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR (SELECT children_have FROM public.dating_profiles WHERE user_id = v_mid) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a setup step went through after the country closed: %', v;
  END IF;
  BEGIN
    PERFORM public.save_dating_children('w1c-anon-000000', false, 'yes', false, false);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a setup writer answered without a signed-in user';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'not_authenticated' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: expected not_authenticated, got %', v_msg; END IF;
  END;
  BEGIN
    PERFORM public.clear_dating_faith('w1c-anon-000001');
    RAISE EXCEPTION 'CONTRACT VIOLATED: Skip answered without a signed-in user';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'not_authenticated' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Skip: expected not_authenticated, got %', v_msg; END IF;
  END;
  IF has_function_privilege('anon', 'public.save_dating_identity(text,text,text,text,text[],boolean)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.save_dating_identity(text,text,text,text,text[],boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.dating_setup_guard()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the setup writers'' grants are wrong';
  END IF;
  -- Batch-2 carry: every writer is the signed-in app's only; the service
  -- role (and anon) runs none of them, nor any helper.
  IF EXISTS (SELECT 1 FROM unnest(ARRAY[
        'public.save_dating_intention(text,text,text,boolean,boolean,text,boolean)',
        'public.save_dating_location(text,text,text,text,text)',
        'public.save_dating_identity(text,text,text,text,text[],boolean)',
        'public.save_dating_who_to_meet(text,text[],integer,integer)',
        'public.save_dating_children(text,boolean,text,boolean,boolean)',
        'public.save_dating_faith(text,text,text,text,boolean)',
        'public.clear_dating_faith(text)',
        -- Batch 8 (Task 10): the remaining writers and both readers.
        'public.save_dating_prompts(text,jsonb)', 'public.save_dating_display_name(text,text)',
        'public.save_dating_family_involvement(text,text)', 'public.save_dating_settings(text,jsonb)',
        'public.set_dating_open_abroad(text,character[])', 'public.set_dating_photos_after_mutual(text,boolean)',
        'public.get_my_dating_profile()', 'public.get_dating_profile_preview()']) AS f
      WHERE has_function_privilege('service_role', f, 'EXECUTE') OR has_function_privilege('anon', f, 'EXECUTE')
         OR NOT has_function_privilege('authenticated', f, 'EXECUTE'))
     OR EXISTS (SELECT 1 FROM unnest(ARRAY[
        'private.dating_setup_guard()', 'private.dating_ensure_profile(uuid)', 'private.dating_same_gender_on(text)',
        'private.dating_default_ages(integer)', 'private.dating_invalid(text)', 'private.dating_clear_faith(uuid)',
        'private.dating_lock_setup(uuid)', 'private.dating_lock_same_gender(text)',
        -- Batch 8 fix round 1.
        'private.dating_lock_same_gender_all(text[])', 'private.dating_profile_plain(jsonb,jsonb)',
        'private.dating_prune_unsafe_abroad(uuid)', 'private.dating_trim(text)', 'private.dating_has_invisible(text)']) AS f
      CROSS JOIN unnest(ARRAY['anon', 'authenticated', 'service_role']) AS r
      WHERE has_function_privilege(r, f, 'EXECUTE')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a setup writer or helper is executable by the wrong role';
  END IF;
END $$;

-- The guard fails closed: an untrusted device (false or NULL) answers
-- reverify_device and an unknown eligibility (NULL) answers not_eligible;
-- neither writes. Stubs live in a sub-block that is rolled back.
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('10', 'GH', 'AA');
  v_before text;
  v_got jsonb := '[]'::jsonb;
BEGIN
  v_before := pg_temp.snapshot(v_u);
  BEGIN
    CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $stub$ SELECT false $stub$;
    v_got := v_got || pg_temp.call(v_u, format('SELECT public.save_dating_children(%L, false, ''yes'', false, false)', pg_temp.key('dev')));
    CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $stub$ SELECT NULL::boolean $stub$;
    v_got := v_got || pg_temp.call(v_u, format('SELECT public.save_dating_children(%L, false, ''yes'', false, false)', pg_temp.key('dev')));
    CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $stub$ SELECT true $stub$;
    CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate') RETURNS text
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $stub$ SELECT NULL::text $stub$;
    v_got := v_got || pg_temp.call(v_u, format('SELECT public.save_dating_children(%L, false, ''yes'', false, false)', pg_temp.key('elig')));
    RAISE SQLSTATE 'W1C99';
  EXCEPTION WHEN SQLSTATE 'W1C99' THEN
    NULL;
  END;
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "reverify_device"}, {"ok": false, "reason": "reverify_device"},
                              {"ok": false, "reason": "not_eligible"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the setup guard let an untrusted device or an unknown eligibility through: %', v_got;
  END IF;
  IF pg_temp.snapshot(v_u) IS DISTINCT FROM v_before
     OR (SELECT children_have FROM public.dating_profiles WHERE user_id = v_u) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a guarded-out setup step wrote a row';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE OR public.dating_eligibility(v_u, 'setup') IS DISTINCT FROM 'eligible' THEN
    RAISE EXCEPTION 'fixture: the guard stubs were not rolled back';
  END IF;
END $$;

-- =====================================================================
-- K. A setup step never reopens an enrolment that is active, paused or
--    suspended (only ineligible, eligible_to_opt_in and exited become
--    profile_draft).
-- =====================================================================
DO $$
DECLARE
  v_state text;
  v_n int := 0;
  v_x uuid;
BEGIN
  FOREACH v_state IN ARRAY ARRAY['active', 'paused', 'suspended', 'exited', 'eligible_to_opt_in'] LOOP
    v_n := v_n + 1;
    v_x := pg_temp.person('2' || v_n);
    INSERT INTO public.dating_enrollments (user_id, state, exited_at)
    VALUES (v_x, v_state, CASE WHEN v_state = 'exited' THEN now() - interval '1 day' END);
    PERFORM pg_temp.call(v_x, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', pg_temp.key('k')));
    IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_x)
         IS DISTINCT FROM (CASE WHEN v_state IN ('exited', 'eligible_to_opt_in') THEN 'profile_draft' ELSE v_state END) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a setup step moved a % enrolment to %', v_state,
        (SELECT state FROM public.dating_enrollments WHERE user_id = v_x);
    END IF;
    IF v_state = 'exited' AND (SELECT exited_at FROM public.dating_enrollments WHERE user_id = v_x) IS NOT NULL THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: re-entering setup kept the old exited_at';
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- L. No answer raises (I-2 sweep): every writer, with NULL in each
--    argument, all NULL, and 5000-character text in each text argument,
--    in a same-gender-on and a same-gender-off country, answers jsonb and
--    never raises (a raised constraint error echoes the row in DETAIL).
-- =====================================================================
DO $$
DECLARE
  v_people uuid[];
  v_calls constant text[] := ARRAY[
    'save_dating_intention|''marriage''|''within_two_years''|true|true|''divorced''|true',
    'save_dating_location|''GH''|''AA''|''tema''|''side''',
    'save_dating_identity|''non_binary''|''Two spirit''|''they/them''|ARRAY[''woman'']|true',
    'save_dating_who_to_meet|ARRAY[''man'']|25|35',
    'save_dating_children|true|''open''|true|true',
    'save_dating_faith|''christian''|''catholic''|''must_share''|true',
    'clear_dating_faith',
    -- Batch 8 (Task 10).
    'save_dating_prompts|''[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}, {"prompt_id": "ask_me_about", "answer": "Ask me about Busua."}]''::jsonb',
    'save_dating_display_name|''Ama''',
    'save_dating_family_involvement|''early''',
    'save_dating_settings|''{"drop_time": "21:30", "digest_push": true}''::jsonb',
    'set_dating_open_abroad|ARRAY[''GH'']::char(2)[]',
    -- Fix round 1 (M-11): the exposure-reducing branches.
    'set_dating_open_abroad|ARRAY[]::char(2)[]',
    'save_dating_settings|''{"chat_push": false, "data_saver": true}''::jsonb',
    'set_dating_photos_after_mutual|true',
    -- Batch 9 (Task 11): never introduce (exposure-reducing, so it also
    -- runs for the person whose country closes).
    'add_dating_never_introduce|''+447700900123''|''Ex'''];
  v_long constant text := quote_literal(repeat('x', 5000));
  v_u uuid;
  v_c text;
  v_parts text[];
  v_args text[];
  v_try text[];
  v_sql text;
  v_bad text[] := ARRAY[]::text[];
  v_n int := 0;
  i int;
BEGIN
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  v_people := ARRAY[pg_temp.located('41', 'GB', 'TLD'), pg_temp.located('42', 'GH', 'AA'),
    -- Fix round 1 (M-11): past other countries' gates (verified, the age
    -- gate, 40 days), not plain and plain; and one whose Dating country is
    -- closed during its calls (the exposure-reducing branches).
    pg_temp.ready('87', 'GB', 'TLD', 'non_binary', ARRAY['man', 'non_binary', 'woman'], ARRAY['woman']),
    pg_temp.ready('88', 'GB', 'TLD', 'woman', ARRAY['man']),
    pg_temp.located('89', 'GH', 'AA')];
  FOREACH v_u IN ARRAY v_people LOOP
    IF v_u = v_people[5] THEN
      PERFORM public.publish_country_config('GH', '{"dating_enabled": false}');
    END IF;
    FOREACH v_c IN ARRAY v_calls LOOP
      v_parts := string_to_array(v_c, '|');
      v_args := v_parts[2:];
      FOR i IN 0 .. 2 * coalesce(cardinality(v_args), 0) + 1 LOOP
        v_try := v_args;
        CONTINUE WHEN i > 0 AND coalesce(cardinality(v_args), 0) = 0;
        IF i = 0 THEN
          NULL;                                             -- as given
        ELSIF i <= cardinality(v_args) THEN
          v_try[i] := 'NULL';                               -- one NULL
        ELSIF i <= 2 * cardinality(v_args) THEN
          CONTINUE WHEN left(v_args[i - cardinality(v_args)], 1) <> '''' AND left(v_args[i - cardinality(v_args)], 6) <> 'ARRAY[';
          v_try[i - cardinality(v_args)] := CASE
            WHEN right(v_args[i - cardinality(v_args)], 7) = '::jsonb'                -- one long JSON (batch 8)
              THEN quote_literal(regexp_replace(substring(v_args[i - cardinality(v_args)] FROM 2
                                                          FOR char_length(v_args[i - cardinality(v_args)]) - 9),
                                                '": "[^"]*"', '": "' || repeat('x', 5000) || '"', 'g')) || '::jsonb'
            WHEN left(v_args[i - cardinality(v_args)], 1) = '''' THEN v_long
            ELSE 'ARRAY[' || v_long || ']' END;   -- one long text
        ELSE
          SELECT array_agg('NULL'::text) INTO v_try FROM unnest(v_args);  -- all NULL
        END IF;
        v_sql := format('SELECT public.%s(%L%s)', v_parts[1], pg_temp.key('L'),
                        CASE WHEN coalesce(cardinality(v_try), 0) > 0 THEN ', ' || array_to_string(v_try, ', ') ELSE '' END);
        v_n := v_n + 1;
        BEGIN
          PERFORM pg_temp.call(v_u, v_sql);
        EXCEPTION WHEN OTHERS THEN
          RESET ROLE;
          v_bad := v_bad || format('%s [%s %s]', left(v_sql, 120), SQLSTATE, SQLERRM);
        END;
      END LOOP;
    END LOOP;
    IF v_u = v_people[5] THEN
      PERFORM public.publish_country_config('GH', '{"dating_enabled": true}');
    END IF;
  END LOOP;
  IF (SELECT count(DISTINCT n.owner_user_id) FROM public.dating_never_introduce AS n WHERE n.owner_user_id = ANY (v_people)) < 4 THEN
    RAISE EXCEPTION 'fixture: the sweep''s never-introduce adds reached too few people';
  END IF;
  -- Batch 8: both readers, for every person, after everything above.
  -- Batch 9 (Task 11): the never-introduce list and remove (NULL, an
  -- unknown id, someone else's row and the person's own).
  FOREACH v_u IN ARRAY v_people LOOP
    FOREACH v_c IN ARRAY ARRAY['get_my_dating_profile()', 'get_dating_profile_preview()',
                               'list_dating_never_introduce()', 'remove_dating_never_introduce(NULL)',
                               format('remove_dating_never_introduce(%L)', gen_random_uuid()),
                               format('remove_dating_never_introduce(%L)',
                                      (SELECT n.id FROM public.dating_never_introduce AS n WHERE n.owner_user_id <> v_u LIMIT 1)),
                               format('remove_dating_never_introduce(%L)',
                                      (SELECT n.id FROM public.dating_never_introduce AS n WHERE n.owner_user_id = v_u LIMIT 1))] LOOP
      v_n := v_n + 1;
      BEGIN
        PERFORM pg_temp.call(v_u, format('SELECT public.%s', v_c));
      EXCEPTION WHEN OTHERS THEN
        RESET ROLE;
        v_bad := v_bad || format('%s [%s %s]', v_c, SQLSTATE, SQLERRM);
      END;
    END LOOP;
  END LOOP;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % of % writer calls raised instead of answering: %', cardinality(v_bad), v_n, v_bad[1];
  END IF;
  IF v_n < 400 THEN
    RAISE EXCEPTION 'fixture: the sweep ran only % calls', v_n;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM bystander AS b WHERE pg_temp.rows_of(b.user_id) IS DISTINCT FROM b.rows) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a writer or reader changed another person''s rows (the bystander, after %)', 'I, K and L';
  END IF;
END $$;

-- =====================================================================
-- L2. (W1d, Task 12) The lifecycle RPCs and the consent writer, swept as
--     in L: NULL in each argument, all NULL, 5000-character text in each
--     text argument, for a complete person, a paused complete person, a
--     located person and an account with no Dating rows. They may refuse
--     only with their own named 22023/42501 messages (never a raw
--     constraint error, whose DETAIL echoes the row) and never with a
--     DETAIL. The exits run last.
-- =====================================================================
DO $$
DECLARE
  v_people uuid[];
  v_calls constant text[] := ARRAY[
    'record_dating_consent|''w1d-L2-consent-grant''|''dating_terms''|''granted''|''dating-2.0''|''["terms"]''::jsonb',
    'record_dating_consent|''w1d-L2-consent-faith''|''special_category_faith''|''withdrawn''|''dating-2.0''|''[]''::jsonb',
    'activate_dating_profile|''w1d-L2-activate-01''',
    'pause_dating_mode|''w1d-L2-pause-0001''',
    'resume_dating_mode|''w1d-L2-resume-001''',
    'activate_dating_profile|''w1d-L2-activate-02''',
    'exit_dating_mode|''w1d-L2-exit-00001''|true',
    'record_dating_consent|''w1d-L2-consent-optout''|''dating_opt_in''|''withdrawn''|''dating-2.0''|''[]''::jsonb'];
  v_allowed constant text[] := ARRAY['not_authenticated', 'reverify_device', 'idempotency_key_required',
    'idempotency_key_invalid', 'invalid_consent_event', 'rate_limited', 'activation_gates_not_met',
    'enrollment_incomplete', 'profile_or_preferences_incomplete', 'not_paused', 'resume_gates_not_met',
    -- fix round 1 (I-1, M-3, M-4)
    'consent_required', 'idempotency_key_reused', 'activation_required'];
  v_long constant text := quote_literal(repeat('x', 5000));
  v_u uuid;
  v_c text;
  v_parts text[];
  v_args text[];
  v_try text[];
  v_sql text;
  v_state text;
  v_msg text;
  v_detail text;
  v_bad text[] := ARRAY[]::text[];
  v_n int := 0;
  v_ok int := 0;
  i int;
BEGIN
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  v_people := ARRAY[pg_temp.ready('95', 'GB', 'TLD', 'woman', ARRAY['man']), pg_temp.ready('98', 'GB', 'TLD', 'man', ARRAY['woman']),
                    pg_temp.located('96', 'GH', 'AA'), pg_temp.person('97')];
  -- 95 and 98 complete (D7, two prompts, two photos); 98 paused.
  FOREACH v_u IN ARRAY v_people[1:2] LOOP
    PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_children(%L, false, ''yes'', false, false)', pg_temp.key('d7')));
    PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_prompts(%L, %L::jsonb)', pg_temp.key('d10'),
      '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}, {"prompt_id": "ask_me_about", "answer": "Ask me about Busua."}]'));
    INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state)
    SELECT v_u, 'w1d-L2/' || v_u || '-' || n || '.jpg', n, 'approved' FROM generate_series(1, 2) AS n;
    IF NOT public.dating_profile_complete(v_u) THEN
      RAISE EXCEPTION 'fixture: L2''s complete person is not complete';
    END IF;
  END LOOP;
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user', paused_at = now(), activated_at = now() - interval '1 day'
   WHERE user_id = v_people[2];
  UPDATE public.dating_profiles SET profile_state = 'paused' WHERE user_id = v_people[2];
  FOREACH v_u IN ARRAY v_people LOOP
    FOREACH v_c IN ARRAY v_calls LOOP
      v_parts := string_to_array(v_c, '|');
      v_args := v_parts[2:];
      FOR i IN 0 .. 2 * cardinality(v_args) + 1 LOOP
        v_try := v_args;
        IF i = 0 THEN
          NULL;                                             -- as given
        ELSIF i <= cardinality(v_args) THEN
          v_try[i] := 'NULL';                               -- one NULL
        ELSIF i <= 2 * cardinality(v_args) THEN
          CONTINUE WHEN left(v_args[i - cardinality(v_args)], 1) <> '''';
          v_try[i - cardinality(v_args)] := CASE
            WHEN right(v_args[i - cardinality(v_args)], 7) = '::jsonb'
              THEN quote_literal(jsonb_build_array(repeat('x', 5000))::text) || '::jsonb'  -- one long JSON
            ELSE v_long END;                                -- one long text
        ELSE
          SELECT array_agg('NULL'::text) INTO v_try FROM unnest(v_args);  -- all NULL
        END IF;
        -- A fresh key for every call that keeps one (a replay would hide the work).
        IF v_try[1] = v_args[1] THEN
          v_try[1] := quote_literal(pg_temp.key('L2'));
        END IF;
        v_sql := format('SELECT to_jsonb(public.%s(%s)::text)', v_parts[1], array_to_string(v_try, ', '));
        v_n := v_n + 1;
        BEGIN
          PERFORM pg_temp.call(v_u, v_sql);
          v_ok := v_ok + 1;
        EXCEPTION WHEN OTHERS THEN
          GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL;
          RESET ROLE;
          IF v_state NOT IN ('22023', '42501') OR NOT (v_msg = ANY (v_allowed)) OR coalesce(v_detail, '') <> '' THEN
            v_bad := v_bad || format('%s [%s %s %s]', left(v_sql, 120), v_state, v_msg, v_detail);
          END IF;
        END;
      END LOOP;
    END LOOP;
  END LOOP;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % of % lifecycle calls raised a raw or unnamed error: %', cardinality(v_bad), v_n, v_bad[1];
  END IF;
  IF v_n < 150 OR v_ok < 20 THEN
    RAISE EXCEPTION 'fixture: L2 ran only % calls (% answered)', v_n, v_ok;
  END IF;
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_people[1]) IS DISTINCT FROM 'exited'
     OR EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = ANY (v_people)) THEN
    RAISE EXCEPTION 'fixture: L2''s exits did not run';
  END IF;
END $$;

-- =====================================================================
-- J. Without dating_field_key every special-category writer answers
--    unavailable, raises nothing and changes nothing (§4.2).
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('13', 'GH', 'AA');
  v_before text;
  v jsonb;
  v_k constant text[] := ARRAY[pg_temp.key('r2'), pg_temp.key('r5'), pg_temp.key('r6'), pg_temp.key('r8')];
  v_first jsonb;
  v_noid constant uuid := pg_temp.located('47', 'GH', 'AA');
BEGIN
  -- M-1: four steps answered while the key is present...
  v_first := jsonb_build_array(
    pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', v_k[1])),
    pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, false)', v_k[2])),
    pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)', v_k[3])),
    pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''christian'', NULL, ''must_share'', false)', v_k[4])));
  IF v_first IS DISTINCT FROM '[{"ok": true, "next_step": "where"}, {"ok": true, "next_step": "meet"},
                                {"ok": true, "next_step": "children"}, {"ok": true, "next_step": "photos"}]'::jsonb THEN
    RAISE EXCEPTION 'fixture: the J steps failed: %', v_first;
  END IF;
  PERFORM set_config('app.settings.dating_field_key', '', true);
  v_before := pg_temp.snapshot(v_u);
  BEGIN
    v := jsonb_build_array(
      pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, ''widowed'', false)', pg_temp.key('k'))),
      pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, false)', pg_temp.key('k'))),
      pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)', pg_temp.key('k'))),
      pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''christian'', NULL, ''must_share'', false)', pg_temp.key('k'))),
      -- Batch 7: D2 without a marriage answer is still unavailable (no step before the key).
      pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', pg_temp.key('k'))),
      -- ...and replayed once it is gone: unavailable, never a stale ok.
      pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', v_k[1])),
      pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, false)', v_k[2])),
      pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)', v_k[3])),
      pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''christian'', NULL, ''must_share'', false)', v_k[4])),
      -- D6 for a person with no identity yet: unavailable (the key first), not invalid.
      pg_temp.call(v_noid, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)', pg_temp.key('k'))));
  EXCEPTION WHEN raise_exception THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: without dating_field_key a writer raised (%) instead of answering unavailable', SQLERRM;
  END;
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1c-contract-field-key-0123456789abcdef', true);
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"},
                          {"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"},
                          {"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"},
                          {"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"},
                          {"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without dating_field_key a special-category writer did not answer unavailable: %', v;
  END IF;
  IF pg_temp.snapshot(v_u) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without dating_field_key a writer changed a row';
  END IF;
END $$;

-- =====================================================================
-- J2. An unreadable stored value (tampered, unknown version) answers
--     unavailable from the writers that decrypt, raises nothing and
--     changes nothing (batch-6 carry: field_decrypt_failed).
-- J3. A key that vanishes mid-write (key_present() stubbed true over an
--     empty key, so encrypt and decrypt raise field_key_missing) answers
--     unavailable from every special-category writer, and the step's claim,
--     rows and counters are all undone.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('15', 'GH', 'AA');
  v_w constant uuid := pg_temp.located('16', 'GH', 'AA');
  v_before text;
  v jsonb;
  v_got jsonb := '[]'::jsonb;
BEGIN
  IF pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, false)', pg_temp.key('d5'))) IS DISTINCT FROM '{"ok": true, "next_step": "meet"}'::jsonb
     OR pg_temp.call(v_w, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, false)', pg_temp.key('d5'))) IS DISTINCT FROM '{"ok": true, "next_step": "meet"}'::jsonb THEN
    RAISE EXCEPTION 'fixture: D5 failed';
  END IF;
  -- J2: an unknown key version in byte 0.
  UPDATE public.dating_profile_sensitive SET identity_enc = '\x02'::bytea || substring(identity_enc FROM 2) WHERE user_id = v_u;
  v_before := pg_temp.snapshot(v_u);
  BEGIN
    v := jsonb_build_array(
      pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)', pg_temp.key('j2'))),
      pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''man'', NULL, NULL, NULL, false)', pg_temp.key('j2'))));
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable stored answer made a writer raise (%)', SQLERRM;
  END;
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable stored answer did not answer unavailable: %', v;
  END IF;
  IF pg_temp.snapshot(v_u) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable stored answer let a writer change a row or a counter';
  END IF;
  -- J3: the key vanishes after the presence check.
  v_before := pg_temp.snapshot(v_w);
  BEGIN
    CREATE OR REPLACE FUNCTION private.dating_field_key_present() RETURNS boolean
      LANGUAGE sql STABLE SET search_path = '' AS $stub$ SELECT true $stub$;
    PERFORM set_config('app.settings.dating_field_key', '', true);
    BEGIN
      v_got := jsonb_build_array(
        pg_temp.call(v_w, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, ''widowed'', false)', pg_temp.key('j3'))),
        pg_temp.call(v_w, format('SELECT public.save_dating_identity(%L, ''man'', NULL, NULL, NULL, false)', pg_temp.key('j3'))),
        pg_temp.call(v_w, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)', pg_temp.key('j3'))),
        pg_temp.call(v_w, format('SELECT public.save_dating_faith(%L, ''christian'', NULL, ''must_share'', false)', pg_temp.key('j3'))));
    EXCEPTION WHEN OTHERS THEN
      v_got := to_jsonb('raised: ' || SQLERRM);
    END;
    IF pg_temp.snapshot(v_w) IS DISTINCT FROM v_before THEN
      v_got := v_got || '["changed"]'::jsonb;
    END IF;
    RAISE SQLSTATE 'W1C99';
  EXCEPTION WHEN SQLSTATE 'W1C99' THEN
    NULL;
  END;
  RESET ROLE;
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"},
                              {"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a key lost mid-write did not answer unavailable with nothing changed: %', v_got;
  END IF;
  IF private.dating_field_key_present() IS NOT TRUE
     OR current_setting('app.settings.dating_field_key', true) IS DISTINCT FROM 'spec2-w1c-contract-field-key-0123456789abcdef' THEN
    RAISE EXCEPTION 'fixture: the key stub was not rolled back';
  END IF;
END $$;

-- =====================================================================
-- M2. (W1 final fix, M-2; the final review's race r3c, sequential) Moving
--     one's Dating country into a country whose same-gender rule is off
--     gives the mover's pairs the kill switch's restrictive treatment,
--     judged by the answers held before the move: a woman-woman match
--     closes ('other', sealed 30 days), their open introduction ends, and
--     the mover is paused (same_gender_switch); her man-woman match stays,
--     the other person is untouched, and nothing is sent. As the switch: a
--     plain mover is not paused, even when a pair of hers that isn't
--     man-woman closes; a mover with no answer in a pair is. (Same-gender
--     on in the UK here, off in Ghana; all undone after.)
-- =====================================================================
DO $$
DECLARE
  v_y uuid;
  v_x uuid;
  v_z uuid;
  v_w uuid;
  v_z2 uuid;
  v_m_xy uuid;
  v_m_xz uuid;
  v_m_wz uuid;
  v_v uuid;
  v_nb uuid;
  v_n uuid;
  v_m_vnb uuid;
  v_i_n uuid;
  v_i_xy uuid;
  v_s_low uuid;
  v_s_high uuid;
  v_y_before text;
  v_sent bigint;
  v_got jsonb;
  v_bad text;
BEGIN
  BEGIN
    UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
    IF private.dating_same_gender_on('GB') IS NOT TRUE OR private.dating_same_gender_on('GH') IS NOT FALSE THEN
      RAISE EXCEPTION 'fixture: M2 needs same-gender on in the UK and off in Ghana';
    END IF;
    v_y := pg_temp.ready('26', 'GB', 'TLI', 'woman', ARRAY['woman']);
    v_x := pg_temp.ready('27', 'GB', 'TLI', 'woman', ARRAY['woman']);
    v_z := pg_temp.ready('28', 'GB', 'TLI', 'man', ARRAY['woman']);
    v_w := pg_temp.ready('29', 'GB', 'TLI', 'woman', ARRAY['man']);
    v_z2 := pg_temp.ready('38', 'GB', 'TLI', 'man', ARRAY['woman']);
    v_v := pg_temp.ready('17', 'GB', 'TLI', 'woman', ARRAY['man']);
    v_nb := pg_temp.ready('18', 'GB', 'TLI', 'non_binary', ARRAY['man', 'non_binary', 'woman']);
    v_n := pg_temp.located('19', 'GB', 'TLI'); -- no identity answered yet
    UPDATE public.dating_profiles SET profile_state = 'active' WHERE user_id IN (v_y, v_x, v_z, v_w, v_z2, v_v, v_nb, v_n);
    UPDATE public.dating_enrollments SET state = 'active', activated_at = now() WHERE user_id IN (v_y, v_x, v_z, v_w, v_z2, v_v, v_nb, v_n);
    INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(v_v, v_nb), greatest(v_v, v_nb), 'active')
    RETURNING id INTO v_m_vnb;
    INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(v_x, v_y), greatest(v_x, v_y), 'active')
    RETURNING id INTO v_m_xy;
    INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(v_x, v_z), greatest(v_x, v_z), 'active')
    RETURNING id INTO v_m_xz;
    INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(v_w, v_z2), greatest(v_w, v_z2), 'active')
    RETURNING id INTO v_m_wz;
    INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (least(v_x, v_y), 'w1final-m2') RETURNING id INTO v_s_low;
    INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (greatest(v_x, v_y), 'w1final-m2') RETURNING id INTO v_s_high;
    INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, display_band, state, algorithm_version,
                                             snapshot_low_id, snapshot_high_id, internal_score)
    VALUES (public.dating_pair_key(v_x, v_y), least(v_x, v_y), greatest(v_x, v_y), 'some_shared_ground', 'presented', 'w1final-m2',
            v_s_low, v_s_high, 0.5)
    RETURNING id INTO v_i_xy;
    INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (least(v_n, v_z2), 'w1final-m2') RETURNING id INTO v_s_low;
    INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (greatest(v_n, v_z2), 'w1final-m2') RETURNING id INTO v_s_high;
    INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, display_band, state, algorithm_version,
                                             snapshot_low_id, snapshot_high_id, internal_score)
    VALUES (public.dating_pair_key(v_n, v_z2), least(v_n, v_z2), greatest(v_n, v_z2), 'some_shared_ground', 'presented', 'w1final-m2',
            v_s_low, v_s_high, 0.5)
    RETURNING id INTO v_i_n;
    v_y_before := pg_temp.rows_of(v_y);
    v_sent := (SELECT count(*) FROM public.scheduled_notifications) + (SELECT count(*) FROM public.in_app_notifications);

    v_got := jsonb_build_array(
      pg_temp.call(v_x, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''region'')', pg_temp.key('m2'))),
      pg_temp.call(v_w, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''region'')', pg_temp.key('m2'))),
      pg_temp.call(v_v, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''region'')', pg_temp.key('m2'))),
      pg_temp.call(v_n, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''region'')', pg_temp.key('m2'))));
    v_bad := concat_ws('; ',
      CASE WHEN v_got IS DISTINCT FROM (SELECT jsonb_agg('{"ok": true, "next_step": "privacy"}'::jsonb) FROM generate_series(1, 4))
           THEN 'the moves answered ' || v_got::text END,
      CASE WHEN (SELECT state || '/' || closed_reason || '/' || (evidence_until BETWEEN now() + interval '29 days' AND now() + interval '31 days')
                   FROM public.dating_matches WHERE id = v_m_xy) IS DISTINCT FROM 'closed/other/true'
           THEN 'the woman-woman match was not closed (other, sealed 30 days)' END,
      CASE WHEN (SELECT state FROM public.dating_introductions WHERE id = v_i_xy) IS DISTINCT FROM 'invalidated'
           THEN 'their introduction stayed open' END,
      CASE WHEN (SELECT state FROM public.dating_matches WHERE id = v_m_xz) IS DISTINCT FROM 'active'
           THEN 'her man-woman match was closed' END,
      CASE WHEN (SELECT e.state || '/' || e.pause_reason || '/' || p.profile_state
                   FROM public.dating_enrollments AS e JOIN public.dating_profiles AS p USING (user_id) WHERE e.user_id = v_x)
                IS DISTINCT FROM 'paused/same_gender_switch/paused'
           THEN 'the mover was not paused (same_gender_switch)' END,
      CASE WHEN (SELECT state FROM public.dating_matches WHERE id = v_m_wz) IS DISTINCT FROM 'active'
                OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_w) IS DISTINCT FROM 'active'
           THEN 'a plain mover was paused or lost her man-woman match' END,
      CASE WHEN pg_temp.rows_of(v_y) IS DISTINCT FROM v_y_before THEN 'the other woman''s rows changed' END,
      CASE WHEN (SELECT state || '/' || closed_reason FROM public.dating_matches WHERE id = v_m_vnb) IS DISTINCT FROM 'closed/other'
                OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_v) IS DISTINCT FROM 'active'
           THEN 'a plain mover''s match with a non-binary person did not close, or she was paused' END,
      CASE WHEN (SELECT state FROM public.dating_introductions WHERE id = v_i_n) IS DISTINCT FROM 'invalidated'
                OR (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_n) IS DISTINCT FROM 'paused/same_gender_switch'
           THEN 'a mover with no answer in an introduction was not paused' END,
      CASE WHEN (SELECT count(*) FROM public.scheduled_notifications) + (SELECT count(*) FROM public.in_app_notifications) IS DISTINCT FROM v_sent
           THEN 'something was sent' END);
    IF v_bad IS DISTINCT FROM '' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: moving into a same-gender-off country: %', v_bad;
    END IF;
    RAISE SQLSTATE 'W1F99';
  EXCEPTION WHEN SQLSTATE 'W1F99' THEN
    NULL;
  END;
  IF private.dating_same_gender_on('GB') IS NOT FALSE OR EXISTS (SELECT 1 FROM public.users WHERE id = pg_temp.id('27')) THEN
    RAISE EXCEPTION 'fixture: section M2 was not undone';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'dating_v2_setup_contracts: all held'; END $$;
ROLLBACK;
