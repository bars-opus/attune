-- Excludes deliberately-skipped messages (AI Assistant Assist-mode
-- output, once Task 6's share RPC sets message_analysis_skipped = true)
-- from the analysis backlog index, so a skipped row can never keep the
-- backlog/health metric permanently red. Spec
-- docs/superpowers/specs/2026-09-15-ai-assistant-design.md §8.2.
--
-- Real prior definition (20260705173000_analysis_pipeline_foundations.sql):
--   CREATE INDEX IF NOT EXISTS idx_messages_analysis_backlog
--     ON public.messages (created_at, id)
--     WHERE message_analysis_done = false;
-- Reproduced here with the exact same columns, only adding the skipped
-- exclusion to the WHERE clause.
DROP INDEX IF EXISTS public.idx_messages_analysis_backlog;

CREATE INDEX IF NOT EXISTS idx_messages_analysis_backlog
  ON public.messages (created_at, id)
  WHERE message_analysis_done = false AND message_analysis_skipped = false;
