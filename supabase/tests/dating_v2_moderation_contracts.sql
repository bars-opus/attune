-- supabase/tests/dating_v2_moderation_contracts.sql
-- Spec 2 W7a (§3.7, §4.3, §4.8, §6.2, §6.3, §7.1, §7.2 S8, S11, §7.5
-- mutants 13-15; W6 carries T2 N-4, T5, T8, M-16): the 14 categories and
-- their priorities, the answers, the evidence, the report windows (A);
-- the automatic steps, never a ban (B); corroboration and credibility, the
-- holds (C); one case per person, every match linked and held from the
-- purge, a report about a deleted account (D). Task 2 adds what the
-- restricted person sees, the appeal, carry-over, deletion and release
-- (E onward). Fixture ids are 7a7000..-nn and phones +1555971nn, unique
-- in the suite; each section takes its own range of nn (A-D 01-59, E-H
-- 60-83, W7b I-M 85-129, W7c N-P 130-159).
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_moderation_contracts.sql
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w7-moderation-key', true);
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w7-field-key-0123456789abcdef-0123', true);
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w7-push-key', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
SELECT private.seed_dating_field_key_fingerprint() AS seeded_field \gset
INSERT INTO public.feature_flags (key, enabled)
VALUES ('dating_mode_enabled', true), ('dating_candidate_generation', true), ('dating_same_gender_matching', true),
       ('dating_match_messaging', true), ('dating_profile_photos', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;
SELECT public.publish_country_config('GH', '{"dating_enabled": true, "open_regions": ["AA", "AH"]}') AS gh \gset
SELECT public.publish_country_config('GB', '{"dating_enabled": true}') AS gb \gset
UPDATE public.dating_algorithm_configs SET state = 'retired', retired_at = now() WHERE state = 'active';
UPDATE public.dating_algorithm_configs
   SET state = 'active', activated_at = now(), product_review_ref = 'DEV-product', clinical_review_ref = 'DEV-clinical',
       fairness_review_ref = 'DEV-fairness', safety_review_ref = 'DEV-safety'
 WHERE version = 'introductions_v2';

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('7a700000-0000-0000-0000-' || lpad(p_n, 12, '0'))::uuid;
$$;
CREATE FUNCTION pg_temp.dev(p_n text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT md5('w7-device-' || p_n);
$$;
-- A current candidate (the chat contract's fixture person) with every
-- answer in [o] over the defaults; "phone" names another fixture's number
-- (the same person on a new account), "device" another's phone.
CREATE FUNCTION pg_temp.ready(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.id(p_n);
  d constant jsonb := '{"identity": "woman", "seeking": ["man"], "country": "GH", "region": "AA", "years": 30,
    "days": 40, "phone": null, "device": null}'::jsonb || o;
  v_phone constant text := '+1555971' || coalesce(d ->> 'phone', p_n);
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_u, ltrim(v_phone, '+'), now(), now() - make_interval(days => (d ->> 'days')::int));
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_u, v_phone, 'Mod ' || p_n, 'dating', now() - make_interval(days => (d ->> 'days')::int), now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_u, (current_date - make_interval(years => (d ->> 'years')::int) - interval '10 days')::date);
  INSERT INTO public.dating_enrollments (user_id, state, opted_in_at, activated_at) VALUES (v_u, 'active', now(), now());
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, moderation_state, verification_state,
    country_code, region_code, intention, timeline_visible, not_married_attested_at, attestation_version,
    children_have, children_want, faith_visible)
  VALUES (v_u, 'Mod ' || p_n, 'active', 'approved', 'verified', d ->> 'country', d ->> 'region',
    'committed', true, now(), '2026-10-v1', false, 'yes', false);
  INSERT INTO public.dating_preferences (user_id, min_age, max_age, region_scope, open_abroad, want_must_match, exclude_parents)
  VALUES (v_u, 25, 40, 'region', '{}', false, false);
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  VALUES (v_u, private.dating_field_encrypt(jsonb_build_object('identity', d ->> 'identity', 'pools', jsonb_build_array(d ->> 'identity'))),
          private.dating_field_encrypt(jsonb_build_object('seeking', d -> 'seeking')));
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer, moderation_state)
  SELECT v_u, n, CASE n WHEN 1 THEN 'perfect_sunday' ELSE 'ask_me_about' END, 'A moderation fixture answer ' || n, 'approved'
    FROM generate_series(1, 2) AS n;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
  SELECT v_u, 'w7/' || v_u || '/' || n || '.jpg', n, 'approved', 'clear' FROM generate_series(1, 2) AS n;
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, age_vendor, age_decided_at,
    identity_method, identity_result, identity_vendor, identity_decided_at)
  VALUES (v_u, 'id', 'pass', 'contract', now(), 'liveness_compare', 'pass', 'contract', now());
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'w7-consent-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']) AS p;
  INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
  VALUES (v_u, encode(extensions.digest(pg_temp.dev(coalesce(d ->> 'device', p_n)), 'sha256'), 'hex'), now(), now());
  RETURN v_u;
END $$;
CREATE FUNCTION pg_temp.man(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE sql AS $$
  SELECT pg_temp.ready(p_n, '{"identity": "man", "seeking": ["woman"]}'::jsonb || o);
$$;
CREATE FUNCTION pg_temp.as_person(p uuid, p_device text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.headers', CASE WHEN p_device IS NULL THEN '' ELSE json_build_object('x-attune-device', p_device)::text END, true);
END $$;
CREATE FUNCTION pg_temp.as_db() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.headers', '', true);
END $$;
-- [p_sql] as [p] on the phone [p_device] (NULL: no header); the error's
-- SQLSTATE and message when it raises.
CREATE FUNCTION pg_temp.call(p uuid, p_device text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_person(p, p_device);
  EXECUTE p_sql INTO v;
  PERFORM pg_temp.as_db();
  RETURN coalesce(v, '<NULL>');
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.as_db();
  RETURN SQLSTATE || ':' || SQLERRM;
END $$;
-- The same, as jsonb, on the person's own phone (a raised error is
-- {"raised": "<state>:<message>"}).
CREATE FUNCTION pg_temp.j(p uuid, p_n text, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v text := pg_temp.call(p, pg_temp.dev(p_n), p_sql);
BEGIN
  RETURN v::jsonb;
EXCEPTION WHEN invalid_text_representation THEN
  RETURN jsonb_build_object('raised', v);
END $$;
-- Runs [p_setup] and [p_probe], then undoes both (a savepoint).
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
    RAISE EXCEPTION 'w7:probe_undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'w7:probe_undo' THEN
      RAISE;
    END IF;
  END;
  RETURN coalesce(v, '<NULL>');
END $$;
CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0)::bigint;
$$;
CREATE FUNCTION pg_temp.key(p text) RETURNS text LANGUAGE sql AS $$
  SELECT 'w7-' || p || '-' || replace(gen_random_uuid()::text, '-', '');
$$;
-- An active match of two days, and its id.
CREATE FUNCTION pg_temp.match(p_a uuid, p_b uuid) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at, pair_key)
  VALUES (least(p_a, p_b), greatest(p_a, p_b), 'active', now() - interval '2 days', public.dating_pair_key(p_a, p_b))
  RETURNING id;
$$;
-- [p_n] messages from [p_from] in [p_m] (as stored by send), oldest first.
CREATE FUNCTION pg_temp.say(p_m uuid, p_from uuid, p_body text, p_n int DEFAULT 1) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, body, body_masked, mask_version, idempotency_key,
                                      created_at)
  SELECT p_m, CASE WHEN m.user_low_id = p_from THEN 'low' ELSE 'high' END, p_from, p_body || CASE WHEN p_n > 1 THEN ' ' || g ELSE '' END,
         p_body, 1, pg_temp.key('say'), clock_timestamp()
    FROM public.dating_matches AS m, generate_series(1, p_n) AS g WHERE m.id = p_m;
$$;
-- [p_by]'s report of [p_cat] on match [p_m]: the answer.
CREATE FUNCTION pg_temp.report(p_by uuid, p_n text, p_m uuid, p_cat text, p_block boolean DEFAULT false,
                               p_details text DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p_by, p_n, format('SELECT public.report_dating_match(%L, %L, %L, %L, %L)',
                                     pg_temp.key('r' || p_n), p_m, p_cat, p_details, p_block));
$$;
CREATE FUNCTION pg_temp.excluded(p uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT private.dating_generation_removed(p, now(), (private.dating_intro_config()).o_config);
$$;
CREATE FUNCTION pg_temp.marked(p_a uuid, p_b uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_pair_markers AS k
                  WHERE k.pair_code = private.dating_pair_code(public.dating_phone_hmac_for_user(p_a),
                                                               public.dating_phone_hmac_for_user(p_b)));
$$;
-- The person's live restrictions, 'type/source/category/appealable', sorted.
CREATE FUNCTION pg_temp.held(p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce(string_agg(r.restriction_type || '/' || r.source || '/' || coalesce(r.category, '-') || '/' || r.appealable,
                             ' ' ORDER BY r.restriction_type), '')
    FROM public.dating_account_restrictions AS r
   WHERE r.user_id = p AND r.lifted_at IS NULL AND (r.ends_at IS NULL OR r.ends_at > now());
$$;
-- The full deletion path: prepare twice (delete-account retries), as the
-- service role, then Auth's delete.
CREATE FUNCTION pg_temp.delete_account(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.prepare_account_deletion(p);
  PERFORM public.prepare_account_deletion(p);
  RESET ROLE;
  DELETE FROM auth.users WHERE id = p;
END $$;

-- =====================================================================
-- A. (§3.7, §6.2, §7.2 S8) The 14 categories and their priorities; a
--    report's answer, its row (the match, the target and both numbers'
--    codes, the clock, the case), its evidence (the last 50 messages,
--    encrypted); invalid input; who may report and for how long (a match
--    open or ended within 30 days; a phone that isn't checked may report:
--    a safety write, as Block); a replay; the day's limit of 10.
-- =====================================================================
DO $a$
DECLARE
  v_a constant uuid := pg_temp.ready('01');
  v_b constant uuid := pg_temp.man('02');
  v_c constant uuid := pg_temp.man('03');
  v_d constant uuid := pg_temp.ready('04');
  v_e constant uuid := pg_temp.man('05');
  v_m uuid;
  v_old uuid;
  v_de uuid;
  v jsonb;
  v_again jsonb;
  v_key text := pg_temp.key('a-replay');
  v_r public.dating_reports;
  v_snap jsonb;
  v_n bigint := pg_temp.metric('dating.report.harassment');
  v_got text;
  i int;
BEGIN
  IF (SELECT string_agg(c || '=' || private.dating_report_priority(c), ' ' ORDER BY ord)
        FROM unnest(ARRAY['underage_risk', 'csam', 'child_safety', 'threat_to_life', 'sextortion', 'romance_scam', 'threats',
                          'entrapment', 'harassment', 'explicit_content', 'impersonation', 'hiding_relationship', 'spam',
                          'other']) WITH ORDINALITY AS x(c, ord))
     IS DISTINCT FROM 'underage_risk=P0 csam=P0 child_safety=P0 threat_to_life=P0 sextortion=P1 romance_scam=P1 threats=P1 '
                      'entrapment=P1 harassment=P2 explicit_content=P2 impersonation=P2 hiding_relationship=P2 spam=P3 other=P3'
     OR private.dating_report_priority('safety_concern') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the categories and priorities are not §3.7''s';
  END IF;
  -- The clock: four staffed hours for P0 (08:00-22:00 GMT), never past 24.
  IF private.dating_report_sla_due('P0', '2026-12-01 09:00+00') IS DISTINCT FROM '2026-12-01 13:00+00'::timestamptz
     OR private.dating_report_sla_due('P0', '2026-12-01 20:00+00') IS DISTINCT FROM '2026-12-02 10:00+00'::timestamptz
     OR private.dating_report_sla_due('P0', '2026-12-01 23:00+00') IS DISTINCT FROM '2026-12-02 12:00+00'::timestamptz
     OR private.dating_report_sla_due('P0', '2026-12-01 03:00+00') IS DISTINCT FROM '2026-12-01 12:00+00'::timestamptz
     OR private.dating_report_sla_due('P1', '2026-12-01 03:00+00') IS DISTINCT FROM '2026-12-02 03:00+00'::timestamptz
     OR private.dating_report_sla_due('P2', '2026-12-01 03:00+00') IS DISTINCT FROM '2026-12-03 03:00+00'::timestamptz
     OR private.dating_report_sla_due('P3', '2026-12-01 03:00+00') IS DISTINCT FROM '2026-12-04 03:00+00'::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the review clock is not §6.2''s';
  END IF;

  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.say(v_m, v_b, 'w7-first-five', 5);
  PERFORM pg_temp.say(v_m, v_a, 'hello from a', 25);
  PERFORM pg_temp.say(v_m, v_b, 'w7-evidence-marker', 25);
  v := pg_temp.report(v_a, '01', v_m, 'harassment', false, '  He kept writing.  ');
  IF v IS DISTINCT FROM '{"ok": true, "review": "testing", "sla_hours": 48}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report read % (ok, testing, 48 hours)', v;
  END IF;
  SELECT * INTO v_r FROM public.dating_reports WHERE reporter_user_id = v_a AND match_id = v_m;
  IF v_r.category <> 'harassment' OR v_r.priority <> 'P2' OR v_r.details IS DISTINCT FROM 'He kept writing.'
     OR v_r.target_user_id IS DISTINCT FROM v_b OR v_r.target_phone_hmac IS DISTINCT FROM public.dating_phone_hmac_for_user(v_b)
     OR v_r.reporter_phone_hmac IS DISTINCT FROM public.dating_phone_hmac_for_user(v_a)
     OR v_r.state <> 'open' OR v_r.case_id IS NULL OR v_r.introduction_id IS NOT NULL
     OR v_r.sla_due_at NOT BETWEEN now() + interval '47 hours 59 minutes' AND now() + interval '48 hours 1 minute' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the report row is wrong: %', to_jsonb(v_r) - 'details';
  END IF;
  -- Evidence: the last 50 of 55, both sides, oldest first, encrypted.
  IF (SELECT message_count FROM public.dating_report_evidence WHERE report_id = v_r.id) IS DISTINCT FROM 50
     OR (SELECT position('w7-evidence-marker' IN encode(snapshot_enc, 'escape')) FROM public.dating_report_evidence
          WHERE report_id = v_r.id) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the evidence is not 50 encrypted messages';
  END IF;
  v_snap := private.dating_field_decrypt((SELECT snapshot_enc FROM public.dating_report_evidence WHERE report_id = v_r.id));
  IF jsonb_array_length(v_snap -> 'messages') <> 50
     OR v_snap #>> '{messages,0,text}' IS DISTINCT FROM 'hello from a 1'
     OR v_snap #>> '{messages,0,from}' IS DISTINCT FROM 'reporter'
     OR v_snap #>> '{messages,49,from}' IS DISTINCT FROM 'reported'
     OR v_snap #>> '{messages,49,text}' IS DISTINCT FROM 'w7-evidence-marker 25'
     OR (SELECT count(*) FROM jsonb_array_elements(v_snap -> 'messages') AS e WHERE e ->> 'text' LIKE 'w7-first-five%') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the evidence is not the last 50 messages, both sides: %', v_snap #> '{messages,0}';
  END IF;
  IF pg_temp.metric('dating.report.harassment') IS DISTINCT FROM v_n + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the report was not counted under its category';
  END IF;
  -- Invalid input names nothing; a non-member reads report_unavailable.
  v_got := concat_ws(' ',
    pg_temp.report(v_a, '01', v_m, 'safety_concern') ->> 'reason',
    pg_temp.report(v_a, '01', v_m, 'spam', false, repeat('x', 501)) ->> 'reason',
    pg_temp.report(v_a, '01', NULL, 'spam') ->> 'reason',
    pg_temp.j(v_a, '01', format('SELECT public.report_dating_match(''short'', %L, ''spam'', NULL, false)', v_m)) ->> 'reason',
    pg_temp.j(v_a, '01', format('SELECT public.report_dating_match(%L, %L, ''spam'', NULL, NULL)', pg_temp.key('n'), v_m)) ->> 'reason',
    pg_temp.report(v_c, '03', v_m, 'spam') ->> 'reason',
    pg_temp.report(v_c, '03', gen_random_uuid(), 'spam') ->> 'reason');
  IF v_got IS DISTINCT FROM 'invalid invalid invalid invalid invalid report_unavailable report_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: invalid input or a stranger read %', v_got;
  END IF;
  -- A replay answers the same and files nothing more.
  -- (Every call that writes is its own statement: an IF's OR has no order.)
  v := pg_temp.j(v_a, '01', format('SELECT public.report_dating_match(%L, %L, ''spam'', NULL, false)', v_key, v_m));
  v_again := pg_temp.j(v_a, '01', format('SELECT public.report_dating_match(%L, %L, ''spam'', NULL, false)', v_key, v_m));
  IF v IS DISTINCT FROM v_again OR (v ->> 'sla_hours') IS DISTINCT FROM '72'
     OR (SELECT count(*) FROM public.dating_reports WHERE reporter_user_id = v_a AND category = 'spam') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay filed a second report or answered differently';
  END IF;
  -- An ended match within its 30 days may be reported; past them, not.
  -- A phone that isn't checked may report (no header at all).
  UPDATE public.dating_matches SET state = 'unmatched', closed_reason = 'unmatched', closed_at = now() - interval '29 days',
         evidence_until = now() + interval '1 day' WHERE id = v_m;
  v_got := pg_temp.call(v_a, NULL, format('SELECT public.report_dating_match(%L, %L, ''other'', NULL, false) ->> ''ok''',
                                          pg_temp.key('a-nophone'), v_m));
  v_old := pg_temp.match(v_a, v_c);
  UPDATE public.dating_matches SET state = 'unmatched', closed_reason = 'unmatched', closed_at = now() - interval '31 days',
         evidence_until = now() - interval '1 day' WHERE id = v_old;
  v := pg_temp.report(v_a, '01', v_old, 'other');
  IF v_got IS DISTINCT FROM 'true' OR v ->> 'reason' IS DISTINCT FROM 'report_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 30-day window (or the phoneless report) read %', v_got;
  END IF;
  -- 10 a day (the existing limit).
  v_de := pg_temp.match(v_d, v_e);
  FOR i IN 1..10 LOOP
    IF (pg_temp.report(v_d, '04', v_de, 'spam') ->> 'ok') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: report % of the day was refused', i;
    END IF;
  END LOOP;
  IF pg_temp.report(v_d, '04', v_de, 'spam') ->> 'reason' IS DISTINCT FROM 'rate_limited' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 11th report of the day was not rate_limited';
  END IF;
  -- Without the field key the report stands, without evidence, counted.
  v_got := pg_temp.probe(ARRAY[$p$SELECT set_config('app.settings.dating_field_key', '', true)$p$],
    format($p$SELECT (pg_temp.report(%L, '05', %L, 'threats') ->> 'ok') || '/'
                     || (SELECT count(*) FROM public.dating_report_evidence AS e JOIN public.dating_reports AS r ON r.id = e.report_id
                          WHERE r.reporter_user_id = %L AND r.category = 'threats') || '/'
                     || pg_temp.metric('dating.report.evidence_unavailable')$p$, v_e, v_de, v_e));
  IF v_got IS DISTINCT FROM 'true/0/' || (pg_temp.metric('dating.report.evidence_unavailable') + 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the field key a report read % (true/0/counted)', v_got;
  END IF;
END $a$;

-- =====================================================================
-- B. (§6.2, §7.5 mutant 13) The automatic steps, never a ban: one P0
--    report closes the reporter's match (reported, 30-day window, never
--    introduced again) and removes the person from new generation, but
--    holds nothing; P1 removes from generation; P2's step is the
--    reporter's own block; impersonation takes no step beyond it; P3
--    takes none. A card on Today can be reported too.
-- =====================================================================
DO $b$
DECLARE
  v_a constant uuid := pg_temp.ready('10');
  v_b constant uuid := pg_temp.man('11');
  v_c constant uuid := pg_temp.ready('12');
  v_d constant uuid := pg_temp.man('13');
  v_e constant uuid := pg_temp.ready('14');
  v_f constant uuid := pg_temp.man('15');
  v_g constant uuid := pg_temp.ready('16');
  v_h constant uuid := pg_temp.man('17');
  v_k constant uuid := pg_temp.man('18');
  v_m uuid;
  v_m2 uuid;
  v_m3 uuid;
  v_m4 uuid;
  v_m5 uuid;
  v_i uuid;
  v jsonb;
  v_got text;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  v := pg_temp.report(v_a, '10', v_m, 'threat_to_life');
  IF (v ->> 'ok') IS DISTINCT FROM 'true' OR (v ->> 'sla_hours')::int NOT BETWEEN 1 AND 24 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a P0 report read %', v;
  END IF;
  IF (SELECT state || '/' || closed_reason || '/' || (evidence_until > now() + interval '29 days')::text
        FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'closed/reported/true'
     OR NOT pg_temp.marked(v_a, v_b)
     OR NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = v_b AND match_id = v_m) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a P0 report did not close the reporter''s match for good, or the other was not told';
  END IF;
  IF pg_temp.held(v_b) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one P0 report placed a hold (§6.2: only when corroborated): %', pg_temp.held(v_b);
  END IF;
  IF NOT pg_temp.excluded(v_b) OR NOT public.dating_candidate_is_current(v_b) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a P0 report did not remove the person from new generation only (excluded %, current %)',
      pg_temp.excluded(v_b), public.dating_candidate_is_current(v_b);
  END IF;
  IF (SELECT c.kind || '/' || c.priority || '/' || c.state FROM public.dating_moderation_cases AS c
       JOIN public.dating_reports AS r ON r.case_id = c.id WHERE r.match_id = v_m) IS DISTINCT FROM 'report/P0/open' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the P0 report has no open P0 case';
  END IF;
  -- P1: removed from generation; the match stays (no block asked).
  v_m2 := pg_temp.match(v_c, v_d);
  PERFORM pg_temp.report(v_c, '12', v_m2, 'romance_scam');
  IF (SELECT state FROM public.dating_matches WHERE id = v_m2) <> 'active' OR NOT pg_temp.excluded(v_d) OR pg_temp.held(v_d) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a P1 report did more or less than remove the person from generation';
  END IF;
  -- P2 with the block (the toggle's default): blocked, nothing else.
  v_m3 := pg_temp.match(v_e, v_f);
  PERFORM pg_temp.report(v_e, '14', v_m3, 'harassment', true);
  IF (SELECT state || '/' || closed_reason FROM public.dating_matches WHERE id = v_m3) IS DISTINCT FROM 'blocked/blocked'
     OR NOT EXISTS (SELECT 1 FROM public.dating_blocks WHERE blocker_user_id = v_e AND blocked_user_id = v_f)
     OR pg_temp.excluded(v_f) OR pg_temp.held(v_f) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a P2 report with the block did not block only';
  END IF;
  -- §6.2: impersonation takes no automatic step beyond the reporter's
  -- block; P3 takes none.
  v_m4 := pg_temp.match(v_g, v_h);
  PERFORM pg_temp.report(v_g, '16', v_m4, 'impersonation', true);
  v_m5 := pg_temp.match(v_g, v_k);
  PERFORM pg_temp.report(v_g, '16', v_m5, 'spam');
  IF pg_temp.excluded(v_h) OR pg_temp.held(v_h) <> '' OR (SELECT state FROM public.dating_matches WHERE id = v_m4) <> 'blocked'
     OR (SELECT auto_step FROM public.dating_reports WHERE match_id = v_m4)
     OR pg_temp.excluded(v_k) OR (SELECT state FROM public.dating_matches WHERE id = v_m5) <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: impersonation or spam took an automatic step';
  END IF;
  -- A card on Today: a P0 report without the block takes the card away
  -- and the pair is never introduced again; no evidence (no messages).
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version,
                                           visible_from_low, visible_from_high, expires_at)
  VALUES (public.dating_pair_key(v_c, v_k), least(v_c, v_k), greatest(v_c, v_k), 'presented', 'introductions_v2',
          now() - interval '1 hour', now() - interval '1 hour', now() + interval '6 days')
  RETURNING id INTO v_i;
  v := pg_temp.j(v_c, '12', format('SELECT public.report_dating_introduction(%L, %L, ''child_safety'', NULL, false)',
                                   pg_temp.key('b-card'), v_i));
  v_got := pg_temp.j(v_f, '15', format('SELECT public.report_dating_introduction(%L, %L, ''spam'', NULL, false)',
                                       pg_temp.key('b-card2'), v_i)) ->> 'reason';
  IF (v ->> 'ok') IS DISTINCT FROM 'true' OR (SELECT state FROM public.dating_introductions WHERE id = v_i) <> 'invalidated'
     OR NOT pg_temp.marked(v_c, v_k) OR NOT pg_temp.excluded(v_k)
     OR EXISTS (SELECT 1 FROM public.dating_report_evidence AS e JOIN public.dating_reports AS r ON r.id = e.report_id
                 WHERE r.introduction_id = v_i)
     OR v_got IS DISTINCT FROM 'report_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a card report read % (a stranger: %)', v, v_got;
  END IF;
END $b$;

-- =====================================================================
-- C. (§6.2, §6.3, §7.2 S2, S11, §7.5 mutant 14) Corroboration and
--    credibility: two independent P0 reports hold the person (matches
--    stay open, no sending, hidden from Today); the same reporter twice,
--    a reporter under 72 hours, two reporters on one phone, or a
--    reporter whose own messages tripped sexual_pressure or
--    financial_request, never count; underage_risk with the person's
--    tier-3 age_signal (or a second underage_risk) is an age review that
--    closes every match; a CSAM hit holds at once.
-- =====================================================================
DO $c$
DECLARE
  v_t constant uuid := pg_temp.man('20');
  v_r1 constant uuid := pg_temp.ready('21');
  v_r2 constant uuid := pg_temp.ready('22');
  v_r3 constant uuid := pg_temp.ready('23');
  v_t2 constant uuid := pg_temp.man('24');
  v_young constant uuid := pg_temp.ready('25', '{"days": 2}');
  v_twin constant uuid := pg_temp.ready('26', '{"device": "21"}');
  v_t3 constant uuid := pg_temp.man('27');
  v_trip constant uuid := pg_temp.ready('28');
  v_r5 constant uuid := pg_temp.ready('29');
  v_t4 constant uuid := pg_temp.man('30');
  v_r6 constant uuid := pg_temp.ready('31');
  v_r7 constant uuid := pg_temp.ready('32');
  v_t5 constant uuid := pg_temp.man('33');
  v_r8 constant uuid := pg_temp.ready('34');
  v_m1 uuid;
  v_m2 uuid;
  v_m3 uuid;
  v_n bigint := pg_temp.metric('dating.hold.p0');
  v_case uuid;
  v_got text;
BEGIN
  v_m1 := pg_temp.match(v_t, v_r1);
  v_m2 := pg_temp.match(v_t, v_r2);
  v_m3 := pg_temp.match(v_t, v_r3);
  PERFORM pg_temp.report(v_r1, '21', v_m1, 'csam');
  IF pg_temp.held(v_t) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one P0 report held the person';
  END IF;
  PERFORM pg_temp.report(v_r2, '22', v_m2, 'threat_to_life');
  SELECT case_id INTO v_case FROM public.dating_reports WHERE match_id = v_m2;
  IF pg_temp.held(v_t) IS DISTINCT FROM 'moderation_hold/report/threat_to_life/false'
     OR (SELECT case_id FROM public.dating_account_restrictions WHERE user_id = v_t) IS DISTINCT FROM v_case
     OR pg_temp.metric('dating.hold.p0') IS DISTINCT FROM v_n + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two independent P0 reports did not hold (%)', pg_temp.held(v_t);
  END IF;
  -- §6.3: a hold keeps the other match open, stops the person's messages,
  -- and hides them.
  v_got := pg_temp.j(v_t, '20', format('SELECT public.send_dating_message(%L, %L, ''hello'')', pg_temp.key('c-send'), v_m3)) ->> 'ok';
  IF (SELECT state FROM public.dating_matches WHERE id = v_m3) <> 'active'
     OR v_got IS DISTINCT FROM 'false'
     OR public.dating_candidate_is_current(v_t)
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_t) <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the hold closed a match, let the person send, or left them on Today';
  END IF;
  IF (SELECT count(*) FROM public.dating_case_matches WHERE case_id = v_case) <> 2
     OR (SELECT count(*) FROM public.dating_reports WHERE case_id = v_case) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the two reports are not one case linking both matches';
  END IF;
  -- The same reporter twice, a new account, a second account on the first
  -- reporter's phone: none corroborates.
  PERFORM pg_temp.report(v_r1, '21', pg_temp.match(v_t2, v_r1), 'csam');
  -- The same account on a new number, its phone forgotten (only the
  -- account says it is the same reporter).
  UPDATE auth.users SET phone = '15559719921' WHERE id = v_r1;
  DELETE FROM public.dating_trusted_devices WHERE user_id = v_r1;
  PERFORM pg_temp.report(v_r1, '21', (SELECT id FROM public.dating_matches WHERE user_low_id = least(v_t2, v_r1)
                                        AND user_high_id = greatest(v_t2, v_r1)), 'child_safety');
  INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
  VALUES (v_r1, encode(extensions.digest(pg_temp.dev('21'), 'sha256'), 'hex'), now(), now());
  PERFORM pg_temp.report(v_young, '25', pg_temp.match(v_t2, v_young), 'csam');
  PERFORM pg_temp.report(v_twin, '26', pg_temp.match(v_t2, v_twin), 'csam');
  IF pg_temp.held(v_t2) <> '' OR (SELECT counts_for_corroboration FROM public.dating_reports WHERE reporter_user_id = v_young) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeat, a new account or one phone corroborated a hold: %', pg_temp.held(v_t2);
  END IF;
  -- A reporter whose own messages to the person tripped financial_request
  -- in that match: no automatic step, never counts (S11); the case shows
  -- the family.
  v_m1 := pg_temp.match(v_t3, v_trip);
  INSERT INTO public.dating_safety_events (match_id, at_risk_user_id, sender_user_id, rule_id, family, tier, config_version,
                                           source_event_key)
  VALUES (v_m1, v_t3, v_trip, 'financial_request:momo', 'financial_request', 2, 'dating_chat_v1', 'w7-c-trip');
  PERFORM pg_temp.report(v_trip, '28', v_m1, 'underage_risk');
  IF (SELECT reporter_tripped_family || '/' || counts_for_corroboration || '/' || auto_step FROM public.dating_reports
       WHERE reporter_user_id = v_trip) IS DISTINCT FROM 'financial_request/false/false'
     OR pg_temp.excluded(v_t3) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a tripped reporter''s report took a step or counts';
  END IF;
  PERFORM pg_temp.report(v_r5, '29', pg_temp.match(v_t3, v_r5), 'underage_risk');
  IF pg_temp.held(v_t3) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a tripped reporter''s report corroborated a hold (mutant 14): %', pg_temp.held(v_t3);
  END IF;
  -- underage_risk and the person's own tier-3 age_signal in that match: an
  -- age review, every match closed as age_review (S2).
  v_m1 := pg_temp.match(v_t4, v_r6);
  v_m2 := pg_temp.match(v_t4, v_r7);
  INSERT INTO public.dating_safety_events (match_id, at_risk_user_id, sender_user_id, rule_id, family, tier, config_version,
                                           source_event_key)
  VALUES (v_m1, v_r6, v_t4, 'age_signal:shs', 'age_signal', 3, 'dating_chat_v1', 'w7-c-age');
  PERFORM pg_temp.report(v_r6, '31', v_m1, 'underage_risk');
  IF pg_temp.held(v_t4) IS DISTINCT FROM 'age_review/report/underage_risk/false'
     OR (SELECT count(*) FROM public.dating_matches WHERE id IN (v_m1, v_m2) AND closed_reason = 'age_review') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: underage_risk with an age signal read % and did not close every match as age_review',
      pg_temp.held(v_t4);
  END IF;
  -- A CSAM hit holds at once (source csam_hash), matches stay open.
  v_m1 := pg_temp.match(v_t5, v_r8);
  PERFORM public.record_dating_csam_hold(v_t5);
  IF pg_temp.held(v_t5) IS DISTINCT FROM 'moderation_hold/csam_hash/csam/false'
     OR (SELECT state FROM public.dating_matches WHERE id = v_m1) <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a CSAM hit read % (a hold at once, matches open)', pg_temp.held(v_t5);
  END IF;
  -- One writer: a live restriction of a type is never doubled; but a hold
  -- is never folded into a CSAM hold (W7c Task 8 fix round 2, N-2): beside
  -- one it gets its own row, which a second placing then reuses.
  v_got := private.dating_place_restriction(v_t5, 'moderation_hold', 'threats', 'report', NULL, NULL, NULL, false)::text;
  v_got := v_got || '/' || private.dating_place_restriction(v_t5, 'moderation_hold', 'threats', 'report', NULL, NULL, NULL, false)::text;
  IF v_got IS DISTINCT FROM (SELECT r.id || '/' || r.id FROM public.dating_account_restrictions AS r WHERE r.user_id = v_t5 AND r.source = 'report')
     OR (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = v_t5 AND lifted_at IS NULL) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second hold was placed, or a hold was folded into a CSAM hold: %', v_got;
  END IF;
  -- (fix round 3, N2-1) and within its class: a CSAM report's hold is
  -- neither the hash hit's nor the threats one; a second reuses it.
  v_got := private.dating_place_restriction(v_t5, 'moderation_hold', 'csam', 'report', NULL, NULL, NULL, false)::text;
  v_got := v_got || '/' || private.dating_place_restriction(v_t5, 'moderation_hold', 'csam', 'report', NULL, NULL, NULL, false)::text;
  IF v_got IS DISTINCT FROM (SELECT string_agg(r.id || '/' || r.id, ' ') FROM public.dating_account_restrictions AS r
                              WHERE r.user_id = v_t5 AND r.source = 'report' AND r.category = 'csam')
     OR (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = v_t5 AND lifted_at IS NULL) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a CSAM report''s hold was doubled or folded into another class''s hold: %', v_got;
  END IF;
END $c$;

-- =====================================================================
-- D. (§4.3, §4.8, W6 M-16, R-52) One open report case per person: a
--    later report joins it (its priority and clock the most urgent), and
--    every match it comes from is linked and held from the purge while it
--    is open, released once it closes; a signal case links a later hit's
--    match; a report after the other's deletion keeps the number's code,
--    and the next account on that number is out of new generation while
--    the case is open; its block is kept by number.
-- =====================================================================
DO $d$
DECLARE
  v_t constant uuid := pg_temp.man('40');
  v_a constant uuid := pg_temp.ready('41');
  v_b constant uuid := pg_temp.ready('42');
  v_s constant uuid := pg_temp.man('43');
  v_x constant uuid := pg_temp.ready('44');
  v_y constant uuid := pg_temp.ready('45');
  v_g constant uuid := pg_temp.man('46');
  v_h constant uuid := pg_temp.ready('47');
  v_g2 uuid;
  v_m1 uuid;
  v_m2 uuid;
  v_case uuid;
  v_hold_case uuid;
  v_hmac text;
  v jsonb;
BEGIN
  v_m1 := pg_temp.match(v_t, v_a);
  v_m2 := pg_temp.match(v_t, v_b);
  PERFORM pg_temp.report(v_a, '41', v_m1, 'spam');
  PERFORM pg_temp.report(v_b, '42', v_m2, 'sextortion');
  SELECT id INTO v_case FROM public.dating_moderation_cases WHERE kind = 'report' AND target_user_id = v_t;
  IF (SELECT count(*) FROM public.dating_moderation_cases WHERE kind = 'report' AND target_user_id = v_t) <> 1
     OR (SELECT priority FROM public.dating_moderation_cases WHERE id = v_case) <> 'P1'
     OR (SELECT sla_due_at FROM public.dating_moderation_cases WHERE id = v_case)
        IS DISTINCT FROM (SELECT min(sla_due_at) FROM public.dating_reports WHERE case_id = v_case)
     OR (SELECT count(*) FROM public.dating_case_matches WHERE case_id = v_case) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two reports about one person are not one P1 case linking both matches';
  END IF;
  -- The second match (not the case's own) ends past its window: held by
  -- the link while the case is open, purged once it is closed.
  UPDATE public.dating_matches SET state = 'unmatched', closed_reason = 'unmatched', closed_at = now() - interval '40 days',
         evidence_until = now() - interval '10 days' WHERE id = v_m2;
  PERFORM public.purge_dating_retention(now());
  IF NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_m2) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge deleted a match an open case links (W6 M-16)';
  END IF;
  IF private.dating_close_case(v_case, v_a, 'dismissed') IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the case would not close';
  END IF;
  PERFORM public.purge_dating_retention(now());
  IF EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_m2) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed case still holds its linked match';
  END IF;
  -- A signal case links the match of a later hit (W6 M-16).
  v_m1 := pg_temp.match(v_s, v_x);
  v_m2 := pg_temp.match(v_s, v_y);
  PERFORM private.dating_open_chat_case(v_s, v_m1, 'chat_financial_request', 'P1');
  PERFORM private.dating_open_chat_case(v_s, v_m2, 'chat_financial_request', 'P1');
  IF (SELECT count(*) FROM public.dating_case_matches AS l JOIN public.dating_moderation_cases AS c ON c.id = l.case_id
       WHERE c.target_user_id = v_s AND c.signal_kind = 'chat_financial_request') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a later hit''s match was not linked to the open signal case';
  END IF;
  -- The other's account is deleted: the match keeps their number's code,
  -- the report names it, and the next account on that number is out of
  -- new generation while the case is open. The block is kept by number.
  v_m1 := pg_temp.match(v_g, v_h);
  v_hmac := public.dating_phone_hmac_for_user(v_g);
  PERFORM pg_temp.delete_account(v_g);
  IF (SELECT CASE WHEN user_low_id IS NULL THEN low_phone_hmac ELSE high_phone_hmac END FROM public.dating_matches WHERE id = v_m1)
       IS DISTINCT FROM v_hmac THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the deleted side''s number''s code is not on the match';
  END IF;
  v := pg_temp.report(v_h, '47', v_m1, 'threats', true);
  IF (v ->> 'ok') IS DISTINCT FROM 'true'
     OR (SELECT target_user_id IS NULL AND target_phone_hmac = v_hmac FROM public.dating_reports WHERE match_id = v_m1) IS NOT TRUE
     OR NOT EXISTS (SELECT 1 FROM public.dating_block_hmacs
                     WHERE blocker_hmac = public.dating_phone_hmac_for_user(v_h) AND blocked_hmac = v_hmac) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report after the other''s deletion lost the number or its block';
  END IF;
  v_g2 := pg_temp.man('48', '{"phone": "46"}');
  IF NOT pg_temp.excluded(v_g2) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new account on the reported number is in new generation while the case is open';
  END IF;
  -- §4.8 (W6 T8 carry): reports go at 2 years, unless their case is still
  -- open; evidence 180 days after its case closed, unless a restriction
  -- from that case is still live.
  v_m1 := pg_temp.match(v_x, v_y);
  PERFORM pg_temp.say(v_m1, v_y, 'w7-d-purge', 1);
  PERFORM pg_temp.report(v_x, '44', v_m1, 'spam');
  PERFORM pg_temp.report(v_y, '45', v_m1, 'harassment');
  SELECT case_id INTO v_case FROM public.dating_reports WHERE reporter_user_id = v_x AND match_id = v_m1;
  PERFORM private.dating_close_case(v_case, v_x, 'dismissed');
  UPDATE public.dating_moderation_cases SET decided_at = now() - interval '181 days' WHERE id = v_case;
  UPDATE public.dating_reports SET created_at = now() - interval '2 years 1 day' WHERE case_id = v_case;
  SELECT case_id INTO v_hold_case FROM public.dating_reports WHERE reporter_user_id = v_y AND match_id = v_m1;
  PERFORM private.dating_close_case(v_hold_case, v_y, 'restricted');
  UPDATE public.dating_moderation_cases SET decided_at = now() - interval '200 days' WHERE id = v_hold_case;
  PERFORM private.dating_place_restriction(v_x, 'suspended', 'harassment', 'moderator', v_hold_case, v_y, NULL, true);
  PERFORM public.purge_dating_retention(now());
  IF EXISTS (SELECT 1 FROM public.dating_reports WHERE case_id = v_case)
     OR NOT EXISTS (SELECT 1 FROM public.dating_reports WHERE case_id = v_hold_case)
     OR NOT EXISTS (SELECT 1 FROM public.dating_report_evidence AS e JOIN public.dating_reports AS r ON r.id = e.report_id
                     WHERE r.case_id = v_hold_case) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge kept a 2-year report, or took evidence a live restriction needs';
  END IF;
  UPDATE public.dating_account_restrictions SET lifted_at = now() WHERE case_id = v_hold_case;
  PERFORM public.purge_dating_retention(now());
  IF EXISTS (SELECT 1 FROM public.dating_report_evidence AS e JOIN public.dating_reports AS r ON r.id = e.report_id
              WHERE r.case_id = v_hold_case)
     OR NOT EXISTS (SELECT 1 FROM public.dating_reports WHERE case_id = v_hold_case) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: evidence outlived its closed case by 180 days, or the report went with it';
  END IF;
  UPDATE public.dating_reports SET created_at = now() - interval '2 years 1 day' WHERE reporter_user_id = v_h;
  PERFORM public.purge_dating_retention(now());
  IF NOT EXISTS (SELECT 1 FROM public.dating_reports WHERE reporter_user_id = v_h) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge deleted a report whose case is still open';
  END IF;
END $d$;

-- =====================================================================
-- D2. (Fix round 1: I-1, M-1, M-2, M-3, M-6, M-7, M-8, M-11) A reporter's
--     own trip that lands after the report stops it counting (the worker
--     judges it again), and corroboration judges the other report again;
--     a dismissed or lower-tier event never counts; a second account on
--     the reporter's number never corroborates; a failed "Also block" is
--     said; the report purge keeps what a live restriction or record
--     still needs; a card and a number-blocked chat can be reported for
--     30 days, not for ever; a hold's one writer takes the person's setup
--     lock (the CSAM paths' lock), so a hit and a report never both hold.
--     (Fix round 2, N-1) A report takes the target's setup lock with the
--     reporter's at its start, from a chat and from a card (the order the
--     race script's hold cases need).
-- =====================================================================
-- The safety worker's completion of one message from [p_from] in [p_m]
-- with one hit of [p_family] (its config tier and first term).
CREATE FUNCTION pg_temp.trip(p_m uuid, p_from uuid, p_family text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_msg uuid;
  v_cfg constant jsonb := (SELECT c.config FROM public.dating_safety_configs AS c WHERE c.version = 'dating_chat_v1');
BEGIN
  INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, body, body_masked, mask_version, idempotency_key,
                                      created_at)
  SELECT p_m, CASE WHEN m.user_low_id = p_from THEN 'low' ELSE 'high' END, p_from, 'w7-trip', 'w7-trip', 1, pg_temp.key('trip'),
         clock_timestamp()
    FROM public.dating_matches AS m WHERE m.id = p_m
  RETURNING id INTO v_msg;
  INSERT INTO public.dating_message_safety_outbox (message_id, state, attempts, processing_started_at)
  VALUES (v_msg, 'processing', 1, now())
  ON CONFLICT (message_id) DO UPDATE SET state = 'processing', attempts = 1, processing_started_at = now();
  RETURN public.complete_dating_safety_job(v_msg, 'dating_chat_v1', jsonb_build_array(jsonb_build_object(
    'family', p_family, 'tier', (v_cfg #>> ARRAY['families', p_family, 'tier'])::int,
    'rule_id', p_family || ':' || (v_cfg #>> ARRAY['families', p_family, 'terms', '0']))));
END $$;
-- This session holds [p]'s setup lock (private.dating_lock_setup's key).
CREATE FUNCTION pg_temp.setup_locked(p uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_locks AS l
                  WHERE l.locktype = 'advisory' AND l.pid = pg_backend_pid() AND l.granted AND l.objsubid = 2
                    AND l.classid::text::bigint = (hashtext('dating_setup')::bigint + 4294967296) % 4294967296
                    AND l.objid::text::bigint = (hashtext(p::text)::bigint + 4294967296) % 4294967296);
$$;
DO $d2$
DECLARE
  v_t constant uuid := pg_temp.man('49');
  v_r constant uuid := pg_temp.ready('50');
  v_r2 constant uuid := pg_temp.ready('51');
  v_t2 constant uuid := pg_temp.man('52');
  v_s constant uuid := pg_temp.ready('53');
  v_s2 constant uuid := pg_temp.ready('54');
  v_t3 constant uuid := pg_temp.man('55');
  v_q constant uuid := pg_temp.ready('56');
  v_t4 constant uuid := pg_temp.man('58');
  v_p constant uuid := pg_temp.ready('59');
  v_q2 uuid;
  v_m uuid;
  v_m4 uuid;
  v_case uuid;
  v_i constant uuid := gen_random_uuid();
  v jsonb;
  v_got text;
  v_ev constant text := 'INSERT INTO public.dating_safety_events (match_id, at_risk_user_id, sender_user_id, rule_id, family, tier, '
                        'config_version, source_event_key, dismissed_at) VALUES (%L, %L, %L, %L, %L, %s, ''dating_chat_v1'', %L, %s)';
  v_lim constant text := 'INSERT INTO public.dating_rate_limits (user_id, operation, window_started_at, request_count) '
                         'VALUES (%L, ''block'', now(), 20) ON CONFLICT (user_id, operation) '
                         'DO UPDATE SET window_started_at = now(), request_count = 20';
  v_card constant text := 'INSERT INTO public.dating_introductions (id, pair_key, user_low_id, user_high_id, state, algorithm_version, '
                          'visible_from_low, visible_from_high, expires_at, created_at) VALUES (%L, %L, %L, %L, %L, ''introductions_v2'', '
                          'now() - interval ''40 days'', now() - interval ''40 days'', now() - make_interval(days => %s), '
                          'now() - interval ''40 days'')';
BEGIN
  -- M-11: placing a hold takes the person's setup lock, the lock every
  -- CSAM path holds while it checks for a hold and inserts one.
  v_got := pg_temp.probe(ARRAY[format($p$SELECT private.dating_place_restriction(%L, 'moderation_hold', 'csam', 'report', NULL,
                                                                                   NULL, NULL, false)$p$, v_t4)],
                         format('SELECT pg_temp.setup_locked(%L)', v_t4));
  IF pg_temp.setup_locked(v_t4) OR v_got IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: placing a hold did not take the person''s setup lock (a CSAM hit and a report could both hold)';
  END IF;

  -- I-1: the reporter's own money ask is judged after the report (the
  -- worker's lag): the report stops counting and stepping, says why, and
  -- the person is back in new generation.
  v_m := pg_temp.match(v_t, v_r);
  v_got := pg_temp.setup_locked(v_t)::text;
  PERFORM pg_temp.report(v_r, '50', v_m, 'child_safety');
  v_got := v_got || '/' || pg_temp.setup_locked(v_t)::text || '|'
           || pg_temp.probe(ARRAY[format(v_card, v_i, public.dating_pair_key(v_t4, v_p), least(v_t4, v_p), greatest(v_t4, v_p), 'presented', -6),
                                  format($p$SELECT pg_temp.j(%L, '59', format('SELECT public.report_dating_introduction(%%L, %%L, ''spam'', NULL, false)',
                                                             pg_temp.key('d2-lock'), %L))$p$, v_p, v_i)],
                            format('SELECT pg_temp.setup_locked(%L)', v_t4));
  IF v_got IS DISTINCT FROM 'false/true|true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report did not take the target''s setup lock at its start (chat/card: %)', v_got;
  END IF;
  IF NOT pg_temp.excluded(v_t) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: (setup) the P0 report did not remove the person from new generation';
  END IF;
  v := pg_temp.trip(v_m, v_r, 'financial_request');
  IF (v ->> 'events') IS DISTINCT FROM '1'
     OR (SELECT reporter_tripped_family || '/' || counts_for_corroboration || '/' || auto_step FROM public.dating_reports
          WHERE reporter_user_id = v_r AND match_id = v_m) IS DISTINCT FROM 'financial_request/false/false'
     OR pg_temp.excluded(v_t) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reporter''s trip that landed after the report left it counting (%, %)', v,
      (SELECT to_jsonb(r) - 'details' FROM public.dating_reports AS r WHERE reporter_user_id = v_r AND match_id = v_m);
  END IF;
  PERFORM pg_temp.report(v_r2, '51', pg_temp.match(v_t, v_r2), 'csam');
  IF pg_temp.held(v_t) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a late-tripped reporter corroborated a hold: %', pg_temp.held(v_t);
  END IF;
  -- Corroboration judges the other report again (a trip no worker
  -- re-flagged it for).
  v_m := pg_temp.match(v_t2, v_s);
  PERFORM pg_temp.report(v_s, '53', v_m, 'csam');
  EXECUTE format(v_ev, v_m, v_t2, v_s, 'sexual_pressure:w7', 'sexual_pressure', 1, 'w7-d2-late', 'NULL');
  PERFORM pg_temp.report(v_s2, '54', pg_temp.match(v_t2, v_s2), 'threat_to_life');
  IF pg_temp.held(v_t2) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: corroboration counted a report whose reporter has since tripped: %', pg_temp.held(v_t2);
  END IF;

  -- M-3: the reporter deletes the account and reports again from a new
  -- one on the same number (another phone, past 72 hours): the two never
  -- corroborate, though both still count.
  v_m := pg_temp.match(v_t3, v_q);
  PERFORM pg_temp.report(v_q, '56', v_m, 'csam');
  PERFORM pg_temp.delete_account(v_q);
  v_q2 := pg_temp.ready('57', '{"phone": "56"}');
  PERFORM pg_temp.report(v_q2, '57', pg_temp.match(v_t3, v_q2), 'csam');
  SELECT case_id INTO v_case FROM public.dating_reports WHERE reporter_user_id = v_q2;
  IF pg_temp.held(v_t3) <> ''
     OR (SELECT count(*) FROM public.dating_reports WHERE case_id = v_case AND counts_for_corroboration) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two accounts on one number corroborated a hold: %', pg_temp.held(v_t3);
  END IF;

  -- M-6, M-7: an age_signal below tier 3, or one dismissed, is no age
  -- review; a tier-3 one is (the control). A dismissed money ask never
  -- marks the reporter; an undismissed one does (the control).
  v_m4 := pg_temp.match(v_t4, v_p);
  v_got := concat_ws('|',
    pg_temp.probe(ARRAY[format(v_ev, v_m4, v_p, v_t4, 'age_signal:w7', 'age_signal', 2, 'w7-d2-a2', 'NULL'),
                        format($p$SELECT pg_temp.report(%L, '59', %L, 'underage_risk')$p$, v_p, v_m4)],
                  format($p$SELECT coalesce(nullif(pg_temp.held(%L), ''), '-')$p$, v_t4)),
    pg_temp.probe(ARRAY[format(v_ev, v_m4, v_p, v_t4, 'age_signal:w7', 'age_signal', 3, 'w7-d2-a3d', 'now()'),
                        format($p$SELECT pg_temp.report(%L, '59', %L, 'underage_risk')$p$, v_p, v_m4)],
                  format($p$SELECT coalesce(nullif(pg_temp.held(%L), ''), '-')$p$, v_t4)),
    pg_temp.probe(ARRAY[format(v_ev, v_m4, v_p, v_t4, 'age_signal:w7', 'age_signal', 3, 'w7-d2-a3', 'NULL'),
                        format($p$SELECT pg_temp.report(%L, '59', %L, 'underage_risk')$p$, v_p, v_m4)],
                  format($p$SELECT coalesce(nullif(pg_temp.held(%L), ''), '-')$p$, v_t4)),
    pg_temp.probe(ARRAY[format(v_ev, v_m4, v_t4, v_p, 'financial_request:w7', 'financial_request', 2, 'w7-d2-fd', 'now()'),
                        format($p$SELECT pg_temp.report(%L, '59', %L, 'romance_scam')$p$, v_p, v_m4)],
                  format($p$SELECT coalesce(reporter_tripped_family, '-') || '/' || auto_step FROM public.dating_reports
                             WHERE reporter_user_id = %L$p$, v_p)),
    pg_temp.probe(ARRAY[format(v_ev, v_m4, v_t4, v_p, 'financial_request:w7', 'financial_request', 2, 'w7-d2-f', 'NULL'),
                        format($p$SELECT pg_temp.report(%L, '59', %L, 'romance_scam')$p$, v_p, v_m4)],
                  format($p$SELECT coalesce(reporter_tripped_family, '-') || '/' || auto_step FROM public.dating_reports
                             WHERE reporter_user_id = %L$p$, v_p)));
  IF v_got IS DISTINCT FROM '-|-|age_review/report/underage_risk/false|-/true|financial_request/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a lower-tier or dismissed event counted (or a counting one did not): %', v_got;
  END IF;

  -- M-1: "Also block" that does not go through (the day's 20 blocks) is
  -- said ("blocked": false), from a chat and from a card; a block that
  -- does go through says nothing more.
  v_got := concat_ws('|',
    pg_temp.probe(ARRAY[format(v_lim, v_p),
                        format($p$SELECT set_config('w7.ans', pg_temp.report(%L, '59', %L, 'harassment', true)::text, true)$p$, v_p, v_m4)],
                  format($p$SELECT coalesce(current_setting('w7.ans')::jsonb ->> 'blocked', 'absent') || '/'
                                   || (SELECT state FROM public.dating_matches WHERE id = %L)$p$, v_m4)),
    pg_temp.probe(ARRAY[format($p$SELECT set_config('w7.ans', pg_temp.report(%L, '59', %L, 'harassment', true)::text, true)$p$, v_p, v_m4)],
                  format($p$SELECT coalesce(current_setting('w7.ans')::jsonb ->> 'blocked', 'absent') || '/'
                                   || (SELECT state FROM public.dating_matches WHERE id = %L)$p$, v_m4)),
    pg_temp.probe(ARRAY[format(v_lim, v_p),
                        format(v_card, v_i, public.dating_pair_key(v_t4, v_p), least(v_t4, v_p), greatest(v_t4, v_p), 'presented', -6),
                        format($p$SELECT set_config('w7.ans', pg_temp.j(%L, '59', format('SELECT public.report_dating_introduction(%%L, %%L, ''harassment'', NULL, true)',
                                                    pg_temp.key('d2-card'), %L))::text, true)$p$, v_p, v_i)],
                  $p$SELECT coalesce(current_setting('w7.ans')::jsonb ->> 'blocked', 'absent')$p$));
  IF v_got IS DISTINCT FROM 'false/active|absent/blocked|false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed "Also block" read as done (or a done one was flagged): %', v_got;
  END IF;

  -- M-8: a card can be reported for 30 days after its time on Today ends,
  -- not after; a chat only the two numbers' block ended, for 30 days after
  -- the block (in the ended list and to Report), not after.
  v_got := concat_ws('|',
    pg_temp.probe(ARRAY[format(v_card, v_i, public.dating_pair_key(v_t4, v_p), least(v_t4, v_p), greatest(v_t4, v_p), 'expired', 29)],
                  format($p$SELECT coalesce(pg_temp.j(%L, '59', format('SELECT public.report_dating_introduction(%%L, %%L, ''spam'', NULL, false)',
                                                  pg_temp.key('d2-c29'), %L)) ->> 'reason', 'ok')$p$, v_p, v_i)),
    pg_temp.probe(ARRAY[format(v_card, v_i, public.dating_pair_key(v_t4, v_p), least(v_t4, v_p), greatest(v_t4, v_p), 'expired', 31)],
                  format($p$SELECT coalesce(pg_temp.j(%L, '59', format('SELECT public.report_dating_introduction(%%L, %%L, ''spam'', NULL, false)',
                                                  pg_temp.key('d2-c31'), %L)) ->> 'reason', 'ok')$p$, v_p, v_i)),
    pg_temp.probe(ARRAY[format($p$INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac, created_at, purge_after)
                                  VALUES (public.dating_phone_hmac_for_user(%L), public.dating_phone_hmac_for_user(%L),
                                          now() - interval '29 days', now() + interval '1 year')$p$, v_p, v_t4)],
                  format($p$SELECT (pg_temp.j(%L, '59', 'SELECT public.get_my_dating_matches(true)') -> 'ended'
                                    @> jsonb_build_array(jsonb_build_object('match_id', %L::text)))::text || '/'
                                   || coalesce(pg_temp.report(%L, '59', %L, 'spam') ->> 'reason', 'ok')$p$, v_p, v_m4, v_p, v_m4)),
    pg_temp.probe(ARRAY[format($p$INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac, created_at, purge_after)
                                  VALUES (public.dating_phone_hmac_for_user(%L), public.dating_phone_hmac_for_user(%L),
                                          now() - interval '31 days', now() + interval '1 year')$p$, v_p, v_t4)],
                  format($p$SELECT (pg_temp.j(%L, '59', 'SELECT public.get_my_dating_matches(true)') -> 'ended'
                                    @> jsonb_build_array(jsonb_build_object('match_id', %L::text)))::text || '/'
                                   || coalesce(pg_temp.report(%L, '59', %L, 'spam') ->> 'reason', 'ok')$p$, v_p, v_m4, v_p, v_m4)));
  IF v_got IS DISTINCT FROM 'ok|report_unavailable|true/ok|false/report_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the card or number-block report window is not 30 days: %', v_got;
  END IF;

  -- M-2: reports past 2 years stay while a restriction or an enforcement
  -- record from their case still stands (and their evidence with them);
  -- without either they go.
  v_got := concat_ws('|',
    pg_temp.probe(ARRAY[format($p$SELECT private.dating_close_case(%L, NULL, 'restricted')$p$, v_case),
                        format($p$SELECT private.dating_place_restriction(%L, 'suspended', 'csam', 'moderator', %L, NULL, NULL, true)$p$,
                               v_t3, v_case),
                        format($p$UPDATE public.dating_moderation_cases SET decided_at = now() - interval '200 days' WHERE id = %L$p$, v_case),
                        format($p$UPDATE public.dating_reports SET created_at = now() - interval '2 years 1 day' WHERE case_id = %L$p$, v_case),
                        'SELECT public.purge_dating_retention(now())'],
                  format($p$SELECT (SELECT count(*) FROM public.dating_reports WHERE case_id = %L) || '/'
                                   || (SELECT count(*) FROM public.dating_report_evidence AS e JOIN public.dating_reports AS r
                                         ON r.id = e.report_id WHERE r.case_id = %L)$p$, v_case, v_case)),
    pg_temp.probe(ARRAY[format($p$SELECT private.dating_close_case(%L, NULL, 'restricted')$p$, v_case),
                        format($p$INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, category, effect_until,
                                                                         purge_after, case_id)
                                  VALUES (public.dating_phone_hmac_for_user(%L), 'dating', 'suspended', 'csam', NULL,
                                          now() + interval '1 year', %L)$p$, v_t3, v_case),
                        format($p$UPDATE public.dating_moderation_cases SET decided_at = now() - interval '200 days' WHERE id = %L$p$, v_case),
                        format($p$UPDATE public.dating_reports SET created_at = now() - interval '2 years 1 day' WHERE case_id = %L$p$, v_case),
                        'SELECT public.purge_dating_retention(now())'],
                  format($p$SELECT (SELECT count(*) FROM public.dating_reports WHERE case_id = %L) || '/'
                                   || (SELECT count(*) FROM public.dating_report_evidence AS e JOIN public.dating_reports AS r
                                         ON r.id = e.report_id WHERE r.case_id = %L)$p$, v_case, v_case)),
    pg_temp.probe(ARRAY[format($p$SELECT private.dating_close_case(%L, NULL, 'restricted')$p$, v_case),
                        format($p$UPDATE public.dating_moderation_cases SET decided_at = now() - interval '200 days' WHERE id = %L$p$, v_case),
                        format($p$UPDATE public.dating_reports SET created_at = now() - interval '2 years 1 day' WHERE case_id = %L$p$, v_case),
                        'SELECT public.purge_dating_retention(now())'],
                  format($p$SELECT (SELECT count(*) FROM public.dating_reports WHERE case_id = %L) || '/'
                                   || (SELECT count(*) FROM public.dating_report_evidence AS e JOIN public.dating_reports AS r
                                         ON r.id = e.report_id WHERE r.case_id = %L)$p$, v_case, v_case)));
  IF v_got IS DISTINCT FROM '2/2|2/2|0/0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 2-year report purge took what a live restriction or record needs (or kept the rest): %', v_got;
  END IF;
END $d2$;

-- =====================================================================
-- E. (§3.7, §6.3, R-54) What the restricted person sees: the shown
--    restriction (closed for good, then until a date, then the age check,
--    then a hold; a closer look never), its category, whether it can be
--    appealed; never who reported, what they wrote or the evidence. Read
--    on a phone that isn't checked too.
-- =====================================================================
DO $e$
DECLARE
  v_h constant uuid := pg_temp.man('60');
  v_age constant uuid := pg_temp.man('61');
  v_s constant uuid := pg_temp.man('62');
  v_p constant uuid := pg_temp.man('63');
  v_u constant uuid := pg_temp.man('64');
  v_n constant uuid := pg_temp.man('65');
  v_rep constant uuid := pg_temp.ready('66');
  v_m uuid;
  v_case uuid;
  v jsonb;
  v_ends timestamptz := date_trunc('second', now() + interval '7 days');
BEGIN
  v_m := pg_temp.match(v_h, v_rep);
  PERFORM pg_temp.report(v_rep, '66', v_m, 'threats', false, 'w7-secret-details');
  SELECT case_id INTO v_case FROM public.dating_reports WHERE match_id = v_m;
  PERFORM private.dating_place_restriction(v_h, 'moderation_hold', 'threat_to_life', 'report', v_case, NULL, NULL, false);
  v := pg_temp.call(v_h, NULL, 'SELECT public.get_my_dating_restriction()')::jsonb;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v -> 'restriction') AS k)
       IS DISTINCT FROM ARRAY['appeal', 'can_appeal', 'category', 'ends_at', 'id', 'id_check_code', 'source', 'type'] -- W7 final (client I-3, I-1)
     OR v #>> '{restriction,source}' IS DISTINCT FROM 'p0_interim' OR v -> 'restriction' -> 'id_check_code' <> 'null'::jsonb -- W7 final
     OR v #>> '{restriction,type}' IS DISTINCT FROM 'hold' OR v #>> '{restriction,category}' IS DISTINCT FROM 'threat_to_life'
     OR (v #>> '{restriction,can_appeal}')::boolean OR v -> 'restriction' -> 'ends_at' <> 'null'::jsonb
     OR v -> 'restriction' -> 'appeal' <> 'null'::jsonb OR (v ->> 'appeal_accepted')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the hold reads %', v;
  END IF;
  IF position('w7-secret-details' IN v::text) > 0 OR position(v_rep::text IN v::text) > 0
     OR position('Mod 66' IN v::text) > 0 OR position(v_case::text IN v::text) > 0 OR position('report' IN v::text) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restricted person''s read names the reporter, the report or the case: %', v;
  END IF;
  PERFORM private.dating_place_restriction(v_age, 'age_review', 'underage_risk', 'report', NULL, NULL, NULL, false);
  PERFORM private.dating_place_restriction(v_s, 'suspended', 'romance_scam', 'moderator', NULL, v_rep, v_ends, true);
  PERFORM private.dating_place_restriction(v_p, 'moderation_hold', 'csam', 'report', NULL, NULL, NULL, false);
  PERFORM private.dating_place_restriction(v_p, 'suspended', 'harassment', 'moderator', NULL, v_rep, NULL, true);
  PERFORM private.dating_place_restriction(v_u, 'under_review', 'spam', 'moderator', NULL, v_rep, NULL, false);
  IF pg_temp.j(v_age, '61', 'SELECT public.get_my_dating_restriction()') #>> '{restriction,type}' IS DISTINCT FROM 'age_review'
     OR (pg_temp.j(v_age, '61', 'SELECT public.get_my_dating_restriction()') #>> '{restriction,can_appeal}')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the age check reads wrong';
  END IF;
  v := pg_temp.j(v_s, '62', 'SELECT public.get_my_dating_restriction()');
  IF v #>> '{restriction,type}' IS DISTINCT FROM 'suspended' OR (v #>> '{restriction,ends_at}')::timestamptz IS DISTINCT FROM v_ends
     OR NOT (v #>> '{restriction,can_appeal}')::boolean OR v #>> '{restriction,category}' IS DISTINCT FROM 'romance_scam' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a suspension until a date reads %', v;
  END IF;
  v := pg_temp.j(v_p, '63', 'SELECT public.get_my_dating_restriction()');
  IF v #>> '{restriction,type}' IS DISTINCT FROM 'suspended' OR v -> 'restriction' -> 'ends_at' <> 'null'::jsonb
     OR v #>> '{restriction,category}' IS DISTINCT FROM 'harassment' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: closed for good is not shown before a hold: %', v;
  END IF;
  -- A closer look is never shown, leaves the person's standing alone, and
  -- keeps them out of new generation.
  IF pg_temp.j(v_u, '64', 'SELECT public.get_my_dating_restriction()') IS DISTINCT FROM
       '{"ok": true, "review": "testing", "restriction": null, "appeal_accepted": false}'::jsonb -- Spec 2 W8b (M-6)
     OR NOT public.dating_account_in_good_standing(v_u) OR NOT pg_temp.excluded(v_u)
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_u) <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closer look showed, changed standing, or left the person in generation';
  END IF;
  IF pg_temp.j(v_n, '65', 'SELECT public.get_my_dating_restriction()') IS DISTINCT FROM
       '{"ok": true, "review": "testing", "restriction": null, "appeal_accepted": false}'::jsonb THEN -- Spec 2 W8b (M-6)
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone with no restriction reads one';
  END IF;
END $e$;

-- =====================================================================
-- F. (§3.7, §6.3, §7.5 mutant 15) One appeal, to a live appealable
--    restriction of one's own, opening an appeal case due in 7 days;
--    decided by someone other than the restriction's decider, or by the
--    safety owner 24 hours on when the owner decided it; accepting lifts
--    the restriction, leaves Dating paused (never suspended for good) and
--    says so on the section for 7 days; rejecting keeps it.
-- =====================================================================
DO $f$
DECLARE
  v_x constant uuid := pg_temp.man('67');
  v_mod constant uuid := pg_temp.ready('68');
  v_mod2 constant uuid := pg_temp.ready('69');
  v_y constant uuid := pg_temp.man('80');
  v_owner constant uuid := pg_temp.ready('81');
  v_z constant uuid := pg_temp.man('82');
  v_r uuid;
  v_r2 uuid;
  v_hold uuid;
  v_a uuid;
  v_a2 uuid;
  v_key constant text := pg_temp.key('f-appeal');
  v jsonb;
  v_got text;
  v_acc bigint := pg_temp.metric('dating.appeal.accepted');
  v_rej bigint := pg_temp.metric('dating.appeal.rejected');
BEGIN
  v_r := private.dating_place_restriction(v_x, 'suspended', 'harassment', 'moderator', NULL, v_mod, NULL, true);
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_x) <> 'suspended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a suspension left Dating open';
  END IF;
  v := pg_temp.j(v_x, '67', format('SELECT public.submit_dating_appeal(%L, %L, %L)', v_key, v_r, '  I didn''t do this.  '));
  SELECT id INTO v_a FROM public.dating_appeals WHERE restriction_id = v_r;
  IF v IS DISTINCT FROM '{"ok": true, "review": "testing"}'::jsonb -- Spec 2 W8b (M-6)
     OR (SELECT text || '/' || state FROM public.dating_appeals WHERE id = v_a) IS DISTINCT FROM 'I didn''t do this./open'
     OR (SELECT kind || '/' || priority || '/' || state || '/' || (sla_due_at BETWEEN now() + interval '6 days 23 hours' AND now() + interval '7 days 1 hour')
           FROM public.dating_moderation_cases WHERE appeal_id = v_a) IS DISTINCT FROM 'appeal/P2/open/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an appeal read % and opened no 7-day appeal case', v;
  END IF;
  v_got := concat_ws(' ',
    pg_temp.j(v_x, '67', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', v_key, v_r)) ->> 'ok',
    pg_temp.j(v_x, '67', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', pg_temp.key('f2'), v_r)) ->> 'reason',
    pg_temp.j(v_y, '80', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', pg_temp.key('f3'), v_r)) ->> 'reason',
    pg_temp.j(v_x, '67', format('SELECT public.submit_dating_appeal(%L, %L, %L)', pg_temp.key('f4'), v_r, repeat('x', 501))) ->> 'reason');
  IF v_got IS DISTINCT FROM 'true already_appealed appeal_unavailable invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay, a second appeal, a stranger or a long text read %', v_got;
  END IF;
  v := pg_temp.j(v_x, '67', 'SELECT public.get_my_dating_restriction()');
  IF (v #>> '{restriction,can_appeal}')::boolean OR v #>> '{restriction,appeal,state}' IS DISTINCT FROM 'open' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the appeal the read is %', v;
  END IF;
  -- A hold is not appealable until decided.
  v_hold := private.dating_place_restriction(v_z, 'moderation_hold', 'csam', 'report', NULL, NULL, NULL, false);
  IF pg_temp.j(v_z, '82', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', pg_temp.key('f5'), v_hold)) ->> 'reason'
       IS DISTINCT FROM 'appeal_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hold could be appealed';
  END IF;
  -- Mutant 15: the decider of the restriction can't decide its appeal.
  IF private.dating_decide_appeal(v_a, v_mod, false, true) IS DISTINCT FROM '{"ok": false, "reason": "same_decider"}'::jsonb
     OR private.dating_decide_appeal(v_a, v_mod, true, true) IS DISTINCT FROM '{"ok": false, "reason": "same_decider"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first decider decided the appeal';
  END IF;
  v := private.dating_decide_appeal(v_a, v_mod2, false, true);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT lifted_at IS NULL FROM public.dating_account_restrictions WHERE id = v_r)
     OR (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_x) IS DISTINCT FROM 'paused/gates'
     OR (SELECT state || '/' || outcome || '/' || (decided_at IS NOT NULL) FROM public.dating_moderation_cases WHERE appeal_id = v_a)
        IS DISTINCT FROM 'decided/accepted/true'
     OR pg_temp.metric('dating.appeal.accepted') IS DISTINCT FROM v_acc + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an accepted appeal did not lift the restriction, pause Dating and close its case';
  END IF;
  v := pg_temp.j(v_x, '67', 'SELECT public.get_my_dating_restriction()');
  v_got := private.dating_decide_appeal(v_a, v_mod2, false, false) ->> 'reason';
  IF v IS DISTINCT FROM '{"ok": true, "review": "testing", "restriction": null, "appeal_accepted": true}'::jsonb -- Spec 2 W8b (M-6)
     OR NOT coalesce((pg_temp.j(v_x, '67', 'SELECT public.get_dating_home()') ->> 'appeal_accepted')::boolean, false)
     OR v_got IS DISTINCT FROM 'appeal_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the accepted appeal reads % (and on the section), or was decided twice', v;
  END IF;
  -- The owner, working alone, decides their own decision's appeal only 24
  -- hours after it was sent; rejecting keeps the restriction.
  v_r2 := private.dating_place_restriction(v_y, 'suspended', 'spam', 'moderator', NULL, v_owner, NULL, true);
  PERFORM pg_temp.j(v_y, '80', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', pg_temp.key('f6'), v_r2));
  SELECT id INTO v_a2 FROM public.dating_appeals WHERE restriction_id = v_r2;
  UPDATE public.dating_appeals SET submitted_at = now() - interval '23 hours' WHERE id = v_a2;
  v_got := private.dating_decide_appeal(v_a2, v_owner, true, false) ->> 'reason';
  UPDATE public.dating_appeals SET submitted_at = now() - interval '25 hours' WHERE id = v_a2;
  IF v_got IS DISTINCT FROM 'same_decider'
     OR private.dating_decide_appeal(v_a2, v_owner, false, false) ->> 'reason' IS DISTINCT FROM 'same_decider' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the solo owner decided before 24 hours, or a non-owner after';
  END IF;
  v := private.dating_decide_appeal(v_a2, v_owner, true, false);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT lifted_at FROM public.dating_account_restrictions WHERE id = v_r2) IS NOT NULL
     OR pg_temp.j(v_y, '80', 'SELECT public.get_my_dating_restriction()') #>> '{restriction,appeal,state}' IS DISTINCT FROM 'rejected'
     OR pg_temp.metric('dating.appeal.rejected') IS DISTINCT FROM v_rej + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner''s rejection after 24 hours did not stand';
  END IF;
END $f$;

-- =====================================================================
-- G. (§6.3, §7.1, §7.2 S1, S6) Carry-over: a restriction survives the
--    account's deletion and comes back on the next account on the number,
--    from carried_over, with its category and one appeal, once; that
--    person cannot begin or activate Dating; accepting the appeal ends the
--    record. A parked account carries nothing (Spec 1 O3).
-- =====================================================================
DO $g$
DECLARE
  v_c constant uuid := pg_temp.man('70');
  v_mod constant uuid := pg_temp.ready('83');
  v_p constant uuid := pg_temp.man('72');
  v_c2 uuid;
  v_hmac text;
  v jsonb;
  v_r uuid;
  v_a uuid;
  v_got text;
BEGIN
  PERFORM private.dating_place_restriction(v_c, 'suspended', 'harassment', 'moderator', NULL, v_mod, NULL, true);
  v_hmac := public.dating_phone_hmac_for_user(v_c);
  PERFORM pg_temp.delete_account(v_c);
  IF NOT EXISTS (SELECT 1 FROM public.enforcement_records WHERE phone_hmac = v_hmac AND scope = 'dating'
                    AND restriction_type = 'suspended' AND category = 'harassment') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the suspension did not survive the deletion';
  END IF;
  v_c2 := pg_temp.man('71', '{"phone": "70"}');
  -- Beginning Dating refuses (Ruling R-55: the person's read carries it).
  v_got := pg_temp.call(v_c2, pg_temp.dev('71'), format('SELECT (public.begin_dating_enrollment(''dating-2.0'', %L)).state',
                                                       pg_temp.key('g-begin')));
  IF v_got IS DISTINCT FROM '22023:not_eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a carried restriction let the person begin Dating: %', v_got;
  END IF;
  v := pg_temp.j(v_c2, '71', 'SELECT public.get_my_dating_restriction()');
  PERFORM pg_temp.j(v_c2, '71', 'SELECT public.get_my_dating_restriction()');
  IF v #>> '{restriction,type}' IS DISTINCT FROM 'suspended' OR v #>> '{restriction,category}' IS DISTINCT FROM 'harassment'
     OR NOT (v #>> '{restriction,can_appeal}')::boolean
     OR pg_temp.held(v_c2) IS DISTINCT FROM 'suspended/carried_over/harassment/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the next account on the number reads % (carried once, with its appeal)', v;
  END IF;
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE user_id = v_c2;
  v_got := pg_temp.call(v_c2, pg_temp.dev('71'), format('SELECT (public.activate_dating_profile(%L)).state', pg_temp.key('g-act')));
  IF v_got IS DISTINCT FROM '22023:activation_gates_not_met' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restricted person could activate: %', v_got;
  END IF;
  v_r := (v #>> '{restriction,id}')::uuid;
  PERFORM pg_temp.j(v_c2, '71', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', pg_temp.key('g-ap'), v_r));
  SELECT id INTO v_a FROM public.dating_appeals WHERE restriction_id = v_r;
  -- Fix round 1 (I-1): the carried restriction keeps its decider, who
  -- can't decide its appeal; another moderator can.
  v_got := private.dating_decide_appeal(v_a, v_mod, false, true) ->> 'reason';
  v := private.dating_decide_appeal(v_a, pg_temp.id('69'), false, true);
  IF v_got IS DISTINCT FROM 'same_decider' OR v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR NOT public.dating_account_in_good_standing(v_c2)
     OR EXISTS (SELECT 1 FROM public.enforcement_records WHERE phone_hmac = v_hmac AND scope = 'dating'
                   AND (effect_until IS NULL OR effect_until > now())) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: accepting the carried appeal left the record in force';
  END IF;
  -- A parked account (its number presumed someone else's) carries nothing.
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, category, purge_after)
  VALUES (public.dating_phone_hmac_for_user(v_p), 'dating', 'suspended', 'spam', now() + interval '1 year');
  UPDATE public.users SET phone_released_at = now(), parked_phone_hmac = public.dating_phone_hmac_for_user(v_p) WHERE id = v_p;
  v_got := private.dating_carry_over(v_p)::text;
  IF v_got <> '0' OR pg_temp.held(v_p) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a parked account carried a record';
  END IF;
END $g$;

-- =====================================================================
-- H. (§6.3, §4.8; W5 carry T8 N-2/N-3, W6 T2 N-4, W6 T5) Deletion keeps
--    an open case open (userless, by number), so a new account on the
--    number stays throttled; a chat only the two numbers' block ended is
--    in the ended list and can be reported; a suspension that ran out or
--    was lifted becomes a pause (the cron every 15 minutes, the lift at
--    once); closing a case stamps decided_at and settles its reports; the
--    v1 report RPCs are gone.
-- =====================================================================
DO $h$
DECLARE
  v_s constant uuid := pg_temp.man('73');
  v_x constant uuid := pg_temp.ready('75');
  v_y constant uuid := pg_temp.man('76');
  v_z constant uuid := pg_temp.man('77');
  v_w constant uuid := pg_temp.man('78');
  v_q constant uuid := pg_temp.ready('79');
  v_s2 uuid;
  v_m uuid;
  v_r uuid;
  v_case uuid;
  v_hmac text;
  v jsonb;
  v_got text;
BEGIN
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, signal_kind)
  VALUES ('signal', 'P2', v_s, public.dating_phone_hmac_for_user(v_s), 'dragnet')
  RETURNING id INTO v_case;
  v_hmac := public.dating_phone_hmac_for_user(v_s);
  PERFORM pg_temp.delete_account(v_s);
  IF (SELECT state || '/' || (target_user_id IS NULL) || '/' || (target_phone_hmac = v_hmac) FROM public.dating_moderation_cases
       WHERE id = v_case) IS DISTINCT FROM 'open/true/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the deletion closed or emptied an open case (W5 T8 N-3)';
  END IF;
  v_s2 := pg_temp.man('74', '{"phone": "73"}');
  IF NOT private.dating_throttled(v_s2) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-registered sender escaped the open dragnet case';
  END IF;
  -- W6 T2 N-4: blocked by the numbers alone, the chat is ended and reportable.
  v_m := pg_temp.match(v_x, v_y);
  INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
  VALUES (public.dating_phone_hmac_for_user(v_y), public.dating_phone_hmac_for_user(v_x));
  v := pg_temp.j(v_x, '75', 'SELECT public.get_my_dating_matches(true)');
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'ended') AS e WHERE e ->> 'match_id' = v_m::text)
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'conversations') AS e WHERE e ->> 'match_id' = v_m::text) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chat ended by the numbers'' block is not in the ended list: %', v;
  END IF;
  v := pg_temp.report(v_x, '75', v_m, 'harassment');
  IF (v ->> 'ok') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chat ended by the numbers'' block could not be reported: %', v;
  END IF;
  -- A suspension that ran out: the cron makes it a pause.
  v_r := private.dating_place_restriction(v_z, 'suspended', 'spam', 'moderator', NULL, v_q, now() + interval '1 hour', true);
  UPDATE public.dating_account_restrictions SET ends_at = now() - interval '1 minute' WHERE id = v_r;
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_z) <> 'suspended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fixture''s suspension did not suspend';
  END IF;
  PERFORM private.dating_release_expired_suspensions();
  IF (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_z) IS DISTINCT FROM 'paused/gates'
     OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'release-dating-suspensions' AND schedule = '4-59/15 * * * *' -- W7 final (M-4)
                       AND command = 'SELECT private.dating_release_expired_suspensions()') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a suspension that ran out was not released to a pause by the 15-minute cron';
  END IF;
  -- A lift releases at once.
  v_r := private.dating_place_restriction(v_w, 'suspended', 'spam', 'moderator', NULL, v_q, NULL, true);
  UPDATE public.dating_account_restrictions SET lifted_at = now() WHERE id = v_r;
  IF (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_w) IS DISTINCT FROM 'paused/gates' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a lifted suspension left Dating suspended';
  END IF;
  -- W6 T5: closing a case stamps decided_at, and settles its reports.
  SELECT case_id INTO v_case FROM public.dating_reports WHERE match_id = v_m;
  v_got := private.dating_close_case(v_case, v_q, 'bogus') ->> 'reason';
  v_got := v_got || ' ' || (private.dating_close_case(v_case, v_q, 'restricted') ->> 'ok');
  v_got := v_got || ' ' || (private.dating_close_case(v_case, v_q, 'dismissed') ->> 'reason');
  IF v_got IS DISTINCT FROM 'invalid true case_unavailable'
     OR (SELECT state || '/' || outcome || '/' || (decided_at IS NOT NULL) FROM public.dating_moderation_cases WHERE id = v_case)
        IS DISTINCT FROM 'decided/restricted/true'
     OR EXISTS (SELECT 1 FROM public.dating_reports WHERE case_id = v_case AND state <> 'upheld') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: closing a case read % without stamping it or its reports', v_got;
  END IF;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind)
  VALUES ('signal', 'P2', v_q, 'dragnet') RETURNING id INTO v_case;
  PERFORM private.dating_close_case(v_case, v_y, 'no_action');
  IF (SELECT state || '/' || (decided_at IS NOT NULL) FROM public.dating_moderation_cases WHERE id = v_case)
       IS DISTINCT FROM 'closed/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: closing a signal case left decided_at empty (W6 T5)';
  END IF;
  IF to_regprocedure('public.submit_dating_report(text,uuid,text,text)') IS NOT NULL
     OR to_regprocedure('public.report_dating_match(text,uuid,text,text)') IS NOT NULL
     OR to_regprocedure('public.report_dating_introduction(text,uuid,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a v1 report RPC is still there (§4.10)';
  END IF;
END $h$;

-- =====================================================================
-- H (continued; W7a Task 1's carries M-5, O-1, N2-1). A report that
-- stays busy after three tries answers busy, writes nothing and is
-- counted (dating.report.busy, in health), from a chat and from a card.
-- A number stamp that fails at the deletion (a lock conflict on a match
-- row) loses only the stamp: the restriction still carries, and the
-- failure is counted (dating.deletion.stamp_failed, in health). A report
-- out of its window or past the day's 10 never takes the target's setup
-- lock (it never makes a write of theirs wait); one that files does.
-- Carry-over takes the person's setup lock only for a record to carry.
-- =====================================================================
DO $h2$
DECLARE
  v_x constant uuid := pg_temp.id('75');
  v_z constant uuid := pg_temp.id('77');
  v_q constant uuid := pg_temp.id('79');
  v_hz constant text := public.dating_phone_hmac_for_user(pg_temp.id('77'));
  v_m constant uuid := gen_random_uuid();
  v_i constant uuid := gen_random_uuid();
  v_busy constant bigint := pg_temp.metric('dating.report.busy');
  v_stamp constant bigint := pg_temp.metric('dating.deletion.stamp_failed');
  v_match constant text := 'INSERT INTO public.dating_matches (id, user_low_id, user_high_id, state, matched_at, pair_key, closed_reason, '
                           'closed_at, evidence_until) VALUES (%L, %L, %L, %L, now() - interval ''60 days'', %L, %s, %s, %s)';
  v_card constant text := 'INSERT INTO public.dating_introductions (id, pair_key, user_low_id, user_high_id, state, algorithm_version, '
                          'visible_from_low, visible_from_high, expires_at, created_at) VALUES (%L, %L, %L, %L, %L, ''introductions_v2'', '
                          'now() - interval ''40 days'', now() - interval ''40 days'', now() - make_interval(days => %s), '
                          'now() - interval ''40 days'')';
  v_lim constant text := 'INSERT INTO public.dating_rate_limits (user_id, operation, window_started_at, request_count) '
                         'VALUES (%L, ''report'', now(), 10) ON CONFLICT (user_id, operation) '
                         'DO UPDATE SET window_started_at = now(), request_count = 10';
  v_open text;
  v_shut text;
  v_xq text;
  v_xz text;
  v_got text;
BEGIN
  v_open := format(v_match, v_m, least(v_x, v_q), greatest(v_x, v_q), 'active', public.dating_pair_key(v_x, v_q), 'NULL', 'NULL', 'NULL');
  v_shut := format(v_match, v_m, least(v_x, v_q), greatest(v_x, v_q), 'unmatched', public.dating_pair_key(v_x, v_q),
                   '''unmatched''', 'now() - interval ''40 days''', 'now() - interval ''10 days''');
  v_xq := format($p$SELECT set_config('w7.ans', pg_temp.report(%L, '75', %L, 'spam')::text, true)$p$, v_x, v_m);
  v_xz := format($p$SELECT set_config('w7.ans', pg_temp.j(%L, '75', format('SELECT public.report_dating_introduction(%%L, %%L, ''spam'', NULL, false)',
                                                  pg_temp.key('h2-card'), %L))::text, true)$p$, v_x, v_i);
  -- N2-1: out of its window, or past the day's 10, the target's setup lock
  -- is never taken; a report that files takes it (the control).
  IF pg_temp.setup_locked(v_q) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: (setup) the target''s setup lock is already held';
  END IF;
  v_got := concat_ws('|',
    pg_temp.probe(ARRAY[v_shut, v_xq],
                  format($p$SELECT coalesce(current_setting('w7.ans')::jsonb ->> 'reason', 'ok') || '/' || pg_temp.setup_locked(%L)$p$, v_q)),
    pg_temp.probe(ARRAY[v_open, format(v_lim, v_x), v_xq],
                  format($p$SELECT coalesce(current_setting('w7.ans')::jsonb ->> 'reason', 'ok') || '/' || pg_temp.setup_locked(%L)$p$, v_q)),
    pg_temp.probe(ARRAY[v_open, v_xq],
                  format($p$SELECT coalesce(current_setting('w7.ans')::jsonb ->> 'reason', 'ok') || '/' || pg_temp.setup_locked(%L)$p$, v_q)),
    pg_temp.probe(ARRAY[format(v_card, v_i, public.dating_pair_key(v_x, v_q), least(v_x, v_q), greatest(v_x, v_q), 'expired', 31), v_xz],
                  format($p$SELECT coalesce(current_setting('w7.ans')::jsonb ->> 'reason', 'ok') || '/' || pg_temp.setup_locked(%L)$p$, v_q)),
    pg_temp.probe(ARRAY[format(v_card, v_i, public.dating_pair_key(v_x, v_q), least(v_x, v_q), greatest(v_x, v_q), 'presented', -6),
                        format(v_lim, v_x), v_xz],
                  format($p$SELECT coalesce(current_setting('w7.ans')::jsonb ->> 'reason', 'ok') || '/' || pg_temp.setup_locked(%L)$p$, v_q)),
    pg_temp.probe(ARRAY[format(v_card, v_i, public.dating_pair_key(v_x, v_q), least(v_x, v_q), greatest(v_x, v_q), 'presented', -6), v_xz],
                  format($p$SELECT coalesce(current_setting('w7.ans')::jsonb ->> 'reason', 'ok') || '/' || pg_temp.setup_locked(%L)$p$, v_q)));
  IF v_got IS DISTINCT FROM 'report_unavailable/false|rate_limited/false|ok/true|report_unavailable/false|rate_limited/false|ok/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report out of its window or past its limit took the target''s setup lock (or one that files did not): %', v_got;
  END IF;

  -- Carry-over takes the person's setup lock (the hold writer's order)
  -- only when the number has a record to carry; a read with nothing on
  -- the number takes none.
  v_got := concat_ws('|',
    pg_temp.probe(ARRAY[format($p$INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, category, purge_after)
                                  VALUES (public.dating_phone_hmac_for_user(%L), 'dating', 'suspended', 'spam', now() + interval '1 year')$p$, v_q),
                        format($p$SELECT pg_temp.j(%L, '79', 'SELECT public.get_my_dating_restriction()')$p$, v_q)],
                  format($p$SELECT pg_temp.held(%L) || '/' || pg_temp.setup_locked(%L)$p$, v_q, v_q)),
    pg_temp.probe(ARRAY[format($p$SELECT pg_temp.j(%L, '79', 'SELECT public.get_my_dating_restriction()')$p$, v_q)],
                  format($p$SELECT coalesce(nullif(pg_temp.held(%L), ''), '-') || '/' || pg_temp.setup_locked(%L)$p$, v_q, v_q)));
  IF v_got IS DISTINCT FROM 'suspended/carried_over/spam/true/true|-/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: carry-over did not take the person''s setup lock for a record (or took it for none): %', v_got;
  END IF;

  -- M-5: busy after three tries (a lock that is never free), from a chat
  -- and from a card: the answer, the count, and no report row.
  v_got := pg_temp.probe(ARRAY[
      'CREATE FUNCTION public.w7_report_busy() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''w7 busy'' USING ERRCODE = ''lock_not_available''; END $f$',
      'CREATE TRIGGER w7_report_busy BEFORE INSERT ON public.dating_reports FOR EACH ROW EXECUTE FUNCTION public.w7_report_busy()',
      v_open, format(v_card, v_i, public.dating_pair_key(v_x, v_q), least(v_x, v_q), greatest(v_x, v_q), 'presented', -6),
      replace(v_xq, 'w7.ans', 'w7.ans1'), replace(v_xz, 'w7.ans', 'w7.ans2')],
    format($p$SELECT (current_setting('w7.ans1')::jsonb ->> 'reason') || '/' || (current_setting('w7.ans2')::jsonb ->> 'reason') || '/'
                     || (pg_temp.metric('dating.report.busy') - %s) || '/'
                     || (SELECT count(*) FROM public.dating_reports WHERE reporter_user_id = %L AND (match_id = %L OR introduction_id = %L))$p$,
           v_busy, v_x, v_m, v_i));
  IF v_got IS DISTINCT FROM 'busy/busy/2/0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report that stayed busy read % (chat/card/counted/rows)', v_got;
  END IF;

  -- O-1: the deletion's number stamp on the person's matches fails on a
  -- lock conflict (every time): the suspension still carries, the failure
  -- is counted, only the stamp is missing; with no conflict all three land.
  v_got := concat_ws('|',
    pg_temp.probe(ARRAY[
        'CREATE FUNCTION public.w7_stamp_dead() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''deadlock detected'' USING ERRCODE = ''deadlock_detected''; END $f$',
        'CREATE TRIGGER w7_stamp_dead BEFORE UPDATE ON public.dating_matches FOR EACH ROW WHEN (OLD.low_phone_hmac IS DISTINCT FROM NEW.low_phone_hmac OR OLD.high_phone_hmac IS DISTINCT FROM NEW.high_phone_hmac) EXECUTE FUNCTION public.w7_stamp_dead()',
        format(v_match, v_m, least(v_z, v_q), greatest(v_z, v_q), 'active', public.dating_pair_key(v_z, v_q), 'NULL', 'NULL', 'NULL'),
        format($p$SELECT private.dating_place_restriction(%L, 'suspended', 'harassment', 'moderator', NULL, %L, NULL, true)$p$, v_z, v_q),
        format('SELECT pg_temp.delete_account(%L)', v_z)],
      format($p$SELECT (SELECT count(*) FROM public.enforcement_records WHERE phone_hmac = %L AND scope = 'dating'
                          AND restriction_type = 'suspended' AND category = 'harassment') || '/'
                       || (pg_temp.metric('dating.deletion.stamp_failed') > %s) || '/'
                       || (SELECT %L IN (coalesce(low_phone_hmac, '-'), coalesce(high_phone_hmac, '-')) FROM public.dating_matches WHERE id = %L)$p$,
             v_hz, v_stamp, v_hz, v_m)),
    pg_temp.probe(ARRAY[
        format(v_match, v_m, least(v_z, v_q), greatest(v_z, v_q), 'active', public.dating_pair_key(v_z, v_q), 'NULL', 'NULL', 'NULL'),
        format($p$SELECT private.dating_place_restriction(%L, 'suspended', 'harassment', 'moderator', NULL, %L, NULL, true)$p$, v_z, v_q),
        format('SELECT pg_temp.delete_account(%L)', v_z)],
      format($p$SELECT (SELECT count(*) FROM public.enforcement_records WHERE phone_hmac = %L AND scope = 'dating'
                          AND restriction_type = 'suspended' AND category = 'harassment') || '/'
                       || (pg_temp.metric('dating.deletion.stamp_failed') > %s) || '/'
                       || (SELECT %L IN (coalesce(low_phone_hmac, '-'), coalesce(high_phone_hmac, '-')) FROM public.dating_matches WHERE id = %L)$p$,
             v_hz, v_stamp, v_hz, v_m)));
  IF v_got IS DISTINCT FROM '1/true/false|1/false/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed number stamp took the deletion''s carry with it (or was not counted): % (carried/counted/stamped)', v_got;
  END IF;
  IF NOT (public.get_dating_operational_health() -> 'safety_counters_7d') ?& ARRAY['dating.report.busy', 'dating.deletion.stamp_failed'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not list dating.report.busy and dating.deletion.stamp_failed: %',
      public.get_dating_operational_health() -> 'safety_counters_7d';
  END IF;
END $h2$;

-- =====================================================================
-- H (continued; W7a Task 2 fix round 1). The decider survives carry-over,
-- and an unknown decider is no one's to overrule but the safety owner's
-- after 24 hours (I-1); a rejected appeal survives carry-over, an open one
-- leaves the appeal owed (M-1); a read after the carry takes no lock
-- (M-3), and a read that meets a lock answers busy, counted (M-4); the
-- appeal's decision takes the person's setup lock (M-5); a report past
-- its limit never takes the target's report lock (M-6); an
-- accepted appeal settles its case's reports and is said for 7 days, an
-- ended or future restriction can't be appealed, and the read releases a
-- suspension that ran out (M-9); a failed report stamp at the deletion
-- loses only the stamp (M-10).
-- =====================================================================
-- This session holds the report lock on the number [p_hmac].
CREATE FUNCTION pg_temp.report_locked(p_hmac text) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_locks AS l
                  WHERE l.locktype = 'advisory' AND l.pid = pg_backend_pid() AND l.granted AND l.objsubid = 2
                    AND l.classid::text::bigint = (hashtext('dating_report_target')::bigint + 4294967296) % 4294967296
                    AND l.objid::text::bigint = (hashtext(p_hmac)::bigint + 4294967296) % 4294967296);
$$;
DO $fr1$
DECLARE
  v_x constant uuid := pg_temp.id('75');
  v_z constant uuid := pg_temp.id('77');
  v_q constant uuid := pg_temp.id('79');
  v_m1 constant uuid := pg_temp.id('68');
  v_m2 constant uuid := pg_temp.id('69');
  v_hq constant text := public.dating_phone_hmac_for_user(pg_temp.id('79'));
  v_m constant uuid := gen_random_uuid();
  v_i constant uuid := gen_random_uuid();
  v_rid constant uuid := gen_random_uuid();
  v_er constant uuid := gen_random_uuid();
  v_ov constant bigint := pg_temp.metric('dating.overturned.gh');
  v_busy constant bigint := pg_temp.metric('dating.restriction.busy');
  v_stamp constant bigint := pg_temp.metric('dating.deletion.stamp_failed');
  v_place constant text := $p$SELECT set_config('w7.r', private.dating_place_restriction(%L, 'suspended', 'harassment', 'moderator', %s, %s, NULL, true)::text, true)$p$;
  v_appeal constant text := $p$SELECT set_config('w7.ap', pg_temp.j(%L, %L, format('SELECT public.submit_dating_appeal(%%L, %%L, NULL)', pg_temp.key('fr1'),
                                                                    current_setting('w7.r')))::text, true)$p$;
  v_aid constant text := $p$(SELECT id FROM public.dating_appeals WHERE restriction_id = current_setting('w7.r')::uuid)$p$;
  v_read constant text := $p$SELECT set_config(%L, pg_temp.j(%L, %L, 'SELECT public.get_my_dating_restriction()')::text, true)$p$;
  v_rec constant text := 'INSERT INTO public.enforcement_records (id, phone_hmac, scope, restriction_type, category, purge_after) '
                         'VALUES (%L, %L, ''dating'', ''suspended'', ''spam'', now() + interval ''1 year'')';
  v_match constant text := 'INSERT INTO public.dating_matches (id, user_low_id, user_high_id, state, matched_at, pair_key) '
                           'VALUES (%L, %L, %L, ''active'', now() - interval ''2 days'', %L)';
  v_card constant text := 'INSERT INTO public.dating_introductions (id, pair_key, user_low_id, user_high_id, state, algorithm_version, '
                          'visible_from_low, visible_from_high, expires_at, created_at) VALUES (%L, %L, %L, %L, ''presented'', ''introductions_v2'', '
                          'now() - interval ''1 day'', now() - interval ''1 day'', now() + interval ''6 days'', now() - interval ''1 day'')';
  v_lim constant text := 'INSERT INTO public.dating_rate_limits (user_id, operation, window_started_at, request_count) '
                         'VALUES (%L, ''report'', now(), 10) ON CONFLICT (user_id, operation) '
                         'DO UPDATE SET window_started_at = now(), request_count = 10';
  v_got text;
BEGIN
  -- I-1: a restriction with no recorded decider is decided only by the
  -- safety owner, 24 hours after the appeal (never "anyone").
  v_got := pg_temp.probe(ARRAY[format(v_place, v_q, 'NULL', 'NULL'), format(v_appeal, v_q, '79'),
      format($p$SELECT set_config('w7.d1', coalesce(private.dating_decide_appeal(%s, %L, false, true) ->> 'reason', 'ok'), true)$p$, v_aid, v_m1),
      format($p$SELECT set_config('w7.d2', coalesce(private.dating_decide_appeal(%s, %L, true, true) ->> 'reason', 'ok'), true)$p$, v_aid, v_m1),
      format($p$UPDATE public.dating_appeals SET submitted_at = now() - interval '25 hours' WHERE id = %s$p$, v_aid),
      format($p$SELECT set_config('w7.d3', coalesce(private.dating_decide_appeal(%s, %L, true, true) ->> 'reason', 'ok'), true)$p$, v_aid, v_m1)],
    $p$SELECT current_setting('w7.d1') || '/' || current_setting('w7.d2') || '/' || current_setting('w7.d3')$p$);
  IF v_got IS DISTINCT FROM 'same_decider/same_decider/ok' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an appeal of a restriction with no recorded decider was decided by %', v_got;
  END IF;

  -- I-1, M-1: a rejected appeal travels with the record (with the
  -- decider): the next account on the number reads it, can't appeal
  -- again, and the decider is kept. An appeal still open at the deletion
  -- leaves the one appeal owed.
  v_got := concat_ws('|',
    pg_temp.probe(ARRAY[format(v_place, v_q, 'NULL', quote_literal(v_m1)), format(v_appeal, v_q, '79'),
        format('SELECT private.dating_decide_appeal(%s, %L, false, false)', v_aid, v_m2),
        format('SELECT pg_temp.delete_account(%L)', v_q), $p$SELECT pg_temp.ready('84', '{"phone": "79"}')$p$,
        format(v_read, 'w7.v', pg_temp.id('84'), '84'),
        format($p$SELECT set_config('w7.s', pg_temp.j(%L, '84', format('SELECT public.submit_dating_appeal(%%L, %%L, NULL)', pg_temp.key('fr1b'),
                                                       current_setting('w7.v')::jsonb #>> '{restriction,id}'))::text, true)$p$, pg_temp.id('84'))],
      format($p$SELECT (current_setting('w7.v')::jsonb #>> '{restriction,can_appeal}') || '/'
                       || coalesce(current_setting('w7.v')::jsonb #>> '{restriction,appeal,state}', '-') || '/'
                       || coalesce(current_setting('w7.s')::jsonb ->> 'reason', 'ok') || '/'
                       || (SELECT (decided_by = %L)::text FROM public.dating_account_restrictions
                            WHERE user_id = %L AND source = 'carried_over')$p$, v_m1, pg_temp.id('84'))),
    pg_temp.probe(ARRAY[format(v_place, v_q, 'NULL', quote_literal(v_m1)), format(v_appeal, v_q, '79'),
        format('SELECT pg_temp.delete_account(%L)', v_q), $p$SELECT pg_temp.ready('84', '{"phone": "79"}')$p$,
        format(v_read, 'w7.v', pg_temp.id('84'), '84'),
        format($p$SELECT set_config('w7.s', pg_temp.j(%L, '84', format('SELECT public.submit_dating_appeal(%%L, %%L, NULL)', pg_temp.key('fr1c'),
                                                       current_setting('w7.v')::jsonb #>> '{restriction,id}'))::text, true)$p$, pg_temp.id('84'))],
      format($p$SELECT (current_setting('w7.v')::jsonb #>> '{restriction,can_appeal}') || '/'
                       || coalesce(current_setting('w7.v')::jsonb #>> '{restriction,appeal,state}', '-') || '/'
                       || coalesce(current_setting('w7.s')::jsonb ->> 'reason', 'ok') || '/'
                       || (SELECT (decided_by = %L)::text FROM public.dating_account_restrictions
                            WHERE user_id = %L AND source = 'carried_over')$p$, v_m1, pg_temp.id('84'))));
  IF v_got IS DISTINCT FROM 'false/rejected/already_appealed/true|true/-/ok/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: carry-over lost the decider or the appeal already used (rejected | open at deletion): %', v_got;
  END IF;

  -- M-3: a read after the record was carried takes no setup lock.
  v_got := pg_temp.probe(ARRAY[format(v_rec, v_er, v_hq),
      format($p$INSERT INTO public.dating_account_restrictions (id, user_id, restriction_type, category, source, carried_from)
                VALUES (%L, %L, 'suspended', 'spam', 'carried_over', %L)$p$, v_rid, v_q, v_er),
      format(v_read, 'w7.v', v_q, '79')],
    format($p$SELECT (current_setting('w7.v')::jsonb #>> '{restriction,id}') || '/' || pg_temp.setup_locked(%L) || '/'
                     || (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = %L)$p$, v_q, v_q));
  IF v_got IS DISTINCT FROM v_rid || '/false/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a read after the carry took the setup lock (or carried twice): %', v_got;
  END IF;

  -- M-4: a read that meets a lock (here: the carry's insert) answers
  -- busy, counted, never a raw error.
  v_got := pg_temp.probe(ARRAY[
      'CREATE FUNCTION public.w7_read_busy() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''w7 busy'' USING ERRCODE = ''lock_not_available''; END $f$',
      'CREATE TRIGGER w7_read_busy BEFORE INSERT ON public.dating_account_restrictions FOR EACH ROW EXECUTE FUNCTION public.w7_read_busy()',
      format(v_rec, v_er, v_hq), format(v_read, 'w7.v', v_q, '79')],
    format($p$SELECT current_setting('w7.v') || '/' || (pg_temp.metric('dating.restriction.busy') - %s)$p$, v_busy));
  IF v_got IS DISTINCT FROM '{"ok": false, "reason": "busy"}/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restriction read that met a lock read %', v_got;
  END IF;
  IF (SELECT proconfig FROM pg_proc WHERE oid = 'public.get_my_dating_restriction()'::regprocedure)::text NOT LIKE '%lock_timeout=%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restriction read has no lock_timeout';
  END IF;

  -- M-5: deciding an appeal takes the person's setup lock (rows written
  -- here without it).
  v_got := pg_temp.probe(ARRAY[
      format($p$INSERT INTO public.dating_account_restrictions (id, user_id, restriction_type, category, source, decided_by)
                VALUES (%L, %L, 'suspended', 'spam', 'moderator', %L)$p$, v_rid, v_q, v_m1),
      format($p$INSERT INTO public.dating_appeals (id, restriction_id, user_id) VALUES (%L, %L, %L)$p$, v_i, v_rid, v_q),
      format($p$SELECT set_config('w7.d1', private.dating_decide_appeal(%L, %L, false, false)::text, true)$p$, v_i, v_m2)],
    format($p$SELECT current_setting('w7.d1') || '/' || pg_temp.setup_locked(%L)$p$, v_q));
  IF v_got IS DISTINCT FROM '{"ok": true}/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: deciding an appeal did not take the person''s setup lock: %', v_got;
  END IF;

  -- M-6: past the day's 10, a report never takes the target's report
  -- lock (nor the match row, taken after it); one that files does.
  v_got := concat_ws('|',
    pg_temp.probe(ARRAY[format(v_match, v_m, least(v_x, v_q), greatest(v_x, v_q), public.dating_pair_key(v_x, v_q)), format(v_lim, v_x),
        format($p$SELECT set_config('w7.v', pg_temp.report(%L, '75', %L, 'spam')::text, true)$p$, v_x, v_m)],
      format($p$SELECT (current_setting('w7.v')::jsonb ->> 'reason') || '/' || pg_temp.report_locked(%L)$p$, v_hq)),
    pg_temp.probe(ARRAY[format(v_card, v_i, public.dating_pair_key(v_x, v_q), least(v_x, v_q), greatest(v_x, v_q)), format(v_lim, v_x),
        format($p$SELECT set_config('w7.v', pg_temp.j(%L, '75', format('SELECT public.report_dating_introduction(%%L, %%L, ''spam'', NULL, false)',
                                                       pg_temp.key('fr1-card'), %L))::text, true)$p$, v_x, v_i)],
      format($p$SELECT (current_setting('w7.v')::jsonb ->> 'reason') || '/' || pg_temp.report_locked(%L)$p$, v_hq)),
    pg_temp.probe(ARRAY[format(v_match, v_m, least(v_x, v_q), greatest(v_x, v_q), public.dating_pair_key(v_x, v_q)),
        format($p$SELECT set_config('w7.v', pg_temp.report(%L, '75', %L, 'spam')::text, true)$p$, v_x, v_m)],
      format($p$SELECT coalesce(current_setting('w7.v')::jsonb ->> 'reason', 'ok') || '/' || pg_temp.report_locked(%L)$p$, v_hq)));
  IF v_got IS DISTINCT FROM 'rate_limited/false|rate_limited/false|ok/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report past its limit took the target''s report lock (or one that files did not): %', v_got;
  END IF;

  -- M-9: accepting settles the case's reports (not upheld) and counts the
  -- country's overturn; "accepted" is said for 7 days, not 8.
  v_got := pg_temp.probe(ARRAY[format(v_match, v_m, least(v_x, v_q), greatest(v_x, v_q), public.dating_pair_key(v_x, v_q)),
      format('SELECT pg_temp.report(%L, ''75'', %L, ''harassment'')', v_x, v_m),
      format($p$SELECT set_config('w7.c', (SELECT case_id FROM public.dating_reports WHERE reporter_user_id = %L AND target_user_id = %L)::text, true)$p$, v_x, v_q),
      format(v_place, v_q, $p$current_setting('w7.c')::uuid$p$, quote_literal(v_m1)), format(v_appeal, v_q, '79'),
      format('SELECT private.dating_decide_appeal(%s, %L, false, true)', v_aid, v_m2),
      format($p$UPDATE public.dating_appeals SET decided_at = now() - interval '6 days' WHERE id = %s$p$, v_aid),
      format($p$SELECT set_config('w7.a6', private.dating_appeal_accepted(%L)::text, true)$p$, v_q),
      format($p$UPDATE public.dating_appeals SET decided_at = now() - interval '8 days' WHERE id = %s$p$, v_aid)],
    format($p$SELECT (SELECT string_agg(DISTINCT state, ',') FROM public.dating_reports WHERE case_id = current_setting('w7.c')::uuid) || '/'
                     || (pg_temp.metric('dating.overturned.gh') - %s) || '/' || current_setting('w7.a6') || '/'
                     || private.dating_appeal_accepted(%L)$p$, v_ov, v_q));
  IF v_got IS DISTINCT FROM 'not_upheld/1/true/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an accepted appeal did not settle its reports, count the overturn, or keep its 7 days: %', v_got;
  END IF;

  -- M-9: a restriction that has ended, or has not begun, can't be
  -- appealed; the read itself releases a suspension that ran out.
  v_got := concat_ws('|',
    pg_temp.probe(ARRAY[format($p$INSERT INTO public.dating_account_restrictions (id, user_id, restriction_type, category, source, decided_by, ends_at)
                                  VALUES (%L, %L, 'suspended', 'spam', 'moderator', %L, now() - interval '1 minute')$p$, v_rid, v_q, v_m1)],
                  format($p$SELECT pg_temp.j(%L, '79', format('SELECT public.submit_dating_appeal(%%L, %%L, NULL)', pg_temp.key('fr1d'), %L)) ->> 'reason'$p$, v_q, v_rid)),
    pg_temp.probe(ARRAY[format($p$INSERT INTO public.dating_account_restrictions (id, user_id, restriction_type, category, source, decided_by, starts_at)
                                  VALUES (%L, %L, 'suspended', 'spam', 'moderator', %L, now() + interval '1 day')$p$, v_rid, v_q, v_m1)],
                  format($p$SELECT pg_temp.j(%L, '79', format('SELECT public.submit_dating_appeal(%%L, %%L, NULL)', pg_temp.key('fr1e'), %L)) ->> 'reason'$p$, v_q, v_rid)),
    pg_temp.probe(ARRAY[format($p$SELECT private.dating_place_restriction(%L, 'suspended', 'spam', 'moderator', NULL, %L, now() + interval '1 hour', true)$p$, v_q, v_m1),
                        format($p$UPDATE public.dating_account_restrictions SET ends_at = now() - interval '1 minute' WHERE user_id = %L$p$, v_q),
                        format(v_read, 'w7.v', v_q, '79')],
                  format($p$SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = %L$p$, v_q)));
  IF v_got IS DISTINCT FROM 'appeal_unavailable|appeal_unavailable|paused/gates' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ended or future restriction could be appealed, or the read left a run-out suspension: %', v_got;
  END IF;

  -- M-10: the deletion's report stamp (reports about the person keep the
  -- number's code) fails on a lock conflict: only it is lost, counted.
  v_got := pg_temp.probe(ARRAY[
      'CREATE FUNCTION public.w7_rstamp_dead() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''deadlock detected'' USING ERRCODE = ''deadlock_detected''; END $f$',
      'CREATE TRIGGER w7_rstamp_dead BEFORE UPDATE ON public.dating_reports FOR EACH ROW WHEN (OLD.target_phone_hmac IS DISTINCT FROM NEW.target_phone_hmac) EXECUTE FUNCTION public.w7_rstamp_dead()',
      format($p$INSERT INTO public.dating_reports (reporter_user_id, target_user_id, category) VALUES (%L, %L, 'spam')$p$, v_q, v_z),
      format($p$SELECT private.dating_place_restriction(%L, 'suspended', 'harassment', 'moderator', NULL, %L, NULL, true)$p$, v_z, v_q),
      format('SELECT pg_temp.delete_account(%L)', v_z)],
    format($p$SELECT (SELECT count(*) FROM public.enforcement_records WHERE phone_hmac = %L AND scope = 'dating'
                        AND restriction_type = 'suspended' AND category = 'harassment') || '/'
                     || (pg_temp.metric('dating.deletion.stamp_failed') > %s)$p$, public.dating_phone_hmac_for_user(v_z), v_stamp));
  IF v_got IS DISTINCT FROM '1/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed report stamp took the deletion''s carry with it (or was not counted): %', v_got;
  END IF;
  IF NOT (public.get_dating_operational_health() -> 'safety_counters_7d') ?& ARRAY['dating.restriction.busy', 'dating.report.relock'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not list dating.restriction.busy and dating.report.relock';
  END IF;
END $fr1$;

-- [p_sql] run: 'ok', or the error's SQLSTATE and message.
CREATE FUNCTION pg_temp.try_sql(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLSTATE || ':' || SQLERRM;
END $$;
-- [p_sql] as the service role (its claims too): 'ok', or the error.
CREATE FUNCTION pg_temp.as_service(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'DISCARD PLANS';
  PERFORM set_config('request.jwt.claims', '{"role": "service_role"}', true);
  EXECUTE 'SET LOCAL ROLE service_role';
  EXECUTE p_sql;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN SQLSTATE || ':' || SQLERRM;
END $$;

-- =====================================================================
-- I. (§4.3, §4.4, §6.4, §7.3) The console's people and its audit: only an
--    active moderator gets an answer (anyone else: not_moderator,
--    counted); the moderation_* functions are the service role's alone;
--    the audit is append-only (an UPDATE or DELETE is refused; only the
--    purge may delete, and only at 2 years).
-- =====================================================================
DO $i$
DECLARE
  v_mod constant uuid := pg_temp.ready('85');
  v_off constant uuid := pg_temp.ready('86');
  v_stranger constant uuid := pg_temp.ready('87');
  v_target constant uuid := pg_temp.man('111');
  v_n bigint := pg_temp.metric('dating.moderation.not_moderator');
  v_got text;
  v_id uuid;
  v_case uuid;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator');
  INSERT INTO public.dating_moderators (user_id, role, active) VALUES (v_off, 'moderator', false);
  IF public.moderation_whoami(v_mod) IS DISTINCT FROM
       '{"ok": true, "role": "moderator", "languages": [], "sensitive_routing_allowed": false}'::jsonb
     OR public.moderation_whoami(v_off) IS DISTINCT FROM '{"ok": false, "reason": "not_moderator"}'::jsonb
     OR public.moderation_queue(v_stranger) IS DISTINCT FROM '{"ok": false, "reason": "not_moderator"}'::jsonb
     OR public.moderation_case(v_stranger, gen_random_uuid()) IS DISTINCT FROM '{"ok": false, "reason": "not_moderator"}'::jsonb
     OR pg_temp.metric('dating.moderation.not_moderator') < v_n + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the console answered someone who is not an active moderator';
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_got
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname LIKE 'moderation\_%'
     AND (has_function_privilege('authenticated', p.oid, 'EXECUTE') OR has_function_privilege('anon', p.oid, 'EXECUTE')
          OR NOT has_function_privilege('service_role', p.oid, 'EXECUTE'));
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a moderation function is not the service role''s alone: %', v_got;
  END IF;
  PERFORM private.dating_audit(v_mod, NULL, 'note', NULL, '{"note": "x"}');
  SELECT id INTO v_id FROM public.dating_moderation_actions WHERE actor_id = v_mod;
  v_got := pg_temp.try_sql(format('UPDATE public.dating_moderation_actions SET action = ''claim'' WHERE id = %L', v_id))
        || ' ' || pg_temp.try_sql(format('DELETE FROM public.dating_moderation_actions WHERE id = %L', v_id))
        || ' ' || pg_temp.probe(ARRAY[$p$SELECT set_config('attune.dating_audit_purge', 'on', true)$p$],
                    format('SELECT pg_temp.try_sql(%L)', format('DELETE FROM public.dating_moderation_actions WHERE id = %L', v_id)));
  IF v_got IS DISTINCT FROM '42501:audit:append_only 42501:audit:append_only 42501:audit:append_only' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the audit is not append-only (a young row under the purge''s setting too): %', v_got;
  END IF;
  v_got := pg_temp.probe(ARRAY[$p$SELECT set_config('attune.dating_audit_purge', 'on', true)$p$,
                               $p$ALTER TABLE public.dating_moderation_actions DISABLE TRIGGER dating_moderation_actions_append_only$p$,
                               format($p$UPDATE public.dating_moderation_actions SET created_at = now() - interval '2 years 1 day' WHERE id = %L$p$, v_id),
                               $p$ALTER TABLE public.dating_moderation_actions ENABLE TRIGGER dating_moderation_actions_append_only$p$],
                         format('SELECT pg_temp.try_sql(%L)', format('DELETE FROM public.dating_moderation_actions WHERE id = %L', v_id)));
  IF v_got IS DISTINCT FROM 'ok' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge could not delete a 2-year-old audit row: %', v_got;
  END IF;
  -- A foreign key's own SET NULL passes: the case purged, the person's
  -- account deleted (deletion never fails on the audit).
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind, state, decided_at, outcome)
  VALUES ('signal', 'P2', v_target, 'dragnet', 'closed', now(), 'no_action') RETURNING id INTO v_case;
  PERFORM private.dating_audit(v_mod, v_case, 'dismiss', v_target);
  v_got := pg_temp.try_sql(format('DELETE FROM public.dating_moderation_cases WHERE id = %L', v_case))
        || ' ' || pg_temp.try_sql(format('SELECT pg_temp.delete_account(%L)', v_target));
  IF v_got IS DISTINCT FROM 'ok ok'
     OR (SELECT count(*) FROM public.dating_moderation_actions
          WHERE actor_id = v_mod AND action = 'dismiss' AND case_id IS NULL AND target_user_id IS NULL) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a purged case or a deleted account did not leave its audit row behind, unnamed';
  END IF;
END $i$;

-- =====================================================================
-- J. (§6.4, §7.1 routing, §7.5 mutant 26; S-5) Read-time routing: a case
--    whose people are not a woman and a man is left out of the queue of a
--    moderator without sensitive_routing_allowed, and opening or claiming
--    it reads case_unavailable (as a case that doesn't exist); a man-woman
--    case is the same for both; an unreadable identity routes; nothing
--    about routing reaches the audit.
-- =====================================================================
DO $j$
DECLARE
  v_mod constant uuid := pg_temp.ready('88');
  v_owner constant uuid := pg_temp.ready('89');
  v_w1 constant uuid := pg_temp.ready('90');
  v_w2 constant uuid := pg_temp.ready('91', '{"seeking": ["woman"]}');
  v_m constant uuid := pg_temp.man('92');
  v_w3 constant uuid := pg_temp.ready('93');
  v_nb constant uuid := pg_temp.ready('94', '{"identity": "non_binary", "seeking": ["woman"]}');
  v_same uuid;
  v_mw uuid;
  v_lone uuid;
  q jsonb;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator');
  INSERT INTO public.dating_moderators (user_id, role, sensitive_routing_allowed) VALUES (v_owner, 'safety_owner', true);
  PERFORM pg_temp.report(v_w1, '90', pg_temp.match(v_w1, v_w2), 'harassment');
  SELECT case_id INTO v_same FROM public.dating_reports WHERE reporter_user_id = v_w1;
  PERFORM pg_temp.report(v_w3, '93', pg_temp.match(v_w3, v_m), 'harassment');
  SELECT case_id INTO v_mw FROM public.dating_reports WHERE reporter_user_id = v_w3;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind)
  VALUES ('signal', 'P2', v_nb, 'dragnet') RETURNING id INTO v_lone;
  q := public.moderation_queue(v_mod);
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(q -> 'cases') AS c WHERE (c ->> 'id')::uuid IN (v_same, v_lone))
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(q -> 'cases') AS c WHERE (c ->> 'id')::uuid = v_mw) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the queue showed a not-man-woman case to a moderator without routing (mutant 26)';
  END IF;
  IF public.moderation_case(v_mod, v_same) IS DISTINCT FROM '{"ok": false, "reason": "case_unavailable"}'::jsonb
     OR public.moderation_case(v_mod, v_same) IS DISTINCT FROM public.moderation_case(v_mod, gen_random_uuid())
     OR public.moderation_claim(v_mod, v_same) IS DISTINCT FROM '{"ok": false, "reason": "case_unavailable"}'::jsonb
     OR public.moderation_dismiss(v_mod, v_lone) IS DISTINCT FROM '{"ok": false, "reason": "case_unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a routed case opened (or answered differently from a missing one) without routing';
  END IF;
  q := public.moderation_queue(v_owner);
  IF (SELECT count(*) FROM jsonb_array_elements(q -> 'cases') AS c WHERE (c ->> 'id')::uuid IN (v_same, v_lone, v_mw)) <> 3
     OR (public.moderation_case(v_owner, v_same) ->> 'ok')::boolean IS NOT TRUE
     OR (public.moderation_case(v_mod, v_mw) ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner (or the moderator on a man-woman case) could not read a case';
  END IF;
  -- An identity that can't be read routes (fails closed).
  IF pg_temp.probe(ARRAY[format('UPDATE public.dating_profile_sensitive SET identity_enc = NULL WHERE user_id = %L', v_m)],
                   format('SELECT private.dating_case_needs_sensitive_routing(%L)::text', v_mw)) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable identity did not route';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_moderation_actions AS a
              WHERE a.detail::text ~* '(routing|sensitive|identity|gender|woman|man\M|non_binary|seeking)') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the audit holds a routing or identity value';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns AS c
              WHERE c.table_schema IN ('public', 'private') AND c.column_name LIKE '%routing%'
                AND NOT (c.table_name = 'dating_moderators' AND c.column_name = 'sensitive_routing_allowed')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a column stores routing (S-5)';
  END IF;
END $j$;

-- =====================================================================
-- K. (§6.4 Case) One case: its reports with their text, the credibility
--    note and the evidence; the person as others see them (name, age,
--    region, approved prompts and photos) and nothing special-category;
--    prior cases by account or number; the safety families by name; never
--    who reported; opening it is audited.
-- =====================================================================
DO $k$
DECLARE
  v_mod constant uuid := pg_temp.ready('95');
  v_t constant uuid := pg_temp.man('96');
  v_r constant uuid := pg_temp.ready('97');
  v_m uuid;
  v_case uuid;
  v jsonb;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator');
  v_m := pg_temp.match(v_t, v_r);
  PERFORM pg_temp.say(v_m, v_t, 'w7-k-evidence', 2);
  INSERT INTO public.dating_safety_events (match_id, at_risk_user_id, sender_user_id, rule_id, family, tier, config_version,
                                           source_event_key)
  VALUES (v_m, v_t, v_r, 'sexual_pressure:x', 'sexual_pressure', 1, 'dating_chat_v1', 'w7-k-trip'),
         (v_m, v_r, v_t, 'financial_request:momo', 'financial_request', 2, 'dating_chat_v1', 'w7-k-money');
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, signal_kind, state, decided_at,
                                              outcome)
  VALUES ('signal', 'P2', NULL, public.dating_phone_hmac_for_user(v_t), 'dragnet', 'closed', now(), 'no_action');
  PERFORM pg_temp.report(v_r, '97', v_m, 'romance_scam', false, 'He asked for momo.');
  SELECT case_id INTO v_case FROM public.dating_reports WHERE match_id = v_m;
  v := public.moderation_case(v_mod, v_case);
  IF v #>> '{reports,0,details}' IS DISTINCT FROM 'He asked for momo.'
     OR v #>> '{reports,0,reporter_triggered}' IS DISTINCT FROM 'sexual_pressure'
     OR jsonb_array_length(v #> '{reports,0,evidence}') <> 2
     OR v #>> '{reports,0,evidence,0,text}' IS DISTINCT FROM 'w7-k-evidence 1'
     OR v #>> '{profile,display_name}' IS DISTINCT FROM 'Mod 96' OR (v #>> '{profile,age}')::int <> 30
     OR v #>> '{profile,region}' IS DISTINCT FROM 'AA' OR jsonb_array_length(v #> '{profile,photos}') <> 2
     OR jsonb_array_length(v #> '{profile,prompts}') <> 2
     OR jsonb_array_length(v -> 'prior') <> 1
     OR (SELECT array_agg(f ORDER BY f) FROM jsonb_array_elements_text(v -> 'families') AS f)
        IS DISTINCT FROM ARRAY['financial_request', 'sexual_pressure'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the case reads %', v - 'reports';
  END IF;
  IF position(v_r::text IN v::text) > 0 OR position('Mod 97' IN v::text) > 0
     OR v::text ~ '"(identity|seeking|faith|marital|pronouns|pools|reporter_user_id|reporter_phone_hmac)"' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the case names the reporter or a special-category answer';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE case_id = v_case AND action = 'open_case'
                    AND actor_id = v_mod AND detail = '{}'::jsonb) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: opening a case was not audited';
  END IF;
END $k$;

-- =====================================================================
-- L. (§6.3, §6.4) The actions: claim; hold and lift it; dismiss (lifts the
--    case's interim holds, stamps decided_at); restrict until a date (the
--    case decided, its holds lifted, the person suspended and appealable);
--    a closer look; ask for ID; confirm a minor (Spec 1's account hold,
--    once, three arguments); a note; an appeal decided through the
--    console (the restriction's decider refused); photos; verifications;
--    countries (publishing is the safety owner's); S1 W9b's Opinions queue
--    through its own RPCs; the audit log. Every action, one audit row.
-- =====================================================================
DO $l$
DECLARE
  v_mod constant uuid := pg_temp.ready('98');
  v_mod2 constant uuid := pg_temp.ready('99');
  v_owner constant uuid := pg_temp.ready('100');
  v_t1 constant uuid := pg_temp.man('101');
  v_t2 constant uuid := pg_temp.man('102');
  v_t3 constant uuid := pg_temp.man('103');
  v_t4 constant uuid := pg_temp.man('104');
  v_r1 constant uuid := pg_temp.ready('105');
  v_r2 constant uuid := pg_temp.ready('106');
  v_r3 constant uuid := pg_temp.ready('107');
  v_r4 constant uuid := pg_temp.ready('108');
  v_c1 uuid;
  v_c2 uuid;
  v_c3 uuid;
  v_c4 uuid;
  v_restr uuid;
  v_appeal_case uuid;
  v_photo uuid;
  v_ends constant timestamptz := date_trunc('second', now() + interval '14 days');
  v jsonb;
  v_got text;
  v_audit bigint;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator'), (v_mod2, 'moderator');
  INSERT INTO public.dating_moderators (user_id, role, sensitive_routing_allowed) VALUES (v_owner, 'safety_owner', true);
  PERFORM pg_temp.report(v_r1, '105', pg_temp.match(v_t1, v_r1), 'harassment');
  SELECT case_id INTO v_c1 FROM public.dating_reports WHERE reporter_user_id = v_r1;
  PERFORM pg_temp.report(v_r2, '106', pg_temp.match(v_t2, v_r2), 'threats');
  SELECT case_id INTO v_c2 FROM public.dating_reports WHERE reporter_user_id = v_r2;
  PERFORM pg_temp.report(v_r3, '107', pg_temp.match(v_t3, v_r3), 'underage_risk');
  SELECT case_id INTO v_c3 FROM public.dating_reports WHERE reporter_user_id = v_r3;
  PERFORM pg_temp.report(v_r4, '108', pg_temp.match(v_t4, v_r4), 'spam');
  SELECT case_id INTO v_c4 FROM public.dating_reports WHERE reporter_user_id = v_r4;
  v_audit := (SELECT count(*) FROM public.dating_moderation_actions);
  -- Claim, hold, lift, dismiss.
  v_got := concat_ws(' ', public.moderation_claim(v_mod, v_c1) ->> 'ok',
                          public.moderation_place_hold(v_mod, v_c1, 'bogus') ->> 'reason');
  v_got := v_got || ' ' || (public.moderation_place_hold(v_mod, v_c1, 'harassment') ->> 'ok');
  IF v_got IS DISTINCT FROM 'true invalid true'
     OR (SELECT state || '/' || assigned_to::text FROM public.dating_moderation_cases WHERE id = v_c1)
        IS DISTINCT FROM 'in_review/' || v_mod
     OR pg_temp.held(v_t1) IS DISTINCT FROM 'moderation_hold/moderator/harassment/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: claim or hold read % (%)', v_got, pg_temp.held(v_t1);
  END IF;
  v := public.moderation_lift_hold(v_mod, v_c1);
  IF (v ->> 'lifted')::int <> 1 OR pg_temp.held(v_t1) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: lifting the hold read %', v;
  END IF;
  PERFORM private.dating_place_restriction(v_t1, 'moderation_hold', 'harassment', 'report', v_c1, NULL, NULL, false);
  v := public.moderation_dismiss(v_mod, v_c1);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR pg_temp.held(v_t1) <> ''
     OR (SELECT state || '/' || outcome || '/' || (decided_at IS NOT NULL) FROM public.dating_moderation_cases WHERE id = v_c1)
        IS DISTINCT FROM 'decided/dismissed/true'
     OR (SELECT state FROM public.dating_reports WHERE case_id = v_c1) <> 'not_upheld' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dismissing read % or left the interim hold, the stamp or the reports', v;
  END IF;
  -- Restrict until a date; the person can appeal; another moderator
  -- decides it (the decider can't).
  v_got := public.moderation_restrict(v_mod, v_c2, 'suspended', now() - interval '1 day', 'threats') ->> 'reason';
  v := public.moderation_restrict(v_mod, v_c2, 'suspended', v_ends, 'threats');
  IF v_got IS DISTINCT FROM 'invalid' OR v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.held(v_t2) IS DISTINCT FROM 'suspended/moderator/threats/true'
     OR (SELECT state || '/' || outcome FROM public.dating_moderation_cases WHERE id = v_c2) IS DISTINCT FROM 'decided/restricted'
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_t2) <> 'suspended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: restricting read % (%)', v, pg_temp.held(v_t2);
  END IF;
  SELECT id INTO v_restr FROM public.dating_account_restrictions WHERE user_id = v_t2 AND lifted_at IS NULL;
  PERFORM pg_temp.j(v_t2, '102', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', pg_temp.key('l-ap'), v_restr));
  SELECT c.id INTO v_appeal_case FROM public.dating_moderation_cases AS c JOIN public.dating_appeals AS a ON a.id = c.appeal_id
   WHERE a.restriction_id = v_restr;
  IF (public.moderation_case(v_mod2, v_appeal_case) #>> '{appeal,restriction,category}') IS DISTINCT FROM 'threats'
     OR public.moderation_decide_appeal(v_mod, v_appeal_case, true) IS DISTINCT FROM '{"ok": false, "reason": "same_decider"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the appeal case reads wrong or its decider decided it';
  END IF;
  v := public.moderation_decide_appeal(v_mod2, v_appeal_case, true);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR pg_temp.held(v_t2) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another moderator could not accept the appeal: %', v;
  END IF;
  -- A minor confirmed: Spec 1's account hold, once, naming the case.
  v := public.moderation_confirm_minor(v_mod, v_c3);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT count(*) FROM public.account_holds WHERE user_id = v_t3 AND kind = 'age_review' AND reason_ref = v_c3::text) <> 1
     OR pg_temp.held(v_t3) NOT LIKE 'age_review/report/underage_risk/false%' AND pg_temp.held(v_t3) NOT LIKE 'age_review/moderator%'
     OR public.moderation_confirm_minor(v_mod, v_c4) ->> 'reason' IS DISTINCT FROM 'case_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: confirming a minor read % (one account hold, an underage_risk case only)', v;
  END IF;
  -- Ask for ID; a closer look; a note.
  v_got := public.moderation_note(v_mod, v_c4, repeat('x', 1001)) ->> 'reason';
  v_got := v_got || ' ' || (public.moderation_note(v_mod, v_c4, 'Checked the evidence.') ->> 'ok');
  v_got := v_got || ' ' || (public.moderation_ask_for_id(v_mod, v_c4) ->> 'ok');
  IF v_got IS DISTINCT FROM 'invalid true true' OR pg_temp.held(v_t4) IS DISTINCT FROM 'age_review/moderator/underage_risk/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: note or ask for ID read % (%)', v_got, pg_temp.held(v_t4);
  END IF;
  -- R-56: once support has seen the ID, the moderator lifts the age check
  -- (round 3: on the id_check case the ask opened).
  v := public.moderation_lift_hold(v_mod, (public.moderation_case(v_mod, v_c4) #>> '{case,id_case}')::uuid);
  IF (v ->> 'lifted')::int <> 1 OR pg_temp.held(v_t4) <> ''
     OR (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_t4) IS DISTINCT FROM 'paused/gates' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: lifting the age check read % (%)', v, pg_temp.held(v_t4);
  END IF;
  -- Photos.
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state, rejection_reason)
  VALUES (v_t1, 'w7/review.jpg', 3, 'needs_review', 'clear', 'needs_review') RETURNING id INTO v_photo;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_photos(v_mod) -> 'photos') AS p
                  WHERE (p ->> 'id')::uuid = v_photo)
     OR public.moderation_photo_decide(v_mod, v_photo, false, NULL) ->> 'reason' IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the photo queue or its refusal read wrong';
  END IF;
  v := public.moderation_photo_decide(v_mod, v_photo, false, 'face_unclear');
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT moderation_state || '/' || rejection_reason FROM public.dating_profile_photos WHERE id = v_photo)
        IS DISTINCT FROM 'rejected/face_unclear'
     OR public.moderation_photo_decide(v_mod, v_photo, true, NULL) ->> 'reason' IS DISTINCT FROM 'photo_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: deciding a photo read %', v;
  END IF;
  -- Countries: the moderator reads, only the owner publishes.
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_countries(v_mod) -> 'countries') AS c
                  WHERE c ->> 'country' = 'GH')
     OR public.moderation_publish_country(v_mod, 'GH', '{"open_regions": ["AA"]}') IS DISTINCT FROM
        '{"ok": false, "reason": "safety_owner_only"}'::jsonb
     OR (public.moderation_publish_country(v_owner, 'GH', '{"open_regions": ["AA", "AH"]}') ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: countries read or published wrong';
  END IF;
  -- Opinions review queue v0 through its own RPCs (as the service role).
  v_got := pg_temp.as_service(format('SELECT public.moderation_opinions_queue(%L, 10)', v_mod));
  IF v_got IS DISTINCT FROM 'ok' OR public.moderation_opinions_remove(v_mod, 'forum_post', gen_random_uuid()) ->> 'reason'
       IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Opinions queue read %', v_got;
  END IF;
  -- Every action, one audit row; the log lists them newest first.
  IF (SELECT count(*) FROM public.dating_moderation_actions) - v_audit
       <> (SELECT count(*) FROM public.dating_moderation_actions WHERE created_at = now() AND actor_id IN (v_mod, v_mod2, v_owner))
     OR NOT EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE action = 'restrict' AND case_id = v_c2
                       AND detail = jsonb_build_object('type', 'suspended', 'ends_at', v_ends, 'category', 'threats'))
     OR (SELECT count(DISTINCT action) FROM public.dating_moderation_actions WHERE actor_id IN (v_mod, v_mod2, v_owner)
           AND action IN ('claim', 'hold', 'lift_hold', 'dismiss', 'restrict', 'decide_appeal', 'confirm_minor', 'note',
                          'ask_for_id', 'photo_decide', 'publish_country', 'opinions_view')) <> 12 -- each of them
     OR jsonb_array_length(public.moderation_audit_log(v_mod, 5) -> 'actions') <> 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the actions are not each one audit row';
  END IF;
END $l$;

-- =====================================================================
-- L2. (Task 5: W7a M-11/N-1, Task 2 M-11 and R1-3, W6 T5, W6 M-16, S-5,
--     health) Every console write takes the person's setup lock before
--     any row it writes; a replayed action answers as the first did and
--     writes one audit row; an appeal of a restriction nobody is recorded
--     as deciding reads decider_unknown until the safety owner, 24 hours
--     on; dismissing a signal case stamps decided_at, which the cleared
--     filter reads; a later hit's linked match counts for the families and
--     the routing; the audit log leaves out a routed case's rows, and an
--     earlier case carries no id, for a moderator without routing;
--     not_moderator is counted on every function.
-- =====================================================================
-- Records, for the watched person ('w7.watch'), whether this session held
-- their setup lock as each row of theirs was written.
CREATE TEMP TABLE w7_seen (what text) ON COMMIT DROP;
CREATE FUNCTION public.w7_t5_seen() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_who constant text := coalesce(to_jsonb(NEW) ->> 'target_user_id', to_jsonb(NEW) ->> 'user_id');
BEGIN
  IF v_who IS NOT NULL AND v_who = current_setting('w7.watch', true) THEN
    INSERT INTO pg_temp.w7_seen VALUES (TG_TABLE_NAME || ':' || pg_temp.setup_locked(v_who::uuid));
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER w7_t5_seen BEFORE UPDATE ON public.dating_moderation_cases FOR EACH ROW EXECUTE FUNCTION public.w7_t5_seen();
CREATE TRIGGER w7_t5_seen BEFORE UPDATE ON public.dating_reports FOR EACH ROW EXECUTE FUNCTION public.w7_t5_seen();
CREATE TRIGGER w7_t5_seen BEFORE INSERT OR UPDATE ON public.dating_account_restrictions FOR EACH ROW EXECUTE FUNCTION public.w7_t5_seen();
CREATE TRIGGER w7_t5_seen BEFORE UPDATE ON public.dating_enrollments FOR EACH ROW EXECUTE FUNCTION public.w7_t5_seen();
CREATE TRIGGER w7_t5_seen BEFORE UPDATE ON public.dating_profile_photos FOR EACH ROW EXECUTE FUNCTION public.w7_t5_seen();
CREATE TRIGGER w7_t5_seen BEFORE UPDATE ON public.dating_appeals FOR EACH ROW EXECUTE FUNCTION public.w7_t5_seen();
-- One audit row of [p_actor]'s [p_action] on [p_case] (NULL: on no case).
CREATE FUNCTION pg_temp.audit_rows(p_actor uuid, p_case uuid, p_action text) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM public.dating_moderation_actions AS a
   WHERE a.actor_id = p_actor AND a.action = p_action AND a.case_id IS NOT DISTINCT FROM p_case;
$$;
DO $l2$
DECLARE
  v_o constant uuid := pg_temp.ready('112');
  v_m2 constant uuid := pg_temp.ready('113');
  v_p constant uuid := pg_temp.man('114');
  v_q1 constant uuid := pg_temp.man('115');
  v_q2 constant uuid := pg_temp.man('116');
  v_q3 constant uuid := pg_temp.man('117');
  v_q4 constant uuid := pg_temp.man('118');
  v_m constant uuid := pg_temp.ready('119');
  v_u constant uuid := pg_temp.man('120');
  v_s constant uuid := pg_temp.man('121');
  v_h constant uuid := pg_temp.man('122');
  v_w constant uuid := pg_temp.ready('123');
  v_x constant uuid := pg_temp.man('124');
  v_z constant uuid := pg_temp.ready('125');
  v_a uuid;
  v_b uuid;
  v_c uuid;
  v_d uuid;
  v_e uuid;
  v_ap uuid;
  v_s1 uuid;
  v_s2 uuid;
  v_sig uuid;
  v_m1 uuid;
  v_mx uuid;
  v_photo uuid;
  v_session uuid;
  v_restr uuid;
  v_n bigint;
  v_got text;
  v_first jsonb;
  v_again jsonb;
  v jsonb;
  v_sql text;
  v_watch constant text := format($f$SELECT set_config('w7.watch', %L, true)$f$, pg_temp.id('114'));
  v_seen constant text := format($f$SELECT coalesce(string_agg(DISTINCT what, ' ' ORDER BY what), '-') || '|' || pg_temp.setup_locked(%L)
                                      FROM pg_temp.w7_seen$f$, pg_temp.id('114'));
BEGIN
  INSERT INTO public.dating_moderators (user_id, role, sensitive_routing_allowed)
  VALUES (v_o, 'safety_owner', true), (v_m2, 'moderator', false), (v_m, 'moderator', false);

  -- (1) The lock order: the person's setup lock before every row (W7a
  -- M-11, N-1). Each action runs in a probe on one case, undone after.
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, sla_due_at)
  VALUES ('report', 'P1', v_p, now() + interval '1 day') RETURNING id INTO v_a;
  -- (fix round 1, I-2: the reporter is not the acting owner, a party)
  INSERT INTO public.dating_reports (reporter_user_id, target_user_id, category, case_id) VALUES (v_m2, v_p, 'underage_risk', v_a);
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state, rejection_reason)
  VALUES (v_p, 'w7/l2-lock.jpg', 3, 'needs_review', 'clear', 'needs_review') RETURNING id INTO v_photo;
  IF pg_temp.setup_locked(v_p) THEN
    RAISE EXCEPTION 'w7 fixture: the lock person''s setup lock is already held';
  END IF;
  v_got := '';
  FOREACH v_sql IN ARRAY ARRAY[
    v_watch || format('; SELECT public.moderation_claim(%L, %L)', v_o, v_a),
    v_watch || format('; SELECT public.moderation_place_hold(%L, %L, ''harassment'')', v_o, v_a),
    format($f$INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, appealable)
              VALUES (%L, 'moderation_hold', 'harassment', 'moderator', %L, false); %s;
              SELECT public.moderation_lift_hold(%L, %L)$f$, v_p, v_a, v_watch, v_o, v_a),
    format($f$INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, appealable)
              VALUES (%L, 'moderation_hold', 'harassment', 'report', %L, false); %s;
              SELECT public.moderation_dismiss(%L, %L)$f$, v_p, v_a, v_watch, v_o, v_a),
    v_watch || format('; SELECT public.moderation_restrict(%L, %L, ''suspended'', now() + interval ''7 days'', ''harassment'')', v_o, v_a),
    v_watch || format('; SELECT public.moderation_ask_for_id(%L, %L)', v_o, v_a),
    v_watch || format('; SELECT public.moderation_confirm_minor(%L, %L)', v_o, v_a),
    v_watch || format('; SELECT public.moderation_note(%L, %L, ''A lock note.'')', v_o, v_a),
    format($f$INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, decided_by, ends_at)
              VALUES (%1$L, 'suspended', 'harassment', 'moderator', %2$L, now() + interval '9 days');
              INSERT INTO public.dating_appeals (restriction_id, user_id)
              SELECT r.id, %1$L FROM public.dating_account_restrictions AS r WHERE r.user_id = %1$L AND r.restriction_type = 'suspended';
              INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, appeal_id, sla_due_at)
              SELECT 'appeal', 'P2', %1$L, a.id, now() + interval '7 days' FROM public.dating_appeals AS a WHERE a.user_id = %1$L;
              %3$s;
              SELECT public.moderation_decide_appeal(%4$L, (SELECT c.id FROM public.dating_moderation_cases AS c
                                                             WHERE c.kind = 'appeal' AND c.target_user_id = %1$L), true)$f$,
           v_p, v_m2, v_watch, v_o),
    v_watch || format('; SELECT public.moderation_photo_decide(%L, %L, true, NULL)', v_o, v_photo)
  ] LOOP
    v_got := v_got || ' [' || pg_temp.probe(ARRAY[v_sql], v_seen) || ']';
  END LOOP;
  IF v_got ~ ':false|\|false' OR v_got !~ '^( \[[^]]*\|true\]){10}$'
     OR v_got NOT LIKE '%dating_appeals:true%' OR v_got NOT LIKE '%dating_profile_photos:true%'
     OR v_got NOT LIKE '%dating_reports:true%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a console write reached a row before the person''s setup lock: %', v_got;
  END IF;

  -- (2) Replays (Task 2 M-11): the same call again answers as the first
  -- did and writes no second audit row.
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, sla_due_at)
  VALUES ('report', 'P1', v_q1, now() + interval '1 day') RETURNING id INTO v_b;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, sla_due_at)
  VALUES ('report', 'P1', v_q2, now() + interval '1 day') RETURNING id INTO v_c;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, sla_due_at)
  VALUES ('report', 'P1', v_q3, now() + interval '1 day') RETURNING id INTO v_d;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, sla_due_at)
  VALUES ('report', 'P0', v_q4, now() + interval '1 day') RETURNING id INTO v_e;
  INSERT INTO public.dating_reports (reporter_user_id, target_user_id, category, case_id) VALUES (v_o, v_q4, 'underage_risk', v_e);
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state, rejection_reason)
  VALUES (v_q1, 'w7/l2-replay.jpg', 3, 'needs_review', 'clear', 'needs_review') RETURNING id INTO v_photo;
  INSERT INTO public.dating_verification_sessions (user_id, kind, step, state, gestures, expires_at, awaiting_since)
  VALUES (v_q1, 'activation', 'human', 'awaiting_review', ARRAY['wave', 'thumbs_up'], now() + interval '1 day', now())
  RETURNING id INTO v_session;
  v_got := '';
  FOREACH v_sql IN ARRAY ARRAY[
    format('public.moderation_claim(%L, %L)', v_m, v_b),
    format('public.moderation_note(%L, %L, ''Seen twice.'')', v_m, v_b),
    format('public.moderation_place_hold(%L, %L, ''harassment'')', v_m, v_b),
    format('public.moderation_lift_hold(%L, %L)', v_m, v_b),
    format('public.moderation_dismiss(%L, %L)', v_m, v_b),
    format('public.moderation_restrict(%L, %L, ''suspended'', %L::timestamptz, ''threats'')', v_m, v_c,
           date_trunc('second', now() + interval '20 days')),
    format('public.moderation_ask_for_id(%L, %L)', v_m, v_d),
    format('public.moderation_confirm_minor(%L, %L)', v_m, v_e),
    format('public.moderation_photo_decide(%L, %L, false, ''unsafe'')', v_m, v_photo),
    format('public.moderation_verification_decide(%L, %L, ''ask_for_id'')', v_m, v_session)
  ] LOOP
    EXECUTE 'SELECT ' || v_sql INTO v_first;
    EXECUTE 'SELECT ' || v_sql INTO v_again;
    v_got := v_got || ' ' || split_part(split_part(v_sql, '(', 1), '_', 2) || '=' || (v_first = v_again)::text
             || '/' || coalesce(v_first ->> 'ok', v_first ->> 'reason');
  END LOOP;
  -- The appeal of the restriction just placed, decided twice by another.
  SELECT id INTO v_restr FROM public.dating_account_restrictions WHERE user_id = v_q2 AND lifted_at IS NULL AND case_id = v_c;
  PERFORM pg_temp.j(v_q2, '116', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', pg_temp.key('l2-ap'), v_restr));
  SELECT c.id INTO v_ap FROM public.dating_moderation_cases AS c JOIN public.dating_appeals AS a ON a.id = c.appeal_id
   WHERE a.restriction_id = v_restr;
  v_first := public.moderation_decide_appeal(v_m2, v_ap, false);
  v_again := public.moderation_decide_appeal(v_m2, v_ap, false);
  v_got := v_got || ' appeal=' || (v_first = v_again)::text || '/' || coalesce(v_first ->> 'ok', v_first ->> 'reason');
  -- S1 W9b's removal, as the service role: called once.
  v_sql := gen_random_uuid()::text;
  PERFORM pg_temp.as_service(format($f$SELECT set_config('w7.op1', public.moderation_opinions_remove(%L, 'comment', %L)::text, true)$f$,
                                    v_m, v_sql));
  PERFORM pg_temp.as_service(format($f$SELECT set_config('w7.op2', public.moderation_opinions_remove(%L, 'comment', %L)::text, true)$f$,
                                    v_m, v_sql));
  v_got := v_got || ' opinions=' || (current_setting('w7.op1', true) = current_setting('w7.op2', true))::text
           || '/' || coalesce(current_setting('w7.op1', true)::jsonb ->> 'ok', '-');
  v_got := v_got || ' |' || concat_ws(',', pg_temp.audit_rows(v_m, v_b, 'claim'), pg_temp.audit_rows(v_m, v_b, 'note'),
                                      pg_temp.audit_rows(v_m, v_b, 'hold'), pg_temp.audit_rows(v_m, v_b, 'lift_hold'),
                                      pg_temp.audit_rows(v_m, v_b, 'dismiss'), pg_temp.audit_rows(v_m, v_c, 'restrict'),
                                      pg_temp.audit_rows(v_m, v_d, 'ask_for_id'), pg_temp.audit_rows(v_m, v_e, 'confirm_minor'),
                                      pg_temp.audit_rows(v_m, NULL, 'photo_decide'), pg_temp.audit_rows(v_m, NULL, 'verification_decide'),
                                      pg_temp.audit_rows(v_m2, v_ap, 'decide_appeal'), pg_temp.audit_rows(v_m, NULL, 'opinions_remove'));
  IF v_got IS DISTINCT FROM ' claim=true/true note=true/true place=true/true lift=true/true dismiss=true/true restrict=true/true'
                            || ' ask=true/true confirm=true/true photo=true/true verification=true/true appeal=true/true'
                            || ' opinions=true/true |1,1,1,1,1,1,1,1,1,1,1,1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed console action answered differently or wrote a second audit row: %', v_got;
  END IF;
  IF public.moderation_lift_hold(v_m, v_b) ->> 'lifted' IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed lift did not answer the first lift''s count';
  END IF;
  -- Another moderator's same call is no replay of the first's.
  v_got := (public.moderation_dismiss(v_m2, v_b) ->> 'reason');
  v_got := v_got || '/' || (public.moderation_note(v_m2, v_b, 'Seen twice.') ->> 'ok') || '/' || pg_temp.audit_rows(v_m2, v_b, 'note');
  IF v_got IS DISTINCT FROM 'case_unavailable/true/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another moderator''s call was taken for a replay: %', v_got;
  END IF;

  -- (3) R1-3: nobody recorded as deciding the restriction: decider_unknown
  -- (not same_decider) until the safety owner, 24 hours after the appeal.
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, ends_at, appealable)
  VALUES (v_u, 'suspended', 'harassment', 'moderator', now() + interval '10 days', true) RETURNING id INTO v_restr;
  PERFORM pg_temp.j(v_u, '120', format('SELECT public.submit_dating_appeal(%L, %L, NULL)', pg_temp.key('l2-r13'), v_restr));
  SELECT c.id INTO v_ap FROM public.dating_moderation_cases AS c JOIN public.dating_appeals AS a ON a.id = c.appeal_id
   WHERE a.restriction_id = v_restr;
  v_got := (public.moderation_decide_appeal(v_m, v_ap, true) ->> 'reason');
  v_got := v_got || '/' || (public.moderation_decide_appeal(v_o, v_ap, true) ->> 'reason');
  v_got := v_got || '/' || coalesce(public.moderation_case(v_m, v_ap) #>> '{appeal,restriction,decider_known}', '-');
  UPDATE public.dating_appeals SET submitted_at = now() - interval '25 hours' WHERE restriction_id = v_restr;
  v_got := v_got || '/' || (public.moderation_decide_appeal(v_o, v_ap, false) ->> 'ok');
  IF v_got IS DISTINCT FROM 'decider_unknown/decider_unknown/false/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an appeal with no recorded decider read % (decider_unknown until the owner at 24 h)', v_got;
  END IF;

  -- (4) W6 T5: dismissing a signal case stamps decided_at, and the
  -- cleared-signal filter reads it.
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind)
  VALUES ('signal', 'P2', v_s, 'dragnet') RETURNING id INTO v_sig;
  v := public.moderation_dismiss(v_m, v_sig);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT state || '/' || outcome || '/' || (decided_at IS NOT NULL) FROM public.dating_moderation_cases WHERE id = v_sig)
        IS DISTINCT FROM 'decided/dismissed/true'
     OR NOT private.dating_signal_cleared(v_s, 'dragnet', now() - interval '14 days') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dismissing a signal case read % or left decided_at (the cleared filter) unset', v;
  END IF;

  -- (5) W6 M-16: a later hit's linked match counts for the families and the
  -- routing (here a man and a man: routed).
  v_m1 := pg_temp.match(v_h, v_w);
  v_mx := pg_temp.match(v_h, v_x);
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind, match_id)
  VALUES ('signal', 'P1', v_h, 'chat_financial_request', v_m1) RETURNING id INTO v_s1;
  INSERT INTO public.dating_case_matches (case_id, match_id) VALUES (v_s1, v_m1), (v_s1, v_mx);
  INSERT INTO public.dating_safety_events (match_id, at_risk_user_id, sender_user_id, rule_id, family, tier, config_version,
                                           source_event_key)
  VALUES (v_m1, v_w, v_h, 'financial_request:momo', 'financial_request', 2, 'dating_chat_v1', 'w7-l2-money'),
         (v_mx, v_x, v_h, 'sexual_pressure:x', 'sexual_pressure', 1, 'dating_chat_v1', 'w7-l2-later');
  v := public.moderation_case(v_o, v_s1);
  v_got := private.dating_case_needs_sensitive_routing(v_s1)::text || '/'
        || pg_temp.probe(ARRAY[format('DELETE FROM public.dating_case_matches WHERE case_id = %L AND match_id = %L', v_s1, v_mx)],
                         format('SELECT private.dating_case_needs_sensitive_routing(%L)::text', v_s1)) || '/'
        || (public.moderation_case(v_m, v_s1) ->> 'reason');
  IF v_got IS DISTINCT FROM 'true/false/case_unavailable'
     OR (SELECT array_agg(f ORDER BY f) FROM jsonb_array_elements_text(v -> 'families') AS f)
        IS DISTINCT FROM ARRAY['financial_request', 'sexual_pressure'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a later hit''s linked match was missed by the routing or the families: % %', v_got, v -> 'families';
  END IF;

  -- (6) S-5 by inference: without routing, the audit log has no row of a
  -- routed case, and an earlier case carries no id (all of them listed).
  PERFORM public.moderation_dismiss(v_o, v_s1); -- fix round 1 (M-2): a decided routed earlier case is still listed
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind)
  VALUES ('signal', 'P2', v_h, 'dragnet') RETURNING id INTO v_s2;
  v_first := public.moderation_case(v_m, v_s2);
  v_again := public.moderation_case(v_o, v_s2);
  IF jsonb_array_length(v_first -> 'prior') <> 1 OR v_first -> 'prior' -> 0 ? 'id'
     OR v_again #>> '{prior,0,id}' IS DISTINCT FROM v_s1::text
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_audit_log(v_m, 500) -> 'actions') AS a
                 WHERE (a ->> 'case_id')::uuid = v_s1)
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_audit_log(v_o, 500) -> 'actions') AS a
                     WHERE (a ->> 'case_id')::uuid = v_s1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a moderator without routing can tell a routed case is there: % %', v_first -> 'prior',
      v_again -> 'prior';
  END IF;

  -- (7) not_moderator is counted on every moderation_* function.
  v_n := pg_temp.metric('dating.moderation.not_moderator');
  PERFORM public.moderation_whoami(v_z);
  PERFORM public.moderation_queue(v_z);
  PERFORM public.moderation_case(v_z, v_b);
  PERFORM public.moderation_claim(v_z, v_b);
  PERFORM public.moderation_dismiss(v_z, v_b);
  PERFORM public.moderation_place_hold(v_z, v_b, 'spam');
  PERFORM public.moderation_lift_hold(v_z, v_b);
  PERFORM public.moderation_restrict(v_z, v_b, 'suspended', NULL, 'spam');
  PERFORM public.moderation_ask_for_id(v_z, v_b);
  PERFORM public.moderation_confirm_minor(v_z, v_b);
  PERFORM public.moderation_note(v_z, v_b, 'x');
  PERFORM public.moderation_decide_appeal(v_z, v_ap, true);
  PERFORM public.moderation_photos(v_z);
  PERFORM public.moderation_photo_decide(v_z, v_photo, true, NULL);
  PERFORM public.moderation_verifications(v_z);
  PERFORM public.moderation_verification_decide(v_z, v_session, 'pass');
  PERFORM public.moderation_countries(v_z);
  PERFORM public.moderation_publish_country(v_z, 'GH', '{}');
  PERFORM public.moderation_opinions_queue(v_z, 5);
  PERFORM public.moderation_opinions_remove(v_z, 'comment', gen_random_uuid());
  PERFORM public.moderation_audit_log(v_z, 5);
  IF pg_temp.metric('dating.moderation.not_moderator') - v_n <> 21 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: not_moderator was counted % time(s) over the 21 functions',
      pg_temp.metric('dating.moderation.not_moderator') - v_n;
  END IF;
END $l2$;
DROP TRIGGER w7_t5_seen ON public.dating_moderation_cases;
DROP TRIGGER w7_t5_seen ON public.dating_reports;
DROP TRIGGER w7_t5_seen ON public.dating_account_restrictions;
DROP TRIGGER w7_t5_seen ON public.dating_enrollments;
DROP TRIGGER w7_t5_seen ON public.dating_profile_photos;
DROP TRIGGER w7_t5_seen ON public.dating_appeals;
DROP FUNCTION public.w7_t5_seen();

-- =====================================================================
-- L3. (Task 5 fix round 1: C-1, I-1, I-2, M-2..M-7; R-T3-3) A decision
--     lifts every hold its case placed, whatever placed it (a CSAM hold
--     excepted), and an accepted appeal lifts its case's; Lift hold lifts
--     only its own case's holds and refuses a closed case; a moderator who
--     is a party to a case (its person, a reporter, anyone in its chats,
--     by account or number; an appeal through its restriction's case)
--     never sees it, and is refused on every read and action, counted;
--     likewise their own photos and checks; an open routed earlier case is
--     left out without routing; a write that can't get its locks answers
--     busy, counted; a replayed publish publishes once; a hold refuses an
--     appeal case; a claim takes over another's live claim only for the
--     safety owner or after an hour, and says so; a replay is never one
--     when something changed since; another moderator's decision on a
--     decided case places nothing; an ended chat only a number block ended
--     reads the block's time.
-- =====================================================================
CREATE FUNCTION pg_temp.sig(p_target uuid, p_kind text DEFAULT 'dragnet') RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind)
  VALUES ('signal', 'P2', p_target, p_kind) RETURNING id;
$$;
CREATE FUNCTION public.w7_t5_busy() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'w7 busy' USING ERRCODE = '55P03';
END $$;
DO $l3$
DECLARE
  v_o constant uuid := pg_temp.id('112');
  v_m2 constant uuid := pg_temp.id('113');
  v_m constant uuid := pg_temp.id('119');
  v_t constant uuid := pg_temp.man('126');
  v_mp constant uuid := pg_temp.ready('127');
  v_mx constant uuid := pg_temp.man('128');
  v_w constant uuid := pg_temp.ready('129');
  v_q constant uuid := pg_temp.man('109');
  v_a uuid;
  v_a2 uuid;
  v_b uuid;
  v_c uuid;
  v_r1 uuid;
  v_r2 uuid;
  v_r3 uuid;
  v_r4 uuid;
  v_cl uuid;
  v_h6 uuid;
  v_d7 uuid;
  v_tx uuid;
  v_tp uuid;
  v_wq uuid;
  v_photo uuid;
  v_session uuid;
  v_n bigint;
  v_got text;
  v_held text;
  v jsonb;
  v2 jsonb;
  v_appeal_sql text;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role, sensitive_routing_allowed) VALUES (v_mp, 'moderator', true);

  -- (1) C-1: each decision lifts the holds its case placed (a moderator's
  -- too); a CSAM hold and another case's hold stay.
  v_a := pg_temp.sig(v_t);
  v_a2 := pg_temp.sig(v_t, 'money_asks');
  v_appeal_sql := format($f$SELECT pg_temp.j(%1$L, '126', format('SELECT public.submit_dating_appeal(%%L, %%L, NULL)', pg_temp.key('l3-ap'),
                              (SELECT r.id FROM public.dating_account_restrictions AS r WHERE r.user_id = %1$L
                                  AND r.restriction_type = 'suspended' AND r.lifted_at IS NULL)))$f$, v_t);
  v_got := concat_ws(' | ',
    pg_temp.probe(ARRAY[format('SELECT public.moderation_place_hold(%L, %L, ''harassment'')', v_m, v_a),
                        format('SELECT public.moderation_dismiss(%L, %L)', v_m, v_a)],
                  format('SELECT pg_temp.held(%L)', v_t)),
    pg_temp.probe(ARRAY[format('SELECT public.moderation_place_hold(%L, %L, ''harassment'')', v_m, v_a),
                        format('SELECT public.moderation_restrict(%L, %L, ''suspended'', now() + interval ''5 days'', ''threats'')', v_m, v_a)],
                  format('SELECT pg_temp.held(%L)', v_t)),
    pg_temp.probe(ARRAY[format('SELECT public.moderation_place_hold(%L, %L, ''harassment'')', v_m, v_a),
                        format('SELECT public.moderation_ask_for_id(%L, %L)', v_m, v_a)],
                  format('SELECT pg_temp.held(%L)', v_t)),
    pg_temp.probe(ARRAY[format('INSERT INTO public.dating_reports (reporter_user_id, target_user_id, category, case_id) VALUES (%L, %L, ''underage_risk'', %L)',
                               v_w, v_t, v_a),
                        format('SELECT public.moderation_place_hold(%L, %L, ''harassment'')', v_m, v_a),
                        format('SELECT public.moderation_confirm_minor(%L, %L)', v_m, v_a)],
                  format('SELECT pg_temp.held(%L)', v_t)),
    pg_temp.probe(ARRAY[format('SELECT public.moderation_restrict(%L, %L, ''suspended'', now() + interval ''5 days'', ''threats'')', v_m, v_a),
                        format($f$INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, appealable)
                                  VALUES (%L, 'moderation_hold', 'threats', 'moderator', %L, false)$f$, v_t, v_a),
                        v_appeal_sql,
                        format($f$SELECT public.moderation_decide_appeal(%L, (SELECT c.id FROM public.dating_moderation_cases AS c
                                    JOIN public.dating_appeals AS a ON a.id = c.appeal_id WHERE a.user_id = %L), true)$f$, v_m2, v_t)],
                  format('SELECT pg_temp.held(%L)', v_t)),
    pg_temp.probe(ARRAY[format($f$INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, appealable)
                                  VALUES (%1$L, 'moderation_hold', 'csam', 'csam_hash', %2$L, false),
                                         (%1$L, 'moderation_hold', 'spam', 'moderator', %3$L, false)$f$, v_t, v_a, v_a2),
                        format('SELECT public.moderation_dismiss(%L, %L)', v_m, v_a)],
                  format($f$SELECT string_agg(r.source || ':' || (r.case_id = %L), ',' ORDER BY r.source)
                              FROM public.dating_account_restrictions AS r WHERE r.user_id = %L AND r.lifted_at IS NULL$f$, v_a, v_t)));
  IF v_got IS DISTINCT FROM ' | suspended/moderator/threats/true | age_review/moderator/underage_risk/false'
                            || ' | age_review/moderator/underage_risk/false |  | csam_hash:true,moderator:false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a decision left a hold its case placed (or took a CSAM or another case''s hold): %', v_got;
  END IF;

  -- (2) I-1: Lift hold lifts only its own case's holds (a routed case's
  -- hold is untouched through a visible case) and refuses a closed case.
  v_tx := pg_temp.match(v_t, v_mx);
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind, match_id)
  VALUES ('signal', 'P1', v_t, 'chat_financial_request', v_tx) RETURNING id INTO v_b;
  INSERT INTO public.dating_case_matches (case_id, match_id) VALUES (v_b, v_tx);
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, decided_by, appealable)
  VALUES (v_t, 'moderation_hold', 'harassment', 'moderator', v_b, v_o, false);
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind, state, decided_at, outcome)
  VALUES ('signal', 'P3', v_q, 'device_accounts', 'closed', now(), 'no_action') RETURNING id INTO v_c;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, appealable)
  VALUES (v_q, 'moderation_hold', 'spam', 'moderator', v_c, false);
  v_got := public.moderation_lift_hold(v_m, v_a) ->> 'lifted';
  v_got := v_got || '/' || (SELECT count(*) FROM public.dating_account_restrictions WHERE case_id = v_b AND lifted_at IS NULL);
  v_got := v_got || '/' || (public.moderation_lift_hold(v_m, v_b) ->> 'reason');
  v_got := v_got || '/' || coalesce(public.moderation_lift_hold(v_m, v_c) ->> 'reason', 'ok');
  v_got := v_got || '/' || pg_temp.held(v_q);
  IF v_got IS DISTINCT FROM '0/1/case_unavailable/case_unavailable/moderation_hold/moderator/spam/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Lift hold reached past its own open case: %', v_got;
  END IF;
  UPDATE public.dating_account_restrictions SET lifted_at = now() WHERE case_id IN (v_b, v_c) AND lifted_at IS NULL;

  -- (3) I-2: a party to a case never sees it: its reporter (by account,
  -- in its chat), its person, anyone in a linked chat, its number; an
  -- appeal through its restriction's case; their own photo and check.
  -- Refusals are counted.
  v_tp := pg_temp.match(v_t, v_mp);
  -- A card's report (no chat): the reporter rule alone.
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, sla_due_at)
  VALUES ('report', 'P1', v_t, now() + interval '1 day') RETURNING id INTO v_r1;
  INSERT INTO public.dating_reports (reporter_user_id, target_user_id, category, case_id)
  VALUES (v_mp, v_t, 'harassment', v_r1);
  v_r2 := pg_temp.sig(v_mp);
  v_r3 := pg_temp.sig(v_t, 'sexual_pressure');
  INSERT INTO public.dating_case_matches (case_id, match_id) VALUES (v_r3, v_tp);
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, signal_kind)
  VALUES ('signal', 'P2', NULL, public.dating_phone_hmac_for_user(v_mp), 'dragnet') RETURNING id INTO v_r4;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state, rejection_reason)
  VALUES (v_mp, 'w7/l3-own.jpg', 3, 'needs_review', 'clear', 'needs_review') RETURNING id INTO v_photo;
  INSERT INTO public.dating_verification_sessions (user_id, kind, step, state, gestures, expires_at, awaiting_since)
  VALUES (v_mp, 'activation', 'human', 'awaiting_review', ARRAY['wave', 'thumbs_up'], now() + interval '1 day', now())
  RETURNING id INTO v_session;
  PERFORM public.moderation_case(v_m, v_r1); -- another moderator's reading (an audit row of the case)
  v_n := pg_temp.metric('dating.moderation.party_refused');
  v_got := concat_ws(',', public.moderation_case(v_mp, v_r1) ->> 'reason', public.moderation_case(v_mp, v_r2) ->> 'reason',
                          public.moderation_case(v_mp, v_r3) ->> 'reason', public.moderation_case(v_mp, v_r4) ->> 'reason');
  v_got := v_got || ',' || (public.moderation_dismiss(v_mp, v_r1) ->> 'reason');
  v_got := v_got || ',' || (public.moderation_claim(v_mp, v_r3) ->> 'reason');
  v_got := v_got || ',' || (public.moderation_photo_decide(v_mp, v_photo, true, NULL) ->> 'reason');
  v_got := v_got || ',' || (public.moderation_verification_decide(v_mp, v_session, 'ask_for_id') ->> 'reason');
  v_got := v_got || ',' || (pg_temp.metric('dating.moderation.party_refused') - v_n);
  v_got := v_got || ',' || pg_temp.probe(ARRAY[
             format($f$INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, decided_by, ends_at)
                       VALUES (%L, 'suspended', 'harassment', 'moderator', %L, %L, now() + interval '9 days')$f$, v_t, v_r1, v_o),
             format($f$INSERT INTO public.dating_appeals (restriction_id, user_id) SELECT r.id, %1$L FROM public.dating_account_restrictions AS r
                        WHERE r.user_id = %1$L AND r.restriction_type = 'suspended' AND r.lifted_at IS NULL$f$, v_t),
             format($f$INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, appeal_id, sla_due_at)
                       SELECT 'appeal', 'P2', %1$L, a.id, now() + interval '7 days' FROM public.dating_appeals AS a WHERE a.user_id = %1$L$f$, v_t)],
             format($f$SELECT (public.moderation_case(%L, (SELECT c.id FROM public.dating_moderation_cases AS c
                                 JOIN public.dating_appeals AS a ON a.id = c.appeal_id WHERE a.user_id = %L)) ->> 'reason')$f$, v_mp, v_t));
  IF v_got IS DISTINCT FROM 'case_unavailable,case_unavailable,case_unavailable,case_unavailable,case_unavailable,case_unavailable,'
                            || 'photo_unavailable,session_unavailable,8,case_unavailable'
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_queue(v_mp, 200) -> 'cases') AS c
                 WHERE (c ->> 'id')::uuid IN (v_r1, v_r2, v_r3, v_r4))
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_queue(v_m, 200) -> 'cases') AS c WHERE (c ->> 'id')::uuid = v_r1)
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_audit_log(v_mp, 500) -> 'actions') AS a
                 WHERE (a ->> 'case_id')::uuid IN (v_r1, v_r2, v_r3, v_r4))
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_photos(v_mp) -> 'photos') AS p WHERE (p ->> 'id')::uuid = v_photo)
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_photos(v_m) -> 'photos') AS p WHERE (p ->> 'id')::uuid = v_photo)
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_verifications(v_mp) -> 'sessions') AS s
                 WHERE (s ->> 'id')::uuid = v_session)
     OR (SELECT state FROM public.dating_moderation_cases WHERE id = v_r1) <> 'open' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a moderator who is a party to a case saw or acted on it: %', v_got;
  END IF;

  -- (4) M-2: without routing, an open routed earlier case is left out (the
  -- routed case v_b is still open).
  IF jsonb_array_length(public.moderation_case(v_o, v_a) -> 'prior') - jsonb_array_length(public.moderation_case(v_m, v_a) -> 'prior') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an open routed earlier case was listed without routing';
  END IF;

  -- (5) M-3: a write that can't get its locks answers busy, counted; every
  -- console write waits at most 2 s; a replayed publish publishes once.
  v_n := pg_temp.metric('dating.moderation.busy');
  v_got := pg_temp.probe(ARRAY['CREATE TRIGGER w7_t5_busy BEFORE UPDATE ON public.dating_moderation_cases FOR EACH ROW EXECUTE FUNCTION public.w7_t5_busy()',
                               -- a raise (no busy answer) reads as a missing answer
                               format($f$SELECT pg_temp.try_sql(format('SELECT set_config(''w7.busy'', public.moderation_dismiss(%%L, %%L)::text, true)', %L, %L))$f$,
                                      v_m, v_a)],
                         format($f$SELECT current_setting('w7.busy', true) || '/' || (pg_temp.metric('dating.moderation.busy') - %s)$f$, v_n));
  IF v_got IS DISTINCT FROM '{"ok": false, "reason": "busy"}/1'
     OR NOT (public.get_dating_operational_health() -> 'safety_counters_7d') ?& ARRAY['dating.moderation.busy', 'dating.moderation.party_refused'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a console write that could not get its locks read % (busy, counted, listed)', v_got;
  END IF;
  SELECT string_agg(p.proname, ', ') INTO v_got FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname IN ('moderation_claim', 'moderation_dismiss', 'moderation_place_hold', 'moderation_lift_hold',
           'moderation_restrict', 'moderation_ask_for_id', 'moderation_confirm_minor', 'moderation_note', 'moderation_decide_appeal',
           'moderation_photo_decide', 'moderation_verification_decide', 'moderation_publish_country', 'moderation_opinions_remove')
     AND NOT coalesce('lock_timeout=2s' = ANY (p.proconfig), false);
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a console write has no 2 s lock_timeout: %', v_got;
  END IF;
  v_n := (SELECT count(*) FROM public.country_safety_config WHERE country_code = 'GB');
  v := public.moderation_publish_country(v_o, 'GB', '{"dating_enabled": true, "open_regions": ["TLI"]}');
  v2 := public.moderation_publish_country(v_o, 'GB', '{"dating_enabled": true, "open_regions": ["TLI"]}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v2 ->> 'version' IS DISTINCT FROM v ->> 'version' OR (v2 ->> 'ok')::boolean IS NOT TRUE
     OR (SELECT count(*) FROM public.country_safety_config WHERE country_code = 'GB') <> v_n + 1
     OR (SELECT count(*) FROM public.dating_moderation_actions WHERE actor_id = v_o AND action = 'publish_country'
          AND detail ->> 'country' = 'GB') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed publish published again: % / %', v, v2;
  END IF;

  -- (6) M-4: a hold refuses an appeal case.
  v_got := pg_temp.probe(ARRAY[
             format($f$INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, decided_by, ends_at)
                       VALUES (%L, 'suspended', 'spam', 'moderator', %L, now() + interval '9 days')$f$, v_q, v_o),
             format($f$INSERT INTO public.dating_appeals (restriction_id, user_id) SELECT r.id, %1$L FROM public.dating_account_restrictions AS r
                        WHERE r.user_id = %1$L AND r.restriction_type = 'suspended' AND r.lifted_at IS NULL$f$, v_q),
             format($f$INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, appeal_id, sla_due_at)
                       SELECT 'appeal', 'P2', %1$L, a.id, now() + interval '7 days' FROM public.dating_appeals AS a WHERE a.user_id = %1$L$f$, v_q)],
             format($f$SELECT (public.moderation_place_hold(%L, (SELECT c.id FROM public.dating_moderation_cases AS c
                                 JOIN public.dating_appeals AS a ON a.id = c.appeal_id WHERE a.user_id = %L), 'spam') ->> 'reason')$f$, v_m, v_q));
  IF v_got IS DISTINCT FROM 'case_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hold was placed through an appeal case: %', v_got;
  END IF;

  -- (7) M-5: a live claim is taken over only by the safety owner, or after
  -- an hour of the claimer's silence, and the answer says so (audited).
  v_cl := pg_temp.sig(v_q, 'duplicate_opener');
  v_got := public.moderation_claim(v_m, v_cl)::text;
  v_got := v_got || ' ' || public.moderation_claim(v_m2, v_cl)::text;
  v_got := v_got || ' ' || public.moderation_claim(v_o, v_cl)::text;
  v_got := v_got || ' ' || pg_temp.probe(ARRAY[
             'ALTER TABLE public.dating_moderation_actions DISABLE TRIGGER dating_moderation_actions_append_only',
             format($f$UPDATE public.dating_moderation_actions SET created_at = now() - interval '61 minutes' WHERE case_id = %L$f$, v_cl),
             'ALTER TABLE public.dating_moderation_actions ENABLE TRIGGER dating_moderation_actions_append_only'],
             format('SELECT public.moderation_claim(%L, %L)::text', v_m2, v_cl));
  IF v_got IS DISTINCT FROM '{"ok": true} {"ok": false, "reason": "claimed"} {"ok": true, "took_over": true} {"ok": true, "took_over": true}'
     OR NOT EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE actor_id = v_o AND case_id = v_cl AND action = 'claim'
                       AND detail = '{"took_over": true}'::jsonb)
     OR (SELECT assigned_to FROM public.dating_moderation_cases WHERE id = v_cl) IS DISTINCT FROM v_o THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a live claim was taken over silently or by anyone: %', v_got;
  END IF;

  -- (8) M-6: no replay once something changed since: a hold again while
  -- another hold of the case is live is a new hold; a lift after a newer
  -- hold of the case answers its own count.
  v_h6 := pg_temp.sig(v_q, 'money_asks');
  PERFORM public.moderation_place_hold(v_m, v_h6, 'spam');
  PERFORM public.moderation_lift_hold(v_m, v_h6);
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, appealable)
  VALUES (v_q, 'moderation_hold', 'spam', 'report', v_h6, false);
  v_got := public.moderation_place_hold(v_m, v_h6, 'spam') ->> 'ok';
  v_got := v_got || '/' || pg_temp.audit_rows(v_m, v_h6, 'hold');
  v_got := v_got || '/' || (public.moderation_lift_hold(v_m, v_h6) ->> 'lifted');
  PERFORM public.moderation_place_hold(v_o, v_h6, 'spam');
  PERFORM public.moderation_lift_hold(v_o, v_h6);
  v_got := v_got || '/' || (public.moderation_lift_hold(v_m, v_h6) ->> 'lifted') || '/' || pg_temp.audit_rows(v_m, v_h6, 'lift_hold');
  IF v_got IS DISTINCT FROM 'true/2/2/0/3' THEN -- W7 final (I-2): the moderator's hold is its own row; the lift lifts both
    RAISE EXCEPTION 'CONTRACT VIOLATED: a changed case''s call was taken for a replay: %', v_got;
  END IF;

  -- (9) M-7: another moderator's decision on a case already decided
  -- places nothing.
  v_d7 := pg_temp.sig(v_q, 'location_mismatch');
  INSERT INTO public.dating_reports (reporter_user_id, target_user_id, category, case_id) VALUES (v_w, v_q, 'underage_risk', v_d7);
  v_held := pg_temp.held(v_q);
  PERFORM public.moderation_dismiss(v_m, v_d7);
  v_got := concat_ws(',',
    public.moderation_restrict(v_m2, v_d7, 'suspended', now() + interval '3 days', 'spam') ->> 'reason',
    public.moderation_ask_for_id(v_m2, v_d7) ->> 'reason',
    public.moderation_confirm_minor(v_m2, v_d7) ->> 'reason');
  IF v_got IS DISTINCT FROM 'case_unavailable,case_unavailable,case_unavailable' OR pg_temp.held(v_q) IS DISTINCT FROM v_held
     OR EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_q AND reason_ref = v_d7::text) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a decision on a decided case placed something: % (%)', v_got, pg_temp.held(v_q);
  END IF;

  -- (10) R-T3-3: a chat only the numbers' block ended reads the block's
  -- time as its end, not the match's.
  v_wq := pg_temp.match(v_w, v_q);
  UPDATE public.dating_matches SET matched_at = now() - interval '20 days' WHERE id = v_wq;
  INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac, created_at, purge_after)
  VALUES (public.dating_phone_hmac_for_user(v_w), public.dating_phone_hmac_for_user(v_q), now() - interval '5 days', now() + interval '1 year');
  v := pg_temp.j(v_w, '129', 'SELECT public.get_my_dating_matches(true)');
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'ended') AS e
                  WHERE (e ->> 'match_id')::uuid = v_wq
                    AND abs(extract(epoch FROM (e ->> 'ended_at')::timestamptz - (now() - interval '5 days'))) < 60) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chat only a number block ended reads % as its end', v -> 'ended';
  END IF;
END $l3$;
DROP FUNCTION public.w7_t5_busy();

-- =====================================================================
-- M. (§4.6, §6.5) SLA alerts: every 15 minutes; past its clock, one
--    content-free line per priority about the oldest case ("P0 case
--    waiting 3 h 40 m"), to the webhook; without one, counted, nothing
--    sent.
-- =====================================================================
-- pg_net replaced, inside this transaction only, by a recorder (the
-- reaction_push_kick contract's way).
CREATE TEMP TABLE w7_posts (url text, body jsonb) ON COMMIT DROP;
CREATE OR REPLACE FUNCTION net.http_post(
  url text, body jsonb DEFAULT '{}'::jsonb, params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000)
RETURNS bigint LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('test.post_fails', true) = 'on' THEN
    RAISE EXCEPTION 'stub: pg_net is down';
  END IF;
  INSERT INTO pg_temp.w7_posts VALUES (url, body);
  RETURN 1;
END $$;
DO $m$
DECLARE
  v_t constant uuid := pg_temp.man('110');
  v_n bigint := pg_temp.metric('dating.sla.alert_unconfigured');
  v_f bigint := pg_temp.metric('dating.sla.alert_failed');
  v jsonb;
BEGIN
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, sla_due_at, created_at)
  VALUES ('report', 'P0', v_t, now() - interval '1 hour', now() - interval '3 hours 40 minutes');
  PERFORM set_config('app.settings.moderation_alert_webhook', '', true);
  v := public.dating_moderation_sla_check(now());
  IF (v ->> 'alerts')::int <> 0 OR pg_temp.metric('dating.sla.alert_unconfigured') <= v_n
     OR EXISTS (SELECT 1 FROM pg_temp.w7_posts) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without a webhook the check read % (counted, nothing sent)', v;
  END IF;
  PERFORM set_config('app.settings.moderation_alert_webhook', 'https://alerts.invalid/hook', true);
  v := public.dating_moderation_sla_check(now());
  IF (v ->> 'alerts')::int < 1
     OR NOT EXISTS (SELECT 1 FROM pg_temp.w7_posts AS q
                     WHERE q.url = 'https://alerts.invalid/hook' AND q.body = '{"text": "P0 case waiting 3 h 40 m"}'::jsonb)
     OR EXISTS (SELECT 1 FROM pg_temp.w7_posts AS q
                 WHERE (SELECT array_agg(k) FROM jsonb_object_keys(q.body) AS k) <> ARRAY['text']
                    OR q.body ->> 'text' !~ '^P[0-3] case waiting [0-9]+ h [0-9]+ m$')
     OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-moderation-sla' AND schedule = '11-59/15 * * * *' -- W7 final (M-4)
                       AND command = 'SELECT public.dating_moderation_sla_check()') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the SLA alert is missing, carries more than its line, or has no cron';
  END IF;
  PERFORM set_config('test.post_fails', 'on', true);
  PERFORM public.dating_moderation_sla_check(now());
  IF pg_temp.metric('dating.sla.alert_failed') <= v_f THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed alert was not counted';
  END IF;
  PERFORM set_config('test.post_fails', '', true);
  PERFORM set_config('app.settings.moderation_alert_webhook', '', true);
END $m$;

-- M2. (Task 5 fix round 1, M-7) One line per priority: two P1 cases past
-- their clock give one P1 line, about the older.
DO $m2$
DECLARE
  v_t constant uuid := pg_temp.id('110');
  v jsonb;
BEGIN
  DELETE FROM pg_temp.w7_posts;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind, sla_due_at, created_at)
  VALUES ('signal', 'P1', v_t, 'money_asks', now() - interval '1 hour', now() - interval '5 hours 7 minutes'),
         ('signal', 'P1', v_t, 'sexual_pressure', now() - interval '1 hour', now() - interval '2 hours');
  PERFORM set_config('app.settings.moderation_alert_webhook', 'https://alerts.invalid/hook', true);
  v := public.dating_moderation_sla_check(now());
  IF (SELECT count(*) FROM pg_temp.w7_posts AS q WHERE q.body ->> 'text' LIKE 'P1 %') <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_temp.w7_posts AS q WHERE q.body ->> 'text' = 'P1 case waiting 5 h 7 m') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two P1 cases past their clock did not give one line about the older: %',
      (SELECT string_agg(q.body ->> 'text', ', ') FROM pg_temp.w7_posts AS q);
  END IF;
  PERFORM set_config('app.settings.moderation_alert_webhook', '', true);
END $m2$;

-- =====================================================================
-- N. (§6.5, §7.1 escalation rows) An escalation is a record of what a
--    person did, never an automatic send: the console records its kind
--    (CSA 292 only as the victim's-consent kind) and one audit row;
--    nothing that names the table makes a call, and no trigger sits on it.
-- =====================================================================
DO $n$
DECLARE
  v_mod constant uuid := pg_temp.ready('130');
  v_t constant uuid := pg_temp.man('131');
  v_r constant uuid := pg_temp.ready('132');
  v_case uuid;
  v_posts bigint := (SELECT count(*) FROM pg_temp.w7_posts);
  v_got text;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator');
  PERFORM pg_temp.report(v_r, '132', pg_temp.match(v_t, v_r), 'sextortion');
  SELECT case_id INTO v_case FROM public.dating_reports WHERE reporter_user_id = v_r;
  v_got := public.moderation_record_escalation(v_mod, v_case, 'csa_292', NULL) ->> 'reason';
  v_got := v_got || ' ' || (public.moderation_record_escalation(v_mod, v_case, 'csa_292_with_consent', 'CSA-2026-0001') ->> 'ok');
  v_got := v_got || ' ' || (public.moderation_record_escalation(v_mod, gen_random_uuid(), 'police', NULL) ->> 'reason');
  IF v_got IS DISTINCT FROM 'invalid true case_unavailable'
     OR (SELECT kind || '/' || reference || '/' || recorded_by FROM public.dating_escalations WHERE case_id = v_case)
        IS DISTINCT FROM 'csa_292_with_consent/CSA-2026-0001/' || v_mod
     OR NOT EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE case_id = v_case AND action = 'escalation'
                       AND detail = '{"kind": "csa_292_with_consent"}'::jsonb) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recording an escalation read % or was not audited', v_got;
  END IF;
  IF (SELECT count(*) FROM pg_temp.w7_posts) <> v_posts
     OR EXISTS (SELECT 1 FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
                 WHERE n.nspname IN ('public', 'private') AND p.prosrc ~ 'dating_escalations'
                   AND p.prosrc ~ '(net\.http_post|invoke_edge_function|scheduled_notifications|pg_notify)')
     OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.dating_escalations'::regclass AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an escalation sends something by itself (§6.5: always a human decision)';
  END IF;
END $n$;

-- =====================================================================
-- O. (§6.4 Law-enforcement log, §6.6) The log is the safety owner's: a
--    moderator can't read it, record in it or read the summary; a request
--    is recorded pending, then decided (what was disclosed named; refused
--    and contested name nothing), the person's notice stamped once; bad
--    input names nothing; the audit holds the decision only.
-- =====================================================================
DO $o$
DECLARE
  v_mod constant uuid := pg_temp.ready('133');
  v_owner constant uuid := pg_temp.ready('134');
  v_t constant uuid := pg_temp.man('135');
  v jsonb;
  v_id uuid;
  v_got text;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator');
  INSERT INTO public.dating_moderators (user_id, role, sensitive_routing_allowed) VALUES (v_owner, 'safety_owner', true);
  v_got := concat_ws(' ', public.moderation_le_requests(v_mod) ->> 'reason',
                          public.moderation_record_le_request(v_mod, NULL, '{}') ->> 'reason',
                          public.moderation_transparency_summary(v_mod, '2026-07-01', '2026-10-01') ->> 'reason');
  IF v_got IS DISTINCT FROM 'safety_owner_only safety_owner_only safety_owner_only' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a moderator reached the law-enforcement log: %', v_got;
  END IF;
  v := public.moderation_record_le_request(v_owner, NULL, jsonb_build_object(
         'received_at', now() - interval '2 days', 'jurisdiction', 'GH', 'legal_basis', 'Court order 12/2026',
         'scope', 'Account details of one user', 'target_user_id', v_t));
  v_id := (v ->> 'id')::uuid;
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR (SELECT decision || '/' || (decided_at IS NULL) || '/' || target_user_id FROM public.law_enforcement_requests WHERE id = v_id)
        IS DISTINCT FROM 'pending/true/' || v_t THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recording a request read %', v;
  END IF;
  v_got := concat_ws(' ',
    public.moderation_record_le_request(v_owner, v_id, '{"decision": "disclosed"}') ->> 'reason',
    public.moderation_record_le_request(v_owner, v_id, '{"decision": "refused", "disclosed_categories": ["profile"]}') ->> 'reason',
    public.moderation_record_le_request(v_owner, v_id, '{"decision": "disclosed", "disclosed_categories": ["gps"]}') ->> 'reason',
    public.moderation_record_le_request(v_owner, NULL, jsonb_build_object('received_at', now() - interval '1 day', 'jurisdiction', 'Ghana',
                                                                          'legal_basis', 'x', 'scope', 'y')) ->> 'reason',
    public.moderation_record_le_request(v_owner, NULL, '{"received_at": "soon", "jurisdiction": "GH", "legal_basis": "x", "scope": "y"}') ->> 'reason');
  IF v_got IS DISTINCT FROM 'invalid invalid invalid invalid invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: bad decisions or input read %', v_got;
  END IF;
  v := public.moderation_record_le_request(v_owner, v_id,
         '{"decision": "partly_disclosed", "disclosed_categories": ["account", "restrictions"], "user_notified": true}');
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR (SELECT decision || '/' || array_to_string(disclosed_categories, ',') || '/' || (decided_by = v_owner)
                || '/' || (user_notified_at IS NOT NULL)
           FROM public.law_enforcement_requests WHERE id = v_id) IS DISTINCT FROM 'partly_disclosed/account,restrictions/true/true'
     OR jsonb_array_length(public.moderation_le_requests(v_owner) -> 'requests') < 1
     OR EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE action = 'law_enforcement_request'
                   AND actor_id = v_owner AND detail - 'decision' <> '{}'::jsonb) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: deciding a request read %, or the audit holds more than the decision', v;
  END IF;
  PERFORM pg_temp.delete_account(v_t);
  IF (SELECT target_user_id FROM public.law_enforcement_requests WHERE id = v_id) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the log kept a deleted account''s id';
  END IF;
END $o$;

-- =====================================================================
-- P. (§6.6, §4.8) The transparency summary counts exactly what fell in
--    its window (requests by country and decision, those met, reports by
--    category, actions, appeals, overturned; nothing carried, no names);
--    the purge removes the audit, escalations and the log at 2 years.
-- =====================================================================
DO $p$
DECLARE
  v_owner constant uuid := pg_temp.ready('136');
  v_a constant uuid := pg_temp.man('137');
  v_b constant uuid := pg_temp.man('138');
  v_r1 uuid;
  v_r2 uuid;
  v jsonb;
  v_n bigint;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role, sensitive_routing_allowed) VALUES (v_owner, 'safety_owner', true);
  INSERT INTO public.law_enforcement_requests (received_at, jurisdiction, legal_basis, scope, decision, disclosed_categories,
                                               decided_at, decided_by)
  VALUES ('2026-08-01', 'GH', 'order', 'one account', 'disclosed', '{account}', '2026-08-02', v_owner),
         ('2026-08-05', 'GH', 'letter', 'all chats', 'refused', '{}', '2026-08-06', v_owner),
         ('2026-09-01', 'GB', 'warrant', 'one account', 'partly_disclosed', '{account,reports}', '2026-09-02', v_owner),
         ('2026-10-02', 'GB', 'warrant', 'outside', 'refused', '{}', '2026-10-03', v_owner);
  INSERT INTO public.dating_reports (category, created_at) VALUES
    ('harassment', '2026-07-10'), ('harassment', '2026-07-11'), ('spam', '2026-09-30'), ('spam', '2026-06-30');
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, created_at, starts_at, ends_at)
  VALUES (v_a, 'suspended', 'harassment', 'moderator', '2026-08-01', '2026-08-01', '2026-08-15') RETURNING id INTO v_r1;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, created_at, starts_at, ends_at)
  VALUES (v_b, 'moderation_hold', 'csam', 'report', '2026-08-03', '2026-08-03', '2026-08-04') RETURNING id INTO v_r2;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, created_at, starts_at, ends_at, carried_from)
  VALUES (v_b, 'suspended', 'spam', 'carried_over', '2026-08-04', '2026-08-04', '2026-08-05', gen_random_uuid());
  INSERT INTO public.dating_appeals (restriction_id, user_id, submitted_at, state, decided_by, decided_at)
  VALUES (v_r1, v_a, '2026-08-02', 'accepted', v_owner, '2026-08-03'),
         (v_r2, v_b, '2026-08-04', 'rejected', v_owner, '2026-08-05');
  v := public.moderation_transparency_summary(v_owner, '2026-07-01', '2026-10-01');
  IF v -> 'summary' IS DISTINCT FROM jsonb_build_object(
       'from', '2026-07-01', 'to', '2026-10-01',
       'requests', '{"GB": {"partly_disclosed": 1}, "GH": {"refused": 1, "disclosed": 1}}'::jsonb,
       'requests_met', 2,
       'request_types', '{"GB": {"legal_process": 1}, "GH": {"legal_process": 2}}'::jsonb,
       'reports', '{"spam": 1, "harassment": 2}'::jsonb,
       'actions', '{"suspended": 1, "moderation_hold": 1}'::jsonb,
       'actions_by_source', '{"report": {"moderation_hold": 1}, "moderator": {"suspended": 1}}'::jsonb, -- W7 final (M-11)
       'appeals', 2, 'overturned', 1)
     OR public.moderation_transparency_summary(v_owner, '2026-10-01', '2026-07-01') ->> 'reason' IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the transparency summary read %', v;
  END IF;
  -- The purge: 2 years for the audit, escalations and the log.
  INSERT INTO public.law_enforcement_requests (received_at, jurisdiction, legal_basis, scope)
  VALUES (now() - interval '2 years 1 day', 'GH', 'old', 'old'), (now() - interval '1 year', 'GH', 'kept', 'kept');
  INSERT INTO public.dating_escalations (kind, recorded_by, recorded_at)
  VALUES ('police', v_owner, now() - interval '2 years 1 day'), ('iwf', v_owner, now() - interval '1 year');
  ALTER TABLE public.dating_moderation_actions DISABLE TRIGGER dating_moderation_actions_append_only;
  INSERT INTO public.dating_moderation_actions (actor_id, action, created_at)
  VALUES (v_owner, 'note', now() - interval '2 years 1 day'), (v_owner, 'claim', now() - interval '1 year');
  ALTER TABLE public.dating_moderation_actions ENABLE TRIGGER dating_moderation_actions_append_only;
  v := public.purge_dating_retention(now());
  IF EXISTS (SELECT 1 FROM public.law_enforcement_requests WHERE legal_basis = 'old')
     OR NOT EXISTS (SELECT 1 FROM public.law_enforcement_requests WHERE legal_basis = 'kept')
     OR EXISTS (SELECT 1 FROM public.dating_escalations WHERE kind = 'police' AND recorded_by = v_owner)
     OR NOT EXISTS (SELECT 1 FROM public.dating_escalations WHERE kind = 'iwf' AND recorded_by = v_owner)
     OR EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE actor_id = v_owner AND action = 'note')
     OR NOT EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE actor_id = v_owner AND action = 'claim')
     OR v ->> 'moderation_actions' IS NULL OR (v ->> 'moderation_actions') LIKE 'failed%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge read % (2 years for the audit, escalations and the log)', v;
  END IF;
END $p$;


-- =====================================================================
-- Q. (Owner 2026-11-22; §6.3) A CSAM hold is lifted only by the safety
--    owner, after review, with a written reason (a false-positive hash
--    hit): listed for the owner alone; an ordinary moderator, a missing
--    reason, a hold that is not a CSAM hold and the owner's own hold are
--    refused; the lift takes the person's setup lock, is audited once (a
--    replay answers as the first did), counted and listed in health; a
--    carried CSAM hold's record ends with it; Spec 1's account hold is
--    untouched.
-- =====================================================================
DO $q$
DECLARE
  v_mod constant uuid := pg_temp.ready('139');
  v_owner constant uuid := pg_temp.ready('140');
  v_t constant uuid := pg_temp.man('141');
  v_t2 constant uuid := pg_temp.man('142');
  v_t3 constant uuid := pg_temp.man('143');
  v_t4 constant uuid := pg_temp.man('155');
  v_h4 uuid;
  v_n bigint := pg_temp.metric('dating.moderation.csam_lift');
  v_p bigint := pg_temp.metric('dating.moderation.party_refused');
  v_why constant text := 'Vendor review: the hash match was a false positive (ref W7-Q-1).';
  v_hold uuid;
  v_rep uuid;
  v_own uuid;
  v_rec uuid;
  v_car uuid;
  v jsonb;
  v2 jsonb;
  v_got text;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator');
  INSERT INTO public.dating_moderators (user_id, role, sensitive_routing_allowed) VALUES (v_owner, 'safety_owner', true);
  -- The hash path's hold (inserted with no source, as the CSAM paths do)
  -- and Spec 1's account hold on the same person.
  PERFORM public.record_dating_csam_hold(v_t);
  SELECT id INTO v_hold FROM public.dating_account_restrictions WHERE user_id = v_t AND source = 'csam_hash';
  PERFORM public.place_account_hold(v_t, 'safety_review', 'w7-q');
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source)
  VALUES (v_t2, 'moderation_hold', 'harassment', 'report') RETURNING id INTO v_rep;
  PERFORM public.record_dating_csam_hold(v_owner);
  SELECT id INTO v_own FROM public.dating_account_restrictions WHERE user_id = v_owner AND source = 'csam_hash';
  -- A CSAM hold carried past a deletion (its record and the carried row).
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, category, purge_after)
  VALUES (public.dating_phone_hmac_for_user(v_t3), 'dating', 'moderation_hold', 'csam', now() + interval '1 year')
  RETURNING id INTO v_rec;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, carried_from)
  VALUES (v_t3, 'moderation_hold', 'csam', 'carried_over', v_rec) RETURNING id INTO v_car;
  IF v_hold IS NULL OR v_own IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: (setup) the hash path placed no hold';
  END IF;

  v_got := concat_ws(' ', public.moderation_csam_holds(v_mod) ->> 'reason',
                          public.moderation_lift_csam_hold(v_mod, v_hold, v_why) ->> 'reason');
  v_got := v_got || ' ' || concat_ws(' ', public.moderation_lift_csam_hold(v_owner, v_hold, NULL) ->> 'reason',
                                          public.moderation_lift_csam_hold(v_owner, v_hold, '   ') ->> 'reason',
                                          public.moderation_lift_csam_hold(v_owner, v_hold, repeat('x', 1001)) ->> 'reason',
                                          public.moderation_lift_csam_hold(v_owner, NULL, v_why) ->> 'reason');
  v_got := v_got || ' ' || concat_ws(' ', public.moderation_lift_csam_hold(v_owner, v_rep, v_why) ->> 'reason',
                                          public.moderation_lift_csam_hold(v_owner, v_own, v_why) ->> 'reason');
  IF v_got IS DISTINCT FROM 'safety_owner_only safety_owner_only invalid invalid invalid invalid hold_unavailable hold_unavailable'
     OR pg_temp.metric('dating.moderation.party_refused') <= v_p
     OR pg_temp.held(v_t) <> 'moderation_hold/csam_hash/csam/false'
     OR EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE action = 'lift_csam_hold') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a CSAM hold lift was not refused (a moderator, no reason, not a CSAM hold, the owner''s own): %', v_got;
  END IF;
  v := public.moderation_csam_holds(v_owner);
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR NOT (v -> 'holds') @> jsonb_build_array(jsonb_build_object('id', v_hold, 'carried', false))
     OR NOT (v -> 'holds') @> jsonb_build_array(jsonb_build_object('id', v_car, 'carried', true))
     OR (v -> 'holds') @> jsonb_build_array(jsonb_build_object('id', v_rep))
     OR (v -> 'holds') @> jsonb_build_array(jsonb_build_object('id', v_own))
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'holds') AS h
                 WHERE (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(h) AS k) <> ARRAY['carried', 'case_id', 'escalations', 'id', 'since']) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner''s CSAM hold list read %', v;
  END IF;
  -- The lock: a person whose setup lock this transaction has not taken
  -- (the hash path's own writer takes it, so v_t's is held already).
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_t4, 'moderation_hold') RETURNING id INTO v_h4;
  v_got := pg_temp.setup_locked(v_t4)::text || '/'
           || pg_temp.probe(ARRAY[format('SELECT public.moderation_lift_csam_hold(%L, %L, %L)', v_owner, v_h4, v_why)],
                            format('SELECT pg_temp.setup_locked(%L)', v_t4));
  IF v_got IS DISTINCT FROM 'false/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the CSAM hold lift did not take the person''s setup lock';
  END IF;
  v := public.moderation_lift_csam_hold(v_owner, v_hold, v_why);
  v2 := public.moderation_lift_csam_hold(v_owner, v_hold, v_why);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR v2 IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.held(v_t) <> ''
     OR (SELECT count(*) FROM public.dating_moderation_actions WHERE action = 'lift_csam_hold') <> 1
     OR NOT EXISTS (SELECT 1 FROM public.dating_moderation_actions
                     WHERE action = 'lift_csam_hold' AND actor_id = v_owner AND case_id IS NULL AND target_user_id = v_t
                       AND detail = jsonb_build_object('restriction', v_hold, 'reason', v_why))
     OR pg_temp.metric('dating.moderation.csam_lift') <> v_n + 1
     OR NOT (public.get_dating_operational_health() -> 'safety_counters_7d') ? 'dating.moderation.csam_lift'
     OR NOT EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_t AND kind = 'safety_review' AND resolved_at IS NULL)
     OR (public.moderation_csam_holds(v_owner) -> 'holds') @> jsonb_build_array(jsonb_build_object('id', v_hold)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner''s CSAM hold lift read % then % (lifted once, audited once with its reason, counted, listed; Spec 1''s hold kept)', v, v2;
  END IF;
  v := public.moderation_lift_csam_hold(v_owner, v_car, 'Carried hold: same false-positive hash, reviewed (ref W7-Q-2).');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR pg_temp.held(v_t3) <> ''
     OR (SELECT effect_until IS NOT NULL AND effect_until <= now() FROM public.enforcement_records WHERE id = v_rec) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a carried CSAM hold''s lift read % or left its record in force', v;
  END IF;
END $q$;

-- =====================================================================
-- R. (W7 T4 review; §6.3, R-65) What an unavailable person's home shows:
--    a closer look (under_review) never shows as a hold; a carried hold
--    or age check shows as itself, not as restricted; a carried
--    suspension, a live suspension and a live hold as before.
-- =====================================================================
DO $r$
DECLARE
  v_a constant uuid := pg_temp.ready('144');
  v_b constant uuid := pg_temp.ready('145');
  v_c constant uuid := pg_temp.man('146');
  v_rec constant text := 'INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, category, purge_after) '
                         'VALUES (public.dating_phone_hmac_for_user(%L), ''dating'', %L, %L, now() + interval ''1 year'')';
  v_res constant text := 'INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source) '
                         'VALUES (%L, %L, %L, ''moderator'')';
  v_state constant text := 'SELECT private.dating_unavailable_state(%L)';
  v_got text;
BEGIN
  EXECUTE format(v_res, v_a, 'under_review', 'harassment');
  EXECUTE format(v_res, v_a, 'age_review', 'underage_risk');
  EXECUTE format(v_res, v_b, 'under_review', 'spam');
  v_got := concat_ws(' ', private.dating_unavailable_state(v_a), private.dating_unavailable_state(v_b),
    pg_temp.probe(ARRAY[format(v_rec, v_c, 'moderation_hold', 'csam')], format(v_state, v_c)),
    pg_temp.probe(ARRAY[format(v_rec, v_c, 'age_review', 'underage_risk')], format(v_state, v_c)),
    pg_temp.probe(ARRAY[format(v_rec, v_c, 'under_review', 'spam')], format(v_state, v_c)),
    pg_temp.probe(ARRAY[format(v_rec, v_c, 'suspended', 'harassment')], format(v_state, v_c)),
    pg_temp.probe(ARRAY[format(v_res, v_c, 'suspended', 'harassment')], format(v_state, v_c)),
    pg_temp.probe(ARRAY[format(v_res, v_c, 'moderation_hold', 'harassment')], format(v_state, v_c)),
    pg_temp.probe(ARRAY[format(v_rec, v_c, 'moderation_hold', 'csam')],
                  format($p$SELECT pg_temp.j(%L, '146', 'SELECT public.get_dating_home()') ->> 'state'$p$, v_c)));
  IF v_got IS DISTINCT FROM 'age_review unavailable hold age_review unavailable restricted restricted hold hold'
     OR (pg_temp.j(v_b, '145', 'SELECT public.get_dating_home()') ->> 'state') IN ('hold', 'restricted', 'age_review', 'unavailable') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the unavailable home state read % (a closer look shown, or a carried hold or age check as restricted)', v_got;
  END IF;
END $r$;

-- =====================================================================
-- S. (W7 T3 re-review; §6.2) A P0 card report takes the card off Today
--    and marks the pair whatever "Also block" did: refused by the day's
--    limit too; a P2 card report with a refused block leaves the card.
-- =====================================================================
DO $s$
DECLARE
  v_p constant uuid := pg_temp.ready('148');
  v_t constant uuid := pg_temp.man('149');
  v_i constant uuid := gen_random_uuid();
  v_lim constant text := 'INSERT INTO public.dating_rate_limits (user_id, operation, window_started_at, request_count) '
                         'VALUES (%L, ''block'', now(), 20) ON CONFLICT (user_id, operation) '
                         'DO UPDATE SET window_started_at = now(), request_count = 20';
  v_card constant text := 'INSERT INTO public.dating_introductions (id, pair_key, user_low_id, user_high_id, state, algorithm_version, '
                          'visible_from_low, visible_from_high, expires_at, created_at) VALUES (%L, %L, %L, %L, ''presented'', ''introductions_v2'', '
                          'now() - interval ''1 day'', now() - interval ''1 day'', now() + interval ''6 days'', now() - interval ''1 day'')';
  v_rep constant text := $p$SELECT set_config('w7.ans', pg_temp.j(%L, '148', format('SELECT public.report_dating_introduction(%%L, %%L, %%L, NULL, true)',
                                                                   pg_temp.key('s'), %L, %L))::text, true)$p$;
  v_read constant text := $p$SELECT coalesce(current_setting('w7.ans')::jsonb ->> 'blocked', coalesce(current_setting('w7.ans')::jsonb ->> 'reason', 'absent'))
                                    || '/' || (SELECT state FROM public.dating_introductions WHERE id = %L) || '/' || pg_temp.marked(%L, %L)$p$;
  v_got text;
BEGIN
  v_got := concat_ws('|',
    pg_temp.probe(ARRAY[format(v_lim, v_p), format(v_card, v_i, public.dating_pair_key(v_p, v_t), least(v_p, v_t), greatest(v_p, v_t)),
                        format(v_rep, v_p, v_i, 'threat_to_life')], format(v_read, v_i, v_p, v_t)),
    pg_temp.probe(ARRAY[format(v_lim, v_p), format(v_card, v_i, public.dating_pair_key(v_p, v_t), least(v_p, v_t), greatest(v_p, v_t)),
                        format(v_rep, v_p, v_i, 'harassment')], format(v_read, v_i, v_p, v_t)),
    pg_temp.probe(ARRAY[format(v_card, v_i, public.dating_pair_key(v_p, v_t), least(v_p, v_t), greatest(v_p, v_t)),
                        format(v_rep, v_p, v_i, 'threat_to_life')], format(v_read, v_i, v_p, v_t)));
  IF v_got IS DISTINCT FROM 'false/invalidated/true|false/presented/false|absent/invalidated/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a P0 card report whose block was refused left the card or the pair unmarked: %', v_got;
  END IF;
END $s$;

-- =====================================================================
-- T. (§4.8, W6 T8 carry) The 2-year purge keeps what a live restriction
--    or a live enforcement record still needs: its case, the case's
--    reports, its audit rows and escalations, run after run; with
--    neither, all four go at 2 years.
-- =====================================================================
DO $t$
DECLARE
  v_a constant uuid := pg_temp.man('150');
  v_b constant uuid := pg_temp.man('151');
  v_c constant uuid := pg_temp.man('152');
  v_d constant uuid := pg_temp.man('157');
  v_e constant uuid := pg_temp.man('158');
  v_owner constant uuid := pg_temp.id('136');
  v_old constant timestamptz := now() - interval '2 years 10 days';
  v_ca uuid;
  v_cb uuid;
  v_cc uuid;
  v_cd uuid;
  v_ce uuid;
  v_re uuid;
  v_ap uuid;
  v jsonb;
  v2 jsonb;
  v_got text;
BEGIN
  -- d (fix round 1, I-2): a case still open at 3 years (R-66, P-3); e (M-12):
  -- an appeal case whose upheld restriction lives on.
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, state, created_at)
  VALUES ('report', 'P2', v_d, 'open', now() - interval '3 years') RETURNING id INTO v_cd;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, decided_by, created_at, starts_at)
  VALUES (v_e, 'suspended', 'harassment', 'moderator', v_owner, v_old, v_old) RETURNING id INTO v_re;
  INSERT INTO public.dating_appeals (restriction_id, user_id, submitted_at, state, decided_by, decided_at)
  VALUES (v_re, v_e, v_old, 'rejected', v_owner, v_old) RETURNING id INTO v_ap;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, appeal_id, state, created_at, decided_at, outcome)
  VALUES ('appeal', 'P2', v_e, v_ap, 'decided', v_old, v_old, 'rejected') RETURNING id INTO v_ce;
  INSERT INTO public.dating_reports (category, created_at, case_id, target_user_id) VALUES ('harassment', v_old, v_cd, v_d);
  INSERT INTO public.dating_escalations (case_id, kind, recorded_by, recorded_at, reference)
  VALUES (v_cd, 'police', v_owner, v_old, 'W7T-d'), (v_ce, 'police', v_owner, v_old, 'W7T-e');
  ALTER TABLE public.dating_moderation_actions DISABLE TRIGGER dating_moderation_actions_append_only;
  INSERT INTO public.dating_moderation_actions (case_id, actor_id, action, detail, created_at)
  VALUES (v_cd, v_owner, 'note', '{"w7t": "d"}', v_old), (v_ce, v_owner, 'decide_appeal', '{"w7t": "e"}', v_old);
  ALTER TABLE public.dating_moderation_actions ENABLE TRIGGER dating_moderation_actions_append_only;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, state, created_at, decided_at, outcome)
  VALUES ('report', 'P2', v_a, 'decided', v_old, v_old, 'restricted') RETURNING id INTO v_ca;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, state, created_at, decided_at, outcome)
  VALUES ('report', 'P2', v_b, 'decided', v_old, v_old, 'restricted') RETURNING id INTO v_cb;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, state, created_at, decided_at, outcome)
  VALUES ('report', 'P2', v_c, 'decided', v_old, v_old, 'restricted') RETURNING id INTO v_cc;
  INSERT INTO public.dating_reports (category, created_at, case_id, target_user_id)
  VALUES ('harassment', v_old, v_ca, v_a), ('harassment', v_old, v_cb, v_b), ('harassment', v_old, v_cc, v_c);
  INSERT INTO public.dating_escalations (case_id, kind, recorded_by, recorded_at, reference)
  VALUES (v_ca, 'police', v_owner, v_old, 'W7T-a'), (v_cb, 'police', v_owner, v_old, 'W7T-b'), (v_cc, 'police', v_owner, v_old, 'W7T-c');
  ALTER TABLE public.dating_moderation_actions DISABLE TRIGGER dating_moderation_actions_append_only;
  INSERT INTO public.dating_moderation_actions (case_id, actor_id, action, detail, created_at)
  VALUES (v_ca, v_owner, 'restrict', '{"w7t": "a"}', v_old), (v_cb, v_owner, 'restrict', '{"w7t": "b"}', v_old),
         (v_cc, v_owner, 'restrict', '{"w7t": "c"}', v_old),
         (NULL, v_owner, 'note', '{"w7t": "young"}', now() - interval '2 years' + interval '12 hours');
  ALTER TABLE public.dating_moderation_actions ENABLE TRIGGER dating_moderation_actions_append_only;
  -- a: a permanent suspension from its case; b: a live record from its case.
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, decided_by, created_at, starts_at)
  VALUES (v_a, 'suspended', 'harassment', 'moderator', v_ca, v_owner, v_old, v_old);
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, category, case_id, created_at, purge_after)
  VALUES (public.dating_phone_hmac_for_user(v_b), 'dating', 'suspended', 'harassment', v_cb, now() - interval '1 year',
          now() + interval '1 year');
  v := public.purge_dating_retention(now());
  v2 := public.purge_dating_retention(now());
  SELECT string_agg(x.k || ' ' || (SELECT count(*) FROM public.dating_moderation_cases WHERE id = x.c) || '/'
                    || (SELECT count(*) FROM public.dating_reports WHERE target_user_id = x.u) || '/'
                    || (SELECT count(*) FROM public.dating_moderation_actions WHERE detail ->> 'w7t' = x.k) || '/'
                    || (SELECT count(*) FROM public.dating_escalations WHERE reference = 'W7T-' || x.k), ' ' ORDER BY x.k)
    INTO v_got FROM (VALUES ('a', v_ca, v_a), ('b', v_cb, v_b), ('c', v_cc, v_c), ('d', v_cd, v_d), ('e', v_ce, v_e)) AS x (k, c, u);
  IF v_got IS DISTINCT FROM 'a 1/1/1/1 b 1/1/1/1 c 0/0/0/0 d 1/1/1/1 e 1/0/1/1'
     OR EXISTS (SELECT 1 FROM jsonb_each_text(v || v2) AS e WHERE e.key IN ('reports', 'moderation_cases', 'moderation_actions', 'escalations')
                   AND e.value LIKE 'failed%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 2-year purge took what a live restriction or record needs (or kept the rest): % (%, %)', v_got, v, v2;
  END IF;
  -- A purge run for a later moment never trips the audit's guard (2 years
  -- by the clock): an audit row 2 years old tomorrow stays, the step holds.
  v := public.purge_dating_retention(now() + interval '1 day');
  IF v ->> 'moderation_actions' IS DISTINCT FROM '0'
     OR NOT EXISTS (SELECT 1 FROM public.dating_moderation_actions WHERE detail ->> 'w7t' = 'young') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a purge for a later moment read % on the audit', v ->> 'moderation_actions';
  END IF;
END $t$;

-- =====================================================================
-- U. (R-60, R-67) The log and the CSAM lift are the safety owner's: an
--    ordinary moderator's audit log never shows their rows (the owner's
--    does); no API role reads the two tables or runs the summary's query.
--    The audit stays append-only: a TRUNCATE, or an UPDATE that empties
--    its case or person outside a foreign key's own SET NULL, is refused.
-- =====================================================================
DO $u$
DECLARE
  v_mod constant uuid := pg_temp.ready('153');
  v_owner constant uuid := pg_temp.ready('154');
  v_h constant uuid := pg_temp.man('156');
  v_hold uuid;
  v_case_row uuid;
  v_person_row uuid;
  v_got text;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator');
  INSERT INTO public.dating_moderators (user_id, role, sensitive_routing_allowed) VALUES (v_owner, 'safety_owner', true);
  PERFORM public.moderation_record_le_request(v_owner, NULL, jsonb_build_object('received_at', now() - interval '1 day',
    'jurisdiction', 'GB', 'legal_basis', 'Production order 4', 'scope', 'One account'));
  -- Fix round 1 (M-10): this section's own CSAM lift (not Q's).
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_h, 'moderation_hold') RETURNING id INTO v_hold;
  PERFORM public.moderation_lift_csam_hold(v_owner, v_hold, 'Reviewed: the hash match was a false positive (ref W7-U).');
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_audit_log(v_mod, 500) -> 'actions') AS x
              WHERE x ->> 'action' IN ('law_enforcement_request', 'lift_csam_hold'))
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_audit_log(v_owner, 500) -> 'actions') AS x
                     WHERE x ->> 'action' = 'law_enforcement_request')
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_audit_log(v_owner, 500) -> 'actions') AS x
                     WHERE x ->> 'action' = 'lift_csam_hold' AND x -> 'detail' ->> 'restriction' = v_hold::text) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ordinary moderator''s audit log shows the law-enforcement log or a CSAM lift (R-60)';
  END IF;
  SELECT string_agg(o.obj || ':' || o.role, ', ') INTO v_got
    FROM (SELECT t.obj, r.role FROM unnest(ARRAY['public.dating_escalations', 'public.law_enforcement_requests']) AS t (obj),
                 unnest(ARRAY['anon', 'authenticated', 'service_role']) AS r (role)
           WHERE has_table_privilege(r.role, t.obj, 'SELECT, INSERT, UPDATE, DELETE')
          UNION ALL
          SELECT 'private.dating_transparency_summary', r.role FROM unnest(ARRAY['anon', 'authenticated', 'service_role']) AS r (role)
           WHERE has_function_privilege(r.role, 'private.dating_transparency_summary(date,date)', 'EXECUTE')) AS o;
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an API role reaches the log, the escalations or the summary''s query: %', v_got;
  END IF;
  -- (the TRUNCATE in a statement of its own: no other scan of the table open)
  v_got := pg_temp.probe(ARRAY[]::text[], $p$SELECT pg_temp.try_sql('TRUNCATE public.dating_moderation_actions')$p$);
  SELECT id INTO v_case_row FROM public.dating_moderation_actions WHERE case_id IS NOT NULL LIMIT 1;
  SELECT id INTO v_person_row FROM public.dating_moderation_actions WHERE target_user_id IS NOT NULL LIMIT 1;
  v_got := concat_ws(' ', v_got,
    pg_temp.try_sql(format('UPDATE public.dating_moderation_actions SET case_id = NULL WHERE id = %L', v_case_row)),
    pg_temp.try_sql(format('UPDATE public.dating_moderation_actions SET target_user_id = NULL WHERE id = %L', v_person_row)));
  IF v_got IS DISTINCT FROM '42501:audit:append_only 42501:audit:append_only 42501:audit:append_only' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the audit can be truncated or emptied outside a foreign key (R-67): %', v_got;
  END IF;
END $u$;

-- =====================================================================
-- V. (W7b rules on W7c's writes) Every new function counts not_moderator;
--    a party to a case can't record an escalation on it (counted); the
--    same escalation, the same request and the same decision again are
--    replays (one row, one audit row each); a decision is never undone to
--    pending; each new write waits at most 2 s, then answers busy
--    (counted).
-- =====================================================================
CREATE FUNCTION public.w7_t8_busy() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'w7 busy' USING ERRCODE = '55P03';
END $$;
DO $v$
DECLARE
  v_mod constant uuid := pg_temp.id('130');
  v_party constant uuid := pg_temp.id('132');
  v_owner constant uuid := pg_temp.id('134');
  v_t3 constant uuid := pg_temp.id('143');
  v_x constant uuid := gen_random_uuid();
  v_n bigint := pg_temp.metric('dating.moderation.not_moderator');
  v_p bigint := pg_temp.metric('dating.moderation.party_refused');
  v_b bigint := pg_temp.metric('dating.moderation.busy');
  v_new constant jsonb := jsonb_build_object('received_at', now() - interval '1 day', 'jurisdiction', 'GH', 'legal_basis', 'Order 9',
                                             'scope', 'One account');
  v_case uuid;
  v_a bigint;
  v_id uuid;
  v jsonb;
  v2 jsonb;
  v_got text;
BEGIN
  SELECT case_id INTO v_case FROM public.dating_reports WHERE reporter_user_id = v_party;
  PERFORM public.moderation_record_escalation(v_x, v_case, 'police', NULL);
  PERFORM public.moderation_le_requests(v_x);
  PERFORM public.moderation_record_le_request(v_x, NULL, '{}');
  PERFORM public.moderation_transparency_summary(v_x, '2026-07-01', '2026-10-01');
  PERFORM public.moderation_csam_holds(v_x);
  PERFORM public.moderation_lift_csam_hold(v_x, gen_random_uuid(), 'x');
  IF pg_temp.metric('dating.moderation.not_moderator') - v_n <> 6 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new console function did not count not_moderator (% of 6)',
      pg_temp.metric('dating.moderation.not_moderator') - v_n;
  END IF;
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_party, 'moderator');
  v_got := public.moderation_record_escalation(v_party, v_case, 'police', NULL) ->> 'reason';
  IF v_got IS DISTINCT FROM 'case_unavailable' OR pg_temp.metric('dating.moderation.party_refused') <= v_p THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a party to the case recorded an escalation on it (or was not counted): %', v_got;
  END IF;

  v_a := (SELECT count(*) FROM public.dating_moderation_actions WHERE action IN ('escalation', 'law_enforcement_request'));
  v := public.moderation_record_escalation(v_mod, v_case, 'police', 'GH-POL-77');
  v2 := public.moderation_record_escalation(v_mod, v_case, 'police', 'GH-POL-77');
  v_got := v::text || ' ' || v2::text;
  v := public.moderation_record_le_request(v_owner, NULL, v_new);
  v2 := public.moderation_record_le_request(v_owner, NULL, v_new);
  v_id := (v ->> 'id')::uuid;
  v_got := v_got || ' ' || (v2 ->> 'id' = v ->> 'id' AND (v2 ->> 'ok')::boolean)::text;
  v := public.moderation_record_le_request(v_owner, v_id, '{"decision": "refused"}');
  v2 := public.moderation_record_le_request(v_owner, v_id, '{"decision": "refused"}');
  v_got := v_got || ' ' || (v ->> 'ok') || ' ' || (v2 ->> 'ok') || ' ' || (public.moderation_record_le_request(v_owner, v_id, '{}') ->> 'reason');
  v_got := v_got || ' ' || coalesce(public.moderation_record_le_request(v_owner, v_id,
                                      '{"decision": "disclosed", "disclosed_categories": {"account": true}}') ->> 'reason', 'ok');
  IF v_got IS DISTINCT FROM '{"ok": true} {"ok": true} true true true invalid invalid'
     OR (SELECT count(*) FROM public.dating_escalations WHERE case_id = v_case AND reference = 'GH-POL-77') <> 1
     OR (SELECT count(*) FROM public.law_enforcement_requests WHERE legal_basis = 'Order 9') <> 1
     OR (SELECT decision FROM public.law_enforcement_requests WHERE id = v_id) IS DISTINCT FROM 'refused'
     OR (SELECT count(*) FROM public.dating_moderation_actions WHERE action IN ('escalation', 'law_enforcement_request')) <> v_a + 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed escalation, request or decision wrote twice, or a decision went back to pending: % (audit +%)',
      v_got, (SELECT count(*) FROM public.dating_moderation_actions WHERE action IN ('escalation', 'law_enforcement_request')) - v_a;
  END IF;

  SELECT string_agg(p.proname, ', ') INTO v_got FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname IN ('moderation_record_escalation', 'moderation_record_le_request', 'moderation_lift_csam_hold')
     AND NOT coalesce('lock_timeout=2s' = ANY (p.proconfig), false);
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new console write has no 2 s lock_timeout: %', v_got;
  END IF;
  v_got := concat_ws(' ',
    pg_temp.probe(ARRAY['CREATE TRIGGER w7_t8_busy BEFORE INSERT ON public.dating_escalations FOR EACH ROW EXECUTE FUNCTION public.w7_t8_busy()',
                        format($f$SELECT pg_temp.try_sql(format('SELECT set_config(''w7.busy'', public.moderation_record_escalation(%%L, %%L, ''iwf'', NULL)::text, true)', %L, %L))$f$,
                               v_mod, v_case)],
                  format($f$SELECT current_setting('w7.busy', true) || '/' || (pg_temp.metric('dating.moderation.busy') - %s)$f$, v_b)),
    pg_temp.probe(ARRAY['CREATE TRIGGER w7_t8_busy BEFORE INSERT ON public.law_enforcement_requests FOR EACH ROW EXECUTE FUNCTION public.w7_t8_busy()',
                        format($f$SELECT pg_temp.try_sql(format('SELECT set_config(''w7.busy'', public.moderation_record_le_request(%%L, NULL, %%L)::text, true)', %L, %L))$f$,
                               v_owner, jsonb_build_object('received_at', now() - interval '1 hour', 'jurisdiction', 'GH', 'legal_basis', 'Order 10',
                                                          'scope', 'x'))],
                  format($f$SELECT current_setting('w7.busy', true) || '/' || (pg_temp.metric('dating.moderation.busy') - %s)$f$, v_b)),
    pg_temp.probe(ARRAY[format('SELECT public.record_dating_csam_hold(%L)', v_t3),
                        'CREATE TRIGGER w7_t8_busy BEFORE UPDATE ON public.dating_account_restrictions FOR EACH ROW EXECUTE FUNCTION public.w7_t8_busy()',
                        format($f$SELECT pg_temp.try_sql(format('SELECT set_config(''w7.busy'', public.moderation_lift_csam_hold(%%L, %%L, ''Reviewed.'')::text, true)', %L,
                                 (SELECT r.id FROM public.dating_account_restrictions AS r WHERE r.user_id = %L AND r.source = 'csam_hash' AND r.lifted_at IS NULL)))$f$,
                               v_owner, v_t3)],
                  format($f$SELECT current_setting('w7.busy', true) || '/' || (pg_temp.metric('dating.moderation.busy') - %s)$f$, v_b)));
  IF v_got IS DISTINCT FROM '{"ok": false, "reason": "busy"}/1 {"ok": false, "reason": "busy"}/1 {"ok": false, "reason": "busy"}/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new console write that could not get its locks read % (busy, counted)', v_got;
  END IF;
END $v$;
DROP FUNCTION public.w7_t8_busy();

-- =====================================================================
-- W. (Fix round 1: I-1, M-1..M-4, M-7) The law-enforcement log never
--    drops a decision: the same request again is a replay only when every
--    input is the same; the same request with another decision answers
--    "exists" with its id (decide it there); a decision that is not one,
--    a time ahead of now or past the log's 2 years answers invalid; what
--    was disclosed stays recorded (only a wider disclosure after it); a
--    notice is stamped on its own (the decision kept); a create honours
--    the notice; one create at a time per request; the summary counts the
--    decision and the type (emergency or legal process).
-- =====================================================================
DO $w$
DECLARE
  v_owner constant uuid := pg_temp.id('134');
  v_owner2 constant uuid := pg_temp.id('154');
  v_base constant jsonb := jsonb_build_object('received_at', now() - interval '3 hours', 'jurisdiction', 'GH',
                                              'legal_basis', 'Order W7-W', 'scope', 'One account');
  v_sum constant text := $s$SELECT public.moderation_transparency_summary(%L, current_date - 1, current_date + 1) -> 'summary'$s$;
  v jsonb;
  s0 jsonb;
  s1 jsonb;
  v_id uuid;
  v_a bigint;
  v_got text;
BEGIN
  v := public.moderation_record_le_request(v_owner, NULL, v_base);
  v_id := (v ->> 'id')::uuid;
  v_a := (SELECT count(*) FROM public.dating_moderation_actions WHERE action = 'law_enforcement_request');
  EXECUTE format(v_sum, v_owner) INTO s0;
  v_got := concat_ws(' ',
    public.moderation_record_le_request(v_owner, NULL, v_base || '{"decision": "disclosed", "disclosed_categories": ["account"]}') ->> 'reason',
    (public.moderation_record_le_request(v_owner, NULL, v_base || '{"decision": "refused"}') ->> 'id' = v_id::text)::text,
    public.moderation_record_le_request(v_owner, NULL, v_base || '{"decision": "bogus"}') ->> 'reason',
    public.moderation_record_le_request(v_owner, NULL, v_base || '{"decision": "disclosed"}') ->> 'reason',
    public.moderation_record_le_request(v_owner, NULL, v_base || jsonb_build_object('received_at', now() + interval '3 days',
                                                                                    'legal_basis', 'Ahead')) ->> 'reason',
    public.moderation_record_le_request(v_owner, NULL, v_base || jsonb_build_object('received_at', now() - interval '2 years 1 day',
                                                                                    'legal_basis', 'Past')) ->> 'reason',
    public.moderation_record_le_request(v_owner, v_id, '{"decision": "bogus"}') ->> 'reason');
  IF v_got IS DISTINCT FROM 'exists true invalid invalid invalid invalid invalid'
     OR (SELECT decision FROM public.law_enforcement_requests WHERE id = v_id) IS DISTINCT FROM 'pending'
     OR (SELECT count(*) FROM public.law_enforcement_requests WHERE legal_basis IN ('Order W7-W', 'Ahead', 'Past')) <> 1
     OR (SELECT count(*) FROM public.dating_moderation_actions WHERE action = 'law_enforcement_request') <> v_a THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a request again with another decision, or a bad one, read % (or wrote)', v_got;
  END IF;
  -- Decided through its own path, it counts as met.
  v := public.moderation_record_le_request(v_owner, v_id, '{"decision": "disclosed", "disclosed_categories": ["account"]}');
  EXECUTE format(v_sum, v_owner) INTO s1;
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR (s1 ->> 'requests_met')::int <> (s0 ->> 'requests_met')::int + 1
     OR coalesce((s1 #>> '{requests,GH,disclosed}')::int, 0) <> coalesce((s0 #>> '{requests,GH,disclosed}')::int, 0) + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a decided request read % and the summary % then %', v, s0, s1;
  END IF;
  -- M-2: what was disclosed stays recorded; only a wider disclosure after it.
  v_got := concat_ws(' ',
    public.moderation_record_le_request(v_owner, v_id, '{"decision": "refused"}') ->> 'reason',
    public.moderation_record_le_request(v_owner, v_id, '{"decision": "partly_disclosed", "disclosed_categories": ["profile"]}') ->> 'reason',
    coalesce(public.moderation_record_le_request(v_owner, v_id,
               '{"decision": "disclosed", "disclosed_categories": ["messages", "account"]}') ->> 'reason', 'ok'));
  IF v_got IS DISTINCT FROM 'already_disclosed already_disclosed ok'
     OR (SELECT decision || '/' || array_to_string(disclosed_categories, ',') FROM public.law_enforcement_requests WHERE id = v_id)
        IS DISTINCT FROM 'disclosed/account,messages' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a disclosure was narrowed or undone: %', v_got;
  END IF;
  -- M-3: the notice on its own keeps the decision and its decider (one
  -- audit row); a create honours it.
  v_a := (SELECT count(*) FROM public.dating_moderation_actions WHERE action = 'law_enforcement_request');
  v := public.moderation_record_le_request(v_owner2, v_id,
         '{"decision": "disclosed", "disclosed_categories": ["account", "messages"], "user_notified": true}');
  v := public.moderation_record_le_request(v_owner2, v_id,
         '{"decision": "disclosed", "disclosed_categories": ["account", "messages"], "user_notified": true}');
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR (SELECT (decided_by = v_owner) || '/' || (user_notified_at IS NOT NULL) FROM public.law_enforcement_requests WHERE id = v_id)
        IS DISTINCT FROM 'true/true'
     OR (SELECT count(*) FROM public.dating_moderation_actions WHERE action = 'law_enforcement_request') <> v_a + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a notice rewrote the decision, or was audited % times',
      (SELECT count(*) FROM public.dating_moderation_actions WHERE action = 'law_enforcement_request') - v_a;
  END IF;
  v := public.moderation_record_le_request(v_owner, NULL, v_base || '{"legal_basis": "Order W7-W2", "decision": "refused", "user_notified": true}');
  IF (SELECT decision || '/' || (user_notified_at IS NOT NULL) || '/' || (decided_by = v_owner)
        FROM public.law_enforcement_requests WHERE id = (v ->> 'id')::uuid) IS DISTINCT FROM 'refused/true/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a request recorded with its decision and notice at once read %', v;
  END IF;
  -- M-4: a create holds the request's own lock (one at a time per request).
  v_got := pg_temp.probe(ARRAY[format('SELECT public.moderation_record_le_request(%L, NULL, %L)', v_owner,
                                      v_base || '{"legal_basis": "Order W7-W3"}')],
                         $p$SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_locks AS l
                                            WHERE l.locktype = 'advisory' AND l.pid = pg_backend_pid() AND l.granted AND l.objsubid = 2
                                              AND l.classid::text::bigint = (hashtext('dating_le_request')::bigint + 4294967296) % 4294967296)::text$p$);
  IF v_got IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recording a request took no lock of its own (two at once make two rows)';
  END IF;
  -- M-1 (§6.6): requests by country and type.
  PERFORM public.moderation_record_le_request(v_owner, NULL, v_base || '{"legal_basis": "Emergency W7-W", "emergency": true}');
  EXECUTE format(v_sum, v_owner) INTO s1;
  IF coalesce((s1 #>> '{request_types,GH,emergency}')::int, 0) < 1 OR coalesce((s1 #>> '{request_types,GH,legal_process}')::int, 0) < 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the summary does not give requests by country and type: %', s1 -> 'request_types';
  END IF;
END $w$;


-- =====================================================================
-- X. (Fix round 1: (a), the W7b carried-hold lift, M-11) A CSAM hit
--    always writes its own hold, by each of the three paths, beside a
--    report's hold, and a decision on the report's case leaves it; a
--    case decision that lifts a carried hold ends its record too (the
--    person is in good standing, the home no longer reads hold); a
--    carried CSAM hold is not appealable (the owner's lift is its end).
-- =====================================================================
DO $x$
DECLARE
  v_owner constant uuid := pg_temp.id('140');
  v_t constant uuid := pg_temp.id('142');
  v_c constant uuid := pg_temp.man('159');
  v_case uuid;
  v_case2 uuid;
  v_rec uuid;
  v_photo uuid;
  v_intent uuid;
  v_n constant text := $n$SELECT (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = %1$L AND source = 'csam_hash'
                                         AND lifted_at IS NULL) || '/'
                              || (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = %1$L AND source = 'report'
                                         AND lifted_at IS NULL)$n$;
  v_got text;
  v_after text;
BEGIN
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, state) VALUES ('report', 'P0', v_t, 'open')
  RETURNING id INTO v_case;
  UPDATE public.dating_account_restrictions SET case_id = v_case WHERE user_id = v_t AND source = 'report' AND lifted_at IS NULL;
  SELECT id INTO v_photo FROM public.dating_profile_photos WHERE user_id = v_t ORDER BY position LIMIT 1;
  INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at, created_at, orphan_claimed_at)
  VALUES (v_t, 'w7x/' || gen_random_uuid() || '.jpg', 'image/jpeg', now() - interval '1 hour', now() - interval '2 hours', now())
  RETURNING id INTO v_intent;
  v_got := concat_ws('|', pg_temp.probe(ARRAY[]::text[], format(v_n, v_t)),
    pg_temp.probe(ARRAY[format($p$SELECT public.record_dating_photo_csam(%L, 'hit')$p$, v_photo)], format(v_n, v_t)),
    pg_temp.probe(ARRAY[format($p$SELECT public.record_dating_orphan_scan(%L, 'hit')$p$, v_intent)], format(v_n, v_t)),
    pg_temp.probe(ARRAY[format('SELECT public.record_dating_csam_hold(%L)', v_t)], format(v_n, v_t)));
  PERFORM public.record_dating_csam_hold(v_t);
  PERFORM public.moderation_dismiss(v_owner, v_case);
  EXECUTE format(v_n, v_t) INTO v_after;
  IF v_got IS DISTINCT FROM '0/1|1/1|1/1|1/1' OR v_after IS DISTINCT FROM '1/0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a CSAM hit beside a report''s hold read % (photo, orphan, worker), then % after the case''s decision', v_got, v_after;
  END IF;

  -- A carried hold from an open case, lifted by the case's decision.
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, state) VALUES ('report', 'P2', v_c, 'open')
  RETURNING id INTO v_case2;
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, category, case_id, purge_after)
  VALUES (public.dating_phone_hmac_for_user(v_c), 'dating', 'moderation_hold', 'harassment', v_case2, now() + interval '1 year')
  RETURNING id INTO v_rec;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, carried_from)
  VALUES (v_c, 'moderation_hold', 'harassment', 'carried_over', v_case2, v_rec);
  v_got := pg_temp.held(v_c) || '|' || pg_temp.probe(ARRAY[format($p$INSERT INTO public.dating_account_restrictions
                                                     (user_id, restriction_type, category, source) VALUES (%L, 'moderation_hold', 'csam', 'carried_over')$p$, v_c)],
                                   format($p$SELECT appealable FROM public.dating_account_restrictions WHERE user_id = %L AND category = 'csam'$p$, v_c));
  PERFORM public.moderation_dismiss(v_owner, v_case2);
  IF v_got IS DISTINCT FROM 'moderation_hold/carried_over/harassment/true|false'
     OR pg_temp.held(v_c) <> ''
     OR (SELECT effect_until IS NOT NULL AND effect_until <= now() FROM public.enforcement_records WHERE id = v_rec) IS NOT TRUE
     OR public.dating_account_in_good_standing(v_c) IS NOT TRUE
     OR (pg_temp.j(v_c, '159', 'SELECT public.get_dating_home()') ->> 'state') IN ('hold', 'restricted', 'age_review', 'unavailable') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a carried hold''s case lift left its record in force (% | %), or a carried CSAM hold is appealable',
      v_got, pg_temp.j(v_c, '159', 'SELECT public.get_dating_home()') ->> 'state';
  END IF;
END $x$;

-- =====================================================================
-- Y. (Fix round 1: (b), M-5) A case's escalations, for the console: any
--    moderator who can see the case reads their kinds and dates; the
--    reference only the safety owner and whoever recorded it; a party,
--    a routed case without routing or no case reads case_unavailable
--    (a party counted). CSA without the consent kind is refused on a
--    sextortion case.
-- =====================================================================
DO $y$
DECLARE
  v_mod constant uuid := pg_temp.id('130');
  v_other constant uuid := pg_temp.id('139');
  v_party constant uuid := pg_temp.id('132');
  v_owner constant uuid := pg_temp.id('134');
  v_p bigint := pg_temp.metric('dating.moderation.party_refused');
  v_n bigint := pg_temp.metric('dating.moderation.not_moderator');
  v_case uuid;
  v jsonb;
  v_got text;
BEGIN
  SELECT case_id INTO v_case FROM public.dating_reports WHERE reporter_user_id = v_party;
  v_got := public.moderation_record_escalation(v_mod, v_case, 'csa', NULL) ->> 'reason';
  IF v_got IS DISTINCT FROM 'consent_kind_required' OR EXISTS (SELECT 1 FROM public.dating_escalations WHERE case_id = v_case AND kind = 'csa') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: CSA was recorded on a sextortion case without the victim''s consent kind: %', v_got;
  END IF;
  SELECT string_agg(x.who || ':' || (SELECT string_agg(e ->> 'kind' || '/' || coalesce(e ->> 'reference', '-') || '/' || (e ->> 'mine'), ','
                                                        ORDER BY e ->> 'kind')
                                       FROM jsonb_array_elements(public.moderation_case_escalations(x.m, v_case) -> 'escalations') AS e),
                    ' ' ORDER BY x.who)
    INTO v_got FROM (VALUES ('a_owner', v_owner), ('b_recorder', v_mod), ('c_other', v_other)) AS x (who, m);
  IF v_got IS DISTINCT FROM
       'a_owner:csa_292_with_consent/CSA-2026-0001/false,police/GH-POL-77/false '
       'b_recorder:csa_292_with_consent/CSA-2026-0001/true,police/GH-POL-77/true '
       'c_other:csa_292_with_consent/-/false,police/-/false'
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_case_escalations(v_owner, v_case) -> 'escalations') AS e
                 WHERE (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e) AS k) <> ARRAY['kind', 'mine', 'recorded_at', 'reference']) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a case''s escalations read % (the reference is the owner''s and the recorder''s)', v_got;
  END IF;
  v_got := concat_ws(' ', public.moderation_case_escalations(v_party, v_case) ->> 'reason',
                          public.moderation_case_escalations(v_mod, gen_random_uuid()) ->> 'reason',
                          public.moderation_case_escalations(gen_random_uuid(), v_case) ->> 'reason');
  IF v_got IS DISTINCT FROM 'case_unavailable case_unavailable not_moderator'
     OR pg_temp.metric('dating.moderation.party_refused') <= v_p OR pg_temp.metric('dating.moderation.not_moderator') <= v_n THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a party, no case or a stranger read the escalations: % (counted?)', v_got;
  END IF;
END $y$;

-- =====================================================================
-- Z. (Fix round 2: N-1, N-2, the csam-category carried report hold) A
--    hold of category csam is a CSAM hold, whatever placed it: only the
--    owner's lift ends it, never a case decision or Lift hold. Any other
--    hold placed while a CSAM hold lives gets its own row, so the owner's
--    false-positive lift leaves it in force (the person still can't
--    send). Lift hold of a carried hold or age check ends its record too.
-- =====================================================================
DO $z$
DECLARE
  v_owner constant uuid := pg_temp.id('140');
  v_mod constant uuid := pg_temp.id('139');
  v_p constant uuid := pg_temp.id('155');
  v_q constant uuid := pg_temp.id('156');
  v_r constant uuid := pg_temp.id('143');
  v_partner constant uuid := pg_temp.id('153');
  v_m uuid;
  v_case uuid;
  v_hold uuid;
  v_rep uuid;
  v_csam uuid;
  v_rec1 uuid;
  v_rec2 uuid;
  v_send constant text := $s$SELECT pg_temp.j(%L, %L, format('SELECT public.send_dating_message(%%L, %%L, ''hello'')', pg_temp.key('z'), %L)) ->> 'ok'$s$;
  v jsonb;
  v_got text;
  v_ok text;
BEGIN
  -- N-2: a CSAM hold, then a P0 report's hold and a moderator's hold on a
  -- case: each its own row; the owner's lift leaves both.
  PERFORM public.record_dating_csam_hold(v_p);
  SELECT id INTO v_hold FROM public.dating_account_restrictions WHERE user_id = v_p AND source = 'csam_hash' AND lifted_at IS NULL;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, state) VALUES ('report', 'P0', v_p, 'open')
  RETURNING id INTO v_case;
  v_rep := private.dating_place_restriction(v_p, 'moderation_hold', 'threats', 'report', v_case, NULL, NULL, false);
  v := public.moderation_place_hold(v_mod, v_case, 'harassment');
  v_m := pg_temp.match(v_p, v_partner);
  v_got := (v_rep IS DISTINCT FROM v_hold)::text || '/' || (v ->> 'ok')
           || '/' || (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = v_p AND case_id = v_case AND lifted_at IS NULL);
  v := public.moderation_lift_csam_hold(v_owner, v_hold, 'Vendor review: a false-positive hash match (ref W7-Z).');
  EXECUTE format(v_send, v_p, '155', v_m) INTO v_ok;
  IF v_got IS DISTINCT FROM 'true/true/2' OR (v ->> 'ok')::boolean IS NOT TRUE -- W7 final (I-2): a report's and a moderator's hold, two rows
     OR (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = v_p AND case_id = v_case AND lifted_at IS NULL) <> 2
     OR public.dating_account_in_good_standing(v_p) IS NOT FALSE OR v_ok IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report''s or moderator''s hold was folded into a CSAM hold, and the owner''s lift freed the person (%, %, send %)',
      v_got, v, v_ok;
  END IF;

  -- The csam-category carried report hold, and a live csam-category report
  -- hold: neither a case decision nor Lift hold ends them; the owner's lift does.
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, state) VALUES ('report', 'P0', v_q, 'open')
  RETURNING id INTO v_case;
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, category, case_id, purge_after)
  VALUES (public.dating_phone_hmac_for_user(v_q), 'dating', 'moderation_hold', 'csam', v_case, now() + interval '1 year')
  RETURNING id INTO v_rec1;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, carried_from)
  VALUES (v_q, 'moderation_hold', 'csam', 'carried_over', v_case, v_rec1) RETURNING id INTO v_csam;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id)
  VALUES (v_q, 'moderation_hold', 'csam', 'report', v_case);
  v_got := (public.moderation_lift_hold(v_owner, v_case) ->> 'lifted');
  PERFORM public.moderation_dismiss(v_owner, v_case);
  v_got := v_got || '/' || (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = v_q AND category = 'csam' AND lifted_at IS NULL)
           || '/' || (SELECT effect_until IS NULL FROM public.enforcement_records WHERE id = v_rec1)
           || '/' || (SELECT count(*) FROM jsonb_array_elements(public.moderation_csam_holds(v_owner) -> 'holds') AS h
                       WHERE (h ->> 'id')::uuid IN (SELECT id FROM public.dating_account_restrictions WHERE user_id = v_q));
  v := public.moderation_lift_csam_hold(v_owner, v_csam, 'Reviewed: the reported image was not CSAM (ref W7-Z-2).');
  IF v_got IS DISTINCT FROM '0/2/true/2' OR (v ->> 'ok')::boolean IS NOT TRUE
     OR (SELECT effect_until IS NOT NULL FROM public.enforcement_records WHERE id = v_rec1) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a csam-category hold was ended by a case decision or Lift hold, or not listed for the owner: % / %', v_got, v;
  END IF;

  -- N-1: Lift hold of a carried hold and a carried age check ends both
  -- records: the person is free and the home reads neither.
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, state) VALUES ('report', 'P1', v_r, 'open')
  RETURNING id INTO v_case;
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, category, case_id, purge_after)
  VALUES (public.dating_phone_hmac_for_user(v_r), 'dating', 'moderation_hold', 'harassment', v_case, now() + interval '1 year')
  RETURNING id INTO v_rec1;
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, category, case_id, purge_after)
  VALUES (public.dating_phone_hmac_for_user(v_r), 'dating', 'age_review', 'underage_risk', v_case, now() + interval '1 year')
  RETURNING id INTO v_rec2;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id, carried_from)
  VALUES (v_r, 'moderation_hold', 'harassment', 'carried_over', v_case, v_rec1),
         (v_r, 'age_review', 'underage_risk', 'carried_over', v_case, v_rec2);
  v := public.moderation_lift_hold(v_owner, v_case);
  IF v IS DISTINCT FROM '{"ok": true, "lifted": 2}'::jsonb OR pg_temp.held(v_r) <> ''
     OR (SELECT count(*) FROM public.enforcement_records WHERE id IN (v_rec1, v_rec2) AND effect_until IS NOT NULL AND effect_until <= now()) <> 2
     OR public.dating_account_in_good_standing(v_r) IS NOT TRUE
     OR (pg_temp.j(v_r, '143', 'SELECT public.get_dating_home()') ->> 'state') IN ('hold', 'restricted', 'age_review', 'unavailable') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Lift hold of a carried hold and age check read % and left a record in force (home %)', v,
      pg_temp.j(v_r, '143', 'SELECT public.get_dating_home()') ->> 'state';
  END IF;
END $z$;

-- =====================================================================
-- Z2. (Fix round 3: N2-1) A hold is reused only within its class: further
--    corroborated CSAM reports reuse the report's CSAM row (one row, one
--    dating.hold.p0); a CSAM report after a threats hold gets a CSAM row
--    of its own, which only the owner lifts; a CSAM report after a hash
--    hit gets its own row too, and the owner lifts each. (Fixture ids
--    160-169, past W7c's 130-159, which are all taken.)
-- =====================================================================
DO $z2$
DECLARE
  v_owner constant uuid := pg_temp.id('140');
  v_a constant uuid := pg_temp.man('160');
  v_b constant uuid := pg_temp.man('164');
  v_c constant uuid := pg_temp.man('168');
  v_r1 constant uuid := pg_temp.ready('161');
  v_r2 constant uuid := pg_temp.ready('162');
  v_r3 constant uuid := pg_temp.ready('163');
  v_r4 constant uuid := pg_temp.ready('165');
  v_r5 constant uuid := pg_temp.ready('166');
  v_r6 constant uuid := pg_temp.ready('167');
  v_r7 constant uuid := pg_temp.ready('169');
  v_n bigint := pg_temp.metric('dating.hold.p0');
  v_csam uuid;
  v_case uuid;
  v_got text;
  v jsonb;
BEGIN
  -- Three CSAM reports, all independent: the second holds, the third reuses.
  PERFORM pg_temp.report(v_r1, '161', pg_temp.match(v_a, v_r1), 'csam');
  PERFORM pg_temp.report(v_r2, '162', pg_temp.match(v_a, v_r2), 'csam');
  PERFORM pg_temp.report(v_r3, '163', pg_temp.match(v_a, v_r3), 'csam');
  v_got := pg_temp.held(v_a) || '|' || (pg_temp.metric('dating.hold.p0') - v_n);
  IF v_got IS DISTINCT FROM 'moderation_hold/report/csam/false|1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: corroborated CSAM reports doubled the hold or its count: %', v_got;
  END IF;

  -- A threats hold first, then a corroborated CSAM report: a CSAM row of
  -- its own; the case's Lift hold ends the threats hold only; the owner's
  -- lift ends the CSAM row.
  PERFORM pg_temp.report(v_r4, '165', pg_temp.match(v_b, v_r4), 'threat_to_life');
  PERFORM pg_temp.report(v_r5, '166', pg_temp.match(v_b, v_r5), 'threat_to_life');
  PERFORM pg_temp.report(v_r6, '167', pg_temp.match(v_b, v_r6), 'csam');
  SELECT id, case_id INTO v_csam, v_case FROM public.dating_account_restrictions
   WHERE user_id = v_b AND category = 'csam' AND lifted_at IS NULL;
  v_got := (SELECT string_agg(category, ',' ORDER BY category) FROM public.dating_account_restrictions
             WHERE user_id = v_b AND restriction_type = 'moderation_hold' AND lifted_at IS NULL)
           || '|' || (public.moderation_lift_hold(v_owner, v_case) ->> 'lifted') || '|' || pg_temp.held(v_b);
  v := public.moderation_lift_csam_hold(v_owner, v_csam, 'Reviewed: the reported image was not CSAM (ref W7-Z2-b).');
  IF v_got IS DISTINCT FROM 'csam,threat_to_life|1|moderation_hold/report/csam/false'
     OR (v ->> 'ok')::boolean IS NOT TRUE OR pg_temp.held(v_b) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a CSAM report after a threats hold read % then % (its own row, the owner''s alone)', v_got, v;
  END IF;

  -- A hash hit, then a corroborated CSAM report: two rows; the owner lifts each.
  PERFORM public.record_dating_csam_hold(v_c);
  PERFORM pg_temp.report(v_r7, '169', pg_temp.match(v_c, v_r7), 'csam');
  PERFORM pg_temp.report(v_r1, '161', pg_temp.match(v_c, v_r1), 'csam');
  v_got := (SELECT string_agg(source, ',' ORDER BY source) FROM public.dating_account_restrictions
             WHERE user_id = v_c AND category = 'csam' AND lifted_at IS NULL) || '|';
  FOR v_csam IN SELECT r.id FROM public.dating_account_restrictions AS r
                 WHERE r.user_id = v_c AND r.category = 'csam' AND r.lifted_at IS NULL ORDER BY r.created_at, r.id LOOP
    v := public.moderation_lift_csam_hold(v_owner, v_csam, 'Reviewed: a false positive (ref W7-Z2-c).');
    v_got := v_got || (v ->> 'ok') || ',';
  END LOOP;
  IF v_got IS DISTINCT FROM 'csam_hash,report|true,true,' OR pg_temp.held(v_c) <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a CSAM report after a hash hit read % (two rows, the owner lifts each)', v_got;
  END IF;
END $z2$;

-- =====================================================================
-- AI. (W7 final server fix round 3; replaces AA, AB, AC and AH) The ID
--    check is its own case. Ask for ID on a case opens a new case of kind
--    id_check for the same person, moves the open underage_risk reports
--    and the asked age check (with its code) there, and leaves the rest:
--    the original is decided asked_for_id when nothing else is open on it
--    (its holds go, as with every decision), else it stays open at its
--    other reports' priority and clock, holds unchanged. On an id_check
--    case: Lift hold (the ID shows an adult: id_verified, its reports not
--    upheld), Confirm a minor (restricted, upheld, Spec 1's hold), No ID
--    came (no_id_received, upheld, the check kept; a late Lift still
--    frees and leaves the reports as they are), Dismiss (asked by
--    mistake: the check ends, not upheld); Hold, Restrict and Ask answer
--    case_unavailable. New reports never join it; a person has at most one
--    open id_check case beside one open report case. It never pages and is
--    never past due. (Fixture ids 170-189, 200-219, 260-269.)
-- =====================================================================
CREATE FUNCTION pg_temp.ic(p_case uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.moderation_case(pg_temp.id('140'), p_case) #> '{case,id_check}';
$$;
CREATE FUNCTION pg_temp.in_kind(p_kind text, p_case uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT coalesce((public.moderation_queue(pg_temp.id('140'), 200, p_kind) -> 'cases')
                    @> jsonb_build_array(jsonb_build_object('id', p_case)), false);
$$;
CREATE FUNCTION pg_temp.reps(p_case uuid) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce(string_agg(category || '=' || state, ',' ORDER BY category, state), '-')
    FROM public.dating_reports WHERE case_id = p_case;
$$;
CREATE FUNCTION pg_temp.cs(p_case uuid) RETURNS text LANGUAGE sql AS $$
  SELECT kind || '/' || state || '/' || coalesce(outcome, '-') FROM public.dating_moderation_cases WHERE id = p_case;
$$;
-- The id_check case Ask for ID opened from [p_case] (the console's id_case).
CREATE FUNCTION pg_temp.idc(p_case uuid) RETURNS uuid LANGUAGE sql AS $$
  SELECT (public.moderation_case(pg_temp.id('140'), p_case) #>> '{case,id_case}')::uuid;
$$;
CREATE FUNCTION public.w7_r3_busy() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'w7 busy' USING ERRCODE = '55P03';
END $$;
DO $ai$
DECLARE
  v_mod constant uuid := pg_temp.ready('170');
  v_owner constant uuid := pg_temp.id('140');
  v_party constant uuid := pg_temp.ready('174');
  v_mx constant uuid := pg_temp.man('175');
  v_w constant uuid := pg_temp.ready('176');
  v_r constant uuid := pg_temp.ready('177');
  v_r2 constant uuid := pg_temp.ready('178');
  v_t1 constant uuid := pg_temp.man('180');
  v_t2 constant uuid := pg_temp.man('181');
  v_t3 constant uuid := pg_temp.man('182');
  v_t4 constant uuid := pg_temp.man('183');
  v_t5 constant uuid := pg_temp.man('184');
  v_t6 constant uuid := pg_temp.man('185');
  v_t7 constant uuid := pg_temp.man('186');
  v_t8 constant uuid := pg_temp.man('187');
  v_t9 constant uuid := pg_temp.man('188');
  v_t10 constant uuid := pg_temp.man('189');
  v_t11 constant uuid := pg_temp.man('200');
  v_t12 constant uuid := pg_temp.man('201');
  v_t13 constant uuid := pg_temp.man('202');
  v_t14 constant uuid := pg_temp.man('203');
  v_t15 constant uuid := pg_temp.man('204');
  v_t16 constant uuid := pg_temp.man('205');
  v_t17 constant uuid := pg_temp.man('206');
  v_t18 constant uuid := pg_temp.man('207');
  v_c uuid[] := ARRAY[]::uuid[];
  v_x uuid;
  v_x2 uuid;
  v_x3 uuid;
  v_k uuid;
  v jsonb;
  v2 jsonb;
  v_got text;
  v_code text;
  v_n bigint;
  v_p bigint := pg_temp.metric('dating.moderation.party_refused');
  v_due0 bigint;
  v_new constant text := $s$INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, state, sla_due_at, created_at)
                            VALUES ('report', %L, %L, 'open', now() + interval '40 hours', now() - interval '4 hours') RETURNING id$s$;
  v_rep constant text := $s$INSERT INTO public.dating_reports (category, case_id, target_user_id, reporter_user_id, priority, sla_due_at)
                            VALUES (%L, %L, %L, %L, %L, now() + interval '20 hours')$s$;
  v_t uuid;
  i int;
BEGIN
  INSERT INTO public.dating_moderators (user_id, role) VALUES (v_mod, 'moderator'), (v_party, 'moderator');
  -- Cases 1..15, one per person: an underage report each, except where said.
  FOREACH v_t IN ARRAY ARRAY[v_t1, v_t2, v_t3, v_t4, v_t5, v_t6, v_t7, v_t8, v_t9, v_t10, v_t11, v_t12, v_t13, v_t14, v_t15] LOOP
    EXECUTE format(v_new, 'P2', v_t) INTO v_k;
    v_c := v_c || v_k;
  END LOOP;
  FOR i IN 1..15 LOOP
    CONTINUE WHEN i IN (7, 10, 12, 13);
    EXECUTE format(v_rep, 'underage_risk', v_c[i], (SELECT target_user_id FROM public.dating_moderation_cases WHERE id = v_c[i]), v_w, 'P2');
  END LOOP;

  -- (1) Age only: the ask opens the id_check case and decides the original.
  v := public.moderation_ask_for_id(v_mod, v_c[1]);
  v_x := (v ->> 'id_case')::uuid;
  v2 := public.moderation_ask_for_id(v_mod, v_c[1]);
  v_code := pg_temp.ic(v_x) ->> 'code';
  v_got := concat_ws(' ', v ->> 'ok', v2 = v, public.moderation_ask_for_id(v_owner, v_c[1]) ->> 'reason',
                     pg_temp.cs(v_c[1]), pg_temp.cs(v_x), pg_temp.reps(v_c[1]), pg_temp.reps(v_x), pg_temp.held(v_t1),
                     public.moderation_case(v_owner, v_x) #>> '{case,state}', public.moderation_case(v_owner, v_x) #>> '{case,origin_case}' = v_c[1]::text,
                     pg_temp.idc(v_c[1]) = v_x, coalesce(pg_temp.ic(v_c[1]), 'null') = 'null'::jsonb, pg_temp.ic(v_x) ->> 'state', pg_temp.ic(v_x) ->> 'restriction_live',
                     pg_temp.in_kind('id_check', v_x), pg_temp.in_kind(NULL, v_x), pg_temp.in_kind('report', v_x),
                     (SELECT count(*) FROM public.dating_moderation_actions WHERE action = 'ask_for_id' AND case_id IN (v_c[1], v_x)));
  IF v_got IS DISTINCT FROM concat_ws(' ', 'true', 't', 'case_unavailable', 'report/decided/asked_for_id', 'id_check/in_review/-',
                                     '-', 'underage_risk=open', 'age_review/moderator/underage_risk/false', 'awaiting_id', 't',
                                     't', 't', 'awaiting', 'true', 't', 't', 'f', '2')
     OR coalesce(v_code, '') !~ '^[2-9A-HJKMNP-Z]{8}$'
     OR pg_temp.j(v_t1, '180', 'SELECT public.get_my_dating_restriction()') #>> '{restriction,id_check_code}' IS DISTINCT FROM v_code
     OR pg_temp.j(v_t1, '180', 'SELECT public.get_my_dating_restriction()') #>> '{restriction,source}' IS DISTINCT FROM 'id_check' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ask for ID did not open its own id_check case: %', v_got;
  END IF;
  -- Only the ID actions on it: Hold, Restrict and Ask are refused.
  v_got := concat_ws(' ', public.moderation_place_hold(v_mod, v_x, 'underage_risk') ->> 'reason',
                          public.moderation_restrict(v_mod, v_x, 'suspended', NULL, 'underage_risk') ->> 'reason',
                          public.moderation_ask_for_id(v_mod, v_x) ->> 'reason');
  IF v_got IS DISTINCT FROM 'case_unavailable case_unavailable case_unavailable' OR pg_temp.held(v_t1) IS DISTINCT FROM 'age_review/moderator/underage_risk/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an id_check case took a hold, a restriction or a second ask: %', v_got;
  END IF;
  -- Lift (the ID shows an adult): id_verified, its report not upheld, free; once.
  v := public.moderation_lift_hold(v_mod, v_x);
  v2 := public.moderation_lift_hold(v_mod, v_x);
  v_got := concat_ws(' ', v::text, v2 = v, pg_temp.cs(v_x), pg_temp.reps(v_x), pg_temp.held(v_t1), public.dating_account_in_good_standing(v_t1),
                     coalesce(pg_temp.ic(v_x) ->> 'state', '-'), pg_temp.ic(v_x) ->> 'restriction_live', pg_temp.ic(v_x) ->> 'outcome',
                     pg_temp.in_kind('id_check', v_x),
                     (SELECT count(*) FROM public.dating_moderation_actions WHERE case_id = v_x AND action = 'lift_hold'));
  IF v_got IS DISTINCT FROM '{"ok": true, "lifted": 1} t id_check/decided/id_verified underage_risk=not_upheld  t - false id_verified f 1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Lift on an id_check case read %', v_got;
  END IF;

  -- (2) A report after the ask (the original decided): a new report case;
  -- the id_check case keeps only its age report; Dismiss and Restrict on
  -- the new case leave the ID check alone (N2-1); a dated suspension still
  -- shows the code first (m-3); the ID later frees the age part only.
  v_x := (public.moderation_ask_for_id(v_mod, v_c[2]) ->> 'id_case')::uuid;
  PERFORM pg_temp.report(v_r, '177', pg_temp.match(v_t2, v_r), 'harassment');
  v_k := (SELECT case_id FROM public.dating_reports WHERE reporter_user_id = v_r AND target_user_id = v_t2);
  v_got := concat_ws(' ', v_k IS DISTINCT FROM v_x, v_k IS DISTINCT FROM v_c[2], pg_temp.cs(v_k), pg_temp.reps(v_x), pg_temp.reps(v_k));
  v := public.moderation_dismiss(v_mod, v_k);
  v_got := concat_ws(' ', v_got, v ->> 'ok', pg_temp.held(v_t2), pg_temp.cs(v_x), pg_temp.ic(v_x) ->> 'restriction_live');
  IF v_got IS DISTINCT FROM concat_ws(' ', 't t report/open/- underage_risk=open harassment=open',
                                     'true age_review/moderator/underage_risk/false id_check/in_review/- true') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report after the ask, then Dismiss, read % (the ID check untouched)', v_got;
  END IF;
  PERFORM pg_temp.report(v_r2, '178', pg_temp.match(v_t2, v_r2), 'threats');
  v_k := (SELECT case_id FROM public.dating_reports WHERE reporter_user_id = v_r2 AND target_user_id = v_t2);
  PERFORM public.moderation_restrict(v_mod, v_k, 'suspended', now() + interval '7 days', 'threats');
  v := pg_temp.j(v_t2, '181', 'SELECT public.get_my_dating_restriction()');
  v_got := concat_ws(' ', v #>> '{restriction,source}', v #>> '{restriction,id_check_code}' = pg_temp.ic(v_x) ->> 'code', pg_temp.reps(v_k), pg_temp.reps(v_x));
  PERFORM public.moderation_lift_hold(v_mod, v_x);
  v_got := concat_ws(' ', v_got, pg_temp.held(v_t2), pg_temp.reps(v_x), pg_temp.reps(v_k), pg_temp.cs(v_x));
  IF v_got IS DISTINCT FROM concat_ws(' ', 'id_check t threats=upheld underage_risk=open',
                                     'suspended/moderator/threats/true underage_risk=not_upheld threats=upheld id_check/decided/id_verified') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Restrict on another case, then the ID, read % (each case its own reports)', v_got;
  END IF;

  -- (3) A case with another report open keeps it: open at that report's
  -- priority and clock, its holds unchanged (a hold placed while the ID
  -- waits is the original case's, never the ID case's); Lift on the ID
  -- case leaves it; Dismiss on the original lifts it, not the check.
  EXECUTE format(v_rep, 'harassment', v_c[3], v_t3, v_r, 'P1');
  PERFORM public.moderation_place_hold(v_mod, v_c[3], 'harassment');
  v_x := (public.moderation_ask_for_id(v_mod, v_c[3]) ->> 'id_case')::uuid;
  v_got := concat_ws(' ', pg_temp.cs(v_c[3]), (SELECT priority FROM public.dating_moderation_cases WHERE id = v_c[3]),
                     (SELECT sla_due_at = (SELECT sla_due_at FROM public.dating_reports WHERE case_id = v_c[3])
                        FROM public.dating_moderation_cases WHERE id = v_c[3]),
                     pg_temp.reps(v_c[3]), pg_temp.reps(v_x), pg_temp.held(v_t3), pg_temp.in_kind('report', v_c[3]));
  PERFORM public.moderation_place_hold(v_mod, v_c[3], 'harassment'); -- a replay
  v := public.moderation_lift_hold(v_mod, v_x);
  v_got := concat_ws(' ', v_got, v::text, pg_temp.held(v_t3));
  v := public.moderation_dismiss(v_mod, v_c[3]);
  v_got := concat_ws(' ', v_got, v ->> 'ok', pg_temp.held(v_t3), pg_temp.reps(v_c[3]));
  IF v_got IS DISTINCT FROM concat_ws(' ', 'report/in_review/- P1 t harassment=open underage_risk=open',
                                     'age_review/moderator/underage_risk/false moderation_hold/moderator/harassment/false t',
                                     '{"ok": true, "lifted": 1} moderation_hold/moderator/harassment/false', 'true  harassment=not_upheld') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the original case with another report open read %', v_got;
  END IF;

  -- (4) No ID came: decided, upheld, the check kept, counted, in the
  -- id_check list; Dismiss then refused; a late Lift frees and leaves the
  -- reports upheld and the outcome (m2-1).
  v_n := pg_temp.metric('dating.moderation.no_id');
  v_x := (public.moderation_ask_for_id(v_mod, v_c[4]) ->> 'id_case')::uuid;
  v := public.moderation_close_no_id(v_mod, v_x);
  v2 := public.moderation_close_no_id(v_mod, v_x);
  v_got := concat_ws(' ', v::text, v2 = v, pg_temp.cs(v_x), pg_temp.reps(v_x), pg_temp.held(v_t4), pg_temp.ic(v_x) ->> 'state',
                     pg_temp.ic(v_x) ->> 'outcome', pg_temp.in_kind('id_check', v_x), pg_temp.metric('dating.moderation.no_id') - v_n,
                     (SELECT count(*) FROM public.dating_moderation_actions WHERE case_id = v_x AND action = 'close_no_id'),
                     public.moderation_dismiss(v_mod, v_x) ->> 'reason', public.moderation_close_no_id(v_mod, v_c[5]) ->> 'reason');
  v := public.moderation_lift_hold(v_mod, v_x);
  v_got := concat_ws(' ', v_got, v::text, pg_temp.held(v_t4), pg_temp.reps(v_x), pg_temp.cs(v_x), coalesce(pg_temp.ic(v_x) ->> 'state', '-'));
  IF v_got IS DISTINCT FROM concat_ws(' ', '{"ok": true} t id_check/decided/no_id_received underage_risk=upheld',
                                     'age_review/moderator/underage_risk/false no_id no_id_received t 1 1 case_unavailable case_unavailable',
                                     '{"ok": true, "lifted": 1}  underage_risk=upheld id_check/decided/no_id_received -') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: No ID came, then a late ID, read %', v_got;
  END IF;

  -- (5) Confirm a minor on an id_check case, and from a decided No ID came
  -- one (restricted either way, m2-2); no ID action after it; Confirm on
  -- an ordinary case with no age report is refused.
  v_x := (public.moderation_ask_for_id(v_mod, v_c[5]) ->> 'id_case')::uuid;
  v := public.moderation_confirm_minor(v_mod, v_x);
  v2 := public.moderation_confirm_minor(v_mod, v_x);
  v_got := concat_ws(' ', v ->> 'ok', v2 ->> 'ok', pg_temp.cs(v_x), pg_temp.reps(v_x), pg_temp.held(v_t5),
                     public.moderation_lift_hold(v_mod, v_x) ->> 'reason', public.moderation_close_no_id(v_mod, v_x) ->> 'reason',
                     coalesce(pg_temp.ic(v_x) ->> 'state', '-'),
                     EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_t5 AND kind = 'age_review' AND resolved_at IS NULL),
                     (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = v_t5 AND lifted_at IS NULL AND id_check_code IS NOT NULL));
  v_x2 := (public.moderation_ask_for_id(v_mod, v_c[6]) ->> 'id_case')::uuid;
  PERFORM public.moderation_close_no_id(v_mod, v_x2);
  v := public.moderation_confirm_minor(v_mod, v_x2);
  v_got := concat_ws(' ', v_got, v ->> 'ok', pg_temp.cs(v_x2), pg_temp.held(v_t6), public.moderation_lift_hold(v_mod, v_x2) ->> 'reason',
                     public.moderation_confirm_minor(v_mod, v_c[7]) ->> 'reason');
  IF v_got IS DISTINCT FROM concat_ws(' ', 'true true id_check/decided/restricted underage_risk=upheld age_review/moderator/underage_risk/false',
                                     'case_unavailable case_unavailable - t 0',
                                     'true id_check/decided/restricted age_review/moderator/underage_risk/false case_unavailable case_unavailable') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Confirm a minor read %', v_got;
  END IF;

  -- (6) Dismiss on an id_check case (asked by mistake): the check ends,
  -- its report not upheld, the person free.
  v_x := (public.moderation_ask_for_id(v_mod, v_c[8]) ->> 'id_case')::uuid;
  v := public.moderation_dismiss(v_mod, v_x);
  v_got := concat_ws(' ', v ->> 'ok', pg_temp.cs(v_x), pg_temp.reps(v_x), pg_temp.held(v_t8), pg_temp.in_kind('id_check', v_x));
  IF v_got IS DISTINCT FROM 'true id_check/decided/dismissed underage_risk=not_upheld  f' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dismiss on an id_check case read %', v_got;
  END IF;

  -- (7) W4's own age check and a carried one stay (two rows; the ID's lift
  -- or dismissal takes only the asked check); the asked check shows first.
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source)
  VALUES (v_t9, 'age_review', 'underage_risk', 'age_assurance');
  v_x := (public.moderation_ask_for_id(v_mod, v_c[9]) ->> 'id_case')::uuid;
  UPDATE public.dating_account_restrictions SET created_at = now() + interval '1 minute' WHERE user_id = v_t9 AND source = 'age_assurance';
  v_got := concat_ws(' ', (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = v_t9 AND lifted_at IS NULL),
                     pg_temp.j(v_t9, '188', 'SELECT public.get_my_dating_restriction()') #>> '{restriction,source}',
                     public.moderation_lift_hold(v_mod, v_x)::text, pg_temp.held(v_t9));
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source)
  VALUES (v_t11, 'age_review', 'underage_risk', 'carried_over');
  v_x := (public.moderation_ask_for_id(v_mod, v_c[11]) ->> 'id_case')::uuid;
  PERFORM public.moderation_dismiss(v_mod, v_x);
  v_got := concat_ws(' ', v_got, pg_temp.held(v_t11));
  IF v_got IS DISTINCT FROM '2 id_check {"ok": true, "lifted": 1} age_review/age_assurance/underage_risk/false age_review/carried_over/underage_risk/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ask for ID took W4''s or a carried age check: %', v_got;
  END IF;

  -- (8) An ask from a case with no age report: its id_check case has no
  -- report, the original stays open for its own; Confirm a minor stands on
  -- the ID itself.
  EXECUTE format(v_rep, 'harassment', v_c[10], v_t10, v_r, 'P1');
  v_x := (public.moderation_ask_for_id(v_mod, v_c[10]) ->> 'id_case')::uuid;
  v_got := concat_ws(' ', pg_temp.cs(v_c[10]), pg_temp.reps(v_x), public.moderation_confirm_minor(v_mod, v_x) ->> 'ok', pg_temp.cs(v_x),
                     pg_temp.reps(v_c[10]));
  IF v_got IS DISTINCT FROM 'report/in_review/- - true id_check/decided/restricted harassment=open' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ask from a case with no age report read %', v_got;
  END IF;

  -- (9) Parties and routing: a reporter whose report moved, and a reporter
  -- on the original case, are parties to the id_check case (counted); a
  -- case that needs routing makes its id_check case need it too.
  EXECUTE format(v_rep, 'underage_risk', v_c[12], v_t12, v_party, 'P2');
  v_x := (public.moderation_ask_for_id(v_owner, v_c[12]) ->> 'id_case')::uuid;
  EXECUTE format(v_rep, 'harassment', v_c[13], v_t13, v_party, 'P1');
  v_x2 := (public.moderation_ask_for_id(v_owner, v_c[13]) ->> 'id_case')::uuid;
  UPDATE public.dating_reports SET reporter_user_id = v_mx WHERE case_id = v_c[14];
  v_x3 := (public.moderation_ask_for_id(v_owner, v_c[14]) ->> 'id_case')::uuid;
  v_got := concat_ws(' ', public.moderation_lift_hold(v_party, v_x) ->> 'reason', public.moderation_close_no_id(v_party, v_x2) ->> 'reason',
                     public.moderation_case(v_party, v_x2) ->> 'reason', public.moderation_lift_hold(v_mod, v_x3) ->> 'reason',
                     (public.moderation_queue(v_mod, 200, 'id_check') -> 'cases') @> jsonb_build_array(jsonb_build_object('id', v_x3)),
                     (public.moderation_queue(v_party, 200, 'id_check') -> 'cases') @> jsonb_build_array(jsonb_build_object('id', v_x2)),
                     pg_temp.metric('dating.moderation.party_refused') - v_p >= 3);
  IF v_got IS DISTINCT FROM 'case_unavailable case_unavailable case_unavailable case_unavailable f f t' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a party or an unrouted moderator reached an id_check case: %', v_got;
  END IF;

  -- (10) One open id_check case per person: a second ask (another case,
  -- another moderator) is refused; it never pages and is never past due.
  v_x := (public.moderation_ask_for_id(v_mod, v_c[15]) ->> 'id_case')::uuid;
  v_k := pg_temp.sig(v_t15);
  v_got := concat_ws(' ', public.moderation_ask_for_id(v_owner, v_k) ->> 'reason',
                     (SELECT count(*) FROM public.dating_moderation_cases WHERE kind = 'id_check' AND target_user_id = v_t15));
  UPDATE public.dating_moderation_cases SET sla_due_at = now() - interval '1 hour', created_at = now() - interval '30 days 7 minutes'
   WHERE id = v_x;
  PERFORM set_config('app.settings.moderation_alert_webhook', 'https://alerts.invalid/hook', true);
  DELETE FROM pg_temp.w7_posts;
  v_due0 := (public.get_dating_operational_health() #>> '{reports_open,past_due}')::bigint;
  PERFORM public.dating_moderation_sla_check(now());
  v_got := concat_ws(' ', v_got, (SELECT count(*) FROM pg_temp.w7_posts WHERE body ->> 'text' LIKE '% case waiting 720 h 7 m'));
  UPDATE public.dating_moderation_cases SET kind = 'report' WHERE id = v_x; -- (the same row as a report case would page)
  DELETE FROM pg_temp.w7_posts;
  PERFORM public.dating_moderation_sla_check(now());
  v_got := concat_ws(' ', v_got, (SELECT count(*) FROM pg_temp.w7_posts WHERE body ->> 'text' LIKE '% case waiting 720 h 7 m'));
  UPDATE public.dating_moderation_cases SET kind = 'id_check', sla_due_at = NULL WHERE id = v_x;
  PERFORM set_config('app.settings.moderation_alert_webhook', '', true);
  IF v_got IS DISTINCT FROM 'case_unavailable 1 0 1'
     OR (public.get_dating_operational_health() #>> '{reports_open,past_due}')::bigint IS DISTINCT FROM v_due0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second ask, or an id_check case paging, read %', v_got;
  END IF;

  -- (11) No ID came under every console-write rule: refused on an ordinary
  -- case, for a party, without routing, for a stranger; 2 s then busy.
  v_got := concat_ws(' ', public.moderation_close_no_id(v_mod, v_c[13]) ->> 'reason',
                          public.moderation_close_no_id(v_party, v_x2) ->> 'reason',
                          public.moderation_close_no_id(v_mod, v_x3) ->> 'reason',
                          public.moderation_close_no_id(gen_random_uuid(), v_x2) ->> 'reason');
  v_n := pg_temp.metric('dating.moderation.busy');
  v_got := v_got || ' ' || pg_temp.probe(ARRAY['CREATE TRIGGER w7_r3_busy BEFORE UPDATE ON public.dating_moderation_cases FOR EACH ROW EXECUTE FUNCTION public.w7_r3_busy()',
                     format($f$SELECT pg_temp.try_sql(format('SELECT set_config(''w7.busy'', public.moderation_close_no_id(%%L, %%L)::text, true)', %L, %L))$f$,
                            v_owner, v_x2)],
                     format($f$SELECT coalesce(nullif(current_setting('w7.busy', true), '')::jsonb ->> 'reason', '<raised>') || '/' || (pg_temp.metric('dating.moderation.busy') - %s)$f$, v_n));
  IF v_got IS DISTINCT FROM 'case_unavailable case_unavailable case_unavailable not_moderator busy/1'
     OR NOT coalesce((SELECT 'lock_timeout=2s' = ANY (p.proconfig) FROM pg_proc AS p WHERE p.oid = 'public.moderation_close_no_id(uuid,uuid)'::regprocedure), false)
     OR NOT (public.get_dating_operational_health() -> 'safety_counters_7d') ? 'dating.moderation.no_id' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Close (no ID came) read %', v_got;
  END IF;

  -- (13) Round 3 pins: the original's own read, the queue rows, the plain
  -- Lift hold and Lift the case's holds on an ordinary case.
  v_got := concat_ws(' ', public.moderation_case(v_owner, v_c[3]) #>> '{case,state}', public.moderation_case(v_owner, v_c[10]) #>> '{case,state}',
                     (SELECT e -> 'id_check' FROM jsonb_array_elements(public.moderation_queue(v_owner, 200) -> 'cases') AS e
                       WHERE e ->> 'id' = v_c[10]::text) = 'null'::jsonb,
                     (SELECT e ->> 'state' FROM jsonb_array_elements(public.moderation_queue(v_owner, 200, 'id_check') -> 'cases') AS e
                       WHERE e ->> 'id' = v_x2::text),
                     public.moderation_lift_hold(v_mod, v_c[1]) ->> 'reason');
  IF v_got IS DISTINCT FROM 'decided in_review t awaiting_id case_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the original, the queue rows or Lift on a decided case read %', v_got;
  END IF;
  -- Two holds on an ordinary case: Lift hold lifts both; Lift the case's
  -- holds then finds none (audited once, replayed); Lift hold again answers
  -- its own count; Lift the case's holds on a decided case is refused; a
  -- report's hold inserted bare is not appealable.
  EXECUTE format(v_new, 'P1', v_t16) INTO v_k;
  EXECUTE format(v_rep, 'harassment', v_k, v_t16, v_r, 'P1');
  PERFORM public.moderation_place_hold(v_mod, v_k, 'harassment');
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, case_id)
  VALUES (v_t16, 'moderation_hold', 'threats', 'report', v_k);
  v_got := pg_temp.held(v_t16);
  v_got := concat_ws(' ', v_got, public.moderation_lift_hold(v_mod, v_k)::text, public.moderation_lift_case_holds(v_mod, v_k)::text,
                     public.moderation_lift_case_holds(v_mod, v_k)::text, public.moderation_lift_hold(v_mod, v_k)::text);
  v_got := concat_ws(' ', v_got, (SELECT count(*) FROM public.dating_moderation_actions WHERE case_id = v_k AND action = 'lift_hold' AND detail ? 'holds'),
                     public.moderation_lift_case_holds(v_mod, v_c[1]) ->> 'reason');
  IF v_got IS DISTINCT FROM concat_ws(' ', 'moderation_hold/moderator/harassment/false moderation_hold/report/threats/false',
                                     '{"ok": true, "lifted": 2} {"ok": true, "lifted": 0} {"ok": true, "lifted": 0} {"ok": true, "lifted": 2} 1 case_unavailable') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Lift hold and Lift the case''s holds on an ordinary case read %', v_got;
  END IF;

  -- (14) A real report's case: the ask moves its report (the original's
  -- read lists none); the original's interim age check goes while its
  -- other report keeps it open; routing from the original alone reaches
  -- the id_check case.
  PERFORM pg_temp.report(v_r2, '178', pg_temp.match(v_t17, v_r2), 'underage_risk');
  v_k := (SELECT case_id FROM public.dating_reports WHERE reporter_user_id = v_r2 AND target_user_id = v_t17);
  PERFORM private.dating_place_restriction(v_t17, 'age_review', 'underage_risk', 'report', v_k, NULL, NULL, false);
  EXECUTE format(v_rep, 'spam', v_k, v_t17, v_r, 'P3');
  v_x := (public.moderation_ask_for_id(v_mod, v_k) ->> 'id_case')::uuid;
  v_got := concat_ws(' ', jsonb_array_length(public.moderation_case(v_owner, v_k) -> 'reports'), pg_temp.reps(v_k), pg_temp.cs(v_k),
                     pg_temp.held(v_t17));
  EXECUTE format(v_new, 'P2', v_t18) INTO v_k;
  EXECUTE format(v_rep, 'harassment', v_k, v_t18, v_mx, 'P1');
  EXECUTE format(v_rep, 'underage_risk', v_k, v_t18, v_w, 'P2');
  v_x2 := (public.moderation_ask_for_id(v_owner, v_k) ->> 'id_case')::uuid;
  v_got := concat_ws(' ', v_got, public.moderation_lift_hold(v_mod, v_x2) ->> 'reason', pg_temp.reps(v_x2));
  IF v_got IS DISTINCT FROM '1 spam=open report/in_review/- age_review/moderator/underage_risk/false case_unavailable underage_risk=open' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a real report''s ask, the interim age check or routing by origin read %', v_got;
  END IF;

  -- (12) m-1: pg_net's answers unreadable: counted, and the run still pages.
  v_n := pg_temp.metric('dating.sla.answers_unreadable');
  v_got := pg_temp.probe(ARRAY[
      'DROP TABLE IF EXISTS net._http_response',
      'CREATE TABLE net._http_response (id bigint)', -- no status_code: the read fails
      'DELETE FROM pg_temp.w7_posts',
      format($f$INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind, sla_due_at, created_at)
                VALUES ('signal', 'P3', %L, 'money_asks', now() - interval '1 hour', now() - interval '80 hours')$f$, v_t14),
      $f$SELECT set_config('app.settings.moderation_alert_webhook', 'https://alerts.invalid/hook', true)$f$,
      $f$SELECT set_config('w7.sla', public.dating_moderation_sla_check(now())::text, true)$f$,
      $f$SELECT set_config('app.settings.moderation_alert_webhook', '', true)$f$],
    format($f$SELECT (current_setting('w7.sla', true)::jsonb ->> 'alerts')::int > 0 AND (SELECT count(*) FROM pg_temp.w7_posts) > 0
                     AND pg_temp.metric('dating.sla.answers_unreadable') - %s = 1$f$, v_n));
  IF v_got IS DISTINCT FROM 'true' OR NOT (public.get_dating_operational_health() -> 'safety_counters_7d') ? 'dating.sla.answers_unreadable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable pg_net answer stopped the SLA run or went uncounted: %', v_got;
  END IF;
END $ai$;
DROP FUNCTION public.w7_r3_busy();
-- =====================================================================
-- AD. (W7 final server fix, I-2, I-4, M-9) A restriction is its case's:
--    placing one reuses only the same case's live row of that type,
--    placed the same way (a replay), never another case's or a carried
--    one, so each case's decision has its row, dismissing one case leaves
--    another's, and a permanent suspension is never folded into a dated
--    one. Ask for ID places its check before it lifts the case's interim
--    holds, so the enrolment is never released and suspended again.
--    (Fixture ids 220-229.)
-- =====================================================================
DO $ad$
DECLARE
  v_mod constant uuid := pg_temp.id('170');
  v_owner constant uuid := pg_temp.id('140');
  v_p constant uuid := pg_temp.man('220');
  v_q constant uuid := pg_temp.man('221');
  v_s constant uuid := pg_temp.man('222');
  v_rw constant uuid := pg_temp.ready('223');
  v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_e uuid;
  v_got text;
  v jsonb;
BEGIN
  -- (1) Holds on two cases: two rows; dismissing one leaves the other's.
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, sla_due_at)
  VALUES ('report', 'P1', v_p, now() + interval '1 day') RETURNING id INTO v_a;
  v_b := pg_temp.sig(v_p);
  PERFORM public.moderation_place_hold(v_mod, v_a, 'harassment');
  PERFORM public.moderation_place_hold(v_mod, v_b, 'harassment');
  PERFORM private.dating_place_restriction(v_p, 'moderation_hold', 'harassment', 'moderator', v_b, v_mod, NULL, false); -- a replay
  v_got := (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = v_p AND lifted_at IS NULL)::text;
  PERFORM public.moderation_dismiss(v_mod, v_a);
  IF v_got <> '2' OR (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = v_p AND lifted_at IS NULL AND case_id = v_b) <> 1
     OR public.dating_account_in_good_standing(v_p) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hold on one case was folded into another''s: % rows, after dismissing A %', v_got, pg_temp.held(v_p);
  END IF;
  -- (2) A 7-day suspension, then a permanent one on another case: two rows,
  -- the read shows the permanent one, decided by its own decider.
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, sla_due_at)
  VALUES ('report', 'P1', v_q, now() + interval '1 day') RETURNING id INTO v_c;
  v_d := pg_temp.sig(v_q, 'money_asks');
  PERFORM public.moderation_restrict(v_mod, v_c, 'suspended', now() + interval '7 days', 'harassment');
  v := public.moderation_restrict(v_owner, v_d, 'suspended', NULL, 'threats');
  v_got := (SELECT string_agg(coalesce(ends_at::text, 'forever') || ':' || category || ':' || (case_id = v_d) || ':' || (decided_by = v_owner), ' '
                              ORDER BY ends_at NULLS FIRST)
              FROM public.dating_account_restrictions WHERE user_id = v_q AND lifted_at IS NULL AND ends_at IS NULL);
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v_got IS DISTINCT FROM 'forever:threats:true:true'
     OR (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = v_q AND lifted_at IS NULL) <> 2
     OR pg_temp.j(v_q, '221', 'SELECT public.get_my_dating_restriction()') #> '{restriction,ends_at}' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a permanent suspension on another case was folded into a dated one: % (%)', v, v_got;
  END IF;
  -- (3) M-9: Ask for ID on a case holding a report's age check: the
  -- enrolment stays suspended throughout (never released to a pause).
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, sla_due_at)
  VALUES ('report', 'P0', v_s, now() + interval '4 hours') RETURNING id INTO v_e;
  INSERT INTO public.dating_reports (category, case_id, target_user_id, reporter_user_id) VALUES ('underage_risk', v_e, v_s, v_rw);
  PERFORM private.dating_place_restriction(v_s, 'age_review', 'underage_risk', 'report', v_e, NULL, NULL, false);
  UPDATE public.dating_enrollments SET paused_at = NULL, pause_reason = NULL WHERE user_id = v_s;
  PERFORM public.moderation_ask_for_id(v_mod, v_e);
  v_got := (SELECT state || '/' || coalesce(paused_at::text, '-') || '/' || coalesce(pause_reason, '-') FROM public.dating_enrollments WHERE user_id = v_s);
  IF v_got IS DISTINCT FROM 'suspended/-/-' OR pg_temp.held(v_s) IS DISTINCT FROM 'age_review/moderator/underage_risk/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ask for ID released the enrolment before placing its check: % (holds %)', v_got, pg_temp.held(v_s);
  END IF;
END $ad$;

-- =====================================================================
-- AE. (W7 final server fix, I-5, I-6, M-8) Delete-and-return. Dismissing
--    an orphaned case ends the records its holds left, so the number comes
--    back in good standing; a record carried back before the dismissal is
--    lifted with it, and the returning account is relinked to the number's
--    open case; a closer look follows the number. (Fixture ids 230-239.)
-- =====================================================================
DO $ae$
DECLARE
  v_owner constant uuid := pg_temp.id('140');
  v_mod constant uuid := pg_temp.id('170');
  v_t uuid := pg_temp.man('230');
  v_u uuid := pg_temp.man('232');
  v_x uuid := pg_temp.man('234');
  v_rw constant uuid := pg_temp.ready('236');
  v_t2 uuid;
  v_u2 uuid;
  v_x2 uuid;
  v_ht text;
  v_hu text;
  v_c uuid;
  v_cu uuid;
  v_cx uuid;
  v jsonb;
  v_got text;
BEGIN
  -- (1) A P0 hold on case C; the person deletes; C is dismissed; the number
  -- comes back free.
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, sla_due_at)
  VALUES ('report', 'P0', v_t, public.dating_phone_hmac_for_user(v_t), now() + interval '4 hours') RETURNING id INTO v_c;
  INSERT INTO public.dating_reports (category, case_id, target_user_id, reporter_user_id) VALUES ('threat_to_life', v_c, v_t, v_rw);
  PERFORM private.dating_place_restriction(v_t, 'moderation_hold', 'threat_to_life', 'report', v_c, NULL, NULL, false);
  v_ht := public.dating_phone_hmac_for_user(v_t);
  PERFORM pg_temp.delete_account(v_t);
  v := public.moderation_dismiss(v_owner, v_c);
  v_t2 := pg_temp.man('231', '{"phone": "230"}');
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR EXISTS (SELECT 1 FROM public.enforcement_records WHERE phone_hmac = v_ht AND scope = 'dating'
                   AND (effect_until IS NULL OR effect_until > now()))
     OR NOT public.dating_account_in_good_standing(v_t2)
     OR pg_temp.j(v_t2, '231', 'SELECT public.get_my_dating_restriction()') #> '{restriction}' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dismissed orphaned case''s hold followed the number back: % (good standing %)',
      v, public.dating_account_in_good_standing(v_t2);
  END IF;
  -- (2) The hold carried back first: the returning account reads it, the
  -- number's open case is relinked to it, and the dismissal ends both.
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, target_phone_hmac, sla_due_at)
  VALUES ('report', 'P0', v_u, public.dating_phone_hmac_for_user(v_u), now() + interval '4 hours') RETURNING id INTO v_cu;
  INSERT INTO public.dating_reports (category, case_id, target_user_id, reporter_user_id) VALUES ('threat_to_life', v_cu, v_u, v_rw);
  PERFORM private.dating_place_restriction(v_u, 'moderation_hold', 'threat_to_life', 'report', v_cu, NULL, NULL, false);
  v_hu := public.dating_phone_hmac_for_user(v_u);
  PERFORM pg_temp.delete_account(v_u);
  v_u2 := pg_temp.man('233', '{"phone": "232"}');
  v_got := pg_temp.j(v_u2, '233', 'SELECT public.get_my_dating_restriction()') #>> '{restriction,source}';
  v_got := coalesce(v_got, '-') || ' ' || coalesce((SELECT target_user_id = v_u2 FROM public.dating_moderation_cases WHERE id = v_cu)::text, 'null');
  v := public.moderation_dismiss(v_owner, v_cu);
  IF v_got IS DISTINCT FROM 'carried true' OR (v ->> 'ok')::boolean IS NOT TRUE OR pg_temp.held(v_u2) <> ''
     OR NOT public.dating_account_in_good_standing(v_u2)
     OR EXISTS (SELECT 1 FROM public.enforcement_records WHERE phone_hmac = v_hu AND scope = 'dating'
                   AND (effect_until IS NULL OR effect_until > now())) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a carried hold, relink and dismissal read % / % (holds %)', v_got, v, pg_temp.held(v_u2);
  END IF;
  -- (3) I-6: a closer look is not shed by deleting and coming back.
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, sla_due_at)
  VALUES ('report', 'P2', v_x, now() + interval '1 day') RETURNING id INTO v_cx;
  PERFORM public.moderation_restrict(v_mod, v_cx, 'under_review', NULL, 'spam');
  v_got := pg_temp.excluded(v_x)::text;
  PERFORM pg_temp.delete_account(v_x);
  v_x2 := pg_temp.man('235', '{"phone": "234"}');
  IF v_got IS DISTINCT FROM 'true' OR NOT pg_temp.excluded(v_x2) OR NOT public.dating_account_in_good_standing(v_x2) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closer look was shed by deleting and returning (before %, after %)', v_got, pg_temp.excluded(v_x2);
  END IF;
END $ae$;

-- =====================================================================
-- AF. (W7 final server fix, I-3) The queue by kind: a kind filters before
--    the limit, an unknown kind is invalid, has_more says more are
--    waiting; each row carries id_check. (Fixture ids 240-244.)
-- =====================================================================
DO $af$
DECLARE
  v_owner constant uuid := pg_temp.id('140');
  v_t constant uuid := pg_temp.man('240');
  v_k uuid;
  v jsonb;
BEGIN
  v_k := pg_temp.sig(v_t, 'location_mismatch');
  v := public.moderation_queue(v_owner, 200, 'signal');
  IF (public.moderation_queue(v_owner, 50, 'nonsense') ->> 'reason') IS DISTINCT FROM 'invalid'
     OR NOT (v -> 'cases') @> jsonb_build_array(jsonb_build_object('id', v_k, 'kind', 'signal'))
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'cases') AS e WHERE e ->> 'kind' <> 'signal')
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(public.moderation_queue(v_owner, 200, 'appeal') -> 'cases') AS e WHERE e ->> 'kind' <> 'appeal')
     OR (public.moderation_queue(v_owner, 1) ->> 'has_more')::boolean IS NOT TRUE
     OR jsonb_array_length(public.moderation_queue(v_owner, 1) -> 'cases') <> 1
     OR (public.moderation_queue(v_owner, 200, 'signal') ->> 'has_more')::boolean IS NOT FALSE
     OR NOT (public.moderation_queue(v_owner, 200, 'signal') #> '{cases,0}') ? 'id_check' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the queue by kind read % (kind before the limit, invalid, has_more, id_check)', v;
  END IF;
END $af$;

-- =====================================================================
-- AG. (W7 final server fix, I-9, M-1, M-2, M-5, M-6, M-11, client I-3)
--    The SLA sentence only once moderators are named; the W7 gate on the
--    flag the owner signs; an appeal's busy counted; a rejected SLA alert
--    counted from the next run; a pre-W7 report gets its case; a
--    snapshot that can't be written never loses the report; the
--    summary's actions by source; the restricted person reads where their
--    hold came from. (Fixture ids 245-259.)
-- =====================================================================
CREATE FUNCTION public.w7_final_busy() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'w7 busy' USING ERRCODE = '55P03';
END $$;
DO $ag$
DECLARE
  v_owner constant uuid := pg_temp.id('140');
  v_w constant uuid := pg_temp.ready('245');
  v_t constant uuid := pg_temp.man('246');
  v_a constant uuid := pg_temp.man('247');
  v_h constant uuid := pg_temp.man('248');
  v_m constant uuid := pg_temp.man('249');
  v_cs constant uuid := pg_temp.man('250');
  v_e constant uuid := pg_temp.man('251');
  v_r uuid;
  v_rep uuid;
  v_n bigint;
  v_got text;
  v jsonb;
BEGIN
  -- (1) I-9: staffed only in production with an active safety owner and an
  -- active moderator; the gate row names the W7 gate.
  v_rep := private.dating_file_report(v_w, v_t, public.dating_phone_hmac_for_user(v_t), NULL, NULL, 'spam', NULL, 'low', pg_temp.key('ag'));
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  v_got := private.dating_report_answer(v_rep) ->> 'review';
  UPDATE public.dating_moderators SET active = false WHERE role = 'moderator';
  v_got := v_got || '/' || (private.dating_report_answer(v_rep) ->> 'review');
  UPDATE public.dating_moderators SET active = true WHERE role = 'moderator';
  PERFORM set_config('app.settings.attune_environment', '', true);
  IF v_got IS DISTINCT FROM 'staffed/testing'
     OR NOT EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'dating_match_messaging'
                     AND gate LIKE '%Spec 2 W7 gate%DATING_MODERATION_RUNBOOK.md%DATING_LAW_ENFORCEMENT_POLICY.md%private.dating_report_sla_due%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the SLA sentence or the W7 gate read % (staffed only with named moderators; the gate row)', v_got;
  END IF;
  -- (2) M-1: an appeal that can't get its locks answers busy, counted, listed.
  v_r := private.dating_place_restriction(v_a, 'suspended', 'spam', 'moderator', NULL, v_owner, NULL, true);
  v_n := pg_temp.metric('dating.appeal.busy');
  v_got := pg_temp.probe(ARRAY['CREATE TRIGGER w7_final_busy BEFORE INSERT ON public.dating_appeals FOR EACH ROW EXECUTE FUNCTION public.w7_final_busy()',
                     format($f$SELECT set_config('w7.busy', pg_temp.j(%L, '247', format('SELECT public.submit_dating_appeal(%%L, %%L, NULL)', pg_temp.key('ag-ap'), %L))::text, true)$f$, v_a, v_r)],
                     format($f$SELECT (current_setting('w7.busy', true)::jsonb ->> 'reason') || '/' || (pg_temp.metric('dating.appeal.busy') - %s)$f$, v_n));
  IF v_got IS DISTINCT FROM 'busy/1' OR NOT (public.get_dating_operational_health() -> 'safety_counters_7d') ?& ARRAY['dating.appeal.busy', 'dating.sla.alert_rejected'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an appeal''s busy read % (counted, listed in health)', v_got;
  END IF;
  -- (3) M-2: a webhook that answers 4xx is counted on the next run.
  v_n := pg_temp.metric('dating.sla.alert_rejected');
  v_got := pg_temp.probe(ARRAY[
      'CREATE TABLE IF NOT EXISTS net._http_response (id bigint, status_code integer, timed_out boolean, error_msg text, created timestamptz DEFAULT now())',
      'DELETE FROM net._http_response',
      'DELETE FROM pg_temp.w7_posts',
      format($f$INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, sla_due_at, created_at)
                VALUES ('report', 'P3', %L, now() - interval '1 hour', now() - interval '80 hours')$f$, v_m),
      $f$SELECT set_config('app.settings.moderation_alert_webhook', 'https://alerts.invalid/hook', true)$f$,
      'SELECT public.dating_moderation_sla_check(now())',
      'INSERT INTO net._http_response (id, status_code) VALUES (1, 403)',
      'SELECT public.dating_moderation_sla_check(now())',
      $f$SELECT set_config('app.settings.moderation_alert_webhook', '', true)$f$],
    format('SELECT (pg_temp.metric(%L) - %s)::text', 'dating.sla.alert_rejected', v_n));
  IF v_got IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a rejected SLA alert was counted % times (once, on the next run)', v_got;
  END IF;
  -- (4) M-5: an open pre-W7 report with no case gets one.
  INSERT INTO public.dating_reports (category, target_user_id, reporter_user_id) VALUES ('harassment', v_h, v_w) RETURNING id INTO v_rep;
  UPDATE public.dating_reports SET case_id = NULL WHERE id = v_rep;
  DELETE FROM public.dating_moderation_cases WHERE target_user_id = v_h;
  v_got := private.dating_backfill_report_cases()::text;
  IF coalesce(v_got::int, 0) < 1 OR (SELECT c.kind || '/' || c.state FROM public.dating_reports AS r JOIN public.dating_moderation_cases AS c ON c.id = r.case_id
                                    WHERE r.id = v_rep) IS DISTINCT FROM 'report/open' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pre-W7 open report was not given a case: %', v_got;
  END IF;
  -- (5) M-6: an encryption error other than a missing key: the report
  -- stands without evidence, counted, never a raise.
  v_n := pg_temp.metric('dating.report.evidence_unavailable');
  v_got := pg_temp.probe(ARRAY[
      $f$CREATE OR REPLACE FUNCTION private.dating_field_encrypt(p_plain jsonb) RETURNS bytea LANGUAGE plpgsql AS 'BEGIN RAISE EXCEPTION ''w7 boom''; END'$f$,
      format($f$SELECT set_config('w7.ev', pg_temp.report(%L, '245', pg_temp.match(%L, %L), 'spam')::text, true)$f$, v_w, v_w, v_e)],
    format($f$SELECT (current_setting('w7.ev', true)::jsonb ->> 'ok') || '/' || (pg_temp.metric('dating.report.evidence_unavailable') - %s)$f$, v_n));
  IF v_got IS DISTINCT FROM 'true/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an evidence snapshot error reached the reporter: %', v_got;
  END IF;
  -- (6) M-11: the summary's actions by where they came from.
  v := public.moderation_transparency_summary(v_owner, current_date - 1, current_date + 1);
  IF NOT (v -> 'summary') ? 'actions_by_source' OR (v #>> '{summary,actions_by_source,moderator,suspended}')::int < 1
     OR (v #> '{summary,actions_by_source}') ? 'carried_over' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the summary''s actions by source read %', v -> 'summary';
  END IF;
  -- (7) Client I-3: the restricted person reads where their hold came from.
  PERFORM private.dating_place_restriction(v_cs, 'moderation_hold', 'csam', 'report', NULL, NULL, NULL, false);
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, category, source, appealable)
  VALUES (v_e, 'moderation_hold', 'harassment', 'moderator', false);
  v_got := concat_ws(' ', pg_temp.j(v_cs, '250', 'SELECT public.get_my_dating_restriction()') #>> '{restriction,source}',
                          pg_temp.j(v_e, '251', 'SELECT public.get_my_dating_restriction()') #>> '{restriction,source}',
                          pg_temp.j(v_a, '247', 'SELECT public.get_my_dating_restriction()') #>> '{restriction,source}');
  IF v_got IS DISTINCT FROM 'csam moderator moderator' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restriction read''s source read %', v_got;
  END IF;
END $ag$;
DROP FUNCTION public.w7_final_busy();

-- =====================================================================
-- AJ. (W7 final server fix round 4: N3-1, m3-2, m3-3, m3-4) An ID case
--    whose person deleted while it was open: No ID came closes it on the
--    record the deletion left (the number stays checked; a returning
--    account reads the check and a late Lift frees it); Dismiss and Lift
--    are refused, so nothing frees an unverified person. Ask finds that
--    orphaned case by the number; carry-over's relink never raises. Lift
--    after Lift the case's holds and a Dismiss answers case_unavailable.
--    Health counts open ID cases and the oldest wait. (Fixture ids
--    270-289.)
-- =====================================================================
DO $aj$
DECLARE
  v_mod constant uuid := pg_temp.id('170');
  v_owner constant uuid := pg_temp.id('140');
  v_w constant uuid := pg_temp.ready('270');
  v_t1 uuid := pg_temp.man('271');
  v_t2 uuid := pg_temp.man('273');
  v_t3 uuid := pg_temp.man('276');
  v_t4 constant uuid := pg_temp.man('279');
  v_t1b uuid;
  v_t2b uuid;
  v_t3b uuid;
  v_h1 text;
  v_h2 text;
  v_c uuid;
  v_x1 uuid;
  v_x2 uuid;
  v_x3 uuid;
  v_x4 uuid;
  v jsonb;
  v_got text;
  v_new constant text := $s$INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, state, sla_due_at, created_at)
                            VALUES ('report', 'P2', %L, 'open', now() + interval '40 hours', now() - interval '4 hours') RETURNING id$s$;
  v_rep constant text := $s$INSERT INTO public.dating_reports (category, case_id, target_user_id, reporter_user_id, priority, sla_due_at)
                            VALUES (%L, %L, %L, %L, 'P2', now() + interval '20 hours')$s$;
BEGIN
  -- (1) N3-1: ask, delete, No ID came on the record, return: still checked;
  -- a late Lift then frees the returning account.
  EXECUTE format(v_new, v_t1) INTO v_c;
  EXECUTE format(v_rep, 'underage_risk', v_c, v_t1, v_w);
  v_x1 := (public.moderation_ask_for_id(v_mod, v_c) ->> 'id_case')::uuid;
  v_h1 := public.dating_phone_hmac_for_user(v_t1);
  PERFORM pg_temp.delete_account(v_t1);
  v_got := concat_ws(' ', (SELECT target_user_id IS NULL AND target_phone_hmac = v_h1 FROM public.dating_moderation_cases WHERE id = v_x1),
                     public.moderation_dismiss(v_owner, v_x1) ->> 'reason', public.moderation_lift_hold(v_owner, v_x1) ->> 'reason',
                     public.moderation_close_no_id(v_owner, v_x1)::text);
  v_got := concat_ws(' ', v_got, pg_temp.cs(v_x1), pg_temp.reps(v_x1),
                     EXISTS (SELECT 1 FROM public.enforcement_records WHERE phone_hmac = v_h1 AND scope = 'dating' AND restriction_type = 'age_review'
                                AND (effect_until IS NULL OR effect_until > now())));
  v_t1b := pg_temp.man('272', '{"phone": "271"}');
  v := pg_temp.j(v_t1b, '272', 'SELECT public.get_my_dating_restriction()');
  v_got := concat_ws(' ', v_got, v #>> '{restriction,source}', (v #>> '{restriction,id_check_code}') IS NOT NULL,
                     public.dating_account_in_good_standing(v_t1b), pg_temp.ic(v_x1) ->> 'state',
                     public.moderation_lift_hold(v_owner, v_x1) ->> 'lifted', pg_temp.held(v_t1b));
  v_got := concat_ws(' ', v_got, public.dating_account_in_good_standing(v_t1b)); -- (a STABLE read: its own statement)
  IF v_got IS DISTINCT FROM concat_ws(' ', 't case_unavailable case_unavailable {"ok": true}', 'id_check/decided/no_id_received underage_risk=upheld t',
                                     'id_check t f no_id 1  t') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an orphaned ID case read % (No ID came on the record, never Dismiss; checked on return)', v_got;
  END IF;

  -- (2) N3-1, m3-2: Dismiss refused on an orphaned open ID case; the
  -- returning account can't be asked again (the orphan found by number).
  EXECUTE format(v_new, v_t2) INTO v_c;
  EXECUTE format(v_rep, 'underage_risk', v_c, v_t2, v_w);
  v_x2 := (public.moderation_ask_for_id(v_mod, v_c) ->> 'id_case')::uuid;
  v_h2 := public.dating_phone_hmac_for_user(v_t2);
  PERFORM pg_temp.delete_account(v_t2);
  v_got := concat_ws(' ', public.moderation_dismiss(v_owner, v_x2) ->> 'reason', pg_temp.cs(v_x2),
                     EXISTS (SELECT 1 FROM public.enforcement_records WHERE phone_hmac = v_h2 AND scope = 'dating' AND restriction_type = 'age_review'
                                AND (effect_until IS NULL OR effect_until > now())));
  v_t2b := pg_temp.man('274', '{"phone": "273"}');
  EXECUTE format(v_new, v_t2b) INTO v_c;
  UPDATE public.dating_moderation_cases SET target_phone_hmac = v_h2 WHERE id = v_c;
  v_got := concat_ws(' ', v_got, public.moderation_ask_for_id(v_owner, v_c) ->> 'reason',
                     (SELECT count(*) FROM public.dating_moderation_cases WHERE kind = 'id_check' AND target_phone_hmac = v_h2));
  IF v_got IS DISTINCT FROM 'case_unavailable id_check/in_review/- t case_unavailable 1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dismiss on an orphaned ID case, or a second ask on its number, read %', v_got;
  END IF;

  -- (3) m3-2: the relink never raises: an orphaned open ID case and the
  -- returning account's own open one; the read answers, the orphan stays.
  EXECUTE format(v_new, v_t3) INTO v_c;
  EXECUTE format(v_rep, 'underage_risk', v_c, v_t3, v_w);
  v_x3 := (public.moderation_ask_for_id(v_mod, v_c) ->> 'id_case')::uuid;
  PERFORM pg_temp.delete_account(v_t3);
  v_t3b := pg_temp.man('277', '{"phone": "276"}');
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, state, awaiting_id_since)
  VALUES ('id_check', 'P2', v_t3b, 'in_review', now());
  v_c := (SELECT awaiting_id_restriction FROM public.dating_moderation_cases WHERE id = v_x3);
  v_got := pg_temp.metric('dating.carry_over.relink_skipped')::text;
  v := pg_temp.j(v_t3b, '277', 'SELECT public.get_my_dating_restriction()');
  IF (v ->> 'ok') IS DISTINCT FROM 'true'
     OR (SELECT target_user_id FROM public.dating_moderation_cases WHERE id = v_x3) IS NOT NULL
     OR (SELECT awaiting_id_restriction FROM public.dating_moderation_cases WHERE id = v_x3) IS DISTINCT FROM v_c
     OR pg_temp.metric('dating.carry_over.relink_skipped') <> v_got::bigint + 1
     OR NOT (public.get_dating_operational_health() -> 'safety_counters_7d') ? 'dating.carry_over.relink_skipped' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: carry-over''s relink raised or doubled an open ID case: %', v;
  END IF;

  -- (4) m3-3: Lift the case's holds on an open ID case, Dismiss, then Lift:
  -- case_unavailable (never the holds lift's replay).
  EXECUTE format(v_new, v_t4) INTO v_c;
  EXECUTE format(v_rep, 'underage_risk', v_c, v_t4, v_w);
  v_x4 := (public.moderation_ask_for_id(v_mod, v_c) ->> 'id_case')::uuid;
  v_got := concat_ws(' ', public.moderation_lift_case_holds(v_mod, v_x4)::text, public.moderation_dismiss(v_mod, v_x4) ->> 'ok',
                     public.moderation_lift_hold(v_mod, v_x4)::text);
  IF v_got IS DISTINCT FROM '{"ok": true, "lifted": 0} true {"ok": false, "reason": "case_unavailable"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Lift after a holds lift and a dismissal read %', v_got;
  END IF;

  -- (5) m3-4: health counts open ID cases and the oldest wait (no paging).
  UPDATE public.dating_moderation_cases SET created_at = now() - interval '50 hours' WHERE id = v_x2;
  v := public.get_dating_operational_health() -> 'id_checks_open';
  IF (v ->> 'open')::int < 2 OR (v ->> 'oldest_hours')::int < 50 OR (SELECT count(*) FROM jsonb_object_keys(v)) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health''s open ID cases read %', v;
  END IF;
END $aj$;

-- @@W7-END@@

DO $$ BEGIN RAISE NOTICE 'dating_v2_moderation_contracts: all held'; END $$;
ROLLBACK;
