-- Spec 2 W7b: grants for 20261121110000_dating_v2_moderation_console.sql. The
-- moderators and the audit are no API role's (the console's definer
-- functions read and write them); the moderation_* functions are the
-- service role's alone (the dating-moderation edge function calls them
-- with the moderator's id after checking the moderator's aal2 session); the
-- SLA check is the cron's; the helpers are the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON TABLE public.dating_moderators FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.dating_moderation_actions FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_moderation_actions_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_audit(uuid, uuid, text, uuid, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_moderator(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_identity_of(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_case_needs_sensitive_routing(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_case_for(public.dating_moderators, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_evidence_messages(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_lift_case_holds(uuid) FROM PUBLIC, anon, authenticated, service_role;
-- Task 5: the replay check and the locked case read.
REVOKE ALL ON FUNCTION private.dating_moderation_replayed(uuid, uuid, text, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_case_lock(public.dating_moderators, uuid) FROM PUBLIC, anon, authenticated, service_role;
-- Task 5 fix round 1: who is a party to a case.
REVOKE ALL ON FUNCTION private.dating_case_party(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_moderation_sla_check(timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.moderation_whoami(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_whoami(uuid) TO service_role;
-- W7 final server fix (I-3): the queue's grant is in the W7c twin
-- (20261121120010): W7c drops this 2-argument queue for one with a kind,
-- so a line here would name a function that no longer exists when the
-- twins are replayed after every migration (the local harness).
REVOKE ALL ON FUNCTION public.moderation_case(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_case(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_claim(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_claim(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_dismiss(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_dismiss(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_place_hold(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_place_hold(uuid, uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_lift_hold(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_lift_hold(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_restrict(uuid, uuid, text, timestamptz, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_restrict(uuid, uuid, text, timestamptz, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_ask_for_id(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_ask_for_id(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_confirm_minor(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_confirm_minor(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_note(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_note(uuid, uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_decide_appeal(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_decide_appeal(uuid, uuid, boolean) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_photos(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_photos(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_photo_decide(uuid, uuid, boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_photo_decide(uuid, uuid, boolean, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_verifications(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_verifications(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_verification_decide(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_verification_decide(uuid, uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_countries(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_countries(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_publish_country(uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_publish_country(uuid, text, jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_opinions_queue(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_opinions_queue(uuid, integer) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_opinions_remove(uuid, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_opinions_remove(uuid, text, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.moderation_audit_log(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.moderation_audit_log(uuid, integer) TO service_role;
COMMIT;
