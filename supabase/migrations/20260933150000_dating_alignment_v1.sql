-- Alignment v1: the pure scoring core (Spec §6, implementation order step 6).
--
-- Everything here is a deterministic function of its arguments. No table
-- reads, no now(), no random() -- so a score can be replayed from immutable
-- snapshots without exposing raw private data (§6.2 replayability), and the
-- golden-fixture test can pin exact values.
--
-- Evidence boundary (§6.1) is enforced one layer up, in the snapshot
-- builder: this file cannot reach a forbidden source because it cannot read
-- anything at all. Love-language is absent by construction -- there is no
-- love_language component, and adding one would fail the contract test.

-- ---------------------------------------------------------------------
-- 1. Component distance.
-- ---------------------------------------------------------------------
-- Both values are normalized to [0,1] before they reach here. Distance is
-- the absolute difference, so similarity is 1 - distance. Symmetric by
-- construction: |a-b| = |b-a|.
--
-- NULL on either side means "not present", which is NOT a distance of 1.
-- It returns NULL, and the caller drops the component from both numerator
-- and denominator. That is §6.2 missingness neutrality: an absent answer
-- must not read as a poor fit.
CREATE OR REPLACE FUNCTION public.dating_component_similarity(
  p_a numeric,
  p_b numeric
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_a IS NULL OR p_b IS NULL THEN NULL
    -- Clamped rather than rejected: a snapshot written by an older builder
    -- must not be able to push a component score outside [0,1] (§6.2
    -- boundedness).
    ELSE 1 - abs(
      LEAST(GREATEST(p_a, 0), 1) - LEAST(GREATEST(p_b, 0), 1)
    )
  END;
$$;

-- ---------------------------------------------------------------------
-- 2. Set overlap, for list-valued features (values, priorities).
-- ---------------------------------------------------------------------
-- Jaccard: |intersection| / |union|. Symmetric, bounded [0,1], and 1.0 only
-- for identical sets. Two empty sets are NOT similar -- they are absent
-- evidence, so this returns NULL and the component drops out.
CREATE OR REPLACE FUNCTION public.dating_set_similarity(
  p_a jsonb,
  p_b jsonb
)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_a text[];
  v_b text[];
  v_inter int;
  v_union int;
BEGIN
  IF p_a IS NULL OR p_b IS NULL
     OR jsonb_typeof(p_a) <> 'array' OR jsonb_typeof(p_b) <> 'array' THEN
    RETURN NULL;
  END IF;

  SELECT array_agg(DISTINCT v) INTO v_a
  FROM jsonb_array_elements_text(p_a) AS t(v);
  SELECT array_agg(DISTINCT v) INTO v_b
  FROM jsonb_array_elements_text(p_b) AS t(v);

  IF v_a IS NULL OR v_b IS NULL
     OR cardinality(v_a) = 0 OR cardinality(v_b) = 0 THEN
    RETURN NULL;
  END IF;

  SELECT count(*) INTO v_inter
  FROM (SELECT unnest(v_a) INTERSECT SELECT unnest(v_b)) AS s;
  SELECT count(*) INTO v_union
  FROM (SELECT unnest(v_a) UNION SELECT unnest(v_b)) AS s;

  IF v_union = 0 THEN RETURN NULL; END IF;
  RETURN v_inter::numeric / v_union::numeric;
END;
$$;

-- ---------------------------------------------------------------------
-- 3. The scorer.
-- ---------------------------------------------------------------------
-- Returns the full provenance record, not just a number (§6.2 provenance):
-- every component carries its feature id, both source types, the weight
-- applied, and the transform version. An auditor can reconstruct the total
-- from the components alone.
--
-- Weights come from the versioned config, never from constants here
-- ("placeholder constants are forbidden", §6.2). A component whose weight
-- is absent from the config is not scored.
--
-- Confidence is evidence completeness -- the share of available weight that
-- was actually present -- and is deliberately NOT a function of the score
-- (§6.2). A perfect match on one of six components is high-scoring and
-- low-confidence, and must present as such.
CREATE OR REPLACE FUNCTION public.dating_alignment_score(
  p_features_a jsonb,
  p_features_b jsonb,
  p_config jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_weights jsonb := COALESCE(p_config->'weights', '{}'::jsonb);
  v_transform text := COALESCE(p_config->>'transform_version', 'unknown');
  v_feature text;
  v_kind text;
  v_weight numeric;
  v_sim numeric;
  v_components jsonb := '[]'::jsonb;
  v_weighted_sum numeric := 0;
  v_present_weight numeric := 0;
  v_total_weight numeric := 0;
  v_score numeric;
  v_confidence numeric;
  v_band text;
BEGIN
  IF p_features_a IS NULL OR p_features_b IS NULL THEN
    RETURN NULL;
  END IF;

  -- Ordered so the component list is deterministic regardless of jsonb key
  -- ordering (§6.2 determinism).
  FOR v_feature, v_kind, v_weight IN
    SELECT key,
           COALESCE(value->>'kind', 'scalar'),
           (value->>'weight')::numeric
    FROM jsonb_each(v_weights)
    ORDER BY key
  LOOP
    CONTINUE WHEN v_weight IS NULL OR v_weight <= 0;
    v_total_weight := v_total_weight + v_weight;

    IF v_kind = 'set' THEN
      v_sim := public.dating_set_similarity(
        p_features_a->v_feature, p_features_b->v_feature);
    ELSE
      v_sim := public.dating_component_similarity(
        NULLIF(p_features_a->>v_feature, '')::numeric,
        NULLIF(p_features_b->>v_feature, '')::numeric);
    END IF;

    -- A missing component contributes to neither sum: it is dropped from
    -- the normalizer too, which is what keeps missingness neutral rather
    -- than penalizing.
    CONTINUE WHEN v_sim IS NULL;

    v_weighted_sum := v_weighted_sum + (v_sim * v_weight);
    v_present_weight := v_present_weight + v_weight;

    v_components := v_components || jsonb_build_object(
      'feature_id', v_feature,
      'kind', v_kind,
      'similarity', round(v_sim, 6),
      'weight', v_weight,
      'source_a', p_features_a->'_provenance'->>v_feature,
      'source_b', p_features_b->'_provenance'->>v_feature,
      'transform_version', v_transform
    );
  END LOOP;

  -- No approved component was present on both sides. Not a zero score --
  -- an absence of evidence, which the caller must not present as a poor
  -- match.
  IF v_present_weight = 0 THEN
    RETURN jsonb_build_object(
      'score', NULL,
      'confidence', 0,
      'display_band', 'limited_signal',
      'components', v_components,
      'transform_version', v_transform,
      'present_weight', 0,
      'total_weight', v_total_weight
    );
  END IF;

  v_score := v_weighted_sum / v_present_weight;
  v_confidence := CASE
    WHEN v_total_weight = 0 THEN 0
    ELSE v_present_weight / v_total_weight
  END;

  -- §6.2 band mapping. Thresholds live in the config, not here. A band is
  -- the ONLY thing shown to a user: the raw score never leaves the backend,
  -- which is what forbids "84% compatible" (§6.3) structurally rather than
  -- by copy review.
  --
  -- Low confidence caps the band regardless of score: a strong agreement on
  -- one component is not promising shared ground, and saying so would be
  -- the false precision §6.5 tests for.
  v_band := CASE
    WHEN v_confidence < COALESCE((p_config->>'min_confidence_for_band')::numeric, 0.5)
      THEN 'limited_signal'
    WHEN v_score >= COALESCE((p_config->'bands'->>'promising')::numeric, 0.75)
      THEN 'promising_shared_ground'
    WHEN v_score >= COALESCE((p_config->'bands'->>'some')::numeric, 0.5)
      THEN 'some_shared_ground'
    ELSE 'limited_signal'
  END;

  RETURN jsonb_build_object(
    'score', round(v_score, 6),
    'confidence', round(v_confidence, 6),
    'display_band', v_band,
    'components', v_components,
    'transform_version', v_transform,
    'present_weight', v_present_weight,
    'total_weight', v_total_weight
  );
END;
$$;

-- ---------------------------------------------------------------------
-- 4. Explanations.
-- ---------------------------------------------------------------------
-- §6.2 explainability fidelity: reasons are DERIVED from scored components,
-- never authored. This maps a feature id and its similarity to approved
-- clinical language (§6.3) via the config's own phrase table -- so changing
-- the copy is a reviewed config change, not a code edit.
--
-- Only components that were actually scored can produce a reason, and only
-- the top few, so a sparse profile yields fewer reasons rather than vaguer
-- ones.
CREATE OR REPLACE FUNCTION public.dating_alignment_reasons(
  p_result jsonb,
  p_config jsonb
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(jsonb_agg(reason ORDER BY sim DESC, feature_id), '[]'::jsonb)
  FROM (
    SELECT
      c->>'feature_id' AS feature_id,
      (c->>'similarity')::numeric AS sim,
      jsonb_build_object(
        'feature_id', c->>'feature_id',
        'text', p_config->'phrases'->(c->>'feature_id')->>(
          CASE
            WHEN (c->>'similarity')::numeric
                 >= COALESCE((p_config->>'reason_similar_threshold')::numeric, 0.7)
              THEN 'similar'
            ELSE 'differs'
          END
        )
      ) AS reason
    FROM jsonb_array_elements(COALESCE(p_result->'components', '[]'::jsonb)) AS c
    WHERE p_config->'phrases'->(c->>'feature_id') IS NOT NULL
    ORDER BY (c->>'similarity')::numeric DESC, c->>'feature_id'
    LIMIT COALESCE((p_config->>'max_reasons')::int, 3)
  ) ranked
  WHERE reason->>'text' IS NOT NULL;
$$;

-- Backend-only. These are ranking internals: exposing them to a client
-- would hand out the raw score the band exists to hide.
REVOKE ALL ON FUNCTION public.dating_component_similarity(numeric, numeric)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dating_set_similarity(jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dating_alignment_score(jsonb, jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dating_alignment_reasons(jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;
