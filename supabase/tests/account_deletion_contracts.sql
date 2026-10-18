-- supabase/tests/account_deletion_contracts.sql
-- Spec 3b (research 06 §3 F13 (2); 05 D.3 #1 "deletion is deletion"):
-- prepare_account_deletion + DELETE FROM auth.users removes the person's own
-- data and shared-answer data, queues their media, never fails on a game or
-- poll they touched, and nothing resurfaces when the same phone signs up
-- again.
BEGIN;

-- D (01) is deleted. P (02) is D's current partner; Q (03) a former one.
INSERT INTO auth.users (id) VALUES
  ('9d100000-0000-0000-0000-000000000001'),
  ('9d100000-0000-0000-0000-000000000002'),
  ('9d100000-0000-0000-0000-000000000003')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9d100000-0000-0000-0000-000000000001', '+233599300001', 'Dee'),
  ('9d100000-0000-0000-0000-000000000002', '+233599300002', 'Pat'),
  ('9d100000-0000-0000-0000-000000000003', '+233599300003', 'Quinn')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.d() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9d100000-0000-0000-0000-000000000001'::uuid $$;
CREATE FUNCTION pg_temp.p() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9d100000-0000-0000-0000-000000000002'::uuid $$;
CREATE FUNCTION pg_temp.q() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9d100000-0000-0000-0000-000000000003'::uuid $$;
CREATE FUNCTION pg_temp.r() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9d200000-0000-0000-0000-000000000001'::uuid $$;
CREATE FUNCTION pg_temp.r0() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9d200000-0000-0000-0000-000000000002'::uuid $$;

INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at, ended_at)
VALUES
  (pg_temp.r(), pg_temp.d(), pg_temp.p(), 'active', CURRENT_DATE, now() - interval '9 days', now(), NULL),
  (pg_temp.r0(), pg_temp.q(), pg_temp.d(), 'ended', CURRENT_DATE, now() - interval '400 days', now(), now() - interval '200 days');
UPDATE public.relationships SET status = 'archived', chat_archived_at = now() - interval '170 days',
  chat_archived_reason = 'window_closed' WHERE id = pg_temp.r0();

-- Fixture rows skip triggers and FK checks (intents, profile rows); the
-- deletion below runs with both on.
SET LOCAL session_replication_role = replica;
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_url, media_thumbnail_url, media_type)
VALUES
  ('9d300000-0000-0000-0000-000000000001', pg_temp.r(), pg_temp.d(), gen_random_uuid(), 'from dee',
   'chat-media/9d-dee.jpg', 'chat-thumbnails/9d-dee.thumb', 'image'),
  ('9d300000-0000-0000-0000-000000000002', pg_temp.r(), pg_temp.p(), gen_random_uuid(), 'from pat', NULL, NULL, NULL);
INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
VALUES ('9d300000-0000-0000-0000-000000000001', 0, 'chat-media/9d-clip.mp4', 1000);
INSERT INTO public.dating_profile_photos (user_id, storage_key, position)
VALUES (pg_temp.d(), 'dating-photos/9d-photo.jpg', 1);
INSERT INTO public.reflection_journal_entries (user_id) VALUES (pg_temp.d());
INSERT INTO public.quiz_responses (user_id, quiz_type) VALUES (pg_temp.d(), 'attachment');
INSERT INTO public.personal_insights (user_id, relationship_id, insight_type, insight_body)
VALUES (pg_temp.d(), pg_temp.r(), 'pattern', 'now'), (pg_temp.d(), pg_temp.r0(), 'pattern', 'before');
-- A game P started, where D has the turn and won, and a round D is active in.
INSERT INTO public.game_sessions (id, relationship_id, initiator_id, game_type, current_turn_user_id, winner_user_id)
VALUES ('9d400000-0000-0000-0000-000000000001', pg_temp.r(), pg_temp.p(), 'truth_or_dare', pg_temp.d(), pg_temp.d()),
       ('9d400000-0000-0000-0000-000000000002', pg_temp.r0(), pg_temp.q(), 'thirty_six', NULL, NULL);
INSERT INTO public.game_session_rounds (id, session_id, round_number, active_partner_id, answer_a, answer_b)
VALUES ('9d500000-0000-0000-0000-000000000001', '9d400000-0000-0000-0000-000000000001', 1, pg_temp.d(), 'dee said', 'pat said'),
       ('9d500000-0000-0000-0000-000000000002', '9d400000-0000-0000-0000-000000000002', 1, NULL, 'quinn said', 'dee said');
-- A Love Map round on R (no session).
INSERT INTO public.game_session_rounds (id, relationship_id, round_number)
VALUES ('9d500000-0000-0000-0000-000000000003', pg_temp.r(), 1);
INSERT INTO public.mirror_round_truth (round_id, subject_id, truth_text)
VALUES ('9d500000-0000-0000-0000-000000000003', pg_temp.d(), 'dee truth');
INSERT INTO public.thirty_six_question_journeys (id, relationship_id) VALUES ('9d600000-0000-0000-0000-000000000001', pg_temp.r0());
INSERT INTO public.thirty_six_question_answers (round_id, user_id, answer_text)
VALUES ('9d500000-0000-0000-0000-000000000002', pg_temp.q(), 'quinn answer'),
       ('9d500000-0000-0000-0000-000000000002', pg_temp.d(), 'dee answer');
INSERT INTO public.patterns (relationship_id, pattern_type, severity) VALUES (pg_temp.r(), 'pursue_withdraw', 'watch');
INSERT INTO public.pulse_scores (relationship_id, week_ending, overall_score, communication, connection, conflict_health, alignment)
VALUES (pg_temp.r(), CURRENT_DATE, 70, 70, 70, 70, 70);
INSERT INTO public.analysis_sessions (relationship_id, started_at, ended_at) VALUES (pg_temp.r(), now() - interval '1 hour', now());
-- P's game-invite card for D's game: it goes with the game (the one
-- deliberate exception to "P's own messages stay"; plan review M4).
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_type, game_session_id)
VALUES ('9d300000-0000-0000-0000-000000000003', pg_temp.r(), pg_temp.p(), gen_random_uuid(), 'Truth or dare?', 'game', '9d400000-0000-0000-0000-000000000001');
-- A poll D made and a vote D cast.
INSERT INTO public.post_polls (id, opinion_id, created_by) VALUES ('9d700000-0000-0000-0000-000000000001', gen_random_uuid(), pg_temp.d());
INSERT INTO public.poll_votes (poll_id, option_id, user_id) VALUES ('9d700000-0000-0000-0000-000000000001', gen_random_uuid(), pg_temp.d());
-- Uploads D never attached; a safety event about D; P's exclusion of D.
INSERT INTO public.message_media_upload_intents (relationship_id, requester_id, storage_key, media_type, mime_type, expires_at)
VALUES (pg_temp.r(), pg_temp.d(), 'chat-media/9d-intent.jpg', 'image', 'image/jpeg', now() + interval '1 hour');
INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at)
VALUES (pg_temp.d(), 'dating-photos/9d-intent.jpg', 'image/jpeg', now() + interval '1 hour');
INSERT INTO public.safety_events (id, relationship_id, at_risk_user_id, source_event_key, trigger_tier, trigger_family, config_version)
VALUES ('9d800000-0000-0000-0000-000000000001', pg_temp.r(), pg_temp.d(), 'spec3b:test', 1, 'test', 'test');
INSERT INTO public.dating_former_partner_exclusions (user_id, excluded_phone_hmac, relationship_id)
VALUES (pg_temp.p(), 'hmac-of-dee', pg_temp.r());
-- Spec 7 (plan review M8): D's quiet state, hidden period, kept note and
-- dismissed win; and P's kept copy of a note D sent.
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_type)
VALUES ('9d300000-0000-0000-0000-0000000000a7', pg_temp.r(), pg_temp.d(), gen_random_uuid(), 'I noticed you laughed. Thank you.', 'appreciation'),
       ('9d300000-0000-0000-0000-0000000000a8', pg_temp.r(), pg_temp.p(), gen_random_uuid(), 'I noticed you cooked. Thank you.', 'appreciation');
INSERT INTO public.appreciation_jar (user_id, message_id) VALUES
  (pg_temp.p(), '9d300000-0000-0000-0000-0000000000a7'), (pg_temp.d(), '9d300000-0000-0000-0000-0000000000a8');
INSERT INTO public.quiet_states (user_id, kind, until) VALUES (pg_temp.d(), 'loss', now() + interval '5 days');
INSERT INTO public.hidden_periods (user_id, starts_on, ends_on) VALUES (pg_temp.d(), DATE '2025-01-01', DATE '2025-02-01');
-- Spec 8 (plan review I3): D's private safety check goes with them.
INSERT INTO public.safety_self_checks (user_id, relationship_id, answered_at, until, positive_until)
VALUES (pg_temp.d(), pg_temp.r(), now(), now() + interval '180 days', now() + interval '180 days');
INSERT INTO public.timeline_events (id, relationship_id, logged_by, event_type, title, occurred_at)
VALUES ('9d900000-0000-0000-0000-0000000000a1', pg_temp.r(), pg_temp.p(), 'highlight', 'P win', CURRENT_DATE);
INSERT INTO public.win_card_dismissals (event_id, user_id) VALUES ('9d900000-0000-0000-0000-0000000000a1', pg_temp.d());
SET LOCAL session_replication_role = origin;

-- The deletion, as delete-account runs it (service role).
SELECT public.prepare_account_deletion(pg_temp.d());
DELETE FROM auth.users WHERE id = pg_temp.d();

DO $$
DECLARE v record; v_n int;
BEGIN
  -- R ended without an ender left to name; R0 stays archived.
  SELECT * INTO v FROM public.relationships WHERE id = pg_temp.r();
  IF v.status <> 'ended' OR v.ended_at IS NULL OR v.ended_by IS NOT NULL OR v.user_a IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: R after deletion: status %, ended_by %, user_a %', v.status, v.ended_by, v.user_a;
  END IF;

  -- Shared-answer and derived data of both of D's relationships is gone.
  FOR v IN SELECT * FROM (VALUES
    ('game_sessions'), ('game_session_rounds'), ('thirty_six_question_journeys'),
    ('analysis_sessions'), ('attachment_compatibility_cache'), ('ask2_state')) t(tbl)
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I WHERE relationship_id IN ($1, $2)', v.tbl)
      INTO v_n USING pg_temp.r(), pg_temp.r0();
    IF v_n <> 0 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % rows of D''s relationships left in %', v_n, v.tbl;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.game_session_rounds WHERE session_id IN
             ('9d400000-0000-0000-0000-000000000001', '9d400000-0000-0000-0000-000000000002'))
     OR EXISTS (SELECT 1 FROM public.thirty_six_question_answers WHERE round_id = '9d500000-0000-0000-0000-000000000002')
     OR EXISTS (SELECT 1 FROM public.mirror_round_truth WHERE round_id = '9d500000-0000-0000-0000-000000000003') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: game answers that include D''s survived';
  END IF;

  -- Role-free shared history stays with the space for P (review I1).
  IF NOT EXISTS (SELECT 1 FROM public.pulse_scores WHERE relationship_id = pg_temp.r())
     OR NOT EXISTS (SELECT 1 FROM public.patterns WHERE relationship_id = pg_temp.r()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: P lost the shared Pulse history or patterns';
  END IF;

  -- Only anonymised safety events survive (F13 (3)); P keeps the exclusion.
  IF EXISTS (SELECT 1 FROM public.safety_events WHERE id = '9d800000-0000-0000-0000-000000000001'
             AND (at_risk_user_id IS NOT NULL OR anonymised_at IS NULL)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a safety event about D was not anonymised';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_former_partner_exclusions
                 WHERE user_id = pg_temp.p() AND excluded_phone_hmac = 'hmac-of-dee') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: P lost the dating exclusion of D';
  END IF;
  IF EXISTS (SELECT 1 FROM public.couple_events WHERE owner_id = pg_temp.d())
     OR EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE verified_by = pg_temp.d())
     OR EXISTS (SELECT 1 FROM public.couple_events WHERE owner_proposed_to = pg_temp.d()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a column without an FK still names D';
  END IF;

  IF EXISTS (SELECT 1 FROM public.messages WHERE id = '9d300000-0000-0000-0000-000000000003') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a game card outlived its game';
  END IF;
  -- D's messages are gone; P's own stay for P's window.
  IF EXISTS (SELECT 1 FROM public.messages WHERE id = '9d300000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D''s message survived';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.messages WHERE id = '9d300000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: P''s own message was deleted';
  END IF;

  -- D's media is queued for deletion, every bucket.
  FOR v IN SELECT * FROM (VALUES
    ('message-media', 'chat-media/9d-dee.jpg'),
    ('message-media', 'chat-thumbnails/9d-dee.thumb'),
    ('message-media', 'chat-media/9d-clip.mp4'),
    ('dating-profile-photos', 'dating-photos/9d-photo.jpg'),
    ('message-media', 'chat-media/9d-intent.jpg'),
    ('dating-profile-photos', 'dating-photos/9d-intent.jpg')) t(b, n)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = v.b AND object_name = v.n) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % / % was not queued', v.b, v.n;
    END IF;
  END LOOP;

  -- Nothing anywhere still names D.
  FOR v IN
    SELECT c.conrelid::regclass AS tbl, a.attname AS col
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
    WHERE c.contype = 'f' AND c.confrelid IN ('public.users'::regclass, 'auth.users'::regclass)
  LOOP
    EXECUTE format('SELECT count(*) FROM %s WHERE %I = $1', v.tbl, v.col) INTO v_n USING pg_temp.d();
    IF v_n <> 0 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: %.% still holds D (% rows)', v.tbl, v.col, v_n;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.personal_insights WHERE user_id = pg_temp.d()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D''s insights survived';
  END IF;
  -- Spec 7 (M8): nothing of D's remains in the new tables, and P's kept
  -- copy of D's note went with it.
  IF EXISTS (SELECT 1 FROM public.quiet_states WHERE user_id = pg_temp.d())
     OR EXISTS (SELECT 1 FROM public.hidden_periods WHERE user_id = pg_temp.d())
     OR EXISTS (SELECT 1 FROM public.appreciation_jar WHERE user_id = pg_temp.d())
     OR EXISTS (SELECT 1 FROM public.win_card_dismissals WHERE user_id = pg_temp.d())
     OR EXISTS (SELECT 1 FROM public.safety_self_checks WHERE user_id = pg_temp.d()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D''s Spec 7 rows survived';
  END IF;
  IF EXISTS (SELECT 1 FROM public.appreciation_jar WHERE message_id = '9d300000-0000-0000-0000-0000000000a7') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: P still keeps a note from a deleted account';
  END IF;
END $$;

-- The same phone signs up again: a new person, with nothing of D's.
INSERT INTO auth.users (id) VALUES ('9d100000-0000-0000-0000-000000000004');
INSERT INTO public.users (id, phone, display_name)
VALUES ('9d100000-0000-0000-0000-000000000004', '+233599300001', 'Dee again');
-- A brand-new person with a never-seen phone: whatever a signup creates by
-- itself (default settings rows) is the baseline, not resurfaced data.
INSERT INTO auth.users (id) VALUES ('9d100000-0000-0000-0000-000000000005');
INSERT INTO public.users (id, phone, display_name)
VALUES ('9d100000-0000-0000-0000-000000000005', '+233599300099', 'Control');

DO $$
DECLARE v record; v_n int;
BEGIN
  FOR v IN
    SELECT c.conrelid::regclass AS tbl, a.attname AS col
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
    WHERE c.contype = 'f' AND c.confrelid IN ('public.users'::regclass, 'auth.users'::regclass)
      AND c.conrelid NOT IN ('public.users'::regclass)
  LOOP
    EXECUTE format('SELECT (SELECT count(*) FROM %1$s WHERE %2$I = $1) - (SELECT count(*) FROM %1$s WHERE %2$I = $2)', v.tbl, v.col)
      INTO v_n USING '9d100000-0000-0000-0000-000000000004'::uuid, '9d100000-0000-0000-0000-000000000005'::uuid;
    IF v_n <> 0 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the re-registered phone sees % more %.% rows than a new person', v_n, v.tbl, v.col;
    END IF;
  END LOOP;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '9d100000-0000-0000-0000-000000000004', 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_n FROM public.get_my_relationship_lifecycle();
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: the re-registered phone sees an old relationship'; END IF;
  SELECT count(*) INTO v_n FROM public.relationships;
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the re-registered phone reads % relationships', v_n; END IF;
END $$;

-- Only the service role prepares a deletion.
DO $$
BEGIN
  IF has_function_privilege('authenticated', 'public.prepare_account_deletion(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.prepare_account_deletion(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can prepare an account deletion';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'account_deletion_contracts: all held'; END $$;
ROLLBACK;
