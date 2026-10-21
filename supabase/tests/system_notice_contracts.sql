-- supabase/tests/system_notice_contracts.sql
-- Chat review #19 (07 M-6): a partner could INSERT is_system_notice = true
-- and forge a centred, official-looking Attune line. Only the server writes
-- notices; the app's own screenshot notice goes through
-- send_screenshot_notice with server-authored text. Every check RAISEs.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('8d190000-0000-0000-0000-0000000000a1'),
  ('8d190000-0000-0000-0000-0000000000b2'),
  ('8d190000-0000-0000-0000-0000000000c3'),
  ('8d190000-0000-0000-0000-0000000000d4')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('8d190000-0000-0000-0000-0000000000a1', '+233598190001', 'Notice A'),
  ('8d190000-0000-0000-0000-0000000000b2', '+233598190002', 'Notice B'),
  ('8d190000-0000-0000-0000-0000000000c3', '+233598190003', 'Notice C'),
  ('8d190000-0000-0000-0000-0000000000d4', '+233598190004', 'Notice D')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('8d190000-0000-0000-0000-000000000011',
        '8d190000-0000-0000-0000-0000000000a1', '8d190000-0000-0000-0000-0000000000b2',
        'active', CURRENT_DATE, now())
ON CONFLICT (id) DO UPDATE SET status = 'active', chat_archived_at = NULL;
-- C and D: an active couple whose chat is archived (a closed chapter's chat
-- stays read-only).
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at,
                                  chat_archived_at, chat_archived_reason)
VALUES ('8d190000-0000-0000-0000-000000000022',
        '8d190000-0000-0000-0000-0000000000c3', '8d190000-0000-0000-0000-0000000000d4',
        'active', CURRENT_DATE, now(), now(), 'manual_end')
ON CONFLICT (id) DO UPDATE SET status = 'active', chat_archived_at = now(),
                               chat_archived_reason = 'manual_end';
-- B has a profile with a blank display name and a username (the old
-- client's fallback order: profile display name, then username).
INSERT INTO public.profiles (id, username, display_name)
VALUES ('8d190000-0000-0000-0000-0000000000b2', 'notice_b_8d19', '   ')
ON CONFLICT (id) DO UPDATE SET username = EXCLUDED.username, display_name = EXCLUDED.display_name;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
-- The check-1 forge, reused by the mutation checks: true when a client
-- (as `authenticated`) managed to author a notice.
CREATE FUNCTION pg_temp.client_forged_notice() RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, is_system_notice)
  VALUES ('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'Attune: your partner reported this chat', true);
  RETURN true;
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'system_notice:server_only' THEN RAISE; END IF;
  RETURN false;
END $$;

-- edit_message / delete_message outcome as text: 'ok' or the error message.
CREATE FUNCTION pg_temp.try_edit(p_id uuid) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.edit_message(p_id, 'Attune: your partner reported this chat');
  RETURN 'ok';
EXCEPTION WHEN insufficient_privilege THEN RETURN SQLERRM;
END $$;
CREATE FUNCTION pg_temp.try_delete(p_id uuid) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.delete_message(p_id);
  RETURN 'ok';
EXCEPTION WHEN insufficient_privilege THEN RETURN SQLERRM;
END $$;

-- 0. The notice writers (planning_v2_maybe_celebrate, send_screenshot_notice)
--    run as their owner, not the caller, so the guard lets them through; the
--    other message-writing RPCs listed are pinned as definers too, so they
--    keep working if they ever write a notice.
DO $$
DECLARE v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['planning_v2_maybe_celebrate', 'share_ai_assist_draft',
                              'send_appreciation', 'send_pause', 'send_pause_reply',
                              'send_screenshot_notice'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'public' AND p.proname = v_fn AND p.prosecdef) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is not SECURITY DEFINER (a notice it wrote would be refused by the guard)', v_fn;
    END IF;
  END LOOP;
  -- The guard itself must NOT be a definer: it reads current_user.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'messages_system_notice_guard' AND p.prosecdef) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: messages_system_notice_guard is SECURITY DEFINER (current_user would be its owner)';
  END IF;
END $$;

-- 1. A client cannot author a notice; ordinary sends (with or without the
--    column, as old and new app builds send them) still work.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  IF pg_temp.client_forged_notice() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client inserted a system notice';
  END IF;
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, is_system_notice)
  VALUES ('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'hello (old build)', false);
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content)
  VALUES ('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'hello (new build)');
END $$;
RESET ROLE;

-- 1b. Nor turn an ordinary message into one by UPDATE. The client has no
--     UPDATE grant on the column (nor an UPDATE policy) today; add both
--     inside a savepoint so the guard's UPDATE branch is what is tested,
--     not the grant.
SAVEPOINT update_branch;
GRANT UPDATE (is_system_notice) ON public.messages TO authenticated;
CREATE POLICY system_notice_contract_update ON public.messages FOR UPDATE TO authenticated
  USING (sender_id = auth.uid()) WITH CHECK (sender_id = auth.uid());
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content)
VALUES ('8d190000-0000-0000-0000-0000000000e1', '8d190000-0000-0000-0000-000000000011',
        '8d190000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'an ordinary line');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  BEGIN
    UPDATE public.messages SET is_system_notice = true WHERE id = '8d190000-0000-0000-0000-0000000000e1';
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client turned an ordinary message into a system notice';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'system_notice:server_only' THEN RAISE; END IF;
  END;
END $$;
RESET ROLE;
ROLLBACK TO SAVEPOINT update_branch;

-- 2. The screenshot notice: server-authored text, idempotent per client id,
--    members of an open chat only.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000a1');
DO $$
DECLARE v1 uuid; v2 uuid; v_notice boolean; v_sender uuid; v_content text; v_rel uuid;
BEGIN
  v1 := public.send_screenshot_notice('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000f1');
  v2 := public.send_screenshot_notice('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000f1');
  -- Named columns only: the client SELECT grant is a column allowlist
  -- (20261017130100), so SELECT * would fail as authenticated.
  SELECT m.is_system_notice, m.sender_id, m.content, m.relationship_id
    INTO v_notice, v_sender, v_content, v_rel
    FROM public.messages m WHERE m.id = v1;
  IF v1 IS NULL OR v2 <> v1 OR NOT coalesce(v_notice, false)
     OR v_sender <> '8d190000-0000-0000-0000-0000000000a1'
     OR v_rel <> '8d190000-0000-0000-0000-000000000011'
     OR v_content <> 'Notice A took a screenshot' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: send_screenshot_notice wrote % / % / %', v1, v2, v_content;
  END IF;
  IF (SELECT count(*) FROM public.messages WHERE client_message_id = '8d190000-0000-0000-0000-0000000000f1') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the screenshot notice was written twice';
  END IF;

  -- A client id already used for an ordinary message is not answered with
  -- that message: the RPC only ever returns a screenshot notice.
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content)
  VALUES ('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000a1',
          '8d190000-0000-0000-0000-0000000000f2', 'an ordinary line');
  BEGIN
    PERFORM public.send_screenshot_notice('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000f2');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reused client id returned an ordinary message as the notice';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'screenshot_notice:not_allowed' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.send_screenshot_notice('8d190000-0000-0000-0000-000000000011', NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a screenshot notice without a client id';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'screenshot_notice:not_allowed' THEN RAISE; END IF;
  END;
END $$;
-- The name: profile display name, then username (as the old client wrote
-- it), then the account name, then 'Someone'.
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000b2');
DO $$
DECLARE v_id uuid;
BEGIN
  v_id := public.send_screenshot_notice('8d190000-0000-0000-0000-000000000011', gen_random_uuid());
  IF (SELECT m.content FROM public.messages m WHERE m.id = v_id) <> 'notice_b_8d19 took a screenshot' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: blank profile name did not fall back to the username: %',
      (SELECT m.content FROM public.messages m WHERE m.id = v_id);
  END IF;
END $$;
RESET ROLE;
UPDATE public.profiles SET display_name = 'Kofi Notice' WHERE id = '8d190000-0000-0000-0000-0000000000b2';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000b2');
DO $$
DECLARE v_id uuid;
BEGIN
  v_id := public.send_screenshot_notice('8d190000-0000-0000-0000-000000000011', gen_random_uuid());
  IF (SELECT m.content FROM public.messages m WHERE m.id = v_id) <> 'Kofi Notice took a screenshot' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the profile display name was not used: %',
      (SELECT m.content FROM public.messages m WHERE m.id = v_id);
  END IF;
END $$;
-- An outsider cannot write into someone else's chat.
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000c3');
DO $$
BEGIN
  BEGIN
    PERFORM public.send_screenshot_notice('8d190000-0000-0000-0000-000000000011', gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider wrote a screenshot notice into someone else''s chat';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'screenshot_notice:not_allowed' THEN RAISE; END IF;
  END;
  -- A member cannot write into an archived (read-only) chat.
  BEGIN
    PERFORM public.send_screenshot_notice('8d190000-0000-0000-0000-000000000022', gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: a screenshot notice in an archived chat';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'screenshot_notice:not_allowed' THEN RAISE; END IF;
  END;
END $$;
-- No signed-in user, no notice.
SELECT set_config('request.jwt.claims', '', true);
DO $$
BEGIN
  BEGIN
    PERFORM public.send_screenshot_notice('8d190000-0000-0000-0000-000000000011', gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: a screenshot notice with no signed-in user';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'screenshot_notice:not_allowed' THEN RAISE; END IF;
  END;
END $$;
RESET ROLE;

-- 3. The server still writes notices: a service-role worker directly, and
--    the Planning goal notice (planning_v2_maybe_celebrate, a SECURITY
--    DEFINER path) reached through the app's own RPCs as `authenticated`.
SET LOCAL ROLE service_role;
DO $$
BEGIN
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, is_system_notice)
  VALUES ('8d190000-0000-0000-0000-0000000000e2', '8d190000-0000-0000-0000-000000000011',
          '8d190000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'A worker notice', true);
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content)
  VALUES ('8d190000-0000-0000-0000-0000000000e3', '8d190000-0000-0000-0000-000000000011',
          '8d190000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'later made a notice');
  UPDATE public.messages SET is_system_notice = true WHERE id = '8d190000-0000-0000-0000-0000000000e3';
  IF (SELECT count(*) FROM public.messages
      WHERE id IN ('8d190000-0000-0000-0000-0000000000e2', '8d190000-0000-0000-0000-0000000000e3')
        AND is_system_notice) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role could not write a notice';
  END IF;
END $$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000b2');
SELECT public.get_planning_home('8d190000-0000-0000-0000-000000000011') IS NOT NULL AS seeded;
RESET ROLE;
-- planning_categories is not client-readable; look the seeded Goals id up here.
SELECT set_config('system_notice_contracts.goals', id::text, true) FROM public.planning_categories
WHERE relationship_id = '8d190000-0000-0000-0000-000000000011' AND seed_key = 'goals';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000b2');
DO $$
DECLARE
  v_goals uuid := current_setting('system_notice_contracts.goals')::uuid;
  v_goal uuid := '8d190000-0000-0000-0000-00000000e001';
  v_prog uuid := '8d190000-0000-0000-0000-00000000b001';
BEGIN
  PERFORM public.create_planning_entry(v_goal, v_goals, 'Notice trip', false, 'GHS');
  PERFORM public.add_planning_block(v_prog, v_goal, 'progress', '{"mode":"numeric","unit":"money"}', NULL, NULL, NULL);
  PERFORM public.update_planning_block_target(v_prog, 1, 100000, 'GHS');
  PERFORM public.save_planning_rich_item(gen_random_uuid(), v_prog, NULL, '{"amount_minor":100000}', NULL);
  IF NOT EXISTS (SELECT 1 FROM public.messages m
                 WHERE m.relationship_id = '8d190000-0000-0000-0000-000000000011'
                   AND m.is_system_notice AND m.content = '🎉 Goal reached: Notice trip') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Planning goal notice was not written for a client-driven goal';
  END IF;
END $$;
RESET ROLE;

DO $$
BEGIN
  IF has_function_privilege('anon', 'public.send_screenshot_notice(uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can call send_screenshot_notice';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.send_screenshot_notice(uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated cannot call send_screenshot_notice';
  END IF;
  IF has_function_privilege('authenticated', 'public.messages_system_notice_guard()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.messages_system_notice_guard()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the notice guard is executable by clients';
  END IF;
  -- 20261019110320's CREATE OR REPLACE kept the edit/delete grants.
  IF has_function_privilege('anon', 'public.edit_message(uuid,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.delete_message(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.edit_message(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.delete_message(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: edit_message/delete_message grants changed';
  END IF;
END $$;

-- 3b. A notice, once written, is neither rewritten nor hidden by the member
--     it is attributed to: edit_message would otherwise turn "A took a
--     screenshot" (or a goal notice authored as them) into a forged
--     official line in two calls, and delete_message would let the
--     screenshotter erase the notice. Ordinary rows keep both actions.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000a1');
SELECT set_config('system_notice_contracts.shot',
  public.send_screenshot_notice('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000f3')::text,
  true);
DO $$
DECLARE
  v_shot uuid := current_setting('system_notice_contracts.shot')::uuid;
  v_plain uuid;
  v_r text; v_content text; v_deleted timestamptz; v_edited timestamptz;
BEGIN
  v_r := pg_temp.try_edit(v_shot);
  IF v_r <> 'not_editable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the screenshotter edited their screenshot notice (%)', v_r;
  END IF;
  v_r := pg_temp.try_delete(v_shot);
  IF v_r <> 'not_deletable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the screenshotter deleted their screenshot notice (%)', v_r;
  END IF;
  SELECT m.content, m.deleted_at, m.edited_at INTO v_content, v_deleted, v_edited
    FROM public.messages m WHERE m.id = v_shot;
  IF v_content <> 'Notice A took a screenshot' OR v_deleted IS NOT NULL OR v_edited IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the screenshot notice changed: % / % / %', v_content, v_deleted, v_edited;
  END IF;
  -- Regression: the member's own ordinary message is still editable and deletable.
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content)
  VALUES ('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'an ordinary line')
  RETURNING id INTO v_plain;
  IF pg_temp.try_edit(v_plain) <> 'ok' OR pg_temp.try_delete(v_plain) <> 'ok' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ordinary message lost edit/delete';
  END IF;
END $$;
-- The Planning goal notice from 3 is authored as B (the member who hit the goal).
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000b2');
SELECT set_config('system_notice_contracts.goal', m.id::text, true) FROM public.messages m
WHERE m.relationship_id = '8d190000-0000-0000-0000-000000000011'
  AND m.is_system_notice AND m.content = '🎉 Goal reached: Notice trip';
DO $$
DECLARE v_goal uuid := current_setting('system_notice_contracts.goal')::uuid; v_r text;
BEGIN
  IF (SELECT m.sender_id FROM public.messages m WHERE m.id = v_goal) <> '8d190000-0000-0000-0000-0000000000b2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: setup: the goal notice is not authored as B';
  END IF;
  v_r := pg_temp.try_edit(v_goal);
  IF v_r <> 'not_editable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member edited the Planning goal notice (%)', v_r;
  END IF;
  v_r := pg_temp.try_delete(v_goal);
  IF v_r <> 'not_deletable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member deleted the Planning goal notice (%)', v_r;
  END IF;
END $$;
RESET ROLE;

-- 4. Mutation checks: break each rule and show its check is violated.
-- 4a. Guard off: check 1 is violated.
SAVEPOINT mutate;
ALTER TABLE public.messages DISABLE TRIGGER messages_system_notice_guard;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  IF NOT pg_temp.client_forged_notice() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mutation check 4a ineffective (guard disabled, forge still refused)';
  END IF;
  RAISE NOTICE 'mutation check 4a: with the guard disabled a client authored a notice (as expected)';
END $$;
RESET ROLE;
ROLLBACK TO SAVEPOINT mutate;

-- 4b. Guard made SECURITY DEFINER: current_user becomes its owner and check 1
--     is violated -- why the guard is deliberately an invoker function.
SAVEPOINT mutate;
ALTER FUNCTION public.messages_system_notice_guard() SECURITY DEFINER;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  IF NOT pg_temp.client_forged_notice() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mutation check 4b ineffective (definer guard still refused the forge)';
  END IF;
  RAISE NOTICE 'mutation check 4b: a SECURITY DEFINER guard let a client author a notice (as expected)';
END $$;
RESET ROLE;
ROLLBACK TO SAVEPOINT mutate;

-- 4c. Membership check off (relationship_active_for_me always true): the
--     outsider check in 2 is violated.
SAVEPOINT mutate;
CREATE OR REPLACE FUNCTION public.relationship_active_for_me(p_relationship_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$ SELECT true $$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000c3');
DO $$
BEGIN
  PERFORM public.send_screenshot_notice('8d190000-0000-0000-0000-000000000011', gen_random_uuid());
  RAISE NOTICE 'mutation check 4c: without the membership check an outsider wrote a notice (as expected)';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'screenshot_notice:not_allowed' THEN RAISE; END IF;
  RAISE EXCEPTION 'CONTRACT VIOLATED: mutation check 4c ineffective (outsider still refused)';
END $$;
RESET ROLE;
ROLLBACK TO SAVEPOINT mutate;

-- 4d. edit_message without its notice condition: both notices are rewritten.
SAVEPOINT mutate;
DO $$
DECLARE v_def text := pg_get_functiondef('public.edit_message'::regproc); v_mut text;
BEGIN
  v_mut := replace(v_def, 'OR v_is_system_notice', '');
  IF v_mut = v_def THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mutation check 4d could not find the notice condition in edit_message';
  END IF;
  EXECUTE v_mut;
END $$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  IF pg_temp.try_edit(current_setting('system_notice_contracts.shot')::uuid) <> 'ok' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mutation check 4d ineffective (screenshot notice still not editable)';
  END IF;
END $$;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000b2');
DO $$
BEGIN
  IF pg_temp.try_edit(current_setting('system_notice_contracts.goal')::uuid) <> 'ok' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mutation check 4d ineffective (goal notice still not editable)';
  END IF;
  RAISE NOTICE 'mutation check 4d: without the notice condition both notices were rewritten (as expected)';
END $$;
RESET ROLE;
ROLLBACK TO SAVEPOINT mutate;

-- 4e. delete_message without its notice condition: both notices are erased.
SAVEPOINT mutate;
DO $$
DECLARE v_def text := pg_get_functiondef('public.delete_message'::regproc); v_mut text;
BEGIN
  v_mut := replace(v_def, 'AND NOT messages.is_system_notice', '');
  IF v_mut = v_def THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mutation check 4e could not find the notice condition in delete_message';
  END IF;
  EXECUTE v_mut;
END $$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  IF pg_temp.try_delete(current_setting('system_notice_contracts.shot')::uuid) <> 'ok' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mutation check 4e ineffective (screenshot notice still not deletable)';
  END IF;
END $$;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000b2');
DO $$
BEGIN
  IF pg_temp.try_delete(current_setting('system_notice_contracts.goal')::uuid) <> 'ok' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mutation check 4e ineffective (goal notice still not deletable)';
  END IF;
  RAISE NOTICE 'mutation check 4e: without the notice condition both notices were deleted (as expected)';
END $$;
RESET ROLE;
ROLLBACK TO SAVEPOINT mutate;

DO $$ BEGIN RAISE NOTICE 'system_notice_contracts: all held'; END $$;
ROLLBACK;
