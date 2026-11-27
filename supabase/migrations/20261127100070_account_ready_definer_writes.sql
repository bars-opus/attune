-- Entry gates (2026-11-27) fix round, review I-1: the SECURITY DEFINER
-- RPCs that write the gated user-content tables run as the table owner, so
-- 20261127100060's restrictive policies never reach them. Each function
-- below is its LIVE body (pg_get_functiondef on attune_spec3a after
-- 20261127100060; the drift guard refuses to run on any other body) with
-- only these changes:
--   1. SET search_path becomes '' (every name in these bodies was already
--      schema-qualified; checked against every public/private relation,
--      function and type name, and every unqualified call is pg_catalog's).
--   2. Right after the body's first BEGIN, the gate assert_can_post uses:
--        IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid())
--          THEN RAISE 'account_not_ready' (42501)
--      The service role (no auth.uid()) is never gated.
-- Gated (20):
--   * public.save_conflict_quiz_result(jsonb,text) (last migration naming it: 20260703120000; search_path was public, pg_temp)
--   * public.save_loving_now(jsonb) (last migration naming it: 20261018130300; search_path was "")
--   * public.follow_opinion_author(text) (last migration naming it: 20260716140000; search_path was public, private)
--   * public.repost_opinion(uuid) (last migration naming it: 20260728120000; search_path was public, private)
--   * public.edit_opinion(uuid,text) (last migration naming it: 20261104100000; search_path was public, private)
--   * public.edit_opinion_comment(uuid,text) (last migration naming it: 20261104100000; search_path was public, private)
--   * public.cast_poll_vote(uuid) (last migration naming it: 20260726120000; search_path was public, private)
--   * public.attach_opinion_tags(uuid,text[]) (last migration naming it: 20260731120000; search_path was public, private)
--   * public.upsert_family_member(uuid,text,date) (last migration naming it: 20261015100000; search_path was public)
--   * public.post_place_update(uuid,text,text,numeric,numeric,text,text) (last migration naming it: 20260932120000; search_path was public)
--   * public.add_event_memory(uuid,text) (last migration naming it: 20261014150000; search_path was public)
--   * public.share_a_win(uuid,text,text,date) (last migration naming it: 20261018140300; search_path was "")
--   * public.increment_opinion_like_count(uuid) (last migration naming it: 20260826120000; search_path was public)
--   * public.decrement_opinion_like_count(uuid) (last migration naming it: 20260826120000; search_path was public)
--   * public.increment_opinion_dislike_count(uuid) (last migration naming it: 20260826120000; search_path was public)
--   * public.decrement_opinion_dislike_count(uuid) (last migration naming it: 20260826120000; search_path was public)
--   * public.increment_opinion_comment_count(uuid) (last migration naming it: 20260716120000; search_path was public)
--   * public.decrement_opinion_comment_count(uuid) (last migration naming it: 20260716120000; search_path was public)
--   * public.increment_comment_like_count(uuid) (last migration naming it: 20260716120000; search_path was public)
--   * public.decrement_comment_like_count(uuid) (last migration naming it: 20260716120000; search_path was public)
-- Reports stay open, a safety tool (2): the report row is still
-- written (moderators see it, and 'Someone may be at risk' still reaches a
-- person), but a report from an account that is not ready returns before
-- the report_count increment and the 10-report auto-hide:
--   * public.report_opinion(uuid,text) (last migration naming it: 20261104110000; search_path was public, private)
--   * public.report_opinion_comment(uuid,text) (last migration naming it: 20261104110000; search_path was public, private)
-- Not re-created, by design (enumerated with reasons in
-- supabase/tests/entry_gates_contracts.sql section G, which fails on any
-- new SECURITY DEFINER writer of these tables that is neither gated nor
-- listed): create_opinion / create_opinion_with_poll /
-- create_opinion_with_quote / create_opinion_comment (already gated by
-- assert_can_post, 20261127100060); removals and undos of one's own rows
-- (remove_my_opinion, remove_my_comment, unrepost_opinion,
-- unfollow_opinion_author, retract_poll_vote, soft_delete_timeline_event);
-- private preferences and safety tools (follow_tag, unfollow_tag,
-- save/hide/mute and their undos).
-- ACLs are kept by CREATE OR REPLACE (section G asserts authenticated
-- still executes each one). No grants twin: no grant changes.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- Drift guard: each function must hold exactly the live body this was
-- built from (md5 of prosrc), or already the new one (a re-run).
DO $guard$
DECLARE
  r record;
  v_md5 text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.save_conflict_quiz_result(jsonb,text)', 'afdda2b6586fc1351a3e1e9f18026a81', 'f14369089d6ed6e8bb86a429f926ed90'),
      ('public.save_loving_now(jsonb)', 'e7118921994b905c5d2a1e381877b304', 'acfbfc488fd4af5119019a7bd03cd125'),
      ('public.follow_opinion_author(text)', '52640d7b7f3cf52cfd059f49f5f80883', '180b9a8b20df35d59cba250ff7b3bb94'),
      ('public.repost_opinion(uuid)', 'f7f9efe33ad40c4761d84e074f8e4d98', '78e5b861a4c7cb7227ee4f8c375ba905'),
      ('public.edit_opinion(uuid,text)', 'f2695b853e4475a637dc638f392ee65e', '03a9bb79aedadd316f1cd0cb8e3ca008'),
      ('public.edit_opinion_comment(uuid,text)', 'a0e8123c26b5c5422b2e7ba7f19af740', 'cdd823bb0c472fdba221eab5aaf70c2f'),
      ('public.cast_poll_vote(uuid)', 'b83e2cfa353f2c8b0a2e668df48ba475', 'aaf8a300f510d6210ec167b3b3158b32'),
      ('public.attach_opinion_tags(uuid,text[])', 'ce69938bfb1eb7432f39240e97aa150d', 'e8fec5a6e4c7715fae46d2a3522c5a06'),
      ('public.upsert_family_member(uuid,text,date)', '819edc6efafcc76bbeca65b5f80c24d6', '2686077ed3839349ffdbce07a9bf98d6'),
      ('public.post_place_update(uuid,text,text,numeric,numeric,text,text)', '5bbe406c8942f4a7d04881eb3e0c169a', 'ae67be3f09cc4c9435737d8b93d4190e'),
      ('public.add_event_memory(uuid,text)', '35b5aede8e95d8c89f7ddbeeb7ab9181', '3210d6921d595f58d72e3d51168bb835'),
      ('public.share_a_win(uuid,text,text,date)', '76ef0587ac97f06722c386abdd9d956c', 'd92e3ee79cc825d5bb2ba9d48e4e32e7'),
      ('public.increment_opinion_like_count(uuid)', 'f48ae0812cfbbbbec4a6ae65fcd14ba1', 'b55e490d55f01cfd5ebe47e49ed47f95'),
      ('public.decrement_opinion_like_count(uuid)', 'a47f99fdec99df7ee15e37f18b0c950e', 'a9847abfcc36b21786aee3457092c6d0'),
      ('public.increment_opinion_dislike_count(uuid)', 'e2032f48eeb7af97aa5f9a687cb1cce6', 'f8274d4e5a6eb8d7ebf52e3ed69f3ae6'),
      ('public.decrement_opinion_dislike_count(uuid)', 'a5da6b965491ec094174d4839eb7d3ba', 'fbeb96c31652b19af1185f38d0e1f978'),
      ('public.increment_opinion_comment_count(uuid)', '4274f554a9530bca242fd4196b20b8ea', '77ae12a3b6b5a5389a5424c91cbce83c'),
      ('public.decrement_opinion_comment_count(uuid)', '7435e64547b300e2fe1e4f3aa510edc5', '20bc60ea78a3029e14b4e745f97e928a'),
      ('public.increment_comment_like_count(uuid)', '58a1fd5e6c11ef21fe1826e302bae553', '01cc16ca64d7837b510612160cdca3b5'),
      ('public.decrement_comment_like_count(uuid)', 'cf0a361c165ec13fef62d4a0d1063222', 'e03810a42d1c29717db8b584290edf1c'),
      ('public.report_opinion(uuid,text)', '0e9bc7f6755cd1207f6085fefca0046b', '54af383b176d874c76c6cc3d18f9658d'),
      ('public.report_opinion_comment(uuid,text)', '2d80dcfd980bee00965c505ed03c5cac', 'bc3e26e6c5166a50d0be053b75f489eb')
    ) AS t(sig, before_md5, after_md5)
  LOOP
    SELECT pg_catalog.md5(p.prosrc) INTO v_md5
      FROM pg_catalog.pg_proc AS p WHERE p.oid = pg_catalog.to_regprocedure(r.sig);
    IF v_md5 IS NULL THEN
      RAISE EXCEPTION 'entry gates fix round: % is missing', r.sig;
    END IF;
    IF v_md5 NOT IN (r.before_md5, r.after_md5) THEN
      RAISE EXCEPTION 'entry gates fix round: % is not the body this migration was built from (md5 %)', r.sig, v_md5;
    END IF;
  END LOOP;
END $guard$;

CREATE OR REPLACE FUNCTION public.save_conflict_quiz_result(p_responses jsonb, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
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
$function$;

CREATE OR REPLACE FUNCTION public.save_loving_now(p_result jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_ratings jsonb;
  v_moments jsonb;
  v_clean jsonb;
  v_version int;
  v_id uuid;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
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
$function$;

CREATE OR REPLACE FUNCTION public.follow_opinion_author(p_author_handle text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_target uuid;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- Resolve the handle. There is no reverse index; scan is acceptable at launch
  -- scale and keeps the mapping server-only. (Optimizable later with a stored
  -- handle column if the user base grows.)
  SELECT id INTO v_target
  FROM auth.users
  WHERE public.opinion_author_handle(id) = p_author_handle
  LIMIT 1;

  IF v_target IS NULL THEN
    RAISE EXCEPTION 'author_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_target = auth.uid() THEN
    RAISE EXCEPTION 'cannot_follow_self' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.opinion_follows (follower_id, following_id)
  VALUES (auth.uid(), v_target)
  ON CONFLICT (follower_id, following_id) DO NOTHING;
END;
$function$;

CREATE OR REPLACE FUNCTION public.repost_opinion(p_opinion_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_author_id uuid;
  v_inserted boolean := false;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- Refuse to repost something the caller cannot read: removed or
  -- pending-review opinions are invisible in every feed, so a repost row
  -- pointing at one would be a permanently orphaned entry in the timeline.
  -- This also gives us the author's id for the self-repost check and the
  -- notification below, in one query.
  SELECT user_id INTO v_author_id
  FROM public.opinions
  WHERE id = p_opinion_id
    AND removed_at IS NULL
    AND hidden_pending_review = false;

  IF v_author_id IS NULL THEN
    RAISE EXCEPTION 'opinion_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_author_id = v_uid THEN
    RAISE EXCEPTION 'cannot_repost_own_opinion' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.opinion_reposts (user_id, opinion_id)
  VALUES (v_uid, p_opinion_id)
  ON CONFLICT (user_id, opinion_id) DO NOTHING
  RETURNING true INTO v_inserted;

  -- Only move the counter and notify on an actual new repost -- ON CONFLICT
  -- DO NOTHING means a double-tap resolves here as v_inserted staying NULL.
  IF v_inserted THEN
    UPDATE public.opinions
    SET repost_count = repost_count + 1
    WHERE id = p_opinion_id;

    -- "Someone reposted your opinion" (FORUM.md §10 #9). Same anonymous
    -- pattern as the like/comment/reply notifications: the recipient learns
    -- it happened, never who. private.enqueue_forum_notification (see
    -- 20260727120000_opinion_engagement_and_moderation_notifications.sql)
    -- takes no actor-id parameter at all -- v_uid (the reposter) is available
    -- in scope here but there is no parameter to pass it through, which makes
    -- an anonymity leak structurally inexpressible at this call site, not
    -- just a convention to remember.
    PERFORM private.enqueue_forum_notification(
      p_user_id    => v_author_id,
      p_title      => 'New repost',
      p_body       => 'Someone reposted your opinion',
      p_type       => 'opinion_reposted',
      p_opinion_id => p_opinion_id
    );
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.edit_opinion(p_opinion_id uuid, p_content text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_updated_id uuid;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 5000 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;
  PERFORM private.assert_opinion_content_ok(p_content); -- Spec 1 W9a

  UPDATE public.opinions
  SET content = p_content, edited_at = now()
  WHERE id = p_opinion_id
    AND user_id = v_uid
    AND removed_at IS NULL
    AND created_at > now() - interval '15 minutes'
  RETURNING id INTO v_updated_id;

  -- Covers three distinct cases with one message, deliberately: wrong owner,
  -- already removed, and window expired all mean the same thing to the
  -- caller -- "you cannot edit this right now" -- and none should leak which
  -- specific reason applies (e.g. distinguishing "not yours" from "removed"
  -- would confirm to a non-owner that a specific opinion exists and its
  -- moderation state, which is not this RPC's business to reveal).
  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'not_editable' USING ERRCODE = '42501';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.edit_opinion_comment(p_comment_id uuid, p_content text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_updated_id uuid;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 5000 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;
  PERFORM private.assert_opinion_content_ok(p_content); -- Spec 1 W9a

  UPDATE public.opinion_comments
  SET content = p_content, edited_at = now()
  WHERE id = p_comment_id
    AND user_id = v_uid
    AND removed_at IS NULL
    AND created_at > now() - interval '15 minutes'
  RETURNING id INTO v_updated_id;

  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'not_editable' USING ERRCODE = '42501';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cast_poll_vote(p_option_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_poll_id uuid;
  v_previous_option uuid;
  v_banned_until timestamptz;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;

  -- Banned users may read but not write (§7/§8), same gate as posting.
  SELECT banned_until INTO v_banned_until FROM public.profiles WHERE id = v_uid;
  IF v_banned_until IS NOT NULL AND v_banned_until > now() THEN
    RAISE EXCEPTION 'posting_banned' USING ERRCODE = '42501';
  END IF;

  SELECT poll_id INTO v_poll_id FROM public.poll_options WHERE id = p_option_id;
  IF v_poll_id IS NULL THEN
    RAISE EXCEPTION 'poll_option_not_found' USING ERRCODE = '22023';
  END IF;

  -- Lock the caller's existing vote row (if any) so two concurrent taps
  -- serialise instead of racing the counter updates.
  SELECT option_id INTO v_previous_option
  FROM public.poll_votes
  WHERE poll_id = v_poll_id AND user_id = v_uid
  FOR UPDATE;

  -- Re-voting for the option you already hold is a no-op, not a double count.
  IF v_previous_option = p_option_id THEN
    RETURN;
  END IF;

  INSERT INTO public.poll_votes (poll_id, option_id, user_id)
  VALUES (v_poll_id, p_option_id, v_uid)
  ON CONFLICT (poll_id, user_id)
  DO UPDATE SET option_id = EXCLUDED.option_id, updated_at = now();

  IF v_previous_option IS NOT NULL THEN
    UPDATE public.poll_options
    SET vote_count = greatest(COALESCE(vote_count, 0) - 1, 0)
    WHERE id = v_previous_option;
  END IF;

  UPDATE public.poll_options
  SET vote_count = COALESCE(vote_count, 0) + 1
  WHERE id = p_option_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.attach_opinion_tags(p_opinion_id uuid, p_tag_slugs text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_locked_id uuid;
  v_existing_count int;
  v_new_count int;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_tag_slugs IS NULL OR array_length(p_tag_slugs, 1) IS NULL THEN
    RETURN;
  END IF;

  -- Explicit SELECT ... FOR UPDATE, not a NOT EXISTS(... FOR UPDATE): a
  -- locking clause inside an EXISTS subquery is not guaranteed to hold the
  -- lock, since the row is never actually "returned to the outer query" the
  -- way a plain SELECT's rows are. Locks the opinion row so a second
  -- concurrent attach call from the same author blocks here until this one
  -- commits, rather than both reading the same pre-attach count.
  SELECT id INTO v_locked_id
  FROM public.opinions
  WHERE id = p_opinion_id AND user_id = v_uid
  FOR UPDATE;

  IF v_locked_id IS NULL THEN
    RAISE EXCEPTION 'not_owner' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_existing_count
  FROM public.opinion_tags WHERE opinion_id = p_opinion_id;

  -- Distinct NEW slugs this call would add (already-attached ones are a
  -- no-op via ON CONFLICT below and must not count against the cap again).
  SELECT count(*) INTO v_new_count
  FROM (SELECT DISTINCT slug FROM unnest(p_tag_slugs) AS slug) s
  JOIN public.tags t ON t.slug = s.slug
  WHERE NOT EXISTS (
    SELECT 1 FROM public.opinion_tags ot
    WHERE ot.opinion_id = p_opinion_id AND ot.tag_id = t.id
  );

  IF v_existing_count + v_new_count > 3 THEN
    RAISE EXCEPTION 'too_many_tags' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.opinion_tags (opinion_id, tag_id)
  SELECT p_opinion_id, t.id
  FROM (SELECT DISTINCT slug FROM unnest(p_tag_slugs) AS slug) s
  JOIN public.tags t ON t.slug = s.slug
  ON CONFLICT (opinion_id, tag_id) DO NOTHING;
END;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_family_member(p_id uuid, p_name text, p_birthday date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_relationship_id uuid;
  v_member_id uuid;
  v_reminder_id uuid;
  v_old_name text;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT id INTO v_relationship_id
  FROM public.relationships
  WHERE (user_a = v_user_id OR user_b = v_user_id) AND status = 'active';
  IF v_relationship_id IS NULL THEN
    RAISE EXCEPTION 'No active relationship';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.couple_family_members (relationship_id, name, birthday, created_by)
    VALUES (v_relationship_id, p_name, p_birthday, v_user_id)
    RETURNING id INTO v_member_id;
  ELSE
    SELECT name INTO v_old_name FROM public.couple_family_members
    WHERE id = p_id AND relationship_id = v_relationship_id;
    UPDATE public.couple_family_members
    SET name = p_name, birthday = p_birthday
    WHERE id = p_id AND relationship_id = v_relationship_id
    RETURNING id INTO v_member_id;
    IF v_member_id IS NULL THEN
      RAISE EXCEPTION 'Family member not found';
    END IF;
  END IF;

  SELECT id INTO v_reminder_id
  FROM public.reminders
  WHERE family_member_id = v_member_id AND reminder_type = 'birthday';

  IF p_birthday IS NULL THEN
    -- No birthday, no birthday reminder.
    DELETE FROM public.reminders WHERE id = v_reminder_id;
  ELSIF v_reminder_id IS NULL THEN
    INSERT INTO public.reminders (
      relationship_id, created_by, reminder_type, title,
      remind_at, recurrence, family_member_id
    ) VALUES (
      v_relationship_id, v_user_id, 'birthday', left(p_name || '''s birthday', 80),
      (p_birthday::text || ' 00:00:00+00')::timestamptz, 'yearly', v_member_id
    );
  ELSE
    UPDATE public.reminders
    SET remind_at = (p_birthday::text || ' 00:00:00+00')::timestamptz,
        -- Renamed with them, unless the couple wrote their own title.
        title = CASE WHEN title = left(coalesce(v_old_name, p_name) || '''s birthday', 80)
                     THEN left(p_name || '''s birthday', 80) ELSE title END
    WHERE id = v_reminder_id;
  END IF;

  RETURN v_member_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.post_place_update(p_relationship_id uuid, p_label text, p_note text DEFAULT NULL::text, p_latitude numeric DEFAULT NULL::numeric, p_longitude numeric DEFAULT NULL::numeric, p_city text DEFAULT NULL::text, p_country text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_message_id uuid;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND (r.user_a = v_user_id OR r.user_b = v_user_id)
      AND r.chat_archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Not a member of this relationship';
  END IF;

  -- content carries the label: messages_payload_present requires content
  -- or media, and it gives a push preview and any older client something
  -- real to show rather than an empty bubble.
  INSERT INTO public.messages (
    relationship_id, sender_id, client_message_id,
    content, media_type, source
  )
  VALUES (
    p_relationship_id, v_user_id, gen_random_uuid(),
    p_label, 'place', 'native'
  )
  RETURNING id INTO v_message_id;

  INSERT INTO public.place_updates (
    relationship_id, user_id, message_id,
    label, note, latitude, longitude, city, country
  )
  VALUES (
    p_relationship_id, v_user_id, v_message_id,
    p_label, p_note, p_latitude, p_longitude, p_city, p_country
  );

  RETURN v_message_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.add_event_memory(p_event_id uuid, p_line text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v public.couple_events; v_me uuid; v_line text := btrim(p_line); v_id uuid;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v FROM public.couple_events WHERE id = p_event_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.together_fail('not_found'); END IF;
  v_me := public.together_actor(v.relationship_id);
  -- Only an event of both of ours (the prompt's rule, R4).
  IF v.status <> 'confirmed' OR v.visibility <> 'shared' OR NOT (v_me = ANY (v.participant_ids))
     OR cardinality(v.participant_ids) <> 2 THEN
    PERFORM public.together_fail('not_found');
  END IF;
  -- A repeating event has no single day to remember (it would land on its first week).
  IF v.rrule IS NOT NULL THEN PERFORM public.together_fail('invalid_input'); END IF;
  -- A memory is of something that has begun (a day's grace for all-day across zones).
  IF (v.all_day AND v.start_date > current_date + 1) OR (NOT v.all_day AND v.starts_at > now()) THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  IF v_line IS NULL OR v_line = '' OR char_length(v_line) > 300 THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, note, occurred_at, couple_event_id)
  VALUES (v.relationship_id, v_me, 'highlight', left(btrim(v.title), 80), v_line,
          public.together_event_day(v), v.id)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.share_a_win(p_relationship_id uuid, p_title text, p_note text DEFAULT NULL::text, p_occurred_on date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_title text := btrim(coalesce(p_title, ''));
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_today date;
  v_on date;
  v_id uuid;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  IF NOT public.feature_flag_on('share_a_win') THEN RAISE EXCEPTION 'win:not_allowed'; END IF;
  IF v_uid IS NULL OR NOT public.relationship_active_for_me(p_relationship_id) THEN
    RAISE EXCEPTION 'win:not_allowed';
  END IF;
  -- The sharer's own day (review M6), a day either side allowed.
  v_today := (now() AT TIME ZONE coalesce(public.notification_recipient_tz(v_uid), 'UTC'))::date;
  v_on := coalesce(p_occurred_on, v_today);
  IF char_length(v_title) = 0 OR char_length(v_title) > 80
     OR char_length(coalesce(v_note, '')) > 300
     OR v_on NOT BETWEEN v_today - 1 AND v_today + 1 THEN
    RAISE EXCEPTION 'win:invalid';
  END IF;
  PERFORM set_config('attune.share_a_win', 'on', true);
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, note, occurred_at,
                                      visibility, is_win)
  VALUES (p_relationship_id, v_uid, 'highlight', v_title, v_note, v_on, 'shared', true)
  RETURNING id INTO v_id;
  PERFORM set_config('attune.share_a_win', 'off', true);
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.increment_opinion_like_count(p_opinion_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_like_count int;
  v_dislike_count int;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  UPDATE public.opinions
  SET like_count = COALESCE(like_count, 0) + 1
  WHERE id = p_opinion_id
  RETURNING like_count, dislike_count INTO v_like_count, v_dislike_count;

  PERFORM realtime.send(
    jsonb_build_object(
      'opinion_id', p_opinion_id,
      'like_count', v_like_count,
      'dislike_count', v_dislike_count
    ),
    'counts',
    'opinion-counts:' || p_opinion_id,
    false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.decrement_opinion_like_count(p_opinion_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_like_count int;
  v_dislike_count int;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  UPDATE public.opinions
  SET like_count = GREATEST(COALESCE(like_count, 0) - 1, 0)
  WHERE id = p_opinion_id
  RETURNING like_count, dislike_count INTO v_like_count, v_dislike_count;

  PERFORM realtime.send(
    jsonb_build_object(
      'opinion_id', p_opinion_id,
      'like_count', v_like_count,
      'dislike_count', v_dislike_count
    ),
    'counts',
    'opinion-counts:' || p_opinion_id,
    false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.increment_opinion_dislike_count(p_opinion_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_like_count int;
  v_dislike_count int;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  UPDATE public.opinions
  SET dislike_count = COALESCE(dislike_count, 0) + 1
  WHERE id = p_opinion_id
  RETURNING like_count, dislike_count INTO v_like_count, v_dislike_count;

  PERFORM realtime.send(
    jsonb_build_object(
      'opinion_id', p_opinion_id,
      'like_count', v_like_count,
      'dislike_count', v_dislike_count
    ),
    'counts',
    'opinion-counts:' || p_opinion_id,
    false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.decrement_opinion_dislike_count(p_opinion_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_like_count int;
  v_dislike_count int;
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  UPDATE public.opinions
  SET dislike_count = GREATEST(COALESCE(dislike_count, 0) - 1, 0)
  WHERE id = p_opinion_id
  RETURNING like_count, dislike_count INTO v_like_count, v_dislike_count;

  PERFORM realtime.send(
    jsonb_build_object(
      'opinion_id', p_opinion_id,
      'like_count', v_like_count,
      'dislike_count', v_dislike_count
    ),
    'counts',
    'opinion-counts:' || p_opinion_id,
    false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.increment_opinion_comment_count(p_opinion_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  UPDATE public.opinions
  SET comment_count = COALESCE(comment_count, 0) + 1
  WHERE id = p_opinion_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.decrement_opinion_comment_count(p_opinion_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  UPDATE public.opinions
  SET comment_count = GREATEST(COALESCE(comment_count, 0) - 1, 0)
  WHERE id = p_opinion_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.increment_comment_like_count(p_comment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  UPDATE public.opinion_comments
  SET like_count = COALESCE(like_count, 0) + 1
  WHERE id = p_comment_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.decrement_comment_like_count(p_comment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  -- Entry gates 2026-11-27 (fix round): only a complete account writes
  -- (private.account_ready: users row, 18+ DOB, EULA >= 2, no open hold).
  -- The service role (no auth.uid()) is never gated.
  IF auth.uid() IS NOT NULL AND NOT private.account_ready(auth.uid()) THEN
    RAISE EXCEPTION 'account_not_ready' USING ERRCODE = '42501';
  END IF;
  UPDATE public.opinion_comments
  SET like_count = GREATEST(COALESCE(like_count, 0) - 1, 0)
  WHERE id = p_comment_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.report_opinion(p_opinion_id uuid, p_reason text DEFAULT 'Other'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_count int;
  v_inserted boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  PERFORM private.assert_valid_report_reason(p_reason);

  INSERT INTO public.forum_reports (reported_by, opinion_id, reason, priority)
  VALUES (auth.uid(), p_opinion_id, p_reason, private.is_priority_reason(p_reason))
  ON CONFLICT (reported_by, opinion_id) WHERE opinion_id IS NOT NULL DO UPDATE -- Spec 1 W9b (PF-C1)
    SET reason = EXCLUDED.reason, priority = true, status = 'pending', reviewed_at = NULL, created_at = now()
    WHERE EXCLUDED.reason = 'Someone may be at risk'
      AND (forum_reports.reason <> EXCLUDED.reason OR forum_reports.status IN ('reviewed_kept', 'reviewed_removed'))
  RETURNING true INTO v_inserted;

  -- A repeat report from the same account is a silent no-op: the count must
  -- not move a second time for the same reporter.
  IF v_inserted IS NOT TRUE THEN -- Spec 1 W9b (owner a)
    RETURN;
  END IF;
  -- Spec 1 W9b (D13): an at-risk report reaches a person, never auto-hide.
  IF p_reason = 'Someone may be at risk' THEN RETURN; END IF;

  -- Entry gates 2026-11-27 (fix round): reporting stays open (a safety
  -- tool), but a report from an account that is not complete is kept for
  -- moderators only and never counts toward the auto-hide threshold.
  IF NOT private.account_ready(auth.uid()) THEN RETURN; END IF;

  UPDATE public.opinions
  SET report_count = COALESCE(report_count, 0) + 1
  WHERE id = p_opinion_id
  RETURNING report_count INTO v_count;

  IF v_count >= 10 THEN
    UPDATE public.opinions SET hidden_pending_review = true WHERE id = p_opinion_id;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.report_opinion_comment(p_comment_id uuid, p_reason text DEFAULT 'Other'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_count int;
  v_inserted boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  PERFORM private.assert_valid_report_reason(p_reason);

  INSERT INTO public.forum_reports (reported_by, comment_id, reason, priority)
  VALUES (auth.uid(), p_comment_id, p_reason, private.is_priority_reason(p_reason))
  ON CONFLICT (reported_by, comment_id) WHERE comment_id IS NOT NULL DO UPDATE -- Spec 1 W9b (PF-C1)
    SET reason = EXCLUDED.reason, priority = true, status = 'pending', reviewed_at = NULL, created_at = now()
    WHERE EXCLUDED.reason = 'Someone may be at risk'
      AND (forum_reports.reason <> EXCLUDED.reason OR forum_reports.status IN ('reviewed_kept', 'reviewed_removed'))
  RETURNING true INTO v_inserted;

  IF v_inserted IS NOT TRUE THEN -- Spec 1 W9b (owner a)
    RETURN;
  END IF;
  -- Spec 1 W9b (D13): an at-risk report reaches a person, never auto-hide.
  IF p_reason = 'Someone may be at risk' THEN RETURN; END IF;

  -- Entry gates 2026-11-27 (fix round): reporting stays open (a safety
  -- tool), but a report from an account that is not complete is kept for
  -- moderators only and never counts toward the auto-hide threshold.
  IF NOT private.account_ready(auth.uid()) THEN RETURN; END IF;

  UPDATE public.opinion_comments
  SET report_count = COALESCE(report_count, 0) + 1
  WHERE id = p_comment_id
  RETURNING report_count INTO v_count;

  IF v_count >= 10 THEN
    UPDATE public.opinion_comments SET hidden_pending_review = true WHERE id = p_comment_id;
  END IF;
END;
$function$;

COMMIT;
