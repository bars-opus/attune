-- Is Realtime actually emitting change events for chat?
--
-- The client subscribes to postgres_changes on messages, relationships,
-- message_pins and message_reactions. Those events only fire if the table
-- is in the supabase_realtime publication. No migration in this repo adds
-- them, so it is either configured through the dashboard or not at all --
-- and if not, receipts and live message arrival are silently inert: no
-- error, nothing in the logs, just a chat that never updates until the
-- user pulls to refresh.
--
-- Expect all four rows present. A missing row is the bug.
SELECT
  t.tablename,
  CASE WHEN p.tablename IS NULL THEN 'MISSING FROM PUBLICATION'
       ELSE 'ok' END AS realtime
FROM (VALUES ('messages'), ('relationships'),
             ('message_pins'), ('message_reactions')) AS t(tablename)
LEFT JOIN pg_publication_tables p
       ON p.tablename = t.tablename
      AND p.pubname = 'supabase_realtime'
      AND p.schemaname = 'public';

-- REPLICA IDENTITY governs what an UPDATE payload carries. Receipts are
-- UPDATEs (delivered_at / read_at), and under the default identity the old
-- row is not included -- fine here, because the client re-fetches rather
-- than reading the payload, but worth seeing.
SELECT c.relname,
       CASE c.relreplident WHEN 'd' THEN 'default'
                           WHEN 'f' THEN 'full'
                           WHEN 'i' THEN 'index'
                           WHEN 'n' THEN 'nothing' END AS replica_identity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('messages', 'relationships', 'message_pins',
                    'message_reactions');
