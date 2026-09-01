-- Realtime delivery for every table the app subscribes to.
--
-- The supabase_realtime publication was EMPTY. postgres_changes only
-- fires for tables in it, so no message, reaction, pin, game session or
-- notification ever reached a client live -- the app looked broken in the
-- one way users notice most: two partners both sitting in a chat, and a
-- sent message not appearing until the recipient left the screen and came
-- back, watching "Reconnecting…" first.
--
-- Typing worked perfectly throughout, which is what identified this:
-- typing uses .onBroadcast, which pushes client-to-client over the
-- websocket and never touches Postgres. Everything on postgres_changes
-- was dead; everything on broadcast was instant.
--
-- Nothing in the codebase ever added these. Supabase manages the
-- publication platform-side (a toggle per table in the dashboard), so it
-- was left to a manual step nobody performed -- the same class of gap as
-- the app.settings.* GUC and the missing service_role grants.
--
-- Adding it here makes the requirement versioned: a new environment gets
-- working realtime from `supabase db push` rather than from remembering
-- to tick eight boxes.

DO $$
DECLARE
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    -- Chat: the conversation itself, plus the rows that decorate it.
    'messages',
    'relationships',
    'message_pins',
    'message_reactions',
    -- Games: session status drives the chat game cards, and rounds drive
    -- the live game screens (partner-watching, This or That).
    'game_sessions',
    'game_session_rounds',
    'thirty_six_question_answers',
    -- Notifications: the in-app bell.
    'in_app_notifications'
  ] LOOP
    -- Idempotent: re-running must not fail on a table already added, and
    -- `messages` was added by hand while diagnosing this.
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = v_table
    ) THEN
      EXECUTE format(
        'ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table
      );
    END IF;
  END LOOP;
END $$;

-- REPLICA IDENTITY is deliberately left at DEFAULT (primary key only).
--
-- Every handler in the app treats a change event as "something moved,
-- refetch" and ignores the payload, so FULL would ship whole rows --
-- including message content -- over the websocket for no benefit, and
-- widen what a replication stream exposes.
