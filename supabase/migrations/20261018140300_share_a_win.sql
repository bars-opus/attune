-- Spec 7 (research 06 B2; plan review C2, I8, M1, M6): "Share a win".
--   * a win is a shared highlight with is_win, made only by share_a_win
--     (a client cannot set the flag: a guard trigger clears it);
--   * it never pushes (the moment trigger skips it);
--   * the partner gets an in-app card for 3 days ("Ask … about it — what
--     was the best part?") until they tap or dismiss it.
-- Grants in 20261018140310.
INSERT INTO public.feature_flags (key, enabled) VALUES ('share_a_win', false)
ON CONFLICT (key) DO NOTHING;

ALTER TABLE public.timeline_events ADD COLUMN IF NOT EXISTS is_win boolean NOT NULL DEFAULT false;
ALTER TABLE public.timeline_events DROP CONSTRAINT IF EXISTS timeline_events_win_shape;
ALTER TABLE public.timeline_events ADD CONSTRAINT timeline_events_win_shape
  CHECK (NOT is_win OR (event_type = 'highlight' AND visibility = 'shared'));

CREATE OR REPLACE FUNCTION public.timeline_events_win_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NEW.is_win AND coalesce(current_setting('attune.share_a_win', true), '') <> 'on' THEN
    NEW.is_win := CASE WHEN TG_OP = 'UPDATE' THEN OLD.is_win ELSE false END;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS timeline_events_win_guard ON public.timeline_events;
CREATE TRIGGER timeline_events_win_guard
  BEFORE INSERT OR UPDATE OF is_win ON public.timeline_events
  FOR EACH ROW EXECUTE FUNCTION public.timeline_events_win_guard();

CREATE OR REPLACE FUNCTION public.notify_partner_moment_logged()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_partner uuid;
  v_name text;
BEGIN
  -- Spec 7 (B2): a win never pushes; the partner sees an in-app card.
  IF NEW.event_type = 'conflict' OR NEW.is_win THEN
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
$function$;

CREATE TABLE IF NOT EXISTS public.win_card_dismissals (
  event_id uuid NOT NULL REFERENCES public.timeline_events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, user_id)
);
ALTER TABLE public.win_card_dismissals ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.share_a_win(
  p_relationship_id uuid, p_title text, p_note text DEFAULT NULL, p_occurred_on date DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_title text := btrim(coalesce(p_title, ''));
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_today date;
  v_on date;
  v_id uuid;
BEGIN
  IF NOT public.feature_flag_on('share_a_win') THEN RAISE EXCEPTION 'win:not_allowed'; END IF;
  IF v_uid IS NULL OR NOT public.relationship_active_for_me(p_relationship_id) THEN
    RAISE EXCEPTION 'win:not_allowed';
  END IF;
  -- The sharer's own day (review M6), a day either side allowed.
  v_today := (now() AT TIME ZONE coalesce(public.notification_recipient_tz(v_uid), 'UTC'))::date;
  v_on := coalesce(p_occurred_on, v_today);
  IF char_length(v_title) = 0 OR char_length(v_title) > 80
     OR char_length(coalesce(v_note, '')) > 300
     OR v_on NOT BETWEEN v_today - 1 AND v_today + 1 THEN
    RAISE EXCEPTION 'win:invalid';
  END IF;
  PERFORM set_config('attune.share_a_win', 'on', true);
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, note, occurred_at,
                                      visibility, is_win)
  VALUES (p_relationship_id, v_uid, 'highlight', v_title, v_note, v_on, 'shared', true)
  RETURNING id INTO v_id;
  PERFORM set_config('attune.share_a_win', 'off', true);
  RETURN v_id;
END;
$$;

-- The partner's wins from the last 3 days that this person has not yet
-- asked about or put aside.
CREATE OR REPLACE FUNCTION public.list_win_cards(p_relationship_id uuid)
RETURNS TABLE (event_id uuid, title text, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_me uuid := public.together_actor(p_relationship_id);
BEGIN
  -- Sync audit M-6: a quiet person's surfaces stop celebrating, the
  -- partner's wins included. Personal, so it tells the partner nothing.
  IF public.user_is_quiet(v_me) THEN RETURN; END IF;
  RETURN QUERY
  SELECT te.id, te.title, te.created_at
  FROM public.timeline_events te
  WHERE te.relationship_id = p_relationship_id AND te.is_win AND te.deleted_at IS NULL
    AND te.logged_by <> v_me AND te.created_at > now() - interval '3 days'
    AND NOT EXISTS (SELECT 1 FROM public.win_card_dismissals d
                    WHERE d.event_id = te.id AND d.user_id = v_me)
  ORDER BY te.created_at DESC
  LIMIT 3;
END;
$$;

CREATE OR REPLACE FUNCTION public.dismiss_win_card(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_rel uuid;
  v_me uuid;
BEGIN
  SELECT te.relationship_id INTO v_rel FROM public.timeline_events te
  WHERE te.id = p_event_id AND te.is_win;
  v_me := public.together_actor(v_rel);
  INSERT INTO public.win_card_dismissals (event_id, user_id) VALUES (p_event_id, v_me)
  ON CONFLICT DO NOTHING;
END;
$$;
