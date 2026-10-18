-- supabase/tests/quiet_chat_read_contracts.sql
-- A read before 08:00 cancels the overnight chat push (Spec 1b Task 3,
-- owner decision D2): mark_conversation_read cancels the reader's own pending
-- chat pushes for that conversation -- no one else's, no other
-- conversation's, no other kind -- and a later overnight message starts a
-- new one. Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('8d100000-0000-0000-0000-0000000000a1'),
  ('8d100000-0000-0000-0000-0000000000b2'),
  ('8d100000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name, timezone) VALUES
  ('8d100000-0000-0000-0000-0000000000a1', '+233598300001', 'Read A', 'Africa/Accra'),
  ('8d100000-0000-0000-0000-0000000000b2', '+233598300002', 'Read B', 'Africa/Accra'),
  ('8d100000-0000-0000-0000-0000000000c3', '+233598300003', 'Read C', 'Africa/Accra')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('8d200000-0000-0000-0000-000000000001', '8d100000-0000-0000-0000-0000000000a1',
   '8d100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now(), '2026-11-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;
CREATE FUNCTION pg_temp.push(p_user uuid, p_type text, p_at timestamptz, p_rel text)
RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata)
  VALUES (p_user, 'immediate', p_at, 'pending',
          jsonb_build_object('type', p_type, 'title', 'T', 'body', 'B', 'relationship_id', p_rel))
  RETURNING id $$;
CREATE FUNCTION pg_temp.status(p_id uuid) RETURNS text LANGUAGE sql AS $$
  SELECT status FROM public.scheduled_notifications WHERE id = p_id $$;

CREATE TEMP TABLE t_ids (name text PRIMARY KEY, id uuid) ON COMMIT DROP;

-- 1. Fixtures: A's overnight push for this conversation (collapsed key), A's
--    daytime push for it still pending, A's push for another conversation,
--    A's moment push, and B's own chat push.
DO $$
BEGIN
  INSERT INTO t_ids VALUES
    ('night', pg_temp.push('8d100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-10 23:10+00', '8d200000-0000-0000-0000-000000000001')),
    ('day',   pg_temp.push('8d100000-0000-0000-0000-0000000000a1', 'message_reaction', '2026-11-10 12:00+00', '8d200000-0000-0000-0000-000000000001')),
    ('other', pg_temp.push('8d100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-10 23:15+00', '8d200000-0000-0000-0000-000000000099')),
    ('moment', pg_temp.push('8d100000-0000-0000-0000-0000000000a1', 'moment_logged', '2026-11-10 23:20+00', '8d200000-0000-0000-0000-000000000001')),
    ('theirs', pg_temp.push('8d100000-0000-0000-0000-0000000000b2', 'new_message', '2026-11-10 23:25+00', '8d200000-0000-0000-0000-000000000001'));
  IF (SELECT source_key FROM public.scheduled_notifications WHERE id = (SELECT id FROM t_ids WHERE name = 'night')) NOT LIKE 'quiet_chat:%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fixture -- the overnight push is not a collapse row (Task 2 missing?)';
  END IF;
END $$;

-- 2. A reads the conversation: both of A's pushes for it are cancelled,
--    nothing else is.
DO $$
DECLARE v_key text;
BEGIN
  PERFORM pg_temp.as_user('8d100000-0000-0000-0000-0000000000a1');
  PERFORM count(*) FROM public.mark_conversation_read('8d200000-0000-0000-0000-000000000001');
  RESET ROLE;
  IF pg_temp.status((SELECT id FROM t_ids WHERE name = 'night')) <> 'cancelled'
     OR pg_temp.status((SELECT id FROM t_ids WHERE name = 'day')) <> 'cancelled' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a push for a conversation already read is still pending';
  END IF;
  SELECT source_key INTO v_key FROM public.scheduled_notifications WHERE id = (SELECT id FROM t_ids WHERE name = 'night');
  IF v_key IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a cancelled collapse row keeps its key'; END IF;
  IF pg_temp.status((SELECT id FROM t_ids WHERE name = 'other')) <> 'pending'
     OR pg_temp.status((SELECT id FROM t_ids WHERE name = 'moment')) <> 'pending'
     OR pg_temp.status((SELECT id FROM t_ids WHERE name = 'theirs')) <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a read cancelled a push it does not cover';
  END IF;
END $$;

-- 3. A later overnight message starts a fresh collapse (no key clash).
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.push('8d100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-10 23:50+00', '8d200000-0000-0000-0000-000000000001');
  IF v IS NULL OR pg_temp.status(v) <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a message after the read was not queued';
  END IF;
  INSERT INTO t_ids VALUES ('again', v);
END $$;

-- 4. An outsider's call cancels nothing.
DO $$
BEGIN
  PERFORM pg_temp.as_user('8d100000-0000-0000-0000-0000000000c3');
  PERFORM count(*) FROM public.mark_conversation_read('8d200000-0000-0000-0000-000000000001');
  RESET ROLE;
  IF pg_temp.status((SELECT id FROM t_ids WHERE name = 'again')) <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider cancelled a member''s push';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'quiet_chat_read_contracts: all held'; END $$;
ROLLBACK;
