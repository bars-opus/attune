-- Dating match-lifecycle + hardening fixes (Fable review DATING-H4, H5, H7).

-- ============================================================================
-- DATING-H5: exit / suspension / relationship-entry did NOT close existing
-- active matches. invalidate_dating_for_user touched snapshots + introductions
-- only, so a user who exited Dating, was suspended for harassment, or entered a
-- couples relationship kept their active dating matches live and visible.
--
-- Per spec: pause and consent-withdrawal PRESERVE existing matches (Spec :113,
-- :612); exit and suspension (account_restricted) CLOSE them. We gate match
-- closure on the reason so we honor both rules.
-- ============================================================================
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

  -- Close existing active matches ONLY for reasons the contract requires:
  -- exit (leaving Dating), account_restricted (suspension/moderation), and
  -- profile_deleted. Pause, consent-withdrawal, profile edits, and scheduled
  -- revalidation deliberately preserve matches (Spec :113, :612).
  IF p_reason IN ('exit', 'account_restricted', 'profile_deleted') THEN
    UPDATE public.dating_matches
    SET state = 'closed',
        closed_at = COALESCE(closed_at, now())
    WHERE (user_low_id = p_user_id OR user_high_id = p_user_id)
      AND state = 'active';
  END IF;
END;
$$;

-- ============================================================================
-- DATING-H4: get_my_dating_matches returned the counterpart's name/region with
-- no live re-check, so a suspended/exited counterpart (whose match row was left
-- 'active' before the H5 fix) stayed visible with identity, and a blocked pair
-- could linger. Add profile-active + moderation-approved + block re-checks and
-- current-candidacy checks so a stale row never surfaces identity.
-- ============================================================================
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
  WHERE auth.uid() IN (dm.user_low_id,dm.user_high_id)
    AND dm.state='active'
    -- Live re-checks so a stale/closed counterpart never surfaces identity:
    AND dp.profile_state='active' AND dp.moderation_state='approved'
    AND public.dating_candidate_is_current(dm.user_low_id)
    AND public.dating_candidate_is_current(dm.user_high_id)
    -- Block check by user pair (dating_matches has no pair_key column):
    -- excluded if either party blocked the other.
    AND NOT EXISTS(
      SELECT 1 FROM public.dating_blocks b
      WHERE (b.blocker_user_id = dm.user_low_id  AND b.blocked_user_id = dm.user_high_id)
         OR (b.blocker_user_id = dm.user_high_id AND b.blocked_user_id = dm.user_low_id)
    )
  ORDER BY dm.matched_at DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,50),1),50);
$$;

REVOKE ALL ON FUNCTION public.get_my_dating_matches(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_dating_matches(integer) TO authenticated;

-- ============================================================================
-- DATING-H7: the legacy 6-arg save_dating_profile_draft overload was revoked
-- but never DROPped. It lacks the v1.2 validation/rate-limit/moderation-pending
-- logic, so any future re-GRANT or overload-resolution slip could push an
-- unmoderated bio. Drop it; only the 7-arg validated form remains.
-- ============================================================================
DROP FUNCTION IF EXISTS public.save_dating_profile_draft(text, text, text, text, integer, integer);
