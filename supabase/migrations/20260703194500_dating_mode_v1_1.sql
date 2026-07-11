CREATE TABLE IF NOT EXISTS public.dating_enrollments (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  state text NOT NULL DEFAULT 'eligible_to_opt_in'
    CHECK (state IN ('ineligible', 'eligible_to_opt_in', 'profile_draft', 'active', 'paused', 'exited', 'suspended')),
  terms_version text,
  opted_in_at timestamptz,
  activated_at timestamptz,
  paused_at timestamptz,
  exited_at timestamptz,
  adults_only_confirmed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.dating_consent_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  idempotency_key text NOT NULL UNIQUE,
  purpose text NOT NULL,
  action text NOT NULL CHECK (action IN ('grant', 'withdraw')),
  policy_version text NOT NULL,
  categories jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.dating_profiles (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  city_region_code text NOT NULL,
  relationship_intention text NOT NULL,
  bio text,
  profile_state text NOT NULL DEFAULT 'draft'
    CHECK (profile_state IN ('draft', 'active', 'paused', 'exited')),
  moderation_state text NOT NULL DEFAULT 'approved'
    CHECK (moderation_state IN ('pending', 'approved', 'rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.dating_preferences (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  min_age smallint NOT NULL CHECK (min_age BETWEEN 18 AND 70),
  max_age smallint NOT NULL CHECK (max_age BETWEEN 18 AND 70),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (min_age <= max_age)
);

CREATE TABLE IF NOT EXISTS public.dating_introductions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pair_key text NOT NULL UNIQUE,
  user_low_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  user_high_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  display_band text NOT NULL
    CHECK (display_band IN ('limited_signal', 'some_shared_ground', 'promising_shared_ground')),
  explanation_features jsonb NOT NULL DEFAULT '{}'::jsonb,
  low_summary text,
  high_summary text,
  state text NOT NULL DEFAULT 'generated'
    CHECK (state IN ('generated', 'presented', 'interested', 'passed', 'matched', 'expired', 'invalidated')),
  low_action text CHECK (low_action IN ('interested', 'passed')),
  high_action text CHECK (high_action IN ('interested', 'passed')),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  created_at timestamptz NOT NULL DEFAULT now(),
  revealed_at timestamptz
);

-- Reconcile a pre-existing remote table: CREATE TABLE IF NOT EXISTS above skips
-- an already-present table and does NOT add columns from a newer revision, so
-- functions below (e.g. get_my_dating_introductions referencing high_summary)
-- would fail with "column does not exist" (SQLSTATE 42703). Add each column
-- idempotently as nullable so this succeeds whether the table is fresh or old
-- and regardless of existing rows.
ALTER TABLE public.dating_introductions
  ADD COLUMN IF NOT EXISTS display_band text,
  ADD COLUMN IF NOT EXISTS explanation_features jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS low_summary text,
  ADD COLUMN IF NOT EXISTS high_summary text,
  ADD COLUMN IF NOT EXISTS state text NOT NULL DEFAULT 'generated',
  ADD COLUMN IF NOT EXISTS low_action text,
  ADD COLUMN IF NOT EXISTS high_action text,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS revealed_at timestamptz;

CREATE TABLE IF NOT EXISTS public.dating_interest_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  introduction_id uuid NOT NULL REFERENCES public.dating_introductions(id) ON DELETE CASCADE,
  actor_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  action text NOT NULL CHECK (action IN ('interested', 'passed')),
  idempotency_key text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (introduction_id, actor_user_id)
);

CREATE TABLE IF NOT EXISTS public.dating_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  introduction_id uuid NOT NULL UNIQUE REFERENCES public.dating_introductions(id) ON DELETE CASCADE,
  user_low_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  user_high_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  state text NOT NULL DEFAULT 'active'
    CHECK (state IN ('active', 'unmatched', 'blocked', 'closed')),
  matched_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.dating_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  blocked_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  pair_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (blocker_user_id, blocked_user_id)
);

CREATE TABLE IF NOT EXISTS public.dating_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  target_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  category text NOT NULL,
  details text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.dating_date_reflections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES public.dating_matches(id) ON DELETE CASCADE,
  author_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  response text NOT NULL,
  note text,
  idempotency_key text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (match_id, author_user_id)
);

CREATE INDEX IF NOT EXISTS dating_intro_lookup_idx
  ON public.dating_introductions(user_low_id, user_high_id, state, created_at DESC);

CREATE INDEX IF NOT EXISTS dating_matches_lookup_idx
  ON public.dating_matches(user_low_id, user_high_id, state, matched_at DESC);

DROP TRIGGER IF EXISTS set_dating_enrollments_updated_at ON public.dating_enrollments;
CREATE TRIGGER set_dating_enrollments_updated_at
BEFORE UPDATE ON public.dating_enrollments
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_dating_profiles_updated_at ON public.dating_profiles;
CREATE TRIGGER set_dating_profiles_updated_at
BEFORE UPDATE ON public.dating_profiles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_dating_preferences_updated_at ON public.dating_preferences;
CREATE TRIGGER set_dating_preferences_updated_at
BEFORE UPDATE ON public.dating_preferences
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.dating_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_consent_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_introductions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_interest_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_date_reflections ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.dating_introductions FROM anon, authenticated;
REVOKE ALL ON public.dating_interest_actions FROM anon, authenticated;
REVOKE ALL ON public.dating_matches FROM anon, authenticated;
REVOKE ALL ON public.dating_blocks FROM anon, authenticated;
REVOKE ALL ON public.dating_reports FROM anon, authenticated;
REVOKE ALL ON public.dating_date_reflections FROM anon, authenticated;

DROP POLICY IF EXISTS "dating enrollments owner read" ON public.dating_enrollments;
CREATE POLICY "dating enrollments owner read"
ON public.dating_enrollments FOR SELECT
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "dating consent owner read" ON public.dating_consent_events;
CREATE POLICY "dating consent owner read"
ON public.dating_consent_events FOR SELECT
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "dating profiles owner read" ON public.dating_profiles;
CREATE POLICY "dating profiles owner read"
ON public.dating_profiles FOR SELECT
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "dating preferences owner read" ON public.dating_preferences;
CREATE POLICY "dating preferences owner read"
ON public.dating_preferences FOR SELECT
USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.dating_pair_key(p_user_a uuid, p_user_b uuid)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT LEAST(p_user_a::text, p_user_b::text) || ':' || GREATEST(p_user_a::text, p_user_b::text);
$$;

CREATE OR REPLACE FUNCTION public.get_dating_eligibility()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_has_active_relationship boolean;
  v_is_healing_eligible boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'is_eligible', false,
      'reason', 'not_authenticated',
      'message', 'Sign in to continue.'
    );
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE (r.user_a = v_user_id OR r.user_b = v_user_id)
      AND r.status IN ('pending', 'active')
  ) INTO v_has_active_relationship;

  IF v_has_active_relationship THEN
    RETURN jsonb_build_object(
      'is_eligible', false,
      'reason', 'relationship_active',
      'message', 'Dating Mode stays unavailable while a relationship is pending or active.'
    );
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.healing_journeys hj
    WHERE hj.user_id = v_user_id
      AND hj.status = 'eligible_for_dating_opt_in'
    ORDER BY hj.updated_at DESC
    LIMIT 1
  ) INTO v_is_healing_eligible;

  IF NOT v_is_healing_eligible THEN
    RETURN jsonb_build_object(
      'is_eligible', false,
      'reason', 'healing_not_complete',
      'message', 'Dating Mode unlocks only after the Healing eligibility transition.'
    );
  END IF;

  RETURN jsonb_build_object(
    'is_eligible', true,
    'reason', null,
    'message', 'You can opt in to Dating Mode when you are ready.'
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
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.dating_consent_events (
    user_id,
    idempotency_key,
    purpose,
    action,
    policy_version,
    categories
  )
  VALUES (
    v_user_id,
    p_idempotency_key,
    p_purpose,
    p_action,
    p_policy_version,
    COALESCE(p_categories, '[]'::jsonb)
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  IF p_purpose = 'age_gate' AND p_action = 'grant' THEN
    INSERT INTO public.dating_enrollments (user_id, adults_only_confirmed_at)
    VALUES (v_user_id, now())
    ON CONFLICT (user_id) DO UPDATE
      SET adults_only_confirmed_at = COALESCE(public.dating_enrollments.adults_only_confirmed_at, now());
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
  v_eligibility jsonb;
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  v_eligibility := public.get_dating_eligibility();
  IF COALESCE((v_eligibility ->> 'is_eligible')::boolean, false) = false THEN
    RAISE EXCEPTION '%', COALESCE(v_eligibility ->> 'reason', 'not_eligible') USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.dating_enrollments (
    user_id,
    state,
    terms_version,
    opted_in_at
  )
  VALUES (
    v_user_id,
    'profile_draft',
    p_terms_version,
    now()
  )
  ON CONFLICT (user_id) DO UPDATE
    SET state = CASE
          WHEN public.dating_enrollments.state = 'suspended'
            THEN public.dating_enrollments.state
          ELSE 'profile_draft'
        END,
        terms_version = EXCLUDED.terms_version,
        opted_in_at = COALESCE(public.dating_enrollments.opted_in_at, now()),
        exited_at = NULL,
        updated_at = now()
  RETURNING * INTO v_enrollment;

  RETURN v_enrollment;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_dating_profile_draft(
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
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.dating_profiles (
    user_id,
    display_name,
    city_region_code,
    relationship_intention,
    bio,
    profile_state
  )
  VALUES (
    v_user_id,
    trim(p_display_name),
    p_city_region_code,
    p_relationship_intention,
    NULLIF(trim(COALESCE(p_bio, '')), ''),
    'draft'
  )
  ON CONFLICT (user_id) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        city_region_code = EXCLUDED.city_region_code,
        relationship_intention = EXCLUDED.relationship_intention,
        bio = EXCLUDED.bio,
        profile_state = 'draft',
        updated_at = now();

  INSERT INTO public.dating_preferences (
    user_id,
    min_age,
    max_age
  )
  VALUES (
    v_user_id,
    p_min_age,
    p_max_age
  )
  ON CONFLICT (user_id) DO UPDATE
    SET min_age = EXCLUDED.min_age,
        max_age = EXCLUDED.max_age,
        updated_at = now();

  INSERT INTO public.dating_enrollments (user_id, state)
  VALUES (v_user_id, 'profile_draft')
  ON CONFLICT (user_id) DO UPDATE
    SET state = CASE
          WHEN public.dating_enrollments.state = 'suspended'
            THEN public.dating_enrollments.state
          ELSE 'profile_draft'
        END,
        updated_at = now();

  RETURN jsonb_build_object('saved', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_dating_profile(
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
  v_profile public.dating_profiles%ROWTYPE;
  v_eligibility jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  v_eligibility := public.get_dating_eligibility();
  IF COALESCE((v_eligibility ->> 'is_eligible')::boolean, false) = false THEN
    RAISE EXCEPTION '%', COALESCE(v_eligibility ->> 'reason', 'not_eligible') USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_enrollment
  FROM public.dating_enrollments
  WHERE user_id = v_user_id;

  IF v_enrollment.user_id IS NULL THEN
    RAISE EXCEPTION 'enrollment_missing' USING ERRCODE = '22023';
  END IF;

  IF v_enrollment.adults_only_confirmed_at IS NULL THEN
    RAISE EXCEPTION 'adult_confirmation_required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_profile
  FROM public.dating_profiles
  WHERE user_id = v_user_id;

  IF v_profile.user_id IS NULL THEN
    RAISE EXCEPTION 'profile_missing' USING ERRCODE = '22023';
  END IF;

  UPDATE public.dating_profiles
  SET profile_state = 'active',
      updated_at = now()
  WHERE user_id = v_user_id;

  UPDATE public.dating_enrollments
  SET state = 'active',
      activated_at = COALESCE(activated_at, now()),
      paused_at = NULL,
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING * INTO v_enrollment;

  UPDATE public.users
  SET mode = 'dating',
      updated_at = now()
  WHERE id = v_user_id;

  RETURN v_enrollment;
END;
$$;

CREATE OR REPLACE FUNCTION public.pause_dating_mode(
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
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  UPDATE public.dating_profiles
  SET profile_state = 'paused',
      updated_at = now()
  WHERE user_id = v_user_id;

  UPDATE public.dating_enrollments
  SET state = 'paused',
      paused_at = now(),
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING * INTO v_enrollment;

  RETURN v_enrollment;
END;
$$;

CREATE OR REPLACE FUNCTION public.exit_dating_mode(
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
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  UPDATE public.dating_profiles
  SET profile_state = 'exited',
      updated_at = now()
  WHERE user_id = v_user_id;

  UPDATE public.dating_enrollments
  SET state = 'exited',
      exited_at = now(),
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING * INTO v_enrollment;

  UPDATE public.users
  SET mode = 'personal',
      updated_at = now()
  WHERE id = v_user_id;

  UPDATE public.dating_introductions
  SET state = 'invalidated'
  WHERE (user_low_id = v_user_id OR user_high_id = v_user_id)
    AND state IN ('generated', 'presented', 'interested');

  RETURN v_enrollment;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_dating_introductions(
  p_limit integer DEFAULT 20
)
RETURNS TABLE (
  id uuid,
  pair_key text,
  other_user_id uuid,
  display_name text,
  city_region_code text,
  relationship_intention text,
  summary text,
  display_band text,
  explanation_features jsonb,
  state text,
  expires_at timestamptz,
  created_at timestamptz,
  has_acted boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    di.id,
    di.pair_key,
    CASE
      WHEN di.user_low_id = auth.uid() THEN di.user_high_id
      ELSE di.user_low_id
    END AS other_user_id,
    dp.display_name,
    dp.city_region_code,
    dp.relationship_intention,
    CASE
      WHEN di.user_low_id = auth.uid() THEN di.high_summary
      ELSE di.low_summary
    END AS summary,
    di.display_band,
    di.explanation_features,
    di.state,
    di.expires_at,
    di.created_at,
    EXISTS (
      SELECT 1
      FROM public.dating_interest_actions dia
      WHERE dia.introduction_id = di.id
        AND dia.actor_user_id = auth.uid()
    ) AS has_acted
  FROM public.dating_introductions di
  JOIN public.dating_profiles dp
    ON dp.user_id = CASE
      WHEN di.user_low_id = auth.uid() THEN di.user_high_id
      ELSE di.user_low_id
    END
  WHERE (di.user_low_id = auth.uid() OR di.user_high_id = auth.uid())
    AND di.state IN ('generated', 'presented', 'interested')
    AND di.expires_at > now()
  ORDER BY di.created_at DESC
  LIMIT GREATEST(COALESCE(p_limit, 20), 1);
$$;

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
  v_pair_key text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_intro
  FROM public.dating_introductions
  WHERE id = p_introduction_id
    AND (user_low_id = v_user_id OR user_high_id = v_user_id)
  FOR UPDATE;

  IF v_intro.id IS NULL THEN
    RAISE EXCEPTION 'introduction_not_found' USING ERRCODE = '22023';
  END IF;

  v_pair_key := public.dating_pair_key(v_intro.user_low_id, v_intro.user_high_id);

  IF EXISTS (
    SELECT 1
    FROM public.dating_blocks db
    WHERE db.pair_key = v_pair_key
  ) THEN
    RAISE EXCEPTION 'pair_blocked' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.dating_interest_actions (
    introduction_id,
    actor_user_id,
    action,
    idempotency_key
  )
  VALUES (
    v_intro.id,
    v_user_id,
    p_action,
    p_idempotency_key
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  IF v_intro.user_low_id = v_user_id THEN
    UPDATE public.dating_introductions
    SET low_action = p_action,
        state = CASE
          WHEN p_action = 'passed' THEN 'passed'
          WHEN high_action = 'interested' THEN 'matched'
          ELSE 'interested'
        END
    WHERE id = v_intro.id;
  ELSE
    UPDATE public.dating_introductions
    SET high_action = p_action,
        state = CASE
          WHEN p_action = 'passed' THEN 'passed'
          WHEN low_action = 'interested' THEN 'matched'
          ELSE 'interested'
        END
    WHERE id = v_intro.id;
  END IF;

  SELECT * INTO v_intro
  FROM public.dating_introductions
  WHERE id = p_introduction_id;

  IF v_intro.low_action = 'interested' AND v_intro.high_action = 'interested' THEN
    INSERT INTO public.dating_matches (
      introduction_id,
      user_low_id,
      user_high_id,
      state,
      matched_at
    )
    VALUES (
      v_intro.id,
      v_intro.user_low_id,
      v_intro.user_high_id,
      'active',
      now()
    )
    ON CONFLICT (introduction_id) DO NOTHING;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_dating_matches(
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  id uuid,
  other_user_id uuid,
  display_name text,
  city_region_code text,
  matched_at timestamptz,
  state text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    dm.id,
    CASE
      WHEN dm.user_low_id = auth.uid() THEN dm.user_high_id
      ELSE dm.user_low_id
    END AS other_user_id,
    dp.display_name,
    dp.city_region_code,
    dm.matched_at,
    dm.state
  FROM public.dating_matches dm
  JOIN public.dating_profiles dp
    ON dp.user_id = CASE
      WHEN dm.user_low_id = auth.uid() THEN dm.user_high_id
      ELSE dm.user_low_id
    END
  WHERE (dm.user_low_id = auth.uid() OR dm.user_high_id = auth.uid())
    AND dm.state = 'active'
  ORDER BY dm.matched_at DESC
  LIMIT GREATEST(COALESCE(p_limit, 50), 1);
$$;

CREATE OR REPLACE FUNCTION public.unmatch_dating_match(
  p_idempotency_key text,
  p_match_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.dating_matches
  SET state = 'unmatched',
      closed_at = now()
  WHERE id = p_match_id
    AND (user_low_id = auth.uid() OR user_high_id = auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.block_dating_user(
  p_idempotency_key text,
  p_target_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_pair_key text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  v_pair_key := public.dating_pair_key(v_user_id, p_target_user_id);

  INSERT INTO public.dating_blocks (
    blocker_user_id,
    blocked_user_id,
    pair_key
  )
  VALUES (
    v_user_id,
    p_target_user_id,
    v_pair_key
  )
  ON CONFLICT (blocker_user_id, blocked_user_id) DO NOTHING;

  UPDATE public.dating_introductions
  SET state = 'invalidated'
  WHERE pair_key = v_pair_key
    AND state IN ('generated', 'presented', 'interested');

  UPDATE public.dating_matches
  SET state = 'blocked',
      closed_at = now()
  WHERE public.dating_pair_key(user_low_id, user_high_id) = v_pair_key
    AND state = 'active';
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_dating_report(
  p_idempotency_key text,
  p_target_id uuid,
  p_category text,
  p_details text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.dating_reports (
    reporter_user_id,
    target_user_id,
    category,
    details
  )
  VALUES (
    auth.uid(),
    p_target_id,
    p_category,
    NULLIF(trim(COALESCE(p_details, '')), '')
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.record_dating_date_reflection(
  p_idempotency_key text,
  p_match_id uuid,
  p_response text,
  p_note text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.dating_matches dm
    WHERE dm.id = p_match_id
      AND dm.state = 'active'
      AND (dm.user_low_id = v_user_id OR dm.user_high_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'match_not_found' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.dating_date_reflections (
    match_id,
    author_user_id,
    response,
    note,
    idempotency_key
  )
  VALUES (
    p_match_id,
    v_user_id,
    p_response,
    NULLIF(trim(COALESCE(p_note, '')), ''),
    p_idempotency_key
  )
  ON CONFLICT (match_id, author_user_id) DO UPDATE
    SET response = EXCLUDED.response,
        note = EXCLUDED.note,
        idempotency_key = EXCLUDED.idempotency_key,
        created_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.get_dating_eligibility() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_dating_consent(text, text, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.begin_dating_enrollment(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_dating_profile_draft(text, text, text, text, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activate_dating_profile(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pause_dating_mode(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.exit_dating_mode(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_dating_introductions(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.act_on_dating_introduction(text, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_dating_matches(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.unmatch_dating_match(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.block_dating_user(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_dating_report(text, uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_dating_date_reflection(text, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_dating_eligibility() TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_dating_consent(text, text, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.begin_dating_enrollment(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_dating_profile_draft(text, text, text, text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.activate_dating_profile(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pause_dating_mode(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.exit_dating_mode(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_dating_introductions(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.act_on_dating_introduction(text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_dating_matches(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unmatch_dating_match(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.block_dating_user(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_dating_report(text, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_dating_date_reflection(text, uuid, text, text) TO authenticated;
