-- Spec 5 (R5-5): "What feels loving to me right now" (love-language v2).
-- quiz_responses and psych_profiles have no client write policy, so the
-- answers are saved here: only the v2 shape, rebuilt from allowed keys, as
-- the next version; an existing share follows the newest answers (it is
-- "changeable at any time"). Grants in 20261018130310.
CREATE OR REPLACE FUNCTION public.save_loving_now(p_result jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ratings jsonb;
  v_moments jsonb;
  v_clean jsonb;
  v_version int;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'loving_now:not_signed_in'; END IF;
  IF jsonb_typeof(p_result) <> 'object'
     OR (p_result->>'instrument_version') IS DISTINCT FROM '2'
     OR jsonb_typeof(p_result->'ratings') IS DISTINCT FROM 'object'
     OR jsonb_typeof(coalesce(p_result->'moments', '[]')) <> 'array'
     OR EXISTS (SELECT 1 FROM jsonb_each(p_result->'ratings') r
                WHERE r.key NOT IN ('words', 'time', 'help', 'touch', 'gifts')
                   OR jsonb_typeof(r.value) <> 'string'
                   OR r.value #>> '{}' NOT IN ('not_really', 'a_little', 'a_lot'))
     OR NOT EXISTS (SELECT 1 FROM jsonb_each(p_result->'ratings'))
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(p_result->'moments', '[]')) m
                WHERE jsonb_typeof(m) <> 'string'
                   OR m #>> '{}' NOT IN ('stressed', 'sad', 'celebrating', 'everyday')) THEN
    RAISE EXCEPTION 'loving_now:invalid';
  END IF;

  v_ratings := p_result->'ratings';
  SELECT coalesce(jsonb_agg(DISTINCT m), '[]') INTO v_moments
  FROM jsonb_array_elements_text(coalesce(p_result->'moments', '[]')) m;
  v_clean := jsonb_build_object('instrument_version', 2, 'ratings', v_ratings,
                                'moments', v_moments, 'updated_at', now());

  PERFORM pg_advisory_xact_lock(hashtext('loving_now:' || v_uid::text));
  SELECT coalesce(max(version), 0) + 1 INTO v_version
  FROM public.quiz_responses WHERE user_id = v_uid AND quiz_type = 'love_language';
  INSERT INTO public.quiz_responses (user_id, quiz_type, responses, result_data, result_type, version)
  VALUES (v_uid, 'love_language', v_clean, v_clean, 'loving_now', v_version)
  RETURNING id INTO v_id;

  INSERT INTO public.psych_profiles (user_id, love_languages, completed_quizzes, last_updated)
  VALUES (v_uid, v_clean, ARRAY['love_language'], now())
  ON CONFLICT (user_id) DO UPDATE SET
    love_languages = EXCLUDED.love_languages,
    completed_quizzes = CASE WHEN 'love_language' = ANY (public.psych_profiles.completed_quizzes)
                             THEN public.psych_profiles.completed_quizzes
                             ELSE array_append(public.psych_profiles.completed_quizzes, 'love_language') END,
    last_updated = now();

  UPDATE public.quiz_shares SET quiz_response_id = v_id, shared_at = now()
  WHERE sharer_user_id = v_uid AND quiz_type = 'love_language';
END;
$$;
