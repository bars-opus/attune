import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 8, 15);

  test('what can be added depends on the day', () {
    expect(addChoicesFor(null, now: now), AddChoice.values.toSet());
    expect(addChoicesFor(DateTime(2026, 11, 8), now: now), AddChoice.values.toSet());
    // A day gone: remember it or set a reminder, not plan it.
    expect(addChoicesFor(DateTime(2026, 11, 1), now: now), {AddChoice.moment, AddChoice.reminder});
    // A day ahead: plan it or be reminded, not log a moment yet.
    expect(addChoicesFor(DateTime(2026, 11, 20), now: now), {AddChoice.event, AddChoice.reminder});
  });

  Future<void> open(WidgetTester t, {DateTime? day}) async {
    await t.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => MaterialApp(
              home: Builder(
                builder:
                    (context) => TextButton(
                      onPressed: () => AddMomentOrReminderSheet.show(context, day: day),
                      child: const Text('add'),
                    ),
              ),
            ),
      ),
    );
    await t.tap(find.text('add'));
    await t.pumpAndSettle();
  }

  testWidgets('from the + button: all three, each with its own icon', (t) async {
    await open(t);
    expect(find.text('Plan something together'), findsOneWidget);
    expect(find.text('Log a moment'), findsOneWidget);
    expect(find.text('Add a reminder'), findsOneWidget);
    expect(find.byIcon(Icons.event_rounded), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
  });

  testWidgets('for a day ahead: named by its date, no moment yet', (t) async {
    final day = DateTime.now().add(const Duration(days: 10));
    final date = DateTime(day.year, day.month, day.day);
    await open(t, day: date);
    expect(find.text('Add to ${MyDateFormat.toDate(date)}'), findsOneWidget);
    expect(find.text('Log a moment'), findsNothing);
    expect(find.text('Plan something together'), findsOneWidget);
  });
}
