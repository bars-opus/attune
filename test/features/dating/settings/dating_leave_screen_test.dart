// Spec 2 W3c (§3.8; carries 12, 13): Leave Dating and delete my data.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/settings/dating_leave_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

Future<FakeDatingLifecycleGateway> _pump(
  WidgetTester t, {
  DatingLifecycleResult? result,
  bool online = true,
}) async {
  await t.pumpWidget(const SizedBox());
  final life = FakeDatingLifecycleGateway();
  if (result != null) life.result = result;
  await pumpFlowScreen(
    t,
    () => const DatingLeaveScreen(),
    // Fix 1 (I-1): Pause instead is offered on an active home only.
    overrides: datingShellOverrides(
      home: _active(),
      life: life,
      online: online,
    ),
  );
  await t.pumpAndSettle();
  return life;
}

void main() {
  testWidgets('the §3.8 copy, word for word; the list box starts off', (
    t,
  ) async {
    await _pump(t);
    for (final line in [
      'Leave Dating?',
      "Deleted now: your Dating profile, photos, prompts, who you'd like to meet, your gender and faith answers, your settings and your private notes.",
      'Kept for 30 days, then deleted: your conversations, so either of you can still report a problem.',
      "Kept for safety, for up to 2 years, only if your account is restricted or you've blocked someone: a code made from your phone number, never the number itself.",
      "Kept as a record: when you agreed to Dating's terms and when you left.",
      "Keep my 'Never introduce me' list in case I come back. It holds codes, not numbers.",
      'Leave and delete',
      'Pause instead',
    ]) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
    expect(
      t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
  });

  testWidgets(
    'Leave and delete: one exit, the list not kept, then the done line',
    (t) async {
      final life = await _pump(
        t,
        result: const DatingLifecycleResult.done('exited'),
      );
      await tapInReach(t, find.text('Leave and delete'));
      await t.pumpAndSettle();
      expect(life.calls, ['exit']);
      expect(life.keptList, isFalse);
      expect(
        find.text("You've left Dating. You can set it up again any time."),
        findsOneWidget,
      );
      expect(find.text('Leave and delete'), findsNothing);
    },
  );

  testWidgets('ticked: the list is kept', (t) async {
    final life = await _pump(
      t,
      result: const DatingLifecycleResult.done('exited'),
    );
    await tapInReach(t, find.byType(CheckboxListTile));
    await t.pump();
    await tapInReach(t, find.text('Leave and delete'));
    await t.pumpAndSettle();
    expect(life.keptList, isTrue);
  });

  testWidgets('a restricted account: "You\'ve left Dating." only (carry 13)', (
    t,
  ) async {
    await _pump(t, result: const DatingLifecycleResult.done('suspended'));
    await tapInReach(t, find.text('Leave and delete'));
    await t.pumpAndSettle();
    expect(find.text("You've left Dating."), findsOneWidget);
    expect(find.textContaining('set it up again'), findsNothing);
  });

  testWidgets('Pause instead pauses and says so', (t) async {
    final life = await _pump(
      t,
      result: const DatingLifecycleResult.done('paused'),
    );
    await tapInReach(t, find.text('Pause instead'));
    await t.pumpAndSettle();
    expect(life.calls, ['pause']);
    expect(
      find.text(
        'Dating is paused. Nobody new sees you, and your conversations stay open.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('busy and offline', (t) async {
    final life = await _pump(
      t,
      result: const DatingLifecycleResult.refused(DatingLifecycleError.busy),
    );
    await tapInReach(t, find.text('Leave and delete'));
    await t.pumpAndSettle();
    expect(
      find.text(
        'This is taking a little longer than usual. Try again in a moment.',
      ),
      findsOneWidget,
    );
    expect(find.text('Leave and delete'), findsOneWidget);
    // T12 carry C: deletion is never gated offline. The exit is tried; when
    // it can't be sent, the offline line says so and the button stays.
    final offline = await _pump(
      t,
      online: false,
      result: const DatingLifecycleResult.refused(DatingLifecycleError.failed),
    );
    await tapInReach(t, find.text('Leave and delete'));
    await t.pumpAndSettle();
    expect(offline.calls, ['exit']);
    expect(
      find.text("You're offline. Dating needs a connection."),
      findsOneWidget,
    );
    expect(find.text('Something went wrong. Try again.'), findsNothing);
    expect(find.text('Leave and delete'), findsOneWidget);
    expect(life.calls, ['exit']);
  });

  testWidgets('guidelines and goldens', (t) async {
    final semantics = t.ensureSemantics();
    await _pump(t);
    await expectFlowGuidelines(t);
    semantics.dispose();
    await expectFlowGoldens(
      t,
      'dating_leave',
      () => const DatingLeaveScreen(),
      overrides: datingShellOverrides(home: _active()),
    );
  });
}

FakeDatingHomeGateway _active() => FakeDatingHomeGateway(
  home: const DatingHome(state: DatingHomeState.active),
);
