// Spec 1 W2b gate (ruling M-8): every tap target the guest's sign-in tab
// builds is pressed in turn, each on a fresh screen, and the ways in land on
// /welcome (a new account's path first), /signup or /invite. Since 2026-11-26 the old LoginScreen is gone and the
// new sign-in is the only one, so the flag no longer changes the tab.
import 'package:attune/features/auth/log_in/presentation/screens/login_profile.dart';
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
/// router went.
Future<List<String>> _sweep(WidgetTester tester, bool flowV2) async {
  Future<FlowHarness> pump() => pumpFlowScreen(
    tester,
    () => const Scaffold(body: LoginProfile()),
    overrides: [signInFlowV2Provider.overrideWithValue(flowV2)],
  );

  final results = <String>[];
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
    results.add(h.location);
  }
  expect(results, isNotEmpty);
  return results;
}

void main() {
  for (final flowV2 in [true, false]) {
  testWidgets('flag ${flowV2 ? 'on' : 'off'}: every way in is the new sign-in', (
    tester,
  ) async {
    final results = await _sweep(tester, flowV2);

    final reached = results.toSet();
    // Spec 1 W3a (W2 B6 m-4): sign-up's Back returns to Tab 2. A new
    // account goes by Welcome first, for its path, with the same back (fix
    // round I-2, owner 2026-11-26).
    for (final (path, entry) in [('/welcome', null), ('/signup', 'returning')]) {
      expect(
        reached.any((location) {
          final uri = Uri.parse(location);
          final back = Uri.parse(uri.queryParameters['back'] ?? '');
          return uri.path == path &&
              uri.queryParameters['entry'] == entry &&
              back.path == '/home' &&
              back.queryParameters['tab'] == 'chat';
        }),
        isTrue,
        reason: path,
      );
    }
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

  }
}
