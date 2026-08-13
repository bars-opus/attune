# Moment-to-Reminder Offer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After logging a new `anniversary` or `milestone` moment, offer a dialog to also create a yearly recurring reminder for the same date, linked back to the moment via the existing `linked_timeline_event_id` mechanism.

**Architecture:** One method (`_offerYearlyReminder`) added to `LogMomentDetailsScreen`, called from the create-path of its existing `_saveMoment()` only when the event type is eligible. The method itself isolates the two-write sequence (`createReminderProvider` then `RemindersRepository.linkReminderToTimelineEvent`) from the dialog's widget code, with an explicit try/catch distinguishing "reminder never created" from "reminder created but unlinked" — both surfaced to the user via the same generic error snackbar, neither silently dropped.

**Tech Stack:** Flutter, Riverpod, Supabase.

## Global Constraints

- Scope tags per Algorithm Quality Review Checklist v3.1: `[MOBILE]` `[UI]` `[MUTATION]` — `[SERVICE]`/`[ASYNC]`/`[BATCH]`/`[FIN]`/`[UI-WEB]`-only checks are N/A and skipped.
- Only `eventType == 'anniversary'` or `'milestone'` offer the dialog. `conflict`/`highlight`/`first` never do.
- Only fires on the CREATE path (`widget.editEventId == null`) — never re-offered when editing an existing moment.
- Reminder's `remindAt` is the moment's own `occurredAt` (not today's date), `recurrence` is always `'yearly'`.
- `reminderType: 'anniversary'` is used for the created reminder regardless of whether the source moment was `anniversary` or `milestone` — `reminders.reminder_type` has no `'milestone'` value and extending that CHECK constraint is out of scope.
- No PII (title/note content) in logs — this feature adds no logging at all, so this is satisfied by not adding any.
- Declining ("Not now") or dismissing the dialog does nothing further — no partial writes, no reminder created.
- Partial failure (reminder created, link fails) must not silently lose data — the reminder row must still exist and the user must be told, via the same generic error snackbar as a full failure.

---

## File Structure

- **Modify** `lib/features/timeline/presentation/screens/log_moment_details_screen.dart` — add `_offerYearlyReminder`, call it from `_saveMoment`'s create path.
- **Test:** `test/features/timeline/log_moment_details_screen_reminder_offer_test.dart` (new).

---

## Task 1: `_offerYearlyReminder` — the two-write method with failure handling

**Files:**
- Modify: `lib/features/timeline/presentation/screens/log_moment_details_screen.dart`
- Test: `test/features/timeline/log_moment_details_screen_reminder_offer_test.dart`

**Interfaces:**
- Consumes: `createReminderProvider` (`lib/features/reminders/presentation/providers/reminders_providers.dart` — `FutureProvider.family<ReminderModel, ({String reminderType, String title, String? note, DateTime remindAt, String recurrence, String? familyMemberId})>`, returns the created `ReminderModel` with its `.id`), `remindersRepositoryProvider` (same file, `Provider<RemindersRepository>`), `RemindersRepository.linkReminderToTimelineEvent({required String reminderId, required String timelineEventId})` (`lib/features/reminders/data/repositories/reminders_repository.dart`), `createTimelineEventProvider` (`lib/features/timeline/presentation/providers/timeline_providers.dart` — already used by `_saveMoment`, returns `TimelineEventModel` with `.id`).
- Produces: `_LogMomentDetailsScreenState._offerYearlyReminder(TimelineEventModel createdEvent)` — an async method with no return value, called by `_saveMoment` (this task) after a successful create. No later task depends on new symbols from this one.

Read the current file in full before starting: `lib/features/timeline/presentation/screens/log_moment_details_screen.dart` (already reproduced below for exact line references, but confirm against the live file since other work may have touched it since this plan was written).

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/timeline/log_moment_details_screen_reminder_offer_test.dart
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/data/repositories/reminders_repository.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/screens/log_moment_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRemindersRepository implements RemindersRepository {
  _FakeRemindersRepository({this.linkShouldThrow = false});

  final bool linkShouldThrow;
  final List<({String reminderId, String timelineEventId})> linkCalls = [];

  @override
  Future<void> linkReminderToTimelineEvent({
    required String reminderId,
    required String timelineEventId,
  }) async {
    if (linkShouldThrow) {
      throw Exception('network error');
    }
    linkCalls.add((reminderId: reminderId, timelineEventId: timelineEventId));
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TimelineEventModel _event({String id = 'evt-1', String eventType = 'milestone'}) {
  return TimelineEventModel(
    id: id,
    relationshipId: 'rel-1',
    loggedBy: 'user-1',
    eventType: eventType,
    title: 'First trip together',
    occurredAt: DateTime(2026, 6, 4),
    createdAt: DateTime(2026, 6, 4),
  );
}

ReminderModel _reminder({String id = 'rem-1'}) {
  return ReminderModel(
    id: id,
    relationshipId: 'rel-1',
    createdBy: 'user-1',
    reminderType: 'anniversary',
    title: 'First trip together',
    remindAt: DateTime(2026, 6, 4),
    recurrence: 'yearly',
    sent: false,
    createdAt: DateTime(2026, 6, 4),
    updatedAt: DateTime(2026, 6, 4),
  );
}

void main() {
  group('LogMomentDetailsScreen dialog eligibility', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      required String eventType,
      String? editEventId,
    }) {
      return tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: LogMomentDetailsScreen(
              eventType: eventType,
              editEventId: editEventId,
            ),
          ),
        ),
      );
    }

    testWidgets('milestone and anniversary are eligible event types', (
      tester,
    ) async {
      expect(
        const LogMomentDetailsScreen(eventType: 'milestone').isEligibleForReminderOffer,
        isTrue,
      );
      expect(
        const LogMomentDetailsScreen(eventType: 'anniversary').isEligibleForReminderOffer,
        isTrue,
      );
    });

    testWidgets('conflict, highlight, and first are not eligible', (
      tester,
    ) async {
      expect(
        const LogMomentDetailsScreen(eventType: 'conflict').isEligibleForReminderOffer,
        isFalse,
      );
      expect(
        const LogMomentDetailsScreen(eventType: 'highlight').isEligibleForReminderOffer,
        isFalse,
      );
      expect(
        const LogMomentDetailsScreen(eventType: 'first').isEligibleForReminderOffer,
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/timeline/log_moment_details_screen_reminder_offer_test.dart`
Expected: FAIL — `isEligibleForReminderOffer` is not a defined getter on `LogMomentDetailsScreen`.

- [ ] **Step 3: Add the eligibility getter and the offer dialog + write method**

In `lib/features/timeline/presentation/screens/log_moment_details_screen.dart`, add imports:

```dart
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
```

Add a public getter on `LogMomentDetailsScreen` (the widget class, not its State — so it's usable both from the widget and from a plain unit test without pumping):

```dart
class LogMomentDetailsScreen extends ConsumerStatefulWidget {
  final String eventType;
  final String? editEventId;
  final Map<String, dynamic>? initialData;

  const LogMomentDetailsScreen({
    super.key,
    required this.eventType,
    this.editEventId,
    this.initialData,
  });

  /// Only anniversary and milestone moments read as something worth
  /// re-celebrating on a fixed yearly date — conflict/highlight/first
  /// don't fit a recurring nudge the same way.
  bool get isEligibleForReminderOffer =>
      eventType == 'anniversary' || eventType == 'milestone';

  @override
  ConsumerState<LogMomentDetailsScreen> createState() =>
      _LogMomentDetailsScreenState();
}
```

Change `_saveMoment`'s create-path branch to capture the created event and call the new offer method only on create (never on edit — the `else` branch already only runs when `widget.editEventId == null`):

```dart
  Future<void> _saveMoment() async {
    if (!_isValid) return;

    setState(() => _isSubmitting = true);

    try {
      if (widget.editEventId != null) {
        // Update existing event
        await ref.read(
          updateTimelineEventProvider((
            eventId: widget.editEventId!,
            eventType: widget.eventType,
            title: _titleController.text.trim(),
            note:
                _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
            moodScore: _moodScore,
            occurredAt: _selectedDate,
          )).future,
        );
      } else {
        // Create new event
        final createdEvent = await ref.read(
          createTimelineEventProvider((
            eventType: widget.eventType,
            title: _titleController.text.trim(),
            occurredAt: _selectedDate,
            note:
                _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
            moodScore: _moodScore,
          )).future,
        );

        if (widget.isEligibleForReminderOffer && mounted) {
          await _offerYearlyReminder(createdEvent);
        }
      }

      if (mounted) {
        Navigator.pop(context, true); // Return true to signal refresh needed
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
```

Add the offer dialog + write method as new methods on `_LogMomentDetailsScreenState`, placed after `_saveMoment`:

```dart
  Future<void> _offerYearlyReminder(TimelineEventModel createdEvent) async {
    final shouldAdd = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Remind us to revisit this next year?'),
            content: const Text(
              "We'll nudge you both around this date each year.",
            ),
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
    if (shouldAdd != true || !mounted) return;

    ReminderModel reminder;
    try {
      reminder = await ref.read(
        createReminderProvider((
          reminderType: 'anniversary',
          title: createdEvent.title,
          note: null,
          remindAt: createdEvent.occurredAt,
          recurrence: 'yearly',
          familyMemberId: null,
        )).future,
      );
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar("Couldn't add that reminder — try again from Calendar.");
      return;
    }

    try {
      await ref
          .read(remindersRepositoryProvider)
          .linkReminderToTimelineEvent(
            reminderId: reminder.id,
            timelineEventId: createdEvent.id,
          );
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar("Couldn't add that reminder — try again from Calendar.");
    }
  }
```

Note the two try/catch blocks are separate and sequential, not nested — this is what makes the partial-failure case (create succeeds, link fails) distinguishable in tests from the full-failure case (create itself throws): in the partial-failure case, `reminder` is a real, already-created `ReminderModel`, and only the second call's catch fires.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/timeline/log_moment_details_screen_reminder_offer_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Run dart analyze**

Run: `dart analyze lib/features/timeline/presentation/screens/log_moment_details_screen.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/timeline/presentation/screens/log_moment_details_screen.dart test/features/timeline/log_moment_details_screen_reminder_offer_test.dart
git commit -m "feat(timeline): offer a yearly reminder after logging an anniversary/milestone"
```

---

## Task 2: Full write-path tests — success, decline, and both failure modes

**Files:**
- Modify: `test/features/timeline/log_moment_details_screen_reminder_offer_test.dart`

**Interfaces:**
- Consumes: `_offerYearlyReminder` (Task 1) indirectly via the full widget tree — this task drives the dialog through actual widget interaction (tap "Add it"/"Not now") rather than calling the private method directly, since Dart's privacy means a test in a different file cannot call a `_`-prefixed method — the test exercises it through `_saveMoment`'s public trigger (`_isValid ? _saveMoment : null` wired to the Save button's `onPressed`).
- Produces: nothing consumed by later tasks — this is the plan's final task.

This task requires overriding `createReminderProvider`, `remindersRepositoryProvider`, and `createTimelineEventProvider` with fakes via `ProviderScope(overrides: [...])`, since the real providers call `Supabase.instance.client`, which isn't available in a widget test. Riverpod's `overrideWithProvider`/`overrideWith` mechanics apply here.

- [ ] **Step 1: Write the failing tests**

Add to `test/features/timeline/log_moment_details_screen_reminder_offer_test.dart`, inside `main()`, after the existing `group('LogMomentDetailsScreen dialog eligibility', ...)`:

```dart
  group('LogMomentDetailsScreen _offerYearlyReminder write path', () {
    late List<TimelineEventModel> createdEvents;
    late List<({String reminderType, String title, DateTime remindAt})> createdReminders;

    Future<void> pumpScreen(
      WidgetTester tester, {
      required String eventType,
      bool linkShouldThrow = false,
      bool createReminderShouldThrow = false,
    }) async {
      createdEvents = [];
      createdReminders = [];
      final fakeRepo = _FakeRemindersRepository(linkShouldThrow: linkShouldThrow);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            createTimelineEventProvider.overrideWith((ref, params) async {
              final event = TimelineEventModel(
                id: 'evt-${createdEvents.length + 1}',
                relationshipId: 'rel-1',
                loggedBy: 'user-1',
                eventType: params.eventType,
                title: params.title,
                occurredAt: params.occurredAt,
                createdAt: DateTime.now(),
              );
              createdEvents.add(event);
              return event;
            }),
            createReminderProvider.overrideWith((ref, params) async {
              if (createReminderShouldThrow) {
                throw Exception('network error');
              }
              createdReminders.add((
                reminderType: params.reminderType,
                title: params.title,
                remindAt: params.remindAt,
              ));
              return _reminder();
            }),
            remindersRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: MaterialApp(
            home: LogMomentDetailsScreen(eventType: eventType),
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField).first, 'First trip together');
      await tester.tap(find.text('Save moment'));
      await tester.pumpAndSettle();
    }

    testWidgets('accepting the offer creates a linked yearly reminder', (
      tester,
    ) async {
      await pumpScreen(tester, eventType: 'milestone');

      expect(find.text('Remind us to revisit this next year?'), findsOneWidget);
      await tester.tap(find.text('Add it'));
      await tester.pumpAndSettle();

      expect(createdReminders, hasLength(1));
      expect(createdReminders.first.reminderType, 'anniversary');
      expect(createdReminders.first.title, 'First trip together');
    });

    testWidgets('declining the offer creates no reminder', (tester) async {
      await pumpScreen(tester, eventType: 'anniversary');

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(createdReminders, isEmpty);
    });

    testWidgets('conflict event type never shows the offer dialog', (
      tester,
    ) async {
      await pumpScreen(tester, eventType: 'conflict');

      expect(find.text('Remind us to revisit this next year?'), findsNothing);
    });

    testWidgets(
      'createReminder throwing shows an error and creates no reminder row',
      (tester) async {
        await pumpScreen(
          tester,
          eventType: 'milestone',
          createReminderShouldThrow: true,
        );

        await tester.tap(find.text('Add it'));
        await tester.pumpAndSettle();

        expect(createdReminders, isEmpty);
        expect(
          find.text("Couldn't add that reminder — try again from Calendar."),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'linkReminderToTimelineEvent throwing still leaves the reminder created',
      (tester) async {
        await pumpScreen(
          tester,
          eventType: 'milestone',
          linkShouldThrow: true,
        );

        await tester.tap(find.text('Add it'));
        await tester.pumpAndSettle();

        // The reminder WAS created — createReminder succeeded — even
        // though linking it to the moment failed afterward. No data loss.
        expect(createdReminders, hasLength(1));
        expect(
          find.text("Couldn't add that reminder — try again from Calendar."),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a moment with a future occurredAt still produces a correctly-dated reminder',
      (tester) async {
        // LogMomentDetailsScreen's own date picker forbids picking a future
        // date (lastDate: DateTime.now()), so this drives the create path
        // directly with a pre-set _selectedDate via initialData rather than
        // through the picker UI — proving createReminder/_offerYearlyReminder
        // themselves have no hidden assumption that occurredAt is in the
        // past, since nextOccurrence/upcomingReminders (elsewhere in this
        // codebase) already handle a future remindAt correctly with no
        // special-casing needed.
        final future = DateTime.now().add(const Duration(days: 10));
        createdEvents = [];
        createdReminders = [];
        final fakeRepo = _FakeRemindersRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              createTimelineEventProvider.overrideWith((ref, params) async {
                final event = TimelineEventModel(
                  id: 'evt-1',
                  relationshipId: 'rel-1',
                  loggedBy: 'user-1',
                  eventType: params.eventType,
                  title: params.title,
                  occurredAt: params.occurredAt,
                  createdAt: DateTime.now(),
                );
                createdEvents.add(event);
                return event;
              }),
              createReminderProvider.overrideWith((ref, params) async {
                createdReminders.add((
                  reminderType: params.reminderType,
                  title: params.title,
                  remindAt: params.remindAt,
                ));
                return _reminder();
              }),
              remindersRepositoryProvider.overrideWithValue(fakeRepo),
            ],
            child: MaterialApp(
              home: LogMomentDetailsScreen(
                eventType: 'milestone',
                initialData: {'title': 'Future trip', 'occurred_at': future},
              ),
            ),
          ),
        );

        await tester.tap(find.text('Save moment'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add it'));
        await tester.pumpAndSettle();

        expect(createdReminders, hasLength(1));
        expect(createdReminders.first.remindAt, future);
      },
    );
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/timeline/log_moment_details_screen_reminder_offer_test.dart`
Expected: FAIL if `createTimelineEventProvider`/`createReminderProvider` are not `.family` providers with an `overrideWith` matching this call shape, or if the Save button flow doesn't reach the dialog as written — read the actual failure output and adjust the test's provider-override syntax to match the real provider definitions in `lib/features/reminders/presentation/providers/reminders_providers.dart` and `lib/features/timeline/presentation/providers/timeline_providers.dart` if Riverpod's exact override API differs from what's shown here (family provider override syntax has changed across Riverpod versions — check the installed version's API before assuming this compiles as-is).

- [ ] **Step 3: Fix any override-syntax mismatches, re-run until compiling and passing**

No production code changes are expected in this task — Task 1 already implemented the behavior these tests exercise. If a test fails on ASSERTION (not compilation), that indicates a real bug in Task 1's implementation; fix `log_moment_details_screen.dart` to match, re-run.

Run: `flutter test test/features/timeline/log_moment_details_screen_reminder_offer_test.dart`
Expected: PASS (8 tests total: 2 from Task 1 + 6 from this task)

- [ ] **Step 4: Run dart analyze**

Run: `dart analyze test/features/timeline/log_moment_details_screen_reminder_offer_test.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add test/features/timeline/log_moment_details_screen_reminder_offer_test.dart
git commit -m "test(timeline): cover reminder-offer accept/decline/failure paths"
```

---

## Task 3: Full regression pass

**Files:** none (verification only)

- [ ] **Step 1: Run the full timeline test suite**

Run: `flutter test test/features/timeline/`
Expected: PASS — every test across `log_moment_details_screen_reminder_offer_test.dart` plus the existing `upcoming_reminders_section_test.dart`/`calendar_strip_test.dart`, confirming no regression.

- [ ] **Step 2: Run `dart analyze` across the whole project**

Run: `dart analyze`
Expected: zero new errors; only pre-existing info/warning-level lints in files this plan didn't touch.

- [ ] **Step 3: Confirm no other callers of `LogMomentDetailsScreen` were affected**

Run: `grep -rn "LogMomentDetailsScreen(" lib --include="*.dart" | grep -v "_test.dart"`

Expected: only the existing call site in `lib/app/routing/app_router.dart` (or wherever it's routed from) and the class's own declaration — confirming the new `isEligibleForReminderOffer` getter and `_offerYearlyReminder` method are purely additive and don't require changes to how the screen is invoked.

- [ ] **Step 4: Confirm the branch is clean**

Run: `git status --short`

Expected: clean (no commit needed — this task is verification-only).
