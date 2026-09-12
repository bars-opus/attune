-- Stories: the RPC surface. Task 4 owns create_story_upload_intent;
-- Tasks 5, 6 and 7 append their own DO blocks below (finalize, reads,
-- author deletion) inside the SAME transaction, sharing this file's
-- fixtures and test_set_story_rpc_auth helper. Keep new blocks appended
-- after the ROLLBACK-free end of this one, before the final RESET
-- ROLE / DROP FUNCTION / ROLLBACK footer.
--
-- create_story_upload_intent is SECURITY DEFINER and is the only writer
-- of a table (story_media_upload_intents) with zero client grants, and
-- the only path that can mint a key the storage INSERT policy accepts.
-- A hole here is not "a bad row" -- it is an outsider minting an upload
-- slot into someone else's relationship, or an abuse loop that fills a
-- private bucket. Every check below is written as an attack or a limit
-- that must hold, not a happy path that must pass.
--
-- House rule, applied throughout this file: every comparison of a
-- jsonb-extracted value (v_res->>'code', v_res->>'error', and so on)
-- uses IS DISTINCT FROM / IS NOT DISTINCT FROM, never a bare = or <>.
-- A bare comparison against NULL evaluates to NULL, not true -- so an
-- IF built on one silently never fires, and the RAISE EXCEPTION it
-- guards never runs. That makes the assertion pass while checking
-- nothing, which is worse than the assertion being absent: absence is
-- visible in a diff, a silently-vacuous IF is not. This has already
-- produced two vacuous assertions elsewhere in this codebase using
-- exactly this idiom. Every check below extracting a jsonb field is
-- written IS DISTINCT FROM on principle, even where the value happens
-- to be non-nullable today (story_intent_error always populates
-- 'code'), because the next task appending to this file should find one
-- consistent idiom to copy rather than a bare comparison it has to
-- notice is safe-for-now and might not stay that way. Comparisons of
-- count(*) results are the one exception: count(*) can never be NULL,
-- so a bare = or <> there is correct and reads more plainly.

BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-00000000c401'::uuid),
  ('00000000-0000-0000-0000-00000000c402'::uuid),
  ('00000000-0000-0000-0000-00000000c403'::uuid) ON CONFLICT DO NOTHING;

INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-00000000c401'::uuid, '+15557770001', 'SR1'),
  ('00000000-0000-0000-0000-00000000c402'::uuid, '+15557770002', 'SR2'),
  ('00000000-0000-0000-0000-00000000c403'::uuid, '+15557770003', 'SR3')
  ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.test_set_story_rpc_auth(p_user_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p_user_id::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_user_id, 'role', 'authenticated')::text, true);
END;
$$;

-- ---------------------------------------------------------------------
-- Grants: anon must not reach create_story_upload_intent at all.
-- ---------------------------------------------------------------------
RESET ROLE;
DO $$ BEGIN
  IF has_function_privilege('anon',
    'public.create_story_upload_intent(uuid,text,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: anon can execute create_story_upload_intent';
  END IF;
  IF NOT has_function_privilege('authenticated',
    'public.create_story_upload_intent(uuid,text,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated cannot execute create_story_upload_intent';
  END IF;
END $$;

-- =======================================================================
-- Task 4: create_story_upload_intent contracts.
-- =======================================================================
DO $$
DECLARE
  v_rel uuid;
  v_other uuid;
  v_res jsonb;
  v_count int;
  v_key text;
  v_max_bytes bigint;
  i int;
BEGIN
  RESET ROLE;

  -- Flag starts false per 20260938010000's seed row -- confirm that,
  -- since contract 2 depends on it.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'stories';

  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000c401'::uuid,
          '00000000-0000-0000-0000-00000000c402'::uuid, 'active')
  RETURNING id INTO v_rel;

  -- A relationship the attacker (c403) is NOT in.
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000c401'::uuid,
          '00000000-0000-0000-0000-00000000c403'::uuid, 'active')
  RETURNING id INTO v_other;

  -- =================================================================
  -- Contract 1: an outsider requesting an intent for someone else's
  -- relationship gets FORBIDDEN and no row is written.
  -- =================================================================
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c403'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: outsider got an intent for a foreign relationship: %', v_res;
  END IF;
  IF v_res->>'code' IS DISTINCT FROM 'FORBIDDEN' THEN
    RAISE EXCEPTION 'wrong code for outsider intent request: %', v_res->>'code';
  END IF;

  RESET ROLE;
  SELECT count(*) INTO v_count
    FROM public.story_media_upload_intents WHERE relationship_id = v_rel;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a refused intent request still wrote a row';
  END IF;

  -- =================================================================
  -- Contract 2: a member with the stories flag OFF gets a refusal.
  -- §8: the flag gates NEW intents only.
  -- =================================================================
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: a member got an intent while stories flag is OFF: %', v_res;
  END IF;
  IF v_res->>'code' IS DISTINCT FROM 'UNAVAILABLE' THEN
    RAISE EXCEPTION 'wrong code for flag-off intent request: %', v_res->>'code';
  END IF;

  RESET ROLE;
  SELECT count(*) INTO v_count
    FROM public.story_media_upload_intents WHERE relationship_id = v_rel;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a flag-off refusal still wrote a row';
  END IF;

  -- =================================================================
  -- Contract 3: a member with the flag ON gets a key under
  -- story-media/, the right bucket, a 15-minute expiry, and the
  -- correct max_bytes for the object.
  -- =================================================================
  UPDATE public.feature_flags SET enabled = true WHERE key = 'stories';

  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'a member with the flag on could not get an intent: %', v_res;
  END IF;
  v_key := v_res->>'storage_key';
  IF v_key IS NULL OR v_key NOT LIKE 'story-media/%' THEN
    RAISE EXCEPTION 'intent key is not under story-media/: %', v_key;
  END IF;
  IF v_res->>'bucket' IS DISTINCT FROM 'story-media' THEN
    RAISE EXCEPTION 'wrong bucket in intent response: %', v_res->>'bucket';
  END IF;
  IF (v_res->>'intent_id') IS NULL THEN
    RAISE EXCEPTION 'intent response has no intent_id: %', v_res;
  END IF;
  IF ((v_res->>'expires_at')::timestamptz - now())
      NOT BETWEEN interval '14 minutes 55 seconds' AND interval '15 minutes 5 seconds' THEN
    RAISE EXCEPTION 'intent expiry is not ~15 minutes out: %', v_res->>'expires_at';
  END IF;

  RESET ROLE;
  SELECT max_bytes INTO v_max_bytes
    FROM public.story_media_upload_intents WHERE storage_key = v_key;
  IF v_max_bytes IS DISTINCT FROM 5242880 THEN
    RAISE EXCEPTION 'media/image intent got max_bytes %, expected 5242880',
      COALESCE(v_max_bytes::text, 'NULL');
  END IF;

  -- Video media -> 25MB ceiling.
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'video', 'video/mp4');
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'a video media intent was refused: %', v_res;
  END IF;
  RESET ROLE;
  SELECT max_bytes INTO v_max_bytes
    FROM public.story_media_upload_intents WHERE id = (v_res->>'intent_id')::uuid;
  IF v_max_bytes IS DISTINCT FROM 26214400 THEN
    RAISE EXCEPTION 'media/video intent got max_bytes %, expected 26214400',
      COALESCE(v_max_bytes::text, 'NULL');
  END IF;

  -- Thumbnail -> 800KB ceiling.
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'a thumbnail intent was refused: %', v_res;
  END IF;
  RESET ROLE;
  SELECT max_bytes INTO v_max_bytes
    FROM public.story_media_upload_intents WHERE id = (v_res->>'intent_id')::uuid;
  IF v_max_bytes IS DISTINCT FROM 819200 THEN
    RAISE EXCEPTION 'thumbnail intent got max_bytes %, expected 819200',
      COALESCE(v_max_bytes::text, 'NULL');
  END IF;

  -- =================================================================
  -- Contract 6 (checked here, ahead of the volume contracts below so
  -- rejected calls do not consume any of the abuse-limit budget):
  -- an unlisted p_media_role/object_kind, or a MIME outside the
  -- allowlist, gets INVALID_INPUT and writes no row.
  -- =================================================================
  RESET ROLE;
  SELECT count(*) INTO v_count FROM public.story_media_upload_intents;

  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'attachment', 'image', 'image/jpeg');
  IF (v_res->>'error') IS DISTINCT FROM 'true' OR v_res->>'code' IS DISTINCT FROM 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'EXPLOIT: unlisted object_kind accepted: %', v_res;
  END IF;

  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/png');
  IF (v_res->>'error') IS DISTINCT FROM 'true' OR v_res->>'code' IS DISTINCT FROM 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'EXPLOIT: image/png accepted for main media: %', v_res;
  END IF;

  v_res := public.create_story_upload_intent(v_rel, 'media', 'video', 'video/quicktime');
  IF (v_res->>'error') IS DISTINCT FROM 'true' OR v_res->>'code' IS DISTINCT FROM 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'EXPLOIT: video/quicktime accepted for main media: %', v_res;
  END IF;

  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'video/mp4');
  IF (v_res->>'error') IS DISTINCT FROM 'true' OR v_res->>'code' IS DISTINCT FROM 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'EXPLOIT: video/mp4 accepted for a thumbnail: %', v_res;
  END IF;

  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'video', 'image/jpeg');
  IF (v_res->>'error') IS DISTINCT FROM 'true' OR v_res->>'code' IS DISTINCT FROM 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'EXPLOIT: media_type=video accepted for a thumbnail: %', v_res;
  END IF;

  RESET ROLE;
  SELECT count(*) - v_count INTO v_count FROM public.story_media_upload_intents;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: an INVALID_INPUT call still wrote % row(s)', v_count;
  END IF;

  -- =================================================================
  -- Contract 4: holding 20 unconsumed, unexpired intents -> RATE_LIMITED.
  -- Clear out what earlier contracts opened first, so this measures
  -- exactly the ceiling.
  -- =================================================================
  RESET ROLE;
  DELETE FROM public.story_media_upload_intents
   WHERE requester_id = '00000000-0000-0000-0000-00000000c401'::uuid;

  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  FOR i IN 1..20 LOOP
    v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
    IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'intent #% of 20 was refused before the ceiling: %', i, v_res;
    END IF;
  END LOOP;

  RESET ROLE;
  SELECT count(*) INTO v_count
    FROM public.story_media_upload_intents
   WHERE requester_id = '00000000-0000-0000-0000-00000000c401'::uuid
     AND used_at IS NULL AND expires_at > now();
  IF v_count <> 20 THEN
    RAISE EXCEPTION 'expected exactly 20 open intents before the ceiling check, got %', v_count;
  END IF;

  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION
      'EXPLOIT: a 21st unconsumed intent was issued past the 20-intent ceiling: %', v_res;
  END IF;
  IF v_res->>'code' IS DISTINCT FROM 'RATE_LIMITED' THEN
    RAISE EXCEPTION 'wrong code at the 20-intent ceiling: %', v_res->>'code';
  END IF;

  RESET ROLE;
  SELECT count(*) INTO v_count
    FROM public.story_media_upload_intents
   WHERE requester_id = '00000000-0000-0000-0000-00000000c401'::uuid
     AND used_at IS NULL AND expires_at > now();
  IF v_count <> 20 THEN
    RAISE EXCEPTION 'EXPLOIT: a rate-limited call still wrote a row (now % open)', v_count;
  END IF;

  -- Consuming (or expiring) an intent frees a slot -- proves the check
  -- is a live count, not a permanent lockout once tripped.
  UPDATE public.story_media_upload_intents SET used_at = now()
   WHERE requester_id = '00000000-0000-0000-0000-00000000c401'::uuid
     AND used_at IS NULL AND expires_at > now()
   AND id = (SELECT id FROM public.story_media_upload_intents
              WHERE requester_id = '00000000-0000-0000-0000-00000000c401'::uuid
                AND used_at IS NULL AND expires_at > now()
              LIMIT 1);
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'freeing one slot did not allow a new intent: %', v_res;
  END IF;

  -- =================================================================
  -- Contract 5: 121 calls in one hour -> RATE_LIMITED, independent of
  -- how many are currently open. Consume everything so contract 4's
  -- ceiling cannot be what trips this -- this measures the hourly
  -- call-count cap specifically.
  -- =================================================================
  RESET ROLE;
  UPDATE public.story_media_upload_intents SET used_at = now()
   WHERE requester_id = '00000000-0000-0000-0000-00000000c402'::uuid;
  DELETE FROM public.story_media_upload_intents
   WHERE requester_id = '00000000-0000-0000-0000-00000000c402'::uuid;

  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c402'::uuid);
  FOR i IN 1..120 LOOP
    v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
    IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'call #% of 120 was refused before the hourly cap: %', i, v_res;
    END IF;
    -- Consume immediately so this loop measures the CALL-RATE cap, not
    -- the 20-open-intent ceiling from contract 4.
    RESET ROLE;
    UPDATE public.story_media_upload_intents SET used_at = now()
     WHERE id = (v_res->>'intent_id')::uuid;
    PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c402'::uuid);
  END LOOP;

  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION
      'EXPLOIT: the 121st call in the hour was accepted past the hourly cap: %', v_res;
  END IF;
  IF v_res->>'code' IS DISTINCT FROM 'RATE_LIMITED' THEN
    RAISE EXCEPTION 'wrong code at the hourly cap: %', v_res->>'code';
  END IF;

  RAISE NOTICE 'story_rpc_contracts (Task 4): all held';
END $$;

-- Tasks 5, 6 and 7: append further DO $$ ... $$ blocks here, above the
-- footer below. Each should RESET ROLE before touching fixtures
-- directly and re-call test_set_story_rpc_auth before acting as a user.

-- ---------------------------------------------------------------------
-- Grants: anon must not reach create_story_item at all.
-- ---------------------------------------------------------------------
RESET ROLE;
DO $$ BEGIN
  IF has_function_privilege('anon',
    'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: anon can execute create_story_item';
  END IF;
  IF NOT has_function_privilege('authenticated',
    'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated cannot execute create_story_item';
  END IF;
  -- bump_story_signal is an internal helper (named exactly this for
  -- Task 6 to reuse) and must never be directly callable by a client --
  -- it mutates a signals row for whatever relationship id it is handed,
  -- with no membership check of its own.
  IF has_function_privilege('authenticated',
    'public.bump_story_signal(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated can execute bump_story_signal directly';
  END IF;
END $$;

-- =======================================================================
-- Task 5: create_story_item contracts.
--
-- A hole here is not "a bad row" -- it is a client posting a story with
-- a storage key it does not own, extending its own expiry forever by
-- resending the same client_story_id with different intents, filing a
-- story under a stolen intent belonging to someone else, or doubling a
-- post because a response was lost on the wire. Every check below is
-- written as an attack or a duplicate-post scenario that must be
-- refused, not a happy path that must pass.
-- =======================================================================
DO $$
DECLARE
  v_rel          uuid;
  v_other_rel    uuid;
  v_res          jsonb;
  v_res2         jsonb;
  v_count        int;
  v_media_id     uuid;
  v_thumb_id     uuid;
  v_media_id2    uuid;
  v_thumb_id2    uuid;
  v_media_key    text;
  v_thumb_key    text;
  v_story_id     uuid;
  v_row          public.story_items%ROWTYPE;
  v_client_id    uuid;
  v_server_today date;
  v_expect_east  date;
  v_expect_west  date;
  v_got_east     date;
  v_got_west     date;
BEGIN
  RESET ROLE;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'stories';

  -- Task 4's own contracts (above, in this same file/transaction) leave
  -- c401 sitting at its 20-open-intent ceiling and c402 mid rolling-hour
  -- window. Clear both so this block's create_story_upload_intent calls
  -- are not themselves refused with RATE_LIMITED before Task 5 is ever
  -- reached.
  DELETE FROM public.story_media_upload_intents
   WHERE requester_id IN ('00000000-0000-0000-0000-00000000c401'::uuid,
                           '00000000-0000-0000-0000-00000000c402'::uuid);

  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000c401'::uuid,
          '00000000-0000-0000-0000-00000000c402'::uuid, 'active')
  RETURNING id INTO v_rel;

  -- A relationship the attacker (c403) is NOT in -- reuse the earlier
  -- v_other pattern under a fresh name scoped to this block.
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000c401'::uuid,
          '00000000-0000-0000-0000-00000000c403'::uuid, 'active')
  RETURNING id INTO v_other_rel;

  -- Helper: issue one media + one thumbnail intent for c401 in v_rel,
  -- and stamp real storage.objects rows sized/typed to pass validation.
  -- Declared inline each time (no reusable PL/pgSQL function needed for
  -- a single test file) via a small repeated sequence below.

  -- =================================================================
  -- Contract 2 & baseline: a member finalizes a story. expires_at is
  -- exactly created_at + 24h (no client parameter can move it -- the
  -- signature has none), media_type is derived from the intent, and
  -- the row is otherwise correct.
  -- =================================================================
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  v_media_id := (v_res->>'intent_id')::uuid;
  v_media_key := v_res->>'storage_key';
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_thumb_id := (v_res->>'intent_id')::uuid;
  v_thumb_key := v_res->>'storage_key';

  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_media_key,
     jsonb_build_object('size', 1000000, 'mimetype', 'image/jpeg')),
    ('story-media', v_thumb_key,
     jsonb_build_object('size', 100000, 'mimetype', 'image/jpeg'));

  v_client_id := gen_random_uuid();
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_item(
    v_rel, v_client_id, v_media_id, v_thumb_id, 1080, 1920, NULL, 0);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'a valid finalize call was refused: %', v_res;
  END IF;
  IF (v_res->>'existing')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'first finalize call should not report existing=true: %', v_res;
  END IF;
  v_story_id := (v_res->>'story_id')::uuid;
  IF v_story_id IS NULL THEN
    RAISE EXCEPTION 'finalize returned no story_id: %', v_res;
  END IF;

  RESET ROLE;
  SELECT * INTO v_row FROM public.story_items WHERE id = v_story_id;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'finalized story row does not exist: %', v_story_id;
  END IF;
  IF v_row.expires_at IS DISTINCT FROM v_row.created_at + interval '24 hours' THEN
    RAISE EXCEPTION 'expires_at is not created_at + 24h: created_at=%, expires_at=%',
      v_row.created_at, v_row.expires_at;
  END IF;
  IF v_row.media_type IS DISTINCT FROM 'image' THEN
    RAISE EXCEPTION 'media_type was not derived as image from the intent: %', v_row.media_type;
  END IF;
  IF v_row.media_key IS DISTINCT FROM v_media_key
     OR v_row.thumbnail_key IS DISTINCT FROM v_thumb_key THEN
    RAISE EXCEPTION 'stored keys do not match the consumed intents'' storage_key';
  END IF;

  -- Both intents must now be consumed.
  IF (SELECT used_at FROM public.story_media_upload_intents WHERE id = v_media_id) IS NULL
     OR (SELECT used_at FROM public.story_media_upload_intents WHERE id = v_thumb_id) IS NULL
  THEN
    RAISE EXCEPTION 'EXPLOIT: finalize succeeded without consuming both intents';
  END IF;

  -- =================================================================
  -- Contract 1: a replayed (author, client_story_id) call returns the
  -- SAME story id with existing=true, and posts no second row. This is
  -- the whole reason client_story_id exists -- a client that lost the
  -- response to the first call must be able to resend safely, even
  -- though the intents it would otherwise need are already consumed.
  -- =================================================================
  SELECT count(*) INTO v_count FROM public.story_items;
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res2 := public.create_story_item(
    v_rel, v_client_id, v_media_id, v_thumb_id, 1080, 1920, NULL, 0);
  IF (v_res2->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: a replay was refused instead of returning the existing item: %', v_res2;
  END IF;
  IF (v_res2->>'story_id')::uuid IS DISTINCT FROM v_story_id THEN
    RAISE EXCEPTION 'EXPLOIT: a replay returned a DIFFERENT story id: got %, expected %',
      v_res2->>'story_id', v_story_id;
  END IF;
  IF (v_res2->>'existing')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: a replay did not report existing=true: %', v_res2;
  END IF;

  RESET ROLE;
  SELECT count(*) - v_count INTO v_count FROM public.story_items;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a replayed finalize call posted % new row(s)', v_count;
  END IF;

  -- =================================================================
  -- Contract 3: occurred_on follows p_utc_offset_minutes -- the
  -- poster's civil date at v_now, midnight to midnight, no cutoff.
  --
  -- Made non-vacuous: rather than picking one fixed offset (which could
  -- pass by coincidence if the server happens to share the client's
  -- date whenever this suite runs), this computes what occurred_on
  -- SHOULD be, right now, at BOTH clamp extremes (+840 and -840) using
  -- the exact same civil-date arithmetic the spec prescribes, and
  -- requires that at least one of them differ from the server's own
  -- now()::date. A 28-hour window (from now-840min to now+840min)
  -- always straddles at least one midnight, so this holds no matter
  -- what wall-clock time the suite happens to run at -- a wrong
  -- implementation that ignores the offset and uses current_date
  -- always fails whichever side differs; one that honours it always
  -- matches both.
  -- =================================================================
  v_server_today := now()::date;
  v_expect_east := (now() + interval '840 minutes')::date;
  v_expect_west := (now() - interval '840 minutes')::date;
  IF v_expect_east = v_server_today AND v_expect_west = v_server_today THEN
    RAISE EXCEPTION
      'test construction error: neither +840 nor -840 minutes crosses a day boundary right now';
  END IF;

  -- East extreme (+840, e.g. Auckland-and-beyond).
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  v_media_id2 := (v_res->>'intent_id')::uuid;
  v_media_key := v_res->>'storage_key';
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_thumb_id2 := (v_res->>'intent_id')::uuid;
  v_thumb_key := v_res->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_media_key,
     jsonb_build_object('size', 1000000, 'mimetype', 'image/jpeg')),
    ('story-media', v_thumb_key,
     jsonb_build_object('size', 100000, 'mimetype', 'image/jpeg'));
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_item(
    v_rel, gen_random_uuid(), v_media_id2, v_thumb_id2, 1080, 1920, NULL, 840);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'finalize at offset +840 was refused: %', v_res;
  END IF;
  RESET ROLE;
  SELECT occurred_on INTO v_got_east
    FROM public.story_items WHERE id = (v_res->>'story_id')::uuid;

  -- West extreme (-840).
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  v_media_id2 := (v_res->>'intent_id')::uuid;
  v_media_key := v_res->>'storage_key';
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_thumb_id2 := (v_res->>'intent_id')::uuid;
  v_thumb_key := v_res->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_media_key,
     jsonb_build_object('size', 1000000, 'mimetype', 'image/jpeg')),
    ('story-media', v_thumb_key,
     jsonb_build_object('size', 100000, 'mimetype', 'image/jpeg'));
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_item(
    v_rel, gen_random_uuid(), v_media_id2, v_thumb_id2, 1080, 1920, NULL, -840);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'finalize at offset -840 was refused: %', v_res;
  END IF;
  RESET ROLE;
  SELECT occurred_on INTO v_got_west
    FROM public.story_items WHERE id = (v_res->>'story_id')::uuid;

  IF v_got_east IS DISTINCT FROM v_expect_east THEN
    RAISE EXCEPTION
      'EXPLOIT: occurred_on at offset +840 was %, expected % (server today is %) -- offset not honoured',
      v_got_east, v_expect_east, v_server_today;
  END IF;
  IF v_got_west IS DISTINCT FROM v_expect_west THEN
    RAISE EXCEPTION
      'EXPLOIT: occurred_on at offset -840 was %, expected % (server today is %) -- offset not honoured',
      v_got_west, v_expect_west, v_server_today;
  END IF;
  -- And the two extremes must disagree with each other whenever the
  -- window straddles a boundary (guaranteed by the check above) --
  -- otherwise an implementation that ignores the offset entirely could
  -- still coincidentally match one side.
  IF v_got_east IS NOT DISTINCT FROM v_got_west AND v_expect_east IS DISTINCT FROM v_expect_west THEN
    RAISE EXCEPTION
      'EXPLOIT: offsets +840 and -840 produced the SAME occurred_on (%) though they should differ',
      v_got_east;
  END IF;

  -- Offsets outside [-840, 840] are clamped, not trusted: 100000 clamps
  -- down to 840 and must produce the SAME occurred_on as an explicit 840.
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  v_media_id2 := (v_res->>'intent_id')::uuid;
  v_media_key := v_res->>'storage_key';
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_thumb_id2 := (v_res->>'intent_id')::uuid;
  v_thumb_key := v_res->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_media_key,
     jsonb_build_object('size', 1000000, 'mimetype', 'image/jpeg')),
    ('story-media', v_thumb_key,
     jsonb_build_object('size', 100000, 'mimetype', 'image/jpeg'));
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_item(
    v_rel, gen_random_uuid(), v_media_id2, v_thumb_id2, 1080, 1920, NULL, 100000);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'finalize at an out-of-range offset was refused: %', v_res;
  END IF;
  RESET ROLE;
  SELECT occurred_on INTO v_got_east
    FROM public.story_items WHERE id = (v_res->>'story_id')::uuid;
  IF v_got_east IS DISTINCT FROM v_expect_east THEN
    RAISE EXCEPTION
      'EXPLOIT: an offset of 100000 was not clamped to 840 -- got occurred_on %, expected %',
      v_got_east, v_expect_east;
  END IF;

  -- =================================================================
  -- Contract 4: an intent belonging to another user -> unavailable, no
  -- row written.
  -- =================================================================
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c402'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  v_media_id2 := (v_res->>'intent_id')::uuid;
  v_media_key := v_res->>'storage_key';
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_thumb_id2 := (v_res->>'intent_id')::uuid;
  v_thumb_key := v_res->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_media_key,
     jsonb_build_object('size', 1000000, 'mimetype', 'image/jpeg')),
    ('story-media', v_thumb_key,
     jsonb_build_object('size', 100000, 'mimetype', 'image/jpeg'));

  SELECT count(*) INTO v_count FROM public.story_items;
  -- c401 tries to finalize using c402's intents.
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_item(
    v_rel, gen_random_uuid(), v_media_id2, v_thumb_id2, 1080, 1920, NULL, 0);
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: finalize succeeded using another user''s intents: %', v_res;
  END IF;
  IF v_res->>'code' IS DISTINCT FROM 'UNAVAILABLE' THEN
    RAISE EXCEPTION 'wrong code for a foreign intent: %', v_res->>'code';
  END IF;
  RESET ROLE;
  SELECT count(*) - v_count INTO v_count FROM public.story_items;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a foreign-intent finalize call still wrote % row(s)', v_count;
  END IF;
  -- Those two intents remain unconsumed, so their rightful owner can
  -- still use them (proves the refusal did not silently burn them).
  IF (SELECT used_at FROM public.story_media_upload_intents WHERE id = v_media_id2) IS NOT NULL
     OR (SELECT used_at FROM public.story_media_upload_intents WHERE id = v_thumb_id2) IS NOT NULL
  THEN
    RAISE EXCEPTION 'EXPLOIT: a refused finalize call still consumed a foreign intent';
  END IF;

  -- =================================================================
  -- Contract 5: a consumed intent -> unavailable, no second row. Reuse
  -- the baseline story's already-consumed v_media_id.
  -- =================================================================
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_thumb_id2 := (v_res->>'intent_id')::uuid;
  v_thumb_key := v_res->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_thumb_key,
     jsonb_build_object('size', 100000, 'mimetype', 'image/jpeg'));

  SELECT count(*) INTO v_count FROM public.story_items;
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_item(
    v_rel, gen_random_uuid(), v_media_id, v_thumb_id2, 1080, 1920, NULL, 0);
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: finalize succeeded reusing an already-consumed intent: %', v_res;
  END IF;
  IF v_res->>'code' IS DISTINCT FROM 'UNAVAILABLE' THEN
    RAISE EXCEPTION 'wrong code for a consumed intent: %', v_res->>'code';
  END IF;
  RESET ROLE;
  SELECT count(*) - v_count INTO v_count FROM public.story_items;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a consumed-intent finalize call still wrote % row(s)', v_count;
  END IF;

  -- =================================================================
  -- Contract 6: both intents are consumed in the SAME transaction --
  -- failing the second (a stolen/foreign thumbnail intent, here) must
  -- leave the FIRST (a legitimately owned, valid media intent)
  -- unconsumed, so the caller can retry with a fresh, matching pair
  -- rather than having burned the good half for nothing.
  -- =================================================================
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  v_media_id2 := (v_res->>'intent_id')::uuid;
  v_media_key := v_res->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_media_key,
     jsonb_build_object('size', 1000000, 'mimetype', 'image/jpeg'));

  -- A thumbnail intent belonging to c402 -- the second lock will fail.
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c402'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_thumb_id2 := (v_res->>'intent_id')::uuid;
  v_thumb_key := v_res->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_thumb_key,
     jsonb_build_object('size', 100000, 'mimetype', 'image/jpeg'));

  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_item(
    v_rel, gen_random_uuid(), v_media_id2, v_thumb_id2, 1080, 1920, NULL, 0);
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: finalize succeeded with a foreign thumbnail intent: %', v_res;
  END IF;

  RESET ROLE;
  IF (SELECT used_at FROM public.story_media_upload_intents WHERE id = v_media_id2) IS NOT NULL THEN
    RAISE EXCEPTION
      'EXPLOIT: the FIRST (valid, own) intent was consumed even though the second check failed';
  END IF;
  -- The valid media intent must still work for a subsequent, correctly
  -- paired retry -- proves it was never partially spent.
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_thumb_id2 := (v_res->>'intent_id')::uuid;
  v_thumb_key := v_res->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_thumb_key,
     jsonb_build_object('size', 100000, 'mimetype', 'image/jpeg'));
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_item(
    v_rel, gen_random_uuid(), v_media_id2, v_thumb_id2, 1080, 1920, NULL, 0);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION
      'the previously-untouched media intent could not be used on a correct retry: %', v_res;
  END IF;

  -- =================================================================
  -- Contract 7: an object exceeding its intent's max_bytes -> refused,
  -- no row written. Thumbnail ceiling is 800KB (819200); write one byte
  -- over it.
  -- =================================================================
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  v_media_id2 := (v_res->>'intent_id')::uuid;
  v_media_key := v_res->>'storage_key';
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_thumb_id2 := (v_res->>'intent_id')::uuid;
  v_thumb_key := v_res->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_media_key,
     jsonb_build_object('size', 1000000, 'mimetype', 'image/jpeg')),
    ('story-media', v_thumb_key,
     -- 819201 bytes: exactly one over the 800KB (819200) thumbnail ceiling.
     jsonb_build_object('size', 819201, 'mimetype', 'image/jpeg'));

  SELECT count(*) INTO v_count FROM public.story_items;
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_item(
    v_rel, gen_random_uuid(), v_media_id2, v_thumb_id2, 1080, 1920, NULL, 0);
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: finalize accepted a thumbnail 1 byte over max_bytes: %', v_res;
  END IF;
  IF v_res->>'code' IS DISTINCT FROM 'UNAVAILABLE' THEN
    RAISE EXCEPTION 'wrong code for an oversized object: %', v_res->>'code';
  END IF;
  RESET ROLE;
  SELECT count(*) - v_count INTO v_count FROM public.story_items;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: an oversized-object finalize call still wrote % row(s)', v_count;
  END IF;
  -- An object exactly AT the ceiling must still be accepted -- proves
  -- this is a > check, not a mistakenly off-by-one >= check.
  RESET ROLE;
  UPDATE storage.objects SET metadata = jsonb_build_object('size', 819200, 'mimetype', 'image/jpeg')
   WHERE name = v_thumb_key;
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_item(
    v_rel, gen_random_uuid(), v_media_id2, v_thumb_id2, 1080, 1920, NULL, 0);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'finalize refused a thumbnail exactly AT max_bytes: %', v_res;
  END IF;

  -- =================================================================
  -- Signal bump: a successful finalize bumps story_change_signals for
  -- the relationship (needed by Task 6's realtime contract, verified
  -- here since this is the function that must call it).
  -- =================================================================
  RESET ROLE;
  SELECT count(*) INTO v_count FROM public.story_change_signals WHERE relationship_id = v_rel;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'EXPLOIT: create_story_item never bumped story_change_signals (rows=%)', v_count;
  END IF;

  RAISE NOTICE 'story_rpc_contracts (Task 5): all held';
END $$;

-- ---------------------------------------------------------------------
-- Grants: anon must not reach mark_story_viewed at all.
-- ---------------------------------------------------------------------
RESET ROLE;
DO $$ BEGIN
  IF has_function_privilege('anon',
    'public.mark_story_viewed(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: anon can execute mark_story_viewed';
  END IF;
  IF NOT has_function_privilege('authenticated',
    'public.mark_story_viewed(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated cannot execute mark_story_viewed';
  END IF;
END $$;

-- =======================================================================
-- Task 6: mark_story_viewed contracts (spec §3.4).
--
-- A hole here is not "a bad row" -- it is either the private viewed_at
-- timestamp leaking (story_views stays unreadable regardless -- this
-- function is the only writer), or the has_been_viewed indicator
-- becoming meaningless: an author who marks their own story seen, an
-- outsider recording a view into a couple's private state, or a
-- calendar-only replay of a months-old story silently flipping a
-- long-settled boolean. Every check below is written as one of the
-- four refusal rules from §3.4 that must hold, not a happy path.
-- =======================================================================
DO $$
DECLARE
  v_rel        uuid;
  v_res        jsonb;
  v_media_id   uuid;
  v_thumb_id   uuid;
  v_media_key  text;
  v_thumb_key  text;
  v_story_id   uuid;
  v_expired_id uuid;
  v_row        public.story_items%ROWTYPE;
  v_count      int;
  v_viewed_at1 timestamptz;
  v_viewed_at2 timestamptz;
  v_signal_before bigint;
  v_signal_after  bigint;
BEGIN
  RESET ROLE;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'stories';

  -- Fresh relationship: c401 author, c402 partner. c403 is the outsider
  -- (member of neither).
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000c401'::uuid,
          '00000000-0000-0000-0000-00000000c402'::uuid, 'active')
  RETURNING id INTO v_rel;

  DELETE FROM public.story_media_upload_intents
   WHERE requester_id IN ('00000000-0000-0000-0000-00000000c401'::uuid,
                           '00000000-0000-0000-0000-00000000c402'::uuid,
                           '00000000-0000-0000-0000-00000000c403'::uuid);

  -- Baseline story, authored by c401, finalized normally so it carries
  -- a real expires_at = created_at + 24h.
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  v_media_id := (v_res->>'intent_id')::uuid;
  v_media_key := v_res->>'storage_key';
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_thumb_id := (v_res->>'intent_id')::uuid;
  v_thumb_key := v_res->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_media_key,
     jsonb_build_object('size', 1000000, 'mimetype', 'image/jpeg')),
    ('story-media', v_thumb_key,
     jsonb_build_object('size', 100000, 'mimetype', 'image/jpeg'));
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_item(
    v_rel, gen_random_uuid(), v_media_id, v_thumb_id, 1080, 1920, NULL, 0);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'setup: baseline finalize was refused: %', v_res;
  END IF;
  v_story_id := (v_res->>'story_id')::uuid;

  RESET ROLE;
  SELECT version INTO v_signal_before
    FROM public.story_change_signals WHERE relationship_id = v_rel;

  -- =================================================================
  -- Contract 1: the AUTHOR marking their own story does NOT set
  -- has_been_viewed, and writes no story_views row. Without this
  -- check, an author reviewing their own reel would mark their own
  -- story seen and their "seen" indicator would become meaningless.
  -- =================================================================
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.mark_story_viewed(v_story_id);
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: the author was allowed to mark their own story viewed: %', v_res;
  END IF;

  RESET ROLE;
  SELECT * INTO v_row FROM public.story_items WHERE id = v_story_id;
  IF v_row.has_been_viewed IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: the author marking their own story set has_been_viewed';
  END IF;
  SELECT count(*) INTO v_count FROM public.story_views WHERE story_item_id = v_story_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: the author marking their own story wrote a story_views row';
  END IF;

  -- =================================================================
  -- Contract 4: an outsider (c403, not a member of the relationship) is
  -- refused and writes nothing.
  -- =================================================================
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c403'::uuid);
  v_res := public.mark_story_viewed(v_story_id);
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: an outsider was allowed to mark a story viewed: %', v_res;
  END IF;

  RESET ROLE;
  SELECT * INTO v_row FROM public.story_items WHERE id = v_story_id;
  IF v_row.has_been_viewed IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: an outsider''s call set has_been_viewed';
  END IF;
  SELECT count(*) INTO v_count FROM public.story_views WHERE story_item_id = v_story_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: an outsider''s call wrote a story_views row';
  END IF;

  -- =================================================================
  -- Contract 2: the PARTNER (c402) marking it sets has_been_viewed =
  -- true and writes exactly one story_views row. Also asserts the
  -- signal bumped exactly once for this call (contract 7).
  -- =================================================================
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c402'::uuid);
  v_res := public.mark_story_viewed(v_story_id);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'the partner''s first view was refused: %', v_res;
  END IF;

  RESET ROLE;
  SELECT * INTO v_row FROM public.story_items WHERE id = v_story_id;
  IF v_row.has_been_viewed IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: the partner''s first view did not set has_been_viewed';
  END IF;
  SELECT count(*) INTO v_count FROM public.story_views WHERE story_item_id = v_story_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'the partner''s first view should write exactly one story_views row, wrote %', v_count;
  END IF;
  SELECT viewed_at INTO v_viewed_at1
    FROM public.story_views
   WHERE story_item_id = v_story_id
     AND viewer_id = '00000000-0000-0000-0000-00000000c402'::uuid;
  IF v_viewed_at1 IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: the partner''s view row has no viewed_at';
  END IF;

  -- =================================================================
  -- Contract 7: a successful first view bumps story_change_signals.
  -- =================================================================
  SELECT version INTO v_signal_after
    FROM public.story_change_signals WHERE relationship_id = v_rel;
  IF v_signal_after IS DISTINCT FROM v_signal_before + 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: a successful first view did not bump story_change_signals by exactly 1 (before=%, after=%)',
      v_signal_before, v_signal_after;
  END IF;

  -- =================================================================
  -- Contract 3: a second call by the SAME viewer does not move
  -- viewed_at (ON CONFLICT DO NOTHING), and does not bump the signal
  -- again -- there is no new information to refetch for.
  -- =================================================================
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c402'::uuid);
  v_res := public.mark_story_viewed(v_story_id);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'a repeat view call by the same viewer was refused: %', v_res;
  END IF;

  RESET ROLE;
  SELECT count(*) INTO v_count FROM public.story_views WHERE story_item_id = v_story_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'EXPLOIT: a repeat view by the same viewer produced % story_views rows, expected 1', v_count;
  END IF;
  SELECT viewed_at INTO v_viewed_at2
    FROM public.story_views
   WHERE story_item_id = v_story_id
     AND viewer_id = '00000000-0000-0000-0000-00000000c402'::uuid;
  IF v_viewed_at2 IS DISTINCT FROM v_viewed_at1 THEN
    RAISE EXCEPTION
      'EXPLOIT: a repeat view by the same viewer moved viewed_at from % to %',
      v_viewed_at1, v_viewed_at2;
  END IF;
  SELECT version INTO v_signal_after
    FROM public.story_change_signals WHERE relationship_id = v_rel;
  IF v_signal_after IS DISTINCT FROM v_signal_before + 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: a repeat view by the same viewer bumped the signal again (before=%, after=%)',
      v_signal_before, v_signal_after;
  END IF;

  -- =================================================================
  -- Contract 5: a DELETED story is refused, even for the rightful
  -- partner, and writes nothing.
  -- =================================================================
  RESET ROLE;
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  v_media_id := (v_res->>'intent_id')::uuid;
  v_media_key := v_res->>'storage_key';
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_thumb_id := (v_res->>'intent_id')::uuid;
  v_thumb_key := v_res->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_media_key,
     jsonb_build_object('size', 1000000, 'mimetype', 'image/jpeg')),
    ('story-media', v_thumb_key,
     jsonb_build_object('size', 100000, 'mimetype', 'image/jpeg'));
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_item(
    v_rel, gen_random_uuid(), v_media_id, v_thumb_id, 1080, 1920, NULL, 0);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'setup: deleted-story fixture finalize was refused: %', v_res;
  END IF;
  v_story_id := (v_res->>'story_id')::uuid;

  -- Soft-delete it directly (delete_story_item is a later task; stamp
  -- deleted_at ourselves as the definer role to build the fixture).
  RESET ROLE;
  UPDATE public.story_items SET deleted_at = now() WHERE id = v_story_id;

  SELECT count(*) INTO v_count FROM public.story_views WHERE story_item_id = v_story_id;
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c402'::uuid);
  v_res := public.mark_story_viewed(v_story_id);
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: a view was recorded on a deleted story: %', v_res;
  END IF;
  RESET ROLE;
  SELECT count(*) - v_count INTO v_count FROM public.story_views WHERE story_item_id = v_story_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: marking a deleted story viewed wrote % story_views row(s)', v_count;
  END IF;
  SELECT has_been_viewed INTO v_row.has_been_viewed
    FROM public.story_items WHERE id = v_story_id;
  IF v_row.has_been_viewed IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: marking a deleted story viewed set has_been_viewed';
  END IF;

  -- =================================================================
  -- Contract 6: an EXPIRED story is refused. Calendar views must not
  -- flip a long-settled indicator (§3.4) -- an expired-but-undeleted
  -- story opened from the calendar must not record a view.
  -- =================================================================
  RESET ROLE;
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  v_media_id := (v_res->>'intent_id')::uuid;
  v_media_key := v_res->>'storage_key';
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_thumb_id := (v_res->>'intent_id')::uuid;
  v_thumb_key := v_res->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_media_key,
     jsonb_build_object('size', 1000000, 'mimetype', 'image/jpeg')),
    ('story-media', v_thumb_key,
     jsonb_build_object('size', 100000, 'mimetype', 'image/jpeg'));
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_item(
    v_rel, gen_random_uuid(), v_media_id, v_thumb_id, 1080, 1920, NULL, 0);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'setup: expired-story fixture finalize was refused: %', v_res;
  END IF;
  v_expired_id := (v_res->>'story_id')::uuid;

  -- Force it into the past directly, as the definer role -- this is
  -- the calendar scenario: a story whose 24h reel window has passed but
  -- which is still very much undeleted (it lives on in the calendar).
  RESET ROLE;
  UPDATE public.story_items
     SET created_at = now() - interval '48 hours',
         expires_at = now() - interval '24 hours'
   WHERE id = v_expired_id;

  SELECT version INTO v_signal_before
    FROM public.story_change_signals WHERE relationship_id = v_rel;
  SELECT count(*) INTO v_count FROM public.story_views WHERE story_item_id = v_expired_id;
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c402'::uuid);
  v_res := public.mark_story_viewed(v_expired_id);
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: a view was recorded on an expired story opened from the calendar: %', v_res;
  END IF;
  RESET ROLE;
  SELECT count(*) - v_count INTO v_count FROM public.story_views WHERE story_item_id = v_expired_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: marking an expired story viewed wrote % story_views row(s)', v_count;
  END IF;
  SELECT has_been_viewed INTO v_row.has_been_viewed
    FROM public.story_items WHERE id = v_expired_id;
  IF v_row.has_been_viewed IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: marking an expired story viewed set has_been_viewed';
  END IF;
  SELECT version INTO v_signal_after
    FROM public.story_change_signals WHERE relationship_id = v_rel;
  IF v_signal_after IS DISTINCT FROM v_signal_before THEN
    RAISE EXCEPTION
      'EXPLOIT: a refused expired-story view still bumped the signal (before=%, after=%)',
      v_signal_before, v_signal_after;
  END IF;

  RAISE NOTICE 'story_rpc_contracts (Task 6): all held';
END $$;

-- ---------------------------------------------------------------------
-- Grants: anon must not reach delete_story_item at all.
-- ---------------------------------------------------------------------
RESET ROLE;
DO $$ BEGIN
  IF has_function_privilege('anon',
    'public.delete_story_item(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: anon can execute delete_story_item';
  END IF;
  IF NOT has_function_privilege('authenticated',
    'public.delete_story_item(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated cannot execute delete_story_item';
  END IF;
  -- queue_story_media_deletion is an internal helper: every caller
  -- (delete_story_item, the story_items hard-delete trigger, Task 9's
  -- future worker) is itself a SECURITY DEFINER function. It must never
  -- be directly callable -- it enqueues whatever (bucket, key) it is
  -- handed with no ownership check of its own.
  IF has_function_privilege('authenticated',
    'public.queue_story_media_deletion(text,text,timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated can execute queue_story_media_deletion directly';
  END IF;
END $$;

-- =======================================================================
-- Task 7: delete_story_item, queue not_before, and cascades
-- (spec §3.3, §4.5).
--
-- A hole here is not "a bad row" -- it is a tombstone committing without
-- its cleanup work (an object leaked in a private bucket forever), a
-- non-author erasing someone else's retained media, an author LOSING the
-- right to delete their own story just because the relationship ended,
-- or a live player's signed archive URL breaking mid-playback because
-- the delay window was skipped. Every check below is written as one of
-- those failure modes that must not happen, not a happy path that must
-- pass.
-- =======================================================================
DO $$
DECLARE
  v_rel          uuid;
  v_ended_rel    uuid;
  v_res          jsonb;
  v_count        int;
  v_media_id     uuid;
  v_thumb_id     uuid;
  v_media_key    text;
  v_thumb_key    text;
  v_archive_key  text;
  v_story_id     uuid;
  v_story_id2    uuid;
  v_row          public.story_items%ROWTYPE;
  v_queue_row    public.media_deletion_queue%ROWTYPE;
  v_signal_before bigint;
  v_signal_after  bigint;
  v_deleted_at1  timestamptz;
BEGIN
  RESET ROLE;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'stories';

  DELETE FROM public.story_media_upload_intents
   WHERE requester_id IN ('00000000-0000-0000-0000-00000000c401'::uuid,
                           '00000000-0000-0000-0000-00000000c402'::uuid,
                           '00000000-0000-0000-0000-00000000c403'::uuid);

  -- Fresh relationship: c401 author, c402 partner. c403 is the outsider.
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000c401'::uuid,
          '00000000-0000-0000-0000-00000000c402'::uuid, 'active')
  RETURNING id INTO v_rel;

  -- Helper macro (inline, repeated): issue media+thumbnail intents for
  -- c401 in v_rel, stamp storage.objects, finalize, return story id.

  -- =================================================================
  -- Baseline story #1, used by contracts 1, 2, 4 and 5.
  -- =================================================================
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  v_media_id := (v_res->>'intent_id')::uuid;
  v_media_key := v_res->>'storage_key';
  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  v_thumb_id := (v_res->>'intent_id')::uuid;
  v_thumb_key := v_res->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', v_media_key,
     jsonb_build_object('size', 1000000, 'mimetype', 'image/jpeg')),
    ('story-media', v_thumb_key,
     jsonb_build_object('size', 100000, 'mimetype', 'image/jpeg'));
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_item(
    v_rel, gen_random_uuid(), v_media_id, v_thumb_id, 1080, 1920, NULL, 0);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'setup: baseline finalize was refused: %', v_res;
  END IF;
  v_story_id := (v_res->>'story_id')::uuid;
  v_archive_key := 'story-archive/' || v_story_id::text || '.jpg';

  RESET ROLE;
  SELECT version INTO v_signal_before
    FROM public.story_change_signals WHERE relationship_id = v_rel;

  -- =================================================================
  -- Contract 1: a non-author (c402, the partner -- a member, but not
  -- the author) is refused and the row is untouched.
  -- =================================================================
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c402'::uuid);
  v_res := public.delete_story_item(v_story_id);
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: a non-author partner was allowed to delete the story: %', v_res;
  END IF;

  RESET ROLE;
  SELECT * INTO v_row FROM public.story_items WHERE id = v_story_id;
  IF v_row.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: a refused delete still stamped deleted_at';
  END IF;
  SELECT count(*) INTO v_count FROM public.media_deletion_queue
   WHERE object_name IN (v_media_key, v_thumb_key, v_archive_key);
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a refused delete still enqueued % row(s)', v_count;
  END IF;

  -- Outsider (c403, not a relationship member at all) is refused the
  -- same way -- never an existence oracle distinguishing "not a member"
  -- from "not the author".
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c403'::uuid);
  v_res := public.delete_story_item(v_story_id);
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: a total outsider was allowed to delete the story: %', v_res;
  END IF;
  RESET ROLE;
  SELECT * INTO v_row FROM public.story_items WHERE id = v_story_id;
  IF v_row.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: an outsider''s refused delete still stamped deleted_at';
  END IF;

  -- =================================================================
  -- Contract 2: the author stamps deleted_at AND enqueues THREE keys
  -- (media, thumbnail, archive) in the same transaction, and bumps the
  -- change signal.
  -- =================================================================
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.delete_story_item(v_story_id);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'the author''s delete was refused: %', v_res;
  END IF;
  IF (v_res->>'deleted')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'delete_story_item did not report deleted=true: %', v_res;
  END IF;

  RESET ROLE;
  SELECT * INTO v_row FROM public.story_items WHERE id = v_story_id;
  IF v_row.deleted_at IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: the author''s delete did not stamp deleted_at';
  END IF;
  v_deleted_at1 := v_row.deleted_at;

  SELECT count(*) INTO v_count FROM public.media_deletion_queue
   WHERE object_name IN (v_media_key, v_thumb_key, v_archive_key)
     AND bucket_id = 'story-media'
     AND deleted_at IS NULL;
  IF v_count <> 3 THEN
    RAISE EXCEPTION
      'EXPLOIT: expected exactly 3 enqueued keys (media, thumbnail, archive), got %', v_count;
  END IF;

  SELECT version INTO v_signal_after
    FROM public.story_change_signals WHERE relationship_id = v_rel;
  IF v_signal_after IS DISTINCT FROM v_signal_before + 1 THEN
    RAISE EXCEPTION
      'EXPLOIT: delete_story_item did not bump story_change_signals by exactly 1 (before=%, after=%)',
      v_signal_before, v_signal_after;
  END IF;

  -- =================================================================
  -- Contract 5: the ARCHIVE key's queue entry carries
  -- not_before >= now() + 600s. media_key/thumbnail_key do NOT need
  -- the delay.
  -- =================================================================
  SELECT * INTO v_queue_row FROM public.media_deletion_queue
   WHERE object_name = v_archive_key AND bucket_id = 'story-media';
  IF v_queue_row.not_before IS NULL
     OR v_queue_row.not_before < now() + interval '600 seconds'
  THEN
    RAISE EXCEPTION
      'EXPLOIT: archive key not_before (%) is not at least 600s out from now (%)',
      v_queue_row.not_before, now();
  END IF;

  SELECT * INTO v_queue_row FROM public.media_deletion_queue
   WHERE object_name = v_media_key AND bucket_id = 'story-media';
  IF v_queue_row.not_before > now() + interval '5 seconds' THEN
    RAISE EXCEPTION
      'EXPLOIT: media key not_before (%) was delayed like the archive key -- it should not be',
      v_queue_row.not_before;
  END IF;
  SELECT * INTO v_queue_row FROM public.media_deletion_queue
   WHERE object_name = v_thumb_key AND bucket_id = 'story-media';
  IF v_queue_row.not_before > now() + interval '5 seconds' THEN
    RAISE EXCEPTION
      'EXPLOIT: thumbnail key not_before (%) was delayed like the archive key -- it should not be',
      v_queue_row.not_before;
  END IF;

  -- =================================================================
  -- Contract 4: deleting twice returns success and RE-ARMS an
  -- already-completed queue entry (deleted_at set back to NULL) rather
  -- than silently doing nothing or leaving it stamped complete.
  --
  -- Simulate the drain having completed all three keys, then delete
  -- again.
  -- =================================================================
  RESET ROLE;
  UPDATE public.media_deletion_queue
     SET deleted_at = now()
   WHERE object_name IN (v_media_key, v_thumb_key, v_archive_key)
     AND bucket_id = 'story-media';
  SELECT count(*) INTO v_count FROM public.media_deletion_queue
   WHERE object_name IN (v_media_key, v_thumb_key, v_archive_key)
     AND bucket_id = 'story-media'
     AND deleted_at IS NOT NULL;
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'test setup failed: could not mark all 3 queue rows complete (got %)', v_count;
  END IF;

  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.delete_story_item(v_story_id);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: deleting an already-deleted story was refused instead of succeeding: %', v_res;
  END IF;
  IF (v_res->>'deleted')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'a repeat delete did not report deleted=true: %', v_res;
  END IF;

  RESET ROLE;
  -- deleted_at on the STORY row must not have moved (it is the first-
  -- deletion timestamp, not a "last delete call" timestamp).
  SELECT * INTO v_row FROM public.story_items WHERE id = v_story_id;
  IF v_row.deleted_at IS DISTINCT FROM v_deleted_at1 THEN
    RAISE EXCEPTION
      'EXPLOIT: a repeat delete moved the story''s deleted_at from % to %',
      v_deleted_at1, v_row.deleted_at;
  END IF;

  -- All three queue rows must be RE-ARMED: deleted_at back to NULL, no
  -- duplicate rows created (still exactly 3, thanks to the queue's
  -- UNIQUE (bucket_id, object_name)).
  SELECT count(*) INTO v_count FROM public.media_deletion_queue
   WHERE object_name IN (v_media_key, v_thumb_key, v_archive_key)
     AND bucket_id = 'story-media';
  IF v_count <> 3 THEN
    RAISE EXCEPTION
      'EXPLOIT: a repeat delete produced % queue rows for 3 keys -- duplicates instead of re-arming',
      v_count;
  END IF;
  SELECT count(*) INTO v_count FROM public.media_deletion_queue
   WHERE object_name IN (v_media_key, v_thumb_key, v_archive_key)
     AND bucket_id = 'story-media'
     AND deleted_at IS NULL;
  IF v_count <> 3 THEN
    RAISE EXCEPTION
      'EXPLOIT: a repeat delete did not re-arm all 3 already-completed queue rows (only % re-armed)',
      v_count;
  END IF;

  -- The re-armed archive key must still carry its >= 600s delay.
  SELECT * INTO v_queue_row FROM public.media_deletion_queue
   WHERE object_name = v_archive_key AND bucket_id = 'story-media';
  IF v_queue_row.not_before < now() + interval '600 seconds' THEN
    RAISE EXCEPTION
      'EXPLOIT: re-arming the archive key lost its >= 600s not_before delay (got %)',
      v_queue_row.not_before;
  END IF;

  -- =================================================================
  -- Contract 3: deleting from an ENDED relationship SUCCEEDS. An
  -- author never loses the right to remove their own retained media
  -- (§3.3) -- deletion is NOT gated on story_relationship_is_open.
  -- =================================================================
  RESET ROLE;
  INSERT INTO public.relationships(user_a, user_b, status, ended_at)
  VALUES ('00000000-0000-0000-0000-00000000c401'::uuid,
          '00000000-0000-0000-0000-00000000c402'::uuid, 'ended', now())
  RETURNING id INTO v_ended_rel;

  DELETE FROM public.story_media_upload_intents
   WHERE requester_id = '00000000-0000-0000-0000-00000000c401'::uuid;
  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.create_story_upload_intent(v_ended_rel, 'media', 'image', 'image/jpeg');
  -- The intent-creation path itself gates on an OPEN relationship
  -- (§4.2), so it will legitimately refuse here -- that is Task 4's
  -- contract, not this one's. Insert the story row directly, as the
  -- definer role, to build a fixture that is already-finalized in an
  -- ended relationship (exactly what a story that existed BEFORE the
  -- relationship ended looks like once the relationship later ends).
  RESET ROLE;
  INSERT INTO public.story_items (
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at
  ) VALUES (
    gen_random_uuid(), v_ended_rel, '00000000-0000-0000-0000-00000000c401'::uuid,
    'image', 'story-media/ended-rel/media-key', 'story-media/ended-rel/thumb-key',
    1080, 1920, current_date, now(), now() + interval '24 hours'
  ) RETURNING id INTO v_story_id2;

  IF NOT public.story_relationship_is_open(v_ended_rel, '00000000-0000-0000-0000-00000000c401'::uuid) THEN
    NULL; -- Confirms the fixture is genuinely ended/closed, as expected.
  ELSE
    RAISE EXCEPTION 'test construction error: v_ended_rel is not actually closed';
  END IF;

  PERFORM public.test_set_story_rpc_auth('00000000-0000-0000-0000-00000000c401'::uuid);
  v_res := public.delete_story_item(v_story_id2);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION
      'EXPLOIT: the author was refused deletion from an ENDED relationship (%): %',
      v_ended_rel, v_res;
  END IF;

  RESET ROLE;
  SELECT * INTO v_row FROM public.story_items WHERE id = v_story_id2;
  IF v_row.deleted_at IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: deletion from an ended relationship did not stamp deleted_at';
  END IF;
  SELECT count(*) INTO v_count FROM public.media_deletion_queue
   WHERE object_name IN ('story-media/ended-rel/media-key', 'story-media/ended-rel/thumb-key',
                          'story-archive/' || v_story_id2::text || '.jpg');
  IF v_count <> 3 THEN
    RAISE EXCEPTION
      'EXPLOIT: deletion from an ended relationship enqueued % keys, expected 3', v_count;
  END IF;

  -- =================================================================
  -- Contract 6: relationship deletion cascades every story AND
  -- enqueues each one's keys (the BEFORE DELETE trigger on
  -- story_items, since ON DELETE CASCADE alone never calls
  -- delete_story_item).
  -- =================================================================
  RESET ROLE;
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000c401'::uuid,
          '00000000-0000-0000-0000-00000000c403'::uuid, 'active')
  RETURNING id INTO v_ended_rel; -- reused variable, fresh relationship

  INSERT INTO public.story_items (
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height,
    occurred_on, created_at, expires_at
  ) VALUES
    (gen_random_uuid(), v_ended_rel, '00000000-0000-0000-0000-00000000c401'::uuid,
     'image', 'story-media/cascade/media-1', 'story-media/cascade/thumb-1',
     1080, 1920, current_date, now(), now() + interval '24 hours'),
    (gen_random_uuid(), v_ended_rel, '00000000-0000-0000-0000-00000000c403'::uuid,
     'image', 'story-media/cascade/media-2', 'story-media/cascade/thumb-2',
     1080, 1920, current_date, now(), now() + interval '24 hours');
  -- Two rows inserted; ids are not needed by name below, only their
  -- known media/thumbnail keys and the archive-key pattern.

  SELECT count(*) INTO v_count FROM public.story_items WHERE relationship_id = v_ended_rel;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'test construction error: expected 2 cascade fixture stories, got %', v_count;
  END IF;

  DELETE FROM public.relationships WHERE id = v_ended_rel;

  SELECT count(*) INTO v_count FROM public.story_items WHERE relationship_id = v_ended_rel;
  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'test construction error: story_items rows survived the relationship DELETE (ON DELETE CASCADE broken?)';
  END IF;

  SELECT count(*) INTO v_count FROM public.media_deletion_queue
   WHERE bucket_id = 'story-media'
     AND object_name IN (
       'story-media/cascade/media-1', 'story-media/cascade/thumb-1',
       'story-media/cascade/media-2', 'story-media/cascade/thumb-2'
     )
     AND deleted_at IS NULL;
  IF v_count <> 4 THEN
    RAISE EXCEPTION
      'EXPLOIT: relationship deletion cascaded stories away without enqueueing their media/thumbnail keys (got % of 4)',
      v_count;
  END IF;

  -- Both stories' archive keys too -- need the ids the cascade just
  -- destroyed; re-derive them from the media_deletion_queue object
  -- names is not possible (archive key is story-id-derived, not
  -- media-key-derived), so assert by counting archive-shaped keys
  -- enqueued for THIS relationship's window instead: any two
  -- 'story-archive/%.jpg' rows inserted since this block started that
  -- carry the >= 600s delay.
  SELECT count(*) INTO v_count FROM public.media_deletion_queue
   WHERE bucket_id = 'story-media'
     AND object_name LIKE 'story-archive/%.jpg'
     AND not_before >= now() + interval '590 seconds'
     AND requested_at > now() - interval '1 minute';
  IF v_count < 2 THEN
    RAISE EXCEPTION
      'EXPLOIT: relationship deletion cascade did not enqueue an archive key (with the >= 600s delay) for each story (found %, expected >= 2)',
      v_count;
  END IF;

  RAISE NOTICE 'story_rpc_contracts (Task 7): all held';
END $$;

RESET ROLE;
DROP FUNCTION IF EXISTS public.test_set_story_rpc_auth(uuid);
ROLLBACK;
