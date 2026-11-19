-- Spec 2 W4a: grants for 20261109100000_dating_v2_age_assurance.sql. The
-- session table is no API role's, the service role included (the edge
-- function goes through the service functions only). The status read and
-- the human-review upload predicate are the app's (the predicate runs inside
-- the storage policy as the signed-in role). The session, result and review
-- writers, the config read and the far-below path are the service role's
-- (dating-verification; the review decision until W7b's console). The
-- helpers and the sweep are the database's own. The re-created functions
-- keep their grants.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_verification_sessions FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_verification_mode() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_verification_available() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_verification_state(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_age_recheck_due(uuid) FROM PUBLIC, anon, authenticated, service_role; -- Spec 2 W4 final (I-1b)
REVOKE ALL ON FUNCTION private.dating_request_device_hash() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.sweep_dating_verification_sessions() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_verification() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_verification() TO authenticated;
REVOKE ALL ON FUNCTION public.dating_review_upload_open(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.dating_review_upload_open(text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_dating_verification_config() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.begin_dating_verification(uuid, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_dating_verification_session(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_dating_verification_photos(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_dating_verification_ref(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_liveness_attempt(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finish_dating_verification_session(uuid, text, text, smallint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_identity_check(uuid, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_age_assurance(uuid, text, text, smallint, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_age_far_below(uuid, uuid, text) FROM PUBLIC, anon, authenticated; -- Spec 2 W4 final (M-8)
REVOKE ALL ON FUNCTION public.record_dating_video_outcome(uuid, uuid, text, text, smallint, text, text) FROM PUBLIC, anon, authenticated; -- Spec 2 W4a (T2 fix round 1, I-3)
REVOKE ALL ON FUNCTION public.check_dating_id_birth_date(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_dating_human_review(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.decide_dating_human_review(uuid, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.revoke_dating_age_verification(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_dating_verification_config() TO service_role;
GRANT EXECUTE ON FUNCTION public.begin_dating_verification(uuid, text, text, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_verification_session(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_verification_photos(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_dating_verification_ref(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_liveness_attempt(uuid, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_dating_verification_session(uuid, text, text, smallint) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_identity_check(uuid, text, text, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_age_assurance(uuid, text, text, smallint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_age_far_below(uuid, uuid, text) TO service_role; -- Spec 2 W4 final (M-8)
GRANT EXECUTE ON FUNCTION public.record_dating_video_outcome(uuid, uuid, text, text, smallint, text, text) TO service_role; -- Spec 2 W4a (T2 fix round 1, I-3)
GRANT EXECUTE ON FUNCTION public.check_dating_id_birth_date(uuid, date) TO service_role;
GRANT EXECUTE ON FUNCTION public.submit_dating_human_review(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.decide_dating_human_review(uuid, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.revoke_dating_age_verification(uuid, text) TO service_role;
COMMIT;
