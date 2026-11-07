-- Spec 2 W2, migration 1 (spec §4.9 W2 #1, §2.1 gate 5 and "Where the
-- Healing predicates go", §4.10; I-4, I-14, A-9; R7; W1 B10 M-6):
--   * private.dating_gentle_wait_opens_at(p_user): the open date, the latest
--     ended_at + 30 days of a relationship of theirs that is 'ended' and
--     still inside its 30-day ending window (Spec 3a's own window predicate,
--     20261018100000); NULL when there is none (an archived space, by both
--     seals or a new relationship, is no wait). The window, not the status
--     alone, so the gate opens on the D0 date before the archive sweep runs.
--     Fix round 1 (owner ruling on I-1; gate erosion: no path may silently
--     shorten the wait): only two archives shorten it, both members' seals
--     (both still present) and, for the one left behind, the other
--     member's new relationship (A-9). A seal by the last member left (the
--     former partner deleted their account) archives as 'last_member_sealed'
--     and still waits; a member who moved on to a new relationship that
--     then ended keeps the first ending's wait; any other archive waits.
--     The window is counted in UTC (M-1). An archived row with no ended_at
--     waits from its archive time (later than the end, so never shorter);
--     an 'ended' row with no ended_at makes the person no candidate,
--     counted as dating.gentle_wait.undated (M-3).
--   * dating_eligibility re-created from its live body (20261106140000 with
--     its fix rounds) adding gate 5, 'gentle_wait', for the candidate scope
--     only (setup and activation go ahead during the wait).
--   * The Healing gate leaves its four remaining call sites (W1d already
--     moved activate_dating_profile): begin_dating_enrollment and the
--     candidate check go through dating_eligibility; the 15-minute gate cron
--     pauses on the person's own gates (2-4), never on the gentle wait, a
--     closed country or the feature switch, takes the shared lock order and
--     the bounded retry, and writes pause_reason 'gates' (W1 B10 M-6);
--     fix round 1 (M-4): each person's gates are read inside their own
--     block, so an error is counted (dating.gates.failed) and the run goes
--     on;
--     get_dating_eligibility() becomes the compatible shim (I-4) until W3a.
--     Then dating_healing_gates_hold is dropped.
--   * Healing no longer grants Dating (R7): a ready journey becomes
--     'completed'; submit_healing_readiness's message names no Dating date
--     and its is_eligible key now means "this check-in completed the
--     journey with a score above 70" (the result screen's success styling;
--     final review I-1); old 'eligible_for_dating_opt_in' rows become 'completed'
--     (the CHECK keeps the value) and eligible_for_dating_opt_in_at is
--     cleared.
-- Grants in 20261107120010_dating_v2_gentle_wait_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- Fix round 1 (I-1): a seal by the last member left is not both seals.
ALTER TABLE public.relationships DROP CONSTRAINT IF EXISTS relationships_chat_archived_reason_check;
ALTER TABLE public.relationships ADD CONSTRAINT relationships_chat_archived_reason_check
  CHECK (chat_archived_reason IS NULL OR chat_archived_reason IN ('partner_new_relationship', 'manual_end', 'window_closed',
                                                                  'both_sealed', 'last_member_sealed')) NOT VALID;
ALTER TABLE public.relationships VALIDATE CONSTRAINT relationships_chat_archived_reason_check;
-- A former partner who deleted their account counts as not sealed (the
-- seals go with the account, so 'both_sealed' with a member gone can't be
-- told apart from a lone seal); only rows still inside their window matter.
UPDATE public.relationships
   SET chat_archived_reason = 'last_member_sealed'
 WHERE status = 'archived' AND chat_archived_reason = 'both_sealed'
   AND (user_a IS NULL OR user_b IS NULL)
   AND coalesce(ended_at, chat_archived_at) > now() - interval '30 days';

CREATE OR REPLACE FUNCTION public.seal_my_side(p_relationship_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_rel public.relationships := public.relationship_lock_mine(p_relationship_id);
BEGIN
  IF v_rel.status <> 'ended' THEN
    RAISE EXCEPTION 'lifecycle:not_ended';
  END IF;
  INSERT INTO public.relationship_seals (relationship_id, user_id)
  VALUES (p_relationship_id, auth.uid())
  ON CONFLICT (relationship_id, user_id) DO NOTHING;
  IF NOT EXISTS (
    SELECT 1
    FROM (VALUES (v_rel.user_a), (v_rel.user_b)) AS m(uid)
    WHERE m.uid IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.relationship_seals s
        WHERE s.relationship_id = p_relationship_id AND s.user_id = m.uid
      )
  ) THEN
    PERFORM public.relationship_archive(p_relationship_id,
      CASE WHEN v_rel.user_a IS NULL OR v_rel.user_b IS NULL THEN 'last_member_sealed' ELSE 'both_sealed' END); -- Spec 2 W2 fix round 1 (I-1): a former partner who deleted their account has not sealed
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION private.dating_gentle_wait_opens_at(p_user uuid)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
SET "TimeZone" = 'UTC'
AS $fn$
  SELECT max(coalesce(r.ended_at, r.chat_archived_at)) + interval '30 days'
    FROM public.relationships AS r
   WHERE p_user IN (r.user_a, r.user_b)
     AND coalesce(r.ended_at, r.chat_archived_at) > now() - interval '30 days'
     AND (r.status = 'ended'
          OR (r.status = 'archived'
              AND r.chat_archived_reason IS DISTINCT FROM 'both_sealed'
              AND (r.chat_archived_reason IS DISTINCT FROM 'partner_new_relationship'
                   OR EXISTS (SELECT 1 FROM public.relationships AS n
                               WHERE n.id <> r.id
                                 AND p_user IN (n.user_a, n.user_b)
                                 AND greatest(n.invite_accepted_at, n.created_at) >= coalesce(r.ended_at, r.chat_archived_at)))));
$fn$;

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
        state=CASE WHEN public.dating_enrollments.state='suspended' THEN 'suspended' ELSE 'profile_draft' END,
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

CREATE OR REPLACE FUNCTION public.dating_candidate_is_current(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce(public.dating_eligibility(p_user_id) = 'eligible', false) -- Spec 2 W2: gates 1-6 (flag, standing, relationship, gentle wait, country) replace the flag, Healing, standing and relationship lines
    AND coalesce(public.dating_age_gate_holds(p_user_id), false) -- Spec 2 W2: NULL-safe
    AND EXISTS (
      SELECT 1 FROM public.dating_enrollments de
      WHERE de.user_id = p_user_id AND de.state = 'active'
    )
    AND coalesce(public.dating_profile_ready(p_user_id), false); -- Spec 2 W2: NULL-safe
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

CREATE OR REPLACE FUNCTION public.get_dating_eligibility()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_user_id uuid := auth.uid();
  v_reason text; -- Spec 2 W2
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('is_eligible',false,'reason','not_authenticated','message','Sign in to continue.');
  END IF;
  -- Spec 2 W2 (I-4): a compatible shim over dating_eligibility's setup scope
  -- Spec 2 W2 until W3a moves its two callers to get_dating_home and drops it.
  v_reason := public.dating_eligibility(v_user_id, 'setup'); -- Spec 2 W2
  IF v_reason IS NOT DISTINCT FROM 'feature_unavailable' THEN -- Spec 2 W2
    RETURN jsonb_build_object('is_eligible',false,'reason','feature_unavailable','message','Dating Mode is not available yet.');
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'relationship_active' THEN -- Spec 2 W2
    RETURN jsonb_build_object('is_eligible',false,'reason','relationship_active','message','Dating Mode stays unavailable while a relationship is pending or active.');
  END IF;
  IF v_reason IS DISTINCT FROM 'eligible' THEN -- Spec 2 W2: every other reason, and NULL
    RETURN jsonb_build_object('is_eligible',false,'reason','account_unavailable','message','Dating Mode is not available for this account.');
  END IF;
  RETURN jsonb_build_object(
    'is_eligible',true,
    'age_verification_complete',coalesce(public.dating_age_gate_holds(v_user_id), false), -- Spec 2 W2: NULL-safe
    'reason',NULL,
    'message','You can opt in to Dating Mode when you are ready.'
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.dating_healing_gates_hold(uuid);

-- W1 B10 M-6: the gate cron's pauses carry a reason.
ALTER TABLE public.dating_enrollments DROP CONSTRAINT IF EXISTS dating_enrollments_pause_reason_check;
ALTER TABLE public.dating_enrollments ADD CONSTRAINT dating_enrollments_pause_reason_check
  CHECK (pause_reason IS NULL OR pause_reason IN ('user', 'relationship', 'path_change', 'same_gender_switch',
                                                  'away', 'account_parked', 'gates'));

CREATE OR REPLACE FUNCTION public._healing_refresh_status(p_journey_id uuid)
 RETURNS healing_journeys
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_journey public.healing_journeys%ROWTYPE;
  v_ready boolean;
BEGIN
  SELECT * INTO v_journey
  FROM public.healing_journeys
  WHERE id = p_journey_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'journey_not_found' USING ERRCODE = '22023';
  END IF;

  v_ready := v_journey.reflection_completed_at IS NOT NULL
    AND v_journey.post_mortem_completed_at IS NOT NULL
    AND v_journey.pattern_awareness_completed_at IS NOT NULL
    AND v_journey.portrait_completed_at IS NOT NULL
    AND v_journey.readiness_stage_completed_at IS NOT NULL;

  IF v_ready THEN
    -- Spec 2 W2 (§2.1, R7): Healing never grants Dating; a ready journey is
    -- Spec 2 W2 complete, whatever the check-in score.
    UPDATE public.healing_journeys
    SET status = 'completed', -- Spec 2 W2
        completed_at = COALESCE(completed_at, now()),
        eligible_for_dating_opt_in_at = NULL -- Spec 2 W2
    WHERE id = p_journey_id
    RETURNING * INTO v_journey;
  END IF;

  RETURN v_journey;
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_healing_readiness(p_journey_id uuid, p_answers jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_journey public.healing_journeys%ROWTYPE;
  v_latest public.healing_readiness_attempts%ROWTYPE;
  v_score integer;
  v_attempt_id uuid;
  v_updated public.healing_journeys%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_journey
  FROM public.healing_journeys
  WHERE id = p_journey_id
    AND user_id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'journey_not_found' USING ERRCODE = '22023';
  END IF;
  IF v_journey.portrait_completed_at IS NULL THEN
    RAISE EXCEPTION 'portrait_not_complete' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_latest
  FROM public.healing_readiness_attempts
  WHERE journey_id = p_journey_id
  ORDER BY submitted_at DESC
  LIMIT 1;

  IF FOUND AND now() < (v_latest.submitted_at + interval '7 days') THEN
    RAISE EXCEPTION 'readiness_cooldown_active' USING ERRCODE = '22023';
  END IF;

  v_score := public._healing_score_from_answers(p_answers);

  INSERT INTO public.healing_readiness_attempts (
    journey_id,
    user_id,
    answers,
    score,
    scoring_version
  ) VALUES (
    p_journey_id,
    v_user_id,
    p_answers,
    v_score,
    'healing_readiness_v1_1'
  )
  RETURNING id INTO v_attempt_id;

  UPDATE public.healing_journeys
  SET readiness_stage_completed_at = COALESCE(readiness_stage_completed_at, now()),
      current_stage = 5
  WHERE id = p_journey_id;

  v_updated := public._healing_refresh_status(p_journey_id);

  RETURN jsonb_build_object(
    'score', v_score,
    'is_eligible', coalesce(v_updated.status = 'completed' AND v_score > 70, false), -- Spec 2 W2 (final review I-1): the result screen's success styling: a completed journey AND a score above 70 (no Dating outcome); a low score never gets the success ring
    'attempt_id', v_attempt_id,
    'message', CASE
      WHEN v_score <= 70 THEN 'Your answers suggest there may be more you want to explore. Go at your own pace.'
      ELSE 'Your check-in is complete. Healing stays here whenever you want it.' -- Spec 2 W2: no Dating date
    END
  );
END;
$function$;

-- R7: no journey keeps a Dating outcome.
UPDATE public.healing_journeys
   SET status = CASE WHEN status = 'eligible_for_dating_opt_in' THEN 'completed' ELSE status END,
       eligible_for_dating_opt_in_at = NULL
 WHERE status = 'eligible_for_dating_opt_in' OR eligible_for_dating_opt_in_at IS NOT NULL;

REVOKE ALL ON FUNCTION private.dating_gentle_wait_opens_at(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_eligibility(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_candidate_is_current(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.enforce_dating_lifecycle_gates() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
