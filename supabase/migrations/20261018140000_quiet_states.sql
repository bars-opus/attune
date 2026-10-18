-- Spec 7 (research 06 B9, A9): a private quiet state. "Having a hard time"
-- or "Going through a loss" for 14 days, ended at will. While it lasts the
-- app stops celebrating at that person (shimmer, Planning goal notices, the
-- lighter daily summary lines, On this day, Love map fears and dreams,
-- AI idea tone). It is per person, never shown to anyone, never a Pulse or
-- AI input by name, and nothing a client can probe for someone else
-- (plan review C1). Grants in 20261018140010.
INSERT INTO public.feature_flags (key, enabled) VALUES ('quiet_states', false)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.quiet_states (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('hard_time', 'loss')),
  started_at timestamptz NOT NULL DEFAULT now(),
  until timestamptz NOT NULL,
  -- The once-only line ("I'm in a heavy patch…") was offered this time.
  line_offered boolean NOT NULL DEFAULT false
);
ALTER TABLE public.quiet_states ENABLE ROW LEVEL SECURITY;

-- Server-side only (generators, other SECURITY DEFINER functions).
CREATE OR REPLACE FUNCTION public.user_is_quiet(p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.quiet_states q WHERE q.user_id = p_user AND q.until > now());
$$;

-- Whether a feature flag is on (a missing row is off). The Spec 7/8 writers
-- check their own flag, so "off" holds for any client, not just the app's
-- UI (sync audit, Dart audit #3).
CREATE OR REPLACE FUNCTION public.feature_flag_on(p_key text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce((SELECT f.enabled FROM public.feature_flags f WHERE f.key = p_key), false);
$$;
REVOKE ALL ON FUNCTION public.feature_flag_on(text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.set_my_quiet_state(p_kind text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'quiet:not_signed_in'; END IF;
  IF NOT public.feature_flag_on('quiet_states') THEN RAISE EXCEPTION 'quiet:not_allowed'; END IF;
  IF p_kind IS NULL OR p_kind NOT IN ('hard_time', 'loss') THEN RAISE EXCEPTION 'quiet:invalid'; END IF;
  INSERT INTO public.quiet_states (user_id, kind, started_at, until, line_offered)
  VALUES (v_uid, p_kind, now(), now() + interval '14 days', false)
  ON CONFLICT (user_id) DO UPDATE SET
    kind = EXCLUDED.kind,
    -- Switching kind keeps the end date (final review M-1).
    until = CASE WHEN public.quiet_states.until > now()
                 THEN public.quiet_states.until ELSE EXCLUDED.until END,
    -- A new activation (none running) starts fresh; switching kind while
    -- one runs keeps its start and the line already offered (review M3).
    started_at = CASE WHEN public.quiet_states.until > now()
                      THEN public.quiet_states.started_at ELSE EXCLUDED.started_at END,
    line_offered = CASE WHEN public.quiet_states.until > now()
                        THEN public.quiet_states.line_offered ELSE false END;
END;
$$;

CREATE OR REPLACE FUNCTION public.end_my_quiet_state()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  DELETE FROM public.quiet_states WHERE user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_my_quiet_state()
RETURNS TABLE (kind text, until timestamptz, line_offered boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT q.kind, q.until, q.line_offered FROM public.quiet_states q
  WHERE q.user_id = auth.uid() AND q.until > now();
$$;

CREATE OR REPLACE FUNCTION public.mark_quiet_line_offered()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE public.quiet_states SET line_offered = true
  WHERE user_id = auth.uid() AND until > now();
$$;
