-- Grants for 20261019100100_chat_message_counters.
REVOKE ALL ON public.relationship_message_counters FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.relationship_message_counters TO authenticated;
GRANT SELECT ON public.relationship_message_counters TO service_role;
REVOKE ALL ON FUNCTION public.messages_count_on_delete() FROM PUBLIC, anon, authenticated;
