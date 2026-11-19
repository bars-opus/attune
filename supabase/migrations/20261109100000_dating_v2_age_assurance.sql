-- Spec 2 W4a, migration 1 (§4.9 W4a; §3.3; §4.3 dating_age_verifications,
-- dating_verification_sessions; §4.4 record_dating_age_assurance,
-- record_dating_identity_check, revoke_dating_age_verification; §4.5
-- dating-verification-review; §4.10 rows tagged W4; §6.3 account-level age
-- review; I-7; R8; plan R-1..R-14): the verification record keeps methods
-- and pass/fail only (no DOB, no estimate, no image, no template); the
-- verification sessions; the service writers the dating-verification edge
-- function calls, the far-below-18 path into Spec 1's place_account_hold
-- with three arguments (its only Dating caller); age_review and
-- age_verification_invalid close every match; the human-review bucket and
-- its INSERT policy; the client's own status read; the sweep; the flag
-- dating_age_assurance (off). Re-created from their live bodies (changed
-- lines marked -- Spec 2 W4a): dating_age_gate_holds,
-- enforce_dating_age_verification_change, invalidate_dating_for_user,
-- enforce_dating_restriction_change, dating_pair_passes_hard_filters,
-- resume_dating_mode, get_dating_home, private.dating_exit_internal,
-- get_dating_operational_health. Dropped: verify_dating_age,
-- resolve_dating_verification_review, the one-argument
-- revoke_dating_age_verification.
-- Spec 2 W4 final (I-1b ruling; M-1, M-2, M-6, M-8, M-11): an age pass whose
-- every approved photo is newer than it is checked again on the next
-- identity pass (private.dating_age_recheck_due, R-13 applies); the person
-- review waits 72 hours from its submission; a re-check never moves the
-- owner's verification state; far below 18 wins over a photo that doesn't
-- match and names the vendor that decided (record_dating_age_far_below
-- takes p_vendor); the six re-created v1 definers run with an empty search
-- path. Changed lines are marked -- Spec 2 W4 final.
-- Grants in 20261109100010_dating_v2_age_assurance_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- 1. The flag (off; supabase/sql/dev_enable_spec2_dating_flags.sql turns it
--    on in development) and its production gate (Spec 1's gate trigger).
INSERT INTO private.flag_production_gates (flag_key, gate) VALUES
  ('dating_age_assurance', 'Spec 2 W4 gate: signed estimation-vendor (UK highly effective, skin-tone and West African error data) and Smile ID (or equivalent) contracts, the DPIA biometric section, the AWS region recorded, the UK OSA HEAA method documented')
ON CONFLICT (flag_key) DO NOTHING;
INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_age_assurance', false)
ON CONFLICT (key) DO NOTHING;

-- 2. A pause has a reason (carry 1): a revoked or failed age check pauses
--    with 'verification' (resume mirrors it; the app maps it).
ALTER TABLE public.dating_enrollments DROP CONSTRAINT IF EXISTS dating_enrollments_pause_reason_check;
ALTER TABLE public.dating_enrollments ADD CONSTRAINT dating_enrollments_pause_reason_check
  CHECK (pause_reason IS NULL OR pause_reason IN ('user', 'relationship', 'path_change', 'same_gender_switch',
                                                  'away', 'account_parked', 'gates', 'verification'));

-- 3. dating_age_verifications reshaped (§4.3, §1.4): one row per person,
--    the two checks' methods and results, who decided (a reviewer, for
--    identity only: a person never passes age), when, and a revocation.
--    The v1 rows held a typed date of birth and never ran in production:
--    they are deleted once, while the birth_date column still exists (a
--    replay deletes nothing). R-3: each check keeps its own decision time
--    (the ID and human routes finish at different times).
DO $reshape$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns AS c
              WHERE c.table_schema = 'public' AND c.table_name = 'dating_age_verifications'
                AND c.column_name = 'birth_date') THEN
    DELETE FROM public.dating_age_verifications;
  END IF;
END $reshape$;
ALTER TABLE public.dating_age_verifications
  DROP CONSTRAINT IF EXISTS dating_age_verifications_birth_date_check,
  DROP CONSTRAINT IF EXISTS dating_age_verifications_verification_method_check,
  DROP COLUMN IF EXISTS birth_date,
  DROP COLUMN IF EXISTS verification_method,
  DROP COLUMN IF EXISTS expires_at,
  DROP COLUMN IF EXISTS verified_by,
  DROP COLUMN IF EXISTS verified_at,
  ADD COLUMN IF NOT EXISTS age_method text,
  ADD COLUMN IF NOT EXISTS age_result text,
  ADD COLUMN IF NOT EXISTS challenge_age smallint,
  ADD COLUMN IF NOT EXISTS age_vendor text,
  ADD COLUMN IF NOT EXISTS age_decided_at timestamptz,
  ADD COLUMN IF NOT EXISTS identity_method text,
  ADD COLUMN IF NOT EXISTS identity_result text,
  ADD COLUMN IF NOT EXISTS identity_vendor text,
  ADD COLUMN IF NOT EXISTS identity_decided_at timestamptz,
  ADD COLUMN IF NOT EXISTS decided_by uuid,
  ADD COLUMN IF NOT EXISTS revoke_reason text;
ALTER TABLE public.dating_age_verifications DROP CONSTRAINT IF EXISTS dating_age_verifications_v2_check;
ALTER TABLE public.dating_age_verifications ADD CONSTRAINT dating_age_verifications_v2_check CHECK (
  (age_method IS NULL OR age_method IN ('fae', 'id'))
  AND (age_result IS NULL OR age_result IN ('pass', 'fail'))
  AND ((age_method IS NULL) = (age_result IS NULL))
  AND (identity_method IS NULL OR identity_method IN ('liveness_compare', 'human_gesture'))
  AND (identity_result IS NULL OR identity_result IN ('pass', 'fail'))
  AND ((identity_method IS NULL) = (identity_result IS NULL))
  AND (age_vendor IS NULL OR age_vendor ~ '^[a-z0-9_]{1,40}$')
  AND (identity_vendor IS NULL OR identity_vendor ~ '^[a-z0-9_]{1,40}$')
  AND (revoke_reason IS NULL OR revoke_reason ~ '^[a-z0-9_]{1,40}$')
  AND (challenge_age IS NULL OR challenge_age BETWEEN 18 AND 40));
-- §7.1: an estimate below the challenge age can never be a fae pass (a
-- missing challenge age is not one either).
ALTER TABLE public.dating_age_verifications DROP CONSTRAINT IF EXISTS dating_age_verifications_fae_challenge_check;
ALTER TABLE public.dating_age_verifications ADD CONSTRAINT dating_age_verifications_fae_challenge_check
  CHECK (age_method IS DISTINCT FROM 'fae' OR age_result IS DISTINCT FROM 'pass' OR coalesce(challenge_age, 0) >= 25);

-- 4. Verification sessions (§4.3; R-4: the last outcome, the slot it named,
--    the two gestures, the ID document and the device the session runs on
--    are kept with it, so a resumed or a waiting session reads the same).
CREATE TABLE IF NOT EXISTS public.dating_verification_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('activation', 'reverify')),
  step text NOT NULL CHECK (step IN ('liveness', 'id', 'human')),
  vendor text CHECK (vendor IS NULL OR vendor ~ '^[a-z0-9_]{1,40}$'),
  vendor_session_ref text CHECK (vendor_session_ref IS NULL OR char_length(vendor_session_ref) BETWEEN 1 AND 200),
  attempts smallint NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 20),
  state text NOT NULL DEFAULT 'started'
    CHECK (state IN ('started', 'awaiting_review', 'passed', 'failed', 'expired')),
  outcome text CHECK (outcome IS NULL OR outcome IN (
    'retry', 'another_way', 'verified', 'needs_id', 'age_uncertain', 'photo_mismatch', 'far_below',
    'id_pending', 'dob_mismatch', 'age_not_confirmed', 'human_pending', 'identity_failed', 'ask_for_id')),
  outcome_position smallint CHECK (outcome_position IS NULL OR outcome_position BETWEEN 1 AND 6),
  gestures text[] CHECK (gestures IS NULL OR cardinality(gestures) = 2),
  id_document text CHECK (id_document IS NULL OR id_document ~ '^[a-z0-9_]{1,40}$'),
  device_hash text CHECK (device_hash IS NULL OR device_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);
-- Fix round 1 (I-2, M-8): when the session started waiting for review
-- (the submission, or the ID check's answer), which the sweep's ID bound
-- and health's 24-hour clock read.
ALTER TABLE public.dating_verification_sessions ADD COLUMN IF NOT EXISTS awaiting_since timestamptz;
-- One open session per person (begin expires a stale one first).
CREATE UNIQUE INDEX IF NOT EXISTS dating_verification_sessions_open_idx
  ON public.dating_verification_sessions (user_id) WHERE state IN ('started', 'awaiting_review');
CREATE INDEX IF NOT EXISTS dating_verification_sessions_user_created_idx
  ON public.dating_verification_sessions (user_id, created_at DESC);
ALTER TABLE public.dating_verification_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.dating_verification_sessions FROM PUBLIC, anon, authenticated;

-- 5. The human route's private bucket (§3.3.3, §4.5): INSERT only through
--    an open human session's two paths, <session id>/<1|2>.jpg; no client
--    SELECT; JPEG up to 2 MB.
INSERT INTO storage.buckets (id, name, public)
VALUES ('dating-verification-review', 'dating-verification-review', false)
ON CONFLICT (id) DO NOTHING;
DO $limits$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns AS c
              WHERE c.table_schema = 'storage' AND c.table_name = 'buckets' AND c.column_name = 'file_size_limit')
     AND EXISTS (SELECT 1 FROM information_schema.columns AS c
                  WHERE c.table_schema = 'storage' AND c.table_name = 'buckets' AND c.column_name = 'allowed_mime_types') THEN
    EXECUTE $q$UPDATE storage.buckets SET public = false, file_size_limit = 2097152, allowed_mime_types = ARRAY['image/jpeg'] WHERE id = 'dating-verification-review'$q$;
  END IF;
END $limits$;

-- 6. The mode, availability and challenge age the edge function reads
--    (§3.3.5): fake, sandbox or live from app_setting('age_assurance_mode');
--    anything else is unconfigured; fake is never available outside
--    development (the edge function refuses it too). Unavailable whenever
--    the flag is off.
CREATE OR REPLACE FUNCTION private.dating_verification_mode()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE WHEN s.m IN ('fake', 'sandbox', 'live') THEN s.m ELSE 'unconfigured' END
    FROM (SELECT lower(btrim(coalesce(public.app_setting('age_assurance_mode'), ''))) AS m) AS s;
$$;

CREATE OR REPLACE FUNCTION private.dating_verification_available()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(public.dating_flag_enabled('dating_age_assurance'), false)
     AND private.dating_verification_mode() <> 'unconfigured'
     AND NOT (private.dating_verification_mode() IN ('fake', 'sandbox') -- Spec 2 W4a (T2 fix round 1, M-6 ruling): sandbox too
              AND private.attune_environment() IS DISTINCT FROM 'development');
$$;

CREATE OR REPLACE FUNCTION public.get_dating_verification_config()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'available', private.dating_verification_available(),
    'flag', coalesce(public.dating_flag_enabled('dating_age_assurance'), false),
    'mode', private.dating_verification_mode(),
    'environment', private.attune_environment(),
    'challenge_age', 25);
$$;

-- 7. The person's verification state: age and identity, each passed,
--    failed or not decided (revoked counts as not decided).
CREATE OR REPLACE FUNCTION private.dating_verification_state(p_user uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'age', CASE WHEN v.revoked_at IS NULL THEN v.age_result END,
    'identity', CASE WHEN v.revoked_at IS NULL THEN v.identity_result END)
    FROM (SELECT p_user AS id) AS me
    LEFT JOIN public.dating_age_verifications AS v ON v.user_id = me.id;
$$;

-- 7a. Spec 2 W4 final (I-1b ruling): a standing age pass whose every
--     approved photo was added after it was decided (a photo swap: the face
--     in the photos may not be the one whose age was checked). The next
--     identity pass runs the age estimate again (R-13: uncertain or below
--     25 goes to the ID check, far below 18 to Spec 1's hold); a person who
--     keeps one older photo is not asked again. Never NULL.
CREATE OR REPLACE FUNCTION private.dating_age_recheck_due(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce((
    SELECT v.age_result = 'pass' AND v.revoked_at IS NULL AND v.age_decided_at IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.dating_profile_photos AS f
                    WHERE f.user_id = p_user AND f.moderation_state = 'approved' AND f.csam_state = 'clear')
       AND NOT EXISTS (SELECT 1 FROM public.dating_profile_photos AS f
                        WHERE f.user_id = p_user AND f.moderation_state = 'approved' AND f.csam_state = 'clear'
                          AND f.created_at <= v.age_decided_at)
      FROM public.dating_age_verifications AS v WHERE v.user_id = p_user), false);
$$;

-- 8. A session begins (service role: dating-verification's start, start_id
--    and human_start). Fails closed with a named reason, never a raise:
--    unavailable, invalid, not_eligible (setup eligibility, a Dating
--    enrolment), consent_required (biometric_verification), photos_required
--    (2 approved, for the video and the human route), age_not_confirmed (an
--    age check failed), already_verified, awaiting_review, rate_limited (5
--    sessions a day), busy. An open session of the same step resumes (R-5:
--    no new row, no rate cost); another step's open session ends first.
CREATE OR REPLACE FUNCTION public.begin_dating_verification(
  p_user uuid, p_kind text, p_step text, p_vendor text,
  p_device_hash text DEFAULT NULL, p_document text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_try integer;
  v_open public.dating_verification_sessions;
  v_row public.dating_verification_sessions;
  v_state jsonb;
  v_country text;
  v_gestures text[];
  v_has_open boolean;
BEGIN
  IF p_user IS NULL OR p_kind IS DISTINCT FROM 'activation'
     OR (p_step IN ('liveness', 'id', 'human')) IS NOT TRUE
     OR coalesce(p_vendor ~ '^[a-z0-9_]{1,40}$', false) IS NOT TRUE
     OR (p_device_hash IS NOT NULL AND p_device_hash !~ '^[0-9a-f]{64}$')
     OR (p_step = 'id') IS DISTINCT FROM (p_document IS NOT NULL)
     OR (p_document IS NOT NULL AND p_document !~ '^[a-z0-9_]{1,40}$') THEN
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
      IF (p_step = 'id' AND v_state ->> 'age' = 'pass')
         OR (p_step = 'human' AND v_state ->> 'identity' = 'pass'
             AND (SELECT p.verification_state FROM public.dating_profiles AS p WHERE p.user_id = p_user) = 'verified')
         OR (p_step = 'liveness' AND v_state ->> 'age' = 'pass' AND v_state ->> 'identity' = 'pass'
             AND (SELECT p.verification_state FROM public.dating_profiles AS p WHERE p.user_id = p_user) = 'verified') THEN
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
      IF v_has_open AND v_open.state = 'awaiting_review' THEN
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
      IF v_has_open AND v_open.step = p_step AND v_open.id_document IS NOT DISTINCT FROM p_document THEN
        UPDATE public.dating_verification_sessions AS s
           SET vendor = p_vendor, device_hash = coalesce(p_device_hash, s.device_hash), updated_at = now()
         WHERE s.id = v_open.id RETURNING * INTO v_row;
        RETURN jsonb_build_object('ok', true, 'session_id', v_row.id, 'step', v_row.step, 'attempts', v_row.attempts,
                                  'resumed', true, 'gestures', to_jsonb(v_row.gestures), 'expires_at', v_row.expires_at);
      END IF;
      -- A refused start never ends the open session (the limit is read first).
      IF (SELECT count(*) FROM public.dating_verification_sessions AS s
           WHERE s.user_id = p_user AND s.created_at > now() - interval '1 day') >= 5 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
      END IF;
      IF v_has_open THEN
        UPDATE public.dating_verification_sessions AS s SET state = 'expired', updated_at = now() WHERE s.id = v_open.id;
      END IF;
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
$$;

-- 9. The edge function's read of one of the person's sessions (its vendor
--    reference included; no client ever reads it) and of the approved
--    photos it compares against.
CREATE OR REPLACE FUNCTION public.get_dating_verification_session(p_user uuid, p_session uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE WHEN s.id IS NULL THEN jsonb_build_object('ok', false, 'reason', 'session_unavailable')
    ELSE jsonb_build_object('ok', true, 'session_id', s.id, 'kind', s.kind, 'step', s.step, 'state', s.state,
      'vendor', s.vendor, 'vendor_session_ref', s.vendor_session_ref, 'attempts', s.attempts,
      'id_document', s.id_document, 'device_hash', s.device_hash, 'outcome', s.outcome,
      'country', (SELECT p.country_code::text FROM public.dating_profiles AS p WHERE p.user_id = p_user),
      'expired', s.expires_at <= now(), 'age', private.dating_verification_state(p_user) ->> 'age',
      'identity', private.dating_verification_state(p_user) ->> 'identity', -- Spec 2 W4 final
      'age_recheck', private.dating_age_recheck_due(p_user)) END -- Spec 2 W4 final (I-1b): the edge estimates again
    FROM (SELECT 1) AS one
    LEFT JOIN public.dating_verification_sessions AS s ON s.id = p_session AND s.user_id = p_user;
$$;

CREATE OR REPLACE FUNCTION public.get_dating_verification_photos(p_user uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('position', f.position, 'storage_key', f.storage_key) ORDER BY f.position), '[]'::jsonb)
    FROM public.dating_profile_photos AS f
   WHERE f.user_id = p_user AND f.moderation_state = 'approved' AND f.csam_state = 'clear';
$$;

CREATE OR REPLACE FUNCTION public.set_dating_verification_ref(p_session uuid, p_ref text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_try integer;
  v_user uuid;
  v_found boolean; -- Spec 2 W4a (T2 fix round 2, N-2)
BEGIN
  IF p_session IS NULL OR coalesce(char_length(p_ref) BETWEEN 1 AND 200, false) IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  -- Fix round 1 (M-4): the person's setup lock first, then the row, with
  -- the bounded retry every writer has (three tries, then busy).
  SELECT s.user_id INTO v_user FROM public.dating_verification_sessions AS s WHERE s.id = p_session;
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      UPDATE public.dating_verification_sessions AS s SET vendor_session_ref = p_ref, updated_at = now()
       WHERE s.id = p_session AND s.state = 'started' AND s.expires_at > now();
      v_found := FOUND; -- Spec 2 W4a (T2 fix round 2, N-2)
      -- Spec 2 W4a (T2 fix round 2, N-2): the vendor session exists now: it
      -- counts toward the person's 20 an hour (begin reads the count).
      IF v_found THEN -- Spec 2 W4a
        INSERT INTO public.dating_rate_limits AS r (user_id, operation, window_started_at, request_count) -- Spec 2 W4a
        VALUES (v_user, 'dating_verify_vendor_session', now(), 1) -- Spec 2 W4a
        ON CONFLICT (user_id, operation) DO UPDATE SET -- Spec 2 W4a
          window_started_at = CASE WHEN r.window_started_at + interval '1 hour' <= now() THEN now() ELSE r.window_started_at END, -- Spec 2 W4a
          request_count = CASE WHEN r.window_started_at + interval '1 hour' <= now() THEN 1 ELSE r.request_count + 1 END; -- Spec 2 W4a
      END IF; -- Spec 2 W4a
      RETURN jsonb_build_object('ok', v_found, 'reason', CASE WHEN NOT v_found THEN 'session_unavailable' END); -- Spec 2 W4a
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 10. A liveness attempt the vendor answered (§3.3.2): a failure counts
--     (the first offers a retry, from the second "check another way"); a
--     network failure never reaches here (the edge function answers
--     vendor_unavailable without counting, §3.15 D11).
CREATE OR REPLACE FUNCTION public.record_dating_liveness_attempt(p_session uuid, p_passed boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_row public.dating_verification_sessions;
  v_try integer;
  v_user uuid;
BEGIN
  IF p_session IS NULL OR p_passed IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  -- Fix round 1 (M-4): the setup lock first, then the row; three tries.
  SELECT s.user_id INTO v_user FROM public.dating_verification_sessions AS s WHERE s.id = p_session;
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      IF p_passed THEN
        SELECT * INTO v_row FROM public.dating_verification_sessions AS s
         WHERE s.id = p_session AND s.step = 'liveness' AND s.state = 'started' AND s.expires_at > now();
        RETURN CASE WHEN FOUND THEN jsonb_build_object('ok', true, 'attempts', v_row.attempts)
                    ELSE jsonb_build_object('ok', false, 'reason', 'session_unavailable') END;
      END IF;
      UPDATE public.dating_verification_sessions AS s
         SET attempts = least(s.attempts + 1, 20),
             outcome = CASE WHEN s.attempts + 1 >= 2 THEN 'another_way' ELSE 'retry' END, updated_at = now(),
             vendor_session_ref = NULL -- Spec 2 W4a (T2 fix round 1, M-3): counted once per vendor session
       WHERE s.id = p_session AND s.step = 'liveness' AND s.state = 'started' AND s.expires_at > now()
         AND s.vendor_session_ref IS NOT NULL -- Spec 2 W4a (T2 fix round 1, M-3)
      RETURNING * INTO v_row;
      IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
      END IF;
      PERFORM private.bump_metric_internal('dating.verify.liveness_failed');
      RETURN jsonb_build_object('ok', true, 'attempts', v_row.attempts, 'outcome', v_row.outcome);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 11. A session ends with its outcome (the slot a mismatch named).
CREATE OR REPLACE FUNCTION public.finish_dating_verification_session(
  p_session uuid, p_state text, p_outcome text, p_position smallint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_row public.dating_verification_sessions;
  v_try integer;
  v_user uuid;
  v_h numeric;
BEGIN
  IF p_session IS NULL OR (p_state IN ('awaiting_review', 'passed', 'failed')) IS NOT TRUE
     OR (p_outcome IN ('verified', 'needs_id', 'age_uncertain', 'photo_mismatch', 'far_below', 'id_pending', 'dob_mismatch',
                       'age_not_confirmed', 'human_pending', 'identity_failed', 'ask_for_id')) IS NOT TRUE
     OR (p_outcome = 'photo_mismatch') IS DISTINCT FROM (p_position IS NOT NULL)
     OR (p_position IS NOT NULL AND p_position NOT BETWEEN 1 AND 6) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  -- Fix round 1 (M-4): the setup lock first, then the row; three tries.
  SELECT s.user_id INTO v_user FROM public.dating_verification_sessions AS s WHERE s.id = p_session;
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(v_user);
      SELECT * INTO v_row FROM public.dating_verification_sessions AS s
       WHERE s.id = p_session AND s.state IN ('started', 'awaiting_review') FOR UPDATE;
      IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
      END IF;
      -- Fix round 1 (I-2, M-8): the wait starts when the session starts
      -- waiting for review; "Check again" (R-12, still waiting) keeps it.
      UPDATE public.dating_verification_sessions AS s
         SET state = p_state, outcome = p_outcome, outcome_position = p_position,
             awaiting_since = CASE WHEN p_state = 'awaiting_review'
                                   THEN coalesce(CASE WHEN v_row.state = 'awaiting_review' THEN v_row.awaiting_since END, now()) END,
             updated_at = now()
       WHERE s.id = p_session;
      IF v_row.state = 'awaiting_review' AND p_state IN ('passed', 'failed') THEN
        v_h := extract(epoch FROM now() - coalesce(v_row.awaiting_since, v_row.updated_at)) / 3600;
        PERFORM private.bump_metric_internal('dating.verify.hours_to_decision.' || CASE -- §6.9 (fix round 1, M-7)
        WHEN v_h < 6 THEN '0_6' WHEN v_h < 24 THEN '6_24' WHEN v_h < 48 THEN '24_48'
        WHEN v_h < 72 THEN '48_72' ELSE '72_plus' END);
      END IF;
      RETURN jsonb_build_object('ok', true, 'reason', NULL);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 12. The identity result (§3.3.1, §4.4; replaces
--     resolve_dating_verification_review): liveness_compare (the edge
--     function, no decider) or human_gesture (a reviewer's id). It sets the
--     profile's verification_state, which activation and the next step read.
CREATE OR REPLACE FUNCTION public.record_dating_identity_check(
  p_user uuid, p_method text, p_result text, p_vendor text, p_decided_by uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_try integer;
BEGIN
  IF p_user IS NULL OR (p_method IN ('liveness_compare', 'human_gesture')) IS NOT TRUE
     OR (p_result IN ('pass', 'fail')) IS NOT TRUE
     OR coalesce(p_vendor ~ '^[a-z0-9_]{1,40}$', false) IS NOT TRUE
     OR (p_method = 'human_gesture') IS DISTINCT FROM (p_decided_by IS NOT NULL) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(p_user);
      IF NOT EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = p_user) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
      END IF;
      INSERT INTO public.dating_age_verifications AS v (user_id, identity_method, identity_result, identity_vendor,
                                                       identity_decided_at, decided_by)
      VALUES (p_user, p_method, p_result, p_vendor, now(), p_decided_by)
      ON CONFLICT (user_id) DO UPDATE
        SET identity_method = EXCLUDED.identity_method, identity_result = EXCLUDED.identity_result,
            identity_vendor = EXCLUDED.identity_vendor, identity_decided_at = EXCLUDED.identity_decided_at,
            decided_by = EXCLUDED.decided_by, updated_at = now();
      UPDATE public.dating_profiles AS p
         SET verification_state = CASE WHEN p_result = 'pass' THEN 'verified' ELSE 'unverified' END,
             verification_method = p_method,
             verified_at = CASE WHEN p_result = 'pass' THEN now() END
       WHERE p.user_id = p_user;
      PERFORM private.bump_metric_internal('dating.verify.identity_' || p_result);
      -- Fix round 1 (M-7, §6.9): the route that confirmed identity, and a
      -- video pass on the person's only session with no failed attempt.
      IF p_result = 'pass' AND p_method = 'human_gesture' THEN
        PERFORM private.bump_metric_internal('dating.verify.route.human');
      ELSIF p_result = 'pass' AND coalesce((SELECT count(*) = 1 AND bool_and(s.attempts = 0)
                                              FROM public.dating_verification_sessions AS s WHERE s.user_id = p_user), false) THEN
        PERFORM private.bump_metric_internal('dating.verify.first_try_pass');
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
$$;

-- 13. The age result (§3.3.1, §4.4; replaces verify_dating_age: no DOB
--     argument). fae passes only at the challenge age 25 or above (the
--     estimate itself never reaches the database); id needs no challenge
--     age. A new result clears an earlier revocation (fix round 1, I-1); a
--     fail pauses and closes (the trigger); a standing fail is final (M-3).
CREATE OR REPLACE FUNCTION public.record_dating_age_assurance(
  p_user uuid, p_age_method text, p_age_result text, p_challenge_age smallint, p_vendor text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_try integer;
BEGIN
  IF p_user IS NULL OR (p_age_method IN ('fae', 'id')) IS NOT TRUE
     OR (p_age_result IN ('pass', 'fail')) IS NOT TRUE
     OR coalesce(p_vendor ~ '^[a-z0-9_]{1,40}$', false) IS NOT TRUE
     OR (p_age_method = 'fae') IS DISTINCT FROM (p_challenge_age IS NOT NULL)
     OR (p_challenge_age IS NOT NULL AND p_challenge_age NOT BETWEEN 18 AND 40) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  -- R-13 (owner ruling 2026-11-09): an estimate never ends the check. A
  -- failed or uncertain estimate sends the person to the ID route, so a fae
  -- fail is never recorded (far below 18 is record_dating_age_far_below's).
  IF p_age_method = 'fae' AND p_age_result = 'fail' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  IF p_age_method = 'fae' AND p_age_result = 'pass' AND p_challenge_age < 25 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'challenge_too_low');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(p_user);
      -- Fix round 1 (M-3; R-13): a standing failed age check is final here
      -- too, not only at begin; only a revocation (support, W7) reopens it.
      IF EXISTS (SELECT 1 FROM public.dating_age_verifications AS a
                  WHERE a.user_id = p_user AND a.age_result = 'fail' AND a.revoked_at IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'age_not_confirmed');
      END IF;
      INSERT INTO public.dating_age_verifications AS v (user_id, age_method, age_result, challenge_age, age_vendor, age_decided_at)
      VALUES (p_user, p_age_method, p_age_result, p_challenge_age, p_vendor, now())
      ON CONFLICT (user_id) DO UPDATE
        SET age_method = EXCLUDED.age_method, age_result = EXCLUDED.age_result,
            challenge_age = EXCLUDED.challenge_age, age_vendor = EXCLUDED.age_vendor,
            age_decided_at = EXCLUDED.age_decided_at,
            -- Fix round 1 (I-1): a new decision supersedes a revocation, a
            -- fail included, so a failed ID after a revoked pass is final (R-13).
            revoked_at = NULL, revoke_reason = NULL,
            updated_at = now();
      PERFORM private.bump_metric_internal('dating.verify.age_' || p_age_method || '_' || p_age_result);
      -- Fix round 1 (M-7, §6.9): the route that confirmed the age, and an
      -- ID pass's declared age band.
      IF p_age_result = 'pass' THEN
        PERFORM private.bump_metric_internal('dating.verify.route.' || p_age_method);
        IF p_age_method = 'id' AND public.account_age(p_user) >= 18 THEN
          PERFORM private.bump_metric_internal('dating.verify.id_route.' || CASE
            WHEN public.account_age(p_user) < 25 THEN 'age_18_24' WHEN public.account_age(p_user) < 35 THEN 'age_25_34'
            ELSE 'age_35_plus' END);
        END IF;
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
$$;

-- 14. Far below 18 for a declared adult (§3.3.2, §6.3, R8): the vendor's
--     high-confidence under-18 band, or an ID whose date of birth is under
--     18. The age check fails, every match closes as age_review, and Spec
--     1's account hold is placed with all three arguments (I-7), the
--     session id as its reference. The only Dating caller of
--     place_account_hold (a contract scans for others). Once per session.
--     Spec 2 W4 final (M-8): the row names the vendor that decided (the
--     estimator on the video route, the ID vendor on the ID route).
DROP FUNCTION IF EXISTS public.record_dating_age_far_below(uuid, uuid); -- Spec 2 W4 final (M-8)
CREATE OR REPLACE FUNCTION public.record_dating_age_far_below(p_user uuid, p_session uuid, p_vendor text) -- Spec 2 W4 final (M-8)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_row public.dating_verification_sessions;
  v_try integer;
BEGIN
  IF p_user IS NULL OR p_session IS NULL -- Spec 2 W4 final
     OR coalesce(p_vendor ~ '^[a-z0-9_]{1,40}$', false) IS NOT TRUE THEN -- Spec 2 W4 final (M-8)
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(p_user);
      SELECT * INTO v_row FROM public.dating_verification_sessions AS s
       WHERE s.id = p_session AND s.user_id = p_user FOR UPDATE;
      IF NOT FOUND OR v_row.step NOT IN ('liveness', 'id') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
      END IF;
      IF v_row.outcome = 'far_below' THEN
        RETURN jsonb_build_object('ok', true, 'replayed', true);
      END IF;
      -- Fix round 1 (M-3): only an open session takes the far-below path (a
      -- replay is answered above, as one).
      IF v_row.state NOT IN ('started', 'awaiting_review') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
      END IF;
      PERFORM public.invalidate_dating_for_user(p_user, 'age_review');
      INSERT INTO public.dating_age_verifications AS v (user_id, age_method, age_result, challenge_age, age_vendor, age_decided_at)
      VALUES (p_user, CASE WHEN v_row.step = 'id' THEN 'id' ELSE 'fae' END, 'fail',
              CASE WHEN v_row.step = 'id' THEN NULL ELSE 25 END, p_vendor, now()) -- Spec 2 W4 final (M-8): the vendor that decided
      ON CONFLICT (user_id) DO UPDATE
        SET age_method = EXCLUDED.age_method, age_result = 'fail', challenge_age = EXCLUDED.challenge_age,
            age_vendor = EXCLUDED.age_vendor, age_decided_at = EXCLUDED.age_decided_at,
            revoked_at = NULL, revoke_reason = NULL, -- Fix round 1 (I-1): the new decision supersedes a revocation
            updated_at = now();
      PERFORM public.place_account_hold(p_user, 'age_review', p_session::text);
      UPDATE public.dating_verification_sessions AS s
         SET state = 'failed', outcome = 'far_below', outcome_position = NULL, updated_at = now()
       WHERE s.id = p_session;
      PERFORM private.bump_metric_internal('dating.verify.far_below'); -- Fix round 1 (M-7)
      RETURN jsonb_build_object('ok', true, 'replayed', false);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'busy');
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 14b. Spec 2 W4a (Task 2 fix round 1, I-3 ruling): the video check's whole
--      outcome in one transaction, written once every vendor call has
--      answered: the identity result, then the age (a fae pass at 25, or
--      far below 18: Spec 1's age_review hold through
--      record_dating_age_far_below), then the session's end. A refusal or
--      a busy part rolls every part back, so a busy answer can never leave
--      the identity written without the hold. R-13: needs_id and uncertain
--      record no age. A replay of the same outcome answers it again
--      (replayed). Its own bounded retry (three tries, then busy).
--      Spec 2 W4 final (I-1b ruling): 'skip' is refused when the age pass
--      is due a re-check; a re-check that doesn't pass (needs_id,
--      uncertain) clears the pass, so the ID check opens (R-13: never an
--      ending). (M-6): far below 18 wins over a photo that doesn't match.
CREATE OR REPLACE FUNCTION public.record_dating_video_outcome( -- Spec 2 W4a
  p_user uuid, p_session uuid, p_identity text, p_age text, p_position smallint,
  p_identity_vendor text, p_age_vendor text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_try integer;
  v_row public.dating_verification_sessions;
  v_outcome text;
  v jsonb;
  v_reason text;
  v_position smallint; -- Spec 2 W4 final (M-6)
BEGIN
  IF p_user IS NULL OR p_session IS NULL OR (p_identity IN ('pass', 'fail')) IS NOT TRUE
     OR coalesce(p_identity_vendor ~ '^[a-z0-9_]{1,40}$', false) IS NOT TRUE
     OR (p_identity = 'fail' AND ((p_age IS NOT NULL AND p_age <> 'far_below') -- Spec 2 W4 final (M-6): far below wins
                                  OR p_position IS NULL OR p_position NOT BETWEEN 1 AND 6)) -- Spec 2 W4 final
     OR (p_identity = 'pass' AND ((p_age IN ('skip', 'pass', 'needs_id', 'uncertain', 'far_below')) IS NOT TRUE
                                  OR p_position IS NOT NULL))
     OR (p_age IN ('pass', 'far_below') AND coalesce(p_age_vendor ~ '^[a-z0-9_]{1,40}$', false) IS NOT TRUE) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  v_outcome := CASE WHEN p_age = 'far_below' THEN 'far_below' -- Spec 2 W4 final (M-6)
                    WHEN p_identity = 'fail' THEN 'photo_mismatch' -- Spec 2 W4 final
                    WHEN p_age IN ('skip', 'pass') THEN 'verified'
                    WHEN p_age = 'needs_id' THEN 'needs_id'
                    WHEN p_age = 'uncertain' THEN 'age_uncertain'
                    ELSE 'far_below' END;
  v_position := CASE WHEN v_outcome = 'photo_mismatch' THEN p_position END; -- Spec 2 W4 final (M-6): only a mismatch names a slot
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(p_user); -- the shared lock order: the person first, then rows
      SELECT * INTO v_row FROM public.dating_verification_sessions AS s
       WHERE s.id = p_session AND s.user_id = p_user AND s.kind = 'activation' AND s.step = 'liveness' FOR UPDATE;
      IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
      END IF;
      IF v_row.state IN ('passed', 'failed') AND v_row.outcome IS NOT DISTINCT FROM v_outcome
         AND v_row.outcome_position IS NOT DISTINCT FROM v_position THEN -- Spec 2 W4 final (M-6)
        RETURN jsonb_build_object('ok', true, 'replayed', true, 'outcome', v_outcome, 'position', v_position); -- Spec 2 W4 final (M-6)
      END IF;
      IF v_row.state <> 'started' OR v_row.expires_at <= now()
         OR (p_age = 'skip' AND (private.dating_verification_state(p_user) ->> 'age' IS DISTINCT FROM 'pass' -- Spec 2 W4 final
                                 OR private.dating_age_recheck_due(p_user))) THEN -- Spec 2 W4 final (I-1b): a photo swap is estimated again
        RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
      END IF;
      v := public.record_dating_identity_check(p_user, 'liveness_compare', p_identity, p_identity_vendor, NULL);
      IF (v ->> 'ok')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'dating_video_outcome:%', coalesce(v ->> 'reason', 'busy');
      END IF;
      IF p_age = 'far_below' THEN
        v := public.record_dating_age_far_below(p_user, p_session, p_age_vendor); -- Spec 2 W4 final (M-8)
      ELSIF p_age = 'pass' THEN
        v := public.record_dating_age_assurance(p_user, 'fae', 'pass', 25::smallint, p_age_vendor);
      ELSIF p_age IN ('needs_id', 'uncertain') THEN -- Spec 2 W4 final (I-1b): a pass stands only if the new estimate passes
        UPDATE public.dating_age_verifications AS a -- Spec 2 W4 final (I-1b)
           SET age_method = NULL, age_result = NULL, challenge_age = NULL, age_vendor = NULL, age_decided_at = NULL, -- Spec 2 W4 final (I-1b)
               updated_at = now() -- Spec 2 W4 final (I-1b)
         WHERE a.user_id = p_user AND a.age_result = 'pass' AND a.revoked_at IS NULL; -- Spec 2 W4 final (I-1b)
      END IF;
      IF (v ->> 'ok')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'dating_video_outcome:%', coalesce(v ->> 'reason', 'busy');
      END IF;
      IF p_age IS DISTINCT FROM 'far_below' THEN -- far below ends the session itself
        v := public.finish_dating_verification_session(p_session, CASE WHEN p_identity = 'fail' THEN 'failed' ELSE 'passed' END,
                                                       v_outcome, v_position); -- Spec 2 W4 final (M-6)
        IF (v ->> 'ok')::boolean IS NOT TRUE THEN
          RAISE EXCEPTION 'dating_video_outcome:%', coalesce(v ->> 'reason', 'busy');
        END IF;
      END IF;
      RETURN jsonb_build_object('ok', true, 'replayed', false, 'outcome', v_outcome, 'position', v_position); -- Spec 2 W4 final (M-6)
    EXCEPTION
      WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
        IF v_try = 3 THEN
          RETURN jsonb_build_object('ok', false, 'reason', 'busy');
        END IF;
      WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'dating_video_outcome:%' THEN
          RAISE;
        END IF;
        v_reason := substr(SQLERRM, char_length('dating_video_outcome:') + 1);
        IF v_reason <> 'busy' OR v_try = 3 THEN
          RETURN jsonb_build_object('ok', false, 'reason', v_reason);
        END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- 15. The ID's date of birth against the one the person declared (§3.3.2,
--     Spec 1 account_birthdates): match, mismatch, minor (under 18) or
--     unknown (none declared). Compared and forgotten: nothing is stored.
CREATE OR REPLACE FUNCTION public.check_dating_id_birth_date(p_user uuid, p_dob date)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_user IS NULL OR p_dob IS NULL OR p_dob > current_date THEN 'unknown'
    WHEN p_dob > (current_date - interval '18 years')::date THEN 'minor'
    WHEN b.birth_date IS NULL THEN 'unknown'
    WHEN b.birth_date = p_dob THEN 'match'
    ELSE 'mismatch'
  END
    FROM (SELECT 1) AS one
    LEFT JOIN public.account_birthdates AS b ON b.user_id = p_user;
$$;

-- 16. The human route (§3.3.3): the two photos land under an open human
--     session's paths (the storage policy's predicate), then the person
--     submits; a reviewer decides identity only (pass, fail, ask for ID;
--     never age), and may send an ID check waiting for review back for
--     another ID (fix round 1, I-2 ruling). Until W7b's console, from
--     supabase/sql/dev_dating_review_decide.sql.
--     The photos are queued for deletion at the decision (or by the sweep
--     at 72 hours).
CREATE OR REPLACE FUNCTION public.dating_review_upload_open(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(p_name ~ '^[0-9a-f-]{36}/[12]\.jpg$', false) AND EXISTS (
    SELECT 1 FROM public.dating_verification_sessions AS s
     WHERE s.id::text = split_part(p_name, '/', 1) AND s.user_id = auth.uid()
       AND s.step = 'human' AND s.state = 'started' AND s.expires_at > now());
$$;

CREATE OR REPLACE FUNCTION public.submit_dating_human_review(p_user uuid, p_session uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_row public.dating_verification_sessions;
  v_try integer;
BEGIN
  IF p_user IS NULL OR p_session IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP -- Fix round 1 (M-4): three tries, then busy
    BEGIN
      PERFORM private.dating_lock_setup(p_user); -- the shared lock order: the person first, then rows
      SELECT * INTO v_row FROM public.dating_verification_sessions AS s
       WHERE s.id = p_session AND s.user_id = p_user AND s.step = 'human' FOR UPDATE;
      IF NOT FOUND OR v_row.state <> 'started' OR v_row.expires_at <= now() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
      END IF;
      IF (SELECT count(DISTINCT o.name) FROM storage.objects AS o
           WHERE o.bucket_id = 'dating-verification-review'
             AND o.name IN (p_session::text || '/1.jpg', p_session::text || '/2.jpg')) < 2 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'photos_missing');
      END IF;
      UPDATE public.dating_verification_sessions AS s
         SET state = 'awaiting_review', outcome = 'human_pending',
             awaiting_since = now(), -- Fix round 1 (M-8): the 24-hour clock starts at the submission
             updated_at = now()
       WHERE s.id = p_session;
      UPDATE public.dating_profiles AS p SET verification_state = 'needs_review'
       WHERE p.user_id = p_user AND p.verification_state IS DISTINCT FROM 'verified' -- Spec 2 W4 final
         AND v_row.kind = 'activation'; -- Spec 2 W4 final (M-2, R-14): a re-check never writes the owner's state
      PERFORM private.bump_metric_internal('dating.verify.human_submitted');
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

CREATE OR REPLACE FUNCTION public.decide_dating_human_review(p_session uuid, p_outcome text, p_decided_by uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
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
         AND (s.step = 'human' OR (s.step = 'id' AND p_outcome = 'ask_for_id')) FOR UPDATE;
      IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'session_unavailable');
      END IF;
      IF p_outcome IN ('pass', 'fail') THEN
        v := public.record_dating_identity_check(v_row.user_id, 'human_gesture', p_outcome, 'attune', p_decided_by);
        IF (v ->> 'ok')::boolean IS NOT TRUE THEN
          RETURN v;
        END IF;
      ELSE
        UPDATE public.dating_profiles AS p SET verification_state = 'unverified'
         WHERE p.user_id = v_row.user_id AND p.verification_state = 'needs_review';
      END IF;
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
$$;

-- 17. Revocation takes a reason (§4.10); its trigger pauses and closes.
DROP FUNCTION IF EXISTS public.revoke_dating_age_verification(uuid);
CREATE OR REPLACE FUNCTION public.revoke_dating_age_verification(p_user uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_try integer;
BEGIN
  IF p_user IS NULL OR coalesce(p_reason ~ '^[a-z0-9_]{1,40}$', false) IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  FOR v_try IN 1..3 LOOP -- Fix round 1 (M-4): three tries, then busy
    BEGIN
      PERFORM private.dating_lock_setup(p_user);
      UPDATE public.dating_age_verifications AS v
         SET revoked_at = coalesce(v.revoked_at, now()), revoke_reason = coalesce(v.revoke_reason, p_reason), updated_at = now()
       WHERE v.user_id = p_user;
      IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); -- Fix round 1 (M-6): every refusal names its reason
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
$$;

-- 18. The v1 writers go (§4.10: replaced by the two recorders above).
DROP FUNCTION IF EXISTS public.verify_dating_age(uuid, date, text, uuid, timestamptz);
DROP FUNCTION IF EXISTS public.resolve_dating_verification_review(uuid, text);

-- 19. The device a request comes from (§3.3.4): the SHA-256 (hex) of the
--     x-attune-device header when it is 32 lowercase hex characters, else
--     NULL. W4b's trusted-device check reads it; nothing stores the id.
CREATE OR REPLACE FUNCTION private.dating_request_device_hash()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id text;
BEGIN
  BEGIN
    v_id := nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-attune-device';
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  IF v_id IS NULL OR v_id !~ '^[0-9a-f]{32}$' THEN
    RETURN NULL;
  END IF;
  RETURN encode(extensions.digest(v_id, 'sha256'), 'hex');
END;
$$;

-- 20. The person's own verification state (client RPC, §3.3.2): whether
--     the check can run, the two results ('review' while a person or the ID
--     vendor is checking), the open or the last session (no vendor
--     reference, no estimate, nothing about anyone else), the country's ID
--     documents and whether two photos are approved. On a device the
--     trusted-device check refuses, only the re-verification session on
--     this device (W4b) and nothing else.
CREATE OR REPLACE FUNCTION public.get_my_dating_verification()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_state jsonb;
  v_profile public.dating_profiles;
  v_session public.dating_verification_sessions;
  v_open boolean;
  v_country text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    SELECT * INTO v_session FROM public.dating_verification_sessions AS s
     WHERE s.user_id = v_user AND s.kind = 'reverify'
       AND s.device_hash IS NOT DISTINCT FROM private.dating_request_device_hash()
       AND s.created_at > now() - interval '1 day'
     ORDER BY s.created_at DESC LIMIT 1;
    RETURN jsonb_build_object('ok', true, 'device', 'untrusted',
      'available', private.dating_verification_available(),
      'session', CASE WHEN v_session.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', v_session.id, 'kind', v_session.kind, 'step', v_session.step, 'state', v_session.state,
        'attempts', v_session.attempts, 'outcome', v_session.outcome,
        'open', v_session.state IN ('started', 'awaiting_review') AND (v_session.state = 'awaiting_review' OR v_session.expires_at > now()),
        'gestures', to_jsonb(v_session.gestures)) END);
  END IF;
  v_state := private.dating_verification_state(v_user);
  SELECT * INTO v_profile FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  SELECT * INTO v_session FROM public.dating_verification_sessions AS s
   WHERE s.user_id = v_user AND s.kind = 'activation' AND s.created_at > now() - interval '7 days'
   ORDER BY (s.state IN ('started', 'awaiting_review')) DESC, s.created_at DESC LIMIT 1;
  v_open := v_session.id IS NOT NULL AND (v_session.state = 'awaiting_review'
            OR (v_session.state = 'started' AND v_session.expires_at > now()));
  v_country := v_profile.country_code::text;
  RETURN jsonb_build_object(
    'ok', true,
    'device', 'trusted',
    'available', private.dating_verification_available(),
    'age', CASE WHEN v_state ->> 'age' IS NOT NULL THEN v_state ->> 'age'
                WHEN v_open AND v_session.step = 'id' AND v_session.state = 'awaiting_review' THEN 'review' END,
    'identity', CASE WHEN v_state ->> 'identity' = 'pass' AND v_profile.verification_state = 'verified' THEN 'pass'
                     WHEN v_open AND v_session.step = 'human' AND v_session.state = 'awaiting_review' THEN 'review'
                     WHEN v_state ->> 'identity' = 'fail' THEN 'fail' END,
    'session', CASE WHEN v_session.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_session.id, 'kind', v_session.kind, 'step', v_session.step, 'state', v_session.state,
      'attempts', v_session.attempts, 'outcome', v_session.outcome, 'position', v_session.outcome_position,
      'open', v_open, 'gestures', to_jsonb(v_session.gestures)) END,
    'id_documents', coalesce((SELECT jsonb_agg(jsonb_build_object('code', d ->> 'code', 'name_key', d ->> 'name_key'))
                                FROM jsonb_array_elements(coalesce((public.dating_country_config(v_country)).id_documents, '[]'::jsonb)) AS d), '[]'::jsonb),
    'photos_ready', (SELECT count(*) FROM public.dating_profile_photos AS f
                      WHERE f.user_id = v_user AND f.moderation_state = 'approved') >= 2);
END;
$$;

-- 21. The sweep (cron dating-verification-sweep, every 15 minutes; R-6):
--     an open video or ID session past its time expires; a human review
--     waiting past 72 hours expires (the person is asked again), and so does
--     an ID check waiting 72 hours for review (fix round 1, I-2); every
--     human-review photo older than 72 hours is queued for deletion (the
--     objects of a deleted account included); sessions older than 30 days
--     are deleted (§4.8). Each step in its own block, counted.
CREATE OR REPLACE FUNCTION public.sweep_dating_verification_sessions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_n integer := 0;
  v_k integer;
BEGIN
  BEGIN
    UPDATE public.dating_verification_sessions AS s SET state = 'expired', updated_at = now()
     WHERE s.state = 'started' AND s.expires_at <= now();
    GET DIAGNOSTICS v_k = ROW_COUNT; v_n := v_n + v_k;
    UPDATE public.dating_profiles AS p SET verification_state = 'unverified'
     WHERE p.verification_state = 'needs_review'
       AND EXISTS (SELECT 1 FROM public.dating_verification_sessions AS s
                    WHERE s.user_id = p.user_id AND s.step = 'human' AND s.state = 'awaiting_review'
                      AND s.kind = 'activation' -- Spec 2 W4 final (M-2): a re-check never moves the owner's state
                      AND coalesce(s.awaiting_since, s.created_at) <= now() - interval '72 hours'); -- Spec 2 W4 final (M-1): from the submission
    UPDATE public.dating_verification_sessions AS s SET state = 'expired', updated_at = now()
     WHERE s.step = 'human' AND s.state = 'awaiting_review' -- Spec 2 W4 final
       AND coalesce(s.awaiting_since, s.created_at) <= now() - interval '72 hours'; -- Spec 2 W4 final (M-1): from the submission
    GET DIAGNOSTICS v_k = ROW_COUNT; v_n := v_n + v_k;
  EXCEPTION WHEN OTHERS THEN
    PERFORM private.bump_metric_internal('dating.verify.sweep_failed');
  END;
  -- Fix round 1 (I-2 ruling): an ID check left waiting for review (a date
  -- of birth that differs, a vendor still checking) expires after 72 hours
  -- waiting, each one counted; the person can then begin again.
  BEGIN
    UPDATE public.dating_verification_sessions AS s SET state = 'expired', updated_at = now()
     WHERE s.step = 'id' AND s.state = 'awaiting_review' AND s.outcome IN ('dob_mismatch', 'id_pending')
       AND coalesce(s.awaiting_since, s.updated_at) <= now() - interval '72 hours';
    GET DIAGNOSTICS v_k = ROW_COUNT; v_n := v_n + v_k;
    PERFORM private.bump_metric_internal('dating.verify.id_review_expired') FROM generate_series(1, v_k);
  EXCEPTION WHEN OTHERS THEN
    PERFORM private.bump_metric_internal('dating.verify.sweep_failed');
  END;
  BEGIN
    PERFORM public.queue_media_deletion(o.bucket_id, o.name)
       FROM storage.objects AS o
      WHERE o.bucket_id = 'dating-verification-review' AND o.created_at <= now() - interval '72 hours';
  EXCEPTION WHEN OTHERS THEN
    PERFORM private.bump_metric_internal('dating.verify.sweep_failed');
  END;
  BEGIN
    DELETE FROM public.dating_verification_sessions AS s WHERE s.created_at <= now() - interval '30 days';
    GET DIAGNOSTICS v_k = ROW_COUNT; v_n := v_n + v_k;
  EXCEPTION WHEN OTHERS THEN
    PERFORM private.bump_metric_internal('dating.verify.sweep_failed');
  END;
  RETURN v_n;
END;
$$;
DO $unschedule$
BEGIN
  PERFORM cron.unschedule(j.jobid) FROM cron.job AS j WHERE j.jobname = 'dating-verification-sweep';
END $unschedule$;
SELECT cron.schedule('dating-verification-sweep', '*/15 * * * *',
  $cron$SELECT public.sweep_dating_verification_sessions()$cron$);

DROP POLICY IF EXISTS dating_verification_review_insert_by_session ON storage.objects;
CREATE POLICY dating_verification_review_insert_by_session ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'dating-verification-review' AND public.dating_review_upload_open(name));

-- 22. Re-created from their live bodies; every changed line is marked
--     -- Spec 2 W4a (Task 1 Step 8 diffs them).
CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO '' -- Spec 2 W4 final (M-11)
AS $function$
  -- Spec 2 W4a (§3.3.1, §4.10): an age check passed (fae or id) and not
  -- Spec 2 W4a revoked, and Spec 1's declared age 18 or over; the record
  -- Spec 2 W4a keeps no date of birth, and a typed DOB alone never passes.
  SELECT EXISTS (
    SELECT 1 FROM public.dating_age_verifications dav
    WHERE dav.user_id = p_user_id
      AND dav.revoked_at IS NULL
      AND dav.age_result = 'pass' -- Spec 2 W4a
      AND dav.age_method IN ('fae', 'id') -- Spec 2 W4a
  ) AND coalesce(public.account_age(p_user_id) >= 18, false); -- Spec 2 W4a: NULL never passes
$function$;

CREATE OR REPLACE FUNCTION public.enforce_dating_age_verification_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO '' -- Spec 2 W4 final (M-11)
AS $function$
BEGIN
  -- Spec 2 W4a (§4.10, 04 G14): a revocation, or an age check that fails,
  -- Spec 2 W4a pauses the active enrolment with its own reason (carry 1;
  -- Spec 2 W4a resume and the app mirror it) and closes every match.
  IF (NEW.revoked_at IS NOT NULL AND (TG_OP = 'INSERT' OR OLD.revoked_at IS NULL)) -- Spec 2 W4a
     OR (NEW.age_result = 'fail' AND (TG_OP = 'INSERT' OR OLD.age_result IS DISTINCT FROM 'fail')) THEN -- Spec 2 W4a
    UPDATE public.dating_enrollments SET state='paused',paused_at=COALESCE(paused_at,now()), -- Spec 2 W4a
      pause_reason=COALESCE(pause_reason,'verification'),updated_at=now() -- Spec 2 W4a (carry 1)
      WHERE user_id=NEW.user_id AND state='active';
    UPDATE public.dating_enrollments SET pause_reason='verification',updated_at=now() -- Spec 2 W4a (fix round 1, M-1): a person's own
      WHERE user_id=NEW.user_id AND state='paused' AND pause_reason IN ('user','away'); -- Spec 2 W4a pause takes the check's reason
    UPDATE public.dating_profiles SET profile_state='paused',updated_at=now()
      WHERE user_id=NEW.user_id AND profile_state='active';
    PERFORM public.invalidate_dating_for_user(NEW.user_id,'age_verification_invalid');
  ELSIF TG_OP = 'UPDATE' AND OLD.age_result = 'pass' AND NEW.age_result IS NULL AND NEW.revoked_at IS NULL THEN -- Spec 2 W4 final (N-1): a pass
    -- Spec 2 W4 final (N-1) cleared for a re-check (I-1b: photos all newer than it) pauses with
    -- Spec 2 W4 final (N-1) 'verification' at once, as a revocation does (the home: "Verify it's
    -- Spec 2 W4 final (N-1) you", check needed, no Resume until a new pass), and closes no match.
    UPDATE public.dating_enrollments SET state='paused',paused_at=COALESCE(paused_at,now()), -- Spec 2 W4 final (N-1)
      pause_reason=COALESCE(pause_reason,'verification'),updated_at=now() -- Spec 2 W4 final (N-1)
      WHERE user_id=NEW.user_id AND state='active'; -- Spec 2 W4 final (N-1)
    UPDATE public.dating_enrollments SET pause_reason='verification',updated_at=now() -- Spec 2 W4 final (N-1): a person's own
      WHERE user_id=NEW.user_id AND state='paused' AND pause_reason IN ('user','away'); -- Spec 2 W4 final (N-1) pause takes the reason
    UPDATE public.dating_profiles SET profile_state='paused',updated_at=now() -- Spec 2 W4 final (N-1)
      WHERE user_id=NEW.user_id AND profile_state='active'; -- Spec 2 W4 final (N-1)
    PERFORM public.invalidate_dating_for_user(NEW.user_id,'age_recheck'); -- Spec 2 W4 final (N-1): introductions go; matches stay
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO '' -- Spec 2 W4 final (M-11)
AS $function$
DECLARE -- W1 final fix (I-1)
  v_try integer; -- W1 final fix (I-1)
BEGIN
  FOR v_try IN 1..3 LOOP -- W1 final fix (I-1)
  BEGIN -- W1 final fix (I-1)
  UPDATE public.dating_feature_snapshots
  SET invalidated_at = COALESCE(invalidated_at, now())
  WHERE user_id = p_user_id
    AND invalidated_at IS NULL;

  UPDATE public.dating_introductions
  SET state = 'invalidated'
  WHERE (user_low_id = p_user_id OR user_high_id = p_user_id)
    AND state IN ('generated', 'presented', 'interested');

  -- Close existing active matches ONLY for reasons that are genuinely an exit
  -- from Dating: leaving (exit), terms/opt-in withdrawal (dating_consent_withdrawn
  -- — this ALSO sets profile_state='exited', so it must close matches too, per
  -- re-review DATING-H5a; note Spec §3.3/:113 "matches remain on withdrawal"
  -- governs HISTORICAL-DATA consent only, not terms/opt-in), suspension
  -- (account_restricted), and profile deletion. Pause, HISTORICAL-consent
  -- withdrawal, profile edits, and scheduled revalidation deliberately PRESERVE
  -- matches (Spec §14 :612 pause; :113 historical-consent).
  IF p_reason IN (
    'exit', 'dating_consent_withdrawn', 'account_restricted', 'profile_deleted', -- Spec 2 W4a
    'age_review', 'age_verification_invalid' -- Spec 2 W4a (§6.3, §4.10): every match closes
  ) THEN
    UPDATE public.dating_matches
    SET state = 'closed',
        closed_at = COALESCE(closed_at, now()), -- Spec 2 W4a
        closed_reason = CASE WHEN p_reason IN ('age_review', 'age_verification_invalid') THEN p_reason ELSE closed_reason END, -- Spec 2 W4a
        evidence_until = CASE WHEN p_reason IN ('age_review', 'age_verification_invalid') -- Spec 2 W4a
                              THEN now() + interval '30 days' ELSE evidence_until END -- Spec 2 W4a (§4.8)
    WHERE (user_low_id = p_user_id OR user_high_id = p_user_id)
      AND state = 'active';
  END IF;
  EXIT; -- W1 final fix (I-1)
  EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- W1 final fix (I-1)
    IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- W1 final fix (N-M3): an inner retry already ran: no nesting -- W1 final fix (I-1)
  END; -- W1 final fix (I-1)
  END LOOP; -- W1 final fix (I-1)
END;
$function$;

CREATE OR REPLACE FUNCTION public.enforce_dating_restriction_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO '' -- Spec 2 W4 final (M-11)
AS $function$
BEGIN
  IF NEW.lifted_at IS NULL AND NEW.starts_at <= now()
     AND (NEW.ends_at IS NULL OR NEW.ends_at > now()) THEN
    UPDATE public.dating_enrollments SET state='suspended',updated_at=now()
      WHERE user_id=NEW.user_id AND state<>'exited';
    UPDATE public.dating_profiles SET profile_state='paused',updated_at=now()
      WHERE user_id=NEW.user_id AND profile_state='active';
    PERFORM public.invalidate_dating_for_user(NEW.user_id, -- Spec 2 W4a (§6.3): an underage_risk age_review closes every match as age_review
      CASE WHEN NEW.restriction_type = 'age_review' THEN 'age_review' ELSE 'account_restricted' END); -- Spec 2 W4a
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dating_pair_passes_hard_filters(p_a uuid, p_b uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO '' -- Spec 2 W4 final (M-11)
AS $function$
DECLARE
  v_pa record;
  v_pb record;
  v_prefs_a record;
  v_prefs_b record;
  v_age_a int;
  v_age_b int;
BEGIN
  IF p_a IS NULL OR p_b IS NULL OR p_a = p_b THEN
    RETURN false;
  END IF;

  -- Eligibility, age gate, good standing, no relationship, active
  -- enrollment -- the predicate the rest of Dating already trusts.
  IF NOT public.dating_candidate_is_current(p_a)
     OR NOT public.dating_candidate_is_current(p_b) THEN
    RETURN false;
  END IF;

  -- Enough approved content to render safely (§5).
  IF NOT public.dating_profile_ready(p_a)
     OR NOT public.dating_profile_ready(p_b) THEN
    RETURN false;
  END IF;

  -- Former partners, including across re-registration (§5.1).
  IF public.dating_former_partner_excluded(p_a, p_b) THEN
    RETURN false;
  END IF;

  -- Blocks are bilateral and immediate.
  IF EXISTS (
    SELECT 1 FROM public.dating_blocks b
    WHERE (b.blocker_user_id = p_a AND b.blocked_user_id = p_b)
       OR (b.blocker_user_id = p_b AND b.blocked_user_id = p_a)
  ) THEN
    RETURN false;
  END IF;

  -- A pair already introduced must not be re-introduced: §6.4 idempotency,
  -- and re-showing a passed candidate would leak that they passed.
  IF EXISTS (
    SELECT 1 FROM public.dating_introductions di
    WHERE di.pair_key = public.dating_pair_key(p_a, p_b)
  ) THEN
    RETURN false;
  END IF;

  -- Previously unmatched pairs stay apart for the configured cooldown.
  IF EXISTS (
    SELECT 1 FROM public.dating_matches dm
    WHERE dm.pair_key = public.dating_pair_key(p_a, p_b)
  ) THEN
    RETURN false;
  END IF;

  SELECT gender_identity, city_region_code, relationship_intention
    INTO v_pa FROM public.dating_profiles WHERE user_id = p_a;
  SELECT gender_identity, city_region_code, relationship_intention
    INTO v_pb FROM public.dating_profiles WHERE user_id = p_b;

  SELECT min_age, max_age, gender_preferences, region_preferences,
         intention_preferences
    INTO v_prefs_a FROM public.dating_preferences WHERE user_id = p_a;
  SELECT min_age, max_age, gender_preferences, region_preferences,
         intention_preferences
    INTO v_prefs_b FROM public.dating_preferences WHERE user_id = p_b;

  IF v_prefs_a IS NULL OR v_prefs_b IS NULL THEN
    RETURN false;
  END IF;

  -- Spec 2 W4a (§1.4): Spec 1's declared age, counted only while the age
  -- Spec 2 W4a check holds; never a client-supplied integer, never a stored DOB.
  v_age_a := CASE WHEN public.dating_age_gate_holds(p_a) THEN public.account_age(p_a) END; -- Spec 2 W4a
  v_age_b := CASE WHEN public.dating_age_gate_holds(p_b) THEN public.account_age(p_b) END; -- Spec 2 W4a

  IF v_age_a IS NULL OR v_age_b IS NULL THEN
    RETURN false;
  END IF;

  -- Each side's stated range must admit the other. Symmetric because both
  -- directions are required.
  IF v_age_b < v_prefs_a.min_age OR v_age_b > v_prefs_a.max_age
     OR v_age_a < v_prefs_b.min_age OR v_age_a > v_prefs_b.max_age THEN
    RETURN false;
  END IF;

  -- An empty preference list means "no stated restriction" and admits all.
  -- A non-empty list must contain the other's value. Never inferred from
  -- quizzes or behavior (§5).
  IF jsonb_array_length(COALESCE(v_prefs_a.gender_preferences, '[]'::jsonb)) > 0
     AND (v_pb.gender_identity IS NULL
          OR NOT (v_prefs_a.gender_preferences ? v_pb.gender_identity)) THEN
    RETURN false;
  END IF;
  IF jsonb_array_length(COALESCE(v_prefs_b.gender_preferences, '[]'::jsonb)) > 0
     AND (v_pa.gender_identity IS NULL
          OR NOT (v_prefs_b.gender_preferences ? v_pa.gender_identity)) THEN
    RETURN false;
  END IF;

  IF jsonb_array_length(COALESCE(v_prefs_a.region_preferences, '[]'::jsonb)) > 0
     AND NOT (v_prefs_a.region_preferences ? v_pb.city_region_code) THEN
    RETURN false;
  END IF;
  IF jsonb_array_length(COALESCE(v_prefs_b.region_preferences, '[]'::jsonb)) > 0
     AND NOT (v_prefs_b.region_preferences ? v_pa.city_region_code) THEN
    RETURN false;
  END IF;

  IF jsonb_array_length(COALESCE(v_prefs_a.intention_preferences, '[]'::jsonb)) > 0
     AND NOT (v_prefs_a.intention_preferences ? v_pb.relationship_intention) THEN
    RETURN false;
  END IF;
  IF jsonb_array_length(COALESCE(v_prefs_b.intention_preferences, '[]'::jsonb)) > 0
     AND NOT (v_prefs_b.intention_preferences ? v_pa.relationship_intention) THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.resume_dating_mode(p_idempotency_key text)
 RETURNS dating_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
  v_try integer; -- W1 final fix (I-1)
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  PERFORM private.dating_lock_setup(v_user_id); -- the shared lock order (setup, then same-gender: W1 final fix I-1)
  -- W1 final fix (M-1): activation's quiet field-key gate (a replaced or
  -- missing key refuses quietly, counted), before the device.
  IF private.dating_field_key_usable() IS NOT TRUE THEN -- W1 final fix (M-1)
    PERFORM private.bump_metric_internal(CASE WHEN private.dating_field_key_present() -- W1 final fix (M-1)
                                              THEN 'dating.field_key.mismatch' ELSE 'dating.field_key.missing' END); -- W1 final fix (M-1)
    SELECT * INTO v_enrollment FROM public.dating_enrollments AS e WHERE e.user_id = v_user_id; -- W1 final fix (M-1)
    RETURN v_enrollment; -- W1 final fix (M-1)
  END IF; -- W1 final fix (M-1)
  IF NOT public.dating_require_trusted_device() THEN RAISE EXCEPTION 'reverify_device' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_enrollment FROM public.dating_enrollments AS e WHERE e.user_id = v_user_id FOR UPDATE;
  IF NOT FOUND OR v_enrollment.state IS DISTINCT FROM 'paused' THEN
    RAISE EXCEPTION 'not_paused' USING ERRCODE = '22023';
  END IF;
  IF v_enrollment.activated_at IS NULL THEN -- fix round 1 (M-4): a draft that was paused goes through activation
    RAISE EXCEPTION 'activation_required' USING ERRCODE = '22023';
  END IF;
  -- Spec 2 W2 (Task 3): never switched back on off the Dating path: whoever
  -- Spec 2 W2 chose Just for me or Relationship stays paused (each pause has
  -- Spec 2 W2 its one way out); a never-chosen path (NULL) keeps today's rule.
  IF coalesce((SELECT u.path FROM public.users AS u WHERE u.id = v_user_id) IN ('just_me', 'relationship'), false) THEN -- Spec 2 W2
    RAISE EXCEPTION 'path_not_dating' USING ERRCODE = '22023'; -- Spec 2 W2 (fix round 1, M-3): "choose Dating to resume"
  END IF; -- Spec 2 W2
  IF public.dating_eligibility(v_user_id, 'setup') IS DISTINCT FROM 'eligible' -- NULL refuses
     OR (coalesce(v_enrollment.pause_reason IN ('gates', 'verification'), false) -- Spec 2 W4a (carry 1): the cron's and a revocation's pause hold while their cause stands
         AND public.dating_age_gate_holds(v_user_id) IS NOT TRUE) THEN -- Spec 2 W2: NULL-safe (the cron's other causes are checked above and below)
    RAISE EXCEPTION 'resume_gates_not_met' USING ERRCODE = '22023';
  END IF;
  IF NOT (private.dating_consent_granted(v_user_id, 'dating_terms') AND private.dating_consent_granted(v_user_id, 'dating_opt_in')
          AND private.dating_consent_granted(v_user_id, 'special_category_profile')) THEN -- fix round 1 (I-1)
    RAISE EXCEPTION 'consent_required' USING ERRCODE = '22023';
  END IF;
  IF NOT public.dating_profile_complete(v_user_id) THEN
    RAISE EXCEPTION 'profile_or_preferences_incomplete' USING ERRCODE = '22023';
  END IF;
  IF private.content_filter_verdict((SELECT p.display_name FROM public.dating_profiles AS p WHERE p.user_id = v_user_id), NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'profile_or_preferences_incomplete' USING ERRCODE = '22023'; -- a name no writer filtered (batch-7 I-3/M-5)
  END IF;
  IF NOT public.claim_dating_idempotency('resume_dating_mode', p_idempotency_key) THEN
    RETURN v_enrollment;
  END IF;
  FOR v_try IN 1..3 LOOP -- W1 final fix (I-1): a lock conflict is retried (each attempt its own savepoint)
    BEGIN -- W1 final fix (I-1)
      UPDATE public.dating_profiles AS p SET profile_state = 'active', updated_at = now() WHERE p.user_id = v_user_id;
      UPDATE public.dating_enrollments AS e
         SET state = 'active', paused_at = NULL, pause_reason = NULL, updated_at = now()
       WHERE e.user_id = v_user_id
      RETURNING * INTO v_enrollment;
      PERFORM private.bump_metric_internal('dating.resume');
      EXIT; -- W1 final fix (I-1)
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- W1 final fix (I-1)
      IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- W1 final fix (N-M3): an inner retry already ran: no nesting -- W1 final fix (I-1)
    END; -- W1 final fix (I-1)
  END LOOP; -- W1 final fix (I-1)
  RETURN v_enrollment;
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
    v_country := coalesce(v_country, private.dating_phone_country((SELECT a.phone FROM auth.users AS a WHERE a.id = v_user))); -- Spec 2 W3a
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'feature_unavailable', 'country', v_country, -- Spec 2 W3a (C-2)
      'notify', private.dating_notice_state(v_user, v_country, NULL)); -- Spec 2 W3a (R-4, R-5)
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN coalesce(v_has, '{"has_data": true}') || jsonb_build_object('state', 'reverify_device'); -- Spec 2 W3a (C-2)
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
  END IF;
  -- Spec 2 W4a: the verification sessions go, a human review's photos with
  -- Spec 2 W4a them (queued, as every Dating object), and the identity
  -- Spec 2 W4a result, which covered the photos deleted above; the age
  -- Spec 2 W4a result stays while the account exists (§4.8).
  PERFORM public.queue_media_deletion('dating-verification-review', o.name) -- Spec 2 W4a
     FROM storage.objects AS o -- Spec 2 W4a
    WHERE o.bucket_id = 'dating-verification-review' -- Spec 2 W4a
      AND split_part(o.name, '/', 1) IN (SELECT vs.id::text FROM public.dating_verification_sessions AS vs -- Spec 2 W4a
                                          WHERE vs.user_id = p_user); -- Spec 2 W4a
  DELETE FROM public.dating_verification_sessions AS vs WHERE vs.user_id = p_user; -- Spec 2 W4a
  UPDATE public.dating_age_verifications AS av -- Spec 2 W4a
     SET identity_method = NULL, identity_result = NULL, identity_vendor = NULL, -- Spec 2 W4a
         identity_decided_at = NULL, decided_by = NULL, updated_at = now() -- Spec 2 W4a
   WHERE av.user_id = p_user AND av.identity_result IS NOT NULL; -- Spec 2 W4a
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

CREATE OR REPLACE FUNCTION public.get_dating_operational_health()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO '' -- Spec 2 W4 final (M-11)
AS $function$
  SELECT jsonb_build_object(
    'dating_enabled',public.dating_flag_enabled('dating_mode_enabled'),
    'candidate_generation_enabled',public.dating_flag_enabled('dating_candidate_generation'),
    'exclusion_key_present',public.app_setting('dating_exclusion_key') IS NOT NULL,
    'relationships_ended_without_exclusion_24h',(
      SELECT count(*) FROM public.relationships r
      WHERE r.status = 'ended'
        AND r.ended_at >= now() - interval '24 hours'
        AND NOT EXISTS (
          SELECT 1 FROM public.dating_former_partner_exclusions e
          WHERE e.relationship_id = r.id
        )
    ),
    'active_algorithm_versions',(SELECT count(*) FROM public.dating_algorithm_configs WHERE state='active'),
    'stuck_generation_runs',(SELECT count(*) FROM public.dating_generation_runs WHERE state='processing' AND started_at < now()-interval '30 minutes'),
    'failed_generation_runs_24h',(SELECT count(*) FROM public.dating_generation_runs WHERE state IN ('failed','dead_letter') AND created_at >= now()-interval '24 hours'),
    'expired_open_introductions',(SELECT count(*) FROM public.dating_introductions WHERE state IN ('generated','presented','interested') AND expires_at <= now()),
    'pending_bio_moderation',(SELECT count(*) FROM public.dating_profiles WHERE moderation_state='pending'),
    'pending_photo_moderation',(SELECT count(*) FROM public.dating_profile_photos WHERE moderation_state='pending'),
    'environment',private.attune_environment(), -- Spec 2 W1d
    'field_key_present',private.dating_field_key_present(), -- Spec 2 W1d
    -- Spec 2 W1d (§2.4): nothing can write an RPC's parameters to the log.
    'log_settings_safe',coalesce(current_setting('log_statement', true) IN ('none', 'ddl')
      AND (current_setting('log_min_duration_statement', true) = '-1'
           OR current_setting('log_parameter_max_length', true) = '0')
      AND current_setting('log_parameter_max_length_on_error', true) = '0', false),
    'enabled_countries',to_jsonb(private.dating_open_countries()), -- Spec 2 W1d
    'age_assurance_mode',private.dating_verification_mode(), -- Spec 2 W4a
    'verification_awaiting_review',(SELECT count(*) FROM public.dating_verification_sessions WHERE state='awaiting_review'), -- Spec 2 W4a
    'verification_oldest_waiting_hours',(SELECT floor(extract(epoch FROM now() - min(coalesce(awaiting_since, updated_at))) / 3600)::int -- Spec 2 W4a (fix round 1, M-8)
                                           FROM public.dating_verification_sessions WHERE state='awaiting_review'), -- Spec 2 W4a
    -- Spec 2 W1d (B2 I-5, B5 M-4, B6 M-5): each key set and its stored
    -- Spec 2 W1d fingerprint equal (read only; never the counting mismatch()).
    'exclusion_key_fingerprint_ok',private.dating_exclusion_key_ready(), -- Spec 2 W1d
    'field_key_fingerprint_ok',private.dating_field_key_ready(), -- Spec 2 W1d
    'safety_counters_7d',(SELECT jsonb_object_agg(k.key, coalesce((SELECT sum(c.count) FROM public.metric_counters c -- Spec 2 W1d
                            WHERE c.key = k.key AND c.day >= (now() AT TIME ZONE 'utc')::date - 6), 0)) -- Spec 2 W1d
      FROM unnest(ARRAY['dating.deletion.uncarried', 'dating.exclusion_key.mismatch', 'dating.exclusion_key.unseeded', -- Spec 2 W1d
                        'dating.eligibility.key_not_ready', 'dating.field_key.mismatch', 'dating.field_key.missing', -- Spec 2 W1d
                        'dating.parked_pause.failed', -- Spec 2 W1d (fix round 1, M-5)
                        'dating.path_pause.failed', 'dating.gates.busy', -- Spec 2 W2
                        'dating.gates.failed', 'dating.gentle_wait.undated', -- Spec 2 W2 (Task 3 carry: W2 batch 1 fix round 1, M-4 and M-3)
                        'dating.path_pause.swept', -- Spec 2 W2 (Task 3 fix round 1, I-1)
                        'dating.gentle_wait.seen', 'dating.gentle_wait.account_deleted_7d', -- Spec 2 W2 (migration 3, §6.9)
                        'dating.gentle_wait.clear_busy', 'dating.gentle_wait.seen_skipped', 'dating.home.unreadable_field', -- Spec 2 W2 (migration 3 fix round 1)
                        'dating.kill_switch.pending', 'dating.kill_switch.unreadable', -- Spec 2 W1d (migration 11)
                        'dating.verify.sweep_failed', 'dating.verify.id_review_expired', -- Spec 2 W4a (fix round 1, M-7)
                        'dating.deletion.prepare_carry_failed', 'dating.deletion.late_carry_failed']) AS k(key)), -- W1 final fix (M-4)
    -- W1 final fix (M-4): app deletions refused for a missing exclusion key
    -- W1 final fix (delete-account records prepare's message) in 7 days.
    'deletions_refused_key_missing_7d',(SELECT count(*) FROM public.account_deletion_requests AS r -- W1 final fix (M-4)
                                         WHERE r.completed_at IS NULL AND r.requested_at >= now() - interval '7 days' -- W1 final fix (M-4)
                                           AND r.failure_reason LIKE '%deletion:enforcement_key_missing%'), -- W1 final fix (M-4)
    -- Spec 2 W1d (fix round 1, I-1): every purge still pending, until a switch clears it.
    'kill_switch_pending',(SELECT coalesce(jsonb_agg(jsonb_build_object('scope', k.scope, 'since', k.first_failed_at, -- Spec 2 W1d
                             'sqlstate', k.last_sqlstate, 'attempts', k.attempts) ORDER BY k.scope), '[]'::jsonb) -- Spec 2 W1d
                           FROM private.dating_kill_switch_pending k) -- Spec 2 W1d
  );
$function$;

-- 23. The server-only objects are closed in the migration itself (the twin
--     re-asserts them and opens the two client functions).
REVOKE ALL ON public.dating_verification_sessions FROM service_role;
REVOKE ALL ON FUNCTION private.dating_verification_mode() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_verification_available() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_verification_state(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_age_recheck_due(uuid) FROM PUBLIC, anon, authenticated, service_role; -- Spec 2 W4 final (I-1b)
REVOKE ALL ON FUNCTION private.dating_request_device_hash() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.sweep_dating_verification_sessions() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_verification_config() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.begin_dating_verification(uuid, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_dating_verification_session(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_dating_verification_photos(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_dating_verification_ref(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_liveness_attempt(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finish_dating_verification_session(uuid, text, text, smallint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_identity_check(uuid, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_age_assurance(uuid, text, text, smallint, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_age_far_below(uuid, uuid, text) FROM PUBLIC, anon, authenticated; -- Spec 2 W4 final (M-8)
REVOKE ALL ON FUNCTION public.record_dating_video_outcome(uuid, uuid, text, text, smallint, text, text) FROM PUBLIC, anon, authenticated; -- Spec 2 W4a
REVOKE ALL ON FUNCTION public.check_dating_id_birth_date(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_dating_human_review(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.decide_dating_human_review(uuid, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.revoke_dating_age_verification(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_my_dating_verification() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.dating_review_upload_open(text) FROM PUBLIC, anon;

COMMIT;
