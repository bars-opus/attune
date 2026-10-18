-- supabase/migrations/20261017150000_pulse_privacy.sql
--
-- Pulse privacy (Spec 1a Task 7; research 06 §3 F5 with the stronger ruling
-- recorded in PULSE.md §11; SOUL §9 Pulse).
--
-- 1. Emotional safety leaves the shared row. compute-pulse writes it per
--    member into pulse_private_scores (auth.uid()-only RLS); the shared
--    column becomes nullable and is written as NULL from now on.
-- 2. The on-demand refresh limit moves server-side: claim_pulse_recompute is
--    an atomic claim (one INSERT ... ON CONFLICT DO UPDATE ... WHERE) that
--    only the service role (the edge function) may call.
ALTER TABLE public.pulse_scores ALTER COLUMN emotional_safety DROP NOT NULL;

CREATE TABLE public.pulse_private_scores (
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  week_ending date NOT NULL,
  emotional_safety int NOT NULL CHECK (emotional_safety BETWEEN 0 AND 100),
  computed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, week_ending)
);
CREATE INDEX idx_pulse_private_scores_rel ON public.pulse_private_scores (relationship_id, week_ending DESC);
ALTER TABLE public.pulse_private_scores ENABLE ROW LEVEL SECURITY;
CREATE POLICY pulse_private_scores_self ON public.pulse_private_scores
  FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE ALL ON public.pulse_private_scores FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.pulse_private_scores TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.pulse_private_scores TO service_role;

-- Per (relationship, member): keyed per couple, one partner's 429 would say
-- "your partner refreshed in the last day" (SPEC §11 constraint 10).
CREATE TABLE public.pulse_recompute_limits (
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  last_forced_at timestamptz NOT NULL,
  PRIMARY KEY (relationship_id, user_id)
);
ALTER TABLE public.pulse_recompute_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pulse_recompute_limits FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.pulse_recompute_limits TO service_role;

CREATE FUNCTION public.claim_pulse_recompute(
  p_relationship_id uuid,
  p_user_id uuid,
  p_min_interval interval DEFAULT interval '24 hours'
)
RETURNS TABLE (granted boolean, retry_after_seconds int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_last timestamptz;
BEGIN
  INSERT INTO public.pulse_recompute_limits (relationship_id, user_id, last_forced_at)
  VALUES (p_relationship_id, p_user_id, now())
  ON CONFLICT (relationship_id, user_id) DO UPDATE
    SET last_forced_at = now()
    WHERE public.pulse_recompute_limits.last_forced_at <= now() - p_min_interval
  RETURNING last_forced_at INTO v_last;
  IF FOUND THEN
    granted := true;
    retry_after_seconds := 0;
    RETURN NEXT;
    RETURN;
  END IF;
  SELECT l.last_forced_at INTO v_last
    FROM public.pulse_recompute_limits l
   WHERE l.relationship_id = p_relationship_id AND l.user_id = p_user_id;
  granted := false;
  retry_after_seconds := GREATEST(1, ceil(extract(epoch FROM (v_last + p_min_interval - now())))::int);
  RETURN NEXT;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_pulse_recompute(uuid, uuid, interval) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_pulse_recompute(uuid, uuid, interval) TO service_role;
