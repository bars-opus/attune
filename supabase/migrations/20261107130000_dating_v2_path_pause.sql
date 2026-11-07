-- Spec 2 W2, migration 2 (spec §4.9 W2 #1, §4.10 users triggers, R13;
-- Spec 1 D18; I-5): the users.path trigger dating_pause_on_path_change.
--   * AFTER UPDATE OF path: a change from Dating to anything but
--     Relationship pauses an active or draft enrolment with pause_reason
--     'path_change'. A change to Relationship is left to Spec 1's
--     set_user_path_internal, which pauses with 'relationship' (one writer
--     per reason); an enrolment already paused keeps its first reason.
--   * It takes the shared lock order (private.dating_lock_setup: setup,
--     then same-gender, then the enrolment row before the profile row) and
--     the bounded retry on 40P01/55P03/40001, like the parked trigger, and
--     never raises (R13): a failure is counted (dating.path_pause.failed),
--     shown in health, and the path change still goes through.
--   * get_dating_operational_health() re-created from its live body
--     (20261106200000 with the W1 final fixes) with two keys added to
--     safety_counters_7d: dating.path_pause.failed and dating.gates.busy
--     (migration 1's gate cron).
--   * (Task 3 carries) health also shows dating.gates.failed (the gate
--     cron's per-person failures) and dating.gentle_wait.undated (an
--     ending with no date), both counted by migration 1 and shown nowhere.
--   * (Task 3 carry: a pause holds until its own way out) three functions
--     re-created from their live bodies (20261107120000 for begin): a
--     begin_dating_enrollment re-tap keeps a paused enrolment paused (it
--     reset a kill-switch or path pause to profile_draft);
--     resume_dating_mode and activate_dating_profile refuse while the
--     person's chosen path is Just for me or Relationship (they lifted a
--     path or relationship pause off the Dating path). Lines marked
--     "-- Spec 2 W2"; grants unchanged, restated in the twin.
--   * (Task 3 fix round 1; batch-2 review C-1, I-1, I-2, M-3)
--     - The pause itself is private.dating_apply_path_pause(p_user), the
--       one writer of 'path_change': it pauses an active or draft enrolment
--       whose person's chosen path is neither Dating nor Relationship (NULL,
--       never chosen, is no signal), in the shared lock order, retrying a
--       lock conflict, under its own 1s lock_timeout.
--     - The trigger calls it for any change to such a path, whatever the
--       old value (coordinator ruling on I-2), under its own 1s
--       lock_timeout, catching WHEN OTHERS OR query_canceled: a statement
--       timeout while it waits behind a running kill switch is counted and
--       the path change completes (R13; the W9d pattern).
--     - enforce_dating_lifecycle_gates() re-created from its live body
--       (20261107120000) with a sweep before the gates: whoever is still
--       active or a draft on such a path is paused by the helper, per row,
--       counted (dating.path_pause.swept / .failed), so a failed trigger
--       is retried within 15 minutes.
--     - dating_eligibility() re-created from its live body (20261107120000):
--       a candidate whose chosen path is not Dating is account_unavailable,
--       so nobody is introduced before the sweep lands (candidates only:
--       setup's answer drives the cron's 'gates' pause).
--     - resume and activation refuse off the path with 'path_not_dating'.
--   * (W2 final review M-1, M-2, M-3) begin refuses off the path too
--     ('path_not_dating', after the device check, before the rate limit);
--     activation checks the path right after the device, as resume does;
--     a 'gates' pause resumes only while the age gate holds.
--     - health also shows dating.path_pause.swept.
-- set_user_path_internal is not edited (R13).
-- Grants in 20261107130010_dating_v2_path_pause_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- The one writer of pause_reason 'path_change' (I-5): true when it paused.
-- Raises on a failure (each caller catches and counts it).
CREATE OR REPLACE FUNCTION private.dating_apply_path_pause(p_user uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '1s'
AS $fn$
DECLARE
  v_try integer;
  v_paused boolean;
BEGIN
  IF p_user IS NULL THEN
    RETURN false;
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(p_user);
      PERFORM 1 FROM public.dating_enrollments AS e WHERE e.user_id = p_user FOR UPDATE; -- the enrolment row before the profile row
      -- Read after the locks: only a chosen path other than Dating or
      -- Relationship pauses (NULL, never chosen, is no signal).
      UPDATE public.dating_enrollments AS e
         SET state = 'paused', pause_reason = 'path_change', paused_at = coalesce(e.paused_at, now()),
             updated_at = now()
       WHERE e.user_id = p_user AND e.state IN ('active', 'profile_draft')
         AND EXISTS (SELECT 1 FROM public.users AS u
                      WHERE u.id = p_user AND u.path IS NOT NULL AND u.path NOT IN ('dating', 'relationship'));
      v_paused := FOUND;
      IF v_paused THEN
        UPDATE public.dating_profiles AS p SET profile_state = 'paused', updated_at = now()
         WHERE p.user_id = p_user AND p.profile_state = 'active';
        PERFORM public.invalidate_dating_for_user(p_user, 'path_change');
      END IF;
      RETURN v_paused;
    EXCEPTION WHEN OTHERS THEN
      CONTINUE WHEN v_try < 3 AND SQLSTATE IN ('40P01', '55P03', '40001') AND SQLERRM IS DISTINCT FROM 'dating:busy';
      RAISE;
    END;
  END LOOP;
  RETURN false;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.dating_pause_on_path_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '1s' -- 3 tries x 1s stays inside Auth's 8s statement timeout
AS $fn$
BEGIN
  -- A chosen path other than Dating or Relationship, whatever the old value
  -- (coordinator ruling, batch-2 review I-2). A change to Relationship is
  -- Spec 1's set_user_path_internal's to pause (D18, I-5); NULL never pauses.
  IF NEW.path IS NULL OR NEW.path IN ('dating', 'relationship') THEN
    RETURN NULL;
  END IF;
  BEGIN
    PERFORM private.dating_apply_path_pause(NEW.id);
  EXCEPTION WHEN OTHERS OR query_canceled THEN
    -- Never raises (R13), a statement timeout included: the path change
    -- goes through; the failure is counted for health and the gate cron's
    -- sweep pauses the person within 15 minutes (ineligible meanwhile).
    PERFORM private.bump_metric_internal('dating.path_pause.failed');
    RAISE WARNING 'dating_pause_on_path_change:%', SQLSTATE;
  END;
  RETURN NULL;
END;
$fn$;

CREATE OR REPLACE TRIGGER dating_pause_on_path_change
  AFTER UPDATE OF path ON public.users
  FOR EACH ROW
  WHEN (OLD.path IS DISTINCT FROM NEW.path)
  EXECUTE FUNCTION public.dating_pause_on_path_change();

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
                        'dating.parked_pause.failed', -- Spec 2 W1d (fix round 1, M-5)
                        'dating.path_pause.failed', 'dating.gates.busy', -- Spec 2 W2
                        'dating.gates.failed', 'dating.gentle_wait.undated', -- Spec 2 W2 (Task 3 carry: W2 batch 1 fix round 1, M-4 and M-3)
                        'dating.path_pause.swept', -- Spec 2 W2 (Task 3 fix round 1, I-1)
                        'dating.kill_switch.pending', 'dating.kill_switch.unreadable', -- Spec 2 W1d (migration 11)
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

-- Spec 2 W2 (Task 3 carry): a pause holds until its own way out.
CREATE OR REPLACE FUNCTION public.begin_dating_enrollment(p_terms_version text, p_idempotency_key text)
 RETURNS dating_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
  v_try integer; -- Spec 2 W2
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  PERFORM private.dating_lock_setup(v_user_id); -- Spec 2 W2: the shared lock order (setup, then same-gender) before any row
  IF private.dating_exclusion_key_mismatch() THEN -- Spec 2 W1a (I-5): a different exclusion key refuses quietly, counted
    PERFORM private.bump_metric_internal('dating.exclusion_key.mismatch'); -- Spec 2 W1a
    SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id=v_user_id; -- Spec 2 W1a
    RETURN v_enrollment; -- Spec 2 W1a
  END IF; -- Spec 2 W1a
  IF public.dating_require_trusted_device() IS NOT TRUE THEN RAISE EXCEPTION 'reverify_device' USING ERRCODE='22023'; END IF; -- Spec 2 W2
  -- Spec 2 W2 (final review M-1): no setup off the Dating path (a draft begun
  -- Spec 2 W2 on Just for me would be swept into a false path pause).
  IF coalesce((SELECT u.path FROM public.users AS u WHERE u.id = v_user_id) IN ('just_me', 'relationship'), false) THEN -- Spec 2 W2
    RAISE EXCEPTION 'path_not_dating' USING ERRCODE = '22023'; -- Spec 2 W2 (final review M-1): "choose Dating to begin"
  END IF; -- Spec 2 W2
  PERFORM public.check_dating_rate_limit('begin_enrollment',5,interval '1 day');
  IF public.dating_eligibility(v_user_id, 'setup') IS DISTINCT FROM 'eligible' THEN -- Spec 2 W2: gates 1-4 and 6 (no Healing gate; the gentle wait never blocks setup; NULL refuses)
    RAISE EXCEPTION 'not_eligible' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.dating_consent_events dce
    WHERE dce.user_id=v_user_id AND dce.purpose='dating_terms'
      AND dce.action='granted' AND dce.policy_version=p_terms_version
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_consent_events later
        WHERE later.user_id=dce.user_id AND later.purpose=dce.purpose
          AND later.occurred_at>dce.occurred_at AND later.action='withdrawn'
      )
  ) THEN RAISE EXCEPTION 'terms_consent_required' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.dating_consent_events dce
    WHERE dce.user_id=v_user_id AND dce.purpose='dating_opt_in'
      AND dce.action='granted' AND dce.policy_version=p_terms_version
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_consent_events later
        WHERE later.user_id=dce.user_id AND later.purpose=dce.purpose
          AND later.occurred_at>dce.occurred_at AND later.action='withdrawn'
      )
  ) THEN RAISE EXCEPTION 'dating_opt_in_required' USING ERRCODE='22023'; END IF;
  IF NOT public.claim_dating_idempotency('begin_dating_enrollment',p_idempotency_key) THEN
    SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id=v_user_id;
    RETURN v_enrollment;
  END IF;
  FOR v_try IN 1..3 LOOP -- Spec 2 W2: a lock conflict is retried (each attempt its own savepoint)
    BEGIN -- Spec 2 W2
      INSERT INTO public.dating_enrollments(user_id,state,terms_version,opted_in_at)
      VALUES(v_user_id,'profile_draft',p_terms_version,now())
      ON CONFLICT(user_id) DO UPDATE SET
        state=CASE WHEN public.dating_enrollments.state IN ('suspended','paused') THEN public.dating_enrollments.state ELSE 'profile_draft' END, -- Spec 2 W2 (Task 3): a re-tap never lifts a pause or a suspension
        terms_version=EXCLUDED.terms_version,opted_in_at=now(),exited_at=NULL,updated_at=now()
      RETURNING * INTO v_enrollment;
      EXIT; -- Spec 2 W2
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W2
      IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- Spec 2 W2
    END; -- Spec 2 W2
  END LOOP; -- Spec 2 W2
  RETURN v_enrollment;
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
     OR (v_enrollment.pause_reason IS NOT DISTINCT FROM 'gates' -- Spec 2 W2 (final review M-3): the cron's pause holds while its cause stands
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
  -- Spec 2 W2 (Task 3): never switched back on off the Dating path: whoever
  -- Spec 2 W2 chose Just for me or Relationship stays paused (each pause has
  -- Spec 2 W2 its one way out); a never-chosen path (NULL) keeps today's rule.
  IF coalesce((SELECT u.path FROM public.users AS u WHERE u.id = v_user_id) IN ('just_me', 'relationship'), false) THEN -- Spec 2 W2
    RAISE EXCEPTION 'path_not_dating' USING ERRCODE = '22023'; -- Spec 2 W2 (fix round 1, M-3; final review M-2: before the rate limit and the gates, as resume): "choose Dating to resume"
  END IF; -- Spec 2 W2
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

-- Spec 2 W2 (Task 3 fix round 1, I-1): candidates off the Dating path; the path sweep.
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
    RETURN CASE WHEN p_scope = 'setup' THEN 'eligible' ELSE 'country_closed' END;
  END IF;
  v_config := public.dating_country_config(v_country);
  IF v_config IS NULL OR v_config.dating_enabled IS NOT TRUE THEN
    RETURN 'country_closed';
  END IF;
  IF v_config.open_regions IS NOT NULL
     AND (v_region IS NULL OR (v_region = ANY (v_config.open_regions)) IS NOT TRUE) THEN
    RETURN CASE WHEN v_region IS NULL AND p_scope = 'setup' THEN 'eligible' ELSE 'region_closed' END;
  END IF;
  RETURN 'eligible';
END;
$function$;

CREATE OR REPLACE FUNCTION public.enforce_dating_lifecycle_gates()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_user_id uuid; v_count bigint := 0;
  v_try integer; -- Spec 2 W2
BEGIN
  -- Spec 2 W2 (Task 3 fix round 1, I-1): the path sweep, before the gates.
  -- Spec 2 W2 Whoever is still active, or a draft, on a chosen path other than
  -- Spec 2 W2 Dating or Relationship (a path trigger that failed) is paused with
  -- Spec 2 W2 path_change by the one helper; each person in their own block,
  -- Spec 2 W2 counted; a failure is left for the next run.
  FOR v_user_id IN -- Spec 2 W2
    SELECT e.user_id FROM public.dating_enrollments AS e JOIN public.users AS u ON u.id = e.user_id -- Spec 2 W2
     WHERE e.state IN ('active', 'profile_draft') AND u.path IS NOT NULL AND u.path NOT IN ('dating', 'relationship') -- Spec 2 W2
     ORDER BY e.user_id -- Spec 2 W2
  LOOP -- Spec 2 W2
    BEGIN -- Spec 2 W2
      IF private.dating_apply_path_pause(v_user_id) THEN -- Spec 2 W2
        PERFORM private.bump_metric_internal('dating.path_pause.swept'); -- Spec 2 W2
        v_count := v_count + 1; -- Spec 2 W2
      END IF; -- Spec 2 W2
    EXCEPTION WHEN OTHERS THEN -- Spec 2 W2
      PERFORM private.bump_metric_internal('dating.path_pause.failed'); -- Spec 2 W2
    END; -- Spec 2 W2
  END LOOP; -- Spec 2 W2
  FOR v_user_id IN
    SELECT de.user_id FROM public.dating_enrollments de
    WHERE de.state='active'
    ORDER BY de.user_id -- Spec 2 W2 fix round 1 (M-4): the gates are read per person below; one stable order
  LOOP
    BEGIN -- Spec 2 W2: one person's lock conflict or error never stops the run
      IF public.dating_age_gate_holds(v_user_id) IS NOT TRUE -- Spec 2 W2: NULL-safe
         OR public.dating_account_in_good_standing(v_user_id) IS NOT TRUE -- Spec 2 W2: NULL-safe
         OR public.dating_eligibility(v_user_id, 'setup') IN ('account_unavailable', 'relationship_active') -- Spec 2 W2: the person's own gates 2-4 replace the Healing gate; the gentle wait, a closed country and the feature switch never pause
         OR public.dating_has_relationship(v_user_id) IS NOT FALSE -- Spec 2 W2: NULL-safe
         OR public.dating_profile_ready(v_user_id) IS NOT TRUE THEN -- Spec 2 W2: NULL-safe
        PERFORM private.dating_lock_setup(v_user_id); -- Spec 2 W2: the shared lock order (setup, then same-gender)
        FOR v_try IN 1..3 LOOP -- Spec 2 W2: a lock conflict is retried (each attempt its own savepoint)
          BEGIN -- Spec 2 W2
            UPDATE public.dating_enrollments SET state='paused',paused_at=COALESCE(paused_at,now()),
              pause_reason=COALESCE(pause_reason,'gates'),updated_at=now() -- Spec 2 W2 (W1 B10 M-6): a reason for every pause
              WHERE user_id=v_user_id AND state='active';
            IF FOUND THEN -- Spec 2 W2: counted and invalidated only when it paused
              UPDATE public.dating_profiles SET profile_state='paused',updated_at=now()
                WHERE user_id=v_user_id AND profile_state='active';
              PERFORM public.invalidate_dating_for_user(v_user_id,'scheduled_gate_revalidation');
              v_count := v_count + 1;
            END IF; -- Spec 2 W2
            EXIT; -- Spec 2 W2
          EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W2
            IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- Spec 2 W2
          END; -- Spec 2 W2
        END LOOP; -- Spec 2 W2
      END IF; -- Spec 2 W2
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W2
      PERFORM private.bump_metric_internal('dating.gates.busy'); -- Spec 2 W2: left for the next run, counted
    WHEN OTHERS THEN -- Spec 2 W2 fix round 1 (M-4): one bad row is counted and skipped
      PERFORM private.bump_metric_internal('dating.gates.failed'); -- Spec 2 W2 fix round 1
    END; -- Spec 2 W2
  END LOOP;
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.dating_pause_on_path_change() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_apply_path_pause(uuid) FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
