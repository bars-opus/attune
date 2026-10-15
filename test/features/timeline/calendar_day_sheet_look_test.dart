import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_item_row.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _open(WidgetTester t, {List<Object> planning = const [], List<Object> reminders = const [], DateTime? date}) async {
  t.view.physicalSize = const Size(1170, 2532); // a 390-wide phone
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [togetherMeProvider.overrideWithValue('ama')],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder:
                      (c) => TextButton(
                        onPressed:
                            () => showCalendarDaySheet(
                              context: c,
                              relationshipId: null,
                              date: date ?? DateTime(2026, 11, 6),
                              events: const [],
                              reminders: reminders,
                              planningEntries: planning,
                            ),
                        child: const Text('open'),
                      ),
                ),
              ),
            ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a Together event in the sheet is the Agenda\'s row', (t) async {
    await _open(
      t,
      planning: [
        TogetherItem(
          kind: TogetherItemKind.event,
          id: 'e1',
          date: DateTime(2026, 11, 6),
          allDay: true,
          title: 'Dinner at Buka',
          participantIds: const ['ama', 'kofi'],
        ),
      ],
    );
    expect(find.ancestor(of: find.text('Dinner at Buka'), matching: find.byType(TogetherItemRow)), findsOneWidget);
  });

  testWidgets('the sheet fills the width even before (or without) stories', (t) async {
    await _open(t);
    final title = find.text('Friday, November 6, 2026');
    final content = find.ancestor(of: title, matching: find.byType(Column)).first;
    // The sheet spans the phone; its contents fill it (less 16-point sides).
    expect(t.getSize(find.byType(BottomSheet)).width, 390);
    expect(t.getSize(content).width, 390 - 32);
  });

  testWidgets('a tapped birthday shows the same row as Upcoming, with its countdown', (t) async {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day).add(const Duration(days: 3));
    await _open(
      t,
      date: day,
      reminders: [
        ReminderModel(
          id: 'r1', relationshipId: 'r1', createdBy: 'ama', reminderType: 'birthday',
          title: "Ama's birthday", remindAt: day, recurrence: 'yearly', sent: false,
          createdAt: DateTime(2026), updatedAt: DateTime(2026),
        ),
      ],
    );
    expect(find.text("Ama's birthday"), findsOneWidget);
    expect(find.text('In 3 days - Reminder'), findsOneWidget);
    expect(find.byIcon(Icons.cake_outlined), findsOneWidget);
    expect(find.byIcon(FontAwesomeIcons.birthdayCake), findsOneWidget);
  });
}
