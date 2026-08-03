import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attune/features/healing/data/repositories/healing_repository.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/widgets/healing_self_report_sheet.dart';

void main() {
  testWidgets('primary button is disabled until a date is picked', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (context, child) =>
              MaterialApp(home: Scaffold(body: HealingSelfReportSheet())),
        ),
      ),
    );

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('shows inline error text when submission throws', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healingRepositoryProvider.overrideWithValue(_ThrowingHealingRepository()),
        ],
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (context, child) =>
              MaterialApp(home: Scaffold(body: HealingSelfReportSheet())),
        ),
      ),
    );

    // Simulate a date already selected by driving the widget's own date
    // button, since showDatePicker cannot be programmatically driven in a
    // plain widget test without a golden/native dialog harness. Tap the
    // date row, then tap today's date in the picker, then tap submit.
    await tester.tap(find.byKey(const Key('healingSelfReportDateRow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not start'), findsOneWidget);
  });
}

class _ThrowingHealingRepository implements HealingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getOrCreateJourney) {
      throw Exception('network error');
    }
    return super.noSuchMethod(invocation);
  }
}
