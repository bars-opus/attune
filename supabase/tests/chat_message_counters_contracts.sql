-- Chat W1a (#9): a message insert must not touch the published relationships
-- row. The count lives in relationship_message_counters, which stays out of
-- the realtime publication and is readable by the couple only.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('7fea0000-0000-0000-0000-0000000000a1'),
  ('7fea0000-0000-0000-0000-0000000000b2'),
  ('7fea0000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name, mode) VALUES
  ('7fea0000-0000-0000-0000-0000000000a1', '+233200000071', 'Cursor A', 'couples'),
  ('7fea0000-0000-0000-0000-0000000000b2', '+233200000072', 'Cursor B', 'couples'),
  ('7fea0000-0000-0000-0000-0000000000c3', '+233200000073', 'Outsider C', 'couples')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, message_count)
VALUES ('7fea0000-0000-0000-0000-0000000000c1',
        '7fea0000-0000-0000-0000-0000000000a1',
        '7fea0000-0000-0000-0000-0000000000b2',
        'active', CURRENT_DATE, now(), 41)
ON CONFLICT (id) DO UPDATE SET status = 'active', chat_archived_at = NULL, message_count = 41;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

CREATE FUNCTION pg_temp.counter() RETURNS bigint LANGUAGE sql AS $$
  SELECT COALESCE((SELECT message_count FROM public.relationship_message_counters
                   WHERE relationship_id = '7fea0000-0000-0000-0000-0000000000c1'), 0) $$;

CREATE FUNCTION pg_temp.assert_unpublished() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication_tables
             WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
               AND tablename = 'relationship_message_counters') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: relationship_message_counters must not be published (that is the echo this table removes)';
  END IF;
END $$;

CREATE FUNCTION pg_temp.assert_delete_decrements() RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_before bigint; v_after bigint;
BEGIN
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content)
  VALUES ('7fea0000-0000-0000-0000-0000000000d9',
          '7fea0000-0000-0000-0000-0000000000c1',
          '7fea0000-0000-0000-0000-0000000000a1',
          '7fea0000-0000-0000-0000-0000000000e9', 'to delete');
  v_before := pg_temp.counter();
  DELETE FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d9';
  v_after := pg_temp.counter();
  IF v_after <> v_before - 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hard delete did not decrement the counter (% -> %)', v_before, v_after;
  END IF;
END $$;

-- 1. Insert: the relationships row is not touched at all, counter +1.
CREATE FUNCTION pg_temp.assert_insert_quiet() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_counter_before bigint := pg_temp.counter();
  v_xmin_before xid; v_ctid_before tid; v_xmin_after xid; v_ctid_after tid;
BEGIN
  SELECT xmin, ctid INTO v_xmin_before, v_ctid_before FROM public.relationships
   WHERE id = '7fea0000-0000-0000-0000-0000000000c1';
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content)
  VALUES ('7fea0000-0000-0000-0000-0000000000d2',
          '7fea0000-0000-0000-0000-0000000000c1',
          '7fea0000-0000-0000-0000-0000000000a1',
          '7fea0000-0000-0000-0000-0000000000e2', 'counted');
  SELECT xmin, ctid INTO v_xmin_after, v_ctid_after FROM public.relationships
   WHERE id = '7fea0000-0000-0000-0000-0000000000c1';
  IF (SELECT message_count FROM public.relationships WHERE id = '7fea0000-0000-0000-0000-0000000000c1') <> 41
     OR v_xmin_after <> v_xmin_before OR v_ctid_after <> v_ctid_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a message insert still writes the relationships row';
  END IF;
  IF pg_temp.counter() <> v_counter_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: counter did not advance on insert (% -> %)', v_counter_before, pg_temp.counter();
  END IF;
END $$;
SAVEPOINT before_insert;
SELECT pg_temp.assert_insert_quiet();
ROLLBACK TO SAVEPOINT before_insert;

-- 1b. Grants: authenticated is read-only, anon has nothing.
CREATE FUNCTION pg_temp.assert_grants() RETURNS void LANGUAGE plpgsql AS $$
DECLARE p text;
BEGIN
  FOREACH p IN ARRAY ARRAY['INSERT','UPDATE','DELETE','TRUNCATE'] LOOP
    IF has_table_privilege('authenticated', 'public.relationship_message_counters', p) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated has % on relationship_message_counters', p;
    END IF;
  END LOOP;
  FOREACH p IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE'] LOOP
    IF has_table_privilege('anon', 'public.relationship_message_counters', p) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: anon has % on relationship_message_counters', p;
    END IF;
  END LOOP;
END $$;
SELECT pg_temp.assert_grants();

-- 2. Hard delete decrements.
SELECT pg_temp.assert_delete_decrements();

-- 3. Not published.
SELECT pg_temp.assert_unpublished();

-- 4. Member reads, outsider does not.
CREATE FUNCTION pg_temp.assert_rls() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.as_user('7fea0000-0000-0000-0000-0000000000a1');
  IF NOT EXISTS (SELECT 1 FROM public.relationship_message_counters
                 WHERE relationship_id = '7fea0000-0000-0000-0000-0000000000c1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member cannot read the couple''s counter';
  END IF;
  PERFORM pg_temp.as_user('7fea0000-0000-0000-0000-0000000000c3');
  IF EXISTS (SELECT 1 FROM public.relationship_message_counters
             WHERE relationship_id = '7fea0000-0000-0000-0000-0000000000c1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider can read another couple''s counter';
  END IF;
END $$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_rls();
RESET ROLE;

-- Mutation checks.
SAVEPOINT mutation_publish;
ALTER PUBLICATION supabase_realtime ADD TABLE public.relationship_message_counters;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_unpublished();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: publication check passed after publishing the table';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_publish;

SAVEPOINT mutation_delete;
DROP TRIGGER messages_count_on_delete ON public.messages;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_delete_decrements();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: decrement check passed without the trigger';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_delete;

SAVEPOINT mutation_insert_writes;
CREATE FUNCTION pg_temp.bump() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.relationships SET message_count = message_count + 1 WHERE id = NEW.relationship_id;
  RETURN NULL;
END $$;
CREATE TRIGGER zz_mutation_bump AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION pg_temp.bump();
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_insert_quiet();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: insert check passed while a trigger wrote relationships';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
    RAISE NOTICE 'mutation detected: %', SQLERRM;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_insert_writes;

SAVEPOINT mutation_touch_only;
CREATE FUNCTION pg_temp.touch() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.relationships SET message_count = message_count WHERE id = NEW.relationship_id;
  RETURN NULL;
END $$;
CREATE TRIGGER zz_mutation_touch AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION pg_temp.touch();
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_insert_quiet();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: insert check passed while a trigger no-op-updated relationships';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
    RAISE NOTICE 'mutation detected: %', SQLERRM;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_touch_only;

SAVEPOINT mutation_rls;
DROP POLICY relationship_message_counters_select ON public.relationship_message_counters;
CREATE POLICY relationship_message_counters_select ON public.relationship_message_counters
  FOR SELECT TO authenticated USING (true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_rls();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: RLS check passed with USING (true)';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
    RAISE NOTICE 'mutation detected: %', SQLERRM;
  END;
END $$;
RESET ROLE;
ROLLBACK TO SAVEPOINT mutation_rls;

SAVEPOINT mutation_grants;
GRANT INSERT ON public.relationship_message_counters TO authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_grants();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: grants check passed with INSERT granted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
    RAISE NOTICE 'mutation detected: %', SQLERRM;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_grants;

ROLLBACK;
