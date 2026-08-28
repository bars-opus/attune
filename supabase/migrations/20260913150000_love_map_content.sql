-- Love Map's seeded question bank: 60 prompts, 15 in each of the four
-- domains the refresh job maps detected chat topics onto.
--
-- All prompts are third-person about the SUBJECT ("they/them"); the
-- question screen re-frames them for whoever is viewing, so the subject is
-- told to answer about themselves. None references anything from chat --
-- the AI selects among these, it never writes a prompt.
--
-- 60 is the coverage denominator: roughly five months at three per week.
-- Fewer would make the map feel finishable, which §8.4 does not want.
WITH seed(value_domain, question_text) AS (
  VALUES
    ('fears', 'What are they most afraid of losing right now?'),
    ('fears', 'What worry keeps them awake when they cannot sleep?'),
    ('fears', 'What are they quietly dreading this year?'),
    ('fears', 'What do they avoid talking about, even with you?'),
    ('fears', 'What would they say is their biggest insecurity?'),
    ('fears', 'What kind of failure would hurt them most?'),
    ('fears', 'What are they scared of becoming?'),
    ('fears', 'What do they fear people misunderstand about them?'),
    ('fears', 'What situation makes them feel least in control?'),
    ('fears', 'What are they afraid would happen if they slowed down?'),
    ('fears', 'What criticism lands hardest on them?'),
    ('fears', 'What do they worry they are not good enough at?'),
    ('fears', 'What change would unsettle them most right now?'),
    ('fears', 'What are they afraid to ask for?'),
    ('fears', 'What do they fear losing about themselves?'),
    ('dreams', 'What would they do with a completely free year?'),
    ('dreams', 'What are they quietly hoping happens this year?'),
    ('dreams', 'What would they build if money were not a question?'),
    ('dreams', 'Where do they most want to live one day?'),
    ('dreams', 'What version of their work would make them proudest?'),
    ('dreams', 'What have they always wanted to learn but never started?'),
    ('dreams', 'What kind of home do they picture for the two of you?'),
    ('dreams', 'What would make them feel their life was well spent?'),
    ('dreams', 'What dream have they set aside and still think about?'),
    ('dreams', 'What would they want more of in an ordinary week?'),
    ('dreams', 'What place do they most want to see together?'),
    ('dreams', 'What would they do differently if no one was watching?'),
    ('dreams', 'What are they most excited about right now?'),
    ('dreams', 'What would they want to be remembered for?'),
    ('dreams', 'What would make the next five years feel like a success to them?'),
    ('stressors', 'What is draining them most this month?'),
    ('stressors', 'What obligation are they carrying that they did not choose?'),
    ('stressors', 'Which relationship outside this one is costing them most?'),
    ('stressors', 'What at work is weighing heaviest right now?'),
    ('stressors', 'What have they been putting off that keeps nagging at them?'),
    ('stressors', 'What is taking more of their energy than they admit?'),
    ('stressors', 'What would they most like to say no to?'),
    ('stressors', 'What part of their routine is wearing them down?'),
    ('stressors', 'What money worry is on their mind?'),
    ('stressors', 'What are they handling alone that they should not be?'),
    ('stressors', 'Which decision are they stuck on right now?'),
    ('stressors', 'What has been making them feel rushed lately?'),
    ('stressors', 'What do they need more of that they are not getting?'),
    ('stressors', 'What has been harder for them recently than they let on?'),
    ('stressors', 'What would take the most weight off them this week?'),
    ('history', 'What moment shaped how they trust people?'),
    ('history', 'What did they learn about love from their parents?'),
    ('history', 'What were they like as a child?'),
    ('history', 'What early experience still affects how they handle conflict?'),
    ('history', 'Which friendship shaped them most, and how?'),
    ('history', 'What did they want to be when they grew up?'),
    ('history', 'What was the hardest year of their life so far?'),
    ('history', 'What is a memory they return to when they need comfort?'),
    ('history', 'What did they have to figure out on their own too early?'),
    ('history', 'Which teacher or mentor changed how they saw themselves?'),
    ('history', 'What did home feel like when they were growing up?'),
    ('history', 'What is something they were praised for that stuck with them?'),
    ('history', 'What loss still shapes how they hold onto people?'),
    ('history', 'What did they believe at twenty that they no longer believe?'),
    ('history', 'What is a story from their past you have never asked about?')
)
INSERT INTO public.game_questions
  (game_type, tone, question_text, value_domain)
SELECT 'love_map', 'connecting', s.question_text, s.value_domain
FROM seed s
WHERE NOT EXISTS (
  SELECT 1 FROM public.game_questions g
  WHERE g.game_type = 'love_map' AND g.question_text = s.question_text
);
