import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/data/repositories/reminders_repository.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart' show AppTextButton;
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/data/repositories/timeline_repository.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show timelineRepositoryProvider, currentUserIdProvider;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements RemindersRepository {
  final List<Map<String, Object?>> updates = [];
  final List<String> deleted = [];

  /// Failures still to come from updateReminder (one per call).
  int failUpdates = 0;

  @override
  Future<ReminderModel> updateReminder({
    required String id,
    String? reminderType,
    String? title,
    String? note,
    bool clearNote = false,
    DateTime? remindAt,
    String? recurrence,
    String? familyMemberId,
    List<int>? remindDaysBefore,
  }) async {
    if (failUpdates > 0) {
      failUpdates--;
      throw Exception('offline');
    }
    updates.add({
      'id': id,
      'reminderType': reminderType,
      'title': title,
      'note': note,
      'clearNote': clearNote,
      'remindAt': remindAt,
      'recurrence': recurrence,
      'remindDaysBefore': remindDaysBefore,
    });
    return _reminder(type: reminderType ?? 'anniversary');
  }

  @override
  Future<void> deleteReminder(String id) async => deleted.add(id);

  @override
  Future<List<ReminderModel>> listReminders(String relationshipId) async => [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReminderModel _reminder({String type = 'anniversary', String? linkedTo}) => ReminderModel(
  id: 'rem-1',
  relationshipId: 'rel-1',
  createdBy: 'user-1',
  reminderType: type,
  title: 'First date',
  note: 'Jollof place',
  remindAt: DateTime(2026, 11, 2),
  recurrence: 'yearly',
  sent: false,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  linkedTimelineEventId: linkedTo,
);

Future<void> _open(
  WidgetTester tester,
  _FakeRepo repo,
  ReminderModel? r, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(repo),
        currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
        ...overrides,
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => MaterialApp(
              home: Builder(
                builder:
                    (context) => TextButton(
                      onPressed:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder:
                                  (_) => AddEditReminderScreen(reminder: r),
                            ),
                          ),
                      child: const Text('open'),
                    ),
              ),
            ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens prefilled and saves edits, including a new type', (
    tester,
  ) async {
    final repo = _FakeRepo();
    await _open(tester, repo, _reminder());
    expect(find.text('Edit reminder'), findsOneWidget);
    expect(find.text('First date'), findsOneWidget);

    await tester.tap(find.text('Other'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.updates, hasLength(1));
    expect(repo.updates.single['id'], 'rem-1');
    expect(repo.updates.single['reminderType'], 'custom');
    expect(repo.updates.single['recurrence'], 'yearly');
    expect(repo.updates.single['remindAt'], DateTime(2026, 11, 2));
    expect(find.byType(AddEditReminderScreen), findsNothing, reason: 'closed');
  });

  testWidgets('delete asks first, then deletes', (tester) async {
    final repo = _FakeRepo();
    await _open(tester, repo, _reminder());
    await tester.scrollUntilVisible(
      find.text('Delete reminder'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Delete reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repo.deleted, ['rem-1']);
    expect(find.byType(AddEditReminderScreen), findsNothing);
  });

  testWidgets('a type the picker does not offer still opens (shown as Other)', (
    tester,
  ) async {
    final repo = _FakeRepo();
    await _open(tester, repo, _reminder(type: 'checkin'));
    expect(tester.takeException(), isNull);
    expect(find.text('Edit reminder'), findsOneWidget);
  });

  testWidgets('after saving, "Saved." shows on the screen behind the sheet', (
    tester,
  ) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remindersRepositoryProvider.overrideWithValue(repo),
          currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
        ],
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder:
              (_, __) => MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder:
                        (context) => TextButton(
                          onPressed:
                              () => showReminderSheet(
                                context,
                                reminder: _reminder(),
                              ),
                          child: const Text('open'),
                        ),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(AddEditReminderScreen), findsNothing);
    expect(find.text('Saved.'), findsOneWidget);
  });

  testWidgets('a new reminder starts with no type: Save asks for one first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo();
    final created = <String>[];
    await _open(tester, repo, null, overrides: [
      createReminderProvider.overrideWith((ref, p) async {
        created.add(p.reminderType);
        return _reminder();
      }),
    ]);
    final picker = find.byType(SegmentedButton<String>);
    expect(tester.widget<SegmentedButton<String>>(picker).selected, isEmpty);

    await tester.enterText(find.byType(TextField).first, "Angie's birthday");
    await tester.tap(find.byKey(const Key('healingSelfReportDateRow')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CupertinoDatePicker), const Offset(0, -60));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20)); // close the date sheet
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(created, isEmpty);
    expect(find.text('Choose what it’s for.'), findsOneWidget);
    expect(find.byType(AddEditReminderScreen), findsOneWidget, reason: 'stays open');

    await tester.tap(find.text('Birthday'));
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<String>>(picker).selected, {'birthday'});
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(created, ['birthday']);
  });

  testWidgets('a save that failed goes through when tried again', (tester) async {
    final repo = _FakeRepo()..failUpdates = 1;
    await _open(tester, repo, _reminder());
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.updates, isEmpty);
    expect(find.byType(AddEditReminderScreen), findsOneWidget, reason: 'stays open');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.updates, hasLength(1), reason: 'the retry really writes');
    expect(find.byType(AddEditReminderScreen), findsNothing);
  });

  testWidgets('saving the same edit twice writes it twice', (tester) async {
    final repo = _FakeRepo();
    await _open(tester, repo, _reminder());
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.updates, hasLength(2));
  });

  /// Title, a date (today: the picker opened and closed untouched) and a type.
  Future<void> fillNew(WidgetTester tester, String type) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.enterText(find.byType(TextField).first, 'Our anniversary');
    await tester.tap(find.byKey(const Key('healingSelfReportDateRow')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20)); // close the date sheet
    await tester.pumpAndSettle();
    await tester.tap(find.text(type));
    await tester.pumpAndSettle();
  }

  testWidgets("today's date counts once the picker has been opened", (tester) async {
    final created = <String>[];
    await _open(tester, _FakeRepo(), null, overrides: [
      createReminderProvider.overrideWith((ref, p) async {
        created.add(p.title);
        return _reminder();
      }),
    ]);
    await fillNew(tester, 'Birthday');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a date.'), findsNothing);
    expect(created, ['Our anniversary']);
  });

  testWidgets('Save with no date chosen asks for one, and stays open', (tester) async {
    await _open(tester, _FakeRepo(), null);
    await tester.enterText(find.byType(TextField).first, 'Dentist');
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a date.'), findsOneWidget);
    expect(find.byType(AddEditReminderScreen), findsOneWidget);
  });

  testWidgets('the sheet header is the app\'s, with Save as a text button', (tester) async {
    await _open(tester, _FakeRepo(), null);
    final header = tester.widget<BottomSheetHeader>(find.byType(BottomSheetHeader));
    expect(header.title, 'Add reminder');
    expect(header.actionLabel, 'Save');
    expect(header.onPressed, isNotNull, reason: 'never null: that would close the sheet');
    expect(find.widgetWithText(AppTextButton, 'Save'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('yearly is on for birthdays and anniversaries, off for Other', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _open(tester, _FakeRepo(), null);
    bool yearly() => tester
        .widget<InfoRowWidget>(find.widgetWithText(InfoRowWidget, 'Repeats every year'))
        .toggleValue!;
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(yearly(), isFalse);
    await tester.tap(find.text('Birthday'));
    await tester.pumpAndSettle();
    expect(yearly(), isTrue);
  });

  testWidgets('if adding it to the Timeline fails, the reminder is still saved once', (tester) async {
    final created = <String>[];
    await _open(
      tester,
      _FakeRepo(),
      null,
      overrides: [
        createReminderProvider.overrideWith((ref, p) async {
          created.add(p.title);
          return _reminder();
        }),
        timelineRepositoryProvider.overrideWithValue(_FailingTimeline()),
        currentUserIdProvider.overrideWithValue('user-1'),
      ],
    );
    await fillNew(tester, 'Anniversary');
    await tester.tap(find.text('Save'));
    // Save's spinner runs while the question is up: pump, don't settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Add it'));
    await tester.pumpAndSettle();
    expect(created, ['Our anniversary']);
    expect(find.byType(AddEditReminderScreen), findsNothing, reason: 'closed: a retry would duplicate it');
  });

  testWidgets('the date reads in the app format; titles stop at 80', (tester) async {
    await _open(tester, _FakeRepo(), _reminder());
    expect(find.text(MyDateFormat.toDate(DateTime(2026, 11, 2))), findsOneWidget);
    final title = tester.widget<TextField>(find.byType(TextField).first);
    expect(title.maxLength, 80);
  });

  testWidgets('editing a check-in keeps it a check-in', (tester) async {
    final repo = _FakeRepo();
    await _open(tester, repo, _reminder(type: 'checkin'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.updates.single['reminderType'], 'checkin');
  });

  testWidgets('adding says Add reminder', (tester) async {
    await _open(tester, _FakeRepo(), null);
    expect(find.text('Add reminder'), findsOneWidget);
  });

  testWidgets('added to a day, the reminder starts on it: title and type are enough', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remindersRepositoryProvider.overrideWithValue(_FakeRepo()),
          currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
        ],
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder:
              (_, __) => MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder:
                        (context) => TextButton(
                          onPressed: () => showReminderSheet(context, initialDate: DateTime(2026, 12, 24)),
                          child: const Text('open'),
                        ),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(MyDateFormat.toDate(DateTime(2026, 12, 24))), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Christmas Eve');
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a date.'), findsNothing, reason: 'the day is already chosen');
  });

  Future<void> openOnDay(WidgetTester tester, DateTime day, {List<Override> overrides = const []}) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remindersRepositoryProvider.overrideWithValue(_FakeRepo()),
          currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
          ...overrides,
        ],
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder:
              (_, __) => MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder:
                        (context) => TextButton(
                          onPressed: () => showReminderSheet(context, initialDate: day),
                          child: const Text('open'),
                        ),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a one-off in the past is refused: it could never go off', (tester) async {
    final created = <String>[];
    await openOnDay(tester, DateTime(2020, 1, 1), overrides: [
      createReminderProvider.overrideWith((ref, p) async {
        created.add(p.title);
        return _reminder();
      }),
    ]);
    await tester.enterText(find.byType(TextField).first, 'Dentist');
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(created, isEmpty);
    expect(find.text('Pick today or a later date for a one-off reminder.'), findsOneWidget);
  });

  testWidgets('a yearly reminder can start from a past date, like a birthday', (tester) async {
    final created = <String>[];
    await openOnDay(tester, DateTime(1990, 4, 2), overrides: [
      createReminderProvider.overrideWith((ref, p) async {
        created.add(p.title);
        return _reminder();
      }),
    ]);
    await tester.enterText(find.byType(TextField).first, "Mum's birthday");
    await tester.tap(find.text('Birthday'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(created, ["Mum's birthday"]);
  });

  testWidgets('with a title and date but no type, Save says a type is needed', (tester) async {
    await openOnDay(tester, DateTime.now().add(const Duration(days: 3)));
    await tester.enterText(find.byType(TextField).first, 'Dentist');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Choose what it’s for.'), findsOneWidget);
  });

  testWidgets('two quick taps on Save add one reminder', (tester) async {
    final created = <String>[];
    await openOnDay(tester, DateTime.now().add(const Duration(days: 3)), overrides: [
      createReminderProvider.overrideWith((ref, p) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        created.add(p.title);
        return _reminder();
      }),
    ]);
    await tester.enterText(find.byType(TextField).first, 'Dentist');
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    final save = tester.widget<AppTextButton>(find.widgetWithText(AppTextButton, 'Save'));
    save.onPressed!();
    save.onPressed!();
    await tester.pumpAndSettle();
    expect(created, hasLength(1));
  });

  testWidgets('when to hear: on the day and 3 days before, unless chosen otherwise', (tester) async {
    final created = <List<int>>[];
    await openOnDay(tester, DateTime.now().add(const Duration(days: 20)), overrides: [
      createReminderProvider.overrideWith((ref, p) async {
        created.add(p.remindDaysBefore);
        return _reminder();
      }),
    ]);
    bool on(String label) => tester.widget<FilterChip>(find.widgetWithText(FilterChip, label)).selected;
    expect(on('On the day'), isTrue);
    expect(on('3 days before'), isTrue);
    expect(on('1 day before'), isFalse);
    expect(on('1 week before'), isFalse);
    await tester.tap(find.widgetWithText(FilterChip, '1 week before'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Flight');
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(created.single, [0, 3, 7]);
  });

  testWidgets('at least one time to hear stays chosen', (tester) async {
    await openOnDay(tester, DateTime.now().add(const Duration(days: 20)));
    await tester.tap(find.widgetWithText(FilterChip, 'On the day'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '3 days before'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, '3 days before')).selected, isTrue);
  });

  testWidgets('an edit saves when to hear', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo();
    await _open(tester, repo, _reminder());
    await tester.tap(find.widgetWithText(FilterChip, '1 day before'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.updates.single['remindDaysBefore'], [0, 1, 3]);
  });

  for (final linked in [false, true])
    testWidgets(linked ? 'deleting a reminder keeps its memory, and says so' : 'deleting a reminder says so', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = _FakeRepo();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remindersRepositoryProvider.overrideWithValue(repo),
            currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
          ],
          child: ScreenUtilInit(
            designSize: const Size(375, 812),
            builder:
                (_, __) => MaterialApp(
                  home: Scaffold(
                    body: Builder(
                      builder:
                          (context) => TextButton(
                            onPressed: () => showReminderSheet(context, reminder: _reminder(linkedTo: linked ? 'm1' : null)),
                            child: const Text('open'),
                          ),
                    ),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete reminder'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(repo.deleted, ['rem-1']);
      expect(
        find.text(linked ? 'Reminder deleted. The memory stays on your Timeline.' : 'Reminder deleted.'),
        findsOneWidget,
      );
    });

  testWidgets('date and repeat are rows with their own dividers; types never wrap', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _open(tester, _FakeRepo(), _reminder());
    final date = tester.widget<InfoRowWidget>(find.byKey(const Key('healingSelfReportDateRow')));
    expect(date.showDivider, isTrue);
    final repeat = tester.widget<InfoRowWidget>(find.widgetWithText(InfoRowWidget, 'Repeats every year'));
    expect(repeat.showDivider, isTrue);
    for (final label in ['Anniversary', 'Birthday', 'Other']) {
      final text = tester.widget<Text>(
        find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text(label)),
      );
      expect(text.overflow, TextOverflow.ellipsis, reason: label);
      expect(text.maxLines, 1, reason: label);
    }
  });
}

class _FailingTimeline implements TimelineRepository {
  @override
  Future<TimelineEventModel> createEvent({
    required String relationshipId,
    required String loggedBy,
    required String eventType,
    required String title,
    required DateTime occurredAt,
    String? note,
    int? moodScore,
    String visibility = 'shared',
  }) async => throw Exception('offline');

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
