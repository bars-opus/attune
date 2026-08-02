# ATTUNE — COUPLES CALENDAR & REMINDERS SPECIFICATION

**Version:** 1.0
**Created:** August 2026
**Status:** Ready for implementation
**Related documents:** `ATTUNE_MASTER_SPEC.md` (§4.1 `reminders`, §8.3 Relationship Tracking — this document completes both), `PULSE.md` (§3, §8 `timeline_events` — this document extends it), `ATTUNE_SOUL.md`, `ATTUNE_PRINCIPLES_CHECKLIST.md`

---

> **HOW TO USE THIS DOCUMENT**
>
> `ATTUNE_MASTER_SPEC.md` §4.1 already locks in a `reminders` table
> (`reminder_type IN ('anniversary','birthday','checkin','ai_generated')`,
> `recurrence`) and §8.3 already states the product intent ("Anniversaries
> and birthdays: set manually"). Neither was ever migrated or built — this
> document is that completion, not a competing design. Do not invent a new
> events table for anniversaries/birthdays; extend `reminders` as specified
> here, and read `PULSE.md` before touching `timeline_events` (already
> built, already has an `anniversary` event type) — this feature links to
> it, it does not replace it.

---

## TABLE OF CONTENTS

1. [Feature Overview](#1-feature-overview)
2. [Relationship to Timeline](#2-relationship-to-timeline)
3. [Family Members](#3-family-members)
4. [Reminder Delivery](#4-reminder-delivery)
5. [Navigation and Screens](#5-navigation-and-screens)
6. [Database Schema](#6-database-schema)
7. [Build Order](#7-build-order)
8. [Open Questions](#8-open-questions)

---

## 1. FEATURE OVERVIEW

A shared calendar for a couple: anniversaries, kids' birthdays, and any
other date either partner wants a reminder for, plus a note. Both partners
see and can manage every entry — there is no per-partner ownership. Yearly
dates repeat automatically; anything else is a one-off. A push notification
fires 3 days before and again on the day.

This is the manual-entry half of `ATTUNE_MASTER_SPEC.md` §8.3's reminders
bullet list. The weekly check-in reminder (also §8.3) is a separate,
already-built system (`send-checkin-reminders`) and is out of scope here —
this document only completes the `anniversary` / `birthday` /
`ai_generated`-adjacent manual-entry path. `ai_generated` reminders
(pattern-based nudges like "you haven't logged a highlight in 3 weeks") are
also out of scope for this document; they belong to whichever future spec
builds the pattern-nudge system, and are called out only so the
`reminder_type` enum's third value isn't mistaken for something this build
must implement.

## 2. Relationship to Timeline

`timeline_events` (built, `PULSE.md` §3/§8) already has an `anniversary`
event type and an `occurred_at` date — it is the couple's shared *memory
log* (what happened, with a mood score and a note), not a *future*
reminder system. `reminders` is the couple's *forward-looking* list (what's
coming up, so a notification can fire).

The two are linked, not merged: creating a `reminders` row with
`reminder_type = 'anniversary'` or `'birthday'` offers to also create a
matching `timeline_events` row (`event_type = 'anniversary'`,
`occurred_at` = the reminder's original date) — so the date the couple
cares about shows up both as "coming up" (reminders) and in their shared
history (timeline), without maintaining two independent dates by hand.
This link is one-directional and optional: declining it, or later editing
one side, never touches the other. `checkin` and `ai_generated` reminders
never create a timeline event — they aren't "moments," they're nudges.

`getEventsForMonth` (already implemented in `TimelineRepository`) is the
existing hook the calendar screen (§5) reuses to show timeline anniversaries
alongside upcoming reminders in one view, rather than the new screen
re-implementing month-range querying against `timeline_events` itself.

## 3. Family Members

Not in the master spec — a genuine addition this document introduces, to
answer "whose birthday is this" without repeating a name-plus-date pair
by hand every year and re-typing it into a fresh `reminders` row.

A small, couple-shared, reusable list: name, optional birthday. Adding a
family member with a birthday auto-creates a linked `reminders` row
(`reminder_type = 'birthday'`, `recurrence = 'yearly'`, title `"<name>'s
birthday"`) in the same transaction, so the couple never enters the same
date twice. Editing the birthday updates the linked reminder's date in the
same transaction. Deleting the family member does not delete the reminder
— it detaches (`family_member_id` set `NULL`) and the reminder stands on
its own, since the couple may have since customized its title or kept
wanting the nudge after tidying up the person record.

A family member exists to be *tagged*, not to carry its own permissions or
visibility rules — both partners can add, edit, or remove any family
member, matching the fully-shared model for the rest of this feature.

## 4. Reminder Delivery

No new delivery infrastructure. Reuses `scheduled_notifications` and its
existing `process-scheduled-notifications` cron/OneSignal pipeline
unmodified — the same pattern the dating-mode match notification and every
other one-shot notification in this codebase already uses.

A new daily cron (`schedule_generate_reminder_notifications.sql`, same
shape as the existing `schedule_process_scheduled_notifications.sql`,
07:00 UTC) calls a new RPC, `generate_reminder_notifications()`:

1. For every `reminders` row with `sent = false` (one-off) or
   `recurrence = 'yearly'` (repeating — `sent` is meaningless for these,
   see schema note below), compute its next occurrence date: for
   `recurrence = 'yearly'`, today's or next year's month/day match via
   `make_date`, never string/month-day comparison, so a Dec 31 reminder's
   3-day-before notification correctly lands on Jan 3 across the year
   boundary. For `recurrence = 'none'`, the next occurrence is `remind_at`
   itself.
2. A row is due if its next-occurrence date is **today** or **today + 3
   days**. For each due row, insert one `scheduled_notifications` row per
   partner in the relationship (`user_id = user_a`, then `user_id =
   user_b`), `notification_type = 'reminder_upcoming'`, `scheduled_for =
   now()`, `metadata = {reminder_id, title, days_until: 0 or 3}`.
3. Idempotency via `source_key = 'reminder:' || reminder.id || ':' ||
   target_date || ':' || user_id` with `ON CONFLICT (source_key) WHERE
   source_key IS NOT NULL DO NOTHING` — a cron re-run the same day never
   double-sends, same pattern as the dating-mode match notification.
4. A one-off reminder (`recurrence = 'none'`) is marked `sent = true` once
   its day-of notification has been generated, so it drops out of future
   cron scans. A yearly reminder is never marked `sent` — `sent` on a
   recurring row has no meaning and the schema note in §6 says so
   explicitly, so a future reader doesn't "fix" it into firing once.

Per §8.3, notification style stays single-notification, never a barrage —
the 3-day and day-of pushes are the only two per event per year; no
escalating reminder cadence.

## 5. Navigation and Screens

Entry point: a "Calendar" tile from wherever the couple's shared-features
hub already lives (Timeline's own entry point is the closest sibling —
place this alongside it; exact hub screen confirmed by reading
`app_router.dart`'s existing couples-feature routes at implementation
time, not assumed here).

- **Calendar screen** — a single sorted upcoming list (soonest first,
  recurring reminders shown at their next occurrence), each row showing
  title, relative countdown ("in 3 days"), and a small icon distinguishing
  recurring vs one-off. Not a month/week grid in v1 — a grid is listed as
  an open question (§8), not built now.
- **Add/edit reminder sheet** — title, date, recurrence toggle
  (none/yearly), optional note, optional family-member tag (offered only
  when `reminder_type` is `birthday`).
- **Family members screen** — add/edit name + birthday; adding a birthday
  offers the auto-linked reminder per §3.

Follows the Timeline feature's file layout as the closest existing
precedent for a couples-shared, both-edit feature in this codebase:
`lib/features/reminders/data/{repositories,models}`,
`lib/features/reminders/presentation/{screens,providers}`.

## 6. Database Schema

```sql
-- Reminders (completes ATTUNE_MASTER_SPEC.md §4.1 — unmigrated until now)
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
  -- Only 'none' rows use this flag meaningfully — see §4 step 4. This
  -- codebase's v1 only generates 'none' and 'yearly' rows via UI; 'weekly'
  -- and 'monthly' are accepted by the CHECK (master spec's original enum)
  -- but §4's generator RPC does not implement their occurrence math and
  -- must reject them at write time until a future version adds it.
  sent boolean NOT NULL DEFAULT false,
  family_member_id uuid REFERENCES public.couple_family_members(id) ON DELETE SET NULL,
  linked_timeline_event_id uuid REFERENCES public.timeline_events(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Family members (new — not in the master spec; see §3)
CREATE TABLE IF NOT EXISTS public.couple_family_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(name) <= 80),
  birthday date,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

`reminders.family_member_id` forward-references a table defined below it
in this document for readability; the migration must create
`couple_family_members` first, or add the FK via `ALTER TABLE` after both
tables exist (`ATTUNE_MASTER_SPEC.md` §4.3 rule 8 — cross-table FKs added
at the end of the migration, not inline, when creation order would
otherwise force a forward reference).

### RLS policies

Deliberate departure from `timeline_events`' owner-only UPDATE/DELETE
(`PULSE.md` §8): both `reminders` and `couple_family_members` are fully
shared, matching this document's decision that either partner can edit or
delete any entry (§1) — a calendar is a shared plan, not a personal log
entry, and a family member is a shared fact, not one partner's private
note. This is a deliberate divergence from the Timeline precedent, not an
oversight; call it out if a future reviewer expects Timeline's owner-only
pattern to apply here too.

```sql
CREATE POLICY reminders_select_members ON public.reminders
FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.relationships r
  WHERE r.id = reminders.relationship_id
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
));

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

CREATE POLICY reminders_update_members ON public.reminders
FOR UPDATE TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.relationships r
  WHERE r.id = reminders.relationship_id
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
));

CREATE POLICY reminders_delete_members ON public.reminders
FOR DELETE TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.relationships r
  WHERE r.id = reminders.relationship_id
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
));
```

`couple_family_members` gets the identical four-policy shape, substituting
its own table name. Both tables require `status = 'active'` on INSERT only
(mirrors `messages`, `PULSE.md`'s `timeline_events`) — a paused/ended
relationship can still view its calendar but not add to it.

### Indexes

```sql
CREATE INDEX idx_reminders_relationship_remind_at
  ON public.reminders(relationship_id, remind_at);
-- Daily generator scan: only non-terminal one-off rows plus all yearly rows
CREATE INDEX idx_reminders_pending_scan
  ON public.reminders(relationship_id, recurrence, remind_at)
  WHERE sent = false;
CREATE INDEX idx_family_members_relationship
  ON public.couple_family_members(relationship_id);
```

## 7. Build Order

1. Migration: `couple_family_members`, `reminders` (with the
   `linked_timeline_event_id` FK added after `timeline_events` — already
   exists — and `family_member_id` added after `couple_family_members` per
   the ordering note in §6), RLS, indexes.
2. `upsert_family_member(...)` RPC — single-transaction family-member
   create/edit plus its linked reminder create/update (§3).
3. `generate_reminder_notifications()` RPC plus its daily `pg_cron`
   schedule (§4) — reuses `scheduled_notifications`/OneSignal delivery
   unmodified; no new edge function needed for delivery.
4. Flutter data layer: `RemindersRepository`, `ReminderModel`,
   `FamilyMemberModel`, Riverpod providers — file layout per §5.
5. Screens: Calendar (§5), add/edit reminder sheet, family members screen,
   route registration, hub entry point.
6. Timeline link: reminders' add/edit sheet offers the optional linked
   `timeline_events` row per §2; the Calendar screen's month view calls
   `TimelineRepository.getEventsForMonth` to blend in timeline
   anniversaries alongside upcoming reminders.

## 8. Open Questions

- **Month/week grid view.** v1 ships as a sorted list (§5). Whether a real
  calendar grid is worth building later is deferred — no data yet on
  whether couples want it or the list view is sufficient.
- **`weekly`/`monthly` recurrence.** The master spec's original enum
  includes them; this document's generator RPC does not implement their
  occurrence math (§6 schema note) and rejects them at write time. Revisit
  if a real use case surfaces beyond the two named ones (anniversaries,
  birthdays) this feature was scoped for.
- **Notification copy for `days_until: 3` vs `days_until: 0`.** Exact push
  copy (e.g. "Emma's birthday is in 3 days" vs "Today is Emma's birthday")
  is a copywriting detail for the implementation plan, not locked here.
