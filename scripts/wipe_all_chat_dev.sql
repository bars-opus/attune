-- DEV ONLY. Wipes EVERY couple's chat, and everything the app worked out
-- from it, so testing starts from nothing. For the dev project, where the
-- only couple is the owner's two test accounts. Never run on a project
-- with real users. reset_chat_for_relationship.sql (psql) does one couple.
--
-- Runs in the Supabase SQL Editor. Two steps:
--   1. Select STEP 1 only and run it: what's about to go.
--   2. Run STEP 2 (it commits; it can't be undone).
-- Then sign out and back in on both phones: signing out clears the app's
-- local chat cache, which would otherwise still show the old messages.
--
-- Kept: accounts, the relationship, Planning, Together, journals, stories,
-- check-ins, AI sessions (their links to messages are dropped or nulled).
-- Removed with the messages, by cascade: reactions, read receipts, pins,
-- stars, edit history, the three outboxes, streak clips, place updates,
-- jar entries made from a message. Message media files are queued for
-- deletion by the messages' own delete trigger.

-- ── STEP 1: preview ────────────────────────────────────────────────────
SELECT 'messages' AS what, count(*) FROM public.messages
UNION ALL SELECT 'analysis_sessions', count(*) FROM public.analysis_sessions
UNION ALL SELECT 'patterns', count(*) FROM public.patterns
UNION ALL SELECT 'pulse_scores', count(*) FROM public.pulse_scores
UNION ALL SELECT 'pulse_score_diagnostics', count(*) FROM public.pulse_score_diagnostics
UNION ALL SELECT 'timeline_events', count(*) FROM public.timeline_events
UNION ALL SELECT 'personal_insights', count(*) FROM public.personal_insights
UNION ALL SELECT 'verdicts', count(*) FROM public.verdicts
UNION ALL SELECT 'safety_events', count(*) FROM public.safety_events
UNION ALL SELECT 'relationships (message_count reset)', count(*) FROM public.relationships;

-- ── STEP 2: wipe ───────────────────────────────────────────────────────
BEGIN;

-- ask2_state points at messages with NO ACTION: it goes first, or the
-- message delete is blocked.
DELETE FROM public.ask2_state;

-- What was worked out from the chat. Order matters only where FKs chain.
DELETE FROM public.verdict_evidence;
DELETE FROM public.verdicts;
DELETE FROM public.personal_insights;
DELETE FROM public.timeline_events;
DELETE FROM public.pulse_score_diagnostics;
DELETE FROM public.pulse_scores;
DELETE FROM public.patterns;
DELETE FROM public.safety_pattern_occurrences;
DELETE FROM public.safety_events;
DELETE FROM public.analysis_sessions;

-- The chat itself (the message tables above cascade from here).
DELETE FROM public.messages;

-- Relationship-scoped chat state that doesn't hang off a message.
DELETE FROM public.message_media_upload_intents;
DELETE FROM public.message_read_marks;

-- Only incremented on insert; nothing recounts it on delete.
UPDATE public.relationships SET message_count = 0 WHERE message_count <> 0;
-- The live count since 20261019100100 (its delete trigger already
-- decrements it; this makes the reset explicit).
UPDATE public.relationship_message_counters SET message_count = 0, updated_at = now()
WHERE message_count <> 0;

COMMIT;

-- Check: every count should be 0.
SELECT 'messages left' AS what, count(*) FROM public.messages
UNION ALL SELECT 'analysis_sessions left', count(*) FROM public.analysis_sessions
UNION ALL SELECT 'pulse_scores left', count(*) FROM public.pulse_scores
UNION ALL SELECT 'timeline_events left', count(*) FROM public.timeline_events;

-- ── STEP 3: games ──────────────────────────────────────────────────────
-- Every game played, and what each game remembers, so games start fresh.
-- Independent of STEP 2: run it before or after. Preview first:
SELECT 'game_sessions' AS what, count(*) FROM public.game_sessions
UNION ALL SELECT 'game_session_rounds', count(*) FROM public.game_session_rounds
UNION ALL SELECT 'game_questions_seen', count(*) FROM public.game_questions_seen
UNION ALL SELECT 'thirty_six_question_journeys', count(*) FROM public.thirty_six_question_journeys
UNION ALL SELECT 'thirty_six_questions_seen', count(*) FROM public.thirty_six_questions_seen;

-- Kept: the games' own content: game_questions (the question catalogue),
-- snakes_boards, word_hunt_configs, the 36 questions themselves, and the
-- couple's own custom Truth or Dare / This or That questions.
BEGIN;

-- Cascades to rounds, answers (36 questions, This or That, Mirror truths),
-- Mirror scores, Paint Ball penalties, Word Hunt puzzles and attempts, the
-- truth-answer safety outbox, idempotency keys, and any chat message that
-- carried a game.
DELETE FROM public.game_sessions;

-- Which questions each couple has already seen (so nothing repeats).
DELETE FROM public.game_questions_seen;

-- 36 Questions: after game_sessions, which point at journeys. Chapter
-- reflections cascade from the journey.
DELETE FROM public.thirty_six_question_journeys;
DELETE FROM public.thirty_six_questions_seen;

COMMIT;

SELECT 'game_sessions left' AS what, count(*) FROM public.game_sessions
UNION ALL SELECT 'thirty_six_question_journeys left', count(*) FROM public.thirty_six_question_journeys;
