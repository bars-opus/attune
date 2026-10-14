-- Reminders the couple names themselves ("Other" in the picker).
ALTER TABLE public.reminders DROP CONSTRAINT IF EXISTS reminders_reminder_type_check;
ALTER TABLE public.reminders ADD CONSTRAINT reminders_reminder_type_check
  CHECK (reminder_type IN ('anniversary', 'birthday', 'checkin', 'ai_generated', 'custom'));
