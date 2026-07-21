import 'package:attune/features/onboarding/presentation/screens/ask2_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Ask2Flow starts on the intelligence intro, not the quiz directly', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, __) => const Ask2Flow(relationshipId: 'test-rel-id'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A closer look'), findsOneWidget);
    expect(find.text('Relationship reflection quiz'), findsNothing);
  });

  testWidgets('tapping Continue on the intro advances to the quiz', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, __) => const Ask2Flow(relationshipId: 'test-rel-id'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Relationship reflection quiz'), findsOneWidget);
  });
}
