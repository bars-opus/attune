-- supabase/migrations/20260901150000_chat_voice_video_dimension_columns.sql
--
-- Adds messages.media_duration_ms/media_waveform/media_width/media_height —
-- four columns that were supposed to be added by
-- 20260815120000_chat_voice_messages.sql and
-- 20260816120000_chat_video_media_dimensions.sql respectively, but neither
-- of those migrations ever actually ran against this remote database (their
-- original version-number slots had already been claimed by unrelated
-- migrations — end_relationship and dating_match_id_notification — before
-- either voice/video migration was written, so `supabase db push` silently
-- treated them as already-applied and never executed their SQL).
--
-- This migration deliberately does NOT reapply
-- 20260815120000_chat_voice_messages.sql's function bodies
-- (create_chat_media_upload_intent, validate_message_media_before_insert)
-- or its messages_media_type_check widening — those were ALL independently
-- re-created by 20260815130000_chat_video_messages.sql (confirmed already
-- applied to this remote), which already handles 'image'/'audio'/'video'
-- correctly, including the chat_voice_messages flag branch and the 1.2MB
-- audio size ceiling. Reapplying the older voice-only versions of those
-- functions here would silently regress them back to audio-only support,
-- destroying already-working video/ephemeral-video upload functionality.
-- Similarly, the 'chat_voice_messages' feature_flags row already exists
-- (inserted by 20260705190000_chat_system_v1_3.sql, confirmed applied).
--
-- Only the columns are genuinely missing. Nothing else from either
-- never-applied migration needs to be replayed — every other change either
-- flat-lines against a later, already-applied migration, or was never
-- actually needed in the first place.
--
-- Column-level SELECT/INSERT grants for these four columns are already
-- handled by 20260902120000_chat_ephemeral_video_final_review_fixes.sql,
-- which failed to apply specifically because these columns didn't exist yet
-- (42703 "column does not exist" — the columns had to exist before a GRANT
-- naming them could succeed). This migration's timestamp
-- (20260901150000) deliberately sorts BEFORE 20260902120000 so a single
-- `supabase db push` applies this one first and the grants migration
-- succeeds on the same run.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS media_duration_ms integer,
  ADD COLUMN IF NOT EXISTS media_waveform jsonb,
  ADD COLUMN IF NOT EXISTS media_width integer,
  ADD COLUMN IF NOT EXISTS media_height integer;
