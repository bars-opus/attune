-- Spec 2 W5b: grants for 20261119110000_dating_v2_today.sql. Today, the
-- introductions read, act and the two marks are the app's (authenticated
-- only); the photo keys are the service role's (dating-photo-urls); the
-- digest is cron's; the helpers are the database's own, the service role
-- included (the card decrypts what the person chose to show, S-4). The
-- introductions and matches stay no API role's (S-5).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_introductions, public.dating_matches, public.dating_interest_actions
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_photo_viewable(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_caption_has_contact(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_card(uuid, uuid, public.dating_introductions) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_visible_introductions(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_today() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_introductions() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.act_on_dating_introduction(text, uuid, text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.mark_dating_match_moment_seen(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.dismiss_dating_today_note(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_today(), public.get_my_dating_introductions(),
  public.act_on_dating_introduction(text, uuid, text), public.mark_dating_match_moment_seen(uuid),
  public.dismiss_dating_today_note(text) TO authenticated;
REVOKE ALL ON FUNCTION public.dating_photo_keys_for_viewer(uuid, text, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dating_photo_keys_for_viewer(uuid, text, uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.send_dating_digests() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
