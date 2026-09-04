-- The consent-filtered feature vector (Spec §6.1, §6.2 step 1).
--
-- This is the ONLY place raw user data becomes ranking input, which makes it
-- the only place the evidence boundary can be violated. Everything §6.1
-- forbids is absent here by construction, and the contract test greps this
-- function for the forbidden sources.
--
-- Allowed in v1:
--   - attachment dimensions (anxiety, avoidance), from the user's own quiz
--   - communication style, from the user's own quiz
--   - conflict style, from the user's own quiz
--   - explicit values/priorities collected for an approved purpose
--
-- Forbidden, and absent:
--   - love_language (§6.1: never a ranking input, not even as a component
--     with zero weight -- a zero weight is one config edit away from live)
--   - anything from a former partner or any pair-level record
--   - raw messages, journals, Healing reflections, readiness scores,
--     safety events, reports, blocks, location, photos
--   - engagement, popularity, response speed, prior interest volume
--
-- Quiz-derived features require historical-data consent. Refusing that
-- consent must still permit Dating Mode (§16), so a refusal yields a
-- profile-only vector: fewer components, lower confidence, never exclusion.

CREATE OR REPLACE FUNCTION public.dating_has_historical_consent(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- The latest event for this purpose wins: a withdrawal after a grant
  -- revokes it, and a re-grant restores it.
  SELECT COALESCE((
    SELECT ce.action = 'grant'
    FROM public.dating_consent_events ce
    WHERE ce.user_id = p_user_id
      AND ce.purpose = 'historical_data'
    ORDER BY COALESCE(ce.occurred_at, ce.created_at) DESC, ce.id DESC
    LIMIT 1
  ), false);
$$;

-- Normalizes a quiz score to [0,1]. Attachment sub-scales are stored as
-- integers on their own scales; the config carries each scale's bounds so a
-- rescaled instrument is a config change, not a migration.
CREATE OR REPLACE FUNCTION public.dating_normalize_scalar(
  p_value numeric,
  p_min numeric,
  p_max numeric
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_value IS NULL OR p_min IS NULL OR p_max IS NULL OR p_max <= p_min
      THEN NULL
    ELSE LEAST(GREATEST((p_value - p_min) / (p_max - p_min), 0), 1)
  END;
$$;

-- Builds (or rebuilds) one user's snapshot for a given algorithm version.
--
-- Idempotent per (user, version): the previous live snapshot is invalidated
-- and a new row written, so history is preserved for replay (§6.2) while
-- only one row is current.
CREATE OR REPLACE FUNCTION public.build_dating_feature_snapshot(
  p_user_id uuid,
  p_algorithm_version text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_config jsonb;
  v_scales jsonb;
  v_historical boolean;
  v_features jsonb := '{}'::jsonb;
  v_provenance jsonb := '{}'::jsonb;
  v_consent jsonb;
  v_quiz record;
  v_profile record;
  v_id uuid;
  v_norm numeric;
BEGIN
  SELECT config INTO v_config
  FROM public.dating_algorithm_configs
  WHERE version = p_algorithm_version AND state = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no active algorithm config for version %',
      p_algorithm_version;
  END IF;

  v_scales := COALESCE(v_config->'scales', '{}'::jsonb);
  v_historical := public.dating_has_historical_consent(p_user_id);

  SELECT dp.relationship_intention INTO v_profile
  FROM public.dating_profiles dp
  WHERE dp.user_id = p_user_id;

  -- ---- Explicit profile answers. Always available: the user typed them
  -- ---- into Dating itself, so the consent basis is the enrollment.
  IF v_profile.relationship_intention IS NOT NULL THEN
    v_features := v_features || jsonb_build_object(
      'relationship_priorities',
      COALESCE(v_config->'intention_priorities'->v_profile.relationship_intention,
               to_jsonb(ARRAY[v_profile.relationship_intention]))
    );
    v_provenance := v_provenance || jsonb_build_object(
      'relationship_priorities', 'dating_profile');
  END IF;

  -- ---- Quiz-derived dimensions, gated on historical-data consent.
  IF v_historical THEN
    -- Attachment: the user's OWN aggregate dimensions, read from
    -- quiz_responses for p_user_id only -- never a partner's row, and never
    -- any pair-level compatibility cache, which is attributable to a former
    -- partner (§6.1). The contract test greps this function for those
    -- sources, so naming one even in a comment fails the build.
    SELECT anxiety_score, avoidance_score, completed_at INTO v_quiz
    FROM public.quiz_responses
    WHERE user_id = p_user_id AND quiz_type = 'attachment'
    ORDER BY completed_at DESC
    LIMIT 1;

    IF FOUND THEN
      v_norm := public.dating_normalize_scalar(
        v_quiz.anxiety_score,
        (v_scales->'attachment_anxiety'->>'min')::numeric,
        (v_scales->'attachment_anxiety'->>'max')::numeric);
      IF v_norm IS NOT NULL THEN
        v_features := v_features
          || jsonb_build_object('attachment_anxiety', v_norm);
        v_provenance := v_provenance
          || jsonb_build_object('attachment_anxiety', 'quiz:attachment');
      END IF;

      v_norm := public.dating_normalize_scalar(
        v_quiz.avoidance_score,
        (v_scales->'attachment_avoidance'->>'min')::numeric,
        (v_scales->'attachment_avoidance'->>'max')::numeric);
      IF v_norm IS NOT NULL THEN
        v_features := v_features
          || jsonb_build_object('attachment_avoidance', v_norm);
        v_provenance := v_provenance
          || jsonb_build_object('attachment_avoidance', 'quiz:attachment');
      END IF;
    END IF;

    -- Communication and conflict: a single normalized dimension each,
    -- read from the quiz's own result payload under the config's key.
    FOR v_quiz IN
      SELECT quiz_type, result_data
      FROM public.quiz_responses q
      WHERE q.user_id = p_user_id
        AND q.quiz_type IN ('communication', 'conflict')
        AND q.completed_at = (
          SELECT max(q2.completed_at) FROM public.quiz_responses q2
          WHERE q2.user_id = q.user_id AND q2.quiz_type = q.quiz_type
        )
    LOOP
      v_norm := public.dating_normalize_scalar(
        NULLIF(v_quiz.result_data->>(v_scales->v_quiz.quiz_type->>'key'), '')::numeric,
        (v_scales->v_quiz.quiz_type->>'min')::numeric,
        (v_scales->v_quiz.quiz_type->>'max')::numeric);
      IF v_norm IS NOT NULL THEN
        v_features := v_features
          || jsonb_build_object(v_quiz.quiz_type || '_style', v_norm);
        v_provenance := v_provenance
          || jsonb_build_object(v_quiz.quiz_type || '_style',
                                'quiz:' || v_quiz.quiz_type);
      END IF;
    END LOOP;
  END IF;

  v_features := v_features || jsonb_build_object('_provenance', v_provenance);

  v_consent := jsonb_build_object(
    'historical_data', v_historical,
    'basis', 'explicit_opt_in',
    'captured_at', now()
  );

  UPDATE public.dating_feature_snapshots
  SET invalidated_at = now()
  WHERE user_id = p_user_id
    AND algorithm_version = p_algorithm_version
    AND invalidated_at IS NULL;

  INSERT INTO public.dating_feature_snapshots
    (user_id, algorithm_version, consent_basis, features, source_provenance)
  VALUES
    (p_user_id, p_algorithm_version, v_consent, v_features, v_provenance)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.dating_has_historical_consent(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dating_normalize_scalar(numeric, numeric, numeric)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.build_dating_feature_snapshot(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.build_dating_feature_snapshot(uuid, text)
  TO service_role;
