-- supabase/tests/story_export_contracts.sql
--
-- Stories Wave 5, Task 11 (review 04 #1, #12; 07b V8): a person's own
-- stories come first in the media walk, so the part cap can no longer leave
-- them out behind chat media; every story file has an extension; a job that
-- was mid-walk at deploy starts again. Place pins still go at an ending
-- (sync-audit C-2, kept by controller ruling over 04 #19), so an ended
-- space's export carries its stories without a place.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000933a1'), ('00000000-0000-0000-0000-0000000933b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000933a1', '+15550933001', 'Esi'),
  ('00000000-0000-0000-0000-0000000933b2', '+15550933002', 'Yaw')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('00000000-0000-0000-0000-0000000933e1', '00000000-0000-0000-0000-0000000933a1', '00000000-0000-0000-0000-0000000933b2',
   'active', CURRENT_DATE - 100, now() - interval '100 days', now());

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

SET LOCAL session_replication_role = replica;
-- Esi: a video story and a fresh photo story (keys end in -media), an
-- archived photo (story-archive/<id>.jpg), and two chat photos whose bucket
-- sorts first by name.
INSERT INTO public.story_items (id, client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, duration_ms, occurred_on, created_at, expires_at)
VALUES
  ('00000000-0000-0000-0000-000000933001', gen_random_uuid(), '00000000-0000-0000-0000-0000000933e1', '00000000-0000-0000-0000-0000000933a1',
   'video', 'story-media/e933/v-media', 'story-media/e933/v-thumbnail', 1080, 1920, 5000, CURRENT_DATE, now(), now() + interval '24 hours'),
  ('00000000-0000-0000-0000-000000933002', gen_random_uuid(), '00000000-0000-0000-0000-0000000933e1', '00000000-0000-0000-0000-0000000933a1',
   'image', 'story-media/e933/p-media', 'story-media/e933/p-thumbnail', 1080, 1920, NULL, CURRENT_DATE, now(), now() + interval '24 hours'),
  ('00000000-0000-0000-0000-000000933003', gen_random_uuid(), '00000000-0000-0000-0000-0000000933e1', '00000000-0000-0000-0000-0000000933a1',
   'image', 'story-archive/00000000-0000-0000-0000-000000933003.jpg', 'story-media/e933/a-thumbnail', 1080, 1920, NULL,
   CURRENT_DATE - 5, now() - interval '5 days', now() - interval '4 days');
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, created_at, media_url, media_type, is_view_once)
VALUES
  ('00000000-0000-0000-0000-000000933101', '00000000-0000-0000-0000-0000000933e1', '00000000-0000-0000-0000-0000000933a1',
   gen_random_uuid(), NULL, now() - interval '2 days', 'chat-media/e933-1.jpg', 'image', false),
  ('00000000-0000-0000-0000-000000933102', '00000000-0000-0000-0000-0000000933e1', '00000000-0000-0000-0000-0000000933b2',
   gen_random_uuid(), NULL, now() - interval '1 day', 'chat-media/e933-2.jpg', 'image', false);
INSERT INTO public.story_places (story_item_id, relationship_id, author_id, lat, lng, label)
VALUES ('00000000-0000-0000-0000-000000933002', '00000000-0000-0000-0000-0000000933e1', '00000000-0000-0000-0000-0000000933a1', 5.6, -0.18, 'Osu');
-- A journal photo: a second non-story bucket whose name sorts after the chat
-- photos' names but whose bucket sorts first, to pin their order (E3b).
INSERT INTO public.reflection_journal_entries (id, user_id, title, content, tone) VALUES
  ('00000000-0000-0000-0000-000000933201', '00000000-0000-0000-0000-0000000933a1', 'Tuesday', 'calm', 'searching');
INSERT INTO public.reflection_journal_blocks (entry_id, user_id, position, kind, payload)
VALUES ('00000000-0000-0000-0000-000000933201', '00000000-0000-0000-0000-0000000933a1', 1, 'photo',
        '{"path": "e933-journal/pic.jpg"}');
SET LOCAL session_replication_role = origin;

-- E1. Story file names carry the right extension.
DO $$
BEGIN
  IF public.export_story_file_name('story-media/r/u/abc-media', 'video') !~ '^my_stories/[0-9a-f]{16}\.mp4$'
     OR public.export_story_file_name('story-media/r/u/abc-media', 'image') !~ '^my_stories/[0-9a-f]{16}\.jpg$'
     OR public.export_story_file_name('story-archive/x.jpg', 'image') !~ '^my_stories/[0-9a-f]{16}\.jpg$' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: story file names are %, %, %',
      public.export_story_file_name('story-media/r/u/abc-media', 'video'),
      public.export_story_file_name('story-media/r/u/abc-media', 'image'),
      public.export_story_file_name('story-archive/x.jpg', 'image');
  END IF;
END $$;

-- E2. data.json and the ZIP name each story's file the same way.
DO $$
DECLARE v_json text[]; v_zip text[];
BEGIN
  SELECT array_agg(x->>'media_file' ORDER BY x->>'media_file') INTO v_json
    FROM jsonb_array_elements(public.export_relationship('00000000-0000-0000-0000-0000000933a1',
                                                         '00000000-0000-0000-0000-0000000933e1')->'my_stories') x;
  SELECT array_agg(m.zip_path ORDER BY m.zip_path) INTO v_zip
    FROM public.export_media_manifest('00000000-0000-0000-0000-0000000933a1') m WHERE m.bucket = 'story-media';
  IF v_json IS DISTINCT FROM v_zip OR cardinality(v_zip) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: data.json names % but the ZIP holds %', v_json, v_zip;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM unnest(v_zip) z WHERE z LIKE 'media/my_stories/%.mp4') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the video story has no .mp4: %', v_zip;
  END IF;
END $$;

-- E3. Stories first, and the cursor walks every file exactly once, in order.
DO $$
DECLARE v record; v_ranks int[] := '{}'; v_seen text[] := '{}'; v_bucket text; v_name text; v_all int; v_guard int := 0;
BEGIN
  SELECT count(*) INTO v_all FROM public.export_media_manifest('00000000-0000-0000-0000-0000000933a1');
  LOOP
    SELECT * INTO v FROM public.export_media_manifest('00000000-0000-0000-0000-0000000933a1', NULL, v_bucket, v_name, 1);
    EXIT WHEN v.bucket IS NULL;
    v_guard := v_guard + 1;
    IF v_guard > v_all + 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the cursor loops'; END IF;
    IF (v.bucket || '/' || v.object_name) = ANY (v_seen) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % was walked twice', v.object_name;
    END IF;
    v_seen := v_seen || (v.bucket || '/' || v.object_name);
    v_ranks := v_ranks || public.export_media_rank(v.bucket);
    v_bucket := v.bucket; v_name := v.object_name;
  END LOOP;
  IF cardinality(v_seen) <> v_all OR v_all < 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: walked % of % files', cardinality(v_seen), v_all;
  END IF;
  IF v_ranks <> (SELECT array_agg(r ORDER BY r) FROM unnest(v_ranks) r) OR v_ranks[1] <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: stories are not walked first: %', v_ranks;
  END IF;
END $$;

-- E3b. Chat, journal and planning media keep the old walk among themselves
-- (bucket, then name) and their old file names; only stories moved ahead.
DO $$
DECLARE v_walk text[]; v_old text[];
BEGIN
  SELECT array_agg(m.bucket || '/' || m.object_name) INTO v_walk
    FROM public.export_media_manifest('00000000-0000-0000-0000-0000000933a1') m WHERE m.bucket <> 'story-media';
  SELECT array_agg(m.bucket || '/' || m.object_name ORDER BY m.bucket, m.object_name) INTO v_old
    FROM public.export_media_manifest('00000000-0000-0000-0000-0000000933a1') m WHERE m.bucket <> 'story-media';
  IF v_walk IS DISTINCT FROM v_old OR cardinality(v_walk) <> 3 OR v_walk[1] NOT LIKE 'journal-media/%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the other media walk %, want %', v_walk, v_old;
  END IF;
  IF EXISTS (SELECT 1 FROM public.export_media_manifest('00000000-0000-0000-0000-0000000933a1') m
              WHERE (m.bucket = 'message-media' AND m.zip_path <> 'media/' || public.export_file_name('chat', m.object_name))
                 OR (m.bucket = 'journal-media' AND m.zip_path <> 'media/' || public.export_file_name('journal', m.object_name))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chat or journal file was renamed';
  END IF;
END $$;

-- E4. Every in-flight job whose data part may have run in the old order is
-- replaced (its data.json would name story files without extensions); only a
-- job still queued in phase 'data' is re-labelled. The replacement takes a
-- fresh relationship snapshot at its first claim (review M1, M5).
DO $$
DECLARE v_mid uuid; v_chat uuid; v_fresh uuid; v_done uuid; v_new record; v_n int;
BEGIN
  INSERT INTO public.data_export_jobs (user_id, status, phase, relationship_ids, media_after_bucket, media_after_name,
                                       storage_keys, media_order, requested_at)
  VALUES ('00000000-0000-0000-0000-0000000933a1', 'queued', 'media', ARRAY['00000000-0000-0000-0000-0000000933e1']::uuid[],
          'message-media', 'chat-media/e933-1.jpg', '{}', 1, now() - interval '1 hour')
  RETURNING id INTO v_mid;
  INSERT INTO public.media_deletion_queue (bucket_id, object_name, not_before)
  VALUES ('data-exports', v_mid::text || '/attune-export-1.zip', now() + interval '1 day');
  UPDATE public.data_export_jobs SET storage_keys = ARRAY[v_mid::text || '/attune-export-1.zip'] WHERE id = v_mid;
  INSERT INTO public.data_export_jobs (user_id, status, phase, media_order, requested_at)
  VALUES ('00000000-0000-0000-0000-0000000933b2', 'queued', 'chat', 1, now() - interval '30 minutes') RETURNING id INTO v_chat;
  INSERT INTO public.data_export_jobs (user_id, status, phase, media_order, requested_at)
  VALUES ('00000000-0000-0000-0000-0000000933b2', 'queued', 'data', 1, now() - interval '5 minutes') RETURNING id INTO v_fresh;
  INSERT INTO public.data_export_jobs (user_id, status, phase, media_order, requested_at, ready_at, expires_at)
  VALUES ('00000000-0000-0000-0000-0000000933b2', 'ready', 'done', 1, now() - interval '3 days', now() - interval '3 days', now() + interval '4 days')
  RETURNING id INTO v_done;

  v_n := public.export_restart_old_order_jobs();
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % jobs restarted (want 2)', v_n; END IF;
  IF (SELECT status || '/' || coalesce(error, '') FROM public.data_export_jobs WHERE id = v_mid) <> 'failed/restarted' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the mid-walk job is %', (SELECT status FROM public.data_export_jobs WHERE id = v_mid);
  END IF;
  IF (SELECT not_before FROM public.media_deletion_queue WHERE object_name = v_mid::text || '/attune-export-1.zip') > now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restarted job''s part is kept';
  END IF;
  SELECT * INTO v_new FROM public.data_export_jobs
   WHERE user_id = '00000000-0000-0000-0000-0000000933a1' AND id <> v_mid ORDER BY requested_at DESC LIMIT 1;
  IF v_new.id IS NULL OR v_new.status <> 'queued' OR v_new.phase <> 'data' OR v_new.media_order <> 2
     OR v_new.relationship_ids IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the replacement job is %', row_to_json(v_new);
  END IF;
  IF (SELECT status || '/' || coalesce(error, '') FROM public.data_export_jobs WHERE id = v_chat) <> 'failed/restarted' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a job past its old-order data part was kept';
  END IF;
  IF (SELECT status || '/' || media_order FROM public.data_export_jobs WHERE id = v_fresh) <> 'queued/2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a job not yet started was not simply re-labelled';
  END IF;
  IF (SELECT media_order FROM public.data_export_jobs WHERE id = v_done) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a finished job was touched';
  END IF;
  IF public.export_restart_old_order_jobs() <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restart is not idempotent';
  END IF;
  IF (SELECT column_default FROM information_schema.columns WHERE table_schema = 'public'
        AND table_name = 'data_export_jobs' AND column_name = 'media_order') NOT LIKE '2%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: new jobs do not default to the stories-first walk';
  END IF;
END $$;

-- E4b. A job building its first media part (no cursor yet) at deploy may be
-- holding an old-order list in a live worker run, so its next cursor would be
-- in the old order: it is replaced, as is a queued media job with no cursor
-- (its data part ran in the old order).
DO $$
DECLARE v_first uuid; v_waiting uuid; v_n int;
BEGIN
  INSERT INTO public.data_export_jobs (user_id, status, phase, claimed_at, attempts, relationship_ids, media_order, requested_at)
  VALUES ('00000000-0000-0000-0000-0000000933a1', 'building', 'media', now(), 1,
          ARRAY['00000000-0000-0000-0000-0000000933e1']::uuid[], 1, now() - interval '20 minutes')
  RETURNING id INTO v_first;
  INSERT INTO public.data_export_jobs (user_id, status, phase, media_order, requested_at)
  VALUES ('00000000-0000-0000-0000-0000000933b2', 'queued', 'media', 1, now() - interval '10 minutes')
  RETURNING id INTO v_waiting;
  v_n := public.export_restart_old_order_jobs();
  IF v_n <> 2 OR (SELECT status FROM public.data_export_jobs WHERE id = v_first) <> 'failed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a job building its first media part in the old order was kept';
  END IF;
  IF (SELECT status FROM public.data_export_jobs WHERE id = v_waiting) <> 'failed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a queued media job whose data part ran in the old order was kept';
  END IF;
END $$;

-- E4c. The system's 'restarted' failure does not count against the person
-- (review M3): two failed requests today, a third restarted at deploy and
-- its replacement failing leaves the usual wait, not ~14 h.
DO $$
DECLARE v_next timestamptz;
BEGIN
  DELETE FROM public.data_export_jobs WHERE user_id = '00000000-0000-0000-0000-0000000933a1';
  INSERT INTO public.data_export_jobs (user_id, status, phase, error, media_order, requested_at) VALUES
    ('00000000-0000-0000-0000-0000000933a1', 'failed', 'data', 'boom', 2, now() - interval '20 hours'),
    ('00000000-0000-0000-0000-0000000933a1', 'failed', 'data', 'boom', 2, now() - interval '10 hours');
  INSERT INTO public.data_export_jobs (user_id, status, phase, media_after_bucket, media_after_name, media_order, requested_at)
  VALUES ('00000000-0000-0000-0000-0000000933a1', 'queued', 'media', 'message-media', 'chat-media/e933-1.jpg', 1,
          now() - interval '1 hour');
  PERFORM public.export_restart_old_order_jobs();
  UPDATE public.data_export_jobs SET status = 'failed', error = 'boom'
   WHERE user_id = '00000000-0000-0000-0000-0000000933a1' AND status = 'queued';
  v_next := public.export_next_allowed('00000000-0000-0000-0000-0000000933a1');
  IF v_next > now() + interval '4 hours 1 minute' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restart costs the person a wait until % (want <= 4 h)', v_next - now();
  END IF;
END $$;

-- E5. Sync-audit C-2 stands (controller ruling, Wave 5): an ending purges the
-- story pins, so the ending author's export still lists every story and its
-- file, with no place.
DO $$
DECLARE v_stories jsonb;
BEGIN
  UPDATE public.relationships SET status = 'ended', ended_at = now() WHERE id = '00000000-0000-0000-0000-0000000933e1';
  IF EXISTS (SELECT 1 FROM public.story_places WHERE relationship_id = '00000000-0000-0000-0000-0000000933e1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ending kept the story pins (C-2)';
  END IF;
  v_stories := public.export_relationship('00000000-0000-0000-0000-0000000933a1',
                                          '00000000-0000-0000-0000-0000000933e1')->'my_stories';
  IF jsonb_array_length(v_stories) <> 3
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_stories) x WHERE x->'place' <> 'null'::jsonb)
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_stories) x WHERE x->>'media_file' !~ '^media/my_stories/[0-9a-f]{16}\.(mp4|jpg)$') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ended export''s stories are %', v_stories;
  END IF;
END $$;

-- E6. The new helpers are not client functions.
DO $$
DECLARE v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.export_media_rank(text)', 'public.export_story_file_name(text,text)',
                              'public.export_restart_old_order_jobs()'] LOOP
    IF has_function_privilege('authenticated', v_fn, 'EXECUTE') OR has_function_privilege('anon', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a client can execute %', v_fn;
    END IF;
  END LOOP;
END $$;

ROLLBACK;
