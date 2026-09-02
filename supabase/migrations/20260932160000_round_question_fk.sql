-- game_session_rounds.question_id needs a real foreign key.
--
-- Without it PostgREST cannot resolve an embedded select, and This or
-- That's session query -- '*, game_questions(question_text, option_a,
-- ...)' -- fails outright:
--
--   "Could not find a relationship between game_session_rounds and
--    game_questions in the schema cache"
--
-- which is what a partner hit when tapping Resume session. The column has
-- existed and been populated all along; only the constraint was missing,
-- so the join looked correct in every code review and failed at runtime.
--
-- ON DELETE SET NULL rather than CASCADE: retiring a question from the
-- catalogue must never delete the rounds people already played, and the
-- round keeps its question_text_snapshot regardless.
--
-- Any orphan is cleared first. A question_id pointing at a row that no
-- longer exists would block the constraint, and a null there is already
-- the shape the schema allows.
UPDATE public.game_session_rounds r
   SET question_id = NULL
 WHERE r.question_id IS NOT NULL
   AND NOT EXISTS (
     SELECT 1 FROM public.game_questions q WHERE q.id = r.question_id
   );

ALTER TABLE public.game_session_rounds
  DROP CONSTRAINT IF EXISTS game_session_rounds_question_id_fkey;

ALTER TABLE public.game_session_rounds
  ADD CONSTRAINT game_session_rounds_question_id_fkey
  FOREIGN KEY (question_id) REFERENCES public.game_questions(id)
  ON DELETE SET NULL;

-- PostgREST caches the schema; without this the join keeps failing until
-- something else happens to reload it.
NOTIFY pgrst, 'reload schema';
