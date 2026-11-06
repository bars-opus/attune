// Spec 1 W9e (spec 8 W9e, 6.6, 2.2, 2.3; owner approval O2): when Healing's
// crisis check answers support_offered, the stage shows W9c's card instead
// of any AI text and saves nothing; "See support" opens Support; "Not now"
// puts the card away and the AI text stays hidden this run. paused keeps
// today's path. The state is this account's, in memory only: gone on an
// account change, sign-out and quick exit (D8). "Need support now?" is at
// the end of the reflection, whatever the flags say.
//   flutter test --update-goldens test/features/healing/w9e/healing_support_test.dart
import 'dart:async';

import 'package:attune/app/device_wipes.dart';
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/providers/healing_support_providers.dart';
import 'package:attune/features/healing/presentation/screens/healing_portrait_screen.dart';
import 'package:attune/features/healing/presentation/screens/healing_post_mortem_screen.dart';
import 'package:attune/features/healing/presentation/screens/healing_reflection_screen.dart';
import 'package:attune/features/healing/presentation/widgets/healing_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/flow_harness.dart';
import 'support/healing_fakes.dart';
import '../../../helpers/tap_in_reach.dart';

const _offered = {'status': 'support_offered'};
const _paused = {'status': 'paused'};
const _ready = 'Ready for a grounded reflection on the relationship dynamic?';
const _notEnough =
    'There is not enough information for a grounded reflection yet.';

final _signedIn = StateProvider<String?>((ref) => 'ama');

List<Override> _overrides(
  FakeHealingGeneration gen,
  FakeHealingRepository repo, [
  List<Override> more = const [],
]) => [
  healingGenerationServiceProvider.overrideWithValue(gen),
  healingRepositoryProvider.overrideWithValue(repo),
  healingAccountProvider.overrideWith((ref) => ref.watch(_signedIn)),
  ...more,
];

ProviderContainer _container(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(Scaffold).first));

/// The support state seeded with [key] already offered and hidden.
class _Seeded extends HealingSupport {
  _Seeded(this.key);

  final HealingSupportKey key;

  @override
  HealingSupportState build() {
    super.build();
    return HealingSupportState(offered: {key}, hidden: {key});
  }
}

Widget Function() _postMortem(HealingJourney j) =>
    () => HealingPostMortemScreen(journey: j);

void main() {
  testWidgets(
    'post-mortem: support_offered shows the card, saves nothing, shows no AI text',
    (t) async {
      final gen = FakeHealingGeneration([_offered, _offered]);
      final repo = FakeHealingRepository();
      await pumpFlowScreen(
        t,
        _postMortem(testJourney()),
        overrides: _overrides(gen, repo),
      );
      expect(find.text(_ready), findsOneWidget);
      await tapInReach(t, find.text('Generate reflection'));
      await t.pumpAndSettle();
      expect(gen.calls, ['post_mortem:j1']);
      expect(find.text(supportCardText), findsOneWidget);
      expect(find.text('One pattern that surfaced:'), findsNothing);
      expect(repo.saved, isEmpty); // nothing saved about the match

      await tapInReach(t, find.text('Not now'));
      await t.pumpAndSettle();
      expect(find.text(supportCardText), findsNothing);
      expect(find.text(_ready), findsOneWidget);
      expect(_container(t).read(healingSupportProvider).hidden, {
        (journeyId: 'j1', stage: HealingAiStage.postMortem),
      });

      await t.tap(find.text('Generate reflection'));
      await t.pumpAndSettle();
      expect(find.text(supportCardText), findsOneWidget); // the check again
      expect(repo.saved, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.contains('support')), isEmpty);
    },
  );

  testWidgets('portrait: support_offered shows the card, saves nothing', (
    t,
  ) async {
    final gen = FakeHealingGeneration([_offered]);
    final repo = FakeHealingRepository();
    await pumpFlowScreen(
      t,
      () => HealingPortraitScreen(journey: testJourney(stage: 4)),
      overrides: _overrides(gen, repo),
    );
    await tapInReach(t, find.text('Generate portrait'));
    await t.pumpAndSettle();
    expect(gen.calls, ['portrait:j1']);
    expect(find.text(supportCardText), findsOneWidget);
    expect(find.text('How you show up in relationships:'), findsNothing);
    expect(repo.saved, isEmpty);
  });

  testWidgets('See support opens Support, uncounted', (t) async {
    final h = await pumpFlowScreen(
      t,
      _postMortem(testJourney()),
      overrides: _overrides(
        FakeHealingGeneration([_offered]),
        FakeHealingRepository(),
      ),
    );
    await tapInReach(t, find.text('Generate reflection'));
    await t.pumpAndSettle();
    await tapInReach(t, find.text('See support'));
    await t.pumpAndSettle();
    expect(find.text('at /safety-resources'), findsOneWidget);
    expect(h.metrics, isEmpty);
  });

  testWidgets(
    'paused keeps today\'s path: insufficient_evidence, today\'s words',
    (t) async {
      final repo = FakeHealingRepository();
      await pumpFlowScreen(
        t,
        _postMortem(testJourney()),
        overrides: _overrides(FakeHealingGeneration([_paused]), repo),
      );
      await tapInReach(t, find.text('Generate reflection'));
      await t.pumpAndSettle();
      expect(repo.saved, ['post_mortem:insufficient_evidence']);
      expect(find.text(_notEnough), findsOneWidget);
      // Review Focus 5: the person can still finish the stage.
      expect(find.text('Continue \u2192'), findsOneWidget);
      expect(find.text(supportCardText), findsNothing);
    },
  );

  testWidgets(
    'a later completed answer is shown: written for the words as they are now',
    (t) async {
      final repo = FakeHealingRepository();
      await pumpFlowScreen(
        t,
        _postMortem(testJourney()),
        overrides: _overrides(
          FakeHealingGeneration([
            _offered,
            {
              'status': 'completed',
              'observation': 'A fresh observation.',
              'confidence': 'low',
              'reflection_prompt': null,
            },
          ]),
          repo,
        ),
      );
      await tapInReach(t, find.text('Generate reflection'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Not now'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Generate reflection'));
      await t.pumpAndSettle();
      expect(find.text('A fresh observation.'), findsOneWidget);
      expect(repo.saved, ['post_mortem:completed']);
      expect(_container(t).read(healingSupportProvider).hidden, isEmpty);
    },
  );

  testWidgets(
    'reopened this run: saved AI text the check matched stays hidden, the card shows',
    (t) async {
      const key = (journeyId: 'j1', stage: HealingAiStage.postMortem);
      await pumpFlowScreen(
        t,
        _postMortem(
          testJourney(
            postMortemStatus: 'completed',
            postMortemObservation: 'An older observation.',
          ),
        ),
        overrides: _overrides(
          FakeHealingGeneration([]),
          FakeHealingRepository(),
          [healingSupportProvider.overrideWith(() => _Seeded(key))],
        ),
      );
      expect(find.text('An older observation.'), findsNothing);
      expect(find.text(supportCardText), findsOneWidget);
      await tapInReach(t, find.text('Not now'));
      await t.pumpAndSettle();
      expect(find.text('An older observation.'), findsNothing);
      expect(find.text(_notEnough), findsOneWidget);
      expect(find.text('Continue \u2192'), findsOneWidget);
    },
  );

  testWidgets(
    'a completed stage whose AI text was removed shows as having none',
    (t) async {
      await pumpFlowScreen(
        t,
        _postMortem(testJourney(postMortemStatus: 'completed')),
        overrides: _overrides(
          FakeHealingGeneration([]),
          FakeHealingRepository(),
        ),
      );
      expect(find.text(_notEnough), findsOneWidget);
      expect(find.text(_ready), findsNothing);
      expect(find.text('Continue \u2192'), findsOneWidget);
    },
  );

  testWidgets(
    'D8: an answer that lands after the account changed is dropped, and the '
    'next account starts with no support state',
    (t) async {
      final gen = FakeHealingGeneration([_offered])..gate = Completer<void>();
      await pumpFlowScreen(
        t,
        _postMortem(testJourney()),
        overrides: _overrides(gen, FakeHealingRepository()),
      );
      await tapInReach(t, find.text('Generate reflection'));
      await t.pump();
      final c = _container(t);
      c.read(_signedIn.notifier).state = 'kofi';
      await t.pump();
      gen.gate!.complete();
      await t.pump();
      await t.pump();
      expect(c.read(healingSupportProvider).offered, isEmpty);
      expect(c.read(healingSupportProvider).hidden, isEmpty);
      expect(find.text(supportCardText), findsNothing);
    },
  );

  testWidgets('D8: an account change empties the support state', (t) async {
    await pumpFlowScreen(
      t,
      _postMortem(testJourney()),
      overrides: _overrides(
        FakeHealingGeneration([_offered]),
        FakeHealingRepository(),
      ),
    );
    await tapInReach(t, find.text('Generate reflection'));
    await t.pumpAndSettle();
    expect(find.text(supportCardText), findsOneWidget);
    _container(t).read(_signedIn.notifier).state = 'kofi';
    await t.pump();
    expect(_container(t).read(healingSupportProvider).offered, isEmpty);
    expect(find.text(supportCardText), findsNothing);
  });

  testWidgets('sign-out and quick exit empty the support state', (t) async {
    await pumpFlowScreen(
      t,
      _postMortem(testJourney()),
      overrides: _overrides(
        FakeHealingGeneration([_offered]),
        FakeHealingRepository(),
      ),
    );
    await tapInReach(t, find.text('Generate reflection'));
    await t.pumpAndSettle();
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    final entry = registry.entries.firstWhere(
      (e) => e.id == 'spec1.healing_support_memory',
    );
    expect(entry.moments, {WipeMoment.signOut, WipeMoment.quickExit});
    expect(entry.keys, isEmpty);
    expect(entry.protective, isFalse);
    expect(_container(t).read(healingSupportProvider).offered, isNotEmpty);
    await entry.run();
    await t.pump();
    expect(_container(t).read(healingSupportProvider).offered, isEmpty);
    expect(_container(t).read(healingSupportProvider).hidden, isEmpty);
    expect(find.text(supportCardText), findsNothing);
  });

  testWidgets('the card is a plain widget: nothing on it animates (spec 2.2)', (
    t,
  ) async {
    await pumpFlowScreen(
      t,
      _postMortem(testJourney()),
      overrides: _overrides(
        FakeHealingGeneration([_offered]),
        FakeHealingRepository(),
      ),
    );
    await tapInReach(t, find.text('Generate reflection'));
    await t.pump(); // one frame: the card is there at once
    await t.pump();
    expect(find.text(supportCardText), findsOneWidget);
    for (final type in [
      FadeTransition,
      SlideTransition,
      ScaleTransition,
      AnimatedSwitcher,
      AnimatedOpacity,
    ]) {
      expect(
        find.ancestor(
          of: find.text(supportCardText),
          matching: find.byType(type),
        ),
        findsNothing,
        reason: '$type above the card',
      );
    }
  });

  testWidgets(
    '"Need support now?" ends the reflection, always; opens Support',
    (t) async {
      final h = await pumpFlowScreen(
        t,
        () => HealingReflectionScreen(journey: testJourney(stage: 1)),
        overrides: _overrides(
          FakeHealingGeneration([]),
          FakeHealingRepository(),
        ),
      );
      await t.scrollUntilVisible(
        find.text('Need support now?'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(find.text('Need support now?'));
      await t.pumpAndSettle();
      await t.tap(find.text('Need support now?'));
      await t.pumpAndSettle();
      expect(find.text('at /safety-resources'), findsOneWidget);
      expect(h.metrics, isEmpty);
    },
  );

  testWidgets('the manual passage needs no flag (W9 B8 I-4)', (t) async {
    DocumentationRegistry.initialize();
    late BuildContext context;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          documentationFlagsProvider.overrideWith((ref) async => <String>{}),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (c, ref, _) {
              ref.watch(documentationFlagsProvider);
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final module = DocumentationRegistry.getById('healing')!;
    final ids = [
      for (final s in module.getSections(context))
        for (final c in s.contents) c.id,
    ];
    expect(ids, contains('healing_support_first'));
  });

  testWidgets('the card and the link meet the guidelines and let large text '
      'through', (t) async {
    Widget pieces() => Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            HealingSupportCard(onNotNow: () {}),
            const HealingNeedSupportLink(),
          ],
        ),
      ),
    );
    await pumpFlowScreen(t, pieces);
    await expectFlowGuidelines(t);
    await pumpFlowScreen(t, pieces, textScale: 2.0);
    expect(
      MediaQuery.of(t.element(find.text(supportCardText))).textScaler.scale(10),
      20,
    );
    expect(
      MediaQuery.of(
        t.element(find.text('Need support now?')),
      ).textScaler.scale(10),
      20,
    );
    await expectFlowGuidelines(t);
  });

  testWidgets(
    'Review Focus 1: an answer after the screen closed raises nothing, and '
    'the card waits for the next visit',
    (t) async {
      final gen = FakeHealingGeneration([_offered])..gate = Completer<void>();
      final h = await pumpFlowScreen(
        t,
        _postMortem(testJourney()),
        overrides: _overrides(gen, FakeHealingRepository()),
      );
      await tapInReach(t, find.text('Generate reflection'));
      await t.pump();
      final c = _container(t);
      h.router.go('/elsewhere'); // the person left the stage
      await t.pumpAndSettle();
      expect(find.byType(HealingPostMortemScreen), findsNothing);
      gen.gate!.complete();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(c.read(healingSupportProvider).offered, {
        (journeyId: 'j1', stage: HealingAiStage.postMortem),
      });
      h.router.go('/test'); // back to the stage, this run
      await t.pumpAndSettle();
      expect(find.text(supportCardText), findsOneWidget);
    },
  );

  testWidgets(
    'Review Focus 2: at 2.0 the card scrolls and See support stays reachable',
    (t) async {
      await pumpFlowScreen(
        t,
        _postMortem(testJourney()),
        textScale: 2.0,
        overrides: _overrides(
          FakeHealingGeneration([_offered]),
          FakeHealingRepository(),
        ),
      );
      await tapInReach(t, find.text('Generate reflection'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('See support'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('See support'));
      await t.pumpAndSettle();
      expect(find.text('at /safety-resources'), findsOneWidget);
    },
  );

  testWidgets('goldens: the card on both stages, and the link', (t) async {
    Future<void> generate(WidgetTester t, String label) async {
      await tapInReach(t, find.text(label));
      await t.pumpAndSettle();
    }

    await expectFlowGoldens(
      t,
      'healing_post_mortem_support',
      _postMortem(testJourney()),
      overrides: _overrides(
        FakeHealingGeneration(List.filled(4, _offered, growable: true)),
        FakeHealingRepository(),
      ),
      before: (t) => generate(t, 'Generate reflection'),
    );
    await expectFlowGoldens(
      t,
      'healing_portrait_support',
      () => HealingPortraitScreen(journey: testJourney(stage: 4)),
      overrides: _overrides(
        FakeHealingGeneration(List.filled(4, _offered, growable: true)),
        FakeHealingRepository(),
      ),
      before: (t) => generate(t, 'Generate portrait'),
    );
    await expectFlowGoldens(
      t,
      'healing_reflection_support_link',
      () => HealingReflectionScreen(journey: testJourney(stage: 1)),
      overrides: _overrides(FakeHealingGeneration([]), FakeHealingRepository()),
      before: (t) async {
        await t.scrollUntilVisible(
          find.text('Need support now?'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
      },
    );
  });
}
