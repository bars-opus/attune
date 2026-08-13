# Logging a Moment Offers a Yearly Reminder — Design

Date: 2026-08-13

## Problem

`reminders`/`couple_family_members` already offer a one-directional link
the other way: adding an `anniversary`-type reminder in
`AddEditReminderScreen` prompts "Add to your Timeline too?" and, if
accepted, logs a matching `timeline_events` row so the date the couple
cares about shows up both as "coming up" (reminders) and in their shared
memory log (timeline) — `REMINDERS.md` §2.

The reverse direction doesn't exist: logging a moment as `anniversary` or
`milestone` in Timeline has no path back to a recurring reminder to
re-celebrate it. A couple who logs "First trip together" as a milestone
today has no way to be nudged to revisit it next year unless they
separately, manually, add a calendar reminder for the same date.

## Scope

- **Which moment types offer this:** only `anniversary` and `milestone`.
  These are the two types that read as something worth re-celebrating on
  a fixed yearly date. `conflict`, `highlight`, and `first` are left
  alone — a logged "had a great dinner" highlight or a one-off "first"
  doesn't fit a recurring yearly nudge the way an anniversary or milestone
  does.
- **Opt-in, not automatic.** After saving an eligible moment, show a
  dialog offering to add a yearly reminder — mirroring
  `AddEditReminderScreen._offerTimelineLink`'s existing "Add to your
  Timeline too?" pattern in the reverse direction, not a silent
  auto-create. Declining, or later editing/deleting the moment, never
  touches the reminder (same one-directional, no-drift relationship the
  existing reverse link already establishes).
- **Reminder date basis:** the moment's own `occurredAt` date. A milestone
  logged with `occurredAt = 2026-06-04` offers a reminder that recurs
  every June 4th — the actual anniversary of the moment, not the date it
  was logged (which may differ, since `occurredAt` is user-editable and
  can be backdated).

## Flow

In `lib/features/timeline/presentation/screens/log_moment_details_screen.dart`,
after `_saveMoment()`'s create-path (`createTimelineEventProvider(...)`)
succeeds and only when `widget.eventType` is `'anniversary'` or
`'milestone'` and this is a NEW moment (not an edit —
`widget.editEventId == null`; editing an existing moment never re-offers
the reminder, since accepting once is a one-time decision, matching how
`AddEditReminderScreen`'s own offer only fires from its create path too):

```
┌─────────────────────────────────┐
│  Remind us to revisit this      │
│  next year?                     │
│                                  │
│  We'll nudge you both around    │
│  this date each year.           │
│                                  │
│       [Not now]   [Add it]      │
└─────────────────────────────────┘
```

Declining or dismissing does nothing further — the moment is already
saved, the screen pops exactly as it does today. Accepting creates a
`reminders` row:

```dart
await ref.read(
  createReminderProvider((
    reminderType: 'anniversary',   // reminders' own enum has no
                                    // 'milestone' value — anniversary is
                                    // the closest existing fit for
                                    // "recurring date worth marking,"
                                    // and matches what the reverse-
                                    // direction flow already writes
    title: <the moment's title>,
    note: null,
    remindAt: <the moment's occurredAt>,
    recurrence: 'yearly',
    familyMemberId: null,
  )).future,
);
```

then links it back to the just-created timeline event via the existing
`RemindersRepository.linkReminderToTimelineEvent(reminderId:,
timelineEventId:)` method (already used by `AddEditReminderScreen`'s own
offer flow) — so `reminders.linked_timeline_event_id` points at the
moment, and the existing `linkedTimelineEventIds`/dedup logic in
`upcoming_reminders_section.dart` (built for the reverse direction)
automatically prevents this moment from double-appearing once its
reminder becomes upcoming again next year. No new dedup code needed —
this flow produces exactly the same linked-pair shape the dedup logic
was already built to handle, just created from the opposite starting
point.

## Why `reminderType: 'anniversary'` for a `milestone` moment

`reminders.reminder_type` is constrained to
`'anniversary' | 'birthday' | 'checkin' | 'ai_generated'` — there's no
`'milestone'` value, and extending that CHECK constraint is out of scope
for this feature (a schema change belongs to a decision about the
reminder type taxonomy generally, not to wiring up one new offer dialog).
`'anniversary'` is the correct existing value for "something worth
marking on a recurring date," regardless of which Timeline event type
prompted its creation. The created reminder's own `title` still carries
the moment's actual title (e.g. "First trip together"), so the distinction
isn't lost to the user — only the `reminder_type` column, which was never
user-visible in the first place, collapses both source types to the one
existing bucket.

## What does not change

- `reminders`/`couple_family_members` and `timeline_events` stay two
  separate tables — this is a new creation path between them, not a
  schema change.
- `AddEditReminderScreen`'s own existing offer (reminder → timeline) is
  untouched; this is the independent reverse path (timeline → reminder),
  not a modification of the existing one.
- No new dedup logic — the existing `linkedTimelineEventIds` mechanism in
  `upcoming_reminders_section.dart` already handles a linked pair
  correctly regardless of which side created it first.
- `LogMomentTypeScreen` (the type-selection screen before details) is
  untouched — the offer only appears after `LogMomentDetailsScreen`'s
  save, not before.

## Testing

- A widget test confirming the dialog appears only for `eventType ==
  'anniversary'` or `'milestone'`, and not for `conflict`/`highlight`/`first`.
- A widget test confirming the dialog does NOT appear when
  `widget.editEventId != null` (editing an existing moment).
- A test confirming "Not now" pops the screen without creating a
  `reminders` row.
- A test confirming "Add it" creates a `reminders` row with
  `recurrence: 'yearly'`, `remindAt` equal to the moment's `occurredAt`,
  and `linked_timeline_event_id` pointing at the newly created moment.
- Manual verification (no live device/backend in a sandboxed dev
  environment): logging a milestone, accepting the offer, and confirming
  the resulting reminder appears in Timeline's Upcoming section next time
  its yearly date falls within the 3-month window, without the linked
  moment re-appearing as a duplicate Timeline entry.
