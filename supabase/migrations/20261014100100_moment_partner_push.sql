-- Partner push for a new moment (PULSE.md §10; Together spec §8.1 #3).
-- Server-side so it can't be skipped by a client: the old client path
-- (AttuneNotificationService.notifyPartnerMomentLogged) only wrote a
-- debug log. Conflicts never notify. Idempotent per moment+recipient.

CREATE OR REPLACE FUNCTION public.notify_partner_moment_logged()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_partner uuid;
  v_name text;
BEGIN
  IF NEW.event_type = 'conflict' THEN
    RETURN NULL;
  END IF;

  SELECT CASE WHEN r.user_a = NEW.logged_by THEN r.user_b ELSE r.user_a END
  INTO v_partner
  FROM public.relationships r
  WHERE r.id = NEW.relationship_id AND r.status = 'active';

  IF v_partner IS NULL OR v_partner = NEW.logged_by THEN
    RETURN NULL;
  END IF;

  SELECT coalesce(nullif(btrim(display_name), ''), 'Your partner')
  INTO v_name FROM public.users WHERE id = NEW.logged_by;
  v_name := coalesce(v_name, 'Your partner');

  INSERT INTO public.scheduled_notifications (
    user_id, notification_type, scheduled_for, status, metadata,
    source_key, created_at, updated_at
  ) VALUES (
    v_partner, 'immediate', now(), 'pending',
    jsonb_build_object(
      'title', v_name || ' added a moment',
      'body', NEW.title,
      'type', 'moment_logged',
      'relationship_id', NEW.relationship_id
    ),
    'moment:' || NEW.id::text || ':' || v_partner::text,
    now(), now()
  )
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;

  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.notify_partner_moment_logged() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_notify_partner_moment_logged ON public.timeline_events;
CREATE TRIGGER trigger_notify_partner_moment_logged
  AFTER INSERT ON public.timeline_events
  FOR EACH ROW EXECUTE FUNCTION public.notify_partner_moment_logged();
