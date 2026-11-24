-- supabase/tests/dating_v2_verification_contracts.sql
-- Spec 2 W4a (§3.3, §4.3, §4.4, §4.5, §6.3, §7.1, §7.2 S1/S2/S16, §7.5
-- mutant 8; I-7, R8; carries 1, 5): the verification record keeps no DOB,
-- estimate or image (A); a typed DOB alone never opens the age gate (B);
-- only the service role records a result, and a fae pass needs the
-- challenge age 25 (C); identity sets the profile's verification state
-- (D); a revocation or a failed age check pauses with its own reason and
-- closes every match (E, carry 1); an age_review restriction closes every
-- match as age_review (F); far below 18 places Spec 1's account hold once,
-- with three arguments, and nothing else in Dating calls it (G, R8); the
-- sessions (H); the human route (I); the person's own status read (J);
-- get_dating_home's verifying state (K); the ID's date of birth is compared,
-- never stored (L); the sweep (M); exit (N); no Dating function reads a
-- stored DOB (O); the dev script (P). Fix round 1 adds B2, C3, C4, E2,
-- G2, H2, I2, I3, I4, M2, O2 and O3 beside the sections they extend; Task 2's
-- fix round 1 adds U (the video outcome in one transaction, the
-- vendor-session limit, sandbox outside development) above P.
-- W4b appends its sections (trusted devices) above the final ROLLBACK.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_verification_contracts.sql
-- Fixture ids 5e400000-0000-0000-0000-0000000000NN; phones 15558707NN.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w4a-verify-key', true);
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w4a-field-key-0123456789abcdef-0123', true);
  PERFORM set_config('app.settings.age_assurance_mode', 'fake', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
SELECT private.seed_dating_field_key_fingerprint() AS seeded_field \gset
INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_mode_enabled', true), ('dating_age_assurance', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;
SELECT public.publish_country_config('GH', '{"dating_enabled": true, "open_regions": ["AA", "AH"]}') AS gh \gset
SELECT public.publish_country_config('GB', '{"dating_enabled": true}') AS gb \gset

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e400000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;
-- An adult [p_n] (declared age [p_years]) on the Dating path with a draft
-- profile in [p_country]/[p_region], every D4 consent and the biometric one,
-- and [p_photos] approved, scanned photos.
CREATE FUNCTION pg_temp.person(p_n text, p_years int DEFAULT 30, p_photos int DEFAULT 2,
                               p_country text DEFAULT 'GB', p_region text DEFAULT 'TLI',
                               p_biometric boolean DEFAULT true) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.id(p_n);
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_u, '15558707' || p_n, now(), now() - interval '40 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_u, '15558707' || p_n, 'Verify ' || p_n, 'dating', now() - interval '40 days', now(), '2');
  IF p_years IS NOT NULL THEN
    INSERT INTO public.account_birthdates (user_id, birth_date)
    VALUES (v_u, (current_date - make_interval(years => p_years) - interval '10 days')::date);
  END IF;
  INSERT INTO public.dating_enrollments (user_id, state, opted_in_at) VALUES (v_u, 'profile_draft', now());
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code)
  VALUES (v_u, 'Verify', p_country, p_region);
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'w4a-consent-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']
                || CASE WHEN p_biometric THEN ARRAY['biometric_verification'] ELSE ARRAY[]::text[] END) AS p;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
  SELECT v_u, 'w4a/' || v_u || '/' || n || '.jpg', n, 'approved', 'clear' FROM generate_series(1, p_photos) AS n;
  RETURN v_u;
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
-- [p_sql] run as [p]; its raised SQLSTATE and message, or 'ok'.
CREATE FUNCTION pg_temp.err(p uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.as_person(p);
  EXECUTE p_sql;
  PERFORM pg_temp.as_db();
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.as_db();
  RETURN SQLSTATE || ':' || SQLERRM;
END $$;
CREATE FUNCTION pg_temp.start(p uuid, p_step text DEFAULT 'liveness', p_doc text DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  -- Spec 2 W4b (T5 fix round 1, I-3): the first check names its phone.
  SELECT public.begin_dating_verification(p, 'activation', p_step, 'fake',
                                          encode(extensions.digest(repeat('f', 32), 'sha256'), 'hex'), p_doc);
$$;
CREATE FUNCTION pg_temp.match(p_a uuid, p_b uuid) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state)
  VALUES (least(p_a, p_b), greatest(p_a, p_b), 'active') RETURNING id;
$$;
CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0)::bigint;
$$;
-- Spec 2 W4a (fix round 1, M-4): [p_setup] then [p_probe], always undone;
-- the probe's text. pg_temp.conflicts(table, n) is a setup whose first n
-- updates of [table] fail with a lock conflict (55P03).
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
    RAISE EXCEPTION 'w4a:probe_undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'w4a:probe_undo' THEN
      RAISE;
    END IF;
  END;
  RETURN coalesce(v, '<NULL>');
END $$;
CREATE FUNCTION pg_temp.conflicts(p_table text, p_n int) RETURNS text[] LANGUAGE sql AS $fn$
  SELECT ARRAY['CREATE TEMP SEQUENCE w4a_conflicts',
    format($s$CREATE FUNCTION pg_temp.w4a_conflict() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
  IF nextval('pg_temp.w4a_conflicts') <= %s THEN
    RAISE EXCEPTION 'w4a stand-in conflict' USING ERRCODE = '55P03';
  END IF;
  RETURN NEW;
END $f$$s$, p_n),
    format('CREATE TRIGGER w4a_conflict BEFORE UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION pg_temp.w4a_conflict()', p_table)];
$fn$;
-- Spec 2 W4a (T2 fix round 1, M-3): a failed liveness attempt needs the
-- vendor reference it answers for; H2's probe of one sets it first.
CREATE FUNCTION pg_temp.ref_first(p_sql text, p_session uuid) RETURNS text[] LANGUAGE sql AS $$
  SELECT CASE WHEN p_sql LIKE '%record_dating_liveness_attempt%'
              THEN ARRAY[format('UPDATE public.dating_verification_sessions SET vendor_session_ref = ''ref'' WHERE id = %L', p_session)]
              ELSE ARRAY[]::text[] END;
$$;
-- [p_sql]'s answer, then the session [p_session] (state/outcome/attempts/
-- vendor reference), the person's record (age/identity/revoked) and how
-- many updates were tried.
CREATE FUNCTION pg_temp.write_seen(p_sql text, p_user uuid, p_session uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  EXECUTE p_sql INTO v;
  RETURN v || ' / ' || coalesce((SELECT s.state || '/' || coalesce(s.outcome, '-') || '/' || s.attempts || '/' || coalesce(s.vendor_session_ref, '-')
                                   FROM public.dating_verification_sessions AS s WHERE s.id = p_session), '-')
           || ' / ' || coalesce((SELECT coalesce(a.age_result, '-') || '/' || coalesce(a.identity_result, '-') || '/' || (a.revoked_at IS NOT NULL)
                                   FROM public.dating_age_verifications AS a WHERE a.user_id = p_user), '-')
           || ' / ' || currval('pg_temp.w4a_conflicts');
END $$;

-- Spec 2 W4 final (M-3): a phone trusted as the edge function trusts one,
-- through a session that ran on it (a passed re-check two days old, so it
-- is in no rate count and no status read).
CREATE FUNCTION pg_temp.trust(p uuid, p_hash text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_s uuid;
BEGIN
  INSERT INTO public.dating_verification_sessions (user_id, kind, step, vendor, state, outcome, device_hash,
                                                   created_at, updated_at, expires_at)
  VALUES (p, 'reverify', 'liveness', 'fake', 'passed', 'verified', p_hash,
          now() - interval '2 days', now() - interval '2 days', now() - interval '2 days')
  RETURNING id INTO v_s;
  RETURN public.trust_dating_device(p, p_hash, v_s);
END $$;

-- =====================================================================
-- A. (§4.3, §1.4) The record keeps methods and pass/fail only: no DOB, no
--    date of any kind, no estimate, image or template; a fae pass below
--    the challenge age, or without one, is refused by the table itself.
-- =====================================================================
DO $a$
DECLARE
  v_u constant uuid := pg_temp.person('01');
  v_got text;
BEGIN
  SELECT string_agg(c.column_name, ', ' ORDER BY c.column_name) INTO v_got
    FROM information_schema.columns AS c
   WHERE c.table_schema = 'public' AND c.table_name = 'dating_age_verifications'
     AND (c.data_type = 'date' OR c.column_name ~ '(birth|dob|estimate|image|template|frame|selfie)');
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_age_verifications keeps %', v_got;
  END IF;
  SELECT string_agg(c.column_name, ', ' ORDER BY c.column_name) INTO v_got
    FROM information_schema.columns AS c
   WHERE c.table_schema = 'public' AND c.table_name = 'dating_verification_sessions'
     AND (c.data_type IN ('bytea', 'date') OR c.column_name ~ '(birth|dob|estimate|image|template|frame|selfie)');
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_verification_sessions keeps %', v_got;
  END IF;
  BEGIN
    INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, challenge_age, age_vendor)
    VALUES (v_u, 'fae', 'pass', 24, 'fake');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fae pass at challenge age 24 was stored';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
  BEGIN
    INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, challenge_age, age_vendor)
    VALUES (v_u, 'fae', 'pass', NULL, 'fake');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fae pass with no challenge age was stored';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END $a$;

-- =====================================================================
-- B. (§3.3.1, §7.1, Q4) The age gate: a passed age check (fae or id), not
--    revoked, AND Spec 1's declared age 18 or over. A typed DOB alone, an
--    identity pass alone, a declared minor or no declared DOB never pass.
-- =====================================================================
DO $b$
DECLARE
  v_adult constant uuid := pg_temp.person('02');
  v_minor constant uuid := pg_temp.person('03', 17);
  v_none constant uuid := pg_temp.person('04', NULL);
  v_failed constant uuid := pg_temp.person('31');
BEGIN
  IF public.dating_age_gate_holds(v_adult) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a typed DOB alone opened the age gate';
  END IF;
  INSERT INTO public.dating_age_verifications (user_id, identity_method, identity_result, identity_vendor, identity_decided_at)
  VALUES (v_adult, 'liveness_compare', 'pass', 'fake', now());
  IF public.dating_age_gate_holds(v_adult) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an identity pass alone opened the age gate';
  END IF;
  UPDATE public.dating_age_verifications SET age_method = 'fae', age_result = 'pass', challenge_age = 25,
         age_vendor = 'fake', age_decided_at = now() WHERE user_id = v_adult;
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, challenge_age, age_vendor, age_decided_at)
  VALUES (v_minor, 'fae', 'pass', 25, 'fake', now()), (v_none, 'id', 'pass', NULL, 'fake', now());
  IF public.dating_age_gate_holds(v_adult) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fae pass for a declared adult is shut';
  END IF;
  IF public.dating_age_gate_holds(v_minor) IS NOT FALSE OR public.dating_age_gate_holds(v_none) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a declared minor or a missing DOB passed the age gate';
  END IF;
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, challenge_age, age_vendor, age_decided_at)
  VALUES (v_failed, 'id', 'fail', NULL, 'fake', now());
  IF public.dating_age_gate_holds(v_failed) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed age check opened the gate';
  END IF;
  UPDATE public.dating_age_verifications SET revoked_at = now(), revoke_reason = 'contract' WHERE user_id = v_adult;
  IF public.dating_age_gate_holds(v_adult) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a revoked age check still opens the gate';
  END IF;
END $b$;

-- =====================================================================
-- B2. (Spec 2 W4a fix round 1, M-5) A revoked result reads as not decided,
--     age and identity alike.
-- =====================================================================
DO $b2$
DECLARE
  v_u constant uuid := pg_temp.person('43');
BEGIN
  PERFORM public.record_dating_age_assurance(v_u, 'fae', 'pass', 25::smallint, 'fake');
  PERFORM public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', NULL);
  IF private.dating_verification_state(v_u) IS DISTINCT FROM '{"age": "pass", "identity": "pass"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fixture''s results do not read as passed: %', private.dating_verification_state(v_u);
  END IF;
  PERFORM public.revoke_dating_age_verification(v_u, 'contract');
  IF private.dating_verification_state(v_u) IS DISTINCT FROM '{"age": null, "identity": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a revoked result reads as decided: %', private.dating_verification_state(v_u);
  END IF;
END $b2$;

-- =====================================================================
-- C. (§7.1, mutant 8) Only the service role records a result; a client
--    can't, even by calling the writer. A fae pass below 25 is refused
--    by name (no row); 25 passes; id needs no challenge age; bad input is
--    'invalid', never a raise.
-- =====================================================================
DO $c$
DECLARE
  v_u constant uuid := pg_temp.person('05');
  v_w constant uuid := pg_temp.person('06');
  v_sig text;
  v_got jsonb := '[]'::jsonb;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY['public.record_dating_age_assurance(uuid,text,text,smallint,text)',
                               'public.record_dating_identity_check(uuid,text,text,text,uuid)',
                               'public.record_dating_age_far_below(uuid,uuid,text)', -- Spec 2 W4 final (M-8)
                               'public.revoke_dating_age_verification(uuid,text)',
                               'public.begin_dating_verification(uuid,text,text,text,text,text)',
                               'public.decide_dating_human_review(uuid,text,uuid)'] LOOP
    IF has_function_privilege('authenticated', v_sig, 'EXECUTE') OR has_function_privilege('anon', v_sig, 'EXECUTE')
       OR NOT has_function_privilege('service_role', v_sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is not the service role''s alone', v_sig;
    END IF;
  END LOOP;
  IF pg_temp.err(v_u, format('SELECT public.record_dating_age_assurance(%L, ''id'', ''pass'', NULL, ''self'')', v_u))
       NOT LIKE '42501:%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in person recorded their own age check';
  END IF;
  v_got := v_got || jsonb_build_array(
    public.record_dating_age_assurance(v_u, 'fae', 'pass', 24::smallint, 'fake'),
    public.record_dating_age_assurance(v_u, 'fae', 'pass', NULL, 'fake'),
    public.record_dating_age_assurance(v_u, 'id', 'pass', 25::smallint, 'fake'),
    public.record_dating_age_assurance(v_u, 'video', 'pass', NULL, 'fake'),
    public.record_dating_age_assurance(v_u, 'id', NULL, NULL, 'fake'),
    public.record_dating_age_assurance(v_u, 'id', 'pass', NULL, 'Not A Vendor'));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "challenge_too_low"}, {"ok": false, "reason": "invalid"},
      {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"},
      {"ok": false, "reason": "invalid"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the age writer answered %', v_got;
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused age result left a row';
  END IF;
  IF public.record_dating_age_assurance(v_u, 'fae', 'pass', 25::smallint, 'fake') ->> 'ok' IS DISTINCT FROM 'true'
     OR public.record_dating_age_assurance(v_w, 'id', 'pass', NULL, 'smile_id') ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fae pass at 25 or an id pass was refused';
  END IF;
  IF NOT public.dating_age_gate_holds(v_u) OR NOT public.dating_age_gate_holds(v_w)
     OR (SELECT challenge_age FROM public.dating_age_verifications WHERE user_id = v_u) IS DISTINCT FROM 25
     OR (SELECT age_vendor FROM public.dating_age_verifications WHERE user_id = v_w) IS DISTINCT FROM 'smile_id' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a recorded age pass does not hold';
  END IF;
END $c$;

-- =====================================================================
-- C2. (R-13, owner ruling 2026-11-09) An estimate never ends the check: a
--     fae fail is refused ('invalid') and leaves no row; a video check that
--     ended needs_id or age_uncertain lets the ID check begin; only a failed
--     ID check (or Spec 1's under-18 hold, section G) is final.
-- =====================================================================
DO $c2$
DECLARE
  v_u constant uuid := pg_temp.person('32');
  v_v constant uuid := pg_temp.person('33');
  v_s uuid;
  v_o text;
  v_got jsonb := '[]'::jsonb;
BEGIN
  IF public.record_dating_age_assurance(v_u, 'fae', 'fail', 25::smallint, 'fake') IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed estimate was recorded as an age result';
  END IF;
  FOREACH v_o IN ARRAY ARRAY['needs_id', 'age_uncertain'] LOOP
    v_s := (pg_temp.start(v_u) ->> 'session_id')::uuid;
    v_got := v_got || jsonb_build_array(public.finish_dating_verification_session(v_s, 'passed', v_o, NULL) ->> 'ok');
    v_got := v_got || jsonb_build_array(pg_temp.start(v_u, 'id', 'passport') ->> 'ok');
  END LOOP;
  IF v_got IS DISTINCT FROM '["true", "true", "true", "true"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed or uncertain estimate ended the check: %', v_got;
  END IF;
  -- A failed ID check is final: no step begins again.
  PERFORM public.record_dating_age_assurance(v_v, 'id', 'fail', NULL, 'fake');
  v_got := jsonb_build_array(pg_temp.start(v_v), pg_temp.start(v_v, 'id', 'passport'), pg_temp.start(v_v, 'human'));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "age_not_confirmed"}, {"ok": false, "reason": "age_not_confirmed"},
                              {"ok": false, "reason": "age_not_confirmed"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed ID check was not final: %', v_got;
  END IF;
END $c2$;

-- =====================================================================
-- C3. (Spec 2 W4a fix round 1, I-1; R-13) A new age decision supersedes a
--     revocation: after a revoked pass, a failed ID is final (every step
--     answers age_not_confirmed, the status read shows the fail), and so is
--     the far-below path.
-- =====================================================================
DO $c3$
DECLARE
  v_u constant uuid := pg_temp.person('36');
  v_w constant uuid := pg_temp.person('56');
  v_s uuid;
  v_got jsonb;
BEGIN
  PERFORM public.record_dating_age_assurance(v_u, 'fae', 'pass', 25::smallint, 'fake');
  PERFORM public.revoke_dating_age_verification(v_u, 'contract');
  PERFORM public.record_dating_age_assurance(v_u, 'id', 'fail', NULL, 'fake');
  v_got := jsonb_build_array(pg_temp.start(v_u), pg_temp.start(v_u, 'id', 'passport'));
  v_got := v_got || jsonb_build_array(pg_temp.call(v_u, 'SELECT public.get_my_dating_verification()') ->> 'age',
    (SELECT revoked_at IS NULL AND revoke_reason IS NULL FROM public.dating_age_verifications WHERE user_id = v_u));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "age_not_confirmed"}, {"ok": false, "reason": "age_not_confirmed"},
                              "fail", true]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed ID after a revocation was not final: %', v_got;
  END IF;
  PERFORM public.record_dating_age_assurance(v_w, 'fae', 'pass', 25::smallint, 'fake');
  PERFORM public.revoke_dating_age_verification(v_w, 'contract');
  v_s := (pg_temp.start(v_w) ->> 'session_id')::uuid;
  PERFORM public.record_dating_age_far_below(v_w, v_s, 'fake');
  v_got := jsonb_build_array(pg_temp.call(v_w, 'SELECT public.get_my_dating_verification()') ->> 'age',
    (SELECT revoked_at IS NULL AND revoke_reason IS NULL FROM public.dating_age_verifications WHERE user_id = v_w));
  IF v_got IS DISTINCT FROM '["fail", true]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: far below 18 after a revocation does not read as failed: %', v_got;
  END IF;
END $c3$;

-- =====================================================================
-- C4. (Spec 2 W4a fix round 1, M-6) A revocation needs a reason, and every
--     refusal names its own: no record is not_found; a missing or malformed
--     reason, or no person, is invalid (and revokes nothing).
-- =====================================================================
DO $c4$
DECLARE
  v_u constant uuid := pg_temp.person('55');
  v_got jsonb;
BEGIN
  v_got := jsonb_build_array(public.revoke_dating_age_verification(v_u, 'contract'),
                             public.revoke_dating_age_verification(v_u, NULL),
                             public.revoke_dating_age_verification(v_u, ''),
                             public.revoke_dating_age_verification(v_u, 'Not A Reason'),
                             public.revoke_dating_age_verification(NULL, 'contract'));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "not_found"}, {"ok": false, "reason": "invalid"},
      {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the revocation answered %', v_got;
  END IF;
  PERFORM public.record_dating_age_assurance(v_u, 'fae', 'pass', 25::smallint, 'fake');
  v_got := public.revoke_dating_age_verification(v_u, NULL);
  IF v_got IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb
     OR (SELECT revoked_at FROM public.dating_age_verifications WHERE user_id = v_u) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a revocation without a reason revoked: %', v_got;
  END IF;
END $c4$;

-- =====================================================================
-- D. (§3.3.1, §4.4) Identity: liveness_compare (no decider) or
--    human_gesture (a reviewer's id) sets the profile's verification
--    state; a fail clears it; no profile, no record.
-- =====================================================================
DO $d$
DECLARE
  v_u constant uuid := pg_temp.person('07');
  v_got jsonb;
BEGIN
  v_got := jsonb_build_array(
    public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', pg_temp.id('99')),
    public.record_dating_identity_check(v_u, 'human_gesture', 'pass', 'attune', NULL),
    public.record_dating_identity_check(pg_temp.id('98'), 'liveness_compare', 'pass', 'fake', NULL));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"},
                              {"ok": false, "reason": "not_eligible"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the identity writer answered %', v_got;
  END IF;
  PERFORM public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', NULL);
  IF (SELECT verification_state || '/' || verification_method FROM public.dating_profiles WHERE user_id = v_u)
       IS DISTINCT FROM 'verified/liveness_compare'
     OR (SELECT identity_result FROM public.dating_age_verifications WHERE user_id = v_u) IS DISTINCT FROM 'pass' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an identity pass did not verify the profile';
  END IF;
  PERFORM public.record_dating_identity_check(v_u, 'human_gesture', 'fail', 'attune', pg_temp.id('99'));
  IF (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM 'unverified'
     OR (SELECT decided_by FROM public.dating_age_verifications WHERE user_id = v_u) IS DISTINCT FROM pg_temp.id('99') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an identity fail did not clear the profile''s verification';
  END IF;
END $d$;

-- =====================================================================
-- E. (§4.10, 04 G14, carry 1) A revocation, or an age check that fails,
--    pauses the active enrolment with 'verification' and closes every
--    match as age_verification_invalid (30-day evidence window); resume
--    refuses while it stands.
-- =====================================================================
DO $e$
DECLARE
  v_a constant uuid := pg_temp.person('08');
  v_b constant uuid := pg_temp.person('09');
  v_c constant uuid := pg_temp.person('10');
  v_m uuid;
  v_n uuid;
BEGIN
  PERFORM public.record_dating_age_assurance(u, 'fae', 'pass', 25::smallint, 'fake') FROM unnest(ARRAY[v_a, v_b, v_c]) AS u;
  UPDATE public.dating_enrollments SET state = 'active', activated_at = now() WHERE user_id IN (v_a, v_c);
  UPDATE public.dating_profiles SET profile_state = 'active' WHERE user_id IN (v_a, v_c);
  v_m := pg_temp.match(v_a, v_b);
  v_n := pg_temp.match(v_c, v_b);
  IF public.revoke_dating_age_verification(v_a, 'contract') ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the revocation was refused';
  END IF;
  IF (SELECT state || '/' || coalesce(pause_reason, 'NULL') FROM public.dating_enrollments WHERE user_id = v_a) IS DISTINCT FROM 'paused/verification'
     OR NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_m AND state = 'closed'
                     AND closed_reason = 'age_verification_invalid'
                     AND evidence_until BETWEEN now() + interval '29 days' AND now() + interval '31 days') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a revocation did not pause with its reason or close the match: % / %',
      (SELECT state || '/' || coalesce(pause_reason, 'NULL') FROM public.dating_enrollments WHERE user_id = v_a),
      (SELECT state || '/' || coalesce(closed_reason, 'NULL') FROM public.dating_matches WHERE id = v_m);
  END IF;
  IF pg_temp.err(v_a, 'SELECT public.resume_dating_mode(''w4a-resume-00001'')') IS DISTINCT FROM '22023:resume_gates_not_met' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resume did not refuse a revoked age check: %',
      pg_temp.err(v_a, 'SELECT public.resume_dating_mode(''w4a-resume-00002'')');
  END IF;
  PERFORM public.record_dating_age_assurance(v_c, 'id', 'fail', NULL, 'fake');
  IF (SELECT state || '/' || coalesce(pause_reason, 'NULL') FROM public.dating_enrollments WHERE user_id = v_c) IS DISTINCT FROM 'paused/verification'
     OR NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_n AND closed_reason = 'age_verification_invalid') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed age check did not pause or close';
  END IF;
END $e$;

-- =====================================================================
-- E2. (Spec 2 W4a fix round 1, M-1, M-2; carry 1) A person's own pause
--     ('user' or 'away') takes the check's reason when the age is revoked
--     or fails, so resume and the home answer as for any verification
--     pause: no resume while the check fails (the home's can_resume is
--     false), Resume again once a new check passes. A system pause keeps
--     its own reason.
-- =====================================================================
DO $e2$
DECLARE
  v_a constant uuid := pg_temp.person('44');
  v_b constant uuid := pg_temp.person('45');
  v_c constant uuid := pg_temp.person('46');
  v_got jsonb;
BEGIN
  PERFORM public.record_dating_age_assurance(u, 'fae', 'pass', 25::smallint, 'fake') FROM unnest(ARRAY[v_a, v_b, v_c]) AS u;
  UPDATE public.dating_enrollments SET state = 'paused', activated_at = now(), paused_at = now(),
         pause_reason = CASE user_id WHEN v_a THEN 'user' WHEN v_b THEN 'away' ELSE 'gates' END
   WHERE user_id IN (v_a, v_b, v_c);
  PERFORM public.revoke_dating_age_verification(v_a, 'contract');
  PERFORM public.record_dating_age_assurance(v_b, 'id', 'fail', NULL, 'fake');
  PERFORM public.revoke_dating_age_verification(v_c, 'contract');
  v_got := jsonb_build_array(
    (SELECT state || '/' || coalesce(pause_reason, 'NULL') FROM public.dating_enrollments WHERE user_id = v_a),
    (SELECT state || '/' || coalesce(pause_reason, 'NULL') FROM public.dating_enrollments WHERE user_id = v_b),
    (SELECT state || '/' || coalesce(pause_reason, 'NULL') FROM public.dating_enrollments WHERE user_id = v_c));
  v_got := v_got || jsonb_build_array(pg_temp.err(v_a, 'SELECT public.resume_dating_mode(''w4a-resume-00003'')'));
  v_got := v_got || jsonb_build_array(pg_temp.call(v_a, 'SELECT public.get_dating_home()') ->> 'state',
                                      pg_temp.call(v_a, 'SELECT public.get_dating_home()') ->> 'can_resume');
  IF v_got IS DISTINCT FROM '["paused/verification", "paused/verification", "paused/gates",
                              "22023:resume_gates_not_met", "paused", "false"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person''s own pause kept its reason, or the home offers Resume, while the check fails: %', v_got;
  END IF;
  PERFORM public.record_dating_age_assurance(v_a, 'id', 'pass', NULL, 'fake');
  IF pg_temp.call(v_a, 'SELECT public.get_dating_home()') ->> 'can_resume' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a verification pause does not offer Resume once the check passes: %',
      pg_temp.call(v_a, 'SELECT public.get_dating_home()');
  END IF;
END $e2$;

-- =====================================================================
-- F. (§6.3, §7.1, §7.2 S2) An age_review restriction (the underage_risk
--    path) closes every match as age_review.
-- =====================================================================
DO $f$
DECLARE
  v_a constant uuid := pg_temp.person('11');
  v_b constant uuid := pg_temp.person('12');
  v_c constant uuid := pg_temp.person('13');
  v_m1 uuid;
  v_m2 uuid;
BEGIN
  v_m1 := pg_temp.match(v_a, v_b);
  v_m2 := pg_temp.match(v_a, v_c);
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_a, 'age_review');
  IF (SELECT count(*) FROM public.dating_matches WHERE id IN (v_m1, v_m2) AND state = 'closed' AND closed_reason = 'age_review') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an age_review left a match open or closed it under another reason';
  END IF;
END $f$;

-- =====================================================================
-- G. (§3.3.2, §6.3, I-7, R8) Far below 18: the age check fails, every
--    match closes as age_review, and Spec 1's age_review hold is placed
--    with the session as its reference, once; a replay places nothing more.
--    Nothing else in Dating calls place_account_hold.
-- =====================================================================
DO $g$
DECLARE
  v_a constant uuid := pg_temp.person('14');
  v_b constant uuid := pg_temp.person('15');
  v_s uuid;
  v_m uuid;
  v_at timestamptz;
  v_got text;
BEGIN
  v_s := (pg_temp.start(v_a) ->> 'session_id')::uuid;
  v_m := pg_temp.match(v_a, v_b);
  IF public.record_dating_age_far_below(v_a, v_s, 'fake') IS DISTINCT FROM '{"ok": true, "replayed": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the far-below path was refused';
  END IF;
  SELECT created_at INTO v_at FROM public.account_holds WHERE user_id = v_a AND kind = 'age_review';
  IF (SELECT reason_ref FROM public.account_holds WHERE user_id = v_a AND kind = 'age_review' AND resolved_at IS NULL)
       IS DISTINCT FROM v_s::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the age_review hold does not name the session (three arguments, I-7)';
  END IF;
  IF (SELECT age_result || '/' || age_method FROM public.dating_age_verifications WHERE user_id = v_a) IS DISTINCT FROM 'fail/fae'
     OR (SELECT closed_reason FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'age_review'
     OR (SELECT state || '/' || outcome FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'failed/far_below' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: far below 18 did not fail the age check, close as age_review and end the session';
  END IF;
  IF public.record_dating_age_far_below(v_a, v_s, 'fake') IS DISTINCT FROM '{"ok": true, "replayed": true}'::jsonb
     OR (SELECT created_at FROM public.account_holds WHERE user_id = v_a AND kind = 'age_review') IS DISTINCT FROM v_at THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay of the far-below path placed the hold again';
  END IF;
  IF public.record_dating_age_far_below(v_b, v_s, 'fake') IS DISTINCT FROM '{"ok": false, "reason": "session_unavailable"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_b) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another person''s session placed a hold';
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_got
    FROM pg_proc AS p
   WHERE p.prosrc ~ 'place_account_hold\(' AND p.proname <> 'place_account_hold';
  -- Spec 2 W7b (§6.3): a moderator confirming a minor is the other Dating caller.
  IF v_got IS DISTINCT FROM 'consume_fresh_start(text,text), correct_my_birth_date(date), moderation_confirm_minor(uuid,uuid), private.handle_csam_match(text,text,uuid,text,text,boolean,text), record_dating_age_far_below(uuid,uuid,text), set_my_birth_date(date)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the callers of place_account_hold changed (R8): %', v_got;
  END IF;
  -- The hold is Spec 1's: Dating reads it as account_unavailable / age_review.
  IF public.dating_eligibility(v_a, 'setup') IS DISTINCT FROM 'account_unavailable'
     OR private.dating_unavailable_state(v_a) IS DISTINCT FROM 'age_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the hold does not close Dating';
  END IF;
END $g$;

-- =====================================================================
-- G2. (Spec 2 W4a fix round 1, M-3; R-13) The writers hold finality
--     themselves, not only begin: a standing failed age check is never
--     overwritten (age_not_confirmed) until a revocation reopens it; the
--     far-below path takes only an open session (a replay is still
--     answered as one, section G).
-- =====================================================================
DO $g2$
DECLARE
  v_u constant uuid := pg_temp.person('37');
  v_w constant uuid := pg_temp.person('38');
  v_s uuid;
  v_got jsonb;
BEGIN
  PERFORM public.record_dating_age_assurance(v_u, 'id', 'fail', NULL, 'fake');
  v_got := jsonb_build_array(public.record_dating_age_assurance(v_u, 'fae', 'pass', 25::smallint, 'fake'),
                             public.record_dating_age_assurance(v_u, 'id', 'pass', NULL, 'fake'));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "age_not_confirmed"}, {"ok": false, "reason": "age_not_confirmed"}]'::jsonb
     OR (SELECT age_method || '/' || age_result FROM public.dating_age_verifications WHERE user_id = v_u) IS DISTINCT FROM 'id/fail' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a standing failed age check was overwritten: %', v_got;
  END IF;
  PERFORM public.revoke_dating_age_verification(v_u, 'appeal');
  v_got := public.record_dating_age_assurance(v_u, 'id', 'pass', NULL, 'fake');
  IF v_got ->> 'ok' IS DISTINCT FROM 'true' OR public.dating_age_gate_holds(v_u) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pass after a revoked fail did not hold: %', v_got;
  END IF;
  v_s := (pg_temp.start(v_w) ->> 'session_id')::uuid;
  PERFORM public.finish_dating_verification_session(v_s, 'passed', 'verified', NULL);
  v_got := public.record_dating_age_far_below(v_w, v_s, 'fake');
  IF v_got IS DISTINCT FROM '{"ok": false, "reason": "session_unavailable"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_w)
     OR EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE user_id = v_w) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the far-below path took a closed session: %', v_got;
  END IF;
END $g2$;

-- =====================================================================
-- H. (§3.3.2, §4.7) Sessions: every refusal by name, never a raise; a
--    resumed session is the same row; another step ends the open one; 5 a
--    day; a liveness failure counts (retry, then another way).
-- =====================================================================
DO $h$
DECLARE
  v_u constant uuid := pg_temp.person('16');
  v_one constant uuid := pg_temp.person('17', 30, 1);
  v_nobio constant uuid := pg_temp.person('18', 30, 2, 'GB', 'TLI', false);
  v_gh constant uuid := pg_temp.person('19', 30, 2, 'GH', 'AA');
  v_bare constant uuid := pg_temp.id('20');
  v jsonb;
  v_s uuid;
  v_t uuid;
  v_got jsonb;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_bare, '1555870720', now(), now() - interval '40 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_bare, '1555870720', 'Verify 20', 'dating', now() - interval '40 days', now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (v_bare, current_date - interval '30 years');
  v_got := jsonb_build_array(
    public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', NULL, NULL),
    public.begin_dating_verification(v_u, 'activation', 'selfie', 'fake', NULL, NULL),
    public.begin_dating_verification(v_u, 'activation', 'liveness', 'Fake!', NULL, NULL),
    public.begin_dating_verification(v_u, 'activation', 'liveness', 'fake', 'not-a-hash', NULL),
    public.begin_dating_verification(v_u, 'activation', 'id', 'fake', NULL, NULL),
    public.begin_dating_verification(v_u, 'activation', 'liveness', 'fake', NULL, 'passport'),
    pg_temp.start(v_bare), pg_temp.start(v_nobio), pg_temp.start(v_one),
    pg_temp.start(v_gh, 'id', 'uk_photocard_driving_licence'));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"},
      {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"},
      {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "not_eligible"}, {"ok": false, "reason": "consent_required"},
      {"ok": false, "reason": "photos_required"}, {"ok": false, "reason": "invalid"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: begin answered %', v_got;
  END IF;
  -- Off: the flag, or a fake mode outside development.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_age_assurance';
  v := pg_temp.start(v_u);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_age_assurance';
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  v_got := jsonb_build_array(v, pg_temp.start(v_u));
  PERFORM set_config('app.settings.attune_environment', '', true);
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: begin ran with the flag off or fake in production: %', v_got;
  END IF;
  -- Begin, resume (same row, no new one), then a liveness failure twice.
  v := pg_temp.start(v_u);
  v_s := (v ->> 'session_id')::uuid;
  IF v ->> 'resumed' IS DISTINCT FROM 'false' OR (pg_temp.start(v_u) ->> 'session_id')::uuid IS DISTINCT FROM v_s
     OR pg_temp.start(v_u) ->> 'resumed' IS DISTINCT FROM 'true'
     OR (SELECT count(*) FROM public.dating_verification_sessions WHERE user_id = v_u) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a resumed session is not the same row: %', v;
  END IF;
  -- Spec 2 W4a (T2 fix round 1, M-3): a failure counts once per vendor
  -- session (its reference is cleared); a repeat on the same one is refused.
  PERFORM public.set_dating_verification_ref(v_s, 'ref-1');
  v_got := jsonb_build_array(public.record_dating_liveness_attempt(v_s, false), public.record_dating_liveness_attempt(v_s, false));
  PERFORM public.set_dating_verification_ref(v_s, 'ref-2');
  v_got := v_got || jsonb_build_array(public.record_dating_liveness_attempt(v_s, false), public.record_dating_liveness_attempt(v_s, true));
  IF v_got IS DISTINCT FROM '[{"ok": true, "outcome": "retry", "attempts": 1}, {"ok": false, "reason": "session_unavailable"},
                              {"ok": true, "outcome": "another_way", "attempts": 2}, {"ok": true, "attempts": 2}]'::jsonb
     OR (SELECT vendor_session_ref FROM public.dating_verification_sessions WHERE id = v_s) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: liveness attempts answered %', v_got;
  END IF;
  -- Another step ends the open one; an expired session is gone for writes.
  v_t := (pg_temp.start(v_u, 'human') ->> 'session_id')::uuid;
  IF v_t IS NULL OR v_t = v_s OR (SELECT state FROM public.dating_verification_sessions WHERE id = v_s) <> 'expired'
     OR (SELECT cardinality(gestures) FROM public.dating_verification_sessions WHERE id = v_t) <> 2
     OR (SELECT gestures[1] <> gestures[2] AND gestures <@ ARRAY['three_fingers', 'left_ear', 'thumbs_up']
           FROM public.dating_verification_sessions WHERE id = v_t) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the human route did not end the video session or pick two gestures';
  END IF;
  UPDATE public.dating_verification_sessions SET expires_at = now() - interval '1 second' WHERE id = v_t;
  IF public.record_dating_liveness_attempt(v_s, false) IS DISTINCT FROM '{"ok": false, "reason": "session_unavailable"}'::jsonb
     OR public.set_dating_verification_ref(v_t, 'ref') IS DISTINCT FROM '{"ok": false, "reason": "session_unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ended or expired session was written';
  END IF;
  -- Five sessions a day.
  FOR i IN 1..3 LOOP
    PERFORM pg_temp.start(v_u, CASE WHEN i % 2 = 1 THEN 'liveness' ELSE 'human' END);
  END LOOP;
  IF (SELECT count(*) FROM public.dating_verification_sessions WHERE user_id = v_u) <> 5
     OR pg_temp.start(v_u, 'id', 'passport') IS DISTINCT FROM '{"ok": false, "reason": "rate_limited"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sixth session in a day was opened';
  END IF;
  -- The refused start left the open session as it was.
  IF (SELECT count(*) FROM public.dating_verification_sessions WHERE user_id = v_u AND state = 'started') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused start ended the open session';
  END IF;
  -- awaiting review, already verified, age not confirmed.
  UPDATE public.dating_verification_sessions SET state = 'awaiting_review' WHERE user_id = v_u AND state = 'started';
  IF pg_temp.start(v_u) ->> 'reason' IS DISTINCT FROM 'awaiting_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a session opened beside one awaiting review';
  END IF;
  PERFORM public.record_dating_age_assurance(v_gh, 'fae', 'pass', 25::smallint, 'fake');
  PERFORM public.record_dating_identity_check(v_gh, 'liveness_compare', 'pass', 'fake', NULL);
  v_got := jsonb_build_array(pg_temp.start(v_gh), pg_temp.start(v_gh, 'id', 'ghana_card'), pg_temp.start(v_gh, 'human'));
  PERFORM public.record_dating_age_assurance(v_gh, 'id', 'fail', NULL, 'fake');
  v_got := v_got || jsonb_build_array(pg_temp.start(v_gh));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "already_verified"}, {"ok": false, "reason": "already_verified"},
                              {"ok": false, "reason": "already_verified"}, {"ok": false, "reason": "age_not_confirmed"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a verified or failed person began a session: %', v_got;
  END IF;
  -- A new photo after the check needs the video again (W3c: needs_review).
  UPDATE public.dating_age_verifications SET age_result = 'pass', age_method = 'fae', challenge_age = 25 WHERE user_id = v_gh;
  UPDATE public.dating_profiles SET verification_state = 'needs_review' WHERE user_id = v_gh;
  IF pg_temp.start(v_gh) ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new photo after the check could not be checked again';
  END IF;
  -- finish: named outcomes only; a mismatch names its slot.
  v_s := (SELECT id FROM public.dating_verification_sessions WHERE user_id = v_gh AND state = 'started');
  v_got := jsonb_build_array(public.finish_dating_verification_session(v_s, 'failed', 'photo_mismatch', NULL),
                             public.finish_dating_verification_session(v_s, 'failed', 'verified', 2::smallint),
                             public.finish_dating_verification_session(v_s, 'started', 'verified', NULL),
                             public.finish_dating_verification_session(v_s, 'failed', 'photo_mismatch', 2::smallint),
                             public.finish_dating_verification_session(v_s, 'passed', 'verified', NULL));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"},
                              {"ok": true, "reason": null}, {"ok": false, "reason": "session_unavailable"}]'::jsonb
     OR (SELECT outcome || '/' || outcome_position FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'photo_mismatch/2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: finish answered %', v_got;
  END IF;
END $h$;

-- =====================================================================
-- H2. (Spec 2 W4a fix round 1, M-4) Every session, review and revocation
--     writer absorbs two lock conflicts (three tries); endless conflicts
--     answer busy and change nothing (a reviewer's pass records no
--     identity result).
-- =====================================================================
DO $h2$
DECLARE
  v_u constant uuid := pg_temp.person('34');
  v_h constant uuid := pg_temp.person('35');
  v_d constant uuid := pg_temp.person('53');
  v_r constant uuid := pg_temp.person('54');
  v_s uuid;
  v_hs uuid;
  v_ds uuid;
  v_case text[];
  v_got jsonb := '[]'::jsonb;
BEGIN
  PERFORM public.record_dating_age_assurance(v_r, 'fae', 'pass', 25::smallint, 'fake');
  v_s := (pg_temp.start(v_u) ->> 'session_id')::uuid;
  v_hs := (pg_temp.start(v_h, 'human') ->> 'session_id')::uuid;
  v_ds := (pg_temp.start(v_d, 'human') ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_hs || '/1.jpg', v_h), ('dating-verification-review', v_hs || '/2.jpg', v_h),
    ('dating-verification-review', v_ds || '/1.jpg', v_d), ('dating-verification-review', v_ds || '/2.jpg', v_d);
  PERFORM public.submit_dating_human_review(v_d, v_ds);
  FOREACH v_case SLICE 1 IN ARRAY ARRAY[
    ['public.dating_verification_sessions', format('SELECT public.set_dating_verification_ref(%L, ''ref'')::text', v_s), v_u::text, v_s::text],
    ['public.dating_verification_sessions', format('SELECT public.record_dating_liveness_attempt(%L, false)::text', v_s), v_u::text, v_s::text],
    ['public.dating_verification_sessions', format('SELECT public.finish_dating_verification_session(%L, ''failed'', ''photo_mismatch'', 1::smallint)::text', v_s), v_u::text, v_s::text],
    ['public.dating_verification_sessions', format('SELECT public.submit_dating_human_review(%L, %L)::text', v_h, v_hs), v_h::text, v_hs::text],
    ['public.dating_verification_sessions', format('SELECT public.decide_dating_human_review(%L, ''pass'', %L)::text', v_ds, pg_temp.id('99')), v_d::text, v_ds::text],
    ['public.dating_age_verifications', format('SELECT public.revoke_dating_age_verification(%L, ''contract'')::text', v_r), v_r::text, NULL]] LOOP
    v_got := v_got || jsonb_build_array(
      pg_temp.probe(pg_temp.ref_first(v_case[2], v_s) || pg_temp.conflicts(v_case[1], 2), format('SELECT pg_temp.write_seen(%L, %L, %L)', v_case[2], v_case[3], v_case[4])),
      pg_temp.probe(pg_temp.ref_first(v_case[2], v_s) || pg_temp.conflicts(v_case[1], 1000), format('SELECT pg_temp.write_seen(%L, %L, %L)', v_case[2], v_case[3], v_case[4])));
  END LOOP;
  IF v_got IS DISTINCT FROM jsonb_build_array(
      '{"ok": true, "reason": null} / started/-/0/ref / - / 3', '{"ok": false, "reason": "busy"} / started/-/0/- / - / 3',
      '{"ok": true, "outcome": "retry", "attempts": 1} / started/retry/1/- / - / 3', '{"ok": false, "reason": "busy"} / started/-/0/ref / - / 3',
      '{"ok": true, "reason": null} / failed/photo_mismatch/0/- / - / 3', '{"ok": false, "reason": "busy"} / started/-/0/- / - / 3',
      '{"ok": true} / awaiting_review/human_pending/0/- / - / 3', '{"ok": false, "reason": "busy"} / started/-/0/- / - / 3',
      '{"ok": true} / passed/verified/0/- / -/pass/false / 3', '{"ok": false, "reason": "busy"} / awaiting_review/human_pending/0/- / - / 3',
      '{"ok": true} / - / pass/-/true / 3', '{"ok": false, "reason": "busy"} / - / pass/-/false / 3') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a writer did not absorb two lock conflicts, or wrote through endless ones: %', v_got;
  END IF;
END $h2$;

-- =====================================================================
-- I. (§3.3.3, §4.5) The human route: the two photos go only under the
--    person's own open human session's two paths; submit needs both; a
--    reviewer decides identity only (never age); the photos are queued
--    for deletion at the decision.
-- =====================================================================
DO $i$
DECLARE
  v_u constant uuid := pg_temp.person('21');
  v_x constant uuid := pg_temp.person('22');
  v_s uuid;
  v_v uuid;
  v_got jsonb;
BEGIN
  PERFORM public.record_dating_age_assurance(v_u, 'fae', 'pass', 25::smallint, 'fake');
  v_v := (pg_temp.start(v_u) ->> 'session_id')::uuid;
  v_s := (pg_temp.start(v_u, 'human') ->> 'session_id')::uuid;
  v_got := jsonb_build_array(
    pg_temp.call(v_u, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_s || '/1.jpg')),
    pg_temp.call(v_u, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_s || '/2.jpg')),
    pg_temp.call(v_u, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_s || '/3.jpg')),
    pg_temp.call(v_u, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_s || '/1.png')),
    pg_temp.call(v_u, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_v || '/1.jpg')),
    pg_temp.call(v_x, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_s || '/1.jpg')));
  IF v_got IS DISTINCT FROM '[true, true, false, false, false, false]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the review upload predicate answered %', v_got;
  END IF;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-verification-review', v_s || '/1.jpg', v_u);
  IF public.submit_dating_human_review(v_u, v_s) IS DISTINCT FROM '{"ok": false, "reason": "photos_missing"}'::jsonb
     OR public.submit_dating_human_review(v_x, v_s) IS DISTINCT FROM '{"ok": false, "reason": "session_unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a review was submitted with one photo, or for someone else';
  END IF;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-verification-review', v_s || '/2.jpg', v_u);
  -- (Each call is its own statement: an IF's terms have no evaluation order.)
  v_got := public.submit_dating_human_review(v_u, v_s);
  IF v_got ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT state || '/' || outcome FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'awaiting_review/human_pending'
     OR (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM 'needs_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a submitted review is not waiting for a person';
  END IF;
  IF pg_temp.call(v_u, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_s || '/1.jpg')) <> 'false'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a submitted review still takes uploads';
  END IF;
  v_got := jsonb_build_array(public.decide_dating_human_review(v_s, 'pass', NULL),
                             public.decide_dating_human_review(v_s, 'approve', pg_temp.id('99')));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: decide answered %', v_got;
  END IF;
  UPDATE public.dating_age_verifications SET age_result = 'fail', age_method = 'id', challenge_age = NULL WHERE user_id = v_u;
  v_got := public.decide_dating_human_review(v_s, 'pass', pg_temp.id('99'));
  IF v_got ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT identity_method || '/' || identity_result || '/' || decided_by FROM public.dating_age_verifications WHERE user_id = v_u)
          IS DISTINCT FROM 'human_gesture/pass/' || pg_temp.id('99')
     OR (SELECT age_result FROM public.dating_age_verifications WHERE user_id = v_u) IS DISTINCT FROM 'fail'
     OR (SELECT state || '/' || outcome FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'passed/verified'
     OR (SELECT count(*) FROM public.media_deletion_queue WHERE bucket_id = 'dating-verification-review'
          AND object_name IN (v_s || '/1.jpg', v_s || '/2.jpg')) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reviewer''s pass did not decide identity only, or kept the photos';
  END IF;
  -- ask for ID: the profile goes back to unverified, identity untouched.
  v_s := (pg_temp.start(v_x, 'human') ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_x), ('dating-verification-review', v_s || '/2.jpg', v_x);
  PERFORM public.submit_dating_human_review(v_x, v_s);
  PERFORM public.decide_dating_human_review(v_s, 'ask_for_id', pg_temp.id('99'));
  IF (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_x) IS DISTINCT FROM 'unverified'
     OR EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE user_id = v_x AND identity_result IS NOT NULL)
     OR (SELECT outcome FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'ask_for_id' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ask for ID decided identity';
  END IF;
END $i$;

-- =====================================================================
-- I2. (Spec 2 W4a fix round 1, I-2 ruling; M-5) Until W7b's console owns ID
--     review, a reviewer may only send an ID check waiting for review back
--     for another ID (a person never passes age, §3.3.1): a pass or a fail
--     there, and any decision on a video session, is refused; after
--     ask_for_id the person can begin again (no review photos to delete).
-- =====================================================================
DO $i2$
DECLARE
  v_u constant uuid := pg_temp.person('41');
  v_v constant uuid := pg_temp.person('42');
  v_s uuid;
  v_l uuid;
  v_got jsonb;
BEGIN
  v_s := (pg_temp.start(v_u, 'id', 'passport') ->> 'session_id')::uuid;
  PERFORM public.finish_dating_verification_session(v_s, 'awaiting_review', 'dob_mismatch', NULL);
  v_l := (pg_temp.start(v_v) ->> 'session_id')::uuid;
  UPDATE public.dating_verification_sessions SET state = 'awaiting_review' WHERE id = v_l;
  v_got := jsonb_build_array(public.decide_dating_human_review(v_s, 'pass', pg_temp.id('99')),
                             public.decide_dating_human_review(v_s, 'fail', pg_temp.id('99')),
                             public.decide_dating_human_review(v_l, 'pass', pg_temp.id('99')),
                             public.decide_dating_human_review(v_l, 'ask_for_id', pg_temp.id('99')));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "session_unavailable"}, {"ok": false, "reason": "session_unavailable"},
      {"ok": false, "reason": "session_unavailable"}, {"ok": false, "reason": "session_unavailable"}]'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE user_id IN (v_u, v_v)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reviewer decided an ID check or a video session: %', v_got;
  END IF;
  v_got := public.decide_dating_human_review(v_s, 'ask_for_id', pg_temp.id('99'));
  v_got := jsonb_build_array(v_got, (SELECT state || '/' || outcome FROM public.dating_verification_sessions WHERE id = v_s),
    EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE user_id = v_u),
    EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name LIKE v_s || '/%'));
  v_got := v_got || jsonb_build_array(pg_temp.start(v_u, 'id', 'passport') ->> 'ok');
  IF v_got IS DISTINCT FROM '[{"ok": true}, "failed/ask_for_id", false, false, "true"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: asking for another ID on an ID check answered %', v_got;
  END IF;
END $i2$;

-- =====================================================================
-- I3. (Spec 2 W4a fix round 1, M-5) The compare list is the person's own
--     approved, scanned photos only; an expired human session takes no
--     upload.
-- =====================================================================
DO $i3$
DECLARE
  v_u constant uuid := pg_temp.person('57');
  v_x constant uuid := pg_temp.person('58');
  v_s uuid;
BEGIN
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state) VALUES
    (v_u, 'w4a/' || v_u || '/3.jpg', 3, 'pending', 'clear'),
    (v_u, 'w4a/' || v_u || '/4.jpg', 4, 'rejected', 'hit'),
    (v_u, 'w4a/' || v_u || '/5.jpg', 5, 'needs_review', 'pending');
  IF public.get_dating_verification_photos(v_u) IS DISTINCT FROM jsonb_build_array(
       jsonb_build_object('position', 1, 'storage_key', 'w4a/' || v_u || '/1.jpg'),
       jsonb_build_object('position', 2, 'storage_key', 'w4a/' || v_u || '/2.jpg')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the compare list is not the person''s own approved photos: %',
      public.get_dating_verification_photos(v_u);
  END IF;
  v_s := (pg_temp.start(v_x, 'human') ->> 'session_id')::uuid;
  UPDATE public.dating_verification_sessions SET expires_at = now() - interval '1 second' WHERE id = v_s;
  IF pg_temp.call(v_x, format('SELECT to_jsonb(public.dating_review_upload_open(%L))', v_s || '/1.jpg')) IS DISTINCT FROM 'false'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an expired human session takes an upload';
  END IF;
END $i3$;

-- =====================================================================
-- I4. (Spec 2 W4a fix round 1) A reviewer's pass decides identity only,
--     also for a person with no age result: the age stays undecided.
-- =====================================================================
DO $i4$
DECLARE
  v_u constant uuid := pg_temp.person('60');
  v_s uuid;
BEGIN
  v_s := (pg_temp.start(v_u, 'human') ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_u), ('dating-verification-review', v_s || '/2.jpg', v_u);
  PERFORM public.submit_dating_human_review(v_u, v_s);
  PERFORM public.decide_dating_human_review(v_s, 'pass', pg_temp.id('99'));
  IF (SELECT identity_result || '/' || coalesce(age_result, 'NULL') FROM public.dating_age_verifications WHERE user_id = v_u)
       IS DISTINCT FROM 'pass/NULL' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reviewer''s pass decided the age: %',
      (SELECT identity_result || '/' || coalesce(age_result, 'NULL') FROM public.dating_age_verifications WHERE user_id = v_u);
  END IF;
END $i4$;

-- =====================================================================
-- J. (§3.3.2) The person's own status read: signed in; their own data
--    only; never a vendor reference, a device hash or an estimate; on an
--    untrusted device only the device answer; unavailable with the flag
--    off or fake in production.
-- =====================================================================
DO $j$
DECLARE
  v_u constant uuid := pg_temp.person('23', 30, 2, 'GH', 'AA');
  v_x constant uuid := pg_temp.person('24');
  v jsonb;
  v_s uuid;
  v_msg text;
BEGIN
  BEGIN
    PERFORM public.get_my_dating_verification();
    RAISE EXCEPTION 'CONTRACT VIOLATED: the status read answered a signed-out caller';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'not_authenticated' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: signed out raised %', v_msg;
    END IF;
  END;
  v_s := (pg_temp.start(v_u) ->> 'session_id')::uuid;
  PERFORM public.set_dating_verification_ref(v_s, 'vendor-secret-ref');
  UPDATE public.dating_verification_sessions SET device_hash = repeat('a', 64) WHERE id = v_s;
  PERFORM public.record_dating_liveness_attempt(v_s, false);
  -- Spec 2 W4a (T2 fix round 1, M-3): the failure cleared the reference;
  -- the next vendor session's is set, so the leak check below has one.
  PERFORM public.set_dating_verification_ref(v_s, 'vendor-secret-ref');
  v := pg_temp.call(v_u, 'SELECT public.get_my_dating_verification()');
  IF v ->> 'available' IS DISTINCT FROM 'true' OR v ->> 'device' IS DISTINCT FROM 'trusted'
     OR v -> 'age' IS DISTINCT FROM 'null'::jsonb OR v -> 'identity' IS DISTINCT FROM 'null'::jsonb
     OR v #>> '{session,id}' IS DISTINCT FROM v_s::text OR v #>> '{session,open}' IS DISTINCT FROM 'true'
     OR v #>> '{session,outcome}' IS DISTINCT FROM 'retry' OR v #>> '{session,attempts}' IS DISTINCT FROM '1'
     OR v -> 'id_documents' IS DISTINCT FROM '[{"code": "ghana_card", "name_key": "dating_id_ghana_card"}, {"code": "passport", "name_key": "dating_id_passport"}]'::jsonb
     OR v ->> 'photos_ready' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the status read answered %', v;
  END IF;
  IF position('vendor-secret-ref' IN v::text) > 0 OR position(repeat('a', 64) IN v::text) > 0
     OR position('vendor' IN v::text) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the status read carries a vendor reference or a device hash: %', v;
  END IF;
  IF pg_temp.call(v_x, 'SELECT public.get_my_dating_verification()') -> 'session' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the status read showed another person''s session';
  END IF;
  -- An untrusted device (stub, rolled back): only the device answer.
  BEGIN
    CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $stub$ SELECT false $stub$;
    v := pg_temp.call(v_u, 'SELECT public.get_my_dating_verification()');
    RAISE SQLSTATE 'W4A99';
  EXCEPTION WHEN SQLSTATE 'W4A99' THEN
    NULL;
  END;
  IF v IS DISTINCT FROM '{"ok": true, "device": "untrusted", "session": null, "available": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an untrusted device read %', v;
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_age_assurance';
  v := pg_temp.call(v_u, 'SELECT public.get_my_dating_verification()');
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_age_assurance';
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  v := jsonb_build_array(v ->> 'available', pg_temp.call(v_u, 'SELECT public.get_my_dating_verification()') ->> 'available');
  PERFORM set_config('app.settings.attune_environment', '', true);
  IF v IS DISTINCT FROM '["false", "false"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the check reads available with the flag off or fake in production: %', v;
  END IF;
END $j$;

-- =====================================================================
-- K. (§3.1) get_dating_home: 'verifying' while a person or the ID vendor
--    is checking (and the check is the next step); setup otherwise.
-- =====================================================================
DO $k$
DECLARE
  v_u constant uuid := pg_temp.person('25');
  v_s uuid;
BEGIN
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  VALUES (v_u, private.dating_field_encrypt('{"identity": "woman"}'), private.dating_field_encrypt('{"seeking": ["man"]}'));
  UPDATE public.dating_profiles SET intention = 'committed', not_married_attested_at = now(), attestation_version = '2026-10-v1',
         children_have = false, children_want = 'open' WHERE user_id = v_u;
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer, moderation_state)
  SELECT v_u, n, (ARRAY['perfect_sunday', 'friends_say'])[n], 'An answer long enough ' || n, 'approved' FROM generate_series(1, 2) AS n;
  IF pg_temp.call(v_u, 'SELECT public.get_dating_home()') ->> 'next_step' IS DISTINCT FROM 'verify'
     OR pg_temp.call(v_u, 'SELECT public.get_dating_home()') ->> 'state' IS DISTINCT FROM 'setup_in_progress' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fixture is not at the check: %', pg_temp.call(v_u, 'SELECT public.get_dating_home()');
  END IF;
  v_s := (pg_temp.start(v_u, 'human') ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_u), ('dating-verification-review', v_s || '/2.jpg', v_u);
  PERFORM public.submit_dating_human_review(v_u, v_s);
  IF (pg_temp.call(v_u, 'SELECT public.get_dating_home()') - 'has_data') IS DISTINCT FROM '{"state": "verifying", "next_step": "verify"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a review in progress does not read verifying: %', pg_temp.call(v_u, 'SELECT public.get_dating_home()');
  END IF;
END $k$;

-- =====================================================================
-- L. (§3.3.2) The ID's date of birth is compared with the declared one and
--    forgotten: match, mismatch, minor, unknown.
-- =====================================================================
DO $l$
DECLARE
  v_u constant uuid := pg_temp.person('26');
  v_none constant uuid := pg_temp.person('27', NULL);
  v_dob date;
BEGIN
  SELECT birth_date INTO v_dob FROM public.account_birthdates WHERE user_id = v_u;
  IF jsonb_build_array(public.check_dating_id_birth_date(v_u, v_dob), public.check_dating_id_birth_date(v_u, v_dob - 1),
                       public.check_dating_id_birth_date(v_u, (current_date - interval '16 years')::date),
                       public.check_dating_id_birth_date(v_none, v_dob), public.check_dating_id_birth_date(v_u, NULL),
                       public.check_dating_id_birth_date(v_u, current_date + 1))
     IS DISTINCT FROM '["match", "mismatch", "minor", "unknown", "unknown", "unknown"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ID date-of-birth check is wrong';
  END IF;
  IF (SELECT provolatile FROM pg_proc WHERE oid = 'public.check_dating_id_birth_date(uuid,date)'::regprocedure) <> 's' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ID date-of-birth check can write';
  END IF;
END $l$;

-- =====================================================================
-- M. (§4.8, R-6) The sweep: an open session past its time expires; a
--    review waiting 72 hours expires (asked again); every review photo
--    older than 72 hours is queued for deletion; sessions older than 30
--    days are deleted.
-- =====================================================================
DO $m$
DECLARE
  v_u constant uuid := pg_temp.person('28');
  v_w constant uuid := pg_temp.person('29');
  v_s uuid;
  v_r uuid;
BEGIN
  v_s := (pg_temp.start(v_u) ->> 'session_id')::uuid;
  UPDATE public.dating_verification_sessions SET expires_at = now() - interval '1 minute' WHERE id = v_s;
  v_r := (pg_temp.start(v_w, 'human') ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner, created_at) VALUES
    ('dating-verification-review', v_r || '/1.jpg', v_w, now() - interval '73 hours'),
    ('dating-verification-review', v_r || '/2.jpg', v_w, now() - interval '73 hours'),
    ('dating-verification-review', 'orphan-of-a-deleted-account/1.jpg', NULL, now() - interval '80 hours');
  PERFORM public.submit_dating_human_review(v_w, v_r);
  UPDATE public.dating_verification_sessions SET created_at = now() - interval '73 hours',
         awaiting_since = now() - interval '73 hours' -- Spec 2 W4 final (M-1): submitted 73 hours ago (FF3: the clock is the submission's)
   WHERE id = v_r;
  INSERT INTO public.dating_verification_sessions (user_id, kind, step, state, created_at, expires_at)
  VALUES (v_u, 'activation', 'liveness', 'failed', now() - interval '31 days', now() - interval '31 days');
  PERFORM public.sweep_dating_verification_sessions();
  IF (SELECT state FROM public.dating_verification_sessions WHERE id = v_s) <> 'expired'
     OR (SELECT state FROM public.dating_verification_sessions WHERE id = v_r) <> 'expired'
     OR (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_w) <> 'unverified'
     OR (SELECT count(*) FROM public.media_deletion_queue WHERE bucket_id = 'dating-verification-review'
          AND object_name IN (v_r || '/1.jpg', v_r || '/2.jpg', 'orphan-of-a-deleted-account/1.jpg')) <> 3
     OR EXISTS (SELECT 1 FROM public.dating_verification_sessions WHERE user_id = v_u AND created_at < now() - interval '30 days') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep left a session, a review or a photo';
  END IF;
END $m$;

-- =====================================================================
-- M2. (Spec 2 W4a fix round 1, I-2 ruling) An ID check left waiting for
--     review (a date of birth that differs, a vendor still checking)
--     expires after 72 hours waiting, counted, and the person can begin
--     again; at 71 hours it still waits. The wait starts when the check
--     starts waiting, and "Check again" (R-12) keeps its start.
-- =====================================================================
DO $m2$
DECLARE
  v_u constant uuid := pg_temp.person('39');
  v_w constant uuid := pg_temp.person('40');
  v_n constant bigint := pg_temp.metric('dating.verify.id_review_expired');
  v_s uuid;
  v_t uuid;
  v_got jsonb;
BEGIN
  v_s := (pg_temp.start(v_u, 'id', 'passport') ->> 'session_id')::uuid;
  PERFORM public.finish_dating_verification_session(v_s, 'awaiting_review', 'dob_mismatch', NULL);
  v_t := (pg_temp.start(v_w, 'id', 'passport') ->> 'session_id')::uuid;
  PERFORM public.finish_dating_verification_session(v_t, 'awaiting_review', 'id_pending', NULL);
  IF (SELECT count(*) FROM public.dating_verification_sessions WHERE id IN (v_s, v_t) AND awaiting_since = now()) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the wait does not start when the ID check starts waiting';
  END IF;
  UPDATE public.dating_verification_sessions SET awaiting_since = now() - interval '72 hours 1 minute',
         created_at = now() - interval '73 hours' WHERE id = v_s;
  UPDATE public.dating_verification_sessions SET awaiting_since = now() - interval '71 hours',
         created_at = now() - interval '73 hours' WHERE id = v_t;
  PERFORM public.finish_dating_verification_session(v_s, 'awaiting_review', 'dob_mismatch', NULL);
  PERFORM public.sweep_dating_verification_sessions();
  v_got := jsonb_build_array((SELECT state FROM public.dating_verification_sessions WHERE id = v_s),
                             (SELECT state FROM public.dating_verification_sessions WHERE id = v_t),
                             pg_temp.metric('dating.verify.id_review_expired') - v_n);
  v_got := v_got || jsonb_build_array(pg_temp.start(v_u, 'id', 'passport') ->> 'ok');
  v_got := v_got || jsonb_build_array(pg_temp.start(v_w, 'id', 'passport') ->> 'reason');
  IF v_got IS DISTINCT FROM '["expired", "awaiting_review", 1, "true", "awaiting_review"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ID check waiting for review was not expired at 72 hours (or was at 71): %', v_got;
  END IF;
  UPDATE public.dating_verification_sessions SET state = 'expired' WHERE id = v_t; -- (O2 reads the backlog alone)
END $m2$;

-- =====================================================================
-- N. (§3.8, §4.8) Exit: the sessions and their review photos go, and the
--    identity result (it covered the deleted photos); Spec 2 W4 final (I-1a
--    ruling): an age pass goes too (a fail stays: FF1).
-- =====================================================================
DO $n$
DECLARE
  v_u constant uuid := pg_temp.person('30');
  v_s uuid;
BEGIN
  PERFORM public.record_dating_age_assurance(v_u, 'fae', 'pass', 25::smallint, 'fake');
  PERFORM public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', NULL);
  UPDATE public.dating_profiles SET verification_state = 'needs_review' WHERE user_id = v_u;
  v_s := (pg_temp.start(v_u, 'human') ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-verification-review', v_s || '/1.jpg', v_u);
  PERFORM pg_temp.call(v_u, 'SELECT to_jsonb(public.exit_dating_mode(''w4a-exit-000001''))');
  IF EXISTS (SELECT 1 FROM public.dating_verification_sessions WHERE user_id = v_u)
     OR NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = 'dating-verification-review' AND object_name = v_s || '/1.jpg')
     OR (SELECT identity_result FROM public.dating_age_verifications WHERE user_id = v_u) IS NOT NULL
     OR (SELECT age_result FROM public.dating_age_verifications WHERE user_id = v_u) IS NOT NULL THEN -- Spec 2 W4 final (I-1a)
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit kept a session, a review photo, the identity result or the age pass';
  END IF;
END $n$;

-- =====================================================================
-- O. (§1.4) No function reads a date of birth from the verification
--    record; the v1 writers are gone.
-- =====================================================================
DO $o$
DECLARE
  v_got text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_got FROM pg_proc AS p
   WHERE p.prosrc ~ 'dating_age_verifications' AND p.prosrc ~ '(birth_date|verified_by)';
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: functions read v1 verification columns: %', v_got;
  END IF;
  IF to_regprocedure('public.verify_dating_age(uuid,date,text,uuid,timestamptz)') IS NOT NULL
     OR to_regprocedure('public.resolve_dating_verification_review(uuid,text)') IS NOT NULL
     OR to_regprocedure('public.revoke_dating_age_verification(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a v1 age writer is still there';
  END IF;
  -- §4.10 health: the mode and the review backlog are reported.
  IF NOT (public.get_dating_operational_health() ?& ARRAY['age_assurance_mode', 'verification_awaiting_review',
                                                         'verification_oldest_waiting_hours'])
     OR public.get_dating_operational_health() ->> 'age_assurance_mode' IS DISTINCT FROM 'fake' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not report the verification mode and backlog';
  END IF;
END $o$;

-- =====================================================================
-- O2. (Spec 2 W4a fix round 1, M-7, M-8) Health's 24-hour clock starts at
--     the submission, not the session's start; the sweep's failures and
--     the ID reviews it expired are watched.
-- =====================================================================
DO $o2$
DECLARE
  v_u constant uuid := pg_temp.person('47');
  v_s uuid;
  v jsonb;
BEGIN
  UPDATE public.dating_verification_sessions SET state = 'expired' WHERE state = 'awaiting_review'; -- this block's backlog alone
  v_s := (pg_temp.start(v_u, 'human') ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_u), ('dating-verification-review', v_s || '/2.jpg', v_u);
  PERFORM public.submit_dating_human_review(v_u, v_s);
  IF (SELECT awaiting_since FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a submission does not start the wait';
  END IF;
  UPDATE public.dating_verification_sessions SET created_at = now() - interval '50 hours',
         awaiting_since = now() - interval '2 hours 10 minutes' WHERE id = v_s;
  v := public.get_dating_operational_health();
  IF jsonb_build_array(v -> 'verification_awaiting_review', v -> 'verification_oldest_waiting_hours') IS DISTINCT FROM '[1, 2]'::jsonb
     OR NOT (v -> 'safety_counters_7d' ?& ARRAY['dating.verify.sweep_failed', 'dating.verify.id_review_expired']) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health''s review clock or counters are wrong: % / %',
      jsonb_build_array(v -> 'verification_awaiting_review', v -> 'verification_oldest_waiting_hours'), v -> 'safety_counters_7d';
  END IF;
END $o2$;

-- =====================================================================
-- O3. (Spec 2 W4a fix round 1, M-7; §6.9) The verification keys:
--     dating.verify.route.{fae|id|human}, .id_route.age_{band} (declared
--     age), .first_try_pass (the only session, no failed attempt) and
--     .hours_to_decision.{bucket} (from the wait's start); nothing is
--     counted under the old dating.verification. names.
-- =====================================================================
DO $o3$
DECLARE
  v_id constant uuid := pg_temp.person('48');
  v_fae constant uuid := pg_temp.person('49');
  v_hum constant uuid := pg_temp.person('50');
  v_first constant uuid := pg_temp.person('51');
  v_second constant uuid := pg_temp.person('52');
  v_wait constant uuid := pg_temp.person('59');
  v_keys constant text[] := ARRAY['dating.verify.route.id', 'dating.verify.route.fae', 'dating.verify.route.human',
    'dating.verify.id_route.age_25_34', 'dating.verify.first_try_pass', 'dating.verify.hours_to_decision.24_48',
    'dating.verify.hours_to_decision.0_6', 'dating.verify.started'];
  v_before jsonb;
  v_after jsonb;
  v_s uuid;
BEGIN
  SELECT jsonb_object_agg(k, pg_temp.metric(k)) INTO v_before FROM unnest(v_keys) AS k;
  PERFORM public.record_dating_age_assurance(v_id, 'id', 'pass', NULL, 'fake');
  PERFORM public.record_dating_age_assurance(v_fae, 'fae', 'pass', 25::smallint, 'fake');
  v_s := (pg_temp.start(v_hum, 'human') ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_hum), ('dating-verification-review', v_s || '/2.jpg', v_hum);
  PERFORM public.submit_dating_human_review(v_hum, v_s);
  UPDATE public.dating_verification_sessions SET awaiting_since = now() - interval '30 hours' WHERE id = v_s;
  PERFORM public.decide_dating_human_review(v_s, 'pass', pg_temp.id('99'));
  v_s := (pg_temp.start(v_first) ->> 'session_id')::uuid;
  PERFORM public.record_dating_identity_check(v_first, 'liveness_compare', 'pass', 'fake', NULL);
  v_s := (pg_temp.start(v_second) ->> 'session_id')::uuid;
  PERFORM public.set_dating_verification_ref(v_s, 'ref'); -- Spec 2 W4a (T2 fix round 1, M-3)
  PERFORM public.record_dating_liveness_attempt(v_s, false);
  PERFORM public.record_dating_identity_check(v_second, 'liveness_compare', 'pass', 'fake', NULL);
  v_s := (pg_temp.start(v_wait, 'id', 'passport') ->> 'session_id')::uuid;
  PERFORM public.finish_dating_verification_session(v_s, 'awaiting_review', 'id_pending', NULL);
  UPDATE public.dating_verification_sessions SET awaiting_since = now() - interval '5 hours' WHERE id = v_s;
  PERFORM public.finish_dating_verification_session(v_s, 'passed', 'verified', NULL);
  SELECT jsonb_object_agg(k, pg_temp.metric(k) - (v_before ->> k)::bigint) INTO v_after FROM unnest(v_keys) AS k;
  IF v_after IS DISTINCT FROM '{"dating.verify.route.id": 1, "dating.verify.route.fae": 1, "dating.verify.route.human": 1,
      "dating.verify.id_route.age_25_34": 1, "dating.verify.first_try_pass": 1, "dating.verify.hours_to_decision.24_48": 1,
      "dating.verify.hours_to_decision.0_6": 1, "dating.verify.started": 4}'::jsonb
     OR EXISTS (SELECT 1 FROM public.metric_counters WHERE key LIKE 'dating.verification.%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the verification metrics are not §6.9''s: % (old keys: %)', v_after,
      (SELECT string_agg(DISTINCT key, ', ') FROM public.metric_counters WHERE key LIKE 'dating.verification.%');
  END IF;
END $o3$;

-- =====================================================================
-- U. (Spec 2 W4a Task 2 fix round 1, I-3 ruling) The video outcome in one
--    transaction: the service role's alone, SECURITY DEFINER with an empty
--    search path; bad input is 'invalid'; each outcome writes identity, age
--    and the session's end together (R-13: needs_id and uncertain record no
--    age; the ID check opens after them); far below places Spec 1's hold
--    once, with the identity; a replay answers the same and writes nothing
--    more; a refused part rolls every part back (all or nothing); two lock
--    conflicts past the inner writer's own are absorbed, endless ones answer
--    busy and write nothing. M-5: at most 20 vendor sessions an hour per
--    person (a resumed start counts), each refusal counted, nothing ended.
--    M-6 ruling: sandbox is unavailable outside development, as fake is.
-- =====================================================================
DO $u$
DECLARE
  v_sig constant text := 'public.record_dating_video_outcome(uuid,uuid,text,text,smallint,text,text)';
  v_pass constant uuid := pg_temp.person('70');
  v_need constant uuid := pg_temp.person('71');
  v_unsure constant uuid := pg_temp.person('72');
  v_mis constant uuid := pg_temp.person('73');
  v_far constant uuid := pg_temp.person('74');
  v_skip constant uuid := pg_temp.person('75');
  v_bad constant uuid := pg_temp.person('76');
  v_lim constant uuid := pg_temp.person('77');
  v_atom constant uuid := pg_temp.person('78');
  v_busy constant uuid := pg_temp.person('79');
  v_s uuid;
  v_t uuid;
  v_m uuid;
  v jsonb;
  v_at timestamptz;
  v_got jsonb := '[]'::jsonb;
  v_n bigint;
  i int;
BEGIN
  IF has_function_privilege('authenticated', v_sig, 'EXECUTE') OR has_function_privilege('anon', v_sig, 'EXECUTE')
     OR NOT has_function_privilege('service_role', v_sig, 'EXECUTE')
     OR (SELECT p.prosecdef AND p.proconfig @> ARRAY['search_path=""'] FROM pg_proc AS p WHERE p.oid = v_sig::regprocedure) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the video outcome writer is not the service role''s alone, definer, empty search path';
  END IF;
  -- Bad input, another person's session: refused by name, nothing written.
  v_s := (pg_temp.start(v_pass) ->> 'session_id')::uuid;
  v_got := jsonb_build_array(
    public.record_dating_video_outcome(v_pass, v_s, 'maybe', 'pass', NULL, 'fake', 'fake'),
    public.record_dating_video_outcome(v_pass, v_s, 'fail', 'pass', 1::smallint, 'fake', 'fake'),
    public.record_dating_video_outcome(v_pass, v_s, 'fail', NULL, NULL, 'fake', 'fake'),
    public.record_dating_video_outcome(v_pass, v_s, 'fail', NULL, 7::smallint, 'fake', 'fake'),
    public.record_dating_video_outcome(v_pass, v_s, 'pass', 'pass', 1::smallint, 'fake', 'fake'),
    public.record_dating_video_outcome(v_pass, v_s, 'pass', 'fail', NULL, 'fake', 'fake'),
    public.record_dating_video_outcome(v_pass, v_s, 'pass', 'pass', NULL, 'fake', NULL),
    public.record_dating_video_outcome(v_pass, v_s, 'pass', 'pass', NULL, 'Not A Vendor', 'fake'),
    public.record_dating_video_outcome(v_bad, v_s, 'pass', 'pass', NULL, 'fake', 'fake'));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"},
      {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"},
      {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"}, {"ok": false, "reason": "session_unavailable"}]'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE user_id IN (v_pass, v_bad))
     OR (SELECT state FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'started' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the video outcome writer answered % or wrote', v_got;
  END IF;
  -- A pass: identity, the fae pass at 25 and the session, together; a
  -- replay answers the same and writes nothing; another outcome is refused.
  v := public.record_dating_video_outcome(v_pass, v_s, 'pass', 'pass', NULL, 'fake', 'fake');
  SELECT updated_at INTO v_at FROM public.dating_age_verifications WHERE user_id = v_pass;
  IF v IS DISTINCT FROM '{"ok": true, "outcome": "verified", "position": null, "replayed": false}'::jsonb
     OR (SELECT age_method || '/' || age_result || '/' || challenge_age || '/' || identity_method || '/' || identity_result
           FROM public.dating_age_verifications WHERE user_id = v_pass) IS DISTINCT FROM 'fae/pass/25/liveness_compare/pass'
     OR (SELECT state || '/' || outcome FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'passed/verified'
     OR (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_pass) IS DISTINCT FROM 'verified'
     OR public.dating_age_gate_holds(v_pass) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a video pass was not written whole: %', v;
  END IF;
  -- (Every side-effecting call is its own statement: an IF has no order.)
  v_got := jsonb_build_array(public.record_dating_video_outcome(v_pass, v_s, 'pass', 'pass', NULL, 'fake', 'fake'),
                             public.record_dating_video_outcome(v_pass, v_s, 'pass', 'needs_id', NULL, 'fake', 'fake'));
  IF v_got IS DISTINCT FROM '[{"ok": true, "outcome": "verified", "position": null, "replayed": true},
                              {"ok": false, "reason": "session_unavailable"}]'::jsonb
     OR (SELECT updated_at FROM public.dating_age_verifications WHERE user_id = v_pass) IS DISTINCT FROM v_at THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed video outcome wrote again, or a finished session took another';
  END IF;
  -- R-13: below 25 or unsure records identity and no age; the ID check opens.
  v_s := (pg_temp.start(v_need) ->> 'session_id')::uuid;
  v_t := (pg_temp.start(v_unsure) ->> 'session_id')::uuid;
  v_got := jsonb_build_array(public.record_dating_video_outcome(v_need, v_s, 'pass', 'needs_id', NULL, 'fake', 'unconfigured'),
                             public.record_dating_video_outcome(v_unsure, v_t, 'pass', 'uncertain', NULL, 'fake', NULL));
  IF v_got IS DISTINCT FROM '[{"ok": true, "outcome": "needs_id", "position": null, "replayed": false},
                              {"ok": true, "outcome": "age_uncertain", "position": null, "replayed": false}]'::jsonb
     OR (SELECT count(*) FROM public.dating_age_verifications
          WHERE user_id IN (v_need, v_unsure) AND age_result IS NULL AND identity_result = 'pass') <> 2
     OR (SELECT string_agg(state || '/' || outcome, ',' ORDER BY outcome) FROM public.dating_verification_sessions
          WHERE id IN (v_s, v_t)) IS DISTINCT FROM 'passed/age_uncertain,passed/needs_id' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an estimate below 25 or unsure was final or recorded an age: %', v_got;
  END IF;
  v_got := jsonb_build_array(pg_temp.start(v_need, 'id', 'passport') -> 'ok', pg_temp.start(v_unsure, 'id', 'passport') -> 'ok');
  IF v_got IS DISTINCT FROM '[true, true]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ID check did not open after needs_id or age_uncertain: %', v_got;
  END IF;
  -- A photo that doesn't match: identity fail, its slot, no age; fixable.
  v_s := (pg_temp.start(v_mis) ->> 'session_id')::uuid;
  v := public.record_dating_video_outcome(v_mis, v_s, 'fail', NULL, 2::smallint, 'fake', NULL);
  IF v IS DISTINCT FROM '{"ok": true, "outcome": "photo_mismatch", "position": 2, "replayed": false}'::jsonb
     OR (SELECT coalesce(age_result, '-') || '/' || identity_result FROM public.dating_age_verifications WHERE user_id = v_mis)
          IS DISTINCT FROM '-/fail'
     OR (SELECT state || '/' || outcome || '/' || outcome_position FROM public.dating_verification_sessions WHERE id = v_s)
          IS DISTINCT FROM 'failed/photo_mismatch/2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a photo mismatch was not written whole: %', v;
  END IF;
  v := pg_temp.start(v_mis);
  IF v ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a photo mismatch was final: %', v;
  END IF;
  -- Far below 18 (R-8): identity, the age fail and Spec 1's hold, once.
  v_s := (pg_temp.start(v_far) ->> 'session_id')::uuid;
  v_m := pg_temp.match(v_far, v_bad);
  v := public.record_dating_video_outcome(v_far, v_s, 'pass', 'far_below', NULL, 'fake', 'fake');
  IF v IS DISTINCT FROM '{"ok": true, "outcome": "far_below", "position": null, "replayed": false}'::jsonb
     OR (SELECT reason_ref FROM public.account_holds WHERE user_id = v_far AND kind = 'age_review' AND resolved_at IS NULL)
          IS DISTINCT FROM v_s::text
     OR (SELECT age_method || '/' || age_result || '/' || identity_result FROM public.dating_age_verifications WHERE user_id = v_far)
          IS DISTINCT FROM 'fae/fail/pass'
     OR (SELECT state || '/' || outcome FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'failed/far_below'
     OR (SELECT closed_reason FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'age_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: far below 18 was not written whole (the hold, the age fail, the identity)';
  END IF;
  SELECT created_at INTO v_at FROM public.account_holds WHERE user_id = v_far AND kind = 'age_review';
  v := public.record_dating_video_outcome(v_far, v_s, 'pass', 'far_below', NULL, 'fake', 'fake');
  IF v IS DISTINCT FROM '{"ok": true, "outcome": "far_below", "position": null, "replayed": true}'::jsonb
     OR (SELECT count(*) FROM public.account_holds WHERE user_id = v_far) <> 1
     OR (SELECT created_at FROM public.account_holds WHERE user_id = v_far AND kind = 'age_review') IS DISTINCT FROM v_at THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed far-below outcome placed the hold again';
  END IF;
  -- An age already passed: identity only ('skip'); 'skip' without one is refused.
  PERFORM public.record_dating_age_assurance(v_skip, 'id', 'pass', NULL, 'fake');
  v_s := (pg_temp.start(v_skip) ->> 'session_id')::uuid;
  v_t := (pg_temp.start(v_bad) ->> 'session_id')::uuid;
  v_got := jsonb_build_array(public.record_dating_video_outcome(v_skip, v_s, 'pass', 'skip', NULL, 'fake', NULL),
                             public.record_dating_video_outcome(v_bad, v_t, 'pass', 'skip', NULL, 'fake', NULL));
  IF v_got IS DISTINCT FROM '[{"ok": true, "outcome": "verified", "position": null, "replayed": false},
                              {"ok": false, "reason": "session_unavailable"}]'::jsonb
     OR (SELECT age_method || '/' || identity_result FROM public.dating_age_verifications WHERE user_id = v_skip) IS DISTINCT FROM 'id/pass'
     OR EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE user_id = v_bad)
     OR (SELECT state FROM public.dating_verification_sessions WHERE id = v_t) IS DISTINCT FROM 'started' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an age already passed was not kept, or skip ran without one: %', v_got;
  END IF;
  -- All or nothing: the age part refused (a standing failed age check,
  -- R-13) rolls the identity part back; the session stays open.
  v_s := (pg_temp.start(v_atom) ->> 'session_id')::uuid;
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, age_vendor, age_decided_at)
  VALUES (v_atom, 'id', 'fail', 'fake', now());
  v := public.record_dating_video_outcome(v_atom, v_s, 'pass', 'pass', NULL, 'fake', 'fake');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "age_not_confirmed"}'::jsonb
     OR (SELECT coalesce(identity_result, '-') || '/' || age_result FROM public.dating_age_verifications WHERE user_id = v_atom)
          IS DISTINCT FROM '-/fail'
     OR (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_atom) IS NOT DISTINCT FROM 'verified'
     OR (SELECT state FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'started' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused part left the video outcome half written';
  END IF;
  -- Lock conflicts on the session's end: 4 are absorbed (the finish's own
  -- three tries, then this writer's second), endless ones write nothing.
  v_s := (pg_temp.start(v_busy) ->> 'session_id')::uuid;
  v_got := jsonb_build_array(
    pg_temp.probe(pg_temp.conflicts('public.dating_verification_sessions', 4), format('SELECT pg_temp.write_seen(%L, %L, %L)',
      format('SELECT public.record_dating_video_outcome(%L, %L, ''pass'', ''pass'', NULL, ''fake'', ''fake'')::text', v_busy, v_s), v_busy, v_s)),
    pg_temp.probe(pg_temp.conflicts('public.dating_verification_sessions', 1000), format('SELECT pg_temp.write_seen(%L, %L, %L)',
      format('SELECT public.record_dating_video_outcome(%L, %L, ''pass'', ''pass'', NULL, ''fake'', ''fake'')::text', v_busy, v_s), v_busy, v_s)));
  IF v_got IS DISTINCT FROM jsonb_build_array(
      '{"ok": true, "outcome": "verified", "position": null, "replayed": false} / passed/verified/0/- / pass/pass/false / 5',
      '{"ok": false, "reason": "busy"} / started/-/0/- / - / 9') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the video outcome did not absorb lock conflicts, or wrote through endless ones: %', v_got;
  END IF;
  -- M-5: the 21st vendor session in an hour is refused and counted; the
  -- open session is untouched; the human route opens no vendor session.
  -- Fix round 2 (N-2): a vendor session counts once it exists (its
  -- reference set); a start the vendor never answered (an outage's "Try
  -- again") uses nothing: 25 of them, then a start and a reference still
  -- go through. Then 20 references in the hour trip the limit.
  v_n := pg_temp.metric('dating.verify.vendor_session_limited');
  v_s := (pg_temp.start(v_lim) ->> 'session_id')::uuid;
  FOR i IN 2..25 LOOP
    v := pg_temp.start(v_lim);
    IF v ->> 'resumed' IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: start % with no vendor session was refused: %', i, v;
    END IF;
  END LOOP;
  v := pg_temp.start(v_lim);
  v_got := jsonb_build_array(v -> 'ok', public.set_dating_verification_ref(v_s, 'ref-1'));
  IF v_got IS DISTINCT FROM '[true, {"ok": true, "reason": null}]'::jsonb
     OR (SELECT request_count FROM public.dating_rate_limits
          WHERE user_id = v_lim AND operation = 'dating_verify_vendor_session') IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: starts the vendor never answered used the vendor-session limit: % (count %)', v_got,
      (SELECT request_count FROM public.dating_rate_limits WHERE user_id = v_lim AND operation = 'dating_verify_vendor_session');
  END IF;
  FOR i IN 2..20 LOOP
    v := pg_temp.start(v_lim);
    v_got := jsonb_build_array(v -> 'ok', public.set_dating_verification_ref(v_s, 'ref-' || i) -> 'ok');
    IF v_got IS DISTINCT FROM '[true, true]'::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: vendor session % of 20 was refused: %', i, v_got;
    END IF;
  END LOOP;
  v_got := jsonb_build_array(pg_temp.start(v_lim), pg_temp.start(v_lim, 'id', 'passport'));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "rate_limited"}, {"ok": false, "reason": "rate_limited"}]'::jsonb
     OR pg_temp.metric('dating.verify.vendor_session_limited') - v_n <> 2
     OR (SELECT state FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'started' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 21st vendor session in an hour was opened, uncounted, or ended the open one: %', v_got;
  END IF;
  v := pg_temp.start(v_lim, 'human');
  IF v ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the human route was refused by the vendor-session limit: %', v;
  END IF;
  UPDATE public.dating_rate_limits SET window_started_at = now() - interval '61 minutes'
   WHERE user_id = v_lim AND operation = 'dating_verify_vendor_session';
  v := pg_temp.start(v_lim);
  IF v ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the vendor-session limit did not reset after an hour';
  END IF;
  v := public.set_dating_verification_ref((v ->> 'session_id')::uuid, 'ref-new-hour');
  IF v ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT request_count FROM public.dating_rate_limits
          WHERE user_id = v_lim AND operation = 'dating_verify_vendor_session') IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a vendor session after the hour did not start a new window: %', v;
  END IF;
  -- M-6 ruling: sandbox only in development (production refuses it, as fake).
  PERFORM set_config('app.settings.age_assurance_mode', 'sandbox', true);
  v_got := jsonb_build_array(public.get_dating_verification_config() -> 'available');
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  v_got := v_got || jsonb_build_array(public.get_dating_verification_config() -> 'available', pg_temp.start(v_bad, 'id', 'passport'));
  PERFORM set_config('app.settings.age_assurance_mode', 'live', true);
  v_got := v_got || jsonb_build_array(public.get_dating_verification_config() -> 'available');
  PERFORM set_config('app.settings.attune_environment', '', true);
  PERFORM set_config('app.settings.age_assurance_mode', 'fake', true);
  IF v_got IS DISTINCT FROM '[true, false, {"ok": false, "reason": "unavailable"}, true]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: sandbox ran in production, or live / development sandbox were refused: %', v_got;
  END IF;
END $u$;

-- =====================================================================
-- P. (§4.9 dev switch-on, I-15) The dev script turns dating_age_assurance
--    on and, with no mode set on a local database, sets 'fake'.
-- =====================================================================
DO $p$
BEGIN
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_age_assurance';
  PERFORM set_config('app.settings.age_assurance_mode', '', true);
END $p$;
\i supabase/sql/dev_enable_spec2_dating_flags.sql
DO $p2$
BEGIN
  IF public.dating_flag_enabled('dating_age_assurance') IS NOT TRUE
     OR private.dating_verification_mode() IS DISTINCT FROM 'fake' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev script left dating_age_assurance % and the mode %',
      public.dating_flag_enabled('dating_age_assurance'), private.dating_verification_mode();
  END IF;
END $p2$;
-- Spec 2 W9 (R-W9-16): the dev script also turns dating_couple_link on,
-- and every home answer then carries couple_link; this file's exact home
-- answers are W4's, so the couple link is off again here (rolled back).
UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_couple_link';

-- =====================================================================
-- W4b (Task 5). The device helpers: [p] calls [p_sql] from the device
-- [p_device] (32 hex characters; NULL: no header).
-- =====================================================================
CREATE FUNCTION pg_temp.call_on(p uuid, p_device text, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM set_config('request.headers',
    CASE WHEN p_device IS NULL THEN '{}' ELSE json_build_object('x-attune-device', p_device)::text END, true);
  v := pg_temp.call(p, p_sql);
  PERFORM set_config('request.headers', '', true);
  RETURN v;
END $$;
CREATE FUNCTION pg_temp.err_on(p uuid, p_device text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM set_config('request.headers',
    CASE WHEN p_device IS NULL THEN '{}' ELSE json_build_object('x-attune-device', p_device)::text END, true);
  v := pg_temp.err(p, p_sql);
  PERFORM set_config('request.headers', '', true);
  RETURN v;
END $$;
-- The check itself, for [p] on [p_device] (no client may call it: as the
-- database, with the request's claims and headers set).
CREATE FUNCTION pg_temp.guard_on(p uuid, p_device text) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE
  v boolean;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.headers', json_build_object('x-attune-device', p_device)::text, true);
  v := public.dating_require_trusted_device();
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.headers', '', true);
  RETURN v;
END $$;
-- [p_who]'s setup eligibility, asked in [p]'s request from [p_device].
CREATE FUNCTION pg_temp.elig_on(p uuid, p_device text, p_who uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.headers', json_build_object('x-attune-device', p_device)::text, true);
  v := public.dating_eligibility(p_who, 'setup');
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.headers', '', true);
  RETURN v;
END $$;
CREATE FUNCTION pg_temp.dev(p_c text) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT repeat(p_c, 32) $$;
CREATE FUNCTION pg_temp.dev_hash(p_c text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT encode(extensions.digest(repeat(p_c, 32), 'sha256'), 'hex');
$$;

-- =====================================================================
-- V. (carry 11, R-20; W1 B8) Every exposure-reducing write works from an
--    untrusted device under the real check (Q has the four that answer
--    jsonb: the notice, the reflection, a photo, the faith): pause, Leave,
--    a consent withdrawal and adding a number to 'Never introduce me'.
--    Removing a number re-exposes the person to it, so remove keeps the
--    check (W1 B8). Runs before Q, so a raising writer that gains the
--    check dies here with its own line.
-- =====================================================================
DO $v$
DECLARE
  v_p constant uuid := pg_temp.person('66');
  v_x constant uuid := pg_temp.person('67');
  v_w constant uuid := pg_temp.person('68');
  v_n constant uuid := pg_temp.person('69');
  v_id uuid;
  v_got jsonb;
BEGIN
  PERFORM pg_temp.trust(u, pg_temp.dev_hash('a')) FROM unnest(ARRAY[v_p, v_x, v_w, v_n]) AS u;
  UPDATE public.dating_enrollments SET state = 'active', activated_at = now() WHERE user_id IN (v_p, v_x, v_w);
  IF pg_temp.guard_on(v_p, pg_temp.dev('b')) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the check trusts a device never bound, or answers NULL';
  END IF;
  v_got := jsonb_build_array(
    pg_temp.err_on(v_p, pg_temp.dev('b'), 'SELECT public.pause_dating_mode(''w4b-v-pause-0001'')'),
    pg_temp.err_on(v_x, pg_temp.dev('b'), 'SELECT public.exit_dating_mode(''w4b-v-exit-00001'', false)'),
    pg_temp.err_on(v_w, pg_temp.dev('b'),
      'SELECT public.record_dating_consent(''w4b-v-withdraw-1'', ''dating_terms'', ''withdrawn'', ''dating-2.0'', ''[]'')'),
    pg_temp.call_on(v_n, pg_temp.dev('b'),
      'SELECT public.add_dating_never_introduce(''w4b-v-never-0001'', ''+447700900612'', ''Ex'')'));
  IF v_got IS DISTINCT FROM '["ok", "ok", "ok", {"ok": true, "message": "added"}]'::jsonb
     OR (SELECT string_agg(state, '/' ORDER BY user_id) FROM public.dating_enrollments WHERE user_id IN (v_p, v_x, v_w))
        IS DISTINCT FROM (SELECT string_agg(s, '/' ORDER BY u) FROM (VALUES (v_p, 'paused'), (v_x, 'exited'), (v_w, 'exited')) AS t(u, s)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an exposure-reducing write was refused on another device: %', v_got;
  END IF;
  v_id := (SELECT id FROM public.dating_never_introduce WHERE owner_user_id = v_n);
  IF pg_temp.call_on(v_n, pg_temp.dev('b'), format('SELECT public.remove_dating_never_introduce(%L)', v_id))
       IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE id = v_id) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another device took a number off Never introduce me (it re-exposes the person)';
  END IF;
END $v$;

-- =====================================================================
-- Q. (§3.3.4, R-16, §7.1, mutant 9; carries 6, 11) Unbound, any device
--    reads; the first setup write binds its device; any other device then
--    reads reverify_device and no data, writes nothing, and the setup
--    starts again there; exposure-reducing writes never ask; leaving
--    unbinds, and the next device's first write binds it.
-- =====================================================================
DO $q$
DECLARE
  v_u constant uuid := pg_temp.person('61');
  v_photo uuid;
  v_got jsonb;
  v text;
BEGIN
  IF pg_temp.call_on(v_u, NULL, 'SELECT public.get_my_dating_profile()') ->> 'ok' IS DISTINCT FROM 'true'
     OR pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_my_dating_profile()') ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unbound person could not read from a device';
  END IF;
  -- D2's write from A binds A, for the setup (no verification yet).
  v_got := pg_temp.call_on(v_u, pg_temp.dev('a'),
    'SELECT public.save_dating_children(''w4b-q-children-01'', false, ''yes'', false, false)');
  IF v_got ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT count(*) FROM public.dating_trusted_devices WHERE user_id = v_u) <> 1
     OR (SELECT verified_at FROM public.dating_trusted_devices WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('a')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first setup write did not bind its device for the setup: %', v_got;
  END IF;
  -- From B (and with no header): reverify_device, no data, no write.
  v_got := jsonb_build_array(
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_my_dating_profile()'),
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_dating_setup_lists()'),
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.list_dating_profile_photos()'),
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.save_dating_children(''w4b-q-children-02'', true, ''no'', false, false)'),
    pg_temp.call_on(v_u, NULL, 'SELECT public.get_my_dating_profile()'),
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_dating_home()') - 'has_data');
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "reverify_device"}, {"ok": false, "reason": "reverify_device"},
      {"ok": false, "reason": "reverify_device"}, {"ok": false, "reason": "reverify_device"},
      {"ok": false, "reason": "reverify_device"}, {"state": "reverify_device", "variant": "setup_restart"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another device read or wrote: %', v_got;
  END IF;
  IF (SELECT children_have FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another device''s write landed';
  END IF;
  v := jsonb_build_array(
    pg_temp.err_on(v_u, pg_temp.dev('b'), 'SELECT public.activate_dating_profile(''w4b-q-activate-1'')'),
    pg_temp.err_on(v_u, pg_temp.dev('b'), 'SELECT public.begin_dating_enrollment(''2'', ''w4b-q-begin-0001'')'),
    pg_temp.err_on(v_u, pg_temp.dev('b'),
      'SELECT public.record_dating_consent(''w4b-q-consent-1'', ''dating_terms'', ''granted'', ''dating-2.0'', ''[]'')'))::text;
  IF v IS DISTINCT FROM '["22023:reverify_device", "22023:reverify_device", "22023:reverify_device"]' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a raising writer let another device through (a NULL check?): %', v;
  END IF;
  -- A still works; the check never answers NULL.
  IF pg_temp.call_on(v_u, pg_temp.dev('a'), 'SELECT public.get_my_dating_profile()') ->> 'ok' IS DISTINCT FROM 'true'
     OR pg_temp.guard_on(v_u, pg_temp.dev('b')) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the bound device was refused, or the check answered NULL';
  END IF;
  -- Carry 11: exposure-reducing writes from B (never gated).
  SELECT id INTO v_photo FROM public.dating_profile_photos WHERE user_id = v_u AND position = 2;
  INSERT INTO public.dating_notify_requests (user_id, country_code) VALUES (v_u, 'NG');
  INSERT INTO public.dating_gentle_wait_reflections (user_id, answers, saved_at) VALUES (v_u, '{"q1": "a note"}', now());
  v_got := jsonb_build_array(
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.cancel_dating_country_notice()') ->> 'ok',
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.save_gentle_wait_reflection(''{}'')') ->> 'ok',
    pg_temp.call_on(v_u, pg_temp.dev('b'), format('SELECT public.delete_dating_profile_photo(%L)', v_photo)) ->> 'ok',
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.clear_dating_faith(''w4b-q-faith-0001'')') ->> 'ok');
  IF v_got IS DISTINCT FROM '["true", "true", "true", "true"]'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE id = v_photo)
     OR EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an exposure-reducing write was refused on another device: %', v_got;
  END IF;
  -- Leaving from B (setup_restart's Start again): every device unbound;
  -- B's next setup write binds B. R-32 (owner ruling 2026-11-09): Start
  -- again keeps the 'Never introduce me' list, as exit does when its box is
  -- ticked; a later Leave can still delete it.
  INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two) VALUES (v_u, pg_temp.dev_hash('e'), '07');
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT to_jsonb(public.exit_dating_mode(''w4b-q-exit-00001'', true))');
  IF EXISTS (SELECT 1 FROM public.dating_trusted_devices WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: leaving kept a trusted device';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Start again on a new phone lost the never-introduce list';
  END IF;
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_u, 'Verify', 'GB', 'TLI')
  ON CONFLICT (user_id) DO NOTHING;
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'),
    'SELECT public.save_dating_children(''w4b-q-children-03'', false, ''open'', false, false)');
  IF (SELECT array_agg(device_hash) FROM public.dating_trusted_devices WHERE user_id = v_u) IS DISTINCT FROM ARRAY[pg_temp.dev_hash('b')] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after leaving, the next device''s first write did not bind it';
  END IF;
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT to_jsonb(public.exit_dating_mode(''w4b-q-exit-00002'', false))');
  IF EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a later Leave could not delete the kept list';
  END IF;
END $q$;

-- =====================================================================
-- R. (§3.3.4) After a passed check: another device needs a video check
--    ('verified'); up to 3 trusted devices (the least recently used goes);
--    one unused for 180 days no longer counts; seen again at most once a
--    day.
-- =====================================================================
DO $r$
DECLARE
  v_u constant uuid := pg_temp.person('62');
  v_seen timestamptz;
BEGIN
  IF public.trust_dating_device(v_u, 'nothex', gen_random_uuid()) IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb
     OR has_function_privilege('authenticated', 'public.trust_dating_device(uuid,text,uuid)', 'EXECUTE') -- Spec 2 W4 final (M-3)
     OR NOT has_function_privilege('service_role', 'public.trust_dating_device(uuid,text,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: trust_dating_device takes bad input or is a client''s';
  END IF;
  PERFORM pg_temp.trust(v_u, pg_temp.dev_hash('a'));
  UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval '3 days' WHERE user_id = v_u;
  IF pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_dating_home()') ->> 'variant' IS DISTINCT FROM 'verified' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a verified person''s new device is not asked for a video check';
  END IF;
  PERFORM pg_temp.trust(v_u, pg_temp.dev_hash(c)) FROM unnest(ARRAY['b', 'c', 'd']) AS c;
  IF (SELECT array_agg(device_hash ORDER BY device_hash) FROM public.dating_trusted_devices WHERE user_id = v_u)
       IS DISTINCT FROM (SELECT array_agg(pg_temp.dev_hash(c) ORDER BY pg_temp.dev_hash(c)) FROM unnest(ARRAY['b', 'c', 'd']) AS c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: more than 3 devices, or not the least recently used one dropped';
  END IF;
  -- Seen again: once a day at most.
  UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval '2 days' WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('b');
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_my_dating_profile()');
  SELECT last_seen_at INTO v_seen FROM public.dating_trusted_devices WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('b');
  UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval '2 hours' WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('b');
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_my_dating_profile()');
  IF v_seen < now() - interval '1 minute'
     OR (SELECT last_seen_at FROM public.dating_trusted_devices WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('b'))
          > now() - interval '1 hour' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a trusted device''s last use is not kept once a day';
  END IF;
  -- Unused for 180 days: no longer trusted.
  UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval '181 days' WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('c');
  IF pg_temp.call_on(v_u, pg_temp.dev('c'), 'SELECT public.get_my_dating_profile()') ->> 'reason' IS DISTINCT FROM 'reverify_device' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a device unused for 180 days is still trusted';
  END IF;
END $r$;

-- =====================================================================
-- S. (§2.1 gate 8, R-17) The person's own request from an untrusted
--    device fails gate 8; nobody else's check (a cron, another person's
--    request) reads a device.
-- =====================================================================
DO $s$
DECLARE
  v_u constant uuid := pg_temp.person('63');
  v_x constant uuid := pg_temp.person('64');
BEGIN
  PERFORM pg_temp.trust(v_u, pg_temp.dev_hash('a'));
  IF pg_temp.elig_on(v_u, pg_temp.dev('b'), v_u) IS DISTINCT FROM 'reverify_device'
     OR pg_temp.elig_on(v_u, pg_temp.dev('a'), v_u) IS DISTINCT FROM 'eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: gate 8 does not read the caller''s own device';
  END IF;
  IF public.dating_eligibility(v_u, 'setup') IS DISTINCT FROM 'eligible'
     OR pg_temp.elig_on(v_x, pg_temp.dev('b'), v_u) IS DISTINCT FROM 'eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: gate 8 read a device for someone else''s check';
  END IF;
END $s$;

-- =====================================================================
-- T. (§3.3.4) The re-check: only on an untrusted device, only after a
--    passed identity check, never without the device or through an ID; the
--    first check never on an untrusted device; a person's pass on a
--    re-check trusts the device it ran on.
-- =====================================================================
DO $t$
DECLARE
  v_u constant uuid := pg_temp.person('65');
  v_got jsonb;
  v_s uuid;
BEGIN
  -- Spec 2 W4b (T5 fix round 1, I-4): A is bound for the setup only, so
  -- no phone of this person has passed a check yet.
  INSERT INTO public.dating_trusted_devices (user_id, device_hash) VALUES (v_u, pg_temp.dev_hash('a'));
  v_got := jsonb_build_array(
    public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', NULL, NULL),
    public.begin_dating_verification(v_u, 'reverify', 'id', 'fake', pg_temp.dev_hash('b'), 'passport'),
    public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('a'), NULL),
    public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('b'), NULL),
    public.begin_dating_verification(v_u, 'activation', 'liveness', 'fake', pg_temp.dev_hash('b'), NULL));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"}, {"ok": false, "reason": "invalid"},
      {"ok": false, "reason": "already_verified"}, {"ok": false, "reason": "not_eligible"},
      {"ok": false, "reason": "reverify_device"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the re-check began wrongly: %', v_got;
  END IF;
  PERFORM public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', NULL);
  v_s := (public.begin_dating_verification(v_u, 'reverify', 'human', 'attune', pg_temp.dev_hash('b'), NULL) ->> 'session_id')::uuid;
  IF v_s IS NULL OR (SELECT kind || '/' || device_hash FROM public.dating_verification_sessions WHERE id = v_s)
                       IS DISTINCT FROM 'reverify/' || pg_temp.dev_hash('b') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the re-check session is not for this device';
  END IF;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_u), ('dating-verification-review', v_s || '/2.jpg', v_u);
  PERFORM public.submit_dating_human_review(v_u, v_s);
  -- The untrusted device reads only its own re-check.
  IF pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_my_dating_verification()') #>> '{session,id}' IS DISTINCT FROM v_s::text
     OR pg_temp.call_on(v_u, pg_temp.dev('c'), 'SELECT public.get_my_dating_verification()') -> 'session' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a device read a re-check that is not its own';
  END IF;
  PERFORM public.decide_dating_human_review(v_s, 'pass', pg_temp.id('99'));
  IF pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_my_dating_profile()') ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT verified_at FROM public.dating_trusted_devices WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('b')) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person''s pass on a re-check did not trust the device';
  END IF;
  -- A stranger's failed re-check on yet another phone never unverifies
  -- the owner (the account's own result is not the re-check's to write).
  v_s := (public.begin_dating_verification(v_u, 'reverify', 'human', 'attune', pg_temp.dev_hash('c'), NULL) ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_u), ('dating-verification-review', v_s || '/2.jpg', v_u);
  PERFORM public.submit_dating_human_review(v_u, v_s);
  PERFORM public.decide_dating_human_review(v_s, 'fail', pg_temp.id('99'));
  IF (SELECT identity_result FROM public.dating_age_verifications WHERE user_id = v_u) IS DISTINCT FROM 'pass'
     OR (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM 'verified'
     OR EXISTS (SELECT 1 FROM public.dating_trusted_devices WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('c')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed re-check changed the owner''s result or trusted the phone';
  END IF;
END $t$;

-- =====================================================================
-- X. (R-14; beyond the plan) One open session per person (the open
--    index): a re-check never resumes the owner's own check (its result
--    is the owner's) nor ends it, nor another phone's re-check; its own
--    phone's re-check resumes, or moves on to the person route; the
--    owner's trusted phone still starts its own check.
-- =====================================================================
DO $x$
DECLARE
  v_u constant uuid := pg_temp.person('86');
  v_act uuid;
  v_s uuid;
  v_h uuid;
  v_got jsonb;
BEGIN
  PERFORM pg_temp.trust(v_u, pg_temp.dev_hash('a'));
  PERFORM public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', NULL);
  -- The owner's own check (the age is still to come) is open on A.
  v_act := (public.begin_dating_verification(v_u, 'activation', 'liveness', 'fake', pg_temp.dev_hash('a'), NULL) ->> 'session_id')::uuid;
  v_got := jsonb_build_array(
    public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('b'), NULL),
    public.begin_dating_verification(v_u, 'reverify', 'human', 'attune', pg_temp.dev_hash('b'), NULL));
  IF v_act IS NULL OR v_got IS DISTINCT FROM '[{"ok": false, "reason": "session_elsewhere"}, {"ok": false, "reason": "session_elsewhere"}]'::jsonb -- Spec 2 W4 final (M-4)
     OR (SELECT kind || '/' || state || '/' || device_hash FROM public.dating_verification_sessions WHERE id = v_act)
          IS DISTINCT FROM 'activation/started/' || pg_temp.dev_hash('a') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-check took over or ended the owner''s own check: %', v_got;
  END IF;
  -- The owner's check waiting for review: a re-check learns nothing of it.
  UPDATE public.dating_verification_sessions SET state = 'awaiting_review', awaiting_since = now() WHERE id = v_act;
  v_got := public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('b'), NULL);
  IF v_got IS DISTINCT FROM '{"ok": false, "reason": "session_elsewhere"}'::jsonb THEN -- Spec 2 W4 final (M-4)
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-check was told of the owner''s own check: %', v_got;
  END IF;
  -- B's re-check: C can't end it; B resumes it.
  UPDATE public.dating_verification_sessions SET state = 'expired', expires_at = now() - interval '1 minute' WHERE id = v_act;
  v_s := (public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('b'), NULL) ->> 'session_id')::uuid;
  v_got := public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('c'), NULL);
  IF v_s IS NULL OR v_got IS DISTINCT FROM '{"ok": false, "reason": "session_elsewhere"}'::jsonb -- Spec 2 W4 final (M-4)
     OR (public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('b'), NULL) ->> 'session_id')::uuid
          IS DISTINCT FROM v_s
     OR (SELECT state FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'started' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another phone ended a re-check, or its own phone could not resume it: %', v_got;
  END IF;
  -- B moves on to the person route ("check another way").
  v_h := (public.begin_dating_verification(v_u, 'reverify', 'human', 'attune', pg_temp.dev_hash('b'), NULL) ->> 'session_id')::uuid;
  IF v_h IS NULL OR (SELECT state FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'expired' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-check could not move on to the person route on its own phone';
  END IF;
  -- The owner's trusted phone starts its own check; the re-check ends.
  v_got := public.begin_dating_verification(v_u, 'activation', 'liveness', 'fake', pg_temp.dev_hash('a'), NULL);
  IF v_got ->> 'resumed' IS DISTINCT FROM 'false'
     OR (SELECT kind FROM public.dating_verification_sessions WHERE id = (v_got ->> 'session_id')::uuid) IS DISTINCT FROM 'activation'
     OR (SELECT state FROM public.dating_verification_sessions WHERE id = v_h) IS DISTINCT FROM 'expired' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner''s check resumed a re-check, or the re-check stayed open: %', v_got;
  END IF;
END $x$;

-- =====================================================================
-- W. (Task 3 review M-4) A verification pause says where its check
--    stands, as a fixed code: needed, final (a failed ID), waiting (a new
--    check waiting for review), held (the check passed; an open shared
--    space still pauses it). No other pause carries it.
-- =====================================================================
DO $w$
DECLARE
  v_a constant uuid := pg_temp.person('80');
  v_b constant uuid := pg_temp.person('81');
  v_c constant uuid := pg_temp.person('82');
  v_d constant uuid := pg_temp.person('83');
  v_e constant uuid := pg_temp.person('84');
  v_partner constant uuid := pg_temp.person('85');
  v_got jsonb;
BEGIN
  PERFORM public.record_dating_age_assurance(u, 'fae', 'pass', 25::smallint, 'fake') FROM unnest(ARRAY[v_a, v_b, v_c, v_d]) AS u;
  UPDATE public.dating_enrollments SET state = 'paused', activated_at = now(), paused_at = now(), pause_reason = 'user'
   WHERE user_id IN (v_a, v_b, v_c, v_e);
  PERFORM public.revoke_dating_age_verification(v_a, 'contract');
  PERFORM public.record_dating_age_assurance(v_b, 'id', 'fail', NULL, 'fake');
  PERFORM public.revoke_dating_age_verification(v_c, 'contract');
  INSERT INTO public.dating_verification_sessions (user_id, kind, step, vendor, state, outcome, gestures, expires_at, awaiting_since)
  VALUES (v_c, 'activation', 'human', 'attune', 'awaiting_review', 'human_pending', ARRAY['thumbs_up', 'left_ear'],
          now() + interval '72 hours', now());
  INSERT INTO public.relationships (user_a, user_b, status, started_at) VALUES (v_d, v_partner, 'active', current_date);
  UPDATE public.dating_enrollments SET state = 'paused', activated_at = now(), paused_at = now(), pause_reason = 'verification'
   WHERE user_id = v_d;
  v_got := jsonb_build_array(
    pg_temp.call(v_a, 'SELECT public.get_dating_home()') - 'has_data',
    pg_temp.call(v_b, 'SELECT public.get_dating_home()') - 'has_data',
    pg_temp.call(v_c, 'SELECT public.get_dating_home()') - 'has_data',
    pg_temp.call(v_d, 'SELECT public.get_dating_home()') - 'has_data',
    pg_temp.call(v_e, 'SELECT public.get_dating_home()') - 'has_data');
  IF v_got IS DISTINCT FROM '[{"state": "paused", "pause_reason": "verification", "can_resume": false, "check": "needed"},
      {"state": "paused", "pause_reason": "verification", "can_resume": false, "check": "final"},
      {"state": "paused", "pause_reason": "verification", "can_resume": false, "check": "waiting"},
      {"state": "paused", "pause_reason": "verification", "can_resume": false, "check": "held"},
      {"state": "paused", "pause_reason": "user", "can_resume": true}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a verification pause does not say where its check stands: %', v_got;
  END IF;
END $w$;

-- =====================================================================
-- Y1. (T5 fix rounds 1-2, C-1 and I-6 rulings) Rows kept by Start again
--     (or a Leave that keeps the list) are never shown again and never
--     removed one at a time, on any phone, even one that passes its own
--     check; they still keep the pair from being introduced; the list
--     shows only their number; a later Leave deletes them. Adding a kept
--     number looks exactly like adding a fresh one ("Added.", a visible row
--     with the new label, the count unchanged, the same order, the same
--     limit), and removing it hides it again with the protection kept.
-- =====================================================================
DO $y1$
DECLARE
  v_u constant uuid := pg_temp.person('87');
  v_x constant uuid := pg_temp.person('96');
  v_kept uuid;
  v_ids uuid[];
  v_got_ids uuid[];
  v_got jsonb;
BEGIN
  -- A binds and lists v_x's number (+1 555 870 796, ending 96).
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('a'),
    'SELECT public.save_dating_children(''w4b-y1-child-001'', false, ''yes'', false, false)');
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('a'),
    'SELECT public.add_dating_never_introduce(''w4b-y1-never-001'', ''+1555870796'', ''Ex'')');
  v_kept := (SELECT id FROM public.dating_never_introduce WHERE owner_user_id = v_u);
  UPDATE public.dating_never_introduce SET created_at = now() - interval '30 days' WHERE id = v_kept;
  IF v_kept IS NULL OR public.dating_never_introduce_excludes(v_u, v_x) IS NOT TRUE THEN
    RAISE EXCEPTION 'fixture: the listed number does not exclude';
  END IF;
  -- B: setup_restart's Start again keeps the list (R-32), its label gone.
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT to_jsonb(public.exit_dating_mode(''w4b-y1-exit-0001'', true))');
  IF (SELECT kept_at IS NOT NULL AND label IS NULL FROM public.dating_never_introduce WHERE id = v_kept) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Start again did not keep the row, or kept its label';
  END IF;
  v_got := jsonb_build_array(
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.list_dating_never_introduce()'),
    pg_temp.call_on(v_u, pg_temp.dev('c'), 'SELECT public.list_dating_never_introduce()'),
    pg_temp.call_on(v_u, NULL, 'SELECT public.list_dating_never_introduce()'),
    pg_temp.call_on(v_u, pg_temp.dev('b'), format('SELECT public.remove_dating_never_introduce(%L)', v_kept)));
  IF v_got IS DISTINCT FROM '[{"ok": true, "items": [], "kept_count": 1}, {"ok": true, "items": [], "kept_count": 1},
      {"ok": true, "items": [], "kept_count": 1}, {"ok": true}]'::jsonb
     OR (SELECT kept_at IS NOT NULL AND label IS NULL FROM public.dating_never_introduce WHERE id = v_kept) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after Start again a phone saw or removed the kept list, or its label stayed: %', v_got;
  END IF;
  -- B sets up as itself and passes its own check: still the count only.
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_u, 'Verify', 'GB', 'TLI')
  ON CONFLICT (user_id) DO NOTHING;
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'),
    'SELECT public.save_dating_children(''w4b-y1-child-002'', false, ''yes'', false, false)');
  PERFORM pg_temp.trust(v_u, pg_temp.dev_hash('b'));
  v_got := jsonb_build_array(
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.list_dating_never_introduce()'),
    pg_temp.call_on(v_u, pg_temp.dev('b'), format('SELECT public.remove_dating_never_introduce(%L)', v_kept)));
  IF v_got IS DISTINCT FROM '[{"ok": true, "items": [], "kept_count": 1}, {"ok": true}]'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE id = v_kept AND kept_at IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restarting phone''s own check showed or removed the kept list: %', v_got;
  END IF;
  -- I-6: a fresh number (an earlier call), then the kept one: the same
  -- answers, a visible row each, in the order added, the count unchanged.
  v_got := jsonb_build_array(
    pg_temp.call_on(v_u, pg_temp.dev('b'),
      'SELECT public.add_dating_never_introduce(''w4b-y1-never-002'', ''+447700900614'', ''New'')'),
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.list_dating_never_introduce()') -> 'kept_count');
  UPDATE public.dating_never_introduce SET created_at = now() - interval '1 minute' -- T5 fix round 3: the earlier call
   WHERE owner_user_id = v_u AND kept_at IS NULL;
  v_got := v_got || jsonb_build_array(
    pg_temp.call_on(v_u, pg_temp.dev('b'),
      'SELECT public.add_dating_never_introduce(''w4b-y1-never-003'', ''+1555870796'', ''Again'')'),
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.list_dating_never_introduce()') #- '{items,0,id}' #- '{items,1,id}');
  IF v_got IS DISTINCT FROM '[{"ok": true, "message": "added"}, 1, {"ok": true, "message": "added"},
      {"ok": true, "items": [{"label": "New", "last_two": "14"}, {"label": "Again", "last_two": "96"}], "kept_count": 1}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: adding a kept number looked different from adding a fresh one: %', v_got;
  END IF;
  -- I-7 (T5 fix round 3): the re-added row is placed by the clock a fresh
  -- add uses (the transaction's), so overlapping calls order alike.
  IF (SELECT shown_at FROM public.dating_never_introduce WHERE owner_user_id = v_u AND kept_at IS NOT NULL) IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-added kept number is ordered by another clock than a fresh add';
  END IF;
  -- Removing both: the same answers; the kept one hides again, still protecting.
  SELECT array_agg((e ->> 'id')::uuid) INTO v_ids
    FROM jsonb_array_elements(pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.list_dating_never_introduce()') -> 'items') AS e;
  v_got := jsonb_build_array(
    pg_temp.call_on(v_u, pg_temp.dev('b'), format('SELECT public.remove_dating_never_introduce(%L)', v_ids[1])),
    pg_temp.call_on(v_u, pg_temp.dev('b'), format('SELECT public.remove_dating_never_introduce(%L)', v_ids[2])),
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.list_dating_never_introduce()'));
  IF v_got IS DISTINCT FROM '[{"ok": true}, {"ok": true}, {"ok": true, "items": [], "kept_count": 1}]'::jsonb
     OR public.dating_never_introduce_excludes(v_u, v_x) IS NOT TRUE
     OR (SELECT label IS NULL AND shown_at IS NULL FROM public.dating_never_introduce WHERE owner_user_id = v_u AND kept_at IS NOT NULL) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: removing a re-added kept number looked different, or lost its protection: %', v_got;
  END IF;
  -- I-8 (T5 fix round 3): added again, each comes back under a new id.
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'),
    'SELECT public.add_dating_never_introduce(''w4b-y1-never-006'', ''+447700900614'', ''New'')');
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'),
    'SELECT public.add_dating_never_introduce(''w4b-y1-never-007'', ''+1555870796'', ''Again'')');
  SELECT array_agg((e ->> 'id')::uuid) INTO v_got_ids
    FROM jsonb_array_elements(pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.list_dating_never_introduce()') -> 'items') AS e;
  IF coalesce(array_length(v_got_ids, 1), 0) <> 2 OR v_got_ids && v_ids OR v_got_ids && ARRAY[v_kept] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a number added again came back under its old id: % then %', v_ids, v_got_ids;
  END IF;
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('b'), format('SELECT public.remove_dating_never_introduce(%L)', i))
     FROM unnest(v_got_ids) AS i;
  -- At the 50-row limit, a kept number is refused like a fresh one.
  INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two)
  SELECT v_u, encode(extensions.digest('w4b-y1-fill-' || n, 'sha256'), 'hex'), lpad(n::text, 2, '0') FROM generate_series(1, 49) AS n;
  v_got := jsonb_build_array(
    pg_temp.call_on(v_u, pg_temp.dev('b'),
      'SELECT public.add_dating_never_introduce(''w4b-y1-never-004'', ''+447700900615'', NULL)'),
    pg_temp.call_on(v_u, pg_temp.dev('b'),
      'SELECT public.add_dating_never_introduce(''w4b-y1-never-005'', ''+1555870796'', NULL)'));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "limit_reached"}, {"ok": false, "reason": "limit_reached"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: at the limit a kept number answered differently from a fresh one: %', v_got;
  END IF;
  -- A later Leave, from yet another phone, deletes everything.
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('d'), 'SELECT to_jsonb(public.exit_dating_mode(''w4b-y1-exit-0003'', false))');
  IF EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a later Leave did not delete the kept list';
  END IF;
END $y1$;

-- =====================================================================
-- Y2. (T5 fix round 1, I-1 ruling) A re-check has no ID route: a
--     reviewer's ask_for_id on one is refused and changes nothing.
-- =====================================================================
DO $y2$
DECLARE
  v_u constant uuid := pg_temp.person('88');
  v_s uuid;
BEGIN
  PERFORM pg_temp.trust(v_u, pg_temp.dev_hash('a'));
  PERFORM public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', NULL);
  UPDATE public.dating_profiles SET verification_state = 'needs_review' WHERE user_id = v_u;
  v_s := (public.begin_dating_verification(v_u, 'reverify', 'human', 'attune', pg_temp.dev_hash('b'), NULL) ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_u), ('dating-verification-review', v_s || '/2.jpg', v_u);
  PERFORM public.submit_dating_human_review(v_u, v_s);
  IF public.decide_dating_human_review(v_s, 'ask_for_id', pg_temp.id('99')) IS DISTINCT FROM '{"ok": false, "reason": "session_unavailable"}'::jsonb
     OR (SELECT state FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'awaiting_review'
     OR (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM 'needs_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ask_for_id was taken on a re-check';
  END IF;
END $y2$;

-- =====================================================================
-- Y3. (T5 fix round 1, I-2) The owner's phone wins: an activation start is
--     told awaiting_review only for its own kind; another phone's re-check
--     waiting for review ends, and its review photos are queued to go.
-- =====================================================================
DO $y3$
DECLARE
  v_u constant uuid := pg_temp.person('89');
  v_s uuid;
  v_got jsonb;
BEGIN
  PERFORM pg_temp.trust(v_u, pg_temp.dev_hash('a'));
  PERFORM public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', NULL);
  v_s := (public.begin_dating_verification(v_u, 'reverify', 'human', 'attune', pg_temp.dev_hash('b'), NULL) ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_u), ('dating-verification-review', v_s || '/2.jpg', v_u);
  PERFORM public.submit_dating_human_review(v_u, v_s);
  v_got := public.begin_dating_verification(v_u, 'activation', 'liveness', 'fake', pg_temp.dev_hash('a'), NULL);
  IF v_got ->> 'ok' IS DISTINCT FROM 'true' OR v_got ->> 'resumed' IS DISTINCT FROM 'false'
     OR (SELECT state FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'expired'
     OR (SELECT count(*) FROM public.media_deletion_queue
          WHERE bucket_id = 'dating-verification-review' AND object_name IN (v_s || '/1.jpg', v_s || '/2.jpg')) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another phone''s re-check held the owner''s own check: %', v_got;
  END IF;
END $y3$;

-- =====================================================================
-- Y4. (T5 fix round 1, I-3; R-16) A setup write must name its phone: an
--     unbound account's write without the header is refused and binds
--     nothing; the first check needs the phone too. Exposure-reducing
--     writes still never ask, header or not.
-- =====================================================================
DO $y4$
DECLARE
  v_u constant uuid := pg_temp.person('90');
  v_photo uuid;
  v_got jsonb;
BEGIN
  UPDATE public.dating_enrollments SET state = 'active', activated_at = now() WHERE user_id = v_u;
  v_got := jsonb_build_array(
    pg_temp.call_on(v_u, NULL, 'SELECT public.save_dating_children(''w4b-y4-child-001'', true, ''no'', false, false)'),
    public.begin_dating_verification(v_u, 'activation', 'liveness', 'fake', NULL, NULL));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "reverify_device"}, {"ok": false, "reason": "invalid"}]'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_trusted_devices WHERE user_id = v_u)
     OR (SELECT children_have FROM public.dating_profiles WHERE user_id = v_u) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a setup write or the first check ran without naming its phone: %', v_got;
  END IF;
  SELECT id INTO v_photo FROM public.dating_profile_photos WHERE user_id = v_u AND position = 2;
  INSERT INTO public.dating_notify_requests (user_id, country_code) VALUES (v_u, 'NG');
  INSERT INTO public.dating_gentle_wait_reflections (user_id, answers, saved_at) VALUES (v_u, '{"q1": "a note"}', now());
  v_got := jsonb_build_array(
    pg_temp.call_on(v_u, NULL, 'SELECT public.cancel_dating_country_notice()') ->> 'ok',
    pg_temp.call_on(v_u, NULL, 'SELECT public.save_gentle_wait_reflection(''{}'')') ->> 'ok',
    pg_temp.call_on(v_u, NULL, format('SELECT public.delete_dating_profile_photo(%L)', v_photo)) ->> 'ok',
    pg_temp.call_on(v_u, NULL, 'SELECT public.clear_dating_faith(''w4b-y4-faith-0001'')') ->> 'ok',
    pg_temp.err_on(v_u, NULL, 'SELECT public.pause_dating_mode(''w4b-y4-pause-0001'')'),
    pg_temp.err_on(v_u, NULL, 'SELECT public.exit_dating_mode(''w4b-y4-exit-00001'', false)'));
  IF v_got IS DISTINCT FROM '["true", "true", "true", "true", "ok", "ok"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an exposure-reducing write without the header was refused: %', v_got;
  END IF;
END $y4$;

-- =====================================================================
-- Y5. (T5 fix round 1, I-4) One rule decides the home's variant and the
--     re-check: after a revocation, a new phone is told "a video check"
--     by both, and the re-check can begin.
-- =====================================================================
DO $y5$
DECLARE
  v_u constant uuid := pg_temp.person('91');
  v_got jsonb;
BEGIN
  PERFORM pg_temp.trust(v_u, pg_temp.dev_hash('a'));
  PERFORM public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', NULL);
  PERFORM public.record_dating_age_assurance(v_u, 'fae', 'pass', 25::smallint, 'fake');
  PERFORM public.revoke_dating_age_verification(v_u, 'contract');
  v_got := jsonb_build_array(
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_dating_home()') ->> 'variant',
    public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('b'), NULL) ->> 'ok');
  IF v_got IS DISTINCT FROM '["verified", "true"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the home and the re-check disagree after a revocation: %', v_got;
  END IF;
END $y5$;

-- =====================================================================
-- Y6. (T5 fix round 1, I-5 ruling) Storage serves a Dating photo only to
--     the owner's trusted (or unbound) phone. Hosted Storage forwarding
--     x-attune-device is an owner gate (W4b flag-on).
-- =====================================================================
DO $y6$
DECLARE
  v_u constant uuid := pg_temp.person('92');
  v_free constant uuid := pg_temp.person('93');
  v_key text;
  v_free_key text;
  v_got jsonb;
BEGIN
  PERFORM pg_temp.call_on(v_u, pg_temp.dev('a'),
    'SELECT public.save_dating_children(''w4b-y6-child-001'', false, ''yes'', false, false)');
  SELECT storage_key INTO v_key FROM public.dating_profile_photos WHERE user_id = v_u AND position = 1;
  SELECT storage_key INTO v_free_key FROM public.dating_profile_photos WHERE user_id = v_free AND position = 1;
  v_got := jsonb_build_array(
    pg_temp.call_on(v_u, pg_temp.dev('a'), format('SELECT to_jsonb(public.dating_storage_owns(%L))', v_key)),
    pg_temp.call_on(v_u, pg_temp.dev('b'), format('SELECT to_jsonb(public.dating_storage_owns(%L))', v_key)),
    pg_temp.call_on(v_u, NULL, format('SELECT to_jsonb(public.dating_storage_owns(%L))', v_key)),
    pg_temp.call_on(v_free, NULL, format('SELECT to_jsonb(public.dating_storage_owns(%L))', v_free_key)));
  IF v_got IS DISTINCT FROM '[true, false, false, true]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Storage would serve a Dating photo to another phone: %', v_got;
  END IF;
END $y6$;

-- =====================================================================
-- Y7. (T5 fix round 1, M-1, M-4) The trust writer answers invalid for an
--     unknown person; with Dating off, an untrusted phone's home names no
--     country or notice.
-- =====================================================================
DO $y7$
DECLARE
  v_u constant uuid := pg_temp.person('94');
  v_got jsonb;
BEGIN
  PERFORM pg_temp.trust(v_u, pg_temp.dev_hash('a'));
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  v_got := jsonb_build_array(
    public.trust_dating_device(pg_temp.id('98'), pg_temp.dev_hash('a'), gen_random_uuid()), -- Spec 2 W4 final (M-3)
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_dating_home()') - 'has_data',
    (pg_temp.call_on(v_u, pg_temp.dev('a'), 'SELECT public.get_dating_home()') - 'has_data') ?& ARRAY['country', 'notify']);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"}, {"state": "feature_unavailable"}, true]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown person was not invalid, or Dating off told an untrusted phone more: %', v_got;
  END IF;
END $y7$;

-- =====================================================================
-- Y8. (T5 fix rounds 1-2) A person's pass on the first check's person
--     route trusts the phone it ran on, as a re-check's does; it never
--     shows a kept list again (C-1 ruling, round 2).
-- =====================================================================
DO $y8$
DECLARE
  v_u constant uuid := pg_temp.person('95');
  v_s uuid;
BEGIN
  INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two, kept_at) VALUES (v_u, pg_temp.dev_hash('e'), '07', now());
  v_s := (public.begin_dating_verification(v_u, 'activation', 'human', 'attune', pg_temp.dev_hash('e'), NULL) ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_u), ('dating-verification-review', v_s || '/2.jpg', v_u);
  PERFORM public.submit_dating_human_review(v_u, v_s);
  PERFORM public.decide_dating_human_review(v_s, 'pass', pg_temp.id('99'));
  -- T5 fix round 2 (C-1 ruling): no pass ever shows kept rows again.
  IF (SELECT verified_at FROM public.dating_trusted_devices WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('e')) IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_u AND kept_at IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person''s pass on the first check did not trust its phone, or showed the kept list';
  END IF;
END $y8$;

-- =====================================================================
-- Y9. (T5 fix round 3, I-9) The 50-row limit counts what the owner sees
--     (the entries plus the kept count): adding a kept number and adding a
--     fresh one leave the same room for the next adds.
-- =====================================================================
DO $y9$
DECLARE
  v_k constant uuid := pg_temp.person('97');
  v_f constant uuid := pg_temp.person('00');
  v_u uuid;
  v_ans jsonb := '{}';
  v_seen jsonb := '{}';
BEGIN
  FOREACH v_u IN ARRAY ARRAY[v_k, v_f] LOOP
    -- Bound on A; one number from before, kept; 47 entries since.
    PERFORM pg_temp.call_on(v_u, pg_temp.dev('a'),
      'SELECT public.save_dating_children(''w4b-y9-child-001'', false, ''yes'', false, false)');
    PERFORM pg_temp.call_on(v_u, pg_temp.dev('a'),
      'SELECT public.add_dating_never_introduce(''w4b-y9-never-000'', ''+447700900616'', ''Old'')');
    UPDATE public.dating_never_introduce SET kept_at = now(), label = NULL, created_at = now() - interval '30 days'
     WHERE owner_user_id = v_u;
    INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two)
    SELECT v_u, encode(extensions.digest(v_u::text || '-w4b-y9-fill-' || n, 'sha256'), 'hex'), lpad(n::text, 2, '0')
      FROM generate_series(1, 47) AS n;
  END LOOP;
  -- The guess: the kept number for one, a fresh number for the other; then
  -- three fresh adds each.
  v_ans := jsonb_build_object(
    'kept', jsonb_build_array(
      pg_temp.call_on(v_k, pg_temp.dev('a'), 'SELECT public.add_dating_never_introduce(''w4b-y9-never-001'', ''+447700900616'', NULL)'),
      pg_temp.call_on(v_k, pg_temp.dev('a'), 'SELECT public.add_dating_never_introduce(''w4b-y9-never-002'', ''+447700900621'', NULL)'),
      pg_temp.call_on(v_k, pg_temp.dev('a'), 'SELECT public.add_dating_never_introduce(''w4b-y9-never-003'', ''+447700900622'', NULL)'),
      pg_temp.call_on(v_k, pg_temp.dev('a'), 'SELECT public.add_dating_never_introduce(''w4b-y9-never-004'', ''+447700900623'', NULL)')),
    'fresh', jsonb_build_array(
      pg_temp.call_on(v_f, pg_temp.dev('a'), 'SELECT public.add_dating_never_introduce(''w4b-y9-never-001'', ''+447700900617'', NULL)'),
      pg_temp.call_on(v_f, pg_temp.dev('a'), 'SELECT public.add_dating_never_introduce(''w4b-y9-never-002'', ''+447700900621'', NULL)'),
      pg_temp.call_on(v_f, pg_temp.dev('a'), 'SELECT public.add_dating_never_introduce(''w4b-y9-never-003'', ''+447700900622'', NULL)'),
      pg_temp.call_on(v_f, pg_temp.dev('a'), 'SELECT public.add_dating_never_introduce(''w4b-y9-never-004'', ''+447700900623'', NULL)')));
  v_seen := jsonb_build_object(
    'kept', jsonb_build_array(jsonb_array_length(pg_temp.call_on(v_k, pg_temp.dev('a'), 'SELECT public.list_dating_never_introduce()') -> 'items'),
                              pg_temp.call_on(v_k, pg_temp.dev('a'), 'SELECT public.list_dating_never_introduce()') -> 'kept_count'),
    'fresh', jsonb_build_array(jsonb_array_length(pg_temp.call_on(v_f, pg_temp.dev('a'), 'SELECT public.list_dating_never_introduce()') -> 'items'),
                               pg_temp.call_on(v_f, pg_temp.dev('a'), 'SELECT public.list_dating_never_introduce()') -> 'kept_count'));
  IF v_ans -> 'kept' IS DISTINCT FROM v_ans -> 'fresh' OR v_seen -> 'kept' IS DISTINCT FROM v_seen -> 'fresh'
     OR v_ans -> 'kept' IS DISTINCT FROM '[{"ok": true, "message": "added"}, {"ok": true, "message": "added"},
                                          {"ok": false, "reason": "limit_reached"}, {"ok": false, "reason": "limit_reached"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a kept number and a fresh one left different room under the limit: % / %', v_ans, v_seen;
  END IF;
END $y9$;

-- =====================================================================
-- Z. (Spec 2 W4b Task 6, carry B; R-14; C-1 ruling) The edge function's
--    video re-check, call for call (handler.ts reverifyStart, then
--    reverifyComplete): a pass on a new phone trusts that phone, leaves
--    the account's own result as it was and never shows the kept list; a
--    stranger's failed re-check on another phone writes no result of the
--    owner's, trusts nothing and leaves the owner's phones trusted.
-- =====================================================================
DO $z$
DECLARE
  v_u constant uuid := pg_temp.person('98');
  v_s uuid;
  v_got jsonb;
  v_before jsonb;
BEGIN
  -- The owner passed on phone A; one Never-introduce row was kept.
  PERFORM public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', NULL);
  PERFORM pg_temp.trust(v_u, pg_temp.dev_hash('a'));
  INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two, kept_at)
  VALUES (v_u, pg_temp.dev_hash('e'), '07', now());
  v_before := (SELECT to_jsonb(v) - 'updated_at' FROM public.dating_age_verifications AS v WHERE v.user_id = v_u);
  IF v_before ->> 'identity_result' IS DISTINCT FROM 'pass'
     OR pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_dating_home()') ->> 'variant' IS DISTINCT FROM 'verified' THEN
    RAISE EXCEPTION 'fixture: the owner is not verified, or phone B is not asked for a video check';
  END IF;
  -- Phone B: reverify_start (begin, the vendor session's ref) ...
  v_got := public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('b'), NULL);
  v_s := (v_got ->> 'session_id')::uuid;
  IF v_s IS NULL OR public.set_dating_verification_ref(v_s, 'w4b-z-ref-b') ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'fixture: the re-check on phone B did not start: %', v_got;
  END IF;
  -- ... then reverify_complete on a pass: the session read, the liveness
  -- pass, the photos, the trust, the end.
  v_got := jsonb_build_array(
    public.get_dating_verification_session(v_u, v_s) - 'session_id' - 'vendor_session_ref' - 'country' - 'attempts' - 'vendor' - 'id_document' - 'outcome' - 'expired' - 'age' - 'identity' - 'age_recheck',
    public.record_dating_liveness_attempt(v_s, true) ->> 'ok',
    jsonb_array_length(public.get_dating_verification_photos(v_u)),
    public.trust_dating_device(v_u, pg_temp.dev_hash('b'), v_s), -- Spec 2 W4 final (M-3)
    public.finish_dating_verification_session(v_s, 'passed', 'verified', NULL) ->> 'ok');
  IF v_got IS DISTINCT FROM jsonb_build_array(
       jsonb_build_object('ok', true, 'kind', 'reverify', 'step', 'liveness', 'state', 'started', 'device_hash', pg_temp.dev_hash('b')),
       'true', 2, '{"ok": true}'::jsonb, 'true') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the edge''s re-check calls did not answer as it reads them: %', v_got;
  END IF;
  v_got := jsonb_build_array(
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.get_my_dating_profile()') ->> 'ok',
    pg_temp.call_on(v_u, pg_temp.dev('b'), 'SELECT public.list_dating_never_introduce()'));
  IF v_got IS DISTINCT FROM '["true", {"ok": true, "items": [], "kept_count": 1}]'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_u AND kept_at IS NOT NULL AND shown_at IS NULL)
     OR (SELECT to_jsonb(v) - 'updated_at' FROM public.dating_age_verifications AS v WHERE v.user_id = v_u) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a passed re-check did not trust its phone, showed the kept list, or wrote the owner''s result: %', v_got;
  END IF;
  -- Phone C, a stranger: reverify_start, then reverify_complete on a face
  -- that doesn't match (the liveness pass, the photos, the failed end).
  v_s := (public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('c'), NULL) ->> 'session_id')::uuid;
  IF v_s IS NULL OR public.set_dating_verification_ref(v_s, 'w4b-z-ref-c') ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'fixture: the re-check on phone C did not start';
  END IF;
  v_got := jsonb_build_array(
    public.record_dating_liveness_attempt(v_s, true) ->> 'ok',
    jsonb_array_length(public.get_dating_verification_photos(v_u)),
    public.finish_dating_verification_session(v_s, 'failed', 'identity_failed', NULL) ->> 'ok');
  IF v_got IS DISTINCT FROM '["true", 2, "true"]'::jsonb
     OR (SELECT to_jsonb(v) - 'updated_at' FROM public.dating_age_verifications AS v WHERE v.user_id = v_u) IS DISTINCT FROM v_before
     OR (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM 'verified'
     OR EXISTS (SELECT 1 FROM public.dating_trusted_devices WHERE user_id = v_u AND device_hash = pg_temp.dev_hash('c'))
     OR (SELECT count(*) FROM public.dating_trusted_devices WHERE user_id = v_u
          AND device_hash IN (pg_temp.dev_hash('a'), pg_temp.dev_hash('b'))) <> 2
     OR pg_temp.call_on(v_u, pg_temp.dev('c'), 'SELECT public.get_dating_home()') ->> 'state' IS DISTINCT FROM 'reverify_device'
     OR pg_temp.call_on(v_u, pg_temp.dev('a'), 'SELECT public.list_dating_never_introduce()')
          IS DISTINCT FROM '{"ok": true, "items": [], "kept_count": 1}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stranger''s failed re-check changed the owner''s result or phones, or trusted its own: %', v_got;
  END IF;
END $z$;

-- =====================================================================
-- FF1. (Spec 2 W4 final, I-1a ruling) An age pass belongs to the face
--      that earned it: Leave clears it (a fail stays, and Spec 1's hold
--      with it). The SIM-swap route (a new phone Leaves, which is never
--      device-gated, sets up again and passes identity with its own face)
--      finds no age pass to skip to: 'skip' is refused, the estimate's
--      answer stands, and an uncertain one opens the ID check.
-- =====================================================================
DO $ff1$
DECLARE
  v_a constant uuid := pg_temp.person('a0');
  v_f constant uuid := pg_temp.person('a1');
  v_r constant uuid := pg_temp.person('a2');
  v_s uuid;
  v_got jsonb;
BEGIN
  PERFORM public.record_dating_age_assurance(v_a, 'fae', 'pass', 25::smallint, 'fake');
  PERFORM public.record_dating_identity_check(v_a, 'liveness_compare', 'pass', 'fake', NULL);
  PERFORM pg_temp.call(v_a, 'SELECT to_jsonb(public.exit_dating_mode(''w4f-ff1-exit-0001''))');
  IF (SELECT coalesce(age_method, '-') || '/' || coalesce(age_result, '-') || '/' || coalesce(challenge_age::text, '-') || '/'
             || coalesce(age_vendor, '-') || '/' || coalesce(age_decided_at::text, '-') || '/' || coalesce(identity_result, '-')
        FROM public.dating_age_verifications WHERE user_id = v_a) IS DISTINCT FROM '-/-/-/-/-/-'
     OR public.dating_age_gate_holds(v_a) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an age pass survived Leave';
  END IF;
  -- A far-below fail and Spec 1's hold are kept (finality survives Leave).
  v_s := (pg_temp.start(v_f) ->> 'session_id')::uuid;
  PERFORM public.record_dating_age_far_below(v_f, v_s, 'fake');
  PERFORM private.dating_exit_internal(v_f, false);
  IF (SELECT age_method || '/' || age_result FROM public.dating_age_verifications WHERE user_id = v_f) IS DISTINCT FROM 'fae/fail'
     OR NOT EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_f AND kind = 'age_review' AND resolved_at IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Leave cleared an age fail or Spec 1''s hold';
  END IF;
  -- The SIM-swap route: the owner passed age and identity on phone A.
  PERFORM public.record_dating_age_assurance(v_r, 'fae', 'pass', 25::smallint, 'fake');
  PERFORM public.record_dating_identity_check(v_r, 'liveness_compare', 'pass', 'fake', NULL);
  PERFORM pg_temp.trust(v_r, pg_temp.dev_hash('a'));
  -- Phone B Leaves, sets up again (its first setup write binds it) ...
  PERFORM pg_temp.call_on(v_r, pg_temp.dev('b'), 'SELECT to_jsonb(public.exit_dating_mode(''w4f-ff1-exit-0002'', false))');
  UPDATE public.dating_enrollments SET state = 'profile_draft', updated_at = now() WHERE user_id = v_r;
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_r, 'Verify', 'GB', 'TLI');
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_r, 'w4f-consent-' || c, c, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile', 'biometric_verification']) AS c;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
  SELECT v_r, 'w4f/' || v_r || '/' || n || '.jpg', n, 'approved', 'clear' FROM generate_series(1, 2) AS n;
  PERFORM pg_temp.call_on(v_r, pg_temp.dev('b'), 'SELECT public.save_dating_children(''w4f-ff1-children-01'', false, ''yes'', false, false)');
  -- ... and its own face passes identity: no age pass stands to skip to.
  v_s := (public.begin_dating_verification(v_r, 'activation', 'liveness', 'fake', pg_temp.dev_hash('b'), NULL) ->> 'session_id')::uuid;
  v_got := jsonb_build_array(
    public.get_dating_verification_session(v_r, v_s) -> 'age',
    public.record_dating_video_outcome(v_r, v_s, 'pass', 'skip', NULL, 'fake', NULL));
  IF v_s IS NULL OR v_got IS DISTINCT FROM '[null, {"ok": false, "reason": "session_unavailable"}]'::jsonb
     OR public.dating_age_gate_holds(v_r) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after Leave and a new setup, identity alone re-used the age pass: %', v_got;
  END IF;
  v_got := jsonb_build_array(
    public.record_dating_video_outcome(v_r, v_s, 'pass', 'uncertain', NULL, 'fake', 'unconfigured'),
    public.begin_dating_verification(v_r, 'activation', 'id', 'fake', pg_temp.dev_hash('b'), 'passport') -> 'ok');
  IF v_got IS DISTINCT FROM '[{"ok": true, "outcome": "age_uncertain", "position": null, "replayed": false}, true]'::jsonb
     OR public.dating_age_gate_holds(v_r) IS NOT FALSE
     OR (SELECT age_result FROM public.dating_age_verifications WHERE user_id = v_r) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the SIM-swap route got an age pass, or its ID check did not open: %', v_got;
  END IF;
END $ff1$;

-- =====================================================================
-- FF2. (Spec 2 W4 final, I-1b ruling; R-13) Every approved photo newer
--      than the age decision (a photo swap on a trusted phone): the
--      session read says age_recheck, so the edge estimates again; 'skip'
--      is refused; an uncertain or low estimate clears the pass and the ID
--      check opens; far below 18 takes Spec 1's hold; a new pass renews
--      it. An adult who keeps one older photo is not asked again. The
--      person route (a person never passes age) clears it the same way.
-- =====================================================================
DO $ff2$
DECLARE
  v_swap constant uuid := pg_temp.person('a3');
  v_low constant uuid := pg_temp.person('a4');
  v_far constant uuid := pg_temp.person('a5');
  v_renew constant uuid := pg_temp.person('a6');
  v_keep constant uuid := pg_temp.person('a7');
  v_human constant uuid := pg_temp.person('a8');
  v_hkeep constant uuid := pg_temp.person('a9');
  v_other constant uuid := pg_temp.person('aa');
  v_all constant uuid[] := ARRAY[v_swap, v_low, v_far, v_renew, v_keep, v_human, v_hkeep];
  v_s uuid;
  v_m uuid;
  v_at timestamptz;
  v_got jsonb;
  u uuid;
BEGIN
  -- Each passed age (by ID) and identity an hour ago, with photos two hours old.
  FOREACH u IN ARRAY v_all LOOP
    PERFORM public.record_dating_age_assurance(u, 'id', 'pass', NULL, 'fake');
    PERFORM public.record_dating_identity_check(u, 'liveness_compare', 'pass', 'fake', NULL);
  END LOOP;
  UPDATE public.dating_age_verifications SET age_decided_at = now() - interval '1 hour' WHERE user_id = ANY (v_all);
  UPDATE public.dating_profile_photos SET created_at = now() - interval '2 hours' WHERE user_id = ANY (v_all);
  IF EXISTS (SELECT 1 FROM unnest(v_all) AS a(u) WHERE private.dating_age_recheck_due(a.u) IS NOT FALSE)
     OR private.dating_age_recheck_due(v_other) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-check was due with the photos the age was checked with, or with no age at all';
  END IF;
  -- Every photo replaced (newer than the decision), as the photo writer
  -- does it: the profile needs its check again. v_keep and v_hkeep keep
  -- photo 1.
  UPDATE public.dating_profile_photos SET created_at = now()
   WHERE user_id = ANY (v_all) AND NOT (user_id IN (v_keep, v_hkeep) AND position = 1);
  UPDATE public.dating_profiles SET verification_state = 'needs_review' WHERE user_id = ANY (v_all);
  SELECT age_decided_at INTO v_at FROM public.dating_age_verifications WHERE user_id = v_keep;
  -- The swap: the read says so; skip is refused; uncertain clears the pass.
  v_s := (pg_temp.start(v_swap) ->> 'session_id')::uuid;
  v_m := (pg_temp.start(v_keep) ->> 'session_id')::uuid; -- (its own statement: a read sees only what came before it)
  v_got := jsonb_build_array(
    public.get_dating_verification_session(v_swap, v_s) -> 'age_recheck',
    public.get_dating_verification_session(v_keep, v_m) -> 'age_recheck',
    public.record_dating_video_outcome(v_swap, v_s, 'pass', 'skip', NULL, 'fake', NULL));
  IF v_got IS DISTINCT FROM '[true, false, {"ok": false, "reason": "session_unavailable"}]'::jsonb
     OR (SELECT age_result || '/' || identity_result FROM public.dating_age_verifications WHERE user_id = v_swap) IS DISTINCT FROM 'pass/pass'
     OR (SELECT state FROM public.dating_verification_sessions WHERE id = v_s) IS DISTINCT FROM 'started' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a photo swap re-used the age pass without an estimate: %', v_got;
  END IF;
  v_got := jsonb_build_array(
    public.record_dating_video_outcome(v_swap, v_s, 'pass', 'uncertain', NULL, 'fake', NULL),
    pg_temp.start(v_swap, 'id', 'passport') -> 'ok');
  IF v_got IS DISTINCT FROM '[{"ok": true, "outcome": "age_uncertain", "position": null, "replayed": false}, true]'::jsonb
     OR (SELECT coalesce(age_result, '-') || '/' || coalesce(age_method, '-') || '/' || identity_result
           FROM public.dating_age_verifications WHERE user_id = v_swap) IS DISTINCT FROM '-/-/pass'
     OR public.dating_age_gate_holds(v_swap) IS NOT FALSE
     OR pg_temp.call(v_swap, 'SELECT public.get_my_dating_verification()') -> 'age' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an uncertain estimate after a photo swap kept the age pass, or the ID check did not open: %', v_got;
  END IF;
  -- Below 25: the same (R-13: the ID check, never an ending).
  v_s := (pg_temp.start(v_low) ->> 'session_id')::uuid;
  v_got := public.record_dating_video_outcome(v_low, v_s, 'pass', 'needs_id', NULL, 'fake', 'fake');
  IF v_got ->> 'outcome' IS DISTINCT FROM 'needs_id' OR public.dating_age_gate_holds(v_low) IS NOT FALSE
     OR (SELECT age_result FROM public.dating_age_verifications WHERE user_id = v_low) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an estimate below 25 after a photo swap kept the age pass: %', v_got;
  END IF;
  -- Far below 18: Spec 1's hold, every match closed.
  v_s := (pg_temp.start(v_far) ->> 'session_id')::uuid;
  v_m := pg_temp.match(v_far, v_other);
  v_got := public.record_dating_video_outcome(v_far, v_s, 'pass', 'far_below', NULL, 'fake', 'fake');
  IF v_got ->> 'outcome' IS DISTINCT FROM 'far_below'
     OR (SELECT age_method || '/' || age_result FROM public.dating_age_verifications WHERE user_id = v_far) IS DISTINCT FROM 'fae/fail'
     OR NOT EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_far AND kind = 'age_review' AND reason_ref = v_s::text)
     OR (SELECT closed_reason FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'age_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a far-below face after a photo swap did not take Spec 1''s hold: %', v_got;
  END IF;
  -- A new pass renews the decision: no re-check is due after it.
  v_s := (pg_temp.start(v_renew) ->> 'session_id')::uuid;
  v_got := public.record_dating_video_outcome(v_renew, v_s, 'pass', 'pass', NULL, 'fake', 'fake');
  IF v_got ->> 'outcome' IS DISTINCT FROM 'verified' OR private.dating_age_recheck_due(v_renew) IS NOT FALSE
     OR (SELECT age_method || '/' || age_result FROM public.dating_age_verifications WHERE user_id = v_renew) IS DISTINCT FROM 'fae/pass' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a passing estimate after a photo swap did not renew the age: %', v_got;
  END IF;
  -- One older photo kept: identity alone (skip), the age untouched.
  v_s := (SELECT id FROM public.dating_verification_sessions WHERE user_id = v_keep AND state = 'started');
  v_got := public.record_dating_video_outcome(v_keep, v_s, 'pass', 'skip', NULL, 'fake', NULL);
  IF v_got ->> 'outcome' IS DISTINCT FROM 'verified'
     OR (SELECT age_method || '/' || age_result FROM public.dating_age_verifications WHERE user_id = v_keep) IS DISTINCT FROM 'id/pass'
     OR (SELECT age_decided_at FROM public.dating_age_verifications WHERE user_id = v_keep) IS DISTINCT FROM v_at THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an adult who kept an older photo was asked for the age again: %', v_got;
  END IF;
  -- The person route: a pass decides identity; the age pass goes when
  -- every photo is newer, and stays when one older photo is kept.
  FOREACH u IN ARRAY ARRAY[v_human, v_hkeep] LOOP
    v_s := (pg_temp.start(u, 'human') ->> 'session_id')::uuid;
    INSERT INTO storage.objects (bucket_id, name, owner) VALUES
      ('dating-verification-review', v_s || '/1.jpg', u), ('dating-verification-review', v_s || '/2.jpg', u);
    PERFORM public.submit_dating_human_review(u, v_s);
    PERFORM public.decide_dating_human_review(v_s, 'pass', pg_temp.id('99'));
  END LOOP;
  v_got := jsonb_build_array(
    (SELECT coalesce(age_result, '-') || '/' || identity_result FROM public.dating_age_verifications WHERE user_id = v_human),
    (SELECT coalesce(age_result, '-') || '/' || identity_result FROM public.dating_age_verifications WHERE user_id = v_hkeep),
    (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_human));
  IF v_got IS DISTINCT FROM '["-/pass", "pass/pass", "verified"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the person route kept an age pass for newer photos, or cleared a kept one: %', v_got;
  END IF;
END $ff2$;

-- =====================================================================
-- FF3. (Spec 2 W4 final, M-1, M-2) A person review waits 72 hours from
--      its submission, not from the session's start; a re-check (a
--      stranger's phone) never moves the owner's verification state, at
--      its submission or when the sweep expires it.
-- =====================================================================
DO $ff3$
DECLARE
  v_late constant uuid := pg_temp.person('b0');
  v_old constant uuid := pg_temp.person('b1');
  v_own constant uuid := pg_temp.person('b2');
  v_s uuid;
  v_t uuid;
  v_r uuid;
  v_got jsonb;
BEGIN
  v_s := (pg_temp.start(v_late, 'human') ->> 'session_id')::uuid;
  v_t := (pg_temp.start(v_old, 'human') ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_late), ('dating-verification-review', v_s || '/2.jpg', v_late),
    ('dating-verification-review', v_t || '/1.jpg', v_old), ('dating-verification-review', v_t || '/2.jpg', v_old);
  PERFORM public.submit_dating_human_review(v_late, v_s);
  PERFORM public.submit_dating_human_review(v_old, v_t);
  UPDATE public.dating_verification_sessions SET created_at = now() - interval '73 hours', awaiting_since = now() - interval '13 hours'
   WHERE id = v_s;
  UPDATE public.dating_verification_sessions SET created_at = now() - interval '74 hours', awaiting_since = now() - interval '73 hours'
   WHERE id = v_t;
  -- The owner passed on phone A; their profile is not verified now (a new
  -- photo). A stranger on phone C asks a person.
  PERFORM public.record_dating_identity_check(v_own, 'liveness_compare', 'pass', 'fake', NULL);
  PERFORM pg_temp.trust(v_own, pg_temp.dev_hash('a'));
  UPDATE public.dating_profiles SET verification_state = 'unverified' WHERE user_id = v_own;
  v_r := (public.begin_dating_verification(v_own, 'reverify', 'human', 'attune', pg_temp.dev_hash('c'), NULL) ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_r || '/1.jpg', v_own), ('dating-verification-review', v_r || '/2.jpg', v_own);
  v_got := jsonb_build_array(public.submit_dating_human_review(v_own, v_r));
  v_got := v_got || jsonb_build_array((SELECT verification_state FROM public.dating_profiles WHERE user_id = v_own)); -- (its own statement)
  IF v_r IS NULL OR v_got IS DISTINCT FROM '[{"ok": true}, "unverified"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stranger''s re-check moved the owner''s verification state: %', v_got;
  END IF;
  -- The owner's own state waits for their own check; the stranger's
  -- review expires after 72 hours without touching it.
  UPDATE public.dating_profiles SET verification_state = 'needs_review' WHERE user_id = v_own;
  UPDATE public.dating_verification_sessions SET created_at = now() - interval '74 hours', awaiting_since = now() - interval '73 hours'
   WHERE id = v_r;
  PERFORM public.sweep_dating_verification_sessions();
  v_got := jsonb_build_array(
    (SELECT state FROM public.dating_verification_sessions WHERE id = v_s),
    (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_late),
    (SELECT state FROM public.dating_verification_sessions WHERE id = v_t),
    (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_old),
    (SELECT state FROM public.dating_verification_sessions WHERE id = v_r),
    (SELECT verification_state FROM public.dating_profiles WHERE user_id = v_own));
  IF v_got IS DISTINCT FROM '["awaiting_review", "needs_review", "expired", "unverified", "expired", "needs_review"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep counted a review from the session''s start, or a re-check moved the owner: %', v_got;
  END IF;
END $ff3$;

-- =====================================================================
-- FF4. (Spec 2 W4 final, M-3) A phone is trusted only through a session
--      that ran on it, for that person, open or passed: a Leave that lands
--      during the vendor calls deletes the session, so the late trust
--      binds nothing. The service role's alone, definer, empty path.
-- =====================================================================
DO $ff4$
DECLARE
  v_sig constant text := 'public.trust_dating_device(uuid,text,uuid)';
  v_u constant uuid := pg_temp.person('b3');
  v_x constant uuid := pg_temp.person('b4');
  v_s uuid;
  v_got jsonb;
BEGIN
  IF to_regprocedure('public.trust_dating_device(uuid,text)') IS NOT NULL
     OR has_function_privilege('authenticated', v_sig, 'EXECUTE') OR has_function_privilege('anon', v_sig, 'EXECUTE')
     OR NOT has_function_privilege('service_role', v_sig, 'EXECUTE')
     OR (SELECT p.prosecdef AND p.proconfig @> ARRAY['search_path=""'] FROM pg_proc AS p WHERE p.oid = v_sig::regprocedure) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the trust writer takes no session, or is not the service role''s alone';
  END IF;
  v_s := (public.begin_dating_verification(v_u, 'activation', 'liveness', 'fake', pg_temp.dev_hash('a'), NULL) ->> 'session_id')::uuid;
  v_got := jsonb_build_array(
    public.trust_dating_device(v_u, pg_temp.dev_hash('a'), NULL),
    public.trust_dating_device(v_u, pg_temp.dev_hash('b'), v_s),
    public.trust_dating_device(v_x, pg_temp.dev_hash('a'), v_s),
    public.trust_dating_device(v_u, pg_temp.dev_hash('a'), v_s));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"}, {"ok": false, "reason": "session_unavailable"},
      {"ok": false, "reason": "session_unavailable"}, {"ok": true}]'::jsonb
     OR (SELECT array_agg(device_hash) FROM public.dating_trusted_devices WHERE user_id IN (v_u, v_x))
          IS DISTINCT FROM ARRAY[pg_temp.dev_hash('a')] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a phone was trusted through another phone''s or person''s session: %', v_got;
  END IF;
  -- Leave lands during the vendor calls: the late trust binds nothing.
  PERFORM pg_temp.call(v_u, 'SELECT to_jsonb(public.exit_dating_mode(''w4f-ff4-exit-0001''))');
  v_got := public.trust_dating_device(v_u, pg_temp.dev_hash('a'), v_s);
  IF v_got IS DISTINCT FROM '{"ok": false, "reason": "session_unavailable"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_trusted_devices WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a trust that landed after Leave bound a phone to the exited account: %', v_got;
  END IF;
END $ff4$;

-- =====================================================================
-- FF5. (Spec 2 W4 final, M-4) Another phone's open check answers its own
--      fixed code, never busy; a re-check has its own budget per phone (5
--      a day), so a stranger's phone never uses the owner's.
-- =====================================================================
DO $ff5$
DECLARE
  v_u constant uuid := pg_temp.person('b5');
  v_s uuid;
  v_got jsonb;
BEGIN
  PERFORM public.record_dating_identity_check(v_u, 'liveness_compare', 'pass', 'fake', NULL);
  PERFORM pg_temp.trust(v_u, pg_temp.dev_hash('a'));
  v_s := (public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('b'), NULL) ->> 'session_id')::uuid;
  v_got := public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('c'), NULL);
  IF v_s IS NULL OR v_got IS DISTINCT FROM '{"ok": false, "reason": "session_elsewhere"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another phone''s open check did not answer session_elsewhere: %', v_got;
  END IF;
  -- Five re-checks on phone C today: C's sixth is refused; phone D and the
  -- owner's own check on A still start.
  UPDATE public.dating_verification_sessions SET state = 'expired' WHERE id = v_s;
  INSERT INTO public.dating_verification_sessions (user_id, kind, step, vendor, state, device_hash, expires_at)
  SELECT v_u, 'reverify', 'liveness', 'fake', 'expired', pg_temp.dev_hash('c'), now() FROM generate_series(1, 5);
  v_got := jsonb_build_array(public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('c'), NULL));
  v_s := (public.begin_dating_verification(v_u, 'reverify', 'liveness', 'fake', pg_temp.dev_hash('d'), NULL) ->> 'session_id')::uuid;
  UPDATE public.dating_verification_sessions SET state = 'expired' WHERE id = v_s;
  v_got := v_got || jsonb_build_array(v_s IS NOT NULL,
    public.begin_dating_verification(v_u, 'activation', 'liveness', 'fake', pg_temp.dev_hash('a'), NULL) -> 'ok');
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "rate_limited"}, true, true]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-check''s budget is not its own phone''s: %', v_got;
  END IF;
END $ff5$;

-- =====================================================================
-- FF6. (Spec 2 W4 final, M-6, M-8) A far-below face wins over a photo
--      that doesn't match it (Spec 1's hold, never "change that photo");
--      any other estimate on a mismatch records no age. The far-below row
--      names the vendor that decided (the estimator, or the ID vendor).
-- =====================================================================
DO $ff6$
DECLARE
  v_u constant uuid := pg_temp.person('b6');
  v_b constant uuid := pg_temp.person('b7');
  v_id constant uuid := pg_temp.person('b8');
  v_s uuid;
  v_m uuid;
  v_got jsonb;
BEGIN
  v_s := (pg_temp.start(v_u) ->> 'session_id')::uuid;
  v_m := pg_temp.match(v_u, v_b);
  v_got := jsonb_build_array(
    public.record_dating_video_outcome(v_u, v_s, 'fail', 'needs_id', 2::smallint, 'fake', 'fake'),
    public.record_dating_video_outcome(v_u, v_s, 'fail', 'far_below', 2::smallint, 'fake', 'estimator_x'),
    public.record_dating_video_outcome(v_u, v_s, 'fail', 'far_below', 2::smallint, 'fake', 'estimator_x'));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"},
      {"ok": true, "outcome": "far_below", "position": null, "replayed": false},
      {"ok": true, "outcome": "far_below", "position": null, "replayed": true}]'::jsonb
     OR (SELECT age_method || '/' || age_result || '/' || age_vendor || '/' || identity_result
           FROM public.dating_age_verifications WHERE user_id = v_u) IS DISTINCT FROM 'fae/fail/estimator_x/fail'
     OR (SELECT state || '/' || outcome || '/' || coalesce(outcome_position::text, '-') FROM public.dating_verification_sessions WHERE id = v_s)
          IS DISTINCT FROM 'failed/far_below/-'
     OR (SELECT count(*) FROM public.account_holds WHERE user_id = v_u AND kind = 'age_review' AND reason_ref = v_s::text) <> 1
     OR (SELECT closed_reason FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'age_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a far-below face on a photo mismatch was not Spec 1''s hold, or named the wrong vendor: %', v_got;
  END IF;
  -- The ID route names the ID vendor; a vendor that isn't a code is invalid.
  v_s := (pg_temp.start(v_id, 'id', 'passport') ->> 'session_id')::uuid;
  v_got := jsonb_build_array(public.record_dating_age_far_below(v_id, v_s, 'Not A Vendor'),
                             public.record_dating_age_far_below(v_id, v_s, 'smile_id'));
  IF v_got IS DISTINCT FROM '[{"ok": false, "reason": "invalid"}, {"ok": true, "replayed": false}]'::jsonb
     OR (SELECT age_method || '/' || age_vendor FROM public.dating_age_verifications WHERE user_id = v_id) IS DISTINCT FROM 'id/smile_id' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ID route''s far-below row does not name the ID vendor: %', v_got;
  END IF;
END $ff6$;

-- =====================================================================
-- FF7. (Spec 2 W4 final, M-11) The six re-created v1 functions run with
--      an empty search path, as every W4 function does.
-- =====================================================================
DO $ff7$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_bad
    FROM pg_proc AS p
   WHERE p.oid IN ('public.dating_age_gate_holds(uuid)'::regprocedure, 'public.enforce_dating_age_verification_change()'::regprocedure,
                   'public.invalidate_dating_for_user(uuid,text)'::regprocedure, 'public.enforce_dating_restriction_change()'::regprocedure,
                   'public.dating_pair_passes_hard_filters(uuid,uuid)'::regprocedure, 'public.get_dating_operational_health()'::regprocedure)
     AND (p.prosecdef AND p.proconfig @> ARRAY['search_path=""']) IS NOT TRUE;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: definer functions with a search path: %', v_bad;
  END IF;
END $ff7$;

-- =====================================================================
-- FF8. (Spec 2 W4 final re-review 1, N-1) An age pass cleared for a
--      re-check (the video's uncertain estimate, or a person's pass, after
--      every photo was replaced) pauses with 'verification' at once, as a
--      revocation does, closing no match: the home says "check needed" and
--      offers no Resume until a new check passes, then offers it. Leave
--      still ends in exited.
-- =====================================================================
DO $ff8$
DECLARE
  v_vid constant uuid := pg_temp.person('c0');
  v_hum constant uuid := pg_temp.person('c1');
  v_out constant uuid := pg_temp.person('c2');
  v_peer constant uuid := pg_temp.person('c3');
  v_all constant uuid[] := ARRAY[v_vid, v_hum, v_out];
  v_m1 uuid;
  v_m2 uuid;
  v_s uuid;
  v_got jsonb;
  u uuid;
BEGIN
  FOREACH u IN ARRAY v_all LOOP
    PERFORM public.record_dating_age_assurance(u, 'id', 'pass', NULL, 'fake');
    PERFORM public.record_dating_identity_check(u, 'liveness_compare', 'pass', 'fake', NULL);
  END LOOP;
  UPDATE public.dating_age_verifications SET age_decided_at = now() - interval '1 hour' WHERE user_id = ANY (v_all);
  UPDATE public.dating_enrollments SET state = 'active', activated_at = now() - interval '1 day' WHERE user_id = ANY (v_all);
  UPDATE public.dating_profiles SET profile_state = 'active' WHERE user_id = ANY (v_all);
  v_m1 := pg_temp.match(v_vid, v_peer);
  v_m2 := pg_temp.match(v_hum, v_peer);
  -- Every photo replaced after the age decision (the profile needs its check again).
  UPDATE public.dating_profiles SET verification_state = 'needs_review' WHERE user_id = ANY (v_all);
  -- The video route: an uncertain estimate clears the pass.
  v_s := (pg_temp.start(v_vid) ->> 'session_id')::uuid;
  PERFORM public.record_dating_video_outcome(v_vid, v_s, 'pass', 'uncertain', NULL, 'fake', NULL);
  -- The person route: a person's pass clears it.
  v_s := (pg_temp.start(v_hum, 'human') ->> 'session_id')::uuid;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-verification-review', v_s || '/1.jpg', v_hum), ('dating-verification-review', v_s || '/2.jpg', v_hum);
  PERFORM public.submit_dating_human_review(v_hum, v_s);
  PERFORM public.decide_dating_human_review(v_s, 'pass', pg_temp.id('99'));
  v_got := jsonb_build_array(
    (SELECT state || '/' || coalesce(pause_reason, 'NULL') FROM public.dating_enrollments WHERE user_id = v_vid),
    (SELECT state || '/' || coalesce(pause_reason, 'NULL') FROM public.dating_enrollments WHERE user_id = v_hum),
    (SELECT string_agg(state, '/' ORDER BY id) FROM public.dating_matches WHERE id IN (v_m1, v_m2)),
    pg_temp.call_on(v_vid, pg_temp.dev('f'), 'SELECT public.get_dating_home()') - 'has_data',
    pg_temp.call_on(v_hum, pg_temp.dev('f'), 'SELECT public.get_dating_home()') - 'has_data');
  IF v_got IS DISTINCT FROM '["paused/verification", "paused/verification", "active/active",
      {"state": "paused", "pause_reason": "verification", "can_resume": false, "check": "needed"},
      {"state": "paused", "pause_reason": "verification", "can_resume": false, "check": "needed"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a cleared age pass did not pause for verification (or closed a match): %', v_got;
  END IF;
  -- (Read from the phone the checks ran on: the person's pass trusted it.)
  -- A new check passes: Resume is offered again.
  PERFORM public.record_dating_age_assurance(x.p, 'id', 'pass', NULL, 'fake') FROM unnest(ARRAY[v_vid, v_hum]) AS x(p);
  v_got := jsonb_build_array(
    pg_temp.call_on(v_vid, pg_temp.dev('f'), 'SELECT public.get_dating_home()') -> 'can_resume',
    pg_temp.call_on(v_hum, pg_temp.dev('f'), 'SELECT public.get_dating_home()') -> 'can_resume');
  IF v_got IS DISTINCT FROM '[true, true]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new pass after the re-check did not offer Resume: %', v_got;
  END IF;
  -- Leave (it clears the pass too) still ends in exited, no pause reason.
  PERFORM pg_temp.call(v_out, 'SELECT to_jsonb(public.exit_dating_mode(''w4f-ff8-exit-0001''))');
  IF (SELECT state || '/' || coalesce(pause_reason, 'NULL') FROM public.dating_enrollments WHERE user_id = v_out)
       IS DISTINCT FROM 'exited/NULL' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Leave did not end in exited after clearing the age pass';
  END IF;
END $ff8$;

DO $$ BEGIN RAISE NOTICE 'dating_v2_verification_contracts: all held'; END $$;
ROLLBACK;
