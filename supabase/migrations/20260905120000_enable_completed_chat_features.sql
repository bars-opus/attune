-- Enable the chat features that are built, tested, and server-enforced.
--
-- Every feature_flags row in this project shipped `false` and no migration
-- ever flipped one, so a set of fully-implemented features have been dark
-- in production. The gates are real (create_chat_media_upload_intent does
-- `RAISE EXCEPTION 'Image sharing is unavailable'`), not cosmetic — so this
-- is the switch that actually ships them.
--
-- Enabled here, each verified against its client wiring, server
-- enforcement, and passing test suite before being turned on:
--
--   chat_image_sharing    §8.1 Month 2 non-negotiable. ChatImagePreparer +
--                         media upload intents + 4 enforcing migrations.
--   chat_voice_messages   Recorder, player, outbox, 15 service tests.
--   chat_video_sharing    ChatVideoPreparer, trim screen, poster pipeline.
--   chat_ephemeral_video  Camera, viewer, view-once server enforcement.
--   chat_translator_entry §8.6 composer entry into translate-conflict.
--   chat_streaks          Header streak counter, fetchStreak wired.
--
-- Deliberately NOT enabled:
--
--   chat_expanded_header_drawer  Built but unreviewed against §9's
--                                navigation rules; enable once that
--                                review lands.
--   chat_historical_import       Bulk backfill path; needs its own data
--                                -safety review before real user content
--                                flows through it.
--   chat_link_previews           Flag constant only — there is no
--                                implementation behind it. Turning this on
--                                would advertise a feature that does not
--                                exist.
--   chat_reactions               Vestigial. Reactions shipped later
--   chat_edit_delete             (20260901130000_message_reactions.sql)
--                                without ever reading these 20260705 flags,
--                                so both features are ALREADY live and
--                                these rows gate nothing. Left false rather
--                                than implying they are the real switch.
--   dating_*                     §8.10/§14: gated on 2,000+ active couples
--                                and a Month 6+ build. A product gate, not
--                                a readiness one.
--
-- ON CONFLICT DO UPDATE is required, not optional: the rows already exist
-- from earlier migrations, so a plain INSERT would no-op silently and this
-- migration would appear to succeed while changing nothing.

INSERT INTO public.feature_flags (key, enabled) VALUES
  ('chat_image_sharing', true),
  ('chat_voice_messages', true),
  ('chat_video_sharing', true),
  ('chat_ephemeral_video', true),
  ('chat_translator_entry', true),
  ('chat_streaks', true)
ON CONFLICT (key) DO UPDATE
  SET enabled = EXCLUDED.enabled,
      updated_at = now();
