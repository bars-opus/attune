CREATE TABLE IF NOT EXISTS public.safety_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES public.relationships(id) ON DELETE SET NULL,
  at_risk_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  source_event_key text UNIQUE NOT NULL,
  trigger_tier smallint NOT NULL CHECK (trigger_tier BETWEEN 1 AND 3),
  trigger_family text NOT NULL,
  config_version text NOT NULL,
  first_viewed_at timestamptz,
  dismissed_at timestamptz,
  notification_status text NOT NULL DEFAULT 'pending'
    CHECK (notification_status IN ('pending', 'suppressed', 'sent', 'failed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  anonymised_at timestamptz,
  CHECK (
    (anonymised_at IS NULL AND at_risk_user_id IS NOT NULL)
    OR (anonymised_at IS NOT NULL AND at_risk_user_id IS NULL AND relationship_id IS NULL)
  )
);

CREATE TABLE IF NOT EXISTS public.safety_pattern_occurrences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  at_risk_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  rule_id text NOT NULL,
  config_version text NOT NULL,
  source_event_key text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (at_risk_user_id, rule_id, config_version, source_event_key)
);

CREATE INDEX IF NOT EXISTS idx_safety_events_active_user_created_at
  ON public.safety_events(at_risk_user_id, created_at DESC)
  WHERE anonymised_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_safety_pattern_occurrences_lookup
  ON public.safety_pattern_occurrences(
    at_risk_user_id,
    rule_id,
    config_version,
    occurred_at DESC
  );

ALTER TABLE public.safety_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.safety_pattern_occurrences ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.safety_events FROM anon, authenticated;
REVOKE ALL ON public.safety_pattern_occurrences FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_my_safety_resource_events()
RETURNS TABLE (
  created_at timestamptz,
  first_viewed_at timestamptz,
  dismissed_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    se.created_at,
    se.first_viewed_at,
    se.dismissed_at
  FROM public.safety_events se
  WHERE se.at_risk_user_id = auth.uid()
    AND se.anonymised_at IS NULL
  ORDER BY se.created_at DESC;
$$;

REVOKE ALL ON FUNCTION public.get_my_safety_resource_events() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_safety_resource_events() TO authenticated;
