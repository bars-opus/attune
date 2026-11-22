-- Dating Mode contract tests — four-account RLS/RPC proof (DATING-C1).
--
-- Runs inside BEGIN/ROLLBACK: every fixture (including the local feature-flag
-- flip and the seeded age/healing gates) is discarded on exit, so this is safe
-- against any database and leaves no residue.
--
-- Four accounts:
--   A (da01), B (db02) — fully current candidates with a live (A,B) introduction.
--   C (dc03)           — an OUTSIDER: a current candidate (Spec 2 W5b fix round 1 (M-2): so act
--                        reaches the membership check) in NO introduction.
--   D (dd04)           — a current candidate who has BLOCKED A, with a live
--                        (A,D) introduction that the block must neutralize.
--
-- The fixture seeds the complete `dating_candidate_is_current` precondition
-- graph for A, B and D (flag on, active enrollment, age gate, healing gates,
-- profile ready, no relationship) so the happy-path RPCs actually execute —
-- a refusal-only test would never exercise the C3/H4/H5 fixes.
--
-- Assertions prove:
--   1. Owner RLS: A/C each read only their own dating rows; C sees no A/B intro.
--   2. Outsider RPC read: C's get_my_dating_introductions returns 0 rows.
--   3. Actor forgery: C acting on the (A,B) intro raises and writes no action.
--   4. Double-blind (C3): after A → interested, B's own row shows viewer-scoped
--      'open' — never 'interested' — so B cannot infer A liked them.
--   5. Match lifecycle (H5): mutual interest creates a match; A exiting Dating
--      CLOSES it.
--   6. Block bypass (H4/H5): D blocks A → A acting on the (A,D) intro raises,
--      no match is created, and the (A,D) pair leaves A's introductions list.
--   7. Function-privilege + payload-shape guards (raw-target RPCs revoked,
--      payloads never expose user_id/pair_key, unreviewed active config rejected).

BEGIN;
-- Spec 2 W3c (R-24): this file's photo fixtures stand for photos the
-- inline CSAM scan cleared (an approval needs csam_state 'clear');
-- rolled back with the file.
ALTER TABLE public.dating_profile_photos ALTER COLUMN csam_state SET DEFAULT 'clear';

-- Spec 2 W1d: readiness v2 reads the encrypted answers, so the fixture
-- encrypts them under a transaction-local field key.
SET LOCAL app.settings.dating_field_key = 'dating-mode-contracts-field-key-0123456789abcdef';
-- Spec 2 W2: the candidate check is dating_eligibility now (gates 1-6), so
-- the fixture holds what its gates read: a ready exclusion key, adults by
-- Spec 1's DOB with EULA v2, and Ghana open in each candidate's region.
SET LOCAL app.settings.dating_exclusion_key = 'dating-mode-contracts-exclusion-key';
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000da01';
  b uuid := '00000000-0000-0000-0000-00000000db02';
  c uuid := '00000000-0000-0000-0000-00000000dc03';
  d uuid := '00000000-0000-0000-0000-00000000dd04';
  v_snap_a uuid := '00000000-0000-0000-0000-0000000a0000';
  v_snap_b uuid := '00000000-0000-0000-0000-0000000b0000';
  v_snap_d uuid := '00000000-0000-0000-0000-0000000d0000';
  v_intro_ab uuid := '00000000-0000-0000-0000-000000ab0000';
  v_intro_ad uuid := '00000000-0000-0000-0000-000000ad0000';
BEGIN
  -- Feature flag ON (local to this transaction; rolled back on exit).
  INSERT INTO public.feature_flags(key, enabled)
  VALUES ('dating_mode_enabled', true)
  ON CONFLICT (key) DO UPDATE SET enabled = true;

  -- Auth + app users.
  -- Spec 2 W1a: Dating HMACs read Auth's number, so the fixture's phones
  -- are on auth.users (Auth's form, no '+'), confirmed.
  INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    phone, phone_confirmed_at
  ) VALUES
    (a, 'authenticated','authenticated','+233200000001','x',now(),'{}','{}',now(),now(),'233200000001',now()),
    (b, 'authenticated','authenticated','+233200000002','x',now(),'{}','{}',now(),now(),'233200000002',now()),
    (c, 'authenticated','authenticated','+233200000003','x',now(),'{}','{}',now(),now(),'233200000003',now()),
    (d, 'authenticated','authenticated','+233200000004','x',now(),'{}','{}',now(),now(),'233200000004',now())
  ON CONFLICT (id) DO NOTHING;

  -- B and D carry verified phones so the C4 phone-HMAC exclusion is exercisable.
  INSERT INTO public.users(id, phone, display_name, mode) VALUES
    (a, '+233200000001', 'Dating A','dating'),
    (b, '+233200000002', 'Dating B','dating'),
    (c, '+233200000003', 'Dating C','dating'),
    (d, '+233200000004', 'Dating D','dating')
  ON CONFLICT (id) DO UPDATE SET phone=EXCLUDED.phone, display_name=EXCLUDED.display_name;
  -- Spec 2 W2: gate 2 (Spec 1's DOB, EULA v2) and gate 6 (Ghana open).
  UPDATE public.users SET eula_accepted_at = now(), eula_version = '2' WHERE id IN (a, b, c, d);
  INSERT INTO public.account_birthdates (user_id, birth_date)
  SELECT u, current_date - interval '30 years' FROM (VALUES (a), (b), (c), (d)) AS x(u)
  ON CONFLICT (user_id) DO NOTHING;
  PERFORM public.publish_country_config('GH', '{"dating_enabled": true}');

  -- Spec 2 W1d (batch-10 fix round 1, I-1): readiness v2 needs the D4
  -- consents standing, so the three candidates hold them.
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT x.u, 'dating-mode-consent-' || y.purpose, y.purpose, 'granted', 'dating-2.0', clock_timestamp()
    FROM (VALUES (a), (b), (c), (d)) AS x(u), unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']) AS y(purpose); -- Spec 2 W5b fix round 1 (M-2)

  -- Enrollments: A/B/D active current candidates, C only opted-in (not active).
  INSERT INTO public.dating_enrollments(user_id, state, activated_at) VALUES
    (a, 'active', now()),
    (b, 'active', now()),
    (d, 'active', now()),
    (c, 'active', now()) -- Spec 2 W5b fix round 1 (M-2): C is current, in no introduction
  ON CONFLICT (user_id) DO UPDATE
    SET state=EXCLUDED.state, activated_at=EXCLUDED.activated_at;

  -- Profiles: A/B/D active+approved (ready); C draft.
  -- verification_state must be set explicitly: it defaults to 'unverified'
  -- and dating_profile_ready requires 'verified', so leaving it out made
  -- every candidate fail dating_candidate_is_current and every
  -- act_on_dating_introduction call raise introduction_unavailable --
  -- before reaching the double-blind contracts this file exists to test.
  -- Spec 2 W1d: readiness v2 also needs the place, the intention and its
  -- attestation, and the children answers.
  INSERT INTO public.dating_profiles(user_id, display_name, city_region_code, relationship_intention, bio, profile_state, moderation_state, verification_state,
                                     country_code, region_code, intention, not_married_attested_at, attestation_version, children_have, children_want)
  VALUES
    (a, 'Dating A','Accra','Intentional dating',NULL,'active','approved','verified','GH','AA','committed',now(),'2026-10-v1',false,'yes'),
    (b, 'Dating B','Kumasi','Intentional dating',NULL,'active','approved','verified','GH','AH','committed',now(),'2026-10-v1',false,'yes'),
    (d, 'Dating D','Takoradi','Intentional dating',NULL,'active','approved','verified','GH','AA','committed',now(),'2026-10-v1',false,'yes'), -- Spec 2 W2: an open region (gate 6)
    (c, 'Dating C','Accra','Intentional dating',NULL,'active','approved','verified','GH','AA','committed',now(),'2026-10-v1',false,'yes') -- Spec 2 W5b fix round 1 (M-2)
  ON CONFLICT (user_id) DO UPDATE
    SET profile_state=EXCLUDED.profile_state,
        moderation_state=EXCLUDED.moderation_state,
        verification_state=EXCLUDED.verification_state;

  -- Preferences (dating_profile_ready needs non-empty gender/region/intention).
  INSERT INTO public.dating_preferences(user_id, min_age, max_age, gender_preferences, region_preferences, intention_preferences)
  VALUES
    (a, 25, 45, '["woman"]','["Accra"]','["intentional"]'),
    (b, 25, 45, '["man"]','["Kumasi"]','["intentional"]'),
    (d, 25, 45, '["man"]','["Takoradi"]','["intentional"]'),
    (c, 25, 45, '["woman"]','["Accra"]','["intentional"]') -- Spec 2 W5b fix round 1 (M-2)
  ON CONFLICT (user_id) DO UPDATE
    SET gender_preferences=EXCLUDED.gender_preferences,
        region_preferences=EXCLUDED.region_preferences,
        intention_preferences=EXCLUDED.intention_preferences;

  -- Spec 2 W1d: readiness v2's encrypted identity and who-to-meet, two
  -- approved prompts and two approved photos each (before any snapshot or
  -- introduction exists, so the photo trigger invalidates nothing).
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  SELECT u, private.dating_field_encrypt(jsonb_build_object('identity', g, 'pools', jsonb_build_array(g))),
         private.dating_field_encrypt(jsonb_build_object('seeking', jsonb_build_array(CASE g WHEN 'man' THEN 'woman' ELSE 'man' END)))
    FROM (VALUES (a, 'man'), (b, 'woman'), (c, 'man'), (d, 'woman')) AS x(u, g); -- Spec 2 W5b fix round 1 (M-2)
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer)
  SELECT u, n, CASE n WHEN 1 THEN 'perfect_sunday' ELSE 'ask_me_about' END, 'A contract fixture answer ' || n
    FROM (VALUES (a), (b), (c), (d)) AS x(u), generate_series(1, 2) AS n; -- Spec 2 W5b fix round 1 (M-2)
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state)
  SELECT u, 'dating-contract/' || u || '-' || n || '.jpg', n, 'approved'
    FROM (VALUES (a), (b), (c), (d)) AS x(u), generate_series(1, 2) AS n; -- Spec 2 W5b fix round 1 (M-2)

  -- Age gate: A/B/D adults, verified, not revoked/expired.
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, age_vendor, age_decided_at, identity_method, identity_result, identity_vendor, identity_decided_at) -- Spec 2 W4a (R-2)
  VALUES
    (a, 'id', 'pass', 'contract', now(), 'liveness_compare', 'pass', 'contract', now()),
    (b, 'id', 'pass', 'contract', now(), 'liveness_compare', 'pass', 'contract', now()),
    (d, 'id', 'pass', 'contract', now(), 'liveness_compare', 'pass', 'contract', now()),
    (c, 'id', 'pass', 'contract', now(), 'liveness_compare', 'pass', 'contract', now()) -- Spec 2 W5b fix round 1 (M-2)
  ON CONFLICT (user_id) DO UPDATE SET age_result = EXCLUDED.age_result; -- Spec 2 W4a

  -- Healing gates: one completed journey + a passing readiness attempt each.
  INSERT INTO public.healing_journeys(
    user_id, breakup_at, breakup_at_source, status,
    reflection_completed_at, post_mortem_status, post_mortem_completed_at,
    pattern_awareness_completed_at, portrait_status, portrait_completed_at,
    readiness_stage_completed_at, eligible_for_dating_opt_in_at
  )
  SELECT u,
         now() - interval '12 weeks', 'relationship', 'eligible_for_dating_opt_in',
         now(), 'completed', now(), now(), 'completed', now(), now(), now()
  FROM (VALUES (a),(b),(d)) AS s(u);

  INSERT INTO public.healing_readiness_attempts(journey_id, user_id, answers, score, scoring_version)
  SELECT hj.id, hj.user_id, '{}'::jsonb, 90, 'test-v1'
  FROM public.healing_journeys hj
  WHERE hj.user_id IN (a, b, d);

  -- Active reviewed algorithm config (all 4 review refs + activated_at).
  INSERT INTO public.dating_algorithm_configs(
    version, state, config, config_hash,
    clinical_review_ref, product_review_ref, fairness_review_ref, safety_review_ref, activated_at
  ) VALUES (
    'test-active-v1','active','{"weights":{}}','hash-test-active-v1',
    'clin-1','prod-1','fair-1','safe-1', now()
  ) ON CONFLICT (version) DO NOTHING;

  -- Spec 2 W5a (§2.3): A, B and D were seen in Dating today.
  INSERT INTO public.dating_session_context (user_id, effective_tier, dating_allowed_here, same_gender_allowed_here, -- Spec 2 W5a
                                             away_from_home, ip_resolved) -- Spec 2 W5a
  SELECT u, 1, true, false, false, true FROM (VALUES (a), (b), (c), (d)) AS x(u); -- Spec 2 W5a; -- Spec 2 W5b fix round 1 (M-2)

  -- Live introductions: (A,B) and (A,D). user_low/high ordered by uuid text.
  INSERT INTO public.dating_introductions (id, pair_key, user_low_id, user_high_id, state, expires_at, algorithm_version) -- Spec 2 W5a
  VALUES (v_intro_ab, public.dating_pair_key(a,b), LEAST(a,b), GREATEST(a,b), 'presented', now() + interval '7 days', 'test-active-v1'),
         (v_intro_ad, public.dating_pair_key(a,d), LEAST(a,d), GREATEST(a,d), 'presented', now() + interval '7 days', 'test-active-v1') -- Spec 2 W5a
  ON CONFLICT (id) DO NOTHING;
END
$$;

CREATE OR REPLACE FUNCTION public.test_clear_dating_auth()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- RESET ROLE alone is not enough: request.jwt.claims survives it, so
  -- auth.role() keeps returning 'authenticated' and backend-only guards
  -- (dating_former_partner_exclusion) refuse the call.
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  RESET ROLE;
END;
$$;

CREATE OR REPLACE FUNCTION public.test_set_dating_auth(p_user_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p_user_id::text, true);
  PERFORM set_config('request.jwt.claim.role','authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub',p_user_id,'role','authenticated')::text, true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Owner reads — Spec 2 W3a (R11): the app reads its own Dating rows
--    only through definer RPCs; a direct SELECT is refused outright.
-- ---------------------------------------------------------------------------
SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000da01');
DO $$ DECLARE v int; BEGIN
  BEGIN
    SELECT count(*) INTO v FROM public.dating_profiles;
    RAISE EXCEPTION 'A: a signed-in user can still SELECT dating_profiles (% rows)', v;
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    SELECT count(*) INTO v FROM public.dating_enrollments;
    RAISE EXCEPTION 'A: a signed-in user can still SELECT dating_enrollments (% rows)', v;
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000dc03');
DO $$ DECLARE v int; BEGIN
  BEGIN
    SELECT count(*) INTO v FROM public.dating_profiles;
    RAISE EXCEPTION 'C: a signed-in user can still SELECT dating_profiles (% rows)', v;
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  -- C is an outsider to the A/B and A/D intros and must not see them.
  --
  -- Two distinct mechanisms enforce that, and BOTH satisfy the
  -- contract: RLS filtering the rows away (count 0), or the table's own
  -- `REVOKE ALL ON public.dating_introductions FROM anon, authenticated`
  -- (20260703194500_dating_mode_v1_1.sql:168) refusing the read
  -- outright. This test asserted only the first, so the grant — the
  -- STRONGER of the two, since it denies the read before RLS is even
  -- consulted — made it fail with "permission denied for table
  -- dating_introductions" instead of passing.
  BEGIN
    SELECT count(*) INTO v FROM public.dating_introductions;
    IF v <> 0 THEN RAISE EXCEPTION 'C: read % introduction rows (must be 0)', v; END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL; -- refused outright: a stronger guarantee than returning 0 rows.
  END;
END $$;

-- ---------------------------------------------------------------------------
-- 2. Outsider RPC read — C's get_my_dating_introductions returns 0 rows.
-- ---------------------------------------------------------------------------
DO $$ DECLARE v int; BEGIN
  v := jsonb_array_length(public.get_my_dating_introductions() -> 'cards'); -- Spec 2 W5b: the v2 read
  IF v <> 0 THEN RAISE EXCEPTION 'C: get_my_dating_introductions returned % rows (must be 0)', v; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Actor forgery — C acting on the (A,B) intro raises and writes no action.
-- ---------------------------------------------------------------------------
DO $$ DECLARE v int; v_answer jsonb; BEGIN
  v_answer := public.act_on_dating_introduction('w5b-forgery-key-c0', '00000000-0000-0000-0000-000000ab0000', 'interested'); -- Spec 2 W5b: a fixed answer, never a raise
  IF v_answer IS DISTINCT FROM '{"ok": false, "reason": "introduction_unavailable"}'::jsonb THEN -- Spec 2 W5b fix round 1 (M-2): the exact answer
    RAISE EXCEPTION 'C: acting on a non-member intro answered %', v_answer; -- Spec 2 W5b
  END IF; -- Spec 2 W5b
  -- Same grant-vs-RLS split as the dating_introductions check above:
  -- `REVOKE ALL ON public.dating_interest_actions FROM anon,
  -- authenticated` (20260703194500_dating_mode_v1_1.sql:169) refuses
  -- this read outright rather than returning 0 rows. Both outcomes
  -- prove the forged action wrote nothing visible to C.
  BEGIN
    SELECT count(*) INTO v FROM public.dating_interest_actions
    WHERE actor_user_id = '00000000-0000-0000-0000-00000000dc03';
    IF v <> 0 THEN RAISE EXCEPTION 'C: forged action wrote % interest rows (must be 0)', v; END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL; -- refused outright: a stronger guarantee than returning 0 rows.
  END;
END $$;

-- ---------------------------------------------------------------------------
-- 3b. Enumeration oracle (H2) — every act-path refusal is INDISTINGUISHABLE.
--     A non-member forging, a nonexistent intro id, and a self-owned-but-invalid
--     intro must all raise the SAME sqlstate + message, so the error shape can
--     never be used to enumerate which introductions exist or who they belong to.
-- ---------------------------------------------------------------------------
SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000dc03'); -- C, outsider
DO $$
DECLARE
  v_forged jsonb; -- C acts on A/B's intro (exists, not a member) -- Spec 2 W5b
  v_absent jsonb; -- C acts on a random nonexistent intro id -- Spec 2 W5b
BEGIN
  v_forged := public.act_on_dating_introduction('w5b-h2-forged-key0', '00000000-0000-0000-0000-000000ab0000', 'interested'); -- Spec 2 W5b
  v_absent := public.act_on_dating_introduction('w5b-h2-absent-key0', '00000000-0000-0000-0000-0000000ab123', 'interested'); -- Spec 2 W5b
  -- "belongs to someone else" and "does not exist" must be identical responses.
  IF v_forged IS DISTINCT FROM v_absent OR v_forged IS DISTINCT FROM '{"ok": false, "reason": "introduction_unavailable"}'::jsonb THEN -- Spec 2 W5b fix round 1 (M-2)
    RAISE EXCEPTION 'H2 oracle: non-member % distinguishable from nonexistent %', v_forged, v_absent; -- Spec 2 W5b
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 4. Double-blind (C3) — A expresses interest; B must NOT be able to infer it.
-- ---------------------------------------------------------------------------
SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000da01');
DO $$ BEGIN
  IF (public.act_on_dating_introduction('w5b-a-likes-b-key0', '00000000-0000-0000-0000-000000ab0000', 'interested') ->> 'ok')::boolean IS NOT TRUE THEN -- Spec 2 W5b
    RAISE EXCEPTION 'A: interest in a live introduction was refused'; -- Spec 2 W5b
  END IF; -- Spec 2 W5b
END $$;

SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000db02');
DO $$ DECLARE v_card jsonb; BEGIN
  SELECT c INTO v_card FROM jsonb_array_elements(public.get_my_dating_introductions() -> 'cards') AS c -- Spec 2 W5b
   WHERE c ->> 'id' = '00000000-0000-0000-0000-000000ab0000'; -- Spec 2 W5b
  IF v_card IS NULL THEN
    RAISE EXCEPTION 'B: (A,B) intro missing from B''s list after A acted';
  END IF;
  -- B's card carries only B's own action (none yet). Anything reflecting
  -- A's (interested, matched) would be the banned one-sided-interest oracle.
  IF v_card -> 'acted' IS DISTINCT FROM 'null'::jsonb OR v_card::text ~ 'interested|matched' THEN -- Spec 2 W5b
    RAISE EXCEPTION 'B: double-blind leak in B''s card: %', v_card; -- Spec 2 W5b
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 5. Match lifecycle (H5) — mutual interest matches; A exiting closes it.
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  -- B reciprocates → mutual match.
  IF (SELECT (x.r - 'match_id') IS DISTINCT FROM '{"ok": true, "action": "interested", "matched": true}'::jsonb -- Spec 2 W6a (carry 7)
             OR coalesce(x.r ->> 'match_id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -- Spec 2 W6a
        FROM (SELECT public.act_on_dating_introduction('w5b-b-likes-a-key0', '00000000-0000-0000-0000-000000ab0000', 'interested') AS r) AS x) THEN -- Spec 2 W6a
    RAISE EXCEPTION 'B: the reciprocating interest did not answer matched'; -- Spec 2 W5b
  END IF; -- Spec 2 W5b
END $$;

SELECT public.test_clear_dating_auth();
DO $$ DECLARE v int; BEGIN
  SELECT count(*) INTO v FROM public.dating_matches
  WHERE introduction_id = '00000000-0000-0000-0000-000000ab0000' AND state = 'active';
  IF v <> 1 THEN RAISE EXCEPTION 'mutual interest expected 1 active match, got %', v; END IF;

  -- A exits Dating → invalidate_dating_for_user('exit') must CLOSE the match.
  PERFORM public.invalidate_dating_for_user('00000000-0000-0000-0000-00000000da01', 'exit');
  SELECT count(*) INTO v FROM public.dating_matches
  WHERE introduction_id = '00000000-0000-0000-0000-000000ab0000' AND state = 'active';
  IF v <> 0 THEN RAISE EXCEPTION 'A exit left % active match(es) (H5: must be 0)', v; END IF;
  SELECT count(*) INTO v FROM public.dating_matches
  WHERE introduction_id = '00000000-0000-0000-0000-000000ab0000'
    AND state = 'closed' AND closed_at IS NOT NULL;
  IF v <> 1 THEN RAISE EXCEPTION 'A exit did not close the match (got % closed)', v; END IF;
END $$;

-- Re-seed A as a current candidate for the block test (the exit above
-- invalidated A's snapshot and moved A's intros to 'invalidated'). Restore the
-- (A,D) intro state and A's enrollment/snapshot.
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000da01';
BEGIN
  UPDATE public.dating_enrollments SET state='active', activated_at=now() WHERE user_id=a;
  UPDATE public.dating_introductions
  SET state='presented'
  WHERE id='00000000-0000-0000-0000-000000ad0000';
END $$;

-- ---------------------------------------------------------------------------
-- 6. Block bypass (H4/H5) — D blocks A → A cannot act, no match, pair hidden.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000da01';
  d uuid := '00000000-0000-0000-0000-00000000dd04';
BEGIN
  INSERT INTO public.dating_blocks(blocker_user_id, blocked_user_id, pair_key)
  VALUES (d, a, public.dating_pair_key(a, d))
  ON CONFLICT (blocker_user_id, blocked_user_id) DO NOTHING;
END $$;

SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000da01');
DO $$ DECLARE v int; v_answer jsonb; BEGIN
  v_answer := public.act_on_dating_introduction('w5b-a-acts-blocked-d', '00000000-0000-0000-0000-000000ad0000', 'interested'); -- Spec 2 W5b
  IF v_answer IS DISTINCT FROM '{"ok": false, "reason": "introduction_unavailable"}'::jsonb THEN -- Spec 2 W5b
    RAISE EXCEPTION 'A: acting on a blocked pair answered %', v_answer; -- Spec 2 W5b
  END IF; -- Spec 2 W5b
  -- Running as `authenticated` here, and dating_matches carries
  -- REVOKE ALL (20260703194500_dating_mode_v1_1.sql), so this read is
  -- refused outright rather than returning 0 rows. Both outcomes prove
  -- the blocked pair produced no match. (The identical reads earlier in
  -- this file are NOT wrapped, and must not be: they run after
  -- test_clear_dating_auth(), which does RESET ROLE, so they legitimately
  -- read rows as superuser and a refusal there would be a real failure.)
  BEGIN
    SELECT count(*) INTO v FROM public.dating_matches
    WHERE introduction_id = '00000000-0000-0000-0000-000000ad0000';
    IF v <> 0 THEN RAISE EXCEPTION 'blocked pair created % match(es) (must be 0)', v; END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL; -- refused outright: a stronger guarantee than returning 0 rows.
  END;

  -- The (A,D) pair must not surface in A's introductions list.
  SELECT count(*) INTO v FROM jsonb_array_elements(public.get_my_dating_introductions() -> 'cards') AS c -- Spec 2 W5b
   WHERE c ->> 'id' = '00000000-0000-0000-0000-000000ad0000'; -- Spec 2 W5b
  IF v <> 0 THEN RAISE EXCEPTION 'A: blocked (A,D) pair still visible in list (% rows)', v; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 6b. DATING-C2: authenticated cannot write dating_age_verifications directly.
-- ---------------------------------------------------------------------------
SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000da01');
DO $$ DECLARE v_raised boolean := false; BEGIN
  BEGIN
    INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, age_vendor, age_decided_at) -- Spec 2 W4a
    VALUES ('00000000-0000-0000-0000-00000000da01', 'id', 'pass', 'self', now()); -- Spec 2 W4a
  EXCEPTION WHEN OTHERS THEN v_raised := true;  -- RLS/REVOKE denial (42501) or RLS 0-row
  END;
  -- Either a hard permission error, or RLS silently blocked the write: assert no
  -- self-attested row leaked in for this user via the authenticated path.
  IF NOT v_raised
     AND EXISTS(SELECT 1 FROM public.dating_age_verifications
                WHERE user_id='00000000-0000-0000-0000-00000000da01' AND age_vendor='self') THEN -- Spec 2 W4a
    RAISE EXCEPTION 'authenticated inserted a self-attested age-verification row';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 6c. DATING-H1: authenticated cannot read dating_* rollout flags (RLS hides
--     them) but chat_* flags stay readable so chat's client keeps working.
-- ---------------------------------------------------------------------------
DO $$ DECLARE v int; BEGIN
  SELECT count(*) INTO v FROM public.feature_flags WHERE key LIKE 'dating\_%';
  IF v <> 0 THEN RAISE EXCEPTION 'authenticated read % dating_* flag rows (must be 0)', v; END IF;
  -- chat_* flags (seeded by the chat migration) must remain readable — narrowing
  -- the RLS policy for dating must not regress chat's client-side flag read.
  SELECT count(*) INTO v FROM public.feature_flags WHERE key LIKE 'chat\_%';
  IF v < 1 THEN RAISE EXCEPTION 'authenticated can no longer read chat_* flags (regression)'; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 7. Function-privilege + payload-shape guards.
-- ---------------------------------------------------------------------------
SELECT public.test_clear_dating_auth();
DO $$
BEGIN
  IF has_function_privilege('authenticated','public.block_dating_user(text,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute raw-target block RPC';
  END IF;
  -- Spec 2 W7a (§4.10, Fable M1): the raw-target report RPC is gone; the
  -- v2 report RPCs resolve the target from the caller's own match or card.
  IF to_regprocedure('public.submit_dating_report(text,uuid,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'the raw-target report RPC still exists';
  END IF;
  IF has_function_privilege('authenticated','public.get_dating_operational_health()','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can read backend operational health';
  END IF;
  -- DATING-C2: age verification is backend-only. authenticated must be able to
  -- execute neither the writer nor the revoker, and service_role must.
  IF has_function_privilege('authenticated','public.record_dating_age_assurance(uuid,text,text,smallint,text)','EXECUTE') THEN -- Spec 2 W4a
    RAISE EXCEPTION 'authenticated can execute the age-verification writer';
  END IF;
  IF has_function_privilege('authenticated','public.revoke_dating_age_verification(uuid,text)','EXECUTE') THEN -- Spec 2 W4a
    RAISE EXCEPTION 'authenticated can execute the age-verification revoker';
  END IF;
  IF NOT has_function_privilege('service_role','public.record_dating_age_assurance(uuid,text,text,smallint,text)','EXECUTE') THEN -- Spec 2 W4a
    RAISE EXCEPTION 'service_role cannot execute the age-verification writer';
  END IF;
  -- DATING-C4: former-partner exclusion writer/HMAC are backend-only.
  IF has_function_privilege('authenticated','public.record_dating_former_partner_exclusion(uuid, boolean)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute the former-partner exclusion writer';
  END IF;
  IF has_function_privilege('authenticated','public.dating_phone_hmac(text)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute the phone-HMAC function';
  END IF;
  IF to_regprocedure('public.get_my_dating_introductions(integer)') IS NOT NULL THEN -- Spec 2 W5b: the v1 read is gone
    RAISE EXCEPTION 'the v1 introductions read survived W5b'; -- Spec 2 W5b
  END IF;
  IF to_regprocedure('public.get_my_dating_matches(integer)') IS NOT NULL THEN -- Spec 2 W5a (carry 8): the v1 match read is gone
    RAISE EXCEPTION 'the v1 match read (no device check) survived W5a'; -- Spec 2 W5a
  END IF;
  BEGIN
    INSERT INTO public.dating_algorithm_configs(version,state,config,config_hash,activated_at)
    VALUES ('unreviewed-test','active','{}','unreviewed-test',now());
    RAISE EXCEPTION 'unreviewed active algorithm unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END
$$;

-- ---------------------------------------------------------------------------
-- 8. DATING-C4: former-partner exclusion survives via phone-HMAC and blocks
--    both introduction visibility and the act path. Uses B and D (both current
--    candidates, verified phones) with a seeded ended (B,D) relationship.
-- ---------------------------------------------------------------------------
RESET ROLE;
-- Spec 2 W5b fix round 1 (M-2): the fixture's seeded exclusion key stays (another key fails its fingerprint, so every act would answer not_eligible)
DO $$
DECLARE
  b uuid := '00000000-0000-0000-0000-00000000db02';
  d uuid := '00000000-0000-0000-0000-00000000dd04';
  v_snap_b uuid := '00000000-0000-0000-0000-0000000b0000';
  v_snap_d uuid := '00000000-0000-0000-0000-0000000d0000';
  v_rel_id uuid;
  v int;
BEGIN
  -- An ended relationship between B and D, then record the exclusion.
  INSERT INTO public.relationships(user_a, user_b, status, ended_at)
  VALUES (b, d, 'archived', now() - interval '91 days') RETURNING id INTO v_rel_id; -- Spec 2 W5b fix round 1 (M-2): no gentle wait, so B's act reaches the pair check
  PERFORM public.record_dating_former_partner_exclusion(v_rel_id, true);

  -- Exclusion rows exist symmetrically (B protected from D and vice-versa).
  SELECT count(*) INTO v FROM public.dating_former_partner_exclusions
  WHERE user_id IN (b, d);
  IF v <> 2 THEN RAISE EXCEPTION 'C4: expected 2 exclusion rows, got %', v; END IF;

  -- The predicate must hold for the pair (in both argument orders).
  IF NOT public.dating_former_partner_excluded(b, d)
     OR NOT public.dating_former_partner_excluded(d, b) THEN
    RAISE EXCEPTION 'C4: former-partner predicate did not hold for the ended pair';
  END IF;

  -- A live (B,D) introduction must be neither actionable nor visible. Seed one.
  INSERT INTO public.dating_introductions (id, pair_key, user_low_id, user_high_id, state, expires_at, algorithm_version) -- Spec 2 W5a
  VALUES ('00000000-0000-0000-0000-000000bd0000', public.dating_pair_key(b,d), LEAST(b,d), GREATEST(b,d), 'presented', now() + interval '7 days', 'test-active-v1') -- Spec 2 W5a
  ON CONFLICT (id) DO NOTHING;
END $$;

-- B (a former partner of D) must not see the (B,D) intro, and acting must raise.
SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000db02');
DO $$ DECLARE v int; v_answer jsonb; BEGIN
  SELECT count(*) INTO v FROM jsonb_array_elements(public.get_my_dating_introductions() -> 'cards') AS c -- Spec 2 W5b
   WHERE c ->> 'id' = '00000000-0000-0000-0000-000000bd0000'; -- Spec 2 W5b
  IF v <> 0 THEN RAISE EXCEPTION 'C4: former-partner (B,D) intro visible in list (% rows)', v; END IF;
  v_answer := public.act_on_dating_introduction('w5b-b-acts-former-d', '00000000-0000-0000-0000-000000bd0000', 'interested'); -- Spec 2 W5b
  IF v_answer IS DISTINCT FROM '{"ok": false, "reason": "introduction_unavailable"}'::jsonb THEN -- Spec 2 W5b fix round 1 (M-2)
    RAISE EXCEPTION 'C4: acting on a former-partner intro answered %', v_answer; -- Spec 2 W5b
  END IF; -- Spec 2 W5b
  -- As `authenticated` against a REVOKE'd table: refusal and 0 rows both
  -- prove no match was created. See the note at the blocked-pair check.
  BEGIN
    SELECT count(*) INTO v FROM public.dating_matches
    WHERE introduction_id = '00000000-0000-0000-0000-000000bd0000';
    IF v <> 0 THEN RAISE EXCEPTION 'C4: former-partner pair created % match(es) (must be 0)', v; END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL; -- refused outright: a stronger guarantee than returning 0 rows.
  END;
END $$;

RESET ROLE;
DO $$ BEGIN -- Spec 2 W5b fix round 1 (M-2): B's act ended the former partners' pair (a permanent reason)
  IF (SELECT state FROM public.dating_introductions WHERE id = '00000000-0000-0000-0000-000000bd0000') IS DISTINCT FROM 'invalidated' THEN
    RAISE EXCEPTION 'C4: the former-partner act left the introduction %',
      (SELECT state FROM public.dating_introductions WHERE id = '00000000-0000-0000-0000-000000bd0000');
  END IF;
END $$;

ROLLBACK;
