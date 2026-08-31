-- Every table in public must be readable and writable by service_role.
--
-- The Edge Function workers connect as service_role through PostgREST.
-- A missing SELECT grant there does not raise -- it returns an EMPTY
-- RESULT. process-chat-safety-outbox booted every two minutes, queried
-- message_safety_outbox, found "nothing", and returned {processed: 0}
-- while 89 messages sat pending. The cron job logged `succeeded`, because
-- net.http_post reports success once the request is queued, and the
-- function logged no error, because from its point of view there was
-- nothing to do.
--
-- 103 public tables were in that state, including messages, profiles,
-- push_tokens and game_sessions. Supabase grants privileges platform-side
-- when a table is created through its API; a table created by a migration
-- gets only whatever default privileges exist at that moment, so which
-- tables worked was an accident of creation order.
--
-- This test exists because nothing else can see it. The application never
-- notices -- service_role is a backend identity, so no user-facing screen
-- breaks -- and scripts/local_pg_grants.sql used to blanket-grant
-- service_role, which made every table look reachable in the harness.
-- That blanket grant is gone specifically so this test has teeth.

BEGIN;

DO $$
DECLARE
  v_missing text;
  v_count int;
BEGIN
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname), count(*)
  INTO v_missing, v_count
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND NOT has_table_privilege('service_role', c.oid, 'SELECT');

  IF v_count > 0 THEN
    RAISE EXCEPTION
      '% table(s) unreadable by service_role -- their workers will read '
      'empty queues with no error: %', v_count, v_missing;
  END IF;
END $$;

-- Writes matter as much as reads: a worker that can SELECT a job but not
-- UPDATE it would claim nothing and loop forever on the same rows.
DO $$
DECLARE
  v_missing text;
  v_count int;
BEGIN
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname), count(*)
  INTO v_missing, v_count
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND NOT has_table_privilege('service_role', c.oid, 'UPDATE');

  IF v_count > 0 THEN
    RAISE EXCEPTION
      '% table(s) not updatable by service_role -- workers cannot claim '
      'jobs in: %', v_count, v_missing;
  END IF;
END $$;

-- The worker queues specifically, named so a failure points straight at
-- the pipeline it breaks rather than at a list of 100 tables.
DO $$
DECLARE
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'message_safety_outbox',
    'message_notification_outbox',
    'message_media_processing_outbox',
    'media_deletion_queue',
    'truth_answer_safety_outbox',
    'messages'
  ] LOOP
    IF NOT has_table_privilege('service_role', 'public.' || v_table, 'SELECT') THEN
      RAISE EXCEPTION 'service_role cannot read %', v_table;
    END IF;
    IF NOT has_table_privilege('service_role', 'public.' || v_table, 'UPDATE') THEN
      RAISE EXCEPTION 'service_role cannot update %', v_table;
    END IF;
  END LOOP;
END $$;

ROLLBACK;
