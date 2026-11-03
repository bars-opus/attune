// Spec 1 W5 (§3.8 R3): the About us card sits in R3's pending state only
// ("never before an invite exists"), names the partner R1 typed on this
// phone, and is absent with couple_profile off.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/relationships/presentation/screens/relationship_space_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-r3-about';

Future<void> _pump(
  WidgetTester tester, {
  required String link,
  required bool aboutUs,
}) async {
  await tester.pumpWidget(const SizedBox());
  await pumpFlowScreen(
    tester,
    () => RelationshipSpaceScreen(
      home: snapshotOf(homeJson(path: 'relationship', link: link)),
    ),
    size: const Size(390, 2600),
    prefsValues: {'attune.flow.$_uid.partner_first_name': 'Ama'},
    overrides: [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(
          FakeHomeStateGateway(state: homeJson(path: 'relationship')),
        ),
      ),
      invitePartnerServiceProvider.overrideWithValue(FakeInvites()),
      relationshipLifecycleProvider.overrideWith((ref) async => null),
      pushAskerProvider.overrideWithValue(FakePushAsker()),
      flowCouplesV2Provider.overrideWithValue(true),
      coupleProfileEnabledProvider.overrideWithValue(aboutUs),
    ],
  );
}

void main() {
  const body =
      'A few easy questions about you two. Skip any of them. Ama sees your answers after joining.';

  testWidgets('pending: the card, the partner named', (tester) async {
    await _pump(tester, link: 'pending', aboutUs: true);
    expect(find.text(body), findsOneWidget);
  });

  testWidgets('never before an invite exists, and never with the flag off', (
    tester,
  ) async {
    await _pump(tester, link: 'none', aboutUs: true);
    expect(find.text(body), findsNothing);
    await _pump(tester, link: 'pending', aboutUs: false);
    expect(find.text(body), findsNothing);
  });
}
