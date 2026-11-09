// Spec 2 W3a Task 4 fix round 1: a relationship pause read after the space
// ended can resume (I-2, can_resume); every pause reason has its card and
// its Resume rule; the no-date wait; Tell me refreshes the home and asks
// once; reduce motion fades at 150 ms.
import 'dart:async';

import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

const _plainPaused = 'Dating is paused. Nobody new sees you.';
const _spaceOpen = 'Dating is paused while you have a shared space on Attune.';

Widget _screen() => const Scaffold(
  body: SingleChildScrollView(
    padding: EdgeInsets.all(16),
    child: DatingSection(),
  ),
);

Future<(FakeDatingHomeGateway, FakeDatingLifecycleGateway)> _pump(
  WidgetTester t,
  DatingHome state, {
  bool reduceMotion = false,
}) async {
  await t.pumpWidget(const SizedBox());
  final home = FakeDatingHomeGateway(home: state);
  final life = FakeDatingLifecycleGateway();
  await pumpFlowScreen(
    t,
    _screen,
    reduceMotion: reduceMotion,
    overrides: [
      ...datingShellOverrides(home: home, life: life),
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(FakeHomeStateGateway(state: homeJson(path: 'dating'))),
      ),
    ],
  );
  return (home, life);
}

void main() {
  test('I-2: can_resume is read as the server says it, absent is null', () {
    for (final (raw, want) in [(true, true), (false, false), ('x', null)]) {
      final h = DatingHome.fromJson({'state': 'paused', 'can_resume': raw});
      expect(h.canResume, want, reason: '$raw');
    }
    expect(DatingHome.fromJson({'state': 'paused'}).canResume, isNull);
  });

  group('I-2: a relationship pause', () {
    testWidgets('the space has ended (can_resume): plain paused, and Resume '
        'works', (t) async {
      final (home, life) = await _pump(
        t,
        const DatingHome(
          state: DatingHomeState.paused,
          pauseReason: DatingPauseReason.relationship,
          canResume: true,
        ),
      );
      expect(find.text(_plainPaused), findsOneWidget);
      expect(find.text(_spaceOpen), findsNothing);
      home.home = const DatingHome(state: DatingHomeState.active);
      await tapInReach(t, find.text('Resume'));
      await t.pumpAndSettle();
      expect(life.calls, ['resume']);
      expect(
        find.text('Dating is on. Your introductions will show here.'),
        findsOneWidget,
      );
    });

    testWidgets('the space is open (can_resume false): says so, no Resume', (
      t,
    ) async {
      await _pump(
        t,
        const DatingHome(
          state: DatingHomeState.paused,
          pauseReason: DatingPauseReason.relationship,
          canResume: false,
        ),
      );
      expect(find.text(_spaceOpen), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
    });

    testWidgets('any reason while a space is open: no Resume', (t) async {
      await _pump(
        t,
        const DatingHome(
          state: DatingHomeState.paused,
          pauseReason: DatingPauseReason.user,
          canResume: false,
        ),
      );
      expect(find.text(_plainPaused), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
    });
  });

  for (final (reason, line, resume) in [
    (DatingPauseReason.user, _plainPaused, true),
    (DatingPauseReason.gates, _plainPaused, true),
    (DatingPauseReason.pathChange, _plainPaused, true),
    (DatingPauseReason.away, "Dating is hidden while you're away.", false),
    (DatingPauseReason.accountParked, _plainPaused, false),
  ]) {
    testWidgets('paused (${reason.name}): its line; Resume $resume', (t) async {
      await _pump(
        t,
        DatingHome(
          state: DatingHomeState.paused,
          pauseReason: reason,
          canResume: true,
        ),
      );
      expect(find.text(line), findsOneWidget);
      expect(find.text('Resume'), resume ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('gentle wait with no date: the no-date line, then D0', (t) async {
    await _pump(t, const DatingHome(state: DatingHomeState.gentleWait));
    expect(find.text('Dating opens for you after a pause.'), findsOneWidget);
    await tapInReach(t, find.text('Before you begin'));
    await t.pumpAndSettle();
    expect(find.text('at /dating/setup/wait'), findsOneWidget);
  });

  testWidgets('Minor 1: Tell me saved re-reads the home (the settings link '
      'follows has_data)', (t) async {
    final (home, _) = await _pump(
      t,
      const DatingHome(
        state: DatingHomeState.countryClosed,
        country: 'NG',
        notice: DatingNotice(available: true),
      ),
    );
    final reads = home.reads;
    expect(find.text('Dating settings'), findsNothing);
    home.home = const DatingHome(
      state: DatingHomeState.countryClosed,
      country: 'NG',
      hasData: true,
      notice: DatingNotice(available: true, requested: true),
    );
    await tapInReach(t, find.text("Tell me when it's here"));
    await t.pumpAndSettle();
    expect(home.reads, reads + 1);
    expect(find.text('Dating settings'), findsOneWidget);
  });

  testWidgets('Tell me asks once however often it is tapped', (t) async {
    final (home, _) = await _pump(
      t,
      const DatingHome(
        state: DatingHomeState.countryClosed,
        country: 'NG',
        notice: DatingNotice(available: true),
      ),
    );
    home.noticeHold = Completer<void>();
    final button = find.text("Tell me when it's here");
    await tapInReach(t, button);
    await t.pump();
    await t.tap(button, warnIfMissed: false);
    await t.pump();
    home.noticeHold!.complete();
    await t.pumpAndSettle();
    expect(home.requests, [('NG', null)]);
  });

  testWidgets('Minor 4: reduce motion cross-fades in 150 ms, never cuts', (
    t,
  ) async {
    await _pump(
      t,
      const DatingHome(state: DatingHomeState.notStarted),
      reduceMotion: true,
    );
    final switcher = t.widget<AnimatedSwitcher>(
      find.descendant(
        of: find.byType(DatingSection),
        matching: find.byType(AnimatedSwitcher),
      ),
    );
    expect(switcher.duration, kReducedMotionFade);
  });
}
