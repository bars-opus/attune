-- supabase/tests/relationship_lifecycle_hardening_contracts.sql
-- Spec 3a plan-review amendments (2026-10-18): a paused or ended space is
-- frozen for writes too (C2); a service-role call can never end anything
-- (C1); the ex can't read who ended it, who paused or why it was archived
-- (I1); reminders stop and can come back after a resume (I2, I3); nothing
-- is logged into a frozen chapter (I4); Dating treats a pause as a
-- relationship (I5); pause keeps calendar links, ending revokes them (I6);
-- the pause decision closes on time (I12).
BEGIN;

INSERT INTO auth.users (id)
SELECT ('9c100000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid
FROM generate_series(1, 4) i ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name)
SELECT ('9c100000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid,
       '+2335992' || lpad(i::text, 5, '0'), 'Hardening ' || i
FROM generate_series(1, 4) i ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.u(i int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('9c100000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid $$;
CREATE FUNCTION pg_temp.ra() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT '9c200000-0000-0000-0000-000000000001'::uuid $$;
CREATE FUNCTION pg_temp.rb() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT '9c200000-0000-0000-0000-000000000002'::uuid $$;
CREATE FUNCTION pg_temp.msg() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT '9c300000-0000-0000-0000-000000000001'::uuid $$;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at)
VALUES
  (pg_temp.ra(), pg_temp.u(1), pg_temp.u(2), 'active', CURRENT_DATE, now() - interval '9 days', now()),
  (pg_temp.rb(), pg_temp.u(3), pg_temp.u(4), 'paused', CURRENT_DATE, now() - interval '90 days', now());
UPDATE public.relationships SET paused_at = now() - interval '31 days', paused_by = pg_temp.u(3)
WHERE id = pg_temp.rb();

INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content)
VALUES (pg_temp.msg(), pg_temp.ra(), pg_temp.u(2), '9c300000-0000-0000-0000-0000000000c1', 'hello');
INSERT INTO public.message_pins (relationship_id, message_id, pinned_by)
VALUES (pg_temp.ra(), pg_temp.msg(), pg_temp.u(1));
INSERT INTO public.message_reactions (message_id, relationship_id, user_id, emoji)
VALUES (pg_temp.msg(), pg_temp.ra(), pg_temp.u(1), '❤️');
SET LOCAL session_replication_role = replica;
INSERT INTO public.couple_busy_blocks (relationship_id, user_id, starts_at, ends_at)
VALUES (pg_temp.ra(), pg_temp.u(1), date_trunc('hour', now()) + interval '1 day', date_trunc('hour', now()) + interval '1 day 1 hour');
SET LOCAL session_replication_role = origin;
INSERT INTO public.calendar_feed_tokens (user_id, token_hash)
VALUES (pg_temp.u(1), repeat('a', 64)), (pg_temp.u(2), repeat('b', 64));
INSERT INTO public.reminders (id, relationship_id, created_by, reminder_type, title, remind_at)
VALUES ('9c400000-0000-0000-0000-000000000001', pg_temp.ra(), pg_temp.u(1), 'anniversary', 'Our day', now() + interval '3 days');
-- A reminder push written before this change: reminder_id, no relationship_id.
INSERT INTO public.scheduled_notifications (id, user_id, notification_type, scheduled_for, metadata, source_key)
VALUES ('9c500000-0000-0000-0000-000000000001', pg_temp.u(2), 'immediate', now() + interval '1 hour',
        jsonb_build_object('type', 'reminder_upcoming', 'reminder_id', '9c400000-0000-0000-0000-000000000001'),
        'reminder:9c40:spec3a');

-- Every write a frozen space must refuse, run as both members.
CREATE FUNCTION pg_temp.assert_frozen(p_when text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_n int; v_p uuid; v_active uuid;
BEGIN
  FOREACH v_p IN ARRAY ARRAY[pg_temp.u(1), pg_temp.u(2)] LOOP
    PERFORM pg_temp.as_user(v_p);
    DELETE FROM public.message_pins WHERE relationship_id = pg_temp.ra();
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: % unpinned while %', v_p, p_when; END IF;
    DELETE FROM public.message_reactions WHERE relationship_id = pg_temp.ra() AND user_id = v_p;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: % removed a reaction while %', v_p, p_when; END IF;
    BEGIN
      INSERT INTO public.place_updates (relationship_id, user_id, label)
      VALUES (pg_temp.ra(), v_p, 'Here');
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: % shared a place while %', v_p, p_when;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
      INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
      VALUES (pg_temp.ra(), v_p, 'milestone', 'New', now());
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: % logged a timeline event while %', v_p, p_when;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    SELECT count(*) INTO v_n FROM public.mark_delivered(ARRAY[pg_temp.msg()]);
    IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: % marked delivered while %', v_p, p_when; END IF;
    SELECT public.mark_relationship_delivered(pg_temp.ra()) INTO v_n;
    IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: % bulk-delivered while %', v_p, p_when; END IF;
    PERFORM public.set_chat_presence(pg_temp.ra());
    RESET ROLE;
    SELECT active_relationship_id INTO v_active FROM public.chat_presence WHERE user_id = v_p;
    IF v_active IS NOT NULL THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % shows as present in the chat while %', v_p, p_when;
    END IF;
  END LOOP;
  IF (SELECT delivered_at FROM public.messages WHERE id = pg_temp.msg()) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a delivery tick appeared while %', p_when;
  END IF;
END $$;

-- C1. With no caller (a service-role call carries no auth.uid()), nothing ends.
DO $$
DECLARE v_msg text;
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  BEGIN
    PERFORM public.end_relationship(pg_temp.ra());
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ending with no caller succeeded';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'lifecycle:not_found' THEN RAISE; END IF;
  END;
  IF (SELECT status FROM public.relationships WHERE id = pg_temp.ra()) <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the row changed';
  END IF;
END $$;

-- Pause: frozen, links kept, reminders cancelled with their key freed,
-- Dating sees a relationship.
DO $$
DECLARE v_row public.scheduled_notifications%ROWTYPE;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.u(1));
  PERFORM public.pause_relationship(pg_temp.ra());
  RESET ROLE;

  PERFORM pg_temp.assert_frozen('paused');

  IF EXISTS (SELECT 1 FROM public.calendar_feed_tokens
             WHERE user_id IN (pg_temp.u(1), pg_temp.u(2)) AND revoked_at IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pausing revoked a calendar link (I6)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.couple_busy_blocks WHERE relationship_id = pg_temp.ra()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pausing deleted busy blocks (final review MIN-4)';
  END IF;
  SELECT * INTO v_row FROM public.scheduled_notifications WHERE id = '9c500000-0000-0000-0000-000000000001';
  IF v_row.status <> 'cancelled' OR v_row.source_key IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reminder push is %, key % (I2, I3)', v_row.status, v_row.source_key;
  END IF;
  IF NOT public.dating_has_relationship(pg_temp.u(1)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating treats a paused space as single (I5)';
  END IF;

  -- After a resume the same occurrence can be queued again.
  PERFORM pg_temp.as_user(pg_temp.u(2));
  PERFORM public.resume_relationship(pg_temp.ra());
  RESET ROLE;
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, metadata, source_key)
  VALUES (pg_temp.u(2), 'immediate', now() + interval '1 hour',
          jsonb_build_object('type', 'reminder_upcoming', 'reminder_id', '9c400000-0000-0000-0000-000000000001'),
          'reminder:9c40:spec3a');
END $$;

-- I12. Past 30 days of pause, resume is refused even before the cron runs.
DO $$
DECLARE v_msg text;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.u(4));
  BEGIN
    PERFORM public.resume_relationship(pg_temp.rb());
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: resumed after 31 days of pause';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    RESET ROLE;
    IF v_msg <> 'lifecycle:not_paused' THEN RAISE; END IF;
  END;
END $$;

-- End: frozen, links revoked, and who ended it stays private.
DO $$
DECLARE v_ok boolean;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.u(1));
  PERFORM public.end_relationship(pg_temp.ra());
  RESET ROLE;

  PERFORM pg_temp.assert_frozen('ended');

  IF EXISTS (SELECT 1 FROM public.calendar_feed_tokens
             WHERE user_id IN (pg_temp.u(1), pg_temp.u(2)) AND revoked_at IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ending left a calendar link live (I6)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.couple_busy_blocks WHERE relationship_id = pg_temp.ra()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ending kept busy blocks';
  END IF;

  FOREACH v_ok IN ARRAY ARRAY[true] LOOP
    PERFORM pg_temp.as_user(pg_temp.u(2));
    BEGIN
      PERFORM ended_by FROM public.relationships WHERE id = pg_temp.ra();
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: the ex can read ended_by (I1)';
    EXCEPTION WHEN insufficient_privilege THEN RESET ROLE;
    END;
    PERFORM pg_temp.as_user(pg_temp.u(2));
    BEGIN
      PERFORM chat_archived_reason FROM public.relationships WHERE id = pg_temp.ra();
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: the ex can read chat_archived_reason (I1)';
    EXCEPTION WHEN insufficient_privilege THEN RESET ROLE;
    END;
    PERFORM pg_temp.as_user(pg_temp.u(2));
    BEGIN
      PERFORM paused_by FROM public.relationships WHERE id = pg_temp.ra();
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: the ex can read paused_by (I1)';
    EXCEPTION WHEN insufficient_privilege THEN RESET ROLE;
    END;
    -- The columns the app reads still read.
    PERFORM pg_temp.as_user(pg_temp.u(2));
    PERFORM id, status, ended_at, chat_archived_at, paused_at FROM public.relationships WHERE id = pg_temp.ra();
    RESET ROLE;
  END LOOP;
END $$;

DO $$ BEGIN RAISE NOTICE 'relationship_lifecycle_hardening_contracts: all held'; END $$;
ROLLBACK;
