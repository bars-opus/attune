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

RESET ROLE;
DROP FUNCTION IF EXISTS public.test_set_story_rpc_auth(uuid);
ROLLBACK;
