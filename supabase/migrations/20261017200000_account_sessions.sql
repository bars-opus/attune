-- supabase/migrations/20261017200000_account_sessions.sql
--
-- "Where you're signed in" (Spec 2; research 06 §3 F7 (1)). A partner who
-- knows the phone number, or shares the phone, can sign in elsewhere; the
-- owner must be able to see every signed-in phone and sign the others out.
--
-- Sessions are read from Supabase's auth.sessions (never written here:
-- signing out others uses the auth API's own scope=others logout).
-- session_devices holds only the label each device reports for itself,
-- keyed by the session id in its JWT; no client reads or writes it directly.
CREATE TABLE IF NOT EXISTS public.session_devices (
  session_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  label text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 60),
  platform text NOT NULL CHECK (platform IN ('ios', 'android', 'web', 'other')),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.session_devices ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS session_devices_user_idx ON public.session_devices (user_id);

CREATE OR REPLACE FUNCTION public.register_my_device(p_label text, p_platform text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_session uuid;
BEGIN
  BEGIN
    v_session := nullif(auth.jwt()->>'session_id', '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    v_session := NULL;
  END;
  IF auth.uid() IS NULL OR v_session IS NULL
     OR NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.id = v_session AND s.user_id = auth.uid()) THEN
    RAISE EXCEPTION 'session:unknown';
  END IF;
  IF p_label IS NULL OR char_length(btrim(p_label)) NOT BETWEEN 1 AND 60
     OR p_platform IS NULL OR p_platform NOT IN ('ios', 'android', 'web', 'other') THEN
    RAISE EXCEPTION 'session:invalid_input';
  END IF;
  INSERT INTO public.session_devices (session_id, user_id, label, platform, updated_at)
  VALUES (v_session, auth.uid(), btrim(p_label), p_platform, now())
  ON CONFLICT (session_id) DO UPDATE
    SET label = EXCLUDED.label, platform = EXCLUDED.platform, updated_at = now()
    WHERE session_devices.user_id = auth.uid();
END $$;
REVOKE ALL ON FUNCTION public.register_my_device(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_my_device(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_my_sessions()
RETURNS TABLE (session_id uuid, device_label text, platform text,
               signed_in_at timestamptz, last_active_at timestamptz, is_current boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT s.id, d.label, d.platform, s.created_at,
         greatest(s.created_at, s.updated_at, s.refreshed_at AT TIME ZONE 'UTC'),
         s.id::text = coalesce(auth.jwt()->>'session_id', '')
  FROM auth.sessions s
  LEFT JOIN public.session_devices d ON d.session_id = s.id AND d.user_id = s.user_id
  WHERE auth.uid() IS NOT NULL AND s.user_id = auth.uid()
    AND (s.not_after IS NULL OR s.not_after > now())
  ORDER BY 5 DESC, s.id
$$;
REVOKE ALL ON FUNCTION public.list_my_sessions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_sessions() TO authenticated;
