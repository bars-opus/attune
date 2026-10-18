-- supabase/migrations/20261017130000_read_receipts_split.sql
--
-- Chat read receipts (Spec 1a Task 3; research 06 §3 F4 (5)).
--
-- messages.read_at did two jobs: the recipient's own unread marker and the
-- sender's "Read" tick. Both leave it:
--
--   * The recipient's marker moves to message_reads, a table with no client
--     grant that is NOT in the realtime publication. messages IS published,
--     and a column privilege strips a column from a change payload but not
--     the UPDATE event itself -- the sender's chat/inbox channels would
--     learn the read moment from the event alone. So while receipts are
--     off, a read must change no row of messages at all.
--   * The sender's tick becomes read_receipt_at, written by
--     mark_conversation_read only while the couple's "Show when we've seen
--     things" is on (together with delivered_at, since a read tick implies
--     delivery). A read made while off is never written there, so it can
--     never be shown later, including after both turn it back on.
--   * read_at stays only as the WhatsApp import worker's legacy marker
--     (v1_3:399-406 writes read_at = created_at; both already saw that
--     history). It is not client-selectable (20261017130100) and counts as
--     "read" for the badge.
CREATE TABLE public.message_reads (
  message_id uuid PRIMARY KEY REFERENCES public.messages(id) ON DELETE CASCADE,
  reader_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  read_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.message_reads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.message_reads FROM PUBLIC, anon, authenticated;

ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS read_receipt_at timestamptz;

CREATE OR REPLACE FUNCTION public.mark_conversation_read(p_relationship_id uuid)
RETURNS TABLE (
  id uuid,
  delivered_at timestamptz,
  read_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_on boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.chat_archived_at IS NULL
      AND (r.user_a = v_uid OR r.user_b = v_uid)
  ) THEN
    RETURN;
  END IF;
  v_on := public.seen_receipts_effective(p_relationship_id);

  RETURN QUERY
  WITH marked (mid, rat) AS (
    -- The private marker. Never touches messages.
    INSERT INTO public.message_reads (message_id, reader_id)
    SELECT m.id, v_uid
    FROM public.messages m
    WHERE m.relationship_id = p_relationship_id
      AND m.sender_id <> v_uid
      AND m.read_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.message_reads x WHERE x.message_id = m.id)
    ON CONFLICT (message_id) DO NOTHING
    RETURNING message_reads.message_id, message_reads.read_at
  ),
  ticked (tid) AS (
    -- The sender-visible tick, only while on. With v_on false this UPDATE
    -- matches no row, so nothing is written and nothing streams.
    UPDATE public.messages m
    SET read_receipt_at = now(),
        delivered_at = COALESCE(m.delivered_at, now())
    FROM marked
    WHERE v_on AND m.id = marked.mid
    RETURNING m.id
  )
  SELECT marked.mid, m.delivered_at, marked.rat
  FROM marked
  JOIN public.messages m ON m.id = marked.mid
  LEFT JOIN ticked ON ticked.tid = marked.mid;
END;
$$;

-- The recipient's badge. Mirrors the former client query
-- (supabase_chat_repository._fetchUnreadCount): partner messages not yet
-- read by me, member, not archived. A legacy imported row (read_at set)
-- counts as read. Deleted rows count exactly as before.
CREATE OR REPLACE FUNCTION public.count_unread_messages(p_relationship_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)::integer
  FROM public.messages m
  JOIN public.relationships r ON r.id = m.relationship_id
  WHERE m.relationship_id = p_relationship_id
    AND auth.uid() IS NOT NULL
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    AND r.chat_archived_at IS NULL
    AND m.sender_id <> auth.uid()
    AND m.read_at IS NULL
    AND NOT EXISTS (SELECT 1 FROM public.message_reads x WHERE x.message_id = m.id)
$$;
REVOKE ALL ON FUNCTION public.count_unread_messages(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.count_unread_messages(uuid) TO authenticated;

-- Couples that keep today's behaviour (both on after 20261017120000's
-- backfill) keep their existing ticks: copy read_at -> read_receipt_at.
-- messages is a published table, so this rewrites rows in slices
-- (p_batch per call) rather than in one statement; each call is its own
-- small burst of WAL and realtime events. The migration runs it to
-- completion only for a small table; otherwise the owner loops it at a
-- quiet time (hand-off, Task 9).
CREATE OR REPLACE FUNCTION public.backfill_read_receipts(p_batch int DEFAULT 2000)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n integer;
BEGIN
  WITH todo AS (
    SELECT m.id
    FROM public.messages m
    WHERE m.read_at IS NOT NULL
      AND m.read_receipt_at IS NULL
      AND public.seen_receipts_effective(m.relationship_id)
    ORDER BY m.id
    LIMIT GREATEST(1, p_batch)
  ),
  done AS (
    UPDATE public.messages m
    SET read_receipt_at = m.read_at
    FROM todo
    WHERE m.id = todo.id
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM done;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.backfill_read_receipts(int) FROM PUBLIC, anon, authenticated;

DO $$
DECLARE v_total bigint; v_n integer;
BEGIN
  SELECT count(*) INTO v_total FROM public.messages WHERE read_at IS NOT NULL AND read_receipt_at IS NULL;
  IF v_total <= 20000 THEN
    LOOP
      v_n := public.backfill_read_receipts(2000);
      EXIT WHEN v_n = 0;
    END LOOP;
  ELSE
    RAISE NOTICE 'read receipts: % rows to backfill -- run SELECT public.backfill_read_receipts(2000) in a loop at a quiet time', v_total;
  END IF;
END $$;
