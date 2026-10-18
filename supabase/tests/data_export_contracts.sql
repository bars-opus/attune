-- supabase/tests/data_export_contracts.sql
-- Spec 3c (research 06 §3 F1 (5); 05 D.2 Export, D.3 #6): the export round
-- trip. What a person can still read is in it; what is not theirs, AI
-- judgement, role attribution, safety data, view-once and streak media, the
-- partner's private calendar and the partner's stories never are; a sealed
-- or archived relationship contributes only the person's personal classes;
-- nobody can read or request another person's export.
BEGIN;
-- The Spec 7/8 writers refuse while their flags are off; on here.
UPDATE public.feature_flags SET enabled = true
WHERE key IN ('appreciation_notes', 'share_a_win', 'quiet_states', 'private_safety_check', 'conflict_toolkit');

INSERT INTO auth.users (id) VALUES
  ('9f100000-0000-0000-0000-0000000000a1'), ('9f100000-0000-0000-0000-0000000000b2'),
  ('9f100000-0000-0000-0000-0000000000c3'), ('9f100000-0000-0000-0000-0000000000d4')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9f100000-0000-0000-0000-0000000000a1', '+233599600001', 'Una Owusu'),
  ('9f100000-0000-0000-0000-0000000000b2', '+233599600002', 'Paa Kwesi'),
  ('9f100000-0000-0000-0000-0000000000c3', '+233599600003', 'Quarm'),
  ('9f100000-0000-0000-0000-0000000000d4', '+233599600004', 'Dede')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.u() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9f100000-0000-0000-0000-0000000000a1'::uuid $$;
CREATE FUNCTION pg_temp.p() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9f100000-0000-0000-0000-0000000000b2'::uuid $$;
CREATE FUNCTION pg_temp.q() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9f100000-0000-0000-0000-0000000000c3'::uuid $$;
CREATE FUNCTION pg_temp.d() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9f100000-0000-0000-0000-0000000000d4'::uuid $$;
CREATE FUNCTION pg_temp.r1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9f200000-0000-0000-0000-000000000001'::uuid $$;
CREATE FUNCTION pg_temp.r0() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9f200000-0000-0000-0000-000000000002'::uuid $$;
CREATE FUNCTION pg_temp.r2() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9f200000-0000-0000-0000-000000000003'::uuid $$;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- R1 (U,P) active; R0 (Q,U) archived; R2 (U,D) ended and sealed by U.
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at, ended_at)
VALUES
  (pg_temp.r1(), pg_temp.u(), pg_temp.p(), 'active', CURRENT_DATE - 100, now() - interval '100 days', now(), NULL),
  (pg_temp.r0(), pg_temp.q(), pg_temp.u(), 'ended', CURRENT_DATE - 900, now() - interval '900 days', now(), now() - interval '400 days'),
  (pg_temp.r2(), pg_temp.u(), pg_temp.d(), 'ended', CURRENT_DATE - 300, now() - interval '300 days', now(), now() - interval '3 days');
UPDATE public.relationships SET status = 'archived', chat_archived_at = now() - interval '370 days',
  chat_archived_reason = 'window_closed' WHERE id = pg_temp.r0();
INSERT INTO public.relationship_seals (relationship_id, user_id) VALUES (pg_temp.r2(), pg_temp.u());

SET LOCAL session_replication_role = replica;
-- Chat: a plain message with AI columns set; partner media; a view-once; a
-- streak; a screenshot notice; a deleted message; an Assist share.
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, created_at,
  tone_score, nvc_violations, bid_type, sentiment, media_url, media_type, is_view_once, is_system_notice,
  deleted_at, message_origin, assistant_payload)
VALUES
  ('9f300000-0000-0000-0000-000000000001', pg_temp.r1(), pg_temp.u(), gen_random_uuid(), 'hi love', now() - interval '5 days',
   0.8, '["x"]'::jsonb, 'toward', 'positive', NULL, NULL, false, false, NULL, 'user', NULL),
  ('9f300000-0000-0000-0000-000000000002', pg_temp.r1(), pg_temp.p(), gen_random_uuid(), NULL, now() - interval '4 days',
   NULL, NULL, NULL, NULL, 'chat-media/9f-partner.jpg', 'image', false, false, NULL, 'user', NULL),
  ('9f300000-0000-0000-0000-000000000003', pg_temp.r1(), pg_temp.p(), gen_random_uuid(), NULL, now() - interval '3 days',
   NULL, NULL, NULL, NULL, 'chat-media/9f-viewonce.jpg', 'image', true, false, NULL, 'user', NULL),
  ('9f300000-0000-0000-0000-000000000004', pg_temp.r1(), pg_temp.p(), gen_random_uuid(), NULL, now() - interval '3 days',
   NULL, NULL, NULL, NULL, 'chat-media/9f-streak.mp4', 'streak', false, false, NULL, 'user', NULL),
  ('9f300000-0000-0000-0000-000000000005', pg_temp.r1(), pg_temp.p(), gen_random_uuid(), 'Paa took a screenshot', now() - interval '2 days',
   NULL, NULL, NULL, NULL, NULL, NULL, false, true, NULL, 'user', NULL),
  ('9f300000-0000-0000-0000-000000000006', pg_temp.r1(), pg_temp.u(), gen_random_uuid(), NULL, now() - interval '2 days',
   NULL, NULL, NULL, NULL, NULL, NULL, false, false, now(), 'user', NULL),
  ('9f300000-0000-0000-0000-000000000007', pg_temp.r1(), pg_temp.u(), gen_random_uuid(), 'shared from assist', now() - interval '1 day',
   NULL, NULL, NULL, NULL, NULL, NULL, false, false, NULL, 'attune_assist', '{"model":"x","pursuer":"user_a"}'::jsonb),
  ('9f300000-0000-0000-0000-000000000008', pg_temp.r2(), pg_temp.d(), gen_random_uuid(), 'sealed chapter text', now() - interval '10 days',
   NULL, NULL, NULL, NULL, NULL, NULL, false, false, NULL, 'user', NULL),
  ('9f300000-0000-0000-0000-000000000009', pg_temp.r0(), pg_temp.q(), gen_random_uuid(), 'archived chapter text', now() - interval '500 days',
   NULL, NULL, NULL, NULL, NULL, NULL, false, false, NULL, 'user', NULL);
UPDATE public.messages SET content = 'view-once caption' WHERE id = '9f300000-0000-0000-0000-000000000003';
-- Calendar: U's private, P's private, P's busy-only, a shared event.
INSERT INTO public.couple_events (id, relationship_id, created_by, kind, title, all_day, start_date, end_date, visibility, status, participant_ids)
VALUES
  (gen_random_uuid(), pg_temp.r1(), pg_temp.u(), 'event', 'Una private thing', true, CURRENT_DATE + 3, CURRENT_DATE + 3, 'private', 'confirmed', ARRAY[pg_temp.u()]),
  (gen_random_uuid(), pg_temp.r1(), pg_temp.p(), 'event', 'Paa secret plan', true, CURRENT_DATE + 4, CURRENT_DATE + 4, 'private', 'confirmed', ARRAY[pg_temp.p()]),
  (gen_random_uuid(), pg_temp.r1(), pg_temp.p(), 'event', 'Paa doctor', true, CURRENT_DATE + 5, CURRENT_DATE + 5, 'busy_only', 'confirmed', ARRAY[pg_temp.p()]),
  (gen_random_uuid(), pg_temp.r1(), pg_temp.u(), 'event', 'Dinner together', true, CURRENT_DATE + 6, CURRENT_DATE + 6, 'shared', 'confirmed', ARRAY[pg_temp.u(), pg_temp.p()]);
-- Stories by both; Pulse with the old emotional_safety; a verdict with model columns.
INSERT INTO public.story_items (id, client_story_id, relationship_id, author_id, media_type, media_key, thumbnail_key, media_width, media_height, occurred_on, expires_at)
VALUES ('9f400000-0000-0000-0000-000000000001', gen_random_uuid(), pg_temp.r1(), pg_temp.u(), 'image', 'story-media/' || pg_temp.r1() || '/' || pg_temp.u() || '/a-photo.jpg', 'story-media/t-a.jpg', 100, 100, CURRENT_DATE, now() + interval '1 day'),
       ('9f400000-0000-0000-0000-000000000002', gen_random_uuid(), pg_temp.r1(), pg_temp.p(), 'image', 'story-media/' || pg_temp.r1() || '/' || pg_temp.p() || '/b-photo.jpg', 'story-media/t-b.jpg', 100, 100, CURRENT_DATE, now() + interval '1 day');
INSERT INTO public.pulse_scores (relationship_id, week_ending, overall_score, communication, connection, conflict_health, alignment, emotional_safety)
VALUES (pg_temp.r1(), CURRENT_DATE, 71, 70, 72, 69, 73, 40);
INSERT INTO public.verdicts (relationship_id, period_start, period_end, snapshot_at, status, data_confidence, confidence_label,
  headline, strengths, watch_areas, one_action, disclaimer, input_schema_version, prompt_version, model_provider, model_name)
VALUES (pg_temp.r1(), CURRENT_DATE - 30, CURRENT_DATE, now(), 'published', 'medium', 'Medium', 'Warm month',
  '[{"title":"Warmth","body":"Kind words","evidence_ids":["e1"]}]', '[]', 'Keep a date night', 'Not a diagnosis', 'v1', 'p1', 'gemini', 'model-x');
-- Analysis, patterns, a safety event: never exported.
INSERT INTO public.analysis_sessions (relationship_id, started_at, ended_at, pursuer) VALUES (pg_temp.r1(), now() - interval '1 hour', now(), 'user_a');
INSERT INTO public.patterns (relationship_id, pattern_type, severity) VALUES (pg_temp.r1(), 'pursue_withdraw', 'watch');
INSERT INTO public.safety_events (id, relationship_id, at_risk_user_id, source_event_key, trigger_tier, trigger_family, config_version)
VALUES (gen_random_uuid(), pg_temp.r1(), pg_temp.u(), 'export:test', 1, 'test', 'test');
-- Games: a revealed and an unrevealed Love map round (U is user_a).
INSERT INTO public.game_session_rounds (id, relationship_id, round_number, question_text_snapshot, answer_a, answer_b, both_answered)
VALUES ('9f500000-0000-0000-0000-000000000001', pg_temp.r1(), 1, 'Favourite food?', 'jollof', 'waakye', true),
       ('9f500000-0000-0000-0000-000000000002', pg_temp.r1(), 2, 'Dream trip?', 'Kyoto', 'secret answer of Paa', false);
-- Personal: journal (with AI tone), an insight, a check-in, a quiz.
INSERT INTO public.reflection_journal_entries (id, user_id, title, content, tone) VALUES
  ('9f600000-0000-0000-0000-000000000001', pg_temp.u(), 'Tuesday', 'felt calm', 'searching');
INSERT INTO public.personal_insights (user_id, relationship_id, insight_type, insight_body, metadata)
VALUES (pg_temp.u(), pg_temp.r0(), 'pattern', 'You soften when tired', '{"internal":"x"}');
INSERT INTO public.quiz_responses (user_id, quiz_type, responses) VALUES (pg_temp.u(), 'attachment', '{"q1":3}');
INSERT INTO public.weekly_checkins (user_id, relationship_id, week_ending, communication_rating, connection_rating,
  conflict_health_rating, alignment_rating, safety_rating)
VALUES (pg_temp.u(), pg_temp.r1(), CURRENT_DATE, 7, 7, 7, 7, 2);
INSERT INTO public.place_updates (relationship_id, user_id, label, latitude, longitude, city)
VALUES (pg_temp.r1(), pg_temp.p(), 'Paa at work', 5.6037, -0.1870, 'Accra'),
       (pg_temp.r1(), pg_temp.u(), 'Una at home', 5.5500, -0.2000, 'Accra');
INSERT INTO public.reflection_journal_blocks (entry_id, user_id, position, kind, payload)
VALUES ('9f600000-0000-0000-0000-000000000001', pg_temp.u(), 1, 'photo',
        jsonb_build_object('path', pg_temp.u() || '/9f600000-0000-0000-0000-000000000001/pic.jpg'));
SET LOCAL session_replication_role = origin;

-- 1. The bundle.
DO $$
DECLARE b jsonb; r jsonb; c jsonb; v_txt text; k text;
BEGIN
  b := public.export_bundle(pg_temp.u());
  v_txt := b::text;

  IF jsonb_array_length(b->'relationships') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % relationships exported, expected only the open one', jsonb_array_length(b->'relationships');
  END IF;
  r := b->'relationships'->0;
  IF v_txt LIKE '%sealed chapter text%' OR v_txt LIKE '%archived chapter text%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sealed or archived chapter''s chat was exported';
  END IF;
  IF r->>'partner_first_name' <> 'Paa' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: partner named %', r->>'partner_first_name';
  END IF;

  -- No AI judgement, role attribution or safety data anywhere.
  FOREACH k IN ARRAY ARRAY['tone_score', 'nvc_violations', 'bid_type', 'sentiment', 'assistant_payload',
    'pursuer', 'emotional_safety', 'model_name', 'model_provider', 'prompt_version', 'evidence_ids',
    'pursue_withdraw', 'safety_event', '"tone"', 'searching', 'internal'] LOOP
    IF position(k in v_txt) > 0 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the bundle contains %', k;
    END IF;
  END LOOP;
  IF v_txt LIKE '%took a screenshot%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a system notice was exported';
  END IF;
  SELECT p.rows INTO c FROM public.export_chat_page(pg_temp.u(), pg_temp.r1(), NULL, NULL, 100) p;
  v_txt := v_txt || c::text;
  IF NOT (c @> '[{"text":"hi love","from":"me"}]') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the person''s own message is missing';
  END IF;
  IF NOT (c @> '[{"deleted":true}]') OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(c) x WHERE (x->>'deleted')::boolean AND x->>'text' IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the deleted message is not a tombstone';
  END IF;
  IF NOT (c @> '[{"text":"shared from assist","from_attune_assist":true}]') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an Assist share lost its text or flag';
  END IF;
  IF c::text LIKE '%view-once caption%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a view-once message''s text was exported (final review I7)';
  END IF;
  -- Keyset paging: page 2 starts after page 1, with no overlap.
  DECLARE v_at timestamptz; v_id uuid; c2 jsonb;
  BEGIN
    SELECT p.last_at, p.last_id INTO v_at, v_id FROM public.export_chat_page(pg_temp.u(), pg_temp.r1(), NULL, NULL, 2) p;
    SELECT p.rows INTO c2 FROM public.export_chat_page(pg_temp.u(), pg_temp.r1(), v_at, v_id, 100) p;
    IF jsonb_array_length(c2) <> jsonb_array_length(c) - 2 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: chat pages overlap or skip (% vs %)', jsonb_array_length(c2), jsonb_array_length(c);
    END IF;
  END;
  IF c::text LIKE '%took a screenshot%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a system notice was exported';
  END IF;
  -- Allowlist, not denylist: a renamed column cannot slip in (review I9).
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(c) x, jsonb_object_keys(x) AS ok(key)
             WHERE ok.key NOT IN ('ref', 'from', 'at', 'text', 'quoted', 'reply_to', 'media', 'media_file',
                             'view_once', 'edited_at', 'deleted', 'source', 'from_attune_assist', 'kind')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chat row carries an unexpected key';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(b->'personal'->'weekly_checkins') x, jsonb_object_keys(x) AS ok(key)
             WHERE ok.key NOT IN ('week_ending', 'communication', 'connection', 'conflict_health', 'alignment')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a check-in carries the safety rating or another unexpected key';
  END IF;
  IF jsonb_array_length(b->'personal'->'weekly_checkins') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the check-in is missing';
  END IF;
  -- The partner's pins carry no coordinates (review I2); the person's own do.
  IF NOT (r->'places' @> '[{"from":"partner","label":"Paa at work","latitude":null}]')
     OR NOT (r->'places' @> '[{"from":"me","latitude":5.55}]') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: places: %', r->'places';
  END IF;

  -- The calendar shows what the person sees.
  IF v_txt LIKE '%Paa secret plan%' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the partner''s private event leaked'; END IF;
  IF v_txt LIKE '%Paa doctor%' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the partner''s busy-only title leaked'; END IF;
  IF r->'calendar' @> '[{"title":"Busy"}]' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the partner''s busy-only item is exported (review I3)';
  END IF;
  IF NOT (r->'calendar' @> '[{"title":"Una private thing"}]') OR NOT (r->'calendar' @> '[{"title":"Dinner together"}]') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the person''s own or shared events are missing: %', r->'calendar';
  END IF;

  -- Own stories only; Pulse without the private dimension; verdict text.
  IF jsonb_array_length(r->'my_stories') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % stories exported, expected only the person''s own', jsonb_array_length(r->'my_stories');
  END IF;
  IF NOT (r->'pulse' @> '[{"overall":71}]') OR NOT (r->'verdicts' @> '[{"headline":"Warm month"}]') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: shared Pulse or the verdict is missing';
  END IF;

  -- The partner's answer only once revealed.
  IF NOT (r->'game_rounds' @> '[{"my_answer":"jollof","partner_answer":"waakye"}]') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a revealed round is incomplete: %', r->'game_rounds';
  END IF;
  IF v_txt LIKE '%secret answer of Paa%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unrevealed partner answer was exported';
  END IF;

  -- Personal classes come whatever the relationships' state.
  IF NOT (b->'personal'->'insights' @> '[{"text":"You soften when tired"}]')
     OR NOT (b->'personal'->'journal' @> '[{"title":"Tuesday"}]')
     OR jsonb_array_length(b->'personal'->'quiz_responses') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: personal classes are missing';
  END IF;
  -- Sync audit M-9: the person's own settings travel too.
  IF NOT coalesce(b->'personal'->'settings' ?& ARRAY['timezone', 'seen_receipts', 'devices'], false) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: personal settings are missing: %', b->'personal'->'settings';
  END IF;
  FOREACH k IN ARRAY ARRAY['analysis', 'patterns', 'compatibility', 'safety', 'dating', 'forum'] LOOP
    IF b ? k OR (b->'personal') ? k OR r ? k THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a "%" section exists', k;
    END IF;
  END LOOP;

  -- No id of any kind: no uuid-shaped string anywhere (review I1).
  IF v_txt ~ '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an id is in the bundle: %',
      substring(v_txt from '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}');
  END IF;
  IF (b->'personal'->'journal'->0->'blocks') @> '[{"kind":"photo"}]'
     AND NOT ((b->'personal'->'journal'->0->'blocks') @> '[{"photo":null}]')
     AND NOT EXISTS (SELECT 1 FROM public.export_media_manifest(pg_temp.u()) m
                     WHERE m.zip_path = (b->'personal'->'journal'->0->'blocks'->0->>'photo')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a journal photo reference does not match its file';
  END IF;
END $$;

-- 2. The media manifest.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.export_media_manifest(pg_temp.u()) WHERE object_name = 'chat-media/9f-partner.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the partner''s ordinary photo is missing from the media';
  END IF;
  IF EXISTS (SELECT 1 FROM public.export_media_manifest(pg_temp.u())
             WHERE object_name IN ('chat-media/9f-viewonce.jpg', 'chat-media/9f-streak.mp4')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: view-once or streak media is in the export';
  END IF;
  IF EXISTS (SELECT 1 FROM public.export_media_manifest(pg_temp.u()) WHERE object_name LIKE '%b-photo.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the partner''s story media is in the export';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.export_media_manifest(pg_temp.u()) WHERE object_name LIKE '%a-photo.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the person''s own story media is missing';
  END IF;
  IF EXISTS (SELECT 1 FROM public.export_media_manifest(pg_temp.u())
             WHERE zip_path ~ '[0-9a-f]{8}-[0-9a-f]{4}-') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a ZIP path carries an id';
  END IF;
END $$;

-- 3. Jobs: one at a time, one a day, nobody else's.
DO $$
DECLARE v_id uuid; v_msg text; v_n int; v_key text;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.u());
  v_id := public.request_my_export();
  BEGIN
    PERFORM public.request_my_export();
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: two exports at once';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    RESET ROLE;
    IF v_msg <> 'export:in_progress' THEN RAISE; END IF;
  END;
  -- The worker builds it in parts; each part's file is queued for deletion
  -- before it is stored, and kept 7 days once the download is ready.
  IF (SELECT c.user_id FROM public.claim_data_export() c) IS DISTINCT FROM pg_temp.u() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the worker did not claim the job';
  END IF;
  IF (SELECT relationship_ids FROM public.data_export_jobs WHERE id = v_id) IS DISTINCT FROM ARRAY[pg_temp.r1()] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the claim did not snapshot the open relationships';
  END IF;
  v_key := public.export_begin_part(v_id);
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = 'data-exports' AND object_name = v_key) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a part was not queued before upload (final review C2)';
  END IF;
  PERFORM public.export_finish_part(v_id, v_key, 'media', 1, NULL, NULL, 0, NULL, NULL, '[]'::jsonb, false);
  IF (SELECT status FROM public.data_export_jobs WHERE id = v_id) <> 'queued' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a job between parts is not back in the queue';
  END IF;
  PERFORM public.claim_data_export();
  v_key := public.export_begin_part(v_id);
  PERFORM public.export_finish_part(v_id, v_key, 'done', 1, NULL, NULL, 0, NULL, NULL, '[]'::jsonb, true);
  IF (SELECT count(*) FROM public.media_deletion_queue
      WHERE bucket_id = 'data-exports' AND object_name LIKE v_id || '/%' AND not_before > now() + interval '6 days') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ready parts are not kept 7 days';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.u());
  BEGIN
    PERFORM public.request_my_export();
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second export within 24 hours';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    RESET ROLE;
    IF v_msg <> 'export:too_soon' THEN RAISE; END IF;
  END;
  PERFORM pg_temp.as_user(pg_temp.u());
  IF (SELECT status FROM public.get_my_export()) <> 'ready' THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: the person cannot see their ready export';
  END IF;
  RESET ROLE;
  PERFORM pg_temp.as_user(pg_temp.p());
  SELECT count(*) INTO v_n FROM public.get_my_export();
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the partner sees the person''s export'; END IF;
  -- A job that vanished while building (account deleted): its file goes at once (review I5).
  PERFORM pg_temp.as_user(pg_temp.d());
  v_id := public.request_my_export();
  RESET ROLE;
  PERFORM public.claim_data_export();
  v_key := public.export_begin_part(v_id);
  DELETE FROM public.data_export_jobs WHERE id = v_id;
  PERFORM public.export_finish_part(v_id, v_key, 'done', 1, NULL, NULL, 0, NULL, NULL, '[]'::jsonb, true);
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                 WHERE bucket_id = 'data-exports' AND object_name = v_key AND not_before <= now()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an orphaned export file is kept';
  END IF;
  -- After a failure: an hour's pause (review I6).
  PERFORM pg_temp.as_user(pg_temp.q());
  v_id := public.request_my_export();
  RESET ROLE;
  PERFORM public.claim_data_export();
  v_key := public.export_begin_part(v_id);
  PERFORM public.fail_data_export(v_id, 'test');
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                 WHERE bucket_id = 'data-exports' AND object_name = v_key AND not_before <= now()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed job''s part is kept (final review C2)';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.q());
  BEGIN
    PERFORM public.request_my_export();
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retry straight after a failure';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    RESET ROLE;
    IF v_msg <> 'export:too_soon' THEN RAISE; END IF;
  END;
  -- A crashed worker's job comes back after 15 minutes.
  PERFORM pg_temp.as_user(pg_temp.p());
  v_id := public.request_my_export();
  RESET ROLE;
  PERFORM public.claim_data_export();
  UPDATE public.data_export_jobs SET claimed_at = now() - interval '20 minutes' WHERE id = v_id;
  IF (SELECT c.id FROM public.claim_data_export() c) IS DISTINCT FROM v_id THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stale building job was not reclaimed';
  END IF;
END $$;

-- 4. Only the worker builds; only the owner reads the file.
DO $$
DECLARE v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.export_bundle(uuid,uuid[])', 'public.export_media_manifest(uuid,uuid[],text,text,integer)',
    'public.claim_data_export()', 'public.export_begin_part(uuid)', 'public.fail_data_export(uuid,text)',
    'public.export_finish_part(uuid,text,text,integer,timestamptz,uuid,integer,text,text,jsonb,boolean)',
    'public.export_retry_part(uuid,text)', 'public.export_expire_stale(uuid)',
    'public.export_relationship(uuid,uuid)', 'public.relationship_chat_open_for(uuid,uuid)',
    'public.export_chat_page(uuid,uuid,timestamptz,uuid,integer)', 'public.export_drop_files(uuid)'] LOOP
    IF has_function_privilege('authenticated', v_fn, 'EXECUTE') OR has_function_privilege('anon', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a client can execute %', v_fn;
    END IF;
  END LOOP;
  IF has_table_privilege('authenticated', 'public.data_export_jobs', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients read export jobs directly';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'build-data-exports' AND command LIKE '%generate_series%count(*)%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the export worker is not scheduled (or runs when idle)';
  END IF;
  -- No client reaches the bucket directly: only the short signed link.
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects'
             AND (qual LIKE '%data-exports%' OR with_check LIKE '%data-exports%')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client policy opens the export bucket';
  END IF;

END $$;

-- 5. Re-review of the parts build (2026-10-18).
INSERT INTO auth.users (id) VALUES
  ('9f100000-0000-0000-0000-0000000000e5'), ('9f100000-0000-0000-0000-0000000000f6'),
  ('9f100000-0000-0000-0000-0000000000a7')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9f100000-0000-0000-0000-0000000000e5', '+233599600005', 'Esi'),
  ('9f100000-0000-0000-0000-0000000000f6', '+233599600006', 'Fiifi'),
  ('9f100000-0000-0000-0000-0000000000a7', '+233599600007', 'Aba')
ON CONFLICT (id) DO NOTHING;
DO $$
DECLARE
  v_e uuid := '9f100000-0000-0000-0000-0000000000e5';
  v_f uuid := '9f100000-0000-0000-0000-0000000000f6';
  v_a uuid := '9f100000-0000-0000-0000-0000000000a7';
  v_id uuid; v_key text; v_status text; v_next timestamptz; v_first record; v_n int; v_all int; c jsonb;
BEGIN
  -- M7: a quote of a message that no longer exists is not exported.
  PERFORM set_config('session_replication_role', 'replica', true);
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, created_at,
    reply_to_message_id, quoted_text, is_view_once, is_system_notice, message_origin)
  VALUES ('9f300000-0000-0000-0000-0000000000a1', pg_temp.r1(), pg_temp.u(), gen_random_uuid(), 'replying',
          now() - interval '12 hours', '9f300000-0000-0000-0000-0000000000ff', 'ghost quote', false, false, 'user');
  PERFORM set_config('session_replication_role', 'origin', true);
  SELECT p.rows INTO c FROM public.export_chat_page(pg_temp.u(), pg_temp.r1(), NULL, NULL, 100) p;
  IF c::text LIKE '%ghost quote%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a quote of a vanished message was exported (re-review M7)';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(c) x WHERE length(x->>'ref') <> 12) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: refs are not 12 characters (re-review M4)';
  END IF;

  -- M6: ids the person is not in give nothing.
  IF public.export_relationship(pg_temp.q(), pg_temp.r1()) <> '{}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: export_relationship trusts the ids (re-review M6)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.export_media_manifest(pg_temp.q(), ARRAY[pg_temp.r1()])
             WHERE bucket IN ('message-media', 'story-media')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the manifest trusts the ids (re-review M6)';
  END IF;

  -- M5: the manifest is walked by a cursor.
  SELECT count(*) INTO v_all FROM public.export_media_manifest(pg_temp.u());
  SELECT * INTO v_first FROM public.export_media_manifest(pg_temp.u(), NULL, NULL, NULL, 1);
  SELECT count(*) INTO v_n FROM public.export_media_manifest(pg_temp.u(), NULL, v_first.bucket, v_first.object_name);
  IF v_all < 2 OR v_n <> v_all - 1 OR EXISTS (
       SELECT 1 FROM public.export_media_manifest(pg_temp.u(), NULL, v_first.bucket, v_first.object_name)
       WHERE bucket = v_first.bucket AND object_name = v_first.object_name) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the media cursor skips or repeats (% of %)', v_n, v_all;
  END IF;

  -- M1: three requests in a day: allowed when the oldest of the three is a day old.
  INSERT INTO public.data_export_jobs (user_id, status, requested_at) VALUES
    (v_f, 'failed', now() - interval '23 hours'), (v_f, 'failed', now() - interval '20 hours'),
    (v_f, 'failed', now() - interval '18 hours');
  v_next := public.export_next_allowed(v_f);
  IF v_next NOT BETWEEN now() + interval '50 minutes' AND now() + interval '70 minutes' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: next allowed is % (re-review M1)', v_next - now();
  END IF;

  -- I1: a lost response after a committed finish keeps the parts.
  PERFORM pg_temp.as_user(v_e);
  v_id := public.request_my_export();
  RESET ROLE;
  IF (SELECT c.id FROM public.claim_data_export() c) IS DISTINCT FROM v_id THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: setup: the worker did not claim Esi''s job';
  END IF;
  v_key := public.export_begin_part(v_id);
  PERFORM public.export_finish_part(v_id, v_key, 'chat', 1, NULL, NULL, 0, NULL, NULL, '[]'::jsonb, false);
  PERFORM public.fail_data_export(v_id, 'lost response');
  IF (SELECT status FROM public.data_export_jobs WHERE id = v_id) <> 'queued'
     OR EXISTS (SELECT 1 FROM public.media_deletion_queue
                WHERE bucket_id = 'data-exports' AND object_name = v_key AND not_before <= now()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stray failure dropped a live job''s parts (re-review I1)';
  END IF;

  -- I3: a run with nothing to store records progress only.
  PERFORM public.claim_data_export();
  PERFORM public.export_finish_part(v_id, NULL, 'media', 2, NULL, NULL, 0, 'story-media', 'x', '[]'::jsonb, false);
  IF (SELECT cardinality(storage_keys) FROM public.data_export_jobs WHERE id = v_id) <> 1
     OR (SELECT media_after_name FROM public.data_export_jobs WHERE id = v_id) IS DISTINCT FROM 'x' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an empty part was stored or its progress lost (re-review I3)';
  END IF;

  -- I2: an error retries the part; the third on the same part fails the job.
  PERFORM public.claim_data_export();
  v_status := public.export_retry_part(v_id, 'Error');
  PERFORM public.claim_data_export();
  v_status := v_status || ',' || public.export_retry_part(v_id, 'Error');
  IF v_status <> 'queued,queued' OR EXISTS (SELECT 1 FROM public.media_deletion_queue
       WHERE bucket_id = 'data-exports' AND object_name = v_key AND not_before <= now()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a part error discarded the build (re-review I2): %', v_status;
  END IF;
  PERFORM public.claim_data_export();
  v_status := public.export_retry_part(v_id, 'Error');
  IF v_status <> 'failed' OR NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
       WHERE bucket_id = 'data-exports' AND object_name = v_key AND not_before <= now()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the third error on a part did not fail and drop the job (re-review I2)';
  END IF;

  -- I5: a job not done in 6 hours has failed, and its parts go.
  INSERT INTO public.data_export_jobs (user_id, status, requested_at, storage_keys)
  VALUES (v_a, 'queued', now() - interval '7 hours', ARRAY['x']) RETURNING id INTO v_id;
  INSERT INTO public.media_deletion_queue (bucket_id, object_name, not_before)
  VALUES ('data-exports', v_id || '/attune-export-1.zip', now() + interval '1 day');
  PERFORM pg_temp.as_user(v_a);
  IF (SELECT status FROM public.get_my_export()) <> 'failed' THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: a stalled job still shows as in progress (re-review I5)';
  END IF;
  RESET ROLE;
  PERFORM public.claim_data_export();
  IF (SELECT status FROM public.data_export_jobs WHERE id = v_id) <> 'failed' OR NOT EXISTS (
       SELECT 1 FROM public.media_deletion_queue
       WHERE bucket_id = 'data-exports' AND object_name = v_id || '/attune-export-1.zip' AND not_before <= now()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stalled job was not failed and dropped (re-review I5)';
  END IF;

  -- M8: while a new one builds, the ready one is still offered.
  INSERT INTO public.data_export_jobs (user_id, status, requested_at) VALUES (pg_temp.u(), 'queued', now() + interval '1 second');
  PERFORM pg_temp.as_user(pg_temp.u());
  IF (SELECT earlier_parts FROM public.get_my_export()) IS DISTINCT FROM 2 THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: the ready download is hidden by a new request (re-review M8)';
  END IF;
  RESET ROLE;
END $$;

-- 6. Spec 7 (plan review I6): the jar, hidden periods, the quiet state and
-- wins are the person's own and come with them; a note says what it is.
DO $$
DECLARE v_note uuid; b jsonb; c jsonb; r jsonb;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.p());
  v_note := public.send_appreciation(pg_temp.r1(), gen_random_uuid(), 'I noticed you fixed the tap. Thank you.');
  RESET ROLE;
  PERFORM pg_temp.as_user(pg_temp.u());
  PERFORM public.save_to_my_jar(v_note);
  PERFORM public.add_hidden_period(DATE '2025-03-01', DATE '2025-03-31');
  PERFORM public.set_my_quiet_state('hard_time');
  PERFORM public.share_a_win(pg_temp.r1(), 'New job');
  RESET ROLE;
  b := public.export_bundle(pg_temp.u());
  IF NOT coalesce(b->'personal'->'appreciation_jar' @> '[{"relationship":"relationship-1"}]', false)
     OR coalesce((b->'personal'->'appreciation_jar')::text LIKE '%' || v_note || '%', false)
     OR coalesce(length(b->'personal'->'appreciation_jar'->0->>'ref'), 0) <> 12 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the jar in the export: %', b->'personal'->'appreciation_jar';
  END IF;
  IF NOT coalesce(b->'personal'->'hidden_periods' @> '[{"starts_on":"2025-03-01","ends_on":"2025-03-31"}]', false)
     OR coalesce(b->'personal'->'quiet_state'->>'kind', '') <> 'hard_time' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: hidden periods / quiet state: % / %',
      b->'personal'->'hidden_periods', b->'personal'->'quiet_state';
  END IF;
  r := b->'relationships'->0;
  IF NOT coalesce(r->'moments' @> '[{"title":"New job","win":true}]', false) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the win in moments: %', r->'moments';
  END IF;
  SELECT p.rows INTO c FROM public.export_chat_page(pg_temp.u(), pg_temp.r1(), NULL, NULL, 1000) p;
  IF NOT coalesce(c @> '[{"kind":"i_noticed","text":"I noticed you fixed the tap. Thank you."}]', false) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the note in the chat export';
  END IF;
  -- The partner's export has no trace of my jar, periods or quiet state.
  b := public.export_bundle(pg_temp.p());
  IF jsonb_array_length(coalesce(b->'personal'->'appreciation_jar', '[]')) <> 0
     OR jsonb_array_length(coalesce(b->'personal'->'hidden_periods', '[]')) <> 0
     OR b->'personal'->'quiet_state' IS NOT NULL AND b->'personal'->'quiet_state' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: my Spec 7 data is in my partner''s export';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'data_export_contracts: all held'; END $$;
ROLLBACK;
