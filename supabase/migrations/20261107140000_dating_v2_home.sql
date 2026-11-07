-- Spec 2 W2, migration 3 (spec §3.1, §3.2 D0, §4.3, §4.4 Home and Gentle
-- wait, §6.9 gentle-wait keys; I-4, A-10):
--   * dating_gentle_wait_reflections: the person's own three answers (each
--     at most 500 characters, optional), saved_at, and seen_at (when D0 was
--     last opened during a wait, for the two §6.9 counters). RLS on, no API
--     role (the service role included); exit deletes the row (W1d's
--     dating_exit_internal already names this table), account deletion
--     cascades.
--   * save_gentle_wait_reflection(p_answers): pre-validated (an object with
--     only q1-q3, each a string or null, at most 500 characters; anything
--     else is {ok:false, reason:'invalid', field}); saving answers needs the
--     setup guard (lock, trusted device, setup eligibility); clearing them
--     (all blank) needs only the lock (exposure-reducing, never gated).
--   * get_my_gentle_wait_reflection(): own answers plus the wait's dates;
--     while the person is in the wait it records seen_at once per ending
--     and counts dating.gentle_wait.seen.
--   * get_dating_home() v1: the Dating section's one read, {state, ...only
--     what that state needs}: feature_unavailable / country_closed
--     {country}, region_closed {country, region, open_regions},
--     reverify_device, restricted / hold / age_review / unavailable (the
--     person's own standing, never a report or a block), gentle_wait
--     {ended_at, opens_at, next_step}, not_started, setup_in_progress
--     {next_step}, paused {pause_reason}, cool_off {first_drop_at}, active.
--     W4, W5, W7 and W8 re-create it from its live body to add verifying,
--     ready and Today, the restriction's category and away.
--   * Spec 2 W1a's private.dating_carry_on_auth_user_delete() re-created
--     from its live body: an account deleted within 7 days of opening D0
--     counts dating.gentle_wait.account_deleted_7d (the evasion proxy).
--   * (Task 4 carries) Every date the home and D0 show is computed in UTC,
--     so a summer-time change moves none of them; get_dating_home answers
--     'unavailable' for dating:field_decrypt_failed / field_key_missing
--     (any other error still raises); opening D0 retries its one write
--     (a busy mark is skipped, never the read); the reflections table's
--     columns are revoked too; get_dating_operational_health() re-created
--     from its live body shows the two gentle-wait counters.
--   * (Task 4 fix round 1, review I-1/I-2/M-6) Clearing takes no advisory
--     lock and never raises behind a switch (busy, counted); opening D0
--     marks the view only under a free try-lock (else skipped, counted);
--     both RPCs carry lock_timeout = 1s; the decrypt handler counts.
--   * (W2 final review M-4) private.dating_gentle_wait_can_shorten(uuid):
--     get_my_gentle_wait_reflection() also returns can_shorten, so D0 says
--     "If you both close it sooner" only when closing it together still can.
-- Grants in 20261107140010_dating_v2_home_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.dating_gentle_wait_reflections (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  answers jsonb,
  saved_at timestamptz,
  seen_at timestamptz,
  CONSTRAINT dating_gentle_wait_reflections_answers_check CHECK (
    answers IS NULL OR (
      jsonb_typeof(answers) = 'object'
      AND answers - ARRAY['q1', 'q2', 'q3'] = '{}'::jsonb
      AND coalesce(jsonb_typeof(answers -> 'q1'), 'string') = 'string'
      AND coalesce(jsonb_typeof(answers -> 'q2'), 'string') = 'string'
      AND coalesce(jsonb_typeof(answers -> 'q3'), 'string') = 'string'
      AND coalesce(char_length(answers ->> 'q1'), 0) <= 500
      AND coalesce(char_length(answers ->> 'q2'), 0) <= 500
      AND coalesce(char_length(answers ->> 'q3'), 0) <= 500))
);
ALTER TABLE public.dating_gentle_wait_reflections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.dating_gentle_wait_reflections FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL (user_id, answers, saved_at, seen_at) ON TABLE public.dating_gentle_wait_reflections
  FROM PUBLIC, anon, authenticated, service_role;

-- The first setup step not yet done, in §3.14's step names ('how' when
-- nothing is started). Faith (D8) is optional and never blocks a resume.
CREATE OR REPLACE FUNCTION private.dating_next_step(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT CASE
    WHEN p.user_id IS NULL
         AND (e.state IS NULL OR e.state IN ('ineligible', 'eligible_to_opt_in', 'exited')) THEN 'how'
    WHEN p.intention IS NULL OR p.not_married_attested_at IS NULL THEN 'looking-for'
    WHEN p.country_code IS NULL OR p.region_code IS NULL THEN 'where'
    WHEN e.state IS NULL OR e.state NOT IN ('profile_draft', 'active', 'paused')
         OR NOT (private.dating_consent_granted(p_user, 'dating_terms')
                 AND private.dating_consent_granted(p_user, 'dating_opt_in')
                 AND private.dating_consent_granted(p_user, 'special_category_profile')) THEN 'privacy'
    WHEN s.identity_enc IS NULL THEN 'you'
    WHEN s.seeking_enc IS NULL THEN 'meet'
    WHEN p.children_have IS NULL OR p.children_want IS NULL THEN 'children'
    WHEN (SELECT count(*) FROM public.dating_profile_photos AS f
           WHERE f.user_id = p_user AND f.moderation_state = 'approved') < 2 THEN 'photos'
    WHEN (SELECT count(*) FROM public.dating_prompts AS q
           WHERE q.user_id = p_user AND q.moderation_state = 'approved') < 2 THEN 'prompts'
    WHEN p.verification_state IS DISTINCT FROM 'verified'
         OR coalesce(public.dating_age_gate_holds(p_user), false) IS NOT TRUE THEN 'verify'
    ELSE 'preview'
  END
    FROM (SELECT p_user AS id) AS me
    LEFT JOIN public.dating_profiles AS p ON p.user_id = me.id
    LEFT JOIN public.dating_enrollments AS e ON e.user_id = me.id
    LEFT JOIN public.dating_profile_sensitive AS s ON s.user_id = me.id;
$fn$;

-- The person's own standing, for an account_unavailable answer: never a
-- report or a block (nothing tells a reported or blocked person anything).
CREATE OR REPLACE FUNCTION private.dating_unavailable_state(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                  WHERE r.user_id = p_user AND r.restriction_type = 'suspended' AND r.lifted_at IS NULL
                    AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()))
      OR EXISTS (SELECT 1 FROM public.enforcement_records AS er
                  WHERE er.scope = 'dating' AND er.phone_hmac = public.dating_phone_hmac_for_user(p_user)
                    AND (er.effect_until IS NULL OR er.effect_until > now()) AND er.purge_after > now())
      OR EXISTS (SELECT 1 FROM auth.users AS a
                  WHERE a.id = p_user AND a.banned_until > now()) THEN 'restricted'
    WHEN EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                  WHERE r.user_id = p_user AND r.restriction_type IN ('moderation_hold', 'under_review')
                    AND r.lifted_at IS NULL AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()))
      OR EXISTS (SELECT 1 FROM public.account_holds AS h
                  WHERE h.user_id = p_user AND h.kind = 'safety_review' AND h.resolved_at IS NULL) THEN 'hold'
    WHEN EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                  WHERE r.user_id = p_user AND r.restriction_type = 'age_review' AND r.lifted_at IS NULL
                    AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()))
      OR EXISTS (SELECT 1 FROM public.account_holds AS h
                  WHERE h.user_id = p_user AND h.kind = 'age_review' AND h.resolved_at IS NULL) THEN 'age_review'
    ELSE 'unavailable'
  END;
$fn$;

-- The first drop at or after p_after: the person's drop time (default
-- 19:00) in their Dating country's reference time zone (UTC without one).
CREATE OR REPLACE FUNCTION private.dating_first_drop_at(p_user uuid, p_after timestamptz)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_tz text;
  v_drop time;
  v_at timestamptz;
BEGIN
  SELECT coalesce((public.dating_country_config(p.country_code::text)).reference_tz, 'UTC')
    INTO v_tz FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  v_tz := coalesce(v_tz, 'UTC');
  SELECT t.drop_time INTO v_drop FROM public.dating_settings AS t WHERE t.user_id = p_user;
  v_drop := coalesce(v_drop, time '19:00');
  v_at := ((p_after AT TIME ZONE v_tz)::date + v_drop) AT TIME ZONE v_tz;
  IF v_at < p_after THEN
    v_at := (((p_after AT TIME ZONE v_tz)::date + 1) + v_drop) AT TIME ZONE v_tz;
  END IF;
  RETURN v_at;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.get_dating_home()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
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
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_reason := public.dating_eligibility(v_user, 'setup');
  SELECT p.country_code::text, p.region_code INTO v_country, v_region
    FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_reason IS NOT DISTINCT FROM 'feature_unavailable' THEN
    RETURN jsonb_build_object('state', 'feature_unavailable', 'country',
      coalesce(v_country, private.dating_phone_country((SELECT a.phone FROM auth.users AS a WHERE a.id = v_user))));
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('state', 'reverify_device');
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'account_unavailable' THEN
    RETURN jsonb_build_object('state', private.dating_unavailable_state(v_user));
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'country_closed' THEN
    RETURN jsonb_build_object('state', 'country_closed', 'country', v_country);
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'region_closed' THEN
    v_config := public.dating_country_config(v_country);
    RETURN jsonb_build_object('state', 'region_closed', 'country', v_country, 'region', v_region,
      'open_regions', to_jsonb(coalesce(v_config.open_regions, ARRAY[]::text[])));
  END IF;
  SELECT * INTO v_enrol FROM public.dating_enrollments AS e WHERE e.user_id = v_user;
  IF v_reason IS NOT DISTINCT FROM 'relationship_active' THEN
    RETURN CASE WHEN v_enrol.state = 'paused'
                THEN jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason)
                ELSE jsonb_build_object('state', 'unavailable') END;
  END IF;
  IF v_reason IS DISTINCT FROM 'eligible' THEN
    RETURN jsonb_build_object('state', 'unavailable'); -- an unknown or NULL reason fails closed
  END IF;
  IF v_enrol.state = 'suspended' THEN
    RETURN jsonb_build_object('state', 'unavailable'); -- suspended without a live restriction (W7a routes it)
  END IF;
  IF v_enrol.state = 'paused' THEN
    RETURN jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason);
  END IF;
  v_opens := private.dating_gentle_wait_opens_at(v_user);
  IF v_enrol.state = 'active' THEN
    -- The first drop is the later of the open date and the 72 h cool-off
    -- from account creation (§2.1, §2.8).
    v_after := greatest(coalesce(v_opens, '-infinity'::timestamptz),
                        (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours');
    IF v_after > now() THEN
      RETURN jsonb_build_object('state', 'cool_off', 'first_drop_at', private.dating_first_drop_at(v_user, v_after));
    END IF;
    RETURN jsonb_build_object('state', 'active');
  END IF;
  IF v_opens IS NOT NULL THEN
    RETURN jsonb_build_object('state', 'gentle_wait', 'ended_at', (v_opens AT TIME ZONE 'UTC' - interval '30 days') AT TIME ZONE 'UTC', 'opens_at', v_opens, -- in UTC (a DST change moves nothing)
                              'next_step', private.dating_next_step(v_user));
  END IF;
  IF private.dating_next_step(v_user) IS NOT DISTINCT FROM 'how' THEN
    RETURN jsonb_build_object('state', 'not_started');
  END IF;
  RETURN jsonb_build_object('state', 'setup_in_progress', 'next_step', private.dating_next_step(v_user));
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
    RETURN jsonb_build_object('state', 'unavailable');
  END IF;
  RAISE;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.save_gentle_wait_reflection(p_answers jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '1s'
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_key text;
  v_value jsonb;
  v_clean jsonb;
  v_reason text;
  v_at timestamptz;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- Pre-validated: no raw constraint error ever reaches the app.
  IF p_answers IS NULL OR jsonb_typeof(p_answers) IS DISTINCT FROM 'object' THEN
    RETURN private.dating_invalid('answers');
  END IF;
  FOR v_key, v_value IN SELECT k, v FROM jsonb_each(p_answers) AS j(k, v) LOOP
    IF v_key NOT IN ('q1', 'q2', 'q3') THEN
      RETURN private.dating_invalid('answers');
    END IF;
    IF jsonb_typeof(v_value) NOT IN ('string', 'null') OR coalesce(char_length(v_value #>> '{}'), 0) > 500 THEN
      RETURN private.dating_invalid(v_key);
    END IF;
  END LOOP;
  v_clean := jsonb_strip_nulls(jsonb_build_object(
    'q1', nullif(btrim(p_answers ->> 'q1'), ''),
    'q2', nullif(btrim(p_answers ->> 'q2'), ''),
    'q3', nullif(btrim(p_answers ->> 'q3'), '')));
  IF v_clean = '{}'::jsonb THEN
    -- Clearing one's own answers is never gated (exposure-reducing) and never
    -- fails behind a country switch: it takes no advisory lock (no switch
    -- touches this table, and the clear holds only its own row), retries its
    -- one write, and answers busy (counted) rather than raise (review I-1).
    FOR v_try IN 1..3 LOOP -- a lock conflict or a cancel is retried (each attempt its own savepoint)
      BEGIN
        UPDATE public.dating_gentle_wait_reflections AS g SET answers = NULL, saved_at = NULL WHERE g.user_id = v_user;
        RETURN jsonb_build_object('ok', true, 'saved_at', NULL);
      EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure OR query_canceled THEN
        NULL;
      END;
    END LOOP;
    BEGIN
      PERFORM private.bump_metric_internal('dating.gentle_wait.clear_busy');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RETURN jsonb_build_object('ok', false, 'reason', 'busy');
  END IF;
  BEGIN
    v_reason := private.dating_setup_guard(); -- the lock, the trusted device, setup eligibility
  EXCEPTION WHEN lock_not_available OR query_canceled THEN
    RAISE EXCEPTION 'dating:busy' USING ERRCODE = '55P03'; -- waiting behind a switch: the app retries once
  END;
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  v_at := now();
  FOR v_try IN 1..3 LOOP -- a lock conflict is retried (each attempt its own savepoint)
    BEGIN
      INSERT INTO public.dating_gentle_wait_reflections AS g (user_id, answers, saved_at)
      VALUES (v_user, v_clean, v_at)
      ON CONFLICT (user_id) DO UPDATE SET answers = EXCLUDED.answers, saved_at = EXCLUDED.saved_at;
      EXIT;
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'saved_at', v_at);
END;
$fn$;

-- Spec 2 W2 (final review M-4): whether closing the shared space together
-- can still end the person's wait: every ending that holds it is an 'ended'
-- space whose two members' accounts both exist. False after the former
-- partner deleted their account (a lone close still waits), for the one
-- who moved on (their first ending's space is already archived), with no
-- wait, and for an undated ending (no open date). D0 promises "If you both
-- close it sooner" only when this is true.
CREATE OR REPLACE FUNCTION private.dating_gentle_wait_can_shorten(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
AS $function$
  WITH holding AS ( -- the rows private.dating_gentle_wait_opens_at counts
    SELECT r.status, r.user_a, r.user_b
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
                                   AND greatest(n.invite_accepted_at, n.created_at) >= coalesce(r.ended_at, r.chat_archived_at)))))
  )
  SELECT EXISTS (SELECT 1 FROM holding)
     AND NOT EXISTS (SELECT 1 FROM holding AS h
                      WHERE h.status IS DISTINCT FROM 'ended' OR h.user_a IS NULL OR h.user_b IS NULL);
$function$;
REVOKE ALL ON FUNCTION private.dating_gentle_wait_can_shorten(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_my_gentle_wait_reflection()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '1s'
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_opens timestamptz;
  v_row public.dating_gentle_wait_reflections;
  v_marked boolean := false;
  v_done boolean := false;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  v_opens := private.dating_gentle_wait_opens_at(v_user);
  -- D0 opened during a wait: seen once per ending (§6.9), never while
  -- Dating is closed to the person.
  IF v_opens IS NOT NULL
     AND public.dating_eligibility(v_user, 'setup') IS NOT DISTINCT FROM 'eligible' THEN
    -- D0 never waits (review I-2): the mark takes only the person's own setup
    -- lock (it has nothing to do with the same-gender locks), and only if it
    -- is free. A view that can't be marked (the lock taken, or three
    -- conflicts) is skipped and counted; D0 still opens.
    IF pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('dating_setup'), pg_catalog.hashtext(v_user::text)) THEN
      FOR v_try IN 1..3 LOOP -- a lock conflict is retried (each attempt its own savepoint)
        BEGIN
          INSERT INTO public.dating_gentle_wait_reflections AS g (user_id, seen_at)
          VALUES (v_user, now())
          ON CONFLICT (user_id) DO UPDATE SET seen_at = now()
           WHERE g.seen_at IS NULL OR g.seen_at < (v_opens AT TIME ZONE 'UTC' - interval '30 days') AT TIME ZONE 'UTC';
          v_marked := FOUND;
          v_done := true;
          EXIT;
        EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure OR query_canceled THEN
          NULL; -- after three, this view goes uncounted: D0 still opens
        END;
      END LOOP;
    END IF;
    BEGIN
      IF v_marked THEN
        PERFORM private.bump_metric_internal('dating.gentle_wait.seen');
      ELSIF NOT v_done THEN
        PERFORM private.bump_metric_internal('dating.gentle_wait.seen_skipped');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;
  SELECT * INTO v_row FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_user;
  RETURN jsonb_build_object(
    'ok', true,
    'answers', coalesce(v_row.answers, '{}'::jsonb),
    'saved_at', v_row.saved_at,
    'ended_at', (v_opens AT TIME ZONE 'UTC' - interval '30 days') AT TIME ZONE 'UTC', -- in UTC (a DST change moves nothing)
    'opens_at', v_opens,
    'can_shorten', v_opens IS NOT NULL AND coalesce(private.dating_gentle_wait_can_shorten(v_user), false)); -- Spec 2 W2 (final review M-4)
END;
$fn$;

CREATE OR REPLACE FUNCTION private.dating_carry_on_auth_user_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  BEGIN -- W1 final fix (I-1)
    PERFORM private.dating_lock_setup(OLD.id); -- W1 final fix (I-1)
  EXCEPTION WHEN OTHERS THEN -- W1 final fix (I-1): never blocks the deletion
    RAISE WARNING 'dating_carry_on_auth_user_delete:lock:%', SQLSTATE; -- W1 final fix (I-1)
  END; -- W1 final fix (I-1)
  BEGIN
    IF private.dating_deletion_carry(OLD.id, true) > 0 THEN
      PERFORM private.bump_metric_internal('dating.deletion.late_carry');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    PERFORM private.bump_metric_internal('dating.deletion.late_carry_failed');
  END;
  BEGIN -- Spec 2 W2 (§6.9): an account deleted within 7 days of opening D0 (the evasion proxy)
    IF EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections AS g -- Spec 2 W2
                WHERE g.user_id = OLD.id AND g.seen_at > now() - interval '7 days') THEN -- Spec 2 W2
      PERFORM private.bump_metric_internal('dating.gentle_wait.account_deleted_7d'); -- Spec 2 W2
    END IF; -- Spec 2 W2
  EXCEPTION WHEN OTHERS THEN -- Spec 2 W2: never blocks the deletion
    NULL; -- Spec 2 W2
  END; -- Spec 2 W2
  RETURN OLD;
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
                        'dating.parked_pause.failed', -- Spec 2 W1d (fix round 1, M-5)
                        'dating.path_pause.failed', 'dating.gates.busy', -- Spec 2 W2
                        'dating.gates.failed', 'dating.gentle_wait.undated', -- Spec 2 W2 (Task 3 carry: W2 batch 1 fix round 1, M-4 and M-3)
                        'dating.path_pause.swept', -- Spec 2 W2 (Task 3 fix round 1, I-1)
                        'dating.gentle_wait.seen', 'dating.gentle_wait.account_deleted_7d', -- Spec 2 W2 (migration 3, §6.9)
                        'dating.gentle_wait.clear_busy', 'dating.gentle_wait.seen_skipped', 'dating.home.unreadable_field', -- Spec 2 W2 (migration 3 fix round 1)
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

REVOKE ALL ON FUNCTION private.dating_next_step(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_unavailable_state(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_first_drop_at(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
