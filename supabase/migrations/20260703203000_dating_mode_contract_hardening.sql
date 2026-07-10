ALTER TABLE public.dating_enrollments
  ADD COLUMN IF NOT EXISTS suspended_at timestamptz,
  ADD COLUMN IF NOT EXISTS state_version bigint NOT NULL DEFAULT 1;

ALTER TABLE public.dating_profiles
  ADD COLUMN IF NOT EXISTS profile_version bigint NOT NULL DEFAULT 1;

ALTER TABLE public.dating_preferences
  ADD COLUMN IF NOT EXISTS gender_preferences jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS region_preferences jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS intention_preferences jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.dating_consent_events
  ADD COLUMN IF NOT EXISTS occurred_at timestamptz;

UPDATE public.dating_consent_events
SET occurred_at = COALESCE(occurred_at, created_at, now())
WHERE occurred_at IS NULL;

ALTER TABLE public.dating_consent_events
  ALTER COLUMN occurred_at SET NOT NULL;

UPDATE public.dating_consent_events
SET action = CASE
  WHEN action = 'grant' THEN 'granted'
  WHEN action = 'withdraw' THEN 'withdrawn'
  ELSE action
END
WHERE action IN ('grant', 'withdraw');

ALTER TABLE public.dating_consent_events
  DROP CONSTRAINT IF EXISTS dating_consent_events_action_check;

ALTER TABLE public.dating_consent_events
  ADD CONSTRAINT dating_consent_events_action_check
  CHECK (action IN ('granted', 'withdrawn'));

ALTER TABLE public.dating_consent_events
  DROP CONSTRAINT IF EXISTS dating_consent_events_idempotency_key_key;

CREATE UNIQUE INDEX IF NOT EXISTS dating_consent_events_user_idempotency_idx
  ON public.dating_consent_events(user_id, idempotency_key);

ALTER TABLE public.dating_interest_actions
  ADD COLUMN IF NOT EXISTS acted_at timestamptz;

UPDATE public.dating_interest_actions
SET acted_at = COALESCE(acted_at, created_at, now())
WHERE acted_at IS NULL;

ALTER TABLE public.dating_interest_actions
  ALTER COLUMN acted_at SET NOT NULL;

ALTER TABLE public.dating_interest_actions
  DROP CONSTRAINT IF EXISTS dating_interest_actions_idempotency_key_key;

CREATE UNIQUE INDEX IF NOT EXISTS dating_interest_actions_actor_idempotency_idx
  ON public.dating_interest_actions(actor_user_id, idempotency_key);

ALTER TABLE public.dating_date_reflections
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.dating_date_reflections
  DROP CONSTRAINT IF EXISTS dating_date_reflections_idempotency_key_key;

ALTER TABLE public.dating_date_reflections
  ADD CONSTRAINT dating_date_reflections_note_length_check
  CHECK (note IS NULL OR char_length(note) <= 500);

ALTER TABLE public.dating_matches
  ADD COLUMN IF NOT EXISTS created_at timestamptz;

UPDATE public.dating_matches
SET created_at = COALESCE(created_at, matched_at, now())
WHERE created_at IS NULL;

ALTER TABLE public.dating_matches
  ALTER COLUMN created_at SET NOT NULL,
  ALTER COLUMN created_at SET DEFAULT now();

CREATE TABLE IF NOT EXISTS public.dating_profile_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  storage_key text NOT NULL,
  position smallint NOT NULL,
  moderation_state text NOT NULL DEFAULT 'pending'
    CHECK (moderation_state IN ('pending', 'approved', 'rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, position)
);

CREATE TABLE IF NOT EXISTS public.dating_feature_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  algorithm_version text NOT NULL,
  consent_basis jsonb NOT NULL DEFAULT '{}'::jsonb,
  features jsonb NOT NULL DEFAULT '{}'::jsonb,
  source_provenance jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  invalidated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.dating_rpc_idempotency (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  operation text NOT NULL,
  idempotency_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, operation, idempotency_key)
);

ALTER TABLE public.dating_introductions
  ADD COLUMN IF NOT EXISTS algorithm_version text,
  ADD COLUMN IF NOT EXISTS snapshot_low_id uuid,
  ADD COLUMN IF NOT EXISTS snapshot_high_id uuid,
  ADD COLUMN IF NOT EXISTS internal_score numeric;

UPDATE public.dating_introductions
SET algorithm_version = COALESCE(algorithm_version, '1.1.0'),
    internal_score = COALESCE(internal_score, 0)
WHERE algorithm_version IS NULL OR internal_score IS NULL;

DO $$
DECLARE
  v_intro record;
  v_low_snapshot_id uuid;
  v_high_snapshot_id uuid;
BEGIN
  FOR v_intro IN
    SELECT id, user_low_id, user_high_id, snapshot_low_id, snapshot_high_id
    FROM public.dating_introductions
    WHERE snapshot_low_id IS NULL OR snapshot_high_id IS NULL
  LOOP
    IF v_intro.snapshot_low_id IS NULL THEN
      INSERT INTO public.dating_feature_snapshots (
        user_id,
        algorithm_version,
        consent_basis,
        features,
        source_provenance
      )
      VALUES (
        v_intro.user_low_id,
        '1.1.0',
        jsonb_build_object('basis', 'legacy_backfill'),
        '{}'::jsonb,
        jsonb_build_object('source', 'dating_mode_contract_hardening')
      )
      RETURNING id INTO v_low_snapshot_id;
    ELSE
      v_low_snapshot_id := v_intro.snapshot_low_id;
    END IF;

    IF v_intro.snapshot_high_id IS NULL THEN
      INSERT INTO public.dating_feature_snapshots (
        user_id,
        algorithm_version,
        consent_basis,
        features,
        source_provenance
      )
      VALUES (
        v_intro.user_high_id,
        '1.1.0',
        jsonb_build_object('basis', 'legacy_backfill'),
        '{}'::jsonb,
        jsonb_build_object('source', 'dating_mode_contract_hardening')
      )
      RETURNING id INTO v_high_snapshot_id;
    ELSE
      v_high_snapshot_id := v_intro.snapshot_high_id;
    END IF;

    UPDATE public.dating_introductions
    SET snapshot_low_id = v_low_snapshot_id,
        snapshot_high_id = v_high_snapshot_id
    WHERE id = v_intro.id;
  END LOOP;
END;
$$;

ALTER TABLE public.dating_introductions
  ALTER COLUMN algorithm_version SET NOT NULL,
  ALTER COLUMN internal_score SET NOT NULL,
  ALTER COLUMN snapshot_low_id SET NOT NULL,
  ALTER COLUMN snapshot_high_id SET NOT NULL;

ALTER TABLE public.dating_introductions
  DROP CONSTRAINT IF EXISTS dating_introductions_pair_key_key;

DROP INDEX IF EXISTS dating_intro_lookup_idx;

CREATE INDEX IF NOT EXISTS dating_intro_lookup_idx
  ON public.dating_introductions(user_low_id, user_high_id, state, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS dating_introductions_pair_algorithm_created_idx
  ON public.dating_introductions(pair_key, algorithm_version, created_at);

CREATE UNIQUE INDEX IF NOT EXISTS dating_matches_active_pair_idx
  ON public.dating_matches(user_low_id, user_high_id)
  WHERE state = 'active';

ALTER TABLE public.dating_introductions
  ADD CONSTRAINT dating_introductions_pair_order_check
  CHECK (user_low_id::text < user_high_id::text);

ALTER TABLE public.dating_introductions
  ADD CONSTRAINT dating_introductions_no_self_pair_check
  CHECK (user_low_id <> user_high_id);

ALTER TABLE public.dating_matches
  ADD CONSTRAINT dating_matches_pair_order_check
  CHECK (user_low_id::text < user_high_id::text);

ALTER TABLE public.dating_matches
  ADD CONSTRAINT dating_matches_no_self_pair_check
  CHECK (user_low_id <> user_high_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'dating_introductions_snapshot_low_id_fkey'
  ) THEN
    ALTER TABLE public.dating_introductions
      ADD CONSTRAINT dating_introductions_snapshot_low_id_fkey
      FOREIGN KEY (snapshot_low_id) REFERENCES public.dating_feature_snapshots(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'dating_introductions_snapshot_high_id_fkey'
  ) THEN
    ALTER TABLE public.dating_introductions
      ADD CONSTRAINT dating_introductions_snapshot_high_id_fkey
      FOREIGN KEY (snapshot_high_id) REFERENCES public.dating_feature_snapshots(id);
  END IF;
END;
$$;

ALTER TABLE public.dating_profile_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_feature_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_rpc_idempotency ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.dating_profile_photos FROM anon, authenticated;
REVOKE ALL ON public.dating_feature_snapshots FROM anon, authenticated;
REVOKE ALL ON public.dating_rpc_idempotency FROM anon, authenticated;

DROP TRIGGER IF EXISTS set_dating_date_reflections_updated_at ON public.dating_date_reflections;
CREATE TRIGGER set_dating_date_reflections_updated_at
BEFORE UPDATE ON public.dating_date_reflections
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.bump_dating_enrollment_version()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.state_version = COALESCE(OLD.state_version, 1) + 1;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS bump_dating_enrollment_version ON public.dating_enrollments;
CREATE TRIGGER bump_dating_enrollment_version
BEFORE UPDATE ON public.dating_enrollments
FOR EACH ROW EXECUTE FUNCTION public.bump_dating_enrollment_version();

CREATE OR REPLACE FUNCTION public.bump_dating_profile_version()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.profile_version = COALESCE(OLD.profile_version, 1) + 1;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS bump_dating_profile_version ON public.dating_profiles;
CREATE TRIGGER bump_dating_profile_version
BEFORE UPDATE ON public.dating_profiles
FOR EACH ROW EXECUTE FUNCTION public.bump_dating_profile_version();

CREATE OR REPLACE FUNCTION public.claim_dating_idempotency(
  p_operation text,
  p_idempotency_key text
)
RETURNS boolean
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

  IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
    RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.dating_rpc_idempotency (
    user_id,
    operation,
    idempotency_key
  )
  VALUES (
    v_user_id,
    p_operation,
    p_idempotency_key
  )
  ON CONFLICT DO NOTHING;

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(
  p_user_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.dating_feature_snapshots
  SET invalidated_at = COALESCE(invalidated_at, now())
  WHERE user_id = p_user_id
    AND invalidated_at IS NULL;

  UPDATE public.dating_introductions
  SET state = 'invalidated'
  WHERE (user_low_id = p_user_id OR user_high_id = p_user_id)
    AND state IN ('generated', 'presented', 'interested');
END;
$$;

CREATE OR REPLACE FUNCTION public.pause_dating_for_relationship_user(
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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
      updated_at = now()
  WHERE user_id = p_user_id
    AND state IN ('active', 'profile_draft', 'eligible_to_opt_in');

  UPDATE public.users
  SET mode = CASE WHEN mode = 'dating' THEN 'personal' ELSE mode END,
      updated_at = now()
  WHERE id = p_user_id;

  PERFORM public.invalidate_dating_for_user(p_user_id, 'relationship_guard');
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_relationship_dating_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('pending', 'active') THEN
    PERFORM public.pause_dating_for_relationship_user(NEW.user_a);
    IF NEW.user_b IS NOT NULL THEN
      PERFORM public.pause_dating_for_relationship_user(NEW.user_b);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS relationship_dating_guard ON public.relationships;
CREATE TRIGGER relationship_dating_guard
AFTER INSERT OR UPDATE OF status, user_b ON public.relationships
FOR EACH ROW EXECUTE FUNCTION public.handle_relationship_dating_guard();

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
    WHEN p_action IN ('grant', 'granted') THEN 'granted'
    WHEN p_action IN ('withdraw', 'withdrawn') THEN 'withdrawn'
    ELSE p_action
  END;
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
    categories,
    occurred_at
  )
  VALUES (
    v_user_id,
    p_idempotency_key,
    p_purpose,
    v_action,
    p_policy_version,
    COALESCE(p_categories, '[]'::jsonb),
    now()
  )
  ON CONFLICT (user_id, idempotency_key) DO NOTHING;

  IF v_action = 'granted' AND p_purpose = 'age_gate' THEN
    INSERT INTO public.dating_enrollments (user_id, adults_only_confirmed_at)
    VALUES (v_user_id, now())
    ON CONFLICT (user_id) DO UPDATE
      SET adults_only_confirmed_at = COALESCE(public.dating_enrollments.adults_only_confirmed_at, now());
  END IF;

  IF v_action = 'withdrawn' AND p_purpose = 'historical_data' THEN
    PERFORM public.invalidate_dating_for_user(v_user_id, 'historical_consent_withdrawn');
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

  IF NOT public.claim_dating_idempotency('begin_dating_enrollment', p_idempotency_key) THEN
    SELECT * INTO v_enrollment
    FROM public.dating_enrollments
    WHERE user_id = v_user_id;
    RETURN v_enrollment;
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
        suspended_at = NULL,
        updated_at = now()
  RETURNING * INTO v_enrollment;

  RETURN v_enrollment;
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

  IF NOT public.claim_dating_idempotency('activate_dating_profile', p_idempotency_key) THEN
    SELECT * INTO v_enrollment
    FROM public.dating_enrollments
    WHERE user_id = v_user_id;
    RETURN v_enrollment;
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
      exited_at = NULL,
      suspended_at = NULL,
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

  IF NOT public.claim_dating_idempotency('pause_dating_mode', p_idempotency_key) THEN
    SELECT * INTO v_enrollment
    FROM public.dating_enrollments
    WHERE user_id = v_user_id;
    RETURN v_enrollment;
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

  UPDATE public.users
  SET mode = CASE WHEN mode = 'dating' THEN 'personal' ELSE mode END,
      updated_at = now()
  WHERE id = v_user_id;

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

  IF NOT public.claim_dating_idempotency('exit_dating_mode', p_idempotency_key) THEN
    SELECT * INTO v_enrollment
    FROM public.dating_enrollments
    WHERE user_id = v_user_id;
    RETURN v_enrollment;
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

  PERFORM public.invalidate_dating_for_user(v_user_id, 'exit');

  RETURN v_enrollment;
END;
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

  IF p_action NOT IN ('interested', 'passed') THEN
    RAISE EXCEPTION 'invalid_action' USING ERRCODE = '22023';
  END IF;

  IF NOT public.claim_dating_idempotency('act_on_dating_introduction', p_idempotency_key) THEN
    RETURN;
  END IF;

  SELECT * INTO v_intro
  FROM public.dating_introductions
  WHERE id = p_introduction_id
    AND (user_low_id = v_user_id OR user_high_id = v_user_id)
  FOR UPDATE;

  IF v_intro.id IS NULL THEN
    RAISE EXCEPTION 'introduction_not_found' USING ERRCODE = '22023';
  END IF;

  IF v_intro.expires_at <= now() OR v_intro.state IN ('expired', 'invalidated', 'matched', 'passed') THEN
    RAISE EXCEPTION 'introduction_unavailable' USING ERRCODE = '22023';
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
    idempotency_key,
    acted_at
  )
  VALUES (
    v_intro.id,
    v_user_id,
    p_action,
    p_idempotency_key,
    now()
  )
  ON CONFLICT (introduction_id, actor_user_id) DO NOTHING;

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
    BEGIN
      INSERT INTO public.dating_matches (
        introduction_id,
        user_low_id,
        user_high_id,
        state,
        matched_at,
        created_at
      )
      VALUES (
        v_intro.id,
        v_intro.user_low_id,
        v_intro.user_high_id,
        'active',
        now(),
        now()
      )
      ON CONFLICT (introduction_id) DO NOTHING;
    EXCEPTION
      WHEN unique_violation THEN
        NULL;
    END;
  END IF;
END;
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
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public.claim_dating_idempotency('unmatch_dating_match', p_idempotency_key) THEN
    RETURN;
  END IF;

  UPDATE public.dating_matches
  SET state = 'unmatched',
      closed_at = COALESCE(closed_at, now())
  WHERE id = p_match_id
    AND (user_low_id = auth.uid() OR user_high_id = auth.uid())
    AND state = 'active';
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

  IF v_user_id = p_target_user_id THEN
    RAISE EXCEPTION 'invalid_target' USING ERRCODE = '22023';
  END IF;

  IF NOT public.claim_dating_idempotency('block_dating_user', p_idempotency_key) THEN
    RETURN;
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
      closed_at = COALESCE(closed_at, now())
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
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF v_user_id = p_target_id THEN
    RAISE EXCEPTION 'invalid_target' USING ERRCODE = '22023';
  END IF;

  IF NOT public.claim_dating_idempotency('submit_dating_report', p_idempotency_key) THEN
    RETURN;
  END IF;

  INSERT INTO public.dating_reports (
    reporter_user_id,
    target_user_id,
    category,
    details
  )
  VALUES (
    v_user_id,
    p_target_id,
    p_category,
    NULLIF(trim(COALESCE(p_details, '')), '')
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.save_private_date_reflection(
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

  IF NOT public.claim_dating_idempotency('save_private_date_reflection', p_idempotency_key) THEN
    RETURN;
  END IF;

  INSERT INTO public.dating_date_reflections (
    match_id,
    author_user_id,
    response,
    note,
    idempotency_key,
    created_at,
    updated_at
  )
  VALUES (
    p_match_id,
    v_user_id,
    p_response,
    NULLIF(trim(COALESCE(p_note, '')), ''),
    p_idempotency_key,
    now(),
    now()
  )
  ON CONFLICT (match_id, author_user_id) DO UPDATE
    SET response = EXCLUDED.response,
        note = EXCLUDED.note,
        idempotency_key = EXCLUDED.idempotency_key,
        updated_at = now();
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
BEGIN
  PERFORM public.save_private_date_reflection(
    p_idempotency_key,
    p_match_id,
    p_response,
    p_note
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_private_date_reflection(
  p_idempotency_key text,
  p_match_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public.claim_dating_idempotency('delete_private_date_reflection', p_idempotency_key) THEN
    RETURN;
  END IF;

  DELETE FROM public.dating_date_reflections
  WHERE match_id = p_match_id
    AND author_user_id = auth.uid();
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_dating_profile(
  p_idempotency_key text
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

  IF NOT public.claim_dating_idempotency('delete_dating_profile', p_idempotency_key) THEN
    RETURN;
  END IF;

  DELETE FROM public.dating_profile_photos
  WHERE user_id = v_user_id;

  DELETE FROM public.dating_preferences
  WHERE user_id = v_user_id;

  DELETE FROM public.dating_profiles
  WHERE user_id = v_user_id;

  UPDATE public.dating_enrollments
  SET state = CASE
        WHEN state = 'suspended' THEN state
        ELSE 'profile_draft'
      END,
      updated_at = now()
  WHERE user_id = v_user_id;

  UPDATE public.users
  SET mode = CASE WHEN mode = 'dating' THEN 'personal' ELSE mode END,
      updated_at = now()
  WHERE id = v_user_id;

  PERFORM public.invalidate_dating_for_user(v_user_id, 'profile_deleted');
END;
$$;

REVOKE ALL ON FUNCTION public.claim_dating_idempotency(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.invalidate_dating_for_user(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pause_dating_for_relationship_user(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.handle_relationship_dating_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_dating_consent(text, text, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.begin_dating_enrollment(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activate_dating_profile(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pause_dating_mode(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.exit_dating_mode(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.act_on_dating_introduction(text, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.unmatch_dating_match(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.block_dating_user(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_dating_report(text, uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_private_date_reflection(text, uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_dating_date_reflection(text, uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_private_date_reflection(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_dating_profile(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.record_dating_consent(text, text, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.begin_dating_enrollment(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.activate_dating_profile(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pause_dating_mode(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.exit_dating_mode(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.act_on_dating_introduction(text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unmatch_dating_match(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.block_dating_user(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_dating_report(text, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_private_date_reflection(text, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_dating_date_reflection(text, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_private_date_reflection(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_dating_profile(text) TO authenticated;
