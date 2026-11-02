// Spec 1 W4b (batch 4, beyond the brief): R1's name label is long. At the
// largest text size it sits above the field and wraps there, never over
// the field's border; the field is still named by it.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/fake_share_actions.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _label = 'Their first name (optional)';

void main() {
  for (final named in [false, true]) {
    testWidgets('at 2.0 the name label never overlaps the field '
        '(${named ? 'a name typed' : 'empty'})', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpFlowScreen(
        tester,
        () => InvitePartnerScreen(onDone: () {}, onAlreadyInvited: () {}),
        textScale: 2.0,
        size: const Size(390, 2400),
        overrides: [
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-r1'))),
          homeStateServiceProvider.overrideWithValue(
            HomeStateService(
              FakeHomeStateGateway(state: homeJson(path: 'relationship')),
            ),
          ),
          invitePartnerServiceProvider.overrideWithValue(FakeInvites()),
          inviteShareActionsProvider.overrideWithValue(FakeShareActions()),
          pushAskerProvider.overrideWithValue(FakePushAsker()),
          flowCouplesV2Provider.overrideWithValue(true),
        ],
      );
      if (named) {
        await tester.enterText(find.byType(TextField), 'Ama');
        await tester.pumpAndSettle();
      }
      final label = tester.getRect(find.text(_label));
      final box = tester.getRect(find.byType(InputDecorator));
      expect(
        label.bottom,
        lessThanOrEqualTo(box.top),
        reason: 'label $label, field $box',
      );
      expect(
        tester.getSemantics(find.byType(TextField)),
        containsSemantics(label: _label, isTextField: true),
      );
      semantics.dispose();
    });
  }
}
