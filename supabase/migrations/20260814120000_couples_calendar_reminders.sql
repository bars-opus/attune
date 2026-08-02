-- supabase/migrations/20260814120000_couples_calendar_reminders.sql
--
-- Completes ATTUNE_MASTER_SPEC.md §4.1/§8.3's reminders table (spec'd,
-- never migrated) and adds couple_family_members (new — lib/architecture/
-- REMINDERS.md §3). Both tables are fully shared between partners: either
-- can SELECT/UPDATE/DELETE any row, a deliberate divergence from
-- timeline_events' owner-only UPDATE/DELETE (PULSE.md §8).

CREATE TABLE IF NOT EXISTS public.couple_family_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(name) <= 80),
  birthday date,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.reminders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reminder_type text NOT NULL CHECK (reminder_type IN (
    'anniversary', 'birthday', 'checkin', 'ai_generated'
  )),
  title text NOT NULL CHECK (char_length(title) <= 80),
  note text CHECK (note IS NULL OR char_length(note) <= 300),
  remind_at timestamptz NOT NULL,
  recurrence text NOT NULL DEFAULT 'none' CHECK (recurrence IN (
    'none', 'weekly', 'monthly', 'yearly'
  )),
  sent boolean NOT NULL DEFAULT false,
  family_member_id uuid REFERENCES public.couple_family_members(id) ON DELETE SET NULL,
  linked_timeline_event_id uuid REFERENCES public.timeline_events(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- === updated_at triggers (ATTUNE_MASTER_SPEC.md §4.3 rule 4) ===

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_reminders_updated_at ON public.reminders;
CREATE TRIGGER set_reminders_updated_at
  BEFORE UPDATE ON public.reminders
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_family_members_updated_at ON public.couple_family_members;
CREATE TRIGGER set_family_members_updated_at
  BEFORE UPDATE ON public.couple_family_members
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- === RLS ===

ALTER TABLE public.reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.couple_family_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS reminders_select_members ON public.reminders;
CREATE POLICY reminders_select_members ON public.reminders
FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.relationships r
  WHERE r.id = reminders.relationship_id
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
));

DROP POLICY IF EXISTS reminders_insert_members ON public.reminders;
CREATE POLICY reminders_insert_members ON public.reminders
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = reminders.relationship_id
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
      AND r.status = 'active'
  )
);

DROP POLICY IF EXISTS reminders_update_members ON public.reminders;
CREATE POLICY reminders_update_members ON public.reminders
FOR UPDATE TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.relationships r
  WHERE r.id = reminders.relationship_id
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
));

DROP POLICY IF EXISTS reminders_delete_members ON public.reminders;
CREATE POLICY reminders_delete_members ON public.reminders
FOR DELETE TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.relationships r
  WHERE r.id = reminders.relationship_id
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
));

DROP POLICY IF EXISTS family_members_select_members ON public.couple_family_members;
CREATE POLICY family_members_select_members ON public.couple_family_members
FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.relationships r
  WHERE r.id = couple_family_members.relationship_id
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
));

DROP POLICY IF EXISTS family_members_insert_members ON public.couple_family_members;
CREATE POLICY family_members_insert_members ON public.couple_family_members
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = couple_family_members.relationship_id
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
      AND r.status = 'active'
  )
);

DROP POLICY IF EXISTS family_members_update_members ON public.couple_family_members;
CREATE POLICY family_members_update_members ON public.couple_family_members
FOR UPDATE TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.relationships r
  WHERE r.id = couple_family_members.relationship_id
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
));

DROP POLICY IF EXISTS family_members_delete_members ON public.couple_family_members;
CREATE POLICY family_members_delete_members ON public.couple_family_members
FOR DELETE TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.relationships r
  WHERE r.id = couple_family_members.relationship_id
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
));

-- === Column-level write restriction (ATTUNE_MASTER_SPEC.md §4.2 pattern) ===
-- Clients may never directly set: sent, linked_timeline_event_id, created_by
-- (created_by is set via WITH CHECK matching auth.uid(), never trusted from
-- client payload), created_at, updated_at.

REVOKE INSERT ON public.reminders FROM authenticated;
GRANT INSERT (
  relationship_id, created_by, reminder_type, title, note,
  remind_at, recurrence, family_member_id
) ON public.reminders TO authenticated;

REVOKE UPDATE ON public.reminders FROM authenticated;
GRANT UPDATE (
  reminder_type, title, note, remind_at, recurrence, family_member_id
) ON public.reminders TO authenticated;

REVOKE INSERT ON public.couple_family_members FROM authenticated;
GRANT INSERT (relationship_id, created_by, name, birthday)
  ON public.couple_family_members TO authenticated;

REVOKE UPDATE ON public.couple_family_members FROM authenticated;
GRANT UPDATE (name, birthday) ON public.couple_family_members TO authenticated;

GRANT DELETE ON public.reminders TO authenticated;
GRANT DELETE ON public.couple_family_members TO authenticated;
GRANT SELECT ON public.reminders TO authenticated;
GRANT SELECT ON public.couple_family_members TO authenticated;

-- Reject 'weekly'/'monthly' recurrence at write time — REMINDERS.md §8 open
-- question; the CHECK constraint keeps the master spec's original enum
-- intact, but the generator RPC (below) has no occurrence math for these
-- and a silently-accepted-but-never-fired reminder would be worse than a
-- clear rejection.
CREATE OR REPLACE FUNCTION public.reject_unimplemented_recurrence()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.recurrence IN ('weekly', 'monthly') THEN
    RAISE EXCEPTION 'recurrence % is not yet implemented', NEW.recurrence
      USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_reject_unimplemented_recurrence ON public.reminders;
CREATE TRIGGER trigger_reject_unimplemented_recurrence
  BEFORE INSERT OR UPDATE ON public.reminders
  FOR EACH ROW EXECUTE FUNCTION public.reject_unimplemented_recurrence();

-- Validate that family_member_id (client-writable on INSERT and UPDATE)
-- actually belongs to the reminder's own relationship. A plain CHECK
-- constraint can't query another table, so this is enforced via trigger —
-- without it, a malicious/buggy client could point a reminder at a family
-- member belonging to a different couple's relationship.
CREATE OR REPLACE FUNCTION public.validate_reminder_family_member_relationship()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.family_member_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.couple_family_members
      WHERE id = NEW.family_member_id
        AND relationship_id = NEW.relationship_id
    ) THEN
      RAISE EXCEPTION 'family_member_id does not belong to this relationship';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_validate_reminder_family_member_relationship ON public.reminders;
CREATE TRIGGER trigger_validate_reminder_family_member_relationship
  BEFORE INSERT OR UPDATE ON public.reminders
  FOR EACH ROW EXECUTE FUNCTION public.validate_reminder_family_member_relationship();

-- === Indexes ===

CREATE INDEX IF NOT EXISTS idx_reminders_relationship_remind_at
  ON public.reminders(relationship_id, remind_at);
CREATE INDEX IF NOT EXISTS idx_reminders_pending_scan
  ON public.reminders(relationship_id, recurrence, remind_at)
  WHERE sent = false;
CREATE INDEX IF NOT EXISTS idx_family_members_relationship
  ON public.couple_family_members(relationship_id);

-- === RPC: upsert_family_member ===
-- Single-transaction create/edit of a family member plus its linked
-- birthday reminder (REMINDERS.md §3). p_id NULL = create; non-NULL =
-- edit (must belong to caller's relationship, enforced by the UPDATE RLS
-- policy this RPC's caller still passes through — SECURITY DEFINER is
-- used here only to let one call write both tables atomically, not to
-- bypass the membership check, which is re-verified explicitly below).

CREATE OR REPLACE FUNCTION public.upsert_family_member(
  p_id uuid,
  p_name text,
  p_birthday date
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_relationship_id uuid;
  v_member_id uuid;
  v_reminder_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT id INTO v_relationship_id
  FROM public.relationships
  WHERE (user_a = v_user_id OR user_b = v_user_id) AND status = 'active';
  IF v_relationship_id IS NULL THEN
    RAISE EXCEPTION 'No active relationship';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.couple_family_members (relationship_id, name, birthday, created_by)
    VALUES (v_relationship_id, p_name, p_birthday, v_user_id)
    RETURNING id INTO v_member_id;
  ELSE
    UPDATE public.couple_family_members
    SET name = p_name, birthday = p_birthday
    WHERE id = p_id AND relationship_id = v_relationship_id
    RETURNING id INTO v_member_id;
    IF v_member_id IS NULL THEN
      RAISE EXCEPTION 'Family member not found';
    END IF;
  END IF;

  -- Sync the linked birthday reminder (create, update, or leave absent).
  IF p_birthday IS NOT NULL THEN
    SELECT id INTO v_reminder_id
    FROM public.reminders
    WHERE family_member_id = v_member_id AND reminder_type = 'birthday';

    IF v_reminder_id IS NULL THEN
      INSERT INTO public.reminders (
        relationship_id, created_by, reminder_type, title,
        remind_at, recurrence, family_member_id
      ) VALUES (
        v_relationship_id, v_user_id, 'birthday', p_name || '''s birthday',
        p_birthday::timestamptz, 'yearly', v_member_id
      );
    ELSE
      UPDATE public.reminders
      SET remind_at = p_birthday::timestamptz
      WHERE id = v_reminder_id;
    END IF;
  END IF;

  RETURN v_member_id;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_family_member(uuid, text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_family_member(uuid, text, date) TO authenticated;

-- === RPC: generate_reminder_notifications ===
-- Daily cron target. Computes each reminder's next occurrence via real
-- date arithmetic (make_date), never string/month-day comparison, so a
-- Dec 31 reminder's 3-day-before notification correctly lands on Jan 3
-- across a year boundary (REMINDERS.md §4 step 1).

CREATE OR REPLACE FUNCTION public.generate_reminder_notifications()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reminder record;
  v_next_occurrence date;
  v_today date := current_date;
BEGIN
  FOR v_reminder IN
    SELECT r.*, rel.user_a, rel.user_b
    FROM public.reminders r
    JOIN public.relationships rel ON rel.id = r.relationship_id
    WHERE r.recurrence = 'yearly' OR (r.recurrence = 'none' AND r.sent = false)
  LOOP
    IF v_reminder.recurrence = 'yearly' THEN
      -- Per-row computation is wrapped so a single malformed/edge-case date
      -- (e.g. a Feb-29 birthday in a non-leap year) can't raise an
      -- unhandled exception that would abort the entire FOR loop and skip
      -- every other reminder in this cron run.
      BEGIN
        v_next_occurrence := make_date(
          EXTRACT(YEAR FROM v_today)::int,
          EXTRACT(MONTH FROM v_reminder.remind_at)::int,
          EXTRACT(DAY FROM v_reminder.remind_at)::int
        );
        IF v_next_occurrence < v_today THEN
          v_next_occurrence := make_date(
            EXTRACT(YEAR FROM v_today)::int + 1,
            EXTRACT(MONTH FROM v_reminder.remind_at)::int,
            EXTRACT(DAY FROM v_reminder.remind_at)::int
          );
        END IF;
      EXCEPTION WHEN OTHERS THEN
        -- The only case that can raise here is a Feb-29 reminder landing on
        -- a non-leap year: fall back to firing on Feb 28 of that year
        -- (standard "day before" convention) rather than silently skipping
        -- the reminder for the whole year.
        IF EXTRACT(MONTH FROM v_reminder.remind_at)::int = 2
           AND EXTRACT(DAY FROM v_reminder.remind_at)::int = 29 THEN
          v_next_occurrence := make_date(EXTRACT(YEAR FROM v_today)::int, 2, 28);
          IF v_next_occurrence < v_today THEN
            v_next_occurrence := make_date(EXTRACT(YEAR FROM v_today)::int + 1, 2, 28);
          END IF;
        ELSE
          RAISE WARNING 'generate_reminder_notifications: failed to compute next occurrence for reminder %: %',
            v_reminder.id, SQLERRM;
          CONTINUE;
        END IF;
      END;
    ELSE
      v_next_occurrence := v_reminder.remind_at::date;
    END IF;

    IF v_next_occurrence = v_today OR v_next_occurrence = v_today + 3 THEN
      INSERT INTO public.scheduled_notifications (
        user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at
      )
      SELECT
        u.user_id, 'immediate', now(), 'pending',
        jsonb_build_object(
          'title', v_reminder.title,
          'body', CASE WHEN v_next_occurrence = v_today
                    THEN 'Today is ' || v_reminder.title
                    ELSE v_reminder.title || ' is in 3 days' END,
          'type', 'reminder_upcoming',
          'reminder_id', v_reminder.id,
          'days_until', CASE WHEN v_next_occurrence = v_today THEN 0 ELSE 3 END
        ),
        'reminder:' || v_reminder.id::text || ':' || v_next_occurrence::text || ':' || u.user_id::text,
        now(), now()
      FROM (VALUES (v_reminder.user_a), (v_reminder.user_b)) AS u(user_id)
      WHERE u.user_id IS NOT NULL
      ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;

      IF v_reminder.recurrence = 'none' AND v_next_occurrence = v_today THEN
        UPDATE public.reminders SET sent = true WHERE id = v_reminder.id;
      END IF;
    END IF;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.generate_reminder_notifications() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_reminder_notifications() TO service_role;
