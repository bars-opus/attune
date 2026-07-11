-- 36 Questions Journey v2.4
-- Adds the journey schema, canonical localized question bank, answer source of
-- truth, completion helpers, skip replacement, and minimal shared game tables
-- for environments where the games schema has not been migrated yet.

CREATE TABLE IF NOT EXISTS public.game_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  initiator_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  game_type text NOT NULL,
  tone text NOT NULL DEFAULT 'connecting',
  status text NOT NULL DEFAULT 'invited' CHECK (status IN ('invited', 'active', 'completed', 'abandoned')),
  total_rounds int NOT NULL DEFAULT 0,
  current_round int NOT NULL DEFAULT 0,
  skips_used_a int NOT NULL DEFAULT 0,
  skips_used_b int NOT NULL DEFAULT 0,
  intimate_consent_a boolean NOT NULL DEFAULT false,
  intimate_consent_b boolean NOT NULL DEFAULT false,
  match_count int NOT NULL DEFAULT 0,
  total_rounds_completed int NOT NULL DEFAULT 0,
  started_at timestamptz,
  completed_at timestamptz,
  abandoned_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  hidden_by_user_ids uuid[] NOT NULL DEFAULT ARRAY[]::uuid[]
);

CREATE TABLE IF NOT EXISTS public.game_session_rounds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  round_number int NOT NULL,
  question_id uuid,
  level int,
  active_partner_id uuid REFERENCES auth.users(id),
  answer_a text,
  answer_b text,
  answer_a_submitted_at timestamptz,
  answer_b_submitted_at timestamptz,
  chosen_type text,
  both_answered boolean NOT NULL DEFAULT false,
  revealed_at timestamptz,
  reveal_triggered_at timestamptz,
  is_custom boolean NOT NULL DEFAULT false,
  custom_question_data jsonb,
  is_skip boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(session_id, round_number)
);

CREATE TABLE IF NOT EXISTS public.session_idempotency_keys (
  key text PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.thirty_six_questions_canonical (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter int NOT NULL CHECK (chapter IN (1, 2, 3)),
  intensity_order int NOT NULL,
  requires_review boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_36q_canonical_chapter_order
  ON public.thirty_six_questions_canonical(chapter, intensity_order);

CREATE TABLE IF NOT EXISTS public.thirty_six_questions_translations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  canonical_id uuid NOT NULL REFERENCES public.thirty_six_questions_canonical(id) ON DELETE CASCADE,
  locale text NOT NULL,
  question_text text NOT NULL,
  is_reviewed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(canonical_id, locale)
);

CREATE TABLE IF NOT EXISTS public.thirty_six_question_journeys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'abandoned')),
  chapter_1_completed_at timestamptz,
  chapter_2_completed_at timestamptz,
  chapter_3_completed_at timestamptz,
  final_observation text,
  final_observation_confidence text CHECK (final_observation_confidence IN ('high', 'medium', 'low')),
  final_source_answer_ids uuid[],
  final_observation_hidden boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_journey_per_relationship
  ON public.thirty_six_question_journeys(relationship_id)
  WHERE status = 'in_progress';

ALTER TABLE IF EXISTS public.game_sessions
  ADD COLUMN IF NOT EXISTS journey_id uuid REFERENCES public.thirty_six_question_journeys(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS chapter int CHECK (chapter IN (1, 2, 3)),
  ADD COLUMN IF NOT EXISTS abandon_reason text CHECK (abandon_reason IN ('inactivity', 'invite_expired', 'user_initiated')),
  ADD COLUMN IF NOT EXISTS skips_used int NOT NULL DEFAULT 0;

ALTER TABLE IF EXISTS public.game_session_rounds
  ADD COLUMN IF NOT EXISTS canonical_question_id uuid REFERENCES public.thirty_six_questions_canonical(id),
  ADD COLUMN IF NOT EXISTS question_text_snapshot text;

CREATE TABLE IF NOT EXISTS public.chapter_reflections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journey_id uuid NOT NULL REFERENCES public.thirty_six_question_journeys(id) ON DELETE CASCADE,
  chapter int NOT NULL CHECK (chapter IN (1, 2, 3)),
  observation text,
  confidence text CHECK (confidence IN ('high', 'medium', 'low')),
  source_answer_ids uuid[],
  is_hidden boolean NOT NULL DEFAULT false,
  generated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(journey_id, chapter)
);

CREATE TABLE IF NOT EXISTS public.thirty_six_questions_seen (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  canonical_question_id uuid NOT NULL REFERENCES public.thirty_six_questions_canonical(id) ON DELETE CASCADE,
  seen_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(relationship_id, canonical_question_id)
);

CREATE TABLE IF NOT EXISTS public.thirty_six_question_answers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  round_id uuid NOT NULL REFERENCES public.game_session_rounds(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  answer_text text NOT NULL CHECK (char_length(answer_text) <= 400),
  is_removed boolean NOT NULL DEFAULT false,
  is_safety_triggered boolean NOT NULL DEFAULT false,
  is_excluded_from_ai boolean NOT NULL DEFAULT false,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  removed_at timestamptz,
  UNIQUE(round_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_36q_canonical_chapter
  ON public.thirty_six_questions_canonical(chapter, active);
CREATE INDEX IF NOT EXISTS idx_36q_translations_canonical
  ON public.thirty_six_questions_translations(canonical_id, locale);
CREATE INDEX IF NOT EXISTS idx_36q_journeys_relationship
  ON public.thirty_six_question_journeys(relationship_id, status);
CREATE INDEX IF NOT EXISTS idx_36q_sessions_journey
  ON public.game_sessions(journey_id, chapter);
CREATE INDEX IF NOT EXISTS idx_36q_rounds_session
  ON public.game_session_rounds(session_id, round_number);
CREATE INDEX IF NOT EXISTS idx_36q_seen_relationship
  ON public.thirty_six_questions_seen(relationship_id, canonical_question_id);
CREATE INDEX IF NOT EXISTS idx_36q_answers_round
  ON public.thirty_six_question_answers(round_id, user_id);

ALTER TABLE public.game_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_session_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_idempotency_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.thirty_six_questions_canonical ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.thirty_six_questions_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.thirty_six_question_journeys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chapter_reflections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.thirty_six_questions_seen ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.thirty_six_question_answers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "game_sessions_relationship_members" ON public.game_sessions;
CREATE POLICY "game_sessions_relationship_members"
ON public.game_sessions FOR ALL
USING (
  relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
)
WITH CHECK (
  relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

DROP POLICY IF EXISTS "game_rounds_relationship_members" ON public.game_session_rounds;
CREATE POLICY "game_rounds_relationship_members"
ON public.game_session_rounds FOR ALL
USING (
  session_id IN (
    SELECT id FROM public.game_sessions
    WHERE relationship_id IN (
      SELECT id FROM public.relationships
      WHERE user_a = auth.uid() OR user_b = auth.uid()
    )
  )
)
WITH CHECK (
  session_id IN (
    SELECT id FROM public.game_sessions
    WHERE relationship_id IN (
      SELECT id FROM public.relationships
      WHERE user_a = auth.uid() OR user_b = auth.uid()
    )
  )
);

DROP POLICY IF EXISTS "session_idempotency_members" ON public.session_idempotency_keys;
CREATE POLICY "session_idempotency_members"
ON public.session_idempotency_keys FOR ALL
USING (
  session_id IN (
    SELECT id FROM public.game_sessions
    WHERE relationship_id IN (
      SELECT id FROM public.relationships
      WHERE user_a = auth.uid() OR user_b = auth.uid()
    )
  )
)
WITH CHECK (
  session_id IN (
    SELECT id FROM public.game_sessions
    WHERE relationship_id IN (
      SELECT id FROM public.relationships
      WHERE user_a = auth.uid() OR user_b = auth.uid()
    )
  )
);

DROP POLICY IF EXISTS "canonical_questions_readable" ON public.thirty_six_questions_canonical;
CREATE POLICY "canonical_questions_readable"
ON public.thirty_six_questions_canonical FOR SELECT
USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "translations_readable" ON public.thirty_six_questions_translations;
CREATE POLICY "translations_readable"
ON public.thirty_six_questions_translations FOR SELECT
USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "journeys_relationship_members" ON public.thirty_six_question_journeys;
CREATE POLICY "journeys_relationship_members"
ON public.thirty_six_question_journeys FOR SELECT
USING (
  relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

DROP POLICY IF EXISTS "journeys_insert" ON public.thirty_six_question_journeys;
CREATE POLICY "journeys_insert"
ON public.thirty_six_question_journeys FOR INSERT
WITH CHECK (
  relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

DROP POLICY IF EXISTS "journeys_update_members" ON public.thirty_six_question_journeys;
CREATE POLICY "journeys_update_members"
ON public.thirty_six_question_journeys FOR UPDATE
USING (
  relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
)
WITH CHECK (
  relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

DROP POLICY IF EXISTS "reflections_relationship_members" ON public.chapter_reflections;
CREATE POLICY "reflections_relationship_members"
ON public.chapter_reflections FOR SELECT
USING (
  journey_id IN (
    SELECT id FROM public.thirty_six_question_journeys
    WHERE relationship_id IN (
      SELECT id FROM public.relationships
      WHERE user_a = auth.uid() OR user_b = auth.uid()
    )
  )
);

DROP POLICY IF EXISTS "reflections_update_relationship_members" ON public.chapter_reflections;
CREATE POLICY "reflections_update_relationship_members"
ON public.chapter_reflections FOR UPDATE
USING (
  journey_id IN (
    SELECT id FROM public.thirty_six_question_journeys
    WHERE relationship_id IN (
      SELECT id FROM public.relationships
      WHERE user_a = auth.uid() OR user_b = auth.uid()
    )
  )
)
WITH CHECK (
  journey_id IN (
    SELECT id FROM public.thirty_six_question_journeys
    WHERE relationship_id IN (
      SELECT id FROM public.relationships
      WHERE user_a = auth.uid() OR user_b = auth.uid()
    )
  )
);

DROP POLICY IF EXISTS "seen_questions_relationship_members" ON public.thirty_six_questions_seen;
CREATE POLICY "seen_questions_relationship_members"
ON public.thirty_six_questions_seen FOR SELECT
USING (
  relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

DROP POLICY IF EXISTS "answers_private_write" ON public.thirty_six_question_answers;
CREATE POLICY "answers_private_write"
ON public.thirty_six_question_answers FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "answers_partner_read" ON public.thirty_six_question_answers;
CREATE POLICY "answers_partner_read"
ON public.thirty_six_question_answers FOR SELECT
USING (
  auth.uid() = user_id
  OR round_id IN (
    SELECT r.id
    FROM public.game_session_rounds r
    JOIN public.game_sessions s ON s.id = r.session_id
    JOIN public.relationships rel ON rel.id = s.relationship_id
    WHERE (rel.user_a = auth.uid() OR rel.user_b = auth.uid())
      AND r.both_answered = true
  )
);

-- DROP before CREATE OR REPLACE: a prior partial apply may have left an older
-- version whose return type differs, and Postgres cannot change a function's
-- return type via CREATE OR REPLACE (SQLSTATE 42P13).
DROP FUNCTION IF EXISTS public.get_thirty_six_seen_map(uuid);
CREATE OR REPLACE FUNCTION public.get_thirty_six_seen_map(p_relationship_id uuid)
RETURNS TABLE(canonical_question_id uuid, seen_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT s.canonical_question_id, s.seen_at
  FROM public.thirty_six_questions_seen s
  WHERE s.relationship_id = p_relationship_id;
END;
$$;

DROP FUNCTION IF EXISTS public.mark_thirty_six_questions_seen(uuid, uuid[]);
CREATE OR REPLACE FUNCTION public.mark_thirty_six_questions_seen(
  p_relationship_id uuid,
  p_canonical_question_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.thirty_six_questions_seen (relationship_id, canonical_question_id)
  SELECT p_relationship_id, unnest(p_canonical_question_ids)
  ON CONFLICT (relationship_id, canonical_question_id)
  DO UPDATE SET seen_at = EXCLUDED.seen_at;
END;
$$;

DROP FUNCTION IF EXISTS public.mark_thirty_six_round_complete(uuid);
CREATE OR REPLACE FUNCTION public.mark_thirty_six_round_complete(p_round_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_id uuid;
  v_relationship_id uuid;
  v_user_a uuid;
  v_user_b uuid;
  v_user_a_answered boolean;
  v_user_b_answered boolean;
BEGIN
  SELECT r.session_id, s.relationship_id
  INTO v_session_id, v_relationship_id
  FROM public.game_session_rounds r
  JOIN public.game_sessions s ON s.id = r.session_id
  WHERE r.id = p_round_id;

  IF v_session_id IS NULL THEN
    RAISE EXCEPTION 'Round not found';
  END IF;

  SELECT rel.user_a, rel.user_b
  INTO v_user_a, v_user_b
  FROM public.relationships rel
  WHERE rel.id = v_relationship_id;

  SELECT EXISTS (
    SELECT 1 FROM public.thirty_six_question_answers
    WHERE round_id = p_round_id
      AND user_id = v_user_a
      AND is_removed = false
  ) INTO v_user_a_answered;

  SELECT EXISTS (
    SELECT 1 FROM public.thirty_six_question_answers
    WHERE round_id = p_round_id
      AND user_id = v_user_b
      AND is_removed = false
  ) INTO v_user_b_answered;

  IF v_user_a_answered AND v_user_b_answered THEN
    UPDATE public.game_session_rounds
    SET both_answered = true,
        reveal_triggered_at = COALESCE(reveal_triggered_at, now())
    WHERE id = p_round_id;
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

DROP FUNCTION IF EXISTS public.replace_thirty_six_question(uuid, uuid, text);
CREATE OR REPLACE FUNCTION public.replace_thirty_six_question(
  p_session_id uuid,
  p_round_id uuid,
  p_locale text DEFAULT 'en'
)
RETURNS TABLE(canonical_question_id uuid, question_text text, skips_used int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_relationship_id uuid;
  v_chapter int;
  v_skips_used int;
  v_current_question_id uuid;
  v_new_question_id uuid;
  v_question_text text;
BEGIN
  SELECT relationship_id, chapter, COALESCE(game_sessions.skips_used, 0)
  INTO v_relationship_id, v_chapter, v_skips_used
  FROM public.game_sessions
  WHERE id = p_session_id
    AND game_type = '36_questions'
    AND status = 'active'
  FOR UPDATE;

  IF v_relationship_id IS NULL THEN
    RAISE EXCEPTION 'Active 36 Questions chapter not found';
  END IF;

  IF v_skips_used >= 2 THEN
    RAISE EXCEPTION 'No skips remaining';
  END IF;

  SELECT r.canonical_question_id
  INTO v_current_question_id
  FROM public.game_session_rounds r
  WHERE r.id = p_round_id
    AND r.session_id = p_session_id;

  IF v_current_question_id IS NULL THEN
    RAISE EXCEPTION 'Round not found for chapter';
  END IF;

  SELECT c.id, COALESCE(t.question_text, en.question_text)
  INTO v_new_question_id, v_question_text
  FROM public.thirty_six_questions_canonical c
  LEFT JOIN public.thirty_six_questions_translations t
    ON t.canonical_id = c.id AND t.locale = p_locale
  LEFT JOIN public.thirty_six_questions_translations en
    ON en.canonical_id = c.id AND en.locale = 'en'
  WHERE c.chapter = v_chapter
    AND c.active = true
    AND c.id <> v_current_question_id
    AND COALESCE(t.question_text, en.question_text) IS NOT NULL
    AND (v_chapter <> 3 OR COALESCE(t.is_reviewed, en.is_reviewed, false) = true)
    AND NOT EXISTS (
      SELECT 1 FROM public.game_session_rounds used
      WHERE used.session_id = p_session_id
        AND used.canonical_question_id = c.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.thirty_six_questions_seen seen
      WHERE seen.relationship_id = v_relationship_id
        AND seen.canonical_question_id = c.id
    )
  ORDER BY c.intensity_order ASC
  LIMIT 1;

  IF v_new_question_id IS NULL THEN
    SELECT c.id, COALESCE(t.question_text, en.question_text)
    INTO v_new_question_id, v_question_text
    FROM public.thirty_six_questions_canonical c
    LEFT JOIN public.thirty_six_questions_translations t
      ON t.canonical_id = c.id AND t.locale = p_locale
    LEFT JOIN public.thirty_six_questions_translations en
      ON en.canonical_id = c.id AND en.locale = 'en'
    WHERE c.chapter = v_chapter
      AND c.active = true
      AND c.id <> v_current_question_id
      AND COALESCE(t.question_text, en.question_text) IS NOT NULL
      AND (v_chapter <> 3 OR COALESCE(t.is_reviewed, en.is_reviewed, false) = true)
      AND NOT EXISTS (
        SELECT 1 FROM public.game_session_rounds used
        WHERE used.session_id = p_session_id
          AND used.canonical_question_id = c.id
      )
    ORDER BY c.intensity_order ASC
    LIMIT 1;
  END IF;

  IF v_new_question_id IS NULL THEN
    RAISE EXCEPTION 'No replacement question available';
  END IF;

  DELETE FROM public.thirty_six_question_answers
  WHERE round_id = p_round_id;

  UPDATE public.game_session_rounds
  SET canonical_question_id = v_new_question_id,
      question_text_snapshot = v_question_text,
      both_answered = false,
      reveal_triggered_at = NULL,
      revealed_at = NULL
  WHERE id = p_round_id
    AND session_id = p_session_id;

  UPDATE public.game_sessions
  SET skips_used = v_skips_used + 1
  WHERE id = p_session_id;

  RETURN QUERY SELECT v_new_question_id, v_question_text, v_skips_used + 1;
END;
$$;

DROP FUNCTION IF EXISTS public.complete_thirty_six_chapter(uuid);
CREATE OR REPLACE FUNCTION public.complete_thirty_six_chapter(p_session_id uuid)
RETURNS TABLE(journey_id uuid, chapter int, journey_completed boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_journey_id uuid;
  v_relationship_id uuid;
  v_chapter int;
  v_total_rounds int;
  v_completed_rounds int;
  v_all_completed boolean;
BEGIN
  SELECT s.journey_id, s.relationship_id, s.chapter, s.total_rounds
  INTO v_journey_id, v_relationship_id, v_chapter, v_total_rounds
  FROM public.game_sessions s
  WHERE s.id = p_session_id
    AND s.game_type = '36_questions'
  FOR UPDATE;

  IF v_journey_id IS NULL OR v_chapter IS NULL THEN
    RAISE EXCEPTION '36 Questions chapter not found';
  END IF;

  SELECT COUNT(*)
  INTO v_completed_rounds
  FROM public.game_session_rounds
  WHERE session_id = p_session_id
    AND both_answered = true;

  IF v_completed_rounds < COALESCE(v_total_rounds, 12) THEN
    RAISE EXCEPTION 'Chapter is not complete';
  END IF;

  UPDATE public.game_sessions
  SET status = 'completed',
      current_round = total_rounds,
      completed_at = COALESCE(completed_at, now())
  WHERE id = p_session_id;

  UPDATE public.thirty_six_question_journeys
  SET chapter_1_completed_at = CASE WHEN v_chapter = 1 THEN COALESCE(chapter_1_completed_at, now()) ELSE chapter_1_completed_at END,
      chapter_2_completed_at = CASE WHEN v_chapter = 2 THEN COALESCE(chapter_2_completed_at, now()) ELSE chapter_2_completed_at END,
      chapter_3_completed_at = CASE WHEN v_chapter = 3 THEN COALESCE(chapter_3_completed_at, now()) ELSE chapter_3_completed_at END,
      updated_at = now()
  WHERE id = v_journey_id;

  INSERT INTO public.thirty_six_questions_seen (relationship_id, canonical_question_id)
  SELECT v_relationship_id, canonical_question_id
  FROM public.game_session_rounds
  WHERE session_id = p_session_id
    AND canonical_question_id IS NOT NULL
  ON CONFLICT (relationship_id, canonical_question_id)
  DO UPDATE SET seen_at = EXCLUDED.seen_at;

  SELECT chapter_1_completed_at IS NOT NULL
     AND chapter_2_completed_at IS NOT NULL
     AND chapter_3_completed_at IS NOT NULL
  INTO v_all_completed
  FROM public.thirty_six_question_journeys
  WHERE id = v_journey_id;

  IF v_all_completed THEN
    UPDATE public.thirty_six_question_journeys
    SET status = 'completed',
        updated_at = now()
    WHERE id = v_journey_id;
  END IF;

  RETURN QUERY SELECT v_journey_id, v_chapter, v_all_completed;
END;
$$;

WITH seed(chapter, intensity_order, requires_review, question_text) AS (
  VALUES
  (1, 1, false, 'If you could have dinner with anyone in the world, who would it be?'),
  (1, 2, false, 'What would a perfect day look like for you?'),
  (1, 3, false, 'What is something small that always makes you smile?'),
  (1, 4, false, 'Before making a phone call, do you ever rehearse what to say?'),
  (1, 5, false, 'What does a perfect morning look like to you?'),
  (1, 6, false, 'If you could learn any skill instantly, what would it be?'),
  (1, 7, false, 'What is something most people do not know about you?'),
  (1, 8, false, 'What was the best part of your week so far?'),
  (1, 9, false, 'What is something you are looking forward to?'),
  (1, 10, false, 'If you could live anywhere for a year, where would it be?'),
  (1, 11, false, 'What is your favorite way to spend a weekend?'),
  (1, 12, false, 'What is a book, song, or movie that changed your perspective?'),
  (1, 13, false, 'What is something you are curious about right now?'),
  (1, 14, false, 'What is a memory that makes you feel warm?'),
  (1, 15, false, 'What is the best gift you have ever received?'),
  (1, 16, false, 'What is a favorite childhood memory?'),
  (1, 17, false, 'What is something you have never done but would like to try?'),
  (1, 18, false, 'What is your favorite time of day, and why?'),
  (1, 19, false, 'What is a small thing that makes an ordinary day better?'),
  (1, 20, false, 'What is something you would tell your younger self?'),
  (1, 21, false, 'What place makes you feel most at ease?'),
  (1, 22, false, 'What is a simple pleasure you think is underrated?'),
  (1, 23, false, 'What kind of compliment stays with you the longest?'),
  (1, 24, false, 'What is a tradition you enjoy or would like to start?'),
  (1, 25, false, 'What is something you have been enjoying lately?'),
  (1, 26, false, 'What is a meal that feels comforting to you?'),
  (1, 27, false, 'What is one thing that helps you relax after a hard day?'),
  (1, 28, false, 'What is a skill you admire in other people?'),
  (1, 29, false, 'What is something you like about the way you spend time together?'),
  (1, 30, false, 'What is a small adventure you would enjoy this month?'),
  (1, 31, false, 'What is something that makes you laugh almost every time?'),
  (1, 32, false, 'What is a sound, smell, or view that brings you comfort?'),
  (1, 33, false, 'What is something you are glad exists in the world?'),
  (1, 34, false, 'What is a hobby you would like to revisit?'),
  (1, 35, false, 'What is a question you love being asked?'),
  (1, 36, false, 'What is one ordinary moment you wish you could replay?'),
  (1, 37, false, 'What is something you appreciate about your current season of life?'),
  (1, 38, false, 'What is a tiny habit that improves your day?'),
  (1, 39, false, 'What is something you would like to learn about your partner?'),
  (1, 40, false, 'What is one thing you hope this conversation gives you?'),
  (2, 1, false, 'If you could change one thing about how you were raised, what would it be?'),
  (2, 2, false, 'What does home mean to you?'),
  (2, 3, false, 'What is something you are still figuring out about yourself?'),
  (2, 4, false, 'What is a belief you hold that many people around you do not share?'),
  (2, 5, false, 'What is the most important quality in a close friendship?'),
  (2, 6, false, 'What is something you have changed your mind about in the last year?'),
  (2, 7, false, 'When do you feel most alive?'),
  (2, 8, false, 'What is something you want more of in your life right now?'),
  (2, 9, false, 'What is a fear you have learned to handle differently?'),
  (2, 10, false, 'What is something you wish you had known ten years ago?'),
  (2, 11, false, 'What does being truly seen by someone feel like?'),
  (2, 12, false, 'What is a regret that still teaches you something?'),
  (2, 13, false, 'What is something you are proud of that not many people know about?'),
  (2, 14, false, 'What is an important lesson you have learned about relationships?'),
  (2, 15, false, 'What does a good apology look like to you?'),
  (2, 16, false, 'What is something you have been avoiding that you want to face gently?'),
  (2, 17, false, 'What is your definition of success right now?'),
  (2, 18, false, 'What is something you are deeply grateful for?'),
  (2, 19, false, 'What is a question you wish more people would ask you?'),
  (2, 20, false, 'What does love feel like to you?'),
  (2, 21, false, 'What helps you feel emotionally safe in a conversation?'),
  (2, 22, false, 'What is a family pattern you understand better now than you used to?'),
  (2, 23, false, 'What does support look like when you are overwhelmed?'),
  (2, 24, false, 'What is something you are learning to ask for more clearly?'),
  (2, 25, false, 'What is a value you want your life to reflect more often?'),
  (2, 26, false, 'When do you find it hardest to say what you need?'),
  (2, 27, false, 'What kind of encouragement actually reaches you?'),
  (2, 28, false, 'What is something you have forgiven more easily with time?'),
  (2, 29, false, 'What is a moment when you felt unexpectedly understood?'),
  (2, 30, false, 'What does repair after conflict mean to you?'),
  (2, 31, false, 'What is one expectation you are trying to loosen?'),
  (2, 32, false, 'What do you hope people can feel when they are around you?'),
  (2, 33, false, 'What is a part of adulthood that surprised you?'),
  (2, 34, false, 'What is one way you have grown in the last few years?'),
  (2, 35, false, 'What helps you trust someone over time?'),
  (2, 36, false, 'What is something you want to be braver about?'),
  (2, 37, false, 'What is a promise you try to keep to yourself?'),
  (2, 38, false, 'What is a way your partner makes daily life easier?'),
  (2, 39, false, 'What is one thing you want to understand better about your partner?'),
  (2, 40, false, 'What would make this chapter feel meaningful to you?'),
  (3, 1, true, 'If you could know the answer to one question about your future, what would it be?'),
  (3, 2, true, 'What is a fear you are willing to name today?'),
  (3, 3, true, 'What is your most treasured memory?'),
  (3, 4, true, 'If you knew you had one year to live, what would you change?'),
  (3, 5, true, 'What is something tender about you that few people get to see?'),
  (3, 6, true, 'What does being truly known by someone feel like to you?'),
  (3, 7, true, 'What do you most regret not doing?'),
  (3, 8, true, 'If you could give your younger self one piece of advice, what would it be?'),
  (3, 9, true, 'What is something about your life you hope never changes?'),
  (3, 10, true, 'What is something about your relationship that helps you feel safe?'),
  (3, 11, true, 'When do you feel closest to your partner?'),
  (3, 12, true, 'What does the future look like when you imagine it with your partner?'),
  (3, 13, true, 'What is a dream you have not said out loud very often?'),
  (3, 14, true, 'What is something you are still healing around, at your own pace?'),
  (3, 15, true, 'What is something you wish people understood about your grief or sadness?'),
  (3, 16, true, 'What is something you are learning to forgive yourself for?'),
  (3, 17, true, 'What does being fully loved feel like to you?'),
  (3, 18, true, 'What is a fear you have about the future?'),
  (3, 19, true, 'What is something you have had to let go of?'),
  (3, 20, true, 'What does trust mean to you?'),
  (3, 21, true, 'What is a part of your heart you protect carefully?'),
  (3, 22, true, 'What helps you feel brave enough to be honest?'),
  (3, 23, true, 'What is a hope you carry quietly?'),
  (3, 24, true, 'What is something you want your partner to know about your inner world?'),
  (3, 25, true, 'What is a moment when love asked you to grow?'),
  (3, 26, true, 'What is something that has softened in you over time?'),
  (3, 27, true, 'What does commitment mean to you in everyday choices?'),
  (3, 28, true, 'What is one place where you still need gentleness?'),
  (3, 29, true, 'What does emotional intimacy ask of you?'),
  (3, 30, true, 'What is something you are afraid to need?'),
  (3, 31, true, 'What is a way you want to be remembered by the people closest to you?'),
  (3, 32, true, 'What is something you want to build with your partner over time?'),
  (3, 33, true, 'What kind of reassurance matters most to you?'),
  (3, 34, true, 'What is one truth about you that deserves more compassion?'),
  (3, 35, true, 'What is a difficult season that changed what you value?'),
  (3, 36, true, 'What does it mean to choose each other on ordinary days?'),
  (3, 37, true, 'What is one fear that feels smaller when it is shared safely?'),
  (3, 38, true, 'What is something you want to protect in your relationship?'),
  (3, 39, true, 'What is a way your partner has helped you feel known?'),
  (3, 40, true, 'What would make this final chapter feel honest and kind?')
)
INSERT INTO public.thirty_six_questions_canonical (chapter, intensity_order, requires_review, active)
SELECT chapter, intensity_order, requires_review, true
FROM seed
ON CONFLICT (chapter, intensity_order)
DO UPDATE SET requires_review = EXCLUDED.requires_review, active = true;

WITH seed(chapter, intensity_order, requires_review, question_text) AS (
  VALUES
  (1, 1, false, 'If you could have dinner with anyone in the world, who would it be?'),
  (1, 2, false, 'What would a perfect day look like for you?'),
  (1, 3, false, 'What is something small that always makes you smile?'),
  (1, 4, false, 'Before making a phone call, do you ever rehearse what to say?'),
  (1, 5, false, 'What does a perfect morning look like to you?'),
  (1, 6, false, 'If you could learn any skill instantly, what would it be?'),
  (1, 7, false, 'What is something most people do not know about you?'),
  (1, 8, false, 'What was the best part of your week so far?'),
  (1, 9, false, 'What is something you are looking forward to?'),
  (1, 10, false, 'If you could live anywhere for a year, where would it be?'),
  (1, 11, false, 'What is your favorite way to spend a weekend?'),
  (1, 12, false, 'What is a book, song, or movie that changed your perspective?'),
  (1, 13, false, 'What is something you are curious about right now?'),
  (1, 14, false, 'What is a memory that makes you feel warm?'),
  (1, 15, false, 'What is the best gift you have ever received?'),
  (1, 16, false, 'What is a favorite childhood memory?'),
  (1, 17, false, 'What is something you have never done but would like to try?'),
  (1, 18, false, 'What is your favorite time of day, and why?'),
  (1, 19, false, 'What is a small thing that makes an ordinary day better?'),
  (1, 20, false, 'What is something you would tell your younger self?'),
  (1, 21, false, 'What place makes you feel most at ease?'),
  (1, 22, false, 'What is a simple pleasure you think is underrated?'),
  (1, 23, false, 'What kind of compliment stays with you the longest?'),
  (1, 24, false, 'What is a tradition you enjoy or would like to start?'),
  (1, 25, false, 'What is something you have been enjoying lately?'),
  (1, 26, false, 'What is a meal that feels comforting to you?'),
  (1, 27, false, 'What is one thing that helps you relax after a hard day?'),
  (1, 28, false, 'What is a skill you admire in other people?'),
  (1, 29, false, 'What is something you like about the way you spend time together?'),
  (1, 30, false, 'What is a small adventure you would enjoy this month?'),
  (1, 31, false, 'What is something that makes you laugh almost every time?'),
  (1, 32, false, 'What is a sound, smell, or view that brings you comfort?'),
  (1, 33, false, 'What is something you are glad exists in the world?'),
  (1, 34, false, 'What is a hobby you would like to revisit?'),
  (1, 35, false, 'What is a question you love being asked?'),
  (1, 36, false, 'What is one ordinary moment you wish you could replay?'),
  (1, 37, false, 'What is something you appreciate about your current season of life?'),
  (1, 38, false, 'What is a tiny habit that improves your day?'),
  (1, 39, false, 'What is something you would like to learn about your partner?'),
  (1, 40, false, 'What is one thing you hope this conversation gives you?'),
  (2, 1, false, 'If you could change one thing about how you were raised, what would it be?'),
  (2, 2, false, 'What does home mean to you?'),
  (2, 3, false, 'What is something you are still figuring out about yourself?'),
  (2, 4, false, 'What is a belief you hold that many people around you do not share?'),
  (2, 5, false, 'What is the most important quality in a close friendship?'),
  (2, 6, false, 'What is something you have changed your mind about in the last year?'),
  (2, 7, false, 'When do you feel most alive?'),
  (2, 8, false, 'What is something you want more of in your life right now?'),
  (2, 9, false, 'What is a fear you have learned to handle differently?'),
  (2, 10, false, 'What is something you wish you had known ten years ago?'),
  (2, 11, false, 'What does being truly seen by someone feel like?'),
  (2, 12, false, 'What is a regret that still teaches you something?'),
  (2, 13, false, 'What is something you are proud of that not many people know about?'),
  (2, 14, false, 'What is an important lesson you have learned about relationships?'),
  (2, 15, false, 'What does a good apology look like to you?'),
  (2, 16, false, 'What is something you have been avoiding that you want to face gently?'),
  (2, 17, false, 'What is your definition of success right now?'),
  (2, 18, false, 'What is something you are deeply grateful for?'),
  (2, 19, false, 'What is a question you wish more people would ask you?'),
  (2, 20, false, 'What does love feel like to you?'),
  (2, 21, false, 'What helps you feel emotionally safe in a conversation?'),
  (2, 22, false, 'What is a family pattern you understand better now than you used to?'),
  (2, 23, false, 'What does support look like when you are overwhelmed?'),
  (2, 24, false, 'What is something you are learning to ask for more clearly?'),
  (2, 25, false, 'What is a value you want your life to reflect more often?'),
  (2, 26, false, 'When do you find it hardest to say what you need?'),
  (2, 27, false, 'What kind of encouragement actually reaches you?'),
  (2, 28, false, 'What is something you have forgiven more easily with time?'),
  (2, 29, false, 'What is a moment when you felt unexpectedly understood?'),
  (2, 30, false, 'What does repair after conflict mean to you?'),
  (2, 31, false, 'What is one expectation you are trying to loosen?'),
  (2, 32, false, 'What do you hope people can feel when they are around you?'),
  (2, 33, false, 'What is a part of adulthood that surprised you?'),
  (2, 34, false, 'What is one way you have grown in the last few years?'),
  (2, 35, false, 'What helps you trust someone over time?'),
  (2, 36, false, 'What is something you want to be braver about?'),
  (2, 37, false, 'What is a promise you try to keep to yourself?'),
  (2, 38, false, 'What is a way your partner makes daily life easier?'),
  (2, 39, false, 'What is one thing you want to understand better about your partner?'),
  (2, 40, false, 'What would make this chapter feel meaningful to you?'),
  (3, 1, true, 'If you could know the answer to one question about your future, what would it be?'),
  (3, 2, true, 'What is a fear you are willing to name today?'),
  (3, 3, true, 'What is your most treasured memory?'),
  (3, 4, true, 'If you knew you had one year to live, what would you change?'),
  (3, 5, true, 'What is something tender about you that few people get to see?'),
  (3, 6, true, 'What does being truly known by someone feel like to you?'),
  (3, 7, true, 'What do you most regret not doing?'),
  (3, 8, true, 'If you could give your younger self one piece of advice, what would it be?'),
  (3, 9, true, 'What is something about your life you hope never changes?'),
  (3, 10, true, 'What is something about your relationship that helps you feel safe?'),
  (3, 11, true, 'When do you feel closest to your partner?'),
  (3, 12, true, 'What does the future look like when you imagine it with your partner?'),
  (3, 13, true, 'What is a dream you have not said out loud very often?'),
  (3, 14, true, 'What is something you are still healing around, at your own pace?'),
  (3, 15, true, 'What is something you wish people understood about your grief or sadness?'),
  (3, 16, true, 'What is something you are learning to forgive yourself for?'),
  (3, 17, true, 'What does being fully loved feel like to you?'),
  (3, 18, true, 'What is a fear you have about the future?'),
  (3, 19, true, 'What is something you have had to let go of?'),
  (3, 20, true, 'What does trust mean to you?'),
  (3, 21, true, 'What is a part of your heart you protect carefully?'),
  (3, 22, true, 'What helps you feel brave enough to be honest?'),
  (3, 23, true, 'What is a hope you carry quietly?'),
  (3, 24, true, 'What is something you want your partner to know about your inner world?'),
  (3, 25, true, 'What is a moment when love asked you to grow?'),
  (3, 26, true, 'What is something that has softened in you over time?'),
  (3, 27, true, 'What does commitment mean to you in everyday choices?'),
  (3, 28, true, 'What is one place where you still need gentleness?'),
  (3, 29, true, 'What does emotional intimacy ask of you?'),
  (3, 30, true, 'What is something you are afraid to need?'),
  (3, 31, true, 'What is a way you want to be remembered by the people closest to you?'),
  (3, 32, true, 'What is something you want to build with your partner over time?'),
  (3, 33, true, 'What kind of reassurance matters most to you?'),
  (3, 34, true, 'What is one truth about you that deserves more compassion?'),
  (3, 35, true, 'What is a difficult season that changed what you value?'),
  (3, 36, true, 'What does it mean to choose each other on ordinary days?'),
  (3, 37, true, 'What is one fear that feels smaller when it is shared safely?'),
  (3, 38, true, 'What is something you want to protect in your relationship?'),
  (3, 39, true, 'What is a way your partner has helped you feel known?'),
  (3, 40, true, 'What would make this final chapter feel honest and kind?')
)
INSERT INTO public.thirty_six_questions_translations (canonical_id, locale, question_text, is_reviewed)
SELECT c.id, 'en', seed.question_text, true
FROM seed
JOIN public.thirty_six_questions_canonical c
  ON c.chapter = seed.chapter AND c.intensity_order = seed.intensity_order
ON CONFLICT (canonical_id, locale)
DO UPDATE SET question_text = EXCLUDED.question_text, is_reviewed = true;
