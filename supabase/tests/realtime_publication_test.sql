-- Realtime delivery depends on the supabase_realtime publication.
--
-- It was EMPTY in production. postgres_changes fires only for tables in
-- it, so nothing reached a client live: two partners sitting in the same
-- chat, and a sent message not appearing until the recipient left and
-- came back through a "Reconnecting…" banner.
--
-- Typing was instant the whole time, which is what isolated it -- typing
-- is .onBroadcast, client-to-client over the websocket, never touching
-- Postgres. Everything on postgres_changes was dead.
--
-- Nothing in the codebase had ever referenced the publication: Supabase
-- manages it from the dashboard, so it was a manual step nobody knew to
-- perform. This test exists so the requirement cannot go quiet again --
-- a missing table here produces no error anywhere, just a feature that
-- silently stops being live.

BEGIN;

DO $$
DECLARE
  v_required text[] := ARRAY[
    'messages',
    'relationships',
    'message_pins',
    'message_reactions',
    'game_sessions',
    'game_session_rounds',
    'thirty_six_question_answers',
    'in_app_notifications'
  ];
  v_missing text;
BEGIN
  SELECT string_agg(t, ', ' ORDER BY t) INTO v_missing
  FROM unnest(v_required) AS t
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = t
  );

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION
      'not in supabase_realtime, so their subscribers get no live '
      'updates and no error either: %', v_missing;
  END IF;
END $$;

-- The publication must exist at all. A dropped publication would make
-- every check above vacuous rather than failing.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RAISE EXCEPTION 'the supabase_realtime publication does not exist';
  END IF;
END $$;

ROLLBACK;
