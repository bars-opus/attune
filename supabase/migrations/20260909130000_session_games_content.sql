-- Content for the three session games (§8.4).
--
-- tone is 'connecting' throughout: game_questions.tone is NOT NULL with
-- CHECK (tone IN ('connecting','romantic','playful','spicy','intimate')),
-- and these three games are diagnostic rather than playful.

-- Mirror: 24 prompts about the partner's CURRENT state (§8.4 measures
-- attentiveness now, not memory of biographical facts).
WITH seed(question_text) AS (
  VALUES
  ('What is weighing on them most this week?'),
  ('What would they say is going well right now?'),
  ('What are they most looking forward to?'),
  ('What small thing has been irritating them lately?'),
  ('How rested do they feel at the moment?'),
  ('What would help them most this week?'),
  ('What are they worrying about that they have not said out loud?'),
  ('What did they enjoy most in the last few days?'),
  ('How are they feeling about work right now?'),
  ('What would their ideal evening look like this week?'),
  ('What have they been putting off?'),
  ('Who have they been thinking about lately?'),
  ('What is one thing they need more of right now?'),
  ('What would they change about this week if they could?'),
  ('How connected have they been feeling to you lately?'),
  ('What made them laugh most recently?'),
  ('What are they proud of right now?'),
  ('What is draining their energy at the moment?'),
  ('What would they want a whole free day for?'),
  ('What have they been quietly hoping you would notice?'),
  ('What is on their mind just before sleep lately?'),
  ('What kind of support do they want right now — practical or emotional?'),
  ('What has felt harder than usual for them recently?'),
  ('What are they curious about at the moment?')
)
INSERT INTO public.game_questions (game_type, tone, question_text)
SELECT 'mirror', 'connecting', s.question_text
FROM seed s
WHERE NOT EXISTS (
  SELECT 1 FROM public.game_questions g
  WHERE g.game_type = 'mirror' AND g.question_text = s.question_text
);

-- Sliding Scale: one statement per §8.4 domain (money, children,
-- independence, location, ambition, religion).
WITH seed(value_domain, question_text, scale_low, scale_high) AS (
  VALUES
  ('money', 'How much of our money should be shared?',
   'Kept separate', 'Fully shared'),
  ('children', 'How central are children to the life you want?',
   'Not part of it', 'Central to it'),
  ('independence', 'How much time apart feels right to you?',
   'Almost none', 'A great deal'),
  ('location', 'How settled do you want to be geographically?',
   'Open to moving', 'Rooted for good'),
  ('ambition', 'How much should career shape our decisions?',
   'It comes second', 'It leads'),
  ('religion', 'How present should faith or spirituality be in our life?',
   'Not present', 'Central')
)
INSERT INTO public.game_questions
  (game_type, tone, question_text, value_domain, scale_low, scale_high)
SELECT 'sliding_scale', 'connecting',
       s.question_text, s.value_domain, s.scale_low, s.scale_high
FROM seed s
WHERE NOT EXISTS (
  SELECT 1 FROM public.game_questions g
  WHERE g.game_type = 'sliding_scale' AND g.value_domain = s.value_domain
);

-- Scenario: 10 situations, 3 options each. §8.4: "Neither option is
-- 'correct' — the insight is in the pattern across scenarios", so the
-- options are written as equally defensible.
WITH seed(question_text, options) AS (
  VALUES
  ('You are both tired and a disagreement starts. What do you do?',
   '[{"key":"a","text":"Push through and resolve it now"},
     {"key":"b","text":"Pause and return to it tomorrow"},
     {"key":"c","text":"Step away alone for a while first"}]'::jsonb),
  ('Your partner is upset but says they are fine. What do you do?',
   '[{"key":"a","text":"Take them at their word"},
     {"key":"b","text":"Ask once more, gently"},
     {"key":"c","text":"Stay close without asking"}]'::jsonb),
  ('A friend criticises your partner in front of you. What do you do?',
   '[{"key":"a","text":"Defend them on the spot"},
     {"key":"b","text":"Change the subject"},
     {"key":"c","text":"Raise it with the friend privately later"}]'::jsonb),
  ('You get a job offer in another city. What comes first?',
   '[{"key":"a","text":"Talk it through before deciding anything"},
     {"key":"b","text":"Work out what you want, then discuss"},
     {"key":"c","text":"Decline unless you both already wanted to move"}]'::jsonb),
  ('Your partner forgets something that mattered to you. What do you do?',
   '[{"key":"a","text":"Say so directly, soon"},
     {"key":"b","text":"Let it go this time"},
     {"key":"c","text":"Wait to see if they remember on their own"}]'::jsonb),
  ('You disagree about money on something significant. What do you do?',
   '[{"key":"a","text":"Defer to whoever feels more strongly"},
     {"key":"b","text":"Find a compromise you both half-like"},
     {"key":"c","text":"Postpone until you both have more information"}]'::jsonb),
  ('Your partner wants a weekend alone. How do you take it?',
   '[{"key":"a","text":"Straightforwardly — everyone needs space"},
     {"key":"b","text":"Fine, but you would want to know why"},
     {"key":"c","text":"It would sit uneasily with you"}]'::jsonb),
  ('You are running late to something that matters to them. What do you do?',
   '[{"key":"a","text":"Tell them immediately"},
     {"key":"b","text":"Try to make up the time first"},
     {"key":"c","text":"Tell them once you know how late you will be"}]'::jsonb),
  ('A conflict from last month resurfaces. What do you do?',
   '[{"key":"a","text":"Treat it as unfinished and reopen it"},
     {"key":"b","text":"Address only what is happening now"},
     {"key":"c","text":"Ask why it is coming back before engaging"}]'::jsonb),
  ('Your partner is stressed and short with you. What do you do?',
   '[{"key":"a","text":"Give them room until it passes"},
     {"key":"b","text":"Name it kindly in the moment"},
     {"key":"c","text":"Take on something practical to lighten the load"}]'::jsonb)
)
INSERT INTO public.game_questions (game_type, tone, question_text, options)
SELECT 'scenario', 'connecting', s.question_text, s.options
FROM seed s
WHERE NOT EXISTS (
  SELECT 1 FROM public.game_questions g
  WHERE g.game_type = 'scenario' AND g.question_text = s.question_text
);
