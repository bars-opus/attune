-- Spec 8 (research 06 F14; 05 P0-13; plan review C1, C2, I1, I2, I3, I10):
-- the private safety check. Four self-facing items (HARK, clinician sign-off
-- pending: the copy ships as [DRAFT]), each yes / no / prefer not to say,
-- per person per relationship.
--   * the answers are never stored; only whether it was positive, until when;
--   * positive is sticky for 180 days: a later "no" (perhaps under pressure)
--     never clears it (I2);
--   * the client learns nothing back except, at the moment of answering,
--     which card to show (resources once / the plain link / none);
--   * nothing a member can call depends on their partner's check (C1): the
--     predicates below are the server's;
--   * relationship_ai_suppressed keeps AI patterns, chat-derived Pulse and
--     the Verdict away from a relationship with any safety context (I10).
-- Grants in 20261018150010.
INSERT INTO public.feature_flags (key, enabled) VALUES ('private_safety_check', false)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.safety_self_checks (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  answered_at timestamptz NOT NULL,
  until timestamptz NOT NULL,
  -- Set when the check was positive; extended, never shortened (I2).
  positive_until timestamptz,
  PRIMARY KEY (user_id, relationship_id)
);
-- Final review C-1: the row never remembers whether the card was shown
-- (a database that ran an earlier draft of this file drops it).
ALTER TABLE public.safety_self_checks DROP COLUMN IF EXISTS resources_shown;
ALTER TABLE public.safety_self_checks ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS safety_events_relationship_recent_idx
  ON public.safety_events (relationship_id, created_at DESC) WHERE anonymised_at IS NULL;

CREATE OR REPLACE FUNCTION public.submit_my_safety_check(p_relationship_id uuid, p_answers jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_positive boolean;
  v_all_prefer_not boolean;
  v_card text := 'none';
BEGIN
  IF NOT public.feature_flag_on('private_safety_check') THEN
    RAISE EXCEPTION 'safety_check:not_allowed';
  END IF;
  -- The check is about the person, so a paused chapter takes it too
  -- (final review m-9); an ended or archived one does not.
  IF v_uid IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id AND v_uid IN (r.user_a, r.user_b)
      AND r.status IN ('active', 'paused') AND r.chat_archived_at IS NULL) THEN
    RAISE EXCEPTION 'safety_check:not_allowed';
  END IF;
  IF jsonb_typeof(p_answers) IS DISTINCT FROM 'object'
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_answers) k) IS DISTINCT FROM ARRAY['q1', 'q2', 'q3', 'q4']
     OR EXISTS (SELECT 1 FROM jsonb_each_text(p_answers) a WHERE a.value NOT IN ('yes', 'no', 'prefer_not')) THEN
    RAISE EXCEPTION 'safety_check:invalid';
  END IF;
  -- HARK's own scoring: any yes (05 :145). Prefer-not is never positive.
  v_positive := EXISTS (SELECT 1 FROM jsonb_each_text(p_answers) a WHERE a.value = 'yes');
  v_all_prefer_not := NOT EXISTS (SELECT 1 FROM jsonb_each_text(p_answers) a WHERE a.value <> 'prefer_not');

  INSERT INTO public.safety_self_checks AS s (user_id, relationship_id, answered_at, until, positive_until)
  VALUES (v_uid, p_relationship_id, now(), now() + interval '180 days',
          CASE WHEN v_positive THEN now() + interval '180 days' END)
  ON CONFLICT (user_id, relationship_id) DO UPDATE SET
    answered_at = now(),
    until = now() + interval '180 days',
    positive_until = CASE
      WHEN v_positive THEN greatest(coalesce(s.positive_until, now()), now() + interval '180 days')
      ELSE s.positive_until END;

  -- Final review C-1: the card depends only on the answers just given.
  -- Anything about the row's past (was it positive? was the card shown?)
  -- would tell whoever holds the phone what this check exists to hide.
  IF v_positive THEN
    v_card := 'resources';
  ELSIF v_all_prefer_not THEN
    v_card := 'plain';
  END IF;
  RETURN jsonb_build_object('card', v_card);
END;
$$;

-- Only when I answered and until when it holds (stricter than review I1).
CREATE OR REPLACE FUNCTION public.get_my_safety_check(p_relationship_id uuid)
RETURNS TABLE (answered_at timestamptz, until timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT s.answered_at, s.until FROM public.safety_self_checks s
  WHERE s.user_id = auth.uid() AND s.relationship_id = p_relationship_id;
$$;

-- The server's: whether this person's own check is positive and unexpired.
CREATE OR REPLACE FUNCTION public.user_safety_flagged(p_user uuid, p_relationship_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.safety_self_checks s
                 WHERE s.user_id = p_user AND s.relationship_id = p_relationship_id
                   AND s.positive_until > now());
$$;

-- The server's: any safety context for the relationship (I10).
CREATE OR REPLACE FUNCTION public.relationship_ai_suppressed(p_relationship_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.safety_events e
                 WHERE e.relationship_id = p_relationship_id AND e.anonymised_at IS NULL
                   AND e.created_at > now() - interval '180 days')
      OR EXISTS (SELECT 1 FROM public.safety_self_checks s
                 WHERE s.relationship_id = p_relationship_id AND s.positive_until > now());
$$;
