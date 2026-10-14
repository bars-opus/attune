import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/data/repositories/reminders_repository.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements RemindersRepository {
  final List<Map<String, Object?>> updates = [];
  final List<String> deleted = [];

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
  }) async {
    updates.add({
      'id': id,
      'reminderType': reminderType,
      'title': title,
      'note': note,
      'clearNote': clearNote,
      'remindAt': remindAt,
      'recurrence': recurrence,
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

ReminderModel _reminder({String type = 'anniversary'}) => ReminderModel(
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
);

Future<void> _open(WidgetTester tester, _FakeRepo repo, ReminderModel r) async {
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
}
