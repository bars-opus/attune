-- Spec 2 W8b: grants for 20261122100000_dating_v2_traveller.sql. The device
-- check's record is the service role's alone (dating-device-check's); the
-- trip choice is the app's; the helpers are the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.dating_traveller_on() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_wants_same_gender(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_trip_hides(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_trip_json(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_icon_offer_json(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_dating_device_check(uuid, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_dating_device_check(uuid, text, text, text) TO service_role;
REVOKE ALL ON FUNCTION public.set_dating_trip_choice(text, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.set_dating_trip_choice(text, boolean) TO authenticated;
REVOKE ALL ON FUNCTION private.dating_has_same_gender_pair(uuid) FROM PUBLIC, anon, authenticated, service_role; -- fix round 2 (Re-I-1)
REVOKE ALL ON FUNCTION private.dating_same_gender_trip(uuid) FROM PUBLIC, anon, authenticated, service_role; -- fix round 2 (Re-I-1)
REVOKE ALL ON FUNCTION private.dating_intro_counts(text, timestamptz) FROM PUBLIC, anon, authenticated, service_role; -- fix round 3 (Re2-M-1)
REVOKE ALL ON FUNCTION private.dating_pair_seen_as_man_woman(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role; -- fix round 3 (Re2-I-1); final server fix (I-1): viewer-visible only
REVOKE ALL ON FUNCTION private.dating_same_gender_hiding(uuid) FROM PUBLIC, anon, authenticated, service_role; -- fix round 3
REVOKE ALL ON FUNCTION private.dating_trip_hides(uuid, uuid, text, boolean) FROM PUBLIC, anon, authenticated, service_role; -- fix round 3
REVOKE ALL ON FUNCTION private.dating_review_mode() FROM PUBLIC, anon, authenticated, service_role; -- Task 5 (W7 carry M-6)
-- Task 5 (R-T5-1): the reads that hide, re-created with p_show_same_gender
-- (the old signatures dropped), granted exactly as before: the app's alone.
REVOKE ALL ON FUNCTION public.get_my_dating_today(boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_today(boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.get_my_dating_introductions(boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_introductions(boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.act_on_dating_introduction(text, uuid, text, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.act_on_dating_introduction(text, uuid, text, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.get_my_dating_matches(boolean, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_matches(boolean, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.get_dating_messages(uuid, timestamptz, integer, boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_messages(uuid, timestamptz, integer, boolean) TO authenticated;
COMMIT;
