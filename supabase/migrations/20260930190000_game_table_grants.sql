-- Table privileges for the game tables.
--
--   permission denied for table thirty_six_question_journeys (42501)
--
-- Supabase grants table privileges PLATFORM-SIDE when a table is created
-- through its API, not by anything in a migration. A table created by a
-- migration gets whatever the default privileges happen to be at that
-- moment — so some of these work by accident of creation order and the
-- 36 Questions tables, added later, got nothing. Opening the Paint Ball
-- lobby reads the journeys table and failed outright.
--
-- Granted explicitly here so the privilege is versioned with the code
-- rather than depending on how a table happened to come into existence.
--
-- RLS remains the real gate: every table below has it enabled with
-- policies, so a grant widens nothing on its own. Postgres checks the
-- table privilege FIRST and the policy second — without the grant the
-- policy is never consulted, which is why this failed as 42501 rather
-- than returning an empty result.
--
-- The local harness cannot catch this class of bug: scripts/
-- local_pg_grants.sql applies a blanket grant to mirror the platform, so
-- every table looks reachable there. A contract test below asserts the
-- privilege explicitly instead.

-- Read/write: rows a couple owns and mutates through the app.
GRANT SELECT, INSERT, UPDATE ON public.game_sessions TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.game_session_rounds TO authenticated;
GRANT SELECT, INSERT ON public.session_idempotency_keys TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.thirty_six_question_journeys
  TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.thirty_six_question_answers
  TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.chapter_reflections TO authenticated;
GRANT SELECT, INSERT ON public.thirty_six_questions_seen TO authenticated;
GRANT SELECT, INSERT ON public.game_questions_seen TO authenticated;

-- Custom questions are authored and removed by their writer.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.custom_truth_or_dare_questions
  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.custom_this_or_that_questions
  TO authenticated;

-- Content catalogues: read-only to clients. No INSERT — a client that
-- could write these could author the questions everyone else is served.
GRANT SELECT ON public.game_questions TO authenticated;
GRANT SELECT ON public.thirty_six_questions_canonical TO authenticated;
GRANT SELECT ON public.thirty_six_questions_translations TO authenticated;

-- Explicitly revoked, not merely "not granted". A client that could write
-- these would author the questions every other couple is served, and a
-- blanket ALL TABLES grant applied by a future migration would otherwise
-- hand them exactly that.
REVOKE INSERT, UPDATE, DELETE ON public.game_questions FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.thirty_six_questions_canonical
  FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.thirty_six_questions_translations
  FROM authenticated;
