-- Pauses the AI cron jobs during flow testing.
--
-- The test chat is random phrases with no meaning or continuity, so
-- running the analysis pipeline over it costs Gemini calls to produce
-- readings of noise -- and seeds pattern/insight tables with results
-- derived from text that was never a conversation.
--
-- Only the jobs that call an LLM are paused. Everything else keeps
-- running, in particular process-chat-safety-outbox, which is REGEX-based
-- (detectImmediateFamilies / detectTierThreeRuleIds), calls no model,
-- costs nothing, and is the self-harm and abuse net. Pausing that would
-- turn off a safety guarantee to save nothing.
--
-- Re-enable with 20260931160000_resume_ai_jobs.sql, which re-registers
-- all four through invoke_edge_function.

SELECT cron.unschedule(jobname)
FROM cron.job
WHERE jobname IN (
  'analyse-message-backlog',
  'analyse-session-sweep',
  'generate-verdict-monthly',
  'compute-pulse-weekly'
);
