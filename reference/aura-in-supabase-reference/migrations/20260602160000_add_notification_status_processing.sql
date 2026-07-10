-- Add 'processing' to the notification_status enum.
--
-- The original 20260507000000_notification_engine.sql declared status as
-- TEXT with a CHECK list including 'processing'. Production has it as
-- an enum (altered via Supabase dashboard) and 'processing' wasn't
-- carried over, so claim_pending_notifications now fails with:
--   invalid input value for enum notification_status: "processing"
--
-- The atomic-claim transition is required: it's how concurrent scheduler
-- runs avoid racing on the same row (FOR UPDATE SKIP LOCKED + status
-- transition).

DO $$
DECLARE
  v_typname text;
BEGIN
  SELECT t.typname INTO v_typname
  FROM pg_attribute a
  JOIN pg_type t ON t.oid = a.atttypid
  JOIN pg_class c ON c.oid = a.attrelid
  WHERE c.relname = 'scheduled_notifications'
    AND a.attname = 'status'
    AND a.attnum > 0
    AND NOT a.attisdropped;

  IF v_typname IS NULL THEN
    RAISE NOTICE 'scheduled_notifications.status column not found';
    RETURN;
  END IF;

  IF v_typname = 'text' OR v_typname = 'varchar' THEN
    RAISE NOTICE 'status is TEXT — no enum values to add';
    RETURN;
  END IF;

  EXECUTE format('ALTER TYPE %I ADD VALUE IF NOT EXISTS %L', v_typname, 'processing');
  EXECUTE format('ALTER TYPE %I ADD VALUE IF NOT EXISTS %L', v_typname, 'pending');
  EXECUTE format('ALTER TYPE %I ADD VALUE IF NOT EXISTS %L', v_typname, 'sent');
  EXECUTE format('ALTER TYPE %I ADD VALUE IF NOT EXISTS %L', v_typname, 'failed');
  EXECUTE format('ALTER TYPE %I ADD VALUE IF NOT EXISTS %L', v_typname, 'skipped');
  EXECUTE format('ALTER TYPE %I ADD VALUE IF NOT EXISTS %L', v_typname, 'cancelled');
END $$;
