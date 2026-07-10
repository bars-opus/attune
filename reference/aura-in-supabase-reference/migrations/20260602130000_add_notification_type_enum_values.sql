-- Add notification_type enum values for the WhatsApp link-booking flow.
--
-- The notification_type column on scheduled_notifications is declared TEXT
-- in 20260507000000_notification_engine.sql, but production has it as an
-- enum (was likely altered post-migration via the Supabase dashboard).
-- Inserting booking_confirmation / booking_reminder_24h / booking_reminder_2h /
-- booking_review_prompt from the webhooks fails with:
--   invalid input value for enum notification_type: "booking_confirmation"
--
-- This migration discovers whether the column is currently TEXT or an enum
-- and, if enum, adds the four new values. If TEXT, it's a no-op.

DO $$
DECLARE
  v_typname text;
BEGIN
  SELECT t.typname INTO v_typname
  FROM pg_attribute a
  JOIN pg_type t ON t.oid = a.atttypid
  JOIN pg_class c ON c.oid = a.attrelid
  WHERE c.relname = 'scheduled_notifications'
    AND a.attname = 'notification_type'
    AND a.attnum > 0
    AND NOT a.attisdropped;

  IF v_typname IS NULL THEN
    RAISE NOTICE 'scheduled_notifications.notification_type column not found';
    RETURN;
  END IF;

  IF v_typname = 'text' OR v_typname = 'varchar' THEN
    RAISE NOTICE 'notification_type is TEXT — no enum values to add';
    RETURN;
  END IF;

  -- It's an enum. ADD VALUE IF NOT EXISTS is idempotent.
  EXECUTE format('ALTER TYPE %I ADD VALUE IF NOT EXISTS %L', v_typname, 'booking_confirmation');
  EXECUTE format('ALTER TYPE %I ADD VALUE IF NOT EXISTS %L', v_typname, 'booking_reminder_24h');
  EXECUTE format('ALTER TYPE %I ADD VALUE IF NOT EXISTS %L', v_typname, 'booking_reminder_2h');
  EXECUTE format('ALTER TYPE %I ADD VALUE IF NOT EXISTS %L', v_typname, 'booking_review_prompt');
END $$;
