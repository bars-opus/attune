-- Games launch hardening
-- Installs the shared question bank and RPCs used by This or That and
-- Truth or Dare. The 36 Questions migration creates the shared session
-- tables; this migration fills the rest of the Games v1 contract.

CREATE TABLE IF NOT EXISTS public.game_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_type text NOT NULL CHECK (game_type IN ('this_or_that', 'truth_or_dare')),
  tone text NOT NULL CHECK (tone IN ('connecting', 'romantic', 'playful', 'spicy', 'intimate')),
  tone_level int NOT NULL DEFAULT 1 CHECK (tone_level BETWEEN 1 AND 4),
  question_text text NOT NULL,
  question_subtype text CHECK (question_subtype IN ('truth', 'dare')),
  option_a text,
  option_b text,
  emoji_a text,
  emoji_b text,
  is_interesting boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    (game_type = 'this_or_that'
      AND question_subtype IS NULL
      AND option_a IS NOT NULL
      AND option_b IS NOT NULL)
    OR
    (game_type = 'truth_or_dare'
      AND question_subtype IS NOT NULL
      AND option_a IS NULL
      AND option_b IS NULL)
  )
);

CREATE TABLE IF NOT EXISTS public.game_questions_seen (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  question_id uuid NOT NULL REFERENCES public.game_questions(id) ON DELETE CASCADE,
  game_type text NOT NULL CHECK (game_type IN ('this_or_that', 'truth_or_dare')),
  seen_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(relationship_id, question_id)
);

CREATE TABLE IF NOT EXISTS public.custom_this_or_that_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  question_text text NOT NULL CHECK (char_length(question_text) <= 100),
  option_a text NOT NULL CHECK (char_length(option_a) <= 50),
  option_b text NOT NULL CHECK (char_length(option_b) <= 50),
  emoji_a text,
  emoji_b text,
  tone text NOT NULL CHECK (tone IN ('connecting', 'romantic', 'playful', 'spicy', 'intimate')),
  is_private boolean NOT NULL DEFAULT false,
  times_used int NOT NULL DEFAULT 0,
  last_used_at timestamptz,
  hidden_for_review boolean NOT NULL DEFAULT false,
  shared_to_community boolean NOT NULL DEFAULT false,
  community_usage_count int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.custom_truth_or_dare_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  question_type text NOT NULL CHECK (question_type IN ('truth', 'dare')),
  content text NOT NULL CHECK (char_length(content) <= 200),
  tone text NOT NULL CHECK (tone IN ('connecting', 'romantic', 'playful', 'spicy', 'intimate')),
  is_private boolean NOT NULL DEFAULT true,
  times_used int NOT NULL DEFAULT 0,
  last_used_at timestamptz,
  hidden_for_review boolean NOT NULL DEFAULT false,
  shared_to_community boolean NOT NULL DEFAULT false,
  community_usage_count int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE IF EXISTS public.game_session_rounds
  ADD COLUMN IF NOT EXISTS skip_replaced_type text CHECK (skip_replaced_type IN ('truth', 'dare')),
  ADD COLUMN IF NOT EXISTS safety_triggered boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_game_questions_lookup
  ON public.game_questions(game_type, tone, question_subtype, active);
CREATE UNIQUE INDEX IF NOT EXISTS idx_game_questions_seed_unique
  ON public.game_questions(
    game_type,
    tone,
    COALESCE(question_subtype, ''),
    question_text
  );
CREATE INDEX IF NOT EXISTS idx_game_questions_seen_relationship
  ON public.game_questions_seen(relationship_id, game_type);
CREATE UNIQUE INDEX IF NOT EXISTS idx_custom_tot_user_unique
  ON public.custom_this_or_that_questions(user_id, question_text, option_a, option_b);
CREATE UNIQUE INDEX IF NOT EXISTS idx_custom_tod_user_unique
  ON public.custom_truth_or_dare_questions(user_id, question_type, content);
CREATE INDEX IF NOT EXISTS idx_custom_tot_user_tone
  ON public.custom_this_or_that_questions(user_id, tone, is_private, hidden_for_review);
CREATE INDEX IF NOT EXISTS idx_custom_tod_user_tone
  ON public.custom_truth_or_dare_questions(user_id, tone, question_type, is_private, hidden_for_review);

ALTER TABLE public.game_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_questions_seen ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.custom_this_or_that_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.custom_truth_or_dare_questions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "game_questions_readable" ON public.game_questions;
CREATE POLICY "game_questions_readable"
ON public.game_questions FOR SELECT
USING (auth.uid() IS NOT NULL AND active = true);

DROP POLICY IF EXISTS "game_questions_seen_members" ON public.game_questions_seen;
CREATE POLICY "game_questions_seen_members"
ON public.game_questions_seen FOR ALL
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

DROP POLICY IF EXISTS "custom_tot_owner_write" ON public.custom_this_or_that_questions;
CREATE POLICY "custom_tot_owner_write"
ON public.custom_this_or_that_questions FOR ALL
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "custom_tot_partner_read" ON public.custom_this_or_that_questions;
CREATE POLICY "custom_tot_partner_read"
ON public.custom_this_or_that_questions FOR SELECT
USING (
  user_id = auth.uid()
  OR (
    is_private = false
    AND hidden_for_review = false
    AND user_id IN (
      SELECT CASE WHEN user_a = auth.uid() THEN user_b ELSE user_a END
      FROM public.relationships
      WHERE status = 'active'
        AND (user_a = auth.uid() OR user_b = auth.uid())
    )
  )
  OR (shared_to_community = true AND hidden_for_review = false)
);

DROP POLICY IF EXISTS "custom_tod_owner_write" ON public.custom_truth_or_dare_questions;
CREATE POLICY "custom_tod_owner_write"
ON public.custom_truth_or_dare_questions FOR ALL
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "custom_tod_partner_read" ON public.custom_truth_or_dare_questions;
CREATE POLICY "custom_tod_partner_read"
ON public.custom_truth_or_dare_questions FOR SELECT
USING (
  user_id = auth.uid()
  OR (
    is_private = false
    AND hidden_for_review = false
    AND user_id IN (
      SELECT CASE WHEN user_a = auth.uid() THEN user_b ELSE user_a END
      FROM public.relationships
      WHERE status = 'active'
        AND (user_a = auth.uid() OR user_b = auth.uid())
    )
  )
  OR (shared_to_community = true AND hidden_for_review = false)
);

DROP FUNCTION IF EXISTS public.mark_this_or_that_round_complete(uuid);
CREATE OR REPLACE FUNCTION public.mark_this_or_that_round_complete(p_round_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_id uuid;
BEGIN
  UPDATE public.game_session_rounds
  SET both_answered = true,
      reveal_triggered_at = COALESCE(reveal_triggered_at, now())
  WHERE id = p_round_id
    AND answer_a IN ('a', 'b')
    AND answer_b IN ('a', 'b')
    AND both_answered = false
    AND EXISTS (
      SELECT 1
      FROM public.game_sessions s
      JOIN public.relationships r ON r.id = s.relationship_id
      WHERE s.id = game_session_rounds.session_id
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  RETURNING session_id INTO v_session_id;

  RETURN v_session_id IS NOT NULL;
END;
$$;

DROP FUNCTION IF EXISTS public.mark_round_complete(uuid);
CREATE OR REPLACE FUNCTION public.mark_round_complete(p_round_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_id uuid;
BEGIN
  UPDATE public.game_session_rounds
  SET both_answered = true,
      reveal_triggered_at = COALESCE(reveal_triggered_at, now())
  WHERE id = p_round_id
    AND answer_a IS NOT NULL
    AND answer_b IS NOT NULL
    AND both_answered = false
    AND EXISTS (
      SELECT 1
      FROM public.game_sessions s
      JOIN public.relationships r ON r.id = s.relationship_id
      WHERE s.id = game_session_rounds.session_id
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  RETURNING session_id INTO v_session_id;

  RETURN v_session_id IS NOT NULL;
END;
$$;

DROP FUNCTION IF EXISTS public.increment_skip_count(uuid, uuid, text);
CREATE OR REPLACE FUNCTION public.increment_skip_count(
  p_session_id uuid,
  p_user_id uuid,
  p_field text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated int := 0;
BEGIN
  IF p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  IF p_field NOT IN ('skips_used_a', 'skips_used_b') THEN
    RAISE EXCEPTION 'invalid_skip_field' USING ERRCODE = '22023';
  END IF;

  IF p_field = 'skips_used_a' THEN
    UPDATE public.game_sessions s
    SET skips_used_a = skips_used_a + 1
    FROM public.relationships r
    WHERE s.id = p_session_id
      AND s.relationship_id = r.id
      AND r.user_a = p_user_id
      AND s.skips_used_a < 1
      AND s.status = 'active';
  ELSE
    UPDATE public.game_sessions s
    SET skips_used_b = skips_used_b + 1
    FROM public.relationships r
    WHERE s.id = p_session_id
      AND s.relationship_id = r.id
      AND r.user_b = p_user_id
      AND s.skips_used_b < 1
      AND s.status = 'active';
  END IF;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RAISE EXCEPTION 'skip_unavailable' USING ERRCODE = '22023';
  END IF;

  RETURN true;
END;
$$;

DROP FUNCTION IF EXISTS public.increment_custom_question_usage(uuid);
CREATE OR REPLACE FUNCTION public.increment_custom_question_usage(p_question_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Usage counter is written during legitimate play; require an authenticated
  -- caller so anon cannot inflate arbitrary questions' usage.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  UPDATE public.custom_this_or_that_questions
  SET times_used = times_used + 1,
      last_used_at = now()
  WHERE id = p_question_id;

  IF NOT FOUND THEN
    UPDATE public.custom_truth_or_dare_questions
    SET times_used = times_used + 1,
        last_used_at = now()
    WHERE id = p_question_id;
  END IF;
END;
$$;

-- Per-reporter report ledger so a report is one-per-(question, reporter) and a
-- single actor can never hide a question. hidden_for_review flips only once a
-- THRESHOLD of distinct reporters is reached (moderation, not instant censor).
CREATE TABLE IF NOT EXISTS public.custom_question_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  question_id uuid NOT NULL,
  question_table text NOT NULL CHECK (question_table IN ('this_or_that', 'truth_or_dare')),
  reporter_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason text CHECK (reason IS NULL OR char_length(reason) <= 300),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (question_id, reporter_user_id)
);
ALTER TABLE public.custom_question_reports ENABLE ROW LEVEL SECURITY;
-- Reporters may read/insert only their own report rows; nobody reads others'.
DROP POLICY IF EXISTS "custom_question_reports_owner" ON public.custom_question_reports;
CREATE POLICY "custom_question_reports_owner"
ON public.custom_question_reports FOR ALL
USING (reporter_user_id = auth.uid())
WITH CHECK (reporter_user_id = auth.uid());

-- Report a custom question. Records the caller's report (idempotent per reporter)
-- and hides the question only once >= 2 DISTINCT reporters have flagged it, so a
-- lone actor cannot suppress a partner's or community question. The question is
-- resolved across both custom tables by id.
DROP FUNCTION IF EXISTS public.report_custom_question(uuid);
DROP FUNCTION IF EXISTS public.report_custom_question(uuid, text);
CREATE OR REPLACE FUNCTION public.report_custom_question(
  p_question_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_table text;
  v_distinct_reporters int;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- Resolve which custom table the question lives in (existence check).
  IF EXISTS (SELECT 1 FROM public.custom_this_or_that_questions WHERE id = p_question_id) THEN
    v_table := 'this_or_that';
  ELSIF EXISTS (SELECT 1 FROM public.custom_truth_or_dare_questions WHERE id = p_question_id) THEN
    v_table := 'truth_or_dare';
  ELSE
    -- Opaque: do not reveal whether an id exists.
    RETURN;
  END IF;

  INSERT INTO public.custom_question_reports(question_id, question_table, reporter_user_id, reason)
  VALUES (p_question_id, v_table, v_user_id, NULLIF(btrim(COALESCE(p_reason, '')), ''))
  ON CONFLICT (question_id, reporter_user_id) DO NOTHING;

  SELECT count(*) INTO v_distinct_reporters
  FROM public.custom_question_reports
  WHERE question_id = p_question_id;

  IF v_distinct_reporters >= 2 THEN
    IF v_table = 'this_or_that' THEN
      UPDATE public.custom_this_or_that_questions SET hidden_for_review = true WHERE id = p_question_id;
    ELSE
      UPDATE public.custom_truth_or_dare_questions SET hidden_for_review = true WHERE id = p_question_id;
    END IF;
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.increment_community_usage(uuid, text);
CREATE OR REPLACE FUNCTION public.increment_community_usage(
  p_question_id uuid,
  p_table text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF p_table = 'this_or_that' THEN
    UPDATE public.custom_this_or_that_questions
    SET community_usage_count = community_usage_count + 1
    WHERE id = p_question_id;
  ELSIF p_table = 'truth_or_dare' THEN
    UPDATE public.custom_truth_or_dare_questions
    SET community_usage_count = community_usage_count + 1
    WHERE id = p_question_id;
  ELSE
    RAISE EXCEPTION 'invalid_community_table' USING ERRCODE = '22023';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege execute grants. Every Games RPC is SECURITY DEFINER; without
-- an explicit REVOKE they default to EXECUTE for PUBLIC (incl. anon). Lock each
-- to authenticated only. (GAMES-3.)
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.mark_this_or_that_round_complete(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_this_or_that_round_complete(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.mark_round_complete(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_round_complete(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.increment_skip_count(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_skip_count(uuid, uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.increment_custom_question_usage(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_custom_question_usage(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.report_custom_question(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_custom_question(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.increment_community_usage(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_community_usage(uuid, text) TO authenticated;

WITH seed(game_type, tone, tone_level, question_text, question_subtype, option_a, option_b, emoji_a, emoji_b, is_interesting) AS (
  VALUES
  ('this_or_that','connecting',1,'A quiet night in or a spontaneous walk?',NULL,'Quiet night','Spontaneous walk','home','walk',true),
  ('this_or_that','connecting',1,'Talk it out now or sleep on it?',NULL,'Talk now','Sleep on it','chat','moon',true),
  ('this_or_that','connecting',1,'Plan the weekend or leave it open?',NULL,'Plan it','Leave it open','list','open',false),
  ('this_or_that','connecting',1,'Morning check-in or evening debrief?',NULL,'Morning','Evening','sun','stars',false),
  ('this_or_that','connecting',1,'Cook together or order favorites?',NULL,'Cook','Order in','pan','bag',false),
  ('this_or_that','connecting',1,'Photo memories or written notes?',NULL,'Photos','Notes','photo','note',true),
  ('this_or_that','connecting',1,'Fix the problem or feel it first?',NULL,'Fix','Feel first','tool','heart',true),
  ('this_or_that','connecting',1,'Big hug or thoughtful message?',NULL,'Hug','Message','hug','text',false),
  ('this_or_that','connecting',1,'Shared playlist or shared calendar?',NULL,'Playlist','Calendar','music','date',false),
  ('this_or_that','connecting',1,'Ask directly or hint gently?',NULL,'Ask directly','Hint gently','ask','hint',true),
  ('this_or_that','playful',1,'Board game or karaoke?',NULL,'Board game','Karaoke','dice','mic',false),
  ('this_or_that','playful',1,'Silly challenge or cozy movie?',NULL,'Challenge','Movie','spark','film',false),
  ('this_or_that','playful',1,'Dance break or snack run?',NULL,'Dance','Snack run','dance','snack',false),
  ('this_or_that','playful',1,'Matching outfits or inside joke names?',NULL,'Outfits','Joke names','shirt','wink',true),
  ('this_or_that','playful',1,'Mini golf or arcade?',NULL,'Mini golf','Arcade','golf','game',false),
  ('this_or_that','playful',1,'Prank call voice or dramatic reading?',NULL,'Voice','Reading','phone','book',false),
  ('this_or_that','playful',1,'Win together or compete hard?',NULL,'Together','Compete','team','trophy',true),
  ('this_or_that','playful',1,'Dessert first or breakfast for dinner?',NULL,'Dessert','Breakfast','cake','egg',false),
  ('this_or_that','playful',1,'Road trip playlist or surprise route?',NULL,'Playlist','Route','music','map',false),
  ('this_or_that','playful',1,'Laugh until crying or smile all day?',NULL,'Laugh','Smile','laugh','smile',true),
  ('this_or_that','romantic',2,'Handwritten letter or surprise date?',NULL,'Letter','Date','letter','date',true),
  ('this_or_that','romantic',2,'Slow dance or long walk?',NULL,'Slow dance','Long walk','dance','walk',false),
  ('this_or_that','romantic',2,'Flowers or favorite snack?',NULL,'Flowers','Snack','flower','snack',false),
  ('this_or_that','romantic',2,'Candlelit dinner or sunrise breakfast?',NULL,'Dinner','Breakfast','candle','sun',false),
  ('this_or_that','romantic',2,'Sweet nickname or sincere compliment?',NULL,'Nickname','Compliment','name','star',true),
  ('this_or_that','romantic',2,'Anniversary trip or monthly rituals?',NULL,'Trip','Rituals','plane','repeat',true),
  ('this_or_that','romantic',2,'Public affection or private tenderness?',NULL,'Public','Private','people','home',true),
  ('this_or_that','romantic',2,'Shared bath or shared dessert?',NULL,'Bath','Dessert','bath','cake',false),
  ('this_or_that','romantic',2,'Love song or love note?',NULL,'Song','Note','music','note',false),
  ('this_or_that','romantic',2,'Recreate first date or invent a new one?',NULL,'Recreate','New date','rewind','spark',true),
  ('this_or_that','spicy',3,'Flirty text or whispered compliment?',NULL,'Text','Whisper','text','whisper',false),
  ('this_or_that','spicy',3,'Make the first move or be surprised?',NULL,'First move','Surprised','spark','gift',true),
  ('this_or_that','spicy',3,'Slow build or playful teasing?',NULL,'Slow build','Teasing','slow','wink',true),
  ('this_or_that','spicy',3,'Dress up or stay casual?',NULL,'Dress up','Casual','style','tee',false),
  ('this_or_that','spicy',3,'Secret signal or bold invitation?',NULL,'Signal','Invitation','signal','bold',true),
  ('this_or_that','spicy',3,'After-dark walk or stay-in music?',NULL,'Walk','Music','moon','music',false),
  ('this_or_that','spicy',3,'Eye contact or gentle touch?',NULL,'Eye contact','Touch','eye','hand',true),
  ('this_or_that','spicy',3,'Spontaneous kiss or planned date night?',NULL,'Kiss','Date night','kiss','date',false),
  ('this_or_that','spicy',3,'Mystery or directness?',NULL,'Mystery','Directness','mystery','ask',true),
  ('this_or_that','spicy',3,'Playful dare or honest truth?',NULL,'Dare','Truth','target','truth',false),
  ('this_or_that','intimate',4,'Be deeply understood or gently challenged?',NULL,'Understood','Challenged','heart','growth',true),
  ('this_or_that','intimate',4,'Share a fear or share a hope?',NULL,'Fear','Hope','cloud','sun',true),
  ('this_or_that','intimate',4,'More reassurance or more space?',NULL,'Reassurance','Space','anchor','room',true),
  ('this_or_that','intimate',4,'Repair quickly or repair carefully?',NULL,'Quickly','Carefully','fast','care',true),
  ('this_or_that','intimate',4,'Talk about needs or talk about dreams?',NULL,'Needs','Dreams','need','dream',true),
  ('this_or_that','intimate',4,'Name what hurts or name what helps?',NULL,'Hurts','Helps','ache','help',true),
  ('this_or_that','intimate',4,'Hold silence together or ask one brave question?',NULL,'Silence','Question','quiet','ask',true),
  ('this_or_that','intimate',4,'Protect peace or pursue clarity?',NULL,'Peace','Clarity','peace','clear',true),
  ('this_or_that','intimate',4,'Feel safer with plans or promises?',NULL,'Plans','Promises','plan','promise',true),
  ('this_or_that','intimate',4,'Be seen in strength or softness?',NULL,'Strength','Softness','strong','soft',true),
  ('truth_or_dare','connecting',1,'What is one small thing your partner did recently that mattered to you?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','connecting',1,'What makes you feel easy to love?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','connecting',1,'Name one ordinary moment together you would replay.','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','connecting',1,'What is a habit you appreciate in your partner?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','connecting',1,'What helps you feel listened to?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','connecting',1,'Send your partner a voice note saying one thing you appreciate.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','connecting',1,'Hold eye contact for ten seconds, then smile.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','connecting',1,'Pick a song that fits your relationship today and play a clip.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','connecting',1,'Share a photo that reminds you of a good day together.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','connecting',1,'Make your partner a tiny plan for tomorrow.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','playful',1,'What is the funniest thing your partner does without noticing?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','playful',1,'What should your couple team name be?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','playful',1,'Which of you would survive a game show better?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','playful',1,'What is your most ridiculous shared memory?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','playful',1,'What playful rule would improve your week?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','playful',1,'Do your best dramatic reading of the last message you sent.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','playful',1,'Invent a handshake and perform it together when you can.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','playful',1,'Send a selfie with your most exaggerated smile.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','playful',1,'Choose a snack mascot for your relationship.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','playful',1,'Hum a song and let your partner guess it.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','romantic',2,'When did you last feel especially chosen by your partner?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','romantic',2,'What kind of romance reaches you most easily?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','romantic',2,'What is one compliment from your partner that stays with you?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','romantic',2,'What would make your next date feel meaningful?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','romantic',2,'What is a small romantic ritual you would enjoy?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','romantic',2,'Send a message that starts with "I love when you..."','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','romantic',2,'Plan a ten-minute date you can do this week.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','romantic',2,'Give your partner a slow, specific compliment.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','romantic',2,'Choose a song for your next slow dance.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','romantic',2,'Describe your ideal goodnight in one sentence.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','spicy',3,'What kind of flirting makes you feel wanted?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','spicy',3,'What is a playful signal you would like your partner to notice?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','spicy',3,'What makes anticipation fun for you?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','spicy',3,'What is one boundary that helps spicy stay safe and fun?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','spicy',3,'What kind of invitation feels confident but respectful?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','spicy',3,'Send one flirty but kind sentence.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','spicy',3,'Pick a song with chemistry and share it.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','spicy',3,'Give your partner one specific "you looked good when..." compliment.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','spicy',3,'Create a secret signal for "I want your attention."','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','spicy',3,'Plan a playful surprise that respects both your comfort zones.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','intimate',4,'What helps you feel emotionally safe with your partner?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','intimate',4,'What is a need you are learning to name more clearly?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','intimate',4,'What does repair after conflict look like to you?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','intimate',4,'What is one tenderness you want protected between you?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','intimate',4,'What is a hope you carry for this relationship?','truth',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','intimate',4,'Tell your partner one thing that helps you trust them.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','intimate',4,'Ask one gentle question you genuinely want to understand.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','intimate',4,'Name one boundary and one invitation for deeper closeness.','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','intimate',4,'Share one sentence beginning "I feel safest with you when..."','dare',NULL,NULL,NULL,NULL,false),
  ('truth_or_dare','intimate',4,'Offer one concrete way you can show up better this week.','dare',NULL,NULL,NULL,NULL,false)
)
INSERT INTO public.game_questions (
  game_type, tone, tone_level, question_text, question_subtype,
  option_a, option_b, emoji_a, emoji_b, is_interesting
)
SELECT game_type, tone, tone_level, question_text, question_subtype,
       option_a, option_b, emoji_a, emoji_b, is_interesting
FROM seed
ON CONFLICT DO NOTHING;
