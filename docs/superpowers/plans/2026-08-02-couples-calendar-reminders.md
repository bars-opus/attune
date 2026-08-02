# Couples Calendar & Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the shared couples calendar and reminders feature — completing `ATTUNE_MASTER_SPEC.md` §4.1/§8.3's unmigrated `reminders` table, adding a new `couple_family_members` table, and linking both to the already-built `timeline_events` table.

**Architecture:** Two new Postgres tables with fully-shared (both-partner) RLS, a daily `pg_cron`-scheduled RPC that generates reminder notifications by writing directly into the existing `scheduled_notifications` table (reusing `process-scheduled-notifications`/OneSignal delivery unmodified — no new edge function), and a Flutter feature module mirroring the Timeline feature's file layout, entered as a third pill tab alongside Pulse/Timeline.

**Tech Stack:** Flutter/Riverpod, Supabase Postgres (RLS, RPCs, `pg_cron`), GoRouter.

## Global Constraints

- `reminders.reminder_type` CHECK values: exactly `'anniversary'`, `'birthday'`, `'checkin'`, `'ai_generated'` (per `ATTUNE_MASTER_SPEC.md` §4.1 — do not add or remove values).
- `reminders.recurrence` CHECK values: exactly `'none'`, `'weekly'`, `'monthly'`, `'yearly'` — but the generator RPC (Task 3) only implements occurrence math for `'none'` and `'yearly'`; it must reject `'weekly'`/`'monthly'` writes at insert time (`REMINDERS.md` §6 schema note, §8 open question).
- `title` max 80 chars, `note` max 300 chars on both `reminders` and `couple_family_members.name` — matches `timeline_events`' existing length CHECKs (`PULSE.md` §8).
- Both `reminders` and `couple_family_members` are **fully shared**: either partner can SELECT/UPDATE/DELETE any row; INSERT requires `created_by = auth.uid()` plus relationship membership plus `status = 'active'`. This is a deliberate divergence from `timeline_events`' owner-only UPDATE/DELETE — do not copy that owner-only pattern here (`REMINDERS.md` §6).
- Reminder notification cadence is exactly two pushes per event per occurrence: 3 days before and on the day. Never more (`ATTUNE_MASTER_SPEC.md` §8.3: "single notification, never a barrage" — applied here as this fixed two-touch cadence, not zero-to-one).
- No new edge function for notification delivery. `generate_reminder_notifications()` is a plain SQL/plpgsql RPC invoked directly by `pg_cron` (`SELECT public.generate_reminder_notifications();`), not via `net.http_post` to an edge function — matches the `schedule_dating_maintenance.sql` RPC-direct-call shape, not the HTTP-post shape used for the notification *processor* itself.
- Route name for the new Calendar screen must be `couplesCalendar` (path `/couples-calendar`) — `RouteNames.calendar` (`/calendar`) already exists for an unrelated shop-appointment feature and must not be reused or collided with.
- Client-writable columns on both new tables must be restricted via `REVOKE INSERT ... FROM authenticated; GRANT INSERT (...) ON ... TO authenticated;` — server-only columns (`sent`, `linked_timeline_event_id`, timestamps) must never be client-insertable (`ATTUNE_MASTER_SPEC.md` §4.2 pattern).

---

## File Structure

- **Migration:** `supabase/migrations/20260814120000_couples_calendar_reminders.sql` — both tables, RLS, grants, indexes, the two RPCs (`upsert_family_member`, `generate_reminder_notifications`), a small pure-SQL occurrence-math helper function.
- **Cron:** `supabase/sql/schedule_generate_reminder_notifications.sql` — new daily schedule.
- **Flutter data layer:**
  - `lib/features/reminders/data/models/reminder_model.dart`
  - `lib/features/reminders/data/models/family_member_model.dart`
  - `lib/features/reminders/data/repositories/reminders_repository.dart`
- **Flutter presentation layer:**
  - `lib/features/reminders/presentation/providers/reminders_providers.dart`
  - `lib/features/reminders/presentation/screens/couples_calendar_screen.dart`
  - `lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart`
  - `lib/features/reminders/presentation/screens/family_members_screen.dart`
- **Modified:** `lib/app/routing/app_router.dart` (3 new routes), `lib/features/pulse/presentation/screens/pulse_tab.dart` (third pill tab).

---

### Task 1: Database migration — tables, RLS, RPCs

**Files:**
- Create: `supabase/migrations/20260814120000_couples_calendar_reminders.sql`

**Interfaces:**
- Consumes: existing `relationships(id, user_a, user_b, status)`, `timeline_events(id)`, `scheduled_notifications` (existing schema, insert-only from this migration's RPC).
- Produces: tables `public.reminders`, `public.couple_family_members`; RPCs `public.upsert_family_member(p_id uuid, p_name text, p_birthday date) RETURNS uuid`, `public.generate_reminder_notifications() RETURNS void`.

- [ ] **Step 1: Write the migration**

```sql
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
```

- [ ] **Step 2: Verify `scheduled_notifications.source_key` unique index already exists**

Run: `grep -n "scheduled_notifications_source_key_idx" supabase/migrations/*.sql`
Expected: found in `20260705210000_dating_mode_v1_2_hardening.sql` — this migration's `ON CONFLICT (source_key) WHERE source_key IS NOT NULL` clause depends on that pre-existing unique index and does not recreate it.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260814120000_couples_calendar_reminders.sql
git commit -m "feat(reminders): add couples calendar/reminders schema, RLS, RPCs"
```

Note: no automated test for this task — pure DDL/RLS/RPC SQL with no pure-function logic to unit test in isolation (the occurrence-math logic is embedded in the RPC body, not extracted to a separately-testable pure function, since it needs `current_date` and table access). `supabase db push` and live RPC verification are deferred to a human with a linked Supabase project, consistent with how every other migration task in this codebase's recent history has been handled in this sandboxed environment.

---

### Task 2: Cron schedule for reminder notifications

**Files:**
- Create: `supabase/sql/schedule_generate_reminder_notifications.sql`

**Interfaces:**
- Consumes: `public.generate_reminder_notifications()` (Task 1).
- Produces: a `pg_cron` job named `generate-reminder-notifications`, firing daily at 07:00 UTC.

- [ ] **Step 1: Write the schedule file**

```sql
-- supabase/sql/schedule_generate_reminder_notifications.sql
--
-- Daily at 07:00 UTC. Calls the RPC directly (not via net.http_post to an
-- edge function) — matches schedule_dating_maintenance.sql's RPC-direct
-- shape, since generate_reminder_notifications() is a plain SQL/plpgsql
-- function with no need for edge-function runtime.
SELECT cron.schedule(
  'generate-reminder-notifications',
  '0 7 * * *',
  $$ SELECT public.generate_reminder_notifications(); $$
);
```

- [ ] **Step 2: Commit**

```bash
git add supabase/sql/schedule_generate_reminder_notifications.sql
git commit -m "feat(reminders): schedule daily reminder-notification generation"
```

Note: installing this schedule against a live database (`psql` or Supabase SQL editor) is a deferred human/ops step, same as every other `supabase/sql/schedule_*.sql` file in this codebase — they are checked in as the installation script, not auto-applied by migrations.

---

### Task 3: Flutter data layer — models and repository

**Files:**
- Create: `lib/features/reminders/data/models/reminder_model.dart`
- Create: `lib/features/reminders/data/models/family_member_model.dart`
- Create: `lib/features/reminders/data/repositories/reminders_repository.dart`
- Test: `test/features/reminders/reminder_model_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks (independent of Tasks 1-2 for compilation; depends on them at runtime).
- Produces: `ReminderModel` (fields: `id, relationshipId, createdBy, reminderType, title, note, remindAt, recurrence, sent, familyMemberId, linkedTimelineEventId, createdAt, updatedAt`, factory `fromJson`, getters `isRecurring`, `isBirthday`, `isAnniversary`); `FamilyMemberModel` (fields: `id, relationshipId, name, birthday, createdBy, createdAt, updatedAt`, factory `fromJson`); `RemindersRepository` with methods `Future<List<ReminderModel>> listReminders(String relationshipId)`, `Future<ReminderModel> createReminder({required String relationshipId, required String createdBy, required String reminderType, required String title, String? note, required DateTime remindAt, required String recurrence, String? familyMemberId})`, `Future<ReminderModel> updateReminder({required String id, String? title, String? note, DateTime? remindAt, String? recurrence, String? familyMemberId})`, `Future<void> deleteReminder(String id)`, `Future<List<FamilyMemberModel>> listFamilyMembers(String relationshipId)`, `Future<String> upsertFamilyMember({String? id, required String name, DateTime? birthday})`, `Future<void> deleteFamilyMember(String id)`.

- [ ] **Step 1: Write the failing test for the reminder model**

```dart
// test/features/reminders/reminder_model_test.dart
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ReminderModel.fromJson parses a one-off reminder', () {
    final reminder = ReminderModel.fromJson({
      'id': 'rem-1',
      'relationship_id': 'rel-1',
      'created_by': 'user-1',
      'reminder_type': 'anniversary',
      'title': 'Our Anniversary',
      'note': null,
      'remind_at': '2026-09-14T00:00:00Z',
      'recurrence': 'none',
      'sent': false,
      'family_member_id': null,
      'linked_timeline_event_id': null,
      'created_at': '2026-08-02T10:00:00Z',
      'updated_at': '2026-08-02T10:00:00Z',
    });

    expect(reminder.id, 'rem-1');
    expect(reminder.isRecurring, isFalse);
    expect(reminder.isAnniversary, isTrue);
    expect(reminder.isBirthday, isFalse);
  });

  test('ReminderModel.fromJson parses a recurring birthday reminder', () {
    final reminder = ReminderModel.fromJson({
      'id': 'rem-2',
      'relationship_id': 'rel-1',
      'created_by': 'user-1',
      'reminder_type': 'birthday',
      'title': 'Emma\'s birthday',
      'note': 'Loves dinosaurs',
      'remind_at': '2026-03-10T00:00:00Z',
      'recurrence': 'yearly',
      'sent': false,
      'family_member_id': 'fam-1',
      'linked_timeline_event_id': null,
      'created_at': '2026-08-02T10:00:00Z',
      'updated_at': '2026-08-02T10:00:00Z',
    });

    expect(reminder.isRecurring, isTrue);
    expect(reminder.isBirthday, isTrue);
    expect(reminder.familyMemberId, 'fam-1');
    expect(reminder.note, 'Loves dinosaurs');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/reminders/reminder_model_test.dart`
Expected: FAIL — `reminder_model.dart` does not exist.

- [ ] **Step 3: Write the models**

```dart
// lib/features/reminders/data/models/reminder_model.dart
class ReminderModel {
  final String id;
  final String relationshipId;
  final String createdBy;
  final String reminderType; // anniversary | birthday | checkin | ai_generated
  final String title;
  final String? note;
  final DateTime remindAt;
  final String recurrence; // none | weekly | monthly | yearly
  final bool sent;
  final String? familyMemberId;
  final String? linkedTimelineEventId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ReminderModel({
    required this.id,
    required this.relationshipId,
    required this.createdBy,
    required this.reminderType,
    required this.title,
    this.note,
    required this.remindAt,
    required this.recurrence,
    required this.sent,
    this.familyMemberId,
    this.linkedTimelineEventId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    return ReminderModel(
      id: json['id'] as String,
      relationshipId: json['relationship_id'] as String,
      createdBy: json['created_by'] as String,
      reminderType: json['reminder_type'] as String,
      title: json['title'] as String,
      note: json['note'] as String?,
      remindAt: DateTime.parse(json['remind_at'] as String),
      recurrence: json['recurrence'] as String,
      sent: json['sent'] as bool,
      familyMemberId: json['family_member_id'] as String?,
      linkedTimelineEventId: json['linked_timeline_event_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  bool get isRecurring => recurrence == 'yearly';
  bool get isBirthday => reminderType == 'birthday';
  bool get isAnniversary => reminderType == 'anniversary';
}
```

```dart
// lib/features/reminders/data/models/family_member_model.dart
class FamilyMemberModel {
  final String id;
  final String relationshipId;
  final String name;
  final DateTime? birthday;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FamilyMemberModel({
    required this.id,
    required this.relationshipId,
    required this.name,
    this.birthday,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FamilyMemberModel.fromJson(Map<String, dynamic> json) {
    return FamilyMemberModel(
      id: json['id'] as String,
      relationshipId: json['relationship_id'] as String,
      name: json['name'] as String,
      birthday: json['birthday'] != null
          ? DateTime.parse(json['birthday'] as String)
          : null,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/reminders/reminder_model_test.dart`
Expected: PASS, 2/2 tests.

- [ ] **Step 5: Write the repository**

```dart
// lib/features/reminders/data/repositories/reminders_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/family_member_model.dart';
import '../models/reminder_model.dart';

class RemindersRepository {
  final SupabaseClient _supabase;

  RemindersRepository(this._supabase);

  Future<List<ReminderModel>> listReminders(String relationshipId) async {
    final response = await _supabase
        .from('reminders')
        .select()
        .eq('relationship_id', relationshipId)
        .order('remind_at');
    return (response as List)
        .map((row) => ReminderModel.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<ReminderModel> createReminder({
    required String relationshipId,
    required String createdBy,
    required String reminderType,
    required String title,
    String? note,
    required DateTime remindAt,
    required String recurrence,
    String? familyMemberId,
  }) async {
    final response = await _supabase
        .from('reminders')
        .insert({
          'relationship_id': relationshipId,
          'created_by': createdBy,
          'reminder_type': reminderType,
          'title': title,
          'note': note,
          'remind_at': remindAt.toIso8601String(),
          'recurrence': recurrence,
          'family_member_id': familyMemberId,
        })
        .select()
        .single();
    return ReminderModel.fromJson(response);
  }

  Future<ReminderModel> updateReminder({
    required String id,
    String? title,
    String? note,
    DateTime? remindAt,
    String? recurrence,
    String? familyMemberId,
  }) async {
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title;
    if (note != null) updates['note'] = note;
    if (remindAt != null) updates['remind_at'] = remindAt.toIso8601String();
    if (recurrence != null) updates['recurrence'] = recurrence;
    if (familyMemberId != null) updates['family_member_id'] = familyMemberId;

    final response = await _supabase
        .from('reminders')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
    return ReminderModel.fromJson(response);
  }

  Future<void> deleteReminder(String id) async {
    await _supabase.from('reminders').delete().eq('id', id);
  }

  Future<List<FamilyMemberModel>> listFamilyMembers(String relationshipId) async {
    final response = await _supabase
        .from('couple_family_members')
        .select()
        .eq('relationship_id', relationshipId)
        .order('name');
    return (response as List)
        .map((row) => FamilyMemberModel.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<String> upsertFamilyMember({
    String? id,
    required String name,
    DateTime? birthday,
  }) async {
    final response = await _supabase.rpc(
      'upsert_family_member',
      params: {
        'p_id': id,
        'p_name': name,
        'p_birthday': birthday != null
            ? birthday.toIso8601String().split('T')[0]
            : null,
      },
    );
    return response as String;
  }

  Future<void> deleteFamilyMember(String id) async {
    await _supabase.from('couple_family_members').delete().eq('id', id);
  }
}
```

- [ ] **Step 6: Run `flutter analyze`**

Run: `flutter analyze lib/features/reminders test/features/reminders`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/features/reminders/data/models/reminder_model.dart
git add lib/features/reminders/data/models/family_member_model.dart
git add lib/features/reminders/data/repositories/reminders_repository.dart
git add test/features/reminders/reminder_model_test.dart
git commit -m "feat(reminders): add data models and repository"
```

---

### Task 4: Riverpod providers

**Files:**
- Create: `lib/features/reminders/presentation/providers/reminders_providers.dart`

**Interfaces:**
- Consumes: `RemindersRepository`, `ReminderModel`, `FamilyMemberModel` (Task 3).
- Produces: `remindersRepositoryProvider` (`Provider<RemindersRepository>`), `currentRelationshipIdProvider` (`FutureProvider<String?>`, feature-local copy following this codebase's existing per-feature convention — see Timeline/Pulse/Verdict/ConflictTranslator's own copies, not a shared cross-feature import), `remindersListProvider` (`FutureProvider<List<ReminderModel>>`), `familyMembersListProvider` (`FutureProvider<List<FamilyMemberModel>>`), `createReminderProvider` (`FutureProvider.family<ReminderModel, ({String reminderType, String title, String? note, DateTime remindAt, String recurrence, String? familyMemberId})>`), `deleteReminderProvider` (`FutureProvider.family<void, String>`), `upsertFamilyMemberProvider` (`FutureProvider.family<String, ({String? id, String name, DateTime? birthday})>`), `deleteFamilyMemberProvider` (`FutureProvider.family<void, String>`).

- [ ] **Step 1: Write the providers**

```dart
// lib/features/reminders/presentation/providers/reminders_providers.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/family_member_model.dart';
import '../../data/models/reminder_model.dart';
import '../../data/repositories/reminders_repository.dart';

final remindersRepositoryProvider = Provider<RemindersRepository>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return RemindersRepository(supabase);
});

// Feature-local copy of the current active relationship id, following the
// same per-feature convention already used by Timeline/Pulse/Verdict/
// ConflictTranslator in this codebase (each feature keeps its own copy
// rather than importing across feature boundaries).
final currentRelationshipIdProvider = FutureProvider<String?>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final response = await supabase
      .from('relationships')
      .select('id')
      .or('user_a.eq.$userId,user_b.eq.$userId')
      .eq('status', 'active')
      .maybeSingle();
  return response?['id'] as String?;
});

final remindersListProvider = FutureProvider<List<ReminderModel>>((ref) async {
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return const [];
  return ref.read(remindersRepositoryProvider).listReminders(relationshipId);
});

final familyMembersListProvider = FutureProvider<List<FamilyMemberModel>>((ref) async {
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return const [];
  return ref.read(remindersRepositoryProvider).listFamilyMembers(relationshipId);
});

final createReminderProvider = FutureProvider.family<
  ReminderModel,
  ({
    String reminderType,
    String title,
    String? note,
    DateTime remindAt,
    String recurrence,
    String? familyMemberId,
  })
>((ref, params) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser!.id;
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) {
    throw StateError('No active relationship');
  }
  final reminder = await ref.read(remindersRepositoryProvider).createReminder(
        relationshipId: relationshipId,
        createdBy: userId,
        reminderType: params.reminderType,
        title: params.title,
        note: params.note,
        remindAt: params.remindAt,
        recurrence: params.recurrence,
        familyMemberId: params.familyMemberId,
      );
  ref.invalidate(remindersListProvider);
  return reminder;
});

final deleteReminderProvider = FutureProvider.family<void, String>((ref, id) async {
  await ref.read(remindersRepositoryProvider).deleteReminder(id);
  ref.invalidate(remindersListProvider);
});

final upsertFamilyMemberProvider = FutureProvider.family<
  String,
  ({String? id, String name, DateTime? birthday})
>((ref, params) async {
  final memberId = await ref.read(remindersRepositoryProvider).upsertFamilyMember(
        id: params.id,
        name: params.name,
        birthday: params.birthday,
      );
  ref.invalidate(familyMembersListProvider);
  ref.invalidate(remindersListProvider);
  return memberId;
});

final deleteFamilyMemberProvider = FutureProvider.family<void, String>((ref, id) async {
  await ref.read(remindersRepositoryProvider).deleteFamilyMember(id);
  ref.invalidate(familyMembersListProvider);
  ref.invalidate(remindersListProvider);
});
```

- [ ] **Step 2: Run `flutter analyze`**

Run: `flutter analyze lib/features/reminders`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/reminders/presentation/providers/reminders_providers.dart
git commit -m "feat(reminders): add Riverpod providers"
```

---

### Task 5: Screens — Calendar, add/edit reminder, family members

**Files:**
- Create: `lib/features/reminders/presentation/screens/couples_calendar_screen.dart`
- Create: `lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart`
- Create: `lib/features/reminders/presentation/screens/family_members_screen.dart`

**Interfaces:**
- Consumes: `remindersListProvider`, `familyMembersListProvider`, `createReminderProvider`, `deleteReminderProvider`, `upsertFamilyMemberProvider`, `deleteFamilyMemberProvider` (Task 4); `ReminderModel`, `FamilyMemberModel` (Task 3); app-wide `AppButton`, `AppTextFormField`, `EmptyStateWidget`, `ErrorStateWidget` (already used throughout this codebase).
- Produces: `CouplesCalendarScreen` (`ConsumerWidget`, no constructor args), `AddEditReminderScreen` (`ConsumerStatefulWidget`, no constructor args — reads an optional `reminderId` via GoRouter's extra/query param for edit mode), `FamilyMembersScreen` (`ConsumerWidget`, no constructor args).

- [ ] **Step 1: Write `CouplesCalendarScreen`**

```dart
// lib/features/reminders/presentation/screens/couples_calendar_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CouplesCalendarScreen extends ConsumerWidget {
  const CouplesCalendarScreen({super.key});

  DateTime _nextOccurrence(ReminderModel reminder) {
    if (!reminder.isRecurring) return reminder.remindAt;
    final now = DateTime.now();
    var next = DateTime(now.year, reminder.remindAt.month, reminder.remindAt.day);
    if (next.isBefore(DateTime(now.year, now.month, now.day))) {
      next = DateTime(now.year + 1, reminder.remindAt.month, reminder.remindAt.day);
    }
    return next;
  }

  String _countdownLabel(DateTime occurrence) {
    final today = DateTime.now();
    final days = DateTime(occurrence.year, occurrence.month, occurrence.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    return 'In $days days';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(remindersListProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Calendar',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            onPressed: () => context.pushNamed('familyMembers'),
          ),
        ],
      ),
      body: remindersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: ErrorStateWidget(
            title: 'Something went wrong',
            subtitle: 'We couldn\'t load your calendar right now. Please try again in a moment.',
          ),
        ),
        data: (reminders) {
          if (reminders.isEmpty) {
            return Center(
              child: EmptyStateWidget(
                title: 'No events yet',
                subtitle: 'Add an anniversary, birthday, or any date you want to remember together.',
              ),
            );
          }
          final sorted = [...reminders]
            ..sort((a, b) => _nextOccurrence(a).compareTo(_nextOccurrence(b)));
          return ListView.separated(
            padding: EdgeInsets.all(Spacing.md.w),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => Gap(Spacing.sm.h),
            itemBuilder: (context, index) {
              final reminder = sorted[index];
              final occurrence = _nextOccurrence(reminder);
              return Container(
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                ),
                child: Row(
                  children: [
                    Icon(reminder.isRecurring ? Icons.repeat : Icons.event_outlined),
                    Gap(Spacing.sm.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(reminder.title, style: textTheme.titleSmall),
                          Text(_countdownLabel(occurrence), style: textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.pushNamed('addEditReminder'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

- [ ] **Step 2: Write `AddEditReminderScreen`**

```dart
// lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AddEditReminderScreen extends ConsumerStatefulWidget {
  const AddEditReminderScreen({super.key});

  @override
  ConsumerState<AddEditReminderScreen> createState() => _AddEditReminderScreenState();
}

class _AddEditReminderScreenState extends ConsumerState<AddEditReminderScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  String _reminderType = 'anniversary';
  DateTime _remindAt = DateTime.now();
  bool _isYearly = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _remindAt,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _remindAt = picked);
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      context.showErrorSnackbar('Please add a title.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ref.read(
        createReminderProvider((
          reminderType: _reminderType,
          title: _titleController.text.trim(),
          note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          remindAt: _remindAt,
          recurrence: _isYearly ? 'yearly' : 'none',
          familyMemberId: null,
        )).future,
      );
      if (!mounted) return;
      context.showSuccessSnackbar('Added to your calendar.');
      context.pop();
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar('Could not save that. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Add to calendar',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.md.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextFormField(
              controller: _titleController,
              label: 'Title',
              hintText: 'Our anniversary, Emma\'s birthday...',
            ),
            Gap(Spacing.md.h),
            AppTextFormField(
              controller: _noteController,
              label: 'Note (optional)',
              maxLines: 3,
              maxLength: 300,
            ),
            Gap(Spacing.md.h),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text('${_remindAt.year}-${_remindAt.month.toString().padLeft(2, '0')}-${_remindAt.day.toString().padLeft(2, '0')}'),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _pickDate,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeats every year'),
              value: _isYearly,
              onChanged: (value) => setState(() => _isYearly = value),
            ),
            const Spacer(),
            AppButton(
              label: _isSaving ? 'Saving...' : 'Save',
              onPressed: _isSaving ? null : _save,
              size: ButtonSize.large,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Write `FamilyMembersScreen`**

```dart
// lib/features/reminders/presentation/screens/family_members_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FamilyMembersScreen extends ConsumerWidget {
  const FamilyMembersScreen({super.key});

  Future<void> _addOrEdit(BuildContext context, WidgetRef ref, {String? id, String? existingName, DateTime? existingBirthday}) async {
    final nameController = TextEditingController(text: existingName ?? '');
    DateTime? birthday = existingBirthday;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.all(Spacing.md.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextFormField(controller: nameController, label: 'Name'),
              Gap(Spacing.md.h),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Birthday (optional)'),
                subtitle: Text(birthday == null
                    ? 'Not set'
                    : '${birthday!.year}-${birthday!.month.toString().padLeft(2, '0')}-${birthday!.day.toString().padLeft(2, '0')}'),
                trailing: const Icon(Icons.cake_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: sheetContext,
                    initialDate: birthday ?? DateTime(2020),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) birthday = picked;
                },
              ),
              Gap(Spacing.md.h),
              AppButton(
                label: 'Save',
                width: double.infinity,
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) return;
                  await ref.read(
                    upsertFamilyMemberProvider((
                      id: id,
                      name: nameController.text.trim(),
                      birthday: birthday,
                    )).future,
                  );
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(familyMembersListProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Family',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: ErrorStateWidget(
            title: 'Something went wrong',
            subtitle: 'We couldn\'t load your family list right now.',
          ),
        ),
        data: (members) {
          if (members.isEmpty) {
            return Center(
              child: EmptyStateWidget(
                title: 'No family members yet',
                subtitle: 'Add kids or family so their birthdays show up on your calendar automatically.',
              ),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.all(Spacing.md.w),
            itemCount: members.length,
            itemBuilder: (context, index) {
              final member = members[index];
              return ListTile(
                title: Text(member.name),
                subtitle: member.birthday != null
                    ? Text('${member.birthday!.year}-${member.birthday!.month.toString().padLeft(2, '0')}-${member.birthday!.day.toString().padLeft(2, '0')}')
                    : const Text('No birthday set'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => ref.read(deleteFamilyMemberProvider(member.id).future),
                ),
                onTap: () => _addOrEdit(context, ref, id: member.id, existingName: member.name, existingBirthday: member.birthday),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEdit(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

- [ ] **Step 4: Run `flutter analyze`**

Run: `flutter analyze lib/features/reminders`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/reminders/presentation/screens/couples_calendar_screen.dart
git add lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart
git add lib/features/reminders/presentation/screens/family_members_screen.dart
git commit -m "feat(reminders): add calendar, add/edit, and family members screens"
```

---

### Task 6: Route registration and entry point

**Files:**
- Modify: `lib/app/routing/app_router.dart`
- Modify: `lib/features/pulse/presentation/screens/pulse_tab.dart`

**Interfaces:**
- Consumes: `CouplesCalendarScreen`, `AddEditReminderScreen`, `FamilyMembersScreen` (Task 5).
- Produces: three new named routes (`couplesCalendar`, `addEditReminder`, `familyMembers`); a third pill tab in `PulseTab`.

- [ ] **Step 1: Add route name constants**

In `lib/app/routing/app_router.dart`, inside the `RouteNames` class, add alongside the other couples-feature constants (near `pulse`, `weeklyCheckin`):

```dart
  static const String couplesCalendar = '/couples-calendar';
  static const String addEditReminder = '/couples-calendar/add';
  static const String familyMembers = '/couples-calendar/family';
```

Do not reuse `RouteNames.calendar` (`/calendar`) — that constant already exists for the unrelated shop-appointment feature (`lib/core/notifications/config/notification_config.dart`) and colliding with it would misroute `shop_reminder_15min` notification taps.

- [ ] **Step 2: Add the import and GoRoutes**

Add near the other feature imports in `app_router.dart`:

```dart
import 'package:attune/features/reminders/presentation/screens/couples_calendar_screen.dart';
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:attune/features/reminders/presentation/screens/family_members_screen.dart';
```

Add near the other couples-feature `GoRoute`s:

```dart
      GoRoute(
        path: RouteNames.couplesCalendar,
        name: 'couplesCalendar',
        builder: (context, state) => const CouplesCalendarScreen(),
      ),
      GoRoute(
        path: RouteNames.addEditReminder,
        name: 'addEditReminder',
        builder: (context, state) => const AddEditReminderScreen(),
      ),
      GoRoute(
        path: RouteNames.familyMembers,
        name: 'familyMembers',
        builder: (context, state) => const FamilyMembersScreen(),
      ),
```

- [ ] **Step 3: Add the third pill tab in `PulseTab`**

In `lib/features/pulse/presentation/screens/pulse_tab.dart`, this is the exact current file — modify it as follows:

Change the import block to add:
```dart
import 'package:attune/features/reminders/presentation/screens/couples_calendar_screen.dart';
```

Change `_tabController = TabController(length: 2, vsync: this);` to:
```dart
    _tabController = TabController(length: 3, vsync: this);
```

Change the pill row:
```dart
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPillOption('Pulse', 0),
                    _buildPillOption('Timeline', 1),
                    _buildPillOption('Calendar', 2),
                  ],
                ),
```

Change the `TabBarView` children:
```dart
              children: const [PulseScreen(), TimelineScreen(), CouplesCalendarScreen()],
```

- [ ] **Step 4: Run `flutter analyze`**

Run: `flutter analyze lib/app/routing/app_router.dart lib/features/pulse/presentation/screens/pulse_tab.dart lib/features/reminders`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/app/routing/app_router.dart lib/features/pulse/presentation/screens/pulse_tab.dart
git commit -m "feat(reminders): register routes and add Calendar tab entry point"
```

---

### Task 7: Timeline link — optional linked event on anniversary/birthday reminders

**Files:**
- Modify: `lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart`
- Modify: `lib/features/reminders/data/repositories/reminders_repository.dart`

**Interfaces:**
- Consumes: `TimelineRepository.createEvent({required relationshipId, required loggedBy, required eventType, required title, required occurredAt, String? note, int? moodScore})` (already exists at `lib/features/timeline/data/repositories/timeline_repository.dart:17`).
- Produces: `RemindersRepository.linkReminderToTimelineEvent({required String reminderId, required String timelineEventId})`.

- [ ] **Step 1: Add the repository method to write the link**

Add to `RemindersRepository` in `lib/features/reminders/data/repositories/reminders_repository.dart`:

```dart
  Future<void> linkReminderToTimelineEvent({
    required String reminderId,
    required String timelineEventId,
  }) async {
    await _supabase
        .from('reminders')
        .update({'linked_timeline_event_id': timelineEventId})
        .eq('id', reminderId);
  }
```

Note: `linked_timeline_event_id` is intentionally NOT in the column-level `GRANT UPDATE` list from Task 1's migration (`reminder_type, title, note, remind_at, recurrence, family_member_id` only) — this call will be rejected by Postgres's column privilege check as written. Before this step is considered complete, add `linked_timeline_event_id` to that migration's `GRANT UPDATE (...)` column list (Task 1, already committed — this is a follow-up `ALTER` in this task, not a Task 1 edit):

```sql
-- Add to the end of this task's changes, as a small addendum migration:
-- supabase/migrations/20260814130000_reminders_timeline_link_grant.sql
GRANT UPDATE (linked_timeline_event_id) ON public.reminders TO authenticated;
```

Create that file with exactly that one line (plus a comment explaining why), and commit it alongside this task's Dart changes.

- [ ] **Step 2: Wire the optional link into the add/edit screen**

In `lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart`, modify the `_save` method: after a successful `createReminderProvider` call, if `_reminderType` is `'anniversary'` (birthdays get their link automatically via `upsert_family_member`'s own flow in Task 1's RPC — no timeline link needed there since family members aren't "moments"), show a confirmation dialog offering to also log it to the Timeline, then call `TimelineRepository.createEvent` followed by `RemindersRepository.linkReminderToTimelineEvent`:

```dart
  Future<void> _offerTimelineLink(String reminderId) async {
    if (_reminderType != 'anniversary') return;
    final shouldLink = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to your Timeline too?'),
        content: const Text('This will also log it as a memory you can look back on.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add it'),
          ),
        ],
      ),
    );
    if (shouldLink != true || !mounted) return;

    final supabase = Supabase.instance.client;
    final relationshipId = await ref.read(currentRelationshipIdProvider.future);
    final userId = supabase.auth.currentUser?.id;
    if (relationshipId == null || userId == null) return;

    final timelineRepository = TimelineRepository(supabase);
    final event = await timelineRepository.createEvent(
      relationshipId: relationshipId,
      loggedBy: userId,
      eventType: 'anniversary',
      title: _titleController.text.trim(),
      occurredAt: _remindAt,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );
    await ref.read(remindersRepositoryProvider).linkReminderToTimelineEvent(
          reminderId: reminderId,
          timelineEventId: event.id,
        );
  }
```

Add the imports this needs:
```dart
import 'package:attune/features/timeline/data/repositories/timeline_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
```

Change the `_save` method's success path from:
```dart
      if (!mounted) return;
      context.showSuccessSnackbar('Added to your calendar.');
      context.pop();
```
to:
```dart
      if (!mounted) return;
      final reminder = await ref.read(
        createReminderProvider((
          reminderType: _reminderType,
          title: _titleController.text.trim(),
          note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          remindAt: _remindAt,
          recurrence: _isYearly ? 'yearly' : 'none',
          familyMemberId: null,
        )).future,
      );
      await _offerTimelineLink(reminder.id);
      if (!mounted) return;
      context.showSuccessSnackbar('Added to your calendar.');
      context.pop();
```

(This replaces the earlier plain `await ref.read(createReminderProvider(...).future);` call from Task 5 Step 2 — the create call now captures its return value to pass to `_offerTimelineLink`.)

- [ ] **Step 3: Run `flutter analyze`**

Run: `flutter analyze lib/features/reminders`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart
git add lib/features/reminders/data/repositories/reminders_repository.dart
git add supabase/migrations/20260814130000_reminders_timeline_link_grant.sql
git commit -m "feat(reminders): offer optional Timeline link for anniversary reminders"
```

---

### Task 8: Calendar month view blends in Timeline anniversaries

**Files:**
- Modify: `lib/features/reminders/presentation/screens/couples_calendar_screen.dart`

**Interfaces:**
- Consumes: `TimelineRepository.getEventsForMonth({required String relationshipId, required DateTime month})` (existing, `lib/features/timeline/data/repositories/timeline_repository.dart:111`), `TimelineEventModel` (existing).
- Produces: the Calendar screen's list additionally includes past/current-month `timeline_events` rows where `event_type = 'anniversary'`, visually distinguished from upcoming `reminders` rows (§2 of `REMINDERS.md` — this is display-only blending, not a data merge; the two tables remain independent).

- [ ] **Step 1: Add a provider that fetches this month's timeline anniversaries**

Add to `lib/features/reminders/presentation/providers/reminders_providers.dart`:

```dart
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/data/repositories/timeline_repository.dart';

final timelineAnniversariesThisMonthProvider =
    FutureProvider<List<TimelineEventModel>>((ref) async {
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) return const [];
  final supabase = ref.read(supabaseClientProvider);
  final events = await TimelineRepository(supabase).getEventsForMonth(
    relationshipId: relationshipId,
    month: DateTime.now(),
  );
  return events.where((e) => e.eventType == 'anniversary').toList(growable: false);
});
```

- [ ] **Step 2: Show them in a separate section on the Calendar screen**

In `lib/features/reminders/presentation/screens/couples_calendar_screen.dart`, change `CouplesCalendarScreen` from `ConsumerWidget` to read the second provider and render a labeled section above the upcoming-reminders list when non-empty. Replace the `build` method's `data:` branch body with:

```dart
        data: (reminders) {
          final timelineAsync = ref.watch(timelineAnniversariesThisMonthProvider);
          final sorted = [...reminders]
            ..sort((a, b) => _nextOccurrence(a).compareTo(_nextOccurrence(b)));

          if (reminders.isEmpty) {
            return timelineAsync.maybeWhen(
              data: (timelineEvents) => timelineEvents.isEmpty
                  ? Center(
                      child: EmptyStateWidget(
                        title: 'No events yet',
                        subtitle: 'Add an anniversary, birthday, or any date you want to remember together.',
                      ),
                    )
                  : _buildList(context, sorted, timelineEvents, textTheme),
              orElse: () => Center(
                child: EmptyStateWidget(
                  title: 'No events yet',
                  subtitle: 'Add an anniversary, birthday, or any date you want to remember together.',
                ),
              ),
            );
          }

          return timelineAsync.maybeWhen(
            data: (timelineEvents) => _buildList(context, sorted, timelineEvents, textTheme),
            orElse: () => _buildList(context, sorted, const [], textTheme),
          );
        },
```

Add this helper method to the `CouplesCalendarScreen` class:

```dart
  Widget _buildList(
    BuildContext context,
    List<ReminderModel> reminders,
    List<dynamic> timelineEvents,
    TextTheme textTheme,
  ) {
    return ListView(
      padding: EdgeInsets.all(Spacing.md.w),
      children: [
        if (timelineEvents.isNotEmpty) ...[
          Text('This month in your Timeline', style: textTheme.titleSmall),
          Gap(Spacing.sm.h),
          for (final event in timelineEvents)
            Padding(
              padding: EdgeInsets.only(bottom: Spacing.sm.h),
              child: ListTile(
                leading: const Icon(Icons.history_outlined),
                title: Text(event.title as String),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          Gap(Spacing.lg.h),
        ],
        for (final reminder in reminders)
          Padding(
            padding: EdgeInsets.only(bottom: Spacing.sm.h),
            child: Container(
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: Row(
                children: [
                  Icon(reminder.isRecurring ? Icons.repeat : Icons.event_outlined),
                  Gap(Spacing.sm.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(reminder.title, style: textTheme.titleSmall),
                        Text(_countdownLabel(_nextOccurrence(reminder)), style: textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
```

Remove the old inline `ListView.separated`/`itemBuilder` block from the `data:` branch (now replaced by `_buildList`).

- [ ] **Step 3: Run `flutter analyze`**

Run: `flutter analyze lib/features/reminders`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/reminders/presentation/providers/reminders_providers.dart
git add lib/features/reminders/presentation/screens/couples_calendar_screen.dart
git commit -m "feat(reminders): blend Timeline anniversaries into the Calendar view"
```

---

## Post-implementation manual verification (not a task — a checklist for the final reviewer)

- [ ] Add a one-off reminder for tomorrow (1 day out); run `generate_reminder_notifications()` manually via SQL editor (no linked Supabase project exists in this sandbox) and confirm it inserts NO `scheduled_notifications` rows — the fixed cadence only fires at exactly 3-days-out and 0-days-out, so a 1-day-out reminder must generate nothing.
- [ ] Add a one-off reminder for exactly 3 days out; run the RPC and confirm it inserts one `scheduled_notifications` row per partner with `metadata.days_until = 3`.
- [ ] Add a family member with a birthday via `upsert_family_member`; confirm exactly one `reminders` row is created with `reminder_type = 'birthday'`, `recurrence = 'yearly'`, `family_member_id` set.
- [ ] Edit that family member's birthday; confirm the linked reminder's `remind_at` updates in place rather than creating a second reminder row.
- [ ] Delete the family member; confirm the linked reminder still exists with `family_member_id = NULL` (not cascade-deleted).
- [ ] Add a Dec 31 yearly reminder; run `generate_reminder_notifications()` with `current_date` mocked to Dec 28 (or verify the `make_date` logic by inspection); confirm the 3-day-before notification's target date correctly computes to Jan 3 of the following year, not a null/error from an invalid Dec 34.
- [ ] Attempt to insert a reminder with `recurrence = 'weekly'` directly via SQL; confirm the trigger rejects it.
- [ ] As partner A, add a reminder; confirm partner B can see it, edit its title, and delete it (fully-shared RLS, not owner-only).
- [ ] From the add/edit reminder screen, create an anniversary reminder and accept the "add to Timeline too" offer; confirm a `timeline_events` row is created with matching title/date and the `reminders` row's `linked_timeline_event_id` is set.
- [ ] Confirm the Calendar tab appears as a third pill in the existing Pulse/Timeline tab switcher, and that tapping the people icon opens the Family screen.
