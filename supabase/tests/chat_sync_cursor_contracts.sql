-- Chat W1a (#7, #8): the sync cursor. messages.updated_at moves only when a
-- client-visible column moves; a reaction add/remove moves it on the parent
-- message; message_pins ships filtered DELETE events (REPLICA IDENTITY FULL)
-- while messages and message_reactions never ship whole old rows.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('7fea0000-0000-0000-0000-0000000000a1'),
  ('7fea0000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name, mode) VALUES
  ('7fea0000-0000-0000-0000-0000000000a1', '+233200000071', 'Cursor A', 'couples'),
  ('7fea0000-0000-0000-0000-0000000000b2', '+233200000072', 'Cursor B', 'couples')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7fea0000-0000-0000-0000-0000000000c1',
        '7fea0000-0000-0000-0000-0000000000a1',
        '7fea0000-0000-0000-0000-0000000000b2',
        'active', CURRENT_DATE, now())
ON CONFLICT (id) DO UPDATE SET status = 'active', chat_archived_at = NULL;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- The checks are functions so the mutation checks below can rerun them.
CREATE FUNCTION pg_temp.assert_identities() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT relreplident FROM pg_class WHERE oid = 'public.message_pins'::regclass) <> 'f' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: message_pins must be REPLICA IDENTITY FULL (filtered unpin DELETEs are dropped otherwise)';
  END IF;
  IF (SELECT relreplident FROM pg_class WHERE oid = 'public.messages'::regclass) <> 'd' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: messages must stay REPLICA IDENTITY DEFAULT (content must never ride a DELETE frame)';
  END IF;
  IF (SELECT relreplident FROM pg_class WHERE oid = 'public.message_reactions'::regclass) <> 'd' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: message_reactions must stay REPLICA IDENTITY DEFAULT';
  END IF;
END $$;

CREATE FUNCTION pg_temp.assert_reaction_bumps() RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_before timestamptz; v_after timestamptz;
BEGIN
  UPDATE public.messages SET updated_at = now() - interval '1 hour'
   WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  SELECT updated_at INTO v_before FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  SET LOCAL ROLE authenticated;
  PERFORM pg_temp.as_user('7fea0000-0000-0000-0000-0000000000b2');
  PERFORM public.react_to_message('7fea0000-0000-0000-0000-0000000000c1',
                                  '7fea0000-0000-0000-0000-0000000000d1', '❤️');
  RESET ROLE;
  SELECT updated_at INTO v_after FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  IF v_after <= v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reaction did not bump the message updated_at (% -> %)', v_before, v_after;
  END IF;
  UPDATE public.messages SET updated_at = now() - interval '1 hour'
   WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  SET LOCAL ROLE authenticated;
  PERFORM pg_temp.as_user('7fea0000-0000-0000-0000-0000000000b2');
  PERFORM public.remove_reaction('7fea0000-0000-0000-0000-0000000000d1');
  RESET ROLE;
  SELECT updated_at INTO v_after FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  IF v_after <> now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: removing a reaction did not bump the message updated_at';
  END IF;
END $$;

-- Worker-only columns leave the cursor alone; client-visible columns move it.
CREATE FUNCTION pg_temp.assert_visible_change_bumps() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.messages SET updated_at = now() - interval '1 hour'
   WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  UPDATE public.messages SET message_analysis_done = true, tone_score = 0.5
   WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  IF (SELECT updated_at FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1')
     <> now() - interval '1 hour' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an analysis-only update moved updated_at';
  END IF;
  UPDATE public.messages SET content = 'edited', edited_at = now()
   WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  IF (SELECT updated_at FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1') <> now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an edit did not move updated_at';
  END IF;
  UPDATE public.messages SET updated_at = now() - interval '1 hour'
   WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  UPDATE public.messages SET delivered_at = now()
   WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  IF (SELECT updated_at FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1') <> now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a receipt did not move updated_at';
  END IF;
END $$;

CREATE FUNCTION pg_temp.assert_select_updated_at() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM pg_temp.as_user('7fea0000-0000-0000-0000-0000000000a1');
  BEGIN
    PERFORM updated_at FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
  EXCEPTION WHEN insufficient_privilege THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated cannot select messages.updated_at';
  END;
  RESET ROLE;
END $$;

-- Drift guard: a client-selectable column that the touch trigger does not
-- compare would change silently without moving the cursor.
CREATE FUNCTION pg_temp.assert_trigger_covers_columns() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_src text := pg_get_functiondef('public.messages_touch_updated_at()'::regprocedure);
  v_col text;
BEGIN
  FOR v_col IN
    SELECT a.attname::text FROM pg_attribute a
     WHERE a.attrelid = 'public.messages'::regclass AND a.attnum > 0 AND NOT a.attisdropped
       AND has_column_privilege('authenticated', 'public.messages', a.attname, 'SELECT')
       AND a.attname::text NOT IN ('id', 'relationship_id', 'sender_id', 'client_message_id',
                                   'created_at', 'source', 'updated_at')
     ORDER BY a.attnum
  LOOP
    IF v_src !~ ('NEW\.' || v_col || '\y') OR v_src !~ ('OLD\.' || v_col || '\y') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: messages.% is client-selectable but messages_touch_updated_at() does not compare it (add it to the trigger or to the immutable allowlist)', v_col;
    END IF;
  END LOOP;
END $$;

-- 1. A new message carries updated_at, selectable by its members.
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content)
VALUES ('7fea0000-0000-0000-0000-0000000000d1',
        '7fea0000-0000-0000-0000-0000000000c1',
        '7fea0000-0000-0000-0000-0000000000a1',
        '7fea0000-0000-0000-0000-0000000000e1', 'cursor row');
DO $$
BEGIN
  IF (SELECT updated_at FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: updated_at missing on a new message';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public'
                 AND indexname = 'messages_relationship_updated_idx') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: messages_relationship_updated_idx missing';
  END IF;
END $$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('7fea0000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  PERFORM updated_at FROM public.messages WHERE id = '7fea0000-0000-0000-0000-0000000000d1';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated cannot select messages.updated_at';
END $$;
RESET ROLE;

-- 2. Worker-only columns do not move the cursor; visible columns do.
SELECT pg_temp.assert_visible_change_bumps();

-- 3. Reactions bump the parent message (add and remove).
SELECT pg_temp.assert_reaction_bumps();

-- 4. Replica identities.
SELECT pg_temp.assert_identities();

-- 5. Selectable cursor column and trigger coverage.
SELECT pg_temp.assert_select_updated_at();
SELECT pg_temp.assert_trigger_covers_columns();

-- Mutation checks: break each rule inside a savepoint and prove the contract notices.
SAVEPOINT mutation_identity;
ALTER TABLE public.message_pins REPLICA IDENTITY DEFAULT;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_identities();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: pins identity check passed after breaking it';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_identity;

SAVEPOINT mutation_touch;
DROP TRIGGER message_reactions_touch_message ON public.message_reactions;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_reaction_bumps();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: reaction bump check passed without the trigger';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_touch;

SAVEPOINT mutation_visible;
DROP TRIGGER messages_touch_updated_at ON public.messages;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_visible_change_bumps();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: visible-change bump check passed without the trigger';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_visible;

SAVEPOINT mutation_worker_bump;
CREATE OR REPLACE FUNCTION public.messages_touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $f$ BEGIN NEW.updated_at := now(); RETURN NEW; END $f$;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_visible_change_bumps();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: worker-only update moved updated_at unnoticed';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_worker_bump;

SAVEPOINT mutation_messages_identity;
ALTER TABLE public.messages REPLICA IDENTITY FULL;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_identities();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: messages identity FULL not detected';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_messages_identity;

SAVEPOINT mutation_reactions_identity;
ALTER TABLE public.message_reactions REPLICA IDENTITY FULL;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_identities();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: message_reactions identity FULL not detected';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_reactions_identity;

SAVEPOINT mutation_revoke_select;
REVOKE SELECT (updated_at) ON public.messages FROM authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_select_updated_at();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: revoked updated_at select not detected';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_revoke_select;

SAVEPOINT mutation_drift;
ALTER TABLE public.messages ADD COLUMN drift_probe text;
GRANT SELECT (drift_probe) ON public.messages TO authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.assert_trigger_covers_columns();
    RAISE EXCEPTION 'MUTATION NOT DETECTED: untracked selectable column not detected';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'MUTATION NOT DETECTED%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO SAVEPOINT mutation_drift;

RESET ROLE;
ROLLBACK;
