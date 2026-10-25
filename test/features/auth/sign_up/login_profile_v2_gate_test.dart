// Spec 1 W2b gate (ruling M-8): with flow_signin_v2 on, no LoginScreen
// sheet is reachable from the guest's sign-in tab. Every tap target
// LoginProfile builds is pressed in turn, each on a fresh screen: none
// presents LoginScreen, and the ways in land on /signup or /invite.
// With the flag off the same sweep does reach today's LoginScreen sheet,
// so the sweep can see one.
import 'package:attune/features/auth/log_in/presentation/screens/login_profile.dart';
import 'package:attune/features/auth/log_in/presentation/screens/login_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

Finder _tapTargets() => find.descendant(
  of: find.byType(LoginProfile),
  matching: find.byWidgetPredicate(
    (w) =>
        (w is GestureDetector && w.onTap != null) ||
        (w is InkResponse && w.onTap != null),
  ),
);

/// Presses every tap target once and returns, per target, where the
/// router went and whether a LoginScreen appeared.
Future<List<(String, bool)>> _sweep(WidgetTester tester, bool flowV2) async {
  Future<FlowHarness> pump() => pumpFlowScreen(
    tester,
    () => const Scaffold(body: LoginProfile()),
    overrides: [signInFlowV2Provider.overrideWithValue(flowV2)],
  );

  final results = <(String, bool)>[];
  for (var i = 0; ; i++) {
    final h = await pump();
    final targets = _tapTargets().evaluate().toList();
    if (i >= targets.length) break;
    // Held by element: scrolling a card into view rebuilds the topic row,
    // which would shift a by-index finder.
    final element = targets[i];
    final target = find.byElementPredicate((e) => identical(e, element));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target, warnIfMissed: false);
    await tester.pumpAndSettle();
    results.add((h.location, find.byType(LoginScreen).evaluate().isNotEmpty));
  }
  expect(results, isNotEmpty);
  return results;
}

void main() {
  testWidgets('flag on: no tap on the guest tab presents LoginScreen', (
    tester,
  ) async {
    final results = await _sweep(tester, true);

    expect(
      results.where((r) => r.$2),
      isEmpty,
      reason: 'a LoginScreen sheet was reachable under flow_signin_v2',
    );
    final reached = results.map((r) => r.$1).toSet();
    expect(reached, contains('/signup?entry=new&back=%2Fhome'));
    expect(reached, contains('/signup?entry=returning&back=%2Fhome'));
    expect(reached, contains('/invite'));
    // Every other tap stays on the tab (a help or legal sheet) or opens
    // settings; nothing leads to a sign-in screen but sign-up.
    for (final location in reached) {
      final path = Uri.parse(location).path;
      expect(
        ['/test', '/settings', '/signup', '/invite', '/welcome'],
        contains(path),
        reason: 'a guest-tab tap went to $location',
      );
    }
  });

  testWidgets('flag off: the sweep reaches today\'s LoginScreen sheet', (
    tester,
  ) async {
    final results = await _sweep(tester, false);

    // The phone button's own target and the one inside it.
    expect(results.where((r) => r.$2), isNotEmpty);
    expect(
      results.map((r) => Uri.parse(r.$1).path),
      isNot(contains('/signup')),
    );
  });
}
