-- Spec 1 W5: grants for 20261102110000_couple_profiles.sql. The shared
-- profile and the draft are read through their RPCs (and, under RLS,
-- directly: members while relationship_chat_open, the owner for a draft);
-- every write is a definer function. The service role keeps DML on both
-- tables. The merge, the attribution, the ceremony date, the adoption,
-- the anniversary sync and the reminder guard are server-only.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.couple_profiles FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.couple_profile_drafts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.couple_profiles TO authenticated;
GRANT SELECT ON public.couple_profile_drafts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.couple_profiles TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.couple_profile_drafts TO service_role;
REVOKE ALL ON FUNCTION private.couple_profile_ceremony_date(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.couple_profile_change(uuid, uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.couple_profile_merge(jsonb, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.guard_about_us_reminder() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.adopt_couple_profile_drafts(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.sync_anniversary_reminder(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_couple_profile(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_couple_profile(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_couple_profile_draft() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_my_couple_profile_draft(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_couple_profile(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_couple_profile(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_couple_profile_draft() TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_my_couple_profile_draft(jsonb) TO authenticated;
COMMIT;
