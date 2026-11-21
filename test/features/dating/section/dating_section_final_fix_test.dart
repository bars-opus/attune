// Spec 2 W6 final client fix wave (C-1, T4 re-review N-1; M-10): the
// active and paused section cards space Conversations as every other
// button (Spacing.sm, not twice that), and the active card has goldens.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

Widget _screen() => const Scaffold(
  body: SingleChildScrollView(
    padding: EdgeInsets.all(16),
    child: DatingSection(),
  ),
);

List<Override> _overrides(DatingHome home) => [
  ...datingShellOverrides(home: FakeDatingHomeGateway(home: home)),
  homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
  homeStateServiceProvider.overrideWithValue(
    HomeStateService(FakeHomeStateGateway(state: homeJson(path: 'dating'))),
  ),
];

const _active = DatingHome(state: DatingHomeState.active);
const _paused = DatingHome(state: DatingHomeState.paused, canResume: true);

void main() {
  final loc = AppLocalizationsEn();

  Rect button(WidgetTester t, String label) => t.getRect(
    find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
        (w) => w is FlowPrimaryButton || w is FlowSecondaryButton,
      ),
    ),
  );

  for (final (name, home, above) in [
    ('active', _active, loc.dating_sectionOpenToday),
    ('paused', _paused, loc.dating_resume),
  ]) {
    testWidgets('C-1 $name: Conversations sits Spacing.sm under the button '
        'above it', (t) async {
      await pumpFlowScreen(t, _screen, overrides: _overrides(home));
      expect(find.text(loc.dating_chatsTitle), findsOneWidget);
      final gap =
          button(t, loc.dating_chatsTitle).top - button(t, above).bottom;
      expect(gap, Spacing.sm);
    });
  }

  testWidgets('M-10: section_active goldens', (t) async {
    await expectFlowGoldens(
      t,
      'section_active',
      _screen,
      overrides: _overrides(_active),
    );
  });
}
