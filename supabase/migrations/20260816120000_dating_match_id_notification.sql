-- supabase/migrations/20260816120000_dating_match_id_notification.sql
--
-- act_on_dating_introduction's dating_mutual_match push never included the
-- match id, despite v_match_id being in scope — a real payload gap, not
-- just a missing allowlist entry. Re-declares the function verbatim, only
-- adding 'match_id', v_match_id::text to both jsonb_build_object calls.
-- See design spec docs/superpowers/specs/
-- 2026-08-02-notification-routing-completion-design.md §6.

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
         jsonb_build_object('title','New mutual match','body','Open Attune to see your new connection.','type','dating_mutual_match','match_id',v_match_id::text),
         'dating_match:'||v_match_id::text||':'||v_intro.user_low_id::text,now(),now()),
        (v_intro.user_high_id,'immediate',now(),'pending',
         jsonb_build_object('title','New mutual match','body','Open Attune to see your new connection.','type','dating_mutual_match','match_id',v_match_id::text),
         'dating_match:'||v_match_id::text||':'||v_intro.user_high_id::text,now(),now())
      ON CONFLICT(source_key) WHERE source_key IS NOT NULL DO NOTHING;
    END IF;
  END IF;
END;
$$;
