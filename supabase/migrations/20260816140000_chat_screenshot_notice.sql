-- supabase/migrations/20260816140000_chat_screenshot_notice.sql
--
-- The smallest viable addition to support one new use case: an in-chat
-- notice when a screenshot is detected during ephemeral video viewing (see
-- design spec Section 7.5). Confirmed by direct search across this
-- codebase before writing this migration: there is NO existing
-- system-message/message_kind convention to reuse — this genuinely
-- invents the minimal one needed, not a general framework speculatively
-- built for hypothetical future system-message types.
--
-- A screenshot notice is NOT actually "authored by nobody" — per the
-- design spec, it's "authored as if from the viewer (the person who
-- screenshotted)" and rides the ordinary sender_id/insert path unchanged.
-- The only new thing is a flag distinguishing "this row is a system
-- notice, render it as plain informational text, not a normal bubble" —
-- everything else about how it's inserted, synced, and delivered reuses
-- the existing messages pipeline entirely.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS is_system_notice boolean NOT NULL DEFAULT false;
