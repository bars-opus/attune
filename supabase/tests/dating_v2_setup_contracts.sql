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
-- Spec 2 W3c (R-24): this file's photo fixtures stand for photos the
-- inline CSAM scan cleared (an approval needs csam_state 'clear');
-- rolled back with the file.
ALTER TABLE public.dating_profile_photos ALTER COLUMN csam_state SET DEFAULT 'clear';

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
    -- Spec 2 W3c (R11): no client reads the photo table any more.
    IF v_role = 'authenticated' AND has_table_privilege('authenticated', 'public.dating_profile_photos', 'SELECT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated can read dating_profile_photos';
    END IF;
    WITH u AS (UPDATE storage.objects SET metadata = '{"w1c": true}'::jsonb
                WHERE bucket_id = 'dating-profile-photos' AND name = v_key1 RETURNING 1)
    SELECT count(*) INTO v_upd FROM u;
    WITH d AS (DELETE FROM storage.objects WHERE bucket_id = 'dating-profile-photos' AND name = v_key1 RETURNING 1)
    SELECT count(*) INTO v_del FROM d;
    RESET ROLE;
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '', true);
    IF v_read IS DISTINCT FROM (CASE WHEN v_x = v_u THEN 1 ELSE 0 END)::bigint OR v_upd <> 0 OR v_del <> 0 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % (%) reads % / updates % / deletes % Dating photo rows and objects (stranger 0/0/0, owner 1/0/0)',
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
  -- Spec 2 W2: get_dating_home's resume step counts the person's own
  -- approved photos (private.dating_next_step, no API role).
  -- Spec 2 W3c: the v2 photo RPCs (the app's), the owner-read storage
  -- predicate (the app's: it runs inside the storage policy) and the CSAM
  -- recorder and the orphan sweep (the service role's, I-14). None returns
  -- a photo to anyone else.
  -- Spec 2 W3c (M-11): has_data reads only whether the person's own
  -- photo or upload intent exists (the database's own; get_dating_home).
  -- Spec 2 W3 final: the bucket-limit helper (M-3, the database's own),
  -- the strip check (M-5) and the job recovery (I-2: it re-queues a photo
  -- dead-lettered unscanned), the service role's. None returns a photo.
  IF v_got IS DISTINCT FROM 'private.dating_exit_internal(uuid, boolean):; private.dating_has_data(uuid):; private.dating_next_step(uuid):; private.dating_photo_bucket_limits():; public.check_dating_photo_strip(uuid, text, text):service_role; public.claim_dating_orphan_uploads(integer):service_role; public.create_dating_photo_upload_intent(text):authenticated; public.dating_photos_queue_media_before_delete():; public.dating_profile_complete(uuid):; public.dating_storage_owns(text):authenticated; public.delete_dating_profile_photo(uuid):authenticated; public.get_dating_operational_health():service_role; public.get_dating_profile_preview():authenticated; public.insert_dating_profile_photo(uuid, smallint):authenticated; public.list_dating_profile_photos():authenticated; public.prepare_account_deletion(uuid):service_role; public.record_dating_orphan_scan(uuid, text):service_role; public.record_dating_photo_csam(uuid, text):service_role; public.recover_stale_dating_photo_jobs():service_role; public.reorder_dating_photos(text, uuid[]):authenticated; public.set_dating_photo_caption(uuid, text):authenticated' THEN
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
-- =====================================================================
-- M. (W3b, §2.2, R-19) The reviewed faith lists, as the W3b migration
--    published them (this file's own fixture republished GH's list for its
--    D8 rows, so the migration's version is found by its publisher).
-- =====================================================================
DO $m$
DECLARE
  v_gh jsonb;
  v_gb jsonb;
BEGIN
  SELECT c.faith_list INTO v_gh FROM public.country_safety_config AS c
   WHERE c.country_code = 'GH' AND c.published_by = 'migration:dating_v2_setup_lists';
  SELECT c.faith_list INTO v_gb FROM public.country_safety_config AS c
   WHERE c.country_code = 'GB' AND c.published_by = 'migration:dating_v2_setup_lists';
  IF (SELECT array_agg(f ->> 'code' ORDER BY ord) FROM jsonb_array_elements(v_gh) WITH ORDINALITY AS x(f, ord))
       IS DISTINCT FROM ARRAY['christian', 'muslim', 'traditional', 'other', 'none', 'prefer_not_to_say']
     OR (SELECT array_agg(d ->> 'code' ORDER BY ord) FROM jsonb_array_elements(v_gh -> 0 -> 'denominations') WITH ORDINALITY AS x(d, ord))
       IS DISTINCT FROM ARRAY['catholic', 'anglican', 'methodist', 'presbyterian', 'pentecostal_charismatic', 'seventh_day_adventist', 'other_christian'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Ghana faith list is not the reviewed one: %', v_gh;
  END IF;
  IF (SELECT array_agg(f ->> 'code' ORDER BY ord) FROM jsonb_array_elements(v_gb) WITH ORDINALITY AS x(f, ord))
       IS DISTINCT FROM ARRAY['christian', 'muslim', 'hindu', 'sikh', 'jewish', 'buddhist', 'other', 'none', 'prefer_not_to_say']
     OR (SELECT array_agg(d ->> 'code' ORDER BY ord) FROM jsonb_array_elements(v_gb -> 0 -> 'denominations') WITH ORDINALITY AS x(d, ord))
       IS DISTINCT FROM ARRAY['catholic', 'church_of_england_anglican', 'orthodox', 'pentecostal_charismatic', 'other_christian'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the UK faith list is not the reviewed one: %', v_gb;
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_gh || v_gb) AS f
              WHERE f ->> 'name_key' IS DISTINCT FROM 'dating_faith_' || (f ->> 'code')
                 OR EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(f -> 'denominations', '[]'::jsonb)) AS d
                             WHERE d ->> 'name_key' IS DISTINCT FROM 'dating_denomination_' || (d ->> 'code'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a faith name_key breaks the dating_faith_/dating_denomination_ convention';
  END IF;
  -- Publishing a list never opened or closed a country.
  IF EXISTS (SELECT 1 FROM public.country_safety_config AS c
              WHERE c.published_by = 'migration:dating_v2_setup_lists'
                AND c.dating_enabled IS DISTINCT FROM (SELECT p.dating_enabled FROM public.country_safety_config AS p
                                                        WHERE p.country_code = c.country_code AND p.version = c.version - 1)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the faith-list publish changed a country''s dating_enabled';
  END IF;
END $m$;

-- =====================================================================
-- N. (W3b, R-17, R-18) get_dating_setup_lists: signed in; the device
--    check; every open country's regions (open or not, with sides), faith
--    list and same-gender switch; the person's own phone country, the
--    country note's country (Tier 1/2 phone countries only) and default ages.
-- =====================================================================
DO $n$
DECLARE
  v_us constant uuid := pg_temp.ready('a0', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_gh constant uuid := pg_temp.id('a1');
  v_young constant uuid := pg_temp.id('a2');
  v jsonb;
  v_msg text;
  v_country jsonb;
  v_got jsonb := '[]'::jsonb; -- T5 fix round 1 (I-1)
BEGIN
  BEGIN
    PERFORM public.get_dating_setup_lists();
    RAISE EXCEPTION 'CONTRACT VIOLATED: the lists answered a signed-out caller';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'not_authenticated' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: signed out raised %', v_msg;
    END IF;
  END;
  -- A UK phone (Tier 3): its country is read, and Tier 3 gets no note. (The
  -- fixture's own +1 555 phone has no country, so no note either way.)
  -- T5 fix round 1 (M-2): public.users carries a Ghana number, so a
  -- reader of that tamperable copy reads GH and a note.
  UPDATE auth.users SET phone = '447700900' || '190' WHERE id = v_us;
  UPDATE public.users SET phone = '233558703' || '99' WHERE id = v_us;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  v := pg_temp.call(v_us, 'SELECT public.get_dating_setup_lists()');
  IF (v ->> 'ok')::boolean IS NOT TRUE
     -- (Earlier sections of this file open other countries: only GB and GH
     -- are this section's.)
     OR (SELECT array_agg(c ->> 'code' ORDER BY c ->> 'code') FROM jsonb_array_elements(v -> 'countries') AS c
          WHERE c ->> 'code' IN ('GB', 'GH')) IS DISTINCT FROM ARRAY['GB', 'GH'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the lists are not GB and GH: %', v;
  END IF;
  SELECT c INTO v_country FROM jsonb_array_elements(v -> 'countries') AS c WHERE c ->> 'code' = 'GH';
  IF v_country ->> 'same_gender' IS DISTINCT FROM 'false'
     OR jsonb_array_length(v_country -> 'regions') <> 16
     OR (SELECT r ->> 'open' FROM jsonb_array_elements(v_country -> 'regions') AS r WHERE r ->> 'code' = 'AA') IS DISTINCT FROM 'true'
     OR (SELECT r ->> 'open' FROM jsonb_array_elements(v_country -> 'regions') AS r WHERE r ->> 'code' = 'TV') IS DISTINCT FROM 'false'
     OR (SELECT jsonb_array_length(r -> 'sides') FROM jsonb_array_elements(v_country -> 'regions') AS r WHERE r ->> 'code' = 'AA') <> 2
     OR v_country -> 'faiths' IS DISTINCT FROM (public.dating_country_config('GH')).faith_list THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ghana''s lists read %', v_country;
  END IF;
  SELECT c INTO v_country FROM jsonb_array_elements(v -> 'countries') AS c WHERE c ->> 'code' = 'GB';
  IF v_country ->> 'same_gender' IS DISTINCT FROM 'true' OR jsonb_array_length(v_country -> 'regions') <> 12 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the UK''s lists read %', v_country;
  END IF;
  IF v -> 'note_country' IS DISTINCT FROM 'null'::jsonb OR v ->> 'phone_country' IS DISTINCT FROM 'GB'
     OR v -> 'default_ages' IS DISTINCT FROM '[25, 35]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 30-year-old with a Tier 3 phone reads note % ages %', v -> 'note_country', v -> 'default_ages';
  END IF;
  -- A Ghana phone (Tier 1): the note names Ghana. A 19-year-old: 18 to 26.
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES
    (v_gh, '233558703' || '91', now(), now() - interval '40 days'),
    (v_young, '15558709' || '92', now(), now() - interval '40 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version) VALUES
    -- T5 fix round 1 (M-2): a UK copy in public.users; auth.users says Ghana.
    (v_gh, '447700900' || '191', 'Lists a1', 'dating', now() - interval '40 days', now(), '2'),
    (v_young, '15558709' || '92', 'Lists a2', 'dating', now() - interval '40 days', now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES
    (v_gh, current_date - interval '30 years'), (v_young, current_date - interval '19 years 10 days');
  IF pg_temp.call(v_gh, 'SELECT public.get_dating_setup_lists()') ->> 'note_country' IS DISTINCT FROM 'GH'
     OR pg_temp.call(v_gh, 'SELECT public.get_dating_setup_lists()') ->> 'phone_country' IS DISTINCT FROM 'GH'
     OR pg_temp.call(v_young, 'SELECT public.get_dating_setup_lists()') -> 'default_ages' IS DISTINCT FROM '[18, 26]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the note or the 18-20 default ages are wrong: % / %',
      pg_temp.call(v_gh, 'SELECT public.get_dating_setup_lists()'), pg_temp.call(v_young, 'SELECT public.get_dating_setup_lists()');
  END IF;
  -- A closed country is not offered; the global switch off makes every same_gender false.
  PERFORM public.publish_country_config('GB', '{"dating_enabled": false}');
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  v := pg_temp.call(v_us, 'SELECT public.get_dating_setup_lists()');
  IF (SELECT array_agg(c ->> 'code') FROM jsonb_array_elements(v -> 'countries') AS c
       WHERE c ->> 'code' IN ('GB', 'GH')) IS DISTINCT FROM ARRAY['GH']
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'countries') AS c WHERE c ->> 'same_gender' = 'true') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed country or a switched-off same-gender rule is still offered: %', v;
  END IF;
  PERFORM public.publish_country_config('GB', '{"dating_enabled": true}');
  -- No person's data but the caller's own (no gender, no seeking, no other person).
  IF position('woman' IN v::text) > 0 OR position(v_us::text IN v::text) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the lists carry a person''s data: %', v;
  END IF;
  -- T5 fix round 1 (I-1): an untrusted device, or one the check can't
  -- answer for (NULL), reads reverify_device and nothing else (stubs
  -- rolled back, as section I's guard probe).
  BEGIN
    CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $stub$ SELECT false $stub$;
    v_got := v_got || jsonb_build_array(pg_temp.call(v_us, 'SELECT public.get_dating_setup_lists()'));
    CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $stub$ SELECT NULL::boolean $stub$;
    v_got := v_got || jsonb_build_array(pg_temp.call(v_us, 'SELECT public.get_dating_setup_lists()'));
    RAISE SQLSTATE 'W1C99';
  EXCEPTION WHEN SQLSTATE 'W1C99' THEN
    NULL;
  END;
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "reverify_device"}, {"ok": false, "reason": "reverify_device"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the lists answered on an untrusted device: %', v_got;
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RAISE EXCEPTION 'fixture: the device stub was not rolled back';
  END IF;
END $n$;

-- =====================================================================
-- O. (§7.1 "notify requests aggregate only") No API role reads the
--    request table; the only client-callable functions naming it are the
--    request and the cancel; its counter carries no country.
-- =====================================================================
DO $o$
DECLARE
  v_got text;
BEGIN
  IF has_table_privilege('authenticated', 'public.dating_notify_requests', 'SELECT')
     OR has_table_privilege('anon', 'public.dating_notify_requests', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can read dating_notify_requests';
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_got
    FROM pg_proc AS p
   WHERE p.prosrc ~ 'dating_notify_requests' AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
  IF v_got IS DISTINCT FROM 'cancel_dating_country_notice(), request_dating_country_notice(text,text)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: client-callable readers of the notice table: %', v_got;
  END IF;
  IF EXISTS (SELECT 1 FROM public.metric_counters AS c WHERE c.key LIKE 'dating.notify.%' AND c.key ~ '\.[A-Z]{2}$') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a notice counter names a country';
  END IF;
END $o$;

-- Section T's role switches (this file defines pg_temp.call only; I-5).
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

-- =====================================================================
-- P. (W3c, §4.3, R-24) The photo table: positions 1-6; captions to 100;
--    csam_state; the five slot reasons; an approval needs a clear scan;
--    the child-label thresholds.
-- =====================================================================
DO $p$
DECLARE
  v_u constant uuid := pg_temp.ready('b0', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_msg text;
BEGIN
  -- (This file's older fixtures default csam_state to 'clear'; a real
  -- upload is 'pending' until the scan, as insert_dating_profile_photo
  -- sets it: section Q.)
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, csam_state)
  VALUES (v_u, 'dating-photos/' || md5('p6') || '.jpg', 6, 'pending');
  BEGIN
    INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES (v_u, 'dating-photos/' || md5('p7') || '.jpg', 7);
    RAISE EXCEPTION 'CONTRACT VIOLATED: position 7 was stored';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.dating_profile_photos SET moderation_state = 'approved' WHERE user_id = v_u AND position = 6;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a photo with no clear scan was approved';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = CONSTRAINT_NAME;
    IF v_msg IS DISTINCT FROM 'dating_profile_photos_approved_clear_check' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the approval was refused by % instead', v_msg;
    END IF;
  END;
  BEGIN
    UPDATE public.dating_profile_photos SET rejection_reason = 'face_blurred' WHERE user_id = v_u AND position = 6;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a v1 rejection reason was stored';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF (SELECT child_label_reject::text || '/' || child_label_review::text FROM public.dating_photo_moderation_config) IS DISTINCT FROM '0.7/0.5' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the child-label thresholds are not 0.7 / 0.5';
  END IF;
  -- Fix round 1 (I-3): one photo row per object (the storage predicate
  -- and the before-delete queue assume it; the predicate reads by key),
  -- and the orphan sweep reads by an index.
  BEGIN
    INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES (v_u, 'dating-photos/' || md5('p6') || '.jpg', 5);
    RAISE EXCEPTION 'CONTRACT VIOLATED: two photo rows share one object';
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_msg = CONSTRAINT_NAME;
    IF v_msg IS DISTINCT FROM 'dating_profile_photos_storage_key_key' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the shared object was refused by % instead', v_msg;
    END IF;
  END;
  IF to_regclass('public.dating_photo_upload_intents_orphan_idx') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the orphan sweep has no index';
  END IF;
END $p$;

-- =====================================================================
-- Q. (W3c, §4.4 Photos) The upload: an intent (setup guard; mime; six
--    photos at most by position, W3 final I-4; counted), the object, the insert; a slot replaced deletes its old
--    photo; the owner's list; the hit is never named.
-- =====================================================================
DO $q$
DECLARE
  v_u constant uuid := pg_temp.ready('b1', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_other constant uuid := pg_temp.ready('b2', 'GB', 'TLI', 'man', ARRAY['woman']);
  v jsonb;
  v2 jsonb;
  v_intent uuid;
  v_key text;
  v_first uuid;
  v_n int;
BEGIN
  IF pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/gif')$s$)
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "mime"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a gif intent was not refused as invalid';
  END IF;
  v := pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$);
  v_intent := (v ->> 'intent_id')::uuid;
  v_key := v ->> 'storage_key';
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v ->> 'bucket' IS DISTINCT FROM 'dating-profile-photos' OR v_key !~ '^dating-photos/[0-9a-f]{32}\.jpg$' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the intent reads %', v;
  END IF;
  IF pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 1::smallint)$s$, v_intent))
       IS DISTINCT FROM '{"ok": false, "reason": "object_missing"}'::jsonb
     OR pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 9::smallint)$s$, v_intent))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "position"}'::jsonb
     OR pg_temp.call(v_other, format($s$SELECT public.insert_dating_profile_photo(%L, 1::smallint)$s$, v_intent))
       IS DISTINCT FROM '{"ok": false, "reason": "intent_unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an insert without the object, at position 9, or with another''s intent was not refused';
  END IF;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', v_key, v_u);
  v := pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 1::smallint)$s$, v_intent));
  v_first := (v ->> 'photo_id')::uuid;
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR (SELECT csam_state FROM public.dating_profile_photos WHERE id = v_first) IS DISTINCT FROM 'pending'
     OR NOT EXISTS (SELECT 1 FROM public.dating_photo_moderation_outbox WHERE photo_id = v_first AND state = 'pending')
     OR (SELECT used_at FROM public.dating_photo_upload_intents WHERE id = v_intent) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the insert reads % (queued? used?)', v;
  END IF;
  -- The same slot again: the old photo goes.
  v := pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$);
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', v ->> 'storage_key', v_u);
  v := pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 1::smallint)$s$, v ->> 'intent_id'));
  IF EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE id = v_first)
     OR (SELECT count(*) FROM public.dating_profile_photos WHERE user_id = v_u) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: replacing slot 1 kept the old photo';
  END IF;
  -- Six at most.
  FOR v_n IN 2..6 LOOP
    v := pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/png')$s$);
    INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', v ->> 'storage_key', v_u);
    PERFORM pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, %s::smallint)$s$, v ->> 'intent_id', v_n));
  END LOOP;
  -- W3 final (I-4): with six an intent is still given (Replace and Crop);
  -- W3 final the insert's positions 1-6 keep it to six (section AB).
  IF (pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$) ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with six photos no intent was given (Replace and Crop fail)';
  END IF;
  -- The list: own photos only, no csam_state, the day-30 date.
  v := pg_temp.call(v_u, 'SELECT public.list_dating_profile_photos()');
  IF jsonb_array_length(v -> 'photos') <> 6 OR v::text ~ 'csam' OR v -> 'after_mutual_from' IS NULL
     OR pg_temp.call(v_other, 'SELECT public.list_dating_profile_photos()') -> 'photos' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the photo list reads %', v;
  END IF;
  -- The guard: Dating off refuses an intent (not_eligible).
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  IF pg_temp.call(v_other, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$) ->> 'reason' IS DISTINCT FROM 'not_eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an intent was given with Dating off';
  END IF;
  -- ... and deleting is never gated, and idempotent. (Each call is its own
  -- statement: a read in the same IF would not see the call's write, I-1.)
  v := pg_temp.call(v_u, format($s$SELECT public.delete_dating_profile_photo(%L)$s$, (SELECT id FROM public.dating_profile_photos WHERE user_id = v_u AND position = 6)));
  v2 := pg_temp.call(v_u, format($s$SELECT public.delete_dating_profile_photo(%L)$s$, gen_random_uuid()));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR v2 IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT count(*) FROM public.dating_profile_photos WHERE user_id = v_u) <> 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a delete was gated or not idempotent';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
END $q$;

-- =====================================================================
-- R. (W3c) Reorder: a permutation of one's own photos only; positions 1..n;
--    a replay changes nothing. Captions: own photos, 100 at most, no
--    invisible characters; blank clears.
-- =====================================================================
DO $r$
DECLARE
  v_u constant uuid := pg_temp.ready('b3', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_a uuid;
  v_b uuid;
  v_c uuid;
  v_key text := pg_temp.key('ro');
  v jsonb;
  v2 jsonb;
  v3 jsonb;
  v4 jsonb;
BEGIN
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('r1') || '.jpg', 1) RETURNING id INTO v_a;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('r2') || '.jpg', 2) RETURNING id INTO v_b;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('r3') || '.jpg', 4) RETURNING id INTO v_c;
  IF pg_temp.call(v_u, format($s$SELECT public.reorder_dating_photos(%L, ARRAY[%L, %L]::uuid[])$s$, pg_temp.key('x'), v_a, v_b))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "order"}'::jsonb
     OR pg_temp.call(v_u, format($s$SELECT public.reorder_dating_photos(%L, ARRAY[%L, %L, %L]::uuid[])$s$, pg_temp.key('x'), v_a, v_a, v_b))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "order"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reorder that is not a permutation was taken';
  END IF;
  v := pg_temp.call(v_u, format($s$SELECT public.reorder_dating_photos(%L, ARRAY[%L, %L, %L]::uuid[])$s$, v_key, v_c, v_a, v_b));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT string_agg(position::text, ',' ORDER BY id = v_c DESC, id = v_a DESC) FROM public.dating_profile_photos WHERE user_id = v_u) IS DISTINCT FROM '1,2,3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reorder did not number the photos 1..3 in order';
  END IF;
  v := pg_temp.call(v_u, format($s$SELECT public.set_dating_photo_caption(%L, 'Me at the beach')$s$, v_a));
  v2 := pg_temp.call(v_u, format($s$SELECT public.set_dating_photo_caption(%L, %L)$s$, v_a, repeat('x', 101)));
  v3 := pg_temp.call(v_u, format($s$SELECT public.set_dating_photo_caption(%L, %L)$s$, v_a, E'hi​there'));
  v4 := pg_temp.call(pg_temp.ready('b4', 'GB', 'TLI', 'man', ARRAY['woman']), format($s$SELECT public.set_dating_photo_caption(%L, 'mine now')$s$, v_a));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR v2 IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "caption"}'::jsonb
     OR v3 IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "caption"}'::jsonb
     OR v4 IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "photo"}'::jsonb
     OR (SELECT caption FROM public.dating_profile_photos WHERE id = v_a) IS DISTINCT FROM 'Me at the beach' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: captions are not the owner''s, bounded and clean';
  END IF;
  v := pg_temp.call(v_u, format($s$SELECT public.set_dating_photo_caption(%L, '   ')$s$, v_a));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT caption FROM public.dating_profile_photos WHERE id = v_a) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a blank caption did not clear';
  END IF;
END $r$;

-- =====================================================================
-- S. (W3c, I-10, R-25) The CSAM outcome is the service's to record: a hit
--    rejects as "unsafe", holds the Dating account once, and is final; an
--    error leaves the photo unapproved; clear lets Vision's verdict stand.
-- =====================================================================
DO $s$
DECLARE
  v_u constant uuid := pg_temp.ready('b5', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_a uuid;
  v_b uuid;
  v jsonb; -- fix round 1
  v_cs text; -- fix round 1
  v_ms text; -- fix round 1
  v_out text; -- fix round 1
  v_msg text; -- fix round 1
BEGIN
  IF has_function_privilege('authenticated', 'public.record_dating_photo_csam(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_dating_photo_csam(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the CSAM recorder is not the service role''s alone';
  END IF;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('s1') || '.jpg', 1) RETURNING id INTO v_a;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('s2') || '.jpg', 2) RETURNING id INTO v_b;
  PERFORM public.record_dating_photo_csam(v_a, 'hit');
  PERFORM public.record_dating_photo_csam(v_b, 'hit');
  PERFORM public.record_dating_photo_csam(v_a, 'clear');
  IF (SELECT csam_state || '/' || moderation_state || '/' || rejection_reason FROM public.dating_profile_photos WHERE id = v_a)
       IS DISTINCT FROM 'hit/rejected/unsafe'
     OR (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = v_u AND restriction_type = 'moderation_hold' AND lifted_at IS NULL) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hit is not rejected/unsafe, final, with one hold';
  END IF;
  DELETE FROM public.dating_account_restrictions WHERE user_id = v_u;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, csam_state) VALUES -- fix round 1 (I-2): an unscanned upload
    (v_u, 'dating-photos/' || md5('s3') || '.jpg', 3, 'pending') RETURNING id INTO v_a;
  PERFORM public.record_dating_photo_csam(v_a, 'error');
  IF (SELECT csam_state || '/' || moderation_state FROM public.dating_profile_photos WHERE id = v_a) IS DISTINCT FROM 'error/pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a matcher error does not leave the photo pending';
  END IF;
  PERFORM public.record_dating_photo_csam(v_a, 'clear');
  UPDATE public.dating_profile_photos SET moderation_state = 'approved' WHERE id = v_a;
  IF public.record_dating_photo_csam(v_a, 'maybe') IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "outcome"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown outcome was taken';
  END IF;
  -- Fix round 1 (I-2): a later matcher error (a redelivered job) never
  -- undoes a clear scan of the same bytes, and never raises the raw
  -- check violation that would echo the row (the caption) to the worker.
  v := public.record_dating_photo_csam(v_a, 'error');
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT csam_state || '/' || moderation_state FROM public.dating_profile_photos WHERE id = v_a) IS DISTINCT FROM 'clear/approved' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a matcher error after a clear scan reads % (clear/approved kept)', v;
  END IF;
  -- ... and no outcome on any stored state raises.
  FOREACH v_cs IN ARRAY ARRAY['pending', 'clear', 'hit', 'error'] LOOP
    FOREACH v_ms IN ARRAY ARRAY['pending', 'approved', 'rejected', 'needs_review'] LOOP
      CONTINUE WHEN v_ms = 'approved' AND v_cs <> 'clear';
      FOREACH v_out IN ARRAY ARRAY['clear', 'hit', 'error'] LOOP
        DELETE FROM public.dating_profile_photos WHERE user_id = v_u AND position = 5;
        INSERT INTO public.dating_profile_photos (user_id, storage_key, position, csam_state, moderation_state)
        VALUES (v_u, 'dating-photos/' || md5('s-' || v_cs || v_ms || v_out) || '.jpg', 5, v_cs, v_ms) RETURNING id INTO v_b;
        BEGIN
          v := public.record_dating_photo_csam(v_b, v_out);
        EXCEPTION WHEN OTHERS THEN
          RAISE EXCEPTION 'CONTRACT VIOLATED: the CSAM outcome % on %/% raised %', v_out, v_cs, v_ms, SQLSTATE;
        END;
        IF v IS DISTINCT FROM '{"ok": true}'::jsonb THEN
          RAISE EXCEPTION 'CONTRACT VIOLATED: the CSAM outcome % on %/% read %', v_out, v_cs, v_ms, v;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;
  -- Fix round 1 (M-7): a hit is final outside the recorder too: no direct
  -- write un-hits it, the database's or the service role's.
  SELECT id INTO v_b FROM public.dating_profile_photos WHERE user_id = v_u AND csam_state = 'hit' ORDER BY position LIMIT 1;
  FOREACH v_out IN ARRAY ARRAY['db', 'service_role'] LOOP
    BEGIN
      IF v_out = 'service_role' THEN
        SET LOCAL ROLE service_role;
      END IF;
      UPDATE public.dating_profile_photos SET csam_state = 'clear', moderation_state = 'approved', rejection_reason = NULL WHERE id = v_b;
      RAISE EXCEPTION 'CONTRACT VIOLATED: a direct write as % un-hit a CSAM match', v_out;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      IF v_msg IS DISTINCT FROM 'dating:csam_final' THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: un-hitting a match as % read: %', v_out, v_msg;
      END IF;
    END;
  END LOOP;
  IF (SELECT csam_state FROM public.dating_profile_photos WHERE id = v_b) IS DISTINCT FROM 'hit' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a CSAM match is no longer a hit';
  END IF;
END $s$;

-- =====================================================================
-- T. (R11, R-2) No client reads the photo or intent tables; the owner still
--    uploads by intent and reads her own object through the storage
--    policies' definer predicates; nobody else does.
-- =====================================================================
DO $t$
DECLARE
  v_u constant uuid := pg_temp.ready('b6', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_x constant uuid := pg_temp.ready('b7', 'GB', 'TLI', 'man', ARRAY['woman']);
  v jsonb;
  v_key text;
  v_n bigint;
  v_photo uuid; -- fix round 1
  v_key2 constant text := 'dating-photos/' || md5('t-quarantined') || '.jpg'; -- fix round 1
BEGIN
  IF has_table_privilege('authenticated', 'public.dating_profile_photos', 'SELECT')
     OR has_table_privilege('authenticated', 'public.dating_photo_upload_intents', 'SELECT')
     OR has_any_column_privilege('authenticated', 'public.dating_profile_photos', 'SELECT')
     OR EXISTS (SELECT 1 FROM pg_policies WHERE policyname IN ('dating_profile_photos_select_own', 'dating_photo_upload_intents_select_own')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can still read the photo or intent table';
  END IF;
  v := pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$);
  v_key := v ->> 'storage_key';
  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
  GRANT SELECT, INSERT ON storage.objects TO authenticated;
  PERFORM pg_temp.as_person(v_u);
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', v_key, v_u);
  PERFORM pg_temp.as_db();
  PERFORM pg_temp.as_person(v_x);
  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', 'dating-photos/' || md5('t-x') || '.jpg', v_x);
    RAISE EXCEPTION 'CONTRACT VIOLATED: an upload without an intent was let in';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  v_n := (SELECT count(*) FROM storage.objects WHERE name = v_key);
  PERFORM pg_temp.as_db();
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stranger reads another''s upload';
  END IF;
  v_photo := (pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 1::smallint)$s$, v ->> 'intent_id')) ->> 'photo_id')::uuid; -- fix round 1
  PERFORM pg_temp.as_person(v_u);
  v_n := (SELECT count(*) FROM storage.objects WHERE name = v_key);
  PERFORM pg_temp.as_db();
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner cannot read her own photo object';
  END IF;
  -- Fix round 1 (M-1): once the photo row exists, a stranger still reads nothing.
  PERFORM pg_temp.as_person(v_x);
  v_n := (SELECT count(*) FROM storage.objects WHERE name = v_key);
  PERFORM pg_temp.as_db();
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stranger reads another''s attached photo object';
  END IF;
  -- Fix round 1 (M-8): a CSAM match is never served, the owner included ...
  PERFORM public.record_dating_photo_csam(v_photo, 'hit');
  PERFORM pg_temp.as_person(v_u);
  v_n := (SELECT count(*) FROM storage.objects WHERE name = v_key);
  PERFORM pg_temp.as_db();
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner reads a photo object that matched the CSAM list';
  END IF;
  -- ... nor an object Spec 1 recorded as a match (quarantined), whatever the photo row says.
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES (v_u, v_key2, 2);
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', v_key2, v_u);
  PERFORM pg_temp.as_person(v_u);
  v_n := (SELECT count(*) FROM storage.objects WHERE name = v_key2);
  PERFORM pg_temp.as_db();
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'fixture: the owner cannot read her unscanned photo object';
  END IF;
  INSERT INTO private.media_scan_queue (bucket, object_name, owner_user_id, source, status, scanned_at)
  VALUES ('dating-profile-photos', v_key2, v_u, 'inline', 'match', now());
  PERFORM pg_temp.as_person(v_u);
  v_n := (SELECT count(*) FROM storage.objects WHERE name = v_key2);
  PERFORM pg_temp.as_db();
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner reads an object Spec 1 recorded as a CSAM match';
  END IF;
END $t$;

-- =====================================================================
-- U. (I-14) Orphan uploads: an object uploaded under an intent that expired
--    unused is claimed for a scan, and only a recorded scan deletes it
--    (nothing is deleted unscanned); an error releases it for a retry; the
--    sweep is the service role's only.
-- =====================================================================
DO $u$
DECLARE
  v_u constant uuid := pg_temp.ready('b8', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_orphan uuid;
  v_hit uuid;
  v_stale uuid;
  v_key text := 'dating-photos/' || md5('u-orphan') || '.jpg';
  v_hit_key text := 'dating-photos/' || md5('u-hit') || '.jpg';
  v_stale_key text := 'dating-photos/' || md5('u-stale') || '.jpg';
  v_got uuid[];
  v jsonb;
  v_swept bigint := pg_temp.metric('dating.photo.orphan_swept');
  v_stuck uuid; -- fix round 1
  v_stuck_key constant text := 'dating-photos/' || md5('u-stuck') || '.jpg'; -- fix round 1
  v_stuck_n bigint := pg_temp.metric('dating.photo.orphan_scan_stuck'); -- fix round 1
  v_try int; -- fix round 1
  v_errors bigint := pg_temp.metric('dating.photo.orphan_scan_error');
BEGIN
  IF has_function_privilege('authenticated', 'public.claim_dating_orphan_uploads(integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.record_dating_orphan_scan(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.claim_dating_orphan_uploads(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the orphan sweep is not the service role''s alone';
  END IF;
  -- One orphan, and five that are not: not yet expired, expired just now,
  -- expired with no object, used (a photo), and an unused stamp whose key
  -- is a live photo anyway (a live photo is never swept).
  INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at, created_at)
  VALUES (v_u, v_key, 'image/jpeg', now() - interval '1 hour', now() - interval '2 hours') RETURNING id INTO v_orphan;
  INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at, used_at, created_at) VALUES
    (v_u, 'dating-photos/' || md5('u-fresh') || '.jpg', 'image/jpeg', now() + interval '10 minutes', NULL, now()),
    (v_u, 'dating-photos/' || md5('u-recent') || '.jpg', 'image/jpeg', now() - interval '5 minutes', NULL, now() - interval '20 minutes'),
    (v_u, 'dating-photos/' || md5('u-noobj') || '.jpg', 'image/jpeg', now() - interval '1 hour', NULL, now() - interval '2 hours'),
    (v_u, 'dating-photos/' || md5('u-used') || '.jpg', 'image/jpeg', now() - interval '1 hour', now() - interval '90 minutes', now() - interval '2 hours'),
    (v_u, 'dating-photos/' || md5('u-live') || '.jpg', 'image/jpeg', now() - interval '1 hour', NULL, now() - interval '2 hours');
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-profile-photos', v_key, v_u),
    ('dating-profile-photos', 'dating-photos/' || md5('u-fresh') || '.jpg', v_u),
    ('dating-profile-photos', 'dating-photos/' || md5('u-recent') || '.jpg', v_u),
    ('dating-profile-photos', 'dating-photos/' || md5('u-used') || '.jpg', v_u),
    ('dating-profile-photos', 'dating-photos/' || md5('u-live') || '.jpg', v_u);
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('u-used') || '.jpg', 1), (v_u, 'dating-photos/' || md5('u-live') || '.jpg', 2);
  SELECT array_agg(c.intent_id) INTO v_got FROM public.claim_dating_orphan_uploads(50) AS c WHERE c.user_id = v_u;
  IF v_got IS DISTINCT FROM ARRAY[v_orphan] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep claimed % (only the expired, unused, uploaded intent expected)', v_got;
  END IF;
  -- A claim deletes nothing (the bytes are not scanned yet), and is not
  -- claimed twice.
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = 'dating-profile-photos' AND object_name = v_key) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an orphan was queued for deletion before its scan';
  END IF;
  SELECT array_agg(c.intent_id) INTO v_got FROM public.claim_dating_orphan_uploads(50) AS c WHERE c.user_id = v_u;
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a claimed orphan was claimed again: %', v_got;
  END IF;
  -- The matcher couldn't answer: kept, released, counted; claimed again.
  v := public.record_dating_orphan_scan(v_orphan, 'error');
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = v_key)
     OR (SELECT orphan_claimed_at FROM public.dating_photo_upload_intents WHERE id = v_orphan) IS NOT NULL
     OR pg_temp.metric('dating.photo.orphan_scan_error') <> v_errors + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed scan reads % (kept, released, counted)', v;
  END IF;
  SELECT array_agg(c.intent_id) INTO v_got FROM public.claim_dating_orphan_uploads(50) AS c WHERE c.user_id = v_u;
  IF v_got IS DISTINCT FROM ARRAY[v_orphan] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a released orphan was not claimed again: %', v_got;
  END IF;
  -- Scanned clear: deleted, once.
  v := public.record_dating_orphan_scan(v_orphan, 'clear');
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = 'dating-profile-photos' AND object_name = v_key)
     OR (SELECT orphan_state FROM public.dating_photo_upload_intents WHERE id = v_orphan) IS DISTINCT FROM 'swept'
     OR pg_temp.metric('dating.photo.orphan_swept') <> v_swept + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a clear scan reads % (deleted, swept, counted)', v;
  END IF;
  IF public.record_dating_orphan_scan(v_orphan, 'clear') IS DISTINCT FROM '{"ok": false, "reason": "not_claimed"}'::jsonb
     OR public.record_dating_orphan_scan(v_orphan, 'maybe') IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "outcome"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a swept orphan or an unknown outcome was recorded';
  END IF;
  -- A hit: recorded, and not deleted here (Spec 1's inline record owns the
  -- object: it keeps it when the quarantine copy failed); a claim a dead
  -- worker left 11 minutes ago is claimed again.
  INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at, created_at, orphan_claimed_at) VALUES
    (v_u, v_hit_key, 'image/jpeg', now() - interval '1 hour', now() - interval '2 hours', NULL),
    (v_u, v_stale_key, 'image/jpeg', now() - interval '1 hour', now() - interval '2 hours', now() - interval '11 minutes');
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-profile-photos', v_hit_key, v_u), ('dating-profile-photos', v_stale_key, v_u);
  SELECT id INTO v_hit FROM public.dating_photo_upload_intents WHERE storage_key = v_hit_key;
  SELECT id INTO v_stale FROM public.dating_photo_upload_intents WHERE storage_key = v_stale_key;
  SELECT array_agg(c.intent_id ORDER BY c.storage_key = v_hit_key DESC) INTO v_got
    FROM public.claim_dating_orphan_uploads(50) AS c WHERE c.user_id = v_u;
  IF v_got IS DISTINCT FROM ARRAY[v_hit, v_stale] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the hit and the stale claim were not claimed: %', v_got;
  END IF;
  v := public.record_dating_orphan_scan(v_hit, 'hit');
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = v_hit_key)
     OR (SELECT orphan_state FROM public.dating_photo_upload_intents WHERE id = v_hit) IS DISTINCT FROM 'csam' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hit orphan reads %', v;
  END IF;
  -- Fix round 1 (I-1): an orphan match holds the Dating account like a
  -- photo match (R-25: one live moderation_hold, stamped by phone, so it
  -- survives deleting the account); a second match adds none.
  IF (SELECT count(*) FROM public.dating_account_restrictions
       WHERE user_id = v_u AND restriction_type = 'moderation_hold' AND lifted_at IS NULL) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an orphan CSAM match placed no Dating hold';
  END IF;
  PERFORM public.record_dating_orphan_scan(v_stale, 'hit');
  IF (SELECT count(*) FROM public.dating_account_restrictions
       WHERE user_id = v_u AND restriction_type = 'moderation_hold' AND lifted_at IS NULL) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second orphan match placed a second hold';
  END IF;
  -- Fix round 1 (M-10): a scan that fails five times is capped: kept
  -- (never deleted unscanned), flagged stuck, never claimed again, and
  -- counted for an operator. Four failures are retried as before.
  INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at, created_at)
  VALUES (v_u, v_stuck_key, 'image/jpeg', now() - interval '1 hour', now() - interval '2 hours') RETURNING id INTO v_stuck;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', v_stuck_key, v_u);
  FOR v_try IN 1..5 LOOP
    SELECT array_agg(c.intent_id) INTO v_got FROM public.claim_dating_orphan_uploads(50) AS c WHERE c.user_id = v_u;
    IF v_got IS DISTINCT FROM ARRAY[v_stuck] THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: failed scan % left the orphan unclaimable: %', v_try - 1, v_got;
    END IF;
    v := public.record_dating_orphan_scan(v_stuck, 'error');
    IF v IS DISTINCT FROM '{"ok": true}'::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: failed scan % read %', v_try, v;
    END IF;
    IF v_try < 5 AND (SELECT orphan_state FROM public.dating_photo_upload_intents WHERE id = v_stuck) IS NOT NULL THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the orphan was flagged after % failed scans', v_try;
    END IF;
  END LOOP;
  SELECT array_agg(c.intent_id) INTO v_got FROM public.claim_dating_orphan_uploads(50) AS c WHERE c.user_id = v_u;
  IF (SELECT orphan_state FROM public.dating_photo_upload_intents WHERE id = v_stuck) IS DISTINCT FROM 'stuck'
     OR v_got IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = v_stuck_key)
     OR pg_temp.metric('dating.photo.orphan_scan_stuck') <> v_stuck_n + 1
     OR public.record_dating_orphan_scan(v_stuck, 'clear') IS DISTINCT FROM '{"ok": false, "reason": "not_claimed"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an orphan that failed five scans is not kept, flagged stuck, unclaimed and counted (claimed: %)', v_got;
  END IF;
END $u$;

-- =====================================================================
-- V. (W3c; Task 3 review M-11; R-43) has_data stays true for anyone who
--    holds a Dating photo or an upload intent, with or without a profile,
--    so Leave (which deletes both) stays reachable; leaving clears them.
-- =====================================================================
DO $v$
DECLARE
  v_photo constant uuid := pg_temp.person('b9');
  v_intent constant uuid := pg_temp.person('ba');
  v_home_photo text;
  v_home_intent text;
BEGIN
  IF private.dating_has_data(v_photo) IS NOT FALSE OR private.dating_has_data(v_intent) IS NOT FALSE THEN
    RAISE EXCEPTION 'fixture: a person with no Dating rows already has Dating data';
  END IF;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position)
  VALUES (v_photo, 'dating-photos/' || md5('v-photo') || '.jpg', 1);
  INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at)
  VALUES (v_intent, 'dating-photos/' || md5('v-intent') || '.jpg', 'image/jpeg', now() + interval '15 minutes');
  v_home_photo := pg_temp.call(v_photo, 'SELECT public.get_dating_home()') ->> 'has_data';
  v_home_intent := pg_temp.call(v_intent, 'SELECT public.get_dating_home()') ->> 'has_data';
  IF private.dating_has_data(v_photo) IS NOT TRUE OR private.dating_has_data(v_intent) IS NOT TRUE
     OR v_home_photo IS DISTINCT FROM 'true' OR v_home_intent IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person holding only a Dating photo (%) or upload intent (%) has no Dating data (Leave hidden)',
      v_home_photo, v_home_intent;
  END IF;
  PERFORM private.dating_exit_internal(v_photo, false);
  PERFORM private.dating_exit_internal(v_intent, false);
  IF private.dating_has_data(v_photo) IS NOT FALSE OR private.dating_has_data(v_intent) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: leaving kept a Dating photo or upload intent';
  END IF;
END $v$;

-- =====================================================================
-- W. (W3c; R-47, M-9; the shared lock rule) Every photo writer that adds
--    takes the person's setup lock (then the country's) through a bounded
--    retry: a lock timeout or a deadlock is retried (3), then dating:busy
--    with the SQLSTATE, never the raw error. The CSAM recorder takes the
--    setup lock before the photo row, as exit does (a hit's hold suspends
--    the enrolment); a caption's row wait is retried the same way. One
--    connection can't make a real lock wait, so the lock step (and a
--    photo-row trigger) fail their first N calls, inside this transaction
--    only. Last section: the ROLLBACK puts the real functions back.
-- =====================================================================
CREATE TEMP SEQUENCE t8_lock_calls;
SELECT set_config('t8.fail_n', '0', true), set_config('t8.fail_code', '55P03', true);
CREATE OR REPLACE FUNCTION private.dating_lock_setup(p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fault$
BEGIN
  IF nextval('pg_temp.t8_lock_calls') <= current_setting('t8.fail_n')::integer THEN
    RAISE EXCEPTION 'injected lock wait' USING ERRCODE = current_setting('t8.fail_code');
  END IF;
  PERFORM private.dating_lock_setup(p_user, NULL::text[]);
END $fault$;
CREATE FUNCTION public.t8_photo_row_fault() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fault$
BEGIN
  IF nextval('pg_temp.t8_lock_calls') <= current_setting('t8.fail_n')::integer THEN
    RAISE EXCEPTION 'injected lock wait' USING ERRCODE = current_setting('t8.fail_code');
  END IF;
  RETURN NEW;
END $fault$;
CREATE TRIGGER zz_t8_fault BEFORE UPDATE ON public.dating_profile_photos
  FOR EACH ROW EXECUTE FUNCTION public.t8_photo_row_fault();
-- [p_sql] as [p_user] (NULL: as the database) with the first [p_n] lock
-- steps failing as [p_code]: its answer, or SQLSTATE:message.
CREATE FUNCTION pg_temp.faulted(p_user uuid, p_sql text, p_code text, p_n int) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM setval('pg_temp.t8_lock_calls', 1, false);
  PERFORM set_config('t8.fail_code', p_code, true);
  PERFORM set_config('t8.fail_n', p_n::text, true);
  BEGIN
    IF p_user IS NULL THEN
      EXECUTE p_sql INTO v;
    ELSE
      v := pg_temp.call(p_user, p_sql);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('t8.fail_n', '0', true);
    RETURN SQLSTATE || ':' || SQLERRM;
  END;
  PERFORM set_config('t8.fail_n', '0', true);
  RETURN v::text;
END $$;

DO $w$
DECLARE
  v_u constant uuid := pg_temp.ready('bb', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_s constant uuid := pg_temp.person('bc');
  v_o constant uuid := pg_temp.person('bd'); -- fix round 1
  v_oi uuid; -- fix round 1
  v jsonb;
  v_a uuid;
  v_b uuid;
  v_sp uuid;
  v_got text;
  v_intent text;
  v_insert text;
  v_reorder text;
  v_csam text;
  v_caption text;
BEGIN
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('w1') || '.jpg', 1) RETURNING id INTO v_a;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('w2') || '.jpg', 2) RETURNING id INTO v_b;
  -- Two lock waits: retried, the intent is given.
  v_got := pg_temp.faulted(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$, '55P03', 2);
  IF v_got !~ '^\{' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two lock waits on the upload intent were not retried: %', v_got;
  END IF;
  IF (v_got::jsonb ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two lock waits on the upload intent were not retried: %', v_got;
  END IF;
  -- Three: dating:busy with the SQLSTATE, for each writer that adds.
  v_intent := pg_temp.faulted(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/png')$s$, '55P03', 3);
  v_insert := pg_temp.faulted(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 3::smallint)$s$, v_got::jsonb ->> 'intent_id'), '40P01', 3);
  v_reorder := pg_temp.faulted(v_u, format($s$SELECT public.reorder_dating_photos(%L, ARRAY[%L, %L]::uuid[])$s$, pg_temp.key('w'), v_b, v_a), '55P03', 3);
  IF v_intent IS DISTINCT FROM '55P03:dating:busy' OR v_insert IS DISTINCT FROM '40P01:dating:busy'
     OR v_reorder IS DISTINCT FROM '55P03:dating:busy' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under three lock waits intent / insert / reorder read % / % / % (dating:busy expected)',
      v_intent, v_insert, v_reorder;
  END IF;
  IF (SELECT string_agg(position::text, ',' ORDER BY id = v_a DESC) FROM public.dating_profile_photos WHERE user_id = v_u) IS DISTINCT FROM '1,2'
     OR (SELECT count(*) FROM public.dating_photo_upload_intents WHERE user_id = v_u AND used_at IS NULL) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a busy photo writer changed a row';
  END IF;
  -- The CSAM recorder: the person's setup lock first (none held before it).
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, csam_state) VALUES -- fix round 1 (I-2): an unscanned upload
    (v_s, 'dating-photos/' || md5('w-s') || '.jpg', 1, 'pending') RETURNING id INTO v_sp;
  IF pg_temp.holds('dating_setup', v_s::text, 'ExclusiveLock') THEN
    RAISE EXCEPTION 'fixture: the setup lock is held before the CSAM outcome';
  END IF;
  v_csam := pg_temp.faulted(NULL, format($s$SELECT public.record_dating_photo_csam(%L, 'error')$s$, v_sp), '55P03', 2);
  IF v_csam IS DISTINCT FROM '{"ok": true}' OR NOT pg_temp.holds('dating_setup', v_s::text, 'ExclusiveLock') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the CSAM outcome read % without the person''s setup lock (retried)', v_csam;
  END IF;
  v_csam := pg_temp.faulted(NULL, format($s$SELECT public.record_dating_photo_csam(%L, 'hit')$s$, v_sp), '40P01', 3);
  IF v_csam IS DISTINCT FROM '40P01:dating:busy'
     OR (SELECT csam_state FROM public.dating_profile_photos WHERE id = v_sp) IS DISTINCT FROM 'error' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the CSAM outcome under three lock waits read % (dating:busy, nothing written)', v_csam;
  END IF;
  -- A caption's row wait: two retried, three dating:busy.
  v_caption := pg_temp.faulted(v_u, format($s$SELECT public.set_dating_photo_caption(%L, 'Hello')$s$, v_a), '55P03', 2);
  IF v_caption IS DISTINCT FROM '{"ok": true}'
     OR (SELECT caption FROM public.dating_profile_photos WHERE id = v_a) IS DISTINCT FROM 'Hello' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two row waits on a caption were not retried: %', v_caption;
  END IF;
  v_caption := pg_temp.faulted(v_u, format($s$SELECT public.set_dating_photo_caption(%L, 'Again')$s$, v_a), '55P03', 3);
  IF v_caption IS DISTINCT FROM '55P03:dating:busy'
     OR (SELECT caption FROM public.dating_profile_photos WHERE id = v_a) IS DISTINCT FROM 'Hello' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a caption under three row waits read % (dating:busy expected)', v_caption;
  END IF;
  -- Fix round 1 (I-1): an orphan match takes the person's setup lock (its
  -- hold suspends the enrolment, which exit locks first) with the same
  -- bounded retry; under three waits nothing is recorded.
  INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at, created_at, orphan_claimed_at)
  VALUES (v_o, 'dating-photos/' || md5('w-orphan') || '.jpg', 'image/jpeg', now() - interval '1 hour', now() - interval '2 hours', now())
  RETURNING id INTO v_oi;
  v_csam := pg_temp.faulted(NULL, format($s$SELECT public.record_dating_orphan_scan(%L, 'hit')$s$, v_oi), '40P01', 3);
  IF v_csam IS DISTINCT FROM '40P01:dating:busy'
     OR (SELECT orphan_state FROM public.dating_photo_upload_intents WHERE id = v_oi) IS NOT NULL
     OR pg_temp.holds('dating_setup', v_o::text, 'ExclusiveLock') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an orphan match under three lock waits read % (dating:busy, nothing written)', v_csam;
  END IF;
  v_csam := pg_temp.faulted(NULL, format($s$SELECT public.record_dating_orphan_scan(%L, 'hit')$s$, v_oi), '55P03', 2);
  IF v_csam IS DISTINCT FROM '{"ok": true}' OR NOT pg_temp.holds('dating_setup', v_o::text, 'ExclusiveLock')
     OR (SELECT count(*) FROM public.dating_account_restrictions
          WHERE user_id = v_o AND restriction_type = 'moderation_hold' AND lifted_at IS NULL) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an orphan match read % without the person''s setup lock and one hold (retried)', v_csam;
  END IF;
END $w$;

-- =====================================================================
-- X. (W3c; Task 9 carry B; R-25) A CSAM hit whose photo row is gone
--    (deleted mid-scan): record_dating_photo_csam answers gone and holds
--    nothing, so process-dating-photo places the same Dating hold through
--    record_dating_csam_hold (the service role's alone): one live
--    moderation_hold, the person's setup lock first (as exit does), a
--    bounded retry then dating:busy with nothing written; an account that
--    is itself gone answers gone, never a raw error. After W: it reuses
--    W's fault injection (rolled back with the file).
-- =====================================================================
DO $x$
DECLARE
  v_u constant uuid := pg_temp.person('be');
  v_p uuid;
  v jsonb;
  v_got text;
BEGIN
  IF has_function_privilege('authenticated', 'public.record_dating_csam_hold(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.record_dating_csam_hold(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_dating_csam_hold(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gone-hit hold is not the service role''s alone';
  END IF;
  -- The premise: a hit on a deleted photo row answers gone and holds nothing.
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, csam_state) VALUES
    (v_u, 'dating-photos/' || md5('x1') || '.jpg', 1, 'pending') RETURNING id INTO v_p;
  DELETE FROM public.dating_profile_photos WHERE id = v_p;
  v := public.record_dating_photo_csam(v_p, 'hit');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "gone"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_account_restrictions WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'fixture: a hit on a deleted photo read % (gone, no hold, expected)', v;
  END IF;
  -- Three lock waits: dating:busy with the SQLSTATE; nothing written, no lock kept.
  v_got := pg_temp.faulted(NULL, format($s$SELECT public.record_dating_csam_hold(%L)$s$, v_u), '55P03', 3);
  IF v_got IS DISTINCT FROM '55P03:dating:busy'
     OR EXISTS (SELECT 1 FROM public.dating_account_restrictions WHERE user_id = v_u)
     OR pg_temp.holds('dating_setup', v_u::text, 'ExclusiveLock') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gone-hit hold under three lock waits read % (dating:busy, nothing written)', v_got;
  END IF;
  -- Two: retried; the person's setup lock taken; one live hold.
  v_got := pg_temp.faulted(NULL, format($s$SELECT public.record_dating_csam_hold(%L)$s$, v_u), '40P01', 2);
  IF v_got IS DISTINCT FROM '{"ok": true}' OR NOT pg_temp.holds('dating_setup', v_u::text, 'ExclusiveLock')
     OR (SELECT count(*) FROM public.dating_account_restrictions
          WHERE user_id = v_u AND restriction_type = 'moderation_hold' AND lifted_at IS NULL) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gone-hit hold read % without the person''s setup lock and one hold (retried)', v_got;
  END IF;
  -- Again (a redelivered job): still one hold.
  v := public.record_dating_csam_hold(v_u);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT count(*) FROM public.dating_account_restrictions
          WHERE user_id = v_u AND restriction_type = 'moderation_hold' AND lifted_at IS NULL) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second gone-hit hold read % (one live hold expected)', v;
  END IF;
  -- No user, or one whose account is gone: answered, never raised.
  BEGIN
    IF public.record_dating_csam_hold(NULL) IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "user"}'::jsonb
       OR public.record_dating_csam_hold(gen_random_uuid()) IS DISTINCT FROM '{"ok": false, "reason": "gone"}'::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the gone-hit hold took no user or a deleted account';
    END IF;
  EXCEPTION WHEN raise_exception THEN
    RAISE;
  WHEN OTHERS THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gone-hit hold raised % for no user or a deleted account', SQLSTATE;
  END;
END $x$;

-- =====================================================================
-- Y. (W3c; Task 9 fix round 1, I-1, M-5) A CSAM hit's object is never
--    queued for deletion by a Dating path: the person's own delete, exit
--    (its upload intents carry the same key) and account deletion all
--    delete the rows (deletion is never blocked) but leave the object to
--    Spec 1's record, which queues it when a copy is in safety-quarantine
--    and holds it otherwise. A clean photo's object is still queued. A
--    hit and a gone hit's hold are each counted once, not per redelivery.
-- =====================================================================
CREATE FUNCTION pg_temp.escalations(p_key text) RETURNS text LANGUAGE sql AS $$ -- fix round 2 (I-4)
  SELECT coalesce(string_agg(e.status || '/' || coalesce(e.vendor, '-') || '/' || e.quarantined::text, ',' ORDER BY e.id), '')
    FROM public.safety_escalations AS e
   WHERE e.kind = 'csam_match' AND e.bucket = 'dating-profile-photos' AND e.object_name = p_key;
$$;
CREATE FUNCTION pg_temp.queued(p_key text) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM public.media_deletion_queue AS q
                  WHERE q.bucket_id = 'dating-profile-photos' AND q.object_name = p_key);
$$;
-- A photo for [p_user] at [p_pos] under [p_key], with the used upload
-- intent an attached photo has; [p_hit]: recorded as a CSAM hit.
CREATE FUNCTION pg_temp.photo_at(p_user uuid, p_pos int, p_key text, p_hit boolean) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v uuid;
BEGIN
  INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at, used_at)
  VALUES (p_user, p_key, 'image/jpeg', now() + interval '10 minutes', now());
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, csam_state)
  VALUES (p_user, p_key, p_pos, 'pending') RETURNING id INTO v;
  IF p_hit THEN
    PERFORM public.record_dating_photo_csam(v, 'hit');
  END IF;
  RETURN v;
END $$;

DO $y$
DECLARE
  v_u constant uuid := pg_temp.ready('bf', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_d constant uuid := pg_temp.person('c0');
  v_h constant uuid := pg_temp.person('c1');
  k_hit constant text := 'dating-photos/' || md5('y-hit') || '.jpg';
  k_ok constant text := 'dating-photos/' || md5('y-ok') || '.jpg';
  k_xhit constant text := 'dating-photos/' || md5('y-exit-hit') || '.jpg';
  k_xok constant text := 'dating-photos/' || md5('y-exit-ok') || '.jpg';
  k_dhit constant text := 'dating-photos/' || md5('y-del-hit') || '.jpg';
  k_dok constant text := 'dating-photos/' || md5('y-del-ok') || '.jpg';
  v_hit uuid;
  v_ok uuid;
  v_m bigint;
  v jsonb;
BEGIN
  -- M-5: a redelivered hit is counted once.
  v_m := pg_temp.metric('dating.photo.csam_hit');
  v_hit := pg_temp.photo_at(v_u, 1, k_hit, true);
  PERFORM public.record_dating_photo_csam(v_hit, 'hit');
  IF pg_temp.metric('dating.photo.csam_hit') IS DISTINCT FROM v_m + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hit and its redelivery counted % (once expected)', pg_temp.metric('dating.photo.csam_hit') - v_m;
  END IF;
  -- ... and so is a gone hit's hold, placed once.
  v_m := pg_temp.metric('dating.photo.csam_hit');
  PERFORM public.record_dating_csam_hold(v_h);
  PERFORM public.record_dating_csam_hold(v_h);
  IF pg_temp.metric('dating.photo.csam_hit') IS DISTINCT FROM v_m + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a gone hit''s hold and its repeat counted % (once expected)', pg_temp.metric('dating.photo.csam_hit') - v_m;
  END IF;
  -- The person's own delete: both rows go; only the clean object is queued.
  v_ok := pg_temp.photo_at(v_u, 2, k_ok, false);
  v := pg_temp.call(v_u, format('SELECT public.delete_dating_profile_photo(%L)', v_hit));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: deleting a hit photo read % (never blocked)', v;
  END IF;
  PERFORM pg_temp.call(v_u, format('SELECT public.delete_dating_profile_photo(%L)', v_ok));
  IF EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE id IN (v_hit, v_ok))
     OR pg_temp.queued(k_hit) OR NOT pg_temp.queued(k_ok) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the own delete left a row or queued the hit''s object (hit %, clean %)',
      pg_temp.queued(k_hit), pg_temp.queued(k_ok);
  END IF;
  -- Fix round 2 (I-4): Spec 1 never recorded it, so the delete did.
  IF pg_temp.escalations(k_hit) IS DISTINCT FROM 'open/dating_unrecorded/false' OR pg_temp.escalations(k_ok) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the own delete of an unrecorded hit left escalations "%" (clean "%")',
      pg_temp.escalations(k_hit), pg_temp.escalations(k_ok);
  END IF;
  -- Exit: the photos and their intents go; the hit's object is not queued.
  PERFORM pg_temp.photo_at(v_u, 1, k_xhit, true);
  PERFORM pg_temp.photo_at(v_u, 2, k_xok, false);
  PERFORM pg_temp.call(v_u, format('SELECT to_jsonb(public.exit_dating_mode(%L))', pg_temp.key('y-exit')));
  IF EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE user_id = v_u)
     OR EXISTS (SELECT 1 FROM public.dating_photo_upload_intents WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'fixture: exit left a photo or an upload';
  END IF;
  IF pg_temp.queued(k_xhit) OR NOT pg_temp.queued(k_xok) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit queued the hit''s object (hit %, clean %)', pg_temp.queued(k_xhit), pg_temp.queued(k_xok);
  END IF;
  IF pg_temp.escalations(k_xhit) IS DISTINCT FROM 'open/dating_unrecorded/false' THEN -- fix round 2 (I-4)
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit left an unrecorded hit with escalations "%"', pg_temp.escalations(k_xhit);
  END IF;
  -- Account deletion: its own queue lines and the cascade alike.
  PERFORM pg_temp.photo_at(v_d, 1, k_dhit, true);
  PERFORM pg_temp.photo_at(v_d, 2, k_dok, false);
  PERFORM public.prepare_account_deletion(v_d);
  IF pg_temp.queued(k_dhit) OR NOT pg_temp.queued(k_dok) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: account deletion queued the hit''s object (hit %, clean %)', pg_temp.queued(k_dhit), pg_temp.queued(k_dok);
  END IF;
  DELETE FROM auth.users WHERE id = v_d; -- fix round 2 (I-4): the real cascade
  IF EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE user_id = v_d) THEN
    RAISE EXCEPTION 'fixture: the account''s photos outlived it';
  END IF;
  IF pg_temp.queued(k_dhit) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the photo rows'' deletion queued the hit''s object';
  END IF;
  IF pg_temp.escalations(k_dhit) IS DISTINCT FROM 'open/dating_unrecorded/false' THEN -- fix round 2 (I-4)
    RAISE EXCEPTION 'CONTRACT VIOLATED: account deletion left an unrecorded hit with escalations "%"', pg_temp.escalations(k_dhit);
  END IF;
END $y$;

-- =====================================================================
-- AA. (W3 final, I-1, I-2) A photo job never stalls. A job left in
--     processing past its 10-minute lease (a worker that died) goes back
--     to pending whatever its attempts (a recovered job may have seen a
--     match): never dead-lettered, never deleted. A photo dead-lettered
--     unscanned (needs_review with csam_state pending or error: no person
--     can approve it) is re-queued; one a person can review (a clear scan)
--     and a hit are not. The recovery runs every 5 minutes (pg_cron), and
--     a job's attempts never overflow the claim.
-- =====================================================================
CREATE FUNCTION pg_temp.job(p_user uuid, p_pos int, p_tag text, p_csam text, p_mod text, p_state text,
                            p_attempts int, p_started interval) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v uuid;
BEGIN
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, csam_state, moderation_state, rejection_reason)
  VALUES (p_user, 'dating-photos/' || md5('aa-' || p_tag) || '.jpg', p_pos, p_csam, p_mod,
          CASE WHEN p_mod = 'needs_review' THEN 'needs_review' WHEN p_mod = 'rejected' THEN 'unsafe' END)
  RETURNING id INTO v;
  INSERT INTO public.dating_photo_moderation_outbox (photo_id, user_id, state, attempts, processing_started_at, completed_at)
  VALUES (v, p_user, p_state, p_attempts, CASE WHEN p_state = 'processing' THEN now() - p_started END,
          CASE WHEN p_state IN ('done', 'dead_letter') THEN now() END);
  RETURN v;
END $$;
CREATE FUNCTION pg_temp.job_state(p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT o.state || '/' || o.attempts || '/' || f.moderation_state || '/' || f.csam_state
    FROM public.dating_photo_moderation_outbox AS o JOIN public.dating_profile_photos AS f ON f.id = o.photo_id
   WHERE o.photo_id = p;
$$;

DO $aa$
DECLARE
  v_u constant uuid := pg_temp.person('d0');
  v_w constant uuid := pg_temp.person('d1');
  v_stale uuid;
  v_last uuid;
  v_fresh uuid;
  v_err uuid;
  v_pend uuid;
  v_review uuid;
  v_hit uuid;
  v_max uuid;
  v_photos bigint;
  v_cfg text[];
  v_job record;
BEGIN
  v_stale := pg_temp.job(v_u, 1, 'stale', 'pending', 'pending', 'processing', 2, interval '11 minutes');
  v_last := pg_temp.job(v_u, 2, 'last', 'pending', 'pending', 'processing', 5, interval '11 minutes');
  v_fresh := pg_temp.job(v_u, 3, 'fresh', 'pending', 'pending', 'processing', 1, interval '6 minutes');
  v_err := pg_temp.job(v_u, 4, 'err', 'error', 'needs_review', 'dead_letter', 5, NULL);
  v_pend := pg_temp.job(v_u, 5, 'pend', 'pending', 'needs_review', 'dead_letter', 5, NULL);
  v_review := pg_temp.job(v_u, 6, 'review', 'clear', 'needs_review', 'dead_letter', 5, NULL);
  v_hit := pg_temp.job(v_w, 1, 'hit', 'pending', 'pending', 'pending', 1, NULL);
  PERFORM public.record_dating_photo_csam(v_hit, 'hit');
  UPDATE public.dating_photo_moderation_outbox SET state = 'dead_letter', attempts = 5 WHERE photo_id = v_hit;
  v_photos := (SELECT count(*) FROM public.dating_profile_photos WHERE user_id IN (v_u, v_w));
  PERFORM public.recover_stale_dating_photo_jobs();
  IF pg_temp.job_state(v_stale) IS DISTINCT FROM 'pending/2/pending/pending'
     OR pg_temp.job_state(v_last) IS DISTINCT FROM 'pending/5/pending/pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a job stuck in processing past its lease reads % / % (pending, never dead-lettered)',
      pg_temp.job_state(v_stale), pg_temp.job_state(v_last);
  END IF;
  IF (SELECT processing_started_at FROM public.dating_photo_moderation_outbox WHERE photo_id = v_last) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a recovered job kept its lease';
  END IF;
  IF pg_temp.job_state(v_fresh) IS DISTINCT FROM 'processing/1/pending/pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a job 6 minutes into its 10-minute lease was taken back: %', pg_temp.job_state(v_fresh);
  END IF;
  IF pg_temp.job_state(v_err) IS DISTINCT FROM 'pending/0/pending/error'
     OR pg_temp.job_state(v_pend) IS DISTINCT FROM 'pending/0/pending/pending'
     OR (SELECT rejection_reason FROM public.dating_profile_photos WHERE id = v_err) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a photo dead-lettered unscanned was not re-queued: % / %',
      pg_temp.job_state(v_err), pg_temp.job_state(v_pend);
  END IF;
  IF pg_temp.job_state(v_review) IS DISTINCT FROM 'dead_letter/5/needs_review/clear'
     OR pg_temp.job_state(v_hit) IS DISTINCT FROM 'dead_letter/5/rejected/hit' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a scanned photo for a person (%) or a hit (%) was re-queued',
      pg_temp.job_state(v_review), pg_temp.job_state(v_hit);
  END IF;
  IF (SELECT count(*) FROM public.dating_profile_photos WHERE user_id IN (v_u, v_w)) IS DISTINCT FROM v_photos THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the recovery deleted a photo';
  END IF;
  -- Its schedule, and its definer settings.
  IF (SELECT j.schedule || '|' || j.command FROM cron.job AS j WHERE j.jobname = 'recover-stale-dating-photo-jobs')
       IS DISTINCT FROM '*/5 * * * *|SELECT public.recover_stale_dating_photo_jobs()' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recover-stale-dating-photo-jobs is not scheduled every 5 minutes: %',
      (SELECT j.schedule || '|' || j.command FROM cron.job AS j WHERE j.jobname = 'recover-stale-dating-photo-jobs');
  END IF;
  SELECT p.proconfig INTO v_cfg FROM pg_proc AS p WHERE p.oid = 'public.recover_stale_dating_photo_jobs()'::regprocedure;
  IF NOT (SELECT p.prosecdef FROM pg_proc AS p WHERE p.oid = 'public.recover_stale_dating_photo_jobs()'::regprocedure)
     OR v_cfg IS DISTINCT FROM ARRAY['search_path=""'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the recovery is not SECURITY DEFINER with an empty search_path: %', v_cfg;
  END IF;
  -- A job requeued forever (I-2: never dead-lettered unscanned) never overflows the claim.
  v_max := pg_temp.job(v_w, 2, 'max', 'pending', 'pending', 'pending', 32767, NULL);
  BEGIN
    SELECT * INTO v_job FROM public.claim_dating_photo_jobs(1, v_max);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: claiming a job at 32767 attempts raised %', SQLSTATE;
  END;
  IF v_job.photo_id IS DISTINCT FROM v_max OR v_job.attempts IS DISTINCT FROM 32767::smallint OR v_job.state IS DISTINCT FROM 'processing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the claim at the cap reads % / % / %', v_job.photo_id, v_job.attempts, v_job.state;
  END IF;
END $aa$;

-- =====================================================================
-- AB. (W3 final, I-4) Replace and Crop with six photos: an intent is given
--     (the slot being replaced is not counted); an insert at a taken
--     position replaces that photo (still six); a seventh is refused.
-- =====================================================================
DO $ab$
DECLARE
  v_u constant uuid := pg_temp.ready('d2', 'GB', 'TLI', 'woman', ARRAY['man']);
  v jsonb;
  v_n int;
  v_third uuid;
BEGIN
  FOR v_n IN 1..6 LOOP
    v := pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$);
    INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', v ->> 'storage_key', v_u);
    v := pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, %s::smallint)$s$, v ->> 'intent_id', v_n));
    IF (v ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'fixture: photo % reads %', v_n, v; END IF;
  END LOOP;
  v_third := (SELECT id FROM public.dating_profile_photos WHERE user_id = v_u AND position = 3);
  v := pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$);
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with six photos an intent (Replace, Crop) reads %', v;
  END IF;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', v ->> 'storage_key', v_u);
  IF pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 7::smallint)$s$, v ->> 'intent_id'))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "position"}'::jsonb
     OR (SELECT count(*) FROM public.dating_profile_photos WHERE user_id = v_u) <> 6 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a seventh photo was not refused';
  END IF;
  v := pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 3::smallint)$s$, v ->> 'intent_id'));
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE id = v_third)
     OR (SELECT id FROM public.dating_profile_photos WHERE user_id = v_u AND position = 3) IS DISTINCT FROM (v ->> 'photo_id')::uuid
     OR (SELECT count(*) FROM public.dating_profile_photos WHERE user_id = v_u) <> 6 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: replacing photo 3 of six reads % (the old one gone, still six)', v;
  END IF;
END $ab$;

-- =====================================================================
-- AC. (W3 final, M-7) No photo before Dating's terms: an intent and an
--     insert need the standing D4 consents (as activation) and a profile;
--     otherwise not_eligible. Deleting stays ungated.
-- =====================================================================
DO $ac$
DECLARE
  v_bare constant uuid := pg_temp.id('d3');
  v_noprof constant uuid := pg_temp.person('d4');
  v_u constant uuid := pg_temp.ready('d5', 'GB', 'TLI', 'woman', ARRAY['man']);
  v jsonb;
  v_intent jsonb;
  p text;
BEGIN
  -- An adult on the Dating path with nothing agreed and no profile.
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_bare, '15558703d3', now(), now() - interval '40 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_bare, '15558703d3', 'Bare d3', 'dating', now() - interval '40 days', now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (v_bare, current_date - interval '30 years');
  IF pg_temp.call(v_bare, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$) IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR pg_temp.call(v_noprof, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$) IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an intent was given with no consent (%) or no profile (%)',
      pg_temp.call(v_bare, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$),
      pg_temp.call(v_noprof, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$);
  END IF;
  -- Each activation consent withdrawn in turn: no intent, no insert.
  v_intent := pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$);
  IF (v_intent ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'fixture: the intent reads %', v_intent; END IF;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', v_intent ->> 'storage_key', v_u);
  FOREACH p IN ARRAY ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile'] LOOP
    INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
    VALUES (v_u, 'ac-w-' || p, p, 'withdrawn', 'dating-2.0', clock_timestamp());
    IF pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$) IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
       OR pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 1::smallint)$s$, v_intent ->> 'intent_id'))
            IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: with % withdrawn a photo was taken', p;
    END IF;
    INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
    VALUES (v_u, 'ac-g-' || p, p, 'granted', 'dating-2.0', clock_timestamp());
  END LOOP;
  v := pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 1::smallint)$s$, v_intent ->> 'intent_id'));
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with every consent standing the insert reads %', v;
  END IF;
  -- Deleting never needs a consent.
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'ac-w2-terms', 'dating_terms', 'withdrawn', 'dating-2.0', clock_timestamp());
  v := pg_temp.call(v_u, format($s$SELECT public.delete_dating_profile_photo(%L)$s$, (v ->> 'photo_id')));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a delete with a consent withdrawn reads %', v;
  END IF;
END $ac$;

-- =====================================================================
-- AD. (W3 final, M-3) The bucket takes only what the preparer sends: at
--     most 2 MB, JPEG, PNG or WebP (as the other media buckets, where the
--     storage schema has the columns).
-- =====================================================================
DO $ad$
BEGIN
  ALTER TABLE storage.buckets ADD COLUMN IF NOT EXISTS file_size_limit bigint;
  ALTER TABLE storage.buckets ADD COLUMN IF NOT EXISTS allowed_mime_types text[];
  PERFORM private.dating_photo_bucket_limits();
  IF (SELECT b.file_size_limit::text || '|' || array_to_string(b.allowed_mime_types, ',')
        FROM storage.buckets AS b WHERE b.id = 'dating-profile-photos')
       IS DISTINCT FROM '2097152|image/jpeg,image/png,image/webp' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the photo bucket''s limits read %',
      (SELECT b.file_size_limit::text || '|' || array_to_string(b.allowed_mime_types, ',') FROM storage.buckets AS b WHERE b.id = 'dating-profile-photos');
  END IF;
END $ad$;

-- =====================================================================
-- AE. (W3 final, M-4) After leaving, Leave is offered only while something
--     is left to delete: a kept 'exited' enrolment alone is not Dating
--     data; a never-introduce list kept by choice is (a second Leave can
--     delete it), and so is a suspended enrolment (it stays).
-- =====================================================================
DO $ae$
DECLARE
  v_gone constant uuid := pg_temp.ready('d6', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_kept constant uuid := pg_temp.ready('d7', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_susp constant uuid := pg_temp.ready('d8', 'GB', 'TLI', 'woman', ARRAY['man']);
  v jsonb;
BEGIN
  INSERT INTO public.dating_enrollments (user_id) VALUES (v_gone), (v_kept), (v_susp) ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two) VALUES (v_kept, repeat('ab', 32), '12');
  PERFORM pg_temp.call(v_gone, format('SELECT to_jsonb(public.exit_dating_mode(%L, false))', pg_temp.key('ae-gone')));
  PERFORM pg_temp.call(v_kept, format('SELECT to_jsonb(public.exit_dating_mode(%L, true))', pg_temp.key('ae-kept')));
  UPDATE public.dating_enrollments SET state = 'suspended' WHERE user_id = v_susp;
  PERFORM private.dating_exit_internal(v_susp, false);
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_gone) IS DISTINCT FROM 'exited'
     OR NOT EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_kept)
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_susp) IS DISTINCT FROM 'suspended' THEN
    RAISE EXCEPTION 'fixture: the exits did not land';
  END IF;
  v := pg_temp.call(v_gone, 'SELECT public.get_dating_home()');
  IF private.dating_has_data(v_gone) IS NOT FALSE OR v ->> 'has_data' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after leaving with nothing kept the home still offers Leave: %', v;
  END IF;
  IF private.dating_has_data(v_kept) IS NOT TRUE OR private.dating_has_data(v_susp) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a kept never-introduce list (%) or a suspended enrolment (%) is not Dating data',
      private.dating_has_data(v_kept), private.dating_has_data(v_susp);
  END IF;
  -- The second Leave deletes the kept list; then nothing is left.
  PERFORM pg_temp.call(v_kept, format('SELECT to_jsonb(public.exit_dating_mode(%L, false))', pg_temp.key('ae-kept2')));
  IF private.dating_has_data(v_kept) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the second Leave the person still has Dating data';
  END IF;
END $ae$;

-- =====================================================================
-- AF. (W3 final, M-5) The metadata strip never brings a deleted photo
--     back. Before the re-upload the worker checks, under the photo row's
--     lock, that the row is there with its key and a clear scan; after it,
--     that the row is still there. A row gone after the upload re-arms the
--     object's deletion (the drain may already have run), unless a CSAM
--     match names the object (Spec 1's evidence is kept). Service role only.
-- =====================================================================
DO $af$
DECLARE
  v_u constant uuid := pg_temp.person('d9');
  k_live text := 'dating-photos/' || md5('af-live') || '.jpg';
  k_gone constant text := 'dating-photos/' || md5('af-gone') || '.jpg';
  k_hit constant text := 'dating-photos/' || md5('af-hit') || '.jpg';
  v_live uuid;
  v_gone uuid;
  v_hit uuid;
  v_m bigint;
  v jsonb;
BEGIN
  IF has_function_privilege('authenticated', 'public.check_dating_photo_strip(uuid,text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.check_dating_photo_strip(uuid,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.check_dating_photo_strip(uuid,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the strip check is not the service role''s alone';
  END IF;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, csam_state) VALUES (v_u, k_live, 1, 'clear') RETURNING id INTO v_live;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, csam_state) VALUES (v_u, k_gone, 2, 'clear') RETURNING id INTO v_gone;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, csam_state) VALUES (v_u, k_hit, 3, 'clear') RETURNING id INTO v_hit;
  IF public.check_dating_photo_strip(v_live, k_live, 'before') IS DISTINCT FROM '{"ok": true}'::jsonb
     OR public.check_dating_photo_strip(v_live, k_live, 'after') IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a live photo''s strip check refused';
  END IF;
  IF public.check_dating_photo_strip(v_live, k_gone, 'before') IS DISTINCT FROM '{"ok": false, "reason": "gone"}'::jsonb
     OR public.check_dating_photo_strip(v_live, k_live, 'during') IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "phase"}'::jsonb
     OR public.check_dating_photo_strip(NULL, k_live, 'before') IS DISTINCT FROM '{"ok": false, "reason": "gone"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a mismatched key, a bad phase or no photo was not refused';
  END IF;
  UPDATE public.dating_profile_photos SET csam_state = 'error' WHERE id = v_live;
  IF public.check_dating_photo_strip(v_live, k_live, 'before') IS DISTINCT FROM '{"ok": false, "reason": "gone"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a photo with no clear scan may be re-uploaded';
  END IF;
  -- Deleted, and the drain ran, before the re-upload landed: re-armed.
  DELETE FROM public.dating_profile_photos WHERE id = v_gone;
  UPDATE public.media_deletion_queue SET deleted_at = now() - interval '1 minute', not_before = now() - interval '20 minutes'
   WHERE bucket_id = 'dating-profile-photos' AND object_name = k_gone;
  IF public.check_dating_photo_strip(v_gone, k_gone, 'before') IS DISTINCT FROM '{"ok": false, "reason": "gone"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted photo may be re-uploaded';
  END IF;
  v_m := pg_temp.metric('dating.photo.strip_after_delete');
  -- (Each call is its own statement: a read in the same IF would not see its write.)
  v := public.check_dating_photo_strip(v_gone, k_gone, 'after');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "gone"}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.media_deletion_queue AS q
                     WHERE q.bucket_id = 'dating-profile-photos' AND q.object_name = k_gone
                       AND q.deleted_at IS NULL AND q.not_before <= now())
     OR pg_temp.metric('dating.photo.strip_after_delete') IS DISTINCT FROM v_m + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-upload after the delete was not queued for deletion again: %',
      (SELECT to_jsonb(q) FROM public.media_deletion_queue AS q WHERE q.object_name = k_gone);
  END IF;
  -- A CSAM match names the object: kept (never queued by a Dating path).
  DELETE FROM public.dating_profile_photos WHERE id = v_hit;
  DELETE FROM public.media_deletion_queue WHERE bucket_id = 'dating-profile-photos' AND object_name = k_hit;
  PERFORM public.record_inline_csam_match('dating-profile-photos', k_hit, v_u, 'photodna', 'ref-af', false, NULL);
  DELETE FROM public.media_deletion_queue WHERE bucket_id = 'dating-profile-photos' AND object_name = k_hit;
  v := public.check_dating_photo_strip(v_hit, k_hit, 'after');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "gone"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.media_deletion_queue AS q WHERE q.bucket_id = 'dating-profile-photos' AND q.object_name = k_hit) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-upload of a matched object was queued for deletion';
  END IF;
  -- Either record keeps it: an open escalation alone, or Spec 1's scan
  -- queue's match alone (its escalation closed).
  FOREACH k_live IN ARRAY ARRAY['dating-photos/' || md5('af-esc') || '.jpg', 'dating-photos/' || md5('af-msq') || '.jpg'] LOOP
    PERFORM public.record_inline_csam_match('dating-profile-photos', k_live, v_u, 'photodna', 'ref-' || k_live, false, NULL);
    IF k_live LIKE '%' || md5('af-esc') || '%' THEN
      DELETE FROM private.media_scan_queue WHERE bucket = 'dating-profile-photos' AND object_name = k_live;
    ELSE
      UPDATE public.safety_escalations SET status = 'closed' WHERE bucket = 'dating-profile-photos' AND object_name = k_live;
    END IF;
    DELETE FROM public.media_deletion_queue WHERE bucket_id = 'dating-profile-photos' AND object_name = k_live;
    v := public.check_dating_photo_strip(gen_random_uuid(), k_live, 'after');
    IF v IS DISTINCT FROM '{"ok": false, "reason": "gone"}'::jsonb
       OR EXISTS (SELECT 1 FROM public.media_deletion_queue AS q WHERE q.bucket_id = 'dating-profile-photos' AND q.object_name = k_live) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a re-upload of an object one CSAM record names (%) was queued for deletion', k_live;
    END IF;
  END LOOP;
END $af$;

-- =====================================================================
-- Z. (W3c; Task 9 fix round 2, I-4) A hit whose Spec 1 record never
--    landed: when its row is deleted, the delete trigger records it
--    through Spec 1's record_inline_csam_match, unquarantined (vendor
--    'dating_unrecorded'), so a person is told and the original stays held
--    as the evidence. An object an open escalation already names gets no
--    second one; a closed one does not count. A record that fails never
--    blocks the delete: the row goes and dating.photo.csam_unrecorded is
--    counted. Last section: it replaces record_inline_csam_match inside
--    this transaction (the ROLLBACK puts it back).
-- =====================================================================
DO $z$
DECLARE
  v_u constant uuid := pg_temp.person('c2');
  k_open constant text := 'dating-photos/' || md5('z-open') || '.jpg';
  k_closed constant text := 'dating-photos/' || md5('z-closed') || '.jpg';
  k_fail constant text := 'dating-photos/' || md5('z-fail') || '.jpg';
  v uuid;
  v_m bigint;
BEGIN
  -- Spec 1 already recorded it (an open escalation): no second one.
  v := pg_temp.photo_at(v_u, 1, k_open, true);
  PERFORM public.record_inline_csam_match('dating-profile-photos', k_open, v_u, 'photodna', 'ref-z', true, 'q/z');
  DELETE FROM public.dating_profile_photos WHERE id = v;
  IF pg_temp.escalations(k_open) IS DISTINCT FROM 'open/photodna/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an already escalated hit''s delete made %', pg_temp.escalations(k_open);
  END IF;
  -- Only a closed escalation names it: a new, open one.
  v := pg_temp.photo_at(v_u, 2, k_closed, true);
  PERFORM public.record_inline_csam_match('dating-profile-photos', k_closed, v_u, 'photodna', 'ref-c', true, 'q/c');
  UPDATE public.safety_escalations SET status = 'closed' WHERE object_name = k_closed;
  DELETE FROM public.dating_profile_photos WHERE id = v;
  IF pg_temp.escalations(k_closed) IS DISTINCT FROM 'closed/photodna/true,open/dating_unrecorded/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hit named only by a closed escalation left %', pg_temp.escalations(k_closed);
  END IF;
  -- Spec 1's record fails: the row still goes, the gap is counted.
  CREATE OR REPLACE FUNCTION public.record_inline_csam_match(p_bucket text, p_object_name text, p_owner uuid, p_vendor text,
                                                             p_vendor_ref text, p_quarantined boolean DEFAULT true,
                                                             p_quarantine_path text DEFAULT NULL)
  RETURNS bigint LANGUAGE plpgsql AS $f$
  BEGIN
    RAISE EXCEPTION 'injected record failure';
  END $f$;
  v := pg_temp.photo_at(v_u, 3, k_fail, true);
  v_m := pg_temp.metric('dating.photo.csam_unrecorded');
  BEGIN
    DELETE FROM public.dating_profile_photos WHERE id = v;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing record blocked the delete: %', SQLERRM;
  END;
  IF EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE id = v)
     OR pg_temp.metric('dating.photo.csam_unrecorded') IS DISTINCT FROM v_m + 1
     OR pg_temp.queued(k_fail) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing record left the row (%), counted % or queued the object (%)',
      EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE id = v),
      pg_temp.metric('dating.photo.csam_unrecorded') - v_m, pg_temp.queued(k_fail);
  END IF;
END $z$;

ROLLBACK;
