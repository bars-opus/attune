-- CHAT_SYSTEM_SPEC §5.2 requires the receipt RPCs to "set timestamps only
-- when null". mark_delivered used COALESCE to preserve an existing
-- delivered_at, which keeps the VALUE correct, but had no WHERE guard -- so
-- every replay still wrote and returned every candidate row.
--
-- Found by running chat_system_contracts.sql for the first time; its
-- assertion that a replay returns zero rows has never been able to pass.
--
-- The value was never wrong, so this is not a data-integrity fix: it stops
-- a client that polls delivery receipts from issuing an UPDATE per message
-- per call, each writing a new row version for no change. The RETURNING
-- contract also becomes honest -- callers can now treat returned rows as
-- "newly delivered" rather than "seen again".
CREATE OR REPLACE FUNCTION public.mark_delivered(p_message_ids uuid[])
RETURNS TABLE (id uuid, delivered_at timestamptz, read_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  RETURN QUERY
  WITH candidate_messages AS (
    SELECT m.id
    FROM public.messages m
    JOIN public.relationships r
      ON r.id = m.relationship_id
    WHERE m.id = ANY(p_message_ids)
      AND m.sender_id <> auth.uid()
      AND r.chat_archived_at IS NULL
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
      -- Only rows that will actually change. Without this the UPDATE
      -- rewrites every already-delivered row on every replay.
      AND m.delivered_at IS NULL
    LIMIT 200
  ),
  updated AS (
    UPDATE public.messages m
    SET delivered_at = now()
    FROM candidate_messages c
    WHERE m.id = c.id
    RETURNING m.id, m.delivered_at, m.read_at
  )
  SELECT updated.id, updated.delivered_at, updated.read_at
  FROM updated;
END;
$$;

-- CREATE OR REPLACE resets privileges to the default, so the original
-- grants must be reapplied or this becomes a privilege regression.
REVOKE ALL ON FUNCTION public.mark_delivered(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_delivered(uuid[]) TO authenticated;
