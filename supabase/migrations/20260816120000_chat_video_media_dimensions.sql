-- supabase/migrations/20260816120000_chat_video_media_dimensions.sql
--
-- Follow-up to 20260815130000_chat_video_messages.sql: that migration wired
-- up the video upload-intent/thumbnail-validation pipeline but did not add
-- storage for the video's intrinsic pixel dimensions. The client (Task 3's
-- ChatVideoPreparer) already reports width/height from the compressed
-- output, and the chat pipeline (Task 5) needs a column to persist them so
-- the message list can reserve correct aspect-ratio space before the
-- signed thumbnail URL resolves. No RLS changes — these are plain
-- nullable columns on an already-covered table.

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS media_width integer,
  ADD COLUMN IF NOT EXISTS media_height integer;
