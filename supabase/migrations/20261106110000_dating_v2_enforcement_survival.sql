-- Spec 2 W1a, migration 2 (spec §4.9 W1a #2, §4.3, §4.5, §6.3; Q5, S-5,
-- I-16): what survives an account's deletion, keyed by phone HMAC.
--   * enforcement_records: one row per carried restriction (scope 'dating';
--     'opinions' reserved for Spec 1 W9d, never written here), idempotent
--     on source_restriction_id, purged after purge_after.
--   * dating_block_hmacs: a block pair by both numbers' HMACs; purge_after
--     stays NULL while both accounts exist.
--   * dating_reports: reporter and target become ON DELETE SET NULL; the
--     target's number is kept only as its HMAC in target_phone_hmac (64
--     lowercase hex, I-6). A surviving report is pseudonymised, not
--     anonymised: user ids removed, the target's HMAC, category and the
--     reporter's details kept.
--   * dating_matches: both members and the introduction become ON DELETE
--     SET NULL (else the introduction's cascade would delete the match);
--     closed_reason (spec §4.3's ten values, plus the kill switch's neutral
--     'other': owner 2026-11-06, PF-F2) and evidence_until; the order and
--     self CHECKs say NULL is allowed. A member deleted while the match is
--     active (any path that skips prepare_account_deletion) closes it with
--     account_deleted and the 30-day window (trigger, M-3).
--   * enforcement_records.purge_after is capped at created_at + 2 years
--     (+1 day of slack), M-4.
--   * block_dating_user re-created from its live body (20260703203000):
--     also writes the HMAC pair, and the match it closes gets
--     closed_reason 'blocked' and a 30-day evidence window.
--   * dating_account_in_good_standing re-created from its live body
--     (20260705210000): also false while an enforcement record for the
--     person's number is in effect, or a Spec 1 age_review / safety_review
--     hold is unresolved (spec §2.1 gate 3).
--   * dating_exclusion_key is fingerprinted on first sight
--     (private.dating_key_fingerprints; the fingerprint is the key's HMAC of
--     a fixed label). begin_dating_enrollment, activate_dating_profile and
--     run_dating_candidate_generation, re-created from their live bodies,
--     refuse quietly and count dating.exclusion_key.mismatch while a key is
--     set whose fingerprint differs from the stored one: under a rotated key
--     every carried restriction, block pair and exclusion would be void
--     without a trace (I-5, owner 2026-11-06). The key is never rotated or
--     replaced, and nothing is ever re-HMACed (never-introduce lists and
--     restriction stamps can't be re-keyed; owner checklist item 11, W1
--     final fix I-3): rotation waits for a verify-only secondary key.
--     A missing key is not a mismatch; its own guards refuse.
--   * dating_phone_hmac is no longer the service role's (I-4: a service key
--     must not test guessed numbers against the survivors' HMACs).
-- Grants (and the service_role revoke on introductions, interest actions
-- and matches, S-5) in 20261106110010_dating_v2_enforcement_survival_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.enforcement_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_hmac text NOT NULL CHECK (phone_hmac ~ '^[0-9a-f]{64}$'),
  scope text NOT NULL CHECK (scope IN ('dating', 'opinions')),
  source_restriction_id uuid UNIQUE,
  restriction_type text NOT NULL
    CHECK (restriction_type IN ('suspended', 'under_review', 'age_review', 'moderation_hold')),
  category text,
  confirmed_report_count integer NOT NULL DEFAULT 0 CHECK (confirmed_report_count >= 0),
  effect_until timestamptz,
  purge_after timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS enforcement_records_phone_hmac_idx ON public.enforcement_records (phone_hmac);
ALTER TABLE public.enforcement_records DROP CONSTRAINT IF EXISTS enforcement_records_purge_after_cap_check;
ALTER TABLE public.enforcement_records ADD CONSTRAINT enforcement_records_purge_after_cap_check
  CHECK (purge_after <= created_at + interval '2 years 1 day'); -- M-4: the 2-year retention, enforced
ALTER TABLE public.enforcement_records ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.enforcement_records IS
  'Spec 2 W1a (Q5, §6.3): a Dating restriction carried past account deletion, keyed by the number''s HMAC (dating_phone_hmac_for_user), kept 2 years. scope opinions is reserved for Spec 1 W9d (O4) and never written by Spec 2.';

CREATE TABLE IF NOT EXISTS public.dating_block_hmacs (
  blocker_hmac text NOT NULL CHECK (blocker_hmac ~ '^[0-9a-f]{64}$'),
  blocked_hmac text NOT NULL CHECK (blocked_hmac ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  purge_after timestamptz,
  PRIMARY KEY (blocker_hmac, blocked_hmac)
);
CREATE INDEX IF NOT EXISTS dating_block_hmacs_blocked_idx ON public.dating_block_hmacs (blocked_hmac);
ALTER TABLE public.dating_block_hmacs ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.dating_block_hmacs IS
  'Spec 2 W1a (Q5): a Dating block by both numbers'' HMACs. purge_after is NULL while both accounts exist and set to deletion + 2 years by prepare_account_deletion.';

-- Reports survive either side's deletion (pseudonymised), with the target's HMAC.
ALTER TABLE public.dating_reports ALTER COLUMN reporter_user_id DROP NOT NULL;
ALTER TABLE public.dating_reports ALTER COLUMN target_user_id DROP NOT NULL;
ALTER TABLE public.dating_reports ADD COLUMN IF NOT EXISTS target_phone_hmac text;
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_target_phone_hmac_check;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_target_phone_hmac_check
  CHECK (target_phone_hmac IS NULL OR target_phone_hmac ~ '^[0-9a-f]{64}$'); -- I-6: never a raw number
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_reporter_user_id_fkey;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_reporter_user_id_fkey
  FOREIGN KEY (reporter_user_id) REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_target_user_id_fkey;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_target_user_id_fkey
  FOREIGN KEY (target_user_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- Matches survive deletion as sealed records for the evidence window.
ALTER TABLE public.dating_matches ALTER COLUMN user_low_id DROP NOT NULL;
ALTER TABLE public.dating_matches ALTER COLUMN user_high_id DROP NOT NULL;
ALTER TABLE public.dating_matches ALTER COLUMN introduction_id DROP NOT NULL;
ALTER TABLE public.dating_matches ADD COLUMN IF NOT EXISTS closed_reason text;
ALTER TABLE public.dating_matches ADD COLUMN IF NOT EXISTS evidence_until timestamptz;
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_closed_reason_check;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_closed_reason_check CHECK (
  closed_reason IS NULL OR closed_reason IN ('unmatched', 'blocked', 'closed_kindly', 'exit',
    'account_restricted', 'age_review', 'age_verification_invalid', 'couple_linked',
    'other_linked', 'account_deleted',
    'other')); -- Spec 2 W1a (owner 2026-11-06, PF-F2): the same-gender kill switch
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_pair_order_check;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_pair_order_check CHECK (
  user_low_id IS NULL OR user_high_id IS NULL OR user_low_id::text < user_high_id::text);
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_no_self_pair_check;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_no_self_pair_check CHECK (
  user_low_id IS NULL OR user_high_id IS NULL OR user_low_id <> user_high_id);
-- W1 final fix: the introductions' own account FKs are re-created (same
-- definition) right before the matches' three, so on every database the
-- introductions' cascade fires before the matches' SET NULL when an account
-- is deleted (RI triggers fire in trigger-name order, which embeds the OID;
-- on a database whose OIDs had crossed a digit boundary the order flipped,
-- and a match created in the deleting transaction then failed its
-- introduction_id re-check).
ALTER TABLE public.dating_introductions DROP CONSTRAINT IF EXISTS dating_introductions_user_low_id_fkey;
ALTER TABLE public.dating_introductions ADD CONSTRAINT dating_introductions_user_low_id_fkey
  FOREIGN KEY (user_low_id) REFERENCES public.users(id) ON DELETE CASCADE;
ALTER TABLE public.dating_introductions DROP CONSTRAINT IF EXISTS dating_introductions_user_high_id_fkey;
ALTER TABLE public.dating_introductions ADD CONSTRAINT dating_introductions_user_high_id_fkey
  FOREIGN KEY (user_high_id) REFERENCES public.users(id) ON DELETE CASCADE;
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_user_low_id_fkey;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_user_low_id_fkey
  FOREIGN KEY (user_low_id) REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_user_high_id_fkey;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_user_high_id_fkey
  FOREIGN KEY (user_high_id) REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_introduction_id_fkey;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_introduction_id_fkey
  FOREIGN KEY (introduction_id) REFERENCES public.dating_introductions(id) ON DELETE SET NULL;

-- M-3: an active match whose member is deleted outside
-- prepare_account_deletion (the FK's SET NULL is a row UPDATE) is sealed.
CREATE OR REPLACE FUNCTION private.dating_matches_close_on_member_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  NEW.state := 'closed';
  NEW.closed_reason := 'account_deleted';
  NEW.closed_at := coalesce(NEW.closed_at, now());
  NEW.evidence_until := now() + interval '30 days';
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS dating_matches_close_on_member_delete ON public.dating_matches;
CREATE TRIGGER dating_matches_close_on_member_delete
  BEFORE UPDATE OF user_low_id, user_high_id ON public.dating_matches
  FOR EACH ROW
  WHEN (NEW.state = 'active'
        AND ((OLD.user_low_id IS NOT NULL AND NEW.user_low_id IS NULL)
             OR (OLD.user_high_id IS NOT NULL AND NEW.user_high_id IS NULL)))
  EXECUTE FUNCTION private.dating_matches_close_on_member_delete();

-- I-5: the exclusion key's fingerprint, and the mismatch test.
CREATE TABLE IF NOT EXISTS private.dating_key_fingerprints (
  name text PRIMARY KEY CHECK (name IN ('dating_exclusion_key')),
  fingerprint text NOT NULL CHECK (fingerprint ~ '^[0-9a-f]{64}$'),
  set_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private.dating_key_fingerprints ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE private.dating_key_fingerprints IS
  'Spec 2 W1a (I-5): the fingerprint (HMAC of a fixed label) of the dating_exclusion_key every stored phone HMAC was made with, written on first sight. Rotating the key: re-HMAC the live rows first, then replace this row (owner checklist); carried rows of deleted numbers cannot be re-keyed.';

CREATE OR REPLACE FUNCTION private.dating_exclusion_key_mismatch()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_live constant text := public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1');
  v_stored text;
BEGIN
  IF v_live IS NULL THEN
    RETURN false; -- no key: not a mismatch (generation, deletion and health refuse on a missing key)
  END IF;
  INSERT INTO private.dating_key_fingerprints (name, fingerprint)
  VALUES ('dating_exclusion_key', v_live)
  ON CONFLICT (name) DO NOTHING;
  SELECT k.fingerprint INTO v_stored FROM private.dating_key_fingerprints AS k WHERE k.name = 'dating_exclusion_key';
  RETURN v_stored IS DISTINCT FROM v_live;
END;
$function$;

INSERT INTO public.metric_key_prefixes (prefix, owner_spec) VALUES ('dating.', 'spec2')
ON CONFLICT (prefix) DO NOTHING;

CREATE OR REPLACE FUNCTION public.begin_dating_enrollment(p_terms_version text, p_idempotency_key text)
 RETURNS dating_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF private.dating_exclusion_key_mismatch() THEN -- Spec 2 W1a (I-5): a different exclusion key refuses quietly, counted
    PERFORM private.bump_metric_internal('dating.exclusion_key.mismatch'); -- Spec 2 W1a
    SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id=v_user_id; -- Spec 2 W1a
    RETURN v_enrollment; -- Spec 2 W1a
  END IF; -- Spec 2 W1a
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
$function$;

CREATE OR REPLACE FUNCTION public.activate_dating_profile(p_idempotency_key text)
 RETURNS dating_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF private.dating_exclusion_key_mismatch() THEN -- Spec 2 W1a (I-5): a different exclusion key refuses quietly, counted
    PERFORM private.bump_metric_internal('dating.exclusion_key.mismatch'); -- Spec 2 W1a
    SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id=v_user_id; -- Spec 2 W1a
    RETURN v_enrollment; -- Spec 2 W1a
  END IF; -- Spec 2 W1a
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
  RETURN v_enrollment;
END;
$function$;

CREATE OR REPLACE FUNCTION public.run_dating_candidate_generation(p_partition_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
  IF private.dating_exclusion_key_mismatch() THEN -- Spec 2 W1a (I-5): no run under a different exclusion key, counted
    PERFORM private.bump_metric_internal('dating.exclusion_key.mismatch'); -- Spec 2 W1a
    RETURN jsonb_build_object('skipped', 'exclusion_key_mismatch'); -- Spec 2 W1a
  END IF; -- Spec 2 W1a

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
$function$;

CREATE OR REPLACE FUNCTION public.block_dating_user(p_idempotency_key text, p_target_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- Spec 2 W1a: the pair also survives either account's deletion.
  INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
  SELECT h.blocker, h.blocked
    FROM (SELECT public.dating_phone_hmac_for_user(v_user_id) AS blocker,
                 public.dating_phone_hmac_for_user(p_target_user_id) AS blocked) AS h
   WHERE h.blocker IS NOT NULL AND h.blocked IS NOT NULL
  ON CONFLICT (blocker_hmac, blocked_hmac) DO NOTHING;

  UPDATE public.dating_introductions
  SET state = 'invalidated'
  WHERE pair_key = v_pair_key
    AND state IN ('generated', 'presented', 'interested');

  UPDATE public.dating_matches
  SET state = 'blocked',
      closed_reason = 'blocked', -- Spec 2 W1a
      evidence_until = now() + interval '30 days', -- Spec 2 W1a
      closed_at = COALESCE(closed_at, now())
  WHERE public.dating_pair_key(user_low_id, user_high_id) = v_pair_key
    AND state = 'active';
END;
$function$;

CREATE OR REPLACE FUNCTION public.dating_account_in_good_standing(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
  ) AND NOT EXISTS ( -- Spec 2 W1a: a restriction carried past a deletion
    SELECT 1 FROM public.enforcement_records er
    WHERE er.scope = 'dating'
      AND er.phone_hmac = public.dating_phone_hmac_for_user(p_user_id)
      AND (er.effect_until IS NULL OR er.effect_until > now())
      AND er.purge_after > now()
  ) AND NOT EXISTS ( -- Spec 2 W1a: Spec 1's account holds (gate 3)
    SELECT 1 FROM public.account_holds h
    WHERE h.user_id = p_user_id
      AND h.kind IN ('age_review', 'safety_review')
      AND h.resolved_at IS NULL
  );
$function$;

REVOKE ALL ON public.enforcement_records FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.dating_block_hmacs FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.block_dating_user(text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dating_account_in_good_standing(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON private.dating_key_fingerprints FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_exclusion_key_mismatch() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_matches_close_on_member_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_phone_hmac(text) FROM PUBLIC, anon, authenticated, service_role;

-- I-5: a key already set at deploy is fingerprinted now.
DO $$
BEGIN
  PERFORM private.dating_exclusion_key_mismatch();
END $$;

COMMIT;
