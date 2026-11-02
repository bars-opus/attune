// Spec 1 W3c (§3.8 R2, §2.4): while an invite waits and notifications are
// off, the space offers the heads-up ask in context; once on, it is gone.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/features/me/data/journal_reminder_service.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/relationships/presentation/screens/relationship_space_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_home_state.dart';
import '../../helpers/fake_reminder_rpc.dart';
import '../../helpers/fake_invites.dart';
import '../../helpers/fake_push_asker.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';

Future<(FlowHarness, FakePushAsker)> _pump(
  WidgetTester tester, {
  required bool granted,
  String link = 'pending',
  String? partnerFirstName,
}) async {
  await tester.pumpWidget(const SizedBox());
  final asker = FakePushAsker(granted: granted);
  final h = await pumpFlowScreen(
    tester,
    () => RelationshipSpaceScreen(
      home: snapshotOf(
        homeJson(
          path: 'relationship',
          link: link,
          partnerFirstName: partnerFirstName,
        ),
      ),
    ),
    size: const Size(390, 2400),
    overrides: [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-r2'))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(FakeHomeStateGateway()),
      ),
      invitePartnerServiceProvider.overrideWithValue(FakeInvites()),
      relationshipLifecycleProvider.overrideWith((ref) async => null),
      pushAskerProvider.overrideWithValue(asker),
      journalReminderRpcProvider.overrideWithValue(FakeReminderRpc().call),
    ],
  );
  return (h, asker);
}

void main() {
  testWidgets('pending, notifications off: the R2 ask', (tester) async {
    final (h, asker) = await _pump(tester, granted: false);
    expect(find.text('Get a heads-up when your partner joins'), findsOneWidget);
    await tester.tap(find.text('Turn on').first);
    await tester.pumpAndSettle();
    expect(asker.asked, [PushAskContext.r2]);
    expect(find.text('Get a heads-up when your partner joins'), findsNothing);
    expect(h.metrics, ['push_ask_shown:r2', 'push_ask_granted:r2']);
  });

  testWidgets('notifications on, or no invite: no ask', (tester) async {
    await _pump(tester, granted: true);
    expect(find.text('Get a heads-up when your partner joins'), findsNothing);
    await _pump(tester, granted: false, link: 'none');
    expect(find.text('Get a heads-up when your partner joins'), findsNothing);
  });

  testWidgets('pending with a name: the heads-up names them (R2, M-2)', (
    tester,
  ) async {
    await _pump(tester, granted: false, partnerFirstName: 'Kofi');
    expect(find.text('Get a heads-up when Kofi joins'), findsOneWidget);
    expect(find.text('Get a heads-up when your partner joins'), findsNothing);
  });

  testWidgets('J3 is in the space too', (tester) async {
    await _pump(tester, granted: true);
    expect(find.text('Remind me to write'), findsOneWidget);
  });
}
