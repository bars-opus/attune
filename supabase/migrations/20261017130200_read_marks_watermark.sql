-- supabase/migrations/20261017130200_read_marks_watermark.sql
--
-- Bounded unread scans (Spec 1a final review I2).
--
-- Since 20261017130000 messages.read_at is never written for native
-- messages, so "read_at IS NULL" no longer narrows count_unread_messages and
-- mark_conversation_read to the unread few: both matched every partner
-- message since deploy and anti-joined each against message_reads, on every
-- inbox refresh and visible sync.
--
-- message_read_marks keeps, per (relationship, reader), the created_at of
-- the newest message that reader has marked. Both functions now scan only
-- messages created after it, less a margin, through
-- idx_messages_relationship_created. created_at is server-set (now(); no
-- client INSERT grant), so a message older than the margin was committed
-- before the read that moved the mark and was marked by it. message_reads
-- stays the truth inside the window. Server-only, not published: moving the
-- mark emits no realtime event, so it is as silent as message_reads.
CREATE TABLE public.message_read_marks (
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  reader_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  read_through timestamptz NOT NULL,
  PRIMARY KEY (relationship_id, reader_id)
);
ALTER TABLE public.message_read_marks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.message_read_marks FROM PUBLIC, anon, authenticated;

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
  v_floor timestamptz;
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
  SELECT w.read_through - interval '10 minutes' INTO v_floor
  FROM public.message_read_marks w
  WHERE w.relationship_id = p_relationship_id AND w.reader_id = v_uid;
  v_floor := COALESCE(v_floor, '-infinity'::timestamptz);

  RETURN QUERY
  WITH marked (mid, rat) AS (
    -- The private marker. Never touches messages.
    INSERT INTO public.message_reads (message_id, reader_id)
    SELECT m.id, v_uid
    FROM public.messages m
    WHERE m.relationship_id = p_relationship_id
      AND m.created_at > v_floor
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
  ),
  moved AS (
    -- Forward only; nothing marked, nothing written.
    INSERT INTO public.message_read_marks (relationship_id, reader_id, read_through)
    SELECT p_relationship_id, v_uid, max(m.created_at)
    FROM marked
    JOIN public.messages m ON m.id = marked.mid
    HAVING count(*) > 0
    ON CONFLICT (relationship_id, reader_id) DO UPDATE
      SET read_through = GREATEST(message_read_marks.read_through, EXCLUDED.read_through)
    RETURNING 1
  )
  SELECT marked.mid, m.delivered_at, marked.rat
  FROM marked
  JOIN public.messages m ON m.id = marked.mid
  LEFT JOIN ticked ON ticked.tid = marked.mid;
END;
$$;

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
    AND m.created_at > COALESCE(
      (SELECT w.read_through - interval '10 minutes'
         FROM public.message_read_marks w
        WHERE w.relationship_id = p_relationship_id AND w.reader_id = auth.uid()),
      '-infinity'::timestamptz)
    AND m.sender_id <> auth.uid()
    AND m.read_at IS NULL
    AND NOT EXISTS (SELECT 1 FROM public.message_reads x WHERE x.message_id = m.id)
$$;
