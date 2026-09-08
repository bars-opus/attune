-- Extract the recent-word exclusion into a pure function.
--
-- WHY THIS EXISTS. The rule is "a word this couple has seen recently is
-- not drawn again", and it was tested the obvious way: create several
-- sessions and assert the words differed. That test was measured against
-- a build with the exclusion deleted and caught it 5 times in 12. Three
-- more variants were tried -- a three-word list, a two-word list, a fresh
-- couple, asserting the whole sequence -- and the best of them still
-- missed a third of the time.
--
-- The reason is structural, not a matter of tuning: with the exclusion
-- removed the draw is RANDOM, and a random draw agrees with the rule
-- often enough that any assertion over draws is a coin flip. A coin-flip
-- test is worse than no test, because green proves nothing and red gets
-- rerun until it agrees.
--
-- So the rule is lifted out of the random path. word_hunt_pool() takes a
-- word list and the words already seen and returns what may be drawn --
-- no randomness, exactly one right answer, and a contract test that fails
-- every time if the exclusion is removed.
CREATE OR REPLACE FUNCTION public.word_hunt_pool(
  p_words text[],
  p_recent text[]
)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    -- Falls back to the full list rather than failing: a short config
    -- plus a chatty couple must never mean no game.
    WHEN v.pool IS NULL OR cardinality(v.pool) = 0 THEN p_words
    ELSE v.pool
  END
  FROM (
    SELECT array_agg(w) AS pool
    FROM unnest(p_words) w
    WHERE NOT (w = ANY(COALESCE(p_recent, ARRAY[]::text[])))
  ) v;
$$;

REVOKE ALL ON FUNCTION public.word_hunt_pool(text[], text[])
  FROM PUBLIC, anon, authenticated;
