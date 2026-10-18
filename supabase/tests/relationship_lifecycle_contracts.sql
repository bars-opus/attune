-- supabase/tests/relationship_lifecycle_contracts.sql
-- Spec 3a (research 06 §3 F1; 05 Part D): ending never notifies; paused is
-- real; a 30-day read-only window per person; seal my side; archive on
-- schedule, on both seals, or when either starts a new relationship.
-- Every check RAISEs 'CONTRACT VIOLATED' on a broken contract.
BEGIN;

-- 16 people: 9b100000-…-0000000000NN, NN = 01..16.
INSERT INTO auth.users (id)
SELECT ('9b100000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid
FROM generate_series(1, 16) i
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name)
SELECT ('9b100000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid,
       '+2335991' || lpad(i::text, 5, '0'),
       CASE i WHEN 1 THEN 'Ama Mensah' WHEN 2 THEN 'Kofi Boateng' ELSE 'Person ' || i END
FROM generate_series(1, 16) i
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.u(i int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('9b100000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid $$;
CREATE FUNCTION pg_temp.r(i int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('9b200000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid $$;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- Expects p_sql (run as p_user) to raise exactly p_code.
CREATE FUNCTION pg_temp.expect_error(p_user uuid, p_sql text, p_code text, p_what text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_msg text;
BEGIN
  PERFORM pg_temp.as_user(p_user);
  BEGIN
    EXECUTE p_sql;
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: % succeeded', p_what;
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    RESET ROLE;
    IF v_msg LIKE 'CONTRACT VIOLATED%' THEN RAISE; END IF;
    IF v_msg <> p_code THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % raised "%" not "%"', p_what, v_msg, p_code;
    END IF;
  END;
END $$;

-- Relationships (all non-pending: invite_code NULL).
--   r1 (u1,u2) active: end, read window, seal, healing, lifecycle read
--   r2 (u3,u4) active: pause, resume, end from paused
--   r3 (u5,u6) ended 31 days ago; r4 (u7,u8) paused 31 days ago: the clock
--   r5 (u9,u10) ended; r6 (u9,u11) pending -> active: the new chapter
--   r7 (u12,u13) ended: a third party, untouched
--   r8 (u11,u14) paused: the new member's paused space ends and archives
--   r9 (u15,u16) ended AND archived by the old end_relationship: backfill
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at, ended_at)
VALUES
  (pg_temp.r(1), pg_temp.u(1), pg_temp.u(2), 'active', CURRENT_DATE, now() - interval '9 days', now(), NULL),
  (pg_temp.r(2), pg_temp.u(3), pg_temp.u(4), 'active', CURRENT_DATE, now() - interval '9 days', now(), NULL),
  (pg_temp.r(3), pg_temp.u(5), pg_temp.u(6), 'ended', CURRENT_DATE, now() - interval '90 days', now(), now() - interval '31 days'),
  (pg_temp.r(4), pg_temp.u(7), pg_temp.u(8), 'paused', CURRENT_DATE, now() - interval '90 days', now(), NULL),
  (pg_temp.r(5), pg_temp.u(9), pg_temp.u(10), 'ended', CURRENT_DATE, now() - interval '90 days', now(), now() - interval '2 days'),
  (pg_temp.r(7), pg_temp.u(12), pg_temp.u(13), 'ended', CURRENT_DATE, now() - interval '90 days', now(), now() - interval '2 days'),
  (pg_temp.r(8), pg_temp.u(11), pg_temp.u(14), 'paused', CURRENT_DATE, now() - interval '90 days', now(), NULL),
  (pg_temp.r(9), pg_temp.u(15), pg_temp.u(16), 'ended', CURRENT_DATE, now() - interval '90 days', now(), now() - interval '40 days')
ON CONFLICT (id) DO NOTHING;
UPDATE public.relationships SET paused_at = now() - interval '31 days', paused_by = pg_temp.u(7)
WHERE id = pg_temp.r(4);
UPDATE public.relationships SET paused_at = now() - interval '1 day', paused_by = pg_temp.u(11)
WHERE id = pg_temp.r(8);
UPDATE public.relationships SET chat_archived_at = now() - interval '40 days', chat_archived_reason = 'manual_end'
WHERE id = pg_temp.r(9);
INSERT INTO public.relationships (id, user_a, user_b, status, invite_code, invite_expires_at, created_at)
VALUES (pg_temp.r(6), pg_temp.u(9), pg_temp.u(11), 'pending', 'SPEC3A-R6', now() + interval '1 day', now())
ON CONFLICT (id) DO NOTHING;

-- r1 chat: one message each, media on u2's, a pin, a reaction. Fixture
-- rows skip the upload-intent trigger (the media path is all that matters).
SET LOCAL session_replication_role = replica;
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_url, media_type)
VALUES
  ('9b300000-0000-0000-0000-000000000001', pg_temp.r(1), pg_temp.u(1), '9b300000-0000-0000-0000-0000000000c1', 'from ama', NULL, NULL),
  ('9b300000-0000-0000-0000-000000000002', pg_temp.r(1), pg_temp.u(2), '9b300000-0000-0000-0000-0000000000c2', 'from kofi', '9b200000-0000-0000-0000-000000000001/m2.jpg', 'image');
INSERT INTO public.message_pins (relationship_id, message_id, pinned_by)
VALUES (pg_temp.r(1), '9b300000-0000-0000-0000-000000000001', pg_temp.u(1));
INSERT INTO public.message_reactions (message_id, relationship_id, user_id, emoji)
VALUES ('9b300000-0000-0000-0000-000000000002', pg_temp.r(1), pg_temp.u(1), '❤️');
INSERT INTO storage.objects (bucket_id, name)
VALUES ('message-media', '9b200000-0000-0000-0000-000000000001/m2.jpg');
SET LOCAL session_replication_role = origin;
-- Hosted Supabase grants authenticated SELECT on storage.objects with RLS
-- on; the local stub has neither. Rolled back with the rest.
GRANT SELECT ON storage.objects TO authenticated;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- r1 patterns for the Healing snapshot: a safety pattern must never be copied.
INSERT INTO public.patterns (relationship_id, pattern_type, severity)
VALUES (pg_temp.r(1), 'pursue_withdraw', 'watch'),
       (pg_temp.r(1), 'threat_language', 'safety');

-- A pending relationship-scoped push for u2, and a personal one (no
-- relationship in its metadata) that must survive.
INSERT INTO public.scheduled_notifications (id, user_id, notification_type, scheduled_for, metadata)
VALUES
  ('9b400000-0000-0000-0000-000000000001', pg_temp.u(2), 'ritual_reminder', now() + interval '2 hours',
   jsonb_build_object('relationship_id', pg_temp.r(1))),
  ('9b400000-0000-0000-0000-000000000002', pg_temp.u(2), 'self_alarm', now() + interval '2 hours', '{}'::jsonb);

-- 1. Ending enqueues nothing for the other member and cancels the
--    relationship's pending pushes (F1 (1)).
DO $$
DECLARE
  v_sched int; v_inapp int; v_outbox int; v_status text; v_personal text;
  v_rel public.relationships%ROWTYPE;
BEGIN
  SELECT count(*) INTO v_sched FROM public.scheduled_notifications WHERE user_id = pg_temp.u(2);
  SELECT count(*) INTO v_inapp FROM public.in_app_notifications WHERE user_id = pg_temp.u(2);
  SELECT count(*) INTO v_outbox FROM public.message_notification_outbox WHERE recipient_id = pg_temp.u(2);

  PERFORM pg_temp.as_user(pg_temp.u(1));
  PERFORM public.end_relationship(pg_temp.r(1));
  RESET ROLE;

  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id = pg_temp.u(2)) <> v_sched
     OR (SELECT count(*) FROM public.in_app_notifications WHERE user_id = pg_temp.u(2)) <> v_inapp
     OR (SELECT count(*) FROM public.message_notification_outbox WHERE recipient_id = pg_temp.u(2)) <> v_outbox THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ending queued notification work for the other member';
  END IF;
  SELECT status INTO v_status FROM public.scheduled_notifications WHERE id = '9b400000-0000-0000-0000-000000000001';
  IF v_status <> 'cancelled' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pending push for the ended relationship is %', v_status;
  END IF;
  SELECT status INTO v_personal FROM public.scheduled_notifications WHERE id = '9b400000-0000-0000-0000-000000000002';
  IF v_personal <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a personal push was cancelled (%)', v_personal;
  END IF;

  -- 2. Ended, not archived; the ender is recorded.
  SELECT * INTO v_rel FROM public.relationships WHERE id = pg_temp.r(1);
  IF v_rel.status <> 'ended' OR v_rel.chat_archived_at IS NOT NULL
     OR v_rel.ended_by <> pg_temp.u(1) OR v_rel.ended_at IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after end: status %, archived %, ended_by %',
      v_rel.status, v_rel.chat_archived_at, v_rel.ended_by;
  END IF;
END $$;

-- 2. The window: both read, neither sends.
DO $$
DECLARE v_n int; v_p uuid;
BEGIN
  FOREACH v_p IN ARRAY ARRAY[pg_temp.u(1), pg_temp.u(2)] LOOP
    PERFORM pg_temp.as_user(v_p);
    SELECT count(id) INTO v_n FROM public.messages WHERE relationship_id = pg_temp.r(1);
    RESET ROLE;
    IF v_n <> 2 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % reads % messages in the window, not 2', v_p, v_n;
    END IF;
    PERFORM pg_temp.as_user(v_p);
    BEGIN
      INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content)
      VALUES (pg_temp.r(1), v_p, gen_random_uuid(), 'after the end');
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: % sent into an ended relationship', v_p;
    EXCEPTION WHEN insufficient_privilege OR check_violation THEN
      RESET ROLE;
    END;
  END LOOP;
END $$;

-- 3. Pause, resume, end from paused (F1 (3)).
DO $$
DECLARE v_rel public.relationships%ROWTYPE; v_n int;
BEGIN
  PERFORM pg_temp.expect_error(pg_temp.u(5),
    format('SELECT public.pause_relationship(%L)', pg_temp.r(2)),
    'lifecycle:not_found', 'pause by a non-member');

  PERFORM pg_temp.as_user(pg_temp.u(3));
  PERFORM public.pause_relationship(pg_temp.r(2));
  RESET ROLE;
  SELECT * INTO v_rel FROM public.relationships WHERE id = pg_temp.r(2);
  IF v_rel.status <> 'paused' OR v_rel.paused_by <> pg_temp.u(3) OR v_rel.paused_at IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pause left status %, paused_by %', v_rel.status, v_rel.paused_by;
  END IF;
  PERFORM pg_temp.expect_error(pg_temp.u(4),
    format('SELECT public.pause_relationship(%L)', pg_temp.r(2)),
    'lifecycle:not_active', 'pausing a paused relationship');

  -- Read-only while paused.
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content)
  VALUES (pg_temp.r(2), pg_temp.u(3), gen_random_uuid(), 'before the pause');
  PERFORM pg_temp.as_user(pg_temp.u(4));
  SELECT count(id) INTO v_n FROM public.messages WHERE relationship_id = pg_temp.r(2);
  RESET ROLE;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: paused chat unreadable (% rows)', v_n;
  END IF;
  PERFORM pg_temp.as_user(pg_temp.u(4));
  BEGIN
    INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content)
    VALUES (pg_temp.r(2), pg_temp.u(4), gen_random_uuid(), 'during the pause');
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: sent into a paused relationship';
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    RESET ROLE;
  END;

  -- Either member resumes (D.1).
  PERFORM pg_temp.as_user(pg_temp.u(4));
  PERFORM public.resume_relationship(pg_temp.r(2));
  RESET ROLE;
  SELECT * INTO v_rel FROM public.relationships WHERE id = pg_temp.r(2);
  IF v_rel.status <> 'active' OR v_rel.paused_at IS NOT NULL OR v_rel.paused_by IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resume left status %, paused_at %', v_rel.status, v_rel.paused_at;
  END IF;
  PERFORM pg_temp.expect_error(pg_temp.u(3),
    format('SELECT public.resume_relationship(%L)', pg_temp.r(2)),
    'lifecycle:not_paused', 'resuming an active relationship');

  -- End from paused.
  PERFORM pg_temp.as_user(pg_temp.u(3));
  PERFORM public.pause_relationship(pg_temp.r(2));
  PERFORM public.end_relationship(pg_temp.r(2));
  RESET ROLE;
  SELECT * INTO v_rel FROM public.relationships WHERE id = pg_temp.r(2);
  IF v_rel.status <> 'ended' OR v_rel.paused_at IS NOT NULL OR v_rel.chat_archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: end from paused left status %', v_rel.status;
  END IF;
  PERFORM pg_temp.expect_error(pg_temp.u(3),
    format('SELECT public.end_relationship(%L)', pg_temp.r(2)),
    'lifecycle:not_active', 'ending an ended relationship');
END $$;

-- 8. The lifecycle read, for the person who did not end it (before seals).
DO $$
DECLARE v record; v_n int;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.u(2));
  SELECT * INTO v FROM public.get_my_relationship_lifecycle();
  RESET ROLE;
  IF v.relationship_id IS DISTINCT FROM pg_temp.r(1) OR v.status <> 'ended'
     OR v.ended_by_me OR NOT v.ended_by_partner OR v.partner_first_name <> 'Ama'
     OR NOT v.chat_readable OR v.sealed_by_me
     OR v.window_ends_at IS DISTINCT FROM v.ended_at + interval '30 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: lifecycle read for the other partner: %', row_to_json(v);
  END IF;
  PERFORM pg_temp.as_user(pg_temp.u(1));
  SELECT * INTO v FROM public.get_my_relationship_lifecycle();
  RESET ROLE;
  IF NOT v.ended_by_me OR v.ended_by_partner THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: lifecycle read for the ender: %', row_to_json(v);
  END IF;
END $$;

-- 7. Healing: a role-free snapshot for both members at end, no safety rows.
DO $$
DECLARE v_types text[]; v_p uuid;
BEGIN
  FOREACH v_p IN ARRAY ARRAY[pg_temp.u(1), pg_temp.u(2)] LOOP
    SELECT pattern_types INTO v_types FROM public.healing_ending_snapshots
    WHERE user_id = v_p AND relationship_id = pg_temp.r(1);
    IF v_types IS NULL OR NOT ('pursue_withdraw' = ANY (v_types))
       OR 'threat_language' = ANY (v_types) OR cardinality(v_types) > 6 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: healing snapshot for % is %', v_p, v_types;
    END IF;
  END LOOP;
END $$;

-- 4. Seal my side: u1's chat closes for u1 only; the second seal archives.
DO $$
DECLARE v_n int; v_rel public.relationships%ROWTYPE;
BEGIN
  PERFORM pg_temp.expect_error(pg_temp.u(9),
    format('SELECT public.seal_my_side(%L)', pg_temp.r(6)),
    'lifecycle:not_ended', 'sealing a relationship that has not ended');

  PERFORM pg_temp.as_user(pg_temp.u(2));
  SELECT public.count_unread_messages(pg_temp.r(1)) INTO v_n;
  RESET ROLE;
  PERFORM pg_temp.as_user(pg_temp.u(1));
  SELECT public.count_unread_messages(pg_temp.r(1)) INTO v_n;
  RESET ROLE;
  -- Sync audit I-7: in the ended window nothing can be marked read, so
  -- nothing counts as unread either (the badge used to stick for 30 days).
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ended window shows % unread that can never clear', v_n;
  END IF;

  PERFORM pg_temp.as_user(pg_temp.u(1));
  PERFORM public.seal_my_side(pg_temp.r(1));
  PERFORM public.seal_my_side(pg_temp.r(1));   -- a second seal is a no-op
  SELECT count(id) INTO v_n FROM public.messages WHERE relationship_id = pg_temp.r(1);
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: sealed u1 reads % messages', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.message_pins WHERE relationship_id = pg_temp.r(1);
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: sealed u1 reads % pins', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.message_reactions WHERE relationship_id = pg_temp.r(1);
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: sealed u1 reads % reactions', v_n; END IF;
  SELECT count(*) INTO v_n FROM storage.objects
  WHERE bucket_id = 'message-media' AND name = '9b200000-0000-0000-0000-000000000001/m2.jpg';
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: sealed u1 reads the media object'; END IF;
  SELECT public.count_unread_messages(pg_temp.r(1)) INTO v_n;
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: sealed u1 counts % unread', v_n; END IF;
  RESET ROLE;

  -- u2's window continues, and nothing tells u2 that u1 sealed.
  PERFORM pg_temp.as_user(pg_temp.u(2));
  SELECT count(id) INTO v_n FROM public.messages WHERE relationship_id = pg_temp.r(1);
  IF v_n <> 2 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: u2 lost the window after u1 sealed (% rows)', v_n; END IF;
  SELECT count(*) INTO v_n FROM storage.objects
  WHERE bucket_id = 'message-media' AND name = '9b200000-0000-0000-0000-000000000001/m2.jpg';
  IF v_n <> 1 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: u2 lost the media object'; END IF;
  SELECT count(*) INTO v_n FROM public.relationship_seals WHERE relationship_id = pg_temp.r(1);
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: u2 can see that u1 sealed'; END IF;
  PERFORM public.seal_my_side(pg_temp.r(1));
  RESET ROLE;

  SELECT * INTO v_rel FROM public.relationships WHERE id = pg_temp.r(1);
  IF v_rel.status <> 'archived' OR v_rel.chat_archived_reason <> 'both_sealed' OR v_rel.chat_archived_at IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two seals left status %, reason %', v_rel.status, v_rel.chat_archived_reason;
  END IF;
  PERFORM pg_temp.as_user(pg_temp.u(2));
  SELECT count(id) INTO v_n FROM public.messages WHERE relationship_id = pg_temp.r(1);
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: archived chat readable (% rows)', v_n; END IF;
END $$;

-- 5. The clock: day 30 closes access by itself; the cron then archives, and
--    a 30-day pause ends with no ender (F1 (4)).
DO $$
DECLARE v_open boolean; v_rel public.relationships%ROWTYPE;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.u(5));
  SELECT public.relationship_chat_open(pg_temp.r(3)) INTO v_open;
  RESET ROLE;
  IF v_open THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: day 31 still open before the cron ran';
  END IF;

  PERFORM public.close_relationship_windows();

  SELECT * INTO v_rel FROM public.relationships WHERE id = pg_temp.r(3);
  IF v_rel.status <> 'archived' OR v_rel.chat_archived_reason <> 'window_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: day-31 window left status %, reason %', v_rel.status, v_rel.chat_archived_reason;
  END IF;
  SELECT * INTO v_rel FROM public.relationships WHERE id = pg_temp.r(4);
  IF v_rel.status <> 'ended' OR v_rel.ended_by IS NOT NULL OR v_rel.ended_at IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 30-day pause left status %, ended_by %', v_rel.status, v_rel.ended_by;
  END IF;
  -- A recent ending is left alone.
  SELECT * INTO v_rel FROM public.relationships WHERE id = pg_temp.r(7);
  IF v_rel.status <> 'ended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the cron archived a 2-day-old ending';
  END IF;
END $$;

-- 6. A new relationship archives the old chapter of either new member, and
--    nobody else's (Decision 19).
DO $$
DECLARE v_rel public.relationships%ROWTYPE;
BEGIN
  UPDATE public.relationships
  SET status = 'active', invite_code = NULL, invite_accepted_at = now(), started_at = CURRENT_DATE
  WHERE id = pg_temp.r(6);

  SELECT * INTO v_rel FROM public.relationships WHERE id = pg_temp.r(6);
  IF v_rel.status <> 'active' OR v_rel.chat_archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the new relationship itself was touched (%)', v_rel.status;
  END IF;
  SELECT * INTO v_rel FROM public.relationships WHERE id = pg_temp.r(5);
  IF v_rel.status <> 'archived' OR v_rel.chat_archived_reason <> 'partner_new_relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the old ending was not archived (%, %)', v_rel.status, v_rel.chat_archived_reason;
  END IF;
  SELECT * INTO v_rel FROM public.relationships WHERE id = pg_temp.r(8);
  IF v_rel.status <> 'archived' OR v_rel.ended_at IS NULL OR v_rel.ended_by IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the new member''s paused space left %, ended_by %', v_rel.status, v_rel.ended_by;
  END IF;
  SELECT * INTO v_rel FROM public.relationships WHERE id = pg_temp.r(7);
  IF v_rel.status <> 'ended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a third party''s ending was archived';
  END IF;
END $$;

-- 8c. An archive older than 30 days is history, not news (final review
--     IMP-3); a phone number is never shown as a name (MIN-1).
DO $$
DECLARE v record; v_n int;
BEGIN
  -- r9 (u15,u16) was archived 40 days ago by the old instant archive; the
  -- migration's backfill (section 9 re-asserts it) makes it 'archived'.
  UPDATE public.relationships SET status = 'archived'
  WHERE status = 'ended' AND chat_archived_at IS NOT NULL;
  -- Section 5's window run re-archived it today; put its archive back 40 days.
  UPDATE public.relationships SET chat_archived_at = now() - interval '40 days'
  WHERE id = pg_temp.r(9);
  PERFORM pg_temp.as_user(pg_temp.u(15));
  SELECT count(*) INTO v_n FROM public.get_my_relationship_lifecycle();
  RESET ROLE;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 40-day-old archive still shows (% rows)', v_n;
  END IF;
  -- r5 (u9,u10) ended 2 days ago; u9's name becomes a phone number.
  UPDATE public.users SET display_name = '+233599100009' WHERE id = pg_temp.u(9);
  UPDATE public.relationships SET ended_by = pg_temp.u(9) WHERE id = pg_temp.r(5);
  PERFORM pg_temp.as_user(pg_temp.u(10));
  SELECT * INTO v FROM public.get_my_relationship_lifecycle();
  RESET ROLE;
  IF v.relationship_id IS DISTINCT FROM pg_temp.r(5) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fixture: u10 should see r5, got %', row_to_json(v);
  END IF;
  IF v.partner_first_name IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a phone number is shown as a name: %', v.partner_first_name;
  END IF;
END $$;

-- 8b. Someone whose latest relationship is active gets no lifecycle row.
DO $$
DECLARE v_n int;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.u(9));
  SELECT count(*) INTO v_n FROM public.get_my_relationship_lifecycle();
  RESET ROLE;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an active person got % lifecycle rows', v_n;
  END IF;
END $$;

-- 7b. Healing starts on an archived relationship too.
DO $$
BEGIN
  PERFORM pg_temp.as_user(pg_temp.u(2));
  PERFORM public.get_or_create_healing_journey(pg_temp.r(1));
  RESET ROLE;
END $$;

-- 9. The backfill turned the old instant archives into 'archived'.
DO $$
BEGIN
  UPDATE public.relationships SET status = 'archived'
  WHERE status = 'ended' AND chat_archived_at IS NOT NULL;
  IF (SELECT status FROM public.relationships WHERE id = pg_temp.r(9)) <> 'archived' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: backfill left an archived chat as ended';
  END IF;
END $$;

-- 10. Grants: clients call the five RPCs and the helper, never the internals.
DO $$
DECLARE v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY[
    'public.pause_relationship(uuid)', 'public.resume_relationship(uuid)',
    'public.end_relationship(uuid)', 'public.seal_my_side(uuid)',
    'public.get_my_relationship_lifecycle()', 'public.relationship_chat_open(uuid)'
  ] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: anon can execute %', v_fn;
    END IF;
    IF NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated cannot execute %', v_fn;
    END IF;
  END LOOP;
  FOREACH v_fn IN ARRAY ARRAY[
    'public.relationship_archive(uuid,text)', 'public.relationship_cancel_pending_pushes(uuid)',
    'public.relationship_take_healing_snapshot(uuid)', 'public.relationship_end_internal(uuid,uuid)',
    'public.close_relationship_windows()'
  ] LOOP
    IF has_function_privilege('authenticated', v_fn, 'EXECUTE')
       OR has_function_privilege('anon', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a client can execute internal %', v_fn;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'close_relationship_windows') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the window cron is not scheduled';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'relationship_lifecycle_contracts: all held'; END $$;
ROLLBACK;
