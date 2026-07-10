-- Conflict Style Quiz v1.1: aggregate-only storage and atomic completion.

CREATE TABLE IF NOT EXISTS public.psych_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  attachment_style jsonb,
  love_languages jsonb,
  communication_style jsonb,
  conflict_style jsonb,
  completed_quizzes text[] NOT NULL DEFAULT '{}',
  last_updated timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.quiz_responses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  quiz_type text NOT NULL CHECK (
    quiz_type IN ('attachment', 'love_language', 'communication', 'conflict')
  ),
  responses jsonb NOT NULL DEFAULT '{}'::jsonb,
  result_data jsonb,
  anxiety_score int,
  avoidance_score int,
  result_type text,
  completed_at timestamptz NOT NULL DEFAULT now(),
  version int NOT NULL DEFAULT 1
);

ALTER TABLE public.quiz_responses
  ADD COLUMN IF NOT EXISTS result_data jsonb;

CREATE TABLE IF NOT EXISTS public.quiz_shares (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sharer_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  quiz_type text NOT NULL,
  quiz_response_id uuid NOT NULL REFERENCES public.quiz_responses(id) ON DELETE CASCADE,
  shared_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (sharer_user_id, recipient_user_id, quiz_type),
  CHECK (sharer_user_id <> recipient_user_id)
);

CREATE TABLE IF NOT EXISTS public.psych_profile_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  quiz_type text NOT NULL,
  result_type text NOT NULL,
  anxiety_score int,
  avoidance_score int,
  result_data jsonb,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  version int NOT NULL
);

ALTER TABLE public.psych_profile_history
  ADD COLUMN IF NOT EXISTS result_data jsonb;

CREATE TABLE IF NOT EXISTS public.quiz_submission_keys (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  quiz_type text NOT NULL,
  idempotency_key text NOT NULL,
  quiz_response_id uuid REFERENCES public.quiz_responses(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, quiz_type, idempotency_key)
);

CREATE UNIQUE INDEX IF NOT EXISTS quiz_responses_user_type_version_key
  ON public.quiz_responses(user_id, quiz_type, version);
CREATE INDEX IF NOT EXISTS quiz_responses_latest_idx
  ON public.quiz_responses(user_id, quiz_type, version DESC);
CREATE INDEX IF NOT EXISTS quiz_shares_recipient_idx
  ON public.quiz_shares(recipient_user_id, quiz_type);
CREATE INDEX IF NOT EXISTS psych_profile_history_user_type_idx
  ON public.psych_profile_history(user_id, quiz_type, version DESC);

ALTER TABLE public.psych_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.psych_profile_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_submission_keys ENABLE ROW LEVEL SECURITY;

-- Remove permissive policies from the attachment-era draft schema. Policies
-- are OR-combined, so leaving them in place would bypass the rules below.
DROP POLICY IF EXISTS "quiz_responses_private" ON public.quiz_responses;
DROP POLICY IF EXISTS "quiz_shares_both_parties" ON public.quiz_shares;
DROP POLICY IF EXISTS "quiz_shares_sharer_insert" ON public.quiz_shares;
DROP POLICY IF EXISTS "psych_history_private" ON public.psych_profile_history;

DROP POLICY IF EXISTS "psych profiles owner read" ON public.psych_profiles;
CREATE POLICY "psych profiles owner read"
ON public.psych_profiles FOR SELECT
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "quiz responses owner read" ON public.quiz_responses;
CREATE POLICY "quiz responses owner read"
ON public.quiz_responses FOR SELECT
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "quiz responses shared aggregate read" ON public.quiz_responses;
CREATE POLICY "quiz responses shared aggregate read"
ON public.quiz_responses FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM public.quiz_shares qs
    JOIN public.relationships r
      ON (r.user_a = qs.sharer_user_id AND r.user_b = qs.recipient_user_id)
      OR (r.user_b = qs.sharer_user_id AND r.user_a = qs.recipient_user_id)
    WHERE qs.quiz_response_id = quiz_responses.id
      AND qs.recipient_user_id = auth.uid()
      AND r.status = 'active'
  )
);

DROP POLICY IF EXISTS "quiz shares active members read" ON public.quiz_shares;
CREATE POLICY "quiz shares active members read"
ON public.quiz_shares FOR SELECT
USING (
  (sharer_user_id = auth.uid() OR recipient_user_id = auth.uid())
  AND EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE r.status = 'active'
      AND (
        (r.user_a = quiz_shares.sharer_user_id AND r.user_b = quiz_shares.recipient_user_id)
        OR (r.user_b = quiz_shares.sharer_user_id AND r.user_a = quiz_shares.recipient_user_id)
      )
  )
);

DROP POLICY IF EXISTS "quiz shares owner insert" ON public.quiz_shares;
CREATE POLICY "quiz shares owner insert"
ON public.quiz_shares FOR INSERT
WITH CHECK (
  sharer_user_id = auth.uid()
  AND EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE r.status = 'active'
      AND (
        (r.user_a = auth.uid() AND r.user_b = recipient_user_id)
        OR (r.user_b = auth.uid() AND r.user_a = recipient_user_id)
      )
  )
);

DROP POLICY IF EXISTS "quiz shares owner update" ON public.quiz_shares;
CREATE POLICY "quiz shares owner update"
ON public.quiz_shares FOR UPDATE
USING (
  sharer_user_id = auth.uid()
  AND EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE r.status = 'active'
      AND (
        (r.user_a = auth.uid() AND r.user_b = recipient_user_id)
        OR (r.user_b = auth.uid() AND r.user_a = recipient_user_id)
      )
  )
)
WITH CHECK (
  sharer_user_id = auth.uid()
  AND EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE r.status = 'active'
      AND (
        (r.user_a = auth.uid() AND r.user_b = recipient_user_id)
        OR (r.user_b = auth.uid() AND r.user_a = recipient_user_id)
      )
  )
);

DROP POLICY IF EXISTS "quiz shares owner delete" ON public.quiz_shares;
CREATE POLICY "quiz shares owner delete"
ON public.quiz_shares FOR DELETE
USING (sharer_user_id = auth.uid());

DROP POLICY IF EXISTS "psych history owner read" ON public.psych_profile_history;
CREATE POLICY "psych history owner read"
ON public.psych_profile_history FOR SELECT
USING (user_id = auth.uid());

-- Idempotency records are internal to trusted completion functions.
REVOKE ALL ON public.quiz_submission_keys FROM authenticated;

CREATE OR REPLACE FUNCTION public.save_conflict_quiz_result(
  p_responses jsonb,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_existing_response public.quiz_responses%ROWTYPE;
  v_previous jsonb;
  v_version int;
  v_completed_at timestamptz := now();
  v_collaborating int;
  v_competing int;
  v_avoiding int;
  v_accommodating int;
  v_compromising int;
  v_primary text;
  v_secondary text;
  v_primary_score int;
  v_secondary_score int;
  v_result jsonb;
  v_response_id uuid;
  v_key text;
  v_value text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 16
     OR length(p_idempotency_key) > 200 THEN
    RAISE EXCEPTION 'invalid_idempotency_key' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_responses) <> 'object' THEN
    RAISE EXCEPTION 'invalid_responses' USING ERRCODE = '22023';
  END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(p_responses)) <> 18 THEN
    RAISE EXCEPTION 'invalid_responses' USING ERRCODE = '22023';
  END IF;

  FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(p_responses)
  LOOP
    IF v_key !~ '^Q([1-9]|1[0-8])$'
       OR v_value !~ '^[1-7]$' THEN
      RAISE EXCEPTION 'invalid_responses' USING ERRCODE = '22023';
    END IF;
  END LOOP;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_id::text || ':conflict', 0));

  SELECT qr.* INTO v_existing_response
  FROM public.quiz_submission_keys sk
  JOIN public.quiz_responses qr ON qr.id = sk.quiz_response_id
  WHERE sk.user_id = v_user_id
    AND sk.quiz_type = 'conflict'
    AND sk.idempotency_key = p_idempotency_key;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'result_data', v_existing_response.result_data
    );
  END IF;

  v_collaborating := round((((
    (p_responses->>'Q1')::numeric + (p_responses->>'Q6')::numeric
    + (p_responses->>'Q11')::numeric + (p_responses->>'Q16')::numeric
  ) / 4 - 1) / 6) * 100);
  v_competing := round((((
    (p_responses->>'Q2')::numeric + (p_responses->>'Q7')::numeric
    + (p_responses->>'Q12')::numeric + (p_responses->>'Q17')::numeric
  ) / 4 - 1) / 6) * 100);
  v_avoiding := round((((
    (p_responses->>'Q3')::numeric + (p_responses->>'Q8')::numeric
    + (p_responses->>'Q13')::numeric + (p_responses->>'Q18')::numeric
  ) / 4 - 1) / 6) * 100);
  v_accommodating := round((((
    (p_responses->>'Q4')::numeric + (p_responses->>'Q9')::numeric
    + (p_responses->>'Q14')::numeric
  ) / 3 - 1) / 6) * 100);
  v_compromising := round((((
    (p_responses->>'Q5')::numeric + (p_responses->>'Q10')::numeric
    + (p_responses->>'Q15')::numeric
  ) / 3 - 1) / 6) * 100);

  SELECT style, score INTO v_primary, v_primary_score
  FROM (VALUES
    ('collaborating', v_collaborating, 1),
    ('competing', v_competing, 2),
    ('avoiding', v_avoiding, 3),
    ('accommodating', v_accommodating, 4),
    ('compromising', v_compromising, 5)
  ) AS scores(style, score, canonical_order)
  ORDER BY score DESC, canonical_order
  LIMIT 1;

  SELECT style, score INTO v_secondary, v_secondary_score
  FROM (VALUES
    ('collaborating', v_collaborating, 1),
    ('competing', v_competing, 2),
    ('avoiding', v_avoiding, 3),
    ('accommodating', v_accommodating, 4),
    ('compromising', v_compromising, 5)
  ) AS scores(style, score, canonical_order)
  ORDER BY score DESC, canonical_order
  OFFSET 1 LIMIT 1;

  SELECT conflict_style INTO v_previous
  FROM public.psych_profiles
  WHERE user_id = v_user_id;

  SELECT COALESCE(max(version), 0) + 1 INTO v_version
  FROM public.quiz_responses
  WHERE user_id = v_user_id AND quiz_type = 'conflict';

  v_result := jsonb_build_object(
    'collaborating', v_collaborating,
    'competing', v_competing,
    'avoiding', v_avoiding,
    'accommodating', v_accommodating,
    'compromising', v_compromising,
    'primary', v_primary,
    'secondary', v_secondary,
    'separation', v_primary_score - v_secondary_score,
    'instrument_version', 1,
    'result_version', v_version,
    'completed_at', to_jsonb(v_completed_at)
  );

  IF v_previous IS NOT NULL AND v_previous <> '{}'::jsonb THEN
    INSERT INTO public.psych_profile_history (
      user_id, quiz_type, result_type, result_data, recorded_at, version
    ) VALUES (
      v_user_id,
      'conflict',
      COALESCE(v_previous->>'primary', 'unknown'),
      v_previous,
      COALESCE((v_previous->>'completed_at')::timestamptz, v_completed_at),
      COALESCE((v_previous->>'result_version')::int, v_version - 1)
    );
  END IF;

  INSERT INTO public.quiz_responses (
    user_id, quiz_type, responses, result_data, result_type, completed_at, version
  ) VALUES (
    v_user_id, 'conflict', '{}'::jsonb, v_result, v_primary,
    v_completed_at, v_version
  ) RETURNING id INTO v_response_id;

  INSERT INTO public.psych_profiles (
    user_id, conflict_style, completed_quizzes, last_updated
  ) VALUES (
    v_user_id, v_result, ARRAY['conflict'], v_completed_at
  )
  ON CONFLICT (user_id) DO UPDATE SET
    conflict_style = EXCLUDED.conflict_style,
    completed_quizzes = CASE
      WHEN 'conflict' = ANY(public.psych_profiles.completed_quizzes)
        THEN public.psych_profiles.completed_quizzes
      ELSE array_append(public.psych_profiles.completed_quizzes, 'conflict')
    END,
    last_updated = EXCLUDED.last_updated;

  INSERT INTO public.quiz_submission_keys (
    user_id, quiz_type, idempotency_key, quiz_response_id
  ) VALUES (v_user_id, 'conflict', p_idempotency_key, v_response_id);

  UPDATE public.quiz_shares
  SET quiz_response_id = v_response_id
  WHERE sharer_user_id = v_user_id AND quiz_type = 'conflict';

  RETURN jsonb_build_object('success', true, 'result_data', v_result);
END;
$$;

REVOKE ALL ON FUNCTION public.save_conflict_quiz_result(jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_conflict_quiz_result(jsonb, text) TO authenticated;
