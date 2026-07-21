import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('starts with the locked relationship status fork', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      _TestApp(
        child: OnboardingFlow(
          store: OnboardingStore(prefs, scope: OnboardingStore.previewScope),
          requireAuth: false,
          onComplete: () {},
        ),
      ),
    );

    expect(find.text('What should Attune call you?'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Jordan');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Are you single or in a relationship?'), findsOneWidget);
    expect(find.text('Single'), findsOneWidget);
    expect(find.text('In a relationship'), findsOneWidget);
  });

  testWidgets('starts with partner invite when a deep link is pending', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      OnboardingStore.pendingInviteCodeKey: 'ABC123',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      _TestApp(
        child: OnboardingFlow(
          store: OnboardingStore(prefs, scope: OnboardingStore.previewScope),
          requireAuth: false,
          onComplete: () {},
        ),
      ),
    );

    expect(find.text('What should Attune call you?'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Jordan');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('You have a partner invite'), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
    expect(find.text('Are you single or in a relationship?'), findsNothing);
  });

  testWidgets(
    'couples mode skips the inline quiz and anchors after mode selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _TestApp(
          child: OnboardingFlow(
            store: OnboardingStore(prefs, scope: OnboardingStore.previewScope),
            requireAuth: false,
            onComplete: () {},
          ),
        ),
      );

      expect(find.text('What should Attune call you?'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Jordan');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Are you single or in a relationship?'), findsOneWidget);
      await tester.tap(find.text('In a relationship'));
      await tester.pumpAndSettle();

      // The inline quiz and anchors must never appear for couples mode —
      // mode selection should jump straight to the terminal waiting step.
      expect(find.text('Relationship reflection quiz'), findsNothing);
      expect(find.text('Anchor 1'), findsNothing);
      expect(find.text('Are you single or in a relationship?'), findsNothing);
      expect(find.text('Invite your partner'), findsOneWidget);
    },
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(home: child),
      ),
    );
  }
}
