-- Dating former-partner exclusion (Fable review DATING-C4).
--
-- Spec 5.1 / threat model: a DV survivor who completed Healing after leaving an
-- abuser must never be introduced to that abuser — even if the abuser deletes
-- their account and re-registers under a new UUID with a new profile. UUID-keyed
-- `dating_blocks` die with the account, so they cannot carry this exclusion
-- across a re-registration. The durable key is the abuser's VERIFIED PHONE.
--
-- We store an HMAC of the former partner's phone (keyed with a server secret),
-- one row per ended relationship, purpose-limited and never exposed in any API.
-- On re-registration the same phone yields the same HMAC, so the exclusion
-- survives. The raw phone is never stored here; only the keyed HMAC.
--
-- Candidate generation is not built yet, but this exclusion is a HARD BLOCKER on
-- it. To make that real today we also enforce the predicate in
-- `act_on_dating_introduction` and `get_my_dating_introductions`, so even a
-- manually-seeded introduction between former partners is refused/hidden.
--
-- Residual (documented per spec): populated only for relationships that end via
-- `record_dating_former_partner_exclusion` (called at relationship-end, and
-- backfillable for existing ended rows by an operator). A former partner who
-- changes to a new, never-verified phone is not covered — block-on-sight
-- remains available and this residual is recorded in the Section 15 threat model
-- (docs/reviews/DATING_REVIEW_FABLE.md fix section).

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Exclusion table. RLS on, no client grant: this is server-only safety data.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dating_former_partner_exclusions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- The user who must be PROTECTED (their candidate set excludes the phone below).
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  -- HMAC of the former partner's verified phone. Not reversible to a phone.
  excluded_phone_hmac text NOT NULL,
  relationship_id uuid REFERENCES public.relationships(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, excluded_phone_hmac)
);

CREATE INDEX IF NOT EXISTS idx_dating_fpe_user_hmac
  ON public.dating_former_partner_exclusions(user_id, excluded_phone_hmac);

ALTER TABLE public.dating_former_partner_exclusions ENABLE ROW LEVEL SECURITY;
-- No policy + REVOKE ALL: unreadable and unwritable by anon/authenticated. Only
-- SECURITY DEFINER functions below (owned by the migration role) touch it.
REVOKE ALL ON public.dating_former_partner_exclusions FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Keyed HMAC of a phone. Key comes from app.settings (same pattern chat uses
-- for service secrets). Returns NULL when phone or key is absent, so callers
-- fail SAFE (an unknowable exclusion never silently opens the gate — see the
-- predicate, which treats "cannot compute" conservatively).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.dating_phone_hmac(p_phone text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key text := current_setting('app.settings.dating_exclusion_key', true);
  v_phone text := NULLIF(trim(COALESCE(p_phone, '')), '');
BEGIN
  IF v_phone IS NULL OR v_key IS NULL OR length(v_key) = 0 THEN
    RETURN NULL;
  END IF;
  -- Bare hmac(): pgcrypto is installed into public here (matches the codebase's
  -- unqualified digest() calls), and search_path is pinned to public.
  RETURN encode(hmac(v_phone, v_key, 'sha256'), 'hex');
END;
$$;

REVOKE ALL ON FUNCTION public.dating_phone_hmac(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dating_phone_hmac(text) TO service_role;

-- ---------------------------------------------------------------------------
-- Record the exclusion for an ended relationship. Service-role only. For each
-- party with a verified phone, store the OTHER party's phone-HMAC against them,
-- so each is protected from the other's re-registration.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_dating_former_partner_exclusion(p_relationship_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rel public.relationships%ROWTYPE;
  v_phone_a text; v_phone_b text;
  v_hmac_a text;  v_hmac_b text;
BEGIN
  IF auth.role() IS NOT NULL AND auth.role() = 'authenticated' THEN
    RAISE EXCEPTION 'exclusion_write_is_backend_only' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_rel FROM public.relationships WHERE id = p_relationship_id;
  IF NOT FOUND OR v_rel.user_b IS NULL THEN RETURN; END IF;

  SELECT phone INTO v_phone_a FROM public.users WHERE id = v_rel.user_a;
  SELECT phone INTO v_phone_b FROM public.users WHERE id = v_rel.user_b;
  v_hmac_a := public.dating_phone_hmac(v_phone_a);
  v_hmac_b := public.dating_phone_hmac(v_phone_b);

  -- Protect A from B (store B's phone-HMAC against A) and vice-versa.
  IF v_hmac_b IS NOT NULL THEN
    INSERT INTO public.dating_former_partner_exclusions(user_id, excluded_phone_hmac, relationship_id)
    VALUES (v_rel.user_a, v_hmac_b, p_relationship_id)
    ON CONFLICT (user_id, excluded_phone_hmac) DO NOTHING;
  END IF;
  IF v_hmac_a IS NOT NULL THEN
    INSERT INTO public.dating_former_partner_exclusions(user_id, excluded_phone_hmac, relationship_id)
    VALUES (v_rel.user_b, v_hmac_a, p_relationship_id)
    ON CONFLICT (user_id, excluded_phone_hmac) DO NOTHING;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.record_dating_former_partner_exclusion(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_dating_former_partner_exclusion(uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- Exclusion predicate: TRUE if these two users must never be introduced because
-- one is a recorded former partner of the other (matched by phone-HMAC, so it
-- holds across re-registration under a new UUID). Used by the candidacy gate.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.dating_former_partner_excluded(p_user_a uuid, p_user_b uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone_a text; v_phone_b text;
  v_hmac_a text;  v_hmac_b text;
BEGIN
  SELECT phone INTO v_phone_a FROM public.users WHERE id = p_user_a;
  SELECT phone INTO v_phone_b FROM public.users WHERE id = p_user_b;
  v_hmac_a := public.dating_phone_hmac(v_phone_a);
  v_hmac_b := public.dating_phone_hmac(v_phone_b);

  -- A is protected from B's phone, OR B is protected from A's phone.
  RETURN
    (v_hmac_b IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.dating_former_partner_exclusions e
       WHERE e.user_id = p_user_a AND e.excluded_phone_hmac = v_hmac_b))
    OR
    (v_hmac_a IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.dating_former_partner_exclusions e
       WHERE e.user_id = p_user_b AND e.excluded_phone_hmac = v_hmac_a));
END;
$$;

REVOKE ALL ON FUNCTION public.dating_former_partner_excluded(uuid, uuid) FROM PUBLIC, anon, authenticated;
-- Executable by the SECURITY DEFINER RPCs (which run as the owner), not clients.

-- ---------------------------------------------------------------------------
-- Enforce NOW: re-create act_on_dating_introduction and get_my_dating_introductions
-- with the former-partner exclusion added to the candidacy gate. Bodies are the
-- current live versions (v1.2 / C3 fix) verbatim, plus the one exclusion clause.
-- ---------------------------------------------------------------------------
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
     -- DATING-C4: former-partner exclusion (survives re-registration by phone-HMAC).
     OR public.dating_former_partner_excluded(v_intro.user_low_id, v_intro.user_high_id)
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

-- get_my_dating_introductions: hide any introduction between former partners too
-- (defense in depth; the act path already refuses). Body is the C3-fix version
-- (20260712120000) verbatim plus the exclusion clause.
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
    di.display_band,di.explanation_features,
    CASE
      WHEN (CASE WHEN di.user_low_id=auth.uid() THEN di.low_action ELSE di.high_action END) = 'interested'
        THEN 'awaiting_response'
      ELSE 'open'
    END AS state,
    di.expires_at,di.created_at,
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
    -- DATING-C4: never surface an introduction between recorded former partners.
    AND NOT public.dating_former_partner_excluded(di.user_low_id, di.user_high_id)
    AND EXISTS(SELECT 1 FROM public.dating_feature_snapshots s WHERE s.id=di.snapshot_low_id AND s.invalidated_at IS NULL)
    AND EXISTS(SELECT 1 FROM public.dating_feature_snapshots s WHERE s.id=di.snapshot_high_id AND s.invalidated_at IS NULL)
  ORDER BY di.created_at DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,20),1),20);
$$;

REVOKE ALL ON FUNCTION public.get_my_dating_introductions(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_dating_introductions(integer) TO authenticated;
