import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/data/repositories/reminders_repository.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/screens/log_moment_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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

  group('LogMomentDetailsScreen _offerYearlyReminder write path', () {
    late List<TimelineEventModel> createdEvents;
    late List<({String reminderType, String title, DateTime remindAt, String recurrence})>
    createdReminders;
    late _FakeRemindersRepository fakeRepo;

    Future<void> pumpScreen(
      WidgetTester tester, {
      required String eventType,
      bool linkShouldThrow = false,
      bool createReminderShouldThrow = false,
    }) async {
      createdEvents = [];
      createdReminders = [];
      fakeRepo = _FakeRemindersRepository(linkShouldThrow: linkShouldThrow);

      // The Save button sits below the fold at the default 800x600 test
      // viewport, so a plain tap misses it. Widen the view instead of
      // scrolling to avoid animated-scroll timing flakiness.
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
                recurrence: params.recurrence,
              ));
              return _reminder();
            }),
            remindersRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: MaterialApp(
            home: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, __) => LogMomentDetailsScreen(eventType: eventType),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'First trip together');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save moment'));
      // Not pumpAndSettle here: AppButton's isLoading spinner
      // (CircularProgressIndicator) animates indefinitely for as long as
      // _isSubmitting is true, which spans the entire time the yearly-
      // reminder dialog is up awaiting a user choice — pumpAndSettle would
      // never converge until that choice is made. A few explicit pumps is
      // enough to flush the create-event future and the dialog's own
      // entrance animation.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
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
      expect(createdReminders.first.recurrence, 'yearly');

      expect(fakeRepo.linkCalls, hasLength(1));
      expect(fakeRepo.linkCalls.first.reminderId, _reminder().id);
      expect(
        fakeRepo.linkCalls.first.timelineEventId,
        createdEvents.first.id,
      );
    });

    testWidgets(
      'edit path never shows the offer dialog, even for an eligible event type',
      (tester) async {
        createdEvents = [];
        createdReminders = [];
        fakeRepo = _FakeRemindersRepository();

        tester.view.physicalSize = const Size(1200, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              updateTimelineEventProvider.overrideWith((ref, params) async {
                return TimelineEventModel(
                  id: params.eventId,
                  relationshipId: 'rel-1',
                  loggedBy: 'user-1',
                  eventType: params.eventType ?? 'milestone',
                  title: params.title ?? '',
                  occurredAt: params.occurredAt ?? DateTime.now(),
                  createdAt: DateTime.now(),
                );
              }),
              createReminderProvider.overrideWith((ref, params) async {
                createdReminders.add((
                  reminderType: params.reminderType,
                  title: params.title,
                  remindAt: params.remindAt,
                  recurrence: params.recurrence,
                ));
                return _reminder();
              }),
              remindersRepositoryProvider.overrideWithValue(fakeRepo),
            ],
            child: MaterialApp(
              home: ScreenUtilInit(
                designSize: const Size(390, 844),
                builder:
                    (_, __) => const LogMomentDetailsScreen(
                      eventType: 'milestone',
                      editEventId: 'evt-existing',
                    ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextFormField).first,
          'Updated title',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();

        expect(
          find.text('Remind us to revisit this next year?'),
          findsNothing,
        );
        expect(createdReminders, isEmpty);
      },
    );

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

        // Not pumpAndSettle: after the reminder step fails, _saveMoment
        // still pops the screen (the timeline event itself was created
        // successfully — only the reminder failed). In this test harness
        // there's no route below `home` to land back on, so pumpAndSettle
        // would ride that pop out to an empty tree before we get to look at
        // the SnackBar it briefly carried. Pump a couple of frames instead
        // and assert while it's still up.
        await tester.tap(find.text('Add it'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

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

        // See the comment in the createReminder-throws test above: the
        // screen pops right after the reminder step resolves (success or
        // handled failure), which would otherwise carry the SnackBar's
        // assertion window away under pumpAndSettle.
        await tester.tap(find.text('Add it'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

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

        tester.view.physicalSize = const Size(1200, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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
                  recurrence: params.recurrence,
                ));
                return _reminder();
              }),
              remindersRepositoryProvider.overrideWithValue(fakeRepo),
            ],
            child: MaterialApp(
              home: ScreenUtilInit(
                designSize: const Size(390, 844),
                builder:
                    (_, __) => LogMomentDetailsScreen(
                      eventType: 'milestone',
                      initialData: {'title': 'Future trip', 'occurred_at': future},
                    ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save moment'));
        // See pumpScreen's comment above: pumpAndSettle can't converge
        // while the Save button's spinner is active during the dialog's
        // await, so pump explicitly instead.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Add it'));
        await tester.pumpAndSettle();

        expect(createdReminders, hasLength(1));
        expect(createdReminders.first.remindAt, future);
      },
    );
  });
}
