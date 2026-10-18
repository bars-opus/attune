-- Spec 5 (R5-12, research 06 A1): Stories update live. The client already
-- listens on story_change_signals (story_read_repository); without the
-- table in the publication nothing arrives and nothing errors. Reads stay
-- under the table's own RLS. Pattern: 20261014100000_together_change_signals.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'story_change_signals'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.story_change_signals;
  END IF;
END $$;
