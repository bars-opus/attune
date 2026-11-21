-- Spec 2 W6a: grants for 20261120100000_dating_v2_chat.sql. The masker,
-- the caption trigger and the pair marker are the database's own (no API
-- role's, the service role included: a marker is a keyed code of two
-- numbers, and the masker is presentation the server applies). The chat's
-- RPCs are the app's (authenticated only); its tables are no API role's
-- but the chat signals, which a signed-in person reads for their own rows
-- (realtime). dating_messages is revoked from the service role too (S-5;
-- W6b's worker reads bodies only through its claim function).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON TABLE public.dating_pair_markers FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_mask_fold(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_mask_leet(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_mask_digits(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_mask_contacts(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_mask_contacts_safe(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_caption_invites(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_photo_caption_mask() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_code(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_mark_pair(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_new(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_backfill_pair_markers() FROM PUBLIC, anon, authenticated, service_role; -- fix round 1 (M-4)
-- Re-created (CREATE OR REPLACE keeps their grants; re-asserted).
REVOKE ALL ON FUNCTION private.dating_card(uuid, uuid, public.dating_introductions) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_generate_partition(text, text, text, date, timestamptz, text, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.act_on_dating_introduction(text, uuid, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.act_on_dating_introduction(text, uuid, text) TO authenticated;
-- The chat (Task 2).
REVOKE ALL ON TABLE public.dating_messages FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.dating_chat_signals FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.dating_chat_signals TO authenticated;
REVOKE ALL ON FUNCTION private.dating_bump_chat(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_message_json(public.dating_messages, text, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_key_ok(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_chat_header(public.dating_matches, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_swap_write(uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_open_chats(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_first_messages(uuid, timestamptz, timestamptz) FROM PUBLIC, anon, authenticated, service_role; -- fix round 1 (M-8)
REVOKE ALL ON FUNCTION private.dating_pair_blocked(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role; -- fix round 1 (I-1, M-5)
REVOKE ALL ON FUNCTION private.dating_body_blank(text) FROM PUBLIC, anon, authenticated, service_role; -- fix round 1 (M-1)
-- The app's: the chat RPCs; dating_can_send also backs the INSERT policy.
REVOKE ALL ON FUNCTION public.dating_can_send(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.dating_can_send(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.send_dating_message(text, uuid, text, text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.send_dating_message(text, uuid, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_dating_messages(uuid, timestamptz, integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_messages(uuid, timestamptz, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.get_my_dating_matches(boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_matches(boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.offer_dating_contact_swap(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.offer_dating_contact_swap(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.withdraw_dating_contact_swap(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.withdraw_dating_contact_swap(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.block_dating_match(text, uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.block_dating_match(text, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.unmatch_dating_match(text, uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.unmatch_dating_match(text, uuid) TO authenticated;
-- Final server fix (I-8, M-8, I-3, I-1): the database's own.
REVOKE ALL ON FUNCTION private.dating_mask_fallback(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_mask_counted(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_code(text, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_new(uuid, uuid, text, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_chat_on() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_matches_seal_window() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
