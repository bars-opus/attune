// Spec 1 W2b, review B5 fix round 2: the account-check hold. While the
// account of a proven number is read it says so; when that read can't run
// (offline) it says so in its own words, read out on every failed try,
// with "Try again" and "Not now", each run once however often pressed.
import 'dart:async';

import 'package:attune/features/auth/sign_up/presentation/steps/account_check_step.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

const _failedTitle = "We couldn't check your account";
const _failedBody = 'Check your connection and try again.';
const _checking = 'Checking your account…';

/// What the flow drives the hold with.
class _Flow extends ChangeNotifier {
  bool checking = false;
  int failCount = 1;
  String? errorText;

  void update(void Function(_Flow flow) change) {
    change(this);
    notifyListeners();
  }
}

Widget Function() _host(
  _Flow flow, {
  FutureOr<void> Function()? onRetry,
  FutureOr<void> Function()? onNotNow,
}) =>
    () => ListenableBuilder(
      listenable: flow,
      builder:
          (_, __) => AccountCheckStep(
            checking: flow.checking,
            failCount: flow.failCount,
            errorText: flow.errorText,
            onRetry: onRetry ?? () {},
            onNotNow: onNotNow ?? () {},
          ),
    );

List<String> _announcements(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  final said = <String>[];
  messenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (message) async {
      final event = message as Map<Object?, Object?>;
      if (event['type'] == 'announce') {
        said.add((event['data'] as Map<Object?, Object?>)['message'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => messenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      null,
    ),
  );
  return said;
}

void main() {
  testWidgets('failed: its own words with an icon, Try again and Not now, '
      'nothing about a code', (tester) async {
    await pumpFlowScreen(tester, _host(_Flow()));
    expect(find.text(_failedTitle), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text(_failedBody),
        matching: find.byType(FlowErrorLine),
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.textContaining('code'), findsNothing);
    await expectFlowGuidelines(tester);
  });

  testWidgets('checking: says so, with progress and no buttons', (
    tester,
  ) async {
    await pumpFlowScreen(tester, _host(_Flow()..checking = true));
    // Progress after 400 ms (§2.2).
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text(_checking), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text(_failedBody), findsNothing);
    await expectFlowGuidelines(tester);
  });

  testWidgets('each failed check is read out, the first and every later one', (
    tester,
  ) async {
    final said = _announcements(tester);
    final flow = _Flow()..checking = true;
    await pumpFlowScreen(tester, _host(flow));
    expect(said, isEmpty);
    flow.update((f) {
      f.checking = false;
      f.failCount = 1;
    });
    await tester.pump();
    flow.update((f) => f.failCount = 2);
    await tester.pump();
    expect(said, [_failedBody, _failedBody]);
  });

  testWidgets('opened already failed (A4 to the hold), it is read out once', (
    tester,
  ) async {
    final said = _announcements(tester);
    await pumpFlowScreen(tester, _host(_Flow()));
    expect(said, [_failedBody]);
  });

  testWidgets('Try again and Not now each run once however fast they are '
      'pressed, and the other waits', (tester) async {
    final gate = Completer<void>();
    var retries = 0;
    var notNows = 0;
    await pumpFlowScreen(
      tester,
      _host(
        _Flow(),
        onRetry: () {
          retries++;
          return gate.future;
        },
        onNotNow: () => notNows++,
      ),
    );
    await tester.tap(find.text('Try again'));
    await tester.tap(find.text('Try again'), warnIfMissed: false);
    await tester.tap(find.text('Not now'), warnIfMissed: false);
    await tester.pump();
    expect((retries, notNows), (1, 0));
    gate.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect((retries, notNows), (1, 1));
  });

  testWidgets('a sign-out that failed on Not now is said too', (tester) async {
    await pumpFlowScreen(
      tester,
      _host(_Flow()..errorText = "We couldn't save that. Try again."),
    );
    expect(
      find.ancestor(
        of: find.text("We couldn't save that. Try again."),
        matching: find.byType(FlowErrorLine),
      ),
      findsOneWidget,
    );
  });

  testWidgets('goldens: the failed hold', (tester) async {
    await expectFlowGoldens(tester, 'step_account_check', _host(_Flow()));
  });
}
