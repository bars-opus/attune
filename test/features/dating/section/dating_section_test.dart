// Spec 2 W3a (§3.1, §3.15; carries 1, 3, 8, 9, 13; D8): every home state
// has its card; resume's refusals have their own words; nothing of one
// account reaches the next.
import 'dart:async';

import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

Widget _screen() => const Scaffold(
  body: SingleChildScrollView(
    padding: EdgeInsets.all(16),
    child: DatingSection(),
  ),
);

class _Pumped {
  _Pumped(this.harness, this.home, this.life, this.spec1);
  final FlowHarness harness;
  final FakeDatingHomeGateway home;
  final FakeDatingLifecycleGateway life;
  final FakeHomeStateGateway spec1;
}

Future<_Pumped> _pump(
  WidgetTester t,
  DatingHome state, {
  bool online = true,
}) async {
  await t.pumpWidget(const SizedBox());
  final home = FakeDatingHomeGateway(home: state);
  final life = FakeDatingLifecycleGateway();
  final spec1 = FakeHomeStateGateway(state: homeJson(path: 'dating'));
  final h = await pumpFlowScreen(
    t,
    _screen,
    overrides: [
      ...datingShellOverrides(home: home, life: life, online: online),
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
      homeStateServiceProvider.overrideWithValue(HomeStateService(spec1)),
    ],
  );
  return _Pumped(h, home, life, spec1);
}

void main() {
  final cases = <String, (DatingHome, List<String>)>{
    'feature_unavailable': (
      const DatingHome(
        state: DatingHomeState.featureUnavailable,
        country: 'NG',
        notice: DatingNotice(available: true),
      ),
      ["Dating isn't open in Nigeria yet.", "Tell me when it's here"],
    ),
    'country_closed, already asked': (
      const DatingHome(
        state: DatingHomeState.countryClosed,
        country: 'NG',
        notice: DatingNotice(available: true, requested: true),
      ),
      [
        "We'll let you know. You can turn this off in Settings.",
        'Dating settings',
      ],
    ),
    'region_closed': (
      const DatingHome(
        state: DatingHomeState.regionClosed,
        country: 'GH',
        region: 'TV',
        openRegions: ['AA', 'AH'],
        notice: DatingNotice(available: true),
      ),
      [
        'Dating is open in Greater Accra and Ashanti for now.',
        "Tell me when it's open in Volta",
      ],
    ),
    'not_started': (
      const DatingHome(state: DatingHomeState.notStarted),
      [
        "Meet a few people a day. Only when it's mutual.",
        'Set up Dating',
        'Not ready? Use Attune just for me',
      ],
    ),
    'setup_in_progress': (
      const DatingHome(
        state: DatingHomeState.setupInProgress,
        nextStep: 'where',
      ),
      ['Finish setting up Dating', 'Dating settings'],
    ),
    'active': (
      const DatingHome(state: DatingHomeState.active),
      ['Dating is on. Your introductions will show here.'],
    ),
    'reverify_device': (
      const DatingHome(state: DatingHomeState.reverifyDevice),
      ["Confirm it's you on this phone to see Dating."],
    ),
    'restricted': (
      const DatingHome(state: DatingHomeState.restricted),
      ['Your Dating account is restricted. The rest of Attune works as usual.'],
    ),
    'hold': (
      const DatingHome(state: DatingHomeState.hold),
      [
        "Your Dating profile is paused while we look into something. This "
            "isn't a decision yet.",
      ],
    ),
    'age_review': (
      const DatingHome(state: DatingHomeState.ageReview),
      ['We need to confirm your age before you can use Dating.'],
    ),
    'unavailable': (
      const DatingHome(state: DatingHomeState.unavailable),
      ["Dating isn't available on this account right now."],
    ),
    'paused, no reason (carry 9)': (
      const DatingHome(state: DatingHomeState.paused),
      ['Dating is paused. Nobody new sees you.', 'Resume'],
    ),
    'paused by a shared space': (
      const DatingHome(
        state: DatingHomeState.paused,
        pauseReason: DatingPauseReason.relationship,
      ),
      ['Dating is paused while you have a shared space on Attune.'],
    ),
    'paused by the country switch': (
      const DatingHome(
        state: DatingHomeState.paused,
        pauseReason: DatingPauseReason.sameGenderSwitch,
        country: 'GH',
      ),
      [
        "Introductions between people of the same gender aren't available in "
            "Ghana now. We've removed that choice from your profile.",
        'Why?',
        'Choose again',
      ],
    ),
  };
  for (final MapEntry(key: name, value: (home, texts)) in cases.entries) {
    testWidgets('$name: its card', (t) async {
      await _pump(t, home);
      for (final text in texts) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });
  }

  // C-2: whenever there is Dating data, every card links to Dating
  // settings (Leave, Clear), restricted, held and unavailable included.
  for (final state in DatingHomeState.values) {
    testWidgets('C-2: ${state.wire} with Dating data links to settings', (
      t,
    ) async {
      await _pump(
        t,
        DatingHome(state: state, hasData: true, country: 'NG', region: 'TV'),
      );
      await tapInReach(t, find.text('Dating settings'));
      await t.pumpAndSettle();
      expect(find.text('at /dating/settings'), findsOneWidget);
    });
  }

  testWidgets('C-2: no Dating data, no settings link', (t) async {
    await _pump(t, const DatingHome(state: DatingHomeState.notStarted));
    expect(find.text('Dating settings'), findsNothing);
    await _pump(t, const DatingHome(state: DatingHomeState.restricted));
    expect(find.text('Dating settings'), findsNothing);
  });

  testWidgets('a shared-space pause offers no Resume', (t) async {
    await _pump(
      t,
      const DatingHome(
        state: DatingHomeState.paused,
        pauseReason: DatingPauseReason.relationship,
      ),
    );
    expect(find.text('Resume'), findsNothing);
  });

  testWidgets('cool-off: the first drop in full words, local time', (t) async {
    final at = DateTime.utc(2026, 11, 12, 19);
    await _pump(t, DatingHome(state: DatingHomeState.coolOff, firstDropAt: at));
    // Fix round 1 (Minor 8): the exact words, through MyDateFormat, in
    // local time.
    final local = at.toLocal();
    expect(
      find.text(
        'Your first introductions arrive ${MyDateFormat.toDate(local)} '
        'at ${MyDateFormat.toTime(local)}.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('carry 8: the wait card never promises a shorter wait', (
    t,
  ) async {
    await _pump(
      t,
      DatingHome(
        state: DatingHomeState.gentleWait,
        opensAt: DateTime.utc(2026, 12, 1, 10),
        canShorten: true,
      ),
    );
    expect(find.textContaining('Dating opens for you on'), findsOneWidget);
    expect(find.textContaining('sooner'), findsNothing);
    await tapInReach(t, find.text('Before you begin'));
    await t.pumpAndSettle();
    expect(find.text('at /dating/setup/wait'), findsOneWidget);
  });

  testWidgets('Set up Dating opens D1; Finish opens the saved step', (t) async {
    await _pump(t, const DatingHome(state: DatingHomeState.notStarted));
    await tapInReach(t, find.text('Set up Dating'));
    await t.pumpAndSettle();
    expect(find.text('at /dating/setup/how'), findsOneWidget);
    await _pump(
      t,
      const DatingHome(
        state: DatingHomeState.setupInProgress,
        nextStep: 'faith',
      ),
    );
    await tapInReach(t, find.text('Finish setting up Dating'));
    await t.pumpAndSettle();
    expect(find.text('at /dating/setup/faith'), findsOneWidget);
  });

  testWidgets('Tell me when it\'s here asks once, then says so', (t) async {
    final p = await _pump(
      t,
      const DatingHome(
        state: DatingHomeState.countryClosed,
        country: 'NG',
        notice: DatingNotice(available: true),
      ),
    );
    await tapInReach(t, find.text("Tell me when it's here"));
    await t.pumpAndSettle();
    expect(p.home.requests, [('NG', null)]);
    expect(
      find.text("We'll let you know. You can turn this off in Settings."),
      findsOneWidget,
    );
  });

  testWidgets('R-5: Dating off where the country is open: no Tell me', (
    t,
  ) async {
    await _pump(
      t,
      const DatingHome(
        state: DatingHomeState.featureUnavailable,
        country: 'GH',
        notice: DatingNotice(available: false),
      ),
    );
    expect(find.text("Tell me when it's here"), findsNothing);
  });

  testWidgets('a region: the request names it', (t) async {
    final p = await _pump(
      t,
      const DatingHome(
        state: DatingHomeState.regionClosed,
        country: 'GH',
        region: 'TV',
        openRegions: ['AA', 'AH'],
        notice: DatingNotice(available: true),
      ),
    );
    await tapInReach(t, find.text("Tell me when it's open in Volta"));
    await t.pumpAndSettle();
    expect(p.home.requests, [('GH', 'TV')]);
  });

  testWidgets('Resume: one call, one key, then the home again', (t) async {
    final p = await _pump(t, const DatingHome(state: DatingHomeState.paused));
    final reads = p.home.reads;
    p.home.home = const DatingHome(state: DatingHomeState.active);
    await tapInReach(t, find.text('Resume'));
    await t.pumpAndSettle();
    expect(p.life.calls, ['resume']);
    expect(p.home.reads, reads + 1);
    expect(
      find.text('Dating is on. Your introductions will show here.'),
      findsOneWidget,
    );
  });

  for (final (error, text) in [
    (
      DatingLifecycleError.pathNotDating,
      'Choose Dating in How you use Attune to carry on.',
    ),
    (
      DatingLifecycleError.resumeGatesNotMet,
      "Dating can't resume on this account right now.",
    ),
    (
      DatingLifecycleError.consentRequired,
      "Agree to Dating's terms again to carry on.",
    ),
    (DatingLifecycleError.profileIncomplete, 'Finish setting up Dating first.'),
    (
      DatingLifecycleError.busy,
      'This is taking a little longer than usual. Try again in a moment.',
    ),
  ]) {
    testWidgets('Resume refused (${error.name}): its own words', (t) async {
      final p = await _pump(t, const DatingHome(state: DatingHomeState.paused));
      p.life.result = DatingLifecycleResult.refused(error);
      await tapInReach(t, find.text('Resume'));
      await t.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      expect(find.text('Something went wrong. Try again.'), findsNothing);
    });
  }

  testWidgets('pathNotDating links to How you use Attune', (t) async {
    final p = await _pump(t, const DatingHome(state: DatingHomeState.paused));
    p.life.result = const DatingLifecycleResult.refused(
      DatingLifecycleError.pathNotDating,
    );
    await tapInReach(t, find.text('Resume'));
    await t.pumpAndSettle();
    await tapInReach(t, find.text('How you use Attune'));
    await t.pumpAndSettle();
    expect(find.text('at /settings/how-you-use-attune'), findsOneWidget);
  });

  testWidgets(
    'the kill-switch note: Why? calls nothing; Choose again opens D5',
    (t) async {
      final p = await _pump(
        t,
        const DatingHome(
          state: DatingHomeState.paused,
          pauseReason: DatingPauseReason.sameGenderSwitch,
          country: 'GH',
        ),
      );
      final reads = p.home.reads;
      await tapInReach(t, find.text('Why?'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('In Ghana, relationships between people'),
        findsOneWidget,
      );
      expect(p.home.reads, reads);
      expect(p.life.calls, isEmpty);
      await tapInReach(t, find.text('Close'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Choose again'));
      await t.pumpAndSettle();
      // Final fix (M-8): D5 knows to go on to D6, then back to Me.
      expect(find.text('at /dating/setup/you?from=section'), findsOneWidget);
    },
  );

  testWidgets('"Not ready?" is one tap to Just for me', (t) async {
    final p = await _pump(
      t,
      const DatingHome(state: DatingHomeState.notStarted),
    );
    await tapInReach(t, find.text('Not ready? Use Attune just for me'));
    await t.pumpAndSettle();
    expect(p.spec1.count('set_my_path'), 1);
  });

  testWidgets('a failed refresh never shows the last state', (t) async {
    final p = await _pump(t, const DatingHome(state: DatingHomeState.active));
    expect(
      find.text('Dating is on. Your introductions will show here.'),
      findsOneWidget,
    );
    p.home.readError = Exception('down');
    ProviderScope.containerOf(
      t.element(find.byType(DatingSection)),
    ).invalidate(datingHomeProvider);
    await t.pumpAndSettle();
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    expect(
      find.text('Dating is on. Your introductions will show here.'),
      findsNothing,
    );
  });

  testWidgets('D8: a Resume refusal for one account is not shown to the '
      'next', (t) async {
    final p = await _pump(t, const DatingHome(state: DatingHomeState.paused));
    p.life.result = const DatingLifecycleResult.refused(
      DatingLifecycleError.rateLimited,
    );
    await tapInReach(t, find.text('Resume'));
    await t.pumpAndSettle();
    const refusal = "You've done this a lot today. Try again tomorrow.";
    expect(find.text(refusal), findsOneWidget);
    ProviderScope.containerOf(t.element(find.byType(DatingSection)))
        .read(datingTestAccount.notifier)
        .state = 'kofi';
    await t.pumpAndSettle();
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text(refusal), findsNothing);
  });

  testWidgets('a failed read: the error and Retry; offline: says so', (
    t,
  ) async {
    await t.pumpWidget(const SizedBox());
    final home = FakeDatingHomeGateway()..readError = Exception('down');
    await pumpFlowScreen(
      t,
      _screen,
      overrides: datingShellOverrides(home: home),
    );
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    home.readError = null;
    await tapInReach(t, find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('Set up Dating'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    final off = FakeDatingHomeGateway()..readError = Exception('offline');
    await pumpFlowScreen(
      t,
      _screen,
      overrides: datingShellOverrides(home: off, online: false),
    );
    expect(
      find.text("You're offline. Dating needs a connection."),
      findsOneWidget,
    );
  });

  testWidgets('D8: the next account sees nothing of the last one, also while '
      'its read is held', (t) async {
    final p = await _pump(t, const DatingHome(state: DatingHomeState.active));
    expect(
      find.text('Dating is on. Your introductions will show here.'),
      findsOneWidget,
    );
    p.home.hold = Completer<DatingHome>();
    ProviderScope.containerOf(t.element(find.byType(DatingSection)))
        .read(datingTestAccount.notifier)
        .state = 'kofi';
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 40));
      expect(
        find.text('Dating is on. Your introductions will show here.'),
        findsNothing,
      );
    }
    p.home.hold!.complete(const DatingHome(state: DatingHomeState.notStarted));
    await t.pumpAndSettle();
    expect(find.text('Set up Dating'), findsOneWidget);
  });

  testWidgets('a semantic region "Dating"; guidelines', (t) async {
    final semantics = t.ensureSemantics();
    await _pump(t, const DatingHome(state: DatingHomeState.notStarted));
    expect(find.bySemanticsLabel('Dating'), findsWidgets);
    await expectFlowGuidelines(t);
    semantics.dispose();
  });

  for (final (name, home) in [
    (
      'section_not_started',
      const DatingHome(state: DatingHomeState.notStarted),
    ),
    (
      'section_region_closed',
      const DatingHome(
        state: DatingHomeState.regionClosed,
        country: 'GH',
        region: 'TV',
        openRegions: ['AA', 'AH'],
        notice: DatingNotice(available: true),
      ),
    ),
    ('section_paused', const DatingHome(state: DatingHomeState.paused)),
  ]) {
    testWidgets('$name goldens', (t) async {
      await expectFlowGoldens(
        t,
        name,
        _screen,
        overrides: [
          ...datingShellOverrides(home: FakeDatingHomeGateway(home: home)),
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
          homeStateServiceProvider.overrideWithValue(
            HomeStateService(
              FakeHomeStateGateway(state: homeJson(path: 'dating')),
            ),
          ),
        ],
      );
    });
  }
}
