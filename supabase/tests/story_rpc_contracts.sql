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
  IF v_res->>'code' <> 'FORBIDDEN' THEN
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
  IF v_res->>'code' <> 'UNAVAILABLE' THEN
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
  IF (v_res->>'error') IS DISTINCT FROM 'true' OR v_res->>'code' <> 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'EXPLOIT: unlisted object_kind accepted: %', v_res;
  END IF;

  v_res := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/png');
  IF (v_res->>'error') IS DISTINCT FROM 'true' OR v_res->>'code' <> 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'EXPLOIT: image/png accepted for main media: %', v_res;
  END IF;

  v_res := public.create_story_upload_intent(v_rel, 'media', 'video', 'video/quicktime');
  IF (v_res->>'error') IS DISTINCT FROM 'true' OR v_res->>'code' <> 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'EXPLOIT: video/quicktime accepted for main media: %', v_res;
  END IF;

  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'video/mp4');
  IF (v_res->>'error') IS DISTINCT FROM 'true' OR v_res->>'code' <> 'INVALID_INPUT' THEN
    RAISE EXCEPTION 'EXPLOIT: video/mp4 accepted for a thumbnail: %', v_res;
  END IF;

  v_res := public.create_story_upload_intent(v_rel, 'thumbnail', 'video', 'image/jpeg');
  IF (v_res->>'error') IS DISTINCT FROM 'true' OR v_res->>'code' <> 'INVALID_INPUT' THEN
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
  IF v_res->>'code' <> 'RATE_LIMITED' THEN
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
  IF v_res->>'code' <> 'RATE_LIMITED' THEN
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
  IF v_res->>'code' <> 'UNAVAILABLE' THEN
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
  IF v_res->>'code' <> 'UNAVAILABLE' THEN
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
  IF v_res->>'code' <> 'UNAVAILABLE' THEN
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

RESET ROLE;
DROP FUNCTION IF EXISTS public.test_set_story_rpc_auth(uuid);
ROLLBACK;
