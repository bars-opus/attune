// Spec 1 W10b (§2.3): the Spec 1 sheets that had no goldens yet, at 1.0,
// 1.3, 2.0 and right to left: "More ways to use Attune" (J4) and the
// path-switch sheet (Dating -> Just for me); batch 7 review M-3: R1's QR
// sheet, About us's "More about this", its "reminder will stop" question
// and the anniversary reminder's About us sheet. "Cancel your invite?" has
// its goldens as FlowConfirmSheet (flow_confirm, onboarding_gate_v2_test).
//   flutter test --update-goldens test/accessibility/w10/spec1_rtl_goldens_test.dart
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/presentation/about_us_entry.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_question_flow.dart';
import 'package:attune/features/me/presentation/me_providers.dart';
import 'package:attune/features/me/presentation/path_switch.dart';
import 'package:attune/features/me/presentation/screens/me_home_screen.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_couple_profile.dart';
import '../../helpers/fake_home_state.dart';
import '../../helpers/fake_invites.dart';
import '../../helpers/fake_push_asker.dart';
import '../../helpers/fake_share_actions.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';
import '../../helpers/tap_in_reach.dart';

Future<void> _variants(
  WidgetTester t,
  String name,
  Future<void> Function(double scale, TextDirection direction) pumpAndOpen,
) async {
  for (final (variant, scale, direction) in flowGoldenVariants) {
    await pumpAndOpen(scale, direction);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.$variant.png'),
    );
    expect(t.takeException(), isNull, reason: '$name at $variant');
  }
}

List<Override> _aboutUs(FakeCoupleProfileServer server) => [
  coupleProfileEnabledProvider.overrideWithValue(true),
  coupleProfileRpcProvider.overrideWithValue(server.rpc),
  homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-rtl'))),
  togetherChangeSignalProvider.overrideWith((ref, id) => const Stream.empty()),
];

Widget _aboutUsFlow(AboutUsTarget target, {AboutUsQuestion? only}) =>
    AboutUsQuestionFlow(
      target: target,
      only: only,
      partnerName: 'Ama',
      now: () => DateTime(2026, 11, 2, 10),
      onDone: () {},
    );

void main() {
  testWidgets('J4 "More ways to use Attune" on the Dating path', (t) async {
    await _variants(t, 'j4_more_ways', (scale, direction) async {
      await t.pumpWidget(const SizedBox());
      final home = homeJson(path: 'dating');
      await pumpFlowScreen(
        t,
        () => MeHomeScreen(home: snapshotOf(home)),
        textScale: scale,
        direction: direction,
        size: const Size(390, 1600),
        overrides: [
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-rtl'))),
          homeStateServiceProvider.overrideWithValue(
            HomeStateService(FakeHomeStateGateway(state: home)),
          ),
          relationshipLifecycleProvider.overrideWith((ref) async => null),
          firstActionInputsProvider.overrideWithValue((
            hasNote: true,
            hasQuiz: true,
          )),
        ],
      );
      await tapInReach(t, find.text('More ways to use Attune'));
      await t.pumpAndSettle();
    });
  });

  for (final (name, from, to) in [
    ('switch_dating_to_just_me', homeJson(path: 'dating'), AppPath.justMe),
  ]) {
    testWidgets('path switch sheet: $name', (t) async {
      await _variants(t, name, (scale, direction) async {
        await t.pumpWidget(const SizedBox());
        final home = snapshotOf(from);
        await pumpFlowScreen(
          t,
          () => Consumer(
            builder:
                (context, ref, _) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed:
                          () => switchPath(context, ref, to: to, home: home),
                      child: const Text('SWITCH'),
                    ),
                  ),
                ),
          ),
          textScale: scale,
          direction: direction,
          overrides: [
            homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-rtl'))),
            homeStateServiceProvider.overrideWithValue(
              HomeStateService(FakeHomeStateGateway(state: from)),
            ),
          ],
        );
        await tapInReach(t, find.text('SWITCH'));
        await t.pumpAndSettle();
      });
    });
  }
  // Batch 7 review M-3: the four custom sheets.
  testWidgets('R1 QR sheet', (t) async {
    await _variants(t, 'r1_qr_sheet', (scale, direction) async {
      await t.pumpWidget(const SizedBox());
      await pumpFlowScreen(
        t,
        () => InvitePartnerScreen(onDone: () {}, onAlreadyInvited: () {}),
        textScale: scale,
        direction: direction,
        overrides: [
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-rtl'))),
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
      await tapInReach(t, find.text('Show QR code'));
      await t.pumpAndSettle();
    });
  });

  testWidgets('About us "More about this" sheet', (t) async {
    await _variants(t, 'about_us_more_about', (scale, direction) async {
      await t.pumpWidget(const SizedBox());
      await pumpFlowScreen(
        t,
        () => _aboutUsFlow(const AboutUsTarget.draft()),
        textScale: scale,
        direction: direction,
        overrides: _aboutUs(FakeCoupleProfileServer()),
      );
      await tapInReach(t, find.text('More about this'));
      await t.pumpAndSettle();
    });
  });

  testWidgets('About us "Your anniversary reminder will stop" sheet', (
    t,
  ) async {
    await _variants(t, 'about_us_reminder_stop', (scale, direction) async {
      await t.pumpWidget(const SizedBox());
      final server = FakeCoupleProfileServer(
        profiles: {
          'rel-rtl': aboutUsJson(
            stage: 'married',
            ceremonies: [
              {'year': 1999, 'label': 'customary'},
              {'year': 2004, 'month': 8, 'day': 14, 'label': 'church'},
            ],
            anniversary: 'ceremony_2',
          ),
        },
      );
      await pumpFlowScreen(
        t,
        () => _aboutUsFlow(
          const AboutUsTarget.shared('rel-rtl'),
          only: AboutUsQuestion.married,
        ),
        textScale: scale,
        direction: direction,
        overrides: _aboutUs(server),
      );
      await tapInReach(t, find.text('Remove this ceremony'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Your anniversary reminder will stop'), findsOneWidget);
    });
  });

  testWidgets('the anniversary reminder\'s About us sheet', (t) async {
    await _variants(t, 'about_us_reminder_sheet', (scale, direction) async {
      await t.pumpWidget(const SizedBox());
      final server = FakeCoupleProfileServer(
        profiles: {
          'r1': aboutUsJson(
            togetherSince: '2016-03-12',
            precision: 'day',
            anniversary: 'together_since',
            reminderId: 'rem-about-us',
          ),
        },
      );
      await pumpFlowScreen(
        t,
        () => Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showAboutUsReminderLink(
                        context,
                        reminderId: 'rem-about-us',
                        relationshipId: 'r1',
                        reminderType: 'anniversary',
                        title: 'Anniversary',
                      ),
                  child: const Text('open reminder'),
                ),
          ),
        ),
        textScale: scale,
        direction: direction,
        overrides: _aboutUs(server),
      );
      await tapInReach(t, find.text('open reminder'));
      await t.pumpAndSettle();
    });
  });
}
