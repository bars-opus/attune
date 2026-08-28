-- Voice notes have never been sendable: messages_media_type_check allowed
-- only ('image','video'), so every insert failed with 23514.
--
-- How it happened: 20260815120000_chat_voice_messages.sql was written but
-- never executed -- the migration history was marked applied, so its SQL
-- was skipped. 20260901150000 then explicitly declined to reapply that
-- migration's messages_media_type_check widening, on the stated grounds
-- that 20260815130000_chat_video_messages.sql had already re-created it.
-- It had not: 20260815130000 widens
-- message_media_upload_intents_media_type_check, a different table.
--
-- The two constraints therefore drifted, which is exactly why the failure
-- was so hard to place. create_chat_media_upload_intent accepted audio, the
-- file uploaded successfully, and only the final insert into messages
-- failed -- so every layer the user could see appeared to work.
ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_media_type_check;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_media_type_check
  CHECK (media_type IS NULL OR media_type IN ('image', 'audio', 'video'));
