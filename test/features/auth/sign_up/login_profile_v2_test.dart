// Spec 1 W2b (§3.2 G2): the guest's sign-in tab. With flow_signin_v2 on it
// is "Join Attune" and the three ways in; off, it is today's screen.
import 'package:attune/features/auth/log_in/presentation/screens/login_profile.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/join_attune_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

void main() {
  testWidgets('flag on: Join Attune and the three ways in', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await pumpFlowScreen(
      tester,
      () => const Scaffold(body: LoginProfile()),
      overrides: [signInFlowV2Provider.overrideWithValue(true)],
    );
    expect(find.text('Join Attune'), findsOneWidget);
    expect(
      find.text(
        'A private space for couples, a few introductions a day for singles, and a journal just for you.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue with phone number'), findsNothing);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(Uri.parse(h.location).path, '/signup');
    expect(Uri.parse(h.location).queryParameters, {
      'entry': 'new',
      'back': '/home',
    });
    semantics.dispose();
  });

  testWidgets('the panel meets the tap-target, label and contrast guidelines', (
    tester,
  ) async {
    // On its own: the legal link LoginProfile keeps under it is today's and
    // is left for the W10 accessibility pass.
    final semantics = tester.ensureSemantics();
    await pumpFlowScreen(
      tester,
      () =>
          const Scaffold(body: SingleChildScrollView(child: JoinAttunePanel())),
    );
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  for (final (button, entry) in [('I already have an account', 'returning')]) {
    testWidgets('flag on: "$button" opens sign-up as $entry', (tester) async {
      final h = await pumpFlowScreen(
        tester,
        () => const Scaffold(body: LoginProfile()),
        overrides: [signInFlowV2Provider.overrideWithValue(true)],
      );
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      expect(Uri.parse(h.location).queryParameters['entry'], entry);
    });
  }

  testWidgets('flag on: "I have an invite" opens /invite', (tester) async {
    final h = await pumpFlowScreen(
      tester,
      () => const Scaffold(body: LoginProfile()),
      overrides: [signInFlowV2Provider.overrideWithValue(true)],
    );
    await tester.ensureVisible(find.text('I have an invite'));
    await tester.tap(find.text('I have an invite'));
    await tester.pumpAndSettle();
    expect(h.location, '/invite');
  });

  testWidgets("flag off: today's screen, unchanged", (tester) async {
    await pumpFlowScreen(
      tester,
      () => const Scaffold(body: LoginProfile()),
      overrides: [signInFlowV2Provider.overrideWithValue(false)],
    );
    expect(find.text('Continue with phone number'), findsOneWidget);
    expect(find.text('Invite a friend'), findsOneWidget);
    expect(find.text('Join Attune'), findsNothing);
  });
}
