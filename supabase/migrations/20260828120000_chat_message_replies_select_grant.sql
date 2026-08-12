-- messages' SELECT privilege is column-level and additive across migrations
-- (20260705190000_chat_system_v1_3.sql granted the base columns + `source`;
-- 20260705200000_chat_media_hardening.sql later added `media_thumbnail_url`).
-- 20260827120000_chat_message_replies.sql only extended the INSERT grant for
-- reply_to_message_id/quoted_text and missed this SELECT counterpart, so any
-- client .select() naming those two columns was rejected with 42501 even
-- though the columns exist and INSERT already worked. Adding the missing
-- grant here rather than editing the already-applied migration.
GRANT SELECT (
  reply_to_message_id,
  quoted_text
) ON public.messages TO authenticated;
