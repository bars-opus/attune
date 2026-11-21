-- supabase/tests/dating_v2_chat_contracts.sql
-- Spec 2 W6a (§3.6, §4.3, §4.4, §4.5, §5.2 14, §6.1, §7.1, §7.3 masking
-- parity, §7.5 mutants 10-12; carries 1, 3, 5, 7): the masker gives every
-- fixture case's expected output and drops exactly the caption_drop
-- captions, failing closed (A); the card shows captions masked, never
-- dropped for a contact detail (B); the pair marker: written for "Not for
-- me" and a block, read by the single-pair predicate and by generation,
-- kept after leaving and after deleting an account, holding no id (C);
-- the kill switch keeps a man-woman pair whose other member lives
-- elsewhere (D); act names the match it made (E). Task 2 adds the chat
-- (F onward). Fixture ids are 6c6000..-nn and phones +1555960nn, unique
-- in the suite; each section takes its own range of nn (A-E 01-29).
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_chat_contracts.sql
BEGIN;

\set cases `cat supabase/tests/fixtures/dating_mask_cases.json`
SELECT length(set_config('w6.cases', :'cases', true)) AS cases_loaded \gset

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w6-chat-key', true);
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w6-field-key-0123456789abcdef-0123', true);
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w6-push-key', true);
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
  SELECT ('6c600000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;
CREATE FUNCTION pg_temp.dev(p_n text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT md5('w6-device-' || p_n);
$$;
-- A current candidate (the matching contract's fixture person) with every
-- answer in [o] over the defaults; "phone" names another fixture's number
-- (the same person on a new account).
CREATE FUNCTION pg_temp.ready(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.id(p_n);
  d constant jsonb := '{"identity": "woman", "seeking": ["man"], "country": "GH", "region": "AA", "years": 30,
    "days": 40, "phone": null, "name": null}'::jsonb || o;
  v_phone constant text := '+1555960' || coalesce(d ->> 'phone', p_n);
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_u, ltrim(v_phone, '+'), now(), now() - make_interval(days => (d ->> 'days')::int));
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_u, v_phone, 'Chat ' || p_n, 'dating', now() - make_interval(days => (d ->> 'days')::int), now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_u, (current_date - make_interval(years => (d ->> 'years')::int) - interval '10 days')::date);
  INSERT INTO public.dating_enrollments (user_id, state, opted_in_at, activated_at) VALUES (v_u, 'active', now(), now());
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, moderation_state, verification_state,
    country_code, region_code, intention, timeline_visible, not_married_attested_at, attestation_version,
    children_have, children_want, faith_visible)
  VALUES (v_u, coalesce(d ->> 'name', 'Chat ' || p_n), 'active', 'approved', 'verified', d ->> 'country', d ->> 'region',
    'committed', true, now(), '2026-10-v1', false, 'yes', false);
  INSERT INTO public.dating_preferences (user_id, min_age, max_age, region_scope, open_abroad, want_must_match, exclude_parents)
  VALUES (v_u, 25, 40, 'region', '{}', false, false);
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  VALUES (v_u, private.dating_field_encrypt(jsonb_build_object('identity', d ->> 'identity', 'pools', jsonb_build_array(d ->> 'identity'))),
          private.dating_field_encrypt(jsonb_build_object('seeking', d -> 'seeking')));
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer, moderation_state)
  SELECT v_u, n, CASE n WHEN 1 THEN 'perfect_sunday' ELSE 'ask_me_about' END, 'A chat fixture answer ' || n, 'approved'
    FROM generate_series(1, 2) AS n;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
  SELECT v_u, 'w6/' || v_u || '/' || n || '.jpg', n, 'approved', 'clear' FROM generate_series(1, 2) AS n;
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, age_vendor, age_decided_at,
    identity_method, identity_result, identity_vendor, identity_decided_at)
  VALUES (v_u, 'id', 'pass', 'contract', now(), 'liveness_compare', 'pass', 'contract', now());
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'w6-consent-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']) AS p;
  INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
  VALUES (v_u, encode(extensions.digest(pg_temp.dev(p_n), 'sha256'), 'hex'), now(), now());
  RETURN v_u;
END $$;
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
-- [p_sql] as the service role: 'ok', or the error's SQLSTATE and message
-- (fix round 1, M-1). The session's cached plans are dropped first: a
-- trigger function the owner already ran keeps names it resolved, and would
-- hide a schema the service role may not use.
CREATE FUNCTION pg_temp.as_service(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'DISCARD PLANS';
  EXECUTE 'SET LOCAL ROLE service_role';
  EXECUTE p_sql;
  RESET ROLE;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  RETURN SQLSTATE || ':' || SQLERRM;
END $$;
-- The same, as jsonb (a raised error is {"raised": "<state>:<message>"}).
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
    RAISE EXCEPTION 'w6:probe_undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'w6:probe_undo' THEN
      RAISE;
    END IF;
  END;
  RETURN coalesce(v, '<NULL>');
END $$;
-- Both orders of the single-pair predicate, as 'tt', 'ff' or a mix.
CREATE FUNCTION pg_temp.hf(p_a uuid, p_b uuid) RETURNS text LANGUAGE sql AS $$
  SELECT left(public.dating_pair_passes_hard_filters(p_a, p_b)::text, 1) || left(public.dating_pair_passes_hard_filters(p_b, p_a)::text, 1);
$$;
CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0)::bigint;
$$;
-- An introduction both see now (presented), and its id.
CREATE FUNCTION pg_temp.intro(p_a uuid, p_b uuid) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version,
                                           visible_from_low, visible_from_high, expires_at)
  VALUES (public.dating_pair_key(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), 'presented', 'introductions_v2',
          now() - interval '1 hour', now() - interval '1 hour', now() + interval '6 days')
  RETURNING id;
$$;
-- The pair's marker exists.
CREATE FUNCTION pg_temp.marked(p_a uuid, p_b uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_pair_markers AS k
                  WHERE k.pair_code = private.dating_pair_code(public.dating_phone_hmac_for_user(p_a),
                                                               public.dating_phone_hmac_for_user(p_b)));
$$;
CREATE FUNCTION pg_temp.key(p text) RETURNS text LANGUAGE sql AS $$
  SELECT 'w6-' || p || '-' || replace(gen_random_uuid()::text, '-', '');
$$;

-- =====================================================================
-- A. (§6.1, §7.3; carry 3) The masker: every fixture case masks to its
--    expected output and drops a caption exactly for the caption_drop
--    cases (the TypeScript mirror runs the same file); masked text masks
--    to itself (masking never lifts by itself); the wrapper the insert
--    uses fails closed when the masker raises; the masker is IMMUTABLE.
-- =====================================================================
DO $$
DECLARE
  v_cases constant jsonb := current_setting('w6.cases')::jsonb;
  v_bad text[] := '{}';
  c jsonb;
  v_text text;
  v_t0 timestamptz;
  v_got text;
  v_again text;
BEGIN
  IF (v_cases ->> 'mask_version')::int IS DISTINCT FROM 1 OR jsonb_array_length(v_cases -> 'cases') < 207 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the masking fixture is not version 1 with its 207 cases';
  END IF;
  FOR c IN SELECT x FROM jsonb_array_elements(v_cases -> 'cases') AS x LOOP
    BEGIN -- fix round 1: a case that raises is named, not fatal
      v_got := private.dating_mask_contacts(c ->> 'text');
      v_again := private.dating_mask_contacts(c ->> 'expect');
    EXCEPTION WHEN OTHERS THEN
      v_got := 'raised ' || SQLSTATE || ': ' || SQLERRM;
      v_again := v_got;
    END;
    IF v_got IS DISTINCT FROM c ->> 'expect' THEN
      v_bad := v_bad || format('%s -> %s (want %s)', c ->> 'text', v_got, c ->> 'expect');
    END IF;
    IF private.dating_caption_invites(c ->> 'text') IS DISTINCT FROM (c ->> 'scope' = 'caption_drop') THEN
      v_bad := v_bad || format('%s: caption %s', c ->> 'text', CASE WHEN c ->> 'scope' = 'caption_drop' THEN 'kept' ELSE 'dropped' END);
    END IF;
    IF v_again IS DISTINCT FROM c ->> 'expect' THEN
      v_bad := v_bad || format('%s: masks again', c ->> 'expect');
    END IF;
  END LOOP;
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the masker differs from the fixture: %', v_bad;
  END IF;
  IF (SELECT p.provolatile FROM pg_proc AS p WHERE p.oid = 'private.dating_mask_contacts(text)'::regprocedure) <> 'i' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_mask_contacts is not IMMUTABLE';
  END IF;
  -- Fix round 1 (M-3): 2,000 characters made to be slow mask in bounded time
  -- (each rule's next match is one call that stops at it).
  FOREACH v_text IN ARRAY ARRAY[repeat('snap ', 400), repeat('my snap is ', 180), repeat('signal ', 280),
                                repeat('telegram me ', 165)] LOOP
    v_t0 := clock_timestamp();
    PERFORM private.dating_mask_contacts(v_text);
    IF clock_timestamp() - v_t0 > interval '500 milliseconds' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % characters of "%" took % to mask (over 500 ms)',
        char_length(v_text), left(v_text, 12), clock_timestamp() - v_t0;
    END IF;
  END LOOP;
  IF pg_temp.probe(ARRAY['CREATE OR REPLACE FUNCTION private.dating_mask_contacts(p_text text) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $f$ BEGIN RAISE EXCEPTION ''w6:boom''; END $f$'],
       'SELECT private.dating_mask_contacts_safe(''call 0244 123 456 or ama@x.io or www.x.gh now'')')
     IS DISTINCT FROM '••• ••• ••• ••• ••• ••• ••• ••• •••' THEN -- final server fix (I-8): every word, never weaker than the masker
    RAISE EXCEPTION 'CONTRACT VIOLATED: a masker that raises does not fail closed: %',
      pg_temp.probe(ARRAY['CREATE OR REPLACE FUNCTION private.dating_mask_contacts(p_text text) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $f$ BEGIN RAISE EXCEPTION ''w6:boom''; END $f$'],
       'SELECT private.dating_mask_contacts_safe(''call 0244 123 456 or ama@x.io or www.x.gh now'')');
  END IF;
END $$;

-- =====================================================================
-- B. (§3.4, §6.1; carry 3, owner 2026-11-20) Captions on the card: a
--    contact detail is masked and the caption shown; an invitation off
--    the app or an unkind caption stays off; a caption W5b's helper
--    dropped for nothing (one of the 15 documented false positives) now
--    shows; the helper is gone; a caption edit masks again.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('01');
  b constant uuid := pg_temp.ready('02', '{"identity": "man", "seeking": ["woman"]}');
  v_i uuid;
  v_card jsonb;
  v_caps text[];
BEGIN
  UPDATE public.dating_profile_photos SET caption = 'Lunch at Labadi, call 0244 123 456' WHERE user_id = b AND position = 1;
  UPDATE public.dating_profile_photos SET caption = 'DM me' WHERE user_id = b AND position = 2;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state, caption)
  VALUES (b, 'w6/' || b || '/3.jpg', 3, 'approved', 'clear', 'Snap peas from the garden');
  v_i := pg_temp.intro(a, b);
  v_card := private.dating_card(a, b, (SELECT i FROM public.dating_introductions AS i WHERE i.id = v_i));
  v_caps := ARRAY(SELECT coalesce(x ->> 'caption', '<none>') FROM jsonb_array_elements(v_card -> 'photos') AS x ORDER BY (x ->> 'position')::int);
  IF v_caps IS DISTINCT FROM ARRAY['Lunch at Labadi, call •••', '<none>', 'Snap peas from the garden'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the card''s captions are % (expected the number masked, the invitation off, the peas shown)', v_caps;
  END IF;
  UPDATE public.dating_profile_photos SET caption = 'Find me at amab.com' WHERE user_id = b AND position = 3;
  IF (SELECT f.caption_masked FROM public.dating_profile_photos AS f WHERE f.user_id = b AND f.position = 3)
     IS DISTINCT FROM 'Find me at •••' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an edited caption is not masked again';
  END IF;
  IF to_regprocedure('private.dating_caption_has_contact(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W5b''s caption helper is still there';
  END IF;
  -- Fix round 1 (M-1): the caption trigger is the database's own, so the
  -- service role's direct writes work (a NULL caption too) and are masked.
  v_caps := ARRAY[pg_temp.as_service(format('INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES (%L, %L, 4)',
                                            b, 'w6/' || b || '/4.jpg')),
                  pg_temp.as_service(format('INSERT INTO public.dating_profile_photos (user_id, storage_key, position, caption) VALUES (%L, %L, 5, %L)',
                                            b, 'w6/' || b || '/5.jpg', 'Kumasi, call 0244 123 456'))];
  IF v_caps IS DISTINCT FROM ARRAY['ok', 'ok']
     OR (SELECT f.caption_masked FROM public.dating_profile_photos AS f WHERE f.user_id = b AND f.position = 5)
        IS DISTINCT FROM 'Kumasi, call •••' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a direct service-role photo write failed or was not masked (%)', v_caps;
  END IF;
END $$;

-- =====================================================================
-- C. (§5.2 14, §3.6, §4.8; owner decision 2026-11-20, carry 1) The pair
--    marker. "Not for me" and a block keep it; the single-pair predicate
--    and generation read it; it outlives leaving Dating (the introduction
--    deleted) and deleting an account (the same number on a new account
--    is still never introduced); it holds a code and dates only, purged
--    at 2 years; without the key nothing is kept and it is counted.
-- =====================================================================
DO $$
DECLARE
  v_at constant timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '3 hours 17 minutes';
  a constant uuid := pg_temp.ready('03');
  b constant uuid := pg_temp.ready('04', '{"identity": "man", "seeking": ["woman"]}');
  c constant uuid := pg_temp.ready('05');
  e constant uuid := pg_temp.ready('06', '{"identity": "man", "seeking": ["woman"]}');
  v_i uuid;
  v jsonb;
  v_n bigint;
  b2 uuid;
  p1 constant uuid := pg_temp.ready('23');
  p2 constant uuid := pg_temp.ready('24', '{"identity": "man", "seeking": ["woman"]}');
  p3 constant uuid := pg_temp.ready('25');
  p4 constant uuid := pg_temp.ready('26', '{"identity": "man", "seeking": ["woman"]}');
  p5 constant uuid := pg_temp.ready('27');
  p6 constant uuid := pg_temp.ready('28', '{"identity": "man", "seeking": ["woman"]}');
BEGIN
  -- C1. "Not for me": the marker, and the predicate refuses the pair even
  --     with the introduction gone (as after one of them leaves).
  v_i := pg_temp.intro(a, b);
  v := pg_temp.j(a, '03', format('SELECT public.act_on_dating_introduction(%L, %L, ''passed'')', pg_temp.key('pass'), v_i));
  IF v ->> 'ok' IS DISTINCT FROM 'true' OR NOT pg_temp.marked(a, b) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "Not for me" kept no pair marker (%)', v;
  END IF;
  DELETE FROM public.dating_introductions WHERE id = v_i;
  IF pg_temp.hf(a, b) IS DISTINCT FROM 'ff' OR pg_temp.hf(c, e) IS DISTINCT FROM 'tt' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the predicate ignores the marker (passed pair %, control %)', pg_temp.hf(a, b), pg_temp.hf(c, e);
  END IF;
  -- C2. Generation: the marked pair is never introduced; the control is.
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE state = 'active' AND user_id NOT IN (a, b);
  v := public.run_dating_generation_tick(v_at, 'GH');
  IF (v #>> '{runs,0,created}')::int IS DISTINCT FROM 0
     OR EXISTS (SELECT 1 FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(a, b)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: generation introduced a marked pair again (%)', v;
  END IF;
  IF pg_temp.probe(ARRAY['DELETE FROM public.dating_pair_markers', 'DELETE FROM public.dating_generation_runs'],
       format('SELECT public.run_dating_generation_tick(%L, ''GH'') #>> ''{runs,0,created}''', v_at)) IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the marker the control run did not introduce the pair';
  END IF;
  UPDATE public.dating_enrollments SET state = 'active', pause_reason = NULL WHERE user_id IN (c, e);
  -- C3. A deleted account: the same number on a new account is still
  --     never introduced to a.
  DELETE FROM public.dating_trusted_devices WHERE user_id = b;
  DELETE FROM auth.users WHERE id = b;
  DELETE FROM public.users WHERE id = b;
  b2 := pg_temp.ready('07', '{"identity": "man", "seeking": ["woman"], "phone": "04"}');
  IF pg_temp.hf(a, b2) IS DISTINCT FROM 'ff' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the marker did not survive the account''s deletion (%)', pg_temp.hf(a, b2);
  END IF;
  -- C4. A block (through the card) keeps it too.
  v_i := pg_temp.intro(c, e);
  v := pg_temp.j(c, '05', format('SELECT public.block_dating_introduction(%L, %L)', pg_temp.key('block'), v_i));
  IF v ->> 'ok' IS DISTINCT FROM 'true' OR NOT pg_temp.marked(c, e) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a block kept no pair marker (%)', v;
  END IF;
  -- C5. A code and its dates only; kept 2 years.
  IF (SELECT array_agg(column_name::text ORDER BY ordinal_position) FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'dating_pair_markers') IS DISTINCT FROM ARRAY['pair_code', 'created_at', 'purge_after']
     OR EXISTS (SELECT 1 FROM public.dating_pair_markers WHERE purge_after <> created_at + interval '2 years') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the marker holds more than a code and its dates, or is not kept 2 years';
  END IF;
  -- C6. No key: nothing kept, counted, and the pass still answers.
  v_n := pg_temp.metric('dating.pair_marker.unwritten');
  IF pg_temp.probe(ARRAY['SELECT set_config(''app.settings.dating_exclusion_key'', '''', true)'],
       format('SELECT private.dating_mark_pair(%L, %L)::text || '':'' || pg_temp.metric(''dating.pair_marker.unwritten'')', a, c))
     IS DISTINCT FROM 'false:' || (v_n + 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a marker without the key was not refused and counted';
  END IF;
  -- C7. (fix round 1, M-4) The backfill: a pass, an unmatch and a block
  --     kept before W6a each gain a marker, once; without the key, none.
  v_i := pg_temp.intro(p1, p2);
  UPDATE public.dating_introductions SET low_action = 'passed', state = 'passed' WHERE id = v_i;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, closed_reason, closed_at)
  VALUES (least(p3, p4), greatest(p3, p4), 'unmatched', 'unmatched', now());
  INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
  VALUES (public.dating_phone_hmac_for_user(p5), public.dating_phone_hmac_for_user(p6));
  IF pg_temp.probe(ARRAY['SELECT set_config(''app.settings.dating_exclusion_key'', '''', true)'],
                   'SELECT private.dating_backfill_pair_markers()') IS DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill kept a marker without the key';
  END IF;
  v_n := private.dating_backfill_pair_markers();
  IF v_n < 3 OR NOT pg_temp.marked(p1, p2) OR NOT pg_temp.marked(p3, p4) OR NOT pg_temp.marked(p5, p6) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill missed a pass, an unmatch or a block (% kept; %, %, %)', v_n,
      pg_temp.marked(p1, p2), pg_temp.marked(p3, p4), pg_temp.marked(p5, p6);
  END IF;
  v_n := private.dating_backfill_pair_markers();
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second backfill kept % marker(s) more', v_n;
  END IF;
END $$;

-- =====================================================================
-- D. (§2.4; carry 5) A man who moves from Ghana to the UK is asked his
--    gender again; until he answers, the identity he held is kept
--    (encrypted) for the kill switch alone, so a Ghana switch keeps his
--    man-woman match open. A pair with no identity at all still closes
--    (fail-safe), as does a same-gender one; his answer clears what was
--    held; a switched country keeps only a plain woman or man held
--    (final server fix, M-11). Fix round 1: moving
--    back before answering again keeps the match and pauses nobody (I-1);
--    the switch judges everyone, in Ghana or abroad, by what they hold, and
--    never writes it as their answer (M-4).
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('10');
  m constant uuid := pg_temp.ready('11', '{"identity": "man", "seeking": ["woman"]}');
  x constant uuid := pg_temp.ready('12');
  y constant uuid := pg_temp.ready('13', '{"identity": "man", "seeking": ["woman"]}');
  w2 constant uuid := pg_temp.ready('16', '{"seeking": ["woman"]}');
  w3 constant uuid := pg_temp.ready('17', '{"country": "GB", "region": "TLI", "seeking": ["woman"]}');
  r constant uuid := pg_temp.ready('18', '{"identity": "man", "seeking": ["woman"]}');
  n constant uuid := pg_temp.ready('19');
  k constant uuid := pg_temp.ready('20', '{"identity": "man", "seeking": ["woman"]}');
  q constant uuid := pg_temp.ready('29');
  v jsonb;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state)
  VALUES (least(w, m), greatest(w, m), 'active'), (least(x, y), greatest(x, y), 'active'),
         (least(w2, w3), greatest(w2, w3), 'active'), (least(n, k), greatest(n, k), 'active'),
         (least(r, q), greatest(r, q), 'active');
  v := pg_temp.j(m, '11', format('SELECT public.save_dating_location(%L, ''GB'', ''TLI'', NULL, ''region'')', pg_temp.key('move')));
  IF v ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT s.identity_enc IS NULL AND s.held_identity_enc IS NOT NULL FROM public.dating_profile_sensitive AS s WHERE s.user_id = m)
        IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a move did not ask again while holding the identity (%)', v;
  END IF;
  -- D2. (fix round 1, I-1) Back to Ghana 31 days later, still not answered
  --     again: judged by what he held, the match stays open and he is not
  --     paused; it is still held.
  UPDATE public.dating_profiles SET country_changed_at = now() - interval '31 days' WHERE user_id = m;
  v := pg_temp.j(m, '11', format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''region'')', pg_temp.key('back')));
  IF v ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT state FROM public.dating_matches WHERE pair_key = public.dating_pair_key(w, m)) IS DISTINCT FROM 'active'
     OR (SELECT e.state FROM public.dating_enrollments AS e WHERE e.user_id = m) IS DISTINCT FROM 'active'
     OR (SELECT s.identity_enc IS NULL AND s.held_identity_enc IS NOT NULL FROM public.dating_profile_sensitive AS s WHERE s.user_id = m)
        IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: moving back before answering again closed his man-woman match, paused him or lost what he held (%, match %, enrolment %)',
      v, (SELECT state || '/' || coalesce(closed_reason, '-') FROM public.dating_matches WHERE pair_key = public.dating_pair_key(w, m)),
      (SELECT e.state || '/' || coalesce(e.pause_reason, '-') FROM public.dating_enrollments AS e WHERE e.user_id = m);
  END IF;
  -- D3. A woman in Ghana holding an identity with pronouns (not allowed
  --     there), not answered again, matched with a man.
  UPDATE public.dating_profile_sensitive
     SET identity_enc = NULL,
         held_identity_enc = private.dating_field_encrypt(jsonb_build_object('identity', 'woman', 'pronouns', 'she/her',
                                                                             'pools', jsonb_build_array('woman')))
   WHERE user_id = n;
  -- D4. r moves to the UK and has not answered again when Ghana switches.
  v := pg_temp.j(r, '18', format('SELECT public.save_dating_location(%L, ''GB'', ''TLI'', NULL, ''region'')', pg_temp.key('move')));
  IF v ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT s.held_identity_enc IS NOT NULL FROM public.dating_profile_sensitive AS s WHERE s.user_id = r) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a move did not hold the identity (%)', v;
  END IF;
  UPDATE public.dating_profile_sensitive SET identity_enc = NULL WHERE user_id = y; -- no identity, nothing held
  PERFORM public.apply_same_gender_switch('GH');
  IF (SELECT state FROM public.dating_matches WHERE pair_key = public.dating_pair_key(w, m)) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the switch closed a man-woman match because the man moved and has not answered again (carry 5)';
  END IF;
  IF (SELECT state || '/' || closed_reason FROM public.dating_matches WHERE pair_key = public.dating_pair_key(x, y))
     IS DISTINCT FROM 'closed/other'
     OR (SELECT state || '/' || closed_reason FROM public.dating_matches WHERE pair_key = public.dating_pair_key(w2, w3))
     IS DISTINCT FROM 'closed/other' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the switch left open a pair with no identity, or a same-gender pair';
  END IF;
  -- Fix round 1 (M-4): judged by what they held: he (plain) is not paused;
  -- her pair stays man-woman, she is paused (pronouns) and what she held is
  -- never written as her answer; nothing is held in Ghana now (both were).
  IF (SELECT e.state FROM public.dating_enrollments AS e WHERE e.user_id = m) IS DISTINCT FROM 'active'
     OR (SELECT state FROM public.dating_matches WHERE pair_key = public.dating_pair_key(n, k)) IS DISTINCT FROM 'active'
     OR (SELECT e.state || '/' || e.pause_reason FROM public.dating_enrollments AS e WHERE e.user_id = n) IS DISTINCT FROM 'paused/same_gender_switch'
     OR (SELECT s.identity_enc FROM public.dating_profile_sensitive AS s WHERE s.user_id = n) IS NOT NULL
     OR (SELECT state FROM public.dating_matches WHERE pair_key = public.dating_pair_key(r, q)) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the switch did not judge by what was held (his enrolment %, her match %, her enrolment %, her answer written %, the UK mover''s match %)',
      (SELECT e.state || '/' || coalesce(e.pause_reason, '-') FROM public.dating_enrollments AS e WHERE e.user_id = m),
      (SELECT state FROM public.dating_matches WHERE pair_key = public.dating_pair_key(n, k)),
      (SELECT e.state || '/' || coalesce(e.pause_reason, '-') FROM public.dating_enrollments AS e WHERE e.user_id = n),
      (SELECT s.identity_enc IS NOT NULL FROM public.dating_profile_sensitive AS s WHERE s.user_id = n),
      (SELECT state FROM public.dating_matches WHERE pair_key = public.dating_pair_key(r, q));
  END IF;
  -- Final server fix (M-11): what is held keeps a plain woman or man answer
  -- (his, as it was; hers without the pronouns Ghana does not allow), so a
  -- second switch before either answers again still keeps both man-woman
  -- pairs open and pauses him not.
  IF (SELECT private.dating_field_decrypt(s.held_identity_enc) ->> 'identity' FROM public.dating_profile_sensitive AS s WHERE s.user_id = m)
       IS DISTINCT FROM 'man'
     OR (SELECT private.dating_field_decrypt(s.held_identity_enc) FROM public.dating_profile_sensitive AS s WHERE s.user_id = n)
       IS DISTINCT FROM jsonb_build_object('identity', 'woman', 'specific', NULL, 'specific_text', NULL, 'pronouns', NULL,
                                           'pools', jsonb_build_array('woman')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the switch did not keep a plain held identity, or kept a disallowed part (his %, hers %)',
      (SELECT private.dating_field_decrypt(s.held_identity_enc) FROM public.dating_profile_sensitive AS s WHERE s.user_id = m),
      (SELECT private.dating_field_decrypt(s.held_identity_enc) FROM public.dating_profile_sensitive AS s WHERE s.user_id = n);
  END IF;
  PERFORM public.apply_same_gender_switch('GH');
  IF (SELECT state FROM public.dating_matches WHERE pair_key = public.dating_pair_key(w, m)) IS DISTINCT FROM 'active'
     OR (SELECT state FROM public.dating_matches WHERE pair_key = public.dating_pair_key(n, k)) IS DISTINCT FROM 'active'
     OR (SELECT e.state FROM public.dating_enrollments AS e WHERE e.user_id = m) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second switch before he answered again closed a man-woman match or paused him (M-11)';
  END IF;
  -- D5. Answering again clears what was held (r, in the UK).
  v := pg_temp.j(r, '18', format('SELECT public.save_dating_identity(%L, ''man'', NULL, NULL, NULL, true)', pg_temp.key('d5')));
  IF v ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT s.held_identity_enc FROM public.dating_profile_sensitive AS s WHERE s.user_id = r) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: answering again did not clear the held identity (%)', v;
  END IF;
END $$;

-- =====================================================================
-- E. (§3.5; carry 7) Act names the match its answer made, the same on a
--    replay; a later answer meets the first standing and names none; a
--    pass names none.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('14');
  b constant uuid := pg_temp.ready('15', '{"identity": "man", "seeking": ["woman"]}');
  v_i constant uuid := pg_temp.intro(a, b);
  k constant text := pg_temp.key('int');
  a2 constant uuid := pg_temp.ready('21');
  b2 constant uuid := pg_temp.ready('22', '{"identity": "man", "seeking": ["woman"]}');
  v_i2 constant uuid := pg_temp.intro(a2, b2);
  v1 jsonb;
  v2 jsonb;
  v3 jsonb;
  v4 jsonb;
  v5 jsonb;
BEGIN
  v1 := pg_temp.j(a, '14', format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', pg_temp.key('int'), v_i));
  -- Fix round 1 (M-4): a later answer with a new key meets the first answer
  -- standing (no rewind) and names nobody (once matched, the introduction
  -- is no longer the caller's to act on, so this path never meets a match).
  v4 := pg_temp.j(a, '14', format('SELECT public.act_on_dating_introduction(%L, %L, ''passed'')', pg_temp.key('again'), v_i));
  v2 := pg_temp.j(b, '15', format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', k, v_i));
  v3 := pg_temp.j(b, '15', format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', k, v_i));
  v5 := pg_temp.j(a2, '21', format('SELECT public.act_on_dating_introduction(%L, %L, ''passed'')', pg_temp.key('pass'), v_i2));
  IF v1 ? 'match_id'
     OR v2 ->> 'match_id' IS DISTINCT FROM (SELECT id::text FROM public.dating_matches WHERE introduction_id = v_i)
     OR v3 ->> 'match_id' IS DISTINCT FROM v2 ->> 'match_id'
     OR v4 IS DISTINCT FROM '{"ok": true, "action": "interested", "matched": false}'::jsonb
     OR v5 ->> 'ok' IS DISTINCT FROM 'true' OR v5 ? 'match_id' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: act does not name the match it made, or names one it did not (first %, second %, replay %, later %, pass %)',
      v1, v2, v3, v4, v5;
  END IF;
END $$;

-- =====================================================================
-- F. (§3.6, §4.3; chat spec §2.3, §11) A dating message never enters the
--    couples chat: no row in public.messages, relationship_message_counters,
--    message_safety_outbox or message_notification_outbox; it is masked
--    at insert (mask_version 1, counted) and the recipient's chat signal
--    is bumped (no content in it), never the sender's.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('30');
  b constant uuid := pg_temp.ready('31', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_before bigint[];
  v_hits bigint := pg_temp.metric('dating.mask_hit');
  v jsonb;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  v_before := ARRAY[(SELECT count(*) FROM public.messages), (SELECT count(*) FROM public.relationship_message_counters),
                    (SELECT count(*) FROM public.message_safety_outbox), (SELECT count(*) FROM public.message_notification_outbox)];
  v := pg_temp.j(a, '30', format('SELECT public.send_dating_message(%L, %L, ''Call me on 0244 123 456'')', pg_temp.key('send'), v_m));
  IF v ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member could not send: %', v;
  END IF;
  IF ARRAY[(SELECT count(*) FROM public.messages), (SELECT count(*) FROM public.relationship_message_counters),
           (SELECT count(*) FROM public.message_safety_outbox), (SELECT count(*) FROM public.message_notification_outbox)]
     IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dating message reached the couples chat''s tables';
  END IF;
  IF (SELECT d.body || '|' || d.body_masked || '|' || d.mask_version || '|' || d.sender_side || '|' || d.kind
        FROM public.dating_messages AS d WHERE d.match_id = v_m)
     IS DISTINCT FROM ('Call me on 0244 123 456|Call me on •••|1|' || (CASE WHEN a < b THEN 'low' ELSE 'high' END) || '|text')
     OR pg_temp.metric('dating.mask_hit') <> v_hits + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the message was not stored masked at insert, or the hit was not counted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = b AND match_id = v_m)
     OR EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = a)
     OR (SELECT array_agg(column_name::text ORDER BY ordinal_position) FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'dating_chat_signals') IS DISTINCT FROM ARRAY['id', 'user_id', 'match_id', 'bumped_at'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the recipient''s signal was not bumped, the sender''s was, or a signal holds more than a bump';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'dating_chat_signals')
     AND EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the chat signals are not in the realtime publication';
  END IF;
  -- Fix round 1 (I-3): realtime skips RLS for DELETE events and a DELETE
  -- frame carries the key, so the key is an opaque id (and the replica
  -- identity stays the key).
  IF (SELECT array_agg(a.attname::text ORDER BY a.attname) FROM pg_index AS x
        JOIN pg_attribute AS a ON a.attrelid = x.indrelid AND a.attnum = ANY (x.indkey)
       WHERE x.indrelid = 'public.dating_chat_signals'::regclass AND x.indisprimary) IS DISTINCT FROM ARRAY['id']
     OR NOT EXISTS (SELECT 1 FROM pg_index AS x WHERE x.indrelid = 'public.dating_chat_signals'::regclass
                       AND x.indisunique AND NOT x.indisprimary AND x.indnatts = 2)
     OR (SELECT relreplident FROM pg_class WHERE oid = 'public.dating_chat_signals'::regclass) <> 'd' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the chat signals'' key names a person or a match (a realtime DELETE frame carries it)';
  END IF;
END $$;

-- =====================================================================
-- G. (§3.6, §4.4; Fable C1, H2) Send's refusals, each a fixed answer:
--    invalid input; another phone; an outsider and a match that doesn't
--    exist (one answer); a sender not in good standing; a replay answers the first
--    message and stores none.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('32');
  b constant uuid := pg_temp.ready('33', '{"identity": "man", "seeking": ["woman"]}');
  o constant uuid := pg_temp.ready('34');
  v_m uuid;
  k constant text := pg_temp.key('replay');
  v1 jsonb;
  v2 jsonb;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  IF pg_temp.j(a, '32', format('SELECT public.send_dating_message(%L, %L, ''   '')', pg_temp.key('blank'), v_m)) ->> 'reason' IS DISTINCT FROM 'invalid'
     OR pg_temp.j(a, '32', format('SELECT public.send_dating_message(%L, %L, %L)', pg_temp.key('long'), v_m, repeat('x', 1001))) ->> 'reason' IS DISTINCT FROM 'invalid'
     OR pg_temp.j(a, '32', format('SELECT public.send_dating_message(''short'', %L, ''hi'')', v_m)) ->> 'reason' IS DISTINCT FROM 'invalid'
     OR pg_temp.j(a, '32', format('SELECT public.send_dating_message(%L, %L, ''hi'', ''close_kindly'')', pg_temp.key('kind'), v_m)) ->> 'reason' IS DISTINCT FROM 'invalid'
     OR pg_temp.call(a, pg_temp.dev('99'), format('SELECT public.send_dating_message(%L, %L, ''hi'')', pg_temp.key('phone'), v_m))::jsonb ->> 'reason'
        IS DISTINCT FROM 'reverify_device' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: send took invalid input or another phone';
  END IF;
  IF pg_temp.j(o, '34', format('SELECT public.send_dating_message(%L, %L, ''hi'')', pg_temp.key('o'), v_m))
     IS DISTINCT FROM pg_temp.j(o, '34', format('SELECT public.send_dating_message(%L, %L, ''hi'')', pg_temp.key('n'), gen_random_uuid()))
     OR pg_temp.j(o, '34', format('SELECT public.send_dating_message(%L, %L, ''hi'')', pg_temp.key('o'), v_m)) ->> 'reason'
        IS DISTINCT FROM 'match_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider''s send answered differently from a match that doesn''t exist';
  END IF;
  UPDATE auth.users SET banned_until = now() + interval '1 day' WHERE id = a; -- not in good standing (W7a's holds keep the match open)
  IF pg_temp.j(a, '32', format('SELECT public.send_dating_message(%L, %L, ''hi'')', pg_temp.key('held'), v_m)) ->> 'reason' IS DISTINCT FROM 'restricted'
     OR EXISTS (SELECT 1 FROM public.dating_messages WHERE match_id = v_m) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person not in good standing could send';
  END IF;
  UPDATE auth.users SET banned_until = NULL WHERE id = a;
  v1 := pg_temp.j(b, '33', format('SELECT public.send_dating_message(%L, %L, ''Hello there'')', k, v_m));
  v2 := pg_temp.j(b, '33', format('SELECT public.send_dating_message(%L, %L, ''Hello again'')', k, v_m));
  IF v1 ->> 'ok' IS DISTINCT FROM 'true' OR v2 IS DISTINCT FROM v1
     OR (SELECT count(*) FROM public.dating_messages WHERE match_id = v_m) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay sent a second message or answered differently (% then %)', v1, v2;
  END IF;
END $$;

CREATE TEMP SEQUENCE g2_saw;
-- Final server fix (I-8): a's 1,000-character send under the key [p_key]:
-- its answer's ok, and whether what it stored masks every letter and digit.
CREATE FUNCTION pg_temp.g2_send(p_a uuid, p_m uuid, p_key text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  v := pg_temp.j(p_a, '51', format('SELECT public.send_dating_message(%L, %L, %L)', p_key, p_m, rpad('call 0244 123 456', 1000, ' ok')));
  RETURN coalesce(v ->> 'ok', v::text) || '|' || coalesce((SELECT (d.body_masked !~ '[[:alnum:]]')::text FROM public.dating_messages AS d
                                                            WHERE d.match_id = p_m AND d.idempotency_key = p_key), 'none');
END $$;

-- =====================================================================
-- G2. (§3.6; Spec 2 W6a Task 2, controller item 2) The body is capped at
--     1,000 characters before the masker runs: exactly 1,000 is sent,
--     masked; 1,001 and a 2,600-character body answer invalid and store
--     nothing; with a masker that raises, 1,001 still answers invalid (the
--     masker never saw it) while 1,000 reaches it (the probe is live: the
--     fail-closed fallback is stored, no letter or digit left; final server
--     fix, I-8).
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('51');
  b constant uuid := pg_temp.ready('52', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v jsonb;
  -- The stand-in counts each body it sees on a sequence (never undone by
  -- the fallback's savepoint), then raises.
  v_boom constant text[] := ARRAY['CREATE OR REPLACE FUNCTION private.dating_mask_contacts(p_text text) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $f$ BEGIN PERFORM nextval(''pg_temp.g2_saw''); RAISE EXCEPTION ''w6:masker_saw_it''; END $f$'];
  v_k1000 constant text := pg_temp.key('capm1000');
  v_saw bigint;
  v_r1001 text;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  v := pg_temp.j(a, '51', format('SELECT public.send_dating_message(%L, %L, %L)', pg_temp.key('cap1000'), v_m, rpad('call 0244 123 456', 1000, ' ok')));
  IF v ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT char_length(d.body) || '|' || left(d.body_masked, 9) FROM public.dating_messages AS d WHERE d.match_id = v_m)
        IS DISTINCT FROM '1000|call ••• ' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 1,000-character message was not sent masked: %', v;
  END IF;
  IF pg_temp.j(a, '51', format('SELECT public.send_dating_message(%L, %L, %L)', pg_temp.key('cap1001'), v_m, rpad('call 0244 123 456', 1001, ' ok'))) ->> 'reason'
        IS DISTINCT FROM 'invalid'
     OR pg_temp.j(a, '51', format('SELECT public.send_dating_message(%L, %L, %L)', pg_temp.key('caphuge'), v_m, repeat('0244 123 456 ', 200))) ->> 'reason'
        IS DISTINCT FROM 'invalid'
     OR (SELECT count(*) FROM public.dating_messages WHERE match_id = v_m) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a message over 1,000 characters was not refused as invalid';
  END IF;
  PERFORM nextval('pg_temp.g2_saw');
  v_saw := currval('pg_temp.g2_saw');
  v_r1001 := pg_temp.probe(v_boom, format('SELECT pg_temp.j(%L, ''51'', %L) ->> ''reason''', a,
       format('SELECT public.send_dating_message(%L, %L, %L)', pg_temp.key('capm1001'), v_m, rpad('call 0244 123 456', 1001, ' ok'))));
  v_saw := currval('pg_temp.g2_saw') - v_saw; -- final server fix (I-8): what the masker saw of the 1,001 characters
  IF v_r1001 IS DISTINCT FROM 'invalid' OR v_saw <> 0
     OR pg_temp.probe(v_boom, format('SELECT pg_temp.g2_send(%L, %L, %L)', a, v_m, v_k1000)) IS DISTINCT FROM 'true|true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the masker saw a body over the 1,000-character cap (or the probe never reached it)';
  END IF;
END $$;

-- =====================================================================
-- H. (§3.6, §4.4, §4.5; chat spec §4.4; mutant 12) A blocked or unmatched
--    pair can't send through a stale client: the chat still open, the
--    next send answers closed and stores nothing (a block by account, by
--    phone HMAC alone, an unmatch); no API role can insert a row, and were
--    INSERT ever granted the policy refuses the blocked pair.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('35');
  b constant uuid := pg_temp.ready('36', '{"identity": "man", "seeking": ["woman"]}');
  c constant uuid := pg_temp.ready('37');
  e constant uuid := pg_temp.ready('38', '{"identity": "man", "seeking": ["woman"]}');
  f constant uuid := pg_temp.ready('39');
  g constant uuid := pg_temp.ready('40', '{"identity": "man", "seeking": ["woman"]}');
  v_ab uuid;
  v_ce uuid;
  v_fg uuid;
  v jsonb;
  v_err text;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_ab;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(c, e), greatest(c, e), 'active') RETURNING id INTO v_ce;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(f, g), greatest(f, g), 'active') RETURNING id INTO v_fg;
  -- a blocks b from the chat; b's stale screen sends.
  v := pg_temp.j(a, '35', format('SELECT public.block_dating_match(%L, %L)', pg_temp.key('block'), v_ab));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR NOT pg_temp.marked(a, b)
     OR (SELECT state || '/' || closed_reason FROM public.dating_matches WHERE id = v_ab) IS DISTINCT FROM 'blocked/blocked'
     OR NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = b AND match_id = v_ab) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the chat''s Block answered % (or kept no marker, did not close, did not tell b''s chat)', v;
  END IF;
  -- A block by phone HMAC alone (the match left open, as after a
  -- re-registration): the send still refuses.
  INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
  VALUES (public.dating_phone_hmac_for_user(f), public.dating_phone_hmac_for_user(g));
  v := pg_temp.j(e, '38', format('SELECT public.unmatch_dating_match(%L, %L)', pg_temp.key('unmatch'), v_ce));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR NOT pg_temp.marked(c, e)
     OR (SELECT state || '/' || closed_reason || '/' || (evidence_until > now() + interval '29 days')::text FROM public.dating_matches WHERE id = v_ce)
        IS DISTINCT FROM 'unmatched/unmatched/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: unmatch answered % (or kept no marker, or no 30-day evidence window)', v;
  END IF;
  IF pg_temp.j(b, '36', format('SELECT public.send_dating_message(%L, %L, ''still there?'')', pg_temp.key('stale1'), v_ab)) ->> 'reason' IS DISTINCT FROM 'closed'
     OR pg_temp.j(c, '37', format('SELECT public.send_dating_message(%L, %L, ''still there?'')', pg_temp.key('stale2'), v_ce)) ->> 'reason' IS DISTINCT FROM 'closed'
     OR pg_temp.j(g, '40', format('SELECT public.send_dating_message(%L, %L, ''still there?'')', pg_temp.key('stale3'), v_fg)) ->> 'reason' IS DISTINCT FROM 'closed'
     OR EXISTS (SELECT 1 FROM public.dating_messages WHERE match_id IN (v_ab, v_ce, v_fg)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a blocked or unmatched pair sent through a stale client (mutant 12)';
  END IF;
  -- Fixed answers: an outsider's and a missing match's block, and a
  -- second unmatch, never raise.
  IF pg_temp.j(c, '37', format('SELECT public.block_dating_match(%L, %L)', pg_temp.key('ob'), v_fg)) ->> 'reason' IS DISTINCT FROM 'match_unavailable'
     OR pg_temp.j(c, '37', format('SELECT public.block_dating_match(%L, %L)', pg_temp.key('nb'), gen_random_uuid())) ->> 'reason' IS DISTINCT FROM 'match_unavailable'
     OR pg_temp.j(c, '37', format('SELECT public.unmatch_dating_match(%L, %L)', pg_temp.key('again'), v_ce)) IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.j(c, '37', 'SELECT public.block_dating_match(''short'', NULL)') ->> 'reason' IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: block or unmatch raised or answered loosely';
  END IF;
  -- No API role inserts; with INSERT granted (only here) the policy refuses.
  v_err := pg_temp.call(g, pg_temp.dev('40'), format(
    'WITH x AS (INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, body, body_masked, mask_version, idempotency_key)
     VALUES (%L, %L, %L, ''x'', ''x'', 1, ''k-direct'') RETURNING 1) SELECT count(*)::text FROM x', v_fg, CASE WHEN g < f THEN 'low' ELSE 'high' END, g));
  IF v_err NOT LIKE '42501:permission denied%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in person could insert a dating message directly: %', v_err;
  END IF;
  GRANT INSERT ON public.dating_messages TO authenticated;
  v_err := pg_temp.call(g, pg_temp.dev('40'), format(
    'WITH x AS (INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, body, body_masked, mask_version, idempotency_key)
     VALUES (%L, %L, %L, ''x'', ''x'', 1, ''k-direct'') RETURNING 1) SELECT count(*)::text FROM x', v_fg, CASE WHEN g < f THEN 'low' ELSE 'high' END, g));
  REVOKE INSERT ON public.dating_messages FROM authenticated;
  IF v_err NOT LIKE '42501:new row violates row-level security policy%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the INSERT policy let a blocked pair write: %', v_err;
  END IF;
END $$;

-- =====================================================================
-- I. (§3.6, §6.1; mutants 10, 11) The mask holds until both swap: one
--    side's offer unmasks nothing; withdrawn, still nothing; both: the
--    words as written, for old and new messages; time alone never lifts
--    it; swap refused before 72 hours (with the time it opens); after
--    both, it can't be withdrawn; an ended chat can't swap.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('41');
  b constant uuid := pg_temp.ready('42', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v jsonb;
  v_text text;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at)
  VALUES (least(a, b), greatest(a, b), 'active', now() - interval '71 hours') RETURNING id INTO v_m;
  PERFORM pg_temp.j(a, '41', format('SELECT public.send_dating_message(%L, %L, ''my snapchat is amab'')', pg_temp.key('s1'), v_m));
  v := pg_temp.j(a, '41', format('SELECT public.offer_dating_contact_swap(%L)', v_m));
  IF v ->> 'reason' IS DISTINCT FROM 'too_early'
     OR (v ->> 'from')::timestamptz IS DISTINCT FROM (SELECT matched_at + interval '72 hours' FROM public.dating_matches WHERE id = v_m) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: swap was not refused before 72 hours, with the time it opens (mutant 11): %', v;
  END IF;
  UPDATE public.dating_matches SET matched_at = now() - interval '72 hours' WHERE id = v_m;
  v := pg_temp.j(a, '41', format('SELECT public.offer_dating_contact_swap(%L)', v_m));
  v_text := pg_temp.j(b, '42', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{messages,0,text}';
  IF v IS DISTINCT FROM '{"ok": true, "swap": {"both": false, "mine": true, "theirs": false}}'::jsonb OR v_text IS DISTINCT FROM '•••' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one side''s offer unmasked the chat (mutant 10): % / %', v, v_text;
  END IF;
  IF pg_temp.j(b, '42', format('SELECT public.get_dating_messages(%L)', v_m)) #> '{chat,swap}'
     IS DISTINCT FROM jsonb_build_object('mine', false, 'theirs', true, 'both', false,
                                         'from', (SELECT matched_at + interval '72 hours' FROM public.dating_matches WHERE id = v_m)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other side does not see the offer';
  END IF;
  v := pg_temp.j(a, '41', format('SELECT public.withdraw_dating_contact_swap(%L)', v_m));
  PERFORM pg_temp.j(b, '42', format('SELECT public.offer_dating_contact_swap(%L)', v_m));
  IF v IS DISTINCT FROM '{"ok": true, "swap": {"both": false, "mine": false, "theirs": false}}'::jsonb
     OR pg_temp.j(a, '41', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{messages,0,text}' IS DISTINCT FROM '•••' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a withdrawn offer, then the other''s, unmasked the chat: %', v;
  END IF;
  -- Time alone never lifts it.
  UPDATE public.dating_matches SET matched_at = now() - interval '400 days' WHERE id = v_m;
  IF pg_temp.j(a, '41', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{messages,0,text}' IS DISTINCT FROM '•••' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the mask lifted by itself';
  END IF;
  PERFORM pg_temp.j(a, '41', format('SELECT public.offer_dating_contact_swap(%L)', v_m));
  PERFORM pg_temp.j(b, '42', format('SELECT public.send_dating_message(%L, %L, ''mine is 0244 123 456'')', pg_temp.key('s2'), v_m));
  v := pg_temp.j(a, '41', format('SELECT public.get_dating_messages(%L)', v_m));
  IF (SELECT array_agg(x ->> 'text' ORDER BY x ->> 'at') FROM jsonb_array_elements(v -> 'messages') AS x)
     IS DISTINCT FROM ARRAY['my snapchat is amab', 'mine is 0244 123 456']
     OR v #>> '{chat,swap,both}' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after both swapped the words are not as written: %', v;
  END IF;
  IF pg_temp.j(a, '41', format('SELECT public.withdraw_dating_contact_swap(%L)', v_m)) ->> 'reason' IS DISTINCT FROM 'already_swapped' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a swap both made could be undone';
  END IF;
  UPDATE public.dating_matches SET state = 'unmatched', closed_reason = 'unmatched', evidence_until = now() + interval '30 days' WHERE id = v_m;
  IF pg_temp.j(a, '41', format('SELECT public.offer_dating_contact_swap(%L)', v_m)) ->> 'reason' IS DISTINCT FROM 'closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ended chat could swap';
  END IF;
END $$;

-- =====================================================================
-- J. (§3.5, §3.6) The reads: messages newest first with a page bound and
--    keyset paging; an ended chat is read-only for its 30-day window,
--    then gone; the conversations list: newest activity first, the last
--    message as the reader reads it, a dot (never a count) until read,
--    the ended section on request; another phone reads nothing; an
--    outsider reads nothing (one answer with a missing match).
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('43');
  b constant uuid := pg_temp.ready('44', '{"identity": "man", "seeking": ["woman"], "name": "Kofi"}');
  c constant uuid := pg_temp.ready('45', '{"identity": "man", "seeking": ["woman"], "name": "Yaw"}');
  o constant uuid := pg_temp.ready('46');
  v_ab uuid;
  v_ac uuid;
  v jsonb;
  v_page jsonb;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at)
  VALUES (least(a, b), greatest(a, b), 'active', now() - interval '2 days') RETURNING id INTO v_ab;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at)
  VALUES (least(a, c), greatest(a, c), 'active', now() - interval '1 day') RETURNING id INTO v_ac;
  FOR i IN 1..3 LOOP
    PERFORM pg_temp.j(b, '44', format('SELECT public.send_dating_message(%L, %L, %L)', pg_temp.key('m' || i), v_ab, 'message ' || i));
  END LOOP;
  v := pg_temp.j(a, '43', 'SELECT public.get_my_dating_matches()');
  IF (SELECT array_agg(x ->> 'display_name' || ':' || (x ->> 'new') || ':' || coalesce(x #>> '{last,text}', '-') ORDER BY ord)
        FROM jsonb_array_elements(v -> 'conversations') WITH ORDINALITY AS t(x, ord))
     IS DISTINCT FROM ARRAY['Kofi:true:message 3', 'Yaw:false:-'] OR v ? 'ended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the conversations list is %', v;
  END IF;
  v_page := pg_temp.j(a, '43', format('SELECT public.get_dating_messages(%L, NULL, 2)', v_ab));
  IF (SELECT array_agg(x ->> 'text' ORDER BY ord) FROM jsonb_array_elements(v_page -> 'messages') WITH ORDINALITY AS t(x, ord))
     IS DISTINCT FROM ARRAY['message 3', 'message 2'] OR v_page ->> 'more' IS DISTINCT FROM 'true'
     OR v_page #>> '{chat,display_name}' IS DISTINCT FROM 'Kofi' OR v_page #>> '{chat,state}' IS DISTINCT FROM 'active'
     OR (v_page #>> '{messages,0,mine}')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the newest page is %', v_page;
  END IF;
  v := pg_temp.j(a, '43', format('SELECT public.get_dating_messages(%L, %L, 2)', v_ab, v_page #>> '{messages,1,at}'));
  IF (SELECT array_agg(x ->> 'text') FROM jsonb_array_elements(v -> 'messages') AS x) IS DISTINCT FROM ARRAY['message 1']
     OR v ->> 'more' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the next page is %', v;
  END IF;
  IF pg_temp.j(a, '43', 'SELECT public.get_my_dating_matches()') #>> '{conversations,0,new}' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: reading the chat did not clear the dot';
  END IF;
  IF pg_temp.call(a, pg_temp.dev('99'), 'SELECT public.get_my_dating_matches()')::jsonb IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}'::jsonb
     OR pg_temp.call(a, pg_temp.dev('99'), format('SELECT public.get_dating_messages(%L)', v_ab))::jsonb ->> 'reason' IS DISTINCT FROM 'reverify_device'
     OR pg_temp.j(o, '46', format('SELECT public.get_dating_messages(%L)', v_ab))
        IS DISTINCT FROM pg_temp.j(o, '46', format('SELECT public.get_dating_messages(%L)', gen_random_uuid()))
     OR pg_temp.j(o, '46', 'SELECT public.get_my_dating_matches(true)') IS DISTINCT FROM '{"ok": true, "ended": [], "conversations": []}'::jsonb
     OR pg_temp.j(a, '43', format('SELECT public.get_dating_messages(%L, NULL, 101)', v_ab)) ->> 'reason' IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another phone or an outsider read the chat, or a page over 100 was taken';
  END IF;
  -- Ended: read-only for its window, listed under ended, then gone.
  PERFORM pg_temp.j(a, '43', format('SELECT public.unmatch_dating_match(%L, %L)', pg_temp.key('u'), v_ab));
  v := pg_temp.j(a, '43', 'SELECT public.get_my_dating_matches(true)');
  IF jsonb_array_length(v -> 'conversations') <> 1 OR v #>> '{ended,0,display_name}' IS DISTINCT FROM 'Kofi'
     OR pg_temp.j(b, '44', format('SELECT public.get_dating_messages(%L)', v_ab)) #>> '{chat,state}' IS DISTINCT FROM 'ended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ended chat is not listed as ended, or not readable as ended: %', v;
  END IF;
  UPDATE public.dating_matches SET evidence_until = now() - interval '1 minute' WHERE id = v_ab;
  IF pg_temp.j(b, '44', format('SELECT public.get_dating_messages(%L)', v_ab)) ->> 'reason' IS DISTINCT FROM 'match_unavailable'
     OR jsonb_array_length(pg_temp.j(a, '43', 'SELECT public.get_my_dating_matches(true)') -> 'ended') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ended chat is still readable after its evidence window';
  END IF;
END $$;

-- =====================================================================
-- K. (§2.3; W5 final review I-1) The chat's reads refresh the phone's
--    last use as PostgREST calls them (a STABLE RPC runs READ ONLY there),
--    so each is VOLATILE.
-- =====================================================================
DO $$
DECLARE
  u constant uuid := pg_temp.ready('47');
  v_fn text;
  v_ro boolean;
  v_seen timestamptz;
  v_bad text[] := '{}';
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.get_my_dating_matches(boolean)', 'public.get_dating_messages(uuid,timestamp with time zone,integer)'] LOOP
    UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval '2 days' WHERE user_id = u;
    SELECT p.provolatile <> 'v' INTO v_ro FROM pg_catalog.pg_proc AS p WHERE p.oid = v_fn::regprocedure;
    v_seen := NULL;
    BEGIN
      IF v_ro THEN
        PERFORM set_config('transaction_read_only', 'on', true);
      END IF;
      PERFORM pg_temp.call(u, pg_temp.dev('47'), CASE WHEN v_fn LIKE '%messages(uuid%' THEN 'SELECT public.get_dating_messages(gen_random_uuid())::text'
                                                       ELSE 'SELECT public.get_my_dating_matches()::text' END);
      SELECT d.last_seen_at INTO v_seen FROM public.dating_trusted_devices AS d WHERE d.user_id = u;
      RAISE EXCEPTION 'w6:postgrest_undo';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM IS DISTINCT FROM 'w6:postgrest_undo' THEN
        RAISE;
      END IF;
    END;
    IF v_seen IS DISTINCT FROM now() THEN
      v_bad := v_bad || (v_fn || CASE WHEN v_ro THEN ' (runs READ ONLY)' ELSE '' END);
    END IF;
  END LOOP;
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chat read, called as PostgREST calls it, never refreshes the phone''s last use: %', v_bad;
  END IF;
END $$;

-- =====================================================================
-- L. (§5.3, §5.10; carry 6) Open chats count a match under 7 days old or
--    one with a message in the last 14 days; the dragnet's first-message
--    input counts the matches the person wrote in.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('48');
  b constant uuid := pg_temp.ready('49', '{"identity": "man", "seeking": ["woman"]}');
  c constant uuid := pg_temp.ready('50', '{"identity": "man", "seeking": ["woman"]}');
  v_ab uuid;
  v_ac uuid;
  v_i uuid;
BEGIN
  v_i := pg_temp.intro(a, b);
  INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state, matched_at)
  VALUES (v_i, least(a, b), greatest(a, b), 'active', now() - interval '20 days') RETURNING id INTO v_ab;
  v_i := pg_temp.intro(a, c);
  INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state, matched_at)
  VALUES (v_i, least(a, c), greatest(a, c), 'active', now() - interval '20 days') RETURNING id INTO v_ac;
  IF private.dating_open_chats(a, now()) <> 0 OR private.dating_first_messages(a, now() - interval '1 day', clock_timestamp()) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two quiet 20-day-old matches count as open chats or as written in';
  END IF;
  PERFORM pg_temp.j(a, '48', format('SELECT public.send_dating_message(%L, %L, ''hello'')', pg_temp.key('l1'), v_ab));
  PERFORM pg_temp.j(c, '50', format('SELECT public.send_dating_message(%L, %L, ''hello'')', pg_temp.key('l2'), v_ac));
  IF private.dating_open_chats(a, now()) <> 2 OR private.dating_first_messages(a, now() - interval '1 day', clock_timestamp()) <> 1
     OR private.dating_first_messages(c, now() - interval '1 day', clock_timestamp()) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: open chats (%) or first messages (%) don''t read the messages',
      private.dating_open_chats(a, now()), private.dating_first_messages(a, now() - interval '1 day', clock_timestamp());
  END IF;
  UPDATE public.dating_messages SET created_at = now() - interval '15 days' WHERE match_id IN (v_ab, v_ac);
  IF private.dating_open_chats(a, now()) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chat quiet for 15 days still counts as open';
  END IF;
END $$;

-- =====================================================================
-- X1. (Task 2 fix round 1: I-1, M-10; spec §6.3) A swap offer needs what
--     a send needs: a held person's offer is refused (restricted) and,
--     when the other offered first, unmasks nothing; a pair blocked by
--     phone HMAC with the match still open can't offer (closed). Withdraw
--     reduces exposure, so neither the block nor the phone gates it; an
--     offer from another phone still answers reverify_device.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('53');
  b constant uuid := pg_temp.ready('54', '{"identity": "man", "seeking": ["woman"]}');
  c constant uuid := pg_temp.ready('55');
  e constant uuid := pg_temp.ready('56', '{"identity": "man", "seeking": ["woman"]}');
  v_ab uuid;
  v_ce uuid;
  v jsonb;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at)
  VALUES (least(a, b), greatest(a, b), 'active', now() - interval '4 days') RETURNING id INTO v_ab;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at)
  VALUES (least(c, e), greatest(c, e), 'active', now() - interval '4 days') RETURNING id INTO v_ce;
  PERFORM pg_temp.j(a, '53', format('SELECT public.send_dating_message(%L, %L, ''my snapchat is amab'')', pg_temp.key('x1s'), v_ab));
  v := pg_temp.j(b, '54', format('SELECT public.offer_dating_contact_swap(%L)', v_ab));
  IF v ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: b could not offer: %', v;
  END IF;
  UPDATE auth.users SET banned_until = now() + interval '1 day' WHERE id = a; -- held
  v := pg_temp.j(a, '53', format('SELECT public.offer_dating_contact_swap(%L)', v_ab));
  IF v IS DISTINCT FROM '{"ok": false, "reason": "restricted"}'::jsonb
     OR (SELECT CASE WHEN m.user_low_id = a THEN m.low_swap_at ELSE m.high_swap_at END FROM public.dating_matches AS m WHERE m.id = v_ab) IS NOT NULL
     OR pg_temp.j(b, '54', format('SELECT public.get_dating_messages(%L)', v_ab)) #>> '{messages,0,text}' IS DISTINCT FROM '•••'
     OR pg_temp.j(b, '54', format('SELECT public.get_dating_messages(%L)', v_ab)) #>> '{chat,swap,theirs}' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held person''s swap offer went through, or completed the other''s and unmasked the chat (I-1): %', v;
  END IF;
  UPDATE auth.users SET banned_until = NULL WHERE id = a;
  -- Blocked by phone HMAC, the match left open.
  v := pg_temp.j(c, '55', format('SELECT public.offer_dating_contact_swap(%L)', v_ce));
  INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
  VALUES (public.dating_phone_hmac_for_user(c), public.dating_phone_hmac_for_user(e));
  IF v ->> 'ok' IS DISTINCT FROM 'true'
     OR pg_temp.j(e, '56', format('SELECT public.offer_dating_contact_swap(%L)', v_ce)) IS DISTINCT FROM '{"ok": false, "reason": "closed"}'::jsonb
     OR pg_temp.j(c, '55', format('SELECT public.offer_dating_contact_swap(%L)', v_ce)) IS DISTINCT FROM '{"ok": false, "reason": "closed"}'::jsonb
     OR (SELECT CASE WHEN m.user_low_id = e THEN m.low_swap_at ELSE m.high_swap_at END FROM public.dating_matches AS m WHERE m.id = v_ce) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pair blocked by phone could offer a swap (I-1)';
  END IF;
  -- M-10: withdraw is ungated (another phone, and the block); an offer is not.
  -- Final server fix (M-2): from another phone it answers {ok} alone.
  v := pg_temp.call(c, pg_temp.dev('99'), format('SELECT public.withdraw_dating_contact_swap(%L)', v_ce))::jsonb;
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT CASE WHEN m.user_low_id = c THEN m.low_swap_at ELSE m.high_swap_at END FROM public.dating_matches AS m WHERE m.id = v_ce) IS NOT NULL
     OR pg_temp.call(b, pg_temp.dev('99'), format('SELECT public.offer_dating_contact_swap(%L)', v_ab))::jsonb ->> 'reason'
        IS DISTINCT FROM 'reverify_device' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw is gated by the phone or the block, or an offer from another phone is not (M-10): %', v;
  END IF;
END $$;

-- =====================================================================
-- X2. (Task 2 fix round 1: I-2, M-1; spec §4.10) With dating_match_messaging
--     off nobody can send or offer a swap (unavailable, fix round 1b: a
--     pause, never an end; the chat still reads active); withdraw, the reads,
--     Block and Unmatch still answer. A body made only of Unicode blank or
--     zero-width characters is invalid; words wrapped in them are a message.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('57');
  b constant uuid := pg_temp.ready('58', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_body text;
  v_bad text[] := '{}';
  v jsonb;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at)
  VALUES (least(a, b), greatest(a, b), 'active', now() - interval '4 days') RETURNING id INTO v_m;
  FOREACH v_body IN ARRAY ARRAY[E'\n\t \r', U&'\00A0', U&'\200B', U&'\200B\200C\200D', U&'\2060\FEFF', U&'\3164',
                                U&'\2800 \00A0', U&'\115F\1160', U&'\202F\205F\3000', U&'\00AD\034F\FE0F', U&'\200E\200F\2028\2029'] LOOP
    v := pg_temp.j(a, '57', format('SELECT public.send_dating_message(%L, %L, %L)', pg_temp.key('blank'), v_m, v_body));
    IF v ->> 'reason' IS DISTINCT FROM 'invalid' THEN
      v_bad := v_bad || (to_jsonb(v_body)::text || ' -> ' || v::text);
    END IF;
  END LOOP;
  IF cardinality(v_bad) > 0 OR EXISTS (SELECT 1 FROM public.dating_messages WHERE match_id = v_m) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a body of only blank or zero-width characters was taken (M-1): %', v_bad;
  END IF;
  v := pg_temp.j(a, '57', format('SELECT public.send_dating_message(%L, %L, %L)', pg_temp.key('wrapped'), v_m, U&'\200Bhi\00A0'));
  IF v ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: words wrapped in blank characters were refused: %', v;
  END IF;
  PERFORM pg_temp.j(a, '57', format('SELECT public.offer_dating_contact_swap(%L)', v_m));
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_match_messaging';
  IF pg_temp.j(b, '58', format('SELECT public.send_dating_message(%L, %L, ''hello'')', pg_temp.key('flagoff'), v_m))
       IS DISTINCT FROM '{"ok": false, "reason": "unavailable"}'::jsonb
     OR pg_temp.j(b, '58', format('SELECT public.offer_dating_contact_swap(%L)', v_m)) IS DISTINCT FROM '{"ok": false, "reason": "unavailable"}'::jsonb
     OR pg_temp.j(b, '58', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{chat,state}' IS DISTINCT FROM 'active'
     OR (SELECT count(*) FROM public.dating_messages WHERE match_id = v_m) <> 1
     OR (SELECT CASE WHEN m.user_low_id = b THEN m.low_swap_at ELSE m.high_swap_at END FROM public.dating_matches AS m WHERE m.id = v_m) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the chat flag off a message or a swap offer went through (I-2)';
  END IF;
  IF pg_temp.j(a, '57', format('SELECT public.withdraw_dating_contact_swap(%L)', v_m)) ->> 'ok' IS DISTINCT FROM 'true'
     OR pg_temp.j(b, '58', format('SELECT public.get_dating_messages(%L)', v_m)) ->> 'ok' IS DISTINCT FROM 'true'
     OR pg_temp.j(b, '58', 'SELECT public.get_my_dating_matches()') #>> '{conversations,0,match_id}' IS DISTINCT FROM v_m::text
     OR pg_temp.j(b, '58', format('SELECT public.block_dating_match(%L, %L)', pg_temp.key('flagblock'), v_m)) IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.j(a, '57', format('SELECT public.unmatch_dating_match(%L, %L)', pg_temp.key('flagunmatch'), v_m)) IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the chat flag off, withdraw, a read, Block or Unmatch was refused (I-2)';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_match_messaging';
END $$;

-- =====================================================================
-- X3. (Task 2 fix round 1: M-5, M-6, M-9) When the other person leaves,
--     the open chat is told (its signal bumped) and reads as ended, under
--     the ended list. Unmatch on a match a leave already closed still keeps
--     the pair's marker, once.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('59');
  b constant uuid := pg_temp.ready('71', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v jsonb;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at)
  VALUES (least(a, b), greatest(a, b), 'active', now() - interval '2 days') RETURNING id INTO v_m;
  PERFORM pg_temp.j(a, '59', format('SELECT public.send_dating_message(%L, %L, ''hello'')', pg_temp.key('x3s'), v_m));
  DELETE FROM public.dating_chat_signals WHERE match_id = v_m;
  v := pg_temp.j(b, '71', format('SELECT to_jsonb(public.exit_dating_mode(%L))', pg_temp.key('x3exit')));
  IF v ->> 'state' IS DISTINCT FROM 'exited' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: b could not leave: %', v;
  END IF;
  v := pg_temp.j(a, '59', 'SELECT public.get_my_dating_matches(true)');
  IF NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = a AND match_id = v_m)
     OR pg_temp.j(a, '59', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{chat,state}' IS DISTINCT FROM 'ended'
     OR jsonb_array_length(v -> 'conversations') <> 0 OR v #>> '{ended,0,match_id}' IS DISTINCT FROM v_m::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a leave did not tell the other''s open chat, or it does not read as ended (M-5): %', v;
  END IF;
  DELETE FROM public.dating_pair_markers
   WHERE pair_code = private.dating_pair_code(public.dating_phone_hmac_for_user(a), public.dating_phone_hmac_for_user(b));
  -- (Each call is made before the checks: a subquery in an IF can run first.)
  v := pg_temp.j(a, '59', format('SELECT public.unmatch_dating_match(%L, %L)', pg_temp.key('x3u1'), v_m))
       || pg_temp.j(a, '59', format('SELECT public.unmatch_dating_match(%L, %L)', pg_temp.key('x3u2'), v_m));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT count(*) FROM public.dating_pair_markers
          WHERE pair_code = private.dating_pair_code(public.dating_phone_hmac_for_user(a), public.dating_phone_hmac_for_user(b))) <> 1
     OR (SELECT state || '/' || closed_reason FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'closed/exit' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: unmatch on a match a leave closed kept no marker, or kept it twice, or rewrote the close (M-6)';
  END IF;
END $$;

-- =====================================================================
-- X4. (Task 2 fix round 1: M-5) An account deletion tells the other
--     person's open chat. A block of an old account whose number a new
--     account now holds (blocked by phone HMAC) ends the open chat with the
--     new account too: both are told, it reads as ended, it leaves the
--     conversations list, and a send answers closed.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('85');
  b constant uuid := pg_temp.ready('86', '{"identity": "man", "seeking": ["woman"]}');
  h constant uuid := pg_temp.ready('87');
  o constant uuid := pg_temp.ready('88', '{"identity": "man", "seeking": ["woman"]}');
  n constant uuid := pg_temp.ready('89', '{"identity": "man", "seeking": ["woman"]}');
  p constant uuid := pg_temp.ready('c2', '{"phone": "944"}');
  q constant uuid := pg_temp.ready('c3', '{"identity": "man", "seeking": ["woman"], "phone": "945"}');
  v_pq uuid;
  v_ab uuid;
  v_ho uuid;
  v_hn uuid;
  v jsonb;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_ab;
  PERFORM public.prepare_account_deletion(b);
  IF NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = a AND match_id = v_ab)
     OR pg_temp.j(a, '85', format('SELECT public.get_dating_messages(%L)', v_ab)) #>> '{chat,state}' IS DISTINCT FROM 'ended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account deletion did not tell the other''s open chat (M-5)';
  END IF;
  -- o's number now belongs to n (o parked, as after a fresh start).
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, closed_reason, closed_at, evidence_until)
  VALUES (least(h, o), greatest(h, o), 'unmatched', 'unmatched', now(), now() + interval '30 days') RETURNING id INTO v_ho;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(h, n), greatest(h, n), 'active') RETURNING id INTO v_hn;
  UPDATE public.users SET phone_released_at = now(), parked_phone_hmac = public.dating_phone_hmac_for_user(n) WHERE id = o;
  IF public.dating_phone_hmac_for_user(o) IS DISTINCT FROM public.dating_phone_hmac_for_user(n)
     OR (SELECT state FROM public.dating_matches WHERE id = v_hn) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: the parked account does not share the number, or the open match closed';
  END IF;
  v := pg_temp.j(h, '87', format('SELECT public.block_dating_match(%L, %L)', pg_temp.key('x4block'), v_ho));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = n AND match_id = v_hn)
     OR NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = h AND match_id = v_hn)
     OR pg_temp.j(n, '89', format('SELECT public.get_dating_messages(%L)', v_hn)) #>> '{chat,state}' IS DISTINCT FROM 'ended'
     OR pg_temp.j(h, '87', format('SELECT public.get_dating_messages(%L)', v_hn)) #>> '{chat,state}' IS DISTINCT FROM 'ended'
     OR jsonb_array_length(pg_temp.j(n, '89', 'SELECT public.get_my_dating_matches()') -> 'conversations') <> 0
     OR pg_temp.j(n, '89', format('SELECT public.send_dating_message(%L, %L, ''hi'')', pg_temp.key('x4send'), v_hn)) ->> 'reason'
        IS DISTINCT FROM 'closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a block by phone HMAC left the same number''s open chat looking open, or told nobody (M-5): %', v;
  END IF;
  -- Final server fix (M-3): a block now closes that match, so the header's
  -- and the list's own reading of a block by phone HMAC is pinned on a pair
  -- whose numbers became blocked with no block call (a changed number): the
  -- match is still active, and it reads ended and is in no list.
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(p, q), greatest(p, q), 'active') RETURNING id INTO v_pq;
  INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
  VALUES (public.dating_phone_hmac_for_user(q), public.dating_phone_hmac_for_user(p));
  IF pg_temp.j(p, 'c2', format('SELECT public.get_dating_messages(%L)', v_pq)) #>> '{chat,state}' IS DISTINCT FROM 'ended'
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(pg_temp.j(p, 'c2', 'SELECT public.get_my_dating_matches()') -> 'conversations') AS x
                 WHERE x ->> 'match_id' = v_pq::text) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an open match the numbers block by phone HMAC reads open or is listed (M-5)';
  END IF;
END $$;

-- =====================================================================
-- X5. (Task 2 fix round 1: M-9; R-36) Block and Unmatch answer from any
--     phone; after a block both read the chat as ended, under the ended
--     list, never as a conversation.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('90');
  b constant uuid := pg_temp.ready('91', '{"identity": "man", "seeking": ["woman"]}');
  c constant uuid := pg_temp.ready('92', '{"identity": "man", "seeking": ["woman"]}');
  v_ab uuid;
  v_ac uuid;
  v jsonb;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_ab;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, c), greatest(a, c), 'active') RETURNING id INTO v_ac;
  IF pg_temp.call(a, pg_temp.dev('99'), format('SELECT public.block_dating_match(%L, %L)', pg_temp.key('x5b'), v_ab))::jsonb
       IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.call(c, pg_temp.dev('99'), format('SELECT public.unmatch_dating_match(%L, %L)', pg_temp.key('x5u'), v_ac))::jsonb
       IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Block or Unmatch from another phone was refused (R-36)';
  END IF;
  v := pg_temp.j(b, '91', 'SELECT public.get_my_dating_matches(true)');
  IF pg_temp.j(b, '91', format('SELECT public.get_dating_messages(%L)', v_ab)) #>> '{chat,state}' IS DISTINCT FROM 'ended'
     OR pg_temp.j(a, '90', format('SELECT public.get_dating_messages(%L)', v_ab)) #>> '{chat,state}' IS DISTINCT FROM 'ended'
     OR jsonb_array_length(v -> 'conversations') <> 0 OR v #>> '{ended,0,match_id}' IS DISTINCT FROM v_ab::text
     OR jsonb_array_length(pg_temp.j(a, '90', 'SELECT public.get_my_dating_matches()') -> 'conversations') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after a block the chat does not read as ended for both (M-9): %', v;
  END IF;
END $$;

-- =====================================================================
-- X6. (Task 2 fix round 1: M-9; R-41) 500 messages a day per sender: the
--     500th is sent, the 501st answers rate_limited and stores nothing;
--     once the day has passed, sending works again.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('93');
  b constant uuid := pg_temp.ready('94', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v1 jsonb;
  v2 jsonb;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  INSERT INTO public.dating_rate_limits (user_id, operation, window_started_at, request_count)
  VALUES (a, 'dating_message', now(), 499);
  v1 := pg_temp.j(a, '93', format('SELECT public.send_dating_message(%L, %L, ''500th'')', pg_temp.key('x6a'), v_m));
  v2 := pg_temp.j(a, '93', format('SELECT public.send_dating_message(%L, %L, ''501st'')', pg_temp.key('x6b'), v_m));
  IF v1 ->> 'ok' IS DISTINCT FROM 'true' OR v2 IS DISTINCT FROM '{"ok": false, "reason": "rate_limited"}'::jsonb
     OR (SELECT count(*) FROM public.dating_messages WHERE match_id = v_m) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 500-a-day limit is not 500 (R-41): % then %', v1 ->> 'ok', v2;
  END IF;
  UPDATE public.dating_rate_limits SET window_started_at = now() - interval '1 day' WHERE user_id = a AND operation = 'dating_message';
  IF pg_temp.j(a, '93', format('SELECT public.send_dating_message(%L, %L, ''next day'')', pg_temp.key('x6c'), v_m)) ->> 'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the limit did not reset after a day (R-41)';
  END IF;
END $$;

-- =====================================================================
-- X7. (Task 2 fix round 1: M-7, M-8) Reading the newest page marks it seen
--     up to the newest incoming message it returned, so one written while
--     the page was read keeps its dot. First messages count only what was
--     written, in introductions made, by the run's time.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('95');
  b constant uuid := pg_temp.ready('96', '{"identity": "man", "seeking": ["woman"]}');
  c constant uuid := pg_temp.ready('97', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_ac uuid;
  v_i uuid;
  v jsonb;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  PERFORM pg_temp.j(b, '96', format('SELECT public.send_dating_message(%L, %L, ''one'')', pg_temp.key('x7a'), v_m));
  PERFORM pg_temp.j(b, '96', format('SELECT public.send_dating_message(%L, %L, ''two'')', pg_temp.key('x7b'), v_m));
  PERFORM pg_sleep(0.01);
  v := pg_temp.j(a, '95', format('SELECT public.get_dating_messages(%L)', v_m));
  IF (SELECT CASE WHEN m.user_low_id = a THEN m.low_seen_at ELSE m.high_seen_at END FROM public.dating_matches AS m WHERE m.id = v_m)
     IS DISTINCT FROM (v #>> '{messages,0,at}')::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the seen mark is not the newest incoming message the page returned (M-7)';
  END IF;
  INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, body, body_masked, mask_version, idempotency_key, created_at)
  VALUES (v_m, CASE WHEN b < a THEN 'low' ELSE 'high' END, b, 'three', 'three', 1, 'w6-x7-late',
          (v #>> '{messages,0,at}')::timestamptz + interval '1 millisecond');
  IF pg_temp.j(a, '95', 'SELECT public.get_my_dating_matches()') #>> '{conversations,0,new}' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a message written while the page was read lost its dot (M-7)';
  END IF;
  -- M-8: the run's time bounds both the introduction and the message.
  v_i := pg_temp.intro(a, c);
  UPDATE public.dating_introductions SET created_at = now() - interval '2 hours' WHERE id = v_i;
  INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state) VALUES (v_i, least(a, c), greatest(a, c), 'active')
  RETURNING id INTO v_ac;
  PERFORM pg_temp.j(a, '95', format('SELECT public.send_dating_message(%L, %L, ''hello'')', pg_temp.key('x7c'), v_ac));
  IF private.dating_first_messages(a, now() - interval '1 day', clock_timestamp()) <> 1
     OR private.dating_first_messages(a, now() - interval '1 day', now() - interval '1 hour') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: first messages counted a message written after the run''s time (M-8)';
  END IF;
  UPDATE public.dating_messages SET created_at = now() - interval '3 hours' WHERE match_id = v_ac;
  IF private.dating_first_messages(a, now() - interval '1 day', now() - interval '2 hours 1 minute') <> 0
     OR private.dating_first_messages(a, now() - interval '1 day', now() - interval '1 hour') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: first messages counted an introduction made after the run''s time (M-8)';
  END IF;
END $$;

-- =====================================================================
-- X8. (Task 2 fix round 1b: carry 6) Every path that closes a match tells
--     both members' open chats: a move to a country without same-gender
--     matching, a same-gender switch, an age review.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('98', '{"country": "GB", "region": "TLI", "seeking": ["woman"]}');
  b constant uuid := pg_temp.ready('00', '{"seeking": ["woman"]}');
  v_m uuid;
  v jsonb;
  v_bad text[] := '{}';
BEGIN
  -- The move (a, the UK to Ghana, where same-gender matching is off).
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  v := pg_temp.j(a, '98', format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''region'')', pg_temp.key('x8move')));
  IF v ->> 'ok' IS DISTINCT FROM 'true' OR (SELECT state || '/' || closed_reason FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'closed/other' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: the move did not close the same-gender match (%)', v;
  END IF;
  IF (SELECT count(*) FROM public.dating_chat_signals WHERE match_id = v_m AND user_id IN (a, b)) <> 2 THEN
    v_bad := v_bad || 'the move'::text;
  END IF;
  -- The switch (both now in Ghana).
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  PERFORM public.apply_same_gender_switch('GH');
  IF (SELECT state || '/' || closed_reason FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'closed/other' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: the switch did not close the same-gender match';
  END IF;
  IF (SELECT count(*) FROM public.dating_chat_signals WHERE match_id = v_m AND user_id IN (a, b)) <> 2 THEN
    v_bad := v_bad || 'the switch'::text;
  END IF;
  -- The age review (b).
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  PERFORM public.invalidate_dating_for_user(b, 'age_review');
  IF (SELECT state || '/' || closed_reason FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'closed/age_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: the age review did not close the match';
  END IF;
  IF (SELECT count(*) FROM public.dating_chat_signals WHERE match_id = v_m AND user_id IN (a, b)) <> 2 THEN
    v_bad := v_bad || 'the age review'::text;
  END IF;
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match closed without telling both members'' open chats (carry 6): %', v_bad;
  END IF;
END $$;

\set lexicon `cat supabase/functions/_shared/dating_chat_lexicon_v1.json`
SELECT length(set_config('w6.lexicon', :'lexicon', true)) AS lexicon_loaded \gset
-- The worker's claim, made to take [p_msg] (every other pending message
-- waits behind it).
CREATE FUNCTION pg_temp.claim_only(p_msg uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.dating_message_safety_outbox SET created_at = clock_timestamp() + interval '1 day'
   WHERE state = 'pending' AND message_id <> p_msg;
  PERFORM 1 FROM public.claim_dating_safety_jobs(1);
END $$;

-- =====================================================================
-- M. (§6.1, §3.13; chat spec §2.3, §6, §9) A send queues its message for
--    the worker in the chat's own outbox (never the couples one) and a
--    neutral push for the recipient (me_update, no name, no text): at
--    most one per 15 minutes, none with "messages" off; without the push
--    key the message is still delivered and the push counted as failed.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('60');
  b constant uuid := pg_temp.ready('61', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_couples bigint := (SELECT count(*) FROM public.message_safety_outbox);
  v_failed bigint;
  v_ok text;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Hello Kofi'')', pg_temp.key('o1'), v_m));
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Are you there?'')', pg_temp.key('o2'), v_m));
  IF (SELECT count(*) FROM public.dating_message_safety_outbox AS o JOIN public.dating_messages AS d ON d.id = o.message_id
       WHERE d.match_id = v_m AND o.state = 'pending' AND o.attempts = 0) <> 2
     OR (SELECT count(*) FROM public.message_safety_outbox) <> v_couples THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a send did not queue its message for the chat''s worker, or reached the couples outbox';
  END IF;
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b) <> 1
     OR (SELECT metadata FROM public.scheduled_notifications WHERE user_id = b)
        IS DISTINCT FROM '{"type": "me_update", "route": "me", "title": "Attune", "body": "You have something new in Attune."}'::jsonb
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the message push is not one neutral me_update for the recipient (per 15 minutes)';
  END IF;
  DELETE FROM public.scheduled_notifications WHERE user_id = b;
  INSERT INTO public.dating_settings (user_id, chat_push) VALUES (b, false)
  ON CONFLICT (user_id) DO UPDATE SET chat_push = false;
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Still there?'')', pg_temp.key('o3'), v_m));
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = b) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a push was queued with "messages" off';
  END IF;
  UPDATE public.dating_settings SET chat_push = true WHERE user_id = b;
  v_failed := pg_temp.metric('dating.chat.push_failed');
  PERFORM set_config('app.settings.dating_push_key', '', true);
  v_ok := pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''No key'')', pg_temp.key('o4'), v_m)) ->> 'ok';
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w6-push-key', true);
  IF v_ok IS DISTINCT FROM 'true' OR pg_temp.metric('dating.chat.push_failed') <> v_failed + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the push key the message was not delivered, or the failed push not counted';
  END IF;
END $$;

-- =====================================================================
-- N. (§6.1, §4.3; chat spec §3.2, §9) The worker's calls. A claim moves
--    pending messages to processing (one more attempt) and is the one way
--    a body leaves the database (the service role's alone); a completion
--    writes each hit as an event for the recipient only, once per message
--    and rule, never the text; tier 2 and 3 open a case about the sender;
--    malformed hits are refused; an error goes back to pending, then to
--    dead_letter after the 5th attempt (counted); with no config the
--    message is done with no events (counted); a stale claim is recovered.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('62');
  b constant uuid := pg_temp.ready('63', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_msg uuid;
  v_claim record;
  v jsonb;
  v_n bigint;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at)
  VALUES (least(a, b), greatest(a, b), 'active', now() - interval '3 days') RETURNING id INTO v_m;
  v_msg := (pg_temp.j(b, '63', format('SELECT public.send_dating_message(%L, %L, ''send me momo for transport'')', pg_temp.key('n1'), v_m))
            #>> '{message,id}')::uuid;
  UPDATE public.dating_message_safety_outbox SET created_at = clock_timestamp() + interval '1 day'
   WHERE state = 'pending' AND message_id <> v_msg;
  IF has_function_privilege('authenticated', 'public.claim_dating_safety_jobs(integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.complete_dating_safety_job(uuid,text,jsonb,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.claim_dating_safety_jobs(integer)', 'EXECUTE')
     OR has_table_privilege('service_role', 'public.dating_messages', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the worker''s calls are not the service role''s alone, or it reads messages directly';
  END IF;
  SELECT * INTO v_claim FROM public.claim_dating_safety_jobs(1);
  IF v_claim.message_id IS DISTINCT FROM v_msg OR v_claim.body IS DISTINCT FROM 'send me momo for transport' OR NOT v_claim.new_match
     OR (SELECT state || ':' || attempts FROM public.dating_message_safety_outbox WHERE message_id = v_msg) IS DISTINCT FROM 'processing:1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the claim did not hand over the oldest message as processing (%)', v_claim;
  END IF;
  IF public.complete_dating_safety_job(v_msg, 'dating_chat_v1', '[{"rule_id": "x", "family": "couples_control", "tier": 1}]') ->> 'reason'
     IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hit of an unknown family was taken';
  END IF;
  v := public.complete_dating_safety_job(v_msg, 'dating_chat_v1',
         '[{"rule_id": "financial_request:send me momo", "family": "financial_request", "tier": 2},
           {"rule_id": "age_signal:i m 16", "family": "age_signal", "tier": 3}]');
  IF v IS DISTINCT FROM '{"ok": true, "state": "done", "events": 2}'::jsonb
     OR (SELECT array_agg(e.family || ':' || (e.at_risk_user_id = a)::text || ':' || (e.sender_user_id = b)::text ORDER BY e.family)
           FROM public.dating_safety_events AS e WHERE e.message_id = v_msg)
        IS DISTINCT FROM ARRAY['age_signal:true:true', 'financial_request:true:true']
     OR (SELECT array_agg(c.signal_kind || ':' || c.priority ORDER BY c.signal_kind) FROM public.dating_moderation_cases AS c
          WHERE c.target_user_id = b) IS DISTINCT FROM ARRAY['chat_age_signal:P1', 'chat_financial_request:P1'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the completion answered % (events for the recipient, cases about the sender)', v;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'dating_safety_events'
               AND column_name ~ '(body|text|message_text|content)') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the events can hold message text';
  END IF;
  -- An error: back to pending; the 5th attempt dead-letters, counted.
  v_msg := (pg_temp.j(b, '63', format('SELECT public.send_dating_message(%L, %L, ''hello again'')', pg_temp.key('n2'), v_m))
            #>> '{message,id}')::uuid;
  v_n := pg_temp.metric('dating.safety.dead_letter');
  FOR i IN 1..5 LOOP
    PERFORM pg_temp.claim_only(v_msg);
    v := public.complete_dating_safety_job(v_msg, 'dating_chat_v1', '[]', 'engine_error');
  END LOOP;
  IF v IS DISTINCT FROM '{"ok": true, "state": "dead_letter"}'::jsonb OR pg_temp.metric('dating.safety.dead_letter') <> v_n + 1
     OR (SELECT state || ':' || last_error_code FROM public.dating_message_safety_outbox WHERE message_id = v_msg)
        IS DISTINCT FROM 'dead_letter:engine_error' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: five failed attempts did not dead-letter (counted): %', v;
  END IF;
  -- No config: done, no events, counted.
  v_msg := (pg_temp.j(b, '63', format('SELECT public.send_dating_message(%L, %L, ''send me momo'')', pg_temp.key('n3'), v_m))
            #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  v_n := pg_temp.metric('dating.safety.no_config');
  v := public.complete_dating_safety_job(v_msg, NULL, '[]');
  IF v IS DISTINCT FROM '{"ok": true, "state": "done", "events": 0}'::jsonb
     OR pg_temp.metric('dating.safety.no_config') <> v_n + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with no config the message was not done with no events (counted)';
  END IF;
  -- A stale claim comes back.
  v_msg := (pg_temp.j(b, '63', format('SELECT public.send_dating_message(%L, %L, ''one more'')', pg_temp.key('n4'), v_m))
            #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  UPDATE public.dating_message_safety_outbox SET processing_started_at = now() - interval '11 minutes' WHERE message_id = v_msg;
  v_n := public.recover_stale_dating_safety_jobs(); -- its own statement first (an IF's OR has no order)
  IF v_n < 1 OR (SELECT state FROM public.dating_message_safety_outbox WHERE message_id = v_msg) IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stale claim was not recovered';
  END IF;
END $$;

-- =====================================================================
-- O. (§3.6 Safety cards, §6.1; chat spec §1.2) The cards are the
--    recipient's alone (never the sender's, nobody else's, not on another
--    phone), tier 1 and 2 only; a threat card names the country's
--    emergency resource; a dismissed card is gone and later detection is
--    unchanged.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('64');
  b constant uuid := pg_temp.ready('65', '{"identity": "man", "seeking": ["woman"]}');
  o constant uuid := pg_temp.ready('66');
  v_m uuid;
  v_msg uuid;
  v jsonb;
BEGIN
  INSERT INTO public.support_resources (id, country_code, category, name, phone, verified_at, verified_by, catalogue_version)
  VALUES (gen_random_uuid(), 'GH', 'emergency', 'Ghana emergency', '112', current_date, 'contract', 'w6-contract');
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  v_msg := (pg_temp.j(b, '65', format('SELECT public.send_dating_message(%L, %L, ''I know where you live'')', pg_temp.key('o1'), v_m))
            #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  PERFORM public.complete_dating_safety_job(v_msg, 'dating_chat_v1',
    '[{"rule_id": "threat_intimidation:i know where you live", "family": "threat_intimidation", "tier": 2},
      {"rule_id": "identity_inconsistency:my late wife", "family": "identity_inconsistency", "tier": 3}]');
  v := pg_temp.j(a, '64', format('SELECT public.get_my_dating_safety_cards(%L)', v_m));
  IF jsonb_array_length(v -> 'cards') <> 1 OR v #>> '{cards,0,family}' IS DISTINCT FROM 'threat_intimidation'
     OR v #>> '{cards,0,message_id}' IS DISTINCT FROM v_msg::text
     OR v #> '{cards,0,resource}' IS DISTINCT FROM '{"sms": null, "url": null, "name": "Ghana emergency", "phone": "112"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the recipient''s cards are %', v;
  END IF;
  IF pg_temp.j(b, '65', format('SELECT public.get_my_dating_safety_cards(%L)', v_m)) IS DISTINCT FROM '{"ok": true, "cards": []}'::jsonb
     OR pg_temp.j(o, '66', format('SELECT public.get_my_dating_safety_cards(%L)', v_m)) IS DISTINCT FROM '{"ok": true, "cards": []}'::jsonb
     OR pg_temp.call(a, pg_temp.dev('99'), format('SELECT public.get_my_dating_safety_cards(%L)', v_m))::jsonb ->> 'reason'
        IS DISTINCT FROM 'reverify_device' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sender, an outsider or another phone saw a card';
  END IF;
  PERFORM pg_temp.j(o, '66', format('SELECT public.dismiss_dating_safety_card(%L)', v #>> '{cards,0,id}'));
  IF jsonb_array_length(pg_temp.j(a, '64', format('SELECT public.get_my_dating_safety_cards(%L)', v_m)) -> 'cards') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone else dismissed the recipient''s card';
  END IF;
  PERFORM pg_temp.j(a, '64', format('SELECT public.dismiss_dating_safety_card(%L)', v #>> '{cards,0,id}'));
  v_msg := (pg_temp.j(b, '65', format('SELECT public.send_dating_message(%L, %L, ''watch your back'')', pg_temp.key('o2'), v_m))
            #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  PERFORM public.complete_dating_safety_job(v_msg, 'dating_chat_v1',
    '[{"rule_id": "threat_intimidation:watch your back", "family": "threat_intimidation", "tier": 2}]');
  v := pg_temp.j(a, '64', format('SELECT public.get_my_dating_safety_cards(%L)', v_m));
  IF jsonb_array_length(v -> 'cards') <> 1 OR v #>> '{cards,0,message_id}' IS DISTINCT FROM v_msg::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dismissal hid a later card, or kept the dismissed one: %', v;
  END IF;
END $$;

-- =====================================================================
-- P. (§5.10; carry 8) The sender's repeated patterns open signal cases:
--    money asks to two recipients in 7 days (P1), sexual pressure to two,
--    the same opener in three matches in 7 days; two matches alone don't.
--    Never a restriction (chat spec §5.1).
-- =====================================================================
DO $$
DECLARE
  s constant uuid := pg_temp.ready('67', '{"identity": "man", "seeking": ["woman"]}');
  r1 constant uuid := pg_temp.ready('68');
  r2 constant uuid := pg_temp.ready('69');
  r3 constant uuid := pg_temp.ready('70');
  v_m uuid[] := '{}';
  v_msg uuid;
  x uuid;
  i integer := 0;
BEGIN
  FOREACH x IN ARRAY ARRAY[r1, r2, r3] LOOP
    INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(s, x), greatest(s, x), 'active');
    v_m := v_m || (SELECT id FROM public.dating_matches WHERE pair_key = public.dating_pair_key(s, x));
  END LOOP;
  FOREACH x IN ARRAY v_m LOOP
    i := i + 1;
    v_msg := (pg_temp.j(s, '67', format('SELECT public.send_dating_message(%L, %L, ''Hello dear, how was your day?'')', pg_temp.key('p' || i), x))
              #>> '{message,id}')::uuid;
    PERFORM pg_temp.claim_only(v_msg);
    PERFORM public.complete_dating_safety_job(v_msg, 'dating_chat_v1', CASE WHEN i <= 2 THEN
      '[{"rule_id": "financial_request:gift card", "family": "financial_request", "tier": 2},
        {"rule_id": "sexual_pressure:send nudes", "family": "sexual_pressure", "tier": 1}]'::jsonb ELSE '[]'::jsonb END);
    IF i = 2 AND EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE target_user_id = s AND signal_kind = 'duplicate_opener') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the same opener in two matches opened a case';
    END IF;
  END LOOP;
  IF (SELECT array_agg(c.signal_kind || ':' || c.priority ORDER BY c.signal_kind) FROM public.dating_moderation_cases AS c
       WHERE c.target_user_id = s AND c.signal_kind IN ('money_asks', 'sexual_pressure', 'duplicate_opener'))
     IS DISTINCT FROM ARRAY['duplicate_opener:P2', 'money_asks:P1', 'sexual_pressure:P2']
     OR EXISTS (SELECT 1 FROM public.dating_account_restrictions WHERE user_id = s) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the repeated signals are % (or a restriction followed)',
      (SELECT array_agg(c.signal_kind || ':' || c.priority ORDER BY c.signal_kind) FROM public.dating_moderation_cases AS c WHERE c.target_user_id = s);
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_opener_hashes WHERE hash !~ '^[0-9a-f]{64}$')
     OR (SELECT count(*) FROM public.dating_opener_hashes WHERE sender_user_id = s) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the openers are not kept as one keyed hash per match';
  END IF;
END $$;

-- =====================================================================
-- Q. (§6.1 lexicon, §4.3; W5 final M-7) The config: the v1 lexicon is the
--    reviewed file, every term in Spec 1's match form (age_signal in its
--    base form), seeded as a draft; one active version at a time; an
--    active version can't be edited; its hash is its config's; in
--    production a DEV- reference can't activate it.
-- =====================================================================
DO $$
DECLARE
  v_lex constant jsonb := current_setting('w6.lexicon')::jsonb;
  v_bad text;
BEGIN
  IF (SELECT config FROM public.dating_safety_configs WHERE version = 'dating_chat_v1') IS DISTINCT FROM v_lex THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the seeded lexicon is not supabase/functions/_shared/dating_chat_lexicon_v1.json';
  END IF;
  SELECT string_agg(f.key || ': ' || t.term, ', ') INTO v_bad
    FROM jsonb_each(v_lex -> 'families') AS f,
         LATERAL jsonb_array_elements_text((f.value -> 'terms') || coalesce(f.value -> 'new_match_terms', '[]')) AS t(term)
   WHERE t.term IS DISTINCT FROM CASE WHEN f.value ->> 'form' = 'base' THEN private.normalize_for_filter(t.term)
                                      ELSE private.match_form(t.term) END;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: lexicon terms not in their stored form: %', v_bad;
  END IF;
  IF pg_temp.probe(ARRAY['UPDATE public.dating_safety_configs SET state = ''retired'' WHERE state = ''active''',
                         'INSERT INTO public.dating_safety_configs (version, state, config, config_hash, review_ref, activated_at)
                          SELECT ''w6_a'', ''active'', c.config, c.config_hash, ''DEV-safety'', now() FROM public.dating_safety_configs AS c WHERE c.version = ''dating_chat_v1'''],
       'SELECT count(*)::text FROM public.dating_safety_configs WHERE state = ''active''') <> '1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: activating a config did not leave exactly one active';
  END IF;
  BEGIN
    UPDATE public.dating_safety_configs SET state = 'retired' WHERE state = 'active';
    UPDATE public.dating_safety_configs SET state = 'active', review_ref = 'DEV-safety', activated_at = now() WHERE version = 'dating_chat_v1';
    UPDATE public.dating_safety_configs
       SET config = config || '{"x": 1}', config_hash = encode(extensions.digest((config || '{"x": 1}')::text, 'sha256'), 'hex')
     WHERE version = 'dating_chat_v1';
    RAISE EXCEPTION 'CONTRACT VIOLATED: an active config was edited';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM IS DISTINCT FROM 'config:active_frozen' THEN
      RAISE;
    END IF;
  END;
  BEGIN
    PERFORM set_config('app.settings.attune_environment', 'production', true);
    UPDATE public.dating_safety_configs SET state = 'retired' WHERE state = 'active';
    UPDATE public.dating_safety_configs SET state = 'active', review_ref = ' dev-safety', activated_at = now() WHERE version = 'dating_chat_v1';
    RAISE EXCEPTION 'CONTRACT VIOLATED: production activated a config with a DEV- reference';
  EXCEPTION WHEN check_violation THEN
    PERFORM set_config('app.settings.attune_environment', '', true);
    IF SQLERRM IS DISTINCT FROM 'config:dev_review_ref' THEN
      RAISE;
    END IF;
  END;
  BEGIN
    INSERT INTO public.dating_safety_configs (version, config, config_hash) VALUES ('w6_bad', '{}', 'nope');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a config was stored with a hash that is not its own';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM IS DISTINCT FROM 'config:hash_mismatch' THEN
      RAISE;
    END IF;
  END;
END $$;

-- =====================================================================
-- R. (Task 5 rulings; §6.1, §4.6, §3.13, R-42) The worker's calls hold
--    against a worker that is wrong: a completion with a non-array, a hit
--    with no family, a tier that is not its family's in that version, or
--    a version that names no config is refused as invalid (never a raise
--    that holds the message), and the message stays claimed; a stale
--    claim already tried 5 times dead-letters (counted); "new match"
--    follows the active config's new_match_days; the message push is at
--    most one per 15 minutes across a quarter-hour boundary; the two
--    crons are scheduled. People from M and N are reused (no new range).
-- =====================================================================
-- A completion's answer, or 'raised:<message>' when it raises.
CREATE FUNCTION pg_temp.done(p_msg uuid, p_version text, p_hits jsonb) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  RETURN public.complete_dating_safety_job(p_msg, p_version, p_hits)::text;
EXCEPTION WHEN OTHERS THEN
  RETURN 'raised:' || SQLERRM;
END $$;
-- Claims [p_msg] alone and answers its new_match.
CREATE FUNCTION pg_temp.claim_new_match(p_msg uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v boolean;
BEGIN
  UPDATE public.dating_message_safety_outbox SET created_at = clock_timestamp() + interval '1 day'
   WHERE state = 'pending' AND message_id <> p_msg;
  SELECT c.new_match INTO v FROM public.claim_dating_safety_jobs(1) AS c WHERE c.message_id = p_msg;
  RETURN coalesce(v::text, '<none>');
END $$;

DO $$
DECLARE
  a constant uuid := pg_temp.id('62');
  b constant uuid := pg_temp.id('63');
  v_m constant uuid := (SELECT id FROM public.dating_matches WHERE pair_key = public.dating_pair_key(pg_temp.id('62'), pg_temp.id('63')));
  v_msg uuid;
  v_bad text[] := '{}';
  v text;
  v_n bigint;
  v_r integer;
BEGIN
  v_msg := (pg_temp.j(b, '63', format('SELECT public.send_dating_message(%L, %L, ''send me momo please'')', pg_temp.key('r1'), v_m))
            #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  v := pg_temp.done(v_msg, 'dating_chat_v1', '{"rule_id": "x"}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "invalid"}' THEN v_bad := v_bad || ('object: ' || v); END IF;
  v := pg_temp.done(v_msg, 'dating_chat_v1', '[{"rule_id": "financial_request:momo", "tier": 2}]');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "invalid"}' THEN v_bad := v_bad || ('no family: ' || v); END IF;
  v := pg_temp.done(v_msg, 'dating_chat_v1', '[{"rule_id": "financial_request:momo", "family": "financial_request", "tier": 1}]');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "invalid"}' THEN v_bad := v_bad || ('tier not the family''s: ' || v); END IF;
  v := pg_temp.done(v_msg, 'w6_no_such_config', '[]');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "invalid"}' THEN v_bad := v_bad || ('unknown version: ' || v); END IF;
  IF cardinality(v_bad) > 0
     OR (SELECT state FROM public.dating_message_safety_outbox WHERE message_id = v_msg) IS DISTINCT FROM 'processing'
     OR EXISTS (SELECT 1 FROM public.dating_safety_events WHERE message_id = v_msg) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed completion was not refused as invalid (message kept claimed): %', v_bad;
  END IF;
  -- A stale claim tried 5 times: dead_letter, counted.
  v_n := pg_temp.metric('dating.safety.dead_letter');
  UPDATE public.dating_message_safety_outbox SET attempts = 5, processing_started_at = now() - interval '11 minutes'
   WHERE message_id = v_msg;
  v_r := public.recover_stale_dating_safety_jobs();
  IF v_r < 1 OR (SELECT state || ':' || last_error_code FROM public.dating_message_safety_outbox WHERE message_id = v_msg)
                 IS DISTINCT FROM 'dead_letter:stale_claim'
     OR pg_temp.metric('dating.safety.dead_letter') <> v_n + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stale claim tried 5 times did not dead-letter (counted)';
  END IF;
  -- "New match" follows the active config: 2 days, and this match is 3 days old.
  v_msg := (pg_temp.j(b, '63', format('SELECT public.send_dating_message(%L, %L, ''hi'')', pg_temp.key('r2'), v_m))
            #>> '{message,id}')::uuid;
  v := pg_temp.probe(ARRAY['UPDATE public.dating_safety_configs SET state = ''retired'' WHERE state = ''active''',
                           'INSERT INTO public.dating_safety_configs (version, state, config, config_hash, review_ref, activated_at)
                            SELECT ''w6_days'', ''active'', c.config || ''{"new_match_days": 2}'',
                                   encode(extensions.digest((c.config || ''{"new_match_days": 2}'')::text, ''sha256''), ''hex''),
                                   ''DEV-safety'', now()
                              FROM public.dating_safety_configs AS c WHERE c.version = ''dating_chat_v1'''],
                     format('SELECT pg_temp.claim_new_match(%L)', v_msg));
  IF v IS DISTINCT FROM 'false' OR pg_temp.claim_new_match(v_msg) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "new match" does not follow the active config''s new_match_days (2 days: %)', v;
  END IF;
END $$;

-- The push across a quarter-hour boundary (R-42): the previous quarter's
-- push sent under 15 minutes ago holds this one to the end of its window
-- (final server fix, I-6: delayed, never dropped); at 16 minutes it pushes
-- at once.
DO $$
DECLARE
  a constant uuid := pg_temp.id('60');
  b constant uuid := pg_temp.id('61');
  v_m constant uuid := (SELECT id FROM public.dating_matches WHERE pair_key = public.dating_pair_key(pg_temp.id('60'), pg_temp.id('61')));
  v_q constant bigint := floor(extract(epoch FROM now()) / 900)::bigint;
  v_first text;
BEGIN
  DELETE FROM public.scheduled_notifications WHERE user_id = b;
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  VALUES (b, 'immediate', now() - interval '1 minute', 'sent',
          '{"type": "me_update", "route": "me", "title": "Attune", "body": "You have something new in Attune."}',
          private.dating_push_source_key(b, 'chat:' || (v_q - 1)::text, (to_timestamp((v_q - 1) * 900) AT TIME ZONE 'UTC')::date),
          now() - interval '1 minute', now());
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Boundary one'')', pg_temp.key('r3'), v_m));
  v_first := (SELECT string_agg(status || '@' || CASE WHEN scheduled_for = now() + interval '15 minutes' THEN 'window_end' ELSE scheduled_for::text END,
                                ',' ORDER BY status) FROM public.scheduled_notifications WHERE user_id = b AND status <> 'sent');
  DELETE FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending';
  UPDATE public.scheduled_notifications SET created_at = now() - interval '16 minutes',
         updated_at = now() - interval '16 minutes' WHERE user_id = b; -- fix round 4: queued and sent 16 minutes ago
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Boundary two'')', pg_temp.key('r4'), v_m));
  IF v_first IS DISTINCT FROM 'pending@window_end'
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending' AND scheduled_for <= now()) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the message push is not at most one per 15 minutes across a quarter hour, delayed to the window''s end (% then %)',
      v_first, (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending' AND scheduled_for <= now());
  END IF;
END $$;

-- The crons (§4.6), where pg_cron is installed.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron')
     AND (SELECT string_agg(j.jobname || '|' || j.schedule || '|' || j.command, ', ' ORDER BY j.jobname) FROM cron.job AS j
           WHERE j.jobname IN ('process-dating-safety-outbox', 'recover-stale-dating-workers'))
         IS DISTINCT FROM 'process-dating-safety-outbox|* * * * *|SELECT public.invoke_edge_function(''process-dating-safety-outbox'') WHERE EXISTS (SELECT 1 FROM public.dating_message_safety_outbox WHERE state = ''pending''), ' -- final server fix (M-7)
                          || 'recover-stale-dating-workers|*/5 * * * *|SELECT public.recover_stale_dating_safety_jobs()' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the chat safety crons are not the worker every minute (only while a message waits, M-7) and the recovery every 5';
  END IF;
END $$;

-- =====================================================================
-- S. (Task 5 fix round 1: I-1, M-1, M-2, M-5, M-7, M-9, M-10, M-11)
--    A completion is once (a second call answers not_claimed and writes
--    nothing); a hit's rule_id is its family and one of that version's
--    terms, never free text; health shows the chat's outbox, config,
--    events and counters; the sender's pattern cases open only on
--    evidence the completion added and never on evidence a moderator
--    cleared, on the match that holds the event; a recipient's deletion
--    keeps the evidence (and a hit to a deleted recipient still opens the
--    case about the sender); the config guard runs as its owner; a
--    message push is skipped at delivery once nothing is unread. People
--    from M-R are reused (no new range).
-- =====================================================================
-- S1 (M-2) and S2 (M-5).
DO $$
DECLARE
  a constant uuid := pg_temp.id('62');
  b constant uuid := pg_temp.id('63');
  v_m constant uuid := (SELECT id FROM public.dating_matches WHERE pair_key = public.dating_pair_key(pg_temp.id('62'), pg_temp.id('63')));
  v_done uuid;
  v_n bigint;
  v_msg uuid;
  v_bad text[] := '{}';
  v text;
  v2 text;
BEGIN
  SELECT o.message_id INTO v_done FROM public.dating_message_safety_outbox AS o
    JOIN public.dating_messages AS d ON d.id = o.message_id
   WHERE d.match_id = v_m AND o.state = 'done'
     AND EXISTS (SELECT 1 FROM public.dating_safety_events AS e WHERE e.message_id = o.message_id)
   LIMIT 1;
  v_n := (SELECT count(*) FROM public.dating_safety_events);
  v := pg_temp.done(v_done, 'dating_chat_v1', '[{"rule_id": "financial_request:send me momo", "family": "financial_request", "tier": 2}]');
  v2 := pg_temp.done(v_done, 'dating_chat_v1', '[{"rule_id": "sextortion:expose you", "family": "sextortion", "tier": 2}]');
  IF v_done IS NULL OR v IS DISTINCT FROM '{"ok": false, "reason": "not_claimed"}' OR v2 IS DISTINCT FROM '{"ok": false, "reason": "not_claimed"}'
     OR (SELECT count(*) FROM public.dating_safety_events) <> v_n
     OR (SELECT state FROM public.dating_message_safety_outbox WHERE message_id = v_done) IS DISTINCT FROM 'done' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a done message was completed again (% / %)', v, v2;
  END IF;
  v_msg := (pg_temp.j(b, '63', format('SELECT public.send_dating_message(%L, %L, ''hello there'')', pg_temp.key('s2'), v_m))
            #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  v := pg_temp.done(v_msg, 'dating_chat_v1', '[{"rule_id": "financial_request:send me momo 0244 123 456", "family": "financial_request", "tier": 2}]');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "invalid"}' THEN v_bad := v_bad || ('free text: ' || v); END IF;
  v := pg_temp.done(v_msg, 'dating_chat_v1', '[{"rule_id": "financial_request:send nudes", "family": "financial_request", "tier": 2}]');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "invalid"}' THEN v_bad := v_bad || ('another family''s term: ' || v); END IF;
  v := pg_temp.done(v_msg, 'dating_chat_v1', '[{"rule_id": "send me momo", "family": "financial_request", "tier": 2}]');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "invalid"}' THEN v_bad := v_bad || ('no family prefix: ' || v); END IF;
  IF cardinality(v_bad) > 0 OR EXISTS (SELECT 1 FROM public.dating_safety_events WHERE message_id = v_msg) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hit whose rule_id is not its family and a term of the version was taken: %', v_bad;
  END IF;
  -- A first-14-days term is one of the version's terms too.
  v := pg_temp.done(v_msg, 'dating_chat_v1', '[{"rule_id": "financial_request:momo", "family": "financial_request", "tier": 2}]');
  IF v IS DISTINCT FROM '{"ok": true, "state": "done", "events": 1}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hit naming a first-14-days term was refused: %', v;
  END IF;
END $$;

-- S3 (M-1, M-10): health.
DO $$
DECLARE
  h constant jsonb := public.get_dating_operational_health();
BEGIN
  IF NOT (h ?& ARRAY['chat_safety_outbox', 'chat_safety_config_active', 'chat_safety_events_24h'])
     OR NOT ((h -> 'safety_counters_7d') ?& ARRAY['dating.pair_marker.unwritten', 'dating.safety.no_config', 'dating.safety.dead_letter',
                                                  'dating.chat.push_failed', 'dating.chat.push_read'])
     OR (h #>> '{chat_safety_outbox,dead_letter}')::bigint IS DISTINCT FROM
        (SELECT count(*) FROM public.dating_message_safety_outbox WHERE state = 'dead_letter')
     OR (h #>> '{chat_safety_outbox,dead_letter}')::bigint < 2
     OR (h #>> '{chat_safety_outbox,pending}')::bigint IS DISTINCT FROM
        (SELECT count(*) FROM public.dating_message_safety_outbox WHERE state = 'pending')
     OR (h #>> '{chat_safety_outbox,processing}')::bigint IS DISTINCT FROM
        (SELECT count(*) FROM public.dating_message_safety_outbox WHERE state = 'processing')
     OR (h #>> '{chat_safety_events_24h,financial_request}')::bigint IS DISTINCT FROM
        (SELECT count(*) FROM public.dating_safety_events WHERE family = 'financial_request' AND created_at >= now() - interval '24 hours')
     OR (h -> 'chat_safety_config_active') IS DISTINCT FROM
        coalesce((SELECT to_jsonb(version) FROM public.dating_safety_configs WHERE state = 'active'), 'null'::jsonb) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not show the chat''s outbox, config, events and counters: %',
      jsonb_build_object('outbox', h -> 'chat_safety_outbox', 'config', h -> 'chat_safety_config_active', 'events', h -> 'chat_safety_events_24h');
  END IF;
END $$;

-- S4 (I-1): a moderator's decision sticks; fresh evidence opens again.
DO $$
DECLARE
  s constant uuid := pg_temp.id('67');
  r3 constant uuid := pg_temp.id('70');
  x constant uuid := pg_temp.id('64');
  v_m3 constant uuid := (SELECT id FROM public.dating_matches WHERE pair_key = public.dating_pair_key(pg_temp.id('67'), pg_temp.id('70')));
  v_mx uuid;
  v_msg uuid;
  v_open text[];
BEGIN
  -- P's evidence is an hour old; a moderator closed its three cases 30 minutes ago.
  UPDATE public.dating_safety_events SET created_at = now() - interval '1 hour' WHERE sender_user_id = s;
  UPDATE public.dating_opener_hashes SET created_at = now() - interval '1 hour' WHERE sender_user_id = s;
  UPDATE public.dating_moderation_cases SET state = 'closed', decided_at = now() - interval '30 minutes'
   WHERE target_user_id = s AND kind = 'signal' AND signal_kind IN ('money_asks', 'sexual_pressure', 'duplicate_opener')
     AND state IN ('open', 'in_review');
  IF (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = s AND state = 'closed'
         AND signal_kind IN ('money_asks', 'sexual_pressure', 'duplicate_opener')) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: P did not leave its three pattern cases';
  END IF;
  -- (a) A hit-free message.
  v_msg := (pg_temp.j(s, '67', format('SELECT public.send_dating_message(%L, %L, ''How was the market today?'')', pg_temp.key('s4a'), v_m3))
            #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  PERFORM public.complete_dating_safety_job(v_msg, 'dating_chat_v1', '[]');
  IF EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE target_user_id = s AND state IN ('open', 'in_review')
               AND signal_kind IN ('money_asks', 'sexual_pressure', 'duplicate_opener'))
     OR (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = s AND state = 'closed'
           AND signal_kind IN ('money_asks', 'sexual_pressure', 'duplicate_opener')) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a moderator''s decision was undone by the sender''s next hit-free message';
  END IF;
  -- (b) One recipient asked after the decision: not a pattern yet.
  v_msg := (pg_temp.j(s, '67', format('SELECT public.send_dating_message(%L, %L, ''please'')', pg_temp.key('s4b'), v_m3))
            #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  PERFORM public.complete_dating_safety_job(v_msg, 'dating_chat_v1',
    '[{"rule_id": "financial_request:gift card", "family": "financial_request", "tier": 2},
      {"rule_id": "sexual_pressure:send nudes", "family": "sexual_pressure", "tier": 1}]');
  IF EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE target_user_id = s AND state IN ('open', 'in_review')
               AND signal_kind IN ('money_asks', 'sexual_pressure', 'duplicate_opener')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: evidence a moderator cleared counted again (one new recipient opened a pattern case)';
  END IF;
  -- (c) A second recipient after the decision: the patterns open again, on
  -- the match that holds the event; the same opener a 4th time is only the
  -- first after the decision.
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(s, x), greatest(s, x), 'active') RETURNING id INTO v_mx;
  v_msg := (pg_temp.j(s, '67', format('SELECT public.send_dating_message(%L, %L, ''Hello dear, how was your day?'')', pg_temp.key('s4c'), v_mx))
            #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  PERFORM public.complete_dating_safety_job(v_msg, 'dating_chat_v1',
    '[{"rule_id": "financial_request:gift card", "family": "financial_request", "tier": 2},
      {"rule_id": "sexual_pressure:send nudes", "family": "sexual_pressure", "tier": 1}]');
  SELECT array_agg(c.signal_kind || ':' || (c.match_id IS NOT DISTINCT FROM v_mx)::text ORDER BY c.signal_kind) INTO v_open
    FROM public.dating_moderation_cases AS c
   WHERE c.target_user_id = s AND c.state IN ('open', 'in_review') AND c.signal_kind IN ('money_asks', 'sexual_pressure', 'duplicate_opener');
  IF v_open IS DISTINCT FROM ARRAY['money_asks:true', 'sexual_pressure:true']
     OR (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = s AND state = 'closed'
           AND signal_kind IN ('money_asks', 'sexual_pressure', 'duplicate_opener')) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fresh evidence after a decision did not reopen on its own match (open: %)', v_open;
  END IF;
END $$;

-- S5 (I-1 gate, M-7): evidence the completion did not add opens nothing;
-- a deleted recipient's evidence still counts; a hit to a recipient
-- deleted before the completion still opens the case about the sender.
DO $$
DECLARE
  a constant uuid := pg_temp.id('62');
  b constant uuid := pg_temp.id('63');
  v_m constant uuid := (SELECT id FROM public.dating_matches WHERE pair_key = public.dating_pair_key(pg_temp.id('62'), pg_temp.id('63')));
  v_msg uuid;
  v_hash text;
  v text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE target_user_id = b
               AND signal_kind IN ('money_asks', 'sexual_pressure', 'duplicate_opener')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: b already has a pattern case';
  END IF;
  -- Evidence with no case yet (as when the case could not be opened then):
  -- a second recipient's money ask, two recipients' sexual pressure, and
  -- b's opener in two more matches.
  INSERT INTO public.dating_safety_events (match_id, message_id, at_risk_user_id, sender_user_id, rule_id, family, tier,
                                           config_version, source_event_key)
  VALUES (NULL, NULL, pg_temp.id('60'), b, 'financial_request:gift card', 'financial_request', 2, 'dating_chat_v1', 'w6-s5-fin'),
         (NULL, NULL, pg_temp.id('60'), b, 'sexual_pressure:send nudes', 'sexual_pressure', 1, 'dating_chat_v1', 'w6-s5-sex'),
         (NULL, NULL, a, b, 'sexual_pressure:send nudes', 'sexual_pressure', 1, 'dating_chat_v1', 'w6-s5-sex2');
  SELECT k.hash INTO v_hash FROM public.dating_opener_hashes AS k WHERE k.sender_user_id = b AND k.match_id = v_m;
  INSERT INTO public.dating_opener_hashes (sender_user_id, match_id, hash)
  SELECT b, m.id, v_hash FROM public.dating_matches AS m
   WHERE m.pair_key IN (public.dating_pair_key(pg_temp.id('60'), pg_temp.id('61')), public.dating_pair_key(pg_temp.id('64'), pg_temp.id('65')));
  IF v_hash IS NULL OR (SELECT count(*) FROM public.dating_opener_hashes WHERE sender_user_id = b AND hash = v_hash) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: b''s opener is not in three matches';
  END IF;
  v_msg := (pg_temp.j(b, '63', format('SELECT public.send_dating_message(%L, %L, ''see you soon'')', pg_temp.key('s5a'), v_m))
            #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  PERFORM public.complete_dating_safety_job(v_msg, 'dating_chat_v1', '[]');
  IF EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE target_user_id = b
               AND signal_kind IN ('money_asks', 'sexual_pressure', 'duplicate_opener')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hit-free message opened a pattern case on evidence it did not add: %',
      (SELECT array_agg(signal_kind) FROM public.dating_moderation_cases WHERE target_user_id = b
          AND signal_kind IN ('money_asks', 'sexual_pressure', 'duplicate_opener'));
  END IF;
  -- The second recipient deletes their account (the event keeps no one).
  UPDATE public.dating_safety_events SET at_risk_user_id = NULL WHERE source_event_key = 'w6-s5-fin';
  v_msg := (pg_temp.j(b, '63', format('SELECT public.send_dating_message(%L, %L, ''send me momo'')', pg_temp.key('s5b'), v_m))
            #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  PERFORM public.complete_dating_safety_job(v_msg, 'dating_chat_v1',
    '[{"rule_id": "financial_request:send me momo", "family": "financial_request", "tier": 2}]');
  IF (SELECT array_agg(c.signal_kind || ':' || (c.match_id IS NOT DISTINCT FROM v_m)::text) FROM public.dating_moderation_cases AS c
       WHERE c.target_user_id = b AND c.state = 'open' AND c.signal_kind IN ('money_asks', 'sexual_pressure', 'duplicate_opener'))
     IS DISTINCT FROM ARRAY['money_asks:true'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted recipient''s money ask stopped counting, or another pattern opened';
  END IF;
  -- The recipient is deleted between the send and the completion.
  v_msg := (pg_temp.j(b, '63', format('SELECT public.send_dating_message(%L, %L, ''tell me about them'')', pg_temp.key('s5c'), v_m))
            #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  UPDATE public.dating_matches
     SET user_low_id = CASE WHEN user_low_id = a THEN NULL ELSE user_low_id END,
         user_high_id = CASE WHEN user_high_id = a THEN NULL ELSE user_high_id END
   WHERE id = v_m;
  v := pg_temp.done(v_msg, 'dating_chat_v1', '[{"rule_id": "child_access:how old are your kids", "family": "child_access", "tier": 2}]');
  IF v IS DISTINCT FROM '{"ok": true, "state": "done", "events": 1}'
     OR NOT EXISTS (SELECT 1 FROM public.dating_safety_events WHERE message_id = v_msg AND at_risk_user_id IS NULL AND sender_user_id = b)
     OR NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE target_user_id = b AND signal_kind = 'chat_child_access') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a tier-2 hit to a deleted recipient kept no evidence or opened no case about the sender: %', v;
  END IF;
  IF (SELECT confdeltype FROM pg_constraint
       WHERE conrelid = 'public.dating_safety_events'::regclass AND contype = 'f'
         AND conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'public.dating_safety_events'::regclass
                                                             AND attname = 'at_risk_user_id')]) IS DISTINCT FROM 'n' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: deleting a recipient deletes the evidence about the sender (at_risk_user_id is not ON DELETE SET NULL)';
  END IF;
END $$;

-- S6 (M-9): the config guard runs as its owner, on an empty search path.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = 'private.dating_safety_config_guard()'::regprocedure
                   AND prosecdef AND proconfig @> ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the config guard is not SECURITY DEFINER with an empty search path';
  END IF;
END $$;

-- S7 (M-11): a message push goes out only while something is unread.
DO $$
DECLARE
  a constant uuid := pg_temp.id('60');
  b constant uuid := pg_temp.id('61');
  v_m constant uuid := (SELECT id FROM public.dating_matches WHERE pair_key = public.dating_pair_key(pg_temp.id('60'), pg_temp.id('61')));
  v_push uuid;
  v_other uuid;
  v_first text;
BEGIN
  SELECT id INTO v_push FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending' ORDER BY created_at DESC LIMIT 1;
  IF v_push IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: b has no pending message push';
  END IF;
  -- Unread: the worker's claim takes it (or quiet hours bounce it), never skipped.
  UPDATE public.scheduled_notifications SET status = 'processing' WHERE id = v_push;
  v_first := (SELECT status FROM public.scheduled_notifications WHERE id = v_push);
  UPDATE public.scheduled_notifications SET status = 'pending' WHERE id = v_push;
  -- b reads the chat: the seen mark covers a's newest message.
  UPDATE public.dating_matches AS m
     SET low_seen_at = CASE WHEN m.user_low_id = b THEN (SELECT max(d.created_at) FROM public.dating_messages AS d
                                                          WHERE d.match_id = m.id AND d.sender_user_id = a) ELSE m.low_seen_at END,
         high_seen_at = CASE WHEN m.user_high_id = b THEN (SELECT max(d.created_at) FROM public.dating_messages AS d
                                                            WHERE d.match_id = m.id AND d.sender_user_id = a) ELSE m.high_seen_at END
   WHERE m.id = v_m;
  -- Another Dating push of the same type (not a message push) is never skipped.
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  VALUES (b, 'immediate', now(), 'pending',
          '{"type": "me_update", "route": "me", "title": "Attune", "body": "You have something new in Attune."}',
          private.dating_push_source_key(b, 'digest', (now() AT TIME ZONE 'UTC')::date), now(), now())
  RETURNING id INTO v_other;
  UPDATE public.scheduled_notifications SET status = 'processing' WHERE id IN (v_push, v_other);
  IF v_first IS NOT DISTINCT FROM 'skipped'
     OR (SELECT status FROM public.scheduled_notifications WHERE id = v_push) IS DISTINCT FROM 'skipped'
     OR (SELECT status FROM public.scheduled_notifications WHERE id = v_other) IS NOT DISTINCT FROM 'skipped' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a message push was not skipped once read, or was skipped while unread, or another push was (% / % / %)',
      v_first, (SELECT status FROM public.scheduled_notifications WHERE id = v_push),
      (SELECT status FROM public.scheduled_notifications WHERE id = v_other);
  END IF;
END $$;

-- =====================================================================
-- T. (Task 5 fix round 2: I-2, N-1, N-2, N-3) A push skipped as read
--    never holds back the push for the next unread message (in the same
--    quarter hour it comes back; in the next one a new push is queued),
--    while a push that went out still holds the 15 minutes; a guided
--    answer sent first never hides a side's text opener; a config whose
--    terms are not in the form the engine emits is refused; the read
--    guard fires only for a Dating me_update claim (its WHEN clause).
--    People from M-S are reused (no new range).
-- =====================================================================
-- T1 (I-2).
DO $$
DECLARE
  a constant uuid := pg_temp.id('60');
  b constant uuid := pg_temp.id('61');
  v_m constant uuid := (SELECT id FROM public.dating_matches WHERE pair_key = public.dating_pair_key(pg_temp.id('60'), pg_temp.id('61')));
  v_q constant bigint := floor(extract(epoch FROM now()) / 900)::bigint;
  v_push uuid;
BEGIN
  SELECT id INTO v_push FROM public.scheduled_notifications
   WHERE user_id = b AND status = 'skipped' AND last_error = 'dating_chat_read';
  IF v_push IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: b''s message push was not skipped as read (S7)';
  END IF;
  -- S7's other claim went out (fix round 3: an unsent push holds the next back).
  UPDATE public.scheduled_notifications SET status = 'sent', updated_at = now() - interval '20 minutes' -- fix round 4: sent a while ago
   WHERE user_id = b AND status = 'processing';
  -- The same quarter hour: a writes again.
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Are you free on Saturday?'')', pg_temp.key('t1a'), v_m));
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending') <> 1
     OR (SELECT status || ':' || coalesce(last_error, '-') FROM public.scheduled_notifications WHERE id = v_push) IS DISTINCT FROM 'pending:-' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a push skipped as read held back the next unread message''s push (same quarter hour)';
  END IF;
  -- b reads again; the push is skipped again, and now it is the previous
  -- quarter hour's (2 minutes ago). R's sent push gives up its key.
  UPDATE public.dating_matches AS m
     SET low_seen_at = CASE WHEN m.user_low_id = b THEN clock_timestamp() ELSE m.low_seen_at END,
         high_seen_at = CASE WHEN m.user_high_id = b THEN clock_timestamp() ELSE m.high_seen_at END
   WHERE m.id = v_m;
  UPDATE public.scheduled_notifications SET status = 'processing' WHERE id = v_push;
  IF (SELECT status FROM public.scheduled_notifications WHERE id = v_push) IS DISTINCT FROM 'skipped' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: the read push was not skipped again';
  END IF;
  UPDATE public.scheduled_notifications SET source_key = NULL WHERE user_id = b AND status = 'sent';
  UPDATE public.scheduled_notifications
     SET source_key = private.dating_push_source_key(b, 'chat:' || (v_q - 1)::text, (to_timestamp((v_q - 1) * 900) AT TIME ZONE 'UTC')::date),
         created_at = now() - interval '2 minutes'
   WHERE id = v_push;
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Or Sunday?'')', pg_temp.key('t1b'), v_m));
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending') <> 1
     OR (SELECT status FROM public.scheduled_notifications WHERE id = v_push) IS DISTINCT FROM 'skipped' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a push skipped as read held back the next unread message''s push (next quarter hour)';
  END IF;
  -- A push that went out still holds the 15 minutes (R-42): the next one
  -- waits for the end of its window (final server fix, I-6).
  UPDATE public.scheduled_notifications SET status = 'sent', created_at = now() - interval '2 minutes',
         updated_at = now() - interval '2 minutes' WHERE id = v_push;
  DELETE FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending';
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Or Monday?'')', pg_temp.key('t1c'), v_m));
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending' AND scheduled_for < now() + interval '13 minutes')
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending'
          AND scheduled_for = now() + interval '13 minutes') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a push sent 2 minutes ago (previous quarter hour) did not hold the next one to its 15 minutes';
  END IF;
END $$;

-- T2 (N-1): a guided answer sent first does not hide the side's text opener.
DO $$
DECLARE
  s constant uuid := pg_temp.id('67');
  y constant uuid := pg_temp.id('65');
  z constant uuid := pg_temp.id('66');
  v_my uuid;
  v_mz uuid;
  v_msg uuid;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(s, y), greatest(s, y), 'active') RETURNING id INTO v_my;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(s, z), greatest(s, z), 'active') RETURNING id INTO v_mz;
  v_msg := (pg_temp.j(s, '67', format('SELECT public.send_dating_message(%L, %L, ''Hello dear, how was your day?'')', pg_temp.key('t2a'), v_my))
            #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  PERFORM public.complete_dating_safety_job(v_msg, 'dating_chat_v1', '[]');
  IF EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE target_user_id = s AND signal_kind = 'duplicate_opener' AND state = 'open') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: two openers after the decision opened duplicate_opener';
  END IF;
  INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, kind, question_id, body, body_masked, mask_version, idempotency_key)
  VALUES (v_mz, CASE WHEN least(s, z) = s THEN 'low' ELSE 'high' END, s, 'guided_answer', 'w6_question', 'A long walk by the sea',
          'A long walk by the sea', 1, pg_temp.key('t2g'));
  v_msg := (pg_temp.j(s, '67', format('SELECT public.send_dating_message(%L, %L, ''Hello dear, how was your day?'')', pg_temp.key('t2b'), v_mz))
            #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  PERFORM public.complete_dating_safety_job(v_msg, 'dating_chat_v1', '[]');
  IF (SELECT array_agg(c.match_id IS NOT DISTINCT FROM v_mz) FROM public.dating_moderation_cases AS c
       WHERE c.target_user_id = s AND c.signal_kind = 'duplicate_opener' AND c.state = 'open') IS DISTINCT FROM ARRAY[true] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a guided answer sent first hid the side''s text opener from duplicate_opener';
  END IF;
END $$;

-- T3 (N-2): a config's terms are stored in the form the engine emits.
DO $$
DECLARE
  v_cfg constant jsonb := (SELECT config FROM public.dating_safety_configs WHERE version = 'dating_chat_v1');
  v_bad jsonb;
  v_case text;
BEGIN
  FOREACH v_case IN ARRAY ARRAY['{families,financial_request,terms}', '{families,contact_migration_pressure,new_match_terms}',
                                '{families,age_signal,terms}'] LOOP
    v_bad := jsonb_set(v_cfg, v_case::text[], (v_cfg #> v_case::text[]) || CASE v_case
               WHEN '{families,financial_request,terms}' THEN '["Send Me MoMo!"]'
               WHEN '{families,contact_migration_pressure,new_match_terms}' THEN '["DM me on IG"]'
               ELSE '["I''m 15"]' END::jsonb);
    BEGIN
      INSERT INTO public.dating_safety_configs (version, config, config_hash)
      VALUES ('w6_form', v_bad, encode(extensions.digest(v_bad::text, 'sha256'), 'hex'));
      RAISE EXCEPTION 'CONTRACT VIOLATED: a config with a term not in its stored form was taken (%)', v_case;
    EXCEPTION WHEN check_violation THEN
      IF SQLERRM IS DISTINCT FROM 'config:term_form' THEN
        RAISE;
      END IF;
    END;
  END LOOP;
  -- A draft's edit is checked too. Final server fix (M-14): on a draft of
  -- this section's own (the v1 seed may be active where the dev script ran).
  INSERT INTO public.dating_safety_configs (version, config, config_hash)
  SELECT 'w6_t3_draft', c.config, c.config_hash FROM public.dating_safety_configs AS c WHERE c.version = 'dating_chat_v1';
  BEGIN
    UPDATE public.dating_safety_configs SET config = v_bad, config_hash = encode(extensions.digest(v_bad::text, 'sha256'), 'hex')
     WHERE version = 'w6_t3_draft';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: the section''s own draft config is missing';
    END IF;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft config was edited to a term not in its stored form';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM IS DISTINCT FROM 'config:term_form' THEN
      RAISE;
    END IF;
  END;
END $$;

-- T4 (N-3): the read guard fires only for a Dating me_update claim.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger AS t
                  WHERE t.tgrelid = 'public.scheduled_notifications'::regclass AND t.tgname = 'scheduled_notifications_dating_read_guard'
                    AND t.tgqual IS NOT NULL
                    AND pg_get_triggerdef(t.oid) ~ 'old\.status = ''pending'''
                    AND pg_get_triggerdef(t.oid) ~ 'new\.status = ''processing'''
                    AND pg_get_triggerdef(t.oid) ~ '''me_update''') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the read guard is not limited (WHEN) to a me_update claim: %',
      (SELECT pg_get_triggerdef(t.oid) FROM pg_trigger AS t WHERE t.tgname = 'scheduled_notifications_dating_read_guard');
  END IF;
END $$;

-- =====================================================================
-- U. (Task 5 fix round 3: I-3, the overnight burst; R-42) A revived push
--    counts its 15 minutes from the message that revived it; a person
--    with an unsent message push gets no second one (quiet hours hold
--    every push to 08:00, which then sends one), also when the held push
--    was skipped as read and a new message comes in the night. People 60
--    and 61 (M) are reused.
-- =====================================================================
-- An Etc/GMT zone in which the real now() is p_hour:xx local (as
-- quiet_hours_contracts.sql; Etc/GMT-N is UTC+N).
CREATE FUNCTION pg_temp.zone_at(p_hour int) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN n = 0 THEN 'Etc/GMT' WHEN n > 0 THEN 'Etc/GMT-' || n ELSE 'Etc/GMT+' || (-n) END
    FROM (SELECT CASE WHEN m > 12 THEN m - 24 ELSE m END AS n
            FROM (SELECT (((p_hour - extract(hour FROM now() AT TIME ZONE 'UTC')::int) % 24) + 24) % 24 AS m) a) b $$;
-- U1 (I-3).
DO $$
DECLARE
  a constant uuid := pg_temp.id('60');
  b constant uuid := pg_temp.id('61');
  v_m constant uuid := (SELECT id FROM public.dating_matches WHERE pair_key = public.dating_pair_key(pg_temp.id('60'), pg_temp.id('61')));
  v_q constant bigint := floor(extract(epoch FROM now()) / 900)::bigint;
  v_push uuid;
BEGIN
  DELETE FROM public.scheduled_notifications WHERE user_id = b;
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''First thing this quarter'')', pg_temp.key('u1a'), v_m));
  SELECT id INTO v_push FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending';
  -- It was queued early in the quarter (15 min 1 s before the boundary
  -- message below) and b read it: skipped.
  UPDATE public.scheduled_notifications
     SET status = 'skipped', last_error = 'dating_chat_read', created_at = now() - interval '15 minutes 1 second'
   WHERE id = v_push;
  -- A late message in the same quarter revives it, and it goes out.
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Late in the quarter'')', pg_temp.key('u1b'), v_m));
  IF (SELECT status FROM public.scheduled_notifications WHERE id = v_push) IS DISTINCT FROM 'pending'
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: the late message did not revive the push';
  END IF;
  UPDATE public.scheduled_notifications SET status = 'sent' WHERE id = v_push;
  -- Just after the boundary, it is the previous quarter's push.
  UPDATE public.scheduled_notifications
     SET source_key = private.dating_push_source_key(b, 'chat:' || (v_q - 1)::text, (to_timestamp((v_q - 1) * 900) AT TIME ZONE 'UTC')::date)
   WHERE id = v_push;
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Just after the boundary'')', pg_temp.key('u1c'), v_m));
  -- Final server fix (I-6): the next one waits for the end of that window.
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = b AND id <> v_push
                AND scheduled_for < (SELECT updated_at FROM public.scheduled_notifications WHERE id = v_push) + interval '15 minutes') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a revived push did not count its 15 minutes from the revive (a second push seconds later)';
  END IF;
END $$;

-- U2 (the overnight burst).
DO $$
DECLARE
  a constant uuid := pg_temp.id('60');
  b constant uuid := pg_temp.id('61');
  v_m constant uuid := (SELECT id FROM public.dating_matches WHERE pair_key = public.dating_pair_key(pg_temp.id('60'), pg_temp.id('61')));
  v_q constant bigint := floor(extract(epoch FROM now()) / 900)::bigint;
  v_tz text;
  v_push uuid;
BEGIN
  -- b's night: it is 23:xx where b is.
  UPDATE public.users SET timezone = pg_temp.zone_at(23) WHERE id = b;
  v_tz := public.notification_recipient_tz(b);
  DELETE FROM public.scheduled_notifications WHERE user_id = b;
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Late night one'')', pg_temp.key('u2a'), v_m));
  SELECT id INTO v_push FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending';
  IF v_tz IS NULL OR v_push IS NULL OR (SELECT (scheduled_for AT TIME ZONE v_tz)::time FROM public.scheduled_notifications WHERE id = v_push)
       IS DISTINCT FROM time '08:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: the night''s push was not held to 08:00 (zone %)', v_tz;
  END IF;
  -- That push was queued two quarters ago; messages now, in this quarter.
  UPDATE public.scheduled_notifications
     SET source_key = private.dating_push_source_key(b, 'chat:' || (v_q - 2)::text, (to_timestamp((v_q - 2) * 900) AT TIME ZONE 'UTC')::date),
         created_at = now() - interval '35 minutes'
   WHERE id = v_push;
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Late night two'')', pg_temp.key('u2b'), v_m));
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Late night three'')', pg_temp.key('u2c'), v_m));
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a night of messages across quarters left % pushes for 08:00 (at most one)',
      (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending');
  END IF;
  -- The held push was skipped as read (this quarter's), and a message comes in the night.
  DELETE FROM public.scheduled_notifications WHERE user_id = b;
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Late night four'')', pg_temp.key('u2d'), v_m));
  SELECT id INTO v_push FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending';
  UPDATE public.scheduled_notifications SET status = 'skipped', last_error = 'dating_chat_read' WHERE id = v_push;
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Late night five'')', pg_temp.key('u2e'), v_m));
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending') <> 1
     OR (SELECT (scheduled_for AT TIME ZONE v_tz)::time FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending')
        IS DISTINCT FROM time '08:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after a push skipped as read, a night message did not leave exactly one push held to 08:00';
  END IF;
  -- The same, with the skipped push the previous quarter's.
  UPDATE public.scheduled_notifications SET status = 'skipped', last_error = 'dating_chat_read',
         source_key = private.dating_push_source_key(b, 'chat:' || (v_q - 1)::text, (to_timestamp((v_q - 1) * 900) AT TIME ZONE 'UTC')::date),
         created_at = now() - interval '2 minutes'
   WHERE user_id = b AND status = 'pending';
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Late night six'')', pg_temp.key('u2f'), v_m));
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending') <> 1
     OR (SELECT (scheduled_for AT TIME ZONE v_tz)::time FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending')
        IS DISTINCT FROM time '08:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after last quarter''s push skipped as read, a night message did not leave exactly one push held to 08:00';
  END IF;
END $$;

-- U3 (the overnight burst): a push being sent (claimed) holds the next one
-- back; a claim stuck for 15 minutes no longer does.
DO $$
DECLARE
  a constant uuid := pg_temp.id('60');
  b constant uuid := pg_temp.id('61');
  v_m constant uuid := (SELECT id FROM public.dating_matches WHERE pair_key = public.dating_pair_key(pg_temp.id('60'), pg_temp.id('61')));
  v_claimed uuid;
BEGIN
  UPDATE public.users SET timezone = NULL WHERE id = b; -- daytime again (U2 set b's night): the claim is not bounced
  DELETE FROM public.scheduled_notifications WHERE user_id = b;
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  VALUES (b, 'immediate', now(), 'pending',
          '{"type": "me_update", "route": "me", "title": "Attune", "body": "You have something new in Attune."}',
          private.dating_push_source_key(b, 'u3', (now() AT TIME ZONE 'UTC')::date), now() - interval '20 minutes', now())
  RETURNING id INTO v_claimed;
  UPDATE public.scheduled_notifications SET status = 'processing', scheduled_for = now(), updated_at = now() WHERE id = v_claimed;
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''While one is sent'')', pg_temp.key('u3a'), v_m));
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a push queued while another was being sent';
  END IF;
  UPDATE public.scheduled_notifications SET updated_at = now() - interval '20 minutes' WHERE id = v_claimed;
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''After a stuck claim'')', pg_temp.key('u3b'), v_m));
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a claim stuck for 15 minutes still held message pushes back';
  END IF;
END $$;

-- U4 (I-4): a push sent minutes ago (released at 08:00 after quiet hours,
-- queued in the night) holds the next one for 15 minutes from its send.
DO $$
DECLARE
  a constant uuid := pg_temp.id('60');
  b constant uuid := pg_temp.id('61');
  v_m constant uuid := (SELECT id FROM public.dating_matches WHERE pair_key = public.dating_pair_key(pg_temp.id('60'), pg_temp.id('61')));
  v_q constant bigint := floor(extract(epoch FROM now()) / 900)::bigint;
  v_sent uuid;
BEGIN
  UPDATE public.users SET timezone = NULL WHERE id = b;
  DELETE FROM public.scheduled_notifications WHERE user_id = b;
  -- Queued at 23:00 (9 hours ago), held to 08:00, sent 5 minutes ago.
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  VALUES (b, 'immediate', now() - interval '5 minutes', 'pending',
          '{"type": "me_update", "route": "me", "title": "Attune", "body": "You have something new in Attune."}',
          private.dating_push_source_key(b, 'chat:' || (v_q - 36)::text, (to_timestamp((v_q - 36) * 900) AT TIME ZONE 'UTC')::date),
          now() - interval '9 hours', now() - interval '9 hours')
  RETURNING id INTO v_sent;
  UPDATE public.scheduled_notifications SET status = 'sent', updated_at = now() - interval '5 minutes' WHERE id = v_sent;
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Good morning'')', pg_temp.key('u4a'), v_m));
  -- Final server fix (I-6): no second push inside the window; one at its end.
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = b AND id <> v_sent AND scheduled_for < now() + interval '10 minutes')
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND id <> v_sent AND status = 'pending'
          AND scheduled_for = now() + interval '10 minutes') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a message 5 minutes after the 08:00 push queued a second push inside its 15 minutes, or none at their end';
  END IF;
  -- 16 minutes after that send (its window's push gone), the next message pushes again.
  DELETE FROM public.scheduled_notifications WHERE user_id = b AND id <> v_sent;
  UPDATE public.scheduled_notifications SET updated_at = now() - interval '16 minutes' WHERE id = v_sent;
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Still there?'')', pg_temp.key('u4b'), v_m));
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending'
         AND scheduled_for <= now() -- final server fix (I-6): due now, under this quarter hour's own key
         AND source_key = private.dating_push_source_key(b, 'chat:' || v_q::text, (now() AT TIME ZONE 'UTC')::date)) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a push sent 16 minutes ago still held the next message push';
  END IF;
END $$;

-- U5 (N-6): a pending notify push ("Something you asked about is ready")
-- does not stand for a message push.
DO $$
DECLARE
  a constant uuid := pg_temp.id('60');
  b constant uuid := pg_temp.id('61');
  v_m constant uuid := (SELECT id FROM public.dating_matches WHERE pair_key = public.dating_pair_key(pg_temp.id('60'), pg_temp.id('61')));
BEGIN
  DELETE FROM public.scheduled_notifications WHERE user_id = b;
  PERFORM private.dating_queue_me_update(b, 'w6_notify', 'notify');
  PERFORM pg_temp.j(a, '60', format('SELECT public.send_dating_message(%L, %L, ''Hello again'')', pg_temp.key('u5a'), v_m));
  IF (SELECT array_agg(metadata ->> 'body' ORDER BY metadata ->> 'body') FROM public.scheduled_notifications
       WHERE user_id = b AND status = 'pending')
     IS DISTINCT FROM ARRAY['Something you asked about is ready in Attune.', 'You have something new in Attune.'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pending notify push held back the message push: %',
      (SELECT array_agg(metadata ->> 'body') FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending');
  END IF;
END $$;

-- =====================================================================
-- X. (Task 7 fix round 1; §3.6 Safety cards, §3.15 Chat) A new card
--    tells the recipient's open chat to read again: the completion that
--    makes a tier 1 or 2 card bumps the recipient's chat signal, never
--    the sender's; a tier 3 hit (a case, no card) bumps nobody. A card's
--    resource falls back to the international ('XX') entry, with its
--    text number or address when it has no phone.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('08');
  b constant uuid := pg_temp.ready('09', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_msg uuid;
  v jsonb;
BEGIN
  INSERT INTO public.support_resources (id, country_code, category, name, url, verified_at, verified_by, catalogue_version)
  VALUES (gen_random_uuid(), 'XX', 'sextortion', 'StopNCII', 'https://stopncii.org', current_date, 'contract', 'w6-contract');
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  -- X1: a tier 3 hit makes no card and bumps nobody.
  v_msg := (pg_temp.j(b, '09', format('SELECT public.send_dating_message(%L, %L, ''My late wife'')', pg_temp.key('x1'), v_m))
            #>> '{message,id}')::uuid;
  DELETE FROM public.dating_chat_signals WHERE match_id = v_m;
  PERFORM pg_temp.claim_only(v_msg);
  PERFORM public.complete_dating_safety_job(v_msg, 'dating_chat_v1',
    '[{"rule_id": "identity_inconsistency:my late wife", "family": "identity_inconsistency", "tier": 3}]');
  IF EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE match_id = v_m) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a tier 3 hit (no card) bumped a chat';
  END IF;
  -- X2: a card bumps the recipient's chat, not the sender's.
  v_msg := (pg_temp.j(b, '09', format('SELECT public.send_dating_message(%L, %L, ''I have your video'')', pg_temp.key('x2'), v_m))
            #>> '{message,id}')::uuid;
  DELETE FROM public.dating_chat_signals WHERE match_id = v_m;
  PERFORM pg_temp.claim_only(v_msg);
  PERFORM public.complete_dating_safety_job(v_msg, 'dating_chat_v1',
    '[{"rule_id": "sextortion:i have your video", "family": "sextortion", "tier": 2}]');
  IF NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = a AND match_id = v_m) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new card did not bump the recipient''s chat';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = b) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new card bumped the sender''s chat';
  END IF;
  -- X3: the resource is the international entry, its address included.
  v := pg_temp.j(a, '08', format('SELECT public.get_my_dating_safety_cards(%L)', v_m));
  IF jsonb_array_length(v -> 'cards') <> 1
     OR v #> '{cards,0,resource}' IS DISTINCT FROM
        '{"sms": null, "url": "https://stopncii.org", "name": "StopNCII", "phone": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the card''s resource did not fall back to the international entry: %', v;
  END IF;
END $$;

-- =====================================================================
-- R. (§3.6 guided first conversation) The questions in order; an answer
--    is seen by the other only once both have answered (and never lights
--    the list's dot before); then both appear together and the next
--    question is current; either may skip a question for both; only the
--    current question, once per side; nobody else skips.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('72');
  b constant uuid := pg_temp.ready('73', '{"identity": "man", "seeking": ["woman"]}');
  o constant uuid := pg_temp.ready('74');
  v_m uuid;
  v jsonb;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  IF pg_temp.j(a, '72', format('SELECT public.get_dating_guided_state(%L)', v_m))
     IS DISTINCT FROM '{"ok": true, "answered": false, "revealed": 0, "question_id": "good_saturday"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first question is not current';
  END IF;
  v := pg_temp.j(a, '72', format('SELECT public.send_dating_message(%L, %L, ''Market, then football'', ''guided_answer'', ''good_saturday'')', pg_temp.key('g1'), v_m));
  IF v ->> 'ok' IS DISTINCT FROM 'true'
     OR pg_temp.j(b, '73', format('SELECT public.get_dating_messages(%L)', v_m)) -> 'messages' IS DISTINCT FROM '[]'::jsonb
     OR pg_temp.j(b, '73', 'SELECT public.get_my_dating_matches()') #> '{conversations,0}' ->> 'new' IS DISTINCT FROM 'false'
     OR pg_temp.j(b, '73', 'SELECT public.get_my_dating_matches()') #> '{conversations,0,last}' IS DISTINCT FROM 'null'::jsonb
     OR pg_temp.j(a, '72', format('SELECT public.get_dating_guided_state(%L)', v_m)) ->> 'answered' IS DISTINCT FROM 'true'
     OR pg_temp.j(b, '73', format('SELECT public.get_dating_guided_state(%L)', v_m)) ->> 'answered' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an answer was seen before both answered (%)', v;
  END IF;
  IF pg_temp.j(a, '72', format('SELECT public.send_dating_message(%L, %L, ''again'', ''guided_answer'', ''good_saturday'')', pg_temp.key('g2'), v_m)) ->> 'reason' IS DISTINCT FROM 'invalid'
     OR pg_temp.j(b, '73', format('SELECT public.send_dating_message(%L, %L, ''early'', ''guided_answer'', ''proud_of'')', pg_temp.key('g3'), v_m)) ->> 'reason' IS DISTINCT FROM 'invalid'
     OR pg_temp.j(b, '73', format('SELECT public.send_dating_message(%L, %L, ''x'', ''guided_answer'', NULL)', pg_temp.key('g4'), v_m)) ->> 'reason' IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second answer, a later question or an unnamed one was taken';
  END IF;
  PERFORM pg_temp.j(b, '73', format('SELECT public.send_dating_message(%L, %L, ''Church, then jollof'', ''guided_answer'', ''good_saturday'')', pg_temp.key('g5'), v_m));
  IF (SELECT array_agg(x ->> 'text' ORDER BY x ->> 'text') FROM jsonb_array_elements(pg_temp.j(a, '72', format('SELECT public.get_dating_messages(%L)', v_m)) -> 'messages') AS x)
     IS DISTINCT FROM ARRAY['Church, then jollof', 'Market, then football']
     OR pg_temp.j(b, '73', format('SELECT public.get_dating_guided_state(%L)', v_m))
        IS DISTINCT FROM '{"ok": true, "answered": false, "revealed": 1, "question_id": "food_every_week"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: both answers did not appear together, or the next question is not current';
  END IF;
  IF pg_temp.j(o, '74', format('SELECT public.skip_dating_guided_question(%L, ''food_every_week'')', v_m)) ->> 'reason' IS DISTINCT FROM 'match_unavailable'
     OR pg_temp.j(a, '72', format('SELECT public.skip_dating_guided_question(%L, ''proud_of'')', v_m)) ->> 'reason' IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider, or a question not current, was skipped';
  END IF;
  v := pg_temp.j(a, '72', format('SELECT public.skip_dating_guided_question(%L, ''food_every_week'')', v_m));
  IF v ->> 'question_id' IS DISTINCT FROM 'looking_forward'
     OR pg_temp.j(b, '73', format('SELECT public.get_dating_guided_state(%L)', v_m)) ->> 'question_id' IS DISTINCT FROM 'looking_forward' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a skip was not for both (%)', v;
  END IF;
END $$;

-- R2 (Task 8 fix round 1, I-2; R-45): a guided answer is masked like any
-- message and queued for the safety scan.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('b0', '{"phone": "916"}');
  b constant uuid := pg_temp.ready('b1', '{"identity": "man", "seeking": ["woman"], "phone": "917"}');
  v_m uuid;
  v_msg uuid;
  v_seen text;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  v_msg := (pg_temp.j(a, 'b0', format('SELECT public.send_dating_message(%L, %L, ''Call me on 0244 123 456'', ''guided_answer'', ''good_saturday'')',
                                      pg_temp.key('r2a'), v_m)) #>> '{message,id}')::uuid;
  PERFORM pg_temp.j(b, 'b1', format('SELECT public.send_dating_message(%L, %L, ''Football all day'', ''guided_answer'', ''good_saturday'')', pg_temp.key('r2b'), v_m));
  v_seen := (SELECT x ->> 'text' FROM jsonb_array_elements(pg_temp.j(b, 'b1', format('SELECT public.get_dating_messages(%L)', v_m)) -> 'messages') AS x
              WHERE x ->> 'id' = v_msg::text);
  IF v_msg IS NULL OR (SELECT body_masked FROM public.dating_messages WHERE id = v_msg) NOT LIKE '%•••%'
     OR v_seen IS DISTINCT FROM (SELECT body_masked FROM public.dating_messages WHERE id = v_msg) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a guided answer with a phone number was not stored and shown masked (%)', v_seen;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_message_safety_outbox WHERE message_id = v_msg AND state = 'pending') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a guided answer was not queued for the safety scan';
  END IF;
END $$;

-- =====================================================================
-- S. (§3.6 We met and the timebox cards; §5.3) Day 7: once to each
--    person; day 21: once, only while neither said We met; We met counts
--    once and takes the chat out of the open pre-date chats.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('75');
  b constant uuid := pg_temp.ready('76', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_met bigint := pg_temp.metric('dating.we_met');
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at)
  VALUES (least(a, b), greatest(a, b), 'active', now() - interval '6 days') RETURNING id INTO v_m;
  IF pg_temp.j(a, '75', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{chat,timebox}' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a timebox card before day 7';
  END IF;
  UPDATE public.dating_matches SET matched_at = now() - interval '8 days' WHERE id = v_m;
  PERFORM pg_temp.j(a, '75', format('SELECT public.dismiss_dating_timebox(%L, ''day7'')', v_m));
  IF pg_temp.j(a, '75', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{chat,timebox}' IS NOT NULL
     OR pg_temp.j(b, '76', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{chat,timebox}' IS DISTINCT FROM 'day7' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the day-7 card is not once to each person';
  END IF;
  UPDATE public.dating_matches SET matched_at = now() - interval '22 days' WHERE id = v_m;
  IF pg_temp.j(a, '75', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{chat,timebox}' IS DISTINCT FROM 'day21' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no day-21 card while neither said We met';
  END IF;
  PERFORM pg_temp.j(b, '76', format('SELECT public.send_dating_message(%L, %L, ''hello'')', pg_temp.key('s1'), v_m));
  IF private.dating_open_chats(a, now()) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chat with a recent message is not an open chat';
  END IF;
  PERFORM pg_temp.j(b, '76', format('SELECT public.mark_dating_we_met(%L)', v_m));
  PERFORM pg_temp.j(b, '76', format('SELECT public.mark_dating_we_met(%L)', v_m));
  IF pg_temp.j(a, '75', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{chat,timebox}' IS NOT NULL
     OR pg_temp.j(a, '75', format('SELECT public.get_dating_messages(%L)', v_m)) #> '{chat,we_met}' IS DISTINCT FROM '{"mine": false, "theirs": true}'::jsonb
     OR private.dating_open_chats(a, now()) <> 0 OR pg_temp.metric('dating.we_met') <> v_met + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after We met the day-21 card showed, the chat stayed open, or We met counted twice';
  END IF;
END $$;

-- S2 (Task 8 fix round 1, I-2, M-4, M-5): no card on an ended chat; no
-- day-7 card past day 21; a day-21 dismissal sticks, as either side's,
-- each side its own; no day-7 card once either said We met; a skip tells
-- the other's chat; skip and We met are refused on a closed match; a pair
-- blocked by phone HMAC alone carries no card and no We met.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('b2', '{"phone": "918"}');
  b constant uuid := pg_temp.ready('b3', '{"identity": "man", "seeking": ["woman"], "phone": "919"}');
  c constant uuid := pg_temp.ready('b4', '{"phone": "920"}');
  d constant uuid := pg_temp.ready('b5', '{"identity": "man", "seeking": ["woman"], "phone": "921"}');
  f constant uuid := pg_temp.ready('b6', '{"phone": "922"}');
  g constant uuid := pg_temp.ready('b7', '{"identity": "man", "seeking": ["woman"], "phone": "923"}');
  v_m uuid;
  v_met uuid;
  v_closed uuid;
  v_hmac uuid;
BEGIN
  -- a (b2) is the low side, b (b3) the high side.
  IF NOT a < b THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: S2 setup: b2 does not sort before b3';
  END IF;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at)
  VALUES (a, b, 'active', now() - interval '22 days') RETURNING id INTO v_m;
  PERFORM pg_temp.j(b, 'b3', format('SELECT public.dismiss_dating_timebox(%L, ''day21'')', v_m));
  IF pg_temp.j(b, 'b3', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{chat,timebox}' IS NOT NULL
     OR pg_temp.j(a, 'b2', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{chat,timebox}' IS DISTINCT FROM 'day21' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the high side''s day-21 dismissal did not stick to that side alone (or showed a day-7 card past day 21)';
  END IF;
  PERFORM pg_temp.j(a, 'b2', format('SELECT public.dismiss_dating_timebox(%L, ''day21'')', v_m));
  IF pg_temp.j(a, 'b2', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{chat,timebox}' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a day-21 dismissal did not stick, or a day-7 card showed past day 21';
  END IF;
  -- A skip tells the other's chat.
  DELETE FROM public.dating_chat_signals WHERE match_id = v_m;
  PERFORM pg_temp.j(a, 'b2', format('SELECT public.skip_dating_guided_question(%L, ''good_saturday'')', v_m));
  IF NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = b AND match_id = v_m) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a skip did not tell the other''s chat';
  END IF;
  -- Day 8, one said We met: no day-7 card for either (M-4).
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at)
  VALUES (least(c, d), greatest(c, d), 'active', now() - interval '8 days') RETURNING id INTO v_met;
  IF pg_temp.j(c, 'b4', format('SELECT public.get_dating_messages(%L)', v_met)) #>> '{chat,timebox}' IS DISTINCT FROM 'day7' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: S2 setup: no day-7 card on day 8';
  END IF;
  PERFORM pg_temp.j(d, 'b5', format('SELECT public.mark_dating_we_met(%L)', v_met));
  IF pg_temp.j(c, 'b4', format('SELECT public.get_dating_messages(%L)', v_met)) #>> '{chat,timebox}' IS NOT NULL
     OR pg_temp.j(d, 'b5', format('SELECT public.get_dating_messages(%L)', v_met)) #>> '{chat,timebox}' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the day-7 card showed after We met (M-4)';
  END IF;
  -- A closed match on day 8 (inside its window): no card; skip and We met refused.
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, closed_reason, closed_at, evidence_until, matched_at)
  VALUES (least(a, d), greatest(a, d), 'closed', 'closed_kindly', now(), now() + interval '30 days', now() - interval '8 days')
  RETURNING id INTO v_closed;
  IF pg_temp.j(a, 'b2', format('SELECT public.get_dating_messages(%L)', v_closed)) #>> '{chat,state}' IS DISTINCT FROM 'ended'
     OR pg_temp.j(a, 'b2', format('SELECT public.get_dating_messages(%L)', v_closed)) #>> '{chat,timebox}' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a timebox card showed on an ended chat';
  END IF;
  IF pg_temp.j(a, 'b2', format('SELECT public.skip_dating_guided_question(%L, ''good_saturday'')', v_closed)) ->> 'reason' IS DISTINCT FROM 'closed'
     OR pg_temp.j(a, 'b2', format('SELECT public.mark_dating_we_met(%L)', v_closed)) ->> 'reason' IS DISTINCT FROM 'closed'
     OR EXISTS (SELECT 1 FROM public.dating_guided_skips WHERE match_id = v_closed)
     OR (SELECT low_we_met_at IS NOT NULL OR high_we_met_at IS NOT NULL FROM public.dating_matches WHERE id = v_closed) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a skip or We met was taken on a closed match';
  END IF;
  -- A block by phone HMAC alone: the header says ended and carries no card, no We met (M-5).
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at, low_we_met_at)
  VALUES (least(f, g), greatest(f, g), 'active', now() - interval '8 days', NULL) RETURNING id INTO v_hmac;
  INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
  VALUES (public.dating_phone_hmac_for_user(g), public.dating_phone_hmac_for_user(f));
  IF pg_temp.j(f, 'b6', format('SELECT public.get_dating_messages(%L)', v_hmac)) #>> '{chat,state}' IS DISTINCT FROM 'ended'
     OR pg_temp.j(f, 'b6', format('SELECT public.get_dating_messages(%L)', v_hmac)) #>> '{chat,timebox}' IS NOT NULL
     OR pg_temp.j(f, 'b6', format('SELECT public.get_dating_messages(%L)', v_hmac)) #>> '{chat,we_met}' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pair blocked by phone HMAC alone still carries a card or We met (M-5): %',
      pg_temp.j(f, 'b6', format('SELECT public.get_dating_messages(%L)', v_hmac)) -> 'chat';
  END IF;
END $$;

-- =====================================================================
-- T. (§3.6 Close kindly) The reviewed message is sent as the last one,
--    the match closes for both (closed_kindly, the 30-day window), the
--    pair is never introduced again; nobody else can; a replay is ok.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('77');
  b constant uuid := pg_temp.ready('78', '{"identity": "man", "seeking": ["woman"]}');
  o constant uuid := pg_temp.ready('79');
  v_m uuid;
  k constant text := pg_temp.key('kind');
  v jsonb;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  IF pg_temp.j(o, '79', format('SELECT public.close_dating_match_kindly(%L, %L)', k, v_m)) ->> 'reason' IS DISTINCT FROM 'match_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider closed the chat';
  END IF;
  v := pg_temp.j(a, '77', format('SELECT public.close_dating_match_kindly(%L, %L)', k, v_m));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT state || '/' || closed_reason || '/' || (evidence_until > now() + interval '29 days')::text FROM public.dating_matches WHERE id = v_m)
        IS DISTINCT FROM 'closed/closed_kindly/true'
     OR NOT pg_temp.marked(a, b)
     OR pg_temp.j(b, '78', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{messages,0,text}'
        IS DISTINCT FROM 'Thank you for chatting with me. I don''t think we''re a match, and I wish you well.'
     OR pg_temp.j(b, '78', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{messages,0,kind}' IS DISTINCT FROM 'close_kindly'
     OR pg_temp.j(b, '78', format('SELECT public.get_dating_messages(%L)', v_m)) #>> '{chat,state}' IS DISTINCT FROM 'ended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Close kindly answered % (the message, the close, the marker)', v;
  END IF;
  IF pg_temp.j(a, '77', format('SELECT public.close_dating_match_kindly(%L, %L)', k, v_m)) IS DISTINCT FROM '{"ok": true}'::jsonb
     OR pg_temp.j(b, '78', format('SELECT public.close_dating_match_kindly(%L, %L)', pg_temp.key('kind2'), v_m)) ->> 'reason' IS DISTINCT FROM 'closed'
     OR (SELECT count(*) FROM public.dating_messages WHERE match_id = v_m) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay sent again, or a closed chat closed again';
  END IF;
END $$;

-- =====================================================================
-- U. (§3.6 Check on me, §3.13; R17) One neutral me_checkin push at the
--    chosen time (no place, no match, no name); a new one replaces the
--    last; cancel removes it; a time under 5 minutes or past 7 days is
--    refused; a check-in at 23:30 local is not folded by quiet hours,
--    while a me_update at the same time is.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('80');
  v_at timestamptz;
  v jsonb;
BEGIN
  UPDATE public.users SET timezone = 'Africa/Accra' WHERE id = a;
  v_at := (date_trunc('day', now() AT TIME ZONE 'Africa/Accra') + interval '23 hours 30 minutes') AT TIME ZONE 'Africa/Accra';
  IF v_at < now() + interval '5 minutes' THEN
    v_at := v_at + interval '1 day';
  END IF;
  IF pg_temp.j(a, '80', format('SELECT public.schedule_dating_checkin(%L)', now() + interval '1 minute')) ->> 'reason' IS DISTINCT FROM 'invalid'
     OR pg_temp.j(a, '80', format('SELECT public.schedule_dating_checkin(%L)', now() + interval '8 days')) ->> 'reason' IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a check-in too soon or too far was taken';
  END IF;
  PERFORM pg_temp.j(a, '80', format('SELECT public.schedule_dating_checkin(%L)', v_at - interval '1 hour'));
  v := pg_temp.j(a, '80', format('SELECT public.schedule_dating_checkin(%L)', v_at));
  IF v ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = a AND status = 'pending') <> 1
     OR (SELECT metadata FROM public.scheduled_notifications WHERE user_id = a AND status = 'pending')
        IS DISTINCT FROM '{"type": "me_checkin", "route": "me_checkin", "title": "Attune", "body": "A quick check-in from Attune."}'::jsonb
     OR (SELECT scheduled_for FROM public.scheduled_notifications WHERE user_id = a AND status = 'pending') IS DISTINCT FROM v_at THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the check-in is not one neutral push at its time (folded by quiet hours?) (%)', v;
  END IF;
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata)
  VALUES (a, 'immediate', v_at, 'pending', '{"type": "me_update", "route": "me", "title": "Attune", "body": "You have something new in Attune."}');
  IF (SELECT scheduled_for FROM public.scheduled_notifications WHERE user_id = a AND metadata ->> 'type' = 'me_update') = v_at THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the control me_update at 23:30 was not folded by quiet hours (the case proves nothing)';
  END IF;
  PERFORM pg_temp.j(a, '80', 'SELECT public.cancel_dating_checkin()');
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = a AND status = 'pending' AND metadata ->> 'type' = 'me_checkin') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: cancel left a check-in';
  END IF;
END $$;

-- U2 (Task 8 fix round 1, I-2): scheduling and cancelling act on the
-- caller's own check-in only, and on nothing else of the caller's.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('b8', '{"phone": "924"}');
  b constant uuid := pg_temp.ready('b9', '{"phone": "925"}');
BEGIN
  UPDATE public.users SET timezone = NULL WHERE id IN (a, b);
  PERFORM pg_temp.j(b, 'b9', format('SELECT public.schedule_dating_checkin(%L)', now() + interval '1 hour'));
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata)
  VALUES (a, 'immediate', now() + interval '1 hour', 'pending', '{"type": "me_update", "route": "me", "title": "Attune", "body": "You have something new in Attune."}'),
         (b, 'immediate', now() + interval '1 hour', 'pending', '{"type": "me_update", "route": "me", "title": "Attune", "body": "You have something new in Attune."}');
  PERFORM pg_temp.j(a, 'b8', format('SELECT public.schedule_dating_checkin(%L)', now() + interval '2 hours'));
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending' AND metadata ->> 'type' = 'me_checkin') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one person''s check-in cancelled another''s';
  END IF;
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = a AND status = 'pending' AND metadata ->> 'type' = 'me_update') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: scheduling a check-in cancelled the person''s other pending push';
  END IF;
  PERFORM pg_temp.j(a, 'b8', 'SELECT public.cancel_dating_checkin()');
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending' AND metadata ->> 'type' = 'me_checkin') <> 1
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = a AND status = 'pending') <> 1
     OR (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: cancelling a check-in cancelled another person''s, or another push';
  END IF;
END $$;

-- U3 (Task 10 fix round 1, I-1, I-3): get_my_dating_checkin reads the
-- caller's own pending check-in (or none), never another person's; the
-- schedule answer and the read say whether this person has a push device.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('d1', '{"phone": "961"}');
  b constant uuid := pg_temp.ready('d2', '{"phone": "962"}');
  v_a constant timestamptz := date_trunc('second', now()) + interval '2 hours';
  v_b constant timestamptz := date_trunc('second', now()) + interval '3 hours';
  v jsonb;
BEGIN
  UPDATE public.users SET timezone = NULL WHERE id IN (a, b);
  DELETE FROM public.push_tokens WHERE user_id IN (a, b);
  INSERT INTO public.push_tokens (user_id, token, platform, is_active)
  VALUES (b, '0b6f1a1e-0000-4000-8000-0000000000d2', 'ios', true);
  v := pg_temp.j(b, 'd2', format('SELECT public.schedule_dating_checkin(%L)', v_b));
  IF v ->> 'ok' IS DISTINCT FROM 'true' OR v ->> 'push' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the schedule answer did not say a push can arrive (%)', v;
  END IF;
  v := pg_temp.j(a, 'd1', 'SELECT public.get_my_dating_checkin()');
  IF v IS DISTINCT FROM '{"ok": true, "at": null, "push": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person with no check-in read % (another person''s?)', v;
  END IF;
  v := pg_temp.j(a, 'd1', format('SELECT public.schedule_dating_checkin(%L)', v_a));
  IF v ->> 'ok' IS DISTINCT FROM 'true' OR v ->> 'push' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the schedule answer said a push can arrive with no device (%)', v;
  END IF;
  -- The latest row is b's again: a read that ignored the caller would see it.
  PERFORM pg_temp.j(b, 'd2', format('SELECT public.schedule_dating_checkin(%L)', v_b));
  v := pg_temp.j(a, 'd1', 'SELECT public.get_my_dating_checkin()');
  IF (v ->> 'at')::timestamptz IS DISTINCT FROM v_a OR v ->> 'push' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a read % is not the caller''s own check-in', v;
  END IF;
  v := pg_temp.j(b, 'd2', 'SELECT public.get_my_dating_checkin()');
  IF (v ->> 'at')::timestamptz IS DISTINCT FROM v_b OR v ->> 'push' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: b read % (own check-in, a device)', v;
  END IF;
  PERFORM pg_temp.j(a, 'd1', 'SELECT public.cancel_dating_checkin()');
  UPDATE public.push_tokens SET is_active = false WHERE user_id = b;
  IF pg_temp.j(a, 'd1', 'SELECT public.get_my_dating_checkin()') ->> 'at' IS NOT NULL
     OR (pg_temp.j(b, 'd2', 'SELECT public.get_my_dating_checkin()') ->> 'at')::timestamptz IS DISTINCT FROM v_b
     OR pg_temp.j(b, 'd2', 'SELECT public.get_my_dating_checkin()') ->> 'push' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after a cancel and a device gone, the reads are wrong';
  END IF;
  -- A sent or cancelled row is never read as pending.
  UPDATE public.scheduled_notifications SET status = 'sent'
   WHERE user_id = b AND status = 'pending' AND metadata ->> 'type' = 'me_checkin';
  IF pg_temp.j(b, 'd2', 'SELECT public.get_my_dating_checkin()') ->> 'at' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sent check-in was read as pending';
  END IF;
END $$;

-- U4 (Task 10 fix rounds 1 and 2, I-4, N-1): in production Dating chat
-- can't be on while support_resources_v2 (Get help's directory) is off,
-- judged on each statement's end state, never row by row: bulk and
-- two-flag statements pass in either row order; the directory off, or
-- deleted, alone under the chat, and the chat on alone without it, are
-- refused, and the refusal tells the operator to turn the chat off first.
-- Development is free. Both gate rows name the dependency.
CREATE FUNCTION pg_temp.u4_try(p_sql text) RETURNS text LANGUAGE plpgsql AS $u4$
BEGIN
  EXECUTE p_sql;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLERRM;
END;
$u4$;

CREATE FUNCTION pg_temp.u4_set(p_chat boolean, p_dir boolean, p_chat_last boolean) RETURNS void LANGUAGE plpgsql AS $u4$
BEGIN
  -- In development (the guard is free there), then the row order on disk:
  -- the row written last sits last in a sequential scan.
  PERFORM set_config('app.settings.attune_environment', '', true);
  -- Final server fix (I-4): the chat needs an active safety config too
  -- (FF4 tests that side); here one is active.
  IF NOT EXISTS (SELECT 1 FROM public.dating_safety_configs WHERE state = 'active') THEN
    INSERT INTO public.dating_safety_configs (version, state, config, config_hash, review_ref, activated_at)
    SELECT 'w6_u4', 'active', c.config, c.config_hash, 'TEST-U4', now() FROM public.dating_safety_configs AS c WHERE c.version = 'dating_chat_v1';
  END IF;
  INSERT INTO public.feature_flags (key, enabled) VALUES ('support_resources_v2', p_dir), ('dating_match_messaging', p_chat)
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled;
  UPDATE public.feature_flags SET updated_at = now()
   WHERE key = CASE WHEN p_chat_last THEN 'dating_match_messaging' ELSE 'support_resources_v2' END;
  PERFORM set_config('app.settings.attune_environment', 'production', true);
END;
$u4$;

DO $$
DECLARE
  v_err text;
  v_last boolean;
BEGIN
  UPDATE private.flag_production_gates SET review_ref = 'TEST-U4'
   WHERE flag_key IN ('dating_match_messaging', 'support_resources_v2');
  FOREACH v_last IN ARRAY ARRAY[true, false] LOOP
    -- Everything off at once (the emergency switch-off).
    PERFORM pg_temp.u4_set(true, true, v_last);
    v_err := pg_temp.u4_try('UPDATE public.feature_flags SET enabled = false');
    IF v_err IS DISTINCT FROM 'ok' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: all flags off was refused in production (chat last: %): %', v_last, v_err;
    END IF;
    -- Both off in one statement.
    PERFORM pg_temp.u4_set(true, true, v_last);
    v_err := pg_temp.u4_try($q$UPDATE public.feature_flags SET enabled = false WHERE key IN ('dating_match_messaging', 'support_resources_v2')$q$);
    IF v_err IS DISTINCT FROM 'ok' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: both off in one statement was refused (chat last: %): %', v_last, v_err;
    END IF;
    -- Both on in one statement.
    PERFORM pg_temp.u4_set(false, false, v_last);
    v_err := pg_temp.u4_try($q$UPDATE public.feature_flags SET enabled = true WHERE key IN ('dating_match_messaging', 'support_resources_v2')$q$);
    IF v_err IS DISTINCT FROM 'ok'
       OR NOT (SELECT bool_and(enabled) FROM public.feature_flags WHERE key IN ('dating_match_messaging', 'support_resources_v2')) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: both on in one statement was refused (chat last: %): %', v_last, v_err;
    END IF;
  END LOOP;
  -- The directory off alone under the chat, or deleted: refused, with the hint.
  PERFORM pg_temp.u4_set(true, true, true);
  v_err := pg_temp.u4_try($q$UPDATE public.feature_flags SET enabled = false WHERE key = 'support_resources_v2'$q$);
  IF v_err NOT LIKE 'flag:dating_chat_needs_support_resources_v2%' OR v_err NOT LIKE '%turn Dating chat (dating_match_messaging) off first%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the directory went off under Dating chat, or the refusal does not say what to do (%)', v_err;
  END IF;
  v_err := pg_temp.u4_try($q$DELETE FROM public.feature_flags WHERE key = 'support_resources_v2'$q$);
  IF v_err NOT LIKE 'flag:dating_chat_needs_support_resources_v2%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the directory row was deleted under Dating chat (%)', v_err;
  END IF;
  -- The chat on alone without the directory: refused.
  PERFORM pg_temp.u4_set(false, false, true);
  v_err := pg_temp.u4_try($q$UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_match_messaging'$q$);
  IF v_err NOT LIKE 'flag:dating_chat_needs_support_resources_v2%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating chat went on in production without Get help''s directory (%)', v_err;
  END IF;
  -- The chat off first, then the directory: allowed.
  PERFORM pg_temp.u4_set(true, true, true);
  IF pg_temp.u4_try($q$UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_match_messaging'$q$) IS DISTINCT FROM 'ok'
     OR pg_temp.u4_try($q$UPDATE public.feature_flags SET enabled = false WHERE key = 'support_resources_v2'$q$) IS DISTINCT FROM 'ok' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the chat off, then the directory off, was refused';
  END IF;
  -- A pair already out of step (set before the guard existed) never holds
  -- up another flag's write.
  PERFORM pg_temp.u4_set(true, false, true);
  IF pg_temp.u4_try($q$UPDATE public.feature_flags SET updated_at = now() WHERE key = 'text_scale_v2'$q$) IS DISTINCT FROM 'ok' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another flag''s write was held up by the Dating chat pair';
  END IF;
  -- Development is free.
  PERFORM set_config('app.settings.attune_environment', '', true);
  IF pg_temp.u4_try($q$UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_match_messaging'$q$) IS DISTINCT FROM 'ok' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: development refused the chat flag';
  END IF;
  -- Final server fix (I-3): the chat needs Dating on too; the all-off above turned it off.
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  IF (SELECT gate FROM private.flag_production_gates WHERE flag_key = 'dating_match_messaging') NOT LIKE '%support_resources_v2%'
     OR (SELECT gate FROM private.flag_production_gates WHERE flag_key = 'dating_match_messaging') NOT LIKE '%active dating_safety_configs version%' -- final server fix (I-4)
     OR (SELECT gate FROM private.flag_production_gates WHERE flag_key = 'support_resources_v2') NOT LIKE '%dating_match_messaging%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a gate row does not name the dependency';
  END IF;
END $$;

-- =====================================================================
-- V. (§4.8; carry 9) The purge: a closed match past its window goes with
--    its messages unless an open case holds it; an active one stays; a
--    resolved introduction keeps only its ids, pair, state and dates; pair
--    markers and moderation cases go at 2 years; openers at 30 days;
--    safety events lose their people at 90 days; one failing step never
--    stops the others (counted).
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('81');
  b constant uuid := pg_temp.ready('82', '{"identity": "man", "seeking": ["woman"]}');
  c constant uuid := pg_temp.ready('83', '{"identity": "man", "seeking": ["woman"]}');
  e constant uuid := pg_temp.ready('84', '{"identity": "man", "seeking": ["woman"]}');
  v_gone uuid;
  v_held uuid;
  v_live uuid;
  v_i uuid;
  v_ev uuid; -- Task 8 Ruling P-4
  v jsonb;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, closed_reason, evidence_until)
  VALUES (least(a, b), greatest(a, b), 'unmatched', 'unmatched', now() - interval '1 day') RETURNING id INTO v_gone;
  INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, body, body_masked, mask_version, idempotency_key)
  VALUES (v_gone, 'low', least(a, b), 'old', 'old', 1, 'w6-purge-1');
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, closed_reason, evidence_until)
  VALUES (least(a, c), greatest(a, c), 'blocked', 'blocked', now() - interval '1 day') RETURNING id INTO v_held;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, match_id, signal_kind)
  VALUES ('signal', 'P1', c, v_held, 'money_asks');
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, e), greatest(a, e), 'active') RETURNING id INTO v_live;
  v_i := pg_temp.intro(b, e);
  UPDATE public.dating_introductions SET state = 'passed', low_action = 'passed', reasons = ARRAY['same_region'], rank_detail = '{"f": 1}',
         created_at = now() - interval '40 days', expires_at = now() - interval '33 days' WHERE id = v_i;
  INSERT INTO public.dating_pair_markers (pair_code, created_at, purge_after)
  VALUES (repeat('a', 64), now() - interval '2 years 1 day', now() - interval '1 day'), (repeat('b', 64), now(), now() + interval '2 years');
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind, state, created_at)
  VALUES ('signal', 'P2', e, 'dragnet', 'decided', now() - interval '2 years 1 day');
  INSERT INTO public.dating_opener_hashes (sender_user_id, match_id, hash, created_at) VALUES (a, v_live, repeat('c', 64), now() - interval '31 days');
  INSERT INTO public.dating_safety_events (match_id, at_risk_user_id, sender_user_id, rule_id, family, tier, config_version, source_event_key, created_at)
  VALUES (v_live, a, e, 'financial_request:x', 'financial_request', 2, 'dating_chat_v1', 'w6-purge-event', now() - interval '91 days')
  RETURNING id INTO v_ev; -- Task 8 Ruling P-4
  v := public.purge_dating_retention();
  IF EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_gone) OR EXISTS (SELECT 1 FROM public.dating_messages WHERE idempotency_key = 'w6-purge-1')
     OR NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_held) OR NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_live)
     OR (SELECT coalesce(low_action, '') || cardinality(reasons) || coalesce(rank_detail::text, '') || state FROM public.dating_introductions WHERE id = v_i)
        IS DISTINCT FROM '0passed'
     OR EXISTS (SELECT 1 FROM public.dating_pair_markers WHERE pair_code = repeat('a', 64))
     OR NOT EXISTS (SELECT 1 FROM public.dating_pair_markers WHERE pair_code = repeat('b', 64))
     OR EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE target_user_id = e AND signal_kind = 'dragnet')
     OR EXISTS (SELECT 1 FROM public.dating_opener_hashes WHERE hash = repeat('c', 64))
     OR (SELECT coalesce(at_risk_user_id::text, '') || coalesce(sender_user_id::text, '') || coalesce(match_id::text, '') || family
           FROM public.dating_safety_events WHERE id = v_ev) IS DISTINCT FROM 'financial_request' THEN -- Task 8 Ruling P-4
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge answered % and left the wrong rows', v;
  END IF;
  IF pg_temp.probe(ARRAY['CREATE FUNCTION pg_temp.w6_boom() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''w6:boom''; END $f$',
                         'CREATE TRIGGER w6_boom BEFORE DELETE ON public.dating_opener_hashes FOR EACH ROW EXECUTE FUNCTION pg_temp.w6_boom()',
                         format('INSERT INTO public.dating_opener_hashes (sender_user_id, match_id, hash, created_at) VALUES (%L, %L, %L, now() - interval ''31 days'')',
                                a, v_live, repeat('e', 64)),
                         format('INSERT INTO public.dating_pair_markers (pair_code, purge_after) VALUES (%L, now() - interval ''1 day'')', repeat('d', 64)),
                         -- health is STABLE: it reads the counter in a statement after the purge's
                         'CREATE FUNCTION pg_temp.w6_purge_then_health() RETURNS text LANGUAGE plpgsql AS $f$
                          DECLARE r jsonb; BEGIN
                            r := public.purge_dating_retention();
                            RETURN (r ->> ''opener_hashes'') || '':'' || (r ->> ''pair_markers'') || '':'' || pg_temp.metric(''dating.purge.failed.opener_hashes'')
                                   || '':'' || coalesce(public.get_dating_operational_health() -> ''purge_failed_7d'' ->> ''opener_hashes'', ''0'');
                          END $f$'],
       $p$SELECT pg_temp.w6_purge_then_health()$p$)
     IS DISTINCT FROM 'failed:P0001:1:' || (pg_temp.metric('dating.purge.failed.opener_hashes') + 1)
                      || ':' || (coalesce((public.get_dating_operational_health() -> 'purge_failed_7d' ->> 'opener_hashes')::bigint, 0) + 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one failing purge step stopped the others, or was not counted (or health does not show it)';
  END IF;
END $$;

-- V2 (Task 8 fix round 1, I-1): every step keeps what is still inside its
-- window: a closed match inside its 30 days, one under a case in review; a
-- resolved introduction under 30 days, a live one however old (and an old
-- resolved one loses its interest actions); a decided case under 2 years;
-- an opener under 30 days; an event under 90 days (one over 90 loses its
-- message too); a pending outbox row however old, a done one under 7 days
-- (one over 7 goes); a rate limit under 2 days (one over goes); a phone
-- HMAC block and a Dating enforcement record before their purge dates (each
-- past one goes), and an Opinions record past its date (not the Dating
-- purge's); a session context under 30 days (one over goes).
DO $$
DECLARE
  a constant uuid := pg_temp.ready('ba', '{"phone": "926"}');
  b constant uuid := pg_temp.ready('bb', '{"identity": "man", "seeking": ["woman"], "phone": "927"}');
  c constant uuid := pg_temp.ready('bc', '{"identity": "man", "seeking": ["woman"], "phone": "928"}');
  d constant uuid := pg_temp.ready('bd', '{"identity": "man", "seeking": ["woman"], "phone": "929"}');
  e constant uuid := pg_temp.ready('be', '{"identity": "man", "seeking": ["woman"], "phone": "930"}');
  f constant uuid := pg_temp.ready('bf', '{"phone": "931"}');
  v_window uuid;
  v_review uuid;
  v_live uuid;
  v_i_young uuid;
  v_i_live uuid;
  v_i_old uuid;
  v_msg uuid[];
  v_ev_young uuid;
  v_ev_old uuid;
  v_bad text[] := '{}';
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, closed_reason, evidence_until)
  VALUES (least(a, b), greatest(a, b), 'unmatched', 'unmatched', now() + interval '1 day') RETURNING id INTO v_window;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, closed_reason, evidence_until)
  VALUES (least(a, c), greatest(a, c), 'blocked', 'blocked', now() - interval '1 day') RETURNING id INTO v_review;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, match_id, signal_kind, state)
  VALUES ('signal', 'P1', c, v_review, 'money_asks', 'in_review');
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, d), greatest(a, d), 'active') RETURNING id INTO v_live;
  -- Introductions: resolved 3 days ago; live and old; resolved long ago with an interest action.
  v_i_young := pg_temp.intro(b, f);
  UPDATE public.dating_introductions SET state = 'passed', low_action = 'passed', reasons = ARRAY['same_region'], rank_detail = '{"f": 1}',
         created_at = now() - interval '10 days', expires_at = now() - interval '3 days' WHERE id = v_i_young;
  v_i_live := pg_temp.intro(c, f);
  UPDATE public.dating_introductions SET state = 'presented', low_action = 'interested', reasons = ARRAY['same_region'], rank_detail = '{"f": 1}',
         created_at = now() - interval '40 days', expires_at = now() - interval '33 days' WHERE id = v_i_live;
  v_i_old := pg_temp.intro(d, f);
  UPDATE public.dating_introductions SET state = 'expired', created_at = now() - interval '40 days', expires_at = now() - interval '33 days'
   WHERE id = v_i_old;
  INSERT INTO public.dating_interest_actions (introduction_id, actor_user_id, action, idempotency_key, acted_at)
  VALUES (v_i_old, d, 'interested', 'w6-v2-action', now() - interval '35 days');
  -- A decided case a year old; an opener 29 days old.
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind, state, created_at)
  VALUES ('signal', 'P2', e, 'dragnet', 'decided', now() - interval '1 year');
  INSERT INTO public.dating_opener_hashes (sender_user_id, match_id, hash, created_at) VALUES (a, v_live, repeat('7', 64), now() - interval '29 days');
  -- Messages in the live match for the events and the outbox.
  WITH x AS (
    INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, body, body_masked, mask_version, idempotency_key)
    SELECT v_live, CASE WHEN a < d THEN 'low' ELSE 'high' END, a, 'v2 ' || n, 'v2 ' || n, 1, 'w6-v2-msg-' || n FROM generate_series(1, 4) AS n
    RETURNING id, idempotency_key)
  SELECT array_agg(x.id ORDER BY x.idempotency_key) INTO v_msg FROM x;
  INSERT INTO public.dating_safety_events (match_id, message_id, at_risk_user_id, sender_user_id, rule_id, family, tier, config_version, source_event_key, created_at)
  VALUES (v_live, v_msg[1], d, a, 'financial_request:x', 'financial_request', 2, 'dating_chat_v1', 'w6-v2-young', now() - interval '89 days')
  RETURNING id INTO v_ev_young;
  INSERT INTO public.dating_safety_events (match_id, message_id, at_risk_user_id, sender_user_id, rule_id, family, tier, config_version, source_event_key, created_at)
  VALUES (v_live, v_msg[2], d, a, 'financial_request:x', 'financial_request', 2, 'dating_chat_v1', 'w6-v2-old', now() - interval '91 days')
  RETURNING id INTO v_ev_old;
  INSERT INTO public.dating_message_safety_outbox (message_id, state, created_at, completed_at)
  VALUES (v_msg[1], 'pending', now() - interval '30 days', NULL),
         (v_msg[2], 'done', now() - interval '30 days', now() - interval '1 day'),
         (v_msg[3], 'done', now() - interval '30 days', now() - interval '8 days');
  INSERT INTO public.dating_rate_limits (user_id, operation, window_started_at, request_count)
  VALUES (a, 'w6_v2_young', now() - interval '1 day', 1), (a, 'w6_v2_old', now() - interval '3 days', 1);
  INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac, purge_after)
  VALUES (repeat('3', 64), repeat('4', 64), now() + interval '1 day'), (repeat('5', 64), repeat('6', 64), now() - interval '1 day');
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, purge_after, created_at)
  VALUES (repeat('8', 64), 'dating', 'suspended', now() + interval '1 day', now() - interval '1 year'),
         (repeat('9', 64), 'opinions', 'opinions_standing', now() - interval '1 day', now() - interval '2 years'),
         (repeat('a', 64), 'dating', 'suspended', now() - interval '1 day', now() - interval '2 years');
  INSERT INTO public.dating_session_context (user_id, effective_tier, dating_allowed_here, same_gender_allowed_here, away_from_home, ip_resolved, checked_at)
  VALUES (e, 1, true, true, false, true, now() - interval '1 day'), (f, 1, true, true, false, true, now() - interval '31 days')
  ON CONFLICT (user_id) DO UPDATE SET checked_at = EXCLUDED.checked_at;
  PERFORM public.purge_dating_retention();
  IF NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_window) THEN v_bad := v_bad || 'a closed match inside its 30 days went'::text; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_review) THEN v_bad := v_bad || 'a match under a case in review went'::text; END IF;
  IF (SELECT coalesce(low_action, '') || cardinality(reasons) || coalesce(rank_detail::text, '') FROM public.dating_introductions WHERE id = v_i_young)
     IS DISTINCT FROM 'passed1{"f": 1}' THEN v_bad := v_bad || 'a resolved introduction under 30 days lost its details'::text; END IF;
  IF (SELECT coalesce(low_action, '') || cardinality(reasons) || coalesce(rank_detail::text, '') FROM public.dating_introductions WHERE id = v_i_live)
     IS DISTINCT FROM 'interested1{"f": 1}' THEN v_bad := v_bad || 'a live introduction lost its details'::text; END IF;
  IF EXISTS (SELECT 1 FROM public.dating_interest_actions WHERE introduction_id = v_i_old) THEN
    v_bad := v_bad || 'an old resolved introduction kept its interest actions'::text; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE target_user_id = e AND signal_kind = 'dragnet') THEN
    v_bad := v_bad || 'a decided case under 2 years went'::text; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_opener_hashes WHERE hash = repeat('7', 64)) THEN v_bad := v_bad || 'an opener under 30 days went'::text; END IF;
  IF (SELECT (at_risk_user_id, sender_user_id, match_id, message_id, source_event_key)::text FROM public.dating_safety_events WHERE id = v_ev_young)
     IS DISTINCT FROM (d, a, v_live, v_msg[1], 'w6-v2-young')::text THEN v_bad := v_bad || 'an event under 90 days was anonymised'::text; END IF;
  IF (SELECT message_id FROM public.dating_safety_events WHERE id = v_ev_old) IS NOT NULL THEN
    v_bad := v_bad || 'an event over 90 days still names its message'::text; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_message_safety_outbox WHERE message_id = v_msg[1]) THEN v_bad := v_bad || 'a pending outbox row went'::text; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_message_safety_outbox WHERE message_id = v_msg[2]) THEN v_bad := v_bad || 'a done outbox row under 7 days went'::text; END IF;
  IF EXISTS (SELECT 1 FROM public.dating_message_safety_outbox WHERE message_id = v_msg[3]) THEN v_bad := v_bad || 'a done outbox row over 7 days stayed'::text; END IF;
  IF (SELECT array_agg(operation ORDER BY operation) FROM public.dating_rate_limits WHERE user_id = a AND operation LIKE 'w6_v2_%')
     IS DISTINCT FROM ARRAY['w6_v2_young'] THEN v_bad := v_bad || 'the rate limits kept are not exactly the one under 2 days'::text; END IF;
  IF (SELECT array_agg(blocker_hmac ORDER BY blocker_hmac) FROM public.dating_block_hmacs WHERE blocker_hmac IN (repeat('3', 64), repeat('5', 64)))
     IS DISTINCT FROM ARRAY[repeat('3', 64)] THEN v_bad := v_bad || 'the phone HMAC blocks kept are not exactly the one before its purge date'::text; END IF;
  IF (SELECT array_agg(phone_hmac ORDER BY phone_hmac) FROM public.enforcement_records WHERE phone_hmac IN (repeat('8', 64), repeat('9', 64), repeat('a', 64)))
     IS DISTINCT FROM ARRAY[repeat('8', 64), repeat('9', 64)] THEN
    v_bad := v_bad || 'the enforcement records kept are not the Dating one before its date and the Opinions one'::text; END IF;
  IF (SELECT array_agg(user_id ORDER BY user_id) FROM public.dating_session_context WHERE user_id IN (e, f)) IS DISTINCT FROM ARRAY[e] THEN
    v_bad := v_bad || 'the session contexts kept are not exactly the one under 30 days'::text; END IF;
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge broke a retention window: %', array_to_string(v_bad, '; ');
  END IF;
END $$;

-- =====================================================================
-- W. (§2.3; W5 final review I-1) W6c's read refreshes the phone's last
--    use as PostgREST calls it (VOLATILE).
-- =====================================================================
DO $$
BEGIN
  IF (SELECT p.provolatile FROM pg_proc AS p WHERE p.oid = 'public.get_dating_guided_state(uuid)'::regprocedure) <> 'v'
     OR (SELECT p.provolatile FROM pg_proc AS p WHERE p.oid = 'public.get_my_dating_safety_cards(uuid)'::regprocedure) <> 'v' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a device-checked chat read is not VOLATILE (PostgREST would run it read-only)';
  END IF;
END $$;

-- =====================================================================
-- Y. (Task 8: the live server's rules for W6c; R-45, R-46, carries W6a
--    M-8, W6b N-1, N-4, M-6) People a1-af (hex, unused by A-X), phones
--    +1555960901-915.
-- =====================================================================
-- Y1 (carry W6a M-8): the dragnet's "wrote in" counts a text or a guided
-- answer, never the Close kindly message.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('a1', '{"phone": "901"}');
  b constant uuid := pg_temp.ready('a2', '{"identity": "man", "seeking": ["woman"], "phone": "902"}');
  v_i constant uuid := pg_temp.intro(pg_temp.id('a1'), pg_temp.id('a2'));
  v_m uuid;
BEGIN
  UPDATE public.dating_introductions SET state = 'matched' WHERE id = v_i;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, introduction_id)
  VALUES (least(a, b), greatest(a, b), 'active', v_i) RETURNING id INTO v_m;
  PERFORM pg_temp.j(a, 'a1', format('SELECT public.send_dating_message(%L, %L, ''Market, then football'', ''guided_answer'', ''good_saturday'')', pg_temp.key('y1a'), v_m));
  PERFORM pg_temp.j(b, 'a2', format('SELECT public.close_dating_match_kindly(%L, %L)', pg_temp.key('y1b'), v_m));
  IF (SELECT count(*) FROM public.dating_messages WHERE match_id = v_m) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Y1 setup: the answer and the Close kindly message were not both written';
  END IF;
  IF private.dating_first_messages(a, now() - interval '1 day', clock_timestamp()) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a guided answer is not writing in for the dragnet';
  END IF;
  IF private.dating_first_messages(b, now() - interval '1 day', clock_timestamp()) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Close kindly message counted as writing in (carry M-8)';
  END IF;
END $$;

-- Y2 (W6b N-1): the side's opener is its first text message, whatever
-- guided answer came before it.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('a3', '{"phone": "903"}');
  b constant uuid := pg_temp.ready('a4', '{"identity": "man", "seeking": ["woman"], "phone": "904"}');
  v_m uuid;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  PERFORM pg_temp.j(a, 'a3', format('SELECT public.send_dating_message(%L, %L, ''Church, then jollof with my cousins'', ''guided_answer'', ''good_saturday'')', pg_temp.key('y2a'), v_m));
  IF NOT EXISTS (SELECT 1 FROM public.dating_messages WHERE match_id = v_m AND kind = 'guided_answer')
     OR EXISTS (SELECT 1 FROM public.dating_opener_hashes WHERE sender_user_id = a AND match_id = v_m) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the guided answer was not taken, or was kept as the opener';
  END IF;
  PERFORM pg_temp.j(a, 'a3', format('SELECT public.send_dating_message(%L, %L, ''Hey there, how is your week going?'')', pg_temp.key('y2b'), v_m));
  IF (SELECT hash FROM public.dating_opener_hashes WHERE sender_user_id = a AND match_id = v_m)
     IS DISTINCT FROM private.dating_opener_hash('Hey there, how is your week going?')
     OR private.dating_opener_hash('Hey there, how is your week going?') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first text message after a guided answer is not the opener';
  END IF;
END $$;

-- Y3 (R-45): an answer the other can't see yet tells them nothing: no
-- bump, no push, no card under it; the answer that shows both does all
-- three. A safety event on the hidden answer shows its card once shown.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('a5', '{"phone": "905"}');
  b constant uuid := pg_temp.ready('a6', '{"identity": "man", "seeking": ["woman"], "phone": "906"}');
  v_m uuid;
  v_msg uuid;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  v_msg := (pg_temp.j(a, 'a5', format('SELECT public.send_dating_message(%L, %L, ''Send me 200 cedis first'', ''guided_answer'', ''good_saturday'')', pg_temp.key('y3a'), v_m))
            #>> '{message,id}')::uuid;
  INSERT INTO public.dating_safety_events (match_id, message_id, at_risk_user_id, sender_user_id, rule_id, family, tier, config_version, source_event_key)
  VALUES (v_m, v_msg, b, a, 'financial_request:send me', 'financial_request', 1, 'dating_chat_v1', 'w6-y3-event');
  IF v_msg IS NULL
     OR EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = b AND match_id = v_m)
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = b AND metadata ->> 'type' = 'me_update') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hidden guided answer bumped or pushed the other (R-45)';
  END IF;
  IF jsonb_array_length(pg_temp.j(b, 'a6', format('SELECT public.get_my_dating_safety_cards(%L)', v_m)) -> 'cards') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a card showed under a guided answer not shown yet (R-45)';
  END IF;
  PERFORM pg_temp.j(b, 'a6', format('SELECT public.send_dating_message(%L, %L, ''Football all day'', ''guided_answer'', ''good_saturday'')', pg_temp.key('y3b'), v_m));
  IF NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = a AND match_id = v_m)
     OR NOT EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = a AND metadata ->> 'type' = 'me_update' AND status = 'pending') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the answer that shows both did not bump or push the other';
  END IF;
  IF jsonb_array_length(pg_temp.j(b, 'a6', format('SELECT public.get_my_dating_safety_cards(%L)', v_m)) -> 'cards') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the card did not show once the answer was shown';
  END IF;
END $$;

-- Y4 (every closing path bumps; the HMAC-only block): We met tells the
-- other's chat; Close kindly tells both members' chats; a pair blocked by
-- phone HMAC alone (the header says ended) can't be closed kindly, marked
-- met or skipped, and nothing is written.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('a7', '{"phone": "907"}');
  b constant uuid := pg_temp.ready('a8', '{"identity": "man", "seeking": ["woman"], "phone": "908"}');
  f constant uuid := pg_temp.ready('a9', '{"phone": "909"}');
  g constant uuid := pg_temp.ready('aa', '{"identity": "man", "seeking": ["woman"], "phone": "910"}');
  v_m uuid;
  v_fg uuid;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(f, g), greatest(f, g), 'active') RETURNING id INTO v_fg;
  PERFORM pg_temp.j(a, 'a7', format('SELECT public.mark_dating_we_met(%L)', v_m));
  IF NOT EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = b AND match_id = v_m) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: We met did not tell the other''s chat';
  END IF;
  DELETE FROM public.dating_chat_signals WHERE match_id = v_m;
  PERFORM pg_temp.j(a, 'a7', format('SELECT public.close_dating_match_kindly(%L, %L)', pg_temp.key('y4a'), v_m));
  IF (SELECT count(DISTINCT user_id) FROM public.dating_chat_signals WHERE match_id = v_m AND user_id IN (a, b)) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Close kindly did not tell both members'' chats';
  END IF;
  INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
  VALUES (public.dating_phone_hmac_for_user(g), public.dating_phone_hmac_for_user(f));
  IF pg_temp.j(f, 'a9', format('SELECT public.close_dating_match_kindly(%L, %L)', pg_temp.key('y4b'), v_fg)) ->> 'reason' IS DISTINCT FROM 'closed'
     OR pg_temp.j(f, 'a9', format('SELECT public.mark_dating_we_met(%L)', v_fg)) ->> 'reason' IS DISTINCT FROM 'closed'
     OR pg_temp.j(f, 'a9', format('SELECT public.skip_dating_guided_question(%L, ''good_saturday'')', v_fg)) ->> 'reason' IS DISTINCT FROM 'closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pair blocked by phone HMAC alone was closed kindly, marked met or skipped';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_messages WHERE match_id = v_fg) OR EXISTS (SELECT 1 FROM public.dating_guided_skips WHERE match_id = v_fg)
     OR EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE match_id = v_fg)
     OR (SELECT low_we_met_at IS NOT NULL OR high_we_met_at IS NOT NULL FROM public.dating_matches WHERE id = v_fg) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: something was written to a pair blocked by phone HMAC alone';
  END IF;
END $$;

-- Y5 (§4.8; W6b N-4, carry M-6): a closed match past its window stays while
-- a safety event about it is inside the 7-day evidence window; an
-- anonymised event's key no longer names its message; a case still open
-- after 2 years stays; a step that deadlocks once is retried and done, one
-- that always deadlocks is skipped and counted once; the purge never waits
-- long on a lock.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('ab', '{"phone": "911"}');
  b constant uuid := pg_temp.ready('ac', '{"identity": "man", "seeking": ["woman"], "phone": "912"}');
  e constant uuid := pg_temp.ready('ad', '{"identity": "man", "seeking": ["woman"], "phone": "913"}');
  v_held uuid;
  v_live uuid;
  v_ev uuid;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, closed_reason, evidence_until)
  VALUES (least(a, b), greatest(a, b), 'unmatched', 'unmatched', now() - interval '1 day') RETURNING id INTO v_held;
  INSERT INTO public.dating_safety_events (match_id, at_risk_user_id, sender_user_id, rule_id, family, tier, config_version, source_event_key, created_at)
  VALUES (v_held, NULL, b, 'financial_request:x', 'financial_request', 2, 'dating_chat_v1', 'w6-y5-recent', now() - interval '1 day');
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, e), greatest(a, e), 'active') RETURNING id INTO v_live;
  INSERT INTO public.dating_safety_events (match_id, at_risk_user_id, sender_user_id, rule_id, family, tier, config_version, source_event_key, created_at)
  VALUES (v_live, a, e, 'financial_request:x', 'financial_request', 2, 'dating_chat_v1', gen_random_uuid()::text || ':financial_request:x',
          now() - interval '91 days') RETURNING id INTO v_ev;
  INSERT INTO public.dating_moderation_cases (kind, priority, target_user_id, signal_kind, state, created_at)
  VALUES ('signal', 'P2', e, 'duplicate_opener', 'open', now() - interval '2 years 1 day');
  PERFORM public.purge_dating_retention();
  IF NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_held) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge deleted a match whose safety event is inside the evidence window (W6b N-4)';
  END IF;
  IF (SELECT source_event_key FROM public.dating_safety_events WHERE id = v_ev) IS DISTINCT FROM 'anon:' || v_ev::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an anonymised safety event still names its message (its key)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE target_user_id = e AND signal_kind = 'duplicate_opener') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge deleted a case still open';
  END IF;
  IF NOT coalesce((SELECT p.proconfig FROM pg_proc AS p WHERE p.oid = 'private.dating_purge_step(text,timestamptz)'::regprocedure) -- fix round 1 (M-1): each step
                  @> ARRAY['lock_timeout=5s'], false) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge may wait without bound on a lock';
  END IF;
  -- Deadlocks once: retried, done, one retry counted, no failure.
  IF pg_temp.probe(ARRAY['CREATE TEMP SEQUENCE w6_dl_seq',
                         'CREATE FUNCTION pg_temp.w6_dl_once() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN
                            IF nextval(''pg_temp.w6_dl_seq'') = 1 THEN RAISE EXCEPTION ''w6:deadlock'' USING ERRCODE = ''40P01''; END IF;
                            RETURN OLD; END $f$',
                         'CREATE TRIGGER w6_dl_once BEFORE DELETE ON public.dating_opener_hashes FOR EACH ROW EXECUTE FUNCTION pg_temp.w6_dl_once()',
                         format('INSERT INTO public.dating_opener_hashes (sender_user_id, match_id, hash, created_at) VALUES (%L, %L, %L, now() - interval ''31 days'')',
                                a, v_live, repeat('f', 64)),
                         'CREATE FUNCTION pg_temp.w6_purge_once() RETURNS text LANGUAGE plpgsql AS $f$
                          DECLARE r jsonb; BEGIN
                            r := public.purge_dating_retention();
                            RETURN (r ->> ''opener_hashes'') || '':'' || pg_temp.metric(''dating.purge.retried'') || '':'' || pg_temp.metric(''dating.purge.failed.opener_hashes'');
                          END $f$'],
       $p$SELECT pg_temp.w6_purge_once()$p$)
     IS DISTINCT FROM '1:' || (pg_temp.metric('dating.purge.retried') + 1) || ':' || pg_temp.metric('dating.purge.failed.opener_hashes') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a step that deadlocked once was not retried and done (carry M-6)';
  END IF;
  -- Always deadlocks: skipped after 3 tries, failed once, 2 retries counted.
  IF pg_temp.probe(ARRAY['CREATE FUNCTION pg_temp.w6_dl_always() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN
                            RAISE EXCEPTION ''w6:deadlock'' USING ERRCODE = ''40P01''; END $f$',
                         'CREATE TRIGGER w6_dl_always BEFORE DELETE ON public.dating_opener_hashes FOR EACH ROW EXECUTE FUNCTION pg_temp.w6_dl_always()',
                         format('INSERT INTO public.dating_opener_hashes (sender_user_id, match_id, hash, created_at) VALUES (%L, %L, %L, now() - interval ''31 days'')',
                                a, v_live, repeat('f', 64)),
                         'CREATE FUNCTION pg_temp.w6_purge_always() RETURNS text LANGUAGE plpgsql AS $f$
                          DECLARE r jsonb; BEGIN
                            r := public.purge_dating_retention();
                            RETURN (r ->> ''opener_hashes'') || '':'' || (r ->> ''pair_markers'') || '':'' || pg_temp.metric(''dating.purge.retried'')
                                   || '':'' || pg_temp.metric(''dating.purge.failed.opener_hashes'');
                          END $f$'],
       $p$SELECT pg_temp.w6_purge_always()$p$)
     IS DISTINCT FROM 'failed:40P01:0:' || (pg_temp.metric('dating.purge.retried') + 2) || ':' || (pg_temp.metric('dating.purge.failed.opener_hashes') + 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a step that always deadlocks was not skipped after 3 tries and counted once (carry M-6)';
  END IF;
END $$;

-- Y6 (R-46; W6b fix rounds 3-4): a pending check-in neither holds a chat
-- push back nor is held by one.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('ae', '{"phone": "914"}');
  b constant uuid := pg_temp.ready('af', '{"identity": "man", "seeking": ["woman"], "phone": "915"}');
  v_m uuid;
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  UPDATE public.users SET timezone = NULL WHERE id = b;
  PERFORM pg_temp.j(b, 'af', format('SELECT public.schedule_dating_checkin(%L)', now() + interval '1 hour'));
  PERFORM pg_temp.j(a, 'ae', format('SELECT public.send_dating_message(%L, %L, ''Hello there'')', pg_temp.key('y6a'), v_m));
  IF NOT EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending' AND metadata ->> 'type' = 'me_update') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pending check-in held a chat push back';
  END IF;
  PERFORM pg_temp.j(b, 'af', format('SELECT public.schedule_dating_checkin(%L)', now() + interval '2 hours'));
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending' AND metadata ->> 'type' = 'me_checkin') <> 1
     OR (SELECT scheduled_for FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending' AND metadata ->> 'type' = 'me_checkin')
        IS DISTINCT FROM now() + interval '2 hours' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pending chat push held the check-in back, or the new one did not replace the last';
  END IF;
END $$;

-- Y7 (Task 8 fix round 1, M-1, M-2, M-3, M-8): the cron CALLs the purge
-- procedure (it commits per step; no API role may call it); events are
-- found by message without a scan; a private date reflection outlives the
-- purged match; Close kindly's key replays only a Close kindly message.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('c4', '{"phone": "936"}');
  b constant uuid := pg_temp.ready('c5', '{"identity": "man", "seeking": ["woman"], "phone": "937"}');
  c constant uuid := pg_temp.ready('c6', '{"phone": "938"}');
  d constant uuid := pg_temp.ready('c7', '{"identity": "man", "seeking": ["woman"], "phone": "939"}');
  k constant text := pg_temp.key('y7');
  v_gone uuid;
  v_m uuid;
BEGIN
  IF (SELECT p.prokind FROM pg_proc AS p WHERE p.oid = to_regprocedure('public.run_dating_retention_purge(timestamptz)')) IS DISTINCT FROM 'p'
     OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-dating-retention' AND schedule = '47 2 * * *'
                                            AND command = 'CALL public.run_dating_retention_purge()')
     OR has_function_privilege('anon', 'public.run_dating_retention_purge(timestamptz)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.run_dating_retention_purge(timestamptz)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.run_dating_retention_purge(timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the cron does not CALL the per-step purge procedure daily at 02:47, or an API role may call it (M-1)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_index AS i JOIN pg_attribute AS t ON t.attrelid = i.indrelid AND t.attnum = i.indkey[0]
                  WHERE i.indrelid = 'public.dating_safety_events'::regclass AND t.attname = 'message_id') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no index leads with dating_safety_events.message_id (M-2)';
  END IF;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, closed_reason, evidence_until)
  VALUES (least(a, b), greatest(a, b), 'closed', 'closed_kindly', now() - interval '1 day') RETURNING id INTO v_gone;
  INSERT INTO public.dating_date_reflections (match_id, author_user_id, response, idempotency_key) VALUES (v_gone, a, 'good', 'w6-y7-reflection');
  PERFORM public.purge_dating_retention();
  IF EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_gone)
     OR NOT EXISTS (SELECT 1 FROM public.dating_date_reflections WHERE idempotency_key = 'w6-y7-reflection' AND author_user_id = a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purged match took its member''s private date reflection with it (M-3)';
  END IF;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(c, d), greatest(c, d), 'active') RETURNING id INTO v_m;
  PERFORM pg_temp.j(c, 'c6', format('SELECT public.send_dating_message(%L, %L, ''Hello there'')', k, v_m));
  IF pg_temp.j(c, 'c6', format('SELECT public.close_dating_match_kindly(%L, %L)', k, v_m)) ->> 'reason' IS DISTINCT FROM 'invalid'
     OR (SELECT state FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'active'
     OR (SELECT count(*) FROM public.dating_messages WHERE match_id = v_m) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Close kindly with a text message''s key answered ok or closed the match (M-8)';
  END IF;
END $$;

-- Z (Task 9 fix round 1, I-2; §3.6 "both answers appear together"): a
-- guided answer sits at its own time while it waits, and both sit at the
-- reveal (the later answer's time) once both answered, whatever was
-- written between; a page never splits the pair.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('c8');
  b constant uuid := pg_temp.ready('c9', '{"identity": "man", "seeking": ["woman"]}');
  v_m uuid;
  v_a uuid;
  v_b uuid;
  v_t uuid[];
  v jsonb;
  v_got text[] := '{}';
  v_before text;
  v_pages integer := 0;
  v_page text[];
BEGIN
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  v_a := (pg_temp.j(a, 'c8', format('SELECT public.send_dating_message(%L, %L, ''Market'', ''guided_answer'', ''good_saturday'')', pg_temp.key('z1'), v_m)) #>> '{message,id}')::uuid;
  UPDATE public.dating_messages SET created_at = now() - interval '60 minutes' WHERE id = v_a;
  FOR i IN 1..3 LOOP
    v_t[i] := (pg_temp.j(CASE WHEN i % 2 = 1 THEN b ELSE a END, CASE WHEN i % 2 = 1 THEN 'c9' ELSE 'c8' END,
                         format('SELECT public.send_dating_message(%L, %L, %L)', pg_temp.key('zt' || i), v_m, 'Text ' || i)) #>> '{message,id}')::uuid;
    UPDATE public.dating_messages SET created_at = now() - make_interval(mins => 60 - 10 * i) WHERE id = v_t[i];
  END LOOP;
  -- Waiting: this side's answer sits at its own time (oldest).
  v := pg_temp.j(a, 'c8', format('SELECT public.get_dating_messages(%L)', v_m)) -> 'messages';
  IF v -> -1 ->> 'id' IS DISTINCT FROM v_a::text OR jsonb_array_length(v) <> 4 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a waiting answer did not sit at its own time (%)', v;
  END IF;
  v_b := (pg_temp.j(b, 'c9', format('SELECT public.send_dating_message(%L, %L, ''Church'', ''guided_answer'', ''good_saturday'')', pg_temp.key('z2'), v_m)) #>> '{message,id}')::uuid;
  UPDATE public.dating_messages SET created_at = now() - interval '20 minutes' WHERE id = v_b;
  v_t[4] := (pg_temp.j(a, 'c8', format('SELECT public.send_dating_message(%L, %L, ''After'')', pg_temp.key('zt4'), v_m)) #>> '{message,id}')::uuid;
  UPDATE public.dating_messages SET created_at = now() - interval '10 minutes' WHERE id = v_t[4];
  -- Revealed: both sit together at the reveal, newest first: After, the pair, Text 3, 2, 1.
  v := pg_temp.j(a, 'c8', format('SELECT public.get_dating_messages(%L)', v_m)) -> 'messages';
  IF jsonb_array_length(v) <> 6 OR v -> 0 ->> 'id' IS DISTINCT FROM v_t[4]::text
     OR ARRAY[v -> 1 ->> 'id', v -> 2 ->> 'id'] <@ ARRAY[v_a::text, v_b::text] IS NOT TRUE
     OR v -> 1 ->> 'id' = v -> 2 ->> 'id'
     OR (v -> 1 ->> 'at')::timestamptz IS DISTINCT FROM (v -> 2 ->> 'at')::timestamptz
     OR (v -> 1 ->> 'at')::timestamptz IS DISTINCT FROM (SELECT created_at FROM public.dating_messages WHERE id = v_b)
     OR ARRAY[v -> 3 ->> 'id', v -> 4 ->> 'id', v -> 5 ->> 'id'] IS DISTINCT FROM ARRAY[v_t[3]::text, v_t[2]::text, v_t[1]::text] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a revealed pair did not sit together at the reveal (%)', v;
  END IF;
  -- Pages of 2: the pair is never split, every message comes once, in order.
  LOOP
    v := pg_temp.j(b, 'c9', format('SELECT public.get_dating_messages(%L, %L, 2)', v_m, v_before));
    v_pages := v_pages + 1;
    v_page := ARRAY(SELECT x ->> 'id' FROM jsonb_array_elements(v -> 'messages') AS x);
    IF (v_a::text = ANY (v_page)) <> (v_b::text = ANY (v_page)) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a page split a revealed pair (page %: %)', v_pages, v;
    END IF;
    v_got := v_got || v_page;
    EXIT WHEN (v ->> 'more')::boolean IS NOT TRUE OR v_pages > 6;
    v_before := v -> 'messages' -> -1 ->> 'at';
  END LOOP;
  IF cardinality(v_got) <> 6 OR (SELECT count(DISTINCT x) FROM unnest(v_got) AS x) <> 6
     OR v_got[1] IS DISTINCT FROM v_t[4]::text OR v_got[6] IS DISTINCT FROM v_t[1]::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the pages did not give every message once, in order (%)', v_got;
  END IF;
END $$;

-- @@W6-FINAL@@

-- =====================================================================
-- FF. (W6 final server review, fixed in the final server fix wave) People
--    e0-ef and f0-ff (hex, unused by A-Z), phones +1555960970-999. Each
--    block is its own case; every one failed on the tree before the fix.
-- =====================================================================
-- [p_sqls] in [p_env], then the transaction's end-state checks as at
-- commit (the deferred config guard made immediate), then all undone (a
-- savepoint): 'ok' or the error's message.
CREATE FUNCTION pg_temp.ff_tx(p_env text, p_sqls text[]) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text := 'ok';
  q text;
BEGIN
  BEGIN
    PERFORM set_config('app.settings.attune_environment', p_env, true);
    FOREACH q IN ARRAY p_sqls LOOP
      EXECUTE q;
    END LOOP;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'dating_safety_configs_chat_keeps_active' AND tgdeferrable) THEN
      EXECUTE 'SET CONSTRAINTS public.dating_safety_configs_chat_keeps_active IMMEDIATE';
    END IF;
    RAISE EXCEPTION 'ff:undo';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM IS DISTINCT FROM 'ff:undo' THEN
      v := SQLERRM;
    END IF;
  END;
  PERFORM set_config('app.settings.attune_environment', '', true);
  RETURN v;
END $$;
-- A matched pair, [p_age] old, and its match.
CREATE FUNCTION pg_temp.ff_match(p_a uuid, p_b uuid, p_age interval DEFAULT interval '1 hour') RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at)
  VALUES (least(p_a, p_b), greatest(p_a, p_b), 'active', now() - p_age) RETURNING id;
$$;

-- FF1 (I-1, W6 T8 M-7): a suspension closes the match as account_restricted
-- with its 30-day evidence window: the other person still reads the ended
-- chat and finds it among the ended ones, and the purge removes it after
-- the window (not before). Every other closing reason names itself too;
-- a writer that leaves the window out still gets one (the trigger); no
-- closed match is left without one (the CHECK).
DO $$
DECLARE
  a constant uuid := pg_temp.ready('e0', '{"phone": "970"}');
  b constant uuid := pg_temp.ready('e1', '{"identity": "man", "seeking": ["woman"], "phone": "971"}');
  c constant uuid := pg_temp.ready('e2', '{"phone": "972"}');
  d constant uuid := pg_temp.ready('e3', '{"identity": "man", "seeking": ["woman"], "phone": "973"}');
  e constant uuid := pg_temp.ready('e4', '{"phone": "974"}');
  f constant uuid := pg_temp.ready('e5', '{"identity": "man", "seeking": ["woman"], "phone": "975"}');
  g constant uuid := pg_temp.ready('e6', '{"phone": "976"}');
  h constant uuid := pg_temp.ready('e7', '{"identity": "man", "seeking": ["woman"], "phone": "977"}');
  v_m constant uuid := pg_temp.ff_match(pg_temp.id('e0'), pg_temp.id('e1'));
  v_cd constant uuid := pg_temp.ff_match(pg_temp.id('e2'), pg_temp.id('e3'));
  v_ef constant uuid := pg_temp.ff_match(pg_temp.id('e4'), pg_temp.id('e5'));
  v_gh constant uuid := pg_temp.ff_match(pg_temp.id('e6'), pg_temp.id('e7'));
  v_ad uuid;
  v jsonb;
  v_bad text[] := '{}';
BEGIN
  PERFORM pg_temp.j(b, 'e1', format('SELECT public.send_dating_message(%L, %L, ''Hello from the other side'')', pg_temp.key('ff1'), v_m));
  DELETE FROM public.dating_chat_signals WHERE match_id = v_m;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (b, 'suspended');
  IF (SELECT state || '/' || coalesce(closed_reason, '-') || '/' || coalesce((evidence_until BETWEEN now() + interval '29 days' AND now() + interval '31 days')::text, 'none')
        FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'closed/account_restricted/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a suspension closed the match without its reason or its 30-day evidence window: %',
      (SELECT state || '/' || coalesce(closed_reason, '-') || '/' || coalesce(evidence_until::text, 'none') FROM public.dating_matches WHERE id = v_m);
  END IF;
  v := pg_temp.j(a, 'e0', format('SELECT public.get_dating_messages(%L)', v_m));
  IF v ->> 'ok' IS DISTINCT FROM 'true' OR v #>> '{chat,state}' IS DISTINCT FROM 'ended' OR jsonb_array_length(v -> 'messages') <> 1
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(pg_temp.j(a, 'e0', 'SELECT public.get_my_dating_matches(true)') -> 'ended') AS x
                     WHERE x ->> 'match_id' = v_m::text)
     OR (SELECT count(*) FROM public.dating_chat_signals WHERE match_id = v_m AND user_id IN (a, b)) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the other''s suspension the chat is not readable as ended, not in the ended list, or not told: %', v;
  END IF;
  IF pg_temp.probe(ARRAY['SELECT private.dating_purge_step(''matches'', now() + interval ''29 days'')'],
                   format('SELECT (SELECT count(*) FROM public.dating_messages WHERE match_id = %L)::text', v_m)) IS DISTINCT FROM '1'
     OR pg_temp.probe(ARRAY['SELECT private.dating_purge_step(''matches'', now() + interval ''31 days'')'],
                   format('SELECT ((SELECT count(*) FROM public.dating_matches WHERE id = %L) + (SELECT count(*) FROM public.dating_messages WHERE match_id = %L))::text', v_m, v_m))
        IS DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the suspended pair''s match was purged inside its window, or kept after it';
  END IF;
  PERFORM public.invalidate_dating_for_user(c, 'exit');
  PERFORM public.invalidate_dating_for_user(e, 'dating_consent_withdrawn');
  PERFORM public.invalidate_dating_for_user(g, 'profile_deleted');
  SELECT array_agg(x) INTO v_bad FROM (
    SELECT m.id::text || ':' || coalesce(m.closed_reason, '-') || ':' || coalesce(m.evidence_until::text, 'none') AS x
      FROM public.dating_matches AS m
      JOIN (VALUES (v_cd, 'exit'), (v_ef, 'other'), (v_gh, 'account_deleted')) AS w(id, reason) ON w.id = m.id
     WHERE m.state IS DISTINCT FROM 'closed' OR m.closed_reason IS DISTINCT FROM w.reason
        OR m.evidence_until IS NULL OR m.evidence_until < now() + interval '29 days') AS y;
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closing reason left its match unnamed or without its window: %', v_bad;
  END IF;
  -- Structural: a writer that leaves the window out, and the CHECK.
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state)
  VALUES (least(a, d), greatest(a, d), 'closed') RETURNING id INTO v_ad;
  IF (SELECT closed_reason || '/' || (evidence_until > now() + interval '29 days')::text FROM public.dating_matches WHERE id = v_ad)
       IS DISTINCT FROM 'other/true'
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.dating_matches'::regclass
                     AND conname = 'dating_matches_evidence_window_check' AND pg_get_constraintdef(oid) ~ 'evidence_until IS NOT NULL')
     OR EXISTS (SELECT 1 FROM public.dating_matches WHERE state <> 'active' AND evidence_until IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match can be closed without an evidence window';
  END IF;
END $$;

-- FF2 (I-3, M-1; W6 T2 N-2): Dating turned off stops the chat: a send and
-- a swap offer answer unavailable and write nothing (no message, no push),
-- while the reads, a withdrawal and Block still work; an ended chat
-- answers closed whichever flag is off.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('e8', '{"phone": "978"}');
  b constant uuid := pg_temp.ready('e9', '{"identity": "man", "seeking": ["woman"], "phone": "979"}');
  v_m constant uuid := pg_temp.ff_match(pg_temp.id('e8'), pg_temp.id('e9'), interval '80 hours');
  v_bad text[] := '{}';
  v jsonb;
BEGIN
  PERFORM pg_temp.j(a, 'e8', format('SELECT public.offer_dating_contact_swap(%L)', v_m));
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  v := pg_temp.j(a, 'e8', format('SELECT public.send_dating_message(%L, %L, ''still on?'')', pg_temp.key('ff2s'), v_m));
  IF v ->> 'reason' IS DISTINCT FROM 'unavailable' THEN v_bad := v_bad || ('send: ' || v::text); END IF;
  v := pg_temp.j(b, 'e9', format('SELECT public.offer_dating_contact_swap(%L)', v_m));
  IF v ->> 'reason' IS DISTINCT FROM 'unavailable' THEN v_bad := v_bad || ('offer: ' || v::text); END IF;
  IF EXISTS (SELECT 1 FROM public.dating_messages WHERE match_id = v_m)
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = b AND metadata ->> 'type' = 'me_update')
     OR (SELECT high_swap_at IS NOT NULL AND low_swap_at IS NOT NULL FROM public.dating_matches WHERE id = v_m) THEN
    v_bad := v_bad || 'something was written'::text;
  END IF;
  IF pg_temp.j(a, 'e8', format('SELECT public.get_dating_messages(%L)', v_m)) ->> 'ok' IS DISTINCT FROM 'true' THEN
    v_bad := v_bad || 'the read'::text;
  END IF;
  v := pg_temp.j(a, 'e8', format('SELECT public.withdraw_dating_contact_swap(%L)', v_m));
  IF v ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT CASE WHEN user_low_id = a THEN low_swap_at ELSE high_swap_at END FROM public.dating_matches WHERE id = v_m) IS NOT NULL THEN
    v_bad := v_bad || 'the withdrawal'::text;
  END IF;
  IF pg_temp.j(b, 'e9', format('SELECT public.block_dating_match(%L, %L)', pg_temp.key('ff2b'), v_m)) IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    v_bad := v_bad || 'Block'::text;
  END IF;
  -- M-1: the ended chat answers closed, with Dating off and with the chat's flag off.
  IF pg_temp.j(a, 'e8', format('SELECT public.send_dating_message(%L, %L, ''hello?'')', pg_temp.key('ff2c'), v_m)) ->> 'reason'
       IS DISTINCT FROM 'closed' THEN
    v_bad := v_bad || 'ended chat, Dating off'::text;
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_match_messaging';
  IF pg_temp.j(a, 'e8', format('SELECT public.send_dating_message(%L, %L, ''hello?'')', pg_temp.key('ff2d'), v_m)) ->> 'reason'
       IS DISTINCT FROM 'closed' THEN
    v_bad := v_bad || 'ended chat, chat off (M-1)'::text;
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_match_messaging';
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating off did not stop the chat (or stopped what reduces exposure, or answered an ended chat unavailable): %', v_bad;
  END IF;
END $$;

-- FF3 (I-4): in production the chat can't be on without an active safety
-- config, and the last active config can't go while the chat is on; judged
-- on the end state (a version swap and the emergency switch-off pass), the
-- refusals say what to do; development is free.
DO $$
DECLARE
  v_res text[] := '{}';
  v_want constant text[] := ARRAY[
    'retire:config:dating_chat_needs_active_config', 'delete:config:dating_chat_needs_active_config', 'swap:ok', 'all off:ok',
    'chat off, then retire:ok', 'development:ok', 'chat on, no config:flag:dating_chat_needs_safety_config',
    'config, then chat on:ok', 'another flag, out of step:ok'];
  v text;
BEGIN
  -- In development: one active config of this section's, the chat and Get help on.
  PERFORM set_config('app.settings.attune_environment', '', true);
  UPDATE public.dating_safety_configs SET state = 'retired' WHERE state = 'active';
  INSERT INTO public.dating_safety_configs (version, state, config, config_hash, review_ref, activated_at)
  SELECT 'w6_ff_a', 'active', c.config, c.config_hash, 'TEST-FF', now() FROM public.dating_safety_configs AS c WHERE c.version = 'dating_chat_v1';
  INSERT INTO public.feature_flags (key, enabled) VALUES ('support_resources_v2', true), ('dating_match_messaging', true), ('dating_mode_enabled', true)
  ON CONFLICT (key) DO UPDATE SET enabled = true;
  UPDATE private.flag_production_gates SET review_ref = 'TEST-FF' WHERE flag_key IN ('dating_match_messaging', 'support_resources_v2');
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'dating_safety_configs_chat_keeps_active' AND tgdeferrable) THEN
    SET CONSTRAINTS public.dating_safety_configs_chat_keeps_active IMMEDIATE; -- the rows changed so far, in development
    SET CONSTRAINTS public.dating_safety_configs_chat_keeps_active DEFERRED;
  END IF;
  FOR v IN
    SELECT w.name || ':' || CASE WHEN r.v = 'ok' THEN 'ok' ELSE split_part(r.v, ':', 1) || ':' || split_part(r.v, ':', 2) END
      FROM (VALUES
        (1, 'retire', 'production', ARRAY['UPDATE public.dating_safety_configs SET state = ''retired'' WHERE version = ''w6_ff_a''']),
        (2, 'delete', 'production', ARRAY['DELETE FROM public.dating_safety_configs WHERE version = ''w6_ff_a''']),
        (3, 'swap', 'production', ARRAY['UPDATE public.dating_safety_configs SET state = ''retired'' WHERE version = ''w6_ff_a''',
                                        'INSERT INTO public.dating_safety_configs (version, state, config, config_hash, review_ref, activated_at)
                                         SELECT ''w6_ff_b'', ''active'', c.config, c.config_hash, ''TEST-FF'', now() FROM public.dating_safety_configs AS c WHERE c.version = ''dating_chat_v1''']),
        (4, 'all off', 'production', ARRAY['UPDATE public.dating_safety_configs SET state = ''retired'' WHERE version = ''w6_ff_a''',
                                           'UPDATE public.feature_flags SET enabled = false']),
        (5, 'chat off, then retire', 'production', ARRAY['UPDATE public.feature_flags SET enabled = false WHERE key = ''dating_match_messaging''',
                                                         'UPDATE public.dating_safety_configs SET state = ''retired'' WHERE version = ''w6_ff_a''']),
        (6, 'development', '', ARRAY['UPDATE public.dating_safety_configs SET state = ''retired'' WHERE version = ''w6_ff_a''']),
        (7, 'chat on, no config', 'production', ARRAY['UPDATE public.feature_flags SET enabled = false WHERE key = ''dating_match_messaging''',
                                                      'UPDATE public.dating_safety_configs SET state = ''retired'' WHERE version = ''w6_ff_a''',
                                                      'UPDATE public.feature_flags SET enabled = true WHERE key = ''dating_match_messaging''']),
        (8, 'config, then chat on', 'production', ARRAY['UPDATE public.feature_flags SET enabled = false WHERE key = ''dating_match_messaging''',
                                                        'UPDATE public.dating_safety_configs SET state = ''retired'' WHERE version = ''w6_ff_a''',
                                                        'INSERT INTO public.dating_safety_configs (version, state, config, config_hash, review_ref, activated_at)
                                                         SELECT ''w6_ff_b'', ''active'', c.config, c.config_hash, ''TEST-FF'', now() FROM public.dating_safety_configs AS c WHERE c.version = ''dating_chat_v1''',
                                                        'UPDATE public.feature_flags SET enabled = true WHERE key = ''dating_match_messaging''']),
        -- A pair already out of step (no config under the chat, set in development) never holds up another flag's write.
        (9, 'another flag, out of step', 'production', ARRAY['SELECT set_config(''app.settings.attune_environment'', '''', true)',
                                                             'UPDATE public.dating_safety_configs SET state = ''retired'' WHERE version = ''w6_ff_a''',
                                                             'SET CONSTRAINTS ALL IMMEDIATE', 'SET CONSTRAINTS ALL DEFERRED',
                                                             'SELECT set_config(''app.settings.attune_environment'', ''production'', true)',
                                                             'UPDATE public.feature_flags SET updated_at = now() WHERE key = ''text_scale_v2'''])
      ) AS w(n, name, env, sqls)
     CROSS JOIN LATERAL (SELECT pg_temp.ff_tx(w.env, w.sqls) AS v) AS r
     ORDER BY w.n
  LOOP
    v_res := v_res || v;
  END LOOP;
  IF v_res IS DISTINCT FROM v_want THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the chat''s safety-config rule in production is not as built (got %, want %)', v_res, v_want;
  END IF;
  IF pg_temp.ff_tx('production', ARRAY['UPDATE public.dating_safety_configs SET state = ''retired'' WHERE version = ''w6_ff_a''']) NOT LIKE '%turn Dating chat (dating_match_messaging) off first%'
     OR pg_temp.ff_tx('production', ARRAY['UPDATE public.feature_flags SET enabled = false WHERE key = ''dating_match_messaging''',
                                          'UPDATE public.dating_safety_configs SET state = ''retired'' WHERE version = ''w6_ff_a''',
                                          'UPDATE public.feature_flags SET enabled = true WHERE key = ''dating_match_messaging''']) NOT LIKE '%activate a dating_safety_configs version%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refusal does not tell the operator what to do';
  END IF;
END $$;

-- FF4 (I-6, W6 T5 O-1, N-7): a message inside the 15 minutes after a push
-- went out is pushed at the end of them, never dropped: one trailing push
-- (its own key, the copy from the one helper); more messages add none; at
-- its claim it is skipped if everything is read by then, and comes back for
-- the next unread message; while something is unread it goes.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('ea', '{"phone": "980"}');
  b constant uuid := pg_temp.ready('eb', '{"identity": "man", "seeking": ["woman"], "phone": "981"}');
  v_m constant uuid := pg_temp.ff_match(pg_temp.id('ea'), pg_temp.id('eb'));
  v_at constant timestamptz := now() + interval '10 minutes';
  v_key constant text := private.dating_push_source_key(pg_temp.id('eb'), 'chat:' || floor(extract(epoch FROM now() + interval '10 minutes') / 900)::bigint::text || ':t',
                                                       ((now() + interval '10 minutes') AT TIME ZONE 'UTC')::date);
  v_t uuid;
  v_got text;
BEGIN
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  VALUES (b, 'immediate', now() - interval '5 minutes', 'sent',
          jsonb_build_object('type', 'me_update', 'route', 'me', 'title', 'Attune', 'body', 'You have something new in Attune.'),
          private.dating_push_source_key(b, 'ff4-sent', (now() AT TIME ZONE 'UTC')::date), now() - interval '5 minutes', now() - interval '5 minutes');
  PERFORM pg_temp.j(a, 'ea', format('SELECT public.send_dating_message(%L, %L, ''One'')', pg_temp.key('ff4a'), v_m));
  PERFORM pg_temp.j(a, 'ea', format('SELECT public.send_dating_message(%L, %L, ''Two'')', pg_temp.key('ff4b'), v_m));
  SELECT string_agg(n.status || '|' || (n.scheduled_for = v_at)::text || '|' || (n.source_key = v_key)::text || '|' || (n.metadata ->> 'body'), ', '),
         min(n.id::text)::uuid
    INTO v_got, v_t
    FROM public.scheduled_notifications AS n WHERE n.user_id = b AND n.status <> 'sent';
  IF v_got IS DISTINCT FROM 'pending|true|true|You have something new in Attune.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: messages inside the 15 minutes after a push were not pushed once at their end (%)', v_got;
  END IF;
  -- b reads everything; at its claim it is skipped.
  UPDATE public.dating_matches AS m
     SET low_seen_at = CASE WHEN m.user_low_id = b THEN clock_timestamp() ELSE m.low_seen_at END,
         high_seen_at = CASE WHEN m.user_high_id = b THEN clock_timestamp() ELSE m.high_seen_at END
   WHERE m.id = v_m;
  UPDATE public.scheduled_notifications SET status = 'processing' WHERE id = v_t;
  IF (SELECT status || ':' || coalesce(last_error, '-') FROM public.scheduled_notifications WHERE id = v_t) IS DISTINCT FROM 'skipped:dating_chat_read' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a trailing push was not skipped at its claim once everything was read';
  END IF;
  -- The next unread message brings it back; unread, its claim goes ahead.
  PERFORM pg_temp.j(a, 'ea', format('SELECT public.send_dating_message(%L, %L, ''Three'')', pg_temp.key('ff4c'), v_m));
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = b AND status <> 'sent') <> 1
     OR (SELECT status || '|' || (scheduled_for = v_at)::text FROM public.scheduled_notifications WHERE id = v_t) IS DISTINCT FROM 'pending|true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a trailing push skipped as read did not come back for the next unread message';
  END IF;
  UPDATE public.scheduled_notifications SET status = 'processing' WHERE id = v_t;
  IF (SELECT status FROM public.scheduled_notifications WHERE id = v_t) IS DISTINCT FROM 'processing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a trailing push was skipped while a message was unread';
  END IF;
  -- N-7: one copy; the three-argument form (every older caller) is the same push, due now.
  DELETE FROM public.scheduled_notifications WHERE user_id = b;
  PERFORM private.dating_queue_me_update(b, 'ff4-notify', 'notify');
  IF private.dating_me_update_body('new') IS DISTINCT FROM 'You have something new in Attune.'
     OR private.dating_me_update_body('notify') IS DISTINCT FROM 'Something you asked about is ready in Attune.'
     OR (SELECT (metadata ->> 'body') || '|' || (scheduled_for = now())::text || '|' || source_key FROM public.scheduled_notifications WHERE user_id = b)
        IS DISTINCT FROM private.dating_me_update_body('notify') || '|true|' || private.dating_push_source_key(b, 'ff4-notify', (now() AT TIME ZONE 'UTC')::date) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the me_update copy is not one helper''s, or the older form changed';
  END IF;
END $$;

-- FF5 (I-7, W6 T8 and T8 M-6): a guided answer the other can't see yet is
-- no news to them: the worker's card on it does not tell their chat, and
-- their push is skipped at its claim (nothing they can read is unread);
-- at the reveal both chats hear of it, the revealing side's other phone
-- too. Both ways round (the recipient the pair's low side, then its high).
CREATE FUNCTION pg_temp.ff5(p_a text, p_ap text, p_b text, p_bp text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  a constant uuid := pg_temp.ready(p_a, jsonb_build_object('phone', p_ap));
  b constant uuid := pg_temp.ready(p_b, jsonb_build_object('identity', 'man', 'seeking', jsonb_build_array('woman'), 'phone', p_bp));
  v_m constant uuid := pg_temp.ff_match(pg_temp.id(p_a), pg_temp.id(p_b));
  v_msg uuid;
  v_push uuid;
  v jsonb;
BEGIN
  v_msg := (pg_temp.j(a, p_a, format('SELECT public.send_dating_message(%L, %L, ''Send me momo and we talk'', ''guided_answer'', ''good_saturday'')',
                                    pg_temp.key('ff5a'), v_m)) #>> '{message,id}')::uuid;
  PERFORM pg_temp.claim_only(v_msg);
  v := public.complete_dating_safety_job(v_msg, 'dating_chat_v1',
         '[{"rule_id": "financial_request:send me momo", "family": "financial_request", "tier": 2}]');
  IF v ->> 'ok' IS DISTINCT FROM 'true' OR NOT EXISTS (SELECT 1 FROM public.dating_safety_events WHERE message_id = v_msg AND at_risk_user_id = b) THEN
    RETURN 'precondition: the completion did not keep the event (' || v::text || ')';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_chat_signals WHERE user_id = b AND match_id = v_m) THEN
    RETURN 'a card on a guided answer not shown yet told the other''s chat (I-7)';
  END IF;
  PERFORM private.dating_queue_chat_push(b);
  SELECT id INTO v_push FROM public.scheduled_notifications WHERE user_id = b AND status = 'pending' AND metadata ->> 'type' = 'me_update';
  UPDATE public.scheduled_notifications SET status = 'processing' WHERE id = v_push;
  IF v_push IS NULL OR (SELECT status FROM public.scheduled_notifications WHERE id = v_push) IS DISTINCT FROM 'skipped' THEN
    RETURN 'a guided answer not shown yet counted as unread at the push''s claim (T8 M-6)';
  END IF;
  PERFORM pg_temp.j(b, p_b, format('SELECT public.send_dating_message(%L, %L, ''Football, then jollof'', ''guided_answer'', ''good_saturday'')',
                                  pg_temp.key('ff5b'), v_m));
  IF (SELECT count(DISTINCT user_id) FROM public.dating_chat_signals WHERE match_id = v_m AND user_id IN (a, b)) <> 2 THEN
    RETURN 'the reveal did not tell both chats (the revealing side''s other phone too)';
  END IF;
  RETURN 'ok';
END $$;
DO $$
DECLARE
  v1 constant text := pg_temp.ff5('ec', '982', 'ed', '983'); -- the recipient is the high side
  v2 constant text := pg_temp.ff5('d4', '941', 'd3', '940'); -- the recipient is the low side
BEGIN
  IF v1 IS DISTINCT FROM 'ok' OR v2 IS DISTINCT FROM 'ok' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % / %', v1, v2;
  END IF;
END $$;

-- FF6 (I-8): a masker that raises is counted (dating.mask.failed, in
-- health) and the fallback stored leaves no letter or digit, on a message
-- and on a caption; the pure fallback is no weaker than the masker on
-- handles, spelled-out emails and number words.
CREATE FUNCTION pg_temp.ff6_send(p_a uuid, p_m uuid, p_key text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_n0 constant bigint := pg_temp.metric('dating.mask.failed');
  v jsonb;
BEGIN
  v := pg_temp.j(p_a, 'ee', format('SELECT public.send_dating_message(%L, %L, ''snap me at ama_b or oh two four four one two three'')', p_key, p_m));
  RETURN coalesce(v ->> 'ok', v::text) || '|' || (pg_temp.metric('dating.mask.failed') - v_n0)::text || '|'
      || coalesce((SELECT (d.body_masked !~ '[[:alnum:]]')::text FROM public.dating_messages AS d WHERE d.match_id = p_m AND d.idempotency_key = p_key), 'none');
END $$;
CREATE FUNCTION pg_temp.ff6_caption(p_a uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_n0 constant bigint := pg_temp.metric('dating.mask.failed');
BEGIN
  UPDATE public.dating_profile_photos SET caption = 'ama dot b at gmail dot com' WHERE user_id = p_a AND position = 1;
  RETURN (pg_temp.metric('dating.mask.failed') - v_n0)::text || '|'
      || coalesce((SELECT (f.caption_masked !~ '[[:alnum:]]')::text FROM public.dating_profile_photos AS f WHERE f.user_id = p_a AND f.position = 1), 'none');
END $$;
DO $$
DECLARE
  a constant uuid := pg_temp.ready('ee', '{"phone": "984"}');
  b constant uuid := pg_temp.ready('ef', '{"identity": "man", "seeking": ["woman"], "phone": "985"}');
  v_m constant uuid := pg_temp.ff_match(pg_temp.id('ee'), pg_temp.id('ef'));
  v_boom constant text[] := ARRAY['CREATE OR REPLACE FUNCTION private.dating_mask_contacts(p_text text) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $f$ BEGIN RAISE EXCEPTION ''w6:boom''; END $f$'];
  v_bad text[] := '{}';
  v text;
  t text;
BEGIN
  v := pg_temp.probe(v_boom, format('SELECT pg_temp.ff6_send(%L, %L, %L)', a, v_m, pg_temp.key('ff6')));
  IF v IS DISTINCT FROM 'true|1|true' THEN v_bad := v_bad || ('message: ' || v); END IF;
  v := pg_temp.probe(v_boom, format('SELECT pg_temp.ff6_caption(%L)', a));
  IF v IS DISTINCT FROM '1|true' THEN v_bad := v_bad || ('caption: ' || v); END IF;
  FOREACH t IN ARRAY ARRAY['snap me at ama_b', 'my insta is ama.b', 'ama dot b at gmail dot com', 'oh two four four one two three four',
                           's n a p ama b', 'call me on zero two four four'] LOOP
    v := pg_temp.probe(v_boom, format('SELECT private.dating_mask_contacts_safe(%L)', t));
    IF v ~ '[[:alnum:]]' THEN v_bad := v_bad || (t || ' -> ' || v); END IF;
  END LOOP;
  IF NOT ((public.get_dating_operational_health() -> 'safety_counters_7d') ? 'dating.mask.failed') THEN
    v_bad := v_bad || 'health has no dating.mask.failed'::text;
  END IF;
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the masker''s fail-closed fallback is silent or weaker than the masker: %', v_bad;
  END IF;
END $$;

-- FF7 (M-2, W6 T2 N-3): a withdrawal from a phone that is not the
-- person's trusted one withdraws and answers {ok} alone (no swap state).
DO $$
DECLARE
  a constant uuid := pg_temp.ready('f0', '{"phone": "986"}');
  b constant uuid := pg_temp.ready('f1', '{"identity": "man", "seeking": ["woman"], "phone": "987"}');
  v_m constant uuid := pg_temp.ff_match(pg_temp.id('f0'), pg_temp.id('f1'), interval '80 hours');
  v1 text;
  v2 text;
BEGIN
  PERFORM pg_temp.j(a, 'f0', format('SELECT public.offer_dating_contact_swap(%L)', v_m));
  v1 := pg_temp.call(a, md5('w6-not-this-phone'), format('SELECT public.withdraw_dating_contact_swap(%L)::text', v_m));
  PERFORM pg_temp.j(a, 'f0', format('SELECT public.offer_dating_contact_swap(%L)', v_m));
  PERFORM pg_temp.j(b, 'f1', format('SELECT public.offer_dating_contact_swap(%L)', v_m));
  v2 := pg_temp.call(b, md5('w6-not-this-phone'), format('SELECT public.withdraw_dating_contact_swap(%L)::text', v_m));
  IF v1 IS DISTINCT FROM '{"ok": true}' OR v2 IS DISTINCT FROM '{"ok": true}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a withdrawal from an untrusted phone answered the swap state (% / %)', v1, v2;
  END IF;
  IF (SELECT low_swap_at IS NOT NULL AND high_swap_at IS NOT NULL FROM public.dating_matches WHERE id = v_m) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: the swap was undone after both swapped';
  END IF;
END $$;

-- FF8 (M-3, W6 T8): a block also closes an open match the pair's numbers
-- now block by phone HMAC alone (here the blocked number's earlier,
-- parked account), sealed for the 30-day window, both told; the purge
-- removes it after the window.
DO $$
DECLARE
  p constant uuid := pg_temp.ready('f2', '{"phone": "988"}');
  q constant uuid := pg_temp.ready('f3', '{"identity": "man", "seeking": ["woman"], "phone": "989"}');
  r constant uuid := pg_temp.ready('f4', '{"identity": "man", "seeking": ["woman"], "phone": "998"}');
  v_pq constant uuid := pg_temp.ff_match(pg_temp.id('f2'), pg_temp.id('f3'));
  v_pr constant uuid := pg_temp.ff_match(pg_temp.id('f2'), pg_temp.id('f4'));
  v jsonb;
BEGIN
  -- r's account was parked before its number (q's now) was released.
  UPDATE public.users SET phone_released_at = now() - interval '1 day',
         parked_phone_hmac = public.dating_phone_hmac(public.dating_phone_canonical('+1555960989'))
   WHERE id = r;
  PERFORM pg_temp.j(p, 'f2', format('SELECT public.send_dating_message(%L, %L, ''Hello again'')', pg_temp.key('ff8m'), v_pr));
  DELETE FROM public.dating_chat_signals WHERE match_id = v_pr;
  v := pg_temp.j(p, 'f2', format('SELECT public.block_dating_match(%L, %L)', pg_temp.key('ff8'), v_pq));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR NOT private.dating_pair_blocked(p, r) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: precondition: the block failed, or does not reach the parked account''s number';
  END IF;
  IF (SELECT state || '/' || coalesce(closed_reason, '-') || '/' || coalesce((evidence_until > now() + interval '29 days')::text, 'none')
        FROM public.dating_matches WHERE id = v_pr) IS DISTINCT FROM 'blocked/blocked/true'
     OR (SELECT count(DISTINCT user_id) FROM public.dating_chat_signals WHERE match_id = v_pr AND user_id IN (p, r)) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the match blocked by phone HMAC alone stayed open, has no window, or was not told: %',
      (SELECT state || '/' || coalesce(closed_reason, '-') || '/' || coalesce(evidence_until::text, 'none') FROM public.dating_matches WHERE id = v_pr);
  END IF;
  IF pg_temp.probe(ARRAY['SELECT private.dating_purge_step(''matches'', now() + interval ''31 days'')'],
                   format('SELECT (SELECT count(*) FROM public.dating_messages WHERE match_id = %L)::text', v_pr)) IS DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the match blocked by phone HMAC alone survived the purge after its window';
  END IF;
END $$;

-- FF9 (M-4, W6 T8 N-1): the owner deletes an unlinked date reflection (its
-- match purged); another person's, and the owner's linked one, stay.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('f6', '{"phone": "990"}');
  b constant uuid := pg_temp.ready('f7', '{"identity": "man", "seeking": ["woman"], "phone": "991"}');
  v_m constant uuid := pg_temp.ff_match(pg_temp.id('f6'), pg_temp.id('f7'));
BEGIN
  INSERT INTO public.dating_date_reflections (match_id, author_user_id, response, idempotency_key)
  VALUES (NULL, a, 'good', 'w6-ff9-a-unlinked'), (v_m, a, 'good', 'w6-ff9-a-linked'), (NULL, b, 'good', 'w6-ff9-b-unlinked');
  PERFORM pg_temp.call(a, pg_temp.dev('f6'), format('SELECT public.delete_private_date_reflection(%L, NULL)::text', pg_temp.key('ff9')));
  IF (SELECT string_agg(idempotency_key, ',' ORDER BY idempotency_key) FROM public.dating_date_reflections WHERE idempotency_key LIKE 'w6-ff9-%')
       IS DISTINCT FROM 'w6-ff9-a-linked,w6-ff9-b-unlinked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner could not delete an unlinked reflection, or deleted another''s: %',
      (SELECT string_agg(idempotency_key, ',' ORDER BY idempotency_key) FROM public.dating_date_reflections WHERE idempotency_key LIKE 'w6-ff9-%');
  END IF;
END $$;

-- FF10 (M-5): a purge step cancelled (a statement timeout) is skipped and
-- counted; the steps after it still run.
CREATE FUNCTION pg_temp.ff10_purge() RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_n0 constant bigint := pg_temp.metric('dating.purge.failed.opener_hashes');
  v jsonb;
BEGIN
  v := public.purge_dating_retention(now());
  RETURN (v ->> 'opener_hashes') || '|' || (v ? 'session_context')::text || '|' || (pg_temp.metric('dating.purge.failed.opener_hashes') - v_n0)::text;
EXCEPTION WHEN OTHERS OR query_canceled THEN
  RETURN 'raised:' || SQLSTATE;
END $$;
DO $$
DECLARE
  a constant uuid := pg_temp.ready('f8', '{"phone": "992"}');
  b constant uuid := pg_temp.ready('f9', '{"identity": "man", "seeking": ["woman"], "phone": "993"}');
  v_m constant uuid := pg_temp.ff_match(pg_temp.id('f8'), pg_temp.id('f9'));
  v text;
BEGIN
  INSERT INTO public.dating_opener_hashes (sender_user_id, match_id, hash, created_at) VALUES (a, v_m, repeat('f', 64), now() - interval '31 days');
  v := pg_temp.probe(ARRAY['CREATE FUNCTION public.w6_ff10_cancel() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''canceling statement due to statement timeout'' USING ERRCODE = ''query_canceled''; END $f$',
                           'CREATE TRIGGER w6_ff10_cancel BEFORE DELETE ON public.dating_opener_hashes FOR EACH ROW EXECUTE FUNCTION public.w6_ff10_cancel()'],
                     'SELECT pg_temp.ff10_purge()');
  IF v IS DISTINCT FROM 'failed:57014|true|1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a cancelled purge step stopped the purge or went uncounted (%)', v;
  END IF;
END $$;

-- FF11 (M-6, W6 T5 M-4): a config once activated is frozen for good: a
-- retired version can't be edited, nor its activation wiped.
DO $$
DECLARE
  v_bad text[] := '{}';
  v text;
BEGIN
  PERFORM set_config('app.settings.attune_environment', '', true);
  UPDATE public.dating_safety_configs SET state = 'retired' WHERE version = 'w6_ff_a';
  BEGIN
    UPDATE public.dating_safety_configs
       SET config = config || '{"x": 1}', config_hash = encode(extensions.digest((config || '{"x": 1}')::text, 'sha256'), 'hex')
     WHERE version = 'w6_ff_a';
    v_bad := v_bad || 'edited'::text;
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM IS DISTINCT FROM 'config:active_frozen' THEN v_bad := v_bad || SQLERRM; END IF;
  END;
  BEGIN
    UPDATE public.dating_safety_configs SET activated_at = NULL WHERE version = 'w6_ff_a';
    v_bad := v_bad || 'activation wiped'::text;
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM IS DISTINCT FROM 'config:active_frozen' THEN v_bad := v_bad || SQLERRM; END IF;
  END;
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retired config can be changed under the same version: %', v_bad;
  END IF;
  UPDATE public.dating_safety_configs SET state = 'active' WHERE version = 'w6_ff_a'; -- the same content, back (allowed)
END $$;

-- FF12 (M-9): the cascades a match's or an account's delete runs are
-- indexed.
DO $$
DECLARE
  v_missing text[];
BEGIN
  SELECT array_agg(w.t || '(' || w.c || ')') INTO v_missing
    FROM (VALUES ('dating_chat_signals', 'match_id'), ('dating_opener_hashes', 'match_id'), ('dating_safety_events', 'at_risk_user_id')) AS w(t, c)
   WHERE NOT EXISTS (SELECT 1 FROM pg_index AS i JOIN pg_attribute AS a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
                      WHERE i.indrelid = ('public.' || w.t)::regclass AND a.attname = w.c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no index leads with %', v_missing;
  END IF;
END $$;

-- FF13 (M-11): a held identity that is not a woman or man answer is
-- cleared by the switch (what is held is the switch's own judge only).
DO $$
DECLARE
  h constant uuid := pg_temp.ready('fa', '{"phone": "994"}');
BEGIN
  UPDATE public.dating_profile_sensitive
     SET identity_enc = NULL,
         held_identity_enc = private.dating_field_encrypt(jsonb_build_object('identity', 'non_binary', 'pools', jsonb_build_array('woman')))
   WHERE user_id = h;
  PERFORM public.apply_same_gender_switch('GH');
  IF (SELECT held_identity_enc FROM public.dating_profile_sensitive WHERE user_id = h) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held identity Ghana does not allow was kept by the switch';
  END IF;
END $$;

-- FF14 (M-12): the check-in is Dating's: an account never in Dating gets
-- no push scheduled.
DO $$
DECLARE
  v_u constant uuid := pg_temp.id('fb');
  v text;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_u, '1555960995', now(), now());
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_u, '+1555960995', 'Not in Dating', 'just_me', now(), now(), '2');
  v := pg_temp.call(v_u, NULL, 'SELECT public.schedule_dating_checkin(now() + interval ''1 hour'')::text');
  IF v::jsonb ->> 'ok' IS DISTINCT FROM 'false'
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account never in Dating scheduled a check-in push (%)', v;
  END IF;
END $$;

-- FF15 (M-13): a pair's marker keeps two years from its latest end.
DO $$
DECLARE
  a constant uuid := pg_temp.ready('fc', '{"phone": "996"}');
  b constant uuid := pg_temp.ready('fd', '{"identity": "man", "seeking": ["woman"], "phone": "997"}');
  v_code constant text := private.dating_pair_code(public.dating_phone_hmac_for_user(pg_temp.id('fc')), public.dating_phone_hmac_for_user(pg_temp.id('fd')));
BEGIN
  PERFORM private.dating_mark_pair(a, b);
  UPDATE public.dating_pair_markers SET purge_after = now() + interval '1 year' WHERE pair_code = v_code; -- written a year ago
  PERFORM private.dating_mark_pair(a, b);
  IF (SELECT purge_after FROM public.dating_pair_markers WHERE pair_code = v_code) < now() + interval '2 years' - interval '1 minute' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pair''s marker counts its two years from its first write, not its latest';
  END IF;
END $$;

-- FF16 (M-8): generation reads the exclusion key once per partition and
-- passes it in; the keyed forms give the same answers.
DO $$
DECLARE
  a constant uuid := pg_temp.id('fc');
  b constant uuid := pg_temp.id('fd');
  ha constant text := public.dating_phone_hmac_for_user(pg_temp.id('fc'));
  hb constant text := public.dating_phone_hmac_for_user(pg_temp.id('fd'));
BEGIN
  IF private.dating_pair_code(ha, hb, public.app_setting('dating_exclusion_key')) IS DISTINCT FROM private.dating_pair_code(ha, hb)
     OR private.dating_pair_new(a, b, ha, hb, public.app_setting('dating_exclusion_key')) IS DISTINCT FROM private.dating_pair_new(a, b, ha, hb)
     OR private.dating_pair_new(a, b, ha, hb) IS NOT FALSE
     OR pg_get_functiondef('private.dating_generate_partition(text,text,text,date,timestamptz,text,jsonb)'::regprocedure)
        !~ 'dating_pair_new\(v_u\.user_id, a\.user_id, \(v_u\.p\)\.hmac, \(a\.p\)\.hmac, v_xkey\)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: generation does not pass the key it read once (M-8), or the keyed forms differ';
  END IF;
END $$;

-- FF17b (I-5): the deletion's close step never skips: a lock conflict is
-- retried (once: it closes), and one that persists refuses the deletion
-- (dating:busy, the app retries) instead of leaving the match open.
CREATE FUNCTION pg_temp.ff17_delete(p_u uuid, p_m uuid) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.prepare_account_deletion(p_u);
  RETURN 'ok|' || (SELECT state || '/' || coalesce(closed_reason, '-') FROM public.dating_matches WHERE id = p_m);
EXCEPTION WHEN OTHERS THEN
  RETURN SQLERRM;
END $$;
DO $$
DECLARE
  a constant uuid := pg_temp.ready('c0', '{"phone": "942"}');
  b constant uuid := pg_temp.ready('c1', '{"identity": "man", "seeking": ["woman"], "phone": "943"}');
  v_m constant uuid := pg_temp.ff_match(pg_temp.id('c0'), pg_temp.id('c1'));
  v_setup constant text[] := ARRAY[
    'CREATE SEQUENCE public.w6_ff17_seq',
    'CREATE FUNCTION public.w6_ff17_dead() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN IF nextval(''public.w6_ff17_seq'') <= current_setting(''w6.ff17_n'')::int THEN RAISE EXCEPTION ''deadlock detected'' USING ERRCODE = ''deadlock_detected''; END IF; RETURN NEW; END $f$',
    'CREATE TRIGGER w6_ff17_dead BEFORE UPDATE ON public.dating_matches FOR EACH ROW EXECUTE FUNCTION public.w6_ff17_dead()'];
  v1 text;
  v2 text;
BEGIN
  PERFORM set_config('w6.ff17_n', '1', true);
  v1 := pg_temp.probe(v_setup, format('SELECT pg_temp.ff17_delete(%L, %L)', a, v_m));
  PERFORM set_config('w6.ff17_n', '99', true);
  v2 := pg_temp.probe(v_setup, format('SELECT pg_temp.ff17_delete(%L, %L)', a, v_m));
  IF v1 IS DISTINCT FROM 'ok|closed/account_deleted' OR v2 IS DISTINCT FROM 'dating:busy' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the deletion''s close step skipped on a lock conflict (once: %, always: %)', v1, v2;
  END IF;
END $$;

-- FF17 (I-5, W6 T2 N-1): every closer locks the match rows before it bumps
-- a chat signal (send's order); the race script proves it under load.
DO $$
DECLARE
  v_bad text[];
BEGIN
  SELECT array_agg(w.sig) INTO v_bad
    FROM (VALUES ('private.dating_exit_internal(uuid,boolean)'), ('public.invalidate_dating_for_user(uuid,text)'),
                 ('public.prepare_account_deletion(uuid)')) AS w(sig)
   CROSS JOIN LATERAL (SELECT p.prosrc AS s FROM pg_proc AS p WHERE p.oid = w.sig::regprocedure) AS f
   WHERE strpos(f.s, 'FOR NO KEY UPDATE OF m') = 0 OR strpos(f.s, 'dating_bump_chat') < strpos(f.s, 'FOR NO KEY UPDATE OF m');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closer bumps the chat before it locks and closes the match: %', v_bad;
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'dating_v2_chat_contracts: all held'; END $$;
ROLLBACK;
