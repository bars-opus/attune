-- supabase/tests/story_capture_date_contracts.sql
--
-- Stories Wave 5, Task 5 (review 04 #3, #13): occurred_on is the poster's
-- civil date at CAPTURE time (clamped to the last 7 days, never the future),
-- computed without the session time zone. The reel window still runs 24h
-- from posting. Fix round 1: the capture's age is taken on the phone's own
-- clock (p_client_now), so a phone clock that is off cannot move the date,
-- and the date never precedes the relationship's start.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000935a1'), ('00000000-0000-0000-0000-0000000935b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000935a1', '+15550935001', 'CA'),
  ('00000000-0000-0000-0000-0000000935b2', '+15550935002', 'CB')
ON CONFLICT (id) DO NOTHING;
UPDATE public.feature_flags SET enabled = true WHERE key = 'stories';
-- Started 60 days ago, so only the 7-day clamp bites in C1-C7 (C8 moves it).
INSERT INTO public.relationships (id, user_a, user_b, status, created_at, invite_accepted_at) VALUES
  ('00000000-0000-0000-0000-0000000935e1', '00000000-0000-0000-0000-0000000935a1', '00000000-0000-0000-0000-0000000935b2', 'active',
   now() - interval '60 days', now() - interval '60 days');

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- Posts one image story for A through the real RPCs; returns the row.
CREATE FUNCTION pg_temp.post(p_offset int, p_captured timestamptz, p_client uuid DEFAULT gen_random_uuid(),
                              p_client_now timestamptz DEFAULT NULL)
RETURNS public.story_items LANGUAGE plpgsql AS $$
DECLARE r jsonb; mid uuid; mkey text; tid uuid; tkey text; v public.story_items;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000935a1');
  r := public.create_story_upload_intent('00000000-0000-0000-0000-0000000935e1', 'media', 'image', 'image/jpeg');
  mid := (r->>'intent_id')::uuid; mkey := r->>'storage_key';
  r := public.create_story_upload_intent('00000000-0000-0000-0000-0000000935e1', 'thumbnail', 'image', 'image/jpeg');
  tid := (r->>'intent_id')::uuid; tkey := r->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', mkey, jsonb_build_object('size', 1000, 'mimetype', 'image/jpeg')),
    ('story-media', tkey, jsonb_build_object('size', 100, 'mimetype', 'image/jpeg'));
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000935a1');
  r := public.create_story_item('00000000-0000-0000-0000-0000000935e1', p_client, mid, tid,
                                1080, 1920, NULL, p_offset, NULL, p_captured, p_client_now);
  RESET ROLE;
  IF (r->>'error') IS NOT DISTINCT FROM 'true' THEN RAISE EXCEPTION 'setup: finalize refused: %', r; END IF;
  SELECT * INTO v FROM public.story_items WHERE id = (r->>'story_id')::uuid;
  RETURN v;
END $$;

-- Dates the test expects, computed in UTC on purpose.
CREATE FUNCTION pg_temp.utc_today() RETURNS date LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'UTC')::date $$;
-- 23:59 UTC yesterday: always between 1 minute and 24 hours ago.
CREATE FUNCTION pg_temp.late_yesterday() RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT ((now() AT TIME ZONE 'UTC')::date::timestamp - interval '1 minute') AT TIME ZONE 'UTC' $$;

-- C1. The capture's date, not the posting's; the window still runs from posting.
DO $$
DECLARE v public.story_items;
BEGIN
  v := pg_temp.post(0, pg_temp.late_yesterday());
  IF v.occurred_on IS DISTINCT FROM pg_temp.utc_today() - 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: captured yesterday 23:59, filed on % (want %)', v.occurred_on, pg_temp.utc_today() - 1;
  END IF;
  IF v.created_at IS DISTINCT FROM now() OR v.expires_at IS DISTINCT FROM now() + interval '24 hours' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reel window moved: created % expires %', v.created_at, v.expires_at;
  END IF;
END $$;

-- C2. Clamps: a month back files 7 days back; the future files today; NULL is now.
DO $$
DECLARE v public.story_items;
BEGIN
  v := pg_temp.post(0, now() - interval '30 days');
  IF v.occurred_on IS DISTINCT FROM ((now() - interval '7 days') AT TIME ZONE 'UTC')::date THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 30-day-old capture filed on %', v.occurred_on;
  END IF;
  v := pg_temp.post(0, now() + interval '2 days');
  IF v.occurred_on IS DISTINCT FROM pg_temp.utc_today() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a future capture filed on %', v.occurred_on;
  END IF;
  v := pg_temp.post(0, NULL);
  IF v.occurred_on IS DISTINCT FROM pg_temp.utc_today() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an old client (no capture time) filed on %', v.occurred_on;
  END IF;
END $$;

-- C3. The offset still applies, to the capture instant: +60 at 23:59 UTC is tomorrow-of-that-day.
DO $$
DECLARE v public.story_items;
BEGIN
  v := pg_temp.post(60, pg_temp.late_yesterday());
  IF v.occurred_on IS DISTINCT FROM pg_temp.utc_today() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: +60 min at 23:59 UTC filed on % (want %)', v.occurred_on, pg_temp.utc_today();
  END IF;
END $$;

-- C4. The session time zone changes nothing (04 #13).
SET LOCAL timezone = 'Asia/Tokyo';
DO $$
DECLARE v public.story_items;
BEGIN
  v := pg_temp.post(0, pg_temp.late_yesterday());
  IF v.occurred_on IS DISTINCT FROM pg_temp.utc_today() - 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under Asia/Tokyo the same capture filed on %', v.occurred_on;
  END IF;
  v := pg_temp.post(0, NULL);
  IF v.occurred_on IS DISTINCT FROM pg_temp.utc_today() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under Asia/Tokyo "now" at offset 0 filed on %', v.occurred_on;
  END IF;
END $$;
SET LOCAL timezone = 'America/Los_Angeles';
DO $$
DECLARE v public.story_items;
BEGIN
  v := pg_temp.post(0, pg_temp.late_yesterday());
  IF v.occurred_on IS DISTINCT FROM pg_temp.utc_today() - 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under America/Los_Angeles the same capture filed on %', v.occurred_on;
  END IF;
END $$;
RESET timezone;

-- C5. A replay with a different capture time returns the first story unchanged.
DO $$
DECLARE v1 public.story_items; v2 public.story_items; c uuid := gen_random_uuid();
BEGIN
  v1 := pg_temp.post(0, pg_temp.late_yesterday(), c);
  v2 := pg_temp.post(0, now(), c);
  IF v2.id IS DISTINCT FROM v1.id OR v2.occurred_on IS DISTINCT FROM v1.occurred_on THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay moved the story (% -> %)', v1.occurred_on, v2.occurred_on;
  END IF;
END $$;

-- C6. Signatures and grants: one finalize, no overload (PGRST203), core server-only.
DO $$
BEGIN
  IF to_regprocedure('public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb,timestamptz)') IS NOT NULL
     OR to_regprocedure('public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb)') IS NOT NULL
     OR to_regprocedure('public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int)') IS NOT NULL
     OR to_regprocedure('public.create_story_item_core(uuid,uuid,uuid,uuid,int,int,int,int,timestamptz)') IS NOT NULL
     OR to_regprocedure('public.create_story_item_core(uuid,uuid,uuid,uuid,int,int,int,int)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an older finalize overload is still there';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb,timestamptz,timestamptz)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb,timestamptz,timestamptz)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.create_story_item_core(uuid,uuid,uuid,uuid,int,int,int,int,timestamptz,timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: finalize grants are wrong';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE oid IN (
               'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb,timestamptz,timestamptz)'::regprocedure,
               'public.create_story_item_core(uuid,uuid,uuid,uuid,int,int,int,int,timestamptz,timestamptz)'::regprocedure)
             AND NOT ('search_path=""' = ANY (coalesce(proconfig, '{}')))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: finalize does not pin search_path';
  END IF;
END $$;

-- C7. A phone clock 3 days behind (fix round 1, review #1): the capture is a
-- minute old on the phone's own clock, so it files today, not 3 days back.
-- A clock error far beyond the window, or a nonsense clock, files at most
-- 7 days back and never errors.
DO $$
DECLARE v public.story_items;
BEGIN
  v := pg_temp.post(0, now() - interval '3 days' - interval '1 minute', gen_random_uuid(), now() - interval '3 days');
  IF v.occurred_on IS DISTINCT FROM ((now() - interval '1 minute') AT TIME ZONE 'UTC')::date THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a phone 3 days behind filed on % (want %)', v.occurred_on,
      ((now() - interval '1 minute') AT TIME ZONE 'UTC')::date;
  END IF;
  v := pg_temp.post(0, now() + interval '5 years' - interval '1 minute', gen_random_uuid(), now() + interval '5 years');
  IF v.occurred_on IS DISTINCT FROM ((now() - interval '1 minute') AT TIME ZONE 'UTC')::date THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a phone 5 years ahead filed on %', v.occurred_on;
  END IF;
  v := pg_temp.post(0, now() - interval '30 days', gen_random_uuid(), now());
  IF v.occurred_on IS DISTINCT FROM ((now() - interval '7 days') AT TIME ZONE 'UTC')::date THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 30-day-old capture (phone clock right) filed on %', v.occurred_on;
  END IF;
  v := pg_temp.post(0, '-infinity', gen_random_uuid(), 'infinity');
  IF v.occurred_on IS DISTINCT FROM ((now() - interval '7 days') AT TIME ZONE 'UTC')::date
     AND v.occurred_on IS DISTINCT FROM pg_temp.utc_today() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an infinite phone clock filed on %', v.occurred_on;
  END IF;
  v := pg_temp.post(0, '4713-01-01 BC', gen_random_uuid(), '294000-01-01');
  IF v.occurred_on < ((now() - interval '7 days') AT TIME ZONE 'UTC')::date OR v.occurred_on > pg_temp.utc_today() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an out-of-range phone clock filed on %', v.occurred_on;
  END IF;
END $$;

-- C8. Never before the relationship began (fix round 1, review #4): started
-- 2 days ago, a capture 5 days old files on the start date.
UPDATE public.relationships
   SET created_at = now() - interval '2 days', invite_accepted_at = now() - interval '2 days'
 WHERE id = '00000000-0000-0000-0000-0000000935e1';
DO $$
DECLARE v public.story_items;
BEGIN
  v := pg_temp.post(0, now() - interval '5 days', gen_random_uuid(), now());
  IF v.occurred_on IS DISTINCT FROM ((now() - interval '2 days') AT TIME ZONE 'UTC')::date THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a capture before the relationship began filed on % (want %)', v.occurred_on,
      ((now() - interval '2 days') AT TIME ZONE 'UTC')::date;
  END IF;
  v := pg_temp.post(0, now() - interval '5 days', gen_random_uuid());
  IF v.occurred_on IS DISTINCT FROM ((now() - interval '2 days') AT TIME ZONE 'UTC')::date THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an older client''s capture before the relationship began filed on %', v.occurred_on;
  END IF;
END $$;

ROLLBACK;
