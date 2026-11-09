// Spec 2 W3a Task 4 carry C (T2 M-5, M-2): one unlock. The PIN entered on
// Spec 1's Me slot is the same unlock every /dating route reads, so opening
// a step after it asks for no second PIN; on the PIN screen, dismissing
// the sheet stays there and Back goes to Me.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/me/presentation/widgets/dating_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

final _slotRoute = GoRoute(
  path: '/slot',
  builder:
      (_, __) => Scaffold(
        body: SingleChildScrollView(
          child: DatingSlot(home: snapshotOf(homeJson(path: 'dating'))),
        ),
      ),
);

void main() {
  testWidgets('the PIN on the slot, then a step: no second PIN', (t) async {
    final s = await pumpDatingShell(
      t,
      initial: '/slot',
      locked: true,
      home: FakeDatingHomeGateway(
        home: DatingHome(
          state: DatingHomeState.gentleWait,
          opensAt: DateTime.utc(2026, 12, 1, 10),
        ),
      ),
      extraRoutes: [_slotRoute],
    );
    expect(find.text('Dating is locked'), findsOneWidget);
    // No PIN on this phone yet: the slot's confirm lets it through.
    await tapInReach(t, find.text('Dating is locked'));
    await t.pumpAndSettle();
    expect(s.container.read(datingUnlockedProvider), isTrue);
    // From now on a PIN exists: any second ask would show its sheet.
    await const FlutterSecureStorage().write(
      key: 'safety_pin_hash',
      value: r'v1$c2FsdA$aGFzaA$100000',
    );
    await tapInReach(t, find.text('Before you begin'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('gentle_wait_q3')), findsOneWidget);
    expect(find.text('Enter your Safety PIN'), findsNothing);
    expect(find.text('Enter my PIN'), findsNothing);
    expect(s.location, isNot(startsWith(DatingPaths.unlock)));
  });

  testWidgets('M-2: dismissing the PIN sheet stays on the PIN screen', (
    t,
  ) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('wait'),
      locked: true,
      pinSet: true,
    );
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    await tapInReach(t, find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Enter your Safety PIN'), findsNothing);
    expect(s.location, startsWith('/dating/unlock?from='));
    expect(find.text('Enter my PIN'), findsOneWidget);
    expect(find.byKey(const ValueKey('gentle_wait_q3')), findsNothing);
    expect(s.container.read(datingUnlockedProvider), isFalse);
    // Asking again shows the sheet again (the button's busy spinner turns
    // while it is open, so no settle here).
    await tapInReach(t, find.text('Enter my PIN'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
  });

  testWidgets('M-2: Back on the PIN screen goes to Me, still locked', (
    t,
  ) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('wait'),
      locked: true,
      pinSet: true,
    );
    await tapInReach(t, find.text('Cancel'));
    await t.pumpAndSettle();
    await tapInReach(t, find.byTooltip('Back'));
    await t.pumpAndSettle();
    expect(find.text('ME me'), findsOneWidget);
    expect(s.location, startsWith('/home?tab=me'));
    expect(s.container.read(datingUnlockedProvider), isFalse);
  });
}
