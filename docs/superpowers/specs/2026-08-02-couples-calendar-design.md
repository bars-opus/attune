# Couples Calendar & Reminders — Design

**Goal:** A shared calendar for couples to track anniversaries, kids' birthdays, and other special dates, with automatic yearly reminders and shared notes — visible and editable by both partners.

## 1. Scope

In scope:
- A shared event list/calendar per relationship: title, date, optional notes, optional recurrence (yearly).
- A lightweight family-member list (for birthdays), reusable across events and years.
- Automatic push reminders: 3 days before and on the day, for every partner.
- Full read/write access for both partners on every event (no per-event ownership/locking).

Out of scope (explicitly deferred):
- General RRULE recurrence (monthly, weekly, custom intervals) — yearly only.
- Calendar sync (Google/Apple Calendar import/export).
- In-app calendar-grid UI (month/week grid view) — v1 ships as a sorted upcoming-events list, not a grid.
- Per-event reminder customization — the 3-day/day-of cadence is fixed for all events.
- Guests/sharing beyond the two partners in the relationship.

## 2. Data model

### `couple_family_members`

Reusable people (kids, family) a couple can tag to birthday events.

```sql
CREATE TABLE public.couple_family_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  name text NOT NULL,
  birthday date,  -- nullable: a family member can exist without a birthday on file
  created_by uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

### `couple_calendar_events`

```sql
CREATE TABLE public.couple_calendar_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  title text NOT NULL,
  notes text,
  event_date date NOT NULL,          -- month/day is what matters if recurring; year is kept as the original/most recent occurrence
  is_recurring_yearly boolean NOT NULL DEFAULT false,
  family_member_id uuid REFERENCES public.couple_family_members(id) ON DELETE SET NULL,
  created_by uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

Adding a family member with a birthday auto-creates a matching `couple_calendar_events` row (`is_recurring_yearly = true`, `family_member_id` set, title `"<name>'s Birthday"`) via a single RPC, `upsert_family_member(...)`, that writes both rows in one transaction — so the couple never has to enter the same date twice and the two rows can't drift out of sync. That same RPC handles edits: changing the birthday on an existing family member updates its linked event's `event_date` in the same transaction. Deleting a family member (`delete_family_member(id)`) sets `family_member_id` to `NULL` on the event via `ON DELETE SET NULL` but leaves the event itself intact (the birthday reminder shouldn't vanish just because the person record was tidied up) — the event's title is left as-is rather than auto-edited, since the couple may have since customized it.

## 3. Access model

Both partners share full read/write/delete access to every event and family member in their relationship — no per-event ownership, matching the "fully shared" decision. RLS follows the `messages` table's membership-check pattern exactly:

```sql
CREATE POLICY couple_calendar_events_select_members ON public.couple_calendar_events
FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.relationships r
  WHERE r.id = couple_calendar_events.relationship_id
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
));

CREATE POLICY couple_calendar_events_insert_members ON public.couple_calendar_events
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = couple_calendar_events.relationship_id
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
      AND r.status = 'active'
  )
);

CREATE POLICY couple_calendar_events_update_members ON public.couple_calendar_events
FOR UPDATE TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.relationships r
  WHERE r.id = couple_calendar_events.relationship_id
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
));

CREATE POLICY couple_calendar_events_delete_members ON public.couple_calendar_events
FOR DELETE TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.relationships r
  WHERE r.id = couple_calendar_events.relationship_id
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
));
```

`couple_family_members` gets the identical four-policy shape. Both tables require `status = 'active'` only on INSERT (mirroring `messages`) — a paused/ended relationship can still be viewed (read history) but not added to.

## 4. Reminders

No new delivery infrastructure. A daily `pg_cron` job (`schedule_generate_calendar_reminders.sql`, mirroring the existing `schedule_process_scheduled_notifications.sql` pattern) invokes a new RPC, `generate_calendar_event_reminders()`, once per day (e.g. 07:00 UTC). That RPC:

1. For each event, computes its *next occurrence date*: for a recurring event, that's `event_date` with the year replaced by the current year (or next year, if that date has already passed this year) — computed via actual date arithmetic (`make_date`), not string/month-day comparison, so year boundaries (e.g. a Dec 31 event's 3-day-before reminder landing on Jan 3) resolve correctly. For a one-off event, the next occurrence is just `event_date` itself. A row is a match if its next-occurrence date equals **today** or **today + 3 days**.
2. For each match, inserts one `scheduled_notifications` row **per partner** in the relationship (`user_id = user_a`, then `user_id = user_b`), `notification_type = 'calendar_event_reminder'`, `scheduled_for = now()`, `metadata = {event_id, title, days_until: 0 or 3}`.
3. Uses a `source_key` (e.g. `'calendar_reminder:' || event_id || ':' || target_date || ':' || user_id`) with `ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING`, so a cron re-run on the same day never double-sends — same idempotency pattern already used for `dating_match` notifications.

This reuses `process-scheduled-notifications` and OneSignal delivery entirely unmodified. No outbox table, no new edge function needed for delivery — only the daily generator RPC and its cron schedule are new.

## 5. Client (Flutter)

Follows the chat feature's file layout:

- `lib/features/couple_calendar/data/repositories/{couple_calendar_repository.dart (abstract), supabase_couple_calendar_repository.dart (impl)}`
- `lib/features/couple_calendar/data/models/{calendar_event.dart, family_member.dart}`
- `lib/features/couple_calendar/presentation/providers/couple_calendar_providers.dart` (Riverpod `FutureProvider`s/`family` providers for list/add/edit/delete, mirroring the dating-photo work's provider shape)
- `lib/features/couple_calendar/presentation/screens/{couple_calendar_screen.dart, add_edit_event_screen.dart, family_members_screen.dart}`

`CoupleCalendarScreen` (v1): a single sorted list of upcoming events (soonest first, recurring events shown at their next occurrence), grouped by month, each row showing title + relative countdown ("in 3 days") + a small icon distinguishing recurring vs one-off. Tapping opens the edit sheet; a FAB opens add-event. A secondary "Family" entry point opens the family-member list (add/edit name + birthday), from which adding a birthday offers to also create the linked event automatically (per §2).

Route registration and an entry point follow the existing pattern: two new `RouteNames` constants, two `GoRoute`s, and an entry point placed in whatever screen already serves as the couple's shared-features hub (to be located during implementation — likely the relationship home/dashboard screen, TBD by reading `app_router.dart`'s existing couples-feature entries at implementation time).

## 6. Testing evidence expected at implementation time

- Unit tests for the "does this event fire a reminder today" date-matching logic (recurring month/day match, one-off exact-date match, leap-year Feb 29 handling — recommend firing on Feb 28 in non-leap years rather than skipping the reminder every 4th year).
- A test proving the idempotency key prevents duplicate `scheduled_notifications` rows on repeated cron runs.
- A test proving deleting a family member does not delete its linked calendar event (`ON DELETE SET NULL`, not `CASCADE`).
- RLS covered by the same manual-verification-checklist pattern used elsewhere in this codebase (no live DB in the sandboxed dev environment), or a pgTAP test if the project has that tooling — to be confirmed during planning.
