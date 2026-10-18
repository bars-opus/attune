-- Spec 8: grants for 20261018150100 (edit_message keeps its own).
REVOKE ALL ON FUNCTION public.send_pause(uuid, uuid, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.send_pause_reply(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pause_reply_state(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_pause(uuid, uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_pause_reply(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pause_reply_state(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.pause_reply_allowed(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.messages_pause_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pause_text(integer) FROM PUBLIC, anon, authenticated;
