import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/features/healing/data/repositories/healing_repository.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/widgets/healing_self_report_sheet.dart';

void main() {
  testWidgets('primary button is hidden until a date is picked', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (context, child) =>
              MaterialApp(home: Scaffold(body: HealingSelfReportSheet())),
        ),
      ),
    );

    // The submit AppButton only exists once _selectedDate is non-null (see
    // `if (_selectedDate != null) ... AppButton(...)`), rather than
    // rendering disabled — so "not yet pickable" reads as "not present"
    // instead of "present but inert".
    expect(find.byType(AppButton), findsNothing);
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

    // The Cupertino wheel picker is inline on the page (no bottom sheet to
    // open first) and auto-saves — onDateTimeChanged only fires in response
    // to an actual scroll, so a real drag on the wheel is what commits a
    // value into _selectedDate, with no separate confirm tap required.
    await tester.drag(find.byType(CupertinoDatePicker), const Offset(0, -50));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppButton));
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
