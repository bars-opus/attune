-- Spec 2 W4b, migration 1 (§4.9 W4b; §3.3.4; §2.1 gate 8; §4.3
-- dating_trusted_devices; §4.4 dating_require_trusted_device,
-- trust_dating_device; S-7, C-6; R15; plan R-15..R-20): trusted devices.
-- A person with no device yet is unbound (nothing of theirs is tied to a
-- phone): the device of the first setup write is trusted for the setup
-- (R-16); the device that passes D11 is trusted (verified); any other
-- device reads reverify_device and no Dating data, until a liveness and
-- CompareFaces check (no age estimate) or a person trusts it. Up to 3
-- devices; one unused for 180 days no longer counts. Exposure-reducing
-- writes never ask (carry 11). Re-created from their live bodies (changed
-- lines marked -- Spec 2 W4b): dating_require_trusted_device (the real
-- check), dating_eligibility (gate 8, for the caller's own requests only:
-- R-17), private.dating_setup_guard (binds the first device),
-- get_dating_home (the reverify variant; where a verification pause's
-- check stands, T3 M-4), begin_dating_verification (the
-- reverify kind), decide_dating_human_review (a person's pass trusts the
-- device), private.dating_exit_internal (the devices go; a kept list is
-- marked kept), list/remove/add_dating_never_introduce (fix rounds 1-2,
-- C-1 and I-6: a kept row is never shown again or removed one at a time,
-- only counted, and still protects; adding its number looks exactly like
-- adding a fresh one).
-- Spec 2 W4 final (I-1a, I-1b rulings; M-3, M-4, M-10): Leave clears an age
-- pass (a fail stays); a person's pass on photos all newer than the age
-- decision clears the pass (the age is checked again); a phone is trusted
-- only through a session that ran on it (trust_dating_device takes
-- p_session), so a trust that lands after a Leave binds nothing; another
-- phone's open check answers session_elsewhere, and a re-check has its own
-- 5-a-day budget per phone; dating_storage_owns's device check is
-- re-created here (W3's committed migration is left as committed).
-- Changed lines are marked -- Spec 2 W4 final.
-- Grants in 20261109110010_dating_v2_trusted_devices_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- 1. The devices: a hash of the install's random id, never the id (§3.3.4).
CREATE TABLE IF NOT EXISTS public.dating_trusted_devices (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  device_hash text NOT NULL CHECK (device_hash ~ '^[0-9a-f]{64}$'),
  -- NULL: trusted for the setup only (R-16); set: passed a check here.
  verified_at timestamptz,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, device_hash)
);
ALTER TABLE public.dating_trusted_devices ENABLE ROW LEVEL SECURITY;
-- Fix round 1 (M-5): rows go only by exit, the cap of 3 and the account
-- cascade, never otherwise to zero: no rows means unbound, which any phone
-- passes. A future retention purge must keep at least the newest row.
COMMENT ON TABLE public.dating_trusted_devices IS
  'Spec 2 W4b: sha256 of the install id per trusted phone. Deleted only by exit, the 3-device cap and the account cascade; never purged to zero (no rows = unbound, which any phone passes).';

-- 1b. (Fix rounds 1-2, C-1 ruling) A Never-introduce row kept by Start
--     again, or by a Leave that keeps the list: never shown again, never
--     removed one at a time (only a Leave deletes it), still protecting;
--     the list gives only how many. No check, trust or phone clears it.
ALTER TABLE public.dating_never_introduce ADD COLUMN IF NOT EXISTS kept_at timestamptz;
-- (Fix round 2, I-6) Set when the person adds a kept row's number again: it
-- then shows as the new, visible entry they just added (its label theirs);
-- removing it hides it again, the kept protection staying.
ALTER TABLE public.dating_never_introduce ADD COLUMN IF NOT EXISTS shown_at timestamptz;
REVOKE ALL ON public.dating_trusted_devices FROM PUBLIC, anon, authenticated, service_role;

-- 2. A device's standing for a person: unbound (no device yet), trusted
--    (this one, used in the last 180 days) or untrusted (any other, or
--    none named). NULL never counts as trusted.
CREATE OR REPLACE FUNCTION private.dating_device_state(p_user uuid, p_hash text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_user IS NULL THEN 'untrusted'
    WHEN NOT EXISTS (SELECT 1 FROM public.dating_trusted_devices AS d WHERE d.user_id = p_user) THEN 'unbound'
    WHEN p_hash IS NOT NULL AND EXISTS (SELECT 1 FROM public.dating_trusted_devices AS d
                                         WHERE d.user_id = p_user AND d.device_hash = p_hash
                                           AND d.last_seen_at > now() - interval '180 days') THEN 'trusted'
    ELSE 'untrusted'
  END;
$$;

-- 3. A trusted device seen again: at most one write a day, never waiting
--    and never failing the read it runs in (best effort).
CREATE OR REPLACE FUNCTION private.dating_touch_device(p_user uuid, p_hash text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '200ms'
AS $$
BEGIN
  UPDATE public.dating_trusted_devices AS d SET last_seen_at = now()
   WHERE d.user_id = p_user AND d.device_hash = p_hash AND d.last_seen_at < now() - interval '1 day';
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$$;

-- 4. The first setup write's device (R-16), under the caller's setup lock.
--    (Fix round 1, M-7) It binds when the setup guard passes, even if the
--    writer then refuses: it is the account's own signed-in phone, as for a
--    write that lands.
CREATE OR REPLACE FUNCTION private.dating_bind_setup_device(p_user uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_hash constant text := private.dating_request_device_hash();
BEGIN
  IF p_user IS NULL OR v_hash IS NULL
     OR EXISTS (SELECT 1 FROM public.dating_trusted_devices AS d WHERE d.user_id = p_user) THEN
    RETURN;
  END IF;
  INSERT INTO public.dating_trusted_devices (user_id, device_hash) VALUES (p_user, v_hash)
  ON CONFLICT (user_id, device_hash) DO NOTHING;
END;
$$;

-- 5. A device that passed a check (service role: dating-verification, the
--    review decision): trusted, and at most 3 kept (the least recently
--    used go first, never the one just trusted).
--    Spec 2 W4 final (M-3): only through [p_session], a session of this
--    person that ran on this phone, open or passed. Leave deletes the
--    sessions, so a trust that lands after it (the vendor calls ran
--    across it) binds nothing to the exited account.
DROP FUNCTION IF EXISTS public.trust_dating_device(uuid, text); -- Spec 2 W4 final (M-3)
CREATE OR REPLACE FUNCTION public.trust_dating_device(p_user uuid, p_device_hash text, p_session uuid) -- Spec 2 W4 final (M-3)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_try integer;
BEGIN
  IF p_user IS NULL OR coalesce(p_device_hash ~ '^[0-9a-f]{64}$', false) IS NOT TRUE -- Spec 2 W4 final
     OR p_session IS NULL THEN -- Spec 2 W4 final (M-3)
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(p_user);
      IF NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'invalid'); -- fix round 1 (M-1): the interface's own codes
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.dating_verification_sessions AS s -- Spec 2 W4 final (M-3): a session of this
                      WHERE s.id = p_session AND s.user_id = p_user AND s.device_hash = p_device_hash -- Spec 2 W4 final person on this phone,
                        AND s.state IN ('started', 'awaiting_review', 'passed')) THEN -- Spec 2 W4 final open or passed
        RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable'); -- Spec 2 W4 final (M-3)
      END IF; -- Spec 2 W4 final (M-3)
      INSERT INTO public.dating_trusted_devices AS d (user_id, device_hash, verified_at, last_seen_at)
      VALUES (p_user, p_device_hash, now(), now())
      ON CONFLICT (user_id, device_hash) DO UPDATE SET verified_at = now(), last_seen_at = now();
      DELETE FROM public.dating_trusted_devices AS d
       WHERE d.user_id = p_user AND d.device_hash <> p_device_hash
         AND d.device_hash NOT IN (SELECT k.device_hash FROM public.dating_trusted_devices AS k
                                    WHERE k.user_id = p_user AND k.device_hash <> p_device_hash
                                    ORDER BY k.last_seen_at DESC, k.device_hash LIMIT 2);
      -- Fix round 2 (C-1 ruling): a pass never shows a kept list again: no
      -- trust (this one, decide's, or T6's video pass) touches kept_at.
      PERFORM private.bump_metric_internal('dating.device.trusted');
      RETURN jsonb_build_object('ok', true);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 6. Gate 8 (§2.1; R-17): only for the caller's own requests (a request
--    carries its own device; generation and the crons have none).
CREATE OR REPLACE FUNCTION private.dating_device_gate(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_user IS DISTINCT FROM auth.uid() THEN 'eligible'
    WHEN public.dating_require_trusted_device() IS TRUE THEN 'eligible'
    ELSE 'reverify_device'
  END;
$$;

-- 7. Which re-verification an untrusted device needs (§3.3.4): after a
--    passed check, a video check here ('verified'); before one, the setup
--    starts again here ('setup_restart').
CREATE OR REPLACE FUNCTION private.dating_reverify_variant(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM public.dating_trusted_devices AS d WHERE d.user_id = p_user AND d.verified_at IS NOT NULL)
      OR EXISTS (SELECT 1 FROM public.dating_age_verifications AS v
                  WHERE v.user_id = p_user AND v.identity_result = 'pass' AND v.revoked_at IS NULL)
    THEN 'verified' ELSE 'setup_restart'
  END;
$$;

-- 7b. (Task 3 review M-4) Where a verification pause's check stands, for
--     the home, as a fixed code (never why): held (a passed age check holds;
--     anything still pausing is something else, such as an open shared
--     space), final (a failed ID: no check can pass now), waiting (a new
--     check is waiting for a person or the ID vendor), needed (a check can
--     run). Only a verification pause carries it.
CREATE OR REPLACE FUNCTION private.dating_check_standing(p_user uuid, p_pause_reason text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_user IS NULL OR p_pause_reason IS DISTINCT FROM 'verification' THEN '{}'::jsonb
    ELSE jsonb_build_object('check', CASE
      WHEN coalesce(public.dating_age_gate_holds(p_user), false) THEN 'held'
      WHEN private.dating_verification_state(p_user) ->> 'age' = 'fail' THEN 'final'
      WHEN EXISTS (SELECT 1 FROM public.dating_verification_sessions AS s
                    WHERE s.user_id = p_user AND s.kind = 'activation' AND s.state = 'awaiting_review') THEN 'waiting'
      ELSE 'needed' END)
  END;
$$;

-- 7c. (Fix round 2, C-1 ruling) Round 1's private.dating_kept_hidden is
--     gone: a kept row is hidden from every phone.
DROP FUNCTION IF EXISTS private.dating_kept_hidden(uuid);

-- 8. Re-created from their live bodies (after W4a); every changed line is
--    marked -- Spec 2 W4b (Task 5 Step 7 diffs them).
CREATE OR REPLACE FUNCTION public.dating_require_trusted_device()
 RETURNS boolean
 LANGUAGE plpgsql -- Spec 2 W4b
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE -- Spec 2 W4b
  v_user constant uuid := auth.uid(); -- Spec 2 W4b
  v_hash constant text := private.dating_request_device_hash(); -- Spec 2 W4b
  v_state text; -- Spec 2 W4b
BEGIN -- Spec 2 W4b
  -- Spec 2 W4b (§3.3.4): unbound (no device yet) or this trusted device;
  -- Spec 2 W4b never NULL, never true without a signed-in caller.
  IF v_user IS NULL THEN -- Spec 2 W4b
    RETURN false; -- Spec 2 W4b
  END IF; -- Spec 2 W4b
  v_state := private.dating_device_state(v_user, v_hash); -- Spec 2 W4b
  IF v_state = 'trusted' AND EXISTS (SELECT 1 FROM public.dating_trusted_devices AS d -- Spec 2 W4b (fix round 1, M-2): no write path on a fresh row
                                       WHERE d.user_id = v_user AND d.device_hash = v_hash -- Spec 2 W4b
                                         AND d.last_seen_at < now() - interval '1 day') THEN -- Spec 2 W4b
    PERFORM private.dating_touch_device(v_user, v_hash); -- Spec 2 W4b
  END IF; -- Spec 2 W4b
  RETURN coalesce(v_state IN ('unbound', 'trusted'), false); -- Spec 2 W4b
END; -- Spec 2 W4b
$function$;

CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate'::text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_profile jsonb;
  v_country text;
  v_region text;
  v_config public.country_safety_config;
BEGIN
  IF p_scope IS NULL OR p_scope NOT IN ('setup', 'candidate') THEN
    RAISE EXCEPTION 'eligibility:invalid_scope' USING ERRCODE = '22023';
  END IF;
  -- 1. Feature.
  IF public.dating_flag_enabled('dating_mode_enabled') IS NOT TRUE THEN
    RETURN 'feature_unavailable';
  END IF;
  -- 1b. (Fix round 1, I-1) Carried restrictions are readable only under a
  -- set exclusion key whose stored fingerprint matches. Otherwise nobody is
  -- eligible, under the generic system reason (never a personal one),
  -- counted best-effort (a read-only caller can't write; the refusal stands).
  IF private.dating_exclusion_key_ready() IS NOT TRUE THEN
    BEGIN
      PERFORM private.bump_metric_internal('dating.eligibility.key_not_ready');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RETURN 'feature_unavailable';
  END IF;
  -- 2. Account: an adult by Spec 1's DOB, a confirmed phone, EULA v2.
  IF p_user IS NULL
     OR coalesce(public.account_age(p_user), 0) < 18
     OR NOT EXISTS (SELECT 1 FROM auth.users AS a WHERE a.id = p_user AND a.phone_confirmed_at IS NOT NULL)
     OR NOT EXISTS (SELECT 1 FROM public.users AS u
                     WHERE u.id = p_user AND u.eula_accepted_at IS NOT NULL
                       AND coalesce(substring(u.eula_version FROM '^[0-9]{1,3}$')::integer, 0) >= 2) THEN
    RETURN 'account_unavailable';
  END IF;
  -- 3. Standing. (Fix round 1, I-1) A person whose own HMAC can't be
  -- computed under the set key can't be checked against carried records.
  IF public.dating_account_in_good_standing(p_user) IS NOT TRUE
     OR public.dating_phone_hmac_for_user(p_user) IS NULL THEN
    RETURN 'account_unavailable';
  END IF;
  -- 4. Relationship guard.
  IF public.dating_has_relationship(p_user) IS NOT FALSE THEN
    RETURN 'relationship_active';
  END IF;
  -- 4b. Spec 2 W2 (Task 3 fix round 1, I-1): a candidate whose chosen path is
  -- Spec 2 W2 not Dating is never introduced, even before the path pause lands.
  -- Spec 2 W2 Candidates only (setup's answer drives the cron's 'gates' pause;
  -- Spec 2 W2 a path change has its own); NULL, never chosen, is no signal.
  IF p_scope = 'candidate' AND coalesce((SELECT u.path FROM public.users AS u WHERE u.id = p_user) <> 'dating', false) THEN -- Spec 2 W2
    RETURN 'account_unavailable'; -- Spec 2 W2
  END IF; -- Spec 2 W2
  -- 5. Gentle wait (Spec 2 W2, A-9): candidates only; setup goes ahead.
  IF p_scope = 'candidate' AND private.dating_gentle_wait_opens_at(p_user) IS NOT NULL THEN -- Spec 2 W2
    RETURN 'gentle_wait'; -- Spec 2 W2
  END IF; -- Spec 2 W2
  IF p_scope = 'candidate' AND EXISTS (SELECT 1 FROM public.relationships AS r -- Spec 2 W2 fix round 1 (M-3): an ending with no date is never "no wait"
                                        WHERE p_user IN (r.user_a, r.user_b) AND r.status = 'ended' AND r.ended_at IS NULL) THEN -- Spec 2 W2
    BEGIN -- Spec 2 W2
      PERFORM private.bump_metric_internal('dating.gentle_wait.undated'); -- Spec 2 W2
    EXCEPTION WHEN OTHERS THEN -- Spec 2 W2
      NULL; -- Spec 2 W2
    END; -- Spec 2 W2
    RETURN 'account_unavailable'; -- Spec 2 W2
  END IF; -- Spec 2 W2
  -- 6. Country and region.
  SELECT to_jsonb(p) INTO v_profile FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  v_country := v_profile ->> 'country_code';
  v_region := v_profile ->> 'region_code';
  IF v_country IS NULL THEN
    RETURN CASE WHEN p_scope = 'setup' THEN private.dating_device_gate(p_user) ELSE 'country_closed' END; -- Spec 2 W4b: gate 8
  END IF;
  v_config := public.dating_country_config(v_country);
  IF v_config IS NULL OR v_config.dating_enabled IS NOT TRUE THEN
    RETURN 'country_closed';
  END IF;
  IF v_config.open_regions IS NOT NULL
     AND (v_region IS NULL OR (v_region = ANY (v_config.open_regions)) IS NOT TRUE) THEN
    RETURN CASE WHEN v_region IS NULL AND p_scope = 'setup' THEN private.dating_device_gate(p_user) ELSE 'region_closed' END; -- Spec 2 W4b: gate 8
  END IF;
  -- 8. Spec 2 W4b (§2.1, R-17): a trusted device, for the caller's own requests.
  RETURN private.dating_device_gate(p_user); -- Spec 2 W4b
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_setup_guard()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  PERFORM private.dating_lock_setup(v_user);
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN 'reverify_device';
  END IF;
  IF public.dating_eligibility(v_user, 'setup') IS DISTINCT FROM 'eligible' THEN
    RETURN 'not_eligible';
  END IF;
  IF private.dating_request_device_hash() IS NULL -- Spec 2 W4b (fix round 1, I-3; R-16): a setup write names its phone
     AND NOT EXISTS (SELECT 1 FROM public.dating_trusted_devices AS d WHERE d.user_id = v_user) THEN -- Spec 2 W4b
    RETURN 'reverify_device'; -- Spec 2 W4b
  END IF; -- Spec 2 W4b
  PERFORM private.dating_bind_setup_device(v_user); -- Spec 2 W4b (§3.3.4, R-16): the first setup write's device
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_dating_home()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country text;
  v_region text;
  v_config public.country_safety_config;
  v_enrol public.dating_enrollments;
  v_opens timestamptz;
  v_after timestamptz;
  v_err text;
  v_undated boolean; -- Spec 2 W3a (fix round 1, M-2, M-4)
  v_cand text; -- Spec 2 W3a
  v_has jsonb; -- Spec 2 W3a (C-2)
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_has := jsonb_build_object('has_data', private.dating_has_data(v_user)); -- Spec 2 W3a (C-2)
  v_reason := public.dating_eligibility(v_user, 'setup');
  SELECT p.country_code::text, p.region_code INTO v_country, v_region
    FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_reason IS NOT DISTINCT FROM 'feature_unavailable' THEN
    IF public.dating_require_trusted_device() IS NOT TRUE THEN -- Spec 2 W4b (fix round 1, M-4): nothing about the person to another phone
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'feature_unavailable'); -- Spec 2 W4b
    END IF; -- Spec 2 W4b
    v_country := coalesce(v_country, private.dating_phone_country((SELECT a.phone FROM auth.users AS a WHERE a.id = v_user))); -- Spec 2 W3a
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'feature_unavailable', 'country', v_country, -- Spec 2 W3a (C-2)
      'notify', private.dating_notice_state(v_user, v_country, NULL)); -- Spec 2 W3a (R-4, R-5)
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'reverify_device', -- Spec 2 W3a (C-2); Spec 2 W4b
      'variant', private.dating_reverify_variant(v_user)); -- Spec 2 W4b (§3.3.4): setup_restart or verified
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'account_unavailable' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', private.dating_unavailable_state(v_user)); -- Spec 2 W3a (C-2)
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'country_closed' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'country_closed', 'country', v_country, -- Spec 2 W3a (C-2)
      'notify', private.dating_notice_state(v_user, v_country, NULL)); -- Spec 2 W3a
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'region_closed' THEN
    v_config := public.dating_country_config(v_country);
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'region_closed', 'country', v_country, 'region', v_region, -- Spec 2 W3a (C-2)
      'open_regions', to_jsonb(coalesce(v_config.open_regions, ARRAY[]::text[])), -- Spec 2 W3a
      'notify', private.dating_notice_state(v_user, v_country, v_region)); -- Spec 2 W3a
  END IF;
  SELECT * INTO v_enrol FROM public.dating_enrollments AS e WHERE e.user_id = v_user;
  IF v_reason IS NOT DISTINCT FROM 'relationship_active' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || CASE WHEN v_enrol.state = 'paused' -- Spec 2 W3a (C-2)
                THEN jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason, -- Spec 2 W3a (fix round 1, M-3)
                                        'can_resume', false) -- Spec 2 W3a (T4 fix round 1, I-2): a shared space is open now
                     || private.dating_check_standing(v_user, v_enrol.pause_reason) -- Spec 2 W4b (T3 M-4): where the check stands
                     || CASE WHEN v_enrol.pause_reason = 'same_gender_switch' THEN jsonb_build_object('country', v_country) -- Spec 2 W3a
                             ELSE '{}'::jsonb END -- Spec 2 W3a
                ELSE jsonb_build_object('state', 'unavailable') END;
  END IF;
  IF v_reason IS DISTINCT FROM 'eligible' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- an unknown or NULL reason fails closed -- Spec 2 W3a (C-2)
  END IF;
  IF v_enrol.state = 'suspended' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- suspended without a live restriction (W7a routes it) -- Spec 2 W3a (C-2)
  END IF;
  IF v_enrol.state = 'paused' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason, -- Spec 2 W3a (C-2)
      'can_resume', coalesce(v_enrol.pause_reason IS DISTINCT FROM 'verification' OR public.dating_age_gate_holds(v_user), false)) -- Spec 2 W4a (fix round 1, M-2): a verification pause resumes once the check holds; W3a (T4 fix round 1, I-2): no shared space holds it
      || private.dating_check_standing(v_user, v_enrol.pause_reason) -- Spec 2 W4b (T3 M-4): where the check stands
      || CASE WHEN v_enrol.pause_reason = 'same_gender_switch' THEN jsonb_build_object('country', v_country) -- Spec 2 W3a (the §2.4 note)
              ELSE '{}'::jsonb END; -- Spec 2 W3a
  END IF;
  v_opens := private.dating_gentle_wait_opens_at(v_user);
  v_undated := EXISTS (SELECT 1 FROM public.relationships AS r -- Spec 2 W3a (fix round 1, M-2, M-4): an ending with no date
                       WHERE v_user IN (r.user_a, r.user_b) AND r.status = 'ended' AND r.ended_at IS NULL); -- Spec 2 W3a
  IF v_enrol.state = 'active' THEN
    -- Spec 2 W3a (fix round 1, M-2): read here, so a home read never
    -- Spec 2 W3a reaches the candidate check's undated-ending counter.
    IF v_undated THEN -- Spec 2 W3a
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a (M-2)
    END IF; -- Spec 2 W3a (M-2)
    -- Spec 2 W3a (W2 carry): never "you're live" while the candidate check
    -- Spec 2 W3a refuses for anything but the wait (an undated ending, a
    -- Spec 2 W3a path off Dating); the wait itself is the cool-off below.
    v_cand := public.dating_eligibility(v_user, 'candidate'); -- Spec 2 W3a
    IF v_cand IS DISTINCT FROM 'eligible' AND v_cand IS DISTINCT FROM 'gentle_wait' THEN -- Spec 2 W3a
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a
    END IF; -- Spec 2 W3a
    -- The first drop is the later of the open date and the 72 h cool-off
    -- from account creation (§2.1, §2.8).
    v_after := greatest(coalesce(v_opens, '-infinity'::timestamptz),
                        (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours');
    IF v_after > now() THEN
      RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'cool_off', 'first_drop_at', private.dating_first_drop_at(v_user, v_after)); -- Spec 2 W3a (C-2)
    END IF;
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'active'); -- Spec 2 W3a (C-2)
  END IF;
  IF v_opens IS NOT NULL THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'gentle_wait', 'ended_at', (v_opens AT TIME ZONE 'UTC' - interval '30 days') AT TIME ZONE 'UTC', 'opens_at', v_opens, -- in UTC (a DST change moves nothing) -- Spec 2 W3a (C-2)
                              'next_step', private.dating_next_step(v_user), -- Spec 2 W3a
                              'can_shorten', coalesce(private.dating_gentle_wait_can_shorten(v_user), false), -- Spec 2 W3a (carry 8)
                              'first_drop_at', private.dating_first_drop_at(v_user, greatest(v_opens, now(), -- Spec 2 W3a
                                (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours'))); -- Spec 2 W3a
  END IF;
  IF private.dating_next_step(v_user) IS NOT DISTINCT FROM 'how' THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'not_started', -- Spec 2 W3a (D1 line 6)
      'first_drop_at', CASE WHEN v_undated THEN NULL -- Spec 2 W3a (fix round 1, M-4): no date to promise
        ELSE private.dating_first_drop_at(v_user, greatest(now(), -- Spec 2 W3a
        (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours')) END); -- Spec 2 W3a
  END IF;
  IF private.dating_next_step(v_user) IS NOT DISTINCT FROM 'verify' -- Spec 2 W4a (§3.1): a person or the ID vendor is checking
     AND EXISTS (SELECT 1 FROM public.dating_verification_sessions AS vs -- Spec 2 W4a
                  WHERE vs.user_id = v_user AND vs.kind = 'activation' AND vs.state = 'awaiting_review') THEN -- Spec 2 W4a
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'verifying', 'next_step', 'verify'); -- Spec 2 W4a
  END IF; -- Spec 2 W4a
  RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'setup_in_progress', 'next_step', private.dating_next_step(v_user), -- Spec 2 W3a (C-2)
    'first_drop_at', CASE WHEN v_undated THEN NULL -- Spec 2 W3a (D13; fix round 1, M-4)
      ELSE private.dating_first_drop_at(v_user, greatest(now(), -- Spec 2 W3a
      (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours')) END); -- Spec 2 W3a
EXCEPTION WHEN raise_exception THEN
  -- An unreadable field or a missing field key is no state the person can
  -- act on: the neutral 'unavailable', never a raw error. Anything else raises.
  -- Every re-creation keeps this handler (W4, W5, W7, W8 add decrypting
  -- readers; nothing in v1's call graph decrypts yet). Counted best-effort.
  v_err := SQLERRM;
  IF v_err IN ('dating:field_decrypt_failed', 'dating:field_key_missing') THEN
    BEGIN
      PERFORM private.bump_metric_internal(CASE WHEN v_err = 'dating:field_key_missing'
                                                THEN 'dating.field_key.missing' ELSE 'dating.home.unreadable_field' END);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a (C-2)
  END IF;
  RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.begin_dating_verification(p_user uuid, p_kind text, p_step text, p_vendor text, p_device_hash text DEFAULT NULL::text, p_document text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_try integer;
  v_open public.dating_verification_sessions;
  v_row public.dating_verification_sessions;
  v_state jsonb;
  v_country text;
  v_gestures text[];
  v_has_open boolean;
  v_device text; -- Spec 2 W4b
BEGIN
  IF p_user IS NULL OR (p_kind IN ('activation', 'reverify')) IS NOT TRUE -- Spec 2 W4b
     OR (p_step IN ('liveness', 'id', 'human')) IS NOT TRUE
     OR coalesce(p_vendor ~ '^[a-z0-9_]{1,40}$', false) IS NOT TRUE
     OR (p_device_hash IS NOT NULL AND p_device_hash !~ '^[0-9a-f]{64}$')
     OR (p_step = 'id') IS DISTINCT FROM (p_document IS NOT NULL)
     OR (p_document IS NOT NULL AND p_document !~ '^[a-z0-9_]{1,40}$') -- Spec 2 W4b
     OR p_device_hash IS NULL -- Spec 2 W4b (fix round 1, I-3): every check names its phone
     OR (p_kind = 'reverify' AND p_step = 'id') THEN -- Spec 2 W4b: a re-check has no ID route
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF private.dating_verification_available() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(p_user);
      IF public.dating_eligibility(p_user, 'setup') IS DISTINCT FROM 'eligible'
         OR NOT EXISTS (SELECT 1 FROM public.dating_enrollments AS e
                         WHERE e.user_id = p_user AND e.state IN ('profile_draft', 'active', 'paused')) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
      END IF;
      IF private.dating_consent_granted(p_user, 'biometric_verification') IS NOT TRUE THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'consent_required');
      END IF;
      v_state := private.dating_verification_state(p_user);
      IF v_state ->> 'age' = 'fail' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'age_not_confirmed');
      END IF;
      v_device := private.dating_device_state(p_user, p_device_hash); -- Spec 2 W4b (§3.3.4)
      IF p_kind = 'activation' AND v_device = 'untrusted' THEN -- Spec 2 W4b: the first check runs on the setup's own phone
        RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device'); -- Spec 2 W4b
      END IF; -- Spec 2 W4b
      IF p_kind = 'reverify' AND v_device IS DISTINCT FROM 'untrusted' THEN -- Spec 2 W4b: nothing to re-check on this phone
        RETURN jsonb_build_object('ok', false, 'reason', 'already_verified'); -- Spec 2 W4b
      END IF; -- Spec 2 W4b
      IF p_kind = 'reverify' AND private.dating_reverify_variant(p_user) IS DISTINCT FROM 'verified' THEN -- Spec 2 W4b (fix round 1, I-4): the home's rule; before a pass, the setup starts again
        RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible'); -- Spec 2 W4b
      END IF; -- Spec 2 W4b
      IF p_kind = 'activation' AND ((p_step = 'id' AND v_state ->> 'age' = 'pass') -- Spec 2 W4b: activation only
         OR (p_step = 'human' AND v_state ->> 'identity' = 'pass'
             AND (SELECT p.verification_state FROM public.dating_profiles AS p WHERE p.user_id = p_user) = 'verified')
         OR (p_step = 'liveness' AND v_state ->> 'age' = 'pass' AND v_state ->> 'identity' = 'pass'
             AND (SELECT p.verification_state FROM public.dating_profiles AS p WHERE p.user_id = p_user) = 'verified')) THEN -- Spec 2 W4b
        RETURN jsonb_build_object('ok', false, 'reason', 'already_verified');
      END IF;
      IF p_step IN ('liveness', 'human')
         AND (SELECT count(*) FROM public.dating_profile_photos AS f
               WHERE f.user_id = p_user AND f.moderation_state = 'approved') < 2 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'photos_required');
      END IF;
      IF p_step = 'id' THEN
        SELECT p.country_code::text INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = p_user;
        IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce((public.dating_country_config(v_country)).id_documents, '[]'::jsonb)) AS d
                        WHERE d ->> 'code' = p_document) THEN
          RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
        END IF;
      END IF;
      UPDATE public.dating_verification_sessions AS s
         SET state = 'expired', updated_at = now()
       WHERE s.user_id = p_user AND s.state = 'started' AND s.expires_at <= now();
      SELECT * INTO v_open FROM public.dating_verification_sessions AS s
       WHERE s.user_id = p_user AND s.state IN ('started', 'awaiting_review') FOR UPDATE;
      v_has_open := FOUND;
      IF v_has_open AND v_open.state = 'awaiting_review' -- Spec 2 W4b (R-14): a re-check is told only of its own phone's
         AND v_open.kind = p_kind AND (p_kind = 'activation' OR v_open.device_hash IS NOT DISTINCT FROM p_device_hash) THEN -- Spec 2 W4b (fix round 1, I-2): activation too, only of its own kind
        RETURN jsonb_build_object('ok', false, 'reason', 'awaiting_review', 'session_id', v_open.id);
      END IF;
      -- Spec 2 W4a (T2 fix round 1, M-5; fix round 2, N-2): at most 20
      -- vendor sessions an hour per person on the video and the ID route, a
      -- resumed start's included. begin only reads the count:
      -- set_dating_verification_ref adds one once the vendor session exists,
      -- so a start the vendor never answered uses nothing. Each refusal is
      -- counted; a refused start ends nothing.
      IF p_step IN ('liveness', 'id') -- Spec 2 W4a
         AND coalesce((SELECT r.request_count FROM public.dating_rate_limits AS r -- Spec 2 W4a
                        WHERE r.user_id = p_user AND r.operation = 'dating_verify_vendor_session' -- Spec 2 W4a
                          AND r.window_started_at + interval '1 hour' > now()), 0) >= 20 THEN -- Spec 2 W4a
        PERFORM private.bump_metric_internal('dating.verify.vendor_session_limited'); -- Spec 2 W4a
        RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited'); -- Spec 2 W4a
      END IF; -- Spec 2 W4a
      IF v_has_open AND v_open.step = p_step AND v_open.id_document IS NOT DISTINCT FROM p_document -- Spec 2 W4b
         AND v_open.kind = p_kind AND (p_kind = 'activation' OR v_open.device_hash IS NOT DISTINCT FROM p_device_hash) THEN -- Spec 2 W4b (R-14): its own kind, a re-check its own phone
        UPDATE public.dating_verification_sessions AS s
           SET vendor = p_vendor, device_hash = coalesce(p_device_hash, s.device_hash), updated_at = now()
         WHERE s.id = v_open.id RETURNING * INTO v_row;
        RETURN jsonb_build_object('ok', true, 'session_id', v_row.id, 'step', v_row.step, 'attempts', v_row.attempts,
                                  'resumed', true, 'gestures', to_jsonb(v_row.gestures), 'expires_at', v_row.expires_at);
      END IF;
      IF v_has_open AND p_kind = 'reverify' -- Spec 2 W4b (R-14): a re-check never ends the owner's session or another phone's
         AND (v_open.kind IS DISTINCT FROM 'reverify' OR v_open.device_hash IS DISTINCT FROM p_device_hash) THEN -- Spec 2 W4b
        RETURN jsonb_build_object('ok', false, 'reason', 'session_elsewhere'); -- Spec 2 W4 final (M-4): never busy (it can last 72 hours)
      END IF; -- Spec 2 W4b
      -- A refused start never ends the open session (the limit is read first).
      IF (SELECT count(*) FROM public.dating_verification_sessions AS s
           WHERE s.user_id = p_user AND s.created_at > now() - interval '1 day' -- Spec 2 W4 final
             AND s.kind = p_kind -- Spec 2 W4 final (M-4): the owner's 5 a day are the owner's;
             AND (p_kind = 'activation' OR s.device_hash = p_device_hash)) >= 5 THEN -- Spec 2 W4 final a re-check's, its own phone's
        RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END IF;
      IF v_has_open THEN
        UPDATE public.dating_verification_sessions AS s SET state = 'expired', updated_at = now() WHERE s.id = v_open.id;
      END IF;
      IF v_has_open AND v_open.kind = 'reverify' AND v_open.step = 'human' THEN -- Spec 2 W4b (fix round 1, I-2): its review photos go
        PERFORM public.queue_media_deletion('dating-verification-review', v_open.id::text || '/' || n || '.jpg') -- Spec 2 W4b
           FROM unnest(ARRAY['1', '2']) AS n; -- Spec 2 W4b
      END IF; -- Spec 2 W4b
      IF p_step = 'human' THEN
        SELECT array_agg(g ORDER BY random()) INTO v_gestures
          FROM (SELECT g FROM unnest(ARRAY['three_fingers', 'left_ear', 'thumbs_up']) AS g ORDER BY random() LIMIT 2) AS pick;
      END IF;
      INSERT INTO public.dating_verification_sessions (user_id, kind, step, vendor, device_hash, id_document, gestures, expires_at)
      VALUES (p_user, p_kind, p_step, p_vendor, p_device_hash, p_document, v_gestures,
              now() + CASE p_step WHEN 'liveness' THEN interval '30 minutes'
                                  WHEN 'id' THEN interval '24 hours' ELSE interval '72 hours' END)
      RETURNING * INTO v_row;
      PERFORM private.bump_metric_internal('dating.verify.started'); -- Fix round 1 (M-7): §6.9's dating.verify. names
      RETURN jsonb_build_object('ok', true, 'session_id', v_row.id, 'step', v_row.step, 'attempts', 0,
                                'resumed', false, 'gestures', to_jsonb(v_row.gestures), 'expires_at', v_row.expires_at);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure OR unique_violation THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$function$;

CREATE OR REPLACE FUNCTION public.decide_dating_human_review(p_session uuid, p_outcome text, p_decided_by uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
DECLARE
  v_row public.dating_verification_sessions;
  v_user uuid;
  v jsonb;
  v_try integer;
  v_h numeric;
BEGIN
  IF p_session IS NULL OR p_decided_by IS NULL OR (p_outcome IN ('pass', 'fail', 'ask_for_id')) IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  SELECT s.user_id INTO v_user FROM public.dating_verification_sessions AS s WHERE s.id = p_session;
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
  END IF;
  FOR v_try IN 1..3 LOOP -- Fix round 1 (M-4): three tries, then busy
    BEGIN
      PERFORM private.dating_lock_setup(v_user); -- the shared lock order: the person first, then rows
      -- Fix round 1 (I-2 ruling): a human review, or (until W7b's console
      -- owns ID review) an ID check waiting for review, which a reviewer may
      -- only send back for another ID: a person never passes age (§3.3.1).
      SELECT * INTO v_row FROM public.dating_verification_sessions AS s
       WHERE s.id = p_session AND s.state = 'awaiting_review'
         AND (s.step = 'human' OR (s.step = 'id' AND p_outcome = 'ask_for_id')) -- Spec 2 W4b
         AND (p_outcome <> 'ask_for_id' OR s.kind = 'activation') FOR UPDATE; -- Spec 2 W4b (fix round 1, I-1): a re-check has no ID route
      IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
      END IF;
      IF p_outcome IN ('pass', 'fail') AND v_row.kind = 'activation' THEN -- Spec 2 W4b: a re-check never writes the owner's result
        IF p_outcome = 'pass' AND private.dating_age_recheck_due(v_row.user_id) THEN -- Spec 2 W4 final (I-1b): a person never passes age;
          UPDATE public.dating_age_verifications AS a -- Spec 2 W4 final photos all newer than the age pass: the age is checked again
             SET age_method = NULL, age_result = NULL, challenge_age = NULL, age_vendor = NULL, age_decided_at = NULL, -- Spec 2 W4 final
                 updated_at = now() -- Spec 2 W4 final
           WHERE a.user_id = v_row.user_id AND a.age_result = 'pass' AND a.revoked_at IS NULL; -- Spec 2 W4 final
        END IF; -- Spec 2 W4 final (I-1b)
        v := public.record_dating_identity_check(v_row.user_id, 'human_gesture', p_outcome, 'attune', p_decided_by);
        IF (v ->> 'ok')::boolean IS NOT TRUE THEN
          RETURN v;
        END IF;
      ELSIF p_outcome = 'ask_for_id' AND v_row.kind = 'activation' THEN -- Spec 2 W4b (fix round 1, I-1)
        UPDATE public.dating_profiles AS p SET verification_state = 'unverified'
         WHERE p.user_id = v_row.user_id AND p.verification_state = 'needs_review';
      END IF;
      IF p_outcome = 'pass' AND v_row.device_hash IS NOT NULL THEN -- Spec 2 W4b (§3.3.4; fix round 1, C-1): a person's pass trusts the phone it ran on
        v := public.trust_dating_device(v_row.user_id, v_row.device_hash, p_session); -- Spec 2 W4 final (M-3): through its own session
        IF (v ->> 'ok')::boolean IS NOT TRUE THEN -- Spec 2 W4b
          RETURN v; -- Spec 2 W4b
        END IF; -- Spec 2 W4b
      END IF; -- Spec 2 W4b
      UPDATE public.dating_verification_sessions AS s
         SET state = CASE WHEN p_outcome = 'pass' THEN 'passed' ELSE 'failed' END,
             outcome = CASE p_outcome WHEN 'pass' THEN 'verified' WHEN 'fail' THEN 'identity_failed' ELSE 'ask_for_id' END,
             awaiting_since = NULL,
             updated_at = now()
       WHERE s.id = p_session;
      v_h := extract(epoch FROM now() - coalesce(v_row.awaiting_since, v_row.updated_at)) / 3600;
      PERFORM private.bump_metric_internal('dating.verify.hours_to_decision.' || CASE -- §6.9 (fix round 1, M-7)
        WHEN v_h < 6 THEN '0_6' WHEN v_h < 24 THEN '6_24' WHEN v_h < 48 THEN '24_48'
        WHEN v_h < 72 THEN '48_72' ELSE '72_plus' END);
      IF v_row.step = 'human' THEN -- an ID check has no review photos
        PERFORM public.queue_media_deletion('dating-verification-review', p_session::text || '/' || n || '.jpg')
           FROM unnest(ARRAY['1', '2']) AS n;
      END IF;
      RETURN jsonb_build_object('ok', true);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_exit_internal(p_user uuid, p_keep_never_introduce boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_found boolean;
  v_exited_at timestamptz;
BEGIN
  IF p_user IS NULL THEN
    RETURN;
  END IF;
  -- The row order: the enrolment before the profile (as activation, the
  -- pauses and the parked trigger).
  SELECT e.exited_at INTO v_exited_at FROM public.dating_enrollments AS e WHERE e.user_id = p_user FOR UPDATE;
  v_found := FOUND;
  -- Uploads never attached go with their storage objects; photo rows queue
  -- their own objects (dating_photos_queue_media_before_delete). Both go
  -- through queue_media_deletion, so the CSAM evidence guard holds back an
  -- object under an open, unquarantined match.
  PERFORM public.queue_media_deletion('dating-profile-photos', i.storage_key)
     FROM public.dating_photo_upload_intents AS i WHERE i.user_id = p_user -- Spec 2 W3c (Task 9 fix round 1, I-1): an intent names its photo's object
      AND NOT EXISTS (SELECT 1 FROM public.dating_profile_photos AS f -- Spec 2 W3c (Task 9 fix round 1, I-1)
                       WHERE f.storage_key = i.storage_key AND f.csam_state = 'hit'); -- Spec 2 W3c (Task 9 fix round 1, I-1): not a hit's
  DELETE FROM public.dating_photo_upload_intents AS i WHERE i.user_id = p_user;
  DELETE FROM public.dating_profile_photos AS f WHERE f.user_id = p_user;
  DELETE FROM public.dating_prompts AS q WHERE q.user_id = p_user;
  DELETE FROM public.dating_settings AS t WHERE t.user_id = p_user;
  DELETE FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user;
  DELETE FROM public.dating_preferences AS d WHERE d.user_id = p_user;
  DELETE FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  DELETE FROM public.dating_date_reflections AS r WHERE r.author_user_id = p_user;
  DELETE FROM public.dating_session_context AS c WHERE c.user_id = p_user;
  DELETE FROM public.dating_notify_requests AS n WHERE n.user_id = p_user;
  IF to_regclass('public.dating_gentle_wait_reflections') IS NOT NULL THEN -- W2's table
    EXECUTE 'DELETE FROM public.dating_gentle_wait_reflections WHERE user_id = $1' USING p_user;
  END IF;
  IF NOT coalesce(p_keep_never_introduce, false) THEN
    DELETE FROM public.dating_never_introduce AS n WHERE n.owner_user_id = p_user;
  ELSE -- Spec 2 W4b (fix rounds 1-2, C-1): kept, never shown again, its label gone
    UPDATE public.dating_never_introduce AS n SET kept_at = coalesce(n.kept_at, now()), shown_at = NULL, label = NULL -- Spec 2 W4b
     WHERE n.owner_user_id = p_user; -- Spec 2 W4b
  END IF;
  -- Spec 2 W4a: the verification sessions go, a human review's photos with
  -- Spec 2 W4a them (queued, as every Dating object), and the identity
  -- Spec 2 W4a result, which covered the photos deleted above. -- Spec 2 W4 final
  -- Spec 2 W4 final (I-1a ruling): an age pass goes too (it belongs to the
  -- Spec 2 W4 final face that earned it; a new setup checks the age again);
  -- Spec 2 W4 final a fail (and Spec 1's hold) stays while the account exists.
  PERFORM public.queue_media_deletion('dating-verification-review', o.name) -- Spec 2 W4a
     FROM storage.objects AS o -- Spec 2 W4a
    WHERE o.bucket_id = 'dating-verification-review' -- Spec 2 W4a
      AND split_part(o.name, '/', 1) IN (SELECT vs.id::text FROM public.dating_verification_sessions AS vs -- Spec 2 W4a
                                          WHERE vs.user_id = p_user); -- Spec 2 W4a
  DELETE FROM public.dating_verification_sessions AS vs WHERE vs.user_id = p_user; -- Spec 2 W4a
  DELETE FROM public.dating_trusted_devices AS td WHERE td.user_id = p_user; -- Spec 2 W4b (§3.3.4): leaving unbinds every phone
  UPDATE public.dating_age_verifications AS av -- Spec 2 W4a
     SET identity_method = NULL, identity_result = NULL, identity_vendor = NULL, -- Spec 2 W4a
         identity_decided_at = NULL, decided_by = NULL, updated_at = now() -- Spec 2 W4a
   WHERE av.user_id = p_user AND av.identity_result IS NOT NULL; -- Spec 2 W4a
  UPDATE public.dating_age_verifications AS av -- Spec 2 W4 final (I-1a)
     SET age_method = NULL, age_result = NULL, challenge_age = NULL, age_vendor = NULL, age_decided_at = NULL, -- Spec 2 W4 final (I-1a)
         updated_at = now() -- Spec 2 W4 final (I-1a)
   WHERE av.user_id = p_user AND av.age_result = 'pass' AND av.revoked_at IS NULL; -- Spec 2 W4 final (I-1a): a fail stays
  -- Conversations close for both and stay sealed for the evidence window.
  UPDATE public.dating_matches AS m
     SET state = 'closed', closed_reason = 'exit', closed_at = coalesce(m.closed_at, now()),
         evidence_until = now() + interval '30 days'
   WHERE p_user IN (m.user_low_id, m.user_high_id) AND m.state = 'active';
  -- Introductions go (their interest actions cascade; a match keeps its row).
  DELETE FROM public.dating_introductions AS i WHERE p_user IN (i.user_low_id, i.user_high_id);
  DELETE FROM public.dating_feature_snapshots AS f WHERE f.user_id = p_user;
  -- "When you left" (§3.8; fix round 1, I-1): every consent whose latest
  -- event is a grant is withdrawn now, on the server's clock, so coming back
  -- needs D4 again. Kept with the consents (Q17 exception 3). A second exit
  -- finds nothing standing and writes nothing (M-2).
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT p_user, 'exit:' || l.purpose || ':' || replace(gen_random_uuid()::text, '-', ''), l.purpose, 'withdrawn',
         l.policy_version, clock_timestamp()
    FROM (SELECT DISTINCT ON (c.purpose) c.purpose, c.action, c.policy_version
            FROM public.dating_consent_events AS c
           WHERE c.user_id = p_user
           ORDER BY c.purpose, c.occurred_at DESC, c.created_at DESC, (c.action = 'withdrawn') DESC) AS l
   WHERE l.action = 'granted';
  -- A suspension stays (only the data goes); a second exit keeps the first
  -- "when you left" (M-2).
  UPDATE public.dating_enrollments AS e
     SET state = CASE WHEN e.state = 'suspended' THEN 'suspended' ELSE 'exited' END,
         exited_at = coalesce(e.exited_at, now()), paused_at = NULL, pause_reason = NULL, updated_at = now()
   WHERE e.user_id = p_user;
  IF v_found AND v_exited_at IS NULL THEN
    PERFORM private.bump_metric_internal('dating.exit');
  END IF;
END;
$function$;

-- Spec 2 W4 final (M-10): Dating photos are served only to the owner's
-- trusted phone. Re-created here from its live body, so a database that
-- recorded W3's 20261107170000 before W4 gets the device check too.
CREATE OR REPLACE FUNCTION public.dating_storage_owns(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.dating_profile_photos AS f
                  WHERE f.storage_key = p_name AND f.user_id = auth.uid()
                    AND f.csam_state IS DISTINCT FROM 'hit' -- Spec 2 W3c (fix round 1, M-8): a match is never served, the owner included
                    AND NOT EXISTS (SELECT 1 FROM private.media_scan_queue AS q -- Spec 2 W3c (fix round 1, M-8): nor a quarantined object
                                     WHERE q.bucket = 'dating-profile-photos' AND q.object_name = p_name AND q.status = 'match')) -- Spec 2 W4b
    AND public.dating_require_trusted_device(); -- Spec 2 W4b (T5 fix round 1, I-5): only to the owner's trusted phone; hosted Storage forwarding x-attune-device is an owner gate
$function$;

CREATE OR REPLACE FUNCTION public.list_dating_never_introduce()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  RETURN jsonb_build_object('ok', true, 'items', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', n.id, 'label', n.label, 'last_two', n.last_two)
                     ORDER BY coalesce(n.shown_at, n.created_at), n.id) -- Spec 2 W4b (fix round 2, I-6): a re-added row sits where it was added
      FROM public.dating_never_introduce AS n WHERE n.owner_user_id = v_user -- Spec 2 W4b
       AND (n.kept_at IS NULL OR n.shown_at IS NOT NULL)), '[]'::jsonb), -- Spec 2 W4b (fix rounds 1-2, C-1): never a kept row
    'kept_count', (SELECT count(*) FROM public.dating_never_introduce AS k -- Spec 2 W4b: only how many are kept
                    WHERE k.owner_user_id = v_user AND k.kept_at IS NOT NULL)); -- Spec 2 W4b
END;
$function$;

CREATE OR REPLACE FUNCTION public.remove_dating_never_introduce(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  PERFORM private.dating_lock_setup(v_user);
  -- Removing raises exposure: the §4.4 device check applies.
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_never_introduce AS k -- Spec 2 W4b (fix rounds 1-2, C-1, I-6): a kept row is never deleted alone
              WHERE k.id = p_id AND k.owner_user_id = v_user AND k.kept_at IS NOT NULL) THEN -- Spec 2 W4b
    UPDATE public.dating_never_introduce AS k SET shown_at = NULL, label = NULL -- Spec 2 W4b: a re-added one hides again, still protecting
     WHERE k.id = p_id AND k.owner_user_id = v_user; -- Spec 2 W4b
    RETURN jsonb_build_object('ok', true); -- Spec 2 W4b: the answer any removal gets
  END IF; -- Spec 2 W4b
  -- The same answer whether the row was the caller's, someone else's or none.
  DELETE FROM public.dating_never_introduce AS n WHERE n.id = p_id AND n.owner_user_id = v_user;
  RETURN jsonb_build_object('ok', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.add_dating_never_introduce(p_idempotency_key text, p_phone_e164 text, p_label text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user constant uuid := auth.uid();
  v_phone text;
  v_label text;
  v_hmac text;
  v_op text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- Exposure-reducing (W1 B8 ruling): no eligibility or device gate. The
  -- setup lock (shared order) serialises the cap and the write.
  PERFORM private.dating_lock_setup(v_user);
  -- In Dating: a profile in any state (fix round 1, M-1; §4.8 keeps the
  -- list while the owner is in Dating).
  IF NOT EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = v_user) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
  END IF;

  -- The number in E.164, as account phones are (W1 B1 M2; fix round 1,
  -- I-2); NULL, malformed or unjudgeable is invalid ("check the number").
  v_phone := private.dating_typed_phone_e164(p_phone_e164);
  IF v_phone IS NULL THEN
    RETURN private.dating_invalid('phone');
  END IF;

  -- The label: private to the owner, at most 20 after trimming; never a
  -- number (only HMACs are kept: 5+ digits of any script, folded by the
  -- shared normaliser), a control character or an invisible mark.
  v_label := nullif(private.dating_trim(p_label), '');
  IF v_label IS NOT NULL
     AND (char_length(v_label) > 20
          OR v_label ~ '[[:cntrl:]]'
          OR private.dating_has_invisible(v_label)
          OR char_length(pg_catalog.regexp_replace(private.normalize_for_filter(v_label), '[^0-9]', '', 'g')) >= 5) THEN
    RETURN private.dating_invalid('label');
  END IF;

  -- The exclusion key must be ready (W1 B5 I-1): else the generic reason,
  -- counted, nothing claimed or written.
  v_hmac := public.dating_phone_hmac(public.dating_phone_canonical(v_phone));
  IF v_hmac IS NULL OR private.dating_exclusion_key_ready() IS NOT TRUE THEN
    PERFORM private.bump_metric_internal('dating.never_introduce.key_not_ready');
    RETURN jsonb_build_object('ok', false, 'reason', 'feature_unavailable');
  END IF;

  -- The key is bound to this number (fix round 1, M-3, M-4): each add
  -- claims it twice, unbound and under a hash of the HMAC (never the
  -- number). A replay is "added" before the rate limit; the key reused for
  -- another number is refused. Both are exact primary-key lookups, so the
  -- work never depends on the number.
  v_op := 'add_dating_never_introduce:' || left(md5(v_hmac), 12);
  IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS i
              WHERE i.user_id = v_user AND i.operation = v_op AND i.idempotency_key = p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'message', 'added');
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS i
              WHERE i.user_id = v_user AND i.operation = 'add_dating_never_introduce'
                AND i.idempotency_key = p_idempotency_key) THEN
    RETURN private.dating_invalid('idempotency_key');
  END IF;

  BEGIN
    PERFORM public.check_dating_rate_limit('never_introduce_add', 60, interval '1 day');
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM IS DISTINCT FROM 'rate_limited' THEN
      RAISE;
    END IF;
    RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
  END;

  IF (SELECT count(*) + count(*) FILTER (WHERE n.kept_at IS NOT NULL AND n.shown_at IS NOT NULL) -- Spec 2 W4b (fix round 3, I-9): as the owner sees it
         FROM public.dating_never_introduce AS n WHERE n.owner_user_id = v_user) >= 50 -- Spec 2 W4b
     AND NOT EXISTS (SELECT 1 FROM public.dating_never_introduce AS n
                      WHERE n.owner_user_id = v_user AND n.phone_hmac = v_hmac -- Spec 2 W4b
                        AND (n.kept_at IS NULL OR n.shown_at IS NOT NULL)) THEN -- Spec 2 W4b (fix round 2, I-6): a hidden kept row counts as fresh
    RETURN jsonb_build_object('ok', false, 'reason', 'limit_reached');
  END IF;
  -- Neither claim exists (checked above, under the setup lock).
  PERFORM public.claim_dating_idempotency('add_dating_never_introduce', p_idempotency_key);
  PERFORM public.claim_dating_idempotency(v_op, p_idempotency_key);

  INSERT INTO public.dating_never_introduce AS n (owner_user_id, phone_hmac, label, last_two)
  VALUES (v_user, v_hmac, v_label, right(v_phone, 2))
  ON CONFLICT (owner_user_id, phone_hmac) DO UPDATE -- Spec 2 W4b
    SET label = CASE WHEN n.kept_at IS NOT NULL AND n.shown_at IS NULL THEN EXCLUDED.label -- Spec 2 W4b (fix round 2, I-6): as a fresh add
                     ELSE coalesce(EXCLUDED.label, n.label) END, -- Spec 2 W4b
        shown_at = CASE WHEN n.kept_at IS NOT NULL AND n.shown_at IS NULL THEN now() ELSE n.shown_at END, -- Spec 2 W4b (fix round 3, I-7): a fresh row's clock
        id = CASE WHEN n.kept_at IS NOT NULL AND n.shown_at IS NULL THEN gen_random_uuid() ELSE n.id END; -- Spec 2 W4b (fix round 3, I-8): a new entry's id
  -- No introduction changes here (fix round 1, I-1): ending one at once would
  -- confirm whose number it is. Filter 13 (dating_never_introduce_excludes)
  -- keeps the pair from matching; the listed person stops seeing the pair
  -- at the next run, as a pass (W5a/W5b gates).
  RETURN jsonb_build_object('ok', true, 'message', 'added');
END;
$function$;

-- 9. The server-only objects are closed in the migration itself (the twin
--    re-asserts them).
REVOKE ALL ON FUNCTION private.dating_device_state(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_touch_device(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_bind_setup_device(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_device_gate(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_reverify_variant(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_check_standing(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.trust_dating_device(uuid, text, uuid) FROM PUBLIC, anon, authenticated; -- Spec 2 W4 final (M-3)

COMMIT;
