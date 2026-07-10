import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:flutter/material.dart';
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
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(home: child),
    );
  }
}
