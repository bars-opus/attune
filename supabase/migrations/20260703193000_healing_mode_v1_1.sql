-- Healing Mode v1.1
-- Private, user-owned post-breakup journeys with trusted server-side scoring.

CREATE TABLE IF NOT EXISTS public.healing_journeys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  relationship_id uuid REFERENCES public.relationships(id) ON DELETE SET NULL,
  breakup_at timestamptz NOT NULL,
  breakup_at_source text NOT NULL
    CHECK (breakup_at_source IN ('relationship', 'user_reported')),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'paused', 'completed', 'eligible_for_dating_opt_in', 'archived')),
  current_stage smallint NOT NULL DEFAULT 1
    CHECK (current_stage BETWEEN 1 AND 5),
  reflection_answers jsonb NOT NULL DEFAULT '{}'::jsonb,
  reflection_completed_at timestamptz,
  post_mortem_status text NOT NULL DEFAULT 'not_started'
    CHECK (post_mortem_status IN ('not_started', 'processing', 'completed', 'skipped', 'insufficient_evidence', 'failed')),
  post_mortem_observation text,
  post_mortem_confidence text
    CHECK (post_mortem_confidence IN ('high', 'medium', 'low', 'none')),
  post_mortem_reflection_prompt text,
  post_mortem_completed_at timestamptz,
  pattern_awareness_completed_at timestamptz,
  portrait_status text NOT NULL DEFAULT 'not_started'
    CHECK (portrait_status IN ('not_started', 'processing', 'completed', 'skipped', 'insufficient_evidence', 'failed')),
  portrait_text text,
  portrait_reflection text,
  portrait_prompt text,
  portrait_completed_at timestamptz,
  readiness_stage_completed_at timestamptz,
  completed_at timestamptz,
  eligible_for_dating_opt_in_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS healing_journeys_relationship_unique
  ON public.healing_journeys(user_id, relationship_id)
  WHERE relationship_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS healing_journeys_solo_active_unique
  ON public.healing_journeys(user_id)
  WHERE relationship_id IS NULL AND status IN ('active', 'paused');

CREATE INDEX IF NOT EXISTS healing_journeys_user_created_idx
  ON public.healing_journeys(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.healing_readiness_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journey_id uuid NOT NULL REFERENCES public.healing_journeys(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  answers jsonb NOT NULL,
  score smallint NOT NULL CHECK (score BETWEEN 0 AND 100),
  scoring_version text NOT NULL,
  submitted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS healing_readiness_journey_submitted_idx
  ON public.healing_readiness_attempts(journey_id, submitted_at DESC);

CREATE TABLE IF NOT EXISTS public.healing_generation_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journey_id uuid NOT NULL REFERENCES public.healing_journeys(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  stage text NOT NULL CHECK (stage IN ('post_mortem', 'portrait')),
  status text NOT NULL CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  idempotency_key text NOT NULL,
  input_hash text NOT NULL,
  input_schema_version text NOT NULL,
  prompt_version text NOT NULL,
  model_provider text,
  model_name text,
  validation_version text NOT NULL,
  attempt_count smallint NOT NULL DEFAULT 0,
  failure_code text,
  output_observation text,
  output_confidence text,
  output_reflection_prompt text,
  output_portrait text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (journey_id, stage, input_hash)
);

CREATE INDEX IF NOT EXISTS healing_generation_jobs_user_stage_idx
  ON public.healing_generation_jobs(user_id, stage, created_at DESC);

DROP TRIGGER IF EXISTS set_healing_journeys_updated_at ON public.healing_journeys;
CREATE TRIGGER set_healing_journeys_updated_at
BEFORE UPDATE ON public.healing_journeys
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_healing_generation_jobs_updated_at ON public.healing_generation_jobs;
CREATE TRIGGER set_healing_generation_jobs_updated_at
BEFORE UPDATE ON public.healing_generation_jobs
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.healing_journeys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.healing_readiness_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.healing_generation_jobs ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.healing_journeys FROM anon;
REVOKE ALL ON public.healing_readiness_attempts FROM anon;
REVOKE ALL ON public.healing_generation_jobs FROM anon, authenticated;

GRANT SELECT ON public.healing_journeys TO authenticated;
GRANT SELECT ON public.healing_readiness_attempts TO authenticated;

DROP POLICY IF EXISTS "healing journeys owner read" ON public.healing_journeys;
CREATE POLICY "healing journeys owner read"
ON public.healing_journeys FOR SELECT
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "healing readiness owner read" ON public.healing_readiness_attempts;
CREATE POLICY "healing readiness owner read"
ON public.healing_readiness_attempts FOR SELECT
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "healing generation jobs owner read" ON public.healing_generation_jobs;
CREATE POLICY "healing generation jobs owner read"
ON public.healing_generation_jobs FOR SELECT
USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public._healing_owns_journey(p_journey_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.healing_journeys hj
    WHERE hj.id = p_journey_id
      AND hj.user_id = p_user_id
  )
$$;

CREATE OR REPLACE FUNCTION public._healing_score_from_answers(p_answers jsonb)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_total integer := 0;
  v_value integer;
  v_key text;
BEGIN
  IF jsonb_typeof(p_answers) <> 'object' THEN
    RAISE EXCEPTION 'invalid_answers' USING ERRCODE = '22023';
  END IF;

  FOR v_key IN SELECT format('q%s', generate_series(1, 7))
  LOOP
    IF NOT (p_answers ? v_key) THEN
      RAISE EXCEPTION 'incomplete_answers' USING ERRCODE = '22023';
    END IF;

    v_value := (p_answers->>v_key)::integer;
    IF v_value < 1 OR v_value > 5 THEN
      RAISE EXCEPTION 'invalid_answers' USING ERRCODE = '22023';
    END IF;
    v_total := v_total + (v_value - 1);
  END LOOP;

  RETURN round((100.0 * v_total) / 28.0)::integer;
END;
$$;

CREATE OR REPLACE FUNCTION public._healing_refresh_status(p_journey_id uuid)
RETURNS public.healing_journeys
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_journey public.healing_journeys%ROWTYPE;
  v_latest_attempt public.healing_readiness_attempts%ROWTYPE;
  v_has_relationship boolean;
  v_ready boolean;
BEGIN
  SELECT * INTO v_journey
  FROM public.healing_journeys
  WHERE id = p_journey_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'journey_not_found' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_latest_attempt
  FROM public.healing_readiness_attempts
  WHERE journey_id = p_journey_id
  ORDER BY submitted_at DESC
  LIMIT 1;

  SELECT EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE (r.user_a = v_journey.user_id OR r.user_b = v_journey.user_id)
      AND r.status IN ('pending', 'active')
  ) INTO v_has_relationship;

  v_ready := v_journey.reflection_completed_at IS NOT NULL
    AND v_journey.post_mortem_completed_at IS NOT NULL
    AND v_journey.pattern_awareness_completed_at IS NOT NULL
    AND v_journey.portrait_completed_at IS NOT NULL
    AND v_journey.readiness_stage_completed_at IS NOT NULL;

  IF v_ready THEN
    UPDATE public.healing_journeys
    SET status = CASE
          WHEN v_latest_attempt.id IS NOT NULL
            AND v_latest_attempt.score > 70
            AND now() >= (breakup_at + interval '8 weeks')
            AND NOT v_has_relationship
          THEN 'eligible_for_dating_opt_in'
          ELSE 'completed'
        END,
        completed_at = COALESCE(completed_at, now()),
        eligible_for_dating_opt_in_at = CASE
          WHEN v_latest_attempt.id IS NOT NULL
            AND v_latest_attempt.score > 70
            AND now() >= (breakup_at + interval '8 weeks')
            AND NOT v_has_relationship
          THEN COALESCE(eligible_for_dating_opt_in_at, now())
          ELSE NULL
        END
    WHERE id = p_journey_id
    RETURNING * INTO v_journey;
  END IF;

  RETURN v_journey;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_or_create_healing_journey(
  p_relationship_id uuid DEFAULT NULL,
  p_breakup_at timestamptz DEFAULT NULL,
  p_breakup_at_source text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_relationship public.relationships%ROWTYPE;
  v_existing uuid;
  v_breakup_at timestamptz;
  v_source text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;

  IF p_relationship_id IS NOT NULL THEN
    SELECT * INTO v_relationship
    FROM public.relationships
    WHERE id = p_relationship_id
      AND status = 'ended'
      AND (user_a = v_user_id OR user_b = v_user_id);

    IF NOT FOUND THEN
      RAISE EXCEPTION 'relationship_not_found' USING ERRCODE = '22023';
    END IF;

    v_breakup_at := v_relationship.ended_at;
    v_source := 'relationship';

    SELECT id INTO v_existing
    FROM public.healing_journeys
    WHERE user_id = v_user_id
      AND relationship_id = p_relationship_id
    LIMIT 1;
  ELSE
    IF p_breakup_at IS NULL OR p_breakup_at_source <> 'user_reported' THEN
      RAISE EXCEPTION 'invalid_breakup_context' USING ERRCODE = '22023';
    END IF;
    v_breakup_at := p_breakup_at;
    v_source := 'user_reported';

    SELECT id INTO v_existing
    FROM public.healing_journeys
    WHERE user_id = v_user_id
      AND relationship_id IS NULL
      AND status IN ('active', 'paused')
    LIMIT 1;
  END IF;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  INSERT INTO public.healing_journeys (
    user_id,
    relationship_id,
    breakup_at,
    breakup_at_source,
    status,
    current_stage
  ) VALUES (
    v_user_id,
    p_relationship_id,
    v_breakup_at,
    v_source,
    'active',
    1
  )
  RETURNING id INTO v_existing;

  RETURN v_existing;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_healing_reflection(
  p_journey_id uuid,
  p_answers jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;
  IF NOT public._healing_owns_journey(p_journey_id, v_user_id) THEN
    RAISE EXCEPTION 'journey_not_found' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_answers) <> 'object' THEN
    RAISE EXCEPTION 'invalid_answers' USING ERRCODE = '22023';
  END IF;

  UPDATE public.healing_journeys
  SET reflection_answers = p_answers
  WHERE id = p_journey_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_healing_reflection(
  p_journey_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;
  IF NOT public._healing_owns_journey(p_journey_id, v_user_id) THEN
    RAISE EXCEPTION 'journey_not_found' USING ERRCODE = '22023';
  END IF;

  UPDATE public.healing_journeys
  SET reflection_completed_at = COALESCE(reflection_completed_at, now()),
      current_stage = GREATEST(current_stage, 2)
  WHERE id = p_journey_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_healing_generated_stage(
  p_journey_id uuid,
  p_stage text,
  p_status text,
  p_observation text DEFAULT NULL,
  p_confidence text DEFAULT NULL,
  p_reflection_prompt text DEFAULT NULL,
  p_portrait text DEFAULT NULL,
  p_portrait_reflection text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_journey public.healing_journeys%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;
  IF p_stage NOT IN ('post_mortem', 'portrait') THEN
    RAISE EXCEPTION 'invalid_stage' USING ERRCODE = '22023';
  END IF;
  IF p_status NOT IN ('completed', 'skipped', 'insufficient_evidence', 'failed') THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_journey
  FROM public.healing_journeys
  WHERE id = p_journey_id
    AND user_id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'journey_not_found' USING ERRCODE = '22023';
  END IF;

  IF p_stage = 'post_mortem' THEN
    IF v_journey.reflection_completed_at IS NULL THEN
      RAISE EXCEPTION 'reflection_not_complete' USING ERRCODE = '22023';
    END IF;

    UPDATE public.healing_journeys
    SET post_mortem_status = p_status,
        post_mortem_observation = CASE WHEN p_status = 'completed' THEN p_observation ELSE NULL END,
        post_mortem_confidence = CASE WHEN p_status = 'completed' THEN p_confidence ELSE NULL END,
        post_mortem_reflection_prompt = CASE WHEN p_status = 'completed' THEN p_reflection_prompt ELSE NULL END,
        post_mortem_completed_at = COALESCE(post_mortem_completed_at, now()),
        current_stage = GREATEST(current_stage, 3)
    WHERE id = p_journey_id;
  ELSE
    IF v_journey.pattern_awareness_completed_at IS NULL THEN
      RAISE EXCEPTION 'pattern_awareness_not_complete' USING ERRCODE = '22023';
    END IF;

    UPDATE public.healing_journeys
    SET portrait_status = p_status,
        portrait_text = CASE WHEN p_status = 'completed' THEN p_portrait ELSE NULL END,
        portrait_reflection = CASE
          WHEN p_status = 'completed' THEN p_portrait_reflection
          ELSE portrait_reflection
        END,
        portrait_prompt = CASE WHEN p_status = 'completed' THEN p_reflection_prompt ELSE NULL END,
        portrait_completed_at = COALESCE(portrait_completed_at, now()),
        current_stage = GREATEST(current_stage, 5)
    WHERE id = p_journey_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_healing_pattern_awareness(
  p_journey_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_journey public.healing_journeys%ROWTYPE;
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
  IF v_journey.post_mortem_completed_at IS NULL THEN
    RAISE EXCEPTION 'post_mortem_not_complete' USING ERRCODE = '22023';
  END IF;

  UPDATE public.healing_journeys
  SET pattern_awareness_completed_at = COALESCE(pattern_awareness_completed_at, now()),
      current_stage = GREATEST(current_stage, 4)
  WHERE id = p_journey_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_healing_readiness_without_score(
  p_journey_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_journey public.healing_journeys%ROWTYPE;
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

  UPDATE public.healing_journeys
  SET readiness_stage_completed_at = COALESCE(readiness_stage_completed_at, now()),
      current_stage = 5
  WHERE id = p_journey_id;

  PERFORM public._healing_refresh_status(p_journey_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_latest_healing_readiness_attempt(
  p_journey_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_attempt public.healing_readiness_attempts%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;
  IF NOT public._healing_owns_journey(p_journey_id, v_user_id) THEN
    RAISE EXCEPTION 'journey_not_found' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_attempt
  FROM public.healing_readiness_attempts
  WHERE journey_id = p_journey_id
  ORDER BY submitted_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'id', v_attempt.id,
    'journey_id', v_attempt.journey_id,
    'score', v_attempt.score,
    'answers', v_attempt.answers,
    'scoring_version', v_attempt.scoring_version,
    'submitted_at', v_attempt.submitted_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_healing_readiness(
  p_journey_id uuid,
  p_answers jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
    'is_eligible', v_updated.status = 'eligible_for_dating_opt_in',
    'attempt_id', v_attempt_id,
    'message', CASE
      WHEN v_score <= 70 THEN 'Your answers suggest there may be more you want to explore. Go at your own pace.'
      WHEN now() < (v_journey.breakup_at + interval '8 weeks') THEN
        'Your check-in is complete. Dating Mode remains unavailable until '
        || to_char((v_journey.breakup_at + interval '8 weeks') AT TIME ZONE 'UTC', 'DD Mon YYYY')
        || '.'
      ELSE 'You can choose whether to explore Dating Mode when it becomes available.'
    END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.archive_healing_journey(
  p_journey_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;
  UPDATE public.healing_journeys
  SET status = 'archived'
  WHERE id = p_journey_id
    AND user_id = v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_healing_journey(
  p_journey_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;
  DELETE FROM public.healing_journeys
  WHERE id = p_journey_id
    AND user_id = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public._healing_refresh_status(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_or_create_healing_journey(uuid, timestamptz, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_healing_reflection(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_healing_reflection(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_healing_generated_stage(uuid, text, text, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_healing_pattern_awareness(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_healing_readiness_without_score(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_latest_healing_readiness_attempt(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_healing_readiness(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.archive_healing_journey(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_healing_journey(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_or_create_healing_journey(uuid, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_healing_reflection(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_healing_reflection(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_healing_generated_stage(uuid, text, text, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_healing_pattern_awareness(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_healing_readiness_without_score(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_latest_healing_readiness_attempt(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_healing_readiness(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_healing_journey(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_healing_journey(uuid) TO authenticated;
