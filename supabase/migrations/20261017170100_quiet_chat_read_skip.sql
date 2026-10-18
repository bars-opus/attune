-- supabase/migrations/20261017170100_quiet_chat_read_skip.sql
--
-- A read cancels the conversation's pending chat pushes (Spec 1b; owner
-- decision D2): the 08:00 "New messages" push must not arrive for a
-- conversation already read at 07:30. scheduled_notifications is not
-- published, so this is as silent as the read itself. The key is cleared so
-- a later overnight message starts a fresh collapse. Otherwise identical to
-- 20261017130200_read_marks_watermark.sql.
--
-- Hard dependency: Spec 1a (20261017120000..130200). Pushed alone, this
-- would stop db push half-way with quiet hours live and no cancel-on-read.
DO $$
BEGIN
  IF to_regclass('public.message_read_marks') IS NULL
     OR to_regprocedure('public.seen_receipts_effective(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Spec 1b 20261017170100 requires Spec 1a (20261017120000..130200)';
  END IF;
END $$;

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

  -- Spec 1b: pushes about this conversation that have not gone out are moot.
  UPDATE public.scheduled_notifications s
     SET status = 'cancelled', source_key = NULL,
         last_error = 'read_before_send', updated_at = now()
   WHERE s.user_id = v_uid
     AND s.status = 'pending'
     AND s.metadata->>'type' IN ('new_message', 'message_reaction')
     AND s.metadata->>'relationship_id' = p_relationship_id::text;

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
