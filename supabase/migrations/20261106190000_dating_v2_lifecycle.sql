-- Spec 2 W1d, migration 10 (spec §4.9 W1d #2, §3.8, §4.3, §4.4, §4.8,
-- §6.3; Q17 exceptions, R-2, I-11, R19):
--   * dating_enrollments: pause_reason (user, relationship, path_change,
--     same_gender_switch, away, account_parked); adults_only_confirmed_at
--     dropped (the "I am 18" checkbox is gone; activate and consent were its
--     only readers and are re-created here).
--   * Consent purposes v2: dating_terms, dating_opt_in,
--     special_category_profile, special_category_faith,
--     biometric_verification; historical_data and age_gate rows deleted
--     (fresh start) and refused by a CHECK. record_dating_consent
--     re-created from its live body: every input checked first (no raw
--     constraint error), the time is the server's clock (batch-6 M-12),
--     a replay changes nothing; withdrawing special_category_faith clears
--     only the faith answer (owner ruling 2026-11-06, PF-F3); withdrawing
--     any other purpose is leaving Dating (§3.2 D4).
--   * private.dating_exit_internal(user, keep_list): the one hard delete
--     (profile, sensitive answers, photos, prompts, settings, preferences,
--     private reflections, introductions, the session row, the notify
--     request (PF-F8); the never-introduce list unless kept). Photos go
--     through queue_media_deletion, so Spec 1 W7's CSAM evidence guard holds
--     back an object under an open match. Active matches close ('exit') and
--     stay sealed 30 days (Q17 exception 1); consent events stay (exception
--     3); the list stays only if ticked (exception 2, unticked by default);
--     the age assurance result stays (§4.8: while the account exists); a
--     suspension stays (only the data goes).
--   * exit_dating_mode(key, keep_never_introduce DEFAULT false) replaces
--     exit_dating_mode(key); delete_dating_profile dropped (one hard delete).
--   * dating_profile_complete (new) and dating_profile_ready v2: approved,
--     verified, age gate, intention + attestation, place, children, the
--     sensitive identity and who-to-meet, >= 2 approved photos, >= 2
--     approved prompts (and, for ready, profile_state active).
--   * activate_dating_profile v2 (dating_eligibility 'setup', the age gate,
--     complete, the name through the content filter (batch-7 I-3/M-5); no
--     checkbox; explicit "Everyone" works; the I-5 key gate kept),
--     pause_dating_mode v2 ('user'), resume_dating_mode (new: eligibility,
--     a complete profile and the name only, Fable L3),
--     pause_dating_for_relationship_user v2 ('relationship'). An enrolment
--     already paused keeps its first reason. Every lifecycle RPC takes the
--     person's setup lock first and the enrolment row before the profile
--     row (the shared order). Activation, resume and a consent grant check
--     the device; pause, exit and a withdrawal never do (W1 B8 ruling:
--     removing data or exposure never needs a device check).
--   * The parked-account trigger dating_on_account_parked on public.users
--     (AFTER UPDATE OF phone_released_at; a no-op unless NULL -> a value;
--     never raises): pauses with account_parked and invalidates the open
--     introductions. Nothing is written to enforcement_records at parking
--     (owner ruling O3: no).
--   * The field key's fingerprint (batch-6 M-5, like the exclusion key's
--     I-5): private.dating_key_fingerprints also holds dating_field_key's
--     (HMAC of a fixed label under the key), seeded here when the key
--     exists at apply time, else by the owner's
--     private.seed_dating_field_key_fingerprint(). A stored fingerprint that
--     differs (a replaced key) is refused everywhere: dating_field_encrypt
--     raises dating:field_key_missing (writers answer unavailable; no
--     mixed-key rows), activation and generation refuse quietly, counted
--     dating.field_key.mismatch. In production an unseeded key is refused
--     too; development allows it (keys there are transaction-local GUCs).
--   * run_dating_candidate_generation re-created from its live body: the
--     I-5 gate kept, then the key guard (no run without dating_exclusion_key
--     or dating_field_key: {"skipped": "missing_key"}), then the field-key
--     fingerprint. Order: flag, exclusion mismatch, missing_key, field key.
--   * get_dating_operational_health v2: + environment, field_key_present,
--     log_settings_safe, enabled_countries, exclusion_key_fingerprint_ok and
--     field_key_fingerprint_ok (STABLE comparisons, never the counting
--     mismatch()), and safety_counters_7d (deletion uncarried, the
--     fingerprint and key-readiness counters).
--   * Fix round 1 (batch-10 review): completeness, activation and resume
--     need standing dating_terms, dating_opt_in and special_category_profile
--     consents (I-1); exit withdraws every standing consent ("when you
--     left"), so re-entering needs D4 again, and a second exit rewrites
--     nothing (M-2); a reused consent key is refused (M-3); resume never
--     makes a never-activated draft live (M-4); a failed parked pause is
--     counted and readiness never counts a parked account (M-5); a faith
--     withdrawal ends introductions (M-7); an unseeded field key is allowed
--     in development only when it isn't in Vault (M-1).
--   * W1 final fix (I-1, M-3, M-1): pause, resume, activation, a consent
--     withdrawal (both branches), the relationship guard's pause and the
--     parked trigger take the shared lock order (dating_lock_setup now also
--     takes the person's same-gender locks, shared, before any row) and
--     retry a deadlock, a lock timeout or a serialization failure up to
--     three times, each attempt its own savepoint; a third failure is
--     dating:busy with the original SQLSTATE (never the raw DETAIL), and the
--     parked trigger counts it as before. Resume repeats activation's quiet
--     field-key gate (M-1). A caller never retries an inner dating:busy (the
--     invalidation already retried): three attempts in all (N-M3).
-- Every re-created body is its live one plus the lines marked "Spec 2 W1d".
-- Grants in 20261106190010_dating_v2_lifecycle_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.dating_enrollments ADD COLUMN IF NOT EXISTS pause_reason text;
ALTER TABLE public.dating_enrollments DROP CONSTRAINT IF EXISTS dating_enrollments_pause_reason_check;
ALTER TABLE public.dating_enrollments ADD CONSTRAINT dating_enrollments_pause_reason_check CHECK (
  pause_reason IS NULL OR pause_reason IN ('user', 'relationship', 'path_change', 'same_gender_switch', 'away', 'account_parked'));
DELETE FROM public.dating_consent_events WHERE purpose IN ('historical_data', 'age_gate');
ALTER TABLE public.dating_consent_events DROP CONSTRAINT IF EXISTS dating_consent_events_purpose_check;
ALTER TABLE public.dating_consent_events ADD CONSTRAINT dating_consent_events_purpose_check CHECK (
  purpose IN ('dating_terms', 'dating_opt_in', 'special_category_profile', 'special_category_faith', 'biometric_verification'));

-- Batch-6 M-5: the field key's fingerprint, beside the exclusion key's.
ALTER TABLE private.dating_key_fingerprints DROP CONSTRAINT IF EXISTS dating_key_fingerprints_name_check;
ALTER TABLE private.dating_key_fingerprints ADD CONSTRAINT dating_key_fingerprints_name_check CHECK (
  name IN ('dating_exclusion_key', 'dating_field_key'));
COMMENT ON TABLE private.dating_key_fingerprints IS
  'Spec 2 W1a (I-5) and W1d (batch-6 M-5): the fingerprint (HMAC of a fixed label) of dating_exclusion_key and of dating_field_key, written only by the owner''s seeders (or a migration when the key exists at apply time). The field key is rotated by re-encrypting every value first, then replacing its row (owner checklist item 15); the exclusion key is never rotated or replaced (item 11, W1 final fix I-3).';

-- The live field key's fingerprint, or NULL without a usable key (the same
-- key read as the field functions: Vault only in production).
CREATE OR REPLACE FUNCTION private.dating_field_key_fingerprint()
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT CASE WHEN char_length(k.v) >= 32
              THEN encode(extensions.hmac('attune:dating_field_key:fingerprint:v1', k.v, 'sha256'), 'hex') END
    FROM (SELECT CASE WHEN private.attune_environment() IS NOT DISTINCT FROM 'development'
                      THEN public.app_setting('dating_field_key')
                      ELSE private.vault_setting_strict('dating_field_key') END AS v) AS k;
$fn$;

-- Ready: the key is set and its stored fingerprint matches (health).
CREATE OR REPLACE FUNCTION private.dating_field_key_ready()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT coalesce((SELECT k.fingerprint FROM private.dating_key_fingerprints AS k WHERE k.name = 'dating_field_key')
                  = private.dating_field_key_fingerprint(), false);
$fn$;

-- Usable: a key, and never a different stored fingerprint; an unseeded key
-- only in development and only when it isn't in Vault (contracts there use
-- transaction-local GUC keys; a hosted project's Vault key is not).
CREATE OR REPLACE FUNCTION private.dating_field_key_usable()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT coalesce(CASE
           WHEN f.live IS NULL THEN false
           WHEN f.stored IS NULL THEN private.attune_environment() IS NOT DISTINCT FROM 'development'
                                      AND private.vault_setting_strict('dating_field_key') IS NULL -- fix round 1 (M-1): a Vault key is always held to the fingerprint
           ELSE f.stored = f.live END, false)
    FROM (SELECT private.dating_field_key_fingerprint() AS live,
                 (SELECT k.fingerprint FROM private.dating_key_fingerprints AS k
                   WHERE k.name = 'dating_field_key') AS stored) AS f;
$fn$;

CREATE OR REPLACE FUNCTION private.seed_dating_field_key_fingerprint()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
-- Owner only (no API role; owner checklist item 15): stores the live key's
-- fingerprint when none is stored. Never replaces a stored one: a rotation
-- deletes the row first, after re-encrypting.
DECLARE
  v_live constant text := private.dating_field_key_fingerprint();
  v_stored text;
BEGIN
  IF v_live IS NULL THEN
    RETURN 'missing_key';
  END IF;
  INSERT INTO private.dating_key_fingerprints (name, fingerprint)
  VALUES ('dating_field_key', v_live)
  ON CONFLICT (name) DO NOTHING;
  SELECT k.fingerprint INTO v_stored FROM private.dating_key_fingerprints AS k WHERE k.name = 'dating_field_key';
  RETURN CASE WHEN v_stored = v_live THEN 'ready' ELSE 'mismatch' END;
END;
$fn$;

CREATE OR REPLACE FUNCTION private.dating_field_encrypt(p_plain jsonb)
 RETURNS bytea
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  v_key constant text := CASE WHEN private.attune_environment() IS NOT DISTINCT FROM 'development'
                             THEN public.app_setting('dating_field_key')
                             ELSE private.vault_setting_strict('dating_field_key') END;
BEGIN
  IF p_plain IS NULL THEN
    RETURN NULL;
  END IF;
  IF coalesce(char_length(v_key), 0) < 32 THEN
    RAISE EXCEPTION 'dating:field_key_missing';
  END IF;
  IF private.dating_field_key_usable() IS NOT TRUE THEN -- Spec 2 W1d (batch-6 M-5): a replaced key (or, in production, an unseeded one)
    RAISE EXCEPTION 'dating:field_key_missing'; -- Spec 2 W1d: never writes, so no mixed-key rows
  END IF; -- Spec 2 W1d
  -- Byte 0 tags the key version (1: dating_field_key), for rotation. Then
  -- an OpenPGP message: AES-256, a random session key and salt per value,
  -- the MDC integrity packet; compression off, so the ciphertext's length
  -- says nothing about the content.
  RETURN '\x01'::bytea || extensions.pgp_sym_encrypt(p_plain::text, v_key,
    'cipher-algo=aes256, compress-algo=0, disable-mdc=0, sess-key=1, s2k-digest-algo=sha256');
END;
$function$;

-- Seeded now if the key is already there (B2 ruling: the migration or the
-- owner seeds it, never a user path).
DO $$
BEGIN
  PERFORM private.seed_dating_field_key_fingerprint();
END $$;

-- The one hard delete (§3.8, §4.8). Callers take the person's setup lock
-- first (the shared order: setup, then same-gender, then rows).
CREATE OR REPLACE FUNCTION private.dating_exit_internal(p_user uuid, p_keep_never_introduce boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
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
     FROM public.dating_photo_upload_intents AS i WHERE i.user_id = p_user;
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
$fn$;

CREATE OR REPLACE FUNCTION public.record_dating_consent(p_idempotency_key text, p_purpose text, p_action text, p_policy_version text, p_categories jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_action text := CASE
    WHEN p_action IN ('grant','granted') THEN 'granted'
    WHEN p_action IN ('withdraw','withdrawn') THEN 'withdrawn'
    ELSE NULL END;
  v_inserted integer; -- Spec 2 W1d
  v_try integer; -- W1 final fix (I-1)
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  -- Spec 2 W1d: every input is checked before any write (a raw constraint
  -- Spec 2 W1d error would echo the row); the key as claim_dating_idempotency.
  IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN -- Spec 2 W1d
    RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE='22023'; -- Spec 2 W1d
  END IF; -- Spec 2 W1d
  IF char_length(p_idempotency_key) NOT BETWEEN 8 AND 200 OR p_idempotency_key !~ '^[A-Za-z0-9_:.-]+$' -- Spec 2 W1d
     OR starts_with(p_idempotency_key, 'exit:') THEN -- Spec 2 W1d (fix round 1, M-3): exit's own records
    RAISE EXCEPTION 'idempotency_key_invalid' USING ERRCODE='22023'; -- Spec 2 W1d
  END IF; -- Spec 2 W1d
  IF (p_purpose IN ('dating_terms','dating_opt_in','special_category_profile', -- Spec 2 W1d
                    'special_category_faith','biometric_verification')) IS NOT TRUE -- Spec 2 W1d
     OR v_action IS NULL OR coalesce(p_policy_version ~ '^[A-Za-z0-9._-]{1,40}$', false) IS NOT TRUE -- Spec 2 W1d
     OR jsonb_typeof(COALESCE(p_categories,'[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'invalid_consent_event' USING ERRCODE='22023';
  END IF;
  IF jsonb_array_length(COALESCE(p_categories,'[]'::jsonb)) > 20 -- Spec 2 W1d: at most 20 short strings
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(p_categories,'[]'::jsonb)) AS c(v) -- Spec 2 W1d
                 WHERE jsonb_typeof(c.v) IS DISTINCT FROM 'string' -- Spec 2 W1d
                    OR (char_length(c.v #>> '{}') BETWEEN 1 AND 64) IS NOT TRUE) THEN -- Spec 2 W1d
    RAISE EXCEPTION 'invalid_consent_event' USING ERRCODE='22023'; -- Spec 2 W1d
  END IF; -- Spec 2 W1d
  -- Spec 2 W1d (§4.4): a grant checks the device; a withdrawal never does
  -- Spec 2 W1d (W1 B8 ruling: removing data never needs a device check).
  IF v_action = 'granted' AND NOT public.dating_require_trusted_device() THEN -- Spec 2 W1d
    RAISE EXCEPTION 'reverify_device' USING ERRCODE='22023'; -- Spec 2 W1d
  END IF; -- Spec 2 W1d
  PERFORM private.dating_lock_setup(v_user_id); -- Spec 2 W1d: the shared lock order (setup first)
  INSERT INTO public.dating_consent_events(
    user_id,idempotency_key,purpose,action,policy_version,categories,occurred_at
  ) VALUES(
    v_user_id,p_idempotency_key,p_purpose,v_action,p_policy_version,
    COALESCE(p_categories,'[]'::jsonb),clock_timestamp() -- Spec 2 W1d (batch-6 M-12): the server's clock, in call order
  ) ON CONFLICT(user_id,idempotency_key) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT; -- Spec 2 W1d: a replay changes nothing
  IF v_inserted = 0 AND NOT EXISTS (SELECT 1 FROM public.dating_consent_events AS c -- Spec 2 W1d (fix round 1, M-3)
                                     WHERE c.user_id = v_user_id AND c.idempotency_key = p_idempotency_key -- Spec 2 W1d
                                       AND c.purpose = p_purpose AND c.action = v_action) THEN -- Spec 2 W1d
    RAISE EXCEPTION 'idempotency_key_reused' USING ERRCODE='22023'; -- Spec 2 W1d: a key once used for another event
  END IF; -- Spec 2 W1d

  -- W1 final fix (I-1): a withdrawal is never lost to a kill switch: a
  -- W1 final fix deadlock, a lock timeout or a serialization failure is
  -- W1 final fix retried (three attempts, each its own savepoint; the event
  -- W1 final fix row above stays); the third surfaces as dating:busy.
  IF v_inserted = 1 AND v_action = 'withdrawn' THEN -- W1 final fix (I-1)
    FOR v_try IN 1..3 LOOP -- W1 final fix (I-1)
      BEGIN -- W1 final fix (I-1)
        IF p_purpose = 'special_category_faith' THEN -- Spec 2 W1d (owner 2026-11-06)
          PERFORM private.dating_clear_faith(v_user_id); -- Spec 2 W1d: only the faith answer goes, as D8's Skip
          PERFORM public.invalidate_dating_for_user(v_user_id, 'faith_consent_withdrawn'); -- Spec 2 W1d (fix round 1, M-7): introductions built on it end; matches stay
        ELSE -- Spec 2 W1d: withdrawing any other consent is leaving Dating
          PERFORM private.dating_exit_internal(v_user_id, false); -- Spec 2 W1d
        END IF;
        EXIT; -- W1 final fix (I-1)
      EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- W1 final fix (I-1)
        IF v_try = 3 OR SQLERRM = 'dating:busy' THEN -- W1 final fix (I-1; N-M3: an inner retry already ran)
          RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; -- W1 final fix (I-1): never the raw DETAIL
        END IF; -- W1 final fix (I-1)
      END; -- W1 final fix (I-1)
    END LOOP; -- W1 final fix (I-1)
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dating_profile_complete(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT EXISTS (
    SELECT 1
      FROM public.dating_profiles AS dp
      JOIN public.dating_preferences AS pref ON pref.user_id = dp.user_id
      JOIN public.dating_profile_sensitive AS s ON s.user_id = dp.user_id
     WHERE dp.user_id = p_user_id
       AND dp.moderation_state = 'approved'
       AND dp.verification_state = 'verified'
       AND dp.country_code IS NOT NULL AND dp.region_code IS NOT NULL
       AND dp.intention IS NOT NULL
       AND dp.not_married_attested_at IS NOT NULL AND dp.attestation_version = '2026-10-v1'
       AND dp.children_have IS NOT NULL AND dp.children_want IS NOT NULL
       AND s.identity_enc IS NOT NULL AND s.seeking_enc IS NOT NULL)
    AND public.dating_age_gate_holds(p_user_id)
    AND (SELECT count(*) FROM public.dating_profile_photos AS f
          WHERE f.user_id = p_user_id AND f.moderation_state = 'approved') >= 2
    AND (SELECT count(*) FROM public.dating_prompts AS q
          WHERE q.user_id = p_user_id AND q.moderation_state = 'approved') >= 2
    -- Fix round 1 (I-1): the standing D4 consents (the latest event of each
    -- is a grant; an exit withdraws them all).
    AND private.dating_consent_granted(p_user_id, 'dating_terms')
    AND private.dating_consent_granted(p_user_id, 'dating_opt_in')
    AND private.dating_consent_granted(p_user_id, 'special_category_profile');
$fn$;

CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS ( -- Spec 2 W1d: v2 readiness
    SELECT 1 FROM public.dating_profiles dp
    WHERE dp.user_id = p_user_id
      AND dp.profile_state = 'active'
  ) AND public.dating_profile_complete(p_user_id) -- Spec 2 W1d
    AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = p_user_id AND u.phone_released_at IS NOT NULL); -- Spec 2 W1d (fix round 1, M-5): never a parked account
$function$;

CREATE OR REPLACE FUNCTION public.activate_dating_profile(p_idempotency_key text)
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
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  PERFORM private.dating_lock_setup(v_user_id); -- Spec 2 W1d: the shared lock order (setup, then same-gender: W1 final fix I-1)
  IF private.dating_exclusion_key_mismatch() THEN -- Spec 2 W1a (I-5): a different exclusion key refuses quietly, counted
    PERFORM private.bump_metric_internal('dating.exclusion_key.mismatch'); -- Spec 2 W1a
    SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id=v_user_id; -- Spec 2 W1a
    RETURN v_enrollment; -- Spec 2 W1a
  END IF; -- Spec 2 W1a
  IF private.dating_field_key_usable() IS NOT TRUE THEN -- Spec 2 W1d (batch-6 M-5): no usable field key refuses quietly, counted
    PERFORM private.bump_metric_internal(CASE WHEN private.dating_field_key_present() -- Spec 2 W1d
                                              THEN 'dating.field_key.mismatch' ELSE 'dating.field_key.missing' END); -- Spec 2 W1d
    SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id=v_user_id; -- Spec 2 W1d
    RETURN v_enrollment; -- Spec 2 W1d
  END IF; -- Spec 2 W1d
  IF NOT public.dating_require_trusted_device() THEN RAISE EXCEPTION 'reverify_device' USING ERRCODE='22023'; END IF; -- Spec 2 W1d
  PERFORM public.check_dating_rate_limit('profile_activation',10,interval '1 day');
  IF public.dating_eligibility(v_user_id, 'setup') IS DISTINCT FROM 'eligible' -- Spec 2 W1d (gates 1-4, 6; NULL refuses)
     OR NOT public.dating_age_gate_holds(v_user_id) THEN
    RAISE EXCEPTION 'activation_gates_not_met' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id=v_user_id FOR UPDATE;
  IF NOT FOUND OR v_enrollment.state NOT IN ('profile_draft','paused','active') THEN -- Spec 2 W1d: no checkbox
    RAISE EXCEPTION 'enrollment_incomplete' USING ERRCODE='22023';
  END IF;
  IF NOT (private.dating_consent_granted(v_user_id, 'dating_terms') AND private.dating_consent_granted(v_user_id, 'dating_opt_in') -- Spec 2 W1d (fix round 1, I-1)
          AND private.dating_consent_granted(v_user_id, 'special_category_profile')) THEN -- Spec 2 W1d
    RAISE EXCEPTION 'consent_required' USING ERRCODE='22023'; -- Spec 2 W1d: D4 again (after an exit, a fresh opt-in)
  END IF; -- Spec 2 W1d
  IF NOT public.dating_profile_complete(v_user_id) THEN -- Spec 2 W1d
    RAISE EXCEPTION 'profile_or_preferences_incomplete' USING ERRCODE='22023';
  END IF;
  IF private.content_filter_verdict((SELECT p.display_name FROM public.dating_profiles AS p WHERE p.user_id = v_user_id), NULL) IS NOT NULL THEN -- Spec 2 W1d (batch-7 I-3/M-5)
    RAISE EXCEPTION 'profile_or_preferences_incomplete' USING ERRCODE='22023'; -- Spec 2 W1d: a name no writer filtered (D12 asks again)
  END IF; -- Spec 2 W1d
  IF NOT public.claim_dating_idempotency('activate_dating_profile',p_idempotency_key) THEN RETURN v_enrollment; END IF;
  FOR v_try IN 1..3 LOOP -- W1 final fix (I-1): a lock conflict is retried (each attempt its own savepoint)
    BEGIN -- W1 final fix (I-1)
      UPDATE public.dating_profiles SET profile_state='active',updated_at=now() WHERE user_id=v_user_id;
      UPDATE public.dating_enrollments SET state='active',activated_at=COALESCE(activated_at,now()),
        paused_at=NULL,pause_reason=NULL,exited_at=NULL,updated_at=now() WHERE user_id=v_user_id RETURNING * INTO v_enrollment; -- Spec 2 W1d: pause_reason
      PERFORM private.bump_metric_internal('dating.activated'); -- Spec 2 W1d
      EXIT; -- W1 final fix (I-1)
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- W1 final fix (I-1)
      IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- W1 final fix (N-M3): an inner retry already ran: no nesting -- W1 final fix (I-1)
    END; -- W1 final fix (I-1)
  END LOOP; -- W1 final fix (I-1)
  RETURN v_enrollment;
END;
$function$;

CREATE OR REPLACE FUNCTION public.pause_dating_mode(p_idempotency_key text)
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
  PERFORM private.dating_lock_setup(v_user_id); -- Spec 2 W1d: the shared lock order (setup, then same-gender: W1 final fix I-1); no device check (W1 B8 ruling)

  IF NOT public.claim_dating_idempotency('pause_dating_mode', p_idempotency_key) THEN
    SELECT * INTO v_enrollment
    FROM public.dating_enrollments
    WHERE user_id = v_user_id;
    RETURN v_enrollment;
  END IF;
  -- W1 final fix (I-1): pausing is never lost to a kill switch: a deadlock,
  -- W1 final fix a lock timeout or a serialization failure is retried (three
  -- W1 final fix attempts, each its own savepoint); the third is dating:busy.
  FOR v_try IN 1..3 LOOP -- W1 final fix (I-1)
    BEGIN -- W1 final fix (I-1)
      PERFORM 1 FROM public.dating_enrollments WHERE user_id = v_user_id FOR UPDATE; -- Spec 2 W1d: the enrolment row before the profile row

      UPDATE public.dating_profiles
      SET profile_state = 'paused',
          updated_at = now()
      WHERE user_id = v_user_id
        AND profile_state = 'active'; -- Spec 2 W1d

      UPDATE public.dating_enrollments
      SET state = 'paused',
          paused_at = now(),
          pause_reason = 'user', -- Spec 2 W1d
          updated_at = now()
      WHERE user_id = v_user_id
        AND state IN ('active', 'profile_draft') -- Spec 2 W1d: an already-paused enrolment keeps its first reason
      RETURNING * INTO v_enrollment;
      IF FOUND THEN PERFORM private.bump_metric_internal('dating.pause'); END IF; -- Spec 2 W1d
      EXIT; -- W1 final fix (I-1)
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- W1 final fix (I-1)
      IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- W1 final fix (N-M3): an inner retry already ran: no nesting -- W1 final fix (I-1): never the raw DETAIL
    END; -- W1 final fix (I-1)
  END LOOP; -- W1 final fix (I-1)

  SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id = v_user_id; -- Spec 2 W1d
  RETURN v_enrollment;
END;
$function$;

-- §3.8 "Resume Dating": eligibility, a complete profile and the name,
-- nothing more (Fable L3).
CREATE OR REPLACE FUNCTION public.resume_dating_mode(p_idempotency_key text)
RETURNS public.dating_enrollments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
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
  IF public.dating_eligibility(v_user_id, 'setup') IS DISTINCT FROM 'eligible' THEN -- NULL refuses
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
$fn$;

DROP FUNCTION IF EXISTS public.exit_dating_mode(text);
CREATE OR REPLACE FUNCTION public.exit_dating_mode(p_idempotency_key text, p_keep_never_introduce boolean DEFAULT false)
RETURNS public.dating_enrollments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- No device check: leaving deletes the person's own data (W1 B8 ruling).
  PERFORM private.dating_lock_setup(v_user_id); -- the shared lock order (setup first)
  IF NOT public.claim_dating_idempotency('exit_dating_mode', p_idempotency_key) THEN
    SELECT * INTO v_enrollment FROM public.dating_enrollments AS e WHERE e.user_id = v_user_id;
    RETURN v_enrollment;
  END IF;
  -- The hard delete also writes "when you left": every standing consent
  -- withdrawn, on the server's clock (fix round 1, I-1).
  PERFORM private.dating_exit_internal(v_user_id, coalesce(p_keep_never_introduce, false));
  SELECT * INTO v_enrollment FROM public.dating_enrollments AS e WHERE e.user_id = v_user_id;
  RETURN v_enrollment;
END;
$fn$;

DROP FUNCTION IF EXISTS public.delete_dating_profile(text);
-- The checkbox column goes now that its two readers are re-created above.
ALTER TABLE public.dating_enrollments DROP COLUMN IF EXISTS adults_only_confirmed_at;

CREATE OR REPLACE FUNCTION public.pause_dating_for_relationship_user(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE -- W1 final fix (I-1)
  v_try integer; -- W1 final fix (I-1)
BEGIN
  PERFORM private.dating_lock_setup(p_user_id); -- W1 final fix (I-1): the shared lock order (setup, then same-gender)
  FOR v_try IN 1..3 LOOP -- W1 final fix (I-1): a lock conflict is retried (each attempt its own savepoint)
    BEGIN -- W1 final fix (I-1)
      PERFORM 1 FROM public.dating_enrollments WHERE user_id = p_user_id FOR UPDATE; -- Spec 2 W1d: the enrolment row before the profile row
      UPDATE public.dating_profiles
      SET profile_state = 'paused',
          updated_at = now()
      WHERE user_id = p_user_id
        AND profile_state = 'active';

      UPDATE public.dating_enrollments
      SET state = CASE
            WHEN state = 'suspended' THEN state
            ELSE 'paused'
          END,
          paused_at = COALESCE(paused_at, now()),
          pause_reason = CASE WHEN state = 'suspended' THEN pause_reason ELSE 'relationship' END, -- Spec 2 W1d
          updated_at = now()
      WHERE user_id = p_user_id
        AND state IN ('active', 'profile_draft', 'eligible_to_opt_in');

      PERFORM public.invalidate_dating_for_user(p_user_id, 'relationship_guard');
      EXIT; -- W1 final fix (I-1)
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- W1 final fix (I-1)
      IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- W1 final fix (N-M3): an inner retry already ran: no nesting -- W1 final fix (I-1)
    END; -- W1 final fix (I-1)
  END LOOP; -- W1 final fix (I-1)
END;
$function$;

-- §6.3, I-11, R19: a parked account leaves everyone's Today at once.
CREATE OR REPLACE FUNCTION public.dating_on_account_parked()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_try integer; -- W1 final fix (I-1)
BEGIN
  IF OLD.phone_released_at IS NOT NULL OR NEW.phone_released_at IS NULL THEN
    RETURN NULL;
  END IF;
  -- W1 final fix (I-1): the shared lock order (setup, then same-gender),
  -- then up to three attempts on a lock conflict before it gives up.
  FOR v_try IN 1..3 LOOP -- W1 final fix (I-1)
    BEGIN
      PERFORM private.dating_lock_setup(NEW.id); -- W1 final fix (I-1)
      UPDATE public.dating_enrollments AS e
         SET state = 'paused', pause_reason = 'account_parked', paused_at = coalesce(e.paused_at, now()),
             updated_at = now()
       WHERE e.user_id = NEW.id AND e.state IN ('active', 'profile_draft');
      UPDATE public.dating_profiles AS p SET profile_state = 'paused', updated_at = now()
       WHERE p.user_id = NEW.id AND p.profile_state = 'active';
      PERFORM public.invalidate_dating_for_user(NEW.id, 'account_parked');
      EXIT; -- W1 final fix (I-1)
    EXCEPTION WHEN OTHERS THEN
      CONTINUE WHEN v_try < 3 AND SQLSTATE IN ('40P01', '55P03', '40001') AND SQLERRM IS DISTINCT FROM 'dating:busy'; -- W1 final fix (I-1): retried (N-M3: not after an inner retry)
      -- Never raises (P-36): Spec 1's park (fresh start, dormancy, deletion)
      -- must not fail on Dating. A failure is counted for health (fix round
      -- 1, M-5), and readiness never counts a parked account, so nobody new is
      -- introduced to it either way; open introductions expire.
      PERFORM private.bump_metric_internal('dating.parked_pause.failed');
      RAISE WARNING 'dating_on_account_parked:%', SQLSTATE;
      EXIT; -- W1 final fix (I-1)
    END;
  END LOOP; -- W1 final fix (I-1)
  RETURN NULL;
END;
$fn$;
DROP TRIGGER IF EXISTS dating_on_account_parked ON public.users;
CREATE TRIGGER dating_on_account_parked
  AFTER UPDATE OF phone_released_at ON public.users
  FOR EACH ROW
  WHEN (OLD.phone_released_at IS NULL AND NEW.phone_released_at IS NOT NULL)
  EXECUTE FUNCTION public.dating_on_account_parked();

CREATE OR REPLACE FUNCTION public.run_dating_candidate_generation(p_partition_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_version text;
  v_config jsonb;
  v_window text := to_char(date_trunc('week', now()), 'IYYY-"W"IW');
  v_partition text := COALESCE(p_partition_key, 'all');
  v_run public.dating_generation_runs%ROWTYPE;
  v_seed text;
  v_user uuid;
  v_total int := 0;
  v_users int := 0;
  v_max_attempts int;
BEGIN
  IF NOT public.dating_flag_enabled('dating_candidate_generation') THEN
    RETURN jsonb_build_object('skipped', 'flag_disabled');
  END IF;
  IF private.dating_exclusion_key_mismatch() THEN -- Spec 2 W1a (I-5): no run under a different exclusion key, counted
    PERFORM private.bump_metric_internal('dating.exclusion_key.mismatch'); -- Spec 2 W1a
    RETURN jsonb_build_object('skipped', 'exclusion_key_mismatch'); -- Spec 2 W1a
  END IF; -- Spec 2 W1a
  -- Spec 2 W1d: no run without both keys (exclusions, blocks and the
  -- encrypted fields all depend on them).
  IF public.app_setting('dating_exclusion_key') IS NULL OR NOT private.dating_field_key_present() THEN -- Spec 2 W1d
    RETURN jsonb_build_object('skipped', 'missing_key'); -- Spec 2 W1d
  END IF; -- Spec 2 W1d
  IF private.dating_field_key_usable() IS NOT TRUE THEN -- Spec 2 W1d (batch-6 M-5): a replaced field key, counted
    PERFORM private.bump_metric_internal('dating.field_key.mismatch'); -- Spec 2 W1d
    RETURN jsonb_build_object('skipped', 'field_key_mismatch'); -- Spec 2 W1d
  END IF; -- Spec 2 W1d

  SELECT version, config INTO v_version, v_config
  FROM public.dating_algorithm_configs
  WHERE state = 'active'
  ORDER BY activated_at DESC
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('skipped', 'no_active_config');
  END IF;

  v_max_attempts := COALESCE((v_config->>'max_attempts')::int, 3);

  -- The seed is per (version, window, partition) and stored, so a rerun of
  -- the same partition shuffles identically -- replayability (§6.2).
  v_seed := encode(digest(v_version || v_window || v_partition, 'sha256'), 'hex');

  INSERT INTO public.dating_generation_runs
    (algorithm_version, cohort_window, state, seed, partition_key, attempts,
     started_at)
  VALUES (v_version, v_window, 'processing', v_seed, v_partition, 1, now())
  ON CONFLICT (algorithm_version, cohort_window, partition_key) DO UPDATE
    SET state = 'processing',
        attempts = public.dating_generation_runs.attempts + 1,
        started_at = now()
    WHERE public.dating_generation_runs.state IN ('pending', 'failed')
      AND public.dating_generation_runs.attempts < v_max_attempts
  RETURNING * INTO v_run;

  -- No row returned means the partition is already completed, already
  -- processing, or has exhausted its attempts. All three mean "not ours".
  IF v_run.id IS NULL THEN
    RETURN jsonb_build_object('skipped', 'partition_unavailable',
                              'partition', v_partition);
  END IF;

  BEGIN
    FOR v_user IN
      SELECT de.user_id
      FROM public.dating_enrollments de
      WHERE de.state = 'active'
        AND public.dating_candidate_is_current(de.user_id)
      ORDER BY de.user_id
      LIMIT COALESCE((v_config->>'batch_user_limit')::int, 500)
    LOOP
      PERFORM public.build_dating_feature_snapshot(v_user, v_version);
      v_users := v_users + 1;
    END LOOP;

    FOR v_user IN
      SELECT de.user_id
      FROM public.dating_enrollments de
      WHERE de.state = 'active'
        AND public.dating_candidate_is_current(de.user_id)
      ORDER BY de.user_id
      LIMIT COALESCE((v_config->>'batch_user_limit')::int, 500)
    LOOP
      v_total := v_total + public.generate_dating_candidates_for_user(
        v_user, v_version, v_window, v_seed);
    END LOOP;

    UPDATE public.dating_generation_runs
    SET state = 'completed', completed_at = now()
    WHERE id = v_run.id;
  EXCEPTION WHEN OTHERS THEN
    -- Exhausted attempts go to dead_letter rather than failed, so the
    -- health view's failed_generation_runs_24h surfaces them and no
    -- further tick picks them up.
    UPDATE public.dating_generation_runs
    SET state = CASE
          WHEN attempts >= v_max_attempts THEN 'dead_letter' ELSE 'failed' END,
        last_error_code = sqlstate,
        completed_at = now()
    WHERE id = v_run.id;
    RETURN jsonb_build_object('error', sqlstate, 'partition', v_partition);
  END;

  RETURN jsonb_build_object(
    'algorithm_version', v_version,
    'cohort_window', v_window,
    'partition', v_partition,
    'users_processed', v_users,
    'introductions_created', v_total
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_dating_operational_health()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
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
    -- Spec 2 W1d (B2 I-5, B5 M-4, B6 M-5): each key set and its stored
    -- Spec 2 W1d fingerprint equal (read only; never the counting mismatch()).
    'exclusion_key_fingerprint_ok',private.dating_exclusion_key_ready(), -- Spec 2 W1d
    'field_key_fingerprint_ok',private.dating_field_key_ready(), -- Spec 2 W1d
    'safety_counters_7d',(SELECT jsonb_object_agg(k.key, coalesce((SELECT sum(c.count) FROM public.metric_counters c -- Spec 2 W1d
                            WHERE c.key = k.key AND c.day >= (now() AT TIME ZONE 'utc')::date - 6), 0)) -- Spec 2 W1d
      FROM unnest(ARRAY['dating.deletion.uncarried', 'dating.exclusion_key.mismatch', 'dating.exclusion_key.unseeded', -- Spec 2 W1d
                        'dating.eligibility.key_not_ready', 'dating.field_key.mismatch', 'dating.field_key.missing', -- Spec 2 W1d
                        'dating.parked_pause.failed']) AS k(key)) -- Spec 2 W1d (fix round 1, M-5)
  );
$function$;

REVOKE ALL ON FUNCTION private.dating_exit_internal(uuid, boolean), public.dating_profile_complete(uuid),
  public.dating_on_account_parked(), public.dating_profile_ready(uuid), public.pause_dating_for_relationship_user(uuid),
  private.dating_field_key_fingerprint(), private.dating_field_key_ready(), private.dating_field_key_usable(),
  private.seed_dating_field_key_fingerprint(), private.dating_field_encrypt(jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_dating_consent(text, text, text, text, jsonb), public.activate_dating_profile(text),
  public.pause_dating_mode(text), public.resume_dating_mode(text), public.exit_dating_mode(text, boolean)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_consent(text, text, text, text, jsonb), public.activate_dating_profile(text),
  public.pause_dating_mode(text), public.resume_dating_mode(text), public.exit_dating_mode(text, boolean)
  TO authenticated;
REVOKE ALL ON FUNCTION public.run_dating_candidate_generation(text), public.get_dating_operational_health()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_dating_candidate_generation(text), public.get_dating_operational_health() TO service_role;

COMMIT;
