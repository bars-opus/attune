-- Golden fixtures for Alignment v1 (Spec §16: "Golden fixtures prove
-- symmetry, determinism, boundedness, provenance, missingness neutrality,
-- and explanation fidelity").
--
-- The scorer is IMMUTABLE and reads no tables, so these run without any
-- fixture users -- the inputs are the whole world it can see.
BEGIN;

-- A config small enough to reason about by hand.
CREATE TEMP TABLE t_cfg AS
SELECT jsonb_build_object(
  'transform_version', 'test_1',
  'weights', jsonb_build_object(
    'a', jsonb_build_object('kind','scalar','weight',1.0),
    'b', jsonb_build_object('kind','scalar','weight',3.0),
    'vals', jsonb_build_object('kind','set','weight',2.0)
  ),
  'bands', jsonb_build_object('promising',0.75,'some',0.5),
  'min_confidence_for_band', 0.5,
  'reason_similar_threshold', 0.7,
  'max_reasons', 3,
  'phrases', jsonb_build_object(
    'a', jsonb_build_object('similar','A similar','differs','A differs'),
    'b', jsonb_build_object('similar','B similar','differs','B differs')
  )
) AS cfg;

-- ---------------------------------------------------------------------
-- Symmetry: score(a,b) = score(b,a). §6.2.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_cfg jsonb := (SELECT cfg FROM t_cfg);
  x jsonb := '{"a":0.2,"b":0.9,"vals":["x","y"]}'::jsonb;
  y jsonb := '{"a":0.7,"b":0.4,"vals":["y","z"]}'::jsonb;
  v_ab jsonb;
  v_ba jsonb;
BEGIN
  v_ab := public.dating_alignment_score(x, y, v_cfg);
  v_ba := public.dating_alignment_score(y, x, v_cfg);

  IF (v_ab->>'score') IS DISTINCT FROM (v_ba->>'score') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: asymmetric score % vs %',
      v_ab->>'score', v_ba->>'score';
  END IF;
  IF (v_ab->>'display_band') IS DISTINCT FROM (v_ba->>'display_band') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: asymmetric band';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- Determinism: same inputs, same output, every time. §6.2.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_cfg jsonb := (SELECT cfg FROM t_cfg);
  x jsonb := '{"a":0.2,"b":0.9,"vals":["x","y"]}'::jsonb;
  y jsonb := '{"a":0.7,"b":0.4,"vals":["y","z"]}'::jsonb;
  v_first jsonb;
  i int;
BEGIN
  v_first := public.dating_alignment_score(x, y, v_cfg);
  FOR i IN 1..5 LOOP
    IF public.dating_alignment_score(x, y, v_cfg) IS DISTINCT FROM v_first THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: non-deterministic on run %', i;
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- Golden values: the score is what hand-computation says it is.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_cfg jsonb := (SELECT cfg FROM t_cfg);
  v_r jsonb;
  v_expected numeric;
BEGIN
  -- a: |0.2-0.7| -> sim 0.5, weight 1
  -- b: |0.9-0.4| -> sim 0.5, weight 3
  -- vals: {x,y} vs {y,z} -> inter 1, union 3 -> 1/3, weight 2
  -- weighted = 0.5*1 + 0.5*3 + (1/3)*2 = 0.5 + 1.5 + 0.666667 = 2.666667
  -- present  = 6  ->  0.444444
  v_r := public.dating_alignment_score(
    '{"a":0.2,"b":0.9,"vals":["x","y"]}'::jsonb,
    '{"a":0.7,"b":0.4,"vals":["y","z"]}'::jsonb, v_cfg);

  v_expected := round((0.5*1 + 0.5*3 + (1.0/3.0)*2) / 6.0, 6);
  IF abs((v_r->>'score')::numeric - v_expected) > 0.000001 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expected score %, got %',
      v_expected, v_r->>'score';
  END IF;

  -- All three components present -> full confidence.
  IF (v_r->>'confidence')::numeric <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expected confidence 1, got %',
      v_r->>'confidence';
  END IF;

  -- 0.444 is below the 0.5 "some" threshold.
  IF v_r->>'display_band' <> 'limited_signal' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expected limited_signal, got %',
      v_r->>'display_band';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- Missingness neutrality: a missing component must not depress the score.
-- §6.2 -- this is the property that keeps sparse profiles from reading as
-- poor fits.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_cfg jsonb := (SELECT cfg FROM t_cfg);
  v_full jsonb;
  v_sparse jsonb;
BEGIN
  -- Identical on 'a'; the sparse pair simply lacks 'b' and 'vals'.
  v_full := public.dating_alignment_score(
    '{"a":0.5,"b":0.5}'::jsonb, '{"a":0.5,"b":0.5}'::jsonb, v_cfg);
  v_sparse := public.dating_alignment_score(
    '{"a":0.5}'::jsonb, '{"a":0.5}'::jsonb, v_cfg);

  IF (v_sparse->>'score')::numeric <> (v_full->>'score')::numeric THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: missing data changed the score (% vs %)',
      v_sparse->>'score', v_full->>'score';
  END IF;

  -- Confidence MUST fall, though -- that is where missingness shows up.
  IF (v_sparse->>'confidence')::numeric >= (v_full->>'confidence')::numeric THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: sparse evidence did not lower confidence';
  END IF;

  -- And low confidence caps the band, so a perfect one-component match
  -- cannot present as promising ground.
  IF v_sparse->>'display_band' <> 'limited_signal' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: low-confidence pair showed band %',
      v_sparse->>'display_band';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- No evidence at all: not a zero score, an absence.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_cfg jsonb := (SELECT cfg FROM t_cfg);
  v_r jsonb;
BEGIN
  v_r := public.dating_alignment_score('{}'::jsonb, '{}'::jsonb, v_cfg);
  IF (v_r->>'score') IS NOT NULL THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: no shared evidence produced a score of %',
      v_r->>'score';
  END IF;
  IF v_r->>'display_band' <> 'limited_signal' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: empty evidence was not limited_signal';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- Boundedness: every score and component similarity is in [0,1], even for
-- out-of-range stored features. §6.2.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_cfg jsonb := (SELECT cfg FROM t_cfg);
  v_r jsonb;
  c jsonb;
BEGIN
  v_r := public.dating_alignment_score(
    '{"a":-5,"b":42,"vals":["x"]}'::jsonb,
    '{"a":9,"b":-3,"vals":["x"]}'::jsonb, v_cfg);

  IF (v_r->>'score')::numeric < 0 OR (v_r->>'score')::numeric > 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: score % outside [0,1]', v_r->>'score';
  END IF;

  FOR c IN SELECT * FROM jsonb_array_elements(v_r->'components') LOOP
    IF (c->>'similarity')::numeric < 0 OR (c->>'similarity')::numeric > 1 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: component % similarity %',
        c->>'feature_id', c->>'similarity';
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- Provenance: every component records what it was and where it came from.
-- §6.2.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_cfg jsonb := (SELECT cfg FROM t_cfg);
  v_r jsonb;
  c jsonb;
BEGIN
  v_r := public.dating_alignment_score(
    '{"a":0.5,"_provenance":{"a":"quiz:communication"}}'::jsonb,
    '{"a":0.5,"_provenance":{"a":"quiz:communication"}}'::jsonb, v_cfg);

  FOR c IN SELECT * FROM jsonb_array_elements(v_r->'components') LOOP
    IF c->>'feature_id' IS NULL OR c->>'weight' IS NULL
       OR c->>'transform_version' IS NULL THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: component missing provenance: %', c;
    END IF;
    IF c->>'source_a' IS DISTINCT FROM 'quiz:communication' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: source not carried through: %', c;
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- Explanation fidelity: reasons come from SCORED features only, and only
-- from the config's approved phrase table. §6.2/§6.3.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_cfg jsonb := (SELECT cfg FROM t_cfg);
  v_r jsonb;
  v_reasons jsonb;
  r jsonb;
BEGIN
  -- 'vals' is scored but has no phrase entry, so it must produce no reason.
  v_r := public.dating_alignment_score(
    '{"a":0.9,"b":0.9,"vals":["x"]}'::jsonb,
    '{"a":0.9,"b":0.1,"vals":["x"]}'::jsonb, v_cfg);
  v_reasons := public.dating_alignment_reasons(v_r, v_cfg);

  FOR r IN SELECT * FROM jsonb_array_elements(v_reasons) LOOP
    IF r->>'text' IS NULL THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: reason with no text: %', r;
    END IF;
    IF v_cfg->'phrases'->(r->>'feature_id') IS NULL THEN
      RAISE EXCEPTION
        'CONTRACT VIOLATED: reason for feature % has no approved phrase',
        r->>'feature_id';
    END IF;
    -- Every reason must be one of the two approved strings for its feature.
    IF r->>'text' NOT IN (
         v_cfg->'phrases'->(r->>'feature_id')->>'similar',
         v_cfg->'phrases'->(r->>'feature_id')->>'differs') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: invented reason text: %', r->>'text';
    END IF;
  END LOOP;

  -- 'a' matches exactly (1.0) and 'b' does not (0.2): the first must read
  -- as similar, the second as differs.
  IF NOT v_reasons::text LIKE '%A similar%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an exact match did not read similar';
  END IF;
  IF NOT v_reasons::text LIKE '%B differs%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a poor match did not read differs';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- The love-language prohibition (§6.1), enforced structurally.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_src text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'build_dating_feature_snapshot';

  -- The snapshot builder is the only path from raw data into ranking. If
  -- it never reads love_language, no weight can ever score it.
  IF v_src ~* 'love_language' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: the snapshot builder references love language';
  END IF;

  -- Nor may it read pair-level attachment data, which is attributable to a
  -- former partner (§6.1).
  IF v_src ~* 'attachment_compatibility_cache' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: the snapshot builder reads pair-level attachment data';
  END IF;

  -- Nor any of the categorically forbidden sources.
  IF v_src ~* '(healing_|readiness|safety_event|dating_reports|dating_blocks|messages)' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: the snapshot builder reads a forbidden source';
  END IF;

  -- And the shipped config must not carry a love-language weight.
  IF EXISTS (
    SELECT 1 FROM public.dating_algorithm_configs
    WHERE config->'weights' ? 'love_language'
  ) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a config weights love language';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- The shipped config must not be active without its review refs (§2.1).
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_state text;
BEGIN
  SELECT state INTO v_state FROM public.dating_algorithm_configs
  WHERE version = 'alignment_v1';

  IF v_state IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: alignment_v1 config was not seeded';
  END IF;
  IF v_state = 'active' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: alignment_v1 shipped active without recorded review';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- Generation is inert while the flag is off, whatever else is true.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_r jsonb;
BEGIN
  v_r := public.run_dating_candidate_generation();
  IF v_r->>'skipped' IS NULL THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: generation ran with the flag disabled: %', v_r;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- Ranking internals stay backend-only: the raw score must never be
-- reachable by a client, since the band exists to hide it.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_fn text;
BEGIN
  FOR v_fn IN
    SELECT unnest(ARRAY[
      'dating_alignment_score','dating_alignment_reasons',
      'dating_component_similarity','dating_set_similarity',
      'dating_pair_passes_hard_filters',
      'generate_dating_candidates_for_user','build_dating_feature_snapshot'])
  LOOP
    IF EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname='public' AND p.proname = v_fn
        AND (has_function_privilege('authenticated', p.oid, 'EXECUTE')
             OR has_function_privilege('anon', p.oid, 'EXECUTE'))
    ) THEN
      RAISE EXCEPTION
        'CONTRACT VIOLATED: % is executable by a client role', v_fn;
    END IF;
  END LOOP;
END $$;

ROLLBACK;
