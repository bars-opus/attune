# Timeline + Reminders/Calendar Merge — Design

Date: 2026-08-28

## Problem

Timeline (`PULSE.md` §3, built) and Reminders/Calendar (`REMINDERS.md`,
built) are two separate screens today — `TimelineScreen` (a calendar strip
+ a vertical log of past moments) and `CouplesCalendarScreen` (a two-tab
screen: an "Upcoming" list of future reminders, and a `TableCalendar`
month-grid). `CouplesCalendarScreen` already reads Timeline data
(`timelineAnniversariesThisMonthProvider`, `timelineEventsProvider`) to
blend anniversaries into its own list and month view, and `REMINDERS.md`
§2 explicitly frames the two features as "linked, not merged" — a
`reminders` row can optionally create a matching `timeline_events` row,
one-directionally.

That data-level link never surfaced as one screen for the user: reaching
"what's coming up" and "what already happened" still means navigating to
two different places. This spec merges them into one screen and one feed,
without touching the underlying data split, which stays real and
load-bearing (see below).

## What does not change

- **Data model.** `reminders` / `couple_family_members` (upcoming,
  recurring, drives push notifications) and `timeline_events` (past,
  mood-scored, feeds the Pulse Score algorithm) stay two separate tables.
  `REMINDERS.md` §6 already documents why their RLS differs — Calendar is
  fully-shared edit, Timeline is owner-only edit — and that divergence is
  a deliberate product decision, not something this merge revisits.
- **Add flows.** `LogMomentTypeScreen` → `LogMomentDetailsScreen` (moment
  logging) and `AddEditReminderScreen` (reminder add/edit) are reused
  exactly as they exist today — only their entry point changes (see
  below). `FamilyMembersScreen` is reused unchanged.
- **Repositories/providers.** `TimelineRepository`/`timeline_providers.dart`
  and `RemindersRepository`/`reminders_providers.dart` both stay. The merged
  screen watches both; neither is rewritten.

## What changes

### One screen, one feed

`TimelineScreen` becomes the single destination for both past moments and
upcoming reminders. Layout:

```
TimelineScreen
├── Calendar strip (top, existing CalendarStrip widget, extended)
│   ● dots = logged moments (existing 5 event-type colors, unchanged)
│   ○ dots = upcoming reminders (new — a distinct marker style so the two
│     categories stay visually distinguishable at a glance)
├── Upcoming section (new — soonest occurrence first)
│   Reused row styling from CouplesCalendarScreen._buildList's reminder
│   rows: title, countdown label ("Today" / "Tomorrow" / "In N days"),
│   recurring-vs-one-off icon.
└── Timeline section (existing, unchanged — newest-first moment cards)
```

Ordering is section-based, not one strict date sort: Upcoming (soonest
first) always renders above Timeline (newest-first), rather than
interleaving future and past items into a single chronological list. This
keeps "what's coming up" glanceable without mixing tenses in one scan.

### Calendar strip tap behavior

- Tapping a **future** date with a reminder scrolls to that reminder's row
  in the Upcoming section.
- Tapping a **past** date with a moment scrolls to that moment's card in
  the Timeline section (existing behavior, unchanged).
- A date with both an upcoming reminder's projected occurrence and a
  logged moment (rare, but possible for a recurring anniversary reminder
  whose original creation also logged a Timeline event) scrolls to
  whichever section the date's dot color indicates was tapped; if both
  dot colors are present on one day, prefer scrolling to Upcoming — it's
  the rarer/more time-sensitive of the two categories to lose track of.

### De-duplication: reminder ↔ linked timeline event

A reminder created via `AddEditReminderScreen`'s "Add to Timeline too?"
flow produces two rows for one real-world event — a `reminders` row and a
linked `timeline_events` row (`reminders.linked_timeline_event_id`). This
already caused double-counting in `CalendarMonthView`
(`calendar_month_view.dart`'s `linkedTimelineEventIds` set), which is
where the fix currently lives. That widget is being dropped (see below),
so the same dedup logic moves into the merged feed's Upcoming-section
builder:

```dart
// Timeline events whose creation already produced a reminder for the same
// real-world date are represented ONCE, in Upcoming — showing them again
// in the Timeline section's past-moments log would double-count the
// event, exactly as CalendarMonthView's linkedTimelineEventIds already
// guards against for the month-grid view this replaces.
final linkedTimelineEventIds = reminders
    .map((r) => r.linkedTimelineEventId)
    .whereType<String>()
    .toSet();
```

This only suppresses an event from double-appearing while its *reminder*
is still upcoming/unexpired-recurring. A past occurrence of a yearly
reminder (e.g. last year's already-happened anniversary, now logged as a
`timeline_events` row) is not suppressed — it's a genuine past moment and
belongs in the Timeline section like any other.

### FAB: one button, choice sheet

Timeline's existing single FAB (`Icons.add` → `logMomentType` route)
becomes a FAB that opens a small bottom sheet with two choices:

```
┌─────────────────────────┐
│  Log a moment            │
│  A milestone, conflict,  │
│  highlight...             │
├─────────────────────────┤
│  Add a reminder           │
│  Anniversary, birthday,  │
│  or any date              │
└─────────────────────────┘
```

- "Log a moment" → pushes `logMomentType` exactly as today.
- "Add a reminder" → opens `AddEditReminderScreen` exactly as
  `CouplesCalendarScreen`'s FAB does today (via
  `BottomSheetUtils.showDocumentationBottomSheet`).

No change to either destination screen — only the launch point moves from
two separate FABs on two separate screens to one FAB with a choice on one
screen.

### AppBar

`TimelineScreen`'s AppBar gains a Family-members icon
(`Icons.people_outline` → `familyMembers` route), matching
`CouplesCalendarScreen`'s existing icon exactly. The "Docs" icon
(`Icons.notes_rounded`, opens `HealingDocs` documentation) does not carry
over — it was calendar-specific documentation content, not something
Timeline's merged scope needs; if a documentation entry point is still
wanted post-merge, that's a separate, smaller follow-up, not part of this
spec.

### What gets retired

- **`CouplesCalendarScreen`** (`lib/features/reminders/presentation/screens/couples_calendar_screen.dart`)
  — deleted. Its two tabs' content (Upcoming list, month grid) are
  absorbed into `TimelineScreen` (Upcoming section) and dropped (month
  grid) respectively.
- **`CalendarMonthView`** (`lib/features/reminders/presentation/screens/calendar_month_view.dart`)
  — deleted. Its dedup logic (`linkedTimelineEventIds`) is preserved by
  moving into the merged feed's Upcoming-section builder, per above.
  `TableCalendar` remains a dependency only if something else in the app
  uses it — confirm at implementation time before removing the package
  dependency itself.
- **`/couplesCalendar` route** — removed from `app_router.dart`. Any
  remaining reference (e.g. `PulseTab`, `familyMembers`'s back-navigation
  assumptions) is repointed to `/timeline`.
- **Docs icon / `HealingDocs` reference** inside the calendar screen —
  dropped along with the screen, per above.

### What is explicitly NOT part of this merge

- The underlying `reminders` / `couple_family_members` / `timeline_events`
  schema — untouched. This is a UI/screen consolidation, not a data
  migration.
- `REMINDERS.md` §6's RLS divergence (shared-edit Calendar vs owner-edit
  Timeline) — untouched; the merged screen still respects each table's own
  access rules per-row, it just displays rows from both in one place.
- `AddEditReminderScreen`, `LogMomentDetailsScreen`,
  `LogMomentTypeScreen`, `FamilyMembersScreen`,
  `FamilyMemberEditSheet` — all reused exactly as they exist today, only
  reached from a different launch point (the FAB choice sheet / AppBar
  icon on the merged screen instead of on `CouplesCalendarScreen`).
- Recurrence/notification logic (`generate_reminder_notifications()`,
  the daily cron) — entirely server-side and untouched by a client-side
  screen merge.

## Testing

- Existing flow-level behavior (logging a moment, adding/editing a
  reminder, adding a family member, the auto-linked-timeline-event offer)
  is unchanged — no new tests needed for those flows themselves.
- New: a test proving the merged feed's Upcoming section excludes a
  `timeline_events` row whose originating reminder is still
  upcoming/active (the ported `linkedTimelineEventIds` logic), so a
  linked anniversary does not appear twice in one screen load.
- New: a widget test confirming the calendar strip renders both dot styles
  (moment-color dots and the new upcoming-reminder dot) on the same
  strip without one overwriting the other when a date has both.
- Manual verification (no live device in a sandboxed dev environment):
  tapping a future dated cell scrolls to Upcoming; tapping a past dated
  cell scrolls to Timeline; the FAB choice sheet correctly launches each
  of the two existing flows unmodified.
