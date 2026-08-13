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

## Failure handling (two-step write)

`createReminder` then `linkReminderToTimelineEvent` are two independent
Supabase calls, not one DB transaction — so a network drop between them
can leave a reminder that exists but isn't linked to its originating
moment. This is handled explicitly, not left as a silent gap:

- Both calls happen inside the offer's own try/catch, isolated from
  `_saveMoment`'s own try/catch (the moment is already saved and the
  screen's overall success path must not be affected by what happens
  after — accepting the offer is best-effort on top of an already-
  successful save, matching `AddEditReminderScreen._offerTimelineLink`'s
  own fire-and-forget-with-catch shape).
- If `createReminder` itself throws: show
  `context.showErrorSnackbar("Couldn't add that reminder — try again from Calendar.")`
  (mirrors the generic, no-internal-detail error copy already used
  throughout this codebase, e.g. `ChatSettingsScreen._saveName`'s catch
  block) and stop — no orphaned row, nothing to link.
- If `createReminder` succeeds but `linkReminderToTimelineEvent` throws:
  the reminder still exists (correctly reachable/editable from Calendar
  on its own) but is unlinked from the moment — meaning the dedup logic
  won't suppress it and it'll appear as its own independent entry once
  upcoming. Show the same generic error snackbar (the two failure modes
  aren't worth distinguishing to the user — "try again from Calendar"
  covers both, since the user can always find and manage the reminder
  from there regardless of which step failed). This is a display
  inconvenience (a moment briefly duplicated across sections), not a
  data-loss bug — nothing is silently dropped, and the ledger the user
  can act on (delete/edit from Calendar) is unaffected.
- Both write calls, plus this error handling, live in one small
  extracted method (e.g. `_offerYearlyReminder`, mirroring
  `_offerTimelineLink`'s own naming) — kept separate from the dialog's
  own widget-building code, so the two-call sequence and its failure
  path are unit-testable without mounting the dialog.

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

## Algorithm Quality Review Checklist v3.1 — scoping and gate

Scope tags: `[MOBILE]` `[UI]` `[MUTATION]`. Not `[SERVICE]`/`[ASYNC]`/
`[BATCH]`/`[FIN]`/`[UI-WEB]` — no service/API of our own, no background
job or webhook, no money involved. `[SERVICE]`-only and CI/infra-level
checks (7.1–7.3, 7.5, 4.6–4.13, 3.x load/backpressure checks, 8.x
deployment checks) are N/A and skipped with that justification.

Checks that DO apply and how this spec satisfies them:

- **1.10 (P1) Compensating transaction for multi-step failure** — see
  "Failure handling" above: the two-step write's partial-failure case is
  explicitly defined (reminder exists but unlinked; user told, nothing
  silently lost).
- **1.11 (P1) Data privacy** — the only new data is the reminder's title
  (copied verbatim from the moment's own title, already user-entered and
  already stored) and its date. No new PII category introduced.
- **2.17 (P2) Side effects isolated** — the two-write sequence is one
  extracted method, testable independent of the dialog's widget tree.
- **4.4 (P0-U) No PII in logs** — the implementation must not log the
  moment/reminder title or note content; only non-PII identifiers
  (reminder id, event type) if any logging is added at all.
- **5.1/5.5 (P2/P0-U) Actionable, non-leaking error UI** — the generic
  snackbar copy in "Failure handling" contains no internal error detail,
  stack trace, or ID.
- **6.1 (P1) Edge cases** — covered in the test list below: ineligible
  event types, edit-path (no re-offer), decline, and a moment backdated
  or postdated relative to today.
- **6.4 (P1) Negative test** — "linkReminderToTimelineEvent failing still
  leaves the reminder created" is an explicit test below, proving no
  silent data loss on partial failure.

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
- A test confirming a moment logged with a future `occurredAt` (a
  postdated entry) still produces a correctly-linked yearly reminder —
  `nextOccurrence`/`upcomingReminders` already handle a future `remindAt`
  correctly with no special-casing needed, this test just proves it.
- A negative test: `createReminder` succeeds but
  `linkReminderToTimelineEvent` throws — assert the reminder row still
  exists (no rollback/deletion of the successful first write) and the
  error snackbar fires, proving the partial-failure path neither loses
  data nor fails silently.
- A test confirming `createReminder` itself throwing shows the error
  snackbar and creates no `reminders` row at all.
- Manual verification (no live device/backend in a sandboxed dev
  environment): logging a milestone, accepting the offer, and confirming
  the resulting reminder appears in Timeline's Upcoming section next time
  its yearly date falls within the 3-month window, without the linked
  moment re-appearing as a duplicate Timeline entry.
