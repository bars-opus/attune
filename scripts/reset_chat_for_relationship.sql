-- Wipes a relationship's chat AND everything derived from it, so real
-- conversations start from nothing.
--
-- Deleting `messages` alone is NOT enough. Message-scoped tables cascade
-- (pins, reactions, stars, edit history, the three outboxes), but the
-- tables that matter for Pulse and insights are keyed on the RELATIONSHIP
-- and survive untouched: analysis_sessions, patterns, pulse_scores,
-- timeline_events, personal_insights, verdicts. Left behind, they carry
-- conclusions drawn from throwaway test chatter into the real data --
-- exactly the wrong starting point for a system whose whole output is
-- pattern detection over time.
--
-- USAGE: set the relationship id below, review, then run. Wrapped in a
-- transaction that ROLLBACKs by default -- change the last line to COMMIT
-- once the counts look right.

BEGIN;

\set rel_id '00000000-0000-0000-0000-000000000000'

-- What is about to be removed.
SELECT 'messages' AS t, count(*) FROM public.messages WHERE relationship_id = :'rel_id'::uuid
UNION ALL SELECT 'analysis_sessions', count(*) FROM public.analysis_sessions WHERE relationship_id = :'rel_id'::uuid
UNION ALL SELECT 'patterns', count(*) FROM public.patterns WHERE relationship_id = :'rel_id'::uuid
UNION ALL SELECT 'pulse_scores', count(*) FROM public.pulse_scores WHERE relationship_id = :'rel_id'::uuid
UNION ALL SELECT 'timeline_events', count(*) FROM public.timeline_events WHERE relationship_id = :'rel_id'::uuid
UNION ALL SELECT 'personal_insights', count(*) FROM public.personal_insights WHERE relationship_id = :'rel_id'::uuid
UNION ALL SELECT 'verdicts', count(*) FROM public.verdicts WHERE relationship_id = :'rel_id'::uuid
UNION ALL SELECT 'safety_events', count(*) FROM public.safety_events WHERE relationship_id = :'rel_id'::uuid;

-- ask2_state references messages with NO ACTION, so it must go first or
-- the message delete is blocked.
DELETE FROM public.ask2_state WHERE relationship_id = :'rel_id'::uuid;

-- Derived analysis. Order matters only where FKs chain.
DELETE FROM public.verdict_evidence WHERE verdict_id IN (
  SELECT id FROM public.verdicts WHERE relationship_id = :'rel_id'::uuid);
DELETE FROM public.verdicts WHERE relationship_id = :'rel_id'::uuid;
DELETE FROM public.personal_insights WHERE relationship_id = :'rel_id'::uuid;
DELETE FROM public.timeline_events WHERE relationship_id = :'rel_id'::uuid;
DELETE FROM public.pulse_score_diagnostics WHERE relationship_id = :'rel_id'::uuid;
DELETE FROM public.pulse_scores WHERE relationship_id = :'rel_id'::uuid;
DELETE FROM public.patterns WHERE relationship_id = :'rel_id'::uuid;
DELETE FROM public.safety_pattern_occurrences WHERE relationship_id = :'rel_id'::uuid;
DELETE FROM public.safety_events WHERE relationship_id = :'rel_id'::uuid;
DELETE FROM public.analysis_sessions WHERE relationship_id = :'rel_id'::uuid;

-- The chat itself. Pins, reactions, stars, edit history and the outboxes
-- cascade from here.
DELETE FROM public.messages WHERE relationship_id = :'rel_id'::uuid;

-- Upload intents are relationship-scoped and do not hang off messages.
DELETE FROM public.message_media_upload_intents WHERE relationship_id = :'rel_id'::uuid;

-- Confirm empty.
SELECT 'messages left' AS t, count(*) FROM public.messages WHERE relationship_id = :'rel_id'::uuid
UNION ALL SELECT 'analysis_sessions left', count(*) FROM public.analysis_sessions WHERE relationship_id = :'rel_id'::uuid
UNION ALL SELECT 'pulse_scores left', count(*) FROM public.pulse_scores WHERE relationship_id = :'rel_id'::uuid
UNION ALL SELECT 'patterns left', count(*) FROM public.patterns WHERE relationship_id = :'rel_id'::uuid;

-- Storage objects are NOT removed here: media files live in the storage
-- bucket, not Postgres. Clear them from the dashboard, or leave them --
-- orphaned objects are harmless once no message references them.

ROLLBACK; -- change to COMMIT when the counts look right
