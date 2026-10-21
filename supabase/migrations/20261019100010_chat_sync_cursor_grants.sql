-- Grants for 20261019100000_chat_sync_cursor.
-- messages SELECT is column-scoped for authenticated; the cursor column
-- must be readable or getMessagesChangedSince fails with 42501.
GRANT SELECT (updated_at) ON public.messages TO authenticated;
GRANT SELECT (updated_at) ON public.messages TO service_role;
-- Trigger functions are never client-callable.
REVOKE ALL ON FUNCTION public.messages_touch_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.message_reactions_touch_message() FROM PUBLIC, anon, authenticated;
