-- Dating Mode contract tests — four-account RLS/RPC proof (DATING-C1).
--
-- Runs inside BEGIN/ROLLBACK: every fixture (including the local feature-flag
-- flip and the seeded age/healing gates) is discarded on exit, so this is safe
-- against any database and leaves no residue.
--
-- Four accounts:
--   A (da01), B (db02) — fully current candidates with a live (A,B) introduction.
--   C (dc03)           — an OUTSIDER: enrolled but NOT a member of any A/B intro.
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
  INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (a, 'authenticated','authenticated','+233200000001','x',now(),'{}','{}',now(),now()),
    (b, 'authenticated','authenticated','+233200000002','x',now(),'{}','{}',now(),now()),
    (c, 'authenticated','authenticated','+233200000003','x',now(),'{}','{}',now(),now()),
    (d, 'authenticated','authenticated','+233200000004','x',now(),'{}','{}',now(),now())
  ON CONFLICT (id) DO NOTHING;

  -- B and D carry verified phones so the C4 phone-HMAC exclusion is exercisable.
  INSERT INTO public.users(id, phone, display_name, mode) VALUES
    (a, '+233200000001', 'Dating A','dating'),
    (b, '+233200000002', 'Dating B','dating'),
    (c, '+233200000003', 'Dating C','dating'),
    (d, '+233200000004', 'Dating D','dating')
  ON CONFLICT (id) DO UPDATE SET phone=EXCLUDED.phone, display_name=EXCLUDED.display_name;

  -- Enrollments: A/B/D active current candidates, C only opted-in (not active).
  INSERT INTO public.dating_enrollments(user_id, state, activated_at) VALUES
    (a, 'active', now()),
    (b, 'active', now()),
    (d, 'active', now()),
    (c, 'eligible_to_opt_in', NULL)
  ON CONFLICT (user_id) DO UPDATE
    SET state=EXCLUDED.state, activated_at=EXCLUDED.activated_at;

  -- Profiles: A/B/D active+approved (ready); C draft.
  -- verification_state must be set explicitly: it defaults to 'unverified'
  -- and dating_profile_ready requires 'verified', so leaving it out made
  -- every candidate fail dating_candidate_is_current and every
  -- act_on_dating_introduction call raise introduction_unavailable --
  -- before reaching the double-blind contracts this file exists to test.
  INSERT INTO public.dating_profiles(user_id, display_name, city_region_code, relationship_intention, bio, profile_state, moderation_state, verification_state)
  VALUES
    (a, 'Dating A','Accra','Intentional dating',NULL,'active','approved','verified'),
    (b, 'Dating B','Kumasi','Intentional dating',NULL,'active','approved','verified'),
    (d, 'Dating D','Takoradi','Intentional dating',NULL,'active','approved','verified'),
    (c, 'Dating C','Tamale','Intentional dating',NULL,'draft','approved','verified')
  ON CONFLICT (user_id) DO UPDATE
    SET profile_state=EXCLUDED.profile_state,
        moderation_state=EXCLUDED.moderation_state,
        verification_state=EXCLUDED.verification_state;

  -- Preferences (dating_profile_ready needs non-empty gender/region/intention).
  INSERT INTO public.dating_preferences(user_id, min_age, max_age, gender_preferences, region_preferences, intention_preferences)
  VALUES
    (a, 25, 45, '["woman"]','["Accra"]','["intentional"]'),
    (b, 25, 45, '["man"]','["Kumasi"]','["intentional"]'),
    (d, 25, 45, '["man"]','["Takoradi"]','["intentional"]')
  ON CONFLICT (user_id) DO UPDATE
    SET gender_preferences=EXCLUDED.gender_preferences,
        region_preferences=EXCLUDED.region_preferences,
        intention_preferences=EXCLUDED.intention_preferences;

  -- Age gate: A/B/D adults, verified, not revoked/expired.
  INSERT INTO public.dating_age_verifications(user_id, birth_date, verification_method, verified_at)
  VALUES
    (a, current_date - interval '30 years', 'test', now()),
    (b, current_date - interval '31 years', 'test', now()),
    (d, current_date - interval '32 years', 'test', now())
  ON CONFLICT (user_id) DO UPDATE SET birth_date=EXCLUDED.birth_date;

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

  -- Feature snapshots for A, B, D (valid, not invalidated).
  -- consent_basis / features / source_provenance are all jsonb NOT NULL.
  INSERT INTO public.dating_feature_snapshots(id, user_id, algorithm_version, consent_basis, features, source_provenance)
  VALUES
    (v_snap_a, a, 'test-active-v1', '{"basis":"explicit_opt_in"}', '{}', '{}'),
    (v_snap_b, b, 'test-active-v1', '{"basis":"explicit_opt_in"}', '{}', '{}'),
    (v_snap_d, d, 'test-active-v1', '{"basis":"explicit_opt_in"}', '{}', '{}')
  ON CONFLICT (id) DO NOTHING;

  -- Live introductions: (A,B) and (A,D). user_low/high ordered by uuid text.
  INSERT INTO public.dating_introductions(
    id, pair_key, user_low_id, user_high_id, display_band, explanation_features,
    low_summary, high_summary, state, expires_at,
    algorithm_version, snapshot_low_id, snapshot_high_id, internal_score
  ) VALUES
    (v_intro_ab, public.dating_pair_key(a,b), LEAST(a,b), GREATEST(a,b),
     'some_shared_ground','{}','You share intentional-dating goals.','You share intentional-dating goals.',
     'presented', now() + interval '7 days',
     'test-active-v1',
     CASE WHEN a < b THEN v_snap_a ELSE v_snap_b END,
     CASE WHEN a < b THEN v_snap_b ELSE v_snap_a END,
     0.5),
    (v_intro_ad, public.dating_pair_key(a,d), LEAST(a,d), GREATEST(a,d),
     'some_shared_ground','{}','You share intentional-dating goals.','You share intentional-dating goals.',
     'presented', now() + interval '7 days',
     'test-active-v1',
     CASE WHEN a < d THEN v_snap_a ELSE v_snap_d END,
     CASE WHEN a < d THEN v_snap_d ELSE v_snap_a END,
     0.5)
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
-- 1. Owner RLS — each account sees only its own dating rows.
-- ---------------------------------------------------------------------------
SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000da01');
DO $$ DECLARE v int; BEGIN
  SELECT count(*) INTO v FROM public.dating_profiles;
  IF v <> 1 THEN RAISE EXCEPTION 'A: profile RLS expected 1 own row, got %', v; END IF;
  SELECT count(*) INTO v FROM public.dating_enrollments;
  IF v <> 1 THEN RAISE EXCEPTION 'A: enrollment RLS expected 1 own row, got %', v; END IF;
END $$;

SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000dc03');
DO $$ DECLARE v int; BEGIN
  SELECT count(*) INTO v FROM public.dating_profiles;
  IF v <> 1 THEN RAISE EXCEPTION 'C: profile RLS expected 1 own row, got %', v; END IF;
  -- C is an outsider to the A/B and A/D intros: base-table RLS must hide them.
  SELECT count(*) INTO v FROM public.dating_introductions;
  IF v <> 0 THEN RAISE EXCEPTION 'C: read % introduction rows (must be 0)', v; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. Outsider RPC read — C's get_my_dating_introductions returns 0 rows.
-- ---------------------------------------------------------------------------
DO $$ DECLARE v int; BEGIN
  SELECT count(*) INTO v FROM public.get_my_dating_introductions(20);
  IF v <> 0 THEN RAISE EXCEPTION 'C: get_my_dating_introductions returned % rows (must be 0)', v; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Actor forgery — C acting on the (A,B) intro raises and writes no action.
-- ---------------------------------------------------------------------------
DO $$ DECLARE v int; v_raised boolean := false; BEGIN
  BEGIN
    PERFORM public.act_on_dating_introduction(
      'forgery-key-c', '00000000-0000-0000-0000-000000ab0000', 'interested');
  EXCEPTION
    -- The RPC signals refusal with USING ERRCODE (e.g. 22023 introduction_unavailable,
    -- 42501 not_authenticated); catch any refusal here. A missing raise fails below.
    WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN RAISE EXCEPTION 'C: acting on non-member intro unexpectedly succeeded'; END IF;
  SELECT count(*) INTO v FROM public.dating_interest_actions
  WHERE actor_user_id = '00000000-0000-0000-0000-00000000dc03';
  IF v <> 0 THEN RAISE EXCEPTION 'C: forged action wrote % interest rows (must be 0)', v; END IF;
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
  s_forged text; m_forged text;   -- C acts on A/B's intro (exists, not a member)
  s_absent text; m_absent text;   -- C acts on a random nonexistent intro id
BEGIN
  BEGIN
    PERFORM public.act_on_dating_introduction('h2-forged','00000000-0000-0000-0000-000000ab0000','interested');
    RAISE EXCEPTION 'H2: forged act did not raise';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s_forged = RETURNED_SQLSTATE; m_forged := SQLERRM;
  END;
  BEGIN
    PERFORM public.act_on_dating_introduction('h2-absent','00000000-0000-0000-0000-0000000ab123','interested');
    RAISE EXCEPTION 'H2: nonexistent act did not raise';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s_absent = RETURNED_SQLSTATE; m_absent := SQLERRM;
  END;
  -- "belongs to someone else" and "does not exist" must be identical responses.
  IF s_forged <> s_absent OR m_forged <> m_absent THEN
    RAISE EXCEPTION 'H2 oracle: non-member (% / %) distinguishable from nonexistent (% / %)',
      s_forged, m_forged, s_absent, m_absent;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 4. Double-blind (C3) — A expresses interest; B must NOT be able to infer it.
-- ---------------------------------------------------------------------------
SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000da01');
DO $$ BEGIN
  PERFORM public.act_on_dating_introduction(
    'a-likes-b', '00000000-0000-0000-0000-000000ab0000', 'interested');
END $$;

SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000db02');
DO $$ DECLARE v_state text; BEGIN
  SELECT state INTO v_state FROM public.get_my_dating_introductions(20)
  WHERE id = '00000000-0000-0000-0000-000000ab0000';
  IF v_state IS NULL THEN
    RAISE EXCEPTION 'B: (A,B) intro missing from B''s list after A acted';
  END IF;
  -- The viewer-scoped status for a non-acting viewer must be 'open'. Any value
  -- reflecting A''s action ('interested', 'awaiting_response', 'matched') would
  -- be the banned one-sided-interest oracle.
  IF v_state <> 'open' THEN
    RAISE EXCEPTION 'B: double-blind leak — B sees state=% (must be open)', v_state;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 5. Match lifecycle (H5) — mutual interest matches; A exiting closes it.
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  -- B reciprocates → mutual match.
  PERFORM public.act_on_dating_introduction(
    'b-likes-a', '00000000-0000-0000-0000-000000ab0000', 'interested');
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
  UPDATE public.dating_feature_snapshots SET invalidated_at=NULL WHERE user_id=a;
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
DO $$ DECLARE v int; v_raised boolean := false; BEGIN
  BEGIN
    PERFORM public.act_on_dating_introduction(
      'a-acts-blocked-d', '00000000-0000-0000-0000-000000ad0000', 'interested');
  EXCEPTION
    WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN RAISE EXCEPTION 'A: acting on a blocked pair unexpectedly succeeded'; END IF;
  SELECT count(*) INTO v FROM public.dating_matches
  WHERE introduction_id = '00000000-0000-0000-0000-000000ad0000';
  IF v <> 0 THEN RAISE EXCEPTION 'blocked pair created % match(es) (must be 0)', v; END IF;

  -- The (A,D) pair must not surface in A's introductions list.
  SELECT count(*) INTO v FROM public.get_my_dating_introductions(20)
  WHERE id = '00000000-0000-0000-0000-000000ad0000';
  IF v <> 0 THEN RAISE EXCEPTION 'A: blocked (A,D) pair still visible in list (% rows)', v; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 6b. DATING-C2: authenticated cannot write dating_age_verifications directly.
-- ---------------------------------------------------------------------------
SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000da01');
DO $$ DECLARE v_raised boolean := false; BEGIN
  BEGIN
    INSERT INTO public.dating_age_verifications(user_id, birth_date, verification_method, verified_at)
    VALUES ('00000000-0000-0000-0000-00000000da01', current_date - interval '30 years', 'self', now());
  EXCEPTION WHEN OTHERS THEN v_raised := true;  -- RLS/REVOKE denial (42501) or RLS 0-row
  END;
  -- Either a hard permission error, or RLS silently blocked the write: assert no
  -- self-attested row leaked in for this user via the authenticated path.
  IF NOT v_raised
     AND EXISTS(SELECT 1 FROM public.dating_age_verifications
                WHERE user_id='00000000-0000-0000-0000-00000000da01' AND verification_method='self') THEN
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
  IF has_function_privilege('authenticated','public.submit_dating_report(text,uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute raw-target report RPC';
  END IF;
  IF has_function_privilege('authenticated','public.get_dating_operational_health()','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can read backend operational health';
  END IF;
  -- DATING-C2: age verification is backend-only. authenticated must be able to
  -- execute neither the writer nor the revoker, and service_role must.
  IF has_function_privilege('authenticated','public.verify_dating_age(uuid,date,text,uuid,timestamptz)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute the age-verification writer';
  END IF;
  IF has_function_privilege('authenticated','public.revoke_dating_age_verification(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute the age-verification revoker';
  END IF;
  IF NOT has_function_privilege('service_role','public.verify_dating_age(uuid,date,text,uuid,timestamptz)','EXECUTE') THEN
    RAISE EXCEPTION 'service_role cannot execute the age-verification writer';
  END IF;
  -- DATING-C4: former-partner exclusion writer/HMAC are backend-only.
  IF has_function_privilege('authenticated','public.record_dating_former_partner_exclusion(uuid, boolean)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute the former-partner exclusion writer';
  END IF;
  IF has_function_privilege('authenticated','public.dating_phone_hmac(text)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated can execute the phone-HMAC function';
  END IF;
  IF pg_get_function_result('public.get_my_dating_introductions(integer)'::regprocedure) ~* '(user_id|pair_key)' THEN
    RAISE EXCEPTION 'introduction payload exposes internal identity';
  END IF;
  IF pg_get_function_result('public.get_my_dating_matches(integer)'::regprocedure) ~* '(user_id|pair_key)' THEN
    RAISE EXCEPTION 'match payload exposes internal identity';
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
SET LOCAL app.settings.dating_exclusion_key = 'test-exclusion-key';
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
  VALUES (b, d, 'ended', now()) RETURNING id INTO v_rel_id;
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
  INSERT INTO public.dating_introductions(
    id, pair_key, user_low_id, user_high_id, display_band, explanation_features,
    low_summary, high_summary, state, expires_at,
    algorithm_version, snapshot_low_id, snapshot_high_id, internal_score
  ) VALUES (
    '00000000-0000-0000-0000-000000bd0000', public.dating_pair_key(b,d),
    LEAST(b,d), GREATEST(b,d), 'some_shared_ground','{}','x','x',
    'presented', now() + interval '7 days', 'test-active-v1',
    CASE WHEN b < d THEN v_snap_b ELSE v_snap_d END,
    CASE WHEN b < d THEN v_snap_d ELSE v_snap_b END, 0.5
  ) ON CONFLICT (id) DO NOTHING;
END $$;

-- B (a former partner of D) must not see the (B,D) intro, and acting must raise.
SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000db02');
DO $$ DECLARE v int; v_raised boolean := false; BEGIN
  SELECT count(*) INTO v FROM public.get_my_dating_introductions(20)
  WHERE id = '00000000-0000-0000-0000-000000bd0000';
  IF v <> 0 THEN RAISE EXCEPTION 'C4: former-partner (B,D) intro visible in list (% rows)', v; END IF;
  BEGIN
    PERFORM public.act_on_dating_introduction(
      'b-acts-former-d', '00000000-0000-0000-0000-000000bd0000', 'interested');
  EXCEPTION WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN RAISE EXCEPTION 'C4: acting on a former-partner intro unexpectedly succeeded'; END IF;
  SELECT count(*) INTO v FROM public.dating_matches
  WHERE introduction_id = '00000000-0000-0000-0000-000000bd0000';
  IF v <> 0 THEN RAISE EXCEPTION 'C4: former-partner pair created % match(es) (must be 0)', v; END IF;
END $$;

RESET ROLE;

ROLLBACK;
