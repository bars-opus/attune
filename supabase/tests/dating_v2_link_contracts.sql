-- supabase/tests/dating_v2_link_contracts.sql
-- Spec 2 W9 (§3.9, §4.3, §4.4, §7.1; S-4, S-5, S-6, A-3, I-12, I-13):
-- "Become a couple on Attune" and the export's own-data Dating part.
--   L (Task 1). The couple link: no relationships row before both say
--      yes; the second Yes makes an active relationship through the
--      invite exchange's rows, pauses both, closes every other open
--      conversation with the neutral reason, sets both paths; the first
--      messages are kept only when both chose it, masked unless both
--      swapped (A-3); a request says nothing about the other person (S-5,
--      carry 5).
--   E (Task 2). The origin, How we met, the post-link offer, the export.
-- Fixture ids 8a900000-0000-0000-0000-0000000000nn, phones +1555982nn:
-- L 01-49, E 50-89, F (final server fix) 90-99.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_link_contracts.sql
BEGIN;

-- =====================================================================
-- Setup: the keys, the flags (dating_couple_link is turned on below, after
-- L1 reads it off, inside this file's transaction), Ghana and the UK open.
-- =====================================================================
DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w9-link-key', true);
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w9-field-key-0123456789abcdef-0123', true);
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w9-push-key', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
SELECT private.seed_dating_field_key_fingerprint() AS seeded_field \gset
INSERT INTO public.feature_flags (key, enabled)
VALUES ('dating_mode_enabled', true), ('dating_same_gender_matching', true), ('dating_match_messaging', true),
       ('dating_profile_photos', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;
SELECT public.publish_country_config('GH', '{"dating_enabled": true, "open_regions": ["AA", "AH"]}') AS gh \gset
SELECT public.publish_country_config('GB', '{"dating_enabled": true}') AS gb \gset

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('8a900000-0000-0000-0000-' || lpad(p_n, 12, '0'))::uuid;
$$;
CREATE FUNCTION pg_temp.dev(p_n text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT md5('w9-link-' || p_n);
$$;
CREATE FUNCTION pg_temp.hash(p_n text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT encode(extensions.digest(pg_temp.dev(p_n), 'sha256'), 'hex');
$$;
-- A person in Dating, active, verified, on their trusted phone.
CREATE FUNCTION pg_temp.ready(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.id(p_n);
  d constant jsonb := '{"identity": "woman", "seeking": ["man"], "country": "GH", "region": "AA", "years": 30,
    "days": 40, "state": "active"}'::jsonb || o;
  v_phone constant text := '+1555982' || p_n;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_u, ltrim(v_phone, '+'), now(), now() - make_interval(days => (d ->> 'days')::int));
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_u, v_phone, 'Link ' || p_n, 'dating', now() - make_interval(days => (d ->> 'days')::int), now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_u, (current_date - make_interval(years => (d ->> 'years')::int) - interval '10 days')::date);
  INSERT INTO public.dating_enrollments (user_id, state, opted_in_at, activated_at)
  VALUES (v_u, d ->> 'state', now(), CASE WHEN d ->> 'state' = 'active' THEN now() END);
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, moderation_state, verification_state,
    country_code, region_code, intention, timeline_visible, not_married_attested_at, attestation_version,
    children_have, children_want, faith_visible)
  VALUES (v_u, 'Link ' || p_n, 'active', 'approved', 'verified', d ->> 'country', d ->> 'region',
    'committed', true, now(), '2026-10-v1', false, 'yes', false);
  INSERT INTO public.dating_preferences (user_id, min_age, max_age, region_scope, open_abroad, want_must_match, exclude_parents)
  VALUES (v_u, 25, 40, 'country', '{}', false, false);
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  VALUES (v_u, private.dating_field_encrypt(jsonb_build_object('identity', d ->> 'identity', 'pools', jsonb_build_array(d ->> 'identity'))),
          private.dating_field_encrypt(jsonb_build_object('seeking', d -> 'seeking')));
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'w9-consent-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']) AS p;
  INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
  VALUES (v_u, pg_temp.hash(p_n), now(), now());
  RETURN v_u;
END $$;
-- A UK person (region TLI).
CREATE FUNCTION pg_temp.uk(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE sql AS $$
  SELECT pg_temp.ready(p_n, '{"country": "GB", "region": "TLI"}'::jsonb || o);
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
-- [p]'s own call from phone [p_n] (null: no install id), as jsonb.
CREATE FUNCTION pg_temp.j(p uuid, p_n text, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_person(p, CASE WHEN p_n IS NULL THEN NULL ELSE pg_temp.dev(p_n) END);
  EXECUTE p_sql INTO v;
  PERFORM pg_temp.as_db();
  RETURN v::jsonb;
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.as_db();
  RETURN jsonb_build_object('raised', SQLSTATE || ':' || SQLERRM);
END $$;
CREATE FUNCTION pg_temp.key(p text) RETURNS text LANGUAGE sql AS $$
  SELECT 'w9-' || p || '-' || replace(gen_random_uuid()::text, '-', '');
$$;
CREATE FUNCTION pg_temp.match(p_a uuid, p_b uuid, p_days int DEFAULT 10) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at, pair_key, chat_started_at)
  VALUES (least(p_a, p_b), greatest(p_a, p_b), 'active', now() - make_interval(days => p_days), public.dating_pair_key(p_a, p_b),
          now() - make_interval(days => p_days))
  RETURNING id;
$$;
-- [p]'s side of match [m].
CREATE FUNCTION pg_temp.side(m uuid, p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN x.user_low_id = p THEN 'low' ELSE 'high' END FROM public.dating_matches AS x WHERE x.id = m;
$$;
-- A message from [p] in [m], [p_min] minutes ago (masked text 'masked n').
CREATE FUNCTION pg_temp.say(m uuid, p uuid, p_n int, p_min int, p_kind text DEFAULT 'text', p_q text DEFAULT NULL)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, kind, question_id, body, body_masked,
                                      mask_version, idempotency_key, created_at)
  VALUES (m, pg_temp.side(m, p), p, p_kind, p_q, 'plain ' || p_n, 'masked ' || p_n, 1, 'w9-say-' || m || '-' || p_n,
          now() - make_interval(mins => p_min));
$$;
CREATE FUNCTION pg_temp.we_met(m uuid, p uuid) RETURNS void LANGUAGE sql AS $$
  UPDATE public.dating_matches SET low_we_met_at = CASE WHEN user_low_id = p THEN now() ELSE low_we_met_at END,
                                   high_we_met_at = CASE WHEN user_high_id = p THEN now() ELSE high_we_met_at END
   WHERE id = m;
$$;
CREATE FUNCTION pg_temp.swap(m uuid) RETURNS void LANGUAGE sql AS $$
  UPDATE public.dating_matches SET low_swap_at = now(), high_swap_at = now() WHERE id = m;
$$;
CREATE FUNCTION pg_temp.ask(p uuid, p_n text, m uuid, p_keep boolean, p_show boolean DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, format('SELECT public.request_dating_couple_link(%L, %L, %L%s)', pg_temp.key('ask'), m, p_keep,
                                  CASE WHEN p_show IS NULL THEN '' ELSE format(', p_show_same_gender => %L', p_show) END));
$$;
CREATE FUNCTION pg_temp.yes(p uuid, p_n text, r uuid, p_keep boolean, p_show boolean DEFAULT NULL, p_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, format('SELECT public.confirm_dating_couple_link(%L, %L, %L%s)', coalesce(p_key, pg_temp.key('yes')), r, p_keep,
                                  CASE WHEN p_show IS NULL THEN '' ELSE format(', p_show_same_gender => %L', p_show) END));
$$;
CREATE FUNCTION pg_temp.no(p uuid, p_n text, r uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, format('SELECT public.decline_dating_couple_link(%L)', r));
$$;
CREATE FUNCTION pg_temp.take_back(p uuid, p_n text, r uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, format('SELECT public.cancel_dating_couple_link(%L)', r));
$$;
-- The chat header's link, and the link page's read, as [p] sees [m].
CREATE FUNCTION pg_temp.link(p uuid, p_n text, m uuid, p_show boolean DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT coalesce(v -> 'chat' -> 'link', CASE WHEN v ->> 'ok' = 'true' THEN 'null'::jsonb
                                              ELSE jsonb_build_object('read', coalesce(v ->> 'reason', v ->> 'raised')) END)
    FROM (SELECT pg_temp.j(p, p_n, format('SELECT public.get_dating_messages(%L%s)', m,
                           CASE WHEN p_show IS NULL THEN '' ELSE format(', p_show_same_gender => %L', p_show) END)) AS v) AS x;
$$;
CREATE FUNCTION pg_temp.page(p uuid, p_n text, m uuid, p_show boolean DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, p_n, format('SELECT public.get_dating_couple_link(%L%s)', m,
                   CASE WHEN p_show IS NULL THEN '' ELSE format(', p_show_same_gender => %L', p_show) END));
$$;
-- Every relationships row either person is in.
CREATE FUNCTION pg_temp.rels(p_a uuid, p_b uuid) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM public.relationships AS r WHERE r.user_a IN (p_a, p_b) OR r.user_b IN (p_a, p_b);
$$;
-- dating-device-check's call, as the service role (a same-gender trip).
CREATE FUNCTION pg_temp.check(p uuid, p_n text, p_ip text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.record_dating_device_check(p, pg_temp.hash(p_n), p_ip, NULL);
  RESET ROLE;
  RETURN v;
END $$;

-- =====================================================================
-- L1. The flag is off as the migration leaves it, with its production
--     gate; with it off nothing links. The couple link's functions are
--     the app's alone; its tables nobody's (S-5).
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('01');
  v_b constant uuid := pg_temp.ready('02', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_t text;
BEGIN
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'dating_couple_link') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_couple_link is not off';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'dating_couple_link') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_couple_link has no production gate';
  END IF;
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.we_met(v_m, v_a);
  IF pg_temp.ask(v_a, '01', v_m, true) ->> 'reason' IS DISTINCT FROM 'unavailable'
     OR pg_temp.page(v_a, '01', v_m) ->> 'reason' IS DISTINCT FROM 'unavailable'
     OR pg_temp.link(v_a, '01', v_m) IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off the couple link answers: % / % / %',
      pg_temp.ask(v_a, '01', v_m, true), pg_temp.page(v_a, '01', v_m), pg_temp.link(v_a, '01', v_m);
  END IF;
  FOREACH v_t IN ARRAY ARRAY['public.get_dating_couple_link(uuid,boolean)',
                             'public.request_dating_couple_link(text,uuid,boolean,boolean)',
                             'public.decline_dating_couple_link(uuid)', 'public.cancel_dating_couple_link(uuid)',
                             'public.confirm_dating_couple_link(text,uuid,boolean,boolean)'] LOOP
    IF NOT has_function_privilege('authenticated', v_t, 'EXECUTE') OR has_function_privilege('anon', v_t, 'EXECUTE')
       OR has_function_privilege('service_role', v_t, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is not the app''s alone', v_t;
    END IF;
  END LOOP;
  FOREACH v_t IN ARRAY ARRAY['public.dating_couple_link_requests', 'public.couple_how_we_met', 'public.dating_link_origins'] LOOP
    IF has_table_privilege('anon', v_t, 'SELECT') OR has_table_privilege('authenticated', v_t, 'SELECT')
       OR has_table_privilege('service_role', v_t, 'SELECT') OR has_table_privilege('service_role', v_t, 'INSERT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is readable or writable by an API role (S-5)', v_t;
    END IF;
  END LOOP;
END $$;

UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_couple_link';

-- =====================================================================
-- L2. Before either says We met there is nothing to ask (not_yet; the
--     header offers nothing); once either has, both may (state none). The
--     link page reads the other person's first name. The answers are the
--     same as the chat's header.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('03');
  v_b constant uuid := pg_temp.ready('04', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v jsonb;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  IF pg_temp.link(v_a, '03', v_m) IS DISTINCT FROM 'null'::jsonb
     OR pg_temp.ask(v_a, '03', v_m, false) ->> 'reason' IS DISTINCT FROM 'not_yet' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Become a couple is offered before We met: %', pg_temp.link(v_a, '03', v_m);
  END IF;
  PERFORM pg_temp.we_met(v_m, v_b);
  v := pg_temp.page(v_a, '03', v_m);
  IF pg_temp.link(v_a, '03', v_m) IS DISTINCT FROM '{"state": "none"}'::jsonb
     OR pg_temp.link(v_b, '04', v_m) IS DISTINCT FROM '{"state": "none"}'::jsonb
     OR v IS DISTINCT FROM jsonb_build_object('ok', true, 'display_name', 'Link 04', 'link', '{"state": "none"}'::jsonb) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the other side''s We met: % / % / %', pg_temp.link(v_a, '03', v_m),
      pg_temp.link(v_b, '04', v_m), v;
  END IF;
  IF pg_temp.page(v_a, NULL, v_m) ->> 'reason' IS DISTINCT FROM 'reverify_device'
     OR pg_temp.page(pg_temp.ready('05'), '05', v_m) ->> 'reason' IS DISTINCT FROM 'match_unavailable'
     OR pg_temp.ask(pg_temp.id('05'), '05', v_m, false) ->> 'reason' IS DISTINCT FROM 'match_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the link page answers another phone or a stranger';
  END IF;
END $$;

-- =====================================================================
-- L3. Asking (step 1): the asker's Yes and keep choice; a replay is the
--     same request; the other side sees asked_you, the asker asked; no
--     relationships row before both say yes (mutant 21), not even when the
--     asker "confirms" their own request; the other side's own ask is
--     asked_you; nothing is said about the other person.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('06');
  v_b constant uuid := pg_temp.ready('07', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v jsonb;
  v_r uuid;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.we_met(v_m, v_a);
  v := pg_temp.ask(v_a, '06', v_m, true);
  v_r := (v ->> 'request_id')::uuid;
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v_r IS NULL
     OR pg_temp.ask(v_a, '06', v_m, true) IS DISTINCT FROM v THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: asking (or its replay) answered % / %', v, pg_temp.ask(v_a, '06', v_m, true);
  END IF;
  IF pg_temp.link(v_a, '06', v_m) IS DISTINCT FROM jsonb_build_object('state', 'asked', 'request_id', v_r)
     OR pg_temp.link(v_b, '07', v_m) IS DISTINCT FROM jsonb_build_object('state', 'asked_you', 'request_id', v_r) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the headers after asking: % / %', pg_temp.link(v_a, '06', v_m), pg_temp.link(v_b, '07', v_m);
  END IF;
  IF (SELECT count(*) FROM public.dating_couple_link_requests WHERE match_id = v_m) <> 1
     OR (SELECT r.state || ':' || r.requested_by_side || ':' || (CASE WHEN r.requested_by_side = 'low' THEN r.low_keep_messages
                                                                    ELSE r.high_keep_messages END)
           FROM public.dating_couple_link_requests AS r WHERE r.id = v_r) IS DISTINCT FROM 'open:' || pg_temp.side(v_m, v_a) || ':true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the request row is wrong';
  END IF;
  IF pg_temp.rels(v_a, v_b) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a relationships row exists after the first Yes';
  END IF;
  v := pg_temp.yes(v_a, '06', v_r, true);
  IF v IS DISTINCT FROM '{"ok": false, "reason": "asked"}'::jsonb OR pg_temp.rels(v_a, v_b) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the asker''s own confirmation made the couple: %', v;
  END IF;
  IF pg_temp.ask(v_b, '07', v_m, false) IS DISTINCT FROM '{"ok": false, "reason": "asked_you"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other side could open a second request';
  END IF;
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_a) IS DISTINCT FROM 'active'
     OR (SELECT path FROM public.users WHERE id = v_b) IS DISTINCT FROM 'dating' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: asking changed someone''s Dating or path';
  END IF;
END $$;

-- =====================================================================
-- L4. "Not right now" (step 2) and taking it back: only the other side
--     declines, only the asker takes back (each replay ok); the asker then
--     reads not_ready and can't ask again for 14 days; the decliner may ask
--     at once; after 14 days the asker may ask again.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('08');
  v_b constant uuid := pg_temp.ready('09', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_r uuid;
  v_r2 uuid;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.we_met(v_m, v_a);
  v_r := (pg_temp.ask(v_a, '08', v_m, false) ->> 'request_id')::uuid;
  IF pg_temp.no(v_a, '08', v_r) ->> 'reason' IS DISTINCT FROM 'request_unavailable'
     OR pg_temp.take_back(v_b, '09', v_r) ->> 'reason' IS DISTINCT FROM 'request_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the wrong side could decline or take back';
  END IF;
  IF pg_temp.no(v_b, '09', v_r) IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.no(v_b, '09', v_r) IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Not right now (or its replay) failed';
  END IF;
  IF pg_temp.link(v_a, '08', v_m) IS DISTINCT FROM '{"state": "not_ready"}'::jsonb
     OR pg_temp.link(v_b, '09', v_m) IS DISTINCT FROM '{"state": "none"}'::jsonb
     OR pg_temp.ask(v_a, '08', v_m, false) IS DISTINCT FROM '{"ok": false, "reason": "not_ready"}'::jsonb
     OR pg_temp.yes(v_b, '09', v_r, false) ->> 'reason' IS DISTINCT FROM 'request_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after Not right now: % / % / %', pg_temp.link(v_a, '08', v_m), pg_temp.link(v_b, '09', v_m),
      pg_temp.ask(v_a, '08', v_m, false);
  END IF;
  v_r2 := (pg_temp.ask(v_b, '09', v_m, false) ->> 'request_id')::uuid;
  IF v_r2 IS NULL OR pg_temp.take_back(v_b, '09', v_r2) IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.take_back(v_b, '09', v_r2) IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.link(v_a, '08', v_m) IS DISTINCT FROM '{"state": "not_ready"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the decliner''s own ask and its take-back: %', pg_temp.link(v_a, '08', v_m);
  END IF;
  UPDATE public.dating_couple_link_requests SET decided_at = now() - interval '13 days' WHERE id = v_r;
  IF pg_temp.ask(v_a, '08', v_m, false) IS DISTINCT FROM '{"ok": false, "reason": "not_ready"}'::jsonb
     OR pg_temp.link(v_a, '08', v_m) IS DISTINCT FROM '{"state": "not_ready"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 13 days after Not right now the asker could ask again';
  END IF;
  UPDATE public.dating_couple_link_requests SET decided_at = now() - interval '15 days' WHERE id = v_r;
  IF (pg_temp.ask(v_a, '08', v_m, false) ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 15 days after Not right now the asker still can''t ask';
  END IF;
END $$;

-- =====================================================================
-- L5. A request lapses after 14 days with no copy: the header shows
--     nothing of it, the second Yes is refused, and either may ask anew.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('10');
  v_b constant uuid := pg_temp.ready('11', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_r uuid;
  v jsonb;
BEGIN
  v_m := pg_temp.match(v_a, v_b, 30);
  PERFORM pg_temp.we_met(v_m, v_a);
  v_r := (pg_temp.ask(v_a, '10', v_m, false) ->> 'request_id')::uuid;
  UPDATE public.dating_couple_link_requests SET created_at = now() - interval '15 days', expires_at = now() - interval '1 day'
   WHERE id = v_r;
  IF pg_temp.link(v_b, '11', v_m) IS DISTINCT FROM '{"state": "none"}'::jsonb
     OR pg_temp.link(v_a, '10', v_m) IS DISTINCT FROM '{"state": "none"}'::jsonb
     OR pg_temp.yes(v_b, '11', v_r, false) ->> 'reason' IS DISTINCT FROM 'request_unavailable'
     OR pg_temp.rels(v_a, v_b) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a lapsed request still shows or links: %', pg_temp.link(v_b, '11', v_m);
  END IF;
  v := pg_temp.ask(v_b, '11', v_m, false);
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR (SELECT state FROM public.dating_couple_link_requests WHERE id = v_r) IS DISTINCT FROM 'expired' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new request after a lapsed one';
  END IF;
END $$;

-- =====================================================================
-- L6. The second Yes (step 3): one transaction. An active relationship
--     through the invite exchange's rows (pending with a code, then active
--     with both, an acceptance row), the asker as user_a; both paused with
--     'relationship'; both paths Relationship; this conversation closed
--     couple_linked, every other open one of either person other_linked
--     (the other people's chats read ended, with nothing of the link);
--     their other requests cancelled; the first messages kept (both chose
--     it), masked (they hadn't both swapped), only what both could see;
--     the origin's match date; the asker's "You decided together." still
--     to come. A replay is the same couple.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('12');
  v_b constant uuid := pg_temp.ready('13', '{"identity": "man", "seeking": ["woman"]}');
  v_c constant uuid := pg_temp.ready('14', '{"identity": "man", "seeking": ["woman"]}');
  v_d constant uuid := pg_temp.ready('15');
  v_m uuid;
  v_ac uuid;
  v_bd uuid;
  v_r uuid;
  v_rc uuid;
  v jsonb;
  v_rel uuid;
  v_items jsonb;
BEGIN
  v_m := pg_temp.match(v_a, v_b, 20);
  v_ac := pg_temp.match(v_a, v_c, 5);
  v_bd := pg_temp.match(v_b, v_d, 5);
  PERFORM pg_temp.say(v_m, v_a, 1, 300);
  PERFORM pg_temp.say(v_m, v_b, 2, 200);
  -- A guided answer only A gave: B never saw it, so it is not kept.
  PERFORM pg_temp.say(v_m, v_a, 3, 150, 'guided_answer', 'good_saturday');
  PERFORM pg_temp.say(v_m, v_a, 4, 100);
  PERFORM pg_temp.we_met(v_m, v_b);
  PERFORM pg_temp.we_met(v_ac, v_a);
  v_rc := (pg_temp.ask(v_c, '14', v_ac, false) ->> 'request_id')::uuid;
  v_r := (pg_temp.ask(v_a, '12', v_m, true) ->> 'request_id')::uuid;
  v := pg_temp.yes(v_b, '13', v_r, true);
  v_rel := (v ->> 'relationship_id')::uuid;
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v_rel IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second Yes answered %', v;
  END IF;
  IF (SELECT r.status || ':' || (r.user_a = v_a) || ':' || (r.user_b = v_b) || ':' || (r.invite_code IS NULL)
             || ':' || (r.invite_accepted_at IS NOT NULL)
        FROM public.relationships AS r WHERE r.id = v_rel) IS DISTINCT FROM 'active:true:true:true:true'
     OR pg_temp.rels(v_a, v_b) <> 1
     OR NOT EXISTS (SELECT 1 FROM public.relationship_invite_acceptances AS x
                     WHERE x.relationship_id = v_rel AND x.accepted_by = v_b AND x.invite_code_hash ~ '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the relationship is not the invite exchange''s';
  END IF;
  IF (SELECT string_agg(e.state || '/' || coalesce(e.pause_reason, '-'), ',' ORDER BY e.user_id)
        FROM public.dating_enrollments AS e WHERE e.user_id IN (v_a, v_b)) IS DISTINCT FROM 'paused/relationship,paused/relationship'
     OR (SELECT string_agg(u.path, ',' ORDER BY u.id) FROM public.users AS u WHERE u.id IN (v_a, v_b))
        IS DISTINCT FROM 'relationship,relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: both are not paused for the relationship on the Relationship path';
  END IF;
  IF (SELECT state || '/' || closed_reason || '/' || (evidence_until > now() + interval '29 days') FROM public.dating_matches WHERE id = v_m)
        IS DISTINCT FROM 'closed/couple_linked/true'
     OR (SELECT string_agg(state || '/' || closed_reason, ',' ORDER BY id) FROM public.dating_matches WHERE id IN (v_ac, v_bd))
        IS DISTINCT FROM 'closed/other_linked,closed/other_linked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the conversations did not close as they should';
  END IF;
  IF (pg_temp.j(v_c, '14', format('SELECT public.get_dating_messages(%L)', v_ac)) -> 'chat' ->> 'state') IS DISTINCT FROM 'ended'
     OR pg_temp.link(v_c, '14', v_ac) IS DISTINCT FROM 'null'::jsonb
     OR pg_temp.link(v_d, '15', v_bd) IS DISTINCT FROM 'null'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = v_c AND match_id = v_ac)
     OR NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = v_d AND match_id = v_bd)
     OR (SELECT state FROM public.dating_couple_link_requests WHERE id = v_rc) IS DISTINCT FROM 'cancelled' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other people''s chats read more than an end: %', pg_temp.link(v_c, '14', v_ac);
  END IF;
  SELECT items INTO v_items FROM public.couple_how_we_met WHERE relationship_id = v_rel;
  IF jsonb_array_length(v_items) <> 3
     OR (SELECT string_agg(x ->> 'text', ',' ORDER BY n) FROM jsonb_array_elements(v_items) WITH ORDINALITY AS t(x, n))
        IS DISTINCT FROM 'masked 1,masked 2,masked 4'
     OR (v_items -> 0 ->> 'by') IS DISTINCT FROM v_a::text OR (v_items -> 1 ->> 'by') IS DISTINCT FROM v_b::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: How we met is not the first messages as both saw them: %', v_items;
  END IF;
  IF (SELECT o.matched_at FROM public.dating_link_origins AS o WHERE o.relationship_id = v_rel)
       IS DISTINCT FROM (SELECT matched_at FROM public.dating_matches WHERE id = v_m)
     OR (SELECT state || '/' || (relationship_id = v_rel) FROM public.dating_couple_link_requests WHERE id = v_r) IS DISTINCT FROM 'linked/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the origin or the request is wrong';
  END IF;
  IF pg_temp.link(v_a, '12', v_m) IS DISTINCT FROM '{"state": "linked", "moment": true}'::jsonb
     OR pg_temp.link(v_b, '13', v_m) IS DISTINCT FROM '{"state": "linked", "moment": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "You decided together." is not still to come for the asker alone: % / %',
      pg_temp.link(v_a, '12', v_m), pg_temp.link(v_b, '13', v_m);
  END IF;
  IF pg_temp.yes(v_b, '13', v_r, true) IS DISTINCT FROM jsonb_build_object('ok', true, 'relationship_id', v_rel)
     OR pg_temp.rels(v_a, v_b) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay of the second Yes made something else';
  END IF;
  -- Fix round 1 (I-1): the linked request is purged with its relationship;
  -- deleting the relationship (the nightly purge) never fails on it.
  BEGIN
    DELETE FROM public.relationships WHERE id = v_rel;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the linked request stops its relationship''s deletion: % %', SQLSTATE, SQLERRM;
  END;
  IF EXISTS (SELECT 1 FROM public.dating_couple_link_requests WHERE id = v_r) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the linked request outlived its relationship';
  END IF;
END $$;

-- =====================================================================
-- L7. Keep our first messages: only when both chose it (either side's
--     yes alone keeps nothing); once both swapped, the plain text (A-3).
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('16');
  v_b constant uuid := pg_temp.ready('17', '{"identity": "man", "seeking": ["woman"]}');
  v_c constant uuid := pg_temp.ready('18');
  v_d constant uuid := pg_temp.ready('19', '{"identity": "man", "seeking": ["woman"]}');
  v_e constant uuid := pg_temp.ready('31');
  v_f constant uuid := pg_temp.ready('32', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_m2 uuid;
  v_rel uuid;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.say(v_m, v_a, 1, 60);
  PERFORM pg_temp.we_met(v_m, v_a);
  v_rel := (pg_temp.yes(v_b, '17', (pg_temp.ask(v_a, '16', v_m, true) ->> 'request_id')::uuid, false) ->> 'relationship_id')::uuid;
  IF v_rel IS NULL OR EXISTS (SELECT 1 FROM public.couple_how_we_met WHERE relationship_id = v_rel) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one side''s choice kept the first messages';
  END IF;
  -- The asker didn't choose it, the other side did: nothing kept either.
  v_m := pg_temp.match(v_e, v_f);
  PERFORM pg_temp.say(v_m, v_e, 1, 60);
  PERFORM pg_temp.we_met(v_m, v_e);
  v_rel := (pg_temp.yes(v_f, '32', (pg_temp.ask(v_e, '31', v_m, false) ->> 'request_id')::uuid, true) ->> 'relationship_id')::uuid;
  IF v_rel IS NULL OR EXISTS (SELECT 1 FROM public.couple_how_we_met WHERE relationship_id = v_rel) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other side''s choice alone kept the first messages';
  END IF;
  v_m2 := pg_temp.match(v_c, v_d);
  PERFORM pg_temp.say(v_m2, v_d, 1, 60);
  PERFORM pg_temp.swap(v_m2);
  PERFORM pg_temp.we_met(v_m2, v_c);
  v_rel := (pg_temp.yes(v_c, '18', (pg_temp.ask(v_d, '19', v_m2, true) ->> 'request_id')::uuid, true) ->> 'relationship_id')::uuid;
  IF (SELECT items -> 0 ->> 'text' FROM public.couple_how_we_met WHERE relationship_id = v_rel) IS DISTINCT FROM 'plain 1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after both swapped How we met is not the plain text';
  END IF;
END $$;

-- =====================================================================
-- L8. Refusals that say nothing about the other person (Ruling R-W9-6,
--     carry 5): asking never depends on the other's life (an Attune
--     relationship, a same-gender trip that hides the chat on their
--     phone); the second Yes refuses (unavailable) while either is in an
--     open Attune relationship or under a hold, and changes nothing; a
--     blocked pair is closed; a chat the confirmer's own trip hides is
--     match_unavailable unless "Show it on this phone anyway".
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('20');
  v_b constant uuid := pg_temp.ready('21', '{"identity": "man", "seeking": ["woman"]}');
  v_x constant uuid := pg_temp.ready('22');
  v_g constant uuid := pg_temp.uk('23', '{"seeking": ["woman"]}');
  v_h constant uuid := pg_temp.uk('24', '{"seeking": ["woman"]}');
  v_p constant uuid := pg_temp.ready('25');
  v_q constant uuid := pg_temp.ready('26', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_gh uuid;
  v_pq uuid;
  v_r uuid;
  v_rel uuid;
  v jsonb;
BEGIN
  -- B is in an Attune relationship with X (Dating paused, the chat kept).
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.we_met(v_m, v_a);
  INSERT INTO public.relationships (user_a, user_b, status, invite_accepted_at) VALUES (v_b, v_x, 'active', now())
  RETURNING id INTO v_rel;
  v := pg_temp.ask(v_a, '20', v_m, false);
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: asking told the asker about the other''s relationship: %', v;
  END IF;
  v_r := (v ->> 'request_id')::uuid;
  IF pg_temp.yes(v_b, '21', v_r, false) IS DISTINCT FROM '{"ok": false, "reason": "unavailable"}'::jsonb
     OR pg_temp.rels(v_a, v_a) <> 0
     OR (SELECT state FROM public.dating_couple_link_requests WHERE id = v_r) IS DISTINCT FROM 'open'
     OR (SELECT state FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second Yes linked someone in another relationship';
  END IF;
  DELETE FROM public.relationships WHERE id = v_rel;
  INSERT INTO public.account_holds (user_id, kind, reason_ref) VALUES (v_a, 'age_review', 'w9-hold');
  IF pg_temp.yes(v_b, '21', v_r, false) IS DISTINCT FROM '{"ok": false, "reason": "unavailable"}'::jsonb
     OR pg_temp.rels(v_a, v_b) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second Yes linked someone under a hold';
  END IF;
  DELETE FROM public.account_holds WHERE user_id = v_a;
  INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key) VALUES (v_a, v_b, public.dating_pair_key(v_a, v_b));
  IF pg_temp.yes(v_b, '21', v_r, false) IS DISTINCT FROM '{"ok": false, "reason": "closed"}'::jsonb
     OR pg_temp.link(v_b, '21', v_m) IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a blocked pair could link';
  END IF;
  -- G and H, two UK women; H in Accra on a same-gender trip: the chat is
  -- hidden on H's phone. G's ask is answered as at home; H can't see or
  -- answer it there, unless "Show it on this phone anyway".
  INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_traveller_detection', true)
  ON CONFLICT (key) DO UPDATE SET enabled = true;
  v_gh := pg_temp.match(v_g, v_h);
  PERFORM pg_temp.we_met(v_gh, v_g);
  PERFORM pg_temp.check(v_h, '24', 'GH');
  IF pg_temp.link(v_h, '24', v_gh) ->> 'read' IS DISTINCT FROM 'match_unavailable'
     OR pg_temp.page(v_h, '24', v_gh) ->> 'reason' IS DISTINCT FROM 'match_unavailable'
     OR pg_temp.ask(v_h, '24', v_gh, false) ->> 'reason' IS DISTINCT FROM 'match_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fixture''s trip does not hide the chat on her phone';
  END IF;
  v := pg_temp.ask(v_g, '23', v_gh, false);
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other''s trip changed the asker''s answer: %', v;
  END IF;
  v_r := (v ->> 'request_id')::uuid;
  IF pg_temp.yes(v_h, '24', v_r, false) ->> 'reason' IS DISTINCT FROM 'match_unavailable' OR pg_temp.rels(v_g, v_h) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chat hidden on her phone could be answered there';
  END IF;
  IF pg_temp.page(v_h, '24', v_gh, true) -> 'link' IS DISTINCT FROM jsonb_build_object('state', 'asked_you', 'request_id', v_r) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Show it on this phone anyway does not show her the request';
  END IF;
  v := pg_temp.yes(v_h, '24', v_r, false, true);
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Show it on this phone anyway does not let her answer';
  END IF;
  -- A man and a woman: the trip flag changes nothing.
  v_pq := pg_temp.match(v_p, v_q);
  PERFORM pg_temp.we_met(v_pq, v_q);
  IF (pg_temp.yes(v_q, '26', (pg_temp.ask(v_p, '25', v_pq, false) ->> 'request_id')::uuid, false) ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a man-woman pair could not link';
  END IF;
END $$;

-- =====================================================================
-- L8b. (Fix round 1, M-7) The invite exchange's own refusals from the
--      other side too: a hold on the confirmer, and a paused Attune
--      relationship on the confirmer's side or on the asker's, each
--      unavailable with nothing changed; once each is gone the same Yes
--      links (so each refusal was its own).
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('33');
  v_b constant uuid := pg_temp.ready('34', '{"identity": "man", "seeking": ["woman"]}');
  v_x constant uuid := pg_temp.ready('35');
  v_m uuid;
  v_r uuid;
  v_rel uuid;
  v jsonb;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.we_met(v_m, v_b);
  v_r := (pg_temp.ask(v_a, '33', v_m, false) ->> 'request_id')::uuid;
  IF v_r IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the L8b fixture could not ask';
  END IF;
  -- A hold on the confirmer.
  INSERT INTO public.account_holds (user_id, kind, reason_ref) VALUES (v_b, 'age_review', 'w9-hold-confirmer');
  v := pg_temp.yes(v_b, '34', v_r, false);
  IF v IS DISTINCT FROM '{"ok": false, "reason": "unavailable"}'::jsonb
     OR pg_temp.rels(v_a, v_b) <> 0
     OR (SELECT state FROM public.dating_couple_link_requests WHERE id = v_r) IS DISTINCT FROM 'open'
     OR (SELECT state FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second Yes linked a confirmer under a hold: %', v;
  END IF;
  DELETE FROM public.account_holds WHERE user_id = v_b;
  -- A paused Attune relationship on the confirmer's side.
  INSERT INTO public.relationships (user_a, user_b, status, invite_accepted_at, paused_at, paused_by)
  VALUES (v_b, v_x, 'paused', now() - interval '30 days', now(), v_b) RETURNING id INTO v_rel;
  v := pg_temp.yes(v_b, '34', v_r, false);
  IF v IS DISTINCT FROM '{"ok": false, "reason": "unavailable"}'::jsonb
     OR (SELECT count(*) FROM public.relationships AS r WHERE v_a IN (r.user_a, r.user_b)) <> 0
     OR (SELECT state FROM public.dating_couple_link_requests WHERE id = v_r) IS DISTINCT FROM 'open'
     OR (SELECT state FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second Yes linked someone in a paused relationship: %', v;
  END IF;
  DELETE FROM public.relationships WHERE id = v_rel;
  -- A paused Attune relationship on the asker's side (begun after asking).
  INSERT INTO public.relationships (user_a, user_b, status, invite_accepted_at, paused_at, paused_by)
  VALUES (v_a, v_x, 'paused', now() - interval '30 days', now(), v_a) RETURNING id INTO v_rel;
  v := pg_temp.yes(v_b, '34', v_r, false);
  IF v IS DISTINCT FROM '{"ok": false, "reason": "unavailable"}'::jsonb
     OR (SELECT count(*) FROM public.relationships AS r WHERE v_b IN (r.user_a, r.user_b)) <> 0
     OR (SELECT state FROM public.dating_couple_link_requests WHERE id = v_r) IS DISTINCT FROM 'open'
     OR (SELECT state FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second Yes linked an asker in a paused relationship: %', v;
  END IF;
  DELETE FROM public.relationships WHERE id = v_rel;
  -- Each refusal was its own: with nothing in the way the same Yes links.
  v := pg_temp.yes(v_b, '34', v_r, false);
  IF (v ->> 'ok')::boolean IS NOT TRUE OR pg_temp.rels(v_a, v_b) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the L8b pair could not link once nothing was in the way: %', v;
  END IF;
END $$;

-- =====================================================================
-- L8c. (Task 2: the carry from Task 1's review; W1 N-M3, no nesting) A
--      Dating pause that is busy has already tried three times on its
--      own: the second Yes answers busy at once (one pause call, never
--      three), and nothing is made. The stand-in pause lives in a block
--      that is undone; with the real pause back the same Yes links.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('38');
  v_b constant uuid := pg_temp.ready('39', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_r uuid;
  v jsonb;
  v_calls bigint;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.we_met(v_m, v_b);
  v_r := (pg_temp.ask(v_a, '38', v_m, false) ->> 'request_id')::uuid;
  IF v_r IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the L8c fixture could not ask';
  END IF;
  CREATE TEMP SEQUENCE w9_l8c_pause_calls;
  BEGIN
    CREATE OR REPLACE FUNCTION public.pause_dating_for_relationship_user(p_user_id uuid) RETURNS void
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $f$
    BEGIN
      PERFORM pg_catalog.nextval('pg_temp.w9_l8c_pause_calls');
      RAISE EXCEPTION 'dating:busy' USING ERRCODE = '55P03';
    END $f$;
    v := pg_temp.yes(v_b, '39', v_r, false);
    RAISE EXCEPTION USING ERRCODE = 'W9L8C';
  EXCEPTION WHEN SQLSTATE 'W9L8C' THEN
    NULL;
  END;
  v_calls := (SELECT CASE WHEN s.is_called THEN s.last_value ELSE 0 END FROM pg_temp.w9_l8c_pause_calls AS s);
  IF v IS DISTINCT FROM '{"ok": false, "reason": "busy"}'::jsonb OR v_calls IS DISTINCT FROM 1::bigint
     OR pg_temp.rels(v_a, v_b) <> 0
     OR (SELECT state FROM public.dating_couple_link_requests WHERE id = v_r) IS DISTINCT FROM 'open'
     OR (SELECT state FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a busy pause inside the second Yes was retried again (% call(s)) or left something: %',
      v_calls, v;
  END IF;
  IF (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'public.pause_dating_for_relationship_user(uuid)'::regprocedure)
       LIKE '%w9_l8c_pause_calls%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the L8c stand-in pause was not undone';
  END IF;
  v := pg_temp.yes(v_b, '39', v_r, false);
  IF (v ->> 'ok')::boolean IS NOT TRUE OR pg_temp.rels(v_a, v_b) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the L8c pair could not link once the pause was free: %', v;
  END IF;
END $$;

-- =====================================================================
-- L9. (Ruling R-W9-1, the controller's: one pairing path) A Dating link
--     and an invite make the same couple. Pair P (Dating: P asks, Q says
--     yes) and pair I (an invite: the pending row create-relationship-
--     invite inserts, then accept_relationship_invite_v2 as accept-invite
--     calls it). The same relationships row (every column's value, times
--     and ids only as set or not), the same acceptance row, the same rows
--     in every table that hangs off a relationship (timeline, About us,
--     everything; Dating's own link tables aside), the same invite
--     metrics, both paths Relationship. The link queues no push and no
--     in-app notice at all (Ruling R-W9-7; the invite's own push is
--     accept-invite's, never the database's); any push it did queue would
--     be neutral (carry 1; section A of dating_v2_device_contracts.sql
--     audits the walk).
-- =====================================================================
-- [p_rel]'s row as a shape: every column but its ids and members, a time
-- as set or not.
CREATE FUNCTION pg_temp.rel_shape(p_rel uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_object_agg(e.key, CASE WHEN jsonb_typeof(e.value) = 'null' THEN 'null'::jsonb
                                      WHEN e.key ~ '(_at|_on)$' THEN '"set"'::jsonb ELSE e.value END)
    FROM public.relationships AS r, jsonb_each(to_jsonb(r) - ARRAY['id', 'user_a', 'user_b']) AS e
   WHERE r.id = p_rel;
$$;
-- How many rows of each table that references relationships hang off
-- [p_rel] (Dating's own link tables aside).
CREATE FUNCTION pg_temp.effects(p_rel uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  c record;
  v_n bigint;
  v_out jsonb := '{}';
BEGIN
  FOR c IN
    SELECT k.conrelid::regclass::text AS t, a.attname AS col
      FROM pg_constraint AS k JOIN pg_attribute AS a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
     WHERE k.contype = 'f' AND k.confrelid = 'public.relationships'::regclass AND cardinality(k.conkey) = 1
  LOOP
    CONTINUE WHEN c.t IN ('dating_link_origins', 'couple_how_we_met', 'dating_couple_link_requests', 'dating_former_partner_exclusions');
    EXECUTE format('SELECT count(*) FROM %s WHERE %I = $1', c.t, c.col) INTO v_n USING p_rel;
    IF v_n > 0 THEN
      v_out := v_out || jsonb_build_object(c.t, v_n);
    END IF;
  END LOOP;
  RETURN v_out;
END $$;
CREATE FUNCTION pg_temp.queued(p_a uuid, p_b uuid) RETURNS bigint LANGUAGE sql AS $$
  SELECT (SELECT count(*) FROM public.scheduled_notifications AS s WHERE s.user_id IN (p_a, p_b))
       + (SELECT count(*) FROM public.in_app_notifications AS n WHERE n.user_id IN (p_a, p_b));
$$;
CREATE FUNCTION pg_temp.delta(a jsonb, b jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT coalesce(jsonb_object_agg(k, (b ->> k)::bigint - coalesce((a ->> k)::bigint, 0)), '{}'::jsonb)
    FROM jsonb_object_keys(b) AS k WHERE (b ->> k)::bigint IS DISTINCT FROM coalesce((a ->> k)::bigint, 0);
$$;
CREATE FUNCTION pg_temp.invite_metrics() RETURNS jsonb LANGUAGE sql AS $$
  SELECT coalesce(jsonb_object_agg(m.key, m.count), '{}'::jsonb) FROM public.metric_counters AS m
   WHERE m.day = (now() AT TIME ZONE 'utc')::date AND m.key LIKE 'invite_accepted%';
$$;
DO $$
DECLARE
  v_p constant uuid := pg_temp.ready('27');
  v_q constant uuid := pg_temp.ready('28', '{"identity": "man", "seeking": ["woman"]}');
  v_i constant uuid := pg_temp.id('29');
  v_k constant uuid := pg_temp.id('30');
  v_e constant uuid := pg_temp.id('36'); -- P's former partner (fix round 1, M-1)
  v_f constant uuid := pg_temp.id('37'); -- I's former partner
  v_old_p uuid;
  v_old_i uuid;
  v_m uuid;
  v_link uuid;
  v_inv uuid;
  v_before jsonb;
  v_link_metrics jsonb;
  v_inv_metrics jsonb;
  v_queued bigint;
BEGIN
  -- I and K: two adults with no Dating, I on the Relationship path (the
  -- inviter has chosen it before inviting).
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_i, '155598229', now(), now() - interval '40 days'), (v_k, '155598230', now(), now() - interval '40 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_i, '+155598229', 'Invite 29', 'relationship', now() - interval '40 days', now(), '2'),
         (v_k, '+155598230', 'Invite 30', NULL, now() - interval '40 days', now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_i, current_date - interval '30 years'), (v_k, current_date - interval '30 years');
  -- Fix round 1 (M-1): the asker P and the inviter I each have an ended
  -- chapter (the new chapter archives it) and About us drafts (the
  -- acceptance adopts them), so the side effects compared below are real.
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_e, '155598236', now(), now() - interval '400 days'), (v_f, '155598237', now(), now() - interval '400 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_e, '+155598236', 'Former 36', NULL, now() - interval '400 days', now(), '2'),
         (v_f, '+155598237', 'Former 37', NULL, now() - interval '400 days', now(), '2');
  INSERT INTO public.relationships (user_a, user_b, status, invite_accepted_at, ended_at, ended_by)
  VALUES (v_p, v_e, 'ended', now() - interval '300 days', now() - interval '100 days', v_e) RETURNING id INTO v_old_p;
  INSERT INTO public.relationships (user_a, user_b, status, invite_accepted_at, ended_at, ended_by)
  VALUES (v_i, v_f, 'ended', now() - interval '300 days', now() - interval '100 days', v_f) RETURNING id INTO v_old_i;
  INSERT INTO public.couple_profile_drafts (user_id, stage, stage_set_at, living, living_set_at)
  VALUES (v_p, 'dating', now(), 'apart_nearby', now()), (v_i, 'dating', now(), 'apart_nearby', now());
  -- The Dating link.
  v_m := pg_temp.match(v_p, v_q);
  PERFORM pg_temp.we_met(v_m, v_p);
  v_queued := pg_temp.queued(v_p, v_q);
  v_before := pg_temp.invite_metrics();
  v_link := (pg_temp.yes(v_q, '28', (pg_temp.ask(v_p, '27', v_m, false) ->> 'request_id')::uuid, false) ->> 'relationship_id')::uuid;
  v_link_metrics := pg_temp.invite_metrics();
  IF v_link IS NULL OR pg_temp.queued(v_p, v_q) <> v_queued THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the link failed or queued a push or notice: % queued', pg_temp.queued(v_p, v_q) - v_queued;
  END IF;
  -- The invite, as the two edge functions write it.
  INSERT INTO public.relationships (user_a, status, invite_code, invite_expires_at)
  VALUES (v_i, 'pending', 'W9EQ29', now() + interval '7 days') RETURNING id INTO v_inv;
  IF (public.accept_relationship_invite_v2(v_k, 'W9EQ29') ->> 'relationship_id')::uuid IS DISTINCT FROM v_inv THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the invite fixture did not accept';
  END IF;
  v_inv_metrics := pg_temp.invite_metrics();
  IF pg_temp.rel_shape(v_link) IS DISTINCT FROM pg_temp.rel_shape(v_inv) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the link''s relationships row differs from an invite''s: % / %',
      pg_temp.rel_shape(v_link), pg_temp.rel_shape(v_inv);
  END IF;
  IF (SELECT count(*) FROM public.relationship_invite_acceptances WHERE relationship_id = v_link AND accepted_by = v_q
         AND invite_code_hash ~ '^[0-9a-f]{64}$') <> 1
     OR (SELECT count(*) FROM public.relationship_invite_acceptances WHERE relationship_id = v_inv AND accepted_by = v_k
            AND invite_code_hash = encode(extensions.digest('W9EQ29', 'sha256'), 'hex')) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the acceptance rows differ';
  END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(pg_temp.effects(v_link))) < 2
     OR NOT pg_temp.effects(v_link) ? 'couple_profiles' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L9''s side effects are trivial (fixture): %', pg_temp.effects(v_link);
  END IF;
  IF (SELECT status || '/' || chat_archived_reason FROM public.relationships WHERE id = v_old_p)
       IS DISTINCT FROM 'archived/partner_new_relationship'
     OR pg_temp.rel_shape(v_old_p) - 'ended_by' IS DISTINCT FROM pg_temp.rel_shape(v_old_i) - 'ended_by' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the link and the invite left the earlier chapters differently: % / %',
      pg_temp.rel_shape(v_old_p), pg_temp.rel_shape(v_old_i);
  END IF;
  IF (SELECT to_jsonb(c) - ARRAY['relationship_id', 'stage_changed_by', 'living_changed_by']
                          - ARRAY['stage_changed_at', 'living_changed_at', 'updated_at', 'created_at']
        FROM public.couple_profiles AS c WHERE c.relationship_id = v_link)
     IS DISTINCT FROM
     (SELECT to_jsonb(c) - ARRAY['relationship_id', 'stage_changed_by', 'living_changed_by']
                          - ARRAY['stage_changed_at', 'living_changed_at', 'updated_at', 'created_at']
        FROM public.couple_profiles AS c WHERE c.relationship_id = v_inv)
     OR (SELECT stage_changed_by FROM public.couple_profiles WHERE relationship_id = v_link) IS DISTINCT FROM v_p
     OR (SELECT stage_changed_by FROM public.couple_profiles WHERE relationship_id = v_inv) IS DISTINCT FROM v_i THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the link''s About us differs from an invite''s';
  END IF;
  IF pg_temp.effects(v_link) IS DISTINCT FROM pg_temp.effects(v_inv) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the link''s side effects differ from an invite''s: % / %',
      pg_temp.effects(v_link), pg_temp.effects(v_inv);
  END IF;
  IF pg_temp.delta(v_before, v_link_metrics) IS DISTINCT FROM pg_temp.delta(v_link_metrics, v_inv_metrics) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the invite metrics differ: % / %', pg_temp.delta(v_before, v_link_metrics),
      pg_temp.delta(v_link_metrics, v_inv_metrics);
  END IF;
  IF (SELECT string_agg(u.path, ',' ORDER BY u.id) FROM public.users AS u WHERE u.id IN (v_p, v_q, v_i, v_k))
       IS DISTINCT FROM 'relationship,relationship,relationship,relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the paths differ';
  END IF;
END $$;

-- =====================================================================
-- Setup for E (Task 2): a couple linked through Dating, the reads of
-- what follows, and the export's call as the worker makes it.
-- =====================================================================
-- [p] and [q] matched, both said We met; [p] asks, [q] says yes, both
-- keep the first messages; the relationship's id.
CREATE FUNCTION pg_temp.couple(p uuid, p_n text, q uuid, q_n text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_m uuid := pg_temp.match(p, q);
  v_rel uuid;
BEGIN
  PERFORM pg_temp.say(v_m, p, 1, 300);
  PERFORM pg_temp.say(v_m, q, 2, 200);
  PERFORM pg_temp.we_met(v_m, p);
  v_rel := (pg_temp.yes(q, q_n, (pg_temp.ask(p, p_n, v_m, true) ->> 'request_id')::uuid, true) ->> 'relationship_id')::uuid;
  IF v_rel IS NULL THEN
    RAISE EXCEPTION 'E setup: the couple did not link';
  END IF;
  RETURN v_rel;
END $$;
CREATE FUNCTION pg_temp.origin(p uuid, p_rel uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, NULL, format('SELECT public.get_dating_link_origin(%L)', p_rel));
$$;
CREATE FUNCTION pg_temp.how(p uuid, p_rel uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, NULL, format('SELECT public.get_how_we_met(%L)', p_rel));
$$;
CREATE FUNCTION pg_temp.offer(p uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, NULL, 'SELECT public.get_dating_post_link_offer()');
$$;
CREATE FUNCTION pg_temp.dismiss(p uuid, p_what text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.j(p, NULL, format('SELECT public.dismiss_dating_post_link_offer(%L)', p_what));
$$;
-- The worker's call (build-data-exports, the service role's), or its error.
CREATE FUNCTION pg_temp.export(p_job uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.dating_export_for_job(p_job);
  RESET ROLE;
  RETURN coalesce(v, 'null'::jsonb);
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  RETURN jsonb_build_object('raised', SQLERRM);
END $$;
CREATE FUNCTION pg_temp.job(p uuid, p_status text) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.data_export_jobs (user_id, status, claimed_at) VALUES (p, p_status, now()) RETURNING id;
$$;
-- The opaque answers (S-6): one text each, whatever the reason.
CREATE FUNCTION pg_temp.no_origin() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"ok": false, "reason": "link_origin_unavailable"}'::jsonb;
$$;
CREATE FUNCTION pg_temp.no_card() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"ok": false, "reason": "how_we_met_unavailable"}'::jsonb;
$$;

-- =====================================================================
-- E1. What follows the link is the app's; the export's Dating part is the
--     service role's alone, with no user id (S-4): no
--     dating_export_for_user exists; the read log is nobody's.
-- =====================================================================
DO $$
DECLARE
  v_t text;
  v_w text; -- Fix round 1 (C-1)
BEGIN
  -- Fix round 1 (C-1): the binding holds only while no API role can make
  -- or rewrite an export job; the service role keeps its read. Task 4
  -- (N-1): INSERT and UPDATE are read column by column too (a grant on
  -- user_id alone would re-point a building job).
  IF has_any_column_privilege('service_role', 'public.data_export_jobs', 'INSERT')
     OR has_any_column_privilege('service_role', 'public.data_export_jobs', 'UPDATE')
     OR has_table_privilege('service_role', 'public.data_export_jobs', 'DELETE')
     OR has_any_column_privilege('authenticated', 'public.data_export_jobs', 'INSERT')
     OR has_any_column_privilege('authenticated', 'public.data_export_jobs', 'UPDATE')
     OR NOT has_table_privilege('service_role', 'public.data_export_jobs', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role can make or rewrite an export job (S-4)';
  END IF;
  FOREACH v_w IN ARRAY ARRAY['INSERT INTO public.data_export_jobs (user_id, status, claimed_at) VALUES (gen_random_uuid(), ''building'', now())',
                             'UPDATE public.data_export_jobs SET status = ''building'' WHERE false'] LOOP
    BEGIN
      EXECUTE 'SET LOCAL ROLE service_role';
      EXECUTE v_w;
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: the service role can make or rewrite an export job (S-4): %', v_w;
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    WHEN OTHERS THEN
      RESET ROLE;
      IF SQLERRM LIKE 'CONTRACT VIOLATED%' THEN
        RAISE;
      END IF;
      RAISE EXCEPTION 'CONTRACT VIOLATED: the service role can make or rewrite an export job (S-4): % (%)', v_w, SQLERRM;
    END;
  END LOOP;
  FOREACH v_t IN ARRAY ARRAY['public.get_dating_link_origin(uuid)', 'public.get_how_we_met(uuid)',
                             'public.get_dating_post_link_offer()', 'public.dismiss_dating_post_link_offer(text)'] LOOP
    IF NOT has_function_privilege('authenticated', v_t, 'EXECUTE') OR has_function_privilege('anon', v_t, 'EXECUTE')
       OR has_function_privilege('service_role', v_t, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is not the app''s alone', v_t;
    END IF;
  END LOOP;
  IF has_function_privilege('authenticated', 'public.dating_export_for_job(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.dating_export_for_job(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.dating_export_for_job(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_export_for_job is not the service role''s alone';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'dating_export_for_user') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dating_export_for_user exists (S-4)';
  END IF;
  IF has_table_privilege('service_role', 'public.dating_export_reads', 'SELECT')
     OR has_table_privilege('authenticated', 'public.dating_export_reads', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the export read log is readable by an API role';
  END IF;
END $$;

-- =====================================================================
-- E2. The link origin (S-6, mutant 28): the match date, to the two
--     members only, while the relationship is open; a stranger, a
--     relationship that never came from Dating, an ended one, no id, the
--     flag off: the same answer.
-- =====================================================================
DO $$
DECLARE
  v_x constant uuid := pg_temp.ready('50');
  v_y constant uuid := pg_temp.ready('51', '{"identity": "man", "seeking": ["woman"]}');
  v_z constant uuid := pg_temp.ready('52');
  v_w constant uuid := pg_temp.ready('53');
  v_v constant uuid := pg_temp.ready('54', '{"identity": "man", "seeking": ["woman"]}');
  v_rel uuid;
  v_plain uuid;
  v_at timestamptz;
BEGIN
  v_rel := pg_temp.couple(v_x, '50', v_y, '51');
  SELECT m.matched_at INTO v_at FROM public.dating_matches AS m JOIN public.dating_couple_link_requests AS r ON r.match_id = m.id
   WHERE r.relationship_id = v_rel;
  IF pg_temp.origin(v_x, v_rel) IS DISTINCT FROM jsonb_build_object('ok', true, 'matched_at', v_at)
     OR pg_temp.origin(v_y, v_rel) IS DISTINCT FROM jsonb_build_object('ok', true, 'matched_at', v_at) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the members don''t read the match date: %', pg_temp.origin(v_x, v_rel);
  END IF;
  INSERT INTO public.relationships (user_a, user_b, status, invite_accepted_at) VALUES (v_w, v_v, 'active', now())
  RETURNING id INTO v_plain;
  IF pg_temp.origin(v_z, v_rel) IS DISTINCT FROM pg_temp.no_origin()
     OR pg_temp.origin(v_w, v_plain) IS DISTINCT FROM pg_temp.no_origin()
     OR pg_temp.origin(v_x, NULL) IS DISTINCT FROM pg_temp.no_origin()
     OR pg_temp.origin(v_x, v_plain) IS DISTINCT FROM pg_temp.no_origin() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the origin answers a stranger or a relationship with no Dating origin differently';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_couple_link';
  IF pg_temp.origin(v_x, v_rel) IS DISTINCT FROM pg_temp.no_origin() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the origin answers with the flag off';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_couple_link';
  UPDATE public.relationships SET status = 'ended', ended_at = now() WHERE id = v_rel;
  IF pg_temp.origin(v_x, v_rel) IS DISTINCT FROM pg_temp.no_origin() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the origin answers for an ended relationship';
  END IF;
END $$;

-- =====================================================================
-- E3. How we met: to the two members only, each message as both saw it,
--     "mine" for the reader's own; a stranger or a couple with no card:
--     the same answer. export_relationship carries the card ('me' or
--     'partner', never an id; I-13), and none for a couple without one.
-- =====================================================================
DO $$
DECLARE
  v_x constant uuid := pg_temp.ready('55');
  v_y constant uuid := pg_temp.ready('56', '{"identity": "man", "seeking": ["woman"]}');
  v_z constant uuid := pg_temp.ready('57');
  v_rel uuid;
  v jsonb;
  e jsonb;
BEGIN
  v_rel := pg_temp.couple(v_x, '55', v_y, '56');
  v := pg_temp.how(v_x, v_rel);
  IF v -> 'items' IS DISTINCT FROM (
       SELECT jsonb_agg(jsonb_build_object('mine', x ->> 'by' = v_x::text, 'kind', 'text', 'question_id', NULL,
                                           'text', x ->> 'text', 'at', x -> 'at') ORDER BY n)
         FROM public.couple_how_we_met AS h, jsonb_array_elements(h.items) WITH ORDINALITY AS t(x, n)
        WHERE h.relationship_id = v_rel)
     OR jsonb_array_length(v -> 'items') <> 2 OR (v -> 'items' -> 0 ->> 'mine')::boolean IS NOT TRUE
     OR (pg_temp.how(v_y, v_rel) -> 'items' -> 0 ->> 'mine')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: How we met reads wrong: % / %', v, pg_temp.how(v_y, v_rel);
  END IF;
  IF pg_temp.how(v_z, v_rel) IS DISTINCT FROM pg_temp.no_card() OR pg_temp.how(v_x, NULL) IS DISTINCT FROM pg_temp.no_card() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: How we met answers a stranger';
  END IF;
  -- Fix round 1 (M-1): the flag off, then an ended relationship (undone).
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_couple_link';
  e := pg_temp.how(v_x, v_rel);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_couple_link';
  IF e IS DISTINCT FROM pg_temp.no_card() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: How we met answers with the flag off: %', e;
  END IF;
  BEGIN
    UPDATE public.relationships SET status = 'ended', ended_at = now() WHERE id = v_rel;
    e := pg_temp.how(v_x, v_rel);
    RAISE EXCEPTION USING ERRCODE = 'W9E3E';
  EXCEPTION WHEN SQLSTATE 'W9E3E' THEN
    NULL;
  END;
  IF e IS DISTINCT FROM pg_temp.no_card() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: How we met answers for an ended relationship: %', e;
  END IF;
  IF (SELECT status FROM public.relationships WHERE id = v_rel) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the E3 fixture''s ending was not undone';
  END IF;
  e := public.export_relationship(v_x, v_rel);
  IF e -> 'how_we_met' IS DISTINCT FROM jsonb_build_array(
         -- Final server fix (M-2): each item carries its question (none for a message).
         jsonb_build_object('from', 'me', 'kind', 'text', 'question', NULL, 'text', 'masked 1', 'at', v -> 'items' -> 0 -> 'at'),
         jsonb_build_object('from', 'partner', 'kind', 'text', 'question', NULL, 'text', 'masked 2', 'at', v -> 'items' -> 1 -> 'at'))
     OR (e -> 'how_we_met')::text ~ '[0-9a-f]{8}-[0-9a-f]{4}-' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: export_relationship lacks the How we met card: %', e -> 'how_we_met';
  END IF;
  DELETE FROM public.couple_how_we_met WHERE relationship_id = v_rel;
  IF pg_temp.how(v_x, v_rel) IS DISTINCT FROM pg_temp.no_card()
     OR NOT (public.export_relationship(v_x, v_rel) ? 'how_we_met')
     OR public.export_relationship(v_x, v_rel) -> 'how_we_met' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a couple without a card reads one';
  END IF;
END $$;

-- =====================================================================
-- E4. The Relationship home's card (C-4, Ruling R-W9-3): the asker reads
--     'linked' until they have seen "You decided together." (the
--     confirmer saw it at the second Yes); from 30 days after linking both
--     read 'delete' while they have Dating data, until either answer;
--     "Keep for now" never asks again; leaving Dating ends it. Answers
--     are fixed codes; a replay is ok.
-- =====================================================================
DO $$
DECLARE
  v_x constant uuid := pg_temp.ready('58');
  v_y constant uuid := pg_temp.ready('59', '{"identity": "man", "seeking": ["woman"]}');
  v_z constant uuid := pg_temp.ready('60');
  v_rel uuid;
  v_off jsonb; -- Fix round 1 (M-1)
BEGIN
  v_rel := pg_temp.couple(v_x, '58', v_y, '59');
  IF pg_temp.offer(v_x) IS DISTINCT FROM '{"ok": true, "offer": "linked"}'::jsonb
     OR pg_temp.offer(v_y) IS DISTINCT FROM '{"ok": true, "offer": null}'::jsonb
     OR pg_temp.offer(v_z) IS DISTINCT FROM '{"ok": true, "offer": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the card after linking: % / %', pg_temp.offer(v_x), pg_temp.offer(v_y);
  END IF;
  -- Fix round 1 (M-1): with the flag off there is no card.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_couple_link';
  v_off := pg_temp.offer(v_x);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_couple_link';
  IF v_off IS DISTINCT FROM '{"ok": true, "offer": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the post-link card shows with the flag off: %', v_off;
  END IF;
  IF pg_temp.dismiss(v_x, 'linked') IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.dismiss(v_x, 'linked') IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.offer(v_x) IS DISTINCT FROM '{"ok": true, "offer": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "You decided together." shows again';
  END IF;
  IF pg_temp.dismiss(v_x, 'other') IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb
     OR pg_temp.dismiss(v_z, 'delete') IS DISTINCT FROM '{"ok": false, "reason": "offer_unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bad dismissal is not a fixed refusal';
  END IF;
  UPDATE public.dating_link_origins SET linked_at = now() - interval '29 days' WHERE relationship_id = v_rel;
  IF pg_temp.offer(v_x) IS DISTINCT FROM '{"ok": true, "offer": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 30-day offer came early';
  END IF;
  UPDATE public.dating_link_origins SET linked_at = now() - interval '31 days' WHERE relationship_id = v_rel;
  IF pg_temp.offer(v_x) IS DISTINCT FROM '{"ok": true, "offer": "delete"}'::jsonb
     OR pg_temp.offer(v_y) IS DISTINCT FROM '{"ok": true, "offer": "delete"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 30-day offer did not come: % / %', pg_temp.offer(v_x), pg_temp.offer(v_y);
  END IF;
  IF pg_temp.dismiss(v_y, 'delete') IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.offer(v_y) IS DISTINCT FROM '{"ok": true, "offer": null}'::jsonb
     OR pg_temp.offer(v_x) IS DISTINCT FROM '{"ok": true, "offer": "delete"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Keep for now is not this person''s alone, for good';
  END IF;
  PERFORM private.dating_exit_internal(v_x, false);
  IF pg_temp.offer(v_x) IS DISTINCT FROM '{"ok": true, "offer": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the offer stays after leaving Dating: %', pg_temp.offer(v_x);
  END IF;
END $$;

-- =====================================================================
-- E5. The export binding (S-4, mutants 22, 23): for A's building job,
--     A's own Dating data (decrypted) and A's own sent messages, none of
--     B's though they matched, no name or age of B's, no id; a queued,
--     ready, failed or unknown job: export:not_building; a fourth call
--     for one job: export:read_limit; every call logged, nothing else;
--     no Dating data: nothing (null).
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('61');
  v_b constant uuid := pg_temp.ready('62', '{"identity": "man", "seeking": ["woman"]}');
  v_n constant uuid := pg_temp.id('63');
  v_m uuid;
  v_job uuid;
  v jsonb;
  v_s text;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.say(v_m, v_a, 1, 300);
  PERFORM pg_temp.say(v_m, v_b, 2, 200);
  PERFORM pg_temp.say(v_m, v_a, 3, 100);
  v_job := pg_temp.job(v_a, 'building');
  v := pg_temp.export(v_job);
  IF v ->> 'format' IS DISTINCT FROM 'attune-dating-export'
     OR v -> 'about_you' -> 'identity' ->> 'identity' IS DISTINCT FROM 'woman'
     OR v -> 'about_you' -> 'seeking' IS DISTINCT FROM '["man"]'::jsonb
     OR v -> 'profile' ->> 'display_name' IS DISTINCT FROM 'Link 61'
     OR jsonb_array_length(v -> 'conversations') <> 1
     OR (SELECT string_agg(x ->> 'text', ',' ORDER BY n) FROM jsonb_array_elements(v -> 'conversations' -> 0 -> 'my_messages')
                                                          WITH ORDINALITY AS t(x, n)) IS DISTINCT FROM 'plain 1,plain 3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the export is not A''s own data: %', v;
  END IF;
  v_s := v::text;
  IF v_s LIKE '%plain 2%' OR v_s LIKE '%masked%' OR v_s LIKE '%Link 62%'
     OR v_s ~ '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the export holds B''s words or name, or an id';
  END IF;
  PERFORM pg_temp.export(v_job);
  PERFORM pg_temp.export(v_job);
  IF pg_temp.export(v_job) IS DISTINCT FROM '{"raised": "export:read_limit"}'::jsonb
     OR (SELECT count(*) FROM public.dating_export_reads WHERE job_id = v_job) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fourth read of one job was allowed, or the reads were not logged';
  END IF;
  IF pg_temp.export(pg_temp.job(v_a, 'queued')) IS DISTINCT FROM '{"raised": "export:not_building"}'::jsonb
     OR pg_temp.export(pg_temp.job(v_a, 'ready')) IS DISTINCT FROM '{"raised": "export:not_building"}'::jsonb
     OR pg_temp.export(pg_temp.job(v_a, 'failed')) IS DISTINCT FROM '{"raised": "export:not_building"}'::jsonb
     OR pg_temp.export(gen_random_uuid()) IS DISTINCT FROM '{"raised": "export:not_building"}'::jsonb
     OR pg_temp.export(NULL) IS DISTINCT FROM '{"raised": "export:not_building"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a job that isn''t building was read';
  END IF;
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (v_n, '155598263', now());
  INSERT INTO public.users (id, phone, display_name) VALUES (v_n, '+155598263', 'No dating');
  -- Fix round 1 (Task 4 review I-1): someone with no Dating data never
  -- spends a read, however often the worker re-runs the data part.
  v_job := pg_temp.job(v_n, 'building');
  FOR i IN 1..5 LOOP
    v := pg_temp.export(v_job);
    IF v IS DISTINCT FROM 'null'::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: someone with no Dating data got a dating part, or was refused (call %): %', i, v;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.dating_export_reads WHERE job_id = v_job) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a call for someone with no Dating data spent a read';
  END IF;
END $$;

-- =====================================================================
-- E6. (Ruling R-W9-16) The app learns the flag from the Dating read it
--     already makes (get_dating_home): every answer, to anyone (in Dating
--     or not, any phone), carries couple_link: true while the flag is on
--     and nothing while it is off, so a phone with the flag off asks
--     nothing more.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('64');
  v_n constant uuid := pg_temp.id('65');
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (v_n, '155598265', now());
  INSERT INTO public.users (id, phone, display_name, path) VALUES (v_n, '+155598265', 'No dating', 'relationship');
  IF pg_temp.j(v_a, '64', 'SELECT public.get_dating_home()') ->> 'couple_link' IS DISTINCT FROM 'true'
     OR pg_temp.j(v_a, NULL, 'SELECT public.get_dating_home()') ->> 'couple_link' IS DISTINCT FROM 'true'
     OR pg_temp.j(v_n, NULL, 'SELECT public.get_dating_home()') ->> 'couple_link' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag on the Dating read does not say so: %',
      pg_temp.j(v_n, NULL, 'SELECT public.get_dating_home()');
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_couple_link';
  IF pg_temp.j(v_a, '64', 'SELECT public.get_dating_home()') ? 'couple_link'
     OR pg_temp.j(v_n, NULL, 'SELECT public.get_dating_home()') ? 'couple_link' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off the Dating read names the couple link';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_couple_link';
END $$;

-- =====================================================================
-- F1. (Final server fix, I-1) Deleting your account takes the How we met
--     card of every relationship you were in: your copied words and your
--     user id never stay with the ex-partner (on their card or in their
--     export). Another couple's card stays. Fixture ids 90-99.
-- =====================================================================
DO $$
DECLARE
  v_x constant uuid := pg_temp.ready('90');
  v_y constant uuid := pg_temp.ready('91', '{"identity": "man", "seeking": ["woman"]}');
  v_z constant uuid := pg_temp.ready('92');
  v_w constant uuid := pg_temp.ready('93', '{"identity": "man", "seeking": ["woman"]}');
  v_rel uuid;
  v_other uuid;
BEGIN
  v_rel := pg_temp.couple(v_x, '90', v_y, '91');
  v_other := pg_temp.couple(v_z, '92', v_w, '93');
  IF NOT EXISTS (SELECT 1 FROM public.couple_how_we_met AS h, jsonb_array_elements(h.items) AS x(v)
                  WHERE h.relationship_id = v_rel AND x.v ->> 'by' = v_x::text)
     OR jsonb_array_length(public.export_relationship(v_y, v_rel) -> 'how_we_met') <> 2 THEN
    RAISE EXCEPTION 'F1 setup: the couple has no How we met card with X''s words';
  END IF;
  PERFORM public.prepare_account_deletion(v_x);
  IF (SELECT status FROM public.relationships WHERE id = v_rel) IS DISTINCT FROM 'ended' THEN
    RAISE EXCEPTION 'F1 setup: the deletion did not end the relationship';
  END IF;
  IF EXISTS (SELECT 1 FROM public.couple_how_we_met WHERE relationship_id = v_rel)
     OR EXISTS (SELECT 1 FROM public.couple_how_we_met AS h, jsonb_array_elements(h.items) AS x(v)
                 WHERE x.v ->> 'by' = v_x::text)
     OR public.export_relationship(v_y, v_rel) -> 'how_we_met' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted account''s words stay in the ex-partner''s How we met card or export: %',
      public.export_relationship(v_y, v_rel) -> 'how_we_met';
  END IF;
  IF (SELECT jsonb_array_length(items) FROM public.couple_how_we_met WHERE relationship_id = v_other) IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one person''s deletion took another couple''s How we met card';
  END IF;
END $$;

-- =====================================================================
-- F2. (Final server fix, M-1) "You decided together." only while the
--     relationship is open: once it has ended, the asker who never saw
--     the moment reads the sealed chat (and the link page) as linked with
--     no moment, so the chat says plainly that it has ended.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('94');
  v_b constant uuid := pg_temp.ready('95', '{"identity": "man", "seeking": ["woman"]}');
  v_rel uuid;
  v_m uuid;
BEGIN
  v_rel := pg_temp.couple(v_a, '94', v_b, '95');
  SELECT r.match_id INTO v_m FROM public.dating_couple_link_requests AS r WHERE r.relationship_id = v_rel;
  IF pg_temp.link(v_a, '94', v_m) IS DISTINCT FROM '{"state": "linked", "moment": true}'::jsonb
     OR pg_temp.page(v_a, '94', v_m) -> 'link' IS DISTINCT FROM '{"state": "linked", "moment": true}'::jsonb THEN
    RAISE EXCEPTION 'F2 setup: the asker''s moment is not still to come: %', pg_temp.link(v_a, '94', v_m);
  END IF;
  PERFORM public.relationship_end_internal(v_rel, v_b);
  IF (SELECT status FROM public.relationships WHERE id = v_rel) IS DISTINCT FROM 'ended' THEN
    RAISE EXCEPTION 'F2 setup: the relationship did not end';
  END IF;
  IF pg_temp.link(v_a, '94', v_m) IS DISTINCT FROM '{"state": "linked", "moment": false}'::jsonb
     OR pg_temp.page(v_a, '94', v_m) -> 'link' IS DISTINCT FROM '{"state": "linked", "moment": false}'::jsonb
     OR pg_temp.link(v_b, '95', v_m) IS DISTINCT FROM '{"state": "linked", "moment": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "You decided together." shows after the relationship ended: % / %',
      pg_temp.link(v_a, '94', v_m), pg_temp.page(v_a, '94', v_m);
  END IF;
END $$;

-- =====================================================================
-- F3. (Final server fix, M-2) The export's How we met keeps each guided
--     answer's question, as the app shows it above the answer.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.ready('96');
  v_b constant uuid := pg_temp.ready('97', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_rel uuid;
  e jsonb;
BEGIN
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.say(v_m, v_a, 1, 300);
  PERFORM pg_temp.say(v_m, v_a, 2, 200, 'guided_answer', 'good_saturday');
  PERFORM pg_temp.say(v_m, v_b, 3, 100, 'guided_answer', 'good_saturday');
  PERFORM pg_temp.we_met(v_m, v_a);
  v_rel := (pg_temp.yes(v_b, '97', (pg_temp.ask(v_a, '96', v_m, true) ->> 'request_id')::uuid, true) ->> 'relationship_id')::uuid;
  e := public.export_relationship(v_b, v_rel) -> 'how_we_met';
  IF jsonb_array_length(e) IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'F3 setup: How we met does not hold both guided answers: %', e;
  END IF;
  -- The two answers share their time (shown once both answered), so
  -- their order between themselves is the ids'; compared as a set.
  IF (SELECT string_agg(s, ',' ORDER BY s)
        FROM (SELECT (x.v ->> 'from') || '/' || (x.v ->> 'kind') || '/' || coalesce(x.v ->> 'question', '-') AS s
                FROM jsonb_array_elements(e) AS x(v)) AS y)
       IS DISTINCT FROM 'me/guided_answer/good_saturday,partner/guided_answer/good_saturday,partner/text/-'
     OR e -> 0 ->> 'kind' IS DISTINCT FROM 'text' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the export''s How we met drops a guided answer''s question: %', e;
  END IF;
END $$;

-- =====================================================================
-- F4. (Final server fix, M-5) Every relationship delete checks the link
--     requests' cascade through an index, not a scan.
-- =====================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_index AS i JOIN pg_attribute AS a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
                  WHERE i.indrelid = 'public.dating_couple_link_requests'::regclass AND a.attname = 'relationship_id') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_couple_link_requests.relationship_id has no index';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'dating_v2_link_contracts: all held'; END $$;
ROLLBACK;
