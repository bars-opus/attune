-- Dating double-blind fix (Fable review DATING-C3).
--
-- `get_my_dating_introductions` returned the pair-level `di.state` verbatim to
-- BOTH members. When A expresses interest and B has not acted, the shared row
-- is state='interested', so B — who has done nothing — sees an introduction
-- already in 'interested', which can only mean the counterpart liked them. That
-- is the "they liked you" one-sided-interest oracle the spec bans (Spec §7,
-- checklist 5.2), leaked at the data layer regardless of UI.
--
-- Fix: never return the pair-level state. Return a VIEWER-SCOPED status derived
-- only from the viewer's own action and the mutual-match fact (which is not
-- one-sided information — both parties learn a match simultaneously):
--   - viewer has not acted            -> 'open'
--   - viewer passed                   -> 'passed'
--   - viewer interested, mutual match -> 'matched'
--   - viewer interested, not yet mutual -> 'awaiting_response'  (own pending
--     state; reveals nothing about whether the counterpart has acted)
--
-- 'awaiting_response' is symmetric-safe: it is true for the viewer purely
-- because THEY expressed interest, independent of the counterpart. A viewer who
-- has not acted can never see it, so it is not an oracle.

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
    -- Viewer-scoped status: derived ONLY from the viewer's own action, never the
    -- counterpart's. This list only ever contains open introductions (the WHERE
    -- filters state IN generated/presented/interested), so the only reachable
    -- values are:
    --   viewer has not acted -> 'open'      (counterpart's action, if any, is hidden)
    --   viewer is interested -> 'awaiting_response'  (own pending state; a viewer
    --     who has not acted can never see this, so it is not a one-sided oracle)
    -- Passed and matched introductions leave this list entirely (WHERE filter),
    -- so no 'passed'/'matched' branch is needed here.
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
    AND EXISTS(SELECT 1 FROM public.dating_feature_snapshots s WHERE s.id=di.snapshot_low_id AND s.invalidated_at IS NULL)
    AND EXISTS(SELECT 1 FROM public.dating_feature_snapshots s WHERE s.id=di.snapshot_high_id AND s.invalidated_at IS NULL)
  ORDER BY di.created_at DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,20),1),20);
$$;

REVOKE ALL ON FUNCTION public.get_my_dating_introductions(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_dating_introductions(integer) TO authenticated;
