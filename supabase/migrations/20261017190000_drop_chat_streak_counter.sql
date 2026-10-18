-- supabase/migrations/20261017190000_drop_chat_streak_counter.sql
--
-- The chat streak counter goes (Spec 1b; research 06 §3 F6 (2); SOUL §5 P1:
-- no streaks, under any name). Its flag was on in production and the client
-- fetched the count on every chat open (nothing displayed it). The streak
-- CAMERA (streak_clips, mark_streak_viewed, streak_views_remaining) is a
-- different feature and stays.
DROP FUNCTION IF EXISTS public.chat_conversation_streak(uuid, int);
DELETE FROM public.feature_flags WHERE key = 'chat_streaks';
