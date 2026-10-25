// Spec 1 §2.3 (W2a): every new screen at text sizes 1.0, 1.3 and 2.0 and
// once right to left. Look at the images when they change: they are the
// review of large text, not just a regression net.
//   flutter test --update-goldens test/features/auth/sign_up/w2a_goldens_test.dart
import 'package:attune/features/auth/sign_up/presentation/screens/guest_age_gate_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/invite_landing_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

DateTime _now() => DateTime.utc(2026, 10, 25, 12);

void main() {
  testWidgets('WL1 Welcome', (tester) async {
    await expectFlowGoldens(tester, 'welcome', () => const WelcomeScreen());
  });

  testWidgets('WL1 Dating preview', (tester) async {
    await expectFlowGoldens(
      tester,
      'welcome_preview_dating',
      () => const WelcomeScreen(),
      openCountries: const ['GB', 'GH'],
      before: (tester) async {
        // At 2.0 the card is below the fold: a blind tap misses it. Scroll
        // only when it is off screen, so the other backdrops stay at the top.
        await Scrollable.ensureVisible(
          tester.element(find.text('Single and open to dating')),
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Single and open to dating'));
        await tester.pumpAndSettle();
        expect(find.text('Introductions, not swiping'), findsOneWidget);
      },
    );
  });

  testWidgets('G1 guest age gate, with an error', (tester) async {
    await expectFlowGoldens(
      tester,
      'guest_age_gate_error',
      () => GuestAgeGateScreen(now: _now),
      before: (tester) async {
        await tester.enterText(find.byType(TextField), '94');
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('X1 under-18 stop', (tester) async {
    await expectFlowGoldens(
      tester,
      'under_age_stop',
      () => const UnderAgeStopScreen(),
    );
  });

  testWidgets('RI-2 invite code', (tester) async {
    await expectFlowGoldens(
      tester,
      'invite_code',
      () => const InviteLandingScreen(),
    );
  });

  testWidgets('RI-1 invited', (tester) async {
    await expectFlowGoldens(
      tester,
      'invite_landing',
      () => const InviteLandingScreen(),
      // Ruling C2: stored now, so W1's 24 h expiry never drops it.
      prefsValues: {
        'attune.onboarding.anonymous.pending_invite':
            '{"code":"K7P2QM","stored_at":"${DateTime.now().toUtc().toIso8601String()}"}',
      },
    );
  });
}
