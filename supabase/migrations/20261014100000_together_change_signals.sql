-- Together (spec 2026-10-14 §5.6): a per-couple "something changed"
-- signal that Realtime delivers, so both partners refetch. Copies
-- planning_change_signals. Triggers rather than RPC bumps because
-- timeline_events and reminders are still written by direct table calls.
-- Realtime is a refetch signal only, never a second source of truth.

CREATE TABLE IF NOT EXISTS public.together_change_signals (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships(id)
                    ON DELETE CASCADE,
  version         bigint NOT NULL DEFAULT 1,
  updated_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.together_change_signals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS together_change_signals_select ON public.together_change_signals;
CREATE POLICY together_change_signals_select ON public.together_change_signals
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = together_change_signals.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );

REVOKE ALL ON public.together_change_signals FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.together_change_signals TO authenticated;

CREATE OR REPLACE FUNCTION public.bump_together_signal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rel uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_rel := OLD.relationship_id;
    -- A relationship being deleted cascades here first; inserting a
    -- signal for it would fail its foreign key and roll the delete back.
    IF NOT EXISTS (SELECT 1 FROM public.relationships WHERE id = v_rel) THEN
      RETURN NULL;
    END IF;
  ELSE
    v_rel := NEW.relationship_id;
  END IF;
  IF v_rel IS NULL THEN
    RETURN NULL;
  END IF;
  INSERT INTO public.together_change_signals (relationship_id, version, updated_at)
  VALUES (v_rel, 1, now())
  ON CONFLICT (relationship_id) DO UPDATE
    SET version = together_change_signals.version + 1, updated_at = now();
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.bump_together_signal() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_together_signal_timeline ON public.timeline_events;
CREATE TRIGGER trigger_together_signal_timeline
  AFTER INSERT OR UPDATE OR DELETE ON public.timeline_events
  FOR EACH ROW EXECUTE FUNCTION public.bump_together_signal();

DROP TRIGGER IF EXISTS trigger_together_signal_reminders ON public.reminders;
CREATE TRIGGER trigger_together_signal_reminders
  AFTER INSERT OR UPDATE OR DELETE ON public.reminders
  FOR EACH ROW EXECUTE FUNCTION public.bump_together_signal();

DROP TRIGGER IF EXISTS trigger_together_signal_family ON public.couple_family_members;
CREATE TRIGGER trigger_together_signal_family
  AFTER INSERT OR UPDATE OR DELETE ON public.couple_family_members
  FOR EACH ROW EXECUTE FUNCTION public.bump_together_signal();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'together_change_signals'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.together_change_signals;
  END IF;
END $$;
