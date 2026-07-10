-- Dating Mode v1.2 implementation hardening.
-- Runtime remains safe-off until the Section 16/17 review evidence exists.
CREATE TABLE IF NOT EXISTS public.feature_flags (
  key text PRIMARY KEY,
  enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.feature_flags(key, enabled) VALUES
  ('dating_mode_enabled', false),
  ('dating_alignment_algorithm_v1', false),
  ('dating_candidate_generation', false),
  ('dating_match_messaging', false),
  ('dating_profile_photos', false)
ON CONFLICT (key) DO UPDATE SET enabled = false, updated_at = now();

CREATE TABLE IF NOT EXISTS public.dating_age_verifications (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  birth_date date NOT NULL,
  verification_method text NOT NULL,
  verified_at timestamptz NOT NULL,
  expires_at timestamptz,
  revoked_at timestamptz,
  verified_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (birth_date <= current_date),
  CHECK (char_length(verification_method) BETWEEN 1 AND 80)
);

CREATE TABLE IF NOT EXISTS public.dating_account_restrictions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  restriction_type text NOT NULL CHECK (
    restriction_type IN ('suspended', 'under_review', 'age_review', 'moderation_hold')
  ),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  lifted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS dating_account_restrictions_active_idx
  ON public.dating_account_restrictions(user_id, starts_at)
  WHERE lifted_at IS NULL;

CREATE TABLE IF NOT EXISTS public.dating_algorithm_configs (
  version text PRIMARY KEY,
  state text NOT NULL CHECK (state IN ('draft', 'reviewed', 'active', 'retired')),
  config jsonb NOT NULL,
  config_hash text NOT NULL UNIQUE,
  clinical_review_ref text,
  product_review_ref text,
  fairness_review_ref text,
  safety_review_ref text,
  activated_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (state <> 'active' OR (
    clinical_review_ref IS NOT NULL
    AND product_review_ref IS NOT NULL
    AND fairness_review_ref IS NOT NULL
    AND safety_review_ref IS NOT NULL
    AND activated_at IS NOT NULL
  ))
);

CREATE UNIQUE INDEX IF NOT EXISTS dating_algorithm_one_active_idx
  ON public.dating_algorithm_configs((state)) WHERE state = 'active';

CREATE TABLE IF NOT EXISTS public.dating_generation_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  algorithm_version text NOT NULL REFERENCES public.dating_algorithm_configs(version),
  cohort_window text NOT NULL,
  state text NOT NULL CHECK (state IN ('pending', 'processing', 'completed', 'failed', 'dead_letter')),
  seed text NOT NULL,
  partition_key text NOT NULL,
  attempts smallint NOT NULL DEFAULT 0,
  started_at timestamptz,
  completed_at timestamptz,
  last_error_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (algorithm_version, cohort_window, partition_key)
);

CREATE TABLE IF NOT EXISTS public.dating_rate_limits (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  operation text NOT NULL,
  window_started_at timestamptz NOT NULL,
  request_count int NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, operation)
);

ALTER TABLE public.dating_age_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_account_restrictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_algorithm_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_generation_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_rate_limits ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.dating_age_verifications FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.dating_account_restrictions FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.dating_algorithm_configs FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.dating_generation_runs FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.dating_rate_limits FROM PUBLIC, anon, authenticated;

ALTER TABLE public.dating_profiles
  ADD COLUMN IF NOT EXISTS gender_identity text,
  ADD COLUMN IF NOT EXISTS gender_visible boolean NOT NULL DEFAULT false,
  ALTER COLUMN moderation_state SET DEFAULT 'pending';

ALTER TABLE public.dating_profiles
  DROP CONSTRAINT IF EXISTS dating_profiles_display_name_length_check,
  ADD CONSTRAINT dating_profiles_display_name_length_check
    CHECK (char_length(btrim(display_name)) BETWEEN 1 AND 50),
  DROP CONSTRAINT IF EXISTS dating_profiles_bio_length_check,
  ADD CONSTRAINT dating_profiles_bio_length_check
    CHECK (bio IS NULL OR char_length(bio) <= 500),
  DROP CONSTRAINT IF EXISTS dating_profiles_gender_visibility_check,
  ADD CONSTRAINT dating_profiles_gender_visibility_check
    CHECK (gender_visible = false OR gender_identity IS NOT NULL);

ALTER TABLE public.dating_preferences
  DROP CONSTRAINT IF EXISTS dating_preferences_gender_array_check,
  ADD CONSTRAINT dating_preferences_gender_array_check
    CHECK (jsonb_typeof(gender_preferences) = 'array'),
  DROP CONSTRAINT IF EXISTS dating_preferences_region_array_check,
  ADD CONSTRAINT dating_preferences_region_array_check
    CHECK (jsonb_typeof(region_preferences) = 'array'),
  DROP CONSTRAINT IF EXISTS dating_preferences_intention_array_check,
  ADD CONSTRAINT dating_preferences_intention_array_check
    CHECK (jsonb_typeof(intention_preferences) = 'array');

ALTER TABLE public.dating_reports
  DROP CONSTRAINT IF EXISTS dating_reports_category_check,
  ADD CONSTRAINT dating_reports_category_check CHECK (category IN (
    'safety_concern', 'harassment', 'impersonation', 'spam',
    'romance_scam', 'underage_risk', 'sexual_content', 'other'
  )),
  DROP CONSTRAINT IF EXISTS dating_reports_details_length_check,
  ADD CONSTRAINT dating_reports_details_length_check
    CHECK (details IS NULL OR char_length(details) <= 500);

CREATE OR REPLACE FUNCTION public.dating_flag_enabled(p_key text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT enabled FROM public.feature_flags WHERE key = p_key), false);
$$;

CREATE OR REPLACE FUNCTION public.check_dating_rate_limit(
  p_operation text,
  p_limit int,
  p_window interval
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_row public.dating_rate_limits%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  INSERT INTO public.dating_rate_limits(user_id, operation, window_started_at, request_count)
  VALUES(v_user_id, p_operation, now(), 1)
  ON CONFLICT(user_id, operation) DO UPDATE SET
    window_started_at = CASE
      WHEN public.dating_rate_limits.window_started_at + p_window <= now() THEN now()
      ELSE public.dating_rate_limits.window_started_at END,
    request_count = CASE
      WHEN public.dating_rate_limits.window_started_at + p_window <= now() THEN 1
      ELSE public.dating_rate_limits.request_count + 1 END
  RETURNING * INTO v_row;
  IF v_row.request_count > p_limit THEN
    RAISE EXCEPTION 'rate_limited' USING ERRCODE='22023';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.dating_healing_gates_hold(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.healing_journeys hj
    JOIN LATERAL (
      SELECT hra.score
      FROM public.healing_readiness_attempts hra
      WHERE hra.journey_id = hj.id AND hra.user_id = p_user_id
      ORDER BY hra.submitted_at DESC LIMIT 1
    ) latest ON true
    WHERE hj.user_id = p_user_id
      AND hj.status = 'eligible_for_dating_opt_in'
      AND hj.reflection_completed_at IS NOT NULL
      AND hj.post_mortem_completed_at IS NOT NULL
      AND hj.pattern_awareness_completed_at IS NOT NULL
      AND hj.portrait_completed_at IS NOT NULL
      AND hj.readiness_stage_completed_at IS NOT NULL
      AND hj.eligible_for_dating_opt_in_at IS NOT NULL
      AND latest.score > 70
      AND now() >= hj.breakup_at + interval '8 weeks'
      AND (
        hj.breakup_at_source = 'relationship'
        OR now() >= hj.created_at + interval '4 weeks'
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.dating_age_verifications dav
    WHERE dav.user_id = p_user_id
      AND dav.revoked_at IS NULL
      AND (dav.expires_at IS NULL OR dav.expires_at > now())
      AND dav.birth_date <= current_date - interval '18 years'
  );
$$;

CREATE OR REPLACE FUNCTION public.dating_account_in_good_standing(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users au
    WHERE au.id = p_user_id
      AND au.deleted_at IS NULL
      AND (au.banned_until IS NULL OR au.banned_until <= now())
  ) AND NOT EXISTS (
    SELECT 1 FROM public.dating_account_restrictions dar
    WHERE dar.user_id = p_user_id
      AND dar.lifted_at IS NULL
      AND dar.starts_at <= now()
      AND (dar.ends_at IS NULL OR dar.ends_at > now())
  );
$$;

CREATE OR REPLACE FUNCTION public.dating_has_relationship(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE p_user_id IN (r.user_a, r.user_b)
      AND r.status IN ('pending', 'active')
  );
$$;

CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.dating_profiles dp
    JOIN public.dating_preferences pref ON pref.user_id = dp.user_id
    WHERE dp.user_id = p_user_id
      AND dp.profile_state = 'active'
      AND dp.moderation_state = 'approved'
      AND jsonb_array_length(pref.gender_preferences) > 0
      AND jsonb_array_length(pref.region_preferences) > 0
      AND jsonb_array_length(pref.intention_preferences) > 0
  );
$$;

CREATE OR REPLACE FUNCTION public.dating_candidate_is_current(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.dating_flag_enabled('dating_mode_enabled')
    AND public.dating_healing_gates_hold(p_user_id)
    AND public.dating_age_gate_holds(p_user_id)
    AND public.dating_account_in_good_standing(p_user_id)
    AND NOT public.dating_has_relationship(p_user_id)
    AND EXISTS (
      SELECT 1 FROM public.dating_enrollments de
      WHERE de.user_id = p_user_id AND de.state = 'active'
    )
    AND public.dating_profile_ready(p_user_id);
$$;

CREATE OR REPLACE FUNCTION public.get_dating_eligibility()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('is_eligible',false,'reason','not_authenticated','message','Sign in to continue.');
  END IF;
  IF NOT public.dating_flag_enabled('dating_mode_enabled') THEN
    RETURN jsonb_build_object('is_eligible',false,'reason','feature_unavailable','message','Dating Mode is not available yet.');
  END IF;
  IF NOT public.dating_account_in_good_standing(v_user_id) THEN
    RETURN jsonb_build_object('is_eligible',false,'reason','account_unavailable','message','Dating Mode is not available for this account.');
  END IF;
  IF public.dating_has_relationship(v_user_id) THEN
    RETURN jsonb_build_object('is_eligible',false,'reason','relationship_active','message','Dating Mode stays unavailable while a relationship is pending or active.');
  END IF;
  IF NOT public.dating_healing_gates_hold(v_user_id) THEN
    RETURN jsonb_build_object('is_eligible',false,'reason','healing_not_complete','message','Dating Mode unlocks only after the Healing eligibility transition.');
  END IF;
  RETURN jsonb_build_object(
    'is_eligible',true,
    'age_verification_complete',public.dating_age_gate_holds(v_user_id),
    'reason',NULL,
    'message','You can opt in to Dating Mode when you are ready.'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.record_dating_consent(
  p_idempotency_key text,
  p_purpose text,
  p_action text,
  p_policy_version text,
  p_categories jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_action text := CASE
    WHEN p_action IN ('grant','granted') THEN 'granted'
    WHEN p_action IN ('withdraw','withdrawn') THEN 'withdrawn'
    ELSE NULL END;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF p_purpose NOT IN ('dating_terms','dating_opt_in','historical_data','age_gate')
     OR v_action IS NULL OR btrim(COALESCE(p_policy_version,'')) = ''
     OR jsonb_typeof(COALESCE(p_categories,'[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'invalid_consent_event' USING ERRCODE='22023';
  END IF;
  INSERT INTO public.dating_consent_events(
    user_id,idempotency_key,purpose,action,policy_version,categories,occurred_at
  ) VALUES(
    v_user_id,p_idempotency_key,p_purpose,v_action,p_policy_version,
    COALESCE(p_categories,'[]'::jsonb),now()
  ) ON CONFLICT(user_id,idempotency_key) DO NOTHING;

  IF p_purpose = 'age_gate' AND v_action = 'granted' THEN
    INSERT INTO public.dating_enrollments(user_id,adults_only_confirmed_at)
    VALUES(v_user_id,now()) ON CONFLICT(user_id) DO UPDATE
    SET adults_only_confirmed_at = COALESCE(public.dating_enrollments.adults_only_confirmed_at,now());
  ELSIF p_purpose = 'historical_data' AND v_action = 'withdrawn' THEN
    PERFORM public.invalidate_dating_for_user(v_user_id,'historical_consent_withdrawn');
  ELSIF p_purpose IN ('dating_terms','dating_opt_in') AND v_action = 'withdrawn' THEN
    UPDATE public.dating_profiles SET profile_state='exited' WHERE user_id=v_user_id;
    UPDATE public.dating_enrollments SET state='exited',exited_at=now() WHERE user_id=v_user_id;
    PERFORM public.invalidate_dating_for_user(v_user_id,'dating_consent_withdrawn');
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.begin_dating_enrollment(
  p_terms_version text,
  p_idempotency_key text
)
RETURNS public.dating_enrollments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  PERFORM public.check_dating_rate_limit('begin_enrollment',5,interval '1 day');
  IF NOT public.dating_flag_enabled('dating_mode_enabled')
     OR NOT public.dating_healing_gates_hold(v_user_id)
     OR public.dating_has_relationship(v_user_id)
     OR NOT public.dating_account_in_good_standing(v_user_id) THEN
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
  INSERT INTO public.dating_enrollments(user_id,state,terms_version,opted_in_at)
  VALUES(v_user_id,'profile_draft',p_terms_version,now())
  ON CONFLICT(user_id) DO UPDATE SET
    state=CASE WHEN public.dating_enrollments.state='suspended' THEN 'suspended' ELSE 'profile_draft' END,
    terms_version=EXCLUDED.terms_version,opted_in_at=now(),exited_at=NULL,updated_at=now()
  RETURNING * INTO v_enrollment;
  RETURN v_enrollment;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_dating_profile_draft(
  p_idempotency_key text,
  p_display_name text,
  p_city_region_code text,
  p_relationship_intention text,
  p_bio text,
  p_min_age integer,
  p_max_age integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_bio text := NULLIF(btrim(COALESCE(p_bio,'')),'');
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  PERFORM public.check_dating_rate_limit('profile_edit',20,interval '1 day');
  IF char_length(btrim(COALESCE(p_display_name,''))) NOT BETWEEN 1 AND 50
     OR char_length(btrim(COALESCE(p_city_region_code,''))) NOT BETWEEN 1 AND 80
     OR char_length(btrim(COALESCE(p_relationship_intention,''))) NOT BETWEEN 1 AND 80
     OR char_length(COALESCE(v_bio,'')) > 500
     OR p_min_age NOT BETWEEN 18 AND 70 OR p_max_age NOT BETWEEN 18 AND 70
     OR p_min_age > p_max_age THEN
    RAISE EXCEPTION 'invalid_profile' USING ERRCODE='22023';
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_profile_draft',p_idempotency_key) THEN
    RETURN jsonb_build_object(
      'saved',true,
      'replayed',true,
      'moderation_state',(SELECT moderation_state FROM public.dating_profiles WHERE user_id=v_user_id)
    );
  END IF;
  INSERT INTO public.dating_profiles(
    user_id,display_name,city_region_code,relationship_intention,bio,
    profile_state,moderation_state
  ) VALUES(
    v_user_id,btrim(p_display_name),btrim(p_city_region_code),
    btrim(p_relationship_intention),v_bio,'draft',
    CASE WHEN v_bio IS NULL THEN 'approved' ELSE 'pending' END
  ) ON CONFLICT(user_id) DO UPDATE SET
    display_name=EXCLUDED.display_name,
    city_region_code=EXCLUDED.city_region_code,
    relationship_intention=EXCLUDED.relationship_intention,
    bio=EXCLUDED.bio,
    profile_state='draft',
    moderation_state=CASE
      WHEN public.dating_profiles.bio IS NOT DISTINCT FROM EXCLUDED.bio
        THEN public.dating_profiles.moderation_state
      WHEN EXCLUDED.bio IS NULL THEN 'approved'
      ELSE 'pending' END,
    updated_at=now();
  INSERT INTO public.dating_preferences(user_id,min_age,max_age)
  VALUES(v_user_id,p_min_age,p_max_age)
  ON CONFLICT(user_id) DO UPDATE SET min_age=EXCLUDED.min_age,max_age=EXCLUDED.max_age,updated_at=now();
  INSERT INTO public.dating_enrollments(user_id,state)
  VALUES(v_user_id,'profile_draft') ON CONFLICT(user_id) DO UPDATE SET
    state=CASE WHEN public.dating_enrollments.state='suspended' THEN 'suspended' ELSE 'profile_draft' END,
    updated_at=now();
  PERFORM public.invalidate_dating_for_user(v_user_id,'profile_changed');
  RETURN jsonb_build_object('saved',true,'moderation_state',CASE WHEN v_bio IS NULL THEN 'approved' ELSE 'pending' END);
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_dating_profile(p_idempotency_key text)
RETURNS public.dating_enrollments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  PERFORM public.check_dating_rate_limit('profile_activation',10,interval '1 day');
  IF NOT public.dating_flag_enabled('dating_mode_enabled')
     OR NOT public.dating_healing_gates_hold(v_user_id)
     OR NOT public.dating_age_gate_holds(v_user_id)
     OR NOT public.dating_account_in_good_standing(v_user_id)
     OR public.dating_has_relationship(v_user_id) THEN
    RAISE EXCEPTION 'activation_gates_not_met' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id=v_user_id FOR UPDATE;
  IF NOT FOUND OR v_enrollment.state NOT IN ('profile_draft','paused','active')
     OR v_enrollment.adults_only_confirmed_at IS NULL THEN
    RAISE EXCEPTION 'enrollment_incomplete' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.dating_profiles dp
    JOIN public.dating_preferences pref ON pref.user_id=dp.user_id
    WHERE dp.user_id=v_user_id AND dp.moderation_state='approved'
      AND jsonb_array_length(pref.gender_preferences)>0
      AND jsonb_array_length(pref.region_preferences)>0
      AND jsonb_array_length(pref.intention_preferences)>0
  ) THEN RAISE EXCEPTION 'profile_or_preferences_incomplete' USING ERRCODE='22023'; END IF;
  IF NOT public.claim_dating_idempotency('activate_dating_profile',p_idempotency_key) THEN RETURN v_enrollment; END IF;
  UPDATE public.dating_profiles SET profile_state='active',updated_at=now() WHERE user_id=v_user_id;
  UPDATE public.dating_enrollments SET state='active',activated_at=COALESCE(activated_at,now()),
    paused_at=NULL,exited_at=NULL,updated_at=now() WHERE user_id=v_user_id RETURNING * INTO v_enrollment;
  UPDATE public.users SET mode='dating',updated_at=now() WHERE id=v_user_id;
  RETURN v_enrollment;
END;
$$;

CREATE OR REPLACE FUNCTION public.invalidate_dating_on_profile_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.invalidate_dating_for_user(NEW.user_id,'profile_or_preference_changed');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS invalidate_dating_on_profile_change ON public.dating_profiles;
CREATE TRIGGER invalidate_dating_on_profile_change
AFTER UPDATE ON public.dating_profiles FOR EACH ROW
WHEN (OLD.profile_version IS DISTINCT FROM NEW.profile_version OR OLD.moderation_state IS DISTINCT FROM NEW.moderation_state)
EXECUTE FUNCTION public.invalidate_dating_on_profile_change();

CREATE OR REPLACE FUNCTION public.invalidate_dating_on_photo_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM public.invalidate_dating_for_user(COALESCE(NEW.user_id,OLD.user_id),'photo_moderation_changed');
  RETURN COALESCE(NEW,OLD);
END;
$$;

DROP TRIGGER IF EXISTS invalidate_dating_on_photo_change ON public.dating_profile_photos;
CREATE TRIGGER invalidate_dating_on_photo_change
AFTER INSERT OR UPDATE OF moderation_state OR DELETE ON public.dating_profile_photos
FOR EACH ROW EXECUTE FUNCTION public.invalidate_dating_on_photo_change();

CREATE OR REPLACE FUNCTION public.enforce_dating_restriction_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.lifted_at IS NULL AND NEW.starts_at <= now()
     AND (NEW.ends_at IS NULL OR NEW.ends_at > now()) THEN
    UPDATE public.dating_enrollments SET state='suspended',updated_at=now()
      WHERE user_id=NEW.user_id AND state<>'exited';
    UPDATE public.dating_profiles SET profile_state='paused',updated_at=now()
      WHERE user_id=NEW.user_id AND profile_state='active';
    PERFORM public.invalidate_dating_for_user(NEW.user_id,'account_restricted');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_dating_restriction_change ON public.dating_account_restrictions;
CREATE TRIGGER enforce_dating_restriction_change
AFTER INSERT OR UPDATE ON public.dating_account_restrictions
FOR EACH ROW EXECUTE FUNCTION public.enforce_dating_restriction_change();

CREATE OR REPLACE FUNCTION public.enforce_dating_age_verification_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.revoked_at IS NOT NULL
     OR NEW.birth_date > current_date - interval '18 years'
     OR (NEW.expires_at IS NOT NULL AND NEW.expires_at <= now()) THEN
    UPDATE public.dating_enrollments SET state='paused',paused_at=COALESCE(paused_at,now()),updated_at=now()
      WHERE user_id=NEW.user_id AND state='active';
    UPDATE public.dating_profiles SET profile_state='paused',updated_at=now()
      WHERE user_id=NEW.user_id AND profile_state='active';
    PERFORM public.invalidate_dating_for_user(NEW.user_id,'age_verification_invalid');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_dating_age_verification_change ON public.dating_age_verifications;
CREATE TRIGGER enforce_dating_age_verification_change
AFTER INSERT OR UPDATE ON public.dating_age_verifications
FOR EACH ROW EXECUTE FUNCTION public.enforce_dating_age_verification_change();

ALTER TABLE public.scheduled_notifications
  ADD COLUMN IF NOT EXISTS source_key text;
CREATE UNIQUE INDEX IF NOT EXISTS scheduled_notifications_source_key_idx
  ON public.scheduled_notifications(source_key) WHERE source_key IS NOT NULL;

CREATE OR REPLACE FUNCTION public.act_on_dating_introduction(
  p_idempotency_key text,
  p_introduction_id uuid,
  p_action text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_intro public.dating_introductions%ROWTYPE;
  v_match_id uuid;
  v_active_algorithm text;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF p_action NOT IN ('interested','passed') THEN RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023'; END IF;
  PERFORM public.check_dating_rate_limit('interest_action',30,interval '1 day');
  IF NOT public.dating_flag_enabled('dating_mode_enabled') THEN
    RAISE EXCEPTION 'dating_unavailable' USING ERRCODE='22023';
  END IF;
  SELECT version INTO v_active_algorithm FROM public.dating_algorithm_configs WHERE state='active';
  IF v_active_algorithm IS NULL THEN RAISE EXCEPTION 'algorithm_unavailable' USING ERRCODE='22023'; END IF;

  SELECT * INTO v_intro FROM public.dating_introductions
  WHERE id=p_introduction_id AND v_user_id IN (user_low_id,user_high_id)
  FOR UPDATE;
  IF NOT FOUND OR v_intro.expires_at<=now()
     OR v_intro.state NOT IN ('generated','presented','interested')
     OR v_intro.algorithm_version<>v_active_algorithm THEN
    RAISE EXCEPTION 'introduction_unavailable' USING ERRCODE='22023';
  END IF;
  IF NOT public.dating_candidate_is_current(v_intro.user_low_id)
     OR NOT public.dating_candidate_is_current(v_intro.user_high_id)
     OR EXISTS(SELECT 1 FROM public.dating_blocks b WHERE b.pair_key=v_intro.pair_key)
     OR NOT EXISTS(SELECT 1 FROM public.dating_feature_snapshots s WHERE s.id=v_intro.snapshot_low_id AND s.invalidated_at IS NULL)
     OR NOT EXISTS(SELECT 1 FROM public.dating_feature_snapshots s WHERE s.id=v_intro.snapshot_high_id AND s.invalidated_at IS NULL) THEN
    UPDATE public.dating_introductions SET state='invalidated' WHERE id=v_intro.id;
    RAISE EXCEPTION 'introduction_unavailable' USING ERRCODE='22023';
  END IF;
  IF NOT public.claim_dating_idempotency('act_on_dating_introduction',p_idempotency_key) THEN RETURN; END IF;

  INSERT INTO public.dating_interest_actions(introduction_id,actor_user_id,action,idempotency_key,acted_at)
  VALUES(v_intro.id,v_user_id,p_action,p_idempotency_key,now())
  ON CONFLICT(introduction_id,actor_user_id) DO NOTHING;

  IF v_intro.user_low_id=v_user_id THEN
    UPDATE public.dating_introductions SET low_action=p_action,state=CASE
      WHEN p_action='passed' THEN 'passed'
      WHEN high_action='interested' THEN 'matched'
      ELSE 'interested' END WHERE id=v_intro.id;
  ELSE
    UPDATE public.dating_introductions SET high_action=p_action,state=CASE
      WHEN p_action='passed' THEN 'passed'
      WHEN low_action='interested' THEN 'matched'
      ELSE 'interested' END WHERE id=v_intro.id;
  END IF;

  SELECT * INTO v_intro FROM public.dating_introductions WHERE id=v_intro.id;
  IF v_intro.low_action='interested' AND v_intro.high_action='interested' THEN
    INSERT INTO public.dating_matches(introduction_id,user_low_id,user_high_id,state,matched_at,created_at)
    VALUES(v_intro.id,v_intro.user_low_id,v_intro.user_high_id,'active',now(),now())
    ON CONFLICT(introduction_id) DO NOTHING RETURNING id INTO v_match_id;
    IF v_match_id IS NOT NULL THEN
      INSERT INTO public.scheduled_notifications(
        user_id,notification_type,scheduled_for,status,metadata,source_key,created_at,updated_at
      ) VALUES
        (v_intro.user_low_id,'immediate',now(),'pending',
         jsonb_build_object('title','New mutual match','body','Open Attune to see your new connection.','type','dating_mutual_match'),
         'dating_match:'||v_match_id::text||':'||v_intro.user_low_id::text,now(),now()),
        (v_intro.user_high_id,'immediate',now(),'pending',
         jsonb_build_object('title','New mutual match','body','Open Attune to see your new connection.','type','dating_mutual_match'),
         'dating_match:'||v_match_id::text||':'||v_intro.user_high_id::text,now(),now())
      ON CONFLICT(source_key) WHERE source_key IS NOT NULL DO NOTHING;
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_dating_introductions()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE v_count bigint;
BEGIN
  UPDATE public.dating_introductions SET state='expired'
  WHERE expires_at<=now() AND state IN ('generated','presented','interested');
  GET DIAGNOSTICS v_count=ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_dating_lifecycle_gates()
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_user_id uuid; v_count bigint := 0;
BEGIN
  FOR v_user_id IN
    SELECT de.user_id FROM public.dating_enrollments de
    WHERE de.state='active' AND (
      NOT public.dating_age_gate_holds(de.user_id)
      OR NOT public.dating_account_in_good_standing(de.user_id)
      OR NOT public.dating_healing_gates_hold(de.user_id)
      OR public.dating_has_relationship(de.user_id)
      OR NOT public.dating_profile_ready(de.user_id)
    )
  LOOP
    UPDATE public.dating_enrollments SET state='paused',paused_at=COALESCE(paused_at,now()),updated_at=now()
      WHERE user_id=v_user_id AND state='active';
    UPDATE public.dating_profiles SET profile_state='paused',updated_at=now()
      WHERE user_id=v_user_id AND profile_state='active';
    PERFORM public.invalidate_dating_for_user(v_user_id,'scheduled_gate_revalidation');
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

DROP TRIGGER IF EXISTS invalidate_dating_on_preference_change ON public.dating_preferences;
CREATE TRIGGER invalidate_dating_on_preference_change
AFTER UPDATE ON public.dating_preferences FOR EACH ROW
EXECUTE FUNCTION public.invalidate_dating_on_profile_change();

DROP FUNCTION IF EXISTS public.get_my_dating_introductions(integer);
CREATE FUNCTION public.get_my_dating_introductions(p_limit integer DEFAULT 20)
RETURNS TABLE(
  id uuid, display_name text, city_region_code text, relationship_intention text,
  summary text, display_band text, explanation_features jsonb, state text,
  expires_at timestamptz, created_at timestamptz, has_acted boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT di.id,dp.display_name,dp.city_region_code,dp.relationship_intention,
    CASE WHEN di.user_low_id=auth.uid() THEN di.high_summary ELSE di.low_summary END,
    di.display_band,di.explanation_features,di.state,di.expires_at,di.created_at,
    EXISTS(SELECT 1 FROM public.dating_interest_actions a WHERE a.introduction_id=di.id AND a.actor_user_id=auth.uid())
  FROM public.dating_introductions di
  JOIN public.dating_profiles dp ON dp.user_id=CASE WHEN di.user_low_id=auth.uid() THEN di.user_high_id ELSE di.user_low_id END
  WHERE public.dating_flag_enabled('dating_mode_enabled')
    AND auth.uid() IN (di.user_low_id,di.user_high_id)
    AND di.state IN ('generated','presented','interested')
    AND di.expires_at>now()
    AND dp.profile_state='active' AND dp.moderation_state='approved'
    AND public.dating_candidate_is_current(di.user_low_id)
    AND public.dating_candidate_is_current(di.user_high_id)
    AND NOT EXISTS(SELECT 1 FROM public.dating_blocks b WHERE b.pair_key=di.pair_key)
    AND EXISTS(SELECT 1 FROM public.dating_feature_snapshots s WHERE s.id=di.snapshot_low_id AND s.invalidated_at IS NULL)
    AND EXISTS(SELECT 1 FROM public.dating_feature_snapshots s WHERE s.id=di.snapshot_high_id AND s.invalidated_at IS NULL)
  ORDER BY di.created_at DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,20),1),20);
$$;

DROP FUNCTION IF EXISTS public.get_my_dating_matches(integer);
CREATE FUNCTION public.get_my_dating_matches(p_limit integer DEFAULT 50)
RETURNS TABLE(id uuid,display_name text,city_region_code text,matched_at timestamptz,state text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT dm.id,dp.display_name,dp.city_region_code,dm.matched_at,dm.state
  FROM public.dating_matches dm
  JOIN public.dating_profiles dp ON dp.user_id=CASE WHEN dm.user_low_id=auth.uid() THEN dm.user_high_id ELSE dm.user_low_id END
  WHERE auth.uid() IN (dm.user_low_id,dm.user_high_id) AND dm.state='active'
  ORDER BY dm.matched_at DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,50),1),50);
$$;

CREATE OR REPLACE FUNCTION public.resolve_dating_introduction_target(p_introduction_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_intro public.dating_introductions%ROWTYPE;
BEGIN
  SELECT * INTO v_intro FROM public.dating_introductions
  WHERE id=p_introduction_id AND auth.uid() IN (user_low_id,user_high_id);
  IF NOT FOUND THEN RAISE EXCEPTION 'introduction_unavailable' USING ERRCODE='22023'; END IF;
  RETURN CASE WHEN v_intro.user_low_id=auth.uid() THEN v_intro.user_high_id ELSE v_intro.user_low_id END;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_dating_match_target(p_match_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_match public.dating_matches%ROWTYPE;
BEGIN
  SELECT * INTO v_match FROM public.dating_matches
  WHERE id=p_match_id AND auth.uid() IN (user_low_id,user_high_id);
  IF NOT FOUND THEN RAISE EXCEPTION 'match_unavailable' USING ERRCODE='22023'; END IF;
  RETURN CASE WHEN v_match.user_low_id=auth.uid() THEN v_match.user_high_id ELSE v_match.user_low_id END;
END;
$$;

CREATE OR REPLACE FUNCTION public.block_dating_introduction(p_idempotency_key text,p_introduction_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM public.check_dating_rate_limit('block',20,interval '1 day');
  PERFORM public.block_dating_user(p_idempotency_key,public.resolve_dating_introduction_target(p_introduction_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.block_dating_match(p_idempotency_key text,p_match_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM public.check_dating_rate_limit('block',20,interval '1 day');
  PERFORM public.block_dating_user(p_idempotency_key,public.resolve_dating_match_target(p_match_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.report_dating_introduction(
  p_idempotency_key text,p_introduction_id uuid,p_category text,p_details text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM public.check_dating_rate_limit('report',10,interval '1 day');
  PERFORM public.submit_dating_report(p_idempotency_key,public.resolve_dating_introduction_target(p_introduction_id),p_category,p_details);
END;
$$;

CREATE OR REPLACE FUNCTION public.report_dating_match(
  p_idempotency_key text,p_match_id uuid,p_category text,p_details text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM public.check_dating_rate_limit('report',10,interval '1 day');
  PERFORM public.submit_dating_report(p_idempotency_key,public.resolve_dating_match_target(p_match_id),p_category,p_details);
END;
$$;

CREATE OR REPLACE FUNCTION public.save_private_date_reflection(
  p_idempotency_key text,p_match_id uuid,p_response text,p_note text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF p_response NOT IN ('meet_again','unsure','rather_not') THEN
    RAISE EXCEPTION 'invalid_reflection_response' USING ERRCODE='22023';
  END IF;
  IF length(COALESCE(p_note,'')) > 500 THEN
    RAISE EXCEPTION 'reflection_note_too_long' USING ERRCODE='22023';
  END IF;
  PERFORM public.check_dating_rate_limit('save_reflection',20,interval '1 day');
  IF NOT EXISTS (
    SELECT 1 FROM public.dating_matches dm WHERE dm.id=p_match_id
      AND dm.state='active' AND v_user_id IN (dm.user_low_id,dm.user_high_id)
  ) THEN RAISE EXCEPTION 'match_not_found' USING ERRCODE='22023'; END IF;
  IF NOT public.claim_dating_idempotency('save_private_date_reflection',p_idempotency_key) THEN RETURN; END IF;
  INSERT INTO public.dating_date_reflections(match_id,author_user_id,response,note,idempotency_key,created_at,updated_at)
  VALUES(p_match_id,v_user_id,p_response,NULLIF(trim(COALESCE(p_note,'')),''),p_idempotency_key,now(),now())
  ON CONFLICT(match_id,author_user_id) DO UPDATE SET
    response=EXCLUDED.response,note=EXCLUDED.note,idempotency_key=EXCLUDED.idempotency_key,updated_at=now();
END;
$$;

REVOKE ALL ON FUNCTION public.save_dating_profile_draft(text,text,text,text,integer,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.block_dating_user(text,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.submit_dating_report(text,uuid,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.record_dating_date_reflection(text,uuid,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.resolve_dating_introduction_target(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.resolve_dating_match_target(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.save_dating_profile_draft(text,text,text,text,text,integer,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.block_dating_introduction(text,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.block_dating_match(text,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.report_dating_introduction(text,uuid,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.report_dating_match(text,uuid,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_my_dating_introductions(integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_my_dating_matches(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.save_dating_profile_draft(text,text,text,text,text,integer,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.block_dating_introduction(text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.block_dating_match(text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_dating_introduction(text,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_dating_match(text,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_dating_introductions(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_dating_matches(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.save_private_date_reflection(text,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.save_private_date_reflection(text,uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_dating_operational_health()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT jsonb_build_object(
    'dating_enabled',public.dating_flag_enabled('dating_mode_enabled'),
    'candidate_generation_enabled',public.dating_flag_enabled('dating_candidate_generation'),
    'active_algorithm_versions',(SELECT count(*) FROM public.dating_algorithm_configs WHERE state='active'),
    'stuck_generation_runs',(SELECT count(*) FROM public.dating_generation_runs WHERE state='processing' AND started_at < now()-interval '30 minutes'),
    'failed_generation_runs_24h',(SELECT count(*) FROM public.dating_generation_runs WHERE state IN ('failed','dead_letter') AND created_at >= now()-interval '24 hours'),
    'expired_open_introductions',(SELECT count(*) FROM public.dating_introductions WHERE state IN ('generated','presented','interested') AND expires_at <= now()),
    'pending_bio_moderation',(SELECT count(*) FROM public.dating_profiles WHERE moderation_state='pending'),
    'pending_photo_moderation',(SELECT count(*) FROM public.dating_profile_photos WHERE moderation_state='pending')
  );
$$;
REVOKE ALL ON FUNCTION public.get_dating_operational_health() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_dating_operational_health() TO service_role;

-- Quarantine profiles activated under the earlier self-attested age/moderation path.
UPDATE public.dating_profiles dp SET profile_state='paused',updated_at=now()
WHERE dp.profile_state='active' AND NOT public.dating_profile_ready(dp.user_id);
UPDATE public.dating_enrollments de SET state='paused',paused_at=COALESCE(paused_at,now()),updated_at=now()
WHERE de.state='active' AND (
  NOT public.dating_age_gate_holds(de.user_id)
  OR NOT public.dating_account_in_good_standing(de.user_id)
  OR NOT public.dating_profile_ready(de.user_id)
);
UPDATE public.dating_introductions SET state='invalidated'
WHERE state IN ('generated','presented','interested');

REVOKE ALL ON FUNCTION public.dating_flag_enabled(text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.check_dating_rate_limit(text,int,interval) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.dating_healing_gates_hold(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.dating_age_gate_holds(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.dating_account_in_good_standing(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.dating_has_relationship(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.dating_profile_ready(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.dating_candidate_is_current(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.expire_dating_introductions() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.enforce_dating_lifecycle_gates() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.invalidate_dating_on_photo_change() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.enforce_dating_restriction_change() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.enforce_dating_age_verification_change() FROM PUBLIC,anon,authenticated;
