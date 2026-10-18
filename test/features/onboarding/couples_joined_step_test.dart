import 'package:attune/features/chat/domain/seen_receipts.dart';
import 'package:attune/features/onboarding/presentation/widgets/couples_joined_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Ask 1 tells a new couple receipts are off to start (F4 (4))', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => Scaffold(
                  body: OnboardingDeckScope(
                    cardKey: 0,
                    accent: OnboardingDeckAccent.neutral,
                    enableDeck: false,
                    child: CouplesJoinedStep(onFinish: () {}),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('You are connected'), findsOneWidget);
    expect(find.text(seenReceiptsAsk1Line), findsOneWidget);
    // Ask 1 copy carries no intelligence vocabulary (AUTH_ONBOARDING_ENGINE §).
    for (final banned in ['AI', 'intelligence', 'insight', 'analysis']) {
      expect(find.textContaining(banned), findsNothing, reason: banned);
    }
  });
}
