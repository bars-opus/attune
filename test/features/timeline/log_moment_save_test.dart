import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/screens/log_moment_details_screen.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_indicators.dart';

TimelineEventModel _event(String title) => TimelineEventModel(
  id: 'e1',
  relationshipId: 'rel',
  loggedBy: 'ama',
  eventType: 'highlight',
  title: title,
  occurredAt: DateTime(2026, 10, 10),
  createdAt: DateTime(2026, 10, 10),
);

/// The details form, failing its first [fail] creates.
Future<List<String>> _pump(WidgetTester t, {int fail = 0}) async {
  final created = <String>[];
  var failures = fail;
  t.view.physicalSize = const Size(1200, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        createTimelineEventProvider.overrideWith((ref, p) async {
          if (failures > 0) {
            failures--;
            throw Exception('PostgrestException(message: offline)');
          }
          created.add(p.title);
          return _event(p.title);
        }),
      ],
      child: MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => const LogMomentDetailsScreen(eventType: 'highlight'),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return created;
}

void main() {
  testWidgets('a save that failed goes through when tried again', (t) async {
    final created = await _pump(t, fail: 1);
    await t.enterText(find.byType(TextFormField).first, 'Date night');
    await t.pump();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(created, isEmpty);
    // A plain message, never the raw error.
    expect(find.textContaining("Postgrest"), findsNothing);
    expect(find.text("Couldn't save that moment. Please try again."), findsOneWidget);

    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(created, ['Date night']);
  });

  testWidgets('emptying the note on an edit clears it', (t) async {
    final updates = <({String? note, bool clearNote})>[];
    t.view.physicalSize = const Size(1200, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          updateTimelineEventProvider.overrideWith((ref, p) async {
            updates.add((note: p.note, clearNote: p.clearNote));
            return _event(p.title ?? '');
          }),
        ],
        child: MaterialApp(
          home: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => LogMomentDetailsScreen(
                  eventType: 'highlight',
                  editEventId: 'e1',
                  initialData: {
                    'title': 'Date night',
                    'note': 'Jollof place',
                    'occurred_at': DateTime(2026, 10, 10),
                  },
                ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Jollof place'), '');
    await t.pump();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(updates.single.note, isNull);
    expect(updates.single.clearNote, isTrue);
  });

  testWidgets('the date reads in the app format, and older moments can be picked', (t) async {
    await _pump(t);
    final today = DateTime.now();
    expect(find.text(MyDateFormat.toDate(today)), findsOneWidget);
    await t.tap(find.text(MyDateFormat.toDate(today)));
    await t.pumpAndSettle();
    final picker = t.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
    expect(picker.minimumDate!.year, lessThanOrEqualTo(1950));
  });

  Future<(List<String>, List<Object?>)> openSheet(WidgetTester t, {DateTime? day}) async {
    final created = <String>[];
    final results = <Object?>[];
    t.view.physicalSize = const Size(1200, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          createTimelineEventProvider.overrideWith((ref, p) async {
            created.add(p.eventType);
            return _event(p.title);
          }),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, __) => MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder:
                        (context) => TextButton(
                          onPressed: () async => results.add(await showMomentSheet(context, day: day)),
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
    return (created, results);
  }

  testWidgets('one sheet: pick the kind of moment right there, then save', (t) async {
    final (created, results) = await openSheet(t);
    for (final type in ['milestone', 'highlight', 'conflict', 'first', 'anniversary']) {
      expect(find.widgetWithText(RadioListTile<String>, calendarEventTypeLabel(type)), findsOneWidget);
    }
    await t.enterText(find.byType(TextFormField).first, 'Date night');
    await t.pump();
    // No kind yet: nothing to save.
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(created, isEmpty);
    // Typing scrolled the field into view; back up to the kinds.
    await t.scrollUntilVisible(
      find.widgetWithText(RadioListTile<String>, 'Highlight'),
      -100,
      scrollable: find.descendant(of: find.byType(LogMomentDetailsScreen), matching: find.byType(Scrollable)).first,
    );
    await t.tap(find.widgetWithText(RadioListTile<String>, 'Highlight'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(created, ['highlight']);
    expect(results, [true]);
    expect(find.byType(LogMomentDetailsScreen), findsNothing);
  });

  testWidgets('the sheet opened from a day starts on it', (t) async {
    final day = DateTime(2026, 9, 12);
    await openSheet(t, day: day);
    expect(find.text(MyDateFormat.toDate(day)), findsOneWidget);
  });

  testWidgets('a memory dated ahead (it follows its reminder) still opens its date picker', (t) async {
    final ahead = DateTime.now().add(const Duration(days: 40));
    final day = DateTime(ahead.year, ahead.month, ahead.day);
    t.view.physicalSize = const Size(1200, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => LogMomentDetailsScreen(
                  eventType: 'anniversary',
                  editEventId: 'e1',
                  initialData: {'title': 'Our day', 'occurred_at': day},
                ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text(MyDateFormat.toDate(day)));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final wheel = t.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
    expect(wheel.maximumDate!.isBefore(day), isFalse);
  });

  group('looks like the other sheets', () {
    testWidgets('a sheet header with Save; the date is a row with the app wheel', (t) async {
      await openSheet(t);
      final header = t.widget<BottomSheetHeader>(find.byType(BottomSheetHeader));
      expect(header.title, 'Log a moment');
      expect(header.actionLabel, 'Save');
      // Save with nothing filled in stays open and says what's missing.
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.byType(LogMomentDetailsScreen), findsOneWidget);
      expect(find.text('Choose what kind of moment it is.'), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      final today = DateTime.now();
      final dateRow = t.widget<InfoRowWidget>(find.widgetWithText(InfoRowWidget, MyDateFormat.toDate(today)));
      expect(dateRow.showDivider, isTrue);
      await t.tap(find.text(MyDateFormat.toDate(today)));
      await t.pumpAndSettle();
      final wheel = t.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
      expect(wheel.minimumDate!.year, lessThanOrEqualTo(1950));
    });

    testWidgets('the kind is a plain radio list: one chosen at a time', (t) async {
      await openSheet(t);
      RadioListTile<String> radio(String label) =>
          t.widget<RadioListTile<String>>(find.widgetWithText(RadioListTile<String>, label));
      expect(radio('Milestone').groupValue, isNull);
      await t.tap(find.text('First'));
      await t.pumpAndSettle();
      expect(radio('First').groupValue, 'first');
      await t.tap(find.text('Conflict'));
      await t.pumpAndSettle();
      expect(radio('First').groupValue, 'conflict');
      expect(radio('Conflict').value, 'conflict');
    });
  });
}
