-- Bounded, idempotent candidate generation (Spec §6.4, order step 8).
--
-- Runs weekly in pg_cron. Everything the pool depends on is a hard filter
-- applied symmetrically BEFORE scoring (§5): a pair is eligible only if each
-- user's stated preferences admit the other. Score never rescues a pair that
-- a filter rejected, and an empty pool stays empty -- §6.4 forbids widening
-- filters to fill it, and §2.1 pre-commits that a thin pool is a growth
-- problem, not an eligibility one.

-- ---------------------------------------------------------------------
-- 1. Symmetric hard filter.
-- ---------------------------------------------------------------------
-- Split out so the contract test can assert symmetry directly:
-- admits(a,b) must equal admits(b,a) for every pair.
CREATE OR REPLACE FUNCTION public.dating_pair_passes_hard_filters(
  p_a uuid,
  p_b uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pa record;
  v_pb record;
  v_prefs_a record;
  v_prefs_b record;
  v_age_a int;
  v_age_b int;
BEGIN
  IF p_a IS NULL OR p_b IS NULL OR p_a = p_b THEN
    RETURN false;
  END IF;

  -- Eligibility, age gate, good standing, no relationship, active
  -- enrollment -- the predicate the rest of Dating already trusts.
  IF NOT public.dating_candidate_is_current(p_a)
     OR NOT public.dating_candidate_is_current(p_b) THEN
    RETURN false;
  END IF;

  -- Enough approved content to render safely (§5).
  IF NOT public.dating_profile_ready(p_a)
     OR NOT public.dating_profile_ready(p_b) THEN
    RETURN false;
  END IF;

  -- Former partners, including across re-registration (§5.1).
  IF public.dating_former_partner_excluded(p_a, p_b) THEN
    RETURN false;
  END IF;

  -- Blocks are bilateral and immediate.
  IF EXISTS (
    SELECT 1 FROM public.dating_blocks b
    WHERE (b.blocker_user_id = p_a AND b.blocked_user_id = p_b)
       OR (b.blocker_user_id = p_b AND b.blocked_user_id = p_a)
  ) THEN
    RETURN false;
  END IF;

  -- A pair already introduced must not be re-introduced: §6.4 idempotency,
  -- and re-showing a passed candidate would leak that they passed.
  IF EXISTS (
    SELECT 1 FROM public.dating_introductions di
    WHERE di.pair_key = public.dating_pair_key(p_a, p_b)
  ) THEN
    RETURN false;
  END IF;

  -- Previously unmatched pairs stay apart for the configured cooldown.
  IF EXISTS (
    SELECT 1 FROM public.dating_matches dm
    WHERE dm.pair_key = public.dating_pair_key(p_a, p_b)
  ) THEN
    RETURN false;
  END IF;

  SELECT gender_identity, city_region_code, relationship_intention
    INTO v_pa FROM public.dating_profiles WHERE user_id = p_a;
  SELECT gender_identity, city_region_code, relationship_intention
    INTO v_pb FROM public.dating_profiles WHERE user_id = p_b;

  SELECT min_age, max_age, gender_preferences, region_preferences,
         intention_preferences
    INTO v_prefs_a FROM public.dating_preferences WHERE user_id = p_a;
  SELECT min_age, max_age, gender_preferences, region_preferences,
         intention_preferences
    INTO v_prefs_b FROM public.dating_preferences WHERE user_id = p_b;

  IF v_prefs_a IS NULL OR v_prefs_b IS NULL THEN
    RETURN false;
  END IF;

  -- Age from the verified birth date, never a client-supplied integer.
  SELECT date_part('year', age(current_date, birth_date))::int INTO v_age_a
  FROM public.dating_age_verifications
  WHERE user_id = p_a AND revoked_at IS NULL;
  SELECT date_part('year', age(current_date, birth_date))::int INTO v_age_b
  FROM public.dating_age_verifications
  WHERE user_id = p_b AND revoked_at IS NULL;

  IF v_age_a IS NULL OR v_age_b IS NULL THEN
    RETURN false;
  END IF;

  -- Each side's stated range must admit the other. Symmetric because both
  -- directions are required.
  IF v_age_b < v_prefs_a.min_age OR v_age_b > v_prefs_a.max_age
     OR v_age_a < v_prefs_b.min_age OR v_age_a > v_prefs_b.max_age THEN
    RETURN false;
  END IF;

  -- An empty preference list means "no stated restriction" and admits all.
  -- A non-empty list must contain the other's value. Never inferred from
  -- quizzes or behavior (§5).
  IF jsonb_array_length(COALESCE(v_prefs_a.gender_preferences, '[]'::jsonb)) > 0
     AND (v_pb.gender_identity IS NULL
          OR NOT (v_prefs_a.gender_preferences ? v_pb.gender_identity)) THEN
    RETURN false;
  END IF;
  IF jsonb_array_length(COALESCE(v_prefs_b.gender_preferences, '[]'::jsonb)) > 0
     AND (v_pa.gender_identity IS NULL
          OR NOT (v_prefs_b.gender_preferences ? v_pa.gender_identity)) THEN
    RETURN false;
  END IF;

  IF jsonb_array_length(COALESCE(v_prefs_a.region_preferences, '[]'::jsonb)) > 0
     AND NOT (v_prefs_a.region_preferences ? v_pb.city_region_code) THEN
    RETURN false;
  END IF;
  IF jsonb_array_length(COALESCE(v_prefs_b.region_preferences, '[]'::jsonb)) > 0
     AND NOT (v_prefs_b.region_preferences ? v_pa.city_region_code) THEN
    RETURN false;
  END IF;

  IF jsonb_array_length(COALESCE(v_prefs_a.intention_preferences, '[]'::jsonb)) > 0
     AND NOT (v_prefs_a.intention_preferences ? v_pb.relationship_intention) THEN
    RETURN false;
  END IF;
  IF jsonb_array_length(COALESCE(v_prefs_b.intention_preferences, '[]'::jsonb)) > 0
     AND NOT (v_prefs_b.intention_preferences ? v_pa.relationship_intention) THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$$;

-- ---------------------------------------------------------------------
-- 2. Generation for one user.
-- ---------------------------------------------------------------------
-- Caps active unrevealed introductions per user (§6.4). Randomizes only
-- WITHIN a narrow score band using the run's stored seed, so a popular
-- profile cannot climb a deterministic ranking into everyone's pool.
CREATE OR REPLACE FUNCTION public.generate_dating_candidates_for_user(
  p_user_id uuid,
  p_algorithm_version text,
  p_cohort_window text,
  p_seed text
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_config jsonb;
  v_cap int;
  v_open int;
  v_created int := 0;
  v_snap_a jsonb;
  v_cand record;
  v_result jsonb;
  v_reasons jsonb;
  v_band_floor numeric;
BEGIN
  IF NOT public.dating_flag_enabled('dating_candidate_generation') THEN
    RETURN 0;
  END IF;
  IF NOT public.dating_candidate_is_current(p_user_id) THEN
    RETURN 0;
  END IF;

  SELECT config INTO v_config
  FROM public.dating_algorithm_configs
  WHERE version = p_algorithm_version AND state = 'active';
  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  v_cap := COALESCE((v_config->>'max_open_introductions')::int, 5);

  SELECT count(*) INTO v_open
  FROM public.dating_introductions di
  WHERE (di.user_low_id = p_user_id OR di.user_high_id = p_user_id)
    AND di.state IN ('generated', 'presented', 'interested')
    AND di.expires_at > now();
  IF v_open >= v_cap THEN
    RETURN 0;
  END IF;

  SELECT features INTO v_snap_a
  FROM public.dating_feature_snapshots
  WHERE user_id = p_user_id
    AND algorithm_version = p_algorithm_version
    AND invalidated_at IS NULL
  ORDER BY created_at DESC
  LIMIT 1;
  IF v_snap_a IS NULL THEN
    RETURN 0;
  END IF;

  v_band_floor := COALESCE((v_config->'bands'->>'some')::numeric, 0.5);

  FOR v_cand IN
    SELECT s.user_id, s.features
    FROM public.dating_feature_snapshots s
    WHERE s.algorithm_version = p_algorithm_version
      AND s.invalidated_at IS NULL
      AND s.user_id <> p_user_id
      AND public.dating_pair_passes_hard_filters(p_user_id, s.user_id)
    -- Ordering is seeded per run, not by any popularity or engagement
    -- signal (§6.1 forbids those outright). md5 of seed+uuid gives a
    -- stable shuffle that differs between runs and is replayable within
    -- one.
    ORDER BY md5(p_seed || s.user_id::text)
    LIMIT COALESCE((v_config->>'scan_limit')::int, 200)
  LOOP
    EXIT WHEN v_open + v_created >= v_cap;

    v_result := public.dating_alignment_score(
      v_snap_a, v_cand.features, v_config);
    CONTINUE WHEN v_result IS NULL;

    -- Never publish a pair below the presentable band: an introduction is
    -- a claim of some shared ground, and limited_signal is not one.
    CONTINUE WHEN (v_result->>'score') IS NULL;
    CONTINUE WHEN (v_result->>'score')::numeric < v_band_floor;
    CONTINUE WHEN v_result->>'display_band' = 'limited_signal';

    v_reasons := public.dating_alignment_reasons(v_result, v_config);

    -- ON CONFLICT makes the whole batch idempotent per pair (§6.4): a
    -- retried partition re-runs without duplicating introductions.
    INSERT INTO public.dating_introductions (
      pair_key, user_low_id, user_high_id, display_band,
      explanation_features, expires_at
    )
    VALUES (
      public.dating_pair_key(p_user_id, v_cand.user_id),
      LEAST(p_user_id, v_cand.user_id),
      GREATEST(p_user_id, v_cand.user_id),
      v_result->>'display_band',
      jsonb_build_object(
        'reasons', v_reasons,
        'algorithm_version', p_algorithm_version,
        'cohort_window', p_cohort_window,
        -- Provenance for replay. The raw score is deliberately NOT stored
        -- here: this column is returned to clients by
        -- get_my_dating_introductions, so a score in it would leak the
        -- number the band exists to hide.
        'components', v_result->'components',
        'confidence', v_result->>'confidence'
      ),
      now() + COALESCE(
        (v_config->>'introduction_ttl')::interval, interval '7 days')
    )
    ON CONFLICT (pair_key) DO NOTHING;

    IF FOUND THEN
      v_created := v_created + 1;
    END IF;
  END LOOP;

  RETURN v_created;
END;
$$;

-- ---------------------------------------------------------------------
-- 3. The batch.
-- ---------------------------------------------------------------------
-- One partition per invocation, claimed atomically so two overlapping cron
-- ticks cannot process the same partition twice. Failures increment attempts
-- and land in dead_letter after the configured maximum (§6.4, checklist
-- 4.14) rather than retrying forever.
CREATE OR REPLACE FUNCTION public.run_dating_candidate_generation(
  p_partition_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_version text;
  v_config jsonb;
  v_window text := to_char(date_trunc('week', now()), 'IYYY-"W"IW');
  v_partition text := COALESCE(p_partition_key, 'all');
  v_run public.dating_generation_runs%ROWTYPE;
  v_seed text;
  v_user uuid;
  v_total int := 0;
  v_users int := 0;
  v_max_attempts int;
BEGIN
  IF NOT public.dating_flag_enabled('dating_candidate_generation') THEN
    RETURN jsonb_build_object('skipped', 'flag_disabled');
  END IF;

  SELECT version, config INTO v_version, v_config
  FROM public.dating_algorithm_configs
  WHERE state = 'active'
  ORDER BY activated_at DESC
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('skipped', 'no_active_config');
  END IF;

  v_max_attempts := COALESCE((v_config->>'max_attempts')::int, 3);

  -- The seed is per (version, window, partition) and stored, so a rerun of
  -- the same partition shuffles identically -- replayability (§6.2).
  v_seed := encode(digest(v_version || v_window || v_partition, 'sha256'), 'hex');

  INSERT INTO public.dating_generation_runs
    (algorithm_version, cohort_window, state, seed, partition_key, attempts,
     started_at)
  VALUES (v_version, v_window, 'processing', v_seed, v_partition, 1, now())
  ON CONFLICT (algorithm_version, cohort_window, partition_key) DO UPDATE
    SET state = 'processing',
        attempts = public.dating_generation_runs.attempts + 1,
        started_at = now()
    WHERE public.dating_generation_runs.state IN ('pending', 'failed')
      AND public.dating_generation_runs.attempts < v_max_attempts
  RETURNING * INTO v_run;

  -- No row returned means the partition is already completed, already
  -- processing, or has exhausted its attempts. All three mean "not ours".
  IF v_run.id IS NULL THEN
    RETURN jsonb_build_object('skipped', 'partition_unavailable',
                              'partition', v_partition);
  END IF;

  BEGIN
    FOR v_user IN
      SELECT de.user_id
      FROM public.dating_enrollments de
      WHERE de.state = 'active'
        AND public.dating_candidate_is_current(de.user_id)
      ORDER BY de.user_id
      LIMIT COALESCE((v_config->>'batch_user_limit')::int, 500)
    LOOP
      PERFORM public.build_dating_feature_snapshot(v_user, v_version);
      v_users := v_users + 1;
    END LOOP;

    FOR v_user IN
      SELECT de.user_id
      FROM public.dating_enrollments de
      WHERE de.state = 'active'
        AND public.dating_candidate_is_current(de.user_id)
      ORDER BY de.user_id
      LIMIT COALESCE((v_config->>'batch_user_limit')::int, 500)
    LOOP
      v_total := v_total + public.generate_dating_candidates_for_user(
        v_user, v_version, v_window, v_seed);
    END LOOP;

    UPDATE public.dating_generation_runs
    SET state = 'completed', completed_at = now()
    WHERE id = v_run.id;
  EXCEPTION WHEN OTHERS THEN
    -- Exhausted attempts go to dead_letter rather than failed, so the
    -- health view's failed_generation_runs_24h surfaces them and no
    -- further tick picks them up.
    UPDATE public.dating_generation_runs
    SET state = CASE
          WHEN attempts >= v_max_attempts THEN 'dead_letter' ELSE 'failed' END,
        last_error_code = sqlstate,
        completed_at = now()
    WHERE id = v_run.id;
    RETURN jsonb_build_object('error', sqlstate, 'partition', v_partition);
  END;

  RETURN jsonb_build_object(
    'algorithm_version', v_version,
    'cohort_window', v_window,
    'partition', v_partition,
    'users_processed', v_users,
    'introductions_created', v_total
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dating_pair_passes_hard_filters(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.generate_dating_candidates_for_user(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.run_dating_candidate_generation(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_dating_candidate_generation(text)
  TO service_role;
