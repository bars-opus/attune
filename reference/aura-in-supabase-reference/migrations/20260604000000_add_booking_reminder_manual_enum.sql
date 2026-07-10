-- Add 'booking_reminder_manual' to the notification_type enum.
--
-- Required by the new schedule_manual_booking_reminder /
-- schedule_bulk_manual_booking_reminders RPCs (migrations 20260604000200
-- and 20260604000300). Without this value, every INSERT into
-- scheduled_notifications from those RPCs would fail with
-- `invalid input value for enum notification_type`.
--
-- Discovery guard pattern lifted from 20260602130000_add_notification_type_enum_values.sql:
-- detect whether scheduled_notifications.notification_type is backed by
-- an enum or by plain TEXT/VARCHAR. ALTER TYPE only runs in the enum
-- case; the TEXT case is a no-op (CHECK constraints are tolerant of new
-- string values once we update them).

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
    RAISE NOTICE 'notification_type is TEXT — no enum value to add';
    RETURN;
  END IF;

  EXECUTE format(
    'ALTER TYPE %I ADD VALUE IF NOT EXISTS %L',
    v_typname,
    'booking_reminder_manual'
  );
END $$;
