-- supabase/migrations/20261017160000_user_timezone.sql
--
-- The recipient's time zone, for quiet hours (Spec 1b; owner decision
-- 2026-10-17: a user-level column the app reports on open).
--
-- users is self-only under RLS, so the partner never reads it (a zone is
-- coarse location). Clients hold table-level UPDATE on their own users row,
-- so a client could write anything here: set_my_timezone is the app's path,
-- and every reader validates with presence_tz_ok and falls back.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS timezone text
  CHECK (timezone IS NULL OR char_length(timezone) BETWEEN 1 AND 64);

CREATE OR REPLACE FUNCTION public.set_my_timezone(p_timezone text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.presence_tz_ok(p_timezone) THEN
    RAISE EXCEPTION 'timezone:invalid_input';
  END IF;
  -- The app reports at sign-in, before onboarding creates the profile row.
  -- Saying "done" then would make it never report again (final review C1);
  -- refuse, and it retries on the next open.
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'timezone:no_profile';
  END IF;
  UPDATE public.users SET timezone = p_timezone
   WHERE id = auth.uid() AND timezone IS DISTINCT FROM p_timezone;
END $$;
REVOKE ALL ON FUNCTION public.set_my_timezone(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_timezone(text) TO authenticated;

-- Where a push's recipient is: their own report, then the zone Planning or
-- Together last stored for them, then the couple map's. NULL means unknown:
-- callers must not guess (a UTC guess holds a UTC-5 user's 19:00 push until
-- 03:00 local).
CREATE OR REPLACE FUNCTION public.notification_recipient_tz(p_user uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v text;
BEGIN
  SELECT u.timezone INTO v FROM public.users u WHERE u.id = p_user;
  IF public.presence_tz_ok(v) THEN RETURN v; END IF;
  FOR v IN SELECT s.timezone FROM public.planning_member_settings s
            WHERE s.user_id = p_user ORDER BY s.updated_at DESC LIMIT 3 LOOP
    IF public.presence_tz_ok(v) THEN RETURN v; END IF;
  END LOOP;
  FOR v IN SELECT p.timezone FROM public.partner_presence p
            WHERE p.user_id = p_user AND p.timezone IS NOT NULL
            ORDER BY p.updated_at DESC NULLS LAST LIMIT 3 LOOP
    IF public.presence_tz_ok(v) THEN RETURN v; END IF;
  END LOOP;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.notification_recipient_tz(uuid) FROM PUBLIC, anon, authenticated;

-- The resolver runs on every queued push (Spec 1b quiet guard); its Planning
-- lookup is by user, which the (relationship_id, user_id) key cannot serve.
CREATE INDEX IF NOT EXISTS planning_member_settings_user_idx
  ON public.planning_member_settings (user_id, updated_at DESC);
