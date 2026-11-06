// Spec 1 W10b (§2.3): right to left, the screen mirrors but a phone number
// or an invite code is still typed and shown left to right inside its box.
// In a right-to-left field, groups separated by spaces would show in
// reverse order ("024 412 3456" as "3456 412 024", "AB2 3CD" as "3CD AB2").
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/invite_landing_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/phone_step.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate_v2.dart';
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';
import 'package:attune/features/relationships/presentation/screens/join_invite_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_home_state.dart';
import '../../helpers/fake_invites.dart';
import '../../helpers/fake_push_asker.dart';
import '../../helpers/fake_share_actions.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';

final _ghana = PhoneCountries.all.firstWhere((c) => c.isoCode == 'GH');

/// The one text field on screen reads left to right, its hint too, while
/// the screen around it follows [direction].
void _expectLeftToRight(WidgetTester t, TextDirection direction) {
  final field = find.byType(EditableText);
  expect(Directionality.of(t.element(field)), direction);
  expect(
    t.state<EditableTextState>(field).renderEditable.textDirection,
    TextDirection.ltr,
  );
  expect(
    t.widget<TextField>(find.byType(TextField)).decoration?.hintTextDirection,
    TextDirection.ltr,
    reason: 'the hint, before anything is typed',
  );
}

final _screens = <String, (Widget Function(), List<Override>)>{
  'the phone number (A3)': (
    () => PhoneStep(
      initialCountry: _ghana,
      initialNational: '24 412 3456',
      onSend: (_, __) {},
      onBack: () {},
    ),
    const [],
  ),
  // B7 review M-2: the three invite-code fields.
  'the invite code before sign-up (RI-2)': (
    () => const InviteLandingScreen(),
    const [],
  ),
  'the invite code in onboarding (InviteCodeStep)': (
    () => InviteCodeStep(onSubmit: (_) async {}, onBack: () {}, errorCount: 0),
    const [],
  ),
  'the invite code signed in (JoinInviteScreen)': (
    () => JoinInviteScreen(
      onDone: () {},
      onJoined: () {},
      onChooseAnotherWay: (_) {},
      onNeedsAccount: () {},
    ),
    [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-rtl'))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(
          FakeHomeStateGateway(state: homeJson(path: null, needs: ['path'])),
        ),
      ),
      invitePartnerServiceProvider.overrideWithValue(FakeInvites()),
      inviteShareActionsProvider.overrideWithValue(
        FakeShareActions(whatsApp: true),
      ),
      pushAskerProvider.overrideWithValue(FakePushAsker()),
      coupleNameProvider.overrideWith((ref, id) async => null),
    ],
  ),
};

void main() {
  for (final MapEntry(key: name, value: (screen, overrides))
      in _screens.entries) {
    for (final direction in TextDirection.values) {
      testWidgets('$name reads left to right ($direction)', (t) async {
        await pumpFlowScreen(
          t,
          screen,
          direction: direction,
          overrides: overrides,
        );
        _expectLeftToRight(t, direction);
      });
    }
  }
}
