// Spec 1 W10b (§2.2), batch 7 review I-1 and M-4: motion that follows the
// reading direction and the phone's reduce-motion setting, checked on the
// widgets themselves (the file-level guard in
// test/architecture/spec1_rtl_motion_test.dart cannot tell one read from
// one per animation).
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/features/couple_profile/presentation/widgets/about_us_choice.dart';
import 'package:attune/features/me/data/me_device_store.dart';
import 'package:attune/features/me/presentation/me_providers.dart';
import 'package:attune/features/me/presentation/widgets/first_action_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/path_step.dart';
import 'package:attune/features/relationships/presentation/widgets/linked_moment.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_push_asker.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';

void main() {
  // I-1: R4's two avatars settle toward each other, whichever side each
  // one is on (the Row mirrors right to left; the offsets must too).
  for (final direction in TextDirection.values) {
    testWidgets('R4 avatars settle together ($direction)', (t) async {
      final show = ValueNotifier(false);
      addTearDown(show.dispose);
      await pumpFlowScreen(
        t,
        () => ValueListenableBuilder<bool>(
          valueListenable: show,
          builder:
              (_, shown, __) =>
                  shown
                      ? LinkedMoment(
                        relationshipId: 'r-1',
                        myInitial: 'E',
                        partnerFirstName: 'Yaw',
                        onContinue: () {},
                      )
                      : const SizedBox.shrink(),
        ),
        direction: direction,
        overrides: [
          pushAskerProvider.overrideWithValue(FakePushAsker()),
          coupleNameProvider.overrideWith((ref, id) async => null),
        ],
      );
      List<double> xs() =>
          find
              .byType(CircleAvatar)
              .evaluate()
              .map((e) => t.getCenter(find.byWidget(e.widget)).dx)
              .toList()
            ..sort();
      show.value = true;
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      final moving = xs();
      await t.pumpAndSettle();
      final settled = xs();
      expect(moving, hasLength(2));
      expect(settled, hasLength(2));
      expect(moving.first, lessThan(settled.first), reason: 'left one');
      expect(moving.last, greaterThan(settled.last), reason: 'right one');
    });
  }

  // M-4: the three Spec 1 selection animations stop under reduce motion.
  final selections = <String, (Widget Function(), Finder Function())>{
    'PathChoiceCard': (
      () => Scaffold(
        body: PathChoiceCard(
          title: 'Just for me',
          line: 'A line',
          selected: true,
          onTap: () {},
        ),
      ),
      () => find.descendant(
        of: find.byType(PathChoiceCard),
        matching: find.byType(AnimatedContainer),
      ),
    ),
    'AboutUsChoice': (
      () => Scaffold(
        body: AboutUsChoice(label: 'Yes', selected: true, onTap: () {}),
      ),
      () => find.descendant(
        of: find.byType(AboutUsChoice),
        matching: find.byType(AnimatedContainer),
      ),
    ),
    'FirstActionCard (saved for you)': (
      () => const Scaffold(body: FirstActionCard()),
      () => find.descendant(
        of: find.byType(FirstActionCard),
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
    ),
  };
  for (final MapEntry(key: name, value: (screen, animation))
      in selections.entries) {
    for (final reduce in [false, true]) {
      testWidgets('$name animates ${reduce ? 'not at all' : 'in 150 ms'} '
          'with reduce motion ${reduce ? 'on' : 'off'}', (t) async {
        await pumpFlowScreen(
          t,
          screen,
          reduceMotion: reduce,
          prefsValues: {MeDeviceStore.firstActionKey('u-rm'): 'started'},
          overrides: [
            homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-rm'))),
            firstActionInputsProvider.overrideWithValue((
              hasNote: true,
              hasQuiz: false,
            )),
          ],
        );
        final found = animation();
        expect(found, findsWidgets);
        for (final e in found.evaluate()) {
          final duration = switch (e.widget) {
            AnimatedContainer(:final duration) => duration,
            TweenAnimationBuilder<double>(:final duration) => duration,
            _ => null,
          };
          expect(duration, reduce ? Duration.zero : kSelectionDuration);
        }
      });
    }
  }
}
